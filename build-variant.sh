#!/bin/bash
set -e
TOP=/home/twrp/fox_14.1
P=$1; R=$2; OUT=$3
DTB=/home/twrp/fox_14.1/device/xiaomi/dash/prebuilt/dtb/dash.dtb
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
python3 $TOP/system/tools/mkbootimg/mkbootimg.py --header_version 4 --pagesize 4096 --base 0x00000000 \
  --kernel_offset 0x80000000 --ramdisk_offset 0xa6f00000 --tags_offset 0x87c80000 \
  --dtb_offset 0x0000000087c80000 --vendor_cmdline "bootopt=64S3,32N2,64N2" \
  --dtb "$DTB" --vendor_ramdisk "$P" --ramdisk_type RECOVERY --ramdisk_name recovery \
  --vendor_ramdisk_fragment "$R" --vendor_boot "$WORK/pre.img"
PRE=$(stat -c %s "$WORK/pre.img")
[ "$PRE" -le 67108864 ] || { echo "SKIP: 超分区 $PRE"; exit 1; }
python3 $TOP/external/avb/avbtool.py add_hash_footer --image "$WORK/pre.img" --partition_size 67108864 \
  --partition_name vendor_boot --hash_algorithm sha256 \
  --salt 01b91678eb9d1a40c6e012ce76745b0561a8be6a5867c0b3a5ccc7051e3dbc48 --algorithm NONE \
  --prop "com.android.build.vendor_boot.fingerprint:alps/hal_mgvi_64_64only_armv82/mgvi_64_64only_armv82:15/AP3A.240905.015.A2/OS3.0.305.0.WPLCNXM:user/release-keys"
install -m 0644 "$WORK/pre.img" "$OUT"
echo "生成 $OUT ($(stat -c %s "$OUT"))"
