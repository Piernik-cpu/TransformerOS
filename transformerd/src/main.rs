use std::env;
use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

const DOCK_VENDOR: &str = "0b05";
const DOCK_PRODUCT: &str = "17e0";
const DISPLAY_OUTPUT: &str = "DSI-1";

#[derive(Clone, Debug)]
struct ConfigState {
    mode_override: String, // "auto", "docked", "tablet"
    rotation_locked: bool,
    auto_brightness: bool,
    game_mode: bool,
    power_override: String, // "auto", "performance", "balanced", "power-saver"
    brightness_offset: i32,
}

impl Default for ConfigState {
    fn default() -> Self {
        Self {
            mode_override: "auto".to_string(),
            rotation_locked: false,
            auto_brightness: true,
            game_mode: false,
            power_override: "auto".to_string(),
            brightness_offset: 0,
        }
    }
}

#[derive(Clone, Debug)]
struct RuntimeState {
    dock_attached: bool,
    keyboard_attached: bool,
    effective_mode: String, // "docked" or "tablet"
    mode_override: String,
    orientation: String, // "normal", "90", "180", "270"
    rotation_locked: bool,
    auto_brightness: bool,
    ambient_lux: f64,
    brightness_pct: u32,
    battery_pct: u32,
    battery_raw_pct: u32,
    battery_status: String,
    ac_online: bool,
    power_profile: String,
    game_mode: bool,
    osk_visible: bool,
    bt_powered: bool,
    update_status: String,
}

fn config_dir() -> PathBuf {
    if let Ok(xdg) = env::var("XDG_CONFIG_HOME") {
        PathBuf::from(xdg).join("transformeros")
    } else if let Ok(home) = env::var("HOME") {
        PathBuf::from(home).join(".config/transformeros")
    } else {
        PathBuf::from("/tmp/transformeros-config")
    }
}

fn runtime_dir() -> PathBuf {
    if let Ok(xdg) = env::var("XDG_RUNTIME_DIR") {
        PathBuf::from(xdg).join("transformeros")
    } else {
        PathBuf::from("/tmp/transformeros-runtime")
    }
}

fn config_file() -> PathBuf {
    config_dir().join("config.kv")
}

fn state_file() -> PathBuf {
    runtime_dir().join("state.json")
}

fn load_config() -> ConfigState {
    let mut cfg = ConfigState::default();
    if let Ok(content) = fs::read_to_string(config_file()) {
        for line in content.lines() {
            if let Some((k, v)) = line.split_once('=') {
                match k.trim() {
                    "mode_override" => cfg.mode_override = v.trim().to_string(),
                    "rotation_locked" => cfg.rotation_locked = v.trim() == "true",
                    "auto_brightness" => cfg.auto_brightness = v.trim() == "true",
                    "game_mode" => cfg.game_mode = v.trim() == "true",
                    "power_override" => cfg.power_override = v.trim().to_string(),
                    "brightness_offset" => {
                        cfg.brightness_offset = v.trim().parse().unwrap_or(0)
                    }
                    _ => {}
                }
            }
        }
    }
    cfg
}

fn save_config(cfg: &ConfigState) {
    let _ = fs::create_dir_all(config_dir());
    let body = format!(
        "mode_override={}\nrotation_locked={}\nauto_brightness={}\ngame_mode={}\npower_override={}\nbrightness_offset={}\n",
        cfg.mode_override,
        cfg.rotation_locked,
        cfg.auto_brightness,
        cfg.game_mode,
        cfg.power_override,
        cfg.brightness_offset
    );
    let tmp = config_dir().join("config.kv.tmp");
    if fs::write(&tmp, body).is_ok() {
        let _ = fs::rename(&tmp, config_file());
    }
}

fn read_trimmed(path: &Path) -> Option<String> {
    fs::read_to_string(path).ok().map(|s| s.trim().to_string())
}

fn has_dock() -> bool {
    let Ok(entries) = fs::read_dir("/sys/bus/usb/devices") else {
        return false;
    };
    for entry in entries.flatten() {
        let p = entry.path();
        let v = read_trimmed(&p.join("idVendor")).unwrap_or_default();
        let prod = read_trimmed(&p.join("idProduct")).unwrap_or_default();
        if v.eq_ignore_ascii_case(DOCK_VENDOR) && prod.eq_ignore_ascii_case(DOCK_PRODUCT) {
            return true;
        }
    }
    false
}

