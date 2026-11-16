#!/usr/bin/env bash
# TransformerOS Package Management & Mutable /usr Helper
set -euo pipefail

unlock_usr() {
    # Ensure backlight sysfs brightness is writable by active desktop/greeter users
    for bl in /sys/class/backlight/*/brightness; do
        [ -e "$bl" ] && chmod 0666 "$bl" 2>/dev/null || true
    done

    # Ensure /var/usrlocal directories exist so systemd-tmpfiles-setup succeeds cleanly
    mkdir -p /var/usrlocal/bin /var/usrlocal/sbin /var/usrlocal/etc /var/usrlocal/games \
             /var/usrlocal/include /var/usrlocal/lib /var/usrlocal/lib64 /var/usrlocal/libexec \
             /var/usrlocal/share /var/usrlocal/src 2>/dev/null || true

    # Ensure video and input groups exist in /etc/group for greetd and desktop users on ostree/bootc
    for grp_spec in "video:39" "input:104"; do
        gname="${grp_spec%%:*}"
        ggid="${grp_spec##*:}"
        if ! grep -q "^${gname}:" /etc/group 2>/dev/null; then
            echo "${gname}:x:${ggid}:" >> /etc/group 2>/dev/null || true
        fi
    done
    usermod -aG video,input greetd 2>/dev/null || true
    for u in $(awk -F: '$3>=1000 && $3<60000 {print $1}' /etc/passwd 2>/dev/null); do
        usermod -aG video,input "$u" 2>/dev/null || true
    done

    # Only needed on a live ostree/bootc system where /usr is read-only
    if [ ! -e /run/ostree-booted ]; then
        return 0
    fi
    if [ -w /usr/bin ]; then
        return 0
    fi

    # Determine active ostree deployment ID from /proc/cmdline so the disk-backed
    # overlay resets cleanly when bootc switches/upgrades to a new image deployment
    local deploy_raw="default"
    if [ -r /proc/cmdline ]; then
        local ostree_arg
        ostree_arg="$(tr ' ' '\n' < /proc/cmdline | grep '^ostree=' | head -n 1 || true)"
        if [ -n "$ostree_arg" ]; then
            deploy_raw="$(printf '%s' "$ostree_arg" | sha256sum | cut -c1-16)"
        fi
    fi

    local base_dir="/var/lib/transformeros/usr-overlay"
    local deploy_dir="${base_dir}/${deploy_raw}"
    local upper_dir="${deploy_dir}/upper"
    local work_dir="${deploy_dir}/work"
    local lower_mnt="/run/transformeros-usr-lower"

    mkdir -p "$upper_dir" "$work_dir" "$lower_mnt"

    # Prune overlay directories from superseded bootc deployments to save eMMC space
    for old in "${base_dir}"/*; do
        [ -d "$old" ] || continue
        if [ "$old" != "$deploy_dir" ]; then
            rm -rf "$old" 2>/dev/null || true
        fi
    done

    chcon -R --reference=/usr "$deploy_dir" 2>/dev/null || true

    if ! mountpoint -q "$lower_mnt"; then
        mount --bind /usr "$lower_mnt" 2>/dev/null || true
    fi

    if mountpoint -q "$lower_mnt" && mount -t overlay overlay \
        -o "lowerdir=${lower_mnt},upperdir=${upper_dir},workdir=${work_dir}" \
        /usr 2>/dev/null; then
        echo "TransformerOS: mounted persistent disk-backed /usr overlay (${deploy_raw})."
        return 0
    fi

    umount "$lower_mnt" 2>/dev/null || true

    # Fallback to ostree hotfix / bootc usr-overlay
    ostree admin unlock --hotfix 2>/dev/null || \
        bootc usr-overlay 2>/dev/null || \
        ostree admin unlock 2>/dev/null || true
}

ensure_flathub() {
    if command -v flatpak >/dev/null 2>&1; then
        flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
    fi
}

CMD="${1:-unlock}"
shift || true

case "$CMD" in
    unlock)
        unlock_usr
        ;;
    dnf-install)
        unlock_usr
        exec dnf5 install -y --setopt=ip_resolve=ipv4 --setopt=install_weak_deps=False "$@"
        ;;
    dnf-remove)
        unlock_usr
        exec dnf5 remove -y "$@"
        ;;
    dnf-upgrade)
        unlock_usr
        exec dnf5 upgrade -y --setopt=ip_resolve=ipv4 "$@"
        ;;
    flathub-init)
        ensure_flathub
        ;;
    flatpak-install)
        ensure_flathub
        exec flatpak install -y --noninteractive flathub "$@"
        ;;
    flatpak-remove)
        exec flatpak uninstall -y --noninteractive "$@"
        ;;
    flatpak-update)
        ensure_flathub
        exec flatpak update -y --noninteractive
        ;;
    *)
        echo "Usage: transformer-pkg-helper [unlock|dnf-install|dnf-remove|dnf-upgrade|flathub-init|flatpak-install|flatpak-remove|flatpak-update] [args...]" >&2
        exit 1
        ;;
esac
