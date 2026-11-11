# Sabrina-LineageOs

This repo is for people who want a clean Chromecast with Google TV 4K (`sabrina`): LineageOS 23.2 (Android 16) with Google's setup and Play Store, without Google TV's launcher.

The project's output is running on my own Chromecast with Google TV 4K, a production unit unlocked from stock build `UTTC.250917.004` and connected to a 4K TV at 2160p60, and is working fantastically.

The repo contains a [guide](HOWTO.md) on how to reproduce it, and the output is published as a [release](https://github.com/SirBisgaard/Sabrina-LineageOs/releases).

## How to

The step-by-step guide is in [HOWTO.md](HOWTO.md): the tools, the bootloader unlock, then either installing a downloaded release or building the images yourself, and flashing and setting up the TV.

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
| `boot.img` | Stock boot with the new kernel, a first-stage fstab without `/product`, `sabrina.selinux=permissive` on the command line, and stock's unsigned AVB footer |
| `vbmeta.img` | Verification and hashtree disabled (flags 3), unsigned |

The build uses AOSP test keys, and doesn't sign the images. That suits an unlocked device you keep offline, not a device you hand to anyone else.

**Tested on one device.** The images run SELinux permissive with verification disabled. Use the Chromecast's own power supply: on a weak USB source, such as a computer's USB port, the boot waits for the low-power warning, see [Findings from flashing](NOTES.md#findings-from-flashing).

## Notes

What went wrong while porting and flashing, and how each problem was fixed, is in [NOTES.md](NOTES.md).

## Credits

This builds on [fidalgojoao/lineageos-23.2-sabrina](https://github.com/fidalgojoao/lineageos-23.2-sabrina), the LineageOS port, and [oddsolutions/sabrina-unlock-v2](https://github.com/oddsolutions/sabrina-unlock-v2), the bootloader unlock, and on [LineageOS](https://lineageos.org/) itself. See [CREDITS.md](CREDITS.md) for everyone involved.

## License

This repository's own files are licensed under the [European Union Public Licence v. 1.2](LICENSE). The files modified from lineageos-23.2-sabrina stay under the [Apache License 2.0](LICENSE-APACHE-2.0); [NOTICE](NOTICE) lists them.

## Disclaimer

Sabrina-LineageOs is not associated with Google LLC or LineageOS in any way, and is not endorsed or supported by them.

Chromecast, Google TV and Android are trademarks of Google LLC. LineageOS is a trademark of its respective owner.

### Use of LLMs (AI)

LLMs were used to write parts of this code. I review it, I test it, I'm responsible for it.
