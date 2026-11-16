# TransformerOS — Fedora 45 Atomic (`bootc`) OS for ASUS Transformer Book T100TAS

**TransformerOS** is a custom, atomic, image-based operating system built on **Fedora 45 (`bootc`)** specifically engineered for the **ASUS Transformer Book T100TAS** (`Intel Atom Z3775` Bay Trail, `1.81 GiB` soldered RAM, `29.1 GB` eMMC, `32-bit IA32 UEFI`, `SIS0817` I2C touchscreen, `INVN6500` accelerometer, `CPLM3218` ambient light sensor, and `0b05:17e0` detachable keyboard dock).

---

## Key Features

1. **Full 32-bit IA32 UEFI + 64-bit `x86_64` Atomic Boot Stack**:
   - Ships `shim-ia32`, `grub2-efi-ia32`, and standalone `bootia32.efi` managed via `bootupd`.
   - Preloads `mmc_core`, `mmc_block`, `sdhci`, `sdhci_acpi`, `gpio_crystalcove`, `intel_soc_pmic_crc`, `pwm_lpss`, and `i915` in `dracut` initramfs so the internal eMMC root is always discovered regardless of asynchronous probe order (`mmcblk0`/`1`/`2`).
2. **Complete Bay Trail Hardware & Firmware Support**:
   - **Wi-Fi & Bluetooth (`02D0:4324` SDIO)**: Bundles `BCM4324B3.hcd` Bluetooth patch firmware and board-specific `brcmfmac43241b4-sdio.txt` (`brcmfmac43241b4-sdio.ASUSTeK COMPUTER INC.-T100TAS.txt`) with Wi-Fi powersave disabled for rock-solid connectivity.
   - **Audio (`bytcr-rt5640` + HDMI LPE)**: PipeWire + WirePlumber + ALSA UCM + `snd_sof sof_debug=1` safeguard against video playback audio freezes.
   - **Graphics (`Intel HD Graphics BYT 0xf31`)**: Mesa GLES 3.0 + `i965` VA-API hardware video decoding.
   - **Memory & Storage Tuning (`1.81 GiB` RAM)**: `125%` `zstd` ZRAM (`swap-priority=100`, `vm.swappiness=150`, `vm.page-cluster=0`, `zswap.enabled=0`), `earlyoom`, THP `madvise`, and `mq-deadline` tuning for both eMMC and microSD.
3. **`transformerd` — Ultra-Light Rust Hardware & Mode Daemon (~1.5 MB RAM)**:
   - Monitors the ASUS Base Station dock (`0b05:17e0`) and physical keyboard hotplug.
   - **Docked (Laptop Mode)**: Classic resizable desktop windows with title bars, landscape orientation, physical keyboard/touchpad focus.
   - **Undocked (Tablet Mode)**: Automatically maximizes all windows borderlessly (`rc-tablet.xml`), activates the **Android-style Bottom Navigation Bar** (`◀ Back` · `● Home` · `■ Recents` · `⌨ Keyboard` · `⚙ Quick Settings`), enables accelerometer **auto-rotation** (`INVN6500`), and readies the on-screen touch keyboard (`wvkbd-mobintl`).
   - **Ambient Light Auto-Brightness**: Reads `CPLM3218` IIO illuminance sensor with exponential moving average (EMA) smoothing.
   - **Automatic Power Profiles & Calibrated Battery**: Switches between `performance` (AC / Game Mode), `balanced` (Battery > 20%), and `power-saver` (Battery ≤ 20%), while calibrating for the T100TAS `CHARGE_FULL` ACPI quirk.
   - **One-Tap Game Mode**: Boosts CPU/GPU profile and pauses background update checks & auto-brightness.
4. **Adaptive Dock-Aware Login & Lock Screen (`transformer-greeter`)**:
   - Speaks native `greetd` IPC.
   - Displays a classic keyboard-driven password prompt when docked, and automatically expands an integrated touch keypad when undocked.
5. **Unified Package Manager (`transformer-store`) & Mutable `dnf5` Support**:
   - Supports **Fedora 45 RPM packages (`dnf5`)**, **Flatpaks (`Flathub`)**, and **AppImages** (`~/Applications` + automatic `.desktop` & icon integration) in a single lightweight GTK4 UI.
   - Unlocks `/usr` with a deployment-scoped disk-backed overlay (`transformeros-usr-unlock.service`) and configures `dnf5` so `sudo dnf install <pkg>` works out of the box without `bootc` read-only errors.
6. **Simple One-Tap Updates & Instant Rollback**:
   - Powered by `bootc` + GitHub Container Registry (`ghcr.io/piernik-cpu/transformeros:stable`).
   - Background updates are staged automatically without unexpected reboots; previous deployment stays selectable in the boot menu (or via the **Roll Back** button in Quick Settings).

---

## Repository Structure

```text
TransformerOS/
├── Containerfile                 # Multi-stage Fedora 45 bootc build (Rust transformerd + wvkbd + OS)
├── Justfile                      # Build, verify, and QEMU IA32 UEFI test commands
├── .github/workflows/build.yml   # CI/CD: builds & publishes to GHCR on push and weekly schedule
├── transformerd/                 # Rust hardware, dock/tablet mode, sensor, power & update daemon
├── shell/                        # Quickshell adaptive shell, greeter, lock screen, store & labwc configs
├── system/                       # System-level configs (/usr/lib/dracut, kargs.d, sysctl.d, tmpfiles.d, udev)
├── firmware/brcm/                # BCM4324B3.hcd & brcmfmac43241b4-sdio.txt
├── scripts/                      # T100TAS installer (microSD-safe) & live hotfix sync script
├── docs/                         # Architecture, installation, and recovery documentation
└── tests/                        # QEMU Silvermont / 32-bit IA32 UEFI boot verification
```
