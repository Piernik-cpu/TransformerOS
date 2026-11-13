import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit

Scope {
    id: polkitScope
    property string passwordText: ""

    PolkitAgent {
        id: agent
        onAuthenticationRequestStarted: {
            polkitScope.passwordText = "";
        }
    }

    function submitAuth() {
        if (!agent.flow) return;
        agent.flow.submit(passwordText);
        passwordText = "";
    }

    PanelWindow {
        visible: agent.isActive && agent.flow !== null
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        onVisibleChanged: {
            if (visible && !StateBridge.isTabletMode) {
                pkInput.forceActiveFocus();
            }
        }

        Rectangle {
            anchors.fill: parent
            color: "#b0080c16"

            Column {
                anchors.centerIn: parent
                width: Math.min(parent.width - 32, 760)
                spacing: 14

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width, 460)
                    height: pkCardCol.implicitHeight + 36
                    radius: 18
                    color: "#f5131c2e"
                    border.width: 1
                    border.color: Theme.borderSubtle

                    Column {
                        id: pkCardCol
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 12

                        Text {
                            width: parent.width
                            text: "Authentication Required"
                            color: Theme.textPrimary
                            font.family: Theme.fontSans
                            font.pixelSize: 18
                            font.weight: Font.Bold
                        }

                        Text {
                            width: parent.width
                            text: agent.flow ? agent.flow.message : ""
                            color: Theme.textSecondary
                            font.family: Theme.fontSans
                            font.pixelSize: 13
                            wrapMode: Text.Wrap
                        }

                        Rectangle {
                            width: parent.width
                            height: 46
                            radius: 12
                            color: Theme.bgCard
                            border.width: 1
                            border.color: pkInput.activeFocus ? Theme.accentBright : Theme.borderSubtle

                            TextInput {
                                id: pkInput
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.textPrimary
                                font.family: Theme.fontSans
                                font.pixelSize: 16
                                echoMode: (agent.flow && agent.flow.responseVisible) ? TextInput.Normal : TextInput.Password
                                text: polkitScope.passwordText
                                onTextChanged: polkitScope.passwordText = text
                                Keys.onReturnPressed: polkitScope.submitAuth()
                                Keys.onEscapePressed: if (agent.flow) agent.flow.cancelAuthenticationRequest()
                            }
                        }

                        Text {
                            visible: agent.flow && agent.flow.supplementaryMessage.length > 0
                            width: parent.width
                            text: agent.flow ? agent.flow.supplementaryMessage : ""
                            color: (agent.flow && agent.flow.supplementaryIsError) ? "#fc8181" : Theme.textSecondary
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            wrapMode: Text.Wrap
                        }

                        Row {
                            width: parent.width
                            spacing: 10

                            Rectangle {
                                width: (parent.width - 10) / 2
                                height: 46
                                radius: 12
                                color: Theme.bgTile

                                Text {
                                    anchors.centerIn: parent
                                    text: "Cancel"
                                    color: Theme.textPrimary
                                    font.family: Theme.fontSans
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                }

                                TapHandler {
                                    onTapped: if (agent.flow) agent.flow.cancelAuthenticationRequest()
                                }
                            }

                            Rectangle {
                                width: (parent.width - 10) / 2
                                height: 46
                                radius: 12
                                color: Theme.accent

                                Text {
                                    anchors.centerIn: parent
                                    text: "Authenticate"
                                    color: Theme.textPrimary
                                    font.family: Theme.fontSans
                                    font.pixelSize: 14
                                    font.weight: Font.Bold
                                }

                                TapHandler {
                                    onTapped: polkitScope.submitAuth()
                                }
                            }
                        }
                    }
                }

                TouchKeyboard {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: StateBridge.isTabletMode
                    compact: true
                    onKeyPressed: ch => { polkitScope.passwordText += ch; }
                    onBackspacePressed: {
                        if (polkitScope.passwordText.length > 0) {
                            polkitScope.passwordText = polkitScope.passwordText.slice(0, -1);
                        }
                    }
                    onEnterPressed: polkitScope.submitAuth()
                }
            }
        }
    }
}
