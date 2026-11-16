#!/usr/bin/env bash
# TransformerOS Shell CLI dispatcher (calls persistent Quickshell IPC target)
set -euo pipefail
export LANG="${LANG:-C.UTF-8}"

ensure_daemons() {
    if ! pgrep -u "$(id -u)" -x transformerd >/dev/null 2>&1; then
        nohup /usr/bin/transformerd daemon >/dev/null 2>&1 &
    fi
    if ! pgrep -u "$(id -u)" -x quickshell >/dev/null 2>&1; then
        nohup quickshell -c transformeros >/dev/null 2>&1 &
        for _ in $(seq 1 25); do
            quickshell ipc -c transformeros show >/dev/null 2>&1 && break
            sleep 0.1
        done
    fi
}

CMD="${1:-qs}"
case "$CMD" in
    qs|quicksettings|quick)
        ensure_daemons
        exec quickshell ipc -c transformeros call shell toggleQuickSettings
        ;;
    appgrid|apps|launcher)
        ensure_daemons
        exec quickshell ipc -c transformeros call shell toggleAppGrid
        ;;
    recents|overview)
        ensure_daemons
        exec quickshell ipc -c transformeros call shell toggleRecents
        ;;
    lock)
        ensure_daemons
        exec quickshell ipc -c transformeros call shell lock
        ;;
    unlock)
        ensure_daemons
        exec quickshell ipc -c transformeros call shell unlock
        ;;
    close)
        ensure_daemons
        exec quickshell ipc -c transformeros call shell closePopups
        ;;
    ensure)
        ensure_daemons
        ;;
    bar)
        exec quickshell -c transformeros
        ;;
    store|packages)
        exec /usr/bin/transformer-store "${@:2}"
        ;;
    *)
        echo "Usage: transformer-shell [qs|appgrid|recents|lock|unlock|close|ensure|bar|store]" >&2
        exit 1
        ;;
esac
