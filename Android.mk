LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := dash_recovery_prepare_marker
LOCAL_MODULE_TAGS := optional
LOCAL_MODULE_PATH := $(TARGET_RECOVERY_ROOT_OUT)
LOCAL_ADDITIONAL_DEPENDENCIES := \
    $(LOCAL_PATH)/recovery/prepare-ramdisk.sh \
    $(LOCAL_PATH)/prebuilt/recovery_modules/scp.ko \
    $(LOCAL_PATH)/prebuilt/recovery_modules/nt38771_touch_dash.ko \
    $(LOCAL_PATH)/prebuilt/recovery_modules/xiaomi_touch_dash.ko \
    $(LOCAL_PATH)/prebuilt/recovery_modules/modules.dep \
    $(LOCAL_PATH)/prebuilt/recovery_properties/system.build.prop \
    $(LOCAL_PATH)/prebuilt/recovery_properties/vendor.build.prop \
    $(LOCAL_PATH)/recovery/root/system/etc/ld.config.dash-crypto.txt \
    $(LOCAL_PATH)/recovery/root/init.recovery.usb.rc
include $(BUILD_PHONY_PACKAGE)
