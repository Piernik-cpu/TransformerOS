import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam

Scope {
    id: lockScope
    property string passwordText: ""
    property string errorText: ""
    property bool verifying: false
    property bool manualOsk: false
    readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME") || "piergi"
    readonly property bool isDocked: StateBridge.dockAttached || StateBridge.keyboardAttached
    readonly property bool showTouchKeyboard: !isDocked || manualOsk

    SystemClock {
        id: lockClock
        precision: SystemClock.Minutes
    }

    Timer {
        id: verifyTimeout
        interval: 8000
        repeat: false
        onTriggered: {
            if (lockScope.verifying) {
                if (pam.active) pam.abort();
                lockScope.verifying = false;
                lockScope.passwordText = "";
                lockScope.errorText = "Authentication timed out — try again";
            }
        }
    }

    Connections {
        target: StateBridge
        function onLockRequestedChanged() {
            verifyTimeout.stop();
            if (pam.active) {
                pam.abort();
            }
            lockScope.verifying = false;
            lockScope.passwordText = "";
            lockScope.errorText = "";
        }
    }

    function submitPassword() {
        if (verifying) return;
        if (passwordText.length === 0) {
            errorText = "Enter your password";
            return;
        }
        verifying = true;
        errorText = "Verifying...";
        verifyTimeout.restart();
        if (pam.active) {
            pam.abort();
        }
        if (!pam.start()) {
            verifyTimeout.stop();
            verifying = false;
            errorText = "Unable to start PAM authentication";
        }
    }

    PamContext {
        id: pam
        config: "system-auth"
        user: lockScope.userName

        onPamMessage: {
            if (pam.responseRequired) {
                pam.respond(lockScope.passwordText);
            } else if (pam.messageIsError && pam.message.length > 0) {
                lockScope.errorText = pam.message;
            }
        }

        onCompleted: result => {
            verifyTimeout.stop();
            lockScope.verifying = false;
            if (result === PamResult.Success) {
                lockScope.passwordText = "";
                lockScope.errorText = "";
                StateBridge.lockRequested = false;
            } else {
                lockScope.passwordText = "";
                lockScope.errorText = "Incorrect password";
            }
        }

        onError: err => {
            verifyTimeout.stop();
            lockScope.verifying = false;
            lockScope.passwordText = "";
            lockScope.errorText = "Authentication error (" + PamError.toString(err) + ")";
        }
    }

    WlSessionLock {
        id: sessionLock
        locked: StateBridge.lockRequested

        surface: WlSessionLockSurface {
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
                        text: Qt.formatTime(lockClock.date, "HH:mm")
                        color: Theme.textPrimary
                        font.family: Theme.fontSans
                        font.pixelSize: 52
                        font.weight: Font.Bold
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDate(lockClock.date, "dddd, dd MMMM yyyy")
                            + "   •   " + StateBridge.batteryPct + "%"
                        color: Theme.textSecondary
                        font.family: Theme.fontSans
                        font.pixelSize: 15
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(parent.width, 430)
                        height: lockCardCol.implicitHeight + 36
                        radius: 18
                        color: "#ee151e30"
                        border.width: 1
                        border.color: Theme.borderSubtle

                        Column {
                            id: lockCardCol
                            anchors.fill: parent
                            anchors.margins: 18
                            spacing: 12

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                height: 30
                                width: modePillTxt.implicitWidth + 24
                                radius: 15
                                color: lockScope.isDocked ? "#1f4e79" : "#276749"

                                Text {
                                    id: modePillTxt
                                    anchors.centerIn: parent
                                    text: lockScope.isDocked
                                        ? "Laptop Mode — Physical Keyboard"
                                        : "Tablet Mode — Touch Unlock"
                                    color: Theme.textPrimary
                                    font.family: Theme.fontSans
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: lockScope.userName
                                color: Theme.textPrimary
                                font.family: Theme.fontSans
                                font.pixelSize: 22
                                font.weight: Font.Bold
                            }

                            Rectangle {
                                width: parent.width
                                height: lockScope.isDocked ? 46 : 54
                                radius: 12
                                color: Theme.bgCard
                                border.width: 1
                                border.color: lockPwInput.activeFocus ? Theme.accentBright : Theme.borderSubtle

                                TextInput {
                                    id: lockPwInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: Theme.textPrimary
                                    font.family: Theme.fontSans
                                    font.pixelSize: lockScope.isDocked ? 16 : 20
                                    echoMode: TextInput.Password
                                    focus: true
                                    text: lockScope.passwordText
                                    onTextChanged: lockScope.passwordText = text
                                    Keys.onReturnPressed: lockScope.submitPassword()
                                    Keys.onEnterPressed: lockScope.submitPassword()

                                    Component.onCompleted: forceActiveFocus()
                                }
                            }

                            Text {
                                visible: lockScope.errorText.length > 0
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: lockScope.errorText
                                color: "#fc8181"
                                font.family: Theme.fontSans
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }

                            Row {
                                width: parent.width
                                spacing: 10

                                Rectangle {
                                    width: parent.width - (lockScope.isDocked ? 58 : 0)
                                    height: lockScope.isDocked ? 46 : 54
                                    radius: 12
                                    color: lockScope.verifying ? Theme.bgTile : Theme.accent

                                    Text {
                                        anchors.centerIn: parent
                                        text: lockScope.verifying ? "Unlocking..." : "Unlock"
                                        color: Theme.textPrimary
                                        font.family: Theme.fontSans
                                        font.pixelSize: lockScope.isDocked ? 16 : 18
                                        font.weight: Font.Bold
                                    }

                                    TapHandler {
                                        onTapped: lockScope.submitPassword()
                                    }
                                }

                                Rectangle {
                                    visible: lockScope.isDocked
                                    width: 48
                                    height: 46
                                    radius: 12
                                    color: lockScope.manualOsk ? Theme.accent : Theme.bgTile
                                    border.width: 1
                                    border.color: Theme.borderSubtle

                                    Text {
                                        anchors.centerIn: parent
                                        text: "⌨"
                                        color: Theme.textPrimary
                                        font.pixelSize: 18
                                    }

                                    TapHandler {
                                        onTapped: lockScope.manualOsk = !lockScope.manualOsk
                                    }
                                }
                            }
                        }
                    }

                    TouchKeyboard {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: lockScope.showTouchKeyboard
                        onKeyPressed: ch => { lockScope.passwordText += ch; }
                        onBackspacePressed: {
                            if (lockScope.passwordText.length > 0) {
                                lockScope.passwordText = lockScope.passwordText.slice(0, -1);
                            }
                        }
                        onEnterPressed: lockScope.submitPassword()
                    }
                }
            }
        }
    }
}
