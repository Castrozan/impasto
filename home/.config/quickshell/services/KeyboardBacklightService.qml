
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

import "../theme"

Singleton {
    id: root

    readonly property var levels: [0, 5, 25, 50, 100]

    property string device: ""
    property int raw: 0
    property int maximum: 0

    readonly property bool available: root.device !== "" && root.maximum > 0
    readonly property int percent: root.maximum > 0 ? Math.round(root.raw / root.maximum * 100) : 0
    readonly property string icon: root.raw > 0 ? "󰌌" : "󰌐"
    readonly property string detail: root.raw > 0 ? `${root.percent}%` : Tr.t("Off")

    function cycle(): void {
        const next = root.levels
            .map(level => Math.round(level * root.maximum / 100))
            .find(step => step > root.raw)
        root.setRaw(next ?? 0)
    }

    function setPercent(value: int): void {
        root.setRaw(Math.round(value * root.maximum / 100))
    }

    function setRaw(value: int): void {
        if (!root.available)
            return
        root.raw = Math.max(0, Math.min(root.maximum, value))
        root.write.restart()
    }

    readonly property Process discovery: Process {
        command: ["sh", "-c", "ls -1 /sys/class/leds/ 2>/dev/null | grep kbd_backlight | head -1"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const name = text.trim()
                if (name !== "")
                    root.device = name
            }
        }
    }

    readonly property FileView maxView: FileView {
        path: root.device === "" ? "" : `/sys/class/leds/${root.device}/max_brightness`
        onLoaded: root.maximum = parseInt(text().trim()) || 0
    }

    readonly property FileView levelView: FileView {
        path: root.device === "" ? "" : `/sys/class/leds/${root.device}/brightness`
        watchChanges: true
        onLoaded: root.raw = parseInt(text().trim()) || 0
        onFileChanged: reload()
    }

    readonly property Timer write: Timer {
        interval: 120
        onTriggered: Quickshell.execDetached(["brightnessctl", "--quiet", "--class=leds",
            `--device=${root.device}`, "set", String(root.raw)])
    }
}
