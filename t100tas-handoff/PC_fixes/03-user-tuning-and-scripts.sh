#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR" "$HOME/.cache"

echo "=== [1/5] Installing Wayland OSK & Auto-Rotate scripts in $BIN_DIR ==="

cat << 'EOF' > "$BIN_DIR/t100-common.sh"
#!/usr/bin/env bash
# Shared hardware detection helpers for ASUS Transformer Book T100TAS

t100_has_dock() {
    local dev vendor product
    for dev in /sys/bus/usb/devices/*; do
        if [ -f "$dev/idVendor" ] && [ -f "$dev/idProduct" ]; then
            vendor=$(cat "$dev/idVendor" 2>/dev/null || true)
            product=$(cat "$dev/idProduct" 2>/dev/null || true)
            if [ "$vendor" = "0b05" ] && [ "$product" = "17e0" ]; then
                return 0
            fi
        fi
    done
    return 1
}

t100_has_keyboard() {
    if compgen -G "/dev/input/by-id/*-event-kbd" > /dev/null; then
        return 0
    fi
    t100_has_dock
}

t100_claim_pidfile() {
    local pidfile="$1" old_pid
    if [ -f "$pidfile" ]; then
        old_pid=$(cat "$pidfile" 2>/dev/null || true)
        if [ -n "$old_pid" ] && [ "$old_pid" != "$$" ] && kill -0 "$old_pid" 2>/dev/null; then
            kill "$old_pid" 2>/dev/null || true
            sleep 0.1
        fi
    fi
    printf '%s\n' "$$" > "$pidfile"
}
EOF

cat << 'EOF' > "$BIN_DIR/t100-auto-osk-wl.sh"
#!/usr/bin/env bash
set -u

# shellcheck source=/dev/null
. /home/piergi/.local/bin/t100-common.sh

PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/t100-auto-osk-wl.pid"
t100_claim_pidfile "$PID_FILE"

WVKBD_PID=""
UDEV_PID=""

cleanup() {
    trap - EXIT INT TERM
    [ -n "$UDEV_PID" ] && kill "$UDEV_PID" 2>/dev/null || true
    [ -n "$WVKBD_PID" ] && kill "$WVKBD_PID" 2>/dev/null || true
    rm -f "$PID_FILE"
}
trap cleanup EXIT INT TERM

# Avoid duplicate instances if restarted
pkill -u "$USER" -x wvkbd-mobintl 2>/dev/null || true

start_wvkbd() {
    wvkbd-mobintl --hidden \
        -H 240 -L 200 \
        --fn "Noto Sans 15" \
        --bg 232629 --fg 31363b --fg-sp 2a2e32 \
        --press 3daee9 --press-sp 3daee9 \
        --text eff0f1 --text-sp eff0f1 &
    WVKBD_PID=$!
}

LAST_STATE=""

sync_osk_state() {
    local desired
    if ! kill -0 "$WVKBD_PID" 2>/dev/null; then
        start_wvkbd
        sleep 0.3
        LAST_STATE=""
    fi

    if t100_has_keyboard; then
        desired="hidden"
    else
        desired="shown"
    fi

    if [ "$desired" != "$LAST_STATE" ]; then
        if [ "$desired" = "hidden" ]; then
            kill -USR1 "$WVKBD_PID" 2>/dev/null && LAST_STATE="hidden"
        else
            kill -USR2 "$WVKBD_PID" 2>/dev/null && LAST_STATE="shown"
        fi
    fi
}

start_wvkbd
sleep 0.5
sync_osk_state

udevadm monitor --udev --subsystem-match=input --subsystem-match=usb | {
    while IFS= read -r line; do
        case "$line" in
            *" add "*|*" remove "*)
                sleep 0.2
                sync_osk_state
                ;;
        esac
    done
} &
UDEV_PID=$!
wait "$UDEV_PID"
EOF

cat << 'EOF' > "$BIN_DIR/t100-auto-rotate.sh"
#!/usr/bin/env bash
set -u

# shellcheck source=/dev/null
. /home/piergi/.local/bin/t100-common.sh

OUTPUT="DSI-1"
LOCK_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/t100-rotate.lock"
ORIENT_FILE="${XDG_RUNTIME_DIR:-/tmp}/t100-last-orientation"

map_transform() {
    case "$1" in
        normal)    printf 'normal\n' ;;
        bottom-up) printf '180\n' ;;
        right-up)  printf '90\n' ;;
        left-up)   printf '270\n' ;;
        *)         return 1 ;;
    esac
}

apply_transform() {
    local t="$1"
    wlr-randr --output "$OUTPUT" --transform "$t" 2>/dev/null || true
}

cmd_status() {
    if [ -f "$LOCK_FILE" ]; then
        printf '{"text":"Rot:Lock","class":"locked","tooltip":"Auto-rotate locked (click to unlock, right-click to reset)"}\n'
    elif t100_has_dock; then
        printf '{"text":"Rot:Dock","class":"docked","tooltip":"Dock attached (landscape) - click to lock rotation"}\n'
    else
        printf '{"text":"Rot:Auto","class":"auto","tooltip":"Auto-rotate active (click to lock)"}\n'
    fi
}

cmd_toggle() {
    mkdir -p "$(dirname "$LOCK_FILE")"
    if [ -f "$LOCK_FILE" ]; then
        rm -f "$LOCK_FILE"
        notify-send -a "Screen Rotation" -t 2000 "Auto-rotate enabled" 2>/dev/null || true
        if t100_has_dock; then
            wlr-randr --output "$OUTPUT" --transform normal 2>/dev/null || true
        elif [ -f "$ORIENT_FILE" ]; then
            local orient tf
            orient=$(cat "$ORIENT_FILE" 2>/dev/null || true)
            if tf=$(map_transform "$orient"); then
                wlr-randr --output "$OUTPUT" --transform "$tf" 2>/dev/null || true
            fi
        fi
    else
        : > "$LOCK_FILE"
        notify-send -a "Screen Rotation" -t 2000 "Auto-rotate locked" 2>/dev/null || true
    fi
    pkill -RTMIN+10 waybar 2>/dev/null || true
}

case "${1:-}" in
    status)
        cmd_status
        exit 0
        ;;
    toggle)
        cmd_toggle
        exit 0
        ;;
esac

PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/t100-auto-rotate.pid"
t100_claim_pidfile "$PID_FILE"

FIFO_DIR=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/t100-rot.XXXXXX")
FIFO="$FIFO_DIR/events"
mkfifo "$FIFO"
SENSOR_PID=""
UDEV_PID=""

cleanup() {
    trap - EXIT INT TERM
    [ -n "$SENSOR_PID" ] && kill "$SENSOR_PID" 2>/dev/null || true
    [ -n "$UDEV_PID" ] && kill "$UDEV_PID" 2>/dev/null || true
    rm -rf "$FIFO_DIR"
    rm -f "$PID_FILE"
}
trap cleanup EXIT INT TERM

CUR_ORIENT="normal"
printf '%s\n' "$CUR_ORIENT" > "$ORIENT_FILE"

if t100_has_dock; then
    WAS_DOCKED=1
    apply_transform "normal"
else
    WAS_DOCKED=0
fi

LC_ALL=C monitor-sensor --accel 2>/dev/null \
    | sed -u -n \
        -e 's/.*Has accelerometer (orientation: \([a-z-]*\)).*/SENSOR \1/p' \
        -e 's/.*Accelerometer orientation changed: \([a-z-]*\).*/SENSOR \1/p' \
    > "$FIFO" &
SENSOR_PID=$!

udevadm monitor --udev --subsystem-match=usb 2>/dev/null \
    | sed -u -n '/ add \| remove /s/.*/UDEV/p' \
    > "$FIFO" &
UDEV_PID=$!

exec 3<>"$FIFO"
while IFS= read -r event <&3; do
    case "$event" in
        SENSOR\ *)
            CUR_ORIENT="${event#SENSOR }"
            printf '%s\n' "$CUR_ORIENT" > "$ORIENT_FILE"
            if [ ! -f "$LOCK_FILE" ] && ! t100_has_dock; then
                if tf=$(map_transform "$CUR_ORIENT"); then
                    apply_transform "$tf"
                fi
            fi
            ;;
        UDEV)
            sleep 0.2
            if t100_has_dock; then
                IS_DOCKED=1
            else
                IS_DOCKED=0
            fi
            if [ "$IS_DOCKED" != "$WAS_DOCKED" ]; then
                WAS_DOCKED="$IS_DOCKED"
                pkill -RTMIN+10 waybar 2>/dev/null || true
                if [ "$IS_DOCKED" -eq 1 ]; then
                    apply_transform "normal"
                elif [ ! -f "$LOCK_FILE" ]; then
                    if tf=$(map_transform "$CUR_ORIENT"); then
                        apply_transform "$tf"
                    fi
                fi
            fi
            ;;
    esac
