import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Networking

Scope {
    id: qsRoot
    LazyLoader {
        active: StateBridge.quickSettingsOpen
        component: Component {
            PanelWindow {
                id: qsWin
                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"

                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property int curVol: sink && sink.audio ? Math.round((sink.audio.volume || 0) * 100) : 50
    readonly property bool curMuted: sink && sink.audio ? !!sink.audio.muted : false

    PwObjectTracker {
        objects: qsWin.sink ? [qsWin.sink] : []
    }

    function cyclePower() {
        const order = ["auto", "performance", "balanced", "power-saver"];
        const cur = StateBridge.powerProfile || "balanced";
        const nxt = order[(order.indexOf(cur) + 1) % order.length];
        StateBridge.runDaemonCmd(["power", nxt]);
    }

    Rectangle {
        anchors.fill: parent
        color: "#66050810"
        focus: true

        Keys.onEscapePressed: StateBridge.quickSettingsOpen = false

        TapHandler {
            onTapped: StateBridge.quickSettingsOpen = false
        }

        Rectangle {
            id: drawerCard
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: StateBridge.isTabletMode ? 48 : 40
            anchors.rightMargin: 12
            width: Math.min(460, parent.width - 24)
            height: Math.min(parent.height - 64, drawerContent.implicitHeight + 32)
            radius: 18
            color: "#f2131b2b"
            border.width: 1
            border.color: Theme.borderSubtle

            // Prevent backdrop tap from closing drawer when tapping non-button areas inside card
            TapHandler {}

            Flickable {
                anchors.fill: parent
                anchors.margins: 16
                contentHeight: drawerContent.implicitHeight
                clip: true

                Column {
                    id: drawerContent
                    width: parent.width
                    spacing: 12

                    // Header summary + close button
                    Row {
                        width: parent.width
                        spacing: 8

                        Column {
                            width: parent.width - 46
                            Text {
                                text: "Quick Settings  •  " + StateBridge.batteryPct + "% (" + StateBridge.batteryStatus + ")"
                                color: Theme.textPrimary
                                font.family: Theme.fontSans
                                font.pixelSize: 15
                                font.weight: Font.Bold
                            }
                            Text {
                                text: Math.round(StateBridge.ambientLux) + " lux  •  "
                                    + StateBridge.powerProfile + "  •  RAM "
                                    + StateBridge.memUsedMb + "/" + StateBridge.memTotalMb + " MB"
                                color: Theme.textSecondary
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                            }
                        }

                        Rectangle {
                            width: 38
                            height: 38
                            radius: 10
                            color: Theme.bgTile

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                color: Theme.textPrimary
                                font.pixelSize: 15
                                font.weight: Font.Bold
                            }

                            TapHandler {
                                onTapped: StateBridge.quickSettingsOpen = false
                            }
                        }
                    }

                    // 2x4 Touch Tiles
                    Grid {
                        width: parent.width
                        columns: 2
                        spacing: 8

                        readonly property int tileW: Math.floor((width - 8) / 2)

                        // 1. Mode
                        Rectangle {
                            width: parent.tileW
                            height: 62
                            radius: 12
                            color: StateBridge.isTabletMode ? Theme.accent : Theme.bgTile
                            border.width: 1
                            border.color: StateBridge.isTabletMode ? Theme.accentBright : Theme.borderSubtle

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                spacing: 2
                                Text {
                                    text: StateBridge.isTabletMode ? "Tablet Mode" : "Laptop Mode"
                                    color: Theme.textPrimary
                                    font.family: Theme.fontSans
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: "Dock: " + (StateBridge.dockAttached ? "Connected" : "Detached") + " (" + StateBridge.modeOverride + ")"
                                    color: StateBridge.isTabletMode ? "#ebf8ff" : Theme.textSecondary
                                    font.family: Theme.fontSans
                                    font.pixelSize: 11
                                }
                            }

                            TapHandler {
                                onTapped: StateBridge.runDaemonCmd(["mode", "toggle"])
                            }
                        }

                        // 2. Rotation
                        Rectangle {
                            width: parent.tileW
                            height: 62
                            radius: 12
                            color: !StateBridge.rotationLocked ? Theme.accent : Theme.bgTile
                            border.width: 1
                            border.color: !StateBridge.rotationLocked ? Theme.accentBright : Theme.borderSubtle

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                spacing: 2
                                Text {
                                    text: StateBridge.rotationLocked ? "Rotation Locked" : "Auto-Rotate ON"
                                    color: Theme.textPrimary
                                    font.family: Theme.fontSans
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: "Orientation: " + StateBridge.orientation
                                    color: !StateBridge.rotationLocked ? "#ebf8ff" : Theme.textSecondary
                                    font.family: Theme.fontSans
                                    font.pixelSize: 11
                                }
                            }

                            TapHandler {
                                onTapped: StateBridge.runDaemonCmd(["rotate", "toggle"])
                            }
                        }

                        // 3. Auto-Brightness
                        Rectangle {
                            width: parent.tileW
                            height: 62
                            radius: 12
                            color: StateBridge.autoBrightness ? Theme.accent : Theme.bgTile
                            border.width: 1
                            border.color: StateBridge.autoBrightness ? Theme.accentBright : Theme.borderSubtle

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                spacing: 2
                                Text {
                                    text: "Auto-Brightness"
                                    color: Theme.textPrimary
                                    font.family: Theme.fontSans
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: StateBridge.autoBrightness ? ("Sensor ON (" + Math.round(StateBridge.ambientLux) + " lux)") : "Manual"
                                    color: StateBridge.autoBrightness ? "#ebf8ff" : Theme.textSecondary
                                    font.family: Theme.fontSans
                                    font.pixelSize: 11
                                }
                            }

                            TapHandler {
                                onTapped: StateBridge.runDaemonCmd(["autobrightness", "toggle"])
                            }
                        }

                        // 4. Game Mode
                        Rectangle {
                            width: parent.tileW
                            height: 62
                            radius: 12
                            color: StateBridge.gameMode ? Theme.danger : Theme.bgTile
                            border.width: 1
                            border.color: StateBridge.gameMode ? "#fc8181" : Theme.borderSubtle

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                spacing: 2
                                Text {
                                    text: "Game Mode"
                                    color: Theme.textPrimary
                                    font.family: Theme.fontSans
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: StateBridge.gameMode ? "Boost Active (Updates Paused)" : "Off"
                                    color: StateBridge.gameMode ? "#fff5f5" : Theme.textSecondary
                                    font.family: Theme.fontSans
                                    font.pixelSize: 11
                                }
                            }

                            TapHandler {
                                onTapped: StateBridge.runDaemonCmd(["gamemode", "toggle"])
                            }
                        }

                        // 5. Power Profile
                        Rectangle {
                            width: parent.tileW
                            height: 62
                            radius: 12
                            color: StateBridge.powerProfile === "performance" ? Theme.accent : Theme.bgTile
                            border.width: 1
                            border.color: Theme.borderSubtle

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                spacing: 2
                                Text {
                                    text: "Power Profile"
                                    color: Theme.textPrimary
                                    font.family: Theme.fontSans
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: StateBridge.powerProfile
                                    color: Theme.textSecondary
                                    font.family: Theme.fontSans
                                    font.pixelSize: 11
                                }
                            }

                            TapHandler {
                                onTapped: qsWin.cyclePower()
                            }
                        }

                        // 6. On-Screen Keyboard
                        Rectangle {
                            width: parent.tileW
                            height: 62
                            radius: 12
                            color: Theme.bgTile
                            border.width: 1
                            border.color: Theme.borderSubtle

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                spacing: 2
                                Text {
                                    text: "⌨ Touch Keyboard"
                                    color: Theme.textPrimary
                                    font.family: Theme.fontSans
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: "Show / Hide"
                                    color: Theme.textSecondary
                                    font.family: Theme.fontSans
                                    font.pixelSize: 11
                                }
                            }

                            TapHandler {
                                onTapped: {
                                    StateBridge.runDaemonCmd(["osk", "toggle"]);
                                    StateBridge.quickSettingsOpen = false;
                                }
                            }
                        }

                        // 7. Wi-Fi Settings
                        Rectangle {
                            width: parent.tileW
                            height: 62
                            radius: 12
                            color: Networking.wifiEnabled ? "#1c3c5e" : Theme.bgTile
                            border.width: 1
                            border.color: Networking.wifiEnabled ? Theme.accent : Theme.borderSubtle

                            Row {
                                anchors.fill: parent
                                anchors.margins: 10
                                Column {
                                    width: parent.width - 36
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    Text {
                                        text: Networking.wifiEnabled ? "Wi-Fi ON" : "Wi-Fi OFF"
                                        color: Theme.textPrimary
                                        font.family: Theme.fontSans
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        text: "Tap: Toggle • ⚙: Edit"
                                        color: Theme.textSecondary
                                        font.family: Theme.fontSans
                                        font.pixelSize: 11
                                    }
                                }

                                Rectangle {
                                    width: 32
                                    height: 32
                                    radius: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: "#2c3d59"
                                    Text {
                                        anchors.centerIn: parent
                                        text: "⚙"
                                        color: Theme.textPrimary
                                        font.pixelSize: 14
                                    }
                                    TapHandler {
                                        onTapped: {
                                            Quickshell.execDetached(["nm-connection-editor"]);
                                            StateBridge.quickSettingsOpen = false;
                                        }
                                    }
                                }
                            }

                            TapHandler {
                                onTapped: {
                                    Quickshell.execDetached(["nmcli", "radio", "wifi", Networking.wifiEnabled ? "off" : "on"]);
                                }
                            }
                        }

                        // 8. Bluetooth Settings
                        Rectangle {
                            width: parent.tileW
                            height: 62
                            radius: 12
                            color: StateBridge.btPowered ? "#1c3c5e" : Theme.bgTile
                            border.width: 1
                            border.color: Theme.borderSubtle

                            Row {
                                anchors.fill: parent
                                anchors.margins: 10
                                Column {
                                    width: parent.width - 36
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    Text {
                                        text: StateBridge.btPowered ? "Bluetooth" : "BT Off"
                                        color: Theme.textPrimary
                                        font.family: Theme.fontSans
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        text: "Devices & Audio"
                                        color: Theme.textSecondary
                                        font.family: Theme.fontSans
                                        font.pixelSize: 11
                                    }
                                }

                                Rectangle {
                                    width: 32
                                    height: 32
                                    radius: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: "#2c3d59"
                                    Text {
                                        anchors.centerIn: parent
                                        text: "⚙"
                                        color: Theme.textPrimary
                                        font.pixelSize: 14
                                    }
                                    TapHandler {
                                        onTapped: {
                                            Quickshell.execDetached(["blueman-manager"]);
                                            StateBridge.quickSettingsOpen = false;
                                        }
                                    }
                                }
                            }

                            TapHandler {
                                onTapped: {
                                    const nxt = !StateBridge.btPowered;
                                    StateBridge.btPowered = nxt;
                                    Quickshell.execDetached(["bluetoothctl", "power", nxt ? "on" : "off"]);
                                }
                            }
                        }
                    }

                    // Brightness Touch Slider
                    Rectangle {
                        width: parent.width
                        height: 48
                        radius: 12
                        color: Theme.bgCard
                        border.width: 1
                        border.color: Theme.borderSubtle

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "☀"
                                color: Theme.warning
                                font.pixelSize: 17
                            }

                            Item {
                                id: bTrackWrap
                                width: parent.width - 78
                                height: parent.height

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    height: 12
                                    radius: 6
                                    color: Theme.bgTile

                                    Rectangle {
                                        width: Math.max(12, parent.width * Math.min(1.0, Math.max(0.05, StateBridge.brightnessPct / 100.0)))
                                        height: parent.height
                                        radius: 6
                                        color: Theme.accent
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    function applyX(mx) {
                                        const pct = Math.round(5 + 95 * Math.min(1, Math.max(0, mx / width)));
                                        StateBridge.brightnessPct = pct;
                                        StateBridge.runDaemonCmd(["brightness", String(pct)]);
                                    }
                                    onPressed: mouse => applyX(mouse.x)
                                    onPositionChanged: mouse => { if (pressed) applyX(mouse.x); }
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 42
                                horizontalAlignment: Text.AlignRight
                                text: StateBridge.brightnessPct + "%"
                                color: Theme.textSecondary
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                            }
                        }
                    }

                    // Volume Touch Slider
                    Rectangle {
                        width: parent.width
                        height: 48
                        radius: 12
                        color: Theme.bgCard
                        border.width: 1
                        border.color: Theme.borderSubtle

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsWin.curMuted ? "Muted" : "Vol"
                                color: qsWin.curMuted ? Theme.warning : Theme.accentBright
                                font.family: Theme.fontSans
                                font.pixelSize: 13
                                font.weight: Font.Bold

                                TapHandler {
                                    onTapped: {
                                        if (qsWin.sink && qsWin.sink.audio) {
                                            qsWin.sink.audio.muted = !qsWin.sink.audio.muted;
                                        } else {
                                            Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
                                        }
                                    }
                                }
                            }

                            Item {
                                width: parent.width - 96
                                height: parent.height

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    height: 12
                                    radius: 6
                                    color: Theme.bgTile

                                    Rectangle {
                                        width: Math.max(8, parent.width * Math.min(1.0, Math.max(0.0, qsWin.curVol / 100.0)))
                                        height: parent.height
                                        radius: 6
                                        color: qsWin.curMuted ? Theme.textMuted : "#38b2ac"
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    function applyVol(mx) {
                                        const pct = Math.round(100 * Math.min(1, Math.max(0, mx / width)));
                                        if (qsWin.sink && qsWin.sink.audio) {
                                            qsWin.sink.audio.volume = pct / 100.0;
                                        } else {
                                            Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", pct + "%"]);
                                        }
                                    }
                                    onPressed: mouse => applyVol(mouse.x)
                                    onPositionChanged: mouse => { if (pressed) applyVol(mouse.x); }
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 42
                                horizontalAlignment: Text.AlignRight
                                text: qsWin.curVol + "%"
                                color: Theme.textSecondary
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                            }
                        }
                    }

                    // Atomic Update & Rollback Card
                    Rectangle {
                        width: parent.width
                        height: updCol.implicitHeight + 20
                        radius: 12
                        color: "#16263d"
                        border.width: 1
                        border.color: "#2b4b75"

                        Column {
                            id: updCol
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            Row {
                                width: parent.width
                                Text {
                                    width: parent.width - 78
                                    text: "System Image (bootc): " + StateBridge.updateStatus
                                    color: Theme.textPrimary
                                    font.family: Theme.fontSans
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: "Check"
                                    color: Theme.accentBright
                                    font.family: Theme.fontSans
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    TapHandler {
                                        onTapped: StateBridge.runDaemonCmd(["update", "check"])
                                    }
                                }
                            }

                            Row {
                                width: parent.width
                                spacing: 8

                                Rectangle {
                                    width: (parent.width - 16) / 2
                                    height: 42
                                    radius: 10
                                    color: Theme.accent

                                    Text {
                                        anchors.centerIn: parent
                                        text: StateBridge.updateStatus === "ready-to-reboot" ? "↻ Reboot to Apply" : "↻ One-Tap Update"
                                        color: Theme.textPrimary
                                        font.family: Theme.fontSans
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                    }

                                    TapHandler {
                                        onTapped: {
                                            if (StateBridge.updateStatus === "ready-to-reboot") {
                                                Quickshell.execDetached(["systemctl", "reboot"]);
                                            } else {
                                                StateBridge.runDaemonCmd(["update", "apply"]);
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    width: (parent.width - 16) / 2
                                    height: 42
                                    radius: 10
                                    color: Theme.bgTile
                                    border.width: 1
                                    border.color: Theme.borderSubtle

                                    Text {
                                        anchors.centerIn: parent
                                        text: "⏪ Roll Back"
                                        color: Theme.textPrimary
                                        font.family: Theme.fontSans
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                    }

                                    TapHandler {
                                        onTapped: StateBridge.runDaemonCmd(["update", "rollback"])
                                    }
                                }
                            }
                        }
                    }

                    // Notifications History
                    Column {
                        visible: StateBridge.notificationHistory.length > 0
                        width: parent.width
                        spacing: 6

                        Row {
                            width: parent.width
                            Text {
                                width: parent.width - 60
                                text: "Notifications"
                                color: Theme.textSecondary
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                font.weight: Font.Bold
                            }
                            Text {
                                text: "Clear"
                                color: Theme.accentBright
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                TapHandler {
                                    onTapped: StateBridge.clearNotificationHistory()
                                }
                            }
                        }

                        Repeater {
                            model: StateBridge.notificationHistory
                            delegate: Rectangle {
                                required property var modelData
                                width: parent.width
                                height: nItemCol.implicitHeight + 14
                                radius: 10
                                color: Theme.bgCard
                                border.width: 1
                                border.color: Theme.borderSubtle

                                Column {
                                    id: nItemCol
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 2
                                    Text {
                                        width: parent.width
                                        text: modelData.summary + "  (" + modelData.timeStr + ")"
                                        color: Theme.textPrimary
                                        font.family: Theme.fontSans
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        visible: modelData.body.length > 0
                                        width: parent.width
                                        text: modelData.body
                                        color: Theme.textSecondary
                                        font.family: Theme.fontSans
                                        font.pixelSize: 11
                                        wrapMode: Text.Wrap
                                    }
                                }
                            }
                        }
                    }

                    // Bottom Power Row
                    Row {
                        width: parent.width
                        spacing: 8
                        readonly property int btnW: Math.floor((width - 24) / 4)

                        Repeater {
                            model: [
                                { label: "Lock", action: "lock" },
                                { label: "Sleep", cmd: ["systemctl", "suspend"] },
                                { label: "Reboot", cmd: ["systemctl", "reboot"] },
                                { label: "Off", cmd: ["systemctl", "poweroff"] }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                width: parent.btnW
                                height: 44
                                radius: 10
                                color: Theme.bgTile
                                border.width: 1
                                border.color: Theme.borderSubtle

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: Theme.textPrimary
                                    font.family: Theme.fontSans
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }

                                TapHandler {
                                    onTapped: {
                                        StateBridge.quickSettingsOpen = false;
                                        if (modelData.action === "lock") {
                                            StateBridge.lockRequested = true;
                                        } else {
                                            Quickshell.execDetached(modelData.cmd);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
        }
    }
}
