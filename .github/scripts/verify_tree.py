#!/usr/bin/env python3
"""dash-OrangeFox14 tree sanity checks (CI + local).

Cross-checks every fixed SHA-256 constant inside the tree's scripts against
the committed prebuilt files, and verifies internal consistency of
package-vendor-boot.sh (mkbootimg cmdline vs final awk contract).

Usage: python3 verify_tree.py <repo-root>
"""

import gzip
import hashlib
import io
import re
import sys
from pathlib import Path


def die(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _cpio_extract(data: bytes) -> Path:
    """Extract a cpio archive (newc) into a temp dir and return the root."""
    import shutil
    import subprocess
    import tempfile

    dest = Path(tempfile.mkdtemp(prefix="verify-cpio-"))
    proc = subprocess.run(
        ["cpio", "-idmu", "--quiet"], input=data, cwd=dest, capture_output=True
    )
    if proc.returncode != 0:
        shutil.rmtree(dest, ignore_errors=True)
        die("cpio extraction failed")
    return dest


def load_constants(script: Path, names: tuple[str, ...]) -> dict[str, str]:
    """Parse `NAME=64hex` assignments from a shell script."""
    out: dict[str, str] = {}
    text = script.read_text(encoding="utf-8", errors="replace")
    for name in names:
        m = re.search(rf"^{name}=([0-9a-f]{{64}})", text, re.M)
        if not m:
            die(f"{script.name}: missing constant {name}")
        out[name] = m.group(1)
    return out


def main() -> None:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    pkg = root / "package-vendor-boot.sh"
    extract = root / "extract-official-prebuilts.sh"
    prepare = root / "recovery/prepare-ramdisk.sh"

    # ------------------------------------------------------------------ #
    # 1. Required files
    # ------------------------------------------------------------------ #
    required = [
        "package-vendor-boot.sh",
        "extract-official-prebuilts.sh",
        "build.sh",
        "recovery/prepare-ramdisk.sh",
        "recovery/root/init.recovery.mt6991.rc",
        "recovery/root/init.recovery.project.rc",
        "prebuilt/kernel",
        "prebuilt/dtb/dash.dtb",
        "prebuilt/vendor_ramdisk/platform.cpio.gz",
        "prebuilt/vendor_ramdisk/platform.slim.cpio.gz",
        "prebuilt/recovery_modules/scp.ko",
        "prebuilt/recovery_modules/nt38771_touch_dash.ko",
        "prebuilt/recovery_modules/xiaomi_touch_dash.ko",
        "prebuilt/recovery_modules/modules.dep",
        "prebuilt/recovery_properties/system.build.prop",
        "prebuilt/recovery_properties/vendor.build.prop",
        "recovery.fstab",
        "recovery/root/first_stage_ramdisk/fstab.emmc",
        "recovery/root/system/etc/ueventd.rc",
    ]
    for rel in required:
        if not (root / rel).is_file():
            die(f"missing required file: {rel}")

    # ------------------------------------------------------------------ #
    # 2. Dead-code / hardcoded-path residues
    # ------------------------------------------------------------------ #
    for rel in ("build-variant.sh", "recovery/patch-ap-touch-modules.py"):
        if (root / rel).exists():
            die(f"stale file should have been removed: {rel}")
    for script in (pkg, extract, prepare, root / "build.sh"):
        text = script.read_text(encoding="utf-8", errors="replace")
        if "/home/twrp" in text:
            die(f"{script.name}: hardcoded /home/twrp path")

    # scripts executed directly by the build (BOARD_RECOVERY_IMAGE_PREPARE,
    # BOARD_CUSTOM_MKBOOTIMG, init rc) MUST carry the executable bit
    executable = [
        "build.sh",
        "package-vendor-boot.sh",
        "extract-official-prebuilts.sh",
        "tools/slim-platform.sh",
        "recovery/prepare-ramdisk.sh",
        "recovery/root/system/bin/beforemodules.sh",
        "recovery/root/system/bin/postrecoveryboot.sh",
        "scripts/mkbootimg-wrapper.sh",
    ]
    for rel in executable:
        mode = (root / rel).stat().st_mode
        if not mode & 0o111:
            die(f"{rel} is not executable (mode {oct(mode & 0o777)})")
    for script in (root / "Android.mk", prepare):
        text = script.read_text(encoding="utf-8", errors="replace")
        if "patch-ap-touch-modules" in text:
            die(f"{script.name}: still references deleted patch-ap-touch-modules.py")

    wrapper = (root / "scripts/mkbootimg-wrapper.sh").read_text(encoding="utf-8")
    if "../../../.." not in wrapper:
        die("scripts/mkbootimg-wrapper.sh: missing relative TOP resolution")
    if "/home/twrp" in wrapper:
        die("scripts/mkbootimg-wrapper.sh: hardcoded path")

    # ------------------------------------------------------------------ #
    # 3. package-vendor-boot.sh constants vs shipped prebuilts
    # ------------------------------------------------------------------ #
    pkg_const = load_constants(
        pkg,
        (
            "PLATFORM_CPIO_SHA256",
            "PLATFORM_GZIP_SHA256",
            "STOCK_CPIO_SHA256",
            "STOCK_GZIP_SHA256",
            "PLATFORM_LIBCPP_SHA256",
            "DTB_SHA256",
            "SCP_OUTPUT_SHA256",
            "NT38771_OUTPUT_SHA256",
            "XIAOMI_TOUCH_SHA256",
            "MERGED_MODULES_DEP_SHA256",
        ),
    )
    # slim platform (default packaging input) + stock platform (reference)
    slim_gz = (root / "prebuilt/vendor_ramdisk/platform.slim.cpio.gz").read_bytes()
    if hashlib.sha256(slim_gz).hexdigest() != pkg_const["PLATFORM_GZIP_SHA256"]:
        die("platform.slim.cpio.gz != PLATFORM_GZIP_SHA256")
    slim_cpio = gzip.decompress(slim_gz)
    if hashlib.sha256(slim_cpio).hexdigest() != pkg_const["PLATFORM_CPIO_SHA256"]:
        die("platform.slim.cpio.gz(decompressed) != PLATFORM_CPIO_SHA256")
    stock_gz = (root / "prebuilt/vendor_ramdisk/platform.cpio.gz").read_bytes()
    if hashlib.sha256(stock_gz).hexdigest() != pkg_const["STOCK_GZIP_SHA256"]:
        die("platform.cpio.gz != STOCK_GZIP_SHA256")
    if hashlib.sha256(gzip.decompress(stock_gz)).hexdigest() != pkg_const[
        "STOCK_CPIO_SHA256"
    ]:
        die("platform.cpio.gz(decompressed) != STOCK_CPIO_SHA256")

    # slim semantics: res/ empty, libc++.so kept, F1-covered libs removed
    slim_root = _cpio_extract(slim_cpio)
    res_files = [p for p in slim_root.rglob("*") if p.is_file() and "res" in p.parts]
    if res_files:
        die(f"slim platform res/ must be empty, found: {res_files[0]}")
    if not (slim_root / "system/lib64/libc++.so").is_file():
        die("slim platform must keep libc++.so (F1 has none; A16 platform libc++ fallback)")
    removed_libs = [
        "ld-android.so", "libasyncio.so", "libbase.so", "libbinder_ndk.so",
        "libbootloader_message.so", "libcrypto.so", "libcrypto_utils.so",
        "libcutils.so", "libdl.so", "libext2_blkid.so", "libext2_com_err.so",
        "libext2fs.so", "libext2_misc.so", "libext2_quota.so", "libext2_uuid.so",
        "libext4_utils.so", "libfec.so", "libfs_mgr.so", "libgsi.so", "liblog.so",
        "liblp.so", "libm.so", "libpackagelistparser.so", "libpcre2.so",
        "libprotobuf-cpp-lite.so", "libselinux.so", "libsparse.so",
        "libsquashfs_utils.so", "libutils.so", "libz.so",
    ]
    for lib in removed_libs:
        if (slim_root / "system/lib64" / lib).exists():
            die(f"slim platform must not contain {lib} (F1 provides it)")

    # libc++ expected value: merged rootfs libc++ == platform A16 libc++
    stock_libcpp = _cpio_extract(gzip.decompress(stock_gz)) / "system/lib64/libc++.so"
    if hashlib.sha256(stock_libcpp.read_bytes()).hexdigest() != pkg_const[
        "PLATFORM_LIBCPP_SHA256"
    ]:
        die("platform libc++.so != PLATFORM_LIBCPP_SHA256")

    pkg_map = {
        "DTB_SHA256": "prebuilt/dtb/dash.dtb",
        "SCP_OUTPUT_SHA256": "prebuilt/recovery_modules/scp.ko",
        "NT38771_OUTPUT_SHA256": "prebuilt/recovery_modules/nt38771_touch_dash.ko",
        "XIAOMI_TOUCH_SHA256": "prebuilt/recovery_modules/xiaomi_touch_dash.ko",
        "MERGED_MODULES_DEP_SHA256": "prebuilt/recovery_modules/modules.dep",
    }
    for const, rel in pkg_map.items():
        if sha256_file(root / rel) != pkg_const[const]:
            die(f"{rel} != {const}")

    # ------------------------------------------------------------------ #
    # 4. prepare-ramdisk.sh prop hashes vs shipped
    # ------------------------------------------------------------------ #
    prepare_text = prepare.read_text(encoding="utf-8")
    for prop in ("system.build.prop", "vendor.build.prop"):
        m = re.search(
            rf"verify_sha256 ([0-9a-f]{{64}})\s*\\?\s*\"\$property_dir/{prop}\"",
            prepare_text,
        )
        if not m:
            die(f"prepare-ramdisk.sh: missing hash for {prop}")
        if sha256_file(root / f"prebuilt/recovery_properties/{prop}") != m.group(1):
            die(f"prebuilt/recovery_properties/{prop} mismatch in prepare-ramdisk.sh")

    # ------------------------------------------------------------------ #
    # 5. extract-official-prebuilts.sh: OTA-expected hashes vs shipped
    #    (files the script re-installs must match; the SKIP'd locally-modified
    #    files are only baseline-verified and are excluded here)
    # ------------------------------------------------------------------ #
    extract_text = extract.read_text(encoding="utf-8")
    extract_map = {
        r'"\$source_root/boot/kernel"': "prebuilt/kernel",
        r'"\$source_root/vendor_boot/dtb"': "prebuilt/dtb/dash.dtb",
        r'"\$source_root/recovery_ramdisk/root/first_stage_ramdisk/fstab.emmc"':
            "recovery/root/first_stage_ramdisk/fstab.emmc",
        r'"\$source_root/recovery_ramdisk/root/init.recovery.mt6991.rc"':
            "recovery/root/init.recovery.mt6991.rc",
        r'"\$vendor_dlkm_modules/scp.ko"': "prebuilt/recovery_modules/scp.ko",
        r'"\$vendor_dlkm_modules/nt38771_touch_dash.ko"':
            "prebuilt/recovery_modules/nt38771_touch_dash.ko",
        r'"\$vendor_dlkm_modules/xiaomi_touch_dash.ko"':
            "prebuilt/recovery_modules/xiaomi_touch_dash.ko",
        r'"\$platform_modules/modules.dep"': "prebuilt/recovery_modules/modules.dep",
        r'"\$system_build_props"': "prebuilt/recovery_properties/system.build.prop",
        r'"\$vendor_build_props"': "prebuilt/recovery_properties/vendor.build.prop",
    }
    for quoted_path, rel in extract_map.items():
        m = re.search(rf"verify_sha256 ([0-9a-f]{{64}}) {quoted_path}", extract_text)
        if not m:
            die(f"extract script: missing verify for {rel}")
        if sha256_file(root / rel) != m.group(1):
            die(f"{rel} != extract script expected hash")

    # platform ramdisk conversion targets (extract script regenerates the
    # STOCK platform from the OTA — values must match the committed stock file)
    stock_gz_bytes = (root / "prebuilt/vendor_ramdisk/platform.cpio.gz").read_bytes()
    for const, note, actual in (
        (pkg_const["STOCK_CPIO_SHA256"], "cpio",
         hashlib.sha256(gzip.decompress(stock_gz_bytes)).hexdigest()),
        (pkg_const["STOCK_GZIP_SHA256"], "gzip",
         hashlib.sha256(stock_gz_bytes).hexdigest()),
    ):
        if actual != const:
            die(f"extract script {note} target hash drift for platform ramdisk")

    # the locally-modified files must NOT be re-installed by the script
    for rel in ("recovery.fstab", "recovery/root/system/etc/ueventd.rc"):
        if re.search(rf"install.*{re.escape(rel)}", extract_text):
            die(f"extract script must not overwrite locally-modified {rel}")

    # ------------------------------------------------------------------ #
    # 6. package-vendor-boot.sh internal consistency (mkbootimg <-> awk)
    # ------------------------------------------------------------------ #
    pkg_text = pkg.read_text(encoding="utf-8")
    m = re.search(r'--vendor_cmdline "([^"]+)"', pkg_text)
    if not m:
        die("package script: missing --vendor_cmdline")
    cmdline = m.group(1)
    m = re.search(r"vendor command line args: ([^$]+)\$", pkg_text)
    if not m:
        die("package script: missing final awk cmdline contract")
    awk_cmdline = m.group(1).strip()
    if cmdline != awk_cmdline:
        die(f"cmdline drift: mkbootimg '{cmdline}' vs awk contract '{awk_cmdline}'")
    if cmdline != "bootopt=64S3,32N2,64N2":
        die(f"unexpected dash stock cmdline: {cmdline}")
    if "erofs" in cmdline or "erofs" in awk_cmdline:
        die("cmdline must not contain erofs (dash stock has none)")

    print("All tree consistency checks passed.")
    print(f"  platform.slim.cpio.gz: {pkg_const['PLATFORM_CPIO_SHA256'][:16]}... ({len(slim_gz)} B)")
    print(f"  platform.cpio.gz (stock): {pkg_const['STOCK_CPIO_SHA256'][:16]}... ({len(stock_gz)} B)")
    print(f"  cmdline: {cmdline}")


if __name__ == "__main__":
    main()
