# OrangeFox 14.1 `dash` Device Tree

Release package for the Xiaomi `dash` / REDMI K80 Ultra. The tree builds an
OrangeFox 14.1 Recovery `vendor_boot` image from device-derived files taken
from the official `OS3.0.303.0.WONCNXM` OTA.

This repository is a release device tree. It does not contain execution logs,
temporary debugging instructions, or historical device-tree files.

## Release status

| Component | Status |
| --- | --- |
| Display | Verified on device |
| Touch | Verified on device |
| Vibration | Verified on device through CS40L26 EV_FF |
| Flashlight | Verified on device |
| FBE / metadata decryption | Verified, including User 0 |
| MTP | Verified from a Windows host; `Internal Storage` is visible |
| USB OTG | Integrated; removable-media testing was deferred |
| APEX handling | Disabled for this Recovery build |
| SELinux | Enforcing during validation |

## Release artifact

- Image: `vendor_boot-r46-252ef42.img`
- Size: `67108864` bytes
- SHA-256: `4aa9280585e6e699a30259a2bd9dc99c1b373c9bc5bd68c8dc64b55718a24480`
- Code image revision after author normalization: `7a94ef0`

The published image is a complete `vendor_boot` image containing the official
platform vendor ramdisk followed by the Recovery fragment and the required
AVB footer.

## Official inputs

Device-derived files are reconstructed only from the official Xiaomi OTA:

`https://ultimateota.d.miui.com/OS3.0.303.0.WONCNXM/dash-ota_full-OS3.0.303.0.WONCNXM-user-16.0-b0046d97b1.zip`

The extraction script verifies fixed SHA-256 values before preparing inputs.
The inputs include the official kernel, vendor_boot DTB and platform ramdisk,
Recovery fstab files, first-stage fstab, ueventd/init configuration, vendor_dlkm
SCP/Goodix/Xiaomi Touch modules, module dependency metadata, and the official
build properties required for FBE version alignment.

The preserved historical device tree is not used as an input. Recovery-only
module transformations are generated deterministically from the official
module bytes and are kept separate from normal-system `vendor_dlkm` files.

## Included functionality

- Goodix/SCP Recovery module integration with the documented AP-coordinate
  fallback and merged module dependency metadata.
- Official CS40L26 force-feedback haptics for Recovery gestures and controls.
- Android 16 FBE metadata and Weaver compatibility, KeyMint/Gatekeeper startup,
  and User 0 credential unlock.
- Recovery startup ordering for BootControl, narrow Health sysfs labels, and
  the unsupported APEX path disabled.
- Torch LED paths `white:flash-1` and `white:flash-2`.
- Removable `/usb_otg` storage using `sdd1` with an `sdd` fallback. The route
  is integrated and statically/runtime-prepared; physical media acceptance is
  deferred because no FAT32/exFAT test media was available.

## Build and package

Use a separately synchronized OrangeFox 14.1 checkout with the OrangeFox
build-framework overlay required by `vendor/recovery/OrangeFox_A14.sh`. The
overlay is external to this repository and must be reproduced separately:

- `build/make/core/Makefile`
- `build/make/core/config.mk`
- `build/make/envsetup.sh`
- `vendor/twrp/config/BoardConfigSoong.mk`

The normal build configuration is `twrp_dash-ap2a-eng`:

```bash
source build/envsetup.sh
lunch twrp_dash-ap2a-eng
m installclean
m vendorbootimage
```

Package the official platform fragment and the generated Recovery fragment
with the tree's `package-vendor-boot.sh` script. The script validates the
platform ramdisk, DTB, Recovery modules, fragment order, partition size, and
AVB footer before publishing the final image.

## Source boundary

The device tree does not carry or apply OrangeFox/AOSP source patches. The
release build requires these separately maintained, user-authorized source
exceptions outside this repository:

- `bootable/recovery/minuitwrp/events.cpp` for the EV_FF haptics backend.
- `bootable/recovery/gui/slidervalue.cpp` for independent slider haptic preview.
- `system/vold/Android.bp`, `Decrypt.cpp`, `KeystoreInfo.cpp`, `Weaver1.cpp`,
  and `Weaver1.h` for FBE/Weaver compatibility.

## Installation safety

Before installing a release image:

1. Verify the device codename, active slot, image size, and SHA-256.
2. Set the Recovery display brightness to `0` immediately before the flash.
3. Write only the selected `vendor_boot` partition and perform a full readback.
4. Do not write `lk`, preloader, bootloader, `boot`, `init_boot`, `vbmeta`, or
   any unrelated partition.

Persistent forced ADB settings are not part of this release. Debug sessions
must restore `persist.sys.usb.config` after testing.
