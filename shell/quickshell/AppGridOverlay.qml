import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    LazyLoader {
        active: StateBridge.appGridOpen
        component: Component {
            PanelWindow {
                id: gridWin
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

                property string searchText: ""
                property string categoryFilter: "All"

                readonly property var filteredApps: {
                    const list = DesktopEntries.applications ? DesktopEntries.applications.values : [];
                    const q = searchText.trim().toLowerCase();
                    const cat = categoryFilter;
                    const out = [];
                    for (let i = 0; i < list.length; i++) {
                        const e = list[i];
                        if (!e || e.noDisplay) continue;
                        if (cat !== "All") {
                            const cats = (e.categories || []).join(" ").toLowerCase();
                            if (cat === "Internet" && !cats.includes("network") && !cats.includes("web")) continue;
                            if (cat === "Games" && !cats.includes("game")) continue;
                            if (cat === "System" && !cats.includes("system") && !cats.includes("settings") && !cats.includes("terminal")) continue;
                        }
                        if (q.length > 0) {
                            const hay = ((e.name || "") + " " + (e.genericName || "") + " " + (e.comment || "") + " " + (e.id || "")).toLowerCase();
                            if (!hay.includes(q)) continue;
                        }
                        out.push(e);
                    }
                    out.sort((a, b) => (a.name || "").localeCompare(b.name || ""));
                    return out;
                }

                Rectangle {
                    anchors.fill: parent
                    color: "#c8090e1a"

                    Keys.onEscapePressed: StateBridge.appGridOpen = false

                    TapHandler {
                        onTapped: StateBridge.appGridOpen = false
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 36, 980)
                        height: Math.min(parent.height - 76, 650)
                        radius: 20
                        color: "#f2121928"
                        border.width: 1
                        border.color: Theme.borderSubtle

                        TapHandler {}

                        Column {
                            anchors.fill: parent
                            anchors.margins: 18
                            spacing: 12

                            Row {
                                width: parent.width
                                spacing: 10

                                Rectangle {
                                    width: parent.width - closeBtn.width - 58
                                    height: 44
                                    radius: 12
                                    color: Theme.bgCard
                                    border.width: 1
                                    border.color: searchInput.activeFocus ? Theme.accentBright : Theme.borderSubtle

                                    TextInput {
                                        id: searchInput
                                        anchors.fill: parent
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 14
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: Theme.textPrimary
                                        font.family: Theme.fontSans
                                        font.pixelSize: 15
                                        text: gridWin.searchText
                                        onTextChanged: gridWin.searchText = text

                                        Component.onCompleted: {
                                            if (!StateBridge.isTabletMode) forceActiveFocus();
                                        }

                                        Text {
                                            anchors.fill: parent
                                            verticalAlignment: Text.AlignVCenter
                                            text: "Search applications..."
                                            color: Theme.textMuted
                                            font.family: Theme.fontSans
                                            font.pixelSize: 15
                                            visible: searchInput.text.length === 0
                                        }
                                    }

                                    TapHandler {
                                        onTapped: {
                                            searchInput.forceActiveFocus();
                                            if (StateBridge.isTabletMode) {
                                                StateBridge.runDaemonCmd(["osk", "show"]);
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    width: 44
                                    height: 44
                                    radius: 12
                                    color: Theme.bgTile
                                    border.width: 1
                                    border.color: Theme.borderSubtle
                                    Text {
                                        anchors.centerIn: parent
                                        text: "⌨"
                                        color: Theme.textPrimary
                                        font.pixelSize: 18
                                    }
                                    TapHandler {
                                        onTapped: StateBridge.runDaemonCmd(["osk", "toggle"])
                                    }
                                }

                                Rectangle {
                                    id: closeBtn
                                    width: 44
                                    height: 44
                                    radius: 12
                                    color: Theme.bgTile
                                    border.width: 1
                                    border.color: Theme.borderSubtle
                                    Text {
                                        anchors.centerIn: parent
                                        text: "✕"
                                        color: Theme.textPrimary
                                        font.pixelSize: 16
                                        font.weight: Font.Bold
                                    }
                                    TapHandler {
                                        onTapped: StateBridge.appGridOpen = false
                                    }
                                }
                            }

                            Row {
                                width: parent.width
                                spacing: 8

                                Repeater {
                                    model: ["All", "Internet", "Games", "System"]
                                    delegate: Rectangle {
                                        required property string modelData
                                        height: 36
                                        width: catTxt.implicitWidth + 24
                                        radius: 18
                                        color: gridWin.categoryFilter === modelData ? Theme.accent : Theme.bgTile
                                        border.width: 1
                                        border.color: gridWin.categoryFilter === modelData ? Theme.accentBright : Theme.borderSubtle

                                        Text {
                                            id: catTxt
                                            anchors.centerIn: parent
                                            text: modelData
                                            color: Theme.textPrimary
                                            font.family: Theme.fontSans
                                            font.pixelSize: 13
                                            font.weight: Font.DemiBold
                                        }

                                        TapHandler {
                                            onTapped: gridWin.categoryFilter = modelData
                                        }
                                    }
                                }
                            }

                            Flickable {
                                width: parent.width
                                height: parent.height - 106
                                contentHeight: appFlow.implicitHeight
                                clip: true

                                Flow {
                                    id: appFlow
                                    width: parent.width
                                    spacing: 12

                                    Repeater {
                                        model: gridWin.filteredApps
                                        delegate: Rectangle {
                                            id: appCard
                                            required property var modelData
                                            width: 124
                                            height: 112
                                            radius: 16
                                            color: appTap.pressed ? Theme.accent : Theme.bgCard
                                            border.width: 1
                                            border.color: appTap.pressed ? Theme.accentBright : Theme.borderSubtle

                                            Column {
                                                anchors.centerIn: parent
                                                width: parent.width - 14
                                                spacing: 8

                                                Image {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    width: 44
                                                    height: 44
                                                    sourceSize: Qt.size(44, 44)
                                                    asynchronous: true
                                                    source: (appCard.modelData.icon && Quickshell.hasThemeIcon(appCard.modelData.icon))
                                                          ? Quickshell.iconPath(appCard.modelData.icon)
                                                          : Qt.resolvedUrl("default-app.svg")
                                                    fillMode: Image.PreserveAspectFit
                                                    onStatusChanged: {
                                                        if (status === Image.Error) {
                                                            source = Qt.resolvedUrl("default-app.svg");
                                                        }
                                                    }
                                                }

                                                Text {
                                                    width: parent.width
                                                    horizontalAlignment: Text.AlignHCenter
                                                    maximumLineCount: 2
                                                    wrapMode: Text.Wrap
                                                    elide: Text.ElideRight
                                                    text: appCard.modelData.name || appCard.modelData.id
                                                    color: Theme.textPrimary
                                                    font.family: Theme.fontSans
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                }
                                            }

                                            TapHandler {
                                                id: appTap
                                                onTapped: {
                                                    StateBridge.appGridOpen = false;
                                                    appCard.modelData.execute();
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
