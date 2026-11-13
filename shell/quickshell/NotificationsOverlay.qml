import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications

Scope {
    id: notifScope

    ListModel {
        id: toastModel
    }

    NotificationServer {
        id: server
        bodySupported: true
        actionsSupported: false
        keepOnReload: true
        onNotification: n => {
            const sum = n.summary || "Notification";
            const bod = n.body || "";
            const app = n.appName || "System";
            StateBridge.addNotificationRecord(sum, bod, app);

            toastModel.insert(0, {
                nid: String(n.id),
                summary: sum,
                body: bod,
                appName: app,
                expiresAt: Date.now() + 5000
            });
            while (toastModel.count > 4) {
                toastModel.remove(toastModel.count - 1);
            }
        }
    }

    Timer {
        interval: 500
        running: toastModel.count > 0
        repeat: true
        onTriggered: {
            const now = Date.now();
            for (let i = toastModel.count - 1; i >= 0; i--) {
                if (toastModel.get(i).expiresAt <= now) {
                    toastModel.remove(i);
                }
            }
        }
    }

    PanelWindow {
        visible: toastModel.count > 0
        anchors {
            top: true
            right: true
        }
        margins {
            top: StateBridge.isTabletMode ? 50 : 42
            right: 12
        }
        implicitWidth: 360
        implicitHeight: toastCol.implicitHeight + 8
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Column {
            id: toastCol
            width: parent.width
            spacing: 8

            Repeater {
                model: toastModel
                delegate: Rectangle {
                    required property int index
                    required property string summary
                    required property string body
                    required property string appName

                    width: parent.width
                    height: tTextCol.implicitHeight + 22
                    radius: 14
                    color: "#f2162033"
                    border.width: 1
                    border.color: Theme.accent

                    Column {
                        id: tTextCol
                        anchors.fill: parent
                        anchors.margins: 11
                        spacing: 3

                        Text {
                            width: parent.width
                            text: appName + "  •  " + summary
                            color: Theme.textPrimary
                            font.family: Theme.fontSans
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                        }

                        Text {
                            visible: body.length > 0
                            width: parent.width
                            text: body
                            color: Theme.textSecondary
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                    }

                    TapHandler {
                        onTapped: {
                            if (index >= 0 && index < toastModel.count) {
                                toastModel.remove(index);
                            }
                        }
                    }
                }
            }
        }
    }
}
