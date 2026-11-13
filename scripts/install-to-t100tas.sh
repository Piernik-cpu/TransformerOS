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
IMAGE_REF="ghcr.io/piernik-cpu/transformeros:stable"
MODE="auto"
EMMC_DEV=""
SSH_KEY_FILE=""
GENERIC_IMAGE=false
ASSUME_YES=false
EXTRA_KARGS=()

usage() {
    cat <<'EOF'
Usage: install-to-t100tas.sh [OPTIONS] [IMAGE_REF]

Options:
  --image <ref>         Container image ref (default: ghcr.io/piernik-cpu/transformeros:stable)
  --mode <mode>         auto | to-disk | to-existing-root (default: auto)
  --device <dev>        Override target eMMC block device (auto-detected via boot0)
  --ssh-key <path>      Authorized public key file injected via --root-ssh-authorized-keys
  --generic-image       Pass --generic-image to bootc install (skip efibootmgr NVRAM changes)
  --karg <arg>          Additional kernel argument passed to bootc install (repeatable)
  --yes                 Skip interactive confirmation prompt
  -h, --help            Show this help message
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --image)
            IMAGE_REF="$2"
            shift 2
            ;;
        --mode)
            MODE="$2"
            shift 2
            ;;
        --device)
            EMMC_DEV="$2"
            shift 2
            ;;
        --ssh-key)
            SSH_KEY_FILE="$2"
            shift 2
            ;;
        --generic-image)
            GENERIC_IMAGE=true
            shift
            ;;
        --karg)
            EXTRA_KARGS+=("$2")
            shift 2
            ;;
        --yes)
            ASSUME_YES=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "ERROR: Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            IMAGE_REF="$1"
            shift
            ;;
    esac
done

case "$MODE" in
    auto|to-disk|to-existing-root) ;;
    *)
        echo "ERROR: Invalid --mode '$MODE' (expected auto, to-disk, or to-existing-root)." >&2
        exit 1
        ;;
esac

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Must run as root (sudo)." >&2
    exit 1
fi

if ! command -v podman >/dev/null 2>&1; then
    echo "ERROR: podman is required to run bootc installation." >&2
    exit 1
fi

if [ -n "$SSH_KEY_FILE" ] && [ ! -r "$SSH_KEY_FILE" ]; then
    echo "ERROR: SSH key file not readable: $SSH_KEY_FILE" >&2
    exit 1
fi

# 1. Identify internal eMMC via hardware boot0 partition unless explicitly provided
if [ -z "$EMMC_DEV" ]; then
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
fi

if [ -z "$EMMC_DEV" ] || [ ! -b "$EMMC_DEV" ]; then
    echo "ERROR: Could not uniquely identify internal eMMC (with boot0 partition)." >&2
    exit 1
fi

EMMC_REAL="$(readlink -f "$EMMC_DEV")"

# 2. Safety checks: ensure EMMC_DEV NEVER matches or contains the user's microSD UUID
if blkid "${EMMC_REAL}"* 2>/dev/null | grep -qi "$SDCARD_UUID"; then
    echo "CRITICAL ABORT: Target device $EMMC_REAL matches microSD UUID $SDCARD_UUID!" >&2
    exit 1
fi

if [ -e "/dev/disk/by-uuid/${SDCARD_UUID}" ]; then
    SDCARD_REAL="$(readlink -f "/dev/disk/by-uuid/${SDCARD_UUID}")"
    case "$SDCARD_REAL" in
        "${EMMC_REAL}"*)
            echo "CRITICAL ABORT: MicroSD UUID $SDCARD_UUID resolves inside target $EMMC_REAL ($SDCARD_REAL)!" >&2
            exit 1
            ;;
    esac
fi

echo "Verified internal eMMC target: $EMMC_REAL (size: $(lsblk -dn -o SIZE "$EMMC_REAL"))"
echo "MicroSD card ($SDCARD_UUID) is protected and will remain untouched."

