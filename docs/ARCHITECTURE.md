# TransformerOS Architecture

## 1. Adaptive 2-in-1 Mode Switching (`transformerd`)

`transformerd` ([transformerd/src/main.rs](file:///mnt/Data/AI_Projects/TransformerOS/transformerd/src/main.rs)) is a zero-dependency Rust daemon (~1.5 MB RSS) that unifies all ASUS T100TAS hardware management in a single process:

| Subsystem | Hardware Path | Behavior |
|---|---|---|
| **Dock Detection** | `/sys/bus/usb/devices/*/idVendor` (`0b05:17e0`) & `/dev/input/by-id/*-event-kbd` | Switches between **Laptop Mode (`docked`)** and **Tablet Mode (`tablet`)** in `< 1s`. Supports manual override (`transformerd mode toggle`) with automatic reset on physical dock attach/detach. |
| **Window Rules (`labwc`)** | `~/.config/labwc/rc.xml` (`rc-docked.xml` ↔ `rc-tablet.xml`) | **Laptop Mode**: Server-side titlebars, free window resizing/positioning.<br>**Tablet Mode**: All windows auto-maximize borderlessly (`serverDecoration="no"`), Android-style bottom nav bar appears. |
| **Screen Rotation** | `iio-sensor-proxy` (`monitor-sensor`) + `/sys/bus/iio/devices/iio:device*/in_accel_{x,y}_raw` (`INVN6500`) + `wlr-randr --output DSI-1` | **Laptop Mode**: Locked to `normal` (landscape).<br>**Tablet Mode**: 4-way accelerometer auto-rotation (`normal`, `90`, `180`, `270`) with hysteresis and lock toggle. |
| **Ambient Light (ALS)** | `iio-sensor-proxy` + `/sys/bus/iio/devices/iio:device*/in_illuminance_*` (`CPLM3218`) + `/sys/class/backlight/intel_backlight` | Exponential moving average (EMA) lux filter mapped logarithmically to `8%–100%` display brightness. |
| **Power & Battery** | `/sys/class/power_supply/ADP1` & `BATC` + `powerprofilesctl` | Calibrates `BATC` charge percentage (fixing the T100TAS `CHARGE_FULL > CHARGE_FULL_DESIGN` ACPI quirk). Auto-selects `performance` on AC/Game Mode, `balanced` on battery `> 20%`, and `power-saver` at `≤ 20%`. |
| **Game Mode** | `transformerd gamemode toggle` | Switches CPU governor/profile to `performance`, pauses ALS and background `bootc` updates. |

---

## 2. Quickshell Adaptive Desktop, Greeter & Lock Screen

1. **Login Greeter ([shell/quickshell/greeter.qml](file:///mnt/Data/AI_Projects/TransformerOS/shell/quickshell/greeter.qml) + [shell/transformer-greeter.py](file:///mnt/Data/AI_Projects/TransformerOS/shell/transformer-greeter.py))**:
   - Speaks the native `greetd` binary JSON IPC protocol over `$GREETD_SOCK`.
   - **Docked:** Displays a classic laptop password box with keyboard focus and no OSK clutter.
   - **Undocked:** Automatically reveals an integrated touch keyboard ([shell/quickshell/TouchKeyboard.qml](file:///mnt/Data/AI_Projects/TransformerOS/shell/quickshell/TouchKeyboard.qml)) and enlarged touch controls, updating live if the dock is attached or detached at the login prompt.
2. **Wayland Session Lock ([shell/quickshell/LockScreen.qml](file:///mnt/Data/AI_Projects/TransformerOS/shell/quickshell/LockScreen.qml))**:
   - Uses `ext-session-lock-v1` (`WlSessionLock`) and native PAM authentication (`Quickshell.Services.Pam`).
3. **Top Status Bar & Android Tablet Bottom Navigation Bar ([shell/quickshell/TopBar.qml](file:///mnt/Data/AI_Projects/TransformerOS/shell/quickshell/TopBar.qml), [shell/quickshell/BottomNavBar.qml](file:///mnt/Data/AI_Projects/TransformerOS/shell/quickshell/BottomNavBar.qml))**:
   - Bottom navigation bar automatically appears in **Tablet Mode** and hides in **Laptop Mode**.
   - Provides **`◀ Back`**, **`● Apps`**, **`■ Recents`** ([shell/quickshell/RecentsOverlay.qml](file:///mnt/Data/AI_Projects/TransformerOS/shell/quickshell/RecentsOverlay.qml)), and **`⌨ Keys`**.
4. **Quick Settings & Atomic Update Panel ([shell/quickshell/QuickSettingsDrawer.qml](file:///mnt/Data/AI_Projects/TransformerOS/shell/quickshell/QuickSettingsDrawer.qml))**:
   - 2×4 grid of large touch tiles (Mode, Rotation Lock, Auto-Brightness, Game Mode, Power Profile, Touch Keyboard, Wi-Fi, Bluetooth), Brightness/Volume sliders, Notification history ([shell/quickshell/NotificationsOverlay.qml](file:///mnt/Data/AI_Projects/TransformerOS/shell/quickshell/NotificationsOverlay.qml)), and One-Tap `bootc` Update & Rollback controls.
5. **Full-Screen Touch App Grid ([shell/quickshell/AppGridOverlay.qml](file:///mnt/Data/AI_Projects/TransformerOS/shell/quickshell/AppGridOverlay.qml))**:
   - Summoned via the **Super / Windows** key (`Super_L` / `Super_R` on release, `XF86HomePage`, `W-d`, `W-Space`) or the top/bottom `Apps` button via [shell/transformer-shell-ipc.sh](file:///mnt/Data/AI_Projects/TransformerOS/shell/transformer-shell-ipc.sh).
   - Touch-friendly launcher with category filtering (`All`, `Internet`, `Media`, `Games`, `Utilities`, `System`), search bar, one-tap OSK button, and direct `📦 Store` shortcut.
6. **Unified Package Manager ([shell/transformer-store.py](file:///mnt/Data/AI_Projects/TransformerOS/shell/transformer-store.py))**:
   - Lightweight GTK4 package manager supporting **Fedora 45 RPMs (`dnf5`)**, **Flatpaks (`Flathub`)**, and **AppImages** (local `.AppImage` desktop integration, `~/Downloads` & `/var/mnt/EXTRA` scanner, and URL installer).
   - Paired with [shell/transformer-pkg-helper.sh](file:///mnt/Data/AI_Projects/TransformerOS/shell/transformer-pkg-helper.sh) and `transformeros-usr-unlock.service` so `sudo dnf install` works seamlessly on the `bootc` system.
