# SPDX-License-Identifier: EUPL-1.2
# SmartTube's native libraries are compressed inside its APK, and a preinstalled
# app's libraries are not unpacked at install time, so they are installed next to it.
LOCAL_PATH := $(call my-dir)

ifeq ($(TARGET_DEVICE),sabrina)

define sabrina-smarttube-jni
include $$(CLEAR_VARS)
LOCAL_MODULE := SabrinaSmartTube_$(1)
LOCAL_MODULE_STEM := $(1)
LOCAL_MODULE_CLASS := ETC
LOCAL_SRC_FILES := proprietary/smarttube-lib/$(1)
LOCAL_MODULE_PATH := $$(TARGET_OUT_PRODUCT)/app/SabrinaSmartTube/lib/arm
LOCAL_LICENSE_KINDS := legacy_proprietary
LOCAL_LICENSE_CONDITIONS := proprietary
include $$(BUILD_PREBUILT)
endef

$(foreach lib,$(notdir $(wildcard $(LOCAL_PATH)/proprietary/smarttube-lib/*.so)),\
  $(eval $(call sabrina-smarttube-jni,$(lib))))

endif