# 3. Choose safe install mode automatically based on whether / lives on EMMC_REAL
ROOT_SRC="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
ROOT_SRC="${ROOT_SRC%%[*}"
ROOT_REAL=""
if [ -n "$ROOT_SRC" ] && [ -e "$ROOT_SRC" ]; then
    ROOT_REAL="$(readlink -f "$ROOT_SRC")"
fi

if [ "$MODE" = "auto" ]; then
    case "$ROOT_REAL" in
        "${EMMC_REAL}"*)
            MODE="to-existing-root"
            ;;
        *)
            MODE="to-disk"
            ;;
    esac
fi

echo "Selected installation mode: $MODE (current root: ${ROOT_REAL:-unknown})"

# 4. Back up live Wi-Fi NVRAM EFI variable if present on host before deployment
mkdir -p /var/lib/t100tas
if compgen -G "/sys/firmware/efi/efivars/nvram-*" >/dev/null; then
    for nv in /sys/firmware/efi/efivars/nvram-*; do
        # Strip 4-byte EFI variable attributes header
        dd if="$nv" of=/var/lib/t100tas/efi-nvram.txt bs=1 skip=4 2>/dev/null || true
        break
    done
    echo "Backed up EFI Wi-Fi NVRAM variable to /var/lib/t100tas/efi-nvram.txt"
fi

if [ "$ASSUME_YES" != true ]; then
    echo
    echo "WARNING: This will deploy $IMAGE_REF onto $EMMC_REAL using bootc install $MODE."
    if [ "$MODE" = "to-disk" ]; then
        echo "ALL EXISTING DATA ON $EMMC_REAL WILL BE WIPED (microSD $SDCARD_UUID stays untouched)."
    else
        echo "/boot bootloader state on $EMMC_REAL will be replaced alongside existing root."
    fi
    read -r -p "Type 'INSTALL' to continue: " confirm
    if [ "$confirm" != "INSTALL" ]; then
        echo "Aborted by user."
        exit 1
    fi
fi

if ! podman image exists "$IMAGE_REF"; then
    echo "Pulling $IMAGE_REF..."
    podman pull "$IMAGE_REF"
fi

BOOTC_ARGS=("--target-imgref=${IMAGE_REF}")
if [ ! -d /sys/fs/selinux ]; then
    echo "Host lacks active /sys/fs/selinux; passing --disable-selinux to bootc install."
    BOOTC_ARGS+=("--disable-selinux")
fi
if [ "$GENERIC_IMAGE" = true ]; then
    BOOTC_ARGS+=("--generic-image")
fi
for karg in "${EXTRA_KARGS[@]}"; do
    BOOTC_ARGS+=("--karg=${karg}")
done

PODMAN_ARGS=(
    --rm
    --privileged
    --pid=host
    --ipc=host
    --security-opt label=type:unconfined_t
    -v /dev:/dev
    -v /var/lib/containers:/var/lib/containers
)

if [ -n "$SSH_KEY_FILE" ]; then
    PODMAN_ARGS+=(-v "${SSH_KEY_FILE}:/tmp/t100-root-authorized-keys:ro")
    BOOTC_ARGS+=("--root-ssh-authorized-keys=/tmp/t100-root-authorized-keys")
fi

if [ "$MODE" = "to-disk" ]; then
    echo "Running bootc install to-disk --filesystem=btrfs --wipe on $EMMC_REAL..."
    podman run "${PODMAN_ARGS[@]}" "$IMAGE_REF" \
        bootc install to-disk --filesystem=btrfs --wipe "${BOOTC_ARGS[@]}" "$EMMC_REAL"
else
    echo "Running bootc install to-existing-root on host root ($ROOT_REAL)..."
    PODMAN_ARGS+=(-v /:/target)
    podman run "${PODMAN_ARGS[@]}" "$IMAGE_REF" \
        bootc install to-existing-root --cleanup --acknowledge-destructive "${BOOTC_ARGS[@]}" /target
fi

