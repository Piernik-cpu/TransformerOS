#!/usr/bin/env python3
"""
TransformerOS Adaptive Dock-Aware Greeter & Lock Screen
- Docked (0b05:17e0 / physical keyboard present): Classic laptop login card with focused password input.
- Undocked (Tablet mode): Touch-optimized layout with built-in touch keyboard/keypad and large controls.
- Speaks native greetd IPC protocol over $GREETD_SOCK (or runs as lock screen with --lock).
"""

import datetime
import glob
import json
import os
import socket
import struct
import subprocess
import sys

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, GLib, Gtk

DOCK_VENDOR = "0b05"
DOCK_PRODUCT = "17e0"


def has_dock_or_keyboard() -> bool:
    for dev in glob.glob("/sys/bus/usb/devices/*"):
        try:
            v = open(os.path.join(dev, "idVendor")).read().strip().lower()
            p = open(os.path.join(dev, "idProduct")).read().strip().lower()
            if v == DOCK_VENDOR and p == DOCK_PRODUCT:
                return True
        except OSError:
            pass
    if glob.glob("/dev/input/by-id/*-event-kbd"):
        return True
    return False


def read_battery_text() -> str:
    try:
        cap = open("/sys/class/power_supply/BATC/capacity").read().strip()
        status = open("/sys/class/power_supply/BATC/status").read().strip()
        icon = "⚡" if status == "Charging" else "🔋"
        return f"{icon} {cap}%"
    except OSError:
        return ""


def greetd_roundtrip(sock: socket.socket, payload: dict) -> dict:
    raw = json.dumps(payload).encode("utf-8")
    sock.sendall(struct.pack("=I", len(raw)) + raw)
    hdr = b""
    while len(hdr) < 4:
        chunk = sock.recv(4 - len(hdr))
        if not chunk:
            raise RuntimeError("greetd socket closed")
        hdr += chunk
    (length,) = struct.unpack("=I", hdr)
    body = b""
    while len(body) < length:
        chunk = sock.recv(length - len(body))
        if not chunk:
            raise RuntimeError("greetd socket truncated")
        body += chunk
    return json.loads(body.decode("utf-8"))


def authenticate_greetd(username: str, password: str, session_cmd: list[str]) -> tuple[bool, str]:
    sock_path = os.environ.get("GREETD_SOCK")
    if not sock_path:
        return False, "GREETD_SOCK not set"
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(sock_path)
        try:
            resp = greetd_roundtrip(s, {"type": "create_session", "username": username})
            while resp.get("type") == "auth_message":
                msg_type = resp.get("auth_message_type", "")
                reply = password if msg_type in ("secret", "visible") else ""
                resp = greetd_roundtrip(
                    s, {"type": "post_auth_message_response", "response": reply}
                )
            if resp.get("type") != "success":
                desc = resp.get("description", "Authentication failed")
                greetd_roundtrip(s, {"type": "cancel_session"})
                return False, desc

            start_resp = greetd_roundtrip(
                s,
                {
                    "type": "start_session",
                    "cmd": session_cmd,
                    "env": [
                        "XDG_SESSION_TYPE=wayland",
                        "XDG_CURRENT_DESKTOP=labwc:wlroots",
                        "MOZ_ENABLE_WAYLAND=1",
                    ],
                },
            )
            if start_resp.get("type") == "success":
                return True, "OK"
            desc = start_resp.get("description", "Failed to start session")
            greetd_roundtrip(s, {"type": "cancel_session"})
            return False, desc
        except Exception as exc:
            try:
                greetd_roundtrip(s, {"type": "cancel_session"})
            except Exception:
                pass
            return False, str(exc)


