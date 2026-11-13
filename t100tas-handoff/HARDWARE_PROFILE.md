# Complete Hardware Profile — ASUS Transformer Book T100TAS

Observed directly from live sysfs, procfs, `lscpu`, `lspci`, `lsusb`, ALSA/PipeWire, D-Bus `net.hadess.SensorProxy`, and kernel diagnostics across `2026-11-13` (`3f34ec06` audit + post-reboot verification at `20:43:45 CET`).

---

## 1. Identity, Firmware & Boot Architecture

| Property | Exact Observed Value |
| --- | --- |
| Hostname (`/etc/hostname`) | `T100TASIAN` |
| DMI `sys_vendor` | `ASUSTeK COMPUTER INC.` |
| DMI `product_name` | `T100TAS` |
| DMI `product_version` | `1.0` |
| BIOS Version / Date | `T100TAS.207` (`05/14/2014`) |
| UEFI Platform Width | `/sys/firmware/efi/fw_platform_size` = **`32`** (IA32 32-bit UEFI firmware) |
| Bootloader Stack | `grub-efi-ia32` + `shim-signed` booting 64-bit `amd64` Linux kernel |
| Sleep States (`/sys/power/mem_sleep`) | `[s2idle]` (S3 deep sleep not available) |
| Current Live Kernel | `Linux 6.12.113+deb13-amd64 #1 SMP PREEMPT_DYNAMIC Debian 6.12.113-1 (2026-10-15) x86_64` |
| Current Boot Cmdline (`/proc/cmdline`) | `BOOT_IMAGE=/boot/vmlinuz-6.12.113+deb13-amd64 root=UUID=71f8d441-a98a-405b-a221-e8ae4c32437a ro quiet mitigations=off zswap.enabled=0` |

---

## 2. CPU, Frequency Scaling, Idle States, Vulnerabilities & Thermals

### CPU (`lscpu` & `/proc/cpuinfo`)
- **Model**: `Intel(R) Atom(TM) CPU  Z3775  @ 1.46GHz` (`GenuineIntel`, Bay Trail / Silvermont)
- **IDs**: CPU family `6`, Model `55`, Stepping `8`
- **Topology**: `4` cores / `4` threads, `1` socket, `1` NUMA node
- **Address Sizes**: `36 bits physical, 48 bits virtual`
- **Clocks**: Min `533.2000 MHz` — Max `2399.3999 MHz` (`BogoMIPS: 2933.33`)
- **Caches**: `L1d: 96 KiB (4 instances)`, `L1i: 128 KiB (4 instances)`, `L2: 2 MiB (2 instances)`
- **Virtualization**: `VT-x` (`ept`, `vpid`, `unrestricted_guest`)
- **Microcode**: `0x838` (Note: package `intel-microcode 3.20251111.1~deb13u1` is installed, with `/etc/modprobe.d/intel-microcode-blacklist.conf` containing `blacklist microcode`)

### Scaling & Idle States
- `scaling_driver`: `intel_cpufreq` (`intel_pstate/status` = `passive`)
- `intel_pstate`: `no_turbo=0`, `max_perf_pct=100`, `min_perf_pct=22`
- Available governors: `performance`, `schedutil` (active: `schedutil`)
- `energy_perf_bias`: `0` (also `power-profiles-daemon` configured to `performance`)
- `cpuidle` states (`disable=0` on all):
  - `state0`: `POLL` (latency `0`)
  - `state1`: `C1` (latency `1`)
  - `state2`: `C6N` (latency `300`)
  - `state3`: `C6S` (latency `500`)
  - `state4`: `C7` (latency `1200`)
  - `state5`: `C7S` (latency `10000`)

### CPU Vulnerabilities (Stock Baseline Before `mitigations=off`)
- `/proc/cpuinfo` `bugs`: `cpu_meltdown spectre_v1 spectre_v2 mds msbds_only mmio_unknown`
- Active mitigations before `mitigations=off`:
  - `Mds`: `Mitigation: Clear CPU buffers; SMT disabled`
  - `Meltdown`: `Mitigation: PTI`
  - `Spectre v1`: `Mitigation: usercopy/swapgs barriers and __user pointer sanitization`
  - `Spectre v2`: `Mitigation: Retpolines; IBPB conditional; IBRS_FW; STIBP disabled; RSB filling`
