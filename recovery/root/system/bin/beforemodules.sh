#!/system/bin/sh

# KernelModuleLoader invokes this before vendor modules probe. The Goodix
# driver requests the official config and firmware from /odm/firmware at probe.
status=/tmp/dash-odm-beforemodules.status

report() {
    printf '%s\n' "$1" > "$status"
}

if grep -q ' /odm ' /proc/mounts; then
    report already-mounted
    exit 0
fi

slot_suffix=$(getprop ro.boot.slot_suffix)
if [ -z "$slot_suffix" ]; then
    slot=$(getprop ro.boot.slot)
    [ -n "$slot" ] && slot_suffix="_$slot"
fi

for block in "/dev/block/mapper/odm${slot_suffix}" /dev/block/by-name/odm; do
    [ -b "$block" ] || continue

    if mount -t erofs -o ro "$block" /odm; then
        report "mounted:erofs:$block"
        exit 0
    fi

    if mount -t ext4 -o ro "$block" /odm; then
        report "mounted:ext4:$block"
        exit 0
    fi
done

report mount-failed
exit 0
