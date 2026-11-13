// TransformerOS Quickshell QML companion configuration
// Reads /run/user/$UID/transformeros/state.json maintained by transformerd
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property string effectiveMode: "docked"
    property bool gameMode: false
    property int batteryPct: 100

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: stateProc.running = true
    }

    Process {
        id: stateProc
        command: ["transformerd", "status"]
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => {
                try {
                    const st = JSON.parse(data);
                    root.effectiveMode = st.effective_mode || "docked";
                    root.gameMode = !!st.game_mode;
                    root.batteryPct = st.battery_pct || 100;
                } catch (e) {}
            }
        }
    }
}
