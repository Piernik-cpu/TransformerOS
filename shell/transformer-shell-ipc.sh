#!/usr/bin/env bash
# TransformerOS Shell CLI dispatcher (calls persistent Quickshell IPC target)
set -euo pipefail

CMD="${1:-qs}"
case "$CMD" in
    qs|quicksettings|quick)
        exec quickshell ipc -c transformeros call shell toggleQuickSettings
        ;;
    appgrid|apps|launcher)
        exec quickshell ipc -c transformeros call shell toggleAppGrid
        ;;
    recents|overview)
        exec quickshell ipc -c transformeros call shell toggleRecents
        ;;
    lock)
        exec quickshell ipc -c transformeros call shell lock
        ;;
    close)
        exec quickshell ipc -c transformeros call shell closePopups
        ;;
    bar)
        exec quickshell -c transformeros
        ;;
    *)
        echo "Usage: transformer-shell [qs|appgrid|recents|lock|close|bar]" >&2
        exit 1
        ;;
esac
