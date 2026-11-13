# Debian 13 (`trixie`) State & `PC_fixes` Changes Applied (`2026-11-13`)

This document records the exact pre-fix bottlenecks, every system and user modification performed by `/home/piergi/Scaricati/Antigravity-x64/Projects/PC_fixes/{01,02,03,04}*.sh`, and the live verified state after rebooting into `labwc`.

---

## 1. OS Baseline & Repositories

- **OS**: `Debian GNU/Linux 13 (trixie)`, `DEBIAN_VERSION_FULL=13.7`
- **Architectures**: `amd64` + `i386` (both kept for Wine/Steam/legacy compatibility)
- **APT Sources (`/etc/apt/sources.list`)**: Debian `trixie`, `trixie-security`, `trixie-updates` (`main non-free-firmware`); a `waydroid` APT source was also noted in the prior conversation.
- **Original Backups**: Saved by `PC_fixes` scripts in `/home/piergi/Scaricati/Antigravity-x64/Projects/PC_fixes/backups/`.

---

## 2. Pre-Fix Bottlenecks (`19:07` & `20:20` Baseline)

1. **Critical `/` Disk Saturation**:
   - `423M` free out of `26.7G` (`25G` used, `99%`).
   - Breakdown before cleanup: `/usr` `7.9G` (`/usr/share/fonts` `822M`, `/usr/share/locale` `679M`, `/usr/lib/locale` `238M`), `/var` `5.6G` (`/var/lib/flatpak` `4.5G`, `/var/cache/apt` `523M`), `/home/piergi` `11G` (`.var/app` `5.6G` including Steam `5.2G`, `teams_for_linux` `116M`, `Zelda3` `110M`, `zapzap` `104M`, `dolphin-emu` `42M`; `~/.local/share/flatpak` `2.5G`; `~/.local/share/umu/steamrt3` `778M`; `~/.cache` `547M`; `Scaricati/Antigravity-x64` `495M`; `.gemini/antigravity` `248M`; `~/power-options` `9.8M`).
2. **Severe RAM & Swap Contention under KDE Plasma 6.3 + SDDM**:
   - Kept `Xorg` (`27M`), `plasmashell` (`80–106M`), `kwin_wayland` (`48–70M`), `kded6` (`20–44M`), 3 XDG desktop portals (`xdg-desktop-portal`, `-kde`, `-gtk`), GNOME/Evolution background daemons (`goa-daemon`, `evolution-source-registry`, `evolution-addressbook-factory`), `kdeconnectd`, `kaccess`, `powerdevil`, and dual keyrings (`kwalletd6` + `gnome-keyring-daemon`).
   - Driven to **`676.1M` swap used** (at `20:20` post-reboot Plasma fallback).
3. **Slow Boot & First Reboot Symptom (`20:20`)**:
   - Baseline `systemd-analyze`: `23.231s`.
   - `01-system-cleanup-and-wayland.sh` originally configured `greetd` on `vt = 1` without `_greetd` cache directory permissions, racing `getty@tty1` and dropping the first reboot into SDDM/Plasma fallback. Fixed in `04-fix-greetd.sh` (`vt = 7` + `/var/cache/tuigreet` `_greetd:_greetd 0750` + disabling `sddm.service`).

---

## 3. System-Level Changes Applied (`01`, `02`, `04`)

### Package Purges (`93` packages purged, `1.690 MB` reported freed by `apt`) & Cache Cleanup
- **Purged bloat/unsupported packages**:
  - Localization & giant fonts: `locales-all` (keeping `it_IT.UTF-8` and `en_US.UTF-8`), `fonts-noto-extra`, `fonts-noto-cjk`, `fonts-noto-cjk-extra`, `fonts-noto-ui-extra`
  - Unused GPU/OpenCL/unsupported VA-API: `mesa-opencl-icd`, `libclc-19`, `libclc-19-dev`, `intel-media-va-driver`, `va-driver-all`
  - Speech/accessibility/PIM/GNOME daemons: `pocketsphinx-en-us`, `orca`, `speech-dispatcher*`, `evolution-data-server`, `evolution-ews-core`, `gnome-online-accounts`, `gnome-calendar`, `gnome-clocks`, `gnome-connections`, `gnome-contacts`, `gnome-music`, `gnome-remote-desktop`, `gnome-sound-recorder`, `gnome-user-share`, `gnome-weather`
  - Network file/print/UPnP daemons: `rygel*`, `apache2-bin`, `libapache2-mod-dnssd`, `samba-common*`, `kdenetwork-filesharing`, `cups*`, `ipp-usb`, `system-config-printer*`, `avahi-daemon`, `modemmanager`, `dnsmasq`, `resolvconf`
  - Old kernel & heavy dev headers: `linux-image-6.12.107+deb13-amd64`, `libadwaita-1-dev`, `build-essential`, `dpkg-dev`, `gcc`, `g++`, `manpages-dev`, `python3-dev`, `linux-libc-dev`
  - Telemetry/timers/legacy: `anacron`, `popularity-contest`, `low-memory-monitor`, plus auto-orphans
  - Cleanup commands: `apt-get clean` and `flatpak uninstall --system --unused`