- Other entries:
  - `Mmio stale data`: `Unknown: No mitigations`
  - `Not affected`: `Gather data sampling`, `Indirect target selection`, `Itlb multihit`, `L1tf`, `Reg file data sampling`, `Retbleed`, `Spec rstack overflow`, `Spec store bypass`, `Srbds`, `Tsa`, `Tsx async abort`, `Vmscape`
- Current boot disables runtime mitigations via `mitigations=off` in `/etc/default/grub.d/99-t100tas.cfg`.

### Thermal Zones (`/sys/class/thermal/thermal_zone*`)
- `thermal_zone0` (`acpitz`): `0` m°C
- `thermal_zone1` (`INT3400 Thermal`): `20000` m°C (`20.0 °C`)
- `thermal_zone2..4` (`STR0`, `STR1`, `STR2`): `-273150` m°C (unwired/placeholder sensors)
- `thermal_zone5` (`TCPU`): `50000`–`53000` m°C (`50.0`–`53.0 °C`)
- `thermal_zone6` (`soc_dts0`): `44000`–`47000` m°C (`44.0`–`47.0 °C`)
- `thermal_zone7` (`soc_dts1`): `45000`–`49000` m°C (`45.0`–`49.0 °C`)

---

## 3. Memory, ZRAM & Swap

- **Physical RAM**: `MemTotal: 1903176 kB` (`1.8Gi` / `1.81 GiB` usable, soldered)
- **THP Settings** (`/etc/tmpfiles.d/t100tas-tuning.conf`):
  - `/sys/kernel/mm/transparent_hugepage/enabled` -> `always [madvise] never`
  - `/sys/kernel/mm/transparent_hugepage/defrag` -> `always defer [defer+madvise] madvise never`
- **ZRAM** (`/dev/zram0`):
  - Configured via `/etc/default/zramswap`: `ALGO=zstd`, `PERCENT=125`, `PRIORITY=100`
  - Available algos: `lz4 lz4hc [zstd] deflate`
  - Logical size: `2.3G` (`2378964` KiB)
  - Live `mm_stat` at `20:43`: `142172160` B uncompressed (~`135.6 MiB`) -> `28742802` / `30732288` B physical (~`29.3 MiB`)
- **Disk Swap Partition**: `1.5G` (`1582076` KiB), Priority `-2`, `UUID=59f9aa15-681e-4860-9f5f-b643801b3cde`
- **Kernel Swap Stack**: `zswap.enabled=0` (avoids double compression with ZRAM)

---

## 4. Storage, Partitions & Dynamic MMC Device Numbering

> **WARNING — Dynamic `mmcblk` numbering across boots:**
> Two MMC controllers probe asynchronously:
> - `80860F14:00`: Internal `29.1G` eMMC (`+ mmcblk*boot0` & `mmcblk*boot1` 4M each, `rotational=0`, `discard_max_bytes=16753623040`, scheduler `[mq-deadline]`, `nr_requests=64`, `read_ahead_kb=256`, `life_time: 0x00 0x00`, `pre_eol_info: 0x00`).
> - `80860F14:01`: Removable `7.6G` microSD (`rotational=0`, scheduler `[mq-deadline]`, `nr_requests=64`, `read_ahead_kb=256`).
>
> At `19:07`/`20:20`, internal eMMC was `/dev/mmcblk2` and microSD was `/dev/mmcblk1`.
> After the `20:31` reboot, internal eMMC became **`/dev/mmcblk1`** and microSD became **`/dev/mmcblk2`**.
> Always address storage via `UUID=` or `PARTUUID=`.

