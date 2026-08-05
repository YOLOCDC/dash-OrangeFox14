DEVICE_PATH := device/xiaomi/dash
TARGET_COPY_OUT_VENDOR := vendor
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery.fstab
BOARD_VENDOR_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy
TW_USES_VENDOR_LIBS := true

TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv9-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := generic
TARGET_SUPPORTS_64_BIT_APPS := true

TARGET_NO_BOOTLOADER := true
TARGET_NO_RADIOIMAGE := true
TARGET_NO_RECOVERY := true

AB_OTA_UPDATER := true
AB_OTA_PARTITIONS := \
    boot \
    dtbo \
    init_boot \
    mi_ext \
    odm \
    odm_dlkm \
    product \
    system \
    system_dlkm \
    system_ext \
    vbmeta \
    vbmeta_system \
    vbmeta_vendor \
    vendor \
    vendor_boot \
    vendor_dlkm

BOARD_BOOT_HEADER_VERSION := 4
BOARD_BOOTIMAGE_PARTITION_SIZE := 67108864
BOARD_INIT_BOOT_IMAGE_PARTITION_SIZE := 8388608
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 67108864

BOARD_KERNEL_BASE := 0x00000000
BOARD_KERNEL_PAGESIZE := 4096
BOARD_KERNEL_CMDLINE := bootopt=64S3,32N2,64N2
BOARD_MKBOOTIMG_ARGS := \
    --header_version 4 \
    --kernel_offset 0x80000000 \
    --ramdisk_offset 0xa6f00000 \
    --tags_offset 0x87c80000 \
    --dtb_offset 0x0000000087c80000

TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/kernel
BOARD_INCLUDE_DTB_IN_BOOTIMG := true
BOARD_PREBUILT_DTBIMAGE_DIR := $(DEVICE_PATH)/prebuilt/dtb

BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT := true
BOARD_INCLUDE_RECOVERY_RAMDISK_IN_VENDOR_BOOT := true

TW_THEME := portrait_hdpi
# The default DRM path pairs a 16-bit buffer with a 32-bit draw surface.
# Dash's 1280x2772 panel uses the coherent RGBX/XBGR 32-bit Recovery path.
TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888
TW_BRIGHTNESS_PATH := "/sys/class/leds/lcd-backlight/brightness"
TW_MAX_BRIGHTNESS := 16383
TW_DEFAULT_BRIGHTNESS := 8192
# Keep Novatek active while the timeout leaves the backlight at zero.
TW_NO_SCREEN_BLANK := true

# Gzip leaves room for the official platform ramdisk and recovery in vendor_boot.
TW_EXCLUDE_DEFAULT_USB_INIT := true
TW_EXCLUDE_BASH := true
TW_EXCLUDE_NANO := true
TW_EXCLUDE_TZDATA := true
TW_EXCLUDE_LPDUMP := true
TW_EXCLUDE_LPTOOLS := true

# This tracked OrangeFox hook runs after ordinary Recovery relinking and the
# initial manifests, before mkbootfs packages the final root.
BOARD_RECOVERY_IMAGE_PREPARE = $(DEVICE_PATH)/recovery/prepare-ramdisk.sh \
    $(TARGET_RECOVERY_ROOT_OUT) \
    $(SOONG_OUT_DIR)/Android-$(TARGET_PRODUCT).mk \
    $(abspath $(LLVM_READOBJ)) \
    $(abspath $(DEVICE_PATH)/prebuilt/recovery_modules) \
    $(abspath $(DEVICE_PATH)/prebuilt/recovery_properties)

TARGET_RECOVERY_DEVICE_MODULES += \
    servicemanager.recovery \
    dash_recovery_prepare_marker

TW_RECOVERY_ADDITIONAL_RELINK_LIBRARY_FILES += \
    $(TARGET_OUT_SHARED_LIBRARIES)/libsysutils.so

OF_FLASHLIGHT_ENABLE := 1
OF_FL_PATH1 := /sys/class/leds/white:flash-1
OF_FL_PATH2 := /sys/class/leds/white:flash-2

TW_LOAD_VENDOR_BOOT_MODULES := true
TW_LOAD_VENDOR_MODULES := "teeperf.ko mitee.ko rpmb.ko rpmb-mtk.ko p73.ko flashlight.ko leds-mt6379.ko leds-mt6379pmic.ko xiaomi_touch_dash.ko nt38771_touch_dash.ko cs40l26-core.ko cs40l26-i2c.ko cs40l26-spi.ko snd-soc-cs40l26.ko"

# Recovery has no apexd or linkerconfig; skip unsupported APEX loop setup.
TW_EXCLUDE_APEX := true

# Avoid a Recovery-only AIDL Health lookup in the background battery monitor.
TW_USE_LEGACY_BATTERY_SERVICES := true

TW_INCLUDE_CRYPTO := true
TW_INCLUDE_OMAPI := true
$(call soong_config_set,omapi,uuid,9f36407ead0639fc966f14dde7970f68)

BOARD_CUSTOM_MKBOOTIMG := $(DEVICE_PATH)/scripts/mkbootimg-wrapper.sh
