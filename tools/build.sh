#!/usr/bin/env bash
set -euo pipefail

WORK=${WORK:-/work}
TREE=$WORK/android16
GUIDE=$WORK/lineageos-23.2-sabrina
DOWNLOADS=$WORK/downloads
STOCK=$WORK/stock
STAMPS=$WORK/.stamps
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
JOBS=${JOBS:-$(nproc)}
SYNC_JOBS=${SYNC_JOBS:-8}
CCACHE_SIZE=${CCACHE_SIZE:-50G}
SYNC_ATTEMPTS=${SYNC_ATTEMPTS:-5}
DIAGNOSTIC=${DIAGNOSTIC:-0}
DEBUGFS=/usr/sbin/debugfs
E2FSCK=/usr/sbin/e2fsck
RESIZE2FS=/usr/sbin/resize2fs
MKE2FS=/usr/sbin/mke2fs
IMAGES=$WORK/images
DIST=$WORK/dist

GUIDE_URL=https://github.com/fidalgojoao/lineageos-23.2-sabrina.git
GUIDE_COMMIT=d50e03b84b1f2cae16ea0ea19c7db43d67d235e0
LINEAGE_URL=https://github.com/LineageOS/android.git
LINEAGE_BRANCH=lineage-23.2
REPO_FLAGS=(--depth=1 -g all --git-lfs --no-clone-bundle)

OTA_URL=https://android.googleapis.com/packages/ota-api/package/0d0a14a015085ddff485765a28559bcd858d3018.zip
OTA_SHA256=8aacf5f69036c7b881756f031b45834b1770a6973debe07fc8b8d832d9f0c5c2
SMARTTUBE_URL=https://github.com/yuliskov/SmartTube/releases/download/32.71s/SmartTube_stable_32.71_armeabi-v7a.apk
SMARTTUBE_SHA256=288e8caaa11417f6b64d2a7f906cead85c0b8a9bb5904753d7cb4f79d117d023

KERNEL=$WORK/kernel
KERNEL_COMMON_URL=https://android.googlesource.com/kernel/common
KERNEL_COMMON_COMMIT=c0bad795ed1a0c02f9af7d8622ebe0cf9b446c9c
AMLOGIC_DRIVER_URL=https://nest-open-source.googlesource.com/manifest_repos/amlogic-driver
AMLOGIC_DRIVER_COMMIT=997cd70d4a7705a53d751b3703cf0e9a600e42bc
CLANG_REPO=https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86
CLANG_COMMIT=425c8149f17c8d9914bf690b4d5abe45a13fb993
CLANG_LLVM_COMMIT=d9f89f4d16663d5012e5c09495f3b30ece3d2362
BUILD_TOOLS_REPO=https://android.googlesource.com/kernel/prebuilts/build-tools
BUILD_TOOLS_COMMIT=e905be252a53d20c52bd9e59df3ff8fdd46b9eab
PAHOLE_SHA256=d80203a28816b85d4e5a5a755fe59c94d22949f9800c78d76157f1761eecd278
PAHOLE_LIBCXX_SHA256=51e403f6b471dc79c548f9d8f8d09d999b3857c55f21800efab52cf77187653d
STOCK_MODULE_CERT_SHA256=4c10cfcd09d3063ef243371639704ad6af48f6c487cdafff143446878f245e55
KERNEL_MAKE_VARS=(ARCH=arm64 LLVM=1 LLVM_IAS=1 BRANCH=android14-5.15 KMI_GENERATION=11)
KERNEL_CONFIG_CHANGES_ALLOWED=(
    CONFIG_DM_DEFAULT_KEY
    CONFIG_SYSTEM_TRUSTED_KEYS
    CONFIG_CC_CAN_LINK
    CONFIG_CC_CAN_LINK_STATIC
    CONFIG_UAPI_HEADER_TEST
)

