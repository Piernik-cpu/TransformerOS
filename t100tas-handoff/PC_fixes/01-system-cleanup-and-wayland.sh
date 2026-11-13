#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="/home/piergi/Scaricati/Antigravity-x64/Projects/PC_fixes/backups"
mkdir -p "$BACKUP_DIR"

echo "=== [1/8] Backing up system configuration files ==="
for f in \
  /etc/fstab \
  /etc/default/grub \
  /etc/default/zramswap \
  /etc/default/earlyoom \
  /etc/modules \
  /etc/initramfs-tools/initramfs.conf \
  /etc/sysctl.d/99-t100tas-performance.conf \
  /etc/NetworkManager/NetworkManager.conf \
  /etc/locale.gen
do
  if [ -e "$f" ]; then
    cp -a "$f" "$BACKUP_DIR/$(basename "$f").bak"
  fi
done
chown -R piergi:piergi "$BACKUP_DIR"

echo "=== [2/8] Freeing immediate cache space ==="
apt-get clean
journalctl --vacuum-size=15M || true
df -h /

echo "=== [3/8] Marking core hardware, driver, and user packages manual ==="
KEEP_MANUAL=(
  i965-va-driver
  mesa-va-drivers
  mesa-vulkan-drivers
  libgl1-mesa-dri
  xwayland
  mesa-utils
  network-manager
  wpasupplicant
  wireless-tools
  bluez
  iio-sensor-proxy
  pipewire-audio
  wireplumber
  upower
  udisks2
  gvfs
  gvfs-backends
  gvfs-fuse
  gnome-keyring
  libpam-gnome-keyring
  firmware-brcm80211
  firmware-intel-graphics
  firmware-intel-sound
  intel-microcode
  firefox-esr
  vlc
  libreoffice-writer
  libreoffice-calc
  libreoffice-impress
  libreoffice-gtk3
  scummvm
  qimgv
  zram-tools
  earlyoom
  locales
  sudo
  openssh-server
  dbus-user-session
  qt6-wayland
  qtwayland5
  pavucontrol
  linuxtoys
  git
  python3-pip
)
TO_MARK=()
for pkg in "${KEEP_MANUAL[@]}"; do
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    TO_MARK+=("$pkg")
  fi
done
if [ "${#TO_MARK[@]}" -gt 0 ]; then
  apt-mark manual "${TO_MARK[@]}" >/dev/null
fi

echo "=== [4/8] Capturing active DNS and ensuring locale.gen ==="
ACTIVE_DNS=""
if command -v nmcli >/dev/null 2>&1; then
  ACTIVE_DNS=$(nmcli -t -f IP4.DNS dev show wlan0 2>/dev/null | head -n1 | cut -d: -f2- || true)
fi
if [ -f /etc/locale.gen ]; then
  sed -i 's/^# *\(it_IT\.UTF-8 UTF-8\)/\1/' /etc/locale.gen
  sed -i 's/^# *\(en_US\.UTF-8 UTF-8\)/\1/' /etc/locale.gen
  grep -q '^it_IT\.UTF-8 UTF-8' /etc/locale.gen || echo 'it_IT.UTF-8 UTF-8' >> /etc/locale.gen
  grep -q '^en_US\.UTF-8 UTF-8' /etc/locale.gen || echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
fi

