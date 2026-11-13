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
    podman run --rm localhost/transformeros:stable bash -euxc '\
        echo "--- Kernel & IA32 EFI ---"; \
        rpm -q kernel-core shim-ia32 grub2-efi-ia32 labwc quickshell; \
        find /usr/lib/efi /usr/lib/bootupd/updates /usr/share/transformeros -iname "*ia32*.efi"; \
        echo "--- Firmware ---"; \
        ls -la /usr/lib/firmware/brcm/BCM4324B3.hcd "/usr/lib/firmware/brcm/brcmfmac43241b4-sdio.txt" "/usr/lib/firmware/brcm/brcmfmac43241b4-sdio.ASUSTeK COMPUTER INC.-T100TAS.txt"; \
        echo "--- Binaries ---"; \
        /usr/bin/transformerd status; \
        python3 -m py_compile /usr/bin/transformer-greeter /usr/bin/transformer-shell; \
        bootc container lint || true'

# Run the 32-bit IA32 UEFI boot verification test in QEMU
test-qemu-ia32:
    ./tests/qemu/test-ia32-efi.sh