STOCK_APKS=(
    priv-app/TVLauncherXPrebuilt/TVLauncherXPrebuilt.apk
    priv-app/TVDreamXPrebuilt/TVDreamXPrebuilt.apk
    app/LatinIMEGoogleTvPrebuilt/LatinIMEGoogleTvPrebuilt.apk
    priv-app/TVAxel/TVAxel.apk
    overlay/AxelOverlay/ChromecastAxelOverlay.apk
    etc/permissions/privapp-permissions-atv-product.xml
    etc/default-permissions/default-atv-permissions.xml
)

SUPER_SIZE=2084569088
SUPER_GROUP=amlogic_dynamic_partitions
SUPER_GROUP_SIZE=2080374784
SUPER_PARTITIONS=(system vendor product odm system_dlkm)
BOOT_PARTITION_SIZE=16777216

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

check_sha() {
    echo "$1  $2" | sha256sum -c --quiet - || die "checksum mismatch: $2"
}

fetch() {
    local url=$1 sha=$2 dest=$3
    if [ -f "$dest" ] && echo "$sha  $dest" | sha256sum -c --quiet - 2>/dev/null; then
        return
    fi
    curl -fL --retry 3 -o "$dest.part" "$url"
    mv "$dest.part" "$dest"
    check_sha "$sha" "$dest"
}

shallow_clone() {
    local dir=$1 url=$2 commit=$3
    rm -rf "$dir"
    git init -q "$dir"
    git -C "$dir" fetch -q --depth=1 "$url" "$commit"
    git -C "$dir" checkout -q --detach FETCH_HEAD
    [ "$(git -C "$dir" rev-parse HEAD)" = "$commit" ] || die "$dir is not at $commit"
}

gitiles_file() {
    curl -fsS --retry 3 "$1/+/$2/$3?format=TEXT" | base64 -d
}

stock_ota() {
    local ota=$WORK/inputs/stock-ota.zip
    if [ -f "$ota" ]; then
        check_sha "$OTA_SHA256" "$ota"
    else
        mkdir -p "$DOWNLOADS"
        ota=$DOWNLOADS/stock-ota.zip
        fetch "$OTA_URL" "$OTA_SHA256" "$ota"
    fi
    echo "$ota"
}

kernel_env() {
    export PATH="$KERNEL/tools/clang-r487747c/bin:$KERNEL/tools/pahole:$PATH"
    export LD_LIBRARY_PATH="$KERNEL/tools/pahole/lib64"
    export KBUILD_BUILD_USER=build-user KBUILD_BUILD_HOST=build-host
}

missing_projects() {
    repo list -p 2>/dev/null | while IFS= read -r path; do
        [ -e "$path/.git" ] || echo "$path"
    done
}

clean_sync_leftovers() {
    find .repo/projects .repo/project-objects -name '*.lock' -delete 2>/dev/null || true
    while IFS= read -r gitdir; do
        [ -e "$gitdir/HEAD" ] || rm -rf "$gitdir"
    done < <(find .repo/projects -type d -name '*.git' -prune)
}

# Shallow clone of the upstream guide repository at a pinned commit.
step_guide() {
    shallow_clone "$GUIDE" "$GUIDE_URL" "$GUIDE_COMMIT"
}

# repo init with the pinned manifest, all groups, depth 1 and Git LFS.
# The pinned manifest's duplicate vendor/gapps_tv entry is removed, and -g all is
# needed because most projects are in AOSP groups a plain sync skips.
step_init() {
    mkdir -p "$TREE"
    cd "$TREE"
    repo init -u "$LINEAGE_URL" -b "$LINEAGE_BRANCH" "${REPO_FLAGS[@]}"
    # vendor/gapps_tv is already in the pinned manifest; the local manifest adds it again.
    grep -v 'path="vendor/gapps_tv"' "$GUIDE/manifests/platform-manifest-pinned.xml" \
        > .repo/manifests/sabrina-pinned.xml
    # A bare re-init resets the manifest, so every init repeats all flags.
    repo init -m sabrina-pinned.xml "${REPO_FLAGS[@]}"
    mkdir -p .repo/local_manifests
    cp "$GUIDE/manifests/gapps-local-manifest.xml" .repo/local_manifests/
}

