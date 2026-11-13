import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    TopBar {}
    BottomNavBar {}
    QuickSettingsDrawer {}
    AppGridOverlay {}
    RecentsOverlay {}
    NotificationsOverlay {}
    PolkitOverlay {}
    LockScreen {}

    IpcHandler {
        target: "shell"

        function toggleQuickSettings() {
            StateBridge.toggleQuickSettings();
        }

        function toggleAppGrid() {
            StateBridge.toggleAppGrid();
        }

        function toggleRecents() {
            StateBridge.toggleRecents();
        }

        function closePopups() {
            StateBridge.closePopups();
        }

        function lock() {
            StateBridge.closePopups();
            StateBridge.lockRequested = true;
        }
    }
}