echo "=== [5/8] Purging bloat packages and orphaned dependencies ==="
PURGE_CANDIDATES=(
  locales-all
  fonts-noto-extra
  fonts-noto-cjk
  fonts-noto-cjk-extra
  fonts-noto-ui-extra
  mesa-opencl-icd
  libclc-19
  libclc-19-dev
  intel-media-va-driver
  va-driver-all
  pocketsphinx-en-us
  orca
  speech-dispatcher
  speech-dispatcher-espeak-ng
  evolution-data-server
  evolution-ews-core
  gnome-online-accounts
  gnome-calendar
  gnome-clocks
  gnome-connections
  gnome-contacts
  gnome-music
  gnome-remote-desktop
  gnome-sound-recorder
  gnome-user-share
  gnome-weather
  rygel
  rygel-playbin
  rygel-tracker
  apache2-bin
  libapache2-mod-dnssd
  samba-common
  samba-common-bin
  kdenetwork-filesharing
  cups
  cups-daemon
  cups-browsed
  cups-core-drivers
  ipp-usb
  system-config-printer-common
  system-config-printer-udev
  avahi-daemon
  modemmanager
  anacron
  popularity-contest
  low-memory-monitor
  linux-image-6.12.107+deb13-amd64
  libadwaita-1-dev
  build-essential
  dpkg-dev
  g++
  gcc
  manpages-dev
  python3-dev
  linux-libc-dev
  dnsmasq
  resolvconf
)
TO_PURGE=()
for pkg in "${PURGE_CANDIDATES[@]}"; do
  if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
    TO_PURGE+=("$pkg")
  fi
done
if [ "${#TO_PURGE[@]}" -gt 0 ]; then
  DEBIAN_FRONTEND=noninteractive apt-get purge -y "${TO_PURGE[@]}"
fi
DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y
locale-gen

echo "=== [6/8] Fixing NetworkManager DNS and WiFi powersave ==="
if [ -L /etc/resolv.conf ] || grep -q "127\.0\.0\.1" /etc/resolv.conf 2>/dev/null; then
  rm -f /etc/resolv.conf
  if [ -n "$ACTIVE_DNS" ]; then
    printf "nameserver %s\n" "$ACTIVE_DNS" > /etc/resolv.conf
  else
    printf "nameserver 1.1.1.1\nnameserver 9.9.9.9\n" > /etc/resolv.conf
  fi
fi
cat > /etc/NetworkManager/conf.d/99-t100tas.conf <<'EOF'
[main]
dns=default

[connection]
wifi.powersave=2
EOF
systemctl reload NetworkManager || systemctl restart NetworkManager
for _ in {1..10}; do
  if getent hosts deb.debian.org >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo "=== [7/8] Pruning unused system Flatpaks and installing light Wayland stack ==="
flatpak uninstall --system --unused -y || true
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  greetd tuigreet labwc waybar fuzzel foot mako-notifier \
  swaybg swayidle gtklock kanshi wlr-randr xdg-desktop-portal-wlr \
  wl-clipboard grim slurp brightnessctl playerctl wvkbd \
  mate-polkit network-manager-applet blueman pcmanfm iw vainfo rfkill

echo "=== [8/8] Applying system, kernel, boot, memory, and display-manager optimizations ==="
# Remove parallel printer modules
if [ -f /etc/modules ]; then
  sed -i -E '/^(lp|ppdev|parport_pc)$/d' /etc/modules
fi

# Disable unnecessary system services/timers (keep ssh.service, fstrim.timer, logrotate.timer)
for unit in \
  networking.service \
  NetworkManager-wait-online.service \
  lm-sensors.service \
  apt-daily.timer \
  apt-daily-upgrade.timer \
  man-db.timer \
  dpkg-db-backup.timer
do
  systemctl disable "$unit" 2>/dev/null || true
done

# Disable coredump disk/RAM stalls
mkdir -p /etc/systemd/coredump.conf.d
cat > /etc/systemd/coredump.conf.d/99-disable.conf <<'EOF'
[Coredump]
Storage=none
ProcessSizeMax=0
EOF

# ZRAM: 125% logical zstd swap to keep pressure off slow eMMC
cat > /etc/default/zramswap <<'EOF'
ALGO=zstd
PERCENT=125
PRIORITY=100
EOF

# Sysctl: aggressive ZRAM preference + smooth I/O
cat > /etc/sysctl.d/99-t100tas-performance.conf <<'EOF'
# ASUS Transformer Book T100TAS (Intel Atom Z3775, 2GB RAM, eMMC + ZRAM)
vm.swappiness = 150
vm.page-cluster = 0
vm.vfs_cache_pressure = 80
vm.dirty_background_ratio = 5
vm.dirty_ratio = 15
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
EOF
sysctl --system >/dev/null || true

