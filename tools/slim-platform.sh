#!/bin/bash
# dash stock platform ramdisk 大砍（dali 式，2026-08-06 验证）
# 用法: slim-platform.sh <原厂platform.cpio.gz> <输出slim.cpio.gz>
#
# 背景：原厂 platform F0 42.6MB + OrangeFox F1 ~24-25MB 超 64MB 分区。
# 砍法与 dali_OrangeFox14_vendor_boot.img 的 F0 一致（dali 实机验证过的结构）：
#
#   1. res/ 整个删（13MB stock recovery UI；F1 的 twres 提供 UI，无用途）
#   2. system/lib64 删 F1 会覆盖的库（dali 同款清单 31 个）
#      ⚠️ 保留 libc++.so —— dash 的 F1 被 prepare-ramdisk.sh 删了 libc++
#         （旧 libc++ 缺 A16 verbose-abort ABI），recovery 二进制依赖
#         平台 A16 libc++（794eb8fa，与 rodin 官方平台同款）兜底
#   3. lib/modules 不动（44MB 全量内核模块，recovery first-stage 加载）
#   4. system/bin 不动（toybox 全家桶/servicemanager/adbd 等）
#
# 结果：slim F0 gzip ≈ 29.9MB（省 12.6MB），F0+F1 ≈ 53MB，余量 ~11MB。
set -eu

die() { echo "slim-platform: $*" >&2; exit 1; }

[ "$#" -eq 2 ] || die "usage: $0 <stock-platform.cpio.gz> <out-slim.cpio.gz>"
STOCK=$1
OUT=$2
[ -f "$STOCK" ] || die "missing stock platform: $STOCK"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

gzip -dc "$STOCK" > "$WORK/platform.cpio"
(cd "$WORK" && mkdir root && cd root && cpio -idmu --quiet < ../platform.cpio)

# 1. res/ 整个删（留空目录，与 dali 一致）
rm -rf "$WORK/root/res"
mkdir -p "$WORK/root/res"

# 2. 砍 F1 覆盖库（dali 清单，保留 libc++.so）
SLIM_LIBS="
ld-android.so libasyncio.so libbase.so libbinder_ndk.so libbootloader_message.so
libcrypto.so libcrypto_utils.so libcutils.so libdl.so
libext2_blkid.so libext2_com_err.so libext2fs.so libext2_misc.so libext2_quota.so
libext2_uuid.so libext4_utils.so libfec.so libfs_mgr.so libgsi.so liblog.so
liblp.so libm.so libpackagelistparser.so libpcre2.so libprotobuf-cpp-lite.so
libselinux.so libsparse.so libsquashfs_utils.so libutils.so libz.so
"
for lib in $SLIM_LIBS; do
    rm -f "$WORK/root/system/lib64/$lib"
done
[ -f "$WORK/root/system/lib64/libc++.so" ] || die "libc++.so must be kept"

# 3. 重打包 + gzip -9 -n（确定性：find 排序固定 cpio 条目顺序）
(cd "$WORK/root" && find . | sort | cpio -o -H newc --owner root:root 2>/dev/null) > "$WORK/slim.cpio"
gzip -9 -n -c "$WORK/slim.cpio" > "$OUT.tmp"
mv "$OUT.tmp" "$OUT"
echo "slim platform: $OUT ($(stat -c %s "$OUT") bytes)"
echo "cpio sha256: $(sha256sum "$WORK/slim.cpio" | awk '{print $1}')"
echo "gzip sha256: $(sha256sum "$OUT" | awk '{print $1}')"
