import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    LazyLoader {
        active: StateBridge.recentsOpen
        component: Component {
            PanelWindow {
                id: recentsWin
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

                Rectangle {
                    anchors.fill: parent
                    color: "#b8080c16"
                    focus: true

                    Keys.onEscapePressed: StateBridge.recentsOpen = false

                    TapHandler {
                        onTapped: StateBridge.recentsOpen = false
                    }

                    Column {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 48, 980)
                        spacing: 16

                        Row {
                            width: parent.width
                            spacing: 12

                            Text {
                                text: "Open Applications"
                                color: Theme.textPrimary
                                font.family: Theme.fontSans
                                font.pixelSize: 22
                                font.weight: Font.Bold
                                width: parent.width - closeRecBtn.width - 12
                            }

                            Rectangle {
                                id: closeRecBtn
                                width: 96
                                height: 38
                                radius: 10
                                color: Theme.bgTile
                                border.width: 1
                                border.color: Theme.borderSubtle

                                Text {
                                    anchors.centerIn: parent
                                    text: "✕ Close"
                                    color: Theme.textPrimary
                                    font.family: Theme.fontSans
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }

                                TapHandler {
                                    onTapped: StateBridge.recentsOpen = false
                                }
                            }
                        }

                        Rectangle {
                            visible: !ToplevelManager.toplevels || ToplevelManager.toplevels.values.length === 0
                            width: parent.width
                            height: 150
                            radius: 16
                            color: Theme.bgCard
                            border.width: 1
                            border.color: Theme.borderSubtle

                            Column {
                                anchors.centerIn: parent
                                spacing: 12

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "No open windows right now"
                                    color: Theme.textSecondary
                                    font.family: Theme.fontSans
                                    font.pixelSize: 16
                                }

                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 180
                                    height: 44
                                    radius: 12
                                    color: Theme.accent

                                    Text {
                                        anchors.centerIn: parent
                                        text: "Open App Launcher"
                                        color: Theme.textPrimary
                                        font.family: Theme.fontSans
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                    }

                                    TapHandler {
                                        onTapped: StateBridge.toggleAppGrid()
                                    }
                                }
                            }
                        }

                        Flickable {
                            visible: ToplevelManager.toplevels && ToplevelManager.toplevels.values.length > 0
                            width: parent.width
                            height: Math.min(440, Math.max(170, recGrid.implicitHeight))
                            contentHeight: recGrid.implicitHeight
                            clip: true

                            Flow {
                                id: recGrid
                                width: parent.width
                                spacing: 14

                                Repeater {
                                    model: ToplevelManager.toplevels
                                    delegate: Rectangle {
                                        id: winCard
                                        required property var modelData
                                        readonly property var dEntry: DesktopEntries.heuristicLookup(modelData.appId)
                                        readonly property string iconName: (dEntry && dEntry.icon) ? dEntry.icon : (modelData.appId || "")
                                        width: 280
                                        height: 132
                                        radius: 16
                                        color: modelData.activated ? "#1f3659" : Theme.bgCard
                                        border.width: modelData.activated ? 2 : 1
                                        border.color: modelData.activated ? Theme.accentBright : Theme.borderSubtle

                                        TapHandler {
                                            onTapped: {
                                                if (winCard.modelData) winCard.modelData.activate();
                                                StateBridge.recentsOpen = false;
                                            }
                                        }

                                        Column {
                                            anchors.fill: parent
                                            anchors.margins: 14
                                            spacing: 8

                                            Row {
                                                width: parent.width
                                                spacing: 10

                                                Rectangle {
                                                    width: 40
                                                    height: 40
                                                    radius: 10
                                                    color: Theme.bgTile

                                                    Image {
                                                        anchors.centerIn: parent
                                                        width: 28
                                                        height: 28
                                                        sourceSize: Qt.size(28, 28)
                                                        source: (winCard.iconName && Quickshell.hasThemeIcon(winCard.iconName))
                                                              ? Quickshell.iconPath(winCard.iconName)
                                                              : Qt.resolvedUrl("default-app.svg")
                                                        fillMode: Image.PreserveAspectFit
                                                    }
                                                }

                                                Column {
                                                    width: parent.width - 96
                                                    anchors.verticalCenter: parent.verticalCenter

                                                    Text {
                                                        width: parent.width
                                                        elide: Text.ElideRight
                                                        text: (winCard.dEntry && winCard.dEntry.name) ? winCard.dEntry.name : (winCard.modelData.appId || "Application")
                                                        color: Theme.textPrimary
                                                        font.family: Theme.fontSans
                                                        font.pixelSize: 15
                                                        font.weight: Font.Bold
                                                    }

                                                    Text {
                                                        width: parent.width
                                                        elide: Text.ElideRight
                                                        text: winCard.modelData.activated ? "Active Window" : "Tap to Switch"
                                                        color: winCard.modelData.activated ? Theme.accentBright : Theme.textSecondary
                                                        font.family: Theme.fontSans
                                                        font.pixelSize: 12
                                                    }
                                                }

                                                Rectangle {
                                                    width: 38
                                                    height: 38
                                                    radius: 10
                                                    color: closeCardTap.pressed ? Theme.danger : "#3a2330"

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "✕"
                                                        color: "#feb2b2"
                                                        font.pixelSize: 15
                                                        font.weight: Font.Bold
                                                    }

                                                    TapHandler {
                                                        id: closeCardTap
                                                        onTapped: {
                                                            if (winCard.modelData) winCard.modelData.close();
                                                        }
                                                    }
                                                }
                                            }

                                            Text {
                                                width: parent.width
                                                elide: Text.ElideRight
                                                text: winCard.modelData.title || ""
                                                color: Theme.textSecondary
                                                font.family: Theme.fontSans
                                                font.pixelSize: 13
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
