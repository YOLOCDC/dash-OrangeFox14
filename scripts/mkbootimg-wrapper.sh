#!/bin/bash
# BOARD_CUSTOM_MKBOOTIMG wrapper (OrangeFox 14.1).
# The AOSP top is resolved from this script's own location
# (<top>/device/xiaomi/dash/scripts -> <top>), so the tree is portable.
TOP=$(cd "$(dirname "$0")/../../../.." && pwd)
exec python3 "$TOP/system/tools/mkbootimg/mkbootimg.py" "$@"
