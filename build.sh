#!/bin/bash
set -e
# dash OrangeFox 14.1 一键构建脚本（release 路径）
# 用法:
#   1. 将本设备树放到 OrangeFox 14.1 (fox_14.1) 树的 device/xiaomi/dash/
#   2. 在本脚本目录运行: bash build.sh
# 前置要求见 README_构建.md
#
# release 路径 = README.md "Build and package" 的流程：
#   envsetup -> lunch twrp_dash-ap2a-eng -> installclean -> vendorbootimage
#   -> package-vendor-boot.sh（官方平台片段 + 构建 recovery 片段 + AVB footer，
#      全量哈希/布局/合并树校验）
# 不要使用旧版 build-variant.sh 路径（机器相关硬编码路径，删除集与 release 不一致）。

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 设备树在 fox_14.1/device/xiaomi/dash，脚本在其内
# TOP = fox_14.1 根 = 设备树上三级
TOP=$(cd "$SCRIPT_DIR/../../.." && pwd)
echo "=== OrangeFox 根: $TOP ==="
cd "$TOP"

echo "=== 1. 环境设置 ==="
source build/envsetup.sh
lunch twrp_dash-ap2a-eng

echo "=== 2. 清理并构建 vendor_boot ==="
m installclean
m -j$(nproc) vendorbootimage

echo "=== 3. 打包 release 镜像 ==="
OUT="vendor_boot-dash-$(date +%Y%m%d-%H%M).img"
bash device/xiaomi/dash/package-vendor-boot.sh "$TOP" "$TOP/$OUT"

echo "=== 完成！镜像: $TOP/$OUT ==="
