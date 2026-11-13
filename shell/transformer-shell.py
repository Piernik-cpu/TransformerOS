#!/usr/bin/env python3
"""
TransformerOS Shell Surfaces (GTK4 + gtk4-layer-shell):
1. `transformer-shell bar`     -> Android-style Bottom Navigation Bar (auto-visible in Tablet Mode)
2. `transformer-shell qs`      -> Pull-Down Quick Settings, Sliders & One-Tap Atomic Update Panel
3. `transformer-shell appgrid` -> Full-Screen Touch App Grid for Tablet Mode
"""

from ctypes import CDLL
import configparser
import glob
import json
import os
import subprocess
import sys

# Preload libgtk4-layer-shell before importing gi
for libname in ("libgtk4-layer-shell.so.0", "libgtk4-layer-shell.so"):
    try:
        CDLL(libname)
        break
    except OSError:
        pass

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
try:
    gi.require_version("Gtk4LayerShell", "1.0")
    from gi.repository import Gtk4LayerShell as LayerShell
    HAS_LAYER_SHELL = True
except Exception:
    HAS_LAYER_SHELL = False

from gi.repository import Gdk, Gio, GLib, Gtk


def runtime_dir() -> str:
    xdg = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    d = os.path.join(xdg, "transformeros")
    os.makedirs(d, exist_ok=True)
    return d