# EarlyOOM: protect Wayland stack too
cat > /etc/default/earlyoom <<'EOF'
EARLYOOM_ARGS="-r 0 -m 3 -M 256000 --prefer '^(Web Content|Isolated Web Co|firefox-esr)$' --avoid '^(apt|apt-get|dpkg|greetd|tuigreet|labwc|waybar|wvkbd-mobintl|foot|fuzzel|swaybg|mako|Xwayland|systemd|systemd-logind|dbus-daemon|kwin_wayland|plasmashell|sddm|Xorg)$'"
EOF
systemctl restart earlyoom || true

# fstab: reduce eMMC journal commit frequency slightly
sed -i 's/noatime,commit=15,errors=remount-ro/noatime,commit=30,errors=remount-ro/' /etc/fstab

# Initramfs: hardware-only modules for faster boot & smaller /boot
cat > /etc/initramfs-tools/conf.d/t100tas-modules.conf <<'EOF'
MODULES=dep
COMPRESS=zstd
EOF
update-initramfs -u -k "$(uname -r)"

# GRUB: fast boot + mitigations=off + zswap disabled (use zram)
mkdir -p /etc/default/grub.d
cat > /etc/default/grub.d/99-t100tas.cfg <<'EOF'
GRUB_TIMEOUT=1
GRUB_CMDLINE_LINUX_DEFAULT="quiet mitigations=off zswap.enabled=0"
EOF
update-grub

# Ensure labwc desktop entry exists for session selectors
mkdir -p /usr/share/wayland-sessions
if [ ! -f /usr/share/wayland-sessions/labwc.desktop ]; then
  cat > /usr/share/wayland-sessions/labwc.desktop <<'EOF'
[Desktop Entry]
Name=Labwc
Comment=Lightweight Wayland stacking compositor
Exec=labwc
Type=Application
DesktopNames=wlroots
EOF
fi

# Configure greetd + tuigreet (preserving Debian package's greeter user and checking supported flags)
GREETD_USER="_greetd"
if [ -f /etc/greetd/config.toml ]; then
  cp -a /etc/greetd/config.toml "$BACKUP_DIR/greetd-config.toml.bak"
  DETECTED_USER=$(grep -E '^\s*user\s*=' /etc/greetd/config.toml | head -n1 | sed -E 's/.*=\s*"?([^" ]+)"?.*/\1/' || true)
  if [ -n "$DETECTED_USER" ]; then
    GREETD_USER="$DETECTED_USER"
  fi
fi
TUIGREET_HELP=$(tuigreet --help 2>&1 || true)
echo "--- tuigreet --help ---"
echo "$TUIGREET_HELP"
TUIGREET_CMD="tuigreet --time --remember"
if echo "$TUIGREET_HELP" | grep -q -- "--remember-session"; then
  TUIGREET_CMD="$TUIGREET_CMD --remember-session"
elif echo "$TUIGREET_HELP" | grep -q -- "--remember-user-session"; then
  TUIGREET_CMD="$TUIGREET_CMD --remember-user-session"
fi
if echo "$TUIGREET_HELP" | grep -q -- "--sessions"; then
  TUIGREET_CMD="$TUIGREET_CMD --sessions /usr/share/wayland-sessions:/usr/share/xsessions"
fi
TUIGREET_CMD="$TUIGREET_CMD --cmd labwc"

cat > /etc/greetd/config.toml <<EOF
[terminal]
vt = 1

[default_session]
command = "${TUIGREET_CMD}"
user = "${GREETD_USER}"
EOF

# Switch display manager for NEXT boot without killing the current SDDM/Plasma session!
systemctl disable sddm.service || true
systemctl enable greetd.service --force
echo "--- display-manager status ---"
ls -la /etc/systemd/system/display-manager.service 2>/dev/null || true
systemctl is-enabled greetd.service || true

apt-get clean
echo "=== DONE ==="
df -h /
