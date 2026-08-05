#!/bin/bash
set -e
# dash OrangeFox 14.1 一键构建脚本
# 用法:
#   1. 将本设备树解压到 OrangeFox 14.1 (fox_14.1) 树的 device/xiaomi/dash/
#   2. 在本脚本目录运行: bash build.sh
# 前置要求见 README_构建.md

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 设备树在 fox_14.1/device/xiaomi/dash，脚本在其内
# TOP = fox_14.1 根 = 设备树上两级
TOP=$(cd "$SCRIPT_DIR/../.." && pwd)
echo "=== OrangeFox 根: $TOP ==="
cd "$TOP"

echo "=== 1. 环境设置 ==="
source build/envsetup.sh
lunch twrp_dash-ap2a-eng

echo "=== 2. 清理并构建 vendor_boot ==="
m installclean
m -j$(nproc) vendorbootimage

echo "=== 3. 提取构建 recovery fragment ==="
rm -rf /tmp/dash_vb && mkdir /tmp/dash_vb
python3 system/tools/mkbootimg/unpack_bootimg.py --boot_img out/target/product/dash/vendor_boot.img --out /tmp/dash_vb

echo "=== 4. 精简 recovery（移除非必需，控制在分区内）==="
rm -rf /tmp/dash_rec && cp -a out/target/product/dash/recovery/root /tmp/dash_rec
find /tmp/dash_rec/twres/languages -type f ! -name "en.xml" -delete 2>/dev/null || true
for f in bash nano magiskboot gnutar zip gnused; do rm -f /tmp/dash_rec/sbin/$f 2>/dev/null || true; done
for f in update_engine_sideload fastbootd; do rm -f /tmp/dash_rec/system/bin/$f 2>/dev/null || true; done
for lib in libchrome.so libxml2.so libadbd_services.so libadbconnection_server.so libevent.so libpcre2.so libssl.so; do rm -f /tmp/dash_rec/system/lib64/$lib 2>/dev/null || true; done
(cd /tmp/dash_rec && find . -type f -o -type l | cpio -o -H newc 2>/dev/null > /tmp/dash_rec.cpio)
gzip -9 -n -c /tmp/dash_rec.cpio > /tmp/dash_rec.gz

echo "=== 5. 打包 vendor_boot（官方平台 + 编译 recovery，双 gzip）==="
python3 device/xiaomi/dash/build-variant.sh \
  device/xiaomi/dash/prebuilt/vendor_ramdisk/platform.cpio.gz \
  /tmp/dash_rec.gz \
  dash-OrangeFox-14.1-$(date +%Y%m%d-%H%M).img

echo "=== 完成！镜像在 fox_14.1 根目录 ==="