CSS = """
window {
    background: linear-gradient(145deg, #0d1117 0%, #161f30 55%, #101824 100%);
    color: #f0f4f8;
    font-family: "Sans";
}
.clock-time {
    font-size: 56px;
    font-weight: 700;
    color: #ffffff;
}
.clock-date {
    font-size: 18px;
    color: #9fb3c8;
    margin-bottom: 14px;
}
.login-card {
    background-color: rgba(24, 30, 44, 0.90);
    border: 1px solid rgba(99, 179, 237, 0.28);
    border-radius: 20px;
    padding: 26px 32px;
}
.mode-badge {
    background-color: rgba(56, 161, 105, 0.22);
    border: 1px solid rgba(72, 187, 120, 0.45);
    border-radius: 999px;
    padding: 6px 14px;
    font-size: 13px;
    font-weight: 600;
    color: #9ae6b4;
}
.mode-badge-tablet {
    background-color: rgba(49, 130, 206, 0.28);
    border: 1px solid rgba(99, 179, 237, 0.65);
    border-radius: 999px;
    padding: 8px 18px;
    font-size: 15px;
    font-weight: 700;
    color: #90cdf4;
}
.user-title {
    font-size: 22px;
    font-weight: 700;
    margin-top: 6px;
}
entry.password-entry {
    min-height: 46px;
    font-size: 18px;
    border-radius: 12px;
    padding: 6px 14px;
    background-color: rgba(13, 17, 23, 0.85);
    color: #ffffff;
}
entry.password-entry-tablet {
    min-height: 56px;
    font-size: 22px;
}
button.primary-btn {
    min-height: 46px;
    border-radius: 12px;
    font-size: 17px;
    font-weight: 700;
    background: #3182ce;
    color: #ffffff;
}
button.primary-btn-tablet {
    min-height: 56px;
    font-size: 20px;
}
button.key-btn {
    min-height: 48px;
    min-width: 54px;
    border-radius: 10px;
    font-size: 18px;
    font-weight: 600;
    background-color: rgba(45, 55, 72, 0.92);
    color: #f7fafc;
}
button.key-btn:active {
    background-color: #3182ce;
}
button.power-btn {
    min-height: 42px;
    border-radius: 10px;
    padding: 6px 16px;
    font-size: 14px;
    background-color: rgba(45, 55, 72, 0.65);
    color: #e2e8f0;
}
.error-label {
    color: #fc8181;
    font-size: 14px;
    font-weight: 600;
}
"""