fn has_keyboard() -> bool {
    if has_dock() {
        return true;
    }
    if let Ok(entries) = fs::read_dir("/dev/input/by-id") {
        for entry in entries.flatten() {
            if let Some(name) = entry.file_name().to_str() {
                if name.ends_with("-event-kbd") {
                    return true;
                }
            }
        }
    }
    false
}

fn read_battery_and_ac() -> (bool, u32, u32, String) {
    let ac_online = read_trimmed(Path::new("/sys/class/power_supply/ADP1/online"))
        .map(|v| v == "1")
        .unwrap_or(false);

    let bat = Path::new("/sys/class/power_supply/BATC");
    let status = read_trimmed(&bat.join("status")).unwrap_or_else(|| "Unknown".to_string());
    let raw_cap: u32 = read_trimmed(&bat.join("capacity"))
        .and_then(|v| v.parse().ok())
        .unwrap_or(100);

    // Compensate for T100TAS ACPI quirk where CHARGE_FULL > CHARGE_FULL_DESIGN
    let charge_now: f64 = read_trimmed(&bat.join("charge_now"))
        .and_then(|v| v.parse().ok())
        .unwrap_or(0.0);
    let charge_full: f64 = read_trimmed(&bat.join("charge_full"))
        .and_then(|v| v.parse().ok())
        .unwrap_or(0.0);
    let charge_design: f64 = read_trimmed(&bat.join("charge_full_design"))
        .and_then(|v| v.parse().ok())
        .unwrap_or(0.0);

    let calibrated = if charge_now > 0.0 && charge_design > 0.0 {
        let denom = if charge_full > 0.0 && charge_full <= charge_design * 1.15 {
            charge_full
        } else {
            charge_design.max(charge_now)
        };
        ((charge_now / denom) * 100.0).round().clamp(0.0, 100.0) as u32
    } else {
        raw_cap.min(100)
    };

    (ac_online, calibrated, raw_cap, status)
}

fn read_ambient_lux() -> Option<f64> {
    let Ok(entries) = fs::read_dir("/sys/bus/iio/devices") else {
        return None;
    };
    for entry in entries.flatten() {
        let p = entry.path();
        if let Some(input_str) = read_trimmed(&p.join("in_illuminance_input")) {
            if let Ok(val) = input_str.parse::<f64>() {
                return Some(val.max(0.0));
            }
        }
        if let Some(raw_str) = read_trimmed(&p.join("in_illuminance_raw")) {
            if let Ok(raw) = raw_str.parse::<f64>() {
                let scale = read_trimmed(&p.join("in_illuminance_scale"))
                    .and_then(|s| s.parse::<f64>().ok())
                    .unwrap_or(1.0);
                return Some((raw * scale).max(0.0));
            }
        }
    }
    None
}

#[derive(Default)]
struct SensorProxyCache {
    orientation: Option<String>,
    lux: Option<f64>,
}

fn map_sensor_proxy_orientation(raw: &str) -> Option<&'static str> {
    match raw {
        "normal" => Some("normal"),
        "bottom-up" => Some("180"),
        "left-up" => Some("90"),
        "right-up" => Some("270"),
        _ => None,
    }
}

fn parse_sensor_proxy_line(line: &str, cache: &Arc<Mutex<SensorProxyCache>>) {
    if let Some((_, rest)) = line.split_once("Accelerometer orientation changed:") {
        let token = rest.split_whitespace().next().unwrap_or("");
        if let Some(mapped) = map_sensor_proxy_orientation(token) {
            if let Ok(mut guard) = cache.lock() {
                guard.orientation = Some(mapped.to_string());
            }
        }
    } else if let Some((_, rest)) = line.split_once("Has accelerometer") {
        if let Some((_, orest)) = rest.split_once("orientation:") {
            let token = orest
                .split(|c: char| c == ',' || c == ')' || c.is_whitespace())
                .find(|s| !s.is_empty())
                .unwrap_or("");
            if let Some(mapped) = map_sensor_proxy_orientation(token) {
                if let Ok(mut guard) = cache.lock() {
                    guard.orientation = Some(mapped.to_string());
                }
            }
        }
    }

    if let Some((_, rest)) = line.split_once("Light changed:") {
        let num_str = rest.split_whitespace().next().unwrap_or("").replace(',', ".");
        if let Ok(val) = num_str.parse::<f64>() {
            if let Ok(mut guard) = cache.lock() {
                guard.lux = Some(val.max(0.0));
            }
        }
    } else if let Some((_, rest)) = line.split_once("Has ambient light sensor") {
        if let Some((_, vrest)) = rest.split_once("value:") {
            let num_str = vrest
                .split(|c: char| c == ',' || c == ')' || c.is_whitespace())
                .find(|s| !s.is_empty())
                .unwrap_or("")
                .replace(',', ".");
            if let Ok(val) = num_str.parse::<f64>() {
                if let Ok(mut guard) = cache.lock() {
                    guard.lux = Some(val.max(0.0));
                }
            }
        }
    }
}

