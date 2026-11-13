import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: navBar
    anchors {
        bottom: true
        left: true
        right: true
    }
    implicitHeight: 54
    visible: StateBridge.isTabletMode
    exclusionMode: StateBridge.isTabletMode ? ExclusionMode.Auto : ExclusionMode.Ignore
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        color: "#f00d1320"

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: Theme.borderSubtle
        }

        Row {
            anchors.centerIn: parent
            spacing: 18

            // Back: closes shell overlay if open, else sends Alt+Left back shortcut
            Rectangle {
                width: 128
                height: 42
                radius: 21
                color: backTap.pressed ? Theme.accent : Theme.bgTile
                border.width: 1
                border.color: Theme.borderSubtle

                Text {
                    anchors.centerIn: parent
                    text: "◀  Back"
                    color: Theme.textPrimary
                    font.family: Theme.fontSans
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }

                TapHandler {
                    id: backTap
                    onTapped: {
                        if (StateBridge.quickSettingsOpen || StateBridge.appGridOpen || StateBridge.recentsOpen) {
                            StateBridge.closePopups();
                        } else {
                            Quickshell.execDetached(["wtype", "-M", "alt", "-k", "Left", "-m", "alt"]);
                        }
                    }
                }
            }

            // Home / App Launcher
            Rectangle {
                width: 128
                height: 42
                radius: 21
                color: StateBridge.appGridOpen ? Theme.accent : (homeTap.pressed ? Theme.accent : Theme.bgTile)
                border.width: 1
                border.color: StateBridge.appGridOpen ? Theme.accentBright : Theme.borderSubtle

                Text {
                    anchors.centerIn: parent
                    text: "●  Apps"
                    color: Theme.textPrimary
                    font.family: Theme.fontSans
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }

                TapHandler {
                    id: homeTap
                    onTapped: StateBridge.toggleAppGrid()
                }
            }

            // Recents / Task Cards
            Rectangle {
                width: 136
                height: 42
                radius: 21
                color: StateBridge.recentsOpen ? Theme.accent : (recTap.pressed ? Theme.accent : Theme.bgTile)
                border.width: 1
                border.color: StateBridge.recentsOpen ? Theme.accentBright : Theme.borderSubtle

                Text {
                    anchors.centerIn: parent
                    text: "■  Recents (" + (ToplevelManager.toplevels ? ToplevelManager.toplevels.values.length : 0) + ")"
                    color: Theme.textPrimary
                    font.family: Theme.fontSans
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }

                TapHandler {
                    id: recTap
                    onTapped: StateBridge.toggleRecents()
                }
            }

            // On-Screen Touch Keyboard
            Rectangle {
                width: 128
                height: 42
                radius: 21
                color: kbdTap.pressed ? Theme.accent : Theme.bgTile
                border.width: 1
                border.color: Theme.borderSubtle

                Text {
                    anchors.centerIn: parent
                    text: "⌨  Keys"
                    color: Theme.textPrimary
                    font.family: Theme.fontSans
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }

                TapHandler {
                    id: kbdTap
                    onTapped: StateBridge.runDaemonCmd(["osk", "toggle"])
                }
            }
        }
    }
}
