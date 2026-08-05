#!/bin/sh
set -eu

PARTITION_SIZE=67108864
MAX_PREAVB_SIZE=67039232
PLATFORM_CPIO_SHA256=9ece806a35c1f75a72aa87a2b2d9bdec480805672610c8732f7bdb6646072e03
PLATFORM_LIBCPP_SHA256=69bc8ad4bd7a8613dbc30c4925c74194deb3e7df11c9a2bce7acea29c096787a
PLATFORM_GZIP_SHA256=ef0aee35573a8b94e4fc08c34343f23bb09d3ac1a7637fcf422f6fb1e529af44
DTB_SHA256=2636d5a861e909f5bf32fb3b5c80b25824fbb6591e31a21b6b1326b6dc52d7e3
AVB_SALT=01b91678eb9d1a40c6e012ce76745b0561a8be6a5867c0b3a5ccc7051e3dbc48
AVB_FINGERPRINT=alps/hal_mgvi_64_64only_armv82/mgvi_64_64only_armv82:15/AP3A.240905.015.A2/OS3.0.305.0.WPLCNXM:user/release-keys
SCP_OUTPUT_SHA256=7dd0abf1bdcc804ac2ae077debc52c0646c163b80df505ca99e7713cce297db6
NT38771_OUTPUT_SHA256=b773b1cb3b8004e0f31773a941c728d70ec6f9dddde969fa40c7fff54f51aaca
XIAOMI_TOUCH_SHA256=e4aabc877e0a3af7c0015d63940e50faa41ac391468bf38b0e42670c38c020dc
MERGED_MODULES_DEP_SHA256=dd972abacb2c2cd5475903b8ad681c9985d0a3be67fd2e6f65c812305be8034c

die() {
    echo "$*" >&2
    exit 1
}

file_sha256() {
    sha256sum "$1" | awk '{print $1}'
}

require_sha256() {
    expected=$1
    input=$2
    actual=$(file_sha256 "$input")
    [ "$actual" = "$expected" ] || die "hash mismatch: $input"
}

extract_vendor_ramdisk() {
    fragment=$1
    destination=$2
    mkdir -p "$destination"
    cpio_input="$destination/.dash-vendor-ramdisk.cpio"
    gzip -dc "$fragment" > "$cpio_input"
    (
        cd "$destination"
        cpio -idu --quiet < "$cpio_input"
    )
    rm -f -- "$cpio_input"
}

validate_recovery_payload() {
    recovery_root=$1
    module_root="$recovery_root/lib/modules"
    recovery_binary="$recovery_root/system/bin/recovery"

    [ -d "$module_root" ] || die "final Recovery root has no module directory"
    require_sha256 "$PLATFORM_LIBCPP_SHA256" "$recovery_root/system/lib64/libc++.so"
    require_sha256 "$SCP_OUTPUT_SHA256" "$module_root/scp.ko"
    require_sha256 "$NT38771_OUTPUT_SHA256" "$module_root/nt38771_touch_dash.ko"
    require_sha256 "$XIAOMI_TOUCH_SHA256" "$module_root/xiaomi_touch_dash.ko"
    require_sha256 "$MERGED_MODULES_DEP_SHA256" "$module_root/modules.dep"
    focaltech_entry=$(find "$module_root" -iname "*focaltech*" -print -quit)
    if [ -n "$focaltech_entry" ]; then
        die "final Recovery payload contains a FocalTech module"
    fi
    if grep -F -- "focaltech_touch_dash.ko" "$module_root/modules.dep" >/dev/null; then
        die "final Recovery module metadata references FocalTech"
    fi
    if grep -F -- "/vendor_dlkm/" "$module_root/modules.dep" >/dev/null; then
        die "final Recovery module metadata references vendor_dlkm"
    fi

    python3 - "$module_root" <<'PY'
import stat
import sys
from pathlib import Path

module_root = Path(sys.argv[1])
for line_number, line in enumerate((module_root / "modules.dep").read_text(encoding="ascii").splitlines(), 1):
    owner, separator, dependency_text = line.partition(":")
    if not separator or not owner:
        raise SystemExit(f"invalid modules.dep entry at line {line_number}")
    for entry in (owner, *dependency_text.split()):
        if entry.startswith("/lib/modules/"):
            relative = entry.removeprefix("/lib/modules/")
        elif entry.startswith("/"):
            raise SystemExit(f"unexpected absolute module path at line {line_number}: {entry}")
        else:
            relative = entry
        path = Path(relative)
        if path.is_absolute() or ".." in path.parts:
            raise SystemExit(f"unsafe module path at line {line_number}: {entry}")
        candidate = module_root / path
        try:
            mode = candidate.lstat().st_mode
        except FileNotFoundError:
            raise SystemExit(f"missing module dependency at line {line_number}: {entry}")
        if not stat.S_ISREG(mode):
            raise SystemExit(f"module dependency is not a regular file at line {line_number}: {entry}")
PY

    [ -f "$recovery_binary" ] || die "final Recovery executable is missing"
    for requested_module in xiaomi_touch_dash.ko nt38771_touch_dash.ko
    do
        grep -aF -- "$requested_module" "$recovery_binary" >/dev/null ||
            die "final Recovery executable does not request $requested_module"
    done
    if grep -aF -- "focaltech_touch_dash.ko" "$recovery_binary" >/dev/null; then
        die "final Recovery executable still requests FocalTech"
    fi
}