# repo sync, retried until every project is checked out. Checks the WebView APK
# is real and not a Git LFS pointer, since repo skips LFS by default.
step_sync() {
    cd "$TREE"
    local attempt missing
    for attempt in $(seq 1 "$SYNC_ATTEMPTS"); do
        log "sync attempt $attempt/$SYNC_ATTEMPTS"
        clean_sync_leftovers
        repo sync -c -j"$SYNC_JOBS" --no-tags --no-clone-bundle --optimized-fetch || true
        missing=$(missing_projects)
        if [ -z "$missing" ]; then
            break
        fi
        printf 'still missing:\n%s\n' "$missing"
    done
    [ -z "$(missing_projects)" ] || die "repo sync did not complete after $SYNC_ATTEMPTS attempts"

    local webview=external/chromium-webview/prebuilt/arm/webview.apk
    if [ "$(head -c 2 "$webview")" != PK ]; then
        git -C "$(dirname "$webview")" lfs pull
    fi
    [ "$(head -c 2 "$webview")" = PK ] || die "$webview is still a Git LFS pointer"
}

# Copies the device tree, lays overlay/ on top and applies the upstream patches.
# The patches can't be applied twice: to redo this step, reset the patched
# projects first, then delete .stamps/device. The diagnostic init is always
# applied: it holds the sabrina.selinux=permissive switch, and its watchdog only
# runs with androidboot.sabrina_watchdog=1 on the kernel command line.
step_device() {
    cd "$TREE"
    rm -rf device/google/sabrina16
    cp -r "$GUIDE/device/google/sabrina16" device/google/
    cp -r "$HERE/overlay/." .
    "$GUIDE/scripts/apply-patches.sh" "$TREE"
    # The upstream TvSettings patch uses HDMI_CEC without allowlisting it, which crash-loops system_server.
    git -C packages/apps/TvSettings apply "$HERE/patches/packages_apps_TvSettings-hdmi-cec-allowlist.patch"
    # LineageOS blocks new apps whose INTERNET grant isn't visible yet at install time.
    git -C frameworks/base apply "$HERE/patches/frameworks_base-keep-network-for-apps-requesting-internet.patch"
    git -C system/core apply "$GUIDE/patches/diagnostic/system_core-init-watchdog.patch"
    git -C system/apex apply "$GUIDE/patches/diagnostic/system_apex-bootstrap-logging.patch"
    git -C system/core apply "$HERE/patches/system_core-diagnostic-watchdog-5min.patch"
    git -C system/core apply "$HERE/patches/system_core-diagnostic-watchdog-opt-in.patch"
    log "diagnostic init and apexd logging applied"
}

# Unpacks the stock product image, extracts the launcher, screensaver, Gboard,
# TVAxel and its overlay, and generates TVAxel's permission files.
step_stock() {
    local ota
    ota=$(stock_ota)

    rm -rf "$STOCK"
    mkdir -p "$STOCK/product"
    unzip -q -o "$ota" product.new.dat.br product.transfer.list -d "$STOCK"
    brotli -d -f "$STOCK/product.new.dat.br" -o "$STOCK/product.new.dat"
    python3 -I "$HERE/tools/sdat2img.py" "$STOCK/product.transfer.list" "$STOCK/product.new.dat" "$STOCK/product.img"

    local apk
    for apk in "${STOCK_APKS[@]}"; do
        mkdir -p "$STOCK/product/$(dirname "$apk")"
        "$DEBUGFS" -R "dump /$apk $STOCK/product/$apk" "$STOCK/product.img"
    done
    rm -f "$STOCK/product.new.dat.br" "$STOCK/product.new.dat" "$STOCK/product.img"

    local device=$TREE/device/google/sabrina16
    "$GUIDE/scripts/extract-proprietary.sh" "$STOCK/product" "$device/proprietary"
    cp "$STOCK/product/priv-app/TVAxel/TVAxel.apk" "$device/proprietary/TVAxel.apk"
    cp "$STOCK/product/overlay/AxelOverlay/ChromecastAxelOverlay.apk" "$device/proprietary/ChromecastAxelOverlay.apk"
    python3 -I "$HERE/tools/axel_permissions.py" "$TREE/prebuilts/sdk/tools/linux/bin/aapt2" \
        "$STOCK/product" "$device/permissions"
}