def read_state() -> dict:
    p = os.path.join(runtime_dir(), "state.json")
    try:
        with open(p, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {
            "dock_attached": True,
            "effective_mode": "docked",
            "mode_override": "auto",
            "orientation": "normal",
            "rotation_locked": False,
            "auto_brightness": True,
            "ambient_lux": 80.0,
            "brightness_pct": 60,
            "battery_pct": 100,
            "battery_status": "Full",
            "ac_online": True,
            "power_profile": "balanced",
            "game_mode": False,
            "osk_visible": False,
            "update_status": "up-to-date",
        }


def run_bg(cmd: list[str]):
    try:
        subprocess.Popen(
            cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
    except Exception:
        pass


SHELL_CSS = """
window.transparent-win {
    background: transparent;
}
.android-navbar {
    background-color: rgba(15, 20, 30, 0.94);
    border-top: 1px solid rgba(99, 179, 237, 0.28);
    padding: 4px 24px;
}
button.nav-btn {
    min-height: 42px;
    min-width: 110px;
    border-radius: 999px;
    font-size: 16px;
    font-weight: 700;
    background-color: rgba(45, 55, 72, 0.55);
    color: #f0f4f8;
    border: none;
}
button.nav-btn:active, button.nav-btn:hover {
    background-color: rgba(49, 130, 206, 0.85);
    color: #ffffff;
}
.qs-panel {
    background-color: rgba(17, 23, 35, 0.96);
    border: 1px solid rgba(99, 179, 237, 0.35);
    border-radius: 20px;
    padding: 18px;
    color: #f0f4f8;
}
button.qs-tile {
    min-height: 60px;
    min-width: 185px;
    border-radius: 14px;
    padding: 8px 14px;
    font-size: 14px;
    font-weight: 600;
    background-color: rgba(45, 55, 72, 0.78);
    color: #e2e8f0;
}
button.qs-tile-active {
    background-color: #2b6cb0;
    color: #ffffff;
    border: 1px solid #63b3ed;
}
.update-card {
    background-color: rgba(26, 36, 54, 0.92);
    border: 1px solid rgba(72, 187, 120, 0.40);
    border-radius: 14px;
    padding: 12px 14px;
}
button.action-pill {
    min-height: 42px;
    border-radius: 10px;
    padding: 6px 12px;
    font-size: 14px;
    font-weight: 600;
    background-color: rgba(45, 55, 72, 0.85);
    color: #f0f4f8;
}
.appgrid-bg {
    background-color: rgba(12, 17, 26, 0.94);
    padding: 24px 36px;
    color: #f0f4f8;
}
button.app-tile {
    min-width: 140px;
    min-height: 120px;
    border-radius: 16px;
    padding: 12px;
    background-color: rgba(30, 41, 59, 0.72);
    color: #f8fafc;
}
button.app-tile:hover, button.app-tile:active {
    background-color: rgba(49, 130, 206, 0.75);
}
entry.search-box {
    min-height: 48px;
    font-size: 18px;
    border-radius: 14px;
    padding: 6px 16px;
    background-color: rgba(30, 41, 59, 0.90);
    color: #ffffff;
}
"""


def load_css():
    provider = Gtk.CssProvider()
    provider.load_from_data(SHELL_CSS.encode("utf-8"))
    Gtk.StyleContext.add_provider_for_display(
        Gdk.Display.get_default(),
        provider,
        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
    )


class BottomNavBarApp(Gtk.Application):
    """Android-style bottom navigation bar that automatically shows in Tablet Mode."""

    def __init__(self):
        super().__init__(application_id="org.transformeros.BottomBar")
        self.win = None
        self.currently_visible = None

    def do_activate(self):
        load_css()
        self.win = Gtk.ApplicationWindow(application=self, title="TransformerOS Nav")
        self.win.set_decorated(False)

        if HAS_LAYER_SHELL:
            LayerShell.init_for_window(self.win)
            LayerShell.set_namespace(self.win, "transformeros-navbar")
            LayerShell.set_layer(self.win, LayerShell.Layer.TOP)
            LayerShell.set_anchor(self.win, LayerShell.Edge.BOTTOM, True)
            LayerShell.set_anchor(self.win, LayerShell.Edge.LEFT, True)
            LayerShell.set_anchor(self.win, LayerShell.Edge.RIGHT, True)
            LayerShell.set_exclusive_zone(self.win, 50)
            LayerShell.set_keyboard_mode(
                self.win, LayerShell.KeyboardMode.NONE
            )

        bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=18)
        bar.add_css_class("android-navbar")
        bar.set_halign(Gtk.Align.FILL)

        left_spacer = Gtk.Box()
        left_spacer.set_hexpand(True)
        bar.append(left_spacer)

        buttons = [
            ("◀  Back", lambda _b: run_bg(["wtype", "-k", "Escape"])),
            ("●  Home", lambda _b: run_bg(["/usr/bin/transformer-shell", "appgrid"])),
            (
                "■  Recents",
                lambda _b: run_bg(["wtype", "-M", "alt", "-k", "Tab", "-m", "alt"]),
            ),
            ("⌨  Keyboard", lambda _b: run_bg(["transformerd", "osk", "toggle"])),
            ("⚙  Quick Settings", lambda _b: run_bg(["/usr/bin/transformer-shell", "qs"])),
        ]
        for label, cb in buttons:
            btn = Gtk.Button(label=label)
            btn.add_css_class("nav-btn")
            btn.set_focus_on_click(False)
            btn.connect("clicked", cb)
            bar.append(btn)

        right_spacer = Gtk.Box()
        right_spacer.set_hexpand(True)
        bar.append(right_spacer)

        self.win.set_child(bar)
        self.sync_mode()
        GLib.timeout_add(600, self.sync_mode)

    def sync_mode(self) -> bool:
        st = read_state()
        tablet = st.get("effective_mode") == "tablet"
        if tablet != self.currently_visible:
            self.currently_visible = tablet
            if tablet:
                self.win.present()
                self.win.set_visible(True)
            else:
                self.win.set_visible(False)
        return True


class QuickSettingsApp(Gtk.Application):
    """Pull-down Quick Settings, Brightness/Volume Sliders & One-Tap Update Center."""

    def __init__(self):
        super().__init__(application_id="org.transformeros.QuickSettings")

    def do_activate(self):
        load_css()
        self.win = Gtk.ApplicationWindow(application=self, title="Quick Settings")
        self.win.set_decorated(False)
        self.win.add_css_class("transparent-win")

        if HAS_LAYER_SHELL:
            LayerShell.init_for_window(self.win)
            LayerShell.set_namespace(self.win, "transformeros-qs")
            LayerShell.set_layer(self.win, LayerShell.Layer.OVERLAY)
            LayerShell.set_anchor(self.win, LayerShell.Edge.TOP, True)
            LayerShell.set_anchor(self.win, LayerShell.Edge.RIGHT, True)
            LayerShell.set_margin(self.win, LayerShell.Edge.TOP, 38)
            LayerShell.set_margin(self.win, LayerShell.Edge.RIGHT, 12)
            LayerShell.set_keyboard_mode(
                self.win, LayerShell.KeyboardMode.ON_DEMAND
            )

        panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        panel.add_css_class("qs-panel")
        panel.set_size_request(420, -1)
        self.win.set_child(panel)

        # Header row
        hdr = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.header_lbl = Gtk.Label()
        self.header_lbl.set_xalign(0.0)
        self.header_lbl.set_hexpand(True)
        hdr.append(self.header_lbl)

        close_btn = Gtk.Button(label="✕")
        close_btn.add_css_class("action-pill")
        close_btn.connect("clicked", lambda _b: self.quit())
        hdr.append(close_btn)
        panel.append(hdr)

        # 2x4 Grid of Touch Quick Settings Tiles
        grid = Gtk.Grid(column_spacing=10, row_spacing=10)
        grid.set_column_homogeneous(True)
        panel.append(grid)

        self.btn_mode = Gtk.Button()
        self.btn_mode.add_css_class("qs-tile")
        self.btn_mode.connect(
            "clicked", lambda _b: self.run_and_refresh(["transformerd", "mode", "toggle"])
        )
        grid.attach(self.btn_mode, 0, 0, 1, 1)

        self.btn_rotate = Gtk.Button()
        self.btn_rotate.add_css_class("qs-tile")
        self.btn_rotate.connect(
            "clicked",
            lambda _b: self.run_and_refresh(["transformerd", "rotate", "toggle"]),
        )
        grid.attach(self.btn_rotate, 1, 0, 1, 1)

        self.btn_als = Gtk.Button()
        self.btn_als.add_css_class("qs-tile")
        self.btn_als.connect(
            "clicked",
            lambda _b: self.run_and_refresh(
                ["transformerd", "autobrightness", "toggle"]
            ),
        )
        grid.attach(self.btn_als, 0, 1, 1, 1)

        self.btn_game = Gtk.Button()
        self.btn_game.add_css_class("qs-tile")
        self.btn_game.connect(
            "clicked",
            lambda _b: self.run_and_refresh(["transformerd", "gamemode", "toggle"]),
        )
        grid.attach(self.btn_game, 1, 1, 1, 1)

        self.btn_power = Gtk.Button()
        self.btn_power.add_css_class("qs-tile")
        self.btn_power.connect("clicked", self.on_cycle_power)
        grid.attach(self.btn_power, 0, 2, 1, 1)

        self.btn_osk = Gtk.Button(label="⌨  Touch Keyboard\nShow / Hide")
        self.btn_osk.add_css_class("qs-tile")
        self.btn_osk.connect(
            "clicked", lambda _b: run_bg(["transformerd", "osk", "toggle"])
        )
        grid.attach(self.btn_osk, 1, 2, 1, 1)

        btn_wifi = Gtk.Button(label="󰖩  Wi-Fi Settings\nNetworkManager")
        btn_wifi.add_css_class("qs-tile")
        btn_wifi.connect(
            "clicked",
            lambda _b: (run_bg(["nm-connection-editor"]), self.quit()),
        )
        grid.attach(btn_wifi, 0, 3, 1, 1)

        btn_bt = Gtk.Button(label="󰂯  Bluetooth\nDevices & Audio")
        btn_bt.add_css_class("qs-tile")
        btn_bt.connect(
            "clicked",
            lambda _b: (run_bg(["blueman-manager"]), self.quit()),
        )
        grid.attach(btn_bt, 1, 3, 1, 1)

        # Brightness slider
        b_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        b_row.append(Gtk.Label(label="☀"))
        self.b_scale = Gtk.Scale.new_with_range(
            Gtk.Orientation.HORIZONTAL, 5, 100, 5
        )
        self.b_scale.set_hexpand(True)
        self.b_scale.set_Value = read_state().get("brightness_pct", 60)
        self.b_scale.set_value(read_state().get("brightness_pct", 60))
        self.b_scale.connect("value-changed", self.on_brightness_changed)
        b_row.append(self.b_scale)
        panel.append(b_row)

        # Volume slider
        v_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        v_row.append(Gtk.Label(label="🔊"))
        self.v_scale = Gtk.Scale.new_with_range(
            Gtk.Orientation.HORIZONTAL, 0, 100, 5
        )
        self.v_scale.set_hexpand(True)
        self.v_scale.set_value(70)
        self.v_scale.connect("value-changed", self.on_volume_changed)
        v_row.append(self.v_scale)
        panel.append(v_row)

        # Atomic Update & Rollback Card
        ucard = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        ucard.add_css_class("update-card")
        self.update_lbl = Gtk.Label()
        self.update_lbl.set_xalign(0.0)
        ucard.append(self.update_lbl)

        ubtns = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        btn_upd = Gtk.Button(label="↻ One-Tap Update")
        btn_upd.add_css_class("action-pill")
        btn_upd.set_hexpand(True)
        btn_upd.connect(
            "clicked", lambda _b: run_bg(["transformerd", "update", "apply"])
        )
        ubtns.append(btn_upd)

        btn_rb = Gtk.Button(label="⏪ Roll Back")
        btn_rb.add_css_class("action-pill")
        btn_rb.connect(
            "clicked", lambda _b: run_bg(["transformerd", "update", "rollback"])
        )
        ubtns.append(btn_rb)
        ucard.append(ubtns)
        panel.append(ucard)

        # Bottom Power & Lock Row
        prow = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        for lbl, cmd in [
            ("🔒 Lock", ["/usr/bin/transformer-greeter", "--lock"]),
            ("☾ Sleep", ["systemctl", "suspend"]),
            ("↻ Reboot", ["systemctl", "reboot"]),
            ("⏻ Off", ["systemctl", "poweroff"]),
        ]:
            b = Gtk.Button(label=lbl)
            b.add_css_class("action-pill")
            b.set_hexpand(True)
            b.connect("clicked", lambda _b, c=cmd: (run_bg(c), self.quit()))
            prow.append(b)
        panel.append(prow)

        self.refresh_ui()
        GLib.timeout_add(800, self.refresh_ui)
        self.win.present()

    def set_tile_active(self, btn: Gtk.Button, active: bool):
        if active:
            btn.add_css_class("qs-tile-active")
        else:
            btn.remove_css_class("qs-tile-active")

    def run_and_refresh(self, cmd: list[str]):
        subprocess.run(cmd)
        self.refresh_ui()

    def on_cycle_power(self, _btn):
        st = read_state()
        order = ["auto", "performance", "balanced", "power-saver"]
        cur = st.get("power_profile", "balanced")
        nxt = order[(order.index(cur) + 1) % len(order)] if cur in order else "auto"
        self.run_and_refresh(["transformerd", "power", nxt])

    def on_brightness_changed(self, scale: Gtk.Scale):
        val = int(scale.get_value())
        run_bg(["brightnessctl", "--quiet", "set", f"{val}%"])

    def on_volume_changed(self, scale: Gtk.Scale):
        val = int(scale.get_value())
        run_bg(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{val}%"])

    def refresh_ui(self) -> bool:
        st = read_state()
        bat = st.get("battery_pct", 100)
        bstat = st.get("battery_status", "")
        lux = st.get("ambient_lux", 0.0)
        self.header_lbl.set_text(
            f"🔋 {bat}% ({bstat})   •   ☀ {lux:.0f} lux   •   ⚡ {st.get('power_profile')}"
        )

        is_tablet = st.get("effective_mode") == "tablet"
        self.btn_mode.set_label(
            f"{'󰓶  Tablet Mode' if is_tablet else '󰌢  Laptop Mode'}\nOverride: {st.get('mode_override', 'auto')}"
        )
        self.set_tile_active(self.btn_mode, is_tablet)

        rot_lock = st.get("rotation_locked", False)
        self.btn_rotate.set_label(
            f"ScreenRotation  Rotation\n{'Locked' if rot_lock else 'Auto (' + st.get('orientation', 'normal') + ')'}"
        )
        self.set_tile_active(self.btn_rotate, not rot_lock)

        als = st.get("auto_brightness", True)
        self.btn_als.set_label(
            f"☀  Auto-Brightness\n{'ON (' + str(int(lux)) + ' lux)' if als else 'Manual'}"
        )
        self.set_tile_active(self.btn_als, als)

        gm = st.get("game_mode", False)
        self.btn_game.set_label(
            f"󰊗  Game Mode\n{'ACTIVE (Boost)' if gm else 'Off'}"
        )
        self.set_tile_active(self.btn_game, gm)

        prof = st.get("power_profile", "balanced")
        self.btn_power.set_label(f"⚡  Power Profile\n{prof.capitalize()}")
        self.set_tile_active(self.btn_power, prof == "performance")

        ust = st.get("update_status", "up-to-date")
        self.update_lbl.set_text(f"Atomic Image (bootc): {ust}")
        return True


class AppGridApp(Gtk.Application):
    """Full-screen Android-style touch App Grid for Tablet & Laptop modes."""

    def __init__(self):
        super().__init__(application_id="org.transformeros.AppGrid")
        self.apps = []

    def load_desktop_apps(self):
        dirs = [
            "/usr/share/applications",
            "/usr/local/share/applications",
            "/var/lib/flatpak/exports/share/applications",
            os.path.expanduser("~/.local/share/flatpak/exports/share/applications"),
            os.path.expanduser("~/.local/share/applications"),
        ]
        seen = set()
        apps = []
        for d in dirs:
            for path in sorted(glob.glob(os.path.join(d, "*.desktop"))):
                cp = configparser.ConfigParser(interpolation=None)
                try:
                    cp.read(path, encoding="utf-8")
                    if "Desktop Entry" not in cp:
                        continue
                    sec = cp["Desktop Entry"]
                    if sec.get("NoDisplay", "false").lower() == "true":
                        continue
                    if sec.get("Hidden", "false").lower() == "true":
                        continue
                    name = sec.get("Name", "").strip()
                    exec_cmd = sec.get("Exec", "").strip()
                    icon = sec.get("Icon", "application-x-executable").strip()
                    if not name or not exec_cmd or name in seen:
                        continue
                    seen.add(name)
                    # Strip %u %F etc.
                    clean_exec = [
                        tok for tok in exec_cmd.split() if not tok.startswith("%")
                    ]
                    if clean_exec:
                        apps.append((name, icon, clean_exec))
                except Exception:
                    pass
        apps.sort(key=lambda x: x[0].lower())
        return apps

    def do_activate(self):
        load_css()
        self.apps = self.load_desktop_apps()
        self.win = Gtk.ApplicationWindow(application=self, title="TransformerOS Apps")
        self.win.set_decorated(False)
        self.win.fullscreen()

        if HAS_LAYER_SHELL:
            LayerShell.init_for_window(self.win)
            LayerShell.set_namespace(self.win, "transformeros-appgrid")
            LayerShell.set_layer(self.win, LayerShell.Layer.OVERLAY)
            for edge in (
                LayerShell.Edge.TOP,
                LayerShell.Edge.BOTTOM,
                LayerShell.Edge.LEFT,
                LayerShell.Edge.RIGHT,
            ):
                LayerShell.set_anchor(self.win, edge, True)
            LayerShell.set_keyboard_mode(
                self.win, LayerShell.KeyboardMode.ON_DEMAND
            )

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        root.add_css_class("appgrid-bg")
        self.win.set_child(root)

        # Top search + close bar
        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        self.search = Gtk.Entry()
        self.search.set_placeholder_text("🔍  Search applications...")
        self.search.add_css_class("search-box")
        self.search.set_hexpand(True)
        self.search.connect("changed", self.on_search_changed)
        top.append(self.search)

        kbd_btn = Gtk.Button(label="⌨ Keyboard")
        kbd_btn.add_css_class("action-pill")
        kbd_btn.connect(
            "clicked", lambda _b: run_bg(["transformerd", "osk", "toggle"])
        )
        top.append(kbd_btn)

        close_btn = Gtk.Button(label="✕ Close")
        close_btn.add_css_class("action-pill")
        close_btn.connect("clicked", lambda _b: self.quit())
        top.append(close_btn)
        root.append(top)

        # Scrollable FlowBox of large touch app tiles
        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        scroll.set_hexpand(True)
        self.flow = Gtk.FlowBox()
        self.flow.set_valign(Gtk.Align.START)
        self.flow.set_max_children_per_line(6)
        self.flow.set_min_children_per_line(3)
        self.flow.set_column_spacing(16)
        self.flow.set_row_spacing(16)
        self.flow.set_selection_mode(Gtk.SelectionMode.NONE)
        scroll.set_child(self.flow)
        root.append(scroll)

        self.populate_apps("")
        self.win.present()

    def populate_apps(self, query: str):
        child = self.flow.get_first_child()
        while child is not None:
            nxt = child.get_next_sibling()
            self.flow.remove(child)
            child = nxt

        q = query.strip().lower()
        for name, icon, cmd in self.apps:
            if q and q not in name.lower():
                continue
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
            box.set_halign(Gtk.Align.CENTER)
            box.set_valign(Gtk.Align.CENTER)

            img = Gtk.Image.new_from_icon_name(icon)
            img.set_pixel_size(56)
            box.append(img)

            lbl = Gtk.Label(label=name[:20])
            lbl.set_wrap(True)
            box.append(lbl)

            btn = Gtk.Button()
            btn.add_css_class("app-tile")
            btn.set_child(box)
            btn.connect("clicked", lambda _b, c=cmd: (run_bg(c), self.quit()))
            self.flow.append(btn)

    def on_search_changed(self, entry: Gtk.Entry):
        self.populate_apps(entry.get_text())


def toggle_single_instance(lock_name: str) -> bool:
    pid_file = os.path.join(runtime_dir(), f"{lock_name}.pid")
    if os.path.exists(pid_file):
        try:
            old_pid = int(open(pid_file).read().strip())
            os.kill(old_pid, 15)
            os.remove(pid_file)
            return False
        except Exception:
            pass
    with open(pid_file, "w", encoding="utf-8") as f:
        f.write(str(os.getpid()))
    return True


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "qs"
    if mode == "bar":
        BottomNavBarApp().run([])
    elif mode == "appgrid":
        if toggle_single_instance("appgrid"):
            AppGridApp().run([])
    else:
        if toggle_single_instance("qs"):
            QuickSettingsApp().run([])
