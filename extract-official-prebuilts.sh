#!/bin/sh
set -eu
# Regenerate the committed prebuilts from an unpacked official dash OTA.
#
# ⚠️ 本仓库的 prebuilts 是 release 冻结的（r46 实机验证来源）。本脚本只做两件事：
#   1. 校验 OTA 文件与仓库内 shipped prebuilts 哈希一致（来源可信）；
#   2. 重新生成 platform.cpio.gz（lz4 -> gzip -9 -n，确定性转换）。
# recovery.fstab / ueventd.rc 带有本地修改（FBE 标志 / Mitee 规则），只校验
# 官方基线哈希、不覆盖本地版本。
#
# 用法: $0 /absolute/path/to/official-ota/unpacked
# 解包方式参考 README_构建.md（OTA: OS3.0.305.0.WPLCNXM）。

verify_sha256() {
    expected=$1
    input=$2
    actual=$(sha256sum "$input" | awk '{print $1}')
    if [ "$actual" != "$expected" ]; then
        echo "hash mismatch: $input" >&2
        exit 1
    fi
}

if [ "$#" -ne 1 ]; then
    echo "usage: $0 /absolute/path/to/official-ota/unpacked" >&2
    exit 2
fi

source_root=$(readlink -f -- "$1") || {
    echo "failed to canonicalize official extraction root: $1" >&2
    exit 2
}
case "$source_root" in
    */official-ota/unpacked) ;;
    *)
        echo "refusing non-official extraction root: $source_root" >&2
        exit 2
        ;;
esac

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
official_ota_root=$(dirname -- "$source_root")
vendor_dlkm_modules="$official_ota_root/extracted/vendor_dlkm/lib/modules"
platform_modules="$source_root/vendor_ramdisk/root/lib/modules"
system_build_props="$official_ota_root/extracted/system/system/build.prop"
vendor_build_props="$official_ota_root/extracted/vendor/build.prop"

# --- OTA 校验（值 = shipped prebuilts 哈希，来源 = OS3.0.305.0.WPLCNXM） ---
verify_sha256 5d80fdfed8844e4860327ac7e14fea45d5cdc32e417b204b1d03160619663c98 "$source_root/boot/kernel"
verify_sha256 2636d5a861e909f5bf32fb3b5c80b25824fbb6591e31a21b6b1326b6dc52d7e3 "$source_root/vendor_boot/dtb"
verify_sha256 912a4a651d2197883e46cf9a7afc3035261c1e7a8263709f91d0146ddfd68bfb "$source_root/recovery_ramdisk/root/first_stage_ramdisk/fstab.emmc"
verify_sha256 ba8eddd72cbaad183012da73c1ebd1d2abbacb0ff1ed4eaad5dd0b4ec395371e "$source_root/recovery_ramdisk/root/init.recovery.mt6991.rc"
# 官方基线校验；本地版本带 FBE 标志/Mitee 规则，不覆盖
verify_sha256 13f5bd1abf777a293a7bc74bb14e41757bced12c4fb2d130cf7b0829d35ab6a9 "$source_root/recovery_ramdisk/root/system/etc/recovery.fstab"
verify_sha256 e75201e0a0d2be1a5a13371a010b749ac6d66fe5dc2742fa4a0d13876d5e4312 "$source_root/vendor_ramdisk/root/system/etc/ueventd.rc"
verify_sha256 7dd0abf1bdcc804ac2ae077debc52c0646c163b80df505ca99e7713cce297db6 "$vendor_dlkm_modules/scp.ko"
verify_sha256 b773b1cb3b8004e0f31773a941c728d70ec6f9dddde969fa40c7fff54f51aaca "$vendor_dlkm_modules/nt38771_touch_dash.ko"
verify_sha256 e4aabc877e0a3af7c0015d63940e50faa41ac391468bf38b0e42670c38c020dc "$vendor_dlkm_modules/xiaomi_touch_dash.ko"
verify_sha256 3fc3c92f2885103cd5d7e457358b72abdf33ee6d6f573c2d8f41079d5b9f677a "$platform_modules/modules.dep"
verify_sha256 0a258246106c8d978645963b55cf13d67ca69aea1d1c9f70c0ffe248dd879f9e "$system_build_props"
verify_sha256 987a90fcac6b9e656924298fff2b8cf67b3e3ab475f00d5f50ffe10d20a3586c "$vendor_build_props"