| Mountpoint | Size | FS Type | UUID | Fstab Options / Usage |
| --- | --- | --- | --- | --- |
| `/` | `26.7G` | `ext4` | `UUID=71f8d441-a98a-405b-a221-e8ae4c32437a` | `noatime,commit=30,errors=remount-ro` (`22G` used / `3,4G` free post-cleanup) |
| `/boot/efi` | `976M` | `vfat` | `UUID=76B7-0B3E` | `umask=0077` |
| `swap` | `1.5G` | `swap` | `UUID=59f9aa15-681e-4860-9f5f-b643801b3cde` | `sw` (active at prio `-2`) |
| `/media/piergi/EXTRA` (microSD) | `7.4G` / `7.6G` | `ext4` | `UUID=50e09466-61d9-4b04-9445-161548f62afc` | `defaults,noatime,nofail,x-gvfs-show` (`5.1G` used / `2.0G` free) |

Contents observed on `/media/piergi/EXTRA`:
- `Games/Gamecube` (`1.8G`)
- `The Coma Recut` (`1.3G`)
- `King's Quest II` (`543M`)
- `Geekbench-6.5.0-Linux` (`477M`)
- `SoH-Copper-Charlie-Linux` (`85M`)
- `zxtune` (`52M`)

---

## 5. PCI, Graphics, Display & USB

### PCI Devices (`lspci -nnk`)
| Slot | Class | Vendor:Device (Rev) | Subsystem | Kernel Driver |
| --- | --- | --- | --- | --- |
| `00:00.0` | `0600` (Host bridge) | `8086:0f00` (`rev 0d`) | `1043:14ed` | `iosf_mbi_pci` |
| `00:02.0` | `0300` (VGA) | `8086:0f31` (`rev 0d`) | `1043:14ed` | `i915` |
| `00:14.0` | `0c03` (USB xHCI) | `8086:0f35` (`rev 0d`) | `1043:14ed` | `xhci_hcd` / `xhci_pci` (`usbcore/autosuspend=2`) |
| `00:1a.0` | `1080` (Encryption / TXE) | `8086:0f18` (`rev 0d`) | `1043:14ed` | `mei_txe` |
| `00:1f.0` | `0601` (ISA bridge) | `8086:0f1c` (`rev 0d`) | `1043:14ed` | `lpc_ich` |

### Graphics & Display
- **Renderer**: `Mesa Intel(R) HD Graphics (BYT) (0xf31)` — Mesa `25.0.7-2+deb13u1`, OpenGL Core/Compat `4.2`, GLES `3.0`, unified `1536MB`
- **VA-API**: Uses `i965-va-driver` (`intel-media-va-driver` purged as unsupported on Bay Trail)
- **DRM Connectors**: `card0-DSI-1` (`1366x768`, `60186` mHz), `card0-DP-1`, `card0-HDMI-A-1` (previously observed `ONK 2610` EDID)
- **Backlight**: `intel_backlight`

### USB (`lsusb`) & Dock
- `Bus 001 Device 001`: `1d6b:0002` (xHCI USB 2.0 root hub)
- `Bus 001 Device 002`: `0b05:17e0` `ASUSTek Computer, Inc. ASUS Base Station(T100)`
- `Bus 002 Device 001`: `1d6b:0003` (xHCI USB 3.0 root hub)
- **Dock USB power**: `/sys/bus/usb/devices/usb1/power/control` forced to `on` via `/etc/tmpfiles.d/t100tas-tuning.conf` so tablet-dock detach/attach remains responsive.
- **Custom udev rule**: `/etc/udev/rules.d/51-gcadapter-rules` (present prior to cleanup, preserved).

---

## 6. Networking, Bluetooth, Audio, Sensors, Input & Battery

### Wi-Fi & Bluetooth (`02D0:4324` SDIO)
- **SDIO Functions**: `mmc0:0001:1` & `mmc0:0001:2` (`02D0:4324`)
- **Wi-Fi**: `brcmfmac` + `brcmfmac_wcc`, firmware package `firmware-brcm80211 20250410-2` (`brcmfmac43241b4-sdio.bin`), interface `wlan0`, MAC `54:a0:50:3a:fc:46`
- **Bluetooth**: `hci_uart` (`Manufacturer: 0x000f`, `Version: 0x06`), controller address `7E:FB:1D:A3:E7:DF`

