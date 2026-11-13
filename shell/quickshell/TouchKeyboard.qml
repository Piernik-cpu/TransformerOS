import QtQuick
import QtQuick.Layouts

Rectangle {
    id: kbdRoot
    property bool compact: false
    property bool shifted: false
    property bool symbols: false

    signal keyPressed(string ch)
    signal backspacePressed()
    signal enterPressed()

    readonly property int keyHeight: compact ? 42 : 50
    readonly property int keySpacing: compact ? 5 : 6

    implicitWidth: Math.min(760, kbdColumn.implicitWidth + 20)
    implicitHeight: kbdColumn.implicitHeight + 20
    radius: 16
    color: "#cc111726"
    border.width: 1
    border.color: Theme.borderSubtle

    readonly property var alphaRows: [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l", "⌫"],
        ["⇧", "z", "x", "c", "v", "b", "n", "m", ".", "-"],
        ["?!#", ",", " ", "_", "@", "↵"]
    ]

    readonly property var symbolRows: [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")"],
        ["-", "_", "=", "+", "[", "]", "{", "}", "/", "⌫"],
        [";", ":", "'", "\"", ",", ".", "<", ">", "?", "\\"],
        ["ABC", "`", " ", "~", "|", "↵"]
    ]

    readonly property var activeRows: symbols ? symbolRows : alphaRows

    function handleKey(raw) {
        if (raw === "⌫") {
            backspacePressed();
        } else if (raw === "⇧") {
            shifted = !shifted;
        } else if (raw === "?!#" || raw === "ABC") {
            symbols = !symbols;
        } else if (raw === "↵") {
            enterPressed();
        } else {
            const out = (!symbols && shifted && raw.length === 1 && raw >= "a" && raw <= "z")
                ? raw.toUpperCase()
                : raw;
            keyPressed(out);
            if (shifted && !symbols && raw.length === 1 && raw >= "a" && raw <= "z") {
                shifted = false;
            }
        }
    }

    Column {
        id: kbdColumn
        anchors.centerIn: parent
        spacing: kbdRoot.keySpacing

        Repeater {
            model: kbdRoot.activeRows
            delegate: Row {
                id: rowItem
                required property var modelData
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: kbdRoot.keySpacing

                Repeater {
                    model: rowItem.modelData
                    delegate: Rectangle {
                        id: keyCap
                        required property string modelData
                        readonly property bool isSpecial: modelData === "⌫" || modelData === "⇧" || modelData === "↵" || modelData === "?!#" || modelData === "ABC"
                        readonly property bool isSpace: modelData === " "
                        readonly property bool isEnter: modelData === "↵"
                        readonly property bool isActiveShift: modelData === "⇧" && kbdRoot.shifted

                        width: isSpace ? (kbdRoot.compact ? 190 : 230)
                             : (isEnter ? (kbdRoot.compact ? 74 : 88)
                             : (modelData === "?!#" || modelData === "ABC" ? (kbdRoot.compact ? 64 : 74)
                             : (kbdRoot.compact ? 50 : 58)))
                        height: kbdRoot.keyHeight
                        radius: 10
                        color: keyTap.pressed ? Theme.accent
                             : isEnter ? "#2b6cb0"
                             : isActiveShift ? Theme.accent
                             : isSpecial ? "#253147"
                             : "#1e273a"
                        border.width: 1
                        border.color: (keyTap.pressed || isActiveShift) ? Theme.accentBright : "#313f59"

                        Text {
                            anchors.centerIn: parent
                            text: {
                                if (keyCap.isSpace) return "Space";
                                if (!kbdRoot.symbols && kbdRoot.shifted && keyCap.modelData.length === 1 && keyCap.modelData >= "a" && keyCap.modelData <= "z") {
                                    return keyCap.modelData.toUpperCase();
                                }
                                return keyCap.modelData;
                            }
                            color: Theme.textPrimary
                            font.family: Theme.fontSans
                            font.pixelSize: keyCap.isSpace || keyCap.modelData === "?!#" || keyCap.modelData === "ABC" ? 15 : 18
                            font.weight: keyCap.isSpecial ? Font.DemiBold : Font.Medium
                        }

                        TapHandler {
                            id: keyTap
                            onTapped: kbdRoot.handleKey(keyCap.modelData)
                        }
                    }
                }
            }
        }
    }
}
