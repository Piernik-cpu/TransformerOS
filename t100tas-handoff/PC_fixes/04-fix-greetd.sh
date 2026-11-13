#!/usr/bin/env bash
set -euo pipefail

echo "=== [1/4] Fixing /etc/greetd/config.toml VT (vt = 7 to match greetd.service Conflicts=getty@tty7.service) ==="
cat << 'EOF' > /etc/greetd/config.toml
[terminal]
vt = 7

[default_session]
command = "tuigreet --time --asterisks --remember --remember-session --sessions /usr/share/wayland-sessions --xsessions /usr/share/xsessions --power-shutdown 'systemctl poweroff' --power-reboot 'systemctl reboot' --cmd labwc"
user = "_greetd"
EOF

install -d -m 0750 -o _greetd -g _greetd /var/cache/tuigreet

echo "=== [2/4] Disabling global auto-start of waybar/mako/foot-server in graphical-session.target ==="
systemctl --global disable waybar.service mako.service foot-server.service foot-server.socket 2>/dev/null || true

echo "=== [3/4] Testing tuigreet invocation as _greetd in a pseudo-terminal ==="
rm -f /tmp/tuigreet-test.log
python3 - << 'PYEOF'
import os, pty, pwd, select, signal, time

pw = pwd.getpwnam("_greetd")
cmd = [
    "tuigreet",
    "--debug", "/tmp/tuigreet-test.log",
    "--time", "--asterisks", "--remember", "--remember-session",
    "--sessions", "/usr/share/wayland-sessions",
    "--xsessions", "/usr/share/xsessions",
    "--power-shutdown", "systemctl poweroff",
    "--power-reboot", "systemctl reboot",
    "--cmd", "labwc",
]

pid, master_fd = pty.fork()
if pid == 0:
    os.setgid(pw.pw_gid)
    os.setuid(pw.pw_uid)
    os.environ["HOME"] = pw.pw_dir
    os.environ["USER"] = pw.pw_name
    os.environ["TERM"] = "linux"
    os.execvp("tuigreet", cmd)

deadline = time.monotonic() + 0.8
chunks = []
while time.monotonic() < deadline:
    r, _, _ = select.select([master_fd], [], [], 0.1)
    if r:
        try:
            data = os.read(master_fd, 4096)
            if not data:
                break
            chunks.append(data)
        except OSError:
            break
    wpid, status = os.waitpid(pid, os.WNOHANG)
    if wpid == pid:
        print(f"tuigreet exited early with wait status {status}")
        break

try:
    os.kill(pid, signal.SIGTERM)
    os.waitpid(pid, 0)
except OSError:
    pass
os.close(master_fd)
print(f"PTY output bytes captured: {sum(len(c) for c in chunks)}")
PYEOF

if [ -f /tmp/tuigreet-test.log ]; then
    echo "--- /tmp/tuigreet-test.log ---"
    cat /tmp/tuigreet-test.log
    rm -f /tmp/tuigreet-test.log
fi

echo "=== [4/4] Stopping stuck pre-fix greetd process (greetd.service stays enabled for boot) ==="
systemctl stop greetd.service || true
systemctl is-enabled greetd.service
readlink -f /etc/systemd/system/display-manager.service
cat /etc/greetd/config.toml