# --- 安装（跳过带本地修改的文件） ---
install -D -m 0644 "$source_root/boot/kernel" "$script_dir/prebuilt/kernel"
install -D -m 0644 "$source_root/vendor_boot/dtb" "$script_dir/prebuilt/dtb/dash.dtb"
install -D -m 0644 "$source_root/recovery_ramdisk/root/first_stage_ramdisk/fstab.emmc" \
    "$script_dir/recovery/root/first_stage_ramdisk/fstab.emmc"
install -D -m 0644 "$source_root/recovery_ramdisk/root/init.recovery.mt6991.rc" \
    "$script_dir/recovery/root/init.recovery.mt6991.rc"
echo "SKIP: recovery.fstab (local FBE flags) / ueventd.rc (local Mitee rules) kept as-is"
recovery_modules="$script_dir/prebuilt/recovery_modules"
install -D -m 0644 "$vendor_dlkm_modules/scp.ko" "$recovery_modules/scp.ko"
install -D -m 0644 "$vendor_dlkm_modules/nt38771_touch_dash.ko" "$recovery_modules/nt38771_touch_dash.ko"
install -D -m 0644 "$vendor_dlkm_modules/xiaomi_touch_dash.ko" "$recovery_modules/xiaomi_touch_dash.ko"
install -D -m 0644 "$platform_modules/modules.dep" "$recovery_modules/modules.dep"
recovery_properties="$script_dir/prebuilt/recovery_properties"
install -D -m 0644 "$system_build_props" "$recovery_properties/system.build.prop"
install -D -m 0644 "$vendor_build_props" "$recovery_properties/vendor.build.prop"

# --- platform ramdisk 确定性转换（lz4 -> cpio -> gzip -9 -n） ---
command -v lz4 >/dev/null 2>&1 || {
    echo "lz4 is required to convert the official platform ramdisk" >&2
    exit 1
}
platform_dir="$script_dir/prebuilt/vendor_ramdisk"
mkdir -p "$platform_dir"
platform_raw=$(mktemp "$platform_dir/.platform.cpio.XXXXXX")
platform_gzip="$platform_dir/platform.cpio.gz"
platform_gzip_tmp=$(mktemp "$platform_dir/.platform.cpio.gz.XXXXXX")
cleanup() {
    rm -f "$platform_raw" "$platform_gzip_tmp"
}
trap cleanup EXIT HUP INT TERM
lz4 -dc "$source_root/vendor_boot/vendor_ramdisk00" > "$platform_raw"
verify_sha256 9ece806a35c1f75a72aa87a2b2d9bdec480805672610c8732f7bdb6646072e03 "$platform_raw"
gzip -9 -n -c "$platform_raw" > "$platform_gzip_tmp"
verify_sha256 ef0aee35573a8b94e4fc08c34343f23bb09d3ac1a7637fcf422f6fb1e529af44 "$platform_gzip_tmp"
mv "$platform_gzip_tmp" "$platform_gzip"

sha256sum \
    "$script_dir/prebuilt/kernel" \
    "$script_dir/prebuilt/dtb/dash.dtb" \
    "$platform_gzip" \
    "$script_dir/recovery.fstab" \
    "$script_dir/recovery/root/first_stage_ramdisk/fstab.emmc" \
    "$script_dir/recovery/root/system/etc/ueventd.rc" \
    "$script_dir/recovery/root/init.recovery.mt6991.rc" \
    "$recovery_modules/scp.ko" \
    "$recovery_modules/nt38771_touch_dash.ko" \
    "$recovery_modules/xiaomi_touch_dash.ko" \
    "$recovery_modules/modules.dep" \
    "$recovery_properties/system.build.prop" \
    "$recovery_properties/vendor.build.prop"
