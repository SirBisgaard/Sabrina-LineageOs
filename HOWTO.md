# How to

It takes three parts: install the tools, unlock the bootloader, then install LineageOS, either from a downloaded release or from your own build.

Throughout the unlock and flash, keep the device connected to the computer by USB and to a monitor or TV by HDMI at the same time. USB gives you `adb` and `fastboot` for flashing and debugging, and powers the device. HDMI shows you what it's doing.

## Part 0: Prerequisites

Both parts use the same working folder and the same `adb` and `fastboot`. Set them up once.

**1. Make a working folder.** Everything goes in here: the tools, the unlock repo, this repository, and the build.

```bash
mkdir -p ~/sabrina
cd ~/sabrina
```

**2. Get Android's platform-tools** for `adb` and `fastboot`, and put them on your `PATH`:

```bash
curl -LO https://dl.google.com/android/repository/platform-tools-latest-linux.zip
unzip platform-tools-latest-linux.zip
export PATH="$HOME/sabrina/platform-tools:$PATH"
adb version
fastboot --version
```

The `export` only lasts for this terminal. Run it again in a new one. If `fastboot devices` later says `no permissions`, install your distribution's Android udev rules (on Debian and Ubuntu, `android-sdk-platform-tools-common`) and plug the device in again.

**3. Clone this repository.** Part 1 uses one of its scripts, and track B of Part 2 uses its Docker build.

```bash
git clone https://github.com/SirBisgaard/Sabrina-LineageOs.git
```

## Part 1: Unlock the bootloader

