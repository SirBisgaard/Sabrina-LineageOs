#!/usr/bin/env bash
# Generates your own release signing keys for this build, with AOSP's make_key and
# avbtool from the synced Android tree: the platform keys, one key per APEX in the
# built system image, and the Android Verified Boot key. The keys have no password.
#
# Usage: make_release_keys.sh <android tree> <output folder> [certificate subject]
#   make_release_keys.sh work/android16 ~/private/sabrina-keys
#
# The Android build must have run once, so the APEX list can be read from it.
# Keep the output private: whoever has these keys can sign updates your devices accept.
set -euo pipefail

[ $# -ge 2 ] || { echo "usage: $0 <android tree> <output folder> [certificate subject]" >&2; exit 2; }
tree=$(cd "$1" && pwd)
out=$2
subject=${3:-/C=DK/O=Sabrina-LineageOs/OU=Release/CN=Sabrina-LineageOs}
apex_dir=$tree/out/target/product/generic/system/apex
platform_keys=(releasekey platform shared media networkstack nfc sdk_sandbox bluetooth testkey testcert)

[ -x "$tree/development/tools/make_key" ] || { echo "error: $tree has no development/tools/make_key" >&2; exit 1; }
[ -d "$apex_dir" ] || { echo "error: $apex_dir is missing; run the build once first" >&2; exit 1; }
[ ! -e "$out" ] || { echo "error: $out already exists; keys are never overwritten" >&2; exit 1; }

mapfile -t apexes < <(find "$apex_dir" "$tree/out/target/product/generic/system/system_ext/apex" \
    -maxdepth 1 \( -name '*.apex' -o -name '*.capex' \) -printf '%f\n' 2>/dev/null \
    | sed -E 's/\.c?apex$//' | sort -u)
[ "${#apexes[@]}" -gt 0 ] || { echo "error: no APEXes found in the build" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
sed 's/2048/4096/g' "$tree/development/tools/make_key" > "$work/make_key_4096"
chmod +x "$work/make_key_4096"

mkdir -p "$out/apex"
for key in "${platform_keys[@]}"; do
    printf '\n' | "$tree/development/tools/make_key" "$out/$key" "$subject" >/dev/null 2>&1 || true
done
for apex in "${apexes[@]}"; do
    printf '\n' | "$work/make_key_4096" "$out/apex/$apex" "$subject" >/dev/null 2>&1 || true
    openssl pkcs8 -in "$out/apex/$apex.pk8" -inform DER -nocrypt -out "$out/apex/$apex.pem"
done
openssl genrsa 4096 2>/dev/null > "$out/avb.pem"
python3 -I "$tree/external/avb/avbtool.py" extract_public_key --key "$out/avb.pem" --output "$out/avb_pkmd.bin"

# make_key exits 1 even on success, so the files are checked instead.
for key in "${platform_keys[@]}" "${apexes[@]/#/apex/}"; do
    if [ ! -s "$out/$key.pk8" ] || [ ! -s "$out/$key.x509.pem" ]; then
        echo "error: $key was not created" >&2
        exit 1
    fi
done
echo "created ${#platform_keys[@]} platform keys, ${#apexes[@]} APEX keys and the AVB key in $out"