# Downloads SmartTube at a pinned checksum and unpacks its native libraries.
step_apps() {
    mkdir -p "$DOWNLOADS"
    fetch "$SMARTTUBE_URL" "$SMARTTUBE_SHA256" "$DOWNLOADS/SmartTube.apk"

    local proprietary=$TREE/device/google/sabrina16/proprietary
    cp "$DOWNLOADS/SmartTube.apk" "$proprietary/SmartTube.apk"
    rm -rf "$proprietary/smarttube-lib"
    mkdir -p "$proprietary/smarttube-lib"
    unzip -q -o -j "$proprietary/SmartTube.apk" 'lib/armeabi-v7a/*.so' -d "$proprietary/smarttube-lib"
}

# The stock kernel is rebuilt from the same sources so the stock vendor modules
# keep loading. clang r487747c (LLVM d9f89f4d) and pahole v1.23 are the stock
# kernel's own; both are downloaded from Google's prebuilts and checked.
step_kernel_tools() {
    local tools=$KERNEL/tools
    local clang=$tools/clang-r487747c
    if ! "$clang/bin/clang" --version 2>/dev/null | grep -q "based on r487747c.*$CLANG_LLVM_COMMIT"; then
        rm -rf "$clang"
        mkdir -p "$clang"
        curl -fL --retry 3 "$CLANG_REPO/+archive/$CLANG_COMMIT/clang-r487747c.tar.gz" | tar -xz -C "$clang"
    fi
    "$clang/bin/clang" --version | grep -q "based on r487747c.*$CLANG_LLVM_COMMIT" \
        || die "clang does not match the stock kernel's compiler"

    mkdir -p "$tools/pahole/lib64"
    gitiles_file "$BUILD_TOOLS_REPO" "$BUILD_TOOLS_COMMIT" linux-x86/bin/pahole > "$tools/pahole/pahole"
    check_sha "$PAHOLE_SHA256" "$tools/pahole/pahole"
    chmod 755 "$tools/pahole/pahole"
    local lib=linux-x86/lib64/libc++.so attempt
    for attempt in 1 2 3; do
        gitiles_file "$BUILD_TOOLS_REPO" "$BUILD_TOOLS_COMMIT" "$lib" > "$tools/pahole/lib64/libc++.so"
        [ "$(head -c 4 "$tools/pahole/lib64/libc++.so")" = $'\x7fELF' ] && break
        lib=linux-x86/lib64/$(cat "$tools/pahole/lib64/libc++.so")
    done
    check_sha "$PAHOLE_LIBCXX_SHA256" "$tools/pahole/lib64/libc++.so"
    [ "$(LD_LIBRARY_PATH="$tools/pahole/lib64" "$tools/pahole/pahole" --version)" = v1.23 ] \
        || die "pahole is not v1.23"
}

