# TransformerOS: Installation, Updates & Recovery Guide (ASUS T100TAS)

## 1. Storage & Hardware Safety Rules

1. **MicroSD Card Protection (`UUID=50e09466-61d9-4b04-9445-161548f62afc`)**:
   - The ASUS T100TAS has two asynchronous MMC controllers:
     - `80860F14:00`: Internal `29.1 GB` eMMC (identifiable by its hardware `/dev/mmcblk*boot0` and `/dev/mmcblk*boot1` partitions).
     - `80860F14:01`: Removable `7.6 GB` microSD card (`EXTRA`, `UUID=50e09466-61d9-4b04-9445-161548f62afc`).
   - Because Linux dynamically numbers these `/dev/mmcblk1` and `/dev/mmcblk2` across boots, **never reference `/dev/mmcblk1` or `/dev/mmcblk2` directly in `/etc/fstab` or kernel arguments**.
   - [scripts/install-to-t100tas.sh](file:///mnt/Data/AI_Projects/TransformerOS/scripts/install-to-t100tas.sh) verifies the `/sys/block/${dev}boot0` hardware partition AND aborts if `UUID=50e09466-61d9-4b04-9445-161548f62afc` is present on the target device.

2. **32-bit IA32 UEFI Bootloader (`T100TAS.207` Firmware)**:
   - Even though the `Intel Atom Z3775` CPU and OS are 64-bit (`x86_64`), the UEFI firmware is 32-bit (`fw_platform_size = 32`).
   - `TransformerOS` ships `shim-ia32` (`BOOTIA32.EFI`, `shimia32.efi`), `grub2-efi-ia32` (`grubia32.efi`), and the standalone [bootia32.efi](file:///mnt/Data/AI_Projects/TransformerOS/bootia32.efi) binary in `/usr/share/transformeros/boot/bootia32.efi`.

---

## 2. Installing TransformerOS

### Option A: Direct Install from the Existing Linux System on the Tablet
1. Ensure the tablet is connected to Wi-Fi and plugged into AC power.
2. Run the pre-flight installer check as `root`:
   ```bash
   sudo ./scripts/install-to-t100tas.sh ghcr.io/piernik-cpu/transformeros:stable
   ```
3. Deploy the container image onto the internal eMMC root using `bootc install to-existing-root` (or from a live USB using `bootc install to-disk --via-loopback`).

### Option B: Live USB Installation
1. Flash any 64-bit Fedora Live USB (GPT + FAT32 EFI System Partition).
2. Copy [bootia32.efi](file:///mnt/Data/AI_Projects/TransformerOS/bootia32.efi) to `EFI/BOOT/bootia32.efi` on the USB stick's EFI partition.
3. Boot the T100TAS holding `ESC` and select the USB stick (`Secure Boot` disabled in `F2` BIOS Setup).
4. Run `scripts/install-to-t100tas.sh` to deploy `ghcr.io/piernik-cpu/transformeros:stable` to the internal eMMC.

---

## 3. One-Tap Updates & Rollback

### Updating
- **Automatic Staging:** `transformeros-auto-update.timer` checks `ghcr.io/piernik-cpu/transformeros:stable` daily while on AC power (and not in Game Mode) and stages updates in the background without rebooting.
- **One-Tap Update:** Tap `⚙ Quick` in the top-right bar (or on the bottom Android bar in Tablet Mode) and tap **`↻ One-Tap Update`**. Once staged, reboot at your convenience.

### Rolling Back
- **From the Desktop / Tablet UI:** Open Quick Settings (`⚙ Quick`) and tap **`⏪ Roll Back`**, then reboot.
- **From the Boot Menu (GRUB):** At power-on, select the second `ostree:1` deployment entry in the GRUB menu to boot the previous known-good snapshot immediately.
