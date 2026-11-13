# ASUS Transformer Book T100TAS (`T100TASIAN`) — Remote Control Handoff & TransformerOS Dossier

Prepared on **2026-11-13** for a more powerful PC connecting via **Antigravity Remote Control**.

---

## Live Status Snapshot (Post-Reboot Verified)

Before disconnecting or building `TransformerOS`, note that the machine **successfully rebooted into the new `labwc` Wayland stack around 20:31 CET** (observed alive at `uptime: 749.04s`):

| Metric / State | Pre-Fix Baseline (`19:07` / `20:20` KDE Plasma 6) | Post-Reboot Live State (`20:43` `labwc:wlroots`) |
| --- | --- | --- |
| Desktop / Session | `sddm` + `kwin_wayland` + `plasmashell` (`X11`/`Wayland` mix, `Xorg` running) | `greetd` (`vt = 7`) + `tuigreet` -> `labwc 0.8.3-1` (`XDG_CURRENT_DESKTOP=labwc:wlroots`, `XDG_SESSION_TYPE=wayland`) |
| Kernel Cmdline | Stock GRUB (full CPU mitigations + `zswap`) | `BOOT_IMAGE=/boot/vmlinuz-6.12.113+deb13-amd64 root=UUID=71f8d441-a98a-405b-a221-e8ae4c32437a ro quiet mitigations=off zswap.enabled=0` |
| Memory Available | Heavily pressured (~`1.8Gi` total RAM) | `1,8Gi` total / `1,1Gi` used / `98Mi` free / `930Mi` buff+cache / **`692Mi` available** |
| Swap Usage | **`676.1M` used** (at `20:20` under Plasma fallback) | **`129Mi` used** (`3,8Gi` total: `2.3G` `zstd` `zram0` @ prio `100` + `1.5G` disk swap @ prio `-2`) |
| ZRAM Compression | Smaller ZRAM | `zram0` `mm_stat`: `142,172,160 B` uncompressed -> `28,742,802 B` / `30,732,288 B` physical (`PERCENT=125`, `ALGO=zstd`) |
| Root Filesystem (`/`, `26.7G` eMMC) | **`423M` free** (`25G` used, `99%`) | **`3,4G` free** (`22G` used, `87%`, reported after `02-polish-system.sh`) |

---

## Files in This Workspace (`/home/piergi/Scaricati/Antigravity-x64/Projects/TransformerOS`)

