#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="/home/piergi/Scaricati/Antigravity-x64/Projects/PC_fixes/backups"
mkdir -p "$BACKUP_DIR"

echo "=== [1/5] Installing wlopm and libnotify-bin ==="
export DEBIAN_FRONTEND=noninteractive
apt-get install -y --no-install-recommends wlopm libnotify-bin
apt-get clean

echo "=== [2/5] Configuring /etc/greetd/config.toml ==="
if [ -f /etc/greetd/config.toml ] && [ ! -f "$BACKUP_DIR/greetd-config.toml.orig" ]; then
    cp -a /etc/greetd/config.toml "$BACKUP_DIR/greetd-config.toml.orig"
fi

cat << 'EOF' > /etc/greetd/config.toml
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --asterisks --remember --remember-session --sessions /usr/share/wayland-sessions --xsessions /usr/share/xsessions --power-shutdown 'systemctl poweroff' --power-reboot 'systemctl reboot' --cmd labwc"
user = "_greetd"
EOF

echo "=== [3/5] Configuring logind & journald drop-ins ==="
mkdir -p /etc/systemd/logind.conf.d
cat << 'EOF' > /etc/systemd/logind.conf.d/99-t100tas.conf
[Login]
HandlePowerKey=suspend
HandlePowerKeyLongPress=poweroff
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=suspend
EOF

mkdir -p /etc/systemd/journald.conf.d
cat << 'EOF' > /etc/systemd/journald.conf.d/99-t100tas.conf
[Journal]
SystemMaxUse=64M
RuntimeMaxUse=16M
EOF

echo "=== [4/5] Verifying sessions, services, and network ==="
ls -la /usr/share/wayland-sessions /usr/share/xsessions || true
readlink -f /etc/systemd/system/display-manager.service || true
systemctl is-enabled greetd.service earlyoom.service zramswap.service fstrim.timer power-profiles-daemon.service ssh.service || true
systemctl is-enabled sddm.service 2>/dev/null || echo "sddm.service: disabled"
cat /etc/NetworkManager/conf.d/99-t100tas.conf || true

echo "=== [5/5] Disk usage summary ==="
df -h /
