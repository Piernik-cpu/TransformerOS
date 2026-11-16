set shell := ["bash", "-euo", "pipefail", "-c"]

image := "ghcr.io/piernik-cpu/transformeros:stable"

# Default recipe: list available tasks
default:
    @just --list

# Build the TransformerOS Fedora 45 bootc container image locally
build:
    podman build --format oci -t {{image}} -t localhost/transformeros:stable -f Containerfile .

# Verify 32-bit IA32 UEFI bootloader files, firmware, daemon, and bootc container lint
verify:
    bash -n scripts/install-to-t100tas.sh
    podman run --rm localhost/transformeros:stable bash -euxc '\
        echo "--- bootc lint ---"; \
        bootc container lint || true; \
        echo "--- Kernel & IA32 EFI ---"; \
        rpm -q kernel-core shim-ia32 grub2-efi-ia32 labwc quickshell fastfetch fuse fuse-libs; \
        find /usr/lib/efi /usr/lib/bootupd/updates /usr/share/transformeros -iname "*ia32*.efi"; \
        echo "--- Firmware & Prefs ---"; \
        ls -la /usr/lib/firmware/brcm/BCM4324B3.hcd "/usr/lib/firmware/brcm/brcmfmac43241b4-sdio.txt" "/usr/lib/firmware/brcm/brcmfmac43241b4-sdio.ASUSTeK COMPUTER INC.-T100TAS.txt" /usr/lib64/firefox/browser/defaults/preferences/99-t100tas-prefs.js; \
        echo "--- Binaries & Desktop Hygiene ---"; \
        /usr/bin/transformerd status; \
        /usr/bin/t100-window-ctl --help; \
        /usr/bin/transformer-store --help; \
        fastfetch --version; \
        python3 -m py_compile /usr/bin/transformer-greeter /usr/bin/transformer-store; \
        bash -n /usr/bin/transformer-session /usr/bin/transformer-greeter-session /usr/bin/transformer-shell /usr/bin/transformer-pkg-helper; \
        grep -q "NoDisplay=true" /usr/share/applications/blueman-adapters.desktop; \
        grep -q "NoDisplay=true" /usr/share/applications/pcmanfm-desktop-pref.desktop; \
        grep -q "NoDisplay=true" /usr/share/applications/foot-server.desktop; \
        grep -q "NoDisplay=true" /usr/share/applications/footclient.desktop; \
        grep -q "Super_L.*onRelease=\"yes\"" /usr/share/transformeros/labwc/rc-docked.xml; \
        grep -q "Super_L.*onRelease=\"yes\"" /usr/share/transformeros/labwc/rc-tablet.xml; \
        echo "--- Headless Labwc & Quickshell Verify ---"; \
        export XDG_RUNTIME_DIR=/tmp/t100-verify-rt; \
        mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"; \
        mkdir -p /tmp/t100-verify-labwc; \
        cp -a /usr/share/transformeros/labwc/* /tmp/t100-verify-labwc/; \
        WLR_BACKENDS=headless labwc -C /tmp/t100-verify-labwc >/tmp/labwc.log 2>&1 & \
        LABWC_PID=$!; \
        trap "kill $LABWC_PID 2>/dev/null || true" EXIT; \
        for i in $(seq 1 30); do [ -S "$XDG_RUNTIME_DIR/wayland-0" ] && break; sleep 0.2; done; \
        export WAYLAND_DISPLAY=wayland-0 QT_QUICK_BACKEND=software QSG_RENDER_LOOP=basic; \
        timeout 15 quickshell -c transformeros >/tmp/qs-shell.log 2>&1 & \
        QS_PID=$!; \
        for i in $(seq 1 40); do sed -E "s/\x1b\[[0-9;]*m//g" /tmp/qs-shell.log 2>/dev/null | grep -q "Configuration Loaded" && break; sleep 0.2; done; \
        sleep 0.4; \
        quickshell ipc -c transformeros show; \
        quickshell ipc -c transformeros call shell toggleQuickSettings; \
        sleep 0.4; \
        quickshell ipc -c transformeros call shell toggleAppGrid; \
        sleep 0.4; \
        quickshell ipc -c transformeros call shell setAppGridCategory Internet; \
        sleep 0.3; \
        quickshell ipc -c transformeros call shell setAppGridCategory System; \
        sleep 0.3; \
        quickshell ipc -c transformeros call shell setAppGridCategory All; \
        sleep 0.3; \
        quickshell ipc -c transformeros call shell toggleRecents; \
        sleep 0.4; \
        kill "$QS_PID" 2>/dev/null || true; wait "$QS_PID" 2>/dev/null || true; \
        sed -E "s/\x1b\[[0-9;]*m//g" /tmp/qs-shell.log > /tmp/qs-shell.clean; \
        cat /tmp/qs-shell.clean; \
        grep -q "Configuration Loaded" /tmp/qs-shell.clean; \
        ! grep -qiE "QQml|ReferenceError|TypeError|SyntaxError|Cannot assign|file:///etc/xdg/quickshell.*(WARN|ERROR)|Could not resolve.*icon|Cannot open" /tmp/qs-shell.clean; \
        timeout 15 quickshell -p /etc/xdg/quickshell/transformeros/greeter.qml >/tmp/qs-greeter.log 2>&1 & \
        QG_PID=$!; \
        for i in $(seq 1 40); do sed -E "s/\x1b\[[0-9;]*m//g" /tmp/qs-greeter.log 2>/dev/null | grep -q "Configuration Loaded" && break; sleep 0.2; done; \
        kill "$QG_PID" 2>/dev/null || true; wait "$QG_PID" 2>/dev/null || true; \
        sed -E "s/\x1b\[[0-9;]*m//g" /tmp/qs-greeter.log > /tmp/qs-greeter.clean; \
        cat /tmp/qs-greeter.clean; \
        grep -q "Configuration Loaded" /tmp/qs-greeter.clean; \
        ! grep -qiE "QQml|ReferenceError|TypeError|SyntaxError|Cannot assign|file:///etc/xdg/quickshell.*(WARN|ERROR)|Could not resolve.*icon|Cannot open" /tmp/qs-greeter.clean'

# Run the 32-bit IA32 UEFI boot verification test in QEMU
test-qemu-ia32:
    ./tests/qemu/test-ia32-efi.sh
