#!/usr/bin/env bash
# Builds LineageOS 24.0 (Android 17) for the Chromecast with Google TV 4K (sabrina)
# from the official LineageOS device tree and TheMuppets' vendor files.
set -euo pipefail

WORK=${WORK:-/work}
TREE=$WORK/lineage-24
STAMPS=$WORK/.stamps-24
DIST=$WORK/dist-24
DOWNLOADS=$WORK/downloads
EXTRA=$TREE/vendor/extra
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
JOBS=${JOBS:-$(nproc)}
SYNC_JOBS=${SYNC_JOBS:-8}
SYNC_ATTEMPTS=${SYNC_ATTEMPTS:-5}
CCACHE_SIZE=${CCACHE_SIZE:-50G}
VARIANT=${VARIANT:-userdebug}

LINEAGE_URL=https://github.com/LineageOS/android.git
LINEAGE_BRANCH=lineage-24.0
REPO_FLAGS=(--depth=1 --git-lfs --no-clone-bundle --repo-rev=v2.72)

OTA_URL=https://android.googleapis.com/packages/ota-api/package/0d0a14a015085ddff485765a28559bcd858d3018.zip
OTA_SHA256=8aacf5f69036c7b881756f031b45834b1770a6973debe07fc8b8d832d9f0c5c2
SMARTTUBE_URL=https://github.com/yuliskov/SmartTube/releases/download/32.71s/SmartTube_stable_32.71_armeabi-v7a.apk
SMARTTUBE_SHA256=288e8caaa11417f6b64d2a7f906cead85c0b8a9bb5904753d7cb4f79d117d023
STOCK_APKS=(
    priv-app/TVDreamXPrebuilt/TVDreamXPrebuilt.apk
)

log() { printf '==> %s\n' "$*"; }
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

missing_projects() {
    repo list -p 2>/dev/null | while IFS= read -r path; do
        [ -e "$path/.git" ] || echo "$path"
    done
}

clean_sync_leftovers() {
    find .repo/projects .repo/project-objects -name '*.lock' -delete 2>/dev/null || true
    while IFS= read -r gitdir; do
        [ -e "$gitdir/HEAD" ] || rm -rf "$gitdir"
    done < <(find .repo/projects -type d -name '*.git' -prune 2>/dev/null)
}

# repo init of LineageOS 24.0 at depth 1 with Git LFS, plus the local manifest
# with the device trees, the kernel sources and the vendor files.
step_init() {
    mkdir -p "$TREE"
    cd "$TREE"
    repo init -u "$LINEAGE_URL" -b "$LINEAGE_BRANCH" "${REPO_FLAGS[@]}"
    mkdir -p .repo/local_manifests
    cp "$HERE/manifests/sabrina.xml" .repo/local_manifests/
}

# repo sync, retried until every project is checked out.
step_sync() {
    cd "$TREE"
    cp "$HERE/manifests/sabrina.xml" .repo/local_manifests/
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
}

# Lays this repository's additions over the tree as vendor/extra, which LineageOS
# inherits by itself, and takes the bootloader out of the update zip: the device's
# bootloader holds the unlock and is never written. Delete .stamps-24/device to
# redo it after changing overlay/.
step_device() {
    cd "$TREE"
    rm -rf vendor/extra
    cp -r "$HERE/overlay/vendor/extra" vendor/extra
    git -C vendor/google/sabrina checkout -q -- Android.mk
    sed -i '/radio\/bootloader\.img/d' vendor/google/sabrina/Android.mk
    ! grep -q bootloader vendor/google/sabrina/Android.mk || die "the bootloader is still in the update zip"
}

# Takes the stock screensaver out of the stock OTA's product image.
step_stock() {
    local ota=$WORK/inputs/stock-ota.zip stock=$WORK/stock-24 apk
    if [ -f "$ota" ]; then
        check_sha "$OTA_SHA256" "$ota"
    else
        mkdir -p "$DOWNLOADS"
        ota=$DOWNLOADS/stock-ota.zip
        fetch "$OTA_URL" "$OTA_SHA256" "$ota"
    fi
    rm -rf "$stock"
    mkdir -p "$stock" "$EXTRA/proprietary"
    unzip -q -o "$ota" product.new.dat.br product.transfer.list -d "$stock"
    brotli -d -f "$stock/product.new.dat.br" -o "$stock/product.new.dat"
    python3 -I "$HERE/tools/sdat2img.py" "$stock/product.transfer.list" "$stock/product.new.dat" "$stock/product.img"
    for apk in "${STOCK_APKS[@]}"; do
        /usr/sbin/debugfs -R "dump /$apk $EXTRA/proprietary/$(basename "$apk")" "$stock/product.img"
        [ "$(head -c 2 "$EXTRA/proprietary/$(basename "$apk")")" = PK ] || die "$apk is not in the stock product image"
    done
    rm -rf "$stock"
}

# Downloads SmartTube at a pinned checksum and unpacks its native libraries.
step_apps() {
    mkdir -p "$DOWNLOADS" "$EXTRA/proprietary"
    fetch "$SMARTTUBE_URL" "$SMARTTUBE_SHA256" "$DOWNLOADS/SmartTube.apk"
    cp "$DOWNLOADS/SmartTube.apk" "$EXTRA/proprietary/SmartTube.apk"
    rm -rf "$EXTRA/proprietary/smarttube-lib"
    mkdir -p "$EXTRA/proprietary/smarttube-lib"
    unzip -q -o -j "$EXTRA/proprietary/SmartTube.apk" 'lib/armeabi-v7a/*.so' -d "$EXTRA/proprietary/smarttube-lib"
}

# The full LineageOS build: the kernel from source, the images and the flashable zip.
# ccache in $WORK/ccache speeds up rebuilds after a clean out/.
step_build() {
    cd "$TREE"
    mkdir -p out
    repo manifest -r -o out/sabrina-source-manifest.xml
    set +u
    # shellcheck source=/dev/null
    source build/envsetup.sh
    # shellcheck source=/dev/null
    source vendor/lineage/vars/aosp_target_release
    export USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache CCACHE_DIR=$WORK/ccache
    mkdir -p "$CCACHE_DIR"
    ccache -M "$CCACHE_SIZE" >/dev/null
    # shellcheck disable=SC2154
    lunch lineage_sabrina "$aosp_target_release" "$VARIANT"
    m -j"$JOBS" bacon
    set -u
    ccache -s | grep -E 'Hits|Misses|Cache size' || true
}

# Copies the flashable zip and the images out of the tree.
step_dist() {
    local out=$TREE/out/target/product/sabrina file
    rm -rf "$DIST"
    mkdir -p "$DIST"
    for file in "$out"/lineage-*.zip "$out"/boot.img "$out"/recovery.img "$out"/dtbo.img \
        "$out"/vbmeta*.img "$out"/super.img "$out"/logo.img "$TREE/out/sabrina-source-manifest.xml"; do
        [ -f "$file" ] && cp "$file" "$DIST/"
    done
    [ -n "$(ls "$DIST")" ] || die "the build left no images in $out"
    (cd "$DIST" && sha256sum -- * > SHA256SUMS.txt)
    log "output: $DIST"
}

# Each step leaves a marker in .stamps-24/ and is skipped on the next run, except
# build and dist. Name steps as arguments to run only those.
main() {
    local steps=(init sync device stock apps build dist)
    local always=" build dist "
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
        # A fresh vendor/extra has lost the files stock and apps put into it.
        [ "$step" = device ] && rm -f "$STAMPS/stock" "$STAMPS/apps"
        [[ "$always" == *" $step "* ]] || touch "$STAMPS/$step"
    done
}

main "$@"
