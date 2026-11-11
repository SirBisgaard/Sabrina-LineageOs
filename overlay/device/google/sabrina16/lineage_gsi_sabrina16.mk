# SPDX-License-Identifier: Apache-2.0
# Experimental framework-only image. Retain the on-device stock boot/vendor/odm.
TARGET_PRODUCT_PROP := device/google/sabrina16/bluetooth.prop
PRODUCT_GMS_CLIENTID_BASE := android-google-tv
$(call inherit-product, vendor/lineage/build/target/product/lineage_gsi_tv_arm.mk)

# This Chromecast has ARM32 userspace and a 64-bit binder/kernel interface.
# The generic ARM TV board already implements that combination.
PRODUCT_NAME := lineage_gsi_sabrina16
PRODUCT_MODEL := Chromecast with Google TV 4K (Android 16 development)
PRODUCT_BRAND := google
PRODUCT_MANUFACTURER := Google

# Only VNDK 34 is needed by the verified stock Android 14 vendor image.
PRODUCT_EXTRA_VNDK_VERSIONS := 34

# Firmware OTAs use recovery on this non-A/B device. APK/APEX updates remain on.
PRODUCT_SYSTEM_PROPERTIES += ro.build.firmware_ota_blocked=true
PRODUCT_SYSTEM_PROPERTIES += ro.build.privacy_minimized=true

# Minimal here means keep the original Google TV home app instead of replacing
# it with the Android TV launcher. Play services, TV Play Store, Cast and account
# setup are still included by the upstream TV GApps product.
GMS_VARIANT := minimal
$(call inherit-product, vendor/gapps_tv/arm/arm-vendor.mk)

PRODUCT_SOONG_NAMESPACES += device/google/sabrina16
SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS += device/google/sabrina16/sepolicy/system_ext/private
PRODUCT_PACKAGES += SabrinaLegacyFrameworkMatrix4
PRODUCT_PACKAGES += SabrinaGoogleTVDream SabrinaGboardTV
PRODUCT_PACKAGES += SabrinaSmartTube
PRODUCT_PACKAGES += SabrinaTVAxel SabrinaChromecastAxelOverlay
PRODUCT_PACKAGES += SabrinaSetupBridge
PRODUCT_PACKAGES += SabrinaFrameworkOverlay SabrinaTvSettingsOverlay SabrinaWifiOverlay
PRODUCT_COPY_FILES += \
    device/google/sabrina16/permissions/privapp-permissions-sabrina-axel.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/permissions/privapp-permissions-sabrina-axel.xml \
    device/google/sabrina16/permissions/default-sabrina-axel.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/default-permissions/default-sabrina-axel.xml
PRODUCT_BUILD_PROP_OVERRIDES += DeviceName=sabrina ProductModel=Chromecast
PRODUCT_PACKAGES += $(foreach lib,$(notdir $(wildcard device/google/sabrina16/proprietary/smarttube-lib/*.so)),SabrinaSmartTube_$(lib))
PRODUCT_PACKAGES += SabrinaFrameworkExtensionMatrix

PRODUCT_COPY_FILES += \
    device/google/sabrina16/permissions/privapp-permissions-sabrina-launcher.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/permissions/privapp-permissions-sabrina-launcher.xml \
    device/google/sabrina16/permissions/privapp-permissions-sabrina-dreamx.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/permissions/privapp-permissions-sabrina-dreamx.xml \
    device/google/sabrina16/permissions/sabrina-launcher-defaults.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/default-permissions/sabrina-launcher-defaults.xml \
    device/google/sabrina16/permissions/sabrina-google-tv.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/sysconfig/sabrina-google-tv.xml \
    device/google/sabrina16/permissions/sabrina-google-build.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/sysconfig/sabrina-google-build.xml \
    device/google/sabrina16/permissions/sabrina-ota-components.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/sysconfig/sabrina-ota-components.xml \
    device/google/sabrina16/permissions/sabrina-privacy-components.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/sysconfig/sabrina-privacy-components.xml

# Compile a system image only. No boot chain, firmware or full OTA is generated.
PRODUCT_BUILD_SYSTEM_IMAGE := true
PRODUCT_BUILD_BOOT_IMAGE := false
PRODUCT_BUILD_DEBUG_BOOT_IMAGE := false
PRODUCT_BUILD_RECOVERY_IMAGE := false
PRODUCT_BUILD_VENDOR_BOOT_IMAGE := false
PRODUCT_BUILD_DEBUG_VENDOR_BOOT_IMAGE := false
PRODUCT_BUILD_INIT_BOOT_IMAGE := false
PRODUCT_BUILD_VENDOR_IMAGE := false
PRODUCT_BUILD_ODM_IMAGE := false
PRODUCT_BUILD_SYSTEM_DLKM_IMAGE := false
PRODUCT_BUILD_PRODUCT_IMAGE := false
PRODUCT_BUILD_USERDATA_IMAGE := false
PRODUCT_BUILD_SUPER_PARTITION := false
PRODUCT_BUILD_SUPER_EMPTY_IMAGE := false
PRODUCT_BUILD_VBMETA_IMAGE := false
TARGET_FORCE_OTA_PACKAGE :=

# Board-specific optional legacy controller; also included by the offline vendor assembler.
PRODUCT_COPY_FILES += \
    device/google/sabrina16/vendor-config/cgroups.json:$(TARGET_COPY_OUT_VENDOR)/etc/cgroups.json

# Android 16's EGL loader stops at ro.board.platform=sabrina and skips its wildcard search.
PRODUCT_PRODUCT_PROPERTIES += ro.hardware.egl=mali

# File picker for the Updater's local update.
PRODUCT_PACKAGES += DocumentsUI

# Battery level of remotes and accessories.
