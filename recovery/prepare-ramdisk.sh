#!/bin/sh
set -eu

die() {
    echo "dash recovery ramdisk preparation: $*" >&2
    exit 2
}

verify_sha256() {
    expected=$1
    input=$2
    actual=$(sha256sum "$input" | awk '{print $1}')
    [ "$actual" = "$expected" ] || die "hash mismatch: $input"
}

if [ "$#" -ne 5 ]; then
    die "usage: $0 /absolute/path/to/recovery-root /absolute/path/to/soong-bridge /absolute/path/to/llvm-readobj /absolute/path/to/recovery-module-inputs /absolute/path/to/recovery-property-inputs"
fi

input_root=$1
input_bridge=$2
input_llvm_readobj=$3
input_module_dir=$4
input_property_dir=$5
case "$input_root" in
    /*) ;;
    *) die "recovery root must be absolute" ;;
esac
case "$input_bridge" in
    /*) ;;
    *) die "Soong bridge must be absolute" ;;
esac
case "$input_llvm_readobj" in
    /*) ;;
    *) die "llvm-readobj must be absolute" ;;
esac
case "$input_module_dir" in
    /*) ;;
    *) die "recovery module input directory must be absolute" ;;
esac
case "$input_property_dir" in
    /*) ;;
    *) die "recovery property input directory must be absolute" ;;
esac

root=$(readlink -f -- "$input_root") || die "failed to canonicalize recovery root"
bridge=$(readlink -f -- "$input_bridge") || die "failed to canonicalize Soong bridge"
llvm_readobj=$(readlink -f -- "$input_llvm_readobj") || die "failed to canonicalize llvm-readobj"
module_dir=$(readlink -f -- "$input_module_dir") || die "failed to canonicalize recovery module input directory"
property_dir=$(readlink -f -- "$input_property_dir") || die "failed to canonicalize recovery property input directory"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
device_root=$(dirname -- "$script_dir")
soong_dir=$(dirname "$bridge")
out_dir=$(dirname "$soong_dir")

case "$soong_dir" in
    */soong) ;;
    *) die "unexpected Soong directory: $soong_dir" ;;
esac
case "$bridge" in
    "$soong_dir"/Android-*.mk) ;;
    *) die "unexpected Soong bridge: $bridge" ;;
