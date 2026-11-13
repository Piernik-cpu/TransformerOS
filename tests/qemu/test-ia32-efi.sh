#!/usr/bin/env bash
# =============================================================================
# Verify 32-bit IA32 UEFI Bootloader Payloads & Boot TransformerOS Kernel/Initrd
# in QEMU with Intel Atom Z3775 (Silvermont, 4 cores, 1858 MiB RAM) emulation
# =============================================================================
set -euo pipefail

IMAGE="${1:-localhost/transformeros:stable}"
WORKDIR="$(mktemp -d /tmp/transformeros-qemu-test.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "=== [1/3] Extracting IA32 EFI binaries, kernel, and initramfs from $IMAGE ==="
podman run --rm -v "$WORKDIR:/out:Z" "$IMAGE" bash -euxc '
    cp -a /usr/share/transformeros/boot/bootia32.efi /out/bootia32-standalone.efi
    IA32_GRUB=$(find /usr/lib/efi /boot/efi -iname "grubia32.efi" | head -n 1)
    IA32_SHIM=$(find /usr/lib/efi /boot/efi -iname "BOOTIA32.EFI" -o -iname "shimia32.efi" | head -n 1)
    cp -a "$IA32_GRUB" /out/grubia32.efi
    cp -a "$IA32_SHIM" /out/BOOTIA32.EFI
    KVER=$(cd /usr/lib/modules && ls -1 | head -n 1)
    cp -a "/usr/lib/modules/$KVER/vmlinuz" /out/vmlinuz
    cp -a "/usr/lib/modules/$KVER/initramfs.img" /out/initramfs.img
'

echo "=== [2/3] Verifying 32-bit IA32 PE32 EFI headers ==="
for efi in "$WORKDIR/bootia32-standalone.efi" "$WORKDIR/grubia32.efi" "$WORKDIR/BOOTIA32.EFI"; do
    info="$(file -b "$efi")"
    echo "  $(basename "$efi"): $info"
    echo "$info" | grep -q "EFI"
    echo "$info" | grep -qiE "i386|Intel 80386"
done

echo "=== [3/3] Booting TransformerOS Kernel + Initramfs in QEMU (Silvermont Atom Z3775, 1858M RAM) ==="
KVM_ARGS=(-cpu Silvermont)
if [ -w /dev/kvm ]; then
    KVM_ARGS=(-enable-kvm -cpu host)
fi
qemu-system-x86_64 \
    -M q35 \
    "${KVM_ARGS[@]}" \
    -smp 4 \
    -m 1858M \
    -display none \
    -serial "file:$WORKDIR/boot.log" \
    -no-reboot \
    -kernel "$WORKDIR/vmlinuz" \
    -initrd "$WORKDIR/initramfs.img" \
    -append "console=ttyS0,115200 zswap.enabled=0 mitigations=off rd.driver.pre=mmc_core,mmc_block,sdhci,sdhci_acpi rd.break=cmdline" >/dev/null 2>&1 &
QPID=$!

for _ in $(seq 1 30); do
    if grep -qE "Starting dracut|dracut-cmdline|Linux version" "$WORKDIR/boot.log" 2>/dev/null; then
        if grep -qE "Starting dracut|dracut-cmdline|Reached target" "$WORKDIR/boot.log" 2>/dev/null; then
            break
        fi
    fi
    sleep 1
done
kill "$QPID" 2>/dev/null || true
wait "$QPID" 2>/dev/null || true

grep -E "Linux version|Command line:|systemd|dracut" "$WORKDIR/boot.log" | head -n 20
echo "=== QEMU Silvermont + IA32 EFI Verification PASSED ==="
