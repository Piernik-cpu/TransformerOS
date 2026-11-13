import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Networking

PanelWindow {
    id: bar
    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: StateBridge.isTabletMode ? 42 : 34
    exclusionMode: ExclusionMode.Auto
    color: "transparent"

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property int volPct: sink && sink.audio ? Math.round((sink.audio.volume || 0) * 100) : 0
    readonly property bool volMuted: sink && sink.audio ? !!sink.audio.muted : false

    PwObjectTracker {
        objects: bar.sink ? [bar.sink] : []
    }

    SystemClock {
        id: sysClock
        precision: SystemClock.Minutes
    }

    Rectangle {
        anchors.fill: parent
        color: "#ea0f1626"
        border.width: 0

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Theme.borderSubtle
        }

        // Left: Apps + Mode + Running Toplevels
        Row {
            id: leftRow
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Rectangle {
                height: StateBridge.isTabletMode ? 32 : 26
                width: appsLbl.implicitWidth + 20
                radius: 8
                color: StateBridge.appGridOpen ? Theme.accent : (appsTap.pressed ? Theme.bgTileHover : Theme.bgTile)
                border.width: 1
                border.color: StateBridge.appGridOpen ? Theme.accentBright : Theme.borderSubtle

                Text {
                    id: appsLbl
                    anchors.centerIn: parent
                    text: "Apps"
                    color: Theme.textPrimary
                    font.family: Theme.fontSans
                    font.pixelSize: StateBridge.isTabletMode ? 14 : 13
                    font.weight: Font.DemiBold
                }

                TapHandler {
                    id: appsTap
                    onTapped: StateBridge.toggleAppGrid()
                }
            }

            Rectangle {
                height: StateBridge.isTabletMode ? 32 : 26
                width: modeLbl.implicitWidth + 18
                radius: 8
                color: StateBridge.isTabletMode ? Theme.accent : Theme.bgTile
                border.width: 1
                border.color: StateBridge.isTabletMode ? Theme.accentBright : Theme.borderSubtle

                Text {
                    id: modeLbl
                    anchors.centerIn: parent
                    text: StateBridge.isTabletMode ? "Tablet" : "Laptop"
                    color: Theme.textPrimary
                    font.family: Theme.fontSans
                    font.pixelSize: StateBridge.isTabletMode ? 14 : 12
                    font.weight: Font.DemiBold
                }

                TapHandler {
                    onTapped: StateBridge.runDaemonCmd(["mode", "toggle"])
                }
            }

            // Running windows strip
            Row {
                spacing: 4
                Repeater {
                    model: ToplevelManager.toplevels
                    delegate: Rectangle {
                        id: taskChip
                        required property var modelData
                        readonly property string cleanTitle: {
                            const t = (modelData.title || modelData.appId || "App").trim();
                            return t.length > 16 ? t.slice(0, 15) + "…" : t;
                        }
                        visible: !StateBridge.isTabletMode || index < 3
                        height: StateBridge.isTabletMode ? 32 : 26
                        width: Math.min(155, taskTxt.implicitWidth + 18)
                        radius: 7
                        color: modelData.activated ? "#284166" : Theme.bgCard
                        border.width: 1
                        border.color: modelData.activated ? Theme.accentBright : Theme.borderSubtle

                        Text {
                            id: taskTxt
                            anchors.centerIn: parent
                            width: parent.width - 14
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: taskChip.cleanTitle
                            color: modelData.activated ? Theme.textPrimary : Theme.textSecondary
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: modelData.activated ? Font.DemiBold : Font.Normal
                        }

                        TapHandler {
                            onTapped: {
                                if (taskChip.modelData) taskChip.modelData.activate();
                            }
                        }
                    }
                }
            }
        }

        // Center: Clock & Date (tap opens Quick Settings)
        Rectangle {
            anchors.centerIn: parent
            height: StateBridge.isTabletMode ? 32 : 26
            width: clockText.implicitWidth + 20
            radius: 8
            color: clockTap.pressed ? Theme.bgTileHover : "transparent"

            Text {
                id: clockText
                anchors.centerIn: parent
                text: Qt.formatDateTime(sysClock.date, "HH:mm  •  ddd dd MMM")
                color: Theme.textPrimary
                font.family: Theme.fontSans
                font.pixelSize: StateBridge.isTabletMode ? 14 : 13
                font.weight: Font.DemiBold
            }

            TapHandler {
                id: clockTap
                onTapped: StateBridge.toggleQuickSettings()
            }
        }

        // Right: Game badge + OSK + Audio + Wi-Fi + Battery + Quick Settings
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Rectangle {
                visible: StateBridge.gameMode
                height: StateBridge.isTabletMode ? 32 : 26
                width: gmTxt.implicitWidth + 16
                radius: 8
                color: Theme.danger

                Text {
                    id: gmTxt
                    anchors.centerIn: parent
                    text: "GAME"
                    color: Theme.textPrimary
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }

                TapHandler {
                    onTapped: StateBridge.runDaemonCmd(["gamemode", "toggle"])
                }
            }

            Rectangle {
                height: StateBridge.isTabletMode ? 32 : 26
                width: StateBridge.isTabletMode ? 40 : 34
                radius: 8
                color: oskTap.pressed ? Theme.accent : Theme.bgTile
                border.width: 1
                border.color: Theme.borderSubtle

                Text {
                    anchors.centerIn: parent
                    text: "⌨"
                    color: Theme.textPrimary
                    font.pixelSize: 15
                }

                TapHandler {
                    id: oskTap
                    onTapped: StateBridge.runDaemonCmd(["osk", "toggle"])
                }
            }

            Rectangle {
                height: StateBridge.isTabletMode ? 32 : 26
                width: volTxt.implicitWidth + 16
                radius: 8
                color: volTap.pressed ? Theme.bgTileHover : Theme.bgTile
                border.width: 1
                border.color: Theme.borderSubtle

                Text {
                    id: volTxt
                    anchors.centerIn: parent
                    text: bar.volMuted ? "Mute" : ("Vol " + bar.volPct + "%")
                    color: bar.volMuted ? Theme.warning : Theme.textPrimary
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                }

                TapHandler {
                    id: volTap
                    onTapped: {
                        if (bar.sink && bar.sink.audio) {
                            bar.sink.audio.muted = !bar.sink.audio.muted;
                        } else {
                            Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
                        }
                    }
                }
            }

            Rectangle {
                height: StateBridge.isTabletMode ? 32 : 26
                width: wifiTxt.implicitWidth + 16
                radius: 8
                color: Theme.bgTile
                border.width: 1
                border.color: Theme.borderSubtle

                Text {
                    id: wifiTxt
                    anchors.centerIn: parent
                    text: Networking.wifiEnabled ? "Wi-Fi" : "Wi-Fi Off"
                    color: Networking.wifiEnabled ? Theme.accentBright : Theme.textMuted
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                }

                TapHandler {
                    onTapped: StateBridge.toggleQuickSettings()
                }
            }

            Rectangle {
                height: StateBridge.isTabletMode ? 32 : 26
                width: batTxt.implicitWidth + 16
                radius: 8
                color: (StateBridge.batteryPct <= 20 && !StateBridge.acOnline) ? "#742a2a" : Theme.bgTile
                border.width: 1
                border.color: Theme.borderSubtle

                Text {
                    id: batTxt
                    anchors.centerIn: parent
                    text: (StateBridge.acOnline || StateBridge.batteryStatus === "Charging" ? "⚡ " : "") + StateBridge.batteryPct + "%"
                    color: (StateBridge.acOnline || StateBridge.batteryStatus === "Charging") ? "#68d391"
                         : (StateBridge.batteryPct <= 20 ? "#feb2b2" : Theme.textPrimary)
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                TapHandler {
                    onTapped: StateBridge.toggleQuickSettings()
                }
            }

            Rectangle {
                height: StateBridge.isTabletMode ? 32 : 26
                width: qsBtnTxt.implicitWidth + 18
                radius: 8
                color: StateBridge.quickSettingsOpen ? Theme.accent : "#1f3a5f"
                border.width: 1
                border.color: StateBridge.quickSettingsOpen ? Theme.accentBright : "#355a8a"

                Text {
                    id: qsBtnTxt
                    anchors.centerIn: parent
                    text: StateBridge.updateStatus === "update-available" || StateBridge.updateStatus === "ready-to-reboot"
                          ? "⚙ Update" : "⚙ Quick"
                    color: Theme.textPrimary
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                TapHandler {
                    onTapped: StateBridge.toggleQuickSettings()
                }
            }
        }
    }
}