done
EOF

chmod +x "$BIN_DIR/t100-common.sh" "$BIN_DIR/t100-auto-osk-wl.sh" "$BIN_DIR/t100-auto-rotate.sh" "$HOME/.config/labwc/autostart"
bash -n "$BIN_DIR/t100-common.sh" "$BIN_DIR/t100-auto-osk-wl.sh" "$BIN_DIR/t100-auto-rotate.sh"
echo "Syntax OK for all scripts in $BIN_DIR"

echo "=== [2/5] Optimizing Firefox ESR profile for low RAM & eMMC wear ==="
FF_PROFILE="$HOME/.mozilla/firefox/bh8t3up4.default-esr"
if [ -d "$FF_PROFILE" ]; then
    cat << 'EOF' > "$FF_PROFILE/user.js"
// ASUS T100TAS performance & eMMC longevity settings (2 GiB RAM / eMMC)
user_pref("browser.cache.disk.enable", false);
user_pref("browser.cache.memory.enable", true);
user_pref("browser.cache.memory.capacity", 65536);
user_pref("dom.ipc.processCount", 2);
user_pref("dom.ipc.processCount.webIsolated", 1);
user_pref("browser.sessionstore.interval", 60000);
user_pref("gfx.webrender.all", true);
user_pref("media.ffmpeg.vaapi.enabled", true);
user_pref("widget.use-xdg-desktop-portal.file-picker", 1);
EOF
    echo "Wrote $FF_PROFILE/user.js"
