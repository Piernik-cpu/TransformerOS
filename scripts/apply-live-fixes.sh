#!/usr/bin/env bash
# Apply TransformerOS Apps Menu, Super Key, Desktop Icon Cleanup, Mutable DNF5,
# fastfetch, and Unified Package Manager fixes directly to a live T100TAS system.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root: sudo $0" >&2
    exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== 1. Unlocking /usr for persistent package & shell updates ==="
mkdir -p /var/lib/transformeros/bin
install -m 0755 "$REPO_DIR/shell/transformer-pkg-helper.sh" /var/lib/transformeros/bin/transformer-pkg-helper
install -m 0755 "$REPO_DIR/shell/transformer-store.py" /var/lib/transformeros/bin/transformer-store
/var/lib/transformeros/bin/transformer-pkg-helper unlock
install -m 0755 "$REPO_DIR/shell/transformer-pkg-helper.sh" /usr/bin/transformer-pkg-helper

echo "=== 2. Installing DNF5 config, systemd unlock unit, and Polkit rules ==="
mkdir -p /usr/share/dnf5/libdnf.conf.d /etc/dnf/libdnf5.conf.d /etc/systemd/system
cp -a "$REPO_DIR/system/usr/share/dnf5/libdnf.conf.d/90-transformeros.conf" /usr/share/dnf5/libdnf.conf.d/90-transformeros.conf
cp -a "$REPO_DIR/system/etc/dnf/libdnf5.conf.d/90-transformeros.conf" /etc/dnf/libdnf5.conf.d/90-transformeros.conf
cp -a "$REPO_DIR/system/usr/lib/systemd/system/transformeros-usr-unlock.service" /usr/lib/systemd/system/transformeros-usr-unlock.service
cp -a "$REPO_DIR/system/usr/lib/systemd/system/transformeros-usr-unlock.service" /etc/systemd/system/transformeros-usr-unlock.service
cp -a "$REPO_DIR/system/usr/share/polkit-1/rules.d/50-transformeros-bootc.rules" /usr/share/polkit-1/rules.d/50-transformeros-bootc.rules
cp -a "$REPO_DIR/system/etc/default/earlyoom" /etc/default/earlyoom
systemctl daemon-reload
systemctl enable transformeros-usr-unlock.service 2>/dev/null || true

echo "=== 3. Installing TransformerOS Package Manager & updating Quickshell + Labwc ==="
install -m 0755 "$REPO_DIR/shell/transformer-store.py" /usr/bin/transformer-store
install -m 0755 "$REPO_DIR/shell/transformer-shell-ipc.sh" /usr/bin/transformer-shell
install -m 0755 "$REPO_DIR/shell/transformer-session.sh" /usr/bin/transformer-session
install -m 0644 "$REPO_DIR/system/usr/share/applications/transformer-store.desktop" /usr/share/applications/transformer-store.desktop

cp -a "$REPO_DIR/shell/quickshell/"* /etc/xdg/quickshell/transformeros/
cp -a "$REPO_DIR/shell/labwc/"* /usr/share/transformeros/labwc/
cp -a "$REPO_DIR/shell/labwc/rc-docked.xml" /usr/share/transformeros/labwc/rc.xml

