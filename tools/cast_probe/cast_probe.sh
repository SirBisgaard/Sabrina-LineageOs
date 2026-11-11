#!/usr/bin/env bash
# Checks the Chromecast's Cast credentials over adb: reads the factory certificate
# chain and wrapped key through the castkey DRM plugin, and asks the TEE to sign
# with each key file given. Builds the probe with the Android tree's own JDK,
# android.jar and d8, so nothing is downloaded.
#
# Usage: cast_probe.sh <android tree> [device key file ...]
#   cast_probe.sh work/android16 /mnt/vendor/factory/client.key
set -euo pipefail

tree=$(cd "$1" && pwd)
shift
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
adb=${ADB:-adb}
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT

mkdir "$build/classes" "$build/dex"
"$tree/prebuilts/jdk/jdk21/linux-x86/bin/javac" -nowarn -source 8 -target 8 \
    -cp "$tree/prebuilts/sdk/36/public/android.jar" -d "$build/classes" "$here/CastProbe.java" 2>/dev/null
"$tree/prebuilts/jdk/jdk21/linux-x86/bin/java" -cp "$tree/prebuilts/r8/r8.jar" com.android.tools.r8.D8 \
    --min-api 30 --output "$build/dex" "$build"/classes/*.class

remote=/data/local/tmp/cast-probe
"$adb" shell "rm -rf $remote && mkdir -p $remote"
"$adb" push -q "$build/dex/classes.dex" "$remote/probe.dex"
args=()
for key in "$@"; do
    args+=("$key" PKCS1-BlockType1)
done
"$adb" shell "cd $remote && CLASSPATH=$remote/probe.dex app_process $remote CastProbe ${args[*]}"
"$adb" shell "rm -rf $remote"