# kernel/common at c0bad795. The stock version's gf4a1f03072af is the commit
# made by applying Amlogic's patches, not a commit in Google's repository.
# The Amlogic driver repo is pinned to 997cd70d, the revision in Google's Nest
# manifest for this device, nested at common/common_drivers. Then the Amlogic
# patch set and the upstream kernel patches are applied.
step_kernel_source() {
    local common=$KERNEL/common
    shallow_clone "$common" "$KERNEL_COMMON_URL" "$KERNEL_COMMON_COMMIT"
    shallow_clone "$common/common_drivers" "$AMLOGIC_DRIVER_URL" "$AMLOGIC_DRIVER_COMMIT"
    echo common_drivers >> "$common/.git/info/exclude"
    cd "$common"

    local patches=common_drivers/auto_patch/common14-5.15/common group patch change_id
    for group in $(ls "$patches"); do
        for patch in $(find "$patches/$group" -name '*.patch' | sort); do
            change_id=$(grep -m1 '^Change-Id' "$patch" | awk '{print $2}')
            if [ -n "$change_id" ] && git log -n 400 --format=%B | grep -q "$change_id"; then
                continue
            fi
            git am -q "$patch" && continue
            git am --abort
            # Some Amlogic patches are security fixes this kernel revision already contains.
            git apply --reverse --check "$patch" || die "Amlogic patch does not apply: $patch"
            log "already present: $patch"
        done
    done

    for patch in "$GUIDE"/patches/kernel/*.patch; do
        git apply -p1 "$patch"
    done
    git commit -qam 'sabrina: dm-default-key in KABI reserved slot; uapi time.h include'
}

# Takes the config and module-signing certificate from the stock kernel, and the
# stock modules from vendor and the boot ramdisk.
# 51 stock modules, Bluetooth among them, are signed with a key generated during
# Google's build, and MODULE_SIG_PROTECT is on. A fresh key would treat them as
# unsigned and refuse their protected exports, which breaks the remote. The stock
# image carries the public certificate, so it goes into SYSTEM_TRUSTED_KEYS.
step_kernel_stock() {
    local stock=$KERNEL/stock ota
    ota=$(stock_ota)
    rm -rf "$stock"
    mkdir -p "$stock/boot" "$stock/modules/vendor" "$stock/modules/ramdisk"
    unzip -q -o "$ota" boot.img vendor.new.dat.br vendor.transfer.list -d "$stock"
    python3 -I "$TREE/system/tools/mkbootimg/unpack_bootimg.py" --boot_img "$stock/boot.img" --out "$stock/boot" >/dev/null

    python3 -I "$HERE/tools/stock_kernel.py" "$stock/boot/kernel" "$stock/stock.config" "$stock/module-signing.der"
    check_sha "$STOCK_MODULE_CERT_SHA256" "$stock/module-signing.der"
    openssl x509 -inform DER -in "$stock/module-signing.der" -out "$stock/module-signing.pem"

    brotli -d -f "$stock/vendor.new.dat.br" -o "$stock/vendor.new.dat"
    python3 -I "$HERE/tools/sdat2img.py" "$stock/vendor.transfer.list" "$stock/vendor.new.dat" "$stock/vendor.img"
    "$DEBUGFS" -R "rdump /lib/modules $stock/modules/vendor" "$stock/vendor.img" 2>/dev/null || true
    rm -f "$stock/vendor.new.dat.br" "$stock/vendor.new.dat" "$stock/vendor.img"
    (cd "$stock/modules/ramdisk" && gzip -dc "$stock/boot/ramdisk" | cpio -id --no-absolute-filenames --quiet)

    local count
    count=$(find "$stock/modules" -name '*.ko' | wc -l)
    [ "$count" -gt 0 ] || die "no stock modules extracted"
    log "stock modules: $count"
}

# Builds with the stock config plus DM_DEFAULT_KEY, which Android 16's storage
# needs. Fails if the config differs from stock in anything else but the trusted
# key and the host-link probes that only gate a header test, or if any stock
# module imports a symbol whose CRC changed or which nothing exports.
step_kernel_build() {
    kernel_env
    local common=$KERNEL/common out=$KERNEL/out stock=$KERNEL/stock dist=$KERNEL/dist
    local kmake=(make -C "$common" O="$out" "${KERNEL_MAKE_VARS[@]}")

    mkdir -p "$out"
    cp "$stock/stock.config" "$out/.config"
    # The stock modules are signed with the stock build's key; trusting its certificate lets
    # them pass MODULE_SIG_PROTECT, which would otherwise refuse their protected exports.
    "$common/scripts/config" --file "$out/.config" --enable DM_DEFAULT_KEY \
        --set-str SYSTEM_TRUSTED_KEYS "$stock/module-signing.pem"
    "${kmake[@]}" olddefconfig

    local changed unexpected
    changed=$(diff <(grep -E '^(# )?CONFIG_' "$stock/stock.config" | sort) <(grep -E '^(# )?CONFIG_' "$out/.config" | sort) \
        | sed -nE 's/^[<>] (# )?(CONFIG_[A-Za-z0-9_]+).*/\2/p' | sort -u)
    unexpected=$(comm -23 <(echo "$changed") <(printf '%s\n' "${KERNEL_CONFIG_CHANGES_ALLOWED[@]}" | sort))
    [ -z "$unexpected" ] || die "kernel config differs from stock in: $unexpected"

    "${kmake[@]}" -j"$JOBS" Image modules
    python3 -I "$HERE/tools/check_crcs.py" "$out/Module.symvers" "$KERNEL/tools/clang-r487747c/bin" \
        "$stock/modules/vendor" "$stock/modules/ramdisk"

    rm -rf "$dist"
    mkdir -p "$dist"
    cp "$out/arch/arm64/boot/Image" "$out/Module.symvers" "$out/System.map" "$dist/"
    cp "$out/.config" "$dist/kernel.config"
    xz --format=lzma -9 -c < "$dist/Image" > "$dist/Image.lzma"
    (cd "$dist" && sha256sum Image Image.lzma kernel.config Module.symvers > SHA256SUMS)
    log "kernel: $dist/Image.lzma ($(cat "$out/include/config/kernel.release"))"
}