- **Explicitly Preserved**:
  - User Flatpaks & system desktop apps (Steam, LibreOffice, VLC, scummvm, qimgv, firefox-esr)
  - `i386` multiarch libs, `openssh-server`, `linuxtoys`, `git`, `python3-pip`
  - `kde-plasma-desktop` (kept as emergency fallback session selectable in `tuigreet` alongside `labwc`)

### Wayland Stack Installed (`--no-install-recommends`)
`greetd`, `tuigreet`, `labwc`, `waybar`, `fuzzel`, `foot`, `mako-notifier`, `swaybg`, `swayidle`, `gtklock`, `wlopm`, `kanshi`, `wlr-randr`, `xdg-desktop-portal-wlr`, `wl-clipboard`, `grim`, `slurp`, `brightnessctl`, `playerctl`, `wvkbd`, `mate-polkit`, `network-manager-applet`, `blueman`, `pcmanfm`, `libnotify-bin`, `iw`, `vainfo`, `rfkill`.

### Kernel, Bootloader, Memory, Storage & Service Configs
| File | Applied Configuration |
| --- | --- |
| `/etc/default/grub.d/99-t100tas.cfg` | `GRUB_TIMEOUT=1`, `GRUB_CMDLINE_LINUX_DEFAULT="quiet mitigations=off zswap.enabled=0"` |
| `/etc/initramfs-tools/conf.d/t100tas-modules.conf` | `MODULES=dep`, `COMPRESS=zstd` -> `initrd.img-6.12.113+deb13-amd64` (`25.3 MB`) |
| `/etc/default/zramswap` | `ALGO=zstd`, `PERCENT=125`, `PRIORITY=100` |
| `/etc/sysctl.d/99-t100tas-performance.conf` | `vm.swappiness=150`, `vm.page-cluster=0`, `vm.vfs_cache_pressure=80`, `vm.dirty_background_ratio=5`, `vm.dirty_ratio=15`, `vm.watermark_boost_factor=0`, `vm.watermark_scale_factor=125` |
| `/etc/sysctl.d/99-splitlock.conf` *(pre-existing, preserved)* | `kernel.split_lock_mitigate=0` |
| `/etc/tmpfiles.d/t100tas-tuning.conf` | THP `madvise` + defrag `defer+madvise`; `mmcblk1` & `mmcblk2` `nr_requests=64` & `read_ahead_kb=256`; `/sys/bus/usb/devices/usb1/power/control` = `on` |
| `/etc/default/earlyoom` | `-r 0 -m 3 -M 256000 --prefer '^(Web Content\|Isolated Web Co\|firefox-esr)$' --avoid '^(apt\|apt-get\|dpkg\|greetd\|tuigreet\|labwc\|waybar\|wvkbd-mobintl\|foot\|fuzzel\|swaybg\|mako\|Xwayland\|systemd\|systemd-logind\|dbus-daemon\|kwin_wayland\|plasmashell\|sddm\|Xorg)$'` |
| `/etc/fstab` | `/` `ext4` updated `commit=15` -> `commit=30` (`noatime,commit=30,errors=remount-ro`) |
| `/etc/modules` | Stripped `lp`, `ppdev`, `parport_pc` |
| `/etc/greetd/config.toml` | `vt = 7`, `tuigreet` defaulting to `--cmd labwc`; `/var/cache/tuigreet` owned `_greetd:_greetd 0750` |
| `/etc/NetworkManager/conf.d/99-t100tas.conf` | `dns=default`, `wifi.powersave=2` |
| `/etc/systemd/journald.conf.d/99-t100tas.conf` | `SystemMaxUse=64M`, `RuntimeMaxUse=16M` |
| `/etc/systemd/logind.conf.d/99-t100tas.conf` | Power key & lid switch -> suspend; long power-key press -> poweroff |
| `/etc/systemd/coredump.conf.d/99-disable.conf` | Coredumps disabled |