# 5. Guarantee 32-bit IA32 UEFI files and GRUB text console safety on target ESP + /boot
TMP_ESP=""
TMP_BOOT=""
cleanup() {
    if [ -n "$TMP_ESP" ] && mountpoint -q "$TMP_ESP"; then
        umount "$TMP_ESP" || true
    fi
    if [ -n "$TMP_BOOT" ] && mountpoint -q "$TMP_BOOT"; then
        umount "$TMP_BOOT" || true
    fi
    rmdir "${TMP_ESP:-/nonexistent}" "${TMP_BOOT:-/nonexistent}" 2>/dev/null || true
}
trap cleanup EXIT

partprobe "$EMMC_REAL" 2>/dev/null || udevadm settle 2>/dev/null || true

ESP_PART="$(lsblk -nr -o PATH,PARTTYPE "$EMMC_REAL" | awk '{
    pt = tolower($2)
    if (pt == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" || pt == "0xef") { print $1; exit }
}')"
BOOT_PART="$(lsblk -nr -o PATH,LABEL "$EMMC_REAL" | awk '$2 == "boot" { print $1; exit }')"
if [ -z "$BOOT_PART" ] && [ "$MODE" = "to-existing-root" ] && mountpoint -q /boot; then
    BOOT_PART="$(findmnt -nr -o SOURCE /boot 2>/dev/null || true)"
    BOOT_PART="${BOOT_PART%%[*}"
fi

BOOT_UUID=""
if [ -n "$BOOT_PART" ] && [ -b "$BOOT_PART" ]; then
    BOOT_UUID="$(blkid -s UUID -o value "$BOOT_PART" 2>/dev/null || true)"
    BOOT_MNT="$(findmnt -nr -o TARGET "$BOOT_PART" | head -n 1 || true)"
    if [ -z "$BOOT_MNT" ]; then
        TMP_BOOT="$(mktemp -d /tmp/t100tas-boot.XXXXXX)"
        mount "$BOOT_PART" "$TMP_BOOT"
        BOOT_MNT="$TMP_BOOT"
    fi
    for gdir in "$BOOT_MNT/grub2" "$BOOT_MNT/boot/grub2"; do
        if [ -d "$gdir" ]; then
            printf 'terminal_output console\n' > "${gdir}/console.cfg"
            echo "Wrote GRUB text-console guard: ${gdir}/console.cfg"
        fi
    done
elif [ "$MODE" = "to-existing-root" ] && [ -n "$ROOT_REAL" ] && [ -b "$ROOT_REAL" ]; then
    BOOT_UUID="$(blkid -s UUID -o value "$ROOT_REAL" 2>/dev/null || true)"
    if [ -d /boot/grub2 ]; then
        printf 'terminal_output console\n' > /boot/grub2/console.cfg
        echo "Wrote GRUB text-console guard: /boot/grub2/console.cfg"
    fi
fi