[ "$#" -eq 2 ] || die "usage: $0 /absolute/path/to/source /absolute/path/to/vendor_boot.img"
source_root=$1
output_image=$2
case "$source_root" in
    /*) ;;
    *) die "source path must be absolute" ;;
esac
case "$output_image" in
    /*) ;;
    *) die "output path must be absolute" ;;
esac

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
platform_gzip="$script_dir/prebuilt/vendor_ramdisk/platform.cpio.gz"
dtb="$script_dir/prebuilt/dtb/dash.dtb"
built_vendor_boot="$source_root/out/target/product/dash/vendor_boot.img"
mkbootimg="$source_root/system/tools/mkbootimg/mkbootimg.py"
unpack_bootimg="$source_root/system/tools/mkbootimg/unpack_bootimg.py"
avbtool="$source_root/external/avb/avbtool.py"
for input in "$platform_gzip" "$dtb" "$built_vendor_boot" "$mkbootimg" "$unpack_bootimg" "$avbtool"
do
    [ -f "$input" ] || die "missing input: $input"
done

gzip -t "$platform_gzip"
require_sha256 "$PLATFORM_GZIP_SHA256" "$platform_gzip"
output_dir=$(dirname -- "$output_image")
mkdir -p "$output_dir"
work=$(mktemp -d "$output_dir/.dash-vendor-boot.XXXXXX")
cleanup() {
    if [ -d "$work" ]; then
        rm -rf "$work"
    fi
}
trap cleanup EXIT HUP INT TERM

gzip -dc "$platform_gzip" > "$work/platform.cpio"
require_sha256 "$PLATFORM_CPIO_SHA256" "$work/platform.cpio"
require_sha256 "$DTB_SHA256" "$dtb"
max_preavb_size=$(python3 "$avbtool" add_hash_footer \
    --partition_size "$PARTITION_SIZE" \
    --partition_name vendor_boot \
    --hash_algorithm sha256 \
    --salt "$AVB_SALT" \
    --algorithm NONE \
    --calc_max_image_size)
[ "$max_preavb_size" = "$MAX_PREAVB_SIZE" ] ||
    die "unexpected AVB maximum image size: $max_preavb_size"


python3 "$unpack_bootimg" --boot_img "$built_vendor_boot" --out "$work/built" > "$work/built-info.txt"
recovery_fragment="$work/built/vendor_ramdisk01"
awk '
    /^vendor boot image header version: 4$/ { header_v4 = 1 }
    /^    vendor_ramdisk01: \{$/ { recovery = 1; next }
    recovery && /^        type: 0x2$/ { recovery_type = 1 }
    recovery && /^        name: recovery$/ { recovery_name = 1 }
    recovery && /^    }$/ { recovery = 0 }
    END { exit !(header_v4 && recovery_type && recovery_name) }
' "$work/built-info.txt" ||
    die "built vendor_boot does not contain the expected v4 recovery fragment"
[ -f "$recovery_fragment" ] || die "built recovery fragment is missing"
gzip -t "$recovery_fragment"

gzip -dc "$recovery_fragment" > "$work/recovery.cpio"
optimized_recovery_fragment="$work/recovery-gzip9.cpio.gz"
gzip -9 -n -c "$work/recovery.cpio" > "$optimized_recovery_fragment"
gzip -t "$optimized_recovery_fragment"
gzip -dc "$optimized_recovery_fragment" > "$work/recovery-gzip9.cpio"
cmp "$work/recovery.cpio" "$work/recovery-gzip9.cpio"

python3 "$mkbootimg" \
    --header_version 4 \
    --pagesize 4096 \
    --base 0x00000000 \
    --kernel_offset 0x80000000 \
    --ramdisk_offset 0xa6f00000 \
    --tags_offset 0x87c80000 \
    --dtb_offset 0x0000000087c80000 \
    --vendor_cmdline "bootopt=64S3,32N2,64N2" \
    --dtb "$dtb" \
    --vendor_ramdisk "$platform_gzip" \
    --ramdisk_type RECOVERY \
    --ramdisk_name recovery \
    --vendor_ramdisk_fragment "$optimized_recovery_fragment" \
    --vendor_boot "$work/vendor_boot.preavb.img"

preavb_size=$(stat -c '%s' "$work/vendor_boot.preavb.img")
[ "$preavb_size" -le "$PARTITION_SIZE" ] || die "vendor_boot exceeds the partition before AVB: $preavb_size"
[ "$preavb_size" -le "$max_preavb_size" ] ||
    die "vendor_boot exceeds the AVB maximum before footer creation: $preavb_size > $max_preavb_size"
cp "$work/vendor_boot.preavb.img" "$work/vendor_boot.img"
python3 "$avbtool" add_hash_footer \
    --image "$work/vendor_boot.img" \
    --partition_size "$PARTITION_SIZE" \
    --partition_name vendor_boot \
    --hash_algorithm sha256 \
    --salt "$AVB_SALT" \
    --algorithm NONE \
    --prop "com.android.build.vendor_boot.fingerprint:$AVB_FINGERPRINT"
[ "$(stat -c '%s' "$work/vendor_boot.img")" -eq "$PARTITION_SIZE" ] || die "unexpected final image size"

python3 "$unpack_bootimg" --boot_img "$work/vendor_boot.img" --out "$work/output" > "$work/output-info.txt"
awk '
    /^vendor boot image header version: 4$/ { header_v4 = 1 }
    /^page size: 0x00001000$/ { page_size = 1 }
    /^kernel load address: 0x80000000$/ { kernel_address = 1 }
    /^ramdisk load address: 0xa6f00000$/ { ramdisk_address = 1 }
    /^vendor command line args: bootopt=64S3,32N2,64N2$/ { cmdline = 1 }
    /^kernel tags load address: 0x87c80000$/ { tags_address = 1 }
    /^dtb address: 0x0000000087c80000$/ { dtb_address = 1 }
    /^vendor bootconfig size: 0$/ { empty_bootconfig = 1 }
    /^    vendor_ramdisk00: \{$/ { fragment = 1; next }
    /^    vendor_ramdisk01: \{$/ { fragment = 2; next }
    fragment == 1 && /^        type: 0x1$/ { platform_type = 1 }
    fragment == 1 && /^        name: $/ { platform_name = 1 }
    fragment == 2 && /^        type: 0x2$/ { recovery_type = 1 }
    fragment == 2 && /^        name: recovery$/ { recovery_name = 1 }
    fragment && /^    }$/ {
        if (fragment == 1) {
            platform = platform_type && platform_name
        } else if (fragment == 2) {
            recovery = recovery_type && recovery_name
        }
        fragment = 0
    }
    END {
        exit !(header_v4 && page_size && kernel_address && ramdisk_address &&
               cmdline && tags_address && dtb_address && empty_bootconfig &&
               platform && recovery)
    }
' "$work/output-info.txt" ||
    die "final vendor_boot layout does not match the official v4 contract"
cmp "$platform_gzip" "$work/output/vendor_ramdisk00"
cmp "$optimized_recovery_fragment" "$work/output/vendor_ramdisk01"
cmp "$dtb" "$work/output/dtb"
merged_root="$work/merged-root"
extract_vendor_ramdisk "$work/output/vendor_ramdisk00" "$merged_root"
extract_vendor_ramdisk "$work/output/vendor_ramdisk01" "$merged_root"
validate_recovery_payload "$merged_root"
python3 "$avbtool" info_image --image "$work/vendor_boot.img" > "$work/avb-info.txt"
grep -F "Algorithm:                NONE" "$work/avb-info.txt" >/dev/null
grep -F "Hash Algorithm:        sha256" "$work/avb-info.txt" >/dev/null
grep -F "Partition Name:        vendor_boot" "$work/avb-info.txt" >/dev/null
grep -F "Salt:                  $AVB_SALT" "$work/avb-info.txt" >/dev/null
grep -F "Prop: com.android.build.vendor_boot.fingerprint -> '$AVB_FINGERPRINT'" "$work/avb-info.txt" >/dev/null

install -m 0644 "$work/vendor_boot.img" "$output_image"
sha256sum "$output_image" > "$output_image.sha256"
printf 'pre-AVB size: %s (AVB maximum: %s)\n' "$preavb_size" "$max_preavb_size"
printf 'created %s\n' "$output_image"