class GreeterWindow(Gtk.ApplicationWindow):
    def __init__(self, app: Gtk.Application, lock_mode: bool = False):
        super().__init__(application=app, title="TransformerOS Login")
        self.lock_mode = lock_mode
        self.default_user = os.environ.get("TRANSFORMEROS_USER", "piergi")
        self.shift_active = False
        self.docked = has_dock_or_keyboard()
        self.manual_osk = False

        self.set_decorated(False)
        self.fullscreen()

        provider = Gtk.CssProvider()
        provider.load_from_data(CSS.encode("utf-8"))
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        root.set_valign(Gtk.Align.FILL)
        root.set_halign(Gtk.Align.FILL)
        root.set_margin_top(20)
        root.set_margin_bottom(20)
        root.set_margin_start(32)
        root.set_margin_end(32)
        self.set_child(root)

        # Top status bar
        top_bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        self.mode_badge = Gtk.Label()
        top_bar.append(self.mode_badge)

        spacer = Gtk.Box()
        spacer.set_hexpand(True)
        top_bar.append(spacer)

        self.osk_toggle_btn = Gtk.Button(label="⌨ Touch Keyboard")
        self.osk_toggle_btn.add_css_class("power-btn")
        self.osk_toggle_btn.connect("clicked", self.on_toggle_osk)
        top_bar.append(self.osk_toggle_btn)

        self.battery_label = Gtk.Label()
        top_bar.append(self.battery_label)
        root.append(top_bar)

        # Center area
        center = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        center.set_valign(Gtk.Align.CENTER)
        center.set_halign(Gtk.Align.CENTER)
        center.set_vexpand(True)

        self.clock_label = Gtk.Label()
        self.clock_label.add_css_class("clock-time")
        center.append(self.clock_label)

        self.date_label = Gtk.Label()
        self.date_label.add_css_class("clock-date")
        center.append(self.date_label)

        # Login Card
        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        card.add_css_class("login-card")
        card.set_size_request(420, -1)

        user_lbl = Gtk.Label(label=f"👤  {self.default_user}")
        user_lbl.add_css_class("user-title")
        card.append(user_lbl)

        self.subtitle_lbl = Gtk.Label()
        card.append(self.subtitle_lbl)

        self.pass_entry = Gtk.PasswordEntry()
        self.pass_entry.set_show_peek_icon(True)
        self.pass_entry.add_css_class("password-entry")
        self.pass_entry.connect("activate", self.on_submit)
        card.append(self.pass_entry)

        self.error_label = Gtk.Label(label="")
        self.error_label.add_css_class("error-label")
        card.append(self.error_label)

        self.login_btn = Gtk.Button(
            label="Unlock" if self.lock_mode else "Sign In to TransformerOS"
        )
        self.login_btn.add_css_class("primary-btn")
        self.login_btn.connect("clicked", self.on_submit)
        card.append(self.login_btn)

        center.append(card)

        # Built-in Touch Keyboard (auto-shown in Tablet Mode when dock is detached!)
        self.kbd_box = self.build_touch_keyboard()
        center.append(self.kbd_box)

        root.append(center)

        # Bottom power action bar
        bottom = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
        bottom.set_halign(Gtk.Align.CENTER)
        for label, cmd in [
            ("☾ Suspend", ["systemctl", "suspend"]),
            ("↻ Restart", ["systemctl", "reboot"]),
            ("⏻ Power Off", ["systemctl", "poweroff"]),
        ]:
            btn = Gtk.Button(label=label)
            btn.add_css_class("power-btn")
            btn.connect("clicked", lambda _b, c=cmd: subprocess.Popen(c))
            bottom.append(btn)
        root.append(bottom)

        self.update_clock_and_mode()
        GLib.timeout_add(1000, self.update_clock_and_mode)
        GLib.idle_add(lambda: self.pass_entry.grab_focus() or False)

    def build_touch_keyboard(self) -> Gtk.Box:
        container = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        container.set_halign(Gtk.Align.CENTER)
        container.set_margin_top(10)

        rows = [
            ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
            ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
            ["a", "s", "d", "f", "g", "h", "j", "k", "l", "⌫"],
            ["⇧", "z", "x", "c", "v", "b", "n", "m", ".", "↵"],
        ]
        self.key_buttons: list[tuple[Gtk.Button, str]] = []
        for row in rows:
            rbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
            rbox.set_halign(Gtk.Align.CENTER)
            for key in row:
                btn = Gtk.Button(label=key)
                btn.add_css_class("key-btn")
                btn.set_focus_on_click(False)
                btn.connect("clicked", self.on_key_pressed, key)
                rbox.append(btn)
                if len(key) == 1 and key.isalpha():
                    self.key_buttons.append((btn, key))
            container.append(rbox)
        return container

    def on_key_pressed(self, _btn: Gtk.Button, key: str):
        cur = self.pass_entry.get_text()
        if key == "⌫":
            self.pass_entry.set_text(cur[:-1])
            self.pass_entry.set_position(-1)
        elif key == "⇧":
            self.shift_active = not self.shift_active
            for b, ch in self.key_buttons:
                b.set_label(ch.upper() if self.shift_active else ch.lower())
        elif key == "↵":
            self.on_submit(None)
        else:
            ch = key.upper() if (self.shift_active and key.isalpha()) else key
            self.pass_entry.set_text(cur + ch)
            self.pass_entry.set_position(-1)
            if self.shift_active:
                self.shift_active = False
                for b, c in self.key_buttons:
                    b.set_label(c.lower())

    def on_toggle_osk(self, _btn):
        self.manual_osk = not self.manual_osk
        self.apply_mode_ui()

    def apply_mode_ui(self):
        tablet_mode = not self.docked
        show_kbd = tablet_mode or self.manual_osk
        self.kbd_box.set_visible(show_kbd)

        if tablet_mode:
            self.mode_badge.set_text("󰓶 Tablet Mode (Dock Detached — Touch Login)")
            self.mode_badge.remove_css_class("mode-badge")
            self.mode_badge.add_css_class("mode-badge-tablet")
            self.subtitle_lbl.set_text("Tap password below using the touch keypad")
            self.pass_entry.add_css_class("password-entry-tablet")
            self.login_btn.add_css_class("primary-btn-tablet")
        else:
            self.mode_badge.set_text("󰌢 Laptop Mode (Keyboard Dock Connected)")
            self.mode_badge.remove_css_class("mode-badge-tablet")
            self.mode_badge.add_css_class("mode-badge")
            self.subtitle_lbl.set_text("Type your password and press Enter")
            self.pass_entry.remove_css_class("password-entry-tablet")
            self.login_btn.remove_css_class("primary-btn-tablet")

    def update_clock_and_mode(self) -> bool:
        now = datetime.datetime.now()
        self.clock_label.set_text(now.strftime("%H:%M"))
        self.date_label.set_text(now.strftime("%A, %d %B %Y"))
        self.battery_label.set_text(read_battery_text())

        docked_now = has_dock_or_keyboard()
        if docked_now != self.docked:
            self.docked = docked_now
        self.apply_mode_ui()
        return True

    def on_submit(self, _widget):
        pw = self.pass_entry.get_text()
        if not pw:
            self.error_label.set_text("Please enter your password")
            return
        self.error_label.set_text("Signing in...")
        self.login_btn.set_sensitive(False)

        if self.lock_mode:
            res = subprocess.run(
                ["su", "-c", "true", self.default_user],
                input=(pw + "\n").encode("utf-8"),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            if res.returncode == 0:
                self.get_application().quit()
                return
            self.error_label.set_text("Incorrect password")
            self.pass_entry.set_text("")
            self.login_btn.set_sensitive(True)
            return

        ok, msg = authenticate_greetd(
            self.default_user, pw, ["/usr/bin/transformer-session"]
        )
        if ok:
            self.get_application().quit()
        else:
            self.error_label.set_text(msg)
            self.pass_entry.set_text("")
            self.login_btn.set_sensitive(True)


class GreeterApp(Gtk.Application):
    def __init__(self, lock_mode: bool = False):
        super().__init__(application_id="org.transformeros.Greeter")
        self.lock_mode = lock_mode

    def do_activate(self):
        win = GreeterWindow(self, lock_mode=self.lock_mode)
        win.present()


if __name__ == "__main__":
    lock = "--lock" in sys.argv
    app = GreeterApp(lock_mode=lock)
    app.run([])