fn spawn_sensor_proxy_reader(cache: Arc<Mutex<SensorProxyCache>>) {
    thread::spawn(move || loop {
        if let Ok(mut child) = Command::new("monitor-sensor")
            .env("LC_ALL", "C")
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
        {
            if let Some(stdout) = child.stdout.take() {
                let reader = BufReader::new(stdout);
                for line in reader.lines().map_while(Result::ok) {
                    parse_sensor_proxy_line(&line, &cache);
                }
            }
            let _ = child.wait();
        }
        thread::sleep(Duration::from_secs(3));
    });
}

fn read_accel_orientation(current: &str, proxy_orient: Option<&str>) -> Option<String> {
    if let Some(mapped) = proxy_orient {
        return Some(mapped.to_string());
    }
    let Ok(entries) = fs::read_dir("/sys/bus/iio/devices") else {
        return None;
    };
    for entry in entries.flatten() {
        let p = entry.path();
        let Some(x_str) = read_trimmed(&p.join("in_accel_x_raw")) else {
            continue;
        };
        let Some(y_str) = read_trimmed(&p.join("in_accel_y_raw")) else {
            continue;
        };
        let Ok(x_raw) = x_str.parse::<f64>() else {
            continue;
        };
        let Ok(y_raw) = y_str.parse::<f64>() else {
            continue;
        };
        let scale = read_trimmed(&p.join("in_accel_scale"))
            .and_then(|s| s.parse::<f64>().ok())
            .unwrap_or(0.001);
        let gx = x_raw * scale;
        let gy = y_raw * scale;

        // Require clear dominant axis >= 4.5 m/s^2 for hysteresis stability
        let threshold = 4.5;
        if gx.abs() < threshold && gy.abs() < threshold {
            return Some(current.to_string());
        }
        if gy.abs() >= gx.abs() * 1.25 {
            if gy < -threshold {
                return Some("normal".to_string());
            } else if gy > threshold {
                return Some("180".to_string());
            }
        } else if gx.abs() >= gy.abs() * 1.25 {
            if gx > threshold {
                return Some("270".to_string());
            } else if gx < -threshold {
                return Some("90".to_string());
            }
        }
        return Some(current.to_string());
    }
    None
}

fn find_backlight_dir() -> Option<PathBuf> {
    for name in ["intel_backlight", "acpi_video0", "acpi_video1"] {
        let p = Path::new("/sys/class/backlight").join(name);
        if p.join("brightness").exists() && p.join("max_brightness").exists() {
            return Some(p);
        }
    }
    let entries = fs::read_dir("/sys/class/backlight").ok()?;
    for entry in entries.flatten() {
        let p = entry.path();
        if p.join("brightness").exists() && p.join("max_brightness").exists() {
            return Some(p);
        }
    }
    None
}

fn get_backlight_pct() -> u32 {
    let Some(bl) = find_backlight_dir() else {
        return 50;
    };
    let cur: f64 = read_trimmed(&bl.join("brightness"))
        .and_then(|v| v.parse().ok())
        .unwrap_or(50.0);
    let max: f64 = read_trimmed(&bl.join("max_brightness"))
        .and_then(|v| v.parse().ok())
        .unwrap_or(100.0);
    if max <= 0.0 {
        return 50;
    }
    ((cur / max) * 100.0).round().clamp(5.0, 100.0) as u32
}

fn set_backlight_pct(pct: u32) {
    let clamped = pct.clamp(5, 100);
    if let Some(bl) = find_backlight_dir() {
        if let Some(max_str) = read_trimmed(&bl.join("max_brightness")) {
            if let Ok(max_val) = max_str.parse::<f64>() {
                let target = ((clamped as f64 / 100.0) * max_val).round() as u32;
                if fs::write(bl.join("brightness"), format!("{}\n", target)).is_ok() {
                    return;
                }
            }
        }
    }
    let _ = Command::new("brightnessctl")
        .args(["--quiet", "set", &format!("{}%", clamped)])
        .status();
}

