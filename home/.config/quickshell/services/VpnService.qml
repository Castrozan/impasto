
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

import "../theme"

Singleton {
    id: root

    readonly property string unit: SettingsService.vpnUnit.trim()
    readonly property string connectCommand: SettingsService.vpnConnectCommand.trim()
    readonly property string disconnectCommand: SettingsService.vpnDisconnectCommand.trim()

    readonly property bool available: root.unit !== ""
        && root.connectCommand !== "" && root.disconnectCommand !== ""

    property bool connected: false

    readonly property string icon: root.connected ? "󰦝" : "󰦞"
    readonly property string detail: root.connected ? Tr.t("Connected") : Tr.t("Disconnected")

    function toggle(): void {
        if (!root.available || root.switcher.running)
            return
        root.switcher.command = ["sh", "-c", root.connected ? root.disconnectCommand : root.connectCommand]
        root.switcher.running = true
    }

    function read(): void {
        if (!root.available || root.reader.running)
            return
        root.reader.running = true
    }

    onAvailableChanged: {
        if (root.available)
            root.read()
        else
            root.connected = false
    }

    readonly property Process reader: Process {
        command: ["systemctl", "is-active", root.unit]
        stdout: StdioCollector {
            onStreamFinished: root.connected = text.trim() === "active"
        }
    }

    readonly property Process switcher: Process {
        onExited: root.read()
    }

    readonly property Timer poller: Timer {
        interval: 5000
        repeat: true
        running: root.available
        triggeredOnStart: true
        onTriggered: root.read()
    }
}
