#!/usr/bin/env bash
set -euo pipefail

export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=labwc:wlroots
export MOZ_ENABLE_WAYLAND=1
export MOZ_USE_XINPUT2=1
export QT_QPA_PLATFORM=wayland
export QSG_RENDER_LOOP=basic
export GDK_BACKEND=wayland,x11
export LIBVA_DRIVER_NAME=i965

# Ensure user config directories exist and OS-managed defaults stay synced across bootc upgrades
mkdir -p "$HOME/.config/labwc" "$HOME/.config/transformeros"

STAMP_FILE="$HOME/.config/labwc/.transformeros-sync"
SYS_LABWC="/usr/share/transformeros/labwc"

if [ -d "$SYS_LABWC" ]; then
    for f in rc-docked.xml rc-tablet.xml autostart environment; do
        if [ -f "$SYS_LABWC/$f" ]; then
            cp -a "$SYS_LABWC/$f" "$HOME/.config/labwc/$f"
        fi
    done
    chmod +x "$HOME/.config/labwc/autostart" 2>/dev/null || true
    if [ ! -f "$HOME/.config/labwc/rc.xml" ] || [ ! -f "$STAMP_FILE" ]; then
        cp -a "$HOME/.config/labwc/rc-docked.xml" "$HOME/.config/labwc/rc.xml"
        date -Is > "$STAMP_FILE"
    fi
fi

exec labwc
