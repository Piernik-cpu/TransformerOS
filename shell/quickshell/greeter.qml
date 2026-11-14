import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: greeterRoot

    property string selectedUser: "piergi"
    property var usersList: ["piergi"]
    property string passwordText: ""
    property string statusMessage: ""
    property bool busy: false
    property bool docked: false
    property bool manualOsk: false
    property string batteryText: ""

    readonly property bool showTouchKeyboard: !docked || manualOsk

    SystemClock {
        id: gClock
        precision: SystemClock.Minutes
    }

    // Dynamic detection of regular UID>=1000 users from /etc/passwd
    Process {
        id: userProbe
        running: true
        command: ["awk", "-F:", "$3>=1000 && $3<60000 && $7!=\"/sbin/nologin\" && $7!=\"/bin/false\" {print $1}", "/etc/passwd"]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = text.split("\n").map(s => s.trim()).filter(s => s.length > 0);
                if (list.length > 0) {
                    greeterRoot.usersList = list;
                    greeterRoot.selectedUser = list[0];
                }
            }
        }
    }

    // Live sysfs probe for 0b05:17e0 dock / USB keyboard & BATC battery %
    Process {
        id: hwProbe
        running: true
        command: [
            "bash", "-c",
            "d=0; for p in /sys/bus/usb/devices/*; do [ -f \"$p/idVendor\" ] || continue; v=$(cat \"$p/idVendor\" 2>/dev/null); pr=$(cat \"$p/idProduct\" 2>/dev/null); if [ \"${v,,}\" = 0b05 ] && [ \"${pr,,}\" = 17e0 ]; then d=1; break; fi; done; if [ $d -eq 0 ] && compgen -G '/dev/input/by-id/*-event-kbd' >/dev/null; then d=1; fi; bat=''; if [ -f /sys/class/power_supply/BATC/capacity ]; then cap=$(cat /sys/class/power_supply/BATC/capacity 2>/dev/null); st=$(cat /sys/class/power_supply/BATC/status 2>/dev/null); bat=\"$cap% ($st)\"; fi; echo \"$d|$bat\""
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const line = text.trim();
                const parts = line.split("|");
                if (parts.length >= 1) {
                    const nextDocked = parts[0] === "1";
                    if (nextDocked !== greeterRoot.docked) {
                        greeterRoot.docked = nextDocked;
                        if (nextDocked) pwInput.forceActiveFocus();
                    }
                }
                if (parts.length >= 2) {
                    greeterRoot.batteryText = parts[1];
                }
            }
        }
    }

    Timer {
        interval: 800
        running: true
        repeat: true
        onTriggered: if (!hwProbe.running) hwProbe.running = true
    }

    function submitLogin() {
        if (busy) return;
        if (passwordText.length === 0) {
            statusMessage = "Please enter your password";
            return;
        }
        busy = true;
        statusMessage = "Signing in...";
        authProc.handledResult = false;
        authProc.pendingPayload = JSON.stringify({
            user: selectedUser,
            password: passwordText,
            cmd: ["/usr/bin/transformer-session"],
            env: [
                "XDG_SESSION_TYPE=wayland",
                "XDG_CURRENT_DESKTOP=labwc:wlroots",
                "MOZ_ENABLE_WAYLAND=1",
                "QT_QPA_PLATFORM=wayland",
                "LIBVA_DRIVER_NAME=i965",
                "XKB_DEFAULT_LAYOUT=it"
            ]
        }) + "\n";
        authProc.running = true;
    }

    Process {
        id: authProc
        property string pendingPayload: ""
        property bool handledResult: false

        command: ["/usr/bin/transformer-greeter", "--auth-stdio"]
        stdinEnabled: true

        onStarted: {
            if (pendingPayload.length > 0) {
                authProc.write(pendingPayload);
                pendingPayload = "";
            }
        }

        stdout: SplitParser {
            onRead: line => {
                const trimmed = line.trim();
                if (trimmed.length === 0) return;
                authProc.handledResult = true;
                try {
                    const res = JSON.parse(trimmed);
                    if (res.ok) {
                        greeterRoot.statusMessage = "";
                        Qt.quit();
                        return;
                    }
                    greeterRoot.busy = false;
                    greeterRoot.passwordText = "";
                    greeterRoot.statusMessage = res.message || "Incorrect password";
                } catch (e) {
                    greeterRoot.busy = false;
                    greeterRoot.passwordText = "";
                    greeterRoot.statusMessage = "Authentication response error";
                }
                if (greeterRoot.docked) pwInput.forceActiveFocus();
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (!authProc.handledResult) {
                greeterRoot.busy = false;
                greeterRoot.passwordText = "";
                greeterRoot.statusMessage = "Authentication failed (code " + exitCode + ")";
                if (greeterRoot.docked) pwInput.forceActiveFocus();
            }
        }
    }

    FloatingWindow {
        id: loginWin
        title: "TransformerOS Login"
        visible: true
        color: Theme.bgBase

        Rectangle {
            anchors.fill: parent
            color: Theme.bgBase

            Column {
                anchors.centerIn: parent
                width: Math.min(parent.width - 32, 780)
                spacing: 14

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatTime(gClock.date, "HH:mm")
                    color: Theme.textPrimary
                    font.family: Theme.fontSans
                    font.pixelSize: 54
                    font.weight: Font.Bold
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDate(gClock.date, "dddd, dd MMMM yyyy")
                        + (greeterRoot.batteryText.length > 0 ? ("   •   " + greeterRoot.batteryText) : "")
                    color: Theme.textSecondary
                    font.family: Theme.fontSans
                    font.pixelSize: 15
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width, 440)
                    height: cardCol.implicitHeight + 36
                    radius: 18
                    color: "#ee151e30"
                    border.width: 1
                    border.color: Theme.borderSubtle

                    Column {
                        id: cardCol
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 12

                        // Adaptive Dock Indicator
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: 30
                            width: dockBadgeTxt.implicitWidth + 24
                            radius: 15
                            color: greeterRoot.docked ? "#1f4e79" : "#276749"

                            Text {
                                id: dockBadgeTxt
                                anchors.centerIn: parent
                                text: greeterRoot.docked
                                    ? "Laptop Mode — Dock Connected"
                                    : "Tablet Mode — Dock Detached"
                                color: Theme.textPrimary
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                        }

                        // User Selector (cycles if multiple users exist)
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            height: 36
                            width: userTxt.implicitWidth + 28
                            radius: 10
                            color: Theme.bgTile

                            Text {
                                id: userTxt
                                anchors.centerIn: parent
                                text: greeterRoot.selectedUser
                                    + (greeterRoot.usersList.length > 1 ? "  ▾" : "")
                                color: Theme.textPrimary
                                font.family: Theme.fontSans
                                font.pixelSize: 20
                                font.weight: Font.Bold
                            }

                            TapHandler {
                                onTapped: {
                                    if (greeterRoot.usersList.length > 1) {
                                        const idx = greeterRoot.usersList.indexOf(greeterRoot.selectedUser);
                                        greeterRoot.selectedUser = greeterRoot.usersList[(idx + 1) % greeterRoot.usersList.length];
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: greeterRoot.docked
                                ? "Type your password and press Enter"
                                : "Tap password below using the touch keyboard"
                            color: Theme.textSecondary
                            font.family: Theme.fontSans
                            font.pixelSize: 13
                        }

                        Rectangle {
                            width: parent.width
                            height: greeterRoot.docked ? 46 : 54
                            radius: 12
                            color: Theme.bgCard
                            border.width: 1
                            border.color: pwInput.activeFocus ? Theme.accentBright : Theme.borderSubtle

                            TextInput {
                                id: pwInput
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.textPrimary
                                font.family: Theme.fontSans
                                font.pixelSize: greeterRoot.docked ? 16 : 20
                                echoMode: TextInput.Password
                                focus: true
                                text: greeterRoot.passwordText
                                onTextChanged: greeterRoot.passwordText = text
                                Keys.onReturnPressed: greeterRoot.submitLogin()
                                Keys.onEnterPressed: greeterRoot.submitLogin()

                                Component.onCompleted: forceActiveFocus()
                            }
                        }

                        Text {
                            visible: greeterRoot.statusMessage.length > 0
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: greeterRoot.statusMessage
                            color: "#fc8181"
                            font.family: Theme.fontSans
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }

                        Row {
                            width: parent.width
                            spacing: 10

                            Rectangle {
                                width: parent.width - (greeterRoot.docked ? 58 : 0)
                                height: greeterRoot.docked ? 46 : 54
                                radius: 12
                                color: greeterRoot.busy ? Theme.bgTile : Theme.accent

                                Text {
                                    anchors.centerIn: parent
                                    text: greeterRoot.busy ? "Signing in..." : "Sign In"
                                    color: Theme.textPrimary
                                    font.family: Theme.fontSans
                                    font.pixelSize: greeterRoot.docked ? 16 : 18
                                    font.weight: Font.Bold
                                }

                                TapHandler {
                                    onTapped: greeterRoot.submitLogin()
                                }
                            }

                            Rectangle {
                                visible: greeterRoot.docked
                                width: 48
                                height: 46
                                radius: 12
                                color: greeterRoot.manualOsk ? Theme.accent : Theme.bgTile
                                border.width: 1
                                border.color: Theme.borderSubtle

                                Text {
                                    anchors.centerIn: parent
                                    text: "⌨"
                                    color: Theme.textPrimary
                                    font.pixelSize: 18
                                }

                                TapHandler {
                                    onTapped: greeterRoot.manualOsk = !greeterRoot.manualOsk
                                }
                            }
                        }

                        // Power Controls
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 10

                            Repeater {
                                model: [
                                    { label: "Sleep", cmd: ["systemctl", "suspend"] },
                                    { label: "Reboot", cmd: ["systemctl", "reboot"] },
                                    { label: "Power Off", cmd: ["systemctl", "poweroff"] }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    height: 36
                                    width: pTxt.implicitWidth + 24
                                    radius: 10
                                    color: Theme.bgTile
                                    border.width: 1
                                    border.color: Theme.borderSubtle

                                    Text {
                                        id: pTxt
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: Theme.textSecondary
                                        font.family: Theme.fontSans
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }

                                    TapHandler {
                                        onTapped: Quickshell.execDetached(modelData.cmd)
                                    }
                                }
                            }
                        }
                    }
                }

                TouchKeyboard {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: greeterRoot.showTouchKeyboard
                    onKeyPressed: ch => { greeterRoot.passwordText += ch; }
                    onBackspacePressed: {
                        if (greeterRoot.passwordText.length > 0) {
                            greeterRoot.passwordText = greeterRoot.passwordText.slice(0, -1);
                        }
                    }
                    onEnterPressed: greeterRoot.submitLogin()
                }
            }
        }
    }
}
