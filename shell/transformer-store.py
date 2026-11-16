#!/usr/bin/env python3
"""
TransformerOS Package Manager (`transformer-store`)
Unified GTK4 + Libadwaita software center for ASUS Transformer Book T100TAS:
  1. Fedora Apps (RPM packages via DNF5 with automatic bootc /usr overlay unlock)
  2. Flatpaks (Flathub remote browse, search, install, launch & remove)
  3. AppImages (Local .AppImage desktop integration like Gear Lever, scanner for
     ~/Downloads & /var/mnt/EXTRA microSD, plus direct URL download & integration)
  4. Installed & System Updates
"""

import configparser
import glob
import os
import pwd
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import threading
import urllib.request

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
try:
    gi.require_version("Adw", "1")
    from gi.repository import Adw
    HAS_ADW = True
except Exception:
    HAS_ADW = False

from gi.repository import Gdk, Gio, GLib, Gtk, Pango


CURATED_FEDORA_APPS = [
    ("fastfetch", "Fastfetch", "Fast system information tool for Linux terminals"),
    ("htop", "htop", "Interactive process viewer and system monitor"),
    ("btop", "btop", "Modern colorful resource monitor for CPU, memory, disks & network"),
    ("mpv", "mpv Media Player", "Lightweight hardware-accelerated video player (VA-API i965)"),
    ("vlc", "VLC Media Player", "Versatile multimedia player for audio, video & streams"),
    ("qimgv", "qimgv Image Viewer", "Fast, lightweight Qt image viewer with video support"),
    ("mousepad", "Mousepad Text Editor", "Fast and simple GTK text and code editor"),
    ("evince", "Document Viewer (Evince)", "PDF, DjVu and PostScript document reader"),
    ("foliate", "Foliate eBook Reader", "Clean GTK4 eBook and EPUB reader for tablet & laptop"),
    ("galculator", "Galculator", "Lightweight GTK scientific and algebraic calculator"),
    ("file-roller", "Archive Manager", "Create and extract ZIP, TAR, 7z and RAR archives"),
    ("pavucontrol", "PulseAudio / PipeWire Volume Control", "Per-application audio mixer and output routing"),
    ("gimp", "GIMP Image Editor", "GNU Image Manipulation Program for photo editing"),
    ("audacity", "Audacity", "Multi-track audio editor and recorder"),
    ("transmission-gtk", "Transmission BitTorrent", "Lightweight GTK BitTorrent client"),
    ("scummvm", "ScummVM", "Classic point-and-click adventure game engine"),
    ("dosbox-staging", "DOSBox Staging", "Modernized DOS emulator for retro PC games"),
    ("gparted", "GParted Partition Editor", "Graphical disk partition manager"),
    ("lxtask", "LXTask Task Manager", "Ultra-lightweight process and memory manager"),
    ("neovim", "Neovim", "Vim-fork focused on extensibility and usability"),
    ("git", "Git", "Distributed version control system"),
    ("ncdu", "ncdu Disk Usage", "Fast ncurses disk usage analyzer"),
    ("tmux", "tmux", "Terminal multiplexer"),
]

CURATED_FLATPAKS = [
    ("com.github.tchx84.Flatseal", "Flatseal", "Manage and review Flatpak application permissions"),
    ("io.github.flattool.Warehouse", "Warehouse", "Manage installed Flatpaks, user data, and remotes"),
    ("it.mijorus.gearlever", "Gear Lever", "Manage and organize AppImages in your application menu"),
    ("org.videolan.VLC", "VLC", "Multimedia player for all audio and video formats"),
    ("org.libreoffice.LibreOffice", "LibreOffice", "Full office productivity suite (Writer, Calc, Impress)"),
    ("org.gimp.GIMP", "GIMP", "Create images and edit photographs"),
    ("org.kde.krita", "Krita", "Digital painting and illustration studio"),
    ("org.DolphinEmu.dolphin-emu", "Dolphin Emulator", "GameCube and Wii emulator"),
    ("org.scummvm.ScummVM", "ScummVM", "Run classic adventure and role-playing games"),
    ("org.libretro.RetroArch", "RetroArch", "Frontend for emulators, game engines and media players"),
    ("com.valvesoftware.Steam", "Steam", "PC gaming platform and library manager"),
    ("com.discordapp.Discord", "Discord", "Messaging, voice, and video chat client"),
    ("org.telegram.desktop", "Telegram Desktop", "Fast and secure cloud-based messaging app"),
    ("com.rtosta.zapzap", "ZapZap", "WhatsApp desktop client for Linux"),
    ("com.spotify.Client", "Spotify", "Online music streaming service"),
    ("org.mozilla.Thunderbird", "Thunderbird", "Email, newsgroup, feed and calendar client"),
    ("md.obsidian.Obsidian", "Obsidian", "Markdown knowledge base and note-taking app"),
]