### Systemd Services State
- **Disabled / Masked**: `networking.service`, `NetworkManager-wait-online.service`, `lm-sensors.service`, `apt-daily*.timer`, `man-db.timer`, `dpkg-db-backup.timer`, `sddm.service`; globally disabled `waybar.service`, `mako.service`, `foot-server.service`, `foot-server.socket`.
- **Active / Kept**: `greetd`, `ssh`, `earlyoom`, `zramswap`, `fstrim.timer`, `power-profiles-daemon` (`performance`).

---

## 4. User-Level Wayland Configs, Daemons & Custom Tablet Scripts (`03`)

### `labwc` (`~/.config/labwc/`) & Portals/Outputs
- **`environment`**: Sets `XKB_DEFAULT_LAYOUT=it` and Wayland environment variables.
- **`rc.xml` (`labwc 0.8.3-1`)**:
  - `2` virtual desktops
  - `SIS0817:00 0457:1071` touchscreen mapped to `DSI-1` with `mouseEmulation="no"`
  - Touchpad: `scrollFactor=0.4`, `naturalScroll=yes`
  - Keybindings: `W-d` / `W-Space` (`fuzzel`), `W-Return` (`foot`), `W-e` (`pcmanfm`), `W-b` (`firefox`), `W-k` (`wvkbd-mobintl` toggle), `W-r` (auto-rotate toggle), `W-l` (`gtklock`), `Print` / `S-Print` (`grim` / `slurp`).
- **`autostart`**, **`themerc-override`**, **`menu.xml`**
- **`~/.config/waybar/{config.jsonc,power_menu.xml}`**: Top `30px` bar (`Apps`, `wlr/taskbar`, `clock`, `custom/osk`, `custom/rotate`, `pulseaudio`, `backlight`, `network`, `power-profiles-daemon`, `memory`, `battery BATC`, `tray`, `custom/power`).
- **`~/.config/kanshi/config`**, **`~/.config/mako/config`**, **`~/.config/xdg-desktop-portal/labwc-portals.conf`**.

### Custom 2-in-1 Scripts (`~/.local/bin/`)
- **`t100-common.sh`**: `0b05:17e0` dock & keyboard detection + `t100_claim_pidfile` helper.
- **`t100-auto-osk-wl.sh`**: Runs `wvkbd-mobintl -H 240 -L 200` and toggles via `SIGUSR1` / `SIGUSR2` on udev dock attach/detach.
- **`t100-auto-rotate.sh`**: Uses `monitor-sensor --accel` + `wlr-randr --output DSI-1`; forces `normal` orientation when docked; supports lock toggle persisted in `~/.cache/t100-rotate.lock`.
- **Legacy Plasma unit (`~/.config/systemd/user/t100-auto-osk.service`)**: Gated with `ConditionEnvironment=XDG_CURRENT_DESKTOP=KDE` so it never runs in `labwc`.

### User Service Masking, Autostart Hygiene & Firefox Tuning
- **User systemd units masked**: `waybar.service`, `mako.service`, `foot-server.{service,socket}`, `evolution-*`, `localsearch-3`, `kde-baloo`, `plasma-kaccess`, `drkonqi-*`.
- **Autostart entries hidden (`~/.config/autostart/`)**: `blueman`, `nm-applet`, `org.kde.kdeconnect.daemon` (keeps Plasma fallback lean).
- **Firefox ESR (`bh8t3up4.default-esr/user.js`)**:
  - `browser.cache.disk.enable=false`
  - `browser.cache.memory.capacity=65536`
  - `dom.ipc.processCount=2`
  - `dom.ipc.processCount.webIsolated=1`
  - `browser.sessionstore.interval=60000`
  - `gfx.webrender.all=true`
  - `media.ffmpeg.vaapi.enabled=true`
  - `widget.use-xdg-desktop-portal.file-picker=1`
