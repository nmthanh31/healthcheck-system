#!/usr/bin/env bash

check_filesystem() {
    local filesystem blocks used available usage_percent mountpoint usage

    section "4. DISK SPACE AND INODE USAGE"

    # df -P tạo đầu ra một dòng cho mỗi filesystem, dễ đọc ổn định bằng Bash.
    while read -r filesystem blocks used available usage_percent mountpoint; do
        usage="${usage_percent%%%}"
        [ -n "$usage" ] || continue

        if [ "$usage" -ge "$DISK_CRIT" ]; then
            crit "Disk ${mountpoint}=${usage}% (${filesystem})"
        elif [ "$usage" -ge "$DISK_WARN" ]; then
            warn "Disk ${mountpoint}=${usage}% (${filesystem})"
        else
            ok "Disk ${mountpoint}=${usage}% (${filesystem})"
        fi
    done < <(df -P -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | awk 'NR > 1')

    while read -r filesystem blocks used available usage_percent mountpoint; do
        usage="${usage_percent%%%}"
        [ -n "$usage" ] || continue

        if [ "$usage" -ge "$INODE_CRIT" ]; then
            crit "Inode ${mountpoint}=${usage}% (${filesystem})"
        elif [ "$usage" -ge "$INODE_WARN" ]; then
            warn "Inode ${mountpoint}=${usage}% (${filesystem})"
        else
            ok "Inode ${mountpoint}=${usage}% (${filesystem})"
        fi
    done < <(df -Pi -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | awk 'NR > 1')
}