STORE_CSS = """
window {
    background-color: #0e1524;
    color: #f0f4f8;
}
.store-header {
    background-color: #131c2e;
    border-bottom: 1px solid rgba(99, 179, 237, 0.25);
    padding: 10px 16px;
}
.tab-btn {
    min-height: 38px;
    padding: 6px 14px;
    border-radius: 10px;
    font-weight: 700;
    font-size: 13px;
    background-color: #1c2840;
    color: #cbd5e0;
    border: 1px solid rgba(99, 179, 237, 0.2);
}
.tab-btn-active {
    background-color: #2b6cb0;
    color: #ffffff;
    border: 1px solid #63b3ed;
}
.pkg-card {
    background-color: #151f33;
    border: 1px solid rgba(99, 179, 237, 0.22);
    border-radius: 14px;
    padding: 12px 16px;
}
.pkg-title {
    font-size: 15px;
    font-weight: 700;
    color: #f8fafc;
}
.pkg-sub {
    font-size: 12px;
    color: #a0aec0;
}
.badge-rpm {
    background-color: #2a4365;
    color: #90cdf4;
    border-radius: 6px;
    padding: 2px 8px;
    font-size: 11px;
    font-weight: 700;
}
.badge-flatpak {
    background-color: #22543d;
    color: #9ae6b4;
    border-radius: 6px;
    padding: 2px 8px;
    font-size: 11px;
    font-weight: 700;
}
.badge-appimage {
    background-color: #553c9a;
    color: #d6bcfa;
    border-radius: 6px;
    padding: 2px 8px;
    font-size: 11px;
    font-weight: 700;
}
.badge-installed {
    background-color: #276749;
    color: #c6f6d5;
    border-radius: 6px;
    padding: 2px 8px;
    font-size: 11px;
    font-weight: 700;
}
.install-btn {
    min-height: 36px;
    min-width: 92px;
    border-radius: 10px;
    font-weight: 700;
    background-color: #2b6cb0;
    color: #ffffff;
}
.remove-btn {
    min-height: 36px;
    min-width: 92px;
    border-radius: 10px;
    font-weight: 700;
    background-color: #742a2a;
    color: #fed7d7;
}
.action-btn {
    min-height: 36px;
    padding: 4px 12px;
    border-radius: 10px;
    font-weight: 600;
    background-color: #24344d;
    color: #e2e8f0;
}
.search-entry {
    min-height: 40px;
    border-radius: 10px;
    padding: 4px 12px;
    background-color: #1a263d;
    color: #ffffff;
}
.status-bar {
    background-color: #111929;
    border-top: 1px solid rgba(99, 179, 237, 0.25);
    padding: 8px 14px;
}
.log-view {
    background-color: #090d16;
    color: #90cdf4;
    font-family: monospace;
    font-size: 11px;
    padding: 8px;
}
"""


def slugify(text: str) -> str:
    s = re.sub(r"[^a-zA-Z0-9]+", "-", text.strip().lower()).strip("-")
    return s or "appimage"


def real_user_home() -> str:
    env_home = os.environ.get("HOME", "")
    uid = os.getuid()
    if uid != 0 and (not env_home or env_home == "/root" or not os.access(env_home, os.W_OK)):
        try:
            pw_dir = pwd.getpwuid(uid).pw_dir
            if pw_dir:
                os.environ["HOME"] = pw_dir
                return pw_dir
        except Exception:
            pass
    return env_home or os.path.expanduser("~")


def appimage_dir() -> str:
    d = os.path.join(real_user_home(), "Applications")
    try:
        os.makedirs(d, exist_ok=True)
    except OSError:
        pass
    return d


def user_apps_dir() -> str:
    d = os.path.join(real_user_home(), ".local", "share", "applications")
    try:
        os.makedirs(d, exist_ok=True)
    except OSError:
        pass
    return d


def user_icons_dir() -> str:
    d = os.path.join(real_user_home(), ".local", "share", "icons")
    try:
        os.makedirs(d, exist_ok=True)
    except OSError:
        pass
    return d


