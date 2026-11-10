#!/usr/bin/env bash
# Back up the stock partitions of an unlocked sabrina to <dest-dir>.
#
# Usage: backup_stock_partitions.sh <ghostlock-binary> <dest-dir>
#   <ghostlock-binary>  path to the ghostlock binary from sabrina-unlock-v2 (bin/ghostlock).
#   <dest-dir>          folder to write <name>.img, manifest.txt, sha256sums.txt.
#
# Needs: adb on PATH; device in ADB with USB debugging on; bootloader unlocked.
# The exploit is one-shot and sometimes exits before the shell gets its commands,
# so the SELinux-drop + chmod is piped into ghostlock's stdin instead of pasted
# into a second terminal, and retried until `getenforce` reports Permissive.
#
# Every partition except userdata, cache, metadata and mmcblk0 is written as
# <name>.img. super is re-dumped in 64 MiB chunks when adb exec-out truncates
# its multi-GiB stream, which happens on this device.

set -euo pipefail

GHOSTLOCK=${1:?path to ghostlock binary required}
DEST=${2:?destination folder required}
SKIP=' userdata cache metadata mmcblk0 '
CHUNK=$(( 64 * 1024 * 1024 ))

[ -x "$GHOSTLOCK" ] || { echo "ghostlock not executable: $GHOSTLOCK" >&2; exit 1; }
adb get-state >/dev/null 2>&1 || { echo "no adb device" >&2; exit 1; }
mkdir -p "$DEST"

echo ">> push ghostlock"
adb push "$GHOSTLOCK" /data/local/tmp/ghostlock >/dev/null
adb shell chmod 755 /data/local/tmp/ghostlock

echo ">> drop SELinux and open block devices via ghostlock (stdin, retrying)"
state=""
for try in 1 2 3 4 5; do
  adb shell "echo 'setenforce 0; chmod 444 /dev/block/by-name/*' | /data/local/tmp/ghostlock --cred" >/dev/null 2>&1 || true
  state=$(adb shell getenforce 2>/dev/null | tr -d '\r' || true)
  [ "$state" = "Permissive" ] && break
  echo "   attempt $try: getenforce=$state, retrying" >&2
  sleep 2
done
[ "$state" = "Permissive" ] || { echo "ghostlock did not drop SELinux" >&2; exit 1; }
echo "   OK (Permissive)"

: > "$DEST/manifest.txt"
: > "$DEST/sha256sums.txt"

for name in $(adb shell 'ls /dev/block/by-name' | tr -d '\r'); do
  case "$SKIP" in *" $name "*) echo "skip $name"; continue;; esac
  tgt=$(adb shell "readlink -f /dev/block/by-name/$name" | tr -d '\r')
  blocks=$(adb shell "cat /sys/class/block/$(basename "$tgt")/size" | tr -d '\r')
  bytes=$(( blocks * 512 ))
  out="$DEST/$name.img"
  printf 'dump %-16s %12s bytes\n' "$name" "$bytes"
  printf '%s\t%s\t%s\n' "$name" "$bytes" "$tgt" >> "$DEST/manifest.txt"

  adb exec-out "dd if=/dev/block/by-name/$name bs=4M 2>/dev/null" > "$out"
  got=$(stat -c %s "$out")
  if [ "$got" != "$bytes" ]; then
    echo "   adb exec-out truncated at $got, re-dumping in 64 MiB chunks"
    : > "$out"
    N=$(( (bytes + CHUNK - 1) / CHUNK ))
    for i in $(seq 0 $((N - 1))); do
      if [ $i -eq $((N - 1)) ]; then
        expect=$(( bytes - i * CHUNK ))
      else
        expect=$CHUNK
      fi
      tmp=$(mktemp)
      for attempt in 1 2 3; do
        adb exec-out "dd if=/dev/block/by-name/$name bs=64M skip=$i count=1 2>/dev/null" > "$tmp" || true
        cs=$(stat -c %s "$tmp")
        [ "$cs" = "$expect" ] && break
        echo "      chunk $i attempt $attempt: expected $expect got $cs" >&2
        sleep 2
      done
      [ "$cs" = "$expect" ] || { rm -f "$tmp"; echo "   chunk $i never completed" >&2; exit 1; }
      cat "$tmp" >> "$out"
      rm -f "$tmp"
    done
    got=$(stat -c %s "$out")
    [ "$got" = "$bytes" ] || { echo "   assembled size still wrong: $got" >&2; exit 1; }
  fi
  (cd "$DEST" && sha256sum "$name.img") >> "$DEST/sha256sums.txt"
done

echo
echo ">> done: $(ls -1 "$DEST"/*.img | wc -l) images in $DEST"
echo ">> reboot the device to restore SELinux and block-device permissions:"
echo "       adb reboot"