### Audio
- **Sound Cards (ALSA)**:
  - `card 0`: `Intel HDMI/DP LPE Audio` (devices `0`, `1`)
  - `card 1`: `bytcr-rt5640` (devices `0`, `1`; modules `snd_soc_sst_bytcr_rt5640`, `snd_soc_rt5640`, `snd_intel_sst_acpi`, `snd_intel_sst_core`, `snd_soc_sst_atom_hifi2_platform`)
- **Audio Server**: PipeWire `1.4.2` + WirePlumber (`pipewire-pulse`)

### IIO Sensors & `iio-sensor-proxy`
- `iio:device0`: `i2c-CPLM3218:00` (ambient light on `80860F41:02`)
- `iio:device1`: `i2c-INVN6500:00` (accelerometer/gyroscope on `80860F41:04`)
- `iio:device2`: `AK8963` (magnetometer, `ak8975` driver on `14-000c`)
- D-Bus `net.hadess.SensorProxy`: `HasAccelerometer=true`, `HasAmbientLight=true`, `HasProximity=false`

### Input Devices (`/proc/bus/input/devices`)
- `event0`: `Lid Switch`
- `event1`: `Sleep Button`
- `event2` / `mouse0`: `SIS0817:00 0457:1071` I2C touchscreen (`80860F41:05/i2c-5`)
- `event3`: `Video Bus`
- `event4`, `event5`: `Asus Keyboard` (dock)
- `event6` / `mouse1`: `Asus TouchPad` (`[2821][6112]`, dock)
- `event7`: `Asus Wireless Radio Control` (LED `asus-wireless::airplane`)
- `event8`, `event9`: HDMI LPE audio jack events
- `event10`: `PC Speaker`
- `event11`: `Asus WMI hotkeys`
- `event12`: `gpio-keys`
- `event13`: `bytcr-rt5640 Headset`

### Battery & AC (`/sys/class/power_supply/`)
- `BATC` (`SR Real Battery`, `Intel SR 1`, Li-ion):
  - `CYCLE_COUNT=344`
  - `VOLTAGE_MIN_DESIGN=3750000`
  - `VOLTAGE_NOW=3607000`
  - `CHARGE_FULL_DESIGN=8060000`
  - `CHARGE_FULL=11958000` *(ACPI reporting quirk: reported full charge exceeds design capacity)*
- `ADP1`: mains adapter

---

## 7. Known Kernel / Firmware `dmesg` & Journal Warnings (Baseline)

Recorded during `3f34ec06` diagnostics so a custom kernel/OS builder does not waste time chasing normal Bay Trail/ASUS firmware noise:
1. `esrt: ESRT header is not in the memory map` — benign `T100TAS.207` UEFI quirk.
2. `acpi PNP0A08:00: fail to add MMCONFIG information` — Bay Trail ACPI quirk.
3. `byt_gpio INT33FC:02` Firmware Bug on pins `1` & `8`.
4. `ACPI: thermal: [Firmware Bug]: No valid trip points!`
5. `i915: cannot find GPIO chip gpio_crystalcove, deferring` and `[drm] *ERROR* Failed to own gpio for panel control` (transient/defer during probe).
6. `Bluetooth: hci0: BCM: firmware Patch file not found` (`brcm/BCM4324B3.hcd`, `brcm/BCM.hcd`).
7. `brcmfmac` probing missing optional board-specific blobs (`brcmfmac43241b4-sdio.ASUSTeK COMPUTER INC.-T100TAS.{bin,txt}`, `brcmfmac43241b4-sdio.txt`, `brcmfmac43241b4-sdio.clm_blob` returning `-2`, then falling back to `brcmfmac43241b4-sdio.bin`).
8. `asus_wmi: fan_curve_get_factory_default` `-19` (fanless tablet).
9. `mei_txe: PCI INT A: not connected`.
10. Dummy regulators on `inv-mpu6050-i2c`, `hci_uart_bcm`, `ak8975`.
11. Userspace warnings now bypassed or masked: Plasma's `org_kde_powerdevil` `/dev/i2c-7..14` `EACCES`, and `obexd` `evolution-source-registry.service is masked`.
