#!/usr/bin/env bash
# Builds LineageOS 24.0 (Android 17) for the Chromecast with Google TV 4K (sabrina)
# from the official LineageOS device tree and TheMuppets' vendor files.
set -euo pipefail

WORK=${WORK:-/work}
TREE=$WORK/lineage-24
STAMPS=$WORK/.stamps-24
DIST=$WORK/dist-24
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
JOBS=${JOBS:-$(nproc)}
SYNC_JOBS=${SYNC_JOBS:-8}
SYNC_ATTEMPTS=${SYNC_ATTEMPTS:-5}
CCACHE_SIZE=${CCACHE_SIZE:-50G}
VARIANT=${VARIANT:-userdebug}

LINEAGE_URL=https://github.com/LineageOS/android.git
LINEAGE_BRANCH=lineage-24.0
REPO_FLAGS=(--depth=1 --git-lfs --no-clone-bundle --repo-rev=v2.72)

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

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
    local steps=(init sync build dist)
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
        [[ "$always" == *" $step "* ]] || touch "$STAMPS/$step"
    done
}

main "$@"
