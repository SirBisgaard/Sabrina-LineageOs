# Credits

This repository only automates and patches other people's work.

## lineageos-23.2-sabrina

**[fidalgojoao/lineageos-23.2-sabrina](https://github.com/fidalgojoao/lineageos-23.2-sabrina)** is the LineageOS 23.2 port this build is based on: the device tree, the kernel and source patches, the diagnostic init and the build guide. This repository's device makefiles and diagnostic watchdog patches are modified from that project and stay under its Apache 2.0 license; [NOTICE](NOTICE) lists them. See its [CREDITS.md](https://github.com/fidalgojoao/lineageos-23.2-sabrina/blob/main/CREDITS.md) for everyone it builds on.

## sabrina-unlock-v2

**[oddsolutions/sabrina-unlock-v2](https://github.com/oddsolutions/sabrina-unlock-v2)** unlocks the bootloader. Nothing here works without it.

- **Nolen Johnson (npjohnson), Jan Altensen (Stricted) and Ray Volpe (Functioner):** the exploit chain
- **[k-o-n-t-o-r](https://github.com/k-o-n-t-o-r):** [ghostlock-sabrina](https://github.com/k-o-n-t-o-r/ghostlock-sabrina), used for temporary root
- **BigEmpty @ XDA, P0werpl @ XDA and Brian Light:** `env` and CRC work, testing and whitepaper review

Read the [whitepaper](https://oddsolutions.github.io/Chromecast-with-Google-TV-4K-Secure-Boot-Bypass-v2/) for how it works.

## LineageOS

**[LineageOS](https://lineageos.org/)** is the system this builds, including Catapult, the home screen. It's built on the [Android Open Source Project](https://source.android.com/).

The LineageOS 24.0 branch builds directly from LineageOS's official device trees for this Chromecast: [`android_device_google_sabrina`](https://github.com/LineageOS/android_device_google_sabrina), [`android_device_amlogic_g12-common`](https://github.com/LineageOS/android_device_amlogic_g12-common) and [`android_device_amlogic_common`](https://github.com/LineageOS/android_device_amlogic_common), with the Amlogic 5.15 kernel sources LineageOS hosts. They are maintained by Nolen Johnson (npjohnson) and Bruno Martins, among others.

## TheMuppets

**[TheMuppets](https://github.com/TheMuppets)** hosts the device's proprietary vendor files the official device tree builds with: [`proprietary_vendor_google_sabrina`](https://github.com/TheMuppets/proprietary_vendor_google_sabrina) and [`proprietary_vendor_amlogic_g12-common`](https://github.com/TheMuppets/proprietary_vendor_amlogic_g12-common).

## SmartTube

**[yuliskov/SmartTube](https://github.com/yuliskov/SmartTube)**, by Yurii Liskov (yuliskov), is the built-in YouTube app. The build downloads its official release APK and includes it unmodified, so it keeps its author's signature. SmartTube is licensed under the MIT License.

## Others

- **[MindTheGapps](https://github.com/MindTheGapps)** for `vendor_gapps_tv`
- **Google**, for publishing the kernel and Amlogic driver sources through its [Nest open-source manifests](https://nest-open-source.googlesource.com/manifests/)

This project is unofficial and isn't affiliated with Google, LineageOS or the projects above.