# Writes out/sabrina-source-manifest.xml, which the guide doesn't create, then
# builds the system image. Always runs; the Android build is incremental, and
# ccache in $WORK/ccache speeds up rebuilds after a clean out/.
step_build() {
    cd "$TREE"
    mkdir -p out
    repo manifest -o out/sabrina-source-manifest.xml
    set +u
    source build/envsetup.sh
    source vendor/lineage/vars/aosp_target_release
    export USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache CCACHE_DIR=$WORK/ccache
    mkdir -p "$CCACHE_DIR"
    ccache -M "$CCACHE_SIZE" >/dev/null
    lunch lineage_gsi_sabrina16 "$aosp_target_release" user
    local goals=(systemimage checkvintf lpmake lpdump simg2img)
    [ "$DIAGNOSTIC" = 1 ] && goals+=(adb_debug.prop userdebug_plat_sepolicy.cil)
    m -j"$JOBS" "${goals[@]}"
    set -u
    ccache -s | grep -E 'Hits|Misses|Cache size' || true
    log "system image: $TREE/out/target/product/generic/system.img"
}

stock_partition() {
    local ota=$1 name=$2 dest=$3
    unzip -q -o "$ota" "$name.new.dat.br" "$name.transfer.list" -d "$dest"
    brotli -d -f "$dest/$name.new.dat.br" -o "$dest/$name.new.dat"
    python3 -I "$HERE/tools/sdat2img.py" "$dest/$name.transfer.list" "$dest/$name.new.dat" "$dest/$name.img"
    rm -f "$dest/$name.new.dat.br" "$dest/$name.new.dat" "$dest/$name.transfer.list"
}