else
    echo "WARN: $FF_PROFILE not found; skipped user.js"
fi

echo "=== [3/5] Removing stale user caches ==="
rm -rf \
    "$HOME/.cache/appstream" \
    "$HOME/.cache/discover" \
    "$HOME/.cache/gnome-music" \
    "$HOME/.cache/drkonqi" \
    "$HOME/.cache/plasma_theme_"*

echo "=== [4/5] Masking bloaty / conflicting user systemd services ==="
MASK_UNITS=(
    evolution-source-registry.service
    evolution-addressbook-factory.service
    evolution-calendar-factory.service
    evolution-user-prompter.service
    localsearch-3.service
    kde-baloo.service
    plasma-kaccess.service
    drkonqi-coredump-pickup.service
    drkonqi-sentry-postman.path
    drkonqi-sentry-postman.timer
    waybar.service
    mako.service
    foot-server.service
    foot-server.socket
)
systemctl --user stop \
    waybar.service \
    mako.service \
    foot-server.service \
    foot-server.socket \
    app-blueman@autostart.service \
    app-org.kde.kdeconnect.daemon@autostart.service 2>/dev/null || true
systemctl --user mask "${MASK_UNITS[@]}" || true

echo "=== [5/5] Testing non-display script functions ==="
"$BIN_DIR/t100-auto-rotate.sh" status
df -h /