Unlock the device with [oddsolutions/sabrina-unlock-v2](https://github.com/oddsolutions/sabrina-unlock-v2). This build was tested on a device unlocked from stock `UTTC.250917.004`. Read that repository's warnings before you start; they are not repeated here.

You need a USB-C to USB-C cable (USB-A to C will not supply enough power for the device to boot to Android), `python3` on the host, and `adb` and `fastboot` from Part 0.

**1. Enable USB debugging** on stock. In Settings → System → About, click "Android TV OS Build" seven times. Back out, then System → Developer options → USB debugging → on, and accept the "Always allow" prompt that appears on the TV.

**2. Clone the unlock repository:**

```bash
cd ~/sabrina
git clone https://github.com/oddsolutions/sabrina-unlock-v2.git
cd sabrina-unlock-v2
```

**3. Run the unlock.** In your current terminal (call it T1):

```bash
./unlock.sh
```

It hands off to a **second terminal (T2)** three times. Open T2 now; re-run the `export PATH=...` from Part 0 step 2 if needed.

A. In T2, start a silent root shell on the device. No `#` prompt will appear; success is a line ending in `partial plan (hits=3/3) ... battery written`. Re-run the command if the shell exits before that line — a few tries may be needed.

```bash
adb shell "cd /data/local/tmp && ./ghostlock --cred"
```

B. In that same silent T2 shell (keystrokes won't echo), back up env. Wait for `OK: backup`, then in T1 press Enter.

```bash
sh /data/local/tmp/env_tool.sh --backup
```

C. T1 patches env and prints its next instruction. In T2's root shell, flash the patched env (expect `readback lock=10100010`):

```bash
sh /data/local/tmp/env_tool.sh --flash
```

D. **On the device:** unplug power, then power back on and press-and-hold the button on the device when the orange LED comes on. Keep holding through to the bootloader UI.

E. In T1: press Enter at the `Did the device land in RescueParty? [y/N]` prompt (answer No), then Enter again at the `fastboot -w` prompt.

When the script finishes, your pre-unlock `env` is at `~/sabrina/sabrina-unlock-v2/unlock-YYYYMMDD-HHMMSS/env.orig.img`. **Copy that file off this folder now** — it is unique to your board and holds identifiers (MAC, serial) you cannot recover otherwise.

**4. Confirm the unlock** in fastboot:

```bash
fastboot getvar product         # sabrina
fastboot getvar unlocked        # yes
```

If `unlocked` is not `yes`, stop; Part 2 is not safe. Otherwise reboot:

```bash
fastboot reboot
```

Go through stock's setup wizard on the TV far enough to repeat step 1 (re-enable Developer options and USB debugging).

**5. Back up the remaining partitions.** The unlock only captured `env`. For a full restore to stock you need the rest, and the exploit is one-shot and flaky, so do this once now and copy the files somewhere persistent. `tools/backup_stock_partitions.sh` handles it: it pipes the SELinux-drop and the chmod into `ghostlock`'s stdin (no second terminal, no race against the root shell dying), dumps every partition except `userdata`, `cache`, `metadata` and the whole-disk `mmcblk0`, and re-dumps `super` in 64 MiB chunks when `adb exec-out` truncates its ~2 GiB stream, which happens on this device.

```bash
~/sabrina/Sabrina-LineageOs/tools/backup_stock_partitions.sh \
    ~/sabrina/sabrina-unlock-v2/bin/ghostlock \
    ~/sabrina/stock-partitions
```

When done, reboot the device to restore SELinux to enforcing and the block-device permissions:

```bash
adb reboot
```

Move `env.orig.img` from step 3 and this `~/sabrina/stock-partitions/` folder somewhere you keep safe.

After you unlock:

- Keep stock offline, or block its updates. An OTA relocks the bootloader and can stop the unlock from ever working again.
- Never choose Factory data reset in stock recovery. It wipes `env` and relocks the device.
- Leave Developer options and USB debugging switched on. Part 2 uses adb on stock to enter fastboot.

## Part 2: Install LineageOS

Choose one track to get the images, then continue with [Flash and set up](#flash-and-set-up). The commands are for Linux.

### Track A: Download a release

**1. Download** the release zip and its `.sha256` file from the [releases page](https://github.com/SirBisgaard/Sabrina-LineageOs/releases) into `~/sabrina`.

**2. Check and unpack it:**

```bash
cd ~/sabrina
sha256sum -c Sabrina-LineageOs-*.zip.sha256
unzip Sabrina-LineageOs-*.zip
cd Sabrina-LineageOs-*/
sha256sum -c SHA256SUMS.txt
```

Stay in this folder and continue with [Flash and set up](#flash-and-set-up).

### Track B: Build it yourself

These are the steps used for the tested device.

You need:

- Docker and git.
- About 200 GB free for the build.
- 16 GB RAM or more, plus swap. The measured build had 31 GB.
- About 4 hours for the first build. See [Build time and disk space](#build-time-and-disk-space).

All commands in steps 1 to 4 run from the repository folder. The build goes in `work/` inside it, which git and Docker both ignore, so nothing in it is committed or copied into the Docker image.

**1. Make the build folder.** Optionally, put your own stock OTA for `UTTC.250917.004` in it. If it is missing, the build downloads the one linked from sabrina-unlock-v2. Either way, its SHA-256 has to match.

```bash
cd ~/sabrina/Sabrina-LineageOs
mkdir -p work/inputs
cp /path/to/stock-ota.zip work/inputs/stock-ota.zip   # optional
```

**2. Build the Docker image:**

```bash
docker build -t sabrina-build --build-arg UID=$(id -u) --build-arg GID=$(id -g) .
```

**3. Run the build:**

```bash
docker run --rm -v "$PWD/work":/work sabrina-build
```

It downloads the sources, builds the kernel and LineageOS, and assembles the images. The comments in `tools/build.sh` say what each step does. If it stops, run the same command again: finished steps are skipped. Settings can be passed with `-e`: `JOBS` (build jobs, default all cores; lower it if the machine starts swapping), `SYNC_JOBS` (parallel downloads, default 8) and `CCACHE_SIZE` (default `50G`). Every git checkout is shallow (`--depth=1`), so no history is downloaded.

The results are in `work/dist/`: `super.sparse.img`, `boot.img`, `vbmeta.img`, `SHA256SUMS.txt` and the exact `lpmake` command. The kernel and its checksums are in `work/kernel/dist/`.

**4. Check the images:**

```bash
cd work/dist
sha256sum -c SHA256SUMS.txt
```

Then continue with [Flash and set up](#flash-and-set-up), from `work/dist`.

#### Verify a build

Compare a build with another flash set, for example the previous release, from the repository folder:

```bash
python3 tools/compare_images.py work/dist /path/to/previous/dist
```

It compares the boot image part by part, the `super` layout, and every partition file by file, including owners, modes and SELinux labels. Every build stamp comes from one fixed time, the pinned guide commit's (`SOURCE_DATE_EPOCH` overrides it), so two builds of the same sources should be byte-identical.

#### Build time and disk space

Measured on the first full Docker build, on a machine with 12 CPU threads, 31 GB RAM and an NVMe disk:

| Step | Time |
|---|---|
| `guide`, `init`, `sync` (source download) | 18 min |
| `stock`, `apps`, `kernel_tools`, `kernel_source`, `kernel_stock` | 5 min |
| `kernel_build` | 14 min |
| `build` (Android, 130,300 actions) | 2 h 56 min |
| `images` | 6 min |
| **Total** | **about 3 h 40 min** |

The download time depends on your connection. An update only rebuilds what changed, and ccache saves most of the Android build after a clean `out/`.

| Part of the work folder | Size |
|---|---|
| `android16/`, the source checkout | ~87 GB |
| `android16/out/`, the Android build output | 60 GB |
| `android16/.repo/`, git objects | 29 GB |
| `ccache/` | ~5 GB, up to `CCACHE_SIZE` (50 GB) |
| `kernel/` | 4.7 GB |
| `images/` and `dist/` | 3.4 GB |
| `inputs/` and the rest | under 1 GB |
| **Total** | **186 GB** |

The Docker image itself is 1.6 GB. `android16/out/` is the only part you can delete without losing anything; the next build then redoes the Android build, faster with ccache.

## Flash and set up

Run these from the folder with the images: the unpacked release (track A) or `work/dist` (track B).

**1. Connect the device** by USB to a port on the computer itself, not a hub, and by HDMI to the monitor. Through a hub, flashing `super` failed with `reap_urb ... Protocol error`.

**2. Enter fastboot.** On stock, `adb reboot bootloader` comes straight back to Android. Use `adb reboot fastboot`, then `fastboot reboot bootloader`, or hold the button while plugging in power. Then check the device, and stop if any answer differs:

```bash
fastboot devices
fastboot getvar product        # sabrina
fastboot getvar unlocked       # yes
fastboot getvar is-userspace   # no
```

**3. Flash.** Never flash `bootloader` or `env`. The unlock lives in `env`.

```bash
fastboot -S 64M flash super super.sparse.img
fastboot flash boot boot.img
fastboot flash vbmeta vbmeta.img
fastboot flash recovery recovery.img
fastboot getvar unlocked       # still yes
fastboot -w
fastboot reboot
```

`recovery.img` replaces stock recovery, whose Factory data reset wipes `env` and relocks the bootloader. It is LineageOS's recovery in stock's ramdisk, without that wipe list, and it only accepts update zips signed with the build's own key. Move through its menu with the button on the Chromecast: a short press moves, a long press selects. Don't try it with `fastboot boot recovery.img` first: started that way the bootloader leaves HDMI off and the screen stays black, while from its partition the menu shows. A factory reset from this recovery hasn't been tested on a device yet, so keep wiping with `fastboot -w`.

If flashing `super` fails partway, the device isn't bricked. The bootloader is untouched, so flash again from the start.

Now unplug the Chromecast from the computer and connect it to its own power supply. On a computer's USB port the first boot waits for the low-power warning and the screen stays black, see [Findings from flashing](NOTES.md#findings-from-flashing).

**4. Set up the TV.** The first boot takes over a minute. Pair the remote, connect Wi-Fi and sign in to Google. While pairing, the wizard may crash once with `BluetoothHidHost.setPriority`; the remote still pairs and the wizard continues. At the end, setup hands over to Catapult, the home screen.

After sign-in, the Play Store downloads and updates many apps in the background. Give it time on a working network before judging speed.

**5. Updates are blocked automatically.** `SabrinaSetupBridge` sets `ota_disable_automatic_update` to `1` at every boot, also after a wipe. adb is off after a fresh install; to use it, open Settings → System → About on the TV, click "Android TV OS Build" seven times, turn on System → Developer options → USB debugging, connect the Chromecast to the computer by USB and accept the prompt on the TV. Then check:

```bash
adb shell settings get global ota_disable_automatic_update    # 1
```

**6. Install apps** from the Play Store. If an app installed before this build's network fix reports no internet, lift LineageOS's network block for it:

```bash
adb shell pm list packages -U <package>    # shows the app's uid
adb shell service call netpolicy 3 i32 <uid> i32 262144
```

## Diagnostic build

A normal build runs SELinux enforcing and has no diagnostic code. `DIAGNOSTIC=1` adds the upstream `patches/diagnostic/` changes to init and apexd, which hold the `sabrina.selinux=permissive` switch and a boot watchdog, and two extra boot images: `boot-permissive.img`, which is `boot.img` with SELinux permissive and the watchdog switched on, and `boot-debug.img`. Booted with either, init logs each boot stage. If boot doesn't finish, the watchdog copies logcat into the kernel log and warm-reboots to the bootloader, so the log survives in RAM. It only runs with `androidboot.sabrina_watchdog=1` on the kernel command line (`patches/system_core-diagnostic-watchdog-opt-in.patch`), which only the diagnostic boot images add. It waits 2.5 minutes for boot to complete, or 5 minutes once zygote is running (`patches/system_core-diagnostic-watchdog-5min.patch`; upstream waits 15). The `boot.img` of a diagnostic build is the normal enforcing one, but its system image contains the diagnostic code, so use a diagnostic build to debug, not daily:

```bash
docker run --rm -e DIAGNOSTIC=1 -v "$PWD/work":/work sabrina-build   # from the repository folder
```

Switching `DIAGNOSTIC` on or off redoes the `device` step by itself, so the next build applies or removes the diagnostic code.

### Reading logs from a failed boot

`boot-debug.img` is `boot-permissive.img` with Android's own debug-ramdisk files (`adb_debug.prop` and the userdebug policy) and adb switched on. On an unlocked device it boots the same system with adb and `adb root`. Only ever boot it from RAM; never flash it:

```bash
fastboot boot boot-debug.img
adb root
adb shell cat /sys/fs/pstore/console-ramoops-0   # kernel log of the previous boot, if it ended in a warm reboot
adb shell logcat -L -d -b all                    # logcat of the previous boot
adb shell logcat -d -b all                       # this boot
```

The pstore logs only survive a warm reboot, such as the watchdog's. Unplugging the device clears them.

## Your own release keys

The builds sign with AOSP's public test keys, which anyone can use to sign apps and updates the device accepts as part of the system. To ship builds to other people, make your own keys once and keep them private.

**1. Make the keys** after the first build (track B), because the tool reads the list of APEXes from it. From the repository folder:

```bash
tools/make_release_keys.sh work/android16 ~/private/sabrina-release-keys
```

It uses AOSP's own `make_key` and `avbtool` from the synced tree, and creates:

| Files | Use |
|---|---|
| `releasekey`, `platform`, `shared`, `media`, `networkstack`, `nfc`, `sdk_sandbox`, `bluetooth`, `testkey`, `testcert` (`.pk8` and `.x509.pem`) | Android's signing roles for apps and the system |
| `apex/<name>.pk8`, `.x509.pem`, `.pem` | One key per APEX in the build |
| `avb.pem`, `avb_pkmd.bin` | The Android Verified Boot key for `vbmeta`, and its public key |

The keys have no password. A third argument sets the certificate subject; the default is `/C=DK/O=Sabrina-LineageOs/OU=Release/CN=Sabrina-LineageOs`. The tool never overwrites an existing folder.

**2. Keep them private and backed up.** Never commit them to this repository or any public place: whoever has them can sign updates your devices accept. Keep a copy somewhere safe and private, such as a private repository and an offline backup. If you lose them, devices running a build signed with them can't take updates from you without a wipe.

**3. Sign the build with them** by mounting the key folder read-only at `/keys` when you run the build (track B, step 3):

```bash
docker run --rm -v "$PWD/work":/work -v ~/private/sabrina-release-keys:/keys:ro sabrina-build
```

The build then also makes the target files, and the `sign` step signs them with `sign_target_files_apks`: the system apps with your platform keys, every APEX with its own key, and the OTA certificate with your `releasekey`. Prebuilt apps keep their own signatures, so Google's apps and SmartTube still update through the Play Store. The system then reports `release-keys`. `work/dist/KEYS.txt` says how a flash set was signed: `test-keys`, or `release-keys` with the fingerprint of your `releasekey`. Without the mount, the build stays on the test keys.

**4. Switch a device to your keys with one wipe.** The system apps' signatures change, so the first flash of a release-signed build needs `fastboot -w` (see [Flash and set up](#flash-and-set-up), step 3). Every later build signed with the same keys flashes over the top without a wipe.
