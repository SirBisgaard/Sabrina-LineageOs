# SPDX-License-Identifier: EUPL-1.2
# Sabrina-LineageOs additions. vendor/lineage/config/common.mk inherits this file.

# Google's Play Store and services, without Google's Android TV launcher.
GMS_VARIANT := minimal
$(call inherit-product, vendor/gapps_tv/arm/arm-vendor.mk)

PRODUCT_SOONG_NAMESPACES += vendor/extra

PRODUCT_PACKAGES += \
    SabrinaGoogleTVDream \
    SabrinaSmartTube \
    $(foreach lib,$(notdir $(wildcard vendor/extra/proprietary/smarttube-lib/*.so)),SabrinaSmartTube_$(lib)) \
    privapp-permissions-sabrina-dreamx.xml