make_boot() {
    local out=$1 extra_cmdline=$2 args=() i
    eval "args=($(python3 "$TREE/system/tools/mkbootimg/unpack_bootimg.py" \
        --boot_img "$IMAGES/stock/boot.img" --out "$IMAGES/stock/boot" --format mkbootimg))"
    for i in "${!args[@]}"; do
        case "${args[$i]}" in
            --kernel) args[$((i + 1))]=$KERNEL/dist/Image.lzma ;;
            --ramdisk) args[$((i + 1))]=$IMAGES/ramdisk.img ;;
            --cmdline) args[$((i + 1))]="${args[$((i + 1))]}$extra_cmdline" ;;
        esac
    done
    python3 "$TREE/system/tools/mkbootimg/mkbootimg.py" "${args[@]}" --output "$out"

    local props=() key value
    while IFS=$'\t' read -r key value; do
        props+=(--prop "$key:$value")
    done < <(python3 -I "$TREE/external/avb/avbtool.py" info_image --image "$IMAGES/stock/boot.img" \
        | sed -nE "s/^ +Prop: (\S+) -> '(.*)'$/\1\t\2/p")
    python3 -I "$TREE/external/avb/avbtool.py" add_hash_footer --image "$out" --partition_name boot \
        --partition_size "$BOOT_PARTITION_SIZE" --algorithm NONE "${props[@]}"
}

