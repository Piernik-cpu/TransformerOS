pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: bridge

    property bool dockAttached: false
    property bool keyboardAttached: false
    property string effectiveMode: "docked"
    property string modeOverride: "auto"
    property string orientation: "normal"
    property bool rotationLocked: false
    property bool autoBrightness: true
    property real ambientLux: 80.0
    property int brightnessPct: 60
    property int batteryPct: 100
    property string batteryStatus: "Unknown"
    property bool acOnline: false
    property string powerProfile: "balanced"
    property bool gameMode: false
    property bool oskVisible: false
    property bool btPowered: true
    property string updateStatus: "up-to-date"

    property int memUsedMb: 0
    property int memTotalMb: 1858

    property bool quickSettingsOpen: false
    property bool appGridOpen: false
    property string appGridCategory: "All"
    property bool recentsOpen: false
    property bool lockRequested: false
    property var notificationHistory: []

    readonly property bool isTabletMode: effectiveMode === "tablet"
    readonly property string stateFilePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/transformeros/state.json"

    function closePopups() {
        quickSettingsOpen = false;
        appGridOpen = false;
        recentsOpen = false;
    }

    function toggleQuickSettings() {
        const next = !quickSettingsOpen;
        closePopups();
        quickSettingsOpen = next;
        if (next) memView.reload();
    }

    function toggleAppGrid() {
        const next = !appGridOpen;
        closePopups();
        appGridOpen = next;
    }

    function toggleRecents() {
        const next = !recentsOpen;
        closePopups();
        recentsOpen = next;
    }

    function runDaemonCmd(args) {
        Quickshell.execDetached(["transformerd"].concat(args));
        quickRefresh.restart();
    }

    function addNotificationRecord(summary, body, appName) {
        const entry = {
            summary: summary || "Notification",
            body: body || "",
            appName: appName || "System",
            timeStr: Qt.formatTime(new Date(), "hh:mm")
        };
        const arr = [entry].concat(notificationHistory);
        if (arr.length > 15) arr.length = 15;
        notificationHistory = arr;
    }

    function clearNotificationHistory() {
        notificationHistory = [];
    }

    function parseStateText(raw) {
        if (!raw || raw.trim().length === 0) return;
        try {
            const st = JSON.parse(raw);
            if (st.dock_attached !== undefined) dockAttached = !!st.dock_attached;
            if (st.keyboard_attached !== undefined) keyboardAttached = !!st.keyboard_attached;
            if (st.effective_mode) effectiveMode = st.effective_mode;
            if (st.mode_override) modeOverride = st.mode_override;
            if (st.orientation) orientation = st.orientation;
            if (st.rotation_locked !== undefined) rotationLocked = !!st.rotation_locked;
            if (st.auto_brightness !== undefined) autoBrightness = !!st.auto_brightness;
            if (st.ambient_lux !== undefined) ambientLux = st.ambient_lux;
            if (st.brightness_pct !== undefined) brightnessPct = st.brightness_pct;
            if (st.battery_pct !== undefined) batteryPct = st.battery_pct;
            if (st.battery_status) batteryStatus = st.battery_status;
            if (st.ac_online !== undefined) acOnline = !!st.ac_online;
            if (st.power_profile) powerProfile = st.power_profile;
            if (st.game_mode !== undefined) gameMode = !!st.game_mode;
            if (st.osk_visible !== undefined) oskVisible = !!st.osk_visible;
            if (st.bt_powered !== undefined) btPowered = !!st.bt_powered;
            if (st.update_status) updateStatus = st.update_status;
        } catch (e) {}
    }

    function parseMeminfo(raw) {
        if (!raw) return;
        let totalKb = 0;
        let availKb = 0;
        const lines = raw.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const ln = lines[i];
            if (ln.startsWith("MemTotal:")) totalKb = parseInt(ln.replace(/[^0-9]/g, ""), 10) || 0;
            else if (ln.startsWith("MemAvailable:")) availKb = parseInt(ln.replace(/[^0-9]/g, ""), 10) || 0;
        }
        if (totalKb > 0) {
            memTotalMb = Math.round(totalKb / 1024);
            memUsedMb = Math.max(0, Math.round((totalKb - availKb) / 1024));
        }
    }

    FileView {
        id: stateView
        path: bridge.stateFilePath
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: bridge.parseStateText(text())
    }

    FileView {
        id: memView
        path: "/proc/meminfo"
        printErrors: false
        onLoaded: bridge.parseMeminfo(text())
    }

    Timer {
        interval: 900
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            stateView.reload();
            if (bridge.quickSettingsOpen) memView.reload();
        }
    }

    Timer {
        id: quickRefresh
        interval: 150
        repeat: false
        onTriggered: stateView.reload()
    }
}
