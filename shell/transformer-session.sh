#!/usr/bin/env bash
set -euo pipefail

export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=labwc:wlroots
export MOZ_ENABLE_WAYLAND=1
export MOZ_USE_XINPUT2=1
export QT_QPA_PLATFORM=wayland
export GDK_BACKEND=wayland,x11
export LIBVA_DRIVER_NAME=i965

# Ensure user config directories are populated from /etc/skel/.config
mkdir -p "$HOME/.config/labwc" "$HOME/.config/waybar" "$HOME/.config/mako" "$HOME/.config/transformeros"

for f in rc-docked.xml rc-tablet.xml autostart environment; do
    if [ ! -f "$HOME/.config/labwc/$f" ] && [ -f "/etc/skel/.config/labwc/$f" ]; then
        cp -a "/etc/skel/.config/labwc/$f" "$HOME/.config/labwc/$f"
    fi
done
chmod +x "$HOME/.config/labwc/autostart" 2>/dev/null || true

if [ ! -f "$HOME/.config/labwc/rc.xml" ] && [ -f "$HOME/.config/labwc/rc-docked.xml" ]; then
    cp -a "$HOME/.config/labwc/rc-docked.xml" "$HOME/.config/labwc/rc.xml"
fi

for f in config.jsonc style.css; do
    if [ ! -f "$HOME/.config/waybar/$f" ] && [ -f "/etc/skel/.config/waybar/$f" ]; then
        cp -a "/etc/skel/.config/waybar/$f" "$HOME/.config/waybar/$f"
    fi
done

exec labwc
