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
                property string categoryFilter: StateBridge.appGridCategory

                Connections {
                    target: StateBridge
                    function onAppGridCategoryChanged() {
                        gridWin.categoryFilter = StateBridge.appGridCategory;
                        appFlick.contentY = 0;
                    }
                }

                function selectCategory(cat) {
                    gridWin.categoryFilter = cat;
                    StateBridge.appGridCategory = cat;
                    appFlick.contentY = 0;
                }

                readonly property var filteredApps: {
                    const list = DesktopEntries.applications ? DesktopEntries.applications.values : [];
                    const q = searchText.trim().toLowerCase();
                    const cat = categoryFilter;
                    const out = [];
                    for (let i = 0; i < list.length; i++) {
                        const e = list[i];
                        if (!e || e.noDisplay) continue;

                        const entryId = String(e.id || "").toLowerCase();
                        const entryName = String(e.name || "").toLowerCase();
                        if (entryId.includes("blueman-adapters") ||
                            entryId.includes("pcmanfm-desktop-pref") ||
                            entryId.includes("foot-server") ||
                            entryId.includes("footclient") ||
                            entryName === "bluetooth adapters" ||
                            entryName === "desktop preferences" ||
                            entryName === "foot server" ||
                            entryName === "foot client") {
                            continue;
                        }

                        if (cat !== "All") {
                            const catParts = [];
                            if (e.categories) {
                                if (typeof e.categories === "string") {
                                    catParts.push(e.categories);
                                } else if (e.categories.length !== undefined) {
                                    for (let c = 0; c < e.categories.length; c++) {
                                        catParts.push(String(e.categories[c]));
                                    }
                                }
                            }
                            const cats = (catParts.join(" ") + " " + entryId + " " + String(e.genericName || "")).toLowerCase();
                            if (cat === "Internet" &&
                                !cats.includes("network") &&
                                !cats.includes("web") &&
                                !cats.includes("browser") &&
                                !cats.includes("email") &&
                                !cats.includes("instantmessaging") &&
                                !cats.includes("chat") &&
                                !cats.includes("filetransfer") &&
                                !cats.includes("remoteaccess") &&
                                !cats.includes("p2p")) {
                                continue;
                            }
                            if (cat === "Media" &&
                                !cats.includes("audiovideo") &&
                                !cats.includes("audio") &&
                                !cats.includes("video") &&
                                !cats.includes("player") &&
                                !cats.includes("recorder") &&
                                !cats.includes("music")) {
                                continue;
                            }
                            if (cat === "Games" &&
                                !cats.includes("game") &&
                                !cats.includes("emulator") &&
                                !cats.includes("arcade")) {
                                continue;
                            }
                            if (cat === "Utilities" &&
                                !cats.includes("utility") &&
                                !cats.includes("accessories") &&
                                !cats.includes("filemanager") &&
                                !cats.includes("filesystem") &&
                                !cats.includes("filetools") &&
                                !cats.includes("texteditor") &&
                                !cats.includes("archiving") &&
                                !cats.includes("calculator") &&
                                !cats.includes("viewer") &&
                                !cats.includes("graphics") &&
                                !cats.includes("office") &&
                                !cats.includes("development")) {
                                continue;
                            }
                            if (cat === "System" &&
                                !cats.includes("system") &&
                                !cats.includes("settings") &&
                                !cats.includes("terminal") &&
                                !cats.includes("packagemanager") &&
                                !cats.includes("monitor") &&
                                !cats.includes("security") &&
                                !cats.includes("hardwaresettings") &&
                                !cats.includes("bluetooth") &&
                                !cats.includes("transformer-store")) {
                                continue;
                            }
                        }
                        if (q.length > 0) {
                            const hay = (entryName + " " + String(e.genericName || "") + " " + String(e.comment || "") + " " + entryId).toLowerCase();
                            if (!hay.includes(q)) continue;
                        }
                        out.push(e);
                    }
                    out.sort((a, b) => String(a.name || "").localeCompare(String(b.name || "")));
                    return out;
                }

                Rectangle {
                    anchors.fill: parent
                    color: "#c8090e1a"
                    focus: true

                    Keys.onEscapePressed: StateBridge.appGridOpen = false

                    // Backdrop click catcher placed as a sibling behind the card
                    MouseArea {
                        anchors.fill: parent
                        onClicked: StateBridge.appGridOpen = false
                    }

                    Rectangle {
                        id: gridCard
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 36, 980)
                        height: Math.min(parent.height - 76, 650)
                        radius: 20
                        color: "#f2121928"
                        border.width: 1
                        border.color: Theme.borderSubtle

                        // Swallow all mouse/touch events inside the card so they never hit the backdrop
                        MouseArea {
                            anchors.fill: parent
                            onPressed: mouse => { mouse.accepted = true; }
                        }

                        Column {
                            anchors.fill: parent
                            anchors.margins: 18
                            spacing: 12

                            Row {
                                width: parent.width
                                spacing: 10

                                Rectangle {
                                    width: parent.width - storeBtn.width - oskBtn.width - closeBtn.width - 30
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
                                        onTextChanged: {
                                            gridWin.searchText = text;
                                            appFlick.contentY = 0;
                                        }
                                        Keys.onEscapePressed: StateBridge.appGridOpen = false

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

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            searchInput.forceActiveFocus();
                                            if (StateBridge.isTabletMode) {
                                                StateBridge.runDaemonCmd(["osk", "show"]);
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    id: storeBtn
                                    width: storeBtnTxt.implicitWidth + 24
                                    height: 44
                                    radius: 12
                                    color: storeBtnArea.pressed ? Theme.accent : "#1f3a5f"
                                    border.width: 1
                                    border.color: "#355a8a"
                                    Text {
                                        id: storeBtnTxt
                                        anchors.centerIn: parent
                                        text: "📦 Store"
                                        color: Theme.textPrimary
                                        font.family: Theme.fontSans
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                    }
                                    MouseArea {
                                        id: storeBtnArea
                                        anchors.fill: parent
                                        onClicked: {
                                            Quickshell.execDetached([
                                                "/bin/sh",
                                                "-c",
                                                "if [ -x /usr/bin/transformer-store ]; then exec /usr/bin/transformer-store; elif [ -x /var/lib/transformeros/bin/transformer-store ]; then exec /var/lib/transformeros/bin/transformer-store; fi"
                                            ]);
                                            StateBridge.appGridOpen = false;
                                        }
                                    }
                                }

                                Rectangle {
                                    id: oskBtn
                                    width: 44
                                    height: 44
                                    radius: 12
                                    color: oskBtnArea.pressed ? Theme.accent : Theme.bgTile
                                    border.width: 1
                                    border.color: Theme.borderSubtle
                                    Text {
                                        anchors.centerIn: parent
                                        text: "⌨"
                                        color: Theme.textPrimary
                                        font.pixelSize: 18
                                    }
                                    MouseArea {
                                        id: oskBtnArea
                                        anchors.fill: parent
                                        onClicked: StateBridge.runDaemonCmd(["osk", "toggle"])
                                    }
                                }

                                Rectangle {
                                    id: closeBtn
                                    width: 44
                                    height: 44
                                    radius: 12
                                    color: closeBtnArea.pressed ? Theme.danger : Theme.bgTile
                                    border.width: 1
                                    border.color: Theme.borderSubtle
                                    Text {
                                        anchors.centerIn: parent
                                        text: "✕"
                                        color: Theme.textPrimary
                                        font.pixelSize: 16
                                        font.weight: Font.Bold
                                    }
                                    MouseArea {
                                        id: closeBtnArea
                                        anchors.fill: parent
                                        onClicked: StateBridge.appGridOpen = false
                                    }
                                }
                            }

                            Row {
                                width: parent.width
                                spacing: 8

                                Repeater {
                                    model: ["All", "Internet", "Media", "Games", "Utilities", "System"]
                                    delegate: Rectangle {
                                        required property string modelData
                                        height: 36
                                        width: catTxt.implicitWidth + 24
                                        radius: 18
                                        color: gridWin.categoryFilter === modelData ? Theme.accent : (catArea.pressed ? Theme.bgTileHover : Theme.bgTile)
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

                                        MouseArea {
                                            id: catArea
                                            anchors.fill: parent
                                            onClicked: gridWin.selectCategory(modelData)
                                        }
                                    }
                                }
                            }

                            Flickable {
                                id: appFlick
                                width: parent.width
                                height: parent.height - 106
                                contentHeight: Math.max(height, appFlow.implicitHeight)
                                clip: true

                                Text {
                                    anchors.centerIn: parent
                                    visible: gridWin.filteredApps.length === 0
                                    text: "No applications found in \"" + gridWin.categoryFilter + "\""
                                    color: Theme.textSecondary
                                    font.family: Theme.fontSans
                                    font.pixelSize: 15
                                }

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
                                            color: appArea.pressed ? Theme.accent : Theme.bgCard
                                            border.width: 1
                                            border.color: appArea.pressed ? Theme.accentBright : Theme.borderSubtle

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

                                            MouseArea {
                                                id: appArea
                                                anchors.fill: parent
                                                onClicked: {
                                                    const entry = appCard.modelData;
                                                    if (entry) entry.execute();
                                                    StateBridge.appGridOpen = false;
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
