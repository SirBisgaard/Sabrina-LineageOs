# Sabrina-LineageOs

This repo is for people who want a clean Chromecast with Google TV 4K (`sabrina`): LineageOS 23.2 (Android 16) with Google's setup and Play Store, without Google TV's launcher.

The project's output is running on my own Chromecast with Google TV 4K, a production unit unlocked from stock build `UTTC.250917.004` and connected to a 4K TV at 2160p60, and is working fantastically.

The repo contains a guide below on how to reproduce it, and the output is published as a [release](https://github.com/SirBisgaard/Sabrina-LineageOs/releases).

## How to

It takes three parts: install the tools, unlock the bootloader, then build and flash LineageOS.

Throughout the unlock and flash, keep the device connected to the computer by USB and to a monitor or TV by HDMI at the same time. USB gives you `adb` and `fastboot` for flashing and debugging, and powers the device. HDMI shows you what it's doing.

### Part 0: Prerequisites

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

**3. Clone this repository.** Part 1 uses one of its scripts and Part 2 uses the Docker build.

```bash
git clone https://github.com/SirBisgaard/Sabrina-LineageOs.git
```

### Part 1: Unlock the bootloader

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
- Leave Developer options and USB debugging switched on. Step 6 of Part 2 uses adb on stock to enter fastboot.

### Part 2: Build and flash LineageOS

These are the steps used on the tested device, from an empty folder to a set-up TV. The commands are for Linux.

You need:

- Docker and git.
- Roughly 300 GB free for the build. This is an estimate.
- 16 GB RAM or more, plus swap.
- Several hours for the first build.

**1. Make the build folder.** Optionally, put your own stock OTA for `UTTC.250917.004` in it. If it is missing, the build downloads the one linked from sabrina-unlock-v2. Either way, its SHA-256 has to match.

```bash
mkdir -p ~/sabrina/work/inputs
cp /path/to/stock-ota.zip ~/sabrina/work/inputs/stock-ota.zip   # optional
```

**2. Build the Docker image:**

```bash
cd ~/sabrina/Sabrina-LineageOs
docker build -t sabrina-build --build-arg UID=$(id -u) --build-arg GID=$(id -g) .
```

**3. Run the build:**

```bash
docker run --rm -v ~/sabrina/work:/work sabrina-build
```

It downloads the sources, builds the kernel and LineageOS, and assembles the images. The comments in `tools/build.sh` say what each step does. If it stops, run the same command again: finished steps are skipped. Settings can be passed with `-e`: `JOBS` (build jobs, default all cores; lower it if the machine starts swapping), `SYNC_JOBS` (parallel downloads, default 8) and `CCACHE_SIZE` (default `50G`). Every git checkout is shallow (`--depth=1`), so no history is downloaded.

The results are in `~/sabrina/work/dist/`: `super.sparse.img`, `boot.img`, `vbmeta.img`, `SHA256SUMS.txt` and the exact `lpmake` command. The kernel and its checksums are in `~/sabrina/work/kernel/dist/`.

**4. Check the images:**

```bash
cd ~/sabrina/work/dist
sha256sum -c SHA256SUMS.txt
```

**5. Connect the device** by USB to a port on the computer itself, not a hub, and by HDMI to the monitor. Through a hub, flashing `super` failed with `reap_urb ... Protocol error`.

**6. Enter fastboot.** On stock, `adb reboot bootloader` comes straight back to Android. Use `adb reboot fastboot`, then `fastboot reboot bootloader`, or hold the button while plugging in power. Then check the device, and stop if any answer differs:

```bash
fastboot devices
fastboot getvar product        # sabrina
fastboot getvar unlocked       # yes
fastboot getvar is-userspace   # no
```

**7. Flash.** Never flash `bootloader` or `env`. The unlock lives in `env`.

```bash
fastboot -S 64M flash super super.sparse.img
fastboot flash boot boot.img
fastboot flash vbmeta vbmeta.img
fastboot getvar unlocked       # still yes
fastboot -w
fastboot reboot
```

If flashing `super` fails partway, the device isn't bricked. The bootloader is untouched, so flash again from the start.

**8. Set up the TV.** The first boot takes over a minute. Pair the remote, connect Wi-Fi and sign in to Google. While pairing, the wizard may crash once with `BluetoothHidHost.setPriority`; the remote still pairs and the wizard continues. At the end, setup hands over to Catapult, the home screen.

After sign-in, the Play Store downloads and updates many apps in the background. Give it time on a working network before judging speed.

**9. Block updates.** With the device still on USB:

```bash
adb shell settings put global ota_disable_automatic_update 1
```

A wipe resets it, so set it again after every `fastboot -w`.

**10. Install apps** from the Play Store. If an app installed before this build's network fix reports no internet, lift LineageOS's network block for it:

```bash
adb shell pm list packages -U <package>    # shows the app's uid
adb shell service call netpolicy 3 i32 <uid> i32 262144
```

**Updating later.** Keep `~/sabrina/work` between builds. Pull the repository and rerun steps 2 to 4: finished steps are skipped, the Android build only rebuilds what changed, and ccache in `~/sabrina/work/ccache` speeds up the rest, so an update takes a fraction of the first build. To pick up changed patches or overlay files, reset the patched projects and delete `~/sabrina/work/.stamps/device` first. Then run steps 5 to 7, flashing only `super` and `boot`, and skip `fastboot -w`. Every build from this repository uses the same AOSP test keys, so it flashes over the top and keeps apps, sign-in and settings.

## What it builds

`system.img`, with these changes on top of the upstream device tree:

- LineageOS's Catapult as the home screen instead of the stock Google TV launcher.
- `SabrinaSetupBridge`, which fixes Google's setup looping without Google's launcher. The wizard's last step launches `com.google.android.apps.tv.launcherx` by name, and without it crashes with `ActivityNotFoundException` and starts over. This small app, built from source with no Google code, takes that package name. When the wizard launches it, it marks setup complete, disables the wizard's home activity, gives the home role to Catapult and opens it. After each boot it repairs the same if needed, and lifts LineageOS's network block from apps that request INTERNET. Because it uses that package name, Google's real launcher can't be installed next to it.
- The stock Google TV screensaver and Gboard for TV.
- [SmartTube](https://github.com/yuliskov/SmartTube) as a built-in app, unmodified, so it keeps its own signature and can update itself. Other apps, such as Emby, come from the Play Store.
- Its own Bluetooth properties file, so the remote battery client is on without a duplicate property.

Plus the fixes from the upstream `docs/ROOT-CAUSES.md` that the upstream device tree leaves out, because the author applied them by editing finished images:

- TvProvision, LineageSetupWizard and the Leanback keyboard are removed, so Google's setup wizard is the only one and sign-in works.
- The product reports `sabrina` and `Chromecast`, so YouTube isn't held to 360p, and Google's TV client ID.
- Stock's Bluetooth device class `44,4,32`, with LE privacy off, so the remote reconnects after a reboot.
- Stock's TV infrared service (`TVAxel`) and its overlay, with stock's permissions, for TV volume and Input.
- The `SabrinaFrameworkOverlay`, `SabrinaTvSettingsOverlay` and `SabrinaWifiOverlay` resource overlays.

And the kernel, `Image.lzma`: the stock `5.15.170-android14-11` kernel rebuilt with `CONFIG_DM_DEFAULT_KEY`, which Android 16's storage needs. The comments in `tools/build.sh` describe how it is pinned and checked.

The `images` step turns these into the three images the upstream `docs/INSTALL.md` flashes:

| Image | Contents |
|---|---|
| `super.sparse.img` | The new system, stock vendor plus `cgroups.json` and without `/product` in its fstab, a 4 MiB empty product, stock odm and system_dlkm |
| `boot.img` | Stock boot with the new kernel, a first-stage fstab without `/product`, adb switched on (`ro.adb.secure=0`, `persist.sys.usb.config=adb`), `sabrina.selinux=permissive` on the command line, and stock's unsigned AVB footer |
| `vbmeta.img` | Verification and hashtree disabled (flags 3), unsigned |

The build uses AOSP test keys, and doesn't sign the images. That suits an unlocked device you keep offline, not a device you hand to anyone else.

**Tested on one device.** The images run SELinux permissive with verification disabled. The boot image on that device has adb switched on, because with adb off it never gets a display.

## Diagnostic build

Every build includes the upstream `patches/diagnostic/` changes to init and apexd, because they hold the `sabrina.selinux=permissive` switch. `DIAGNOSTIC=1` adds two extra boot images: `boot-permissive.img`, which is `boot.img` with the watchdog switched on, and `boot-debug.img`. Booted with either, init logs each boot stage. If boot doesn't finish, it copies logcat into the kernel log and warm-reboots to the bootloader, so the log survives in RAM. The watchdog only runs with `androidboot.sabrina_watchdog=1` on the kernel command line (`patches/system_core-diagnostic-watchdog-opt-in.patch`), which the diagnostic boot images add and a production boot image leaves out. Without it, init logs `sabrina_watchdog: disabled` and doesn't reboot to the bootloader on a crash. It waits 2.5 minutes for boot to complete, or 5 minutes once zygote is running (`patches/system_core-diagnostic-watchdog-5min.patch`; upstream waits 15). Use it to debug, not daily:

```bash
docker run --rm -e DIAGNOSTIC=1 -v /path/to/workdir:/work sabrina-build
```

`DIAGNOSTIC` takes effect in the `build` and `images` steps, which always run.

### Reading logs from a failed boot

`boot-debug.img` is `boot-permissive.img` with Android's own debug-ramdisk files (`adb_debug.prop` and the userdebug policy) instead of the production adb settings. On an unlocked device it boots the same system with adb and `adb root`. Only ever boot it from RAM; never flash it:

```bash
fastboot boot boot-debug.img
adb root
adb shell cat /sys/fs/pstore/console-ramoops-0   # kernel log of the previous boot, if it ended in a warm reboot
adb shell logcat -L -d -b all                    # logcat of the previous boot
adb shell logcat -d -b all                       # this boot
```

The pstore logs only survive a warm reboot, such as the watchdog's. Unplugging the device clears them.

## Findings from flashing

- **system_server crash loop, fixed.** The upstream TvSettings patch makes TV Settings use `android.permission.HDMI_CEC` but doesn't add it to TV Settings' privileged-permission allowlist. `PermissionService.onSystemReady` throws `Signature|privileged permissions not in privileged permission allowlist`, system_server restarts forever, and the screen shows the G logo, then black or the LineageOS boot animation. `patches/packages_apps_TvSettings-hdmi-cec-allowlist.patch` adds it.
- **Getting into fastboot.** On stock, `adb reboot bootloader` comes straight back to Android. `adb reboot fastboot`, then `fastboot reboot bootloader`, works, as does holding the button at power-on. On this build, `adb reboot bootloader` works.
- **USB.** Flashing `super` through a USB hub failed partway with `reap_urb ... Protocol error`. A rear motherboard port and `-S 64M` worked every time. A failed `super` flash isn't a brick: the bootloader stays, so flash again from the start.
- **Setup loop, fixed** by `SabrinaSetupBridge`, see [What it builds](#what-it-builds). Its home activity needs `launchMode="singleTask"`; without it the system refuses with `Can't change activity type once set`. Tested: after setup, Catapult held the home role and the wizard's home activity was disabled.
- **Remote pairing crash, harmless.** While pairing the remote, the wizard crashes once with `NoSuchMethodException: BluetoothHidHost.setPriority`. It calls a method Android 16 removed. The remote still pairs, and the wizard restarts at the same step.
- **Normal boots stay black with adb off; decided to run with adb on.** With the plain boot image, system_server blocks at startup in `DisplayManagerService` waiting for SurfaceFlinger (`waitForService<ISurfaceComposer>`), which never registers, and Android's watchdog restarts it every 77 seconds. The same image with only adb switched on (`force_debuggable` plus `ro.adb.secure=0` and `persist.sys.usb.config=adb`) boots normally, whether flashed or booted from RAM. The debuggable flag, the userdebug SELinux policy and flashed versus `fastboot boot` were each ruled out, which leaves the USB setup with adb off.
- **Apps installed from Play had no network, fixed.** LineageOS gives a newly installed app `POLICY_REJECT_ALL` when `checkUidPermission(INTERNET)` says it lacks INTERNET. On this build that check fails during `PACKAGE_ADDED` even for apps that request it, so the app gets "No address associated with hostname" for every lookup and reports no internet; DR TV did. Android TV settings have no switch to undo it. `patches/frameworks_base-keep-network-for-apps-requesting-internet.patch` only blocks apps that don't request INTERNET in their manifest. `SabrinaSetupBridge` also lifts the block at each boot from third-party apps that request INTERNET. On a running device: `adb shell service call netpolicy 3 i32 <uid> i32 262144`.
- **Signing in installs a lot.** After Google sign-in, the Play Store downloads and updates many Google and TV apps in the background. Give it time on a working network before judging speed or storage, and expect the first minutes to be slow.
- **adb is on after a fresh install.** `boot.img` switches adb on without an authorisation prompt, so even after `fastboot -w` a hang can be inspected over USB. Anyone with a USB cable to the device gets a shell, though not root.

## Fixes over the upstream guide

- The pinned manifest and the Google apps local manifest both list `vendor/gapps_tv`. The duplicate is removed from the pinned copy.
- Most projects are in AOSP groups that a plain sync skips, so it syncs with `-g all`.
- The build needs `out/sabrina-source-manifest.xml`, which the guide does not create.
- The WebView prebuilt is stored with Git LFS, which repo skips by default.
- The emulator's Bluetooth properties and the device makefile both set the battery client, which the build rejects as a duplicate.
- The device tree never builds `boot`, `vendor`, `super` or `vbmeta`, and has no kernel.

## Credits

This builds on [fidalgojoao/lineageos-23.2-sabrina](https://github.com/fidalgojoao/lineageos-23.2-sabrina), the LineageOS port, and [oddsolutions/sabrina-unlock-v2](https://github.com/oddsolutions/sabrina-unlock-v2), the bootloader unlock, and on [LineageOS](https://lineageos.org/) itself. See [CREDITS.md](CREDITS.md) for everyone involved.

## License

This repository's own files are licensed under the [European Union Public Licence v. 1.2](LICENSE). The files modified from lineageos-23.2-sabrina stay under the [Apache License 2.0](LICENSE-APACHE-2.0); [NOTICE](NOTICE) lists them.

## Disclaimer

Sabrina-LineageOs is not associated with Google LLC or LineageOS in any way, and is not endorsed or supported by them.

Chromecast, Google TV and Android are trademarks of Google LLC. LineageOS is a trademark of its respective owner.

### Use of LLMs (AI)

LLMs were used to write parts of this code. I review it, I test it, I'm responsible for it.
