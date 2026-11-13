# TransformerOS Architecture

## 1. Adaptive 2-in-1 Mode Switching (`transformerd`)

`transformerd` ([transformerd/src/main.rs](file:///mnt/Data/AI_Projects/TransformerOS/transformerd/src/main.rs)) is a zero-dependency Rust daemon (~1.5 MB RSS) that unifies all ASUS T100TAS hardware management in a single process:

| Subsystem | Hardware Path | Behavior |
|---|---|---|
| **Dock Detection** | `/sys/bus/usb/devices/*/idVendor` (`0b05:17e0`) & `/dev/input/by-id/*-event-kbd` | Switches between **Laptop Mode (`docked`)** and **Tablet Mode (`tablet`)** in `< 1s`. Supports manual override (`transformerd mode toggle`). |
| **Window Rules (`labwc`)** | `~/.config/labwc/rc.xml` (`rc-docked.xml` ↔ `rc-tablet.xml`) | **Laptop Mode**: Server-side titlebars, free window resizing/positioning.<br>**Tablet Mode**: All windows auto-maximize borderlessly (`serverDecoration="no"`), Android-style bottom nav bar appears. |
| **Screen Rotation** | `/sys/bus/iio/devices/iio:device*/in_accel_{x,y}_raw` (`INVN6500`) + `wlr-randr --output DSI-1` | **Laptop Mode**: Locked to `normal` (landscape).<br>**Tablet Mode**: 4-way accelerometer auto-rotation (`normal`, `90`, `180`, `270`) with 4.5 m/s² hysteresis and lock toggle. |
| **Ambient Light (ALS)** | `/sys/bus/iio/devices/iio:device*/in_illuminance_*` (`CPLM3218`) + `/sys/class/backlight/intel_backlight` | Exponential moving average (EMA) lux filter mapped logarithmically to `8%–100%` display brightness. |
| **Power & Battery** | `/sys/class/power_supply/ADP1` & `BATC` + `powerprofilesctl` | Calibrates `BATC` charge percentage (fixing the T100TAS `CHARGE_FULL > CHARGE_FULL_DESIGN` ACPI quirk). Auto-selects `performance` on AC/Game Mode, `balanced` on battery `> 20%`, and `power-saver` at `≤ 20%`. |
| **Game Mode** | `transformerd gamemode toggle` | Switches CPU governor/profile to `performance`, pauses ALS and background `bootc` updates. |

---

## 2. Adaptive Login Greeter & Touch Shell

1. **Login & Lock Screen ([shell/transformer-greeter.py](file:///mnt/Data/AI_Projects/TransformerOS/shell/transformer-greeter.py))**:
   - Speaks the native `greetd` binary JSON IPC protocol over `$GREETD_SOCK`.
   - **Docked:** Displays a classic laptop password box with keyboard focus and no OSK clutter.
   - **Undocked:** Automatically reveals a built-in touch keyboard/keypad and enlarged touch controls, updating live if the dock is attached or detached at the login prompt.
2. **Android Tablet Bottom Navigation Bar ([shell/transformer-shell.py](file:///mnt/Data/AI_Projects/TransformerOS/shell/transformer-shell.py) `bar`)**:
   - Uses `gtk4-layer-shell` (`LAYER_TOP`, bottom exclusive zone `50px`).
   - Automatically appears in **Tablet Mode** and hides in **Laptop Mode**.
   - Provides **`◀ Back`**, **`● Home (App Grid)`**, **`■ Recents`**, **`⌨ Keyboard`**, and **`⚙ Quick Settings`**.
3. **Quick Settings & Atomic Update Panel (`transformer-shell qs`)**:
   - 2×4 grid of large touch tiles (Mode, Rotation Lock, Auto-Brightness, Game Mode, Power Profile, Touch Keyboard, Wi-Fi, Bluetooth), Brightness/Volume sliders, and One-Tap `bootc` Update & Rollback controls.
4. **Full-Screen Touch App Grid (`transformer-shell appgrid`)**:
   - Touch-friendly launcher with large application tiles, search bar, and one-tap OSK button.
