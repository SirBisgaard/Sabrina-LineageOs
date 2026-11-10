LOCAL_PATH := $(call my-dir)

ifeq ($(TARGET_PRODUCT),lineage_gsi_sabrina16)

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

include $(CLEAR_VARS)
LOCAL_MODULE := SabrinaChromecastAxelOverlay
LOCAL_MODULE_STEM := ChromecastAxelOverlay.apk
LOCAL_MODULE_CLASS := ETC
LOCAL_SRC_FILES := proprietary/ChromecastAxelOverlay.apk
LOCAL_MODULE_PATH := $(TARGET_OUT_PRODUCT)/overlay/AxelOverlay
LOCAL_LICENSE_KINDS := legacy_proprietary
LOCAL_LICENSE_CONDITIONS := proprietary
include $(BUILD_PREBUILT)

endif
