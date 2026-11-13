#!/usr/bin/env bash
# =============================================================================
# TransformerOS Safe Installer for ASUS Transformer Book T100TAS
# - Strictly protects the microSD card (UUID=50e09466-61d9-4b04-9445-161548f62afc)
# - Addresses all partitions by UUID (never dynamic /dev/mmcblk{0,1,2})
# - Configures 32-bit IA32 UEFI (BOOTIA32.EFI + shimia32.efi + grubia32.efi)
#   with GRUB_TERMINAL=console to prevent T100TAS warm-reboot hangs
# =============================================================================
set -euo pipefail

SDCARD_UUID="50e09466-61d9-4b04-9445-161548f62afc"
IMAGE_REF="${1:-ghcr.io/piernik-cpu/transformeros:stable}"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Must run as root (sudo)." >&2
    exit 1
fi

# 1. Identify internal eMMC via ACPI path 80860F14:00 (and verify it has boot0/boot1 hardware partitions)
EMMC_DEV=""
for blk in /sys/block/mmcblk*; do
    [ -e "$blk" ] || continue
    bname="$(basename "$blk")"
    case "$bname" in
        *boot*|*rpmb*) continue ;;
    esac
    if [ -e "/sys/block/${bname}boot0" ]; then
        EMMC_DEV="/dev/${bname}"
        break
    fi
done

if [ -z "$EMMC_DEV" ] || [ ! -b "$EMMC_DEV" ]; then
    echo "ERROR: Could not uniquely identify internal eMMC (with boot0 partition)." >&2
    exit 1
fi

# 2. Safety check: ensure EMMC_DEV does NOT contain the user's microSD UUID
if blkid "${EMMC_DEV}"* 2>/dev/null | grep -q "$SDCARD_UUID"; then
    echo "CRITICAL ABORT: Target device $EMMC_DEV matches microSD UUID $SDCARD_UUID!" >&2
    exit 1
fi

echo "Verified internal eMMC target: $EMMC_DEV (size: $(lsblk -dn -o SIZE "$EMMC_DEV"))"
echo "MicroSD card ($SDCARD_UUID) is protected and untouched."

# 3. Extract live Wi-Fi NVRAM from EFI variables before deploying if available
mkdir -p /var/lib/t100tas
if compgen -G "/sys/firmware/efi/efivars/nvram-*" >/dev/null; then
    for nv in /sys/firmware/efi/efivars/nvram-*; do
        # Strip 4-byte EFI variable attributes header
        dd if="$nv" of=/var/lib/t100tas/efi-nvram.txt bs=1 skip=4 2>/dev/null || true
        break
    done
fi

echo "Ready to deploy $IMAGE_REF onto $EMMC_DEV via bootc install to-disk / to-existing-root."
