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
KEYS=${KEYS:-/keys}
SIGNED=$WORK/signed

GUIDE_URL=https://github.com/fidalgojoao/lineageos-23.2-sabrina.git
GUIDE_COMMIT=d50e03b84b1f2cae16ea0ea19c7db43d67d235e0
LINEAGE_URL=https://github.com/LineageOS/android.git
LINEAGE_BRANCH=lineage-23.2
REPO_FLAGS=(--depth=1 -g all --git-lfs --no-clone-bundle --repo-rev=v2.72)

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

PATCHED_PROJECTS=(
    bootable/recovery
    device/google/atv
    frameworks/base
    packages/apps/TvSettings
    packages/apps/Updater
    packages/modules/AdServices
    packages/modules/OnDevicePersonalization
    packages/modules/Wifi
    system/apex
    system/core
    system/sepolicy
    vendor/lineage
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

# Every build stamp comes from one fixed time, the pinned guide commit's, so two
# builds of the same sources are byte-identical. Override with SOURCE_DATE_EPOCH.
source_date_epoch() {
    echo "${SOURCE_DATE_EPOCH:-$(git -C "$GUIDE" log -1 --format=%ct)}"
}

kernel_env() {
    export PATH="$KERNEL/tools/clang-r487747c/bin:$KERNEL/tools/pahole:$PATH"
    export LD_LIBRARY_PATH="$KERNEL/tools/pahole/lib64"
    export KBUILD_BUILD_USER=build-user KBUILD_BUILD_HOST=build-host
    KBUILD_BUILD_TIMESTAMP=$(date -u -d "@$(source_date_epoch)")
    export KBUILD_BUILD_TIMESTAMP
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

# Resets the patched projects, copies the device tree, lays overlay/ on top and
# applies the upstream and local patches. Delete .stamps/device to redo it after
# changing patches or overlay/. The diagnostic init and apexd logging are only
# applied with DIAGNOSTIC=1: they hold the sabrina.selinux=permissive switch and
# the watchdog, which only the diagnostic boot images switch on. The step reruns
# by itself when DIAGNOSTIC changes.
step_device() {
    cd "$TREE"
    local project
    for project in "${PATCHED_PROJECTS[@]}"; do
        git -C "$project" reset -q --hard HEAD
        git -C "$project" clean -qfd
    done
    rm -rf device/google/sabrina16
    cp -r "$GUIDE/device/google/sabrina16" device/google/
    cp -r "$HERE/overlay/." .
    "$GUIDE/scripts/apply-patches.sh" "$TREE"
    # The upstream TvSettings patch uses HDMI_CEC without allowlisting it, which crash-loops system_server.
    git -C packages/apps/TvSettings apply "$HERE/patches/packages_apps_TvSettings-hdmi-cec-allowlist.patch"
    # LineageOS blocks new apps whose INTERNET grant isn't visible yet at install time.
    git -C frameworks/base apply "$HERE/patches/frameworks_base-keep-network-for-apps-requesting-internet.patch"
    if [ "$DIAGNOSTIC" = 1 ]; then
        git -C system/core apply "$GUIDE/patches/diagnostic/system_core-init-watchdog.patch"
        git -C system/apex apply "$GUIDE/patches/diagnostic/system_apex-bootstrap-logging.patch"
        git -C system/core apply "$HERE/patches/system_core-diagnostic-watchdog-5min.patch"
        git -C system/core apply "$HERE/patches/system_core-diagnostic-watchdog-opt-in.patch"
        log "diagnostic init and apexd logging applied"
    fi
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
    GIT_AUTHOR_DATE="@$(source_date_epoch) +0000"
    GIT_COMMITTER_DATE=$GIT_AUTHOR_DATE
    export GIT_AUTHOR_DATE GIT_COMMITTER_DATE
    shallow_clone "$common" "$KERNEL_COMMON_URL" "$KERNEL_COMMON_COMMIT"
    shallow_clone "$common/common_drivers" "$AMLOGIC_DRIVER_URL" "$AMLOGIC_DRIVER_COMMIT"
    echo common_drivers >> "$common/.git/info/exclude"
    cd "$common"

    local patches=common_drivers/auto_patch/common14-5.15/common group patch change_id
    for group in "$patches"/*/; do
        for patch in $(find "$group" -name '*.patch' | sort); do
            change_id=$({ grep -m1 '^Change-Id' "$patch" || true; } | awk '{print $2}')
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
    changed=$({ diff <(grep -E '^(# )?CONFIG_' "$stock/stock.config" | sort) <(grep -E '^(# )?CONFIG_' "$out/.config" | sort) || true; } \
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
    # shellcheck source=/dev/null
    source build/envsetup.sh
    # shellcheck source=/dev/null
    source vendor/lineage/vars/aosp_target_release
    export USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache CCACHE_DIR=$WORK/ccache
    BUILD_DATETIME=$(source_date_epoch)
    export BUILD_DATETIME BUILD_USERNAME=sabrina BUILD_HOSTNAME=sabrina-build
    mkdir -p "$CCACHE_DIR"
    ccache -M "$CCACHE_SIZE" >/dev/null
    # shellcheck disable=SC2154
    lunch lineage_gsi_sabrina16 "$aosp_target_release" user
    local goals=(systemimage checkvintf lpmake lpdump simg2img
        recovery fastbootd adbd.recovery minadbd librecovery_ui_default init_second_stage.recovery
        linker.recovery shell_and_utilities_recovery reboot.recovery ueventd.rc.recovery)
    signing && goals+=(target-files-package otatools)
    [ "$DIAGNOSTIC" = 1 ] && goals+=(adb_debug.prop userdebug_plat_sepolicy.cil)
    m -j"$JOBS" "${goals[@]}"
    set -u
    ccache -s | grep -E 'Hits|Misses|Cache size' || true
    log "system image: $TREE/out/target/product/generic/system.img"
}

signing() {
    [ -f "$KEYS/releasekey.pk8" ]
}

# Signs the target files with the release keys mounted at $KEYS and rebuilds the
# system image from them. APEXes that are built but not shipped in the system
# image are left unsigned; a shipped APEX without a release key stops the build.
# APKs copied into the image as plain files, not built as apps, keep their
# signatures too. Prebuilt apps marked presigned or preprocessed, such as
# Google's, keep their own signatures so they can still update through Play.
# Without keys the build stays on AOSP's test keys and this step does nothing.
step_sign() {
    rm -rf "$SIGNED"
    signing || { log "no release keys in $KEYS: test keys"; return; }
    mkdir -p "$SIGNED"
    cd "$TREE"
    local host=$TREE/out/host/linux-x86 jdk target_files args=() line name key keys
    # The signing tools change permissions on the key files they read, which fails
    # on a read-only mount, so they work on a copy that lives only in the container,
    # at a fixed path because the OTA certificate is stored under it.
    keys=/tmp/release-keys
    rm -rf "$keys"
    mkdir -p "$keys"
    cp -r "$KEYS"/. "$keys"/
    chmod -R u+rw "$keys"
    jdk=$(find "$TREE/prebuilts/jdk" -maxdepth 3 -type d -path '*/linux-x86/bin' | sort -V | tail -1)
    target_files=$(find "$TREE/out/target/product/generic/obj/PACKAGING/target_files_intermediates" \
        -maxdepth 1 -name '*-target_files*.zip' | head -1)
    [ -n "$target_files" ] || die "no target files; was the build run with the keys mounted?"

    local shipped
    shipped=$(unzip -Z1 "$target_files" 'SYSTEM/*apex/*' | sed -E 's#.*/##; s/\.capex$/.apex/')
    while IFS= read -r line; do
        name=$(sed -nE 's/^name="([^"]+)".*/\1/p' <<< "$line")
        [ -n "$name" ] || continue
        grep -q 'container_certificate="PRESIGNED"' <<< "$line" && continue
        if ! grep -qxF "$name" <<< "$shipped"; then
            args+=(--extra_apks "$name=PRESIGNED" --extra_apex_payload_key "$name=")
            continue
        fi
        key=$keys/apex/${name%.apex}
        if [ ! -f "$key.pk8" ] || [ ! -f "$key.pem" ]; then
            die "no release key for $name in $KEYS/apex"
        fi
        args+=(--extra_apks "$name=$key" --extra_apex_payload_key "$name=$key.pem")
    done < <(unzip -p "$target_files" META/apexkeys.txt)

    local registered apk
    registered=$(unzip -p "$target_files" META/apkcerts.txt | sed -nE 's/^name="([^"]+)".*/\1/p')
    while IFS= read -r apk; do
        grep -qxF "$apk" <<< "$registered" || args+=(-e "$apk=")
    done < <(unzip -Z1 "$target_files" 'SYSTEM/*.apk' | sed -E 's#.*/##' | sort -u)

    PATH=$host/bin:$jdk:$PATH ANDROID_BUILD_TOP=$TREE \
        "$host/bin/sign_target_files_apks" -o -d "$keys" "${args[@]}" "$target_files" "$SIGNED/target_files.zip"
    rm -rf "$keys"
    PATH=$host/bin:$jdk:$PATH ANDROID_BUILD_TOP=$TREE \
        "$host/bin/add_img_to_target_files" -a "$SIGNED/target_files.zip"
    unzip -p "$SIGNED/target_files.zip" IMAGES/system.img > "$SIGNED/system.img"
    unzip -p "$SIGNED/target_files.zip" SYSTEM/build.prop | grep -q 'release-keys' \
        || die "signed system does not report release-keys"
    openssl x509 -in "$KEYS/releasekey.x509.pem" -noout -fingerprint -sha256 > "$SIGNED/releasekey.txt"
    log "signed with the release keys: $(cut -d= -f2 "$SIGNED/releasekey.txt")"
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
            --kernel) args[i + 1]=$KERNEL/dist/Image.lzma ;;
            --ramdisk) args[i + 1]=$IMAGES/ramdisk.img ;;
            --cmdline) args[i + 1]="${args[i + 1]}$extra_cmdline" ;;
        esac
    done
    python3 "$TREE/system/tools/mkbootimg/mkbootimg.py" "${args[@]}" --output "$out"

    local props=() key value
    while IFS=$'\t' read -r key value; do
        props+=(--prop "$key:$value")
    done < <(python3 -I "$TREE/external/avb/avbtool.py" info_image --image "$IMAGES/stock/boot.img" \
        | sed -nE "s/^ +Prop: (\S+) -> '(.*)'$/\1\t\2/p")
    python3 -I "$TREE/external/avb/avbtool.py" add_hash_footer --image "$out" --partition_name boot \
        --partition_size "$BOOT_PARTITION_SIZE" --algorithm NONE "${props[@]}" \
        --salt "$(basename "$out" | sha256sum | cut -c1-64)"
}