def integrate_appimage_file(src_path: str, move_file: bool = False) -> tuple[bool, str]:
    """
    Integrates a local .AppImage file into ~/Applications and generates a
    ~/.local/share/applications/appimage-<slug>.desktop entry + extracted icon
    so it appears immediately in the TransformerOS Apps launcher.
    """
    src_path = os.path.abspath(os.path.expanduser(src_path))
    if not os.path.isfile(src_path):
        return False, f"File not found: {src_path}"

    fname = os.path.basename(src_path)
    if not fname.lower().endswith(".appimage"):
        fname = fname + ".AppImage"

    dest_dir = appimage_dir()
    dest_path = os.path.join(dest_dir, fname)

    try:
        if os.path.abspath(src_path) != os.path.abspath(dest_path):
            if move_file:
                shutil.move(src_path, dest_path)
            else:
                shutil.copy2(src_path, dest_path)
        st = os.stat(dest_path)
        os.chmod(dest_path, st.st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    except Exception as exc:
        return False, f"Failed to copy AppImage: {exc}"

    raw_title = re.sub(r"\.appimage$", "", fname, flags=re.IGNORECASE)
    raw_title = re.sub(r"[-_](x86_64|amd64|i386|linux).*$", "", raw_title, flags=re.IGNORECASE)
    pretty_name = raw_title.replace("-", " ").replace("_", " ").strip() or fname
    slug = slugify(pretty_name)
    icon_value = "application-x-executable"
    categories = "Utility;Application;"
    comment = f"AppImage portable application ({fname})"

    # Attempt fast metadata/icon extraction from squashfs
    with tempfile.TemporaryDirectory(prefix="t100-appimg-") as tmpdir:
        try:
            subprocess.run(
                [dest_path, "--appimage-extract", "*.desktop"],
                cwd=tmpdir,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=12,
            )
            subprocess.run(
                [dest_path, "--appimage-extract", ".DirIcon"],
                cwd=tmpdir,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=12,
            )
            squash_root = os.path.join(tmpdir, "squashfs-root")
            for df in glob.glob(os.path.join(squash_root, "*.desktop")):
                cp = configparser.ConfigParser(interpolation=None)
                cp.read(df, encoding="utf-8")
                if "Desktop Entry" in cp:
                    sec = cp["Desktop Entry"]
                    pretty_name = sec.get("Name", pretty_name).strip() or pretty_name
                    comment = sec.get("Comment", comment).strip() or comment
                    categories = sec.get("Categories", categories).strip() or categories
                    if not categories.endswith(";"):
                        categories += ";"
                    icon_cand = sec.get("Icon", "").strip()
                    if icon_cand:
                        subprocess.run(
                            [dest_path, "--appimage-extract", f"*{icon_cand}*"],
                            cwd=tmpdir,
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL,
                            timeout=10,
                        )
                break

            # Copy extracted icon if present
            icon_candidates = (
                glob.glob(os.path.join(squash_root, "*.png"))
                + glob.glob(os.path.join(squash_root, "*.svg"))
                + [os.path.join(squash_root, ".DirIcon")]
            )
            for ic in icon_candidates:
                if os.path.isfile(ic):
                    ext = ".svg" if ic.endswith(".svg") else ".png"
                    target_icon = os.path.join(user_icons_dir(), f"appimage-{slug}{ext}")
                    shutil.copy2(ic, target_icon)
                    icon_value = target_icon
                    break
        except Exception:
            pass

    desktop_path = os.path.join(user_apps_dir(), f"appimage-{slug}.desktop")
    desktop_content = (
        "[Desktop Entry]\n"
        "Type=Application\n"
        f"Name={pretty_name}\n"
        f"Comment={comment}\n"
        f'Exec="{dest_path}" %U\n'
        f"TryExec={dest_path}\n"
        f"Icon={icon_value}\n"
        "Terminal=false\n"
        f"Categories={categories}\n"
        "StartupNotify=true\n"
        f"X-AppImage-Path={dest_path}\n"
    )
    try:
        with open(desktop_path, "w", encoding="utf-8") as f:
            f.write(desktop_content)
        os.chmod(desktop_path, 0o755)
        subprocess.run(
            ["update-desktop-database", user_apps_dir()],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception as exc:
        return False, f"Failed to write desktop entry: {exc}"

    return True, f"Integrated '{pretty_name}' into ~/Applications and Apps menu."


def list_integrated_appimages() -> list[dict]:
    items = []
    seen_paths = set()
    for df in sorted(glob.glob(os.path.join(user_apps_dir(), "appimage-*.desktop"))):
        cp = configparser.ConfigParser(interpolation=None)
        try:
            cp.read(df, encoding="utf-8")
            if "Desktop Entry" not in cp:
                continue
            sec = cp["Desktop Entry"]
            ap = sec.get("X-AppImage-Path", "") or sec.get("TryExec", "")
            if ap and os.path.isfile(ap):
                seen_paths.add(os.path.abspath(ap))
                size_mb = os.path.getsize(ap) / (1024 * 1024)
                items.append(
                    {
                        "name": sec.get("Name", os.path.basename(ap)),
                        "path": ap,
                        "desktop": df,
                        "comment": f"{size_mb:.1f} MB  •  {ap}",
                        "integrated": True,
                    }
                )
        except Exception:
            pass

    # Also scan ~/Applications, ~/Downloads, and /var/mnt/EXTRA for unintegrated .AppImage files
    scan_dirs = [
        appimage_dir(),
        os.path.expanduser("~/Downloads"),
        os.path.expanduser("~/Scaricati"),
        "/var/mnt/EXTRA",
    ]
    for sd in scan_dirs:
        if not os.path.isdir(sd):
            continue
        for pat in ("*.AppImage", "*.appimage"):
            for p in sorted(glob.glob(os.path.join(sd, pat))):
                ap = os.path.abspath(p)
                if ap in seen_paths or not os.path.isfile(ap):
                    continue
                seen_paths.add(ap)
                size_mb = os.path.getsize(ap) / (1024 * 1024)
                items.append(
                    {
                        "name": os.path.basename(ap),
                        "path": ap,
                        "desktop": "",
                        "comment": f"{size_mb:.1f} MB  •  Found in {sd} (Not integrated yet)",
                        "integrated": False,
                    }
                )
    return items


class StoreWindow(Gtk.ApplicationWindow):
    def __init__(self, app: Gtk.Application, initial_appimage: str | None = None):
        super().__init__(application=app, title="TransformerOS Package Manager")
        self.set_default_size(940, 620)
        self.busy = False
        self.installed_rpms: set[str] = set()
        self.installed_flatpaks: set[str] = set()

        self.build_ui()
        self.refresh_installed_caches( switch_after=False )
        if initial_appimage:
            GLib.idle_add(self.install_appimage_direct, initial_appimage)

    def build_ui(self):
        provider = Gtk.CssProvider()
        provider.load_from_data(STORE_CSS.encode("utf-8"))
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.set_child(root)

        # Header Bar with Tab Switcher + OSK button
        hdr = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        hdr.add_css_class("store-header")

        title_lbl = Gtk.Label(label="📦  Package Manager")
        title_lbl.add_css_class("pkg-title")
        hdr.append(title_lbl)

        spacer1 = Gtk.Box()
        spacer1.set_hexpand(True)
        hdr.append(spacer1)

        self.tab_buttons: dict[str, Gtk.Button] = {}
        for tab_id, label in [
            ("fedora", "Fedora (RPM)"),
            ("flatpak", "Flatpaks (Flathub)"),
            ("appimage", "AppImages"),
            ("updates", "Installed & Updates"),
        ]:
            b = Gtk.Button(label=label)
            b.add_css_class("tab-btn")
            b.connect("clicked", lambda _btn, tid=tab_id: self.switch_tab(tid))
            hdr.append(b)
            self.tab_buttons[tab_id] = b

        spacer2 = Gtk.Box()
        spacer2.set_hexpand(True)
        hdr.append(spacer2)

        osk_btn = Gtk.Button(label="⌨")
        osk_btn.add_css_class("action-btn")
        osk_btn.set_tooltip_text("Toggle Touch Keyboard")
        osk_btn.connect(
            "clicked",
            lambda _b: subprocess.Popen(
                ["transformerd", "osk", "toggle"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            ),
        )
        hdr.append(osk_btn)
        root.append(hdr)

        # Stack for the 4 views
        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        self.stack.set_vexpand(True)
        self.stack.set_hexpand(True)
        root.append(self.stack)

        self.build_fedora_page()
        self.build_flatpak_page()
        self.build_appimage_page()
        self.build_updates_page()

        # Bottom Status + Progress + Expandable Log
        status_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        status_box.add_css_class("status-bar")

        s_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        self.status_lbl = Gtk.Label(
            label="Ready — supports Fedora 45 RPMs (DNF5), Flatpaks (Flathub), and AppImages."
        )
        self.status_lbl.set_xalign(0.0)
        self.status_lbl.set_hexpand(True)
        self.status_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        s_row.append(self.status_lbl)

        self.spinner = Gtk.Spinner()
        s_row.append(self.spinner)

        log_toggle = Gtk.ToggleButton(label="Terminal Log")
        log_toggle.add_css_class("action-btn")
        log_toggle.connect(
            "toggled", lambda btn: self.log_revealer.set_reveal_child(btn.get_active())
        )
        s_row.append(log_toggle)
        status_box.append(s_row)

        self.log_revealer = Gtk.Revealer()
        self.log_revealer.set_reveal_child(False)
        log_scroll = Gtk.ScrolledWindow()
        log_scroll.set_min_content_height(120)
        self.log_text = Gtk.TextView()
        self.log_text.set_editable(False)
        self.log_text.set_monospace(True)
        self.log_text.add_css_class("log-view")
        log_scroll.set_child(self.log_text)
        self.log_revealer.set_child(log_scroll)
        status_box.append(self.log_revealer)

        root.append(status_box)
        self.switch_tab("fedora")

    # -------------------------------------------------------------------------
    # Page 1: Fedora RPM Packages (DNF5)
    # -------------------------------------------------------------------------
    def build_fedora_page(self):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        page.set_margin_top(12)
        page.set_margin_bottom(12)
        page.set_margin_start(16)
        page.set_margin_end(16)

        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.rpm_search = Gtk.Entry()
        self.rpm_search.set_placeholder_text(
            "🔍  Search Fedora 45 & RPM Fusion packages (e.g. fastfetch, vlc, retroarch)..."
        )
        self.rpm_search.add_css_class("search-entry")
        self.rpm_search.set_hexpand(True)
        self.rpm_search.connect("activate", lambda _e: self.on_search_fedora())
        top.append(self.rpm_search)

        s_btn = Gtk.Button(label="Search DNF")
        s_btn.add_css_class("install-btn")
        s_btn.connect("clicked", lambda _b: self.on_search_fedora())
        top.append(s_btn)

        feat_btn = Gtk.Button(label="Featured")
        feat_btn.add_css_class("action-btn")
        feat_btn.connect("clicked", lambda _b: self.populate_curated_fedora())
        top.append(feat_btn)
        page.append(top)

        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        self.rpm_list = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        scroll.set_child(self.rpm_list)
        page.append(scroll)

        self.stack.add_named(page, "fedora")

    # -------------------------------------------------------------------------
    # Page 2: Flatpaks (Flathub)
    # -------------------------------------------------------------------------
    def build_flatpak_page(self):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        page.set_margin_top(12)
        page.set_margin_bottom(12)
        page.set_margin_start(16)
        page.set_margin_end(16)

        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.fp_search = Gtk.Entry()
        self.fp_search.set_placeholder_text(
            "🔍  Search Flathub applications (e.g. Firefox, Steam, Telegram, Obsidian)..."
        )
        self.fp_search.add_css_class("search-entry")
        self.fp_search.set_hexpand(True)
        self.fp_search.connect("activate", lambda _e: self.on_search_flatpak())
        top.append(self.fp_search)

        s_btn = Gtk.Button(label="Search Flathub")
        s_btn.add_css_class("install-btn")
        s_btn.connect("clicked", lambda _b: self.on_search_flatpak())
        top.append(s_btn)

        feat_btn = Gtk.Button(label="Popular")
        feat_btn.add_css_class("action-btn")
        feat_btn.connect("clicked", lambda _b: self.populate_curated_flatpaks())
        top.append(feat_btn)
        page.append(top)

        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        self.fp_list = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        scroll.set_child(self.fp_list)
        page.append(scroll)

        self.stack.add_named(page, "flatpak")

    # -------------------------------------------------------------------------
    # Page 3: AppImages (Integrator + URL Downloader)
    # -------------------------------------------------------------------------
    def build_appimage_page(self):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        page.set_margin_top(12)
        page.set_margin_bottom(12)
        page.set_margin_start(16)
        page.set_margin_end(16)

        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        pick_btn = Gtk.Button(label="＋ Install Local .AppImage File...")
        pick_btn.add_css_class("install-btn")
        pick_btn.connect("clicked", lambda _b: self.on_pick_appimage())
        actions.append(pick_btn)

        scan_btn = Gtk.Button(label="↻ Rescan ~/Downloads & microSD")
        scan_btn.add_css_class("action-btn")
        scan_btn.connect("clicked", lambda _b: self.populate_appimages())
        actions.append(scan_btn)
        page.append(actions)

        url_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.appimg_url = Gtk.Entry()
        self.appimg_url.set_placeholder_text(
            "🌐  Paste direct .AppImage download URL (https://.../App-x86_64.AppImage)..."
        )
        self.appimg_url.add_css_class("search-entry")
        self.appimg_url.set_hexpand(True)
        url_row.append(self.appimg_url)

        dl_btn = Gtk.Button(label="Download & Integrate")
        dl_btn.add_css_class("action-btn")
        dl_btn.connect("clicked", lambda _b: self.on_download_appimage_url())
        url_row.append(dl_btn)
        page.append(url_row)

        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        self.appimg_list = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        scroll.set_child(self.appimg_list)
        page.append(scroll)

        self.stack.add_named(page, "appimage")

    # -------------------------------------------------------------------------
    # Page 4: Installed & System Updates
    # -------------------------------------------------------------------------
    def build_updates_page(self):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        page.set_margin_top(12)
        page.set_margin_bottom(12)
        page.set_margin_start(16)
        page.set_margin_end(16)

        bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)

        b_fp = Gtk.Button(label="↻ Update All Flatpaks")
        b_fp.add_css_class("install-btn")
        b_fp.connect(
            "clicked",
            lambda _b: self.run_task(
                "Updating all Flatpak applications...",
                ["/usr/bin/transformer-pkg-helper", "flatpak-update"],
            ),
        )
        bar.append(b_fp)

        b_dnf = Gtk.Button(label="↻ Upgrade Fedora Packages (DNF5)")
        b_dnf.add_css_class("action-btn")
        b_dnf.connect(
            "clicked",
            lambda _b: self.run_task(
                "Upgrading Fedora packages via DNF5...",
                ["pkexec", "/usr/bin/transformer-pkg-helper", "dnf-upgrade"],
            ),
        )
        bar.append(b_dnf)

        b_bootc = Gtk.Button(label="↻ Stage OS Image Update (bootc)")
        b_bootc.add_css_class("action-btn")
        b_bootc.connect(
            "clicked",
            lambda _b: self.run_task(
                "Checking & staging TransformerOS bootc image update...",
                ["transformerd", "update", "apply"],
            ),
        )
        bar.append(b_bootc)

        b_ref = Gtk.Button(label="Refresh Installed")
        b_ref.add_css_class("action-btn")
        b_ref.connect("clicked", lambda _b: self.refresh_installed_caches(switch_after=True))
        bar.append(b_ref)
        page.append(bar)

        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        self.installed_list = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        scroll.set_child(self.installed_list)
        page.append(scroll)

        self.stack.add_named(page, "updates")

    # -------------------------------------------------------------------------
    # Helpers & Actions
    # -------------------------------------------------------------------------
    def switch_tab(self, tab_id: str):
        self.stack.set_visible_child_name(tab_id)
        for tid, btn in self.tab_buttons.items():
            if tid == tab_id:
                btn.add_css_class("tab-btn-active")
            else:
                btn.remove_css_class("tab-btn-active")
        if tab_id == "appimage":
            self.populate_appimages()
        elif tab_id == "updates":
            self.populate_installed_overview()

    def clear_box(self, box: Gtk.Box):
        child = box.get_first_child()
        while child is not None:
            nxt = child.get_next_sibling()
            box.remove(child)
            child = nxt

    def append_log(self, text: str):
        buf = self.log_text.get_buffer()
        end_iter = buf.get_end_iter()
        buf.insert(end_iter, text + "\n")

    def make_pkg_row(
        self,
        title: str,
        pkg_id: str,
        summary: str,
        kind_label: str,
        kind_css: str,
        installed: bool,
        on_install,
        on_remove,
        on_launch=None,
    ) -> Gtk.Box:
        card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        card.add_css_class("pkg-card")

        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        left.set_hexpand(True)

        t_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        t_lbl = Gtk.Label(label=title)
        t_lbl.add_css_class("pkg-title")
        t_lbl.set_xalign(0.0)
        t_row.append(t_lbl)

        k_lbl = Gtk.Label(label=kind_label)
        k_lbl.add_css_class(kind_css)
        t_row.append(k_lbl)

        if installed:
            i_lbl = Gtk.Label(label="✓ Installed")
            i_lbl.add_css_class("badge-installed")
            t_row.append(i_lbl)

        left.append(t_row)

        sub_lbl = Gtk.Label(label=f"{pkg_id}  —  {summary}" if pkg_id != title else summary)
        sub_lbl.add_css_class("pkg-sub")
        sub_lbl.set_xalign(0.0)
        sub_lbl.set_wrap(True)
        left.append(sub_lbl)
        card.append(left)

        right = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        right.set_valign(Gtk.Align.CENTER)

        if installed and on_launch is not None:
            l_btn = Gtk.Button(label="▶ Launch")
            l_btn.add_css_class("action-btn")
            l_btn.connect("clicked", lambda _b: on_launch())
            right.append(l_btn)

        if installed:
            if on_remove is not None:
                r_btn = Gtk.Button(label="Remove")
                r_btn.add_css_class("remove-btn")
                r_btn.connect("clicked", lambda _b: on_remove())
                right.append(r_btn)
        else:
            if on_install is not None:
                i_btn = Gtk.Button(label="Install")
                i_btn.add_css_class("install-btn")
                i_btn.connect("clicked", lambda _b: on_install())
                right.append(i_btn)

        card.append(right)
        return card

    def refresh_installed_caches(self, switch_after: bool = False):
        def worker():
            rpms = set()
            try:
                out = subprocess.check_output(
                    ["rpm", "-qa", "--qf", "%{NAME}\n"],
                    text=True,
                    stderr=subprocess.DEVNULL,
                )
                rpms = {ln.strip() for ln in out.splitlines() if ln.strip()}
            except Exception:
                pass

            fps = set()
            try:
                subprocess.run(
                    ["/usr/bin/transformer-pkg-helper", "flathub-init"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                out = subprocess.check_output(
                    ["flatpak", "list", "--app", "--columns=application"],
                    text=True,
                    stderr=subprocess.DEVNULL,
                )
                fps = {ln.strip() for ln in out.splitlines() if ln.strip()}
            except Exception:
                pass

            def finish():
                self.installed_rpms = rpms
                self.installed_flatpaks = fps
                self.populate_curated_fedora()
                self.populate_curated_flatpaks()
                self.populate_appimages()
                self.populate_installed_overview()
                if switch_after:
                    self.switch_tab("updates")
                return False

            GLib.idle_add(finish)

        threading.Thread(target=worker, daemon=True).start()

    def populate_curated_fedora(self):
        self.clear_box(self.rpm_list)
        for pkg, name, desc in CURATED_FEDORA_APPS:
            inst = pkg in self.installed_rpms
            row = self.make_pkg_row(
                title=name,
                pkg_id=pkg,
                summary=desc,
                kind_label="Fedora RPM",
                kind_css="badge-rpm",
                installed=inst,
                on_install=lambda p=pkg: self.run_task(
                    f"Installing Fedora package '{p}'...",
                    ["pkexec", "/usr/bin/transformer-pkg-helper", "dnf-install", p],
                ),
                on_remove=lambda p=pkg: self.run_task(
                    f"Removing Fedora package '{p}'...",
                    ["pkexec", "/usr/bin/transformer-pkg-helper", "dnf-remove", p],
                ),
                on_launch=(
                    (lambda p=pkg: subprocess.Popen([p]))
                    if inst and shutil.which(pkg)
                    else None
                ),
            )
            self.rpm_list.append(row)

    def on_search_fedora(self):
        query = self.rpm_search.get_text().strip()
        if not query:
            self.populate_curated_fedora()
            return
        self.status_lbl.set_text(f"Searching Fedora repositories for '{query}'...")
        self.spinner.start()

        def worker():
            results = []
            try:
                proc = subprocess.run(
                    ["dnf5", "search", "--quiet", query],
                    capture_output=True,
                    text=True,
                    timeout=35,
                )
                seen = set()
                for line in proc.stdout.splitlines():
                    if " : " not in line or line.startswith(" "):
                        continue
                    left, summary = line.split(" : ", 1)
                    pkg_full = left.strip()
                    pkg_name = re.sub(r"\.(x86_64|noarch|i686)$", "", pkg_full)
                    if not pkg_name or pkg_name in seen:
                        continue
                    seen.add(pkg_name)
                    results.append((pkg_name, summary.strip()))
                    if len(results) >= 40:
                        break
            except Exception as exc:
                results = [("Error", str(exc))]

            def finish():
                self.spinner.stop()
                self.clear_box(self.rpm_list)
                self.status_lbl.set_text(
                    f"Found {len(results)} Fedora package(s) matching '{query}'."
                )
                for pkg_name, summary in results:
                    if pkg_name == "Error":
                        lbl = Gtk.Label(label=f"Search error: {summary}")
                        self.rpm_list.append(lbl)
                        continue
                    inst = pkg_name in self.installed_rpms
                    row = self.make_pkg_row(
                        title=pkg_name,
                        pkg_id=pkg_name,
                        summary=summary,
                        kind_label="Fedora RPM",
                        kind_css="badge-rpm",
                        installed=inst,
                        on_install=lambda p=pkg_name: self.run_task(
                            f"Installing Fedora package '{p}'...",
                            ["pkexec", "/usr/bin/transformer-pkg-helper", "dnf-install", p],
                        ),
                        on_remove=lambda p=pkg_name: self.run_task(
                            f"Removing Fedora package '{p}'...",
                            ["pkexec", "/usr/bin/transformer-pkg-helper", "dnf-remove", p],
                        ),
                    )
                    self.rpm_list.append(row)
                return False

            GLib.idle_add(finish)

        threading.Thread(target=worker, daemon=True).start()

    def populate_curated_flatpaks(self):
        self.clear_box(self.fp_list)
        for app_id, name, desc in CURATED_FLATPAKS:
            inst = app_id in self.installed_flatpaks
            row = self.make_pkg_row(
                title=name,
                pkg_id=app_id,
                summary=desc,
                kind_label="Flatpak",
                kind_css="badge-flatpak",
                installed=inst,
                on_install=lambda aid=app_id: self.run_task(
                    f"Installing Flatpak '{aid}' from Flathub...",
                    ["/usr/bin/transformer-pkg-helper", "flatpak-install", aid],
                ),
                on_remove=lambda aid=app_id: self.run_task(
                    f"Removing Flatpak '{aid}'...",
                    ["/usr/bin/transformer-pkg-helper", "flatpak-remove", aid],
                ),
                on_launch=lambda aid=app_id: subprocess.Popen(["flatpak", "run", aid]),
            )
            self.fp_list.append(row)

    def on_search_flatpak(self):
        query = self.fp_search.get_text().strip()
        if not query:
            self.populate_curated_flatpaks()
            return
        self.status_lbl.set_text(f"Searching Flathub for '{query}'...")
        self.spinner.start()

        def worker():
            results = []
            try:
                subprocess.run(
                    ["/usr/bin/transformer-pkg-helper", "flathub-init"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                proc = subprocess.run(
                    [
                        "flatpak",
                        "search",
                        "--columns=name,description,application",
                        query,
                    ],
                    capture_output=True,
                    text=True,
                    timeout=35,
                )
                for line in proc.stdout.splitlines():
                    if "No matches found" in line or not line.strip():
                        continue
                    parts = line.split("\t")
                    if len(parts) >= 3:
                        nm, desc, aid = parts[0].strip(), parts[1].strip(), parts[2].strip()
                        if "." in aid:
                            results.append((aid, nm, desc))
                    if len(results) >= 40:
                        break
            except Exception as exc:
                results = [("error", "Search Error", str(exc))]

            def finish():
                self.spinner.stop()
                self.clear_box(self.fp_list)
                self.status_lbl.set_text(
                    f"Found {len(results)} Flathub application(s) matching '{query}'."
                )
                for aid, nm, desc in results:
                    if aid == "error":
                        self.fp_list.append(Gtk.Label(label=desc))
                        continue
                    inst = aid in self.installed_flatpaks
                    row = self.make_pkg_row(
                        title=nm,
                        pkg_id=aid,
                        summary=desc,
                        kind_label="Flatpak",
                        kind_css="badge-flatpak",
                        installed=inst,
                        on_install=lambda a=aid: self.run_task(
                            f"Installing Flatpak '{a}' from Flathub...",
                            ["/usr/bin/transformer-pkg-helper", "flatpak-install", a],
                        ),
                        on_remove=lambda a=aid: self.run_task(
                            f"Removing Flatpak '{a}'...",
                            ["/usr/bin/transformer-pkg-helper", "flatpak-remove", a],
                        ),
                        on_launch=lambda a=aid: subprocess.Popen(["flatpak", "run", a]),
                    )
                    self.fp_list.append(row)
                return False

            GLib.idle_add(finish)

        threading.Thread(target=worker, daemon=True).start()

    def populate_appimages(self):
        self.clear_box(self.appimg_list)
        items = list_integrated_appimages()
        if not items:
            info = Gtk.Label(
                label="No AppImages found yet in ~/Applications, ~/Downloads, or /var/mnt/EXTRA.\n"
                "Click '＋ Install Local .AppImage File...' or paste an .AppImage URL above to integrate one into your Apps menu."
            )
            info.add_css_class("pkg-sub")
            info.set_margin_top(24)
            self.appimg_list.append(info)
            return

        for item in items:
            ap = item["path"]
            df = item["desktop"]
            integrated = item["integrated"]
            row = self.make_pkg_row(
                title=item["name"],
                pkg_id=os.path.basename(ap),
                summary=item["comment"],
                kind_label="AppImage",
                kind_css="badge-appimage",
                installed=integrated,
                on_install=lambda p=ap: self.install_appimage_direct(p),
                on_remove=lambda p=ap, d=df: self.remove_appimage(p, d),
                on_launch=lambda p=ap: subprocess.Popen([p]),
            )
            self.appimg_list.append(row)

    def install_appimage_direct(self, path: str):
        ok, msg = integrate_appimage_file(path, move_file=False)
        self.status_lbl.set_text(msg)
        self.append_log(msg)
        self.populate_appimages()
        self.populate_installed_overview()
        return False

    def remove_appimage(self, appimage_path: str, desktop_path: str):
        try:
            if desktop_path and os.path.isfile(desktop_path):
                os.remove(desktop_path)
            if appimage_path and os.path.isfile(appimage_path) and appimage_path.startswith(appimage_dir()):
                os.remove(appimage_path)
            subprocess.run(
                ["update-desktop-database", user_apps_dir()],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            self.status_lbl.set_text(f"Removed AppImage {os.path.basename(appimage_path)}.")
        except Exception as exc:
            self.status_lbl.set_text(f"Failed to remove AppImage: {exc}")
        self.populate_appimages()
        self.populate_installed_overview()

    def on_pick_appimage(self):
        dialog = Gtk.FileChooserNative.new(
            "Select an .AppImage File to Integrate",
            self,
            Gtk.FileChooserAction.OPEN,
            "Integrate",
            "Cancel",
        )
        filt = Gtk.FileFilter()
        filt.set_name("AppImage bundles (*.AppImage)")
        filt.add_pattern("*.AppImage")
        filt.add_pattern("*.appimage")
        dialog.add_filter(filt)

        def on_resp(dlg, response):
            if response == Gtk.ResponseType.ACCEPT:
                gfile = dlg.get_file()
                if gfile and gfile.get_path():
                    self.install_appimage_direct(gfile.get_path())
            dlg.destroy()

        dialog.connect("response", on_resp)
        dialog.show()

    def on_download_appimage_url(self):
        url = self.appimg_url.get_text().strip()
        if not url.startswith(("http://", "https://")):
            self.status_lbl.set_text("Enter a valid http:// or https:// .AppImage URL.")
            return
        fname = os.path.basename(url.split("?", 1)[0]) or "Downloaded.AppImage"
        if not fname.lower().endswith(".appimage"):
            fname += ".AppImage"
        dest = os.path.join(appimage_dir(), fname)

        self.status_lbl.set_text(f"Downloading {fname}...")
        self.spinner.start()

        def worker():
            try:
                req = urllib.request.Request(
                    url, headers={"User-Agent": "TransformerOS-Store/1.0"}
                )
                with urllib.request.urlopen(req, timeout=60) as resp, open(dest, "wb") as out:
                    shutil.copyfileobj(resp, out)
                ok, msg = integrate_appimage_file(dest, move_file=False)
            except Exception as exc:
                ok, msg = False, f"Download failed: {exc}"

            def finish():
                self.spinner.stop()
                self.status_lbl.set_text(msg)
                self.append_log(msg)
                if ok:
                    self.appimg_url.set_text("")
                self.populate_appimages()
                self.populate_installed_overview()
                return False

            GLib.idle_add(finish)

        threading.Thread(target=worker, daemon=True).start()

    def populate_installed_overview(self):
        self.clear_box(self.installed_list)

        # 1. Integrated AppImages
        for item in list_integrated_appimages():
            if not item["integrated"]:
                continue
            ap = item["path"]
            df = item["desktop"]
            self.installed_list.append(
                self.make_pkg_row(
                    title=item["name"],
                    pkg_id=os.path.basename(ap),
                    summary=item["comment"],
                    kind_label="AppImage",
                    kind_css="badge-appimage",
                    installed=True,
                    on_install=None,
                    on_remove=lambda p=ap, d=df: self.remove_appimage(p, d),
                    on_launch=lambda p=ap: subprocess.Popen([p]),
                )
            )

        # 2. Installed Flatpaks
        for aid in sorted(self.installed_flatpaks):
            self.installed_list.append(
                self.make_pkg_row(
                    title=aid.split(".")[-1],
                    pkg_id=aid,
                    summary="Installed Flatpak application",
                    kind_label="Flatpak",
                    kind_css="badge-flatpak",
                    installed=True,
                    on_install=None,
                    on_remove=lambda a=aid: self.run_task(
                        f"Removing Flatpak '{a}'...",
                        ["/usr/bin/transformer-pkg-helper", "flatpak-remove", a],
                    ),
                    on_launch=lambda a=aid: subprocess.Popen(["flatpak", "run", a]),
                )
            )

        # 3. Installed Curated Fedora Apps
        for pkg, name, desc in CURATED_FEDORA_APPS:
            if pkg in self.installed_rpms:
                self.installed_list.append(
                    self.make_pkg_row(
                        title=name,
                        pkg_id=pkg,
                        summary=desc,
                        kind_label="Fedora RPM",
                        kind_css="badge-rpm",
                        installed=True,
                        on_install=None,
                        on_remove=lambda p=pkg: self.run_task(
                            f"Removing Fedora package '{p}'...",
                            ["pkexec", "/usr/bin/transformer-pkg-helper", "dnf-remove", p],
                        ),
                        on_launch=(
                            (lambda p=pkg: subprocess.Popen([p]))
                            if shutil.which(pkg)
                            else None
                        ),
                    )
                )

    def run_task(self, description: str, cmd: list[str]):
        if self.busy:
            self.status_lbl.set_text("Another package operation is currently running...")
            return
        self.busy = True
        self.status_lbl.set_text(description)
        self.spinner.start()
        self.append_log(f"$ {' '.join(cmd)}")

        def worker():
            rc = 1
            try:
                proc = subprocess.Popen(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                )
                assert proc.stdout is not None
                for line in proc.stdout:
                    ln = line.rstrip()
                    GLib.idle_add(self.append_log, ln)
                rc = proc.wait()
            except Exception as exc:
                GLib.idle_add(self.append_log, f"Error: {exc}")

            def finish():
                self.busy = False
                self.spinner.stop()
                if rc == 0:
                    self.status_lbl.set_text(f"Completed: {description}")
                else:
                    self.status_lbl.set_text(
                        f"Task exited with code {rc} (click 'Terminal Log' for details)."
                    )
                self.refresh_installed_caches(switch_after=False)
                return False

            GLib.idle_add(finish)

        threading.Thread(target=worker, daemon=True).start()


class StoreApp(Gtk.Application):
    def __init__(self, initial_appimage: str | None = None):
        super().__init__(application_id="org.transformeros.PackageManager")
        self.initial_appimage = initial_appimage

    def do_activate(self):
        win = self.props.active_window
        if not win:
            win = StoreWindow(self, initial_appimage=self.initial_appimage)
        win.present()


def main():
    if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help"):
        print(
            "Usage: transformer-store [--install-appimage <file.AppImage>]\n"
            "TransformerOS Unified Package Manager for Fedora RPMs (DNF5), Flatpaks (Flathub), and AppImages."
        )
        return 0

    initial_appimage = None
    if len(sys.argv) >= 3 and sys.argv[1] == "--install-appimage":
        initial_appimage = sys.argv[2]
    elif len(sys.argv) == 2 and sys.argv[1].lower().endswith(".appimage"):
        initial_appimage = sys.argv[1]

    app = StoreApp(initial_appimage=initial_appimage)
    return app.run([])


if __name__ == "__main__":
    sys.exit(main())