if [ -n "$ESP_PART" ] && [ -b "$ESP_PART" ]; then
    ESP_MNT="$(findmnt -nr -o TARGET "$ESP_PART" | head -n 1 || true)"
    if [ -z "$ESP_MNT" ]; then
        TMP_ESP="$(mktemp -d /tmp/t100tas-esp.XXXXXX)"
        mount "$ESP_PART" "$TMP_ESP"
        ESP_MNT="$TMP_ESP"
    fi

    echo "Verifying 32-bit IA32 EFI payload on ESP ($ESP_PART mounted at $ESP_MNT)..."
    podman run --rm -e "BOOT_UUID=${BOOT_UUID}" -v "${ESP_MNT}:/esp" "$IMAGE_REF" bash -ec '
        mkdir -p /esp/EFI/BOOT /esp/EFI/fedora
        ensure_copy() {
            local src="$1" dst="$2"
            if [ -f "$src" ] && ! cmp -s "$src" "$dst" 2>/dev/null; then
                cp -f "$src" "$dst"
                echo "Synced IA32 EFI asset: $dst"
            fi
        }
        shopt -s nullglob
        for f in /usr/lib/efi/shim/*/EFI/BOOT/BOOTIA32.EFI; do ensure_copy "$f" /esp/EFI/BOOT/BOOTIA32.EFI; done
        for f in /usr/lib/efi/shim/*/EFI/BOOT/fbia32.efi; do ensure_copy "$f" /esp/EFI/BOOT/fbia32.efi; done
        for f in /usr/lib/efi/shim/*/EFI/fedora/shimia32.efi; do ensure_copy "$f" /esp/EFI/fedora/shimia32.efi; done
        for f in /usr/lib/efi/shim/*/EFI/fedora/mmia32.efi; do ensure_copy "$f" /esp/EFI/fedora/mmia32.efi; done
        for f in /usr/lib/efi/shim/*/EFI/fedora/BOOTIA32.CSV; do ensure_copy "$f" /esp/EFI/fedora/BOOTIA32.CSV; done
        for f in /usr/lib/efi/grub2/*/EFI/fedora/grubia32.efi; do ensure_copy "$f" /esp/EFI/fedora/grubia32.efi; done
        for f in /usr/lib/efi/grub2/*/EFI/fedora/gcdia32.efi; do ensure_copy "$f" /esp/EFI/fedora/gcdia32.efi; done
        if [ ! -f /esp/EFI/fedora/grub.cfg ] && [ -f /usr/lib/bootupd/grub2-static/grub-static-efi.cfg ]; then
            cp -f /usr/lib/bootupd/grub2-static/grub-static-efi.cfg /esp/EFI/fedora/grub.cfg
            echo "Installed /esp/EFI/fedora/grub.cfg"
        fi
        if [ -n "${BOOT_UUID:-}" ] && [ ! -f /esp/EFI/fedora/bootuuid.cfg ]; then
            printf "set BOOT_UUID=\"%s\"\n" "$BOOT_UUID" > /esp/EFI/fedora/bootuuid.cfg
            echo "Installed /esp/EFI/fedora/bootuuid.cfg"
        fi
    '

    # bootupd on x86_64 hardcodes \EFI\fedora\shimx64.efi in efibootmgr even when
    # fw_platform_size=32. Replace any shimx64.efi NVRAM entry with shimia32.efi.
    if [ -r /sys/firmware/efi/fw_platform_size ] \
        && [ "$(cat /sys/firmware/efi/fw_platform_size 2>/dev/null || true)" = "32" ] \
        && [ -f "${ESP_MNT}/EFI/fedora/shimia32.efi" ] \
        && command -v efibootmgr >/dev/null 2>&1 \
        && { [ "$MODE" = "to-existing-root" ] || efibootmgr -v 2>/dev/null | grep -qi 'shimx64\.efi'; }; then
        ESP_REAL="$(readlink -f "$ESP_PART")"
        ESP_PARTNUM="$(cat "/sys/class/block/$(basename "$ESP_REAL")/partition" 2>/dev/null || true)"
        if [ -n "$ESP_PARTNUM" ] && [ -b "$EMMC_REAL" ]; then
            while IFS= read -r bootnum; do
                [ -n "$bootnum" ] || continue
                efibootmgr -b "$bootnum" -B >/dev/null 2>&1 || true
            done < <(efibootmgr -v 2>/dev/null | grep -iE 'shimx64\.efi|TransformerOS' | sed -nE 's/^Boot([0-9A-Fa-f]{4}).*/\1/p')
            efibootmgr --create --disk "$EMMC_REAL" --part "$ESP_PARTNUM" --loader '\EFI\fedora\shimia32.efi' --label 'TransformerOS' >/dev/null
            echo "Configured 32-bit IA32 EFI NVRAM boot entry: TransformerOS (\\EFI\\fedora\\shimia32.efi)"
        fi
    fi

    if [ -n "${TMP_ESP:-}" ]; then
        umount "$TMP_ESP" 2>/dev/null || true
        rmdir "$TMP_ESP" 2>/dev/null || true
    fi
else
    echo "WARNING: Could not find EFI System Partition on $EMMC_REAL for IA32 post-check." >&2
fi

sync
echo "TransformerOS deployment complete. Reboot when ready."