# Immediately unlock any stuck WlSessionLock as soon as QML hot-reloads
sleep 1
for rt_dir in /run/user/*; do
    [ -S "$rt_dir/wayland-0" ] || continue
    uid="$(basename "$rt_dir")"
    uname="$(id -nu "$uid" 2>/dev/null || true)"
    if [ -n "$uname" ]; then
        runuser -u "$uname" -- env XDG_RUNTIME_DIR="$rt_dir" WAYLAND_DISPLAY=wayland-0 \
            quickshell ipc -c transformeros call shell unlock >/dev/null 2>&1 || true
    fi
done

for home_dir in /home/*; do
    [ -d "$home_dir" ] || continue
    user_name="$(basename "$home_dir")"
    mkdir -p "$home_dir/.config/labwc"
    cp -a "$REPO_DIR/shell/labwc/"* "$home_dir/.config/labwc/"
    cp -a "$REPO_DIR/shell/labwc/rc-docked.xml" "$home_dir/.config/labwc/rc.xml"
    chown -R "$user_name:$user_name" "$home_dir/.config/labwc" 2>/dev/null || true
done

echo "=== 4. Hiding redundant 'Bluetooth Adapters', 'Desktop Preferences' & 'Foot Server/Client' icons ==="
for df in /usr/share/applications/blueman-adapters.desktop \
          /usr/share/applications/pcmanfm-desktop-pref.desktop \
          /usr/share/applications/foot-server.desktop \
          /usr/share/applications/footclient.desktop; do
    if [ -f "$df" ]; then
        sed -i '/^NoDisplay=/d' "$df"
        printf '\nNoDisplay=true\n' >> "$df"
    fi
done

echo "=== 4b. Configuring xdg-desktop-portal & masking duplicate user services ==="
mkdir -p /usr/lib/systemd/user/xdg-desktop-portal.service.d /usr/share/xdg-desktop-portal
cp -a "$REPO_DIR/system/usr/lib/systemd/user/xdg-desktop-portal.service.d/10-transformeros.conf" /usr/lib/systemd/user/xdg-desktop-portal.service.d/10-transformeros.conf
cp -a "$REPO_DIR/system/usr/share/xdg-desktop-portal/labwc-portals.conf" /usr/share/xdg-desktop-portal/labwc-portals.conf
cp -a "$REPO_DIR/system/usr/lib/udev/rules.d/90-t100tas.rules" /usr/lib/udev/rules.d/90-t100tas.rules
cp -a "$REPO_DIR/system/usr/lib/tmpfiles.d/t100tas-tuning.conf" /usr/lib/tmpfiles.d/t100tas-tuning.conf
systemctl --global mask waybar.service mako.service kanshi.service foot-server.service foot-server.socket 2>/dev/null || true

echo "=== 5. Configuring Flathub & installing fastfetch + AppImage FUSE support ==="
/usr/bin/transformer-pkg-helper flathub-init || true
dnf5 install -y --setopt=ip_resolve=ipv4 --setopt=install_weak_deps=False fastfetch fuse fuse-libs desktop-file-utils || true

echo "=== 6. Reloading running Labwc & Quickshell session ==="
pkill -HUP labwc 2>/dev/null || true
# Allow Quickshell to hot-reload updated QML files and cleanly release any active WlSessionLock before restart
sleep 1
for rt_dir in /run/user/*; do
    [ -S "$rt_dir/wayland-0" ] || continue
    uid="$(basename "$rt_dir")"
    uname="$(id -nu "$uid" 2>/dev/null || true)"
    if [ -n "$uname" ]; then
        runuser -u "$uname" -- env \
            HOME="/home/$uname" \
            USER="$uname" \
            LOGNAME="$uname" \
            XDG_RUNTIME_DIR="$rt_dir" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=$rt_dir/bus" \
            WAYLAND_DISPLAY=wayland-0 \
            labwc --reconfigure >/dev/null 2>&1 || true
        runuser -u "$uname" -- env \
            HOME="/home/$uname" \
            USER="$uname" \
            LOGNAME="$uname" \
            XDG_RUNTIME_DIR="$rt_dir" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=$rt_dir/bus" \
            WAYLAND_DISPLAY=wayland-0 \
            quickshell ipc -c transformeros call shell unlock >/dev/null 2>&1 || true
    fi
done
sleep 0.5
pkill -x quickshell 2>/dev/null || true
sleep 0.3
for rt_dir in /run/user/*; do
    [ -S "$rt_dir/wayland-0" ] || continue
    uid="$(basename "$rt_dir")"
    uname="$(id -nu "$uid" 2>/dev/null || true)"
    if [ -n "$uname" ]; then
        runuser -u "$uname" -- env \
            XDG_RUNTIME_DIR="$rt_dir" \
            WAYLAND_DISPLAY=wayland-0 \
            wtype -k XF86HomePage >/dev/null 2>&1 || true
        sleep 1.2
        runuser -u "$uname" -- env \
            XDG_RUNTIME_DIR="$rt_dir" \
            WAYLAND_DISPLAY=wayland-0 \
            /usr/bin/transformer-shell close >/dev/null 2>&1 || true
    fi
done

echo "All fixes applied! Press the Super/Windows key to test the Apps menu."