fn lux_to_brightness_pct(lux: f64, offset: i32) -> u32 {
    // Smooth logarithmic curve: 0..5 lux -> 15%, 50 lux -> 45%, 300 lux -> 75%, 1000+ lux -> 100%
    let base = if lux <= 2.0 {
        15.0
    } else {
        (15.0 + 28.0 * (lux + 1.0).log10()).clamp(12.0, 100.0)
    };
    (base as i32 + offset).clamp(8, 100) as u32
}

fn apply_display_transform(transform: &str) {
    let _ = Command::new("wlr-randr")
        .args(["--output", DISPLAY_OUTPUT, "--transform", transform])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

fn ensure_wvkbd_running() {
    let status = Command::new("pgrep")
        .args(["-x", "wvkbd-mobintl"])
        .stdout(Stdio::null())
        .status();
    if status.map(|s| !s.success()).unwrap_or(true) {
        let _ = Command::new("wvkbd-mobintl")
            .args([
                "--hidden",
                "-H",
                "250",
                "-L",
                "210",
                "--fn",
                "Sans 15",
                "--bg",
                "181a20",
                "--fg",
                "262934",
                "--fg-sp",
                "1f222b",
                "--press",
                "3daee9",
                "--press-sp",
                "3daee9",
                "--text",
                "f0f4f8",
                "--text-sp",
                "f0f4f8",
            ])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn();
        thread::sleep(Duration::from_millis(250));
    }
}

fn set_osk_visible(show: bool) {
    ensure_wvkbd_running();
    let sig = if show { "-USR2" } else { "-USR1" };
    let _ = Command::new("pkill")
        .args([sig, "-x", "wvkbd-mobintl"])
        .status();
}

fn toggle_osk() -> bool {
    ensure_wvkbd_running();
    let _ = Command::new("pkill")
        .args(["-RTMIN", "-x", "wvkbd-mobintl"])
        .status();
    true
}

fn has_bluetooth_powered() -> bool {
    let mut rfkill_unblocked = true;
    if let Ok(entries) = fs::read_dir("/sys/class/rfkill") {
        for entry in entries.flatten() {
            let p = entry.path();
            if read_trimmed(&p.join("type")).as_deref() == Some("bluetooth") {
                let soft = read_trimmed(&p.join("soft")).unwrap_or_default();
                let hard = read_trimmed(&p.join("hard")).unwrap_or_default();
                if soft != "0" || hard != "0" {
                    rfkill_unblocked = false;
                }
            }
        }
    }
    if !rfkill_unblocked {
        return false;
    }
    if let Ok(out) = Command::new("bluetoothctl").arg("show").output() {
        if out.status.success() {
            let s = String::from_utf8_lossy(&out.stdout);
            for line in s.lines() {
                let t = line.trim();
                if let Some(rest) = t.strip_prefix("Powered:") {
                    return rest.trim() == "yes";
                }
            }
        }
    }
    fs::read_dir("/sys/class/bluetooth")
        .map(|mut d| d.next().is_some())
        .unwrap_or(false)
}

fn set_bluetooth_powered(enable: bool) {
    if enable {
        let _ = Command::new("rfkill")
            .args(["unblock", "bluetooth"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
        let _ = Command::new("bluetoothctl")
            .args(["power", "on"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    } else {
        let _ = Command::new("bluetoothctl")
            .args(["power", "off"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
        let _ = Command::new("rfkill")
            .args(["block", "bluetooth"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }
}

fn apply_labwc_mode(mode: &str) {
    let Ok(home) = env::var("HOME") else {
        return;
    };
    let labwc_dir = PathBuf::from(&home).join(".config/labwc");
    let target_rc = if mode == "tablet" {
        labwc_dir.join("rc-tablet.xml")
    } else {
        labwc_dir.join("rc-docked.xml")
    };
    let active_rc = labwc_dir.join("rc.xml");
    if target_rc.exists() {
        if let Ok(content) = fs::read(&target_rc) {
            let _ = fs::write(&active_rc, content);
            let _ = Command::new("labwc")
                .arg("--reconfigure")
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status();
        }
    }
    if mode == "tablet" {
        let _ = Command::new("t100-window-ctl")
            .arg("maximize-all")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }
    // Signal Waybar custom modules if active
    let _ = Command::new("pkill")
        .args(["-RTMIN+8", "waybar"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    let _ = Command::new("pkill")
        .args(["-RTMIN+10", "waybar"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

fn apply_power_profile(profile: &str) {
    let _ = Command::new("powerprofilesctl")
        .args(["set", profile])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

fn notify(summary: &str, body: &str) {
    let _ = Command::new("notify-send")
        .args(["-a", "TransformerOS", "-t", "2500", summary, body])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
}

fn write_state(st: &RuntimeState) {
    let _ = fs::create_dir_all(runtime_dir());
    let json = format!(
        concat!(
            "{{\n",
            "  \"dock_attached\": {},\n",
            "  \"keyboard_attached\": {},\n",
            "  \"effective_mode\": \"{}\",\n",
            "  \"mode_override\": \"{}\",\n",
            "  \"orientation\": \"{}\",\n",
            "  \"rotation_locked\": {},\n",
            "  \"auto_brightness\": {},\n",
            "  \"ambient_lux\": {:.1},\n",
            "  \"brightness_pct\": {},\n",
            "  \"battery_pct\": {},\n",
            "  \"battery_raw_pct\": {},\n",
            "  \"battery_status\": \"{}\",\n",
            "  \"ac_online\": {},\n",
            "  \"power_profile\": \"{}\",\n",
            "  \"game_mode\": {},\n",
            "  \"osk_visible\": {},\n",
            "  \"bt_powered\": {},\n",
            "  \"update_status\": \"{}\"\n",
            "}}\n"
        ),
        st.dock_attached,
        st.keyboard_attached,
        st.effective_mode,
        st.mode_override,
        st.orientation,
        st.rotation_locked,
        st.auto_brightness,
        st.ambient_lux,
        st.brightness_pct,
        st.battery_pct,
        st.battery_raw_pct,
        st.battery_status,
        st.ac_online,
        st.power_profile,
        st.game_mode,
        st.osk_visible,
        st.bt_powered,
        st.update_status
    );
    let tmp = runtime_dir().join("state.json.tmp");
    if let Ok(mut f) = fs::File::create(&tmp) {
        let _ = f.write_all(json.as_bytes());
        let _ = fs::rename(&tmp, state_file());
    }
}

fn compute_state(cfg: &ConfigState, prev_orient: &str, ema_lux: f64) -> RuntimeState {
    compute_state_with_proxy(cfg, prev_orient, ema_lux, None)
}

fn compute_state_with_proxy(
    cfg: &ConfigState,
    prev_orient: &str,
    ema_lux: f64,
    proxy_orient: Option<&str>,
) -> RuntimeState {
    let dock = has_dock();
    let kbd = has_keyboard();
    let effective_mode = match cfg.mode_override.as_str() {
        "docked" => "docked".to_string(),
        "tablet" => "tablet".to_string(),
        _ => {
            if dock || kbd {
                "docked".to_string()
            } else {
                "tablet".to_string()
            }
        }
    };

    let orientation = if effective_mode == "docked" {
        "normal".to_string()
    } else if cfg.rotation_locked {
        prev_orient.to_string()
    } else {
        read_accel_orientation(prev_orient, proxy_orient)
            .unwrap_or_else(|| prev_orient.to_string())
    };

    let (ac_online, bat_pct, bat_raw, bat_status) = read_battery_and_ac();
    let power_profile = if cfg.game_mode {
        "performance".to_string()
    } else if cfg.power_override != "auto" {
        cfg.power_override.clone()
    } else if ac_online {
        "performance".to_string()
    } else if bat_pct <= 20 {
        "power-saver".to_string()
    } else {
        "balanced".to_string()
    };

    let brightness_pct = get_backlight_pct();
    let update_status = read_trimmed(&runtime_dir().join("update_status"))
        .unwrap_or_else(|| "up-to-date".to_string());

    RuntimeState {
        dock_attached: dock,
        keyboard_attached: kbd,
        effective_mode: effective_mode.clone(),
        mode_override: cfg.mode_override.clone(),
        orientation,
        rotation_locked: cfg.rotation_locked,
        auto_brightness: cfg.auto_brightness,
        ambient_lux: ema_lux,
        brightness_pct,
        battery_pct: bat_pct,
        battery_raw_pct: bat_raw,
        battery_status: bat_status,
        ac_online,
        power_profile,
        game_mode: cfg.game_mode,
        osk_visible: effective_mode == "tablet",
        bt_powered: has_bluetooth_powered(),
        update_status,
    }
}

fn run_daemon() {
    let sensor_cache = Arc::new(Mutex::new(SensorProxyCache::default()));
    spawn_sensor_proxy_reader(Arc::clone(&sensor_cache));

    let mut prev_mode = String::new();
    let mut prev_hw_docked: Option<bool> = None;
    let mut prev_orient = "normal".to_string();
    let mut prev_power = String::new();
    let mut prev_brightness: u32 = get_backlight_pct();
    let mut last_applied_brightness: u32 = prev_brightness;
    let mut ema_lux: f64 = read_ambient_lux().unwrap_or(80.0);
    let mut last_light_apply = Instant::now() - Duration::from_secs(10);
    let mut low_bat_notified = false;

    loop {
        let mut cfg = load_config();
        let hw_docked = has_dock() || has_keyboard();
        if let Some(prev_hw) = prev_hw_docked {
            if hw_docked != prev_hw && cfg.mode_override != "auto" {
                cfg.mode_override = "auto".to_string();
                save_config(&cfg);
            }
        }
        prev_hw_docked = Some(hw_docked);

        let (proxy_orient, proxy_lux) = if let Ok(guard) = sensor_cache.lock() {
            (guard.orientation.clone(), guard.lux)
        } else {
            (None, None)
        };
        if let Some(lux) = read_ambient_lux().or(proxy_lux) {
            ema_lux = ema_lux * 0.75 + lux * 0.25;
        }

        let mut st = compute_state_with_proxy(&cfg, &prev_orient, ema_lux, proxy_orient.as_deref());

        // Preserve external manual brightness changes cleanly by adapting offset
        if cfg.auto_brightness && st.brightness_pct.abs_diff(last_applied_brightness) >= 4 {
            let base = lux_to_brightness_pct(ema_lux, 0) as i32;
            cfg.brightness_offset = (st.brightness_pct as i32 - base).clamp(-60, 60);
            save_config(&cfg);
            last_applied_brightness = st.brightness_pct;
            prev_brightness = st.brightness_pct;
        }

        if st.effective_mode != prev_mode {
            apply_labwc_mode(&st.effective_mode);
            if st.effective_mode == "tablet" {
                set_osk_visible(false); // Ready in background; summoned on tap or bottom nav
                if !prev_mode.is_empty() {
                    notify(
                        "Tablet Mode Active",
                        "Maximized touch windows, bottom navigation bar & auto-rotation enabled",
                    );
                }
            } else {
                set_osk_visible(false);
                apply_display_transform("normal");
                st.orientation = "normal".to_string();
                if !prev_mode.is_empty() {
                    notify(
                        "Laptop Mode Active",
                        "Dock connected — desktop windows & physical keyboard active",
                    );
                }
            }
            prev_mode = st.effective_mode.clone();
        }

        if st.orientation != prev_orient {
            apply_display_transform(&st.orientation);
            prev_orient = st.orientation.clone();
        }

        if st.power_profile != prev_power {
            apply_power_profile(&st.power_profile);
            prev_power = st.power_profile.clone();
        }

        if !st.ac_online && st.battery_pct <= 20 && !low_bat_notified {
            notify(
                "Low Battery (20%)",
                "Switched automatically to Power Saver profile",
            );
            low_bat_notified = true;
        } else if st.ac_online || st.battery_pct > 25 {
            low_bat_notified = false;
        }

        if cfg.auto_brightness
            && !cfg.game_mode
            && last_light_apply.elapsed() >= Duration::from_secs(3)
        {
            let target_b = lux_to_brightness_pct(ema_lux, cfg.brightness_offset);
            if target_b.abs_diff(prev_brightness) >= 4 {
                set_backlight_pct(target_b);
                prev_brightness = target_b;
                last_applied_brightness = target_b;
                st.brightness_pct = target_b;
                last_light_apply = Instant::now();
            }
        }

        write_state(&st);
        thread::sleep(Duration::from_millis(600));
    }
}

fn print_waybar_mode() {
    let cfg = load_config();
    let st = compute_state(&cfg, "normal", 80.0);
    if st.effective_mode == "tablet" {
        println!(
            "{{\"text\":\"Tablet\",\"class\":\"tablet\",\"tooltip\":\"Tablet Mode active (tap to switch or open Quick Settings)\"}}"
        );
    } else {
        println!(
            "{{\"text\":\"Laptop\",\"class\":\"docked\",\"tooltip\":\"Laptop Mode active (dock attached)\"}}"
        );
    }
}

fn print_waybar_rotate() {
    let cfg = load_config();
    let st = compute_state(&cfg, "normal", 80.0);
    if st.rotation_locked {
        println!(
            "{{\"text\":\"🔒 Rot:Lock\",\"class\":\"locked\",\"tooltip\":\"Rotation locked (tap to unlock)\"}}"
        );
    } else if st.effective_mode == "docked" {
        println!(
            "{{\"text\":\"Rot:Dock\",\"class\":\"docked\",\"tooltip\":\"Locked to landscape while docked\"}}"
        );
    } else {
        println!(
            "{{\"text\":\"↻ Rot:Auto\",\"class\":\"auto\",\"tooltip\":\"Auto-rotate enabled (tap to lock)\"}}"
        );
    }
}

fn print_waybar_gamemode() {
    let cfg = load_config();
    if cfg.game_mode {
        println!(
            "{{\"text\":\"Game:ON\",\"class\":\"active\",\"tooltip\":\"Game Mode ON (Performance profile, background updates paused)\"}}"
        );
    } else {
        println!(
            "{{\"text\":\"Game\",\"class\":\"inactive\",\"tooltip\":\"Tap to enable Game Mode\"}}"
        );
    }
}

fn handle_update_cmd(action: &str) {
    let _ = fs::create_dir_all(runtime_dir());
    let status_path = runtime_dir().join("update_status");
    match action {
        "check" => {
            let _ = fs::write(&status_path, "checking\n");
            notify("System Update", "Checking for TransformerOS image updates...");
            let out = Command::new("pkexec")
                .args(["bootc", "upgrade", "--check"])
                .output();
            match out {
                Ok(o) if o.status.success() => {
                    let stdout = String::from_utf8_lossy(&o.stdout);
                    let stderr = String::from_utf8_lossy(&o.stderr);
                    if stdout.contains("No changes")
                        || stderr.contains("No changes")
                        || (stdout.trim().is_empty() && stderr.trim().is_empty())
                    {
                        let _ = fs::write(&status_path, "up-to-date\n");
                        notify("TransformerOS is Up to Date", "Running the latest atomic image.");
                    } else {
                        let _ = fs::write(&status_path, "update-available\n");
                        notify("Update Available", "Tap Update in Quick Settings to stage it.");
                    }
                }
                _ => {
                    let _ = fs::write(&status_path, "up-to-date\n");
                }
            }
        }
        "apply" | "upgrade" => {
            let _ = fs::write(&status_path, "updating\n");
            notify(
                "Downloading Update",
                "Staging new TransformerOS image in the background...",
            );
            let st = Command::new("pkexec").args(["bootc", "upgrade"]).status();
            if st.map(|s| s.success()).unwrap_or(false) {
                let _ = fs::write(&status_path, "ready-to-reboot\n");
                notify(
                    "Update Staged & Ready",
                    "Reboot at your convenience to activate the new image.",
                );
            } else {
                let _ = fs::write(&status_path, "error\n");
                notify("Update Check Finished", "No new deployment staged.");
            }
        }
        "rollback" => {
            notify("Rolling Back", "Switching default boot entry to previous deployment...");
            let st = Command::new("pkexec").args(["bootc", "rollback"]).status();
            if st.map(|s| s.success()).unwrap_or(false) {
                let _ = fs::write(&status_path, "rollback-staged\n");
                notify("Rollback Ready", "Reboot to return to the previous system image.");
            }
        }
        _ => {}
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let cmd = args.get(1).map(|s| s.as_str()).unwrap_or("status");
    let sub = args.get(2).map(|s| s.as_str()).unwrap_or("toggle");

    match cmd {
        "daemon" => run_daemon(),
        "status" => {
            if let Ok(s) = fs::read_to_string(state_file()) {
                print!("{}", s);
            } else {
                let cfg = load_config();
                let st = compute_state(&cfg, "normal", read_ambient_lux().unwrap_or(80.0));
                write_state(&st);
                if let Ok(s) = fs::read_to_string(state_file()) {
                    print!("{}", s);
                }
            }
        }
        "waybar-mode" => print_waybar_mode(),
        "waybar-rotate" => print_waybar_rotate(),
        "waybar-gamemode" => print_waybar_gamemode(),
        "mode" => {
            let mut cfg = load_config();
            let cur = compute_state(&cfg, "normal", 80.0);
            let hw_mode = if cur.dock_attached || cur.keyboard_attached {
                "docked"
            } else {
                "tablet"
            };
            cfg.mode_override = match sub {
                "auto" => "auto".to_string(),
                "docked" | "laptop" => "docked".to_string(),
                "tablet" => "tablet".to_string(),
                _ => {
                    let target = if cur.effective_mode == "tablet" {
                        "docked"
                    } else {
                        "tablet"
                    };
                    if target == hw_mode {
                        "auto".to_string()
                    } else {
                        target.to_string()
                    }
                }
            };
            save_config(&cfg);
            let next = compute_state(&cfg, "normal", 80.0);
            apply_labwc_mode(&next.effective_mode);
            write_state(&next);
        }
        "bluetooth" => {
            let cur = has_bluetooth_powered();
            let target = match sub {
                "on" | "enable" => true,
                "off" | "disable" => false,
                _ => !cur,
            };
            set_bluetooth_powered(target);
            let cfg = load_config();
            let mut next = compute_state(&cfg, "normal", read_ambient_lux().unwrap_or(80.0));
            next.bt_powered = target;
            write_state(&next);
        }
        "rotate" => {
            let mut cfg = load_config();
            cfg.rotation_locked = match sub {
                "lock" => true,
                "unlock" => false,
                _ => !cfg.rotation_locked,
            };
            save_config(&cfg);
            notify(
                "Screen Rotation",
                if cfg.rotation_locked {
                    "Auto-rotation locked"
                } else {
                    "Auto-rotation enabled"
                },
            );
            let _ = Command::new("pkill").args(["-RTMIN+10", "waybar"]).status();
        }
        "autobrightness" => {
            let mut cfg = load_config();
            cfg.auto_brightness = match sub {
                "on" => true,
                "off" => false,
                _ => !cfg.auto_brightness,
            };
            save_config(&cfg);
            notify(
                "Auto-Brightness",
                if cfg.auto_brightness {
                    "Ambient light sensor enabled"
                } else {
                    "Manual brightness active"
                },
            );
        }
        "gamemode" => {
            let mut cfg = load_config();
            cfg.game_mode = match sub {
                "on" => true,
                "off" => false,
                _ => !cfg.game_mode,
            };
            save_config(&cfg);
            let next = compute_state(&cfg, "normal", 80.0);
            apply_power_profile(&next.power_profile);
            write_state(&next);
            notify(
                if cfg.game_mode {
                    "Game Mode Enabled"
                } else {
                    "Game Mode Disabled"
                },
                if cfg.game_mode {
                    "Performance CPU profile active; auto-brightness & updates paused"
                } else {
                    "Restored automatic power & sensor management"
                },
            );
            let _ = Command::new("pkill").args(["-RTMIN+8", "waybar"]).status();
        }
        "power" => {
            let mut cfg = load_config();
            cfg.power_override = match sub {
                "performance" | "balanced" | "power-saver" | "auto" => sub.to_string(),
                _ => "auto".to_string(),
            };
            save_config(&cfg);
            let next = compute_state(&cfg, "normal", 80.0);
            apply_power_profile(&next.power_profile);
            write_state(&next);
            notify(
                "Power Profile",
                &format!("Active profile: {}", next.power_profile),
            );
        }
        "brightness" => {
            let cur = get_backlight_pct() as i32;
            let target = match sub {
                "up" => (cur + 5).clamp(5, 100) as u32,
                "down" => (cur - 5).clamp(5, 100) as u32,
                s if s.starts_with('+') => {
                    let delta: i32 = s[1..].parse().unwrap_or(5);
                    (cur + delta).clamp(5, 100) as u32
                }
                s if s.starts_with('-') => {
                    let delta: i32 = s[1..].parse().unwrap_or(5);
                    (cur - delta).clamp(5, 100) as u32
                }
                other => other.parse::<u32>().unwrap_or(cur as u32).clamp(5, 100),
            };
            set_backlight_pct(target);
            let mut cfg = load_config();
            let lux = read_ambient_lux().unwrap_or(80.0);
            let base = lux_to_brightness_pct(lux, 0) as i32;
            cfg.brightness_offset = (target as i32 - base).clamp(-60, 60);
            save_config(&cfg);
            let next = compute_state(&cfg, "normal", lux);
            write_state(&next);
        }
        "osk" => match sub {
            "show" => set_osk_visible(true),
            "hide" => set_osk_visible(false),
            _ => {
                toggle_osk();
            }
        },
        "update" => handle_update_cmd(sub),
        _ => {
            eprintln!(
                "Usage: transformerd [daemon|status|mode|rotate|autobrightness|brightness|gamemode|power|osk|update]"
            );
        }
    }
}