# Builds vendor, boot, product, super and vbmeta, which the device tree never
# builds, reads every partition back out of super and writes SHA256SUMS.txt.
# Always runs.
step_images() {
    local ota host=$TREE/out/host/linux-x86/bin
    ota=$(stock_ota)
    rm -rf "$IMAGES" "$DIST"
    mkdir -p "$IMAGES/stock" "$DIST"
    cd "$IMAGES"
    unzip -q -o "$ota" boot.img -d stock
    local name
    for name in vendor odm system_dlkm; do
        stock_partition "$ota" "$name" stock
    done
    mv stock/odm.img stock/system_dlkm.img .
    cp "$TREE/out/target/product/generic/system.img" system.img

    # Stock vendor uses deduplicated blocks; unshare them so replacing the fstab frees no shared block.
    cp stock/vendor.img vendor.img
    "$RESIZE2FS" vendor.img $(( $(stat -c %s vendor.img) / 4096 + 8192 ))
    "$E2FSCK" -fy -E unshare_blocks vendor.img || [ $? -eq 1 ]
    "$DEBUGFS" -R "dump /etc/fstab.amlogic fstab.stock" vendor.img
    grep -v -E '^product[[:space:]]+/product[[:space:]]' fstab.stock > fstab.amlogic
    [ "$(wc -l < fstab.amlogic)" -eq $(( $(wc -l < fstab.stock) - 1 )) ] || die "vendor fstab has no single /product entry"
    printf 'u:object_r:vendor_cgroup_desc_file:s0\0' > label.cgroups
    printf 'u:object_r:vendor_configs_file:s0\0' > label.configs
    cat > vendor.debugfs <<EOF
write $TREE/device/google/sabrina16/vendor-config/cgroups.json /etc/cgroups.json
set_inode_field /etc/cgroups.json mode 0100644
set_inode_field /etc/cgroups.json uid 0
set_inode_field /etc/cgroups.json gid 0
ea_set -f label.cgroups /etc/cgroups.json security.selinux
rm /etc/fstab.amlogic
write fstab.amlogic /etc/fstab.amlogic
set_inode_field /etc/fstab.amlogic mode 0100644
set_inode_field /etc/fstab.amlogic uid 0
set_inode_field /etc/fstab.amlogic gid 0
ea_set -f label.configs /etc/fstab.amlogic security.selinux
EOF
    "$DEBUGFS" -w -f vendor.debugfs vendor.img
    "$E2FSCK" -fn vendor.img
    "$DEBUGFS" -R "dump /etc/fstab.amlogic fstab.readback" vendor.img
    cmp fstab.readback fstab.amlogic || die "vendor fstab readback differs"

    truncate -s 4M product.img
    "$MKE2FS" -q -t ext4 -F -b 4096 -L product product.img

    python3 "$TREE/system/tools/mkbootimg/unpack_bootimg.py" --boot_img stock/boot.img --out stock/boot >/dev/null
    python3 -I "$HERE/tools/edit_ramdisk_fstab.py" stock/boot/ramdisk ramdisk.base.img first_stage_ramdisk/fstab.amlogic 'product '
    # With adb off, system_server waits forever for SurfaceFlinger and the screen
    # stays black, so the production ramdisk switches adb on without marking the
    # build debuggable: force_debuggable only makes init read adb_debug.prop.
    printf 'ro.adb.secure=0\npersist.sys.usb.config=adb\n' > adb_debug.prop
    : > force_debuggable
    local files=() name
    for name in force_debuggable adb_debug.prop; do
        files+=("$name=$name" "first_stage_ramdisk/$name=$name")
    done
    python3 -I "$HERE/tools/add_ramdisk_files.py" ramdisk.base.img ramdisk.img "${files[@]}"
    make_boot "$DIST/boot.img" " sabrina.selinux=permissive"
    if [ "$DIAGNOSTIC" = 1 ]; then
        make_boot "$DIST/boot-permissive.img" " sabrina.selinux=permissive androidboot.sabrina_watchdog=1"
        mkdir -p debug
        cp "$TREE/out/target/product/generic/debug_ramdisk/"{adb_debug.prop,userdebug_plat_sepolicy.cil} debug/
        echo 'persist.sys.usb.config=adb' >> debug/adb_debug.prop
        : > debug/force_debuggable
        files=()
        for name in force_debuggable adb_debug.prop userdebug_plat_sepolicy.cil; do
            files+=("$name=debug/$name" "first_stage_ramdisk/$name=debug/$name")
        done
        cp ramdisk.img ramdisk.release.img
        python3 -I "$HERE/tools/add_ramdisk_files.py" ramdisk.base.img ramdisk.img "${files[@]}"
        make_boot "$DIST/boot-debug.img" " sabrina.selinux=permissive androidboot.sabrina_watchdog=1"
        mv ramdisk.release.img ramdisk.img
    fi

    local total=0 cmd=("$host/lpmake" --metadata-size=65536 --metadata-slots=2
        --device=super:$SUPER_SIZE:1048576:0 --super-name=super
        --group=$SUPER_GROUP:$SUPER_GROUP_SIZE --block-size=4096)
    for name in "${SUPER_PARTITIONS[@]}"; do
        total=$(( total + $(stat -c %s "$name.img") ))
        cmd+=(--partition="$name:readonly:$(stat -c %s "$name.img"):$SUPER_GROUP" --image="$name=$name.img")
    done
    [ "$total" -le "$SUPER_GROUP_SIZE" ] || die "partitions do not fit the super group"
    cmd+=(--sparse --output="$DIST/super.sparse.img")
    "${cmd[@]}"
    printf '%q ' "${cmd[@]}" | sed "s|$host/||; s|$DIST/||; s|$IMAGES/||g" > "$DIST/lpmake-invocation.txt"
    echo >> "$DIST/lpmake-invocation.txt"

    "$host/simg2img" "$DIST/super.sparse.img" super.raw
    "$host/lpdump" super.raw > lpdump.txt
    python3 -I "$HERE/tools/verify_super.py" super.raw lpdump.txt "$IMAGES"
    rm -f super.raw

    python3 -I "$TREE/external/avb/avbtool.py" make_vbmeta_image --flags 3 --padding_size 4096 \
        --output "$DIST/vbmeta.img"

    (cd "$DIST" && sha256sum -- *.img > SHA256SUMS.txt)
    log "flash set: $DIST"
}

# Each step leaves a marker in .stamps/ and is skipped on the next run, except
# build and images. Name steps as arguments to run only those.
main() {
    local steps=(guide init sync device stock apps kernel_tools kernel_source kernel_stock kernel_build build images)
    local always=" build images "
    [ $# -eq 0 ] || steps=("$@")
    mkdir -p "$STAMPS"

    local step
    for step in "${steps[@]}"; do
        declare -F "step_$step" >/dev/null || die "unknown step: $step"
        if [[ "$always" != *" $step "* ]] && [ -e "$STAMPS/$step" ]; then
            log "$step: already done"
            continue
        fi
        log "$step"
        ( "step_$step" )
        [[ "$always" == *" $step "* ]] || touch "$STAMPS/$step"
    done
}

main "$@"