1. **[README.md](file:///home/piergi/Scaricati/Antigravity-x64/Projects/TransformerOS/README.md)** — Executive summary, live post-reboot status, design constraints for `TransformerOS`, and next-step options.
2. **[HARDWARE_PROFILE.md](file:///home/piergi/Scaricati/Antigravity-x64/Projects/TransformerOS/HARDWARE_PROFILE.md)** — Full DMI, 32-bit IA32 UEFI, Bay Trail `Atom Z3775` CPU/C-states/vulnerabilities/thermals, `1.81 GiB` RAM, eMMC + microSD UUIDs & dynamic `mmcblk` numbering warning, PCI/DRM/USB/SDIO/Audio/IIO sensors/Input/Battery inventory, and firmware/dmesg quirks.
3. **[DEBIAN_SYSTEM_AND_CHANGES.md](file:///home/piergi/Scaricati/Antigravity-x64/Projects/TransformerOS/DEBIAN_SYSTEM_AND_CHANGES.md)** — Initial Debian 13 (`trixie`) + Plasma bottlenecks, all changes applied by `PC_fixes/{01,02,03,04}`, purged vs preserved software, live system & user configs, and pending optional cleanups.
4. **[system-snapshot.json](file:///home/piergi/Scaricati/Antigravity-x64/Projects/TransformerOS/system-snapshot.json)** — Machine-readable snapshot (IDs, UUIDs, sysfs paths, driver modules, kernel cmdline, storage/memory metrics, and build requirements) for automated tooling on the powerful PC.

Related prior workspace (scripts & backups from `2026-11-13 19:07–20:30`):
- `/home/piergi/Scaricati/Antigravity-x64/Projects/PC_fixes/` (`01-system-cleanup-and-wayland.sh`, `02-polish-system.sh`, `03-user-tuning-and-scripts.sh`, `04-fix-greetd.sh`, and `backups/`).
- Source conversation brain dir: `/home/piergi/.gemini/antigravity/brain/3f34ec06-4f89-4581-98e4-8e69caf271da`.

---

## Critical Constraints for Building `TransformerOS` on the Powerful PC

1. **32-bit IA32 UEFI + 64-bit `x86_64` OS/Kernel**:
   `/sys/firmware/efi/fw_platform_size` is `32` (`T100TAS.207` BIOS, `05/14/2014`). Any bootable image, ISO, or custom distro **must include a 32-bit IA32 EFI bootloader (`BOOTIA32.EFI` / `grub-efi-ia32` + `shim-signed`)** even though the kernel and userspace are `x86_64`. Standard `amd64`-only `BOOTX64.EFI` images will not boot.
2. **Dynamic `mmcblk1` vs `mmcblk2` Probe Order**:
   MMC hosts `80860F14:00` (internal `29.1G` eMMC) and `80860F14:01` (`7.6G` microSD) swap Linux device numbers depending on kernel probe order (`19:07`/`20:20` had eMMC = `mmcblk2`, microSD = `mmcblk1`; `20:31` boot has eMMC = `mmcblk1`, microSD = `mmcblk2`). **Always bind mounts, crypttab, swap, and bootloader roots by `UUID=` or `PARTUUID=`**, never `/dev/mmcblk{1,2}`. (Note: `/etc/tmpfiles.d/t100tas-tuning.conf` intentionally tunes both `mmcblk1` and `mmcblk2` identically.)
3. **1.81 GiB (`1903176 kB`) Hard RAM Ceiling + Storage Budget (`29.1G` eMMC)**:
   - Soldered single-channel RAM cannot be upgraded; ZRAM (`zstd`, `PERCENT=125`, `vm.swappiness=150`, `vm.page-cluster=0`, `zswap.enabled=0`) + `earlyoom` + single lightweight Wayland compositor (`labwc` + `waybar` + `foot` + `fuzzel`) is essential.
   - `glibc` + `i386` multiarch support is needed if retaining compatibility with Steam, Wine/umu, or Electron binaries like Antigravity (`495M` in `~/Scaricati/Antigravity-x64`).
4. **Bay Trail Hardware & Firmware Specifics**:
   - **GPU**: `Intel HD Graphics (BYT)` (`8086:0f31`) uses `i915` and **`i965-va-driver`** (do *not* use `intel-media-va-driver`).
   - **Audio**: `bytcr-rt5640` SST (`snd_soc_sst_bytcr_rt5640`) + `Intel HDMI/DP LPE Audio`; PipeWire + WirePlumber works cleanly.
   - **Wi-Fi / BT**: Broadcom SDIO `02D0:4324` (`brcmfmac`, `brcmfmac_wcc`, `firmware-brcm80211` providing `brcmfmac43241b4-sdio.bin`) + `hci_uart` (`wlan0` MAC `54:a0:50:3a:fc:46`).
   - **Touch, Sensors, Dock**: `SIS0817:00 0457:1071` I2C touchscreen; IIO ambient light (`CPLM3218`), accel/gyro (`INVN6500`), magnetometer (`AK8963` via `ak8975`); `0b05:17e0` USB keyboard/touchpad base station dock (keep `usb1/power/control=on` for dock hotplug detection).
   - **Suspend & Idle**: Only `[s2idle]` is supported in `/sys/power/mem_sleep`. `C6N`/`C6S`/`C7`/`C7S` cpuidle states are all enabled (`disable=0`) and functioning cleanly alongside `intel_cpufreq` (`passive` / `schedutil`).
   - **Microcode Blacklist**: Keep `/etc/modprobe.d/intel-microcode-blacklist.conf` (`blacklist microcode`, `0x838` currently loaded) awareness if rebuilding Debian initramfs/kernel packages.

---

## Pending / Optional Next Actions

1. **Reclaim remaining eMMC space on this Debian install (once finished testing `labwc`)**:
   - KDE Plasma (`kde-plasma-desktop`, `plasma-desktop`, `sddm`) was intentionally kept as a safety fallback. Purging Plasma + SDDM (while verifying `grub`, `NetworkManager`, `pipewire`, `greetd`, `labwc`, `qt5`/`qt6` deps for kept apps remain intact) will free significant additional space on the `26.7G` `/` partition.
   - Audit heavy user storage if needed: `~/.var/app` (`5.6G`, of which Steam is `5.2G`), `~/.local/share/flatpak` (`2.5G`), `~/.local/share/umu/steamrt3` (`778M`), `~/.cache` (`547M`), `/home/piergi/Scaricati/Antigravity-x64` (`495M`), `~/.gemini/antigravity` (`248M`).
2. **Build custom `TransformerOS` on the powerful PC**:
   - Strongest architectural fits identified in prior analysis: minimal stripped Debian `debootstrap` / live-build image, or Void Linux (`glibc` + `runit`, keeping `32`-bit UEFI + Bay Trail firmware + `labwc` user configs from this system), optionally paired with a `CONFIG_MSIC` / Silvermont (`-march=silvermont`) tuned kernel.