esac
case "$root" in
    "$out_dir"/target/product/*/recovery/root) ;;
    *) die "unexpected recovery root: $root" ;;
esac
case "$module_dir" in
    "$device_root"/prebuilt/recovery_modules) ;;
    *) die "unexpected recovery module input directory: $module_dir" ;;
esac
case "$property_dir" in
    "$device_root"/prebuilt/recovery_properties) ;;
    *) die "unexpected recovery property input directory: $property_dir" ;;
esac

test -d "$root" || die "missing recovery root"
test -f "$bridge" || die "missing Soong bridge"
test -x "$llvm_readobj" || die "missing llvm-readobj"
test -f "$script_dir/patch-ap-touch-modules.py" || die "missing AP touch module generator"
test -f "$script_dir/root/init.recovery.usb.rc" || die "missing Recovery USB configfs rc"
test -f "$property_dir/system.build.prop" || die "missing official system build properties"
test -f "$property_dir/vendor.build.prop" || die "missing official vendor build properties"
for manifest in ramdisk-files.txt ramdisk-files.sha256sum
do
    test -f "$root/$manifest" || die "missing recovery manifest: $root/$manifest"
done

extract_prebuilt() {
    module=$1
    module_class=$2
    python3 - "$bridge" "$module" "$module_class" <<'PY'
import sys

bridge, target_module, target_class = sys.argv[1:]
matches = []
current = {}


def record_current():
    if (current.get("module") == target_module and
            current.get("module_class") == target_class):
        prebuilt = current.get("prebuilt")
        link_type = current.get("link_type")
        if prebuilt:
            matches.append((prebuilt, link_type))


with open(bridge, encoding="utf-8") as stream:
    for raw_line in stream:
        line = raw_line.rstrip("\n")
        if line.startswith("include $(CLEAR_VARS)"):
            record_current()
            current = {}
        elif line.startswith("LOCAL_MODULE := "):
            current["module"] = line[len("LOCAL_MODULE := "):]
        elif line.startswith("LOCAL_MODULE_CLASS := "):
            current["module_class"] = line[len("LOCAL_MODULE_CLASS := "):]
        elif line.startswith("LOCAL_PREBUILT_MODULE_FILE := "):
            current["prebuilt"] = line[len("LOCAL_PREBUILT_MODULE_FILE := "):]
        elif line.startswith("LOCAL_SOONG_LINK_TYPE := "):
            current["link_type"] = line[len("LOCAL_SOONG_LINK_TYPE := "):]
record_current()

if len(matches) != 1:
    print(
        "expected exactly one {} {} Recovery artifact, found {}".format(
            target_module, target_class, len(matches)
        ),
        file=sys.stderr,
    )
    raise SystemExit(1)

path, link_type = matches[0]
if link_type != "native:recovery":
    print(
        "{} {} is not native:recovery".format(target_module, target_class),
        file=sys.stderr,
    )
    raise SystemExit(1)
print(path)
PY
}

require_recovery_artifact() {
    path=$1
    name=$2
    [ -n "$path" ] && [ -f "$path" ] || die "missing $name Recovery artifact"
    case "$path" in
        "$out_dir"/soong/.intermediates/*/android_recovery_*/*/*) ;;
        *) die "$name is not a Recovery Soong artifact: $path" ;;
    esac
    case "$path" in
        */unstripped/*) die "$name selected an unstripped artifact" ;;
    esac
}

verify_recovery_symbol() {
    elf=$1
    name=$2

    symbols=$("$llvm_readobj" --dyn-symbols "$elf") ||
        die "failed to read dynamic symbols from $name"
    case "$symbols" in
        *VintfObjectRecovery*) ;;
        *) die "$name lacks the Recovery VINTF dynamic symbol" ;;
    esac
}

# Use the ordinary relinked servicemanager/libvintf when soong recovery variants
# are not available. Recovery variants are preferred when present.
if servicemanager=$(extract_prebuilt servicemanager.recovery EXECUTABLES 2>/dev/null) && \
   libvintf=$(extract_prebuilt libvintf.recovery SHARED_LIBRARIES 2>/dev/null); then
    require_recovery_artifact "$servicemanager" servicemanager
    require_recovery_artifact "$libvintf" libvintf
    verify_recovery_symbol "$servicemanager" servicemanager
    verify_recovery_symbol "$libvintf" libvintf

    [ -f "$root/system/bin/servicemanager" ] || die "ordinary servicemanager relink output is missing"
    [ -f "$root/system/lib64/libvintf.so" ] || die "ordinary libvintf relink output is missing"

    install -m 0755 "$servicemanager" "$root/system/bin/.servicemanager.dash"
    install -m 0644 "$libvintf" "$root/system/lib64/.libvintf.so.dash"
    mv -f "$root/system/bin/.servicemanager.dash" "$root/system/bin/servicemanager"
    mv -f "$root/system/lib64/.libvintf.so.dash" "$root/system/lib64/libvintf.so"
    cmp -s "$servicemanager" "$root/system/bin/servicemanager" || die "servicemanager copy verification failed"
    cmp -s "$libvintf" "$root/system/lib64/libvintf.so" || die "libvintf copy verification failed"
else
    [ -f "$root/system/bin/servicemanager" ] || die "ordinary servicemanager relink output is missing"
    [ -f "$root/system/lib64/libvintf.so" ] || die "ordinary libvintf relink output is missing"
fi

# The Recovery CPIO overlays the official platform fragment. Its older libc++
# lacks Android 16's verbose-abort ABI, while the platform libc++ resolves all
# Recovery C++ imports and must therefore remain the final copy.
recovery_libcpp="$root/system/lib64/libc++.so"
rm -f -- "$recovery_libcpp"
[ ! -e "$recovery_libcpp" ] && [ ! -L "$recovery_libcpp" ] ||
    die "failed to remove incompatible Recovery libc++"

verify_sha256 0a258246106c8d978645963b55cf13d67ca69aea1d1c9f70c0ffe248dd879f9e \
    "$property_dir/system.build.prop"
verify_sha256 987a90fcac6b9e656924298fff2b8cf67b3e3ab475f00d5f50ffe10d20a3586c \
    "$property_dir/vendor.build.prop"
python3 - "$property_dir/system.build.prop" "$property_dir/vendor.build.prop" \
    "$root/prop.default" "$root/default.prop" <<'PY'
import os
import stat
import sys
import tempfile

system_props, vendor_props, target_path, default_link = sys.argv[1:]
keys = (
    "ro.build.version.release",
    "ro.build.version.security_patch",
    "ro.vendor.build.security_patch",
)


def values_from(path, wanted):
    values = {key: [] for key in wanted}
    with open(path, "r", encoding="utf-8", newline="") as stream:
        for raw in stream:
            line = raw.rstrip("\r\n")
            if "=" not in line or line.startswith("#"):
                continue
            key, value = line.split("=", 1)
            if key in values:
                values[key].append(value)
    result = {}
    for key, candidates in values.items():
        if not candidates or len(set(candidates)) != 1:
            raise SystemExit(
                "official property input must provide one unambiguous value for {}".format(key)
            )
        result[key] = candidates[0]
    return result


expected = {}
expected.update(values_from(system_props, keys[:2]))
expected.update(values_from(vendor_props, keys[2:]))

if not os.path.islink(default_link) or os.readlink(default_link) != "prop.default":
    raise SystemExit("default.prop must remain a prop.default symlink")

with open(target_path, "r", encoding="utf-8", newline="") as stream:
    original = stream.readlines()

seen = {key: 0 for key in keys}
rewritten = []
for raw in original:
    line = raw.rstrip("\r\n")
    ending = raw[len(line):]
    if "=" in line and not line.startswith("#"):
        key, _ = line.split("=", 1)
        if key in expected:
            seen[key] += 1
            rewritten.append("{}={}{}".format(key, expected[key], ending))
            continue
    rewritten.append(raw)

if any(count != 1 for count in seen.values()):
    raise SystemExit("Recovery prop.default must contain each target property exactly once")

mode = stat.S_IMODE(os.stat(target_path).st_mode)
directory = os.path.dirname(target_path)
fd, temporary = tempfile.mkstemp(prefix=".prop.default.dash.", dir=directory)
try:
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as stream:
        stream.writelines(rewritten)
    os.chmod(temporary, mode)
    os.replace(temporary, target_path)
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)

actual = values_from(target_path, keys)
if actual != expected:
    raise SystemExit("Recovery prop.default post-write verification failed")
if not os.path.islink(default_link) or os.readlink(default_link) != "prop.default":
    raise SystemExit("default.prop symlink changed during property update")
PY

install -m 0644 "$script_dir/root/init.recovery.usb.rc" "$root/init.recovery.usb.rc"

mkdir -p "$root/lib/modules"
install -m 0644 "$module_dir/scp.ko" "$root/lib/modules/scp.ko"
install -m 0644 "$module_dir/nt38771_touch_dash.ko" "$root/lib/modules/nt38771_touch_dash.ko"
install -m 0644 "$module_dir/xiaomi_touch_dash.ko" "$root/lib/modules/xiaomi_touch_dash.ko"
install -m 0644 "$module_dir/modules.dep" "$root/lib/modules/modules.dep"
for module in scp.ko nt38771_touch_dash.ko xiaomi_touch_dash.ko modules.dep
do
    test -f "$root/lib/modules/$module" || die "missing staged module input: $module"
done

find "$root/lib/modules" -type f -iname "*focaltech*" -delete
find "$root/lib/modules" -type l -iname "*focaltech*" -delete
stale_focaltech=$(find "$root/lib/modules" -iname "*focaltech*" -print -quit)
[ -z "$stale_focaltech" ] || die "stale FocalTech entry remains in Recovery root"
if grep -F -- "focaltech_touch_dash.ko" "$root/lib/modules/modules.dep" >/dev/null; then
    die "Recovery module metadata still references FocalTech"
fi

# The normal Recovery RC retains the recovery SELinux domain. The variant RC
# would define the same service name, and OrangeFox appends Bash/Nano wrappers
# after its feature filters. The marker is only an incremental-build input.
rm -f "$root/system/etc/init/servicemanager.recovery.rc" \
    "$root/sbin/bash" \
    "$root/sbin/nano" \
    "$root/dash_recovery_prepare_marker-timestamp"
cd "$root"
find . | sed "s/.\\///" > ramdisk-files.txt
find -type f | sed "s/.\\/ramdisk-files.sha256sum//" | sed "/prop.default/d" |
    xargs sha256sum > ramdisk-files.sha256sum