# Builds vendor, boot, product, super and vbmeta, which the device tree never
# builds, reads every partition back out of super and writes SHA256SUMS.txt.
# Always runs.
step_images() {
    local ota host=$TREE/out/host/linux-x86/bin
    ota=$(stock_ota)
    E2FSPROGS_FAKE_TIME=$(source_date_epoch)
    export E2FSPROGS_FAKE_TIME
    rm -rf "$IMAGES" "$DIST"
    mkdir -p "$IMAGES/stock" "$DIST"
    cd "$IMAGES"
    unzip -q -o "$ota" boot.img -d stock
    local name
    for name in vendor odm system_dlkm; do
        stock_partition "$ota" "$name" stock
    done
    mv stock/odm.img stock/system_dlkm.img .
    if [ -f "$SIGNED/system.img" ]; then
        cp "$SIGNED/system.img" system.img
    else
        cp "$TREE/out/target/product/generic/system.img" system.img
    fi

    # Stock vendor uses deduplicated blocks; unshare them so replacing the fstab frees no shared block.
    cp stock/vendor.img vendor.img
    "$RESIZE2FS" vendor.img $(( $(stat -c %s vendor.img) / 4096 + 8192 ))
    "$E2FSCK" -fy -E unshare_blocks vendor.img || [ $? -eq 1 ]
    "$DEBUGFS" -R "dump /etc/fstab.amlogic fstab.stock" vendor.img
    grep -v -E '^product[[:space:]]+/product[[:space:]]' fstab.stock > fstab.amlogic
    [ "$(wc -l < fstab.amlogic)" -eq $(( $(wc -l < fstab.stock) - 1 )) ] || die "vendor fstab has no single /product entry"
    # Rules the stock vendor policy lacks under Android 16 enforcing.
    "$DEBUGFS" -R "dump /etc/selinux/vendor_sepolicy.cil vendor_sepolicy.cil" vendor.img
    "$DEBUGFS" -R "ea_get -f label.sepolicy /etc/selinux/vendor_sepolicy.cil security.selinux" vendor.img
    cat "$TREE/device/google/sabrina16/vendor-config/sepolicy-additions.cil" >> vendor_sepolicy.cil
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
rm /etc/selinux/vendor_sepolicy.cil
write vendor_sepolicy.cil /etc/selinux/vendor_sepolicy.cil
set_inode_field /etc/selinux/vendor_sepolicy.cil mode 0100644
set_inode_field /etc/selinux/vendor_sepolicy.cil uid 0
set_inode_field /etc/selinux/vendor_sepolicy.cil gid 0
ea_set -f label.sepolicy /etc/selinux/vendor_sepolicy.cil security.selinux
EOF
    "$DEBUGFS" -w -f vendor.debugfs vendor.img
    "$E2FSCK" -fn vendor.img
    "$DEBUGFS" -R "dump /etc/fstab.amlogic fstab.readback" vendor.img
    cmp fstab.readback fstab.amlogic || die "vendor fstab readback differs"
    "$DEBUGFS" -R "dump /etc/selinux/vendor_sepolicy.cil sepolicy.readback" vendor.img
    cmp sepolicy.readback vendor_sepolicy.cil || die "vendor sepolicy readback differs"

    truncate -s 4M product.img
    "$MKE2FS" -q -t ext4 -F -b 4096 -L product -U 5ab21aa0-0000-4000-8000-000000000001 \
        -E hash_seed=5ab21aa0-0000-4000-8000-000000000002 product.img

    python3 "$TREE/system/tools/mkbootimg/unpack_bootimg.py" --boot_img stock/boot.img --out stock/boot >/dev/null
    python3 -I "$HERE/tools/edit_ramdisk_fstab.py" stock/boot/ramdisk ramdisk.img first_stage_ramdisk/fstab.amlogic 'product '
    make_boot "$DIST/boot.img" ""
    if [ "$DIAGNOSTIC" = 1 ]; then
        make_boot "$DIST/boot-permissive.img" " sabrina.selinux=permissive androidboot.sabrina_watchdog=1"
        local files=() name
        mkdir -p debug
        cp "$TREE/out/target/product/generic/debug_ramdisk/"{adb_debug.prop,userdebug_plat_sepolicy.cil} debug/
        echo 'persist.sys.usb.config=adb' >> debug/adb_debug.prop
        : > debug/force_debuggable
        for name in force_debuggable adb_debug.prop userdebug_plat_sepolicy.cil; do
            files+=("$name=debug/$name" "first_stage_ramdisk/$name=debug/$name")
        done
        cp ramdisk.img ramdisk.release.img
        python3 -I "$HERE/tools/add_ramdisk_files.py" ramdisk.release.img ramdisk.img "${files[@]}"
        make_boot "$DIST/boot-debug.img" " sabrina.selinux=permissive androidboot.sabrina_watchdog=1"
        mv ramdisk.release.img ramdisk.img
    fi

    # Stock recovery's factory reset wipes env and relocks the device; this one doesn't.
    unzip -q -o "$ota" recovery.img -d stock
    local otacert=$TREE/build/make/target/product/security/testkey.x509.pem
    signing && otacert=$KEYS/releasekey.x509.pem
    python3 -I "$HERE/tools/make_recovery.py" --tree "$TREE" --stock stock/recovery.img \
        --kernel "$KERNEL/dist/Image.lzma" --otacert "$otacert" --out "$DIST/recovery.img"

    local total=0 cmd=("$host/lpmake" --metadata-size=65536 --metadata-slots=2
        "--device=super:$SUPER_SIZE:1048576:0" --super-name=super
        "--group=$SUPER_GROUP:$SUPER_GROUP_SIZE" --block-size=4096)
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

    if [ -f "$SIGNED/releasekey.txt" ]; then
        echo "release-keys, releasekey $(cat "$SIGNED/releasekey.txt")" > "$DIST/KEYS.txt"
    else
        echo "test-keys (AOSP's public keys)" > "$DIST/KEYS.txt"
    fi
    (cd "$DIST" && sha256sum -- *.img > SHA256SUMS.txt)
    log "flash set: $DIST"
}

# Each step leaves a marker in .stamps/ and is skipped on the next run, except
# build, sign and images. Name steps as arguments to run only those.
main() {
    local steps=(guide init sync device stock apps kernel_tools kernel_source kernel_stock kernel_build build sign images)
    local always=" build sign images "
    [ $# -eq 0 ] || steps=("$@")
    mkdir -p "$STAMPS"

    local step
    for step in "${steps[@]}"; do
        declare -F "step_$step" >/dev/null || die "unknown step: $step"
        if [ "$step" = device ] && [ "$(cat "$STAMPS/device" 2>/dev/null)" != "diagnostic=$DIAGNOSTIC" ]; then
            rm -f "$STAMPS/device"
        fi
        if [[ "$always" != *" $step "* ]] && [ -e "$STAMPS/$step" ]; then
            log "$step: already done"
            continue
        fi
        log "$step"
        ( "step_$step" )
        # A fresh device tree has lost the files stock and apps put into it.
        [ "$step" = device ] && rm -f "$STAMPS/stock" "$STAMPS/apps"
        [[ "$always" == *" $step "* ]] || echo "diagnostic=$DIAGNOSTIC" > "$STAMPS/$step"
    done
}

main "$@"
