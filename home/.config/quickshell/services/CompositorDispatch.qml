// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   C O M P O S I T O R   D I S P A T C H                                  │
// │   one dispatch, in the form the running config manager reads             │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root

    readonly property string hyprlangOnlyAnswer: "only supported with the lua config manager"

    property bool luaConfigManager: true

    function send(luaDispatch: string, hyprlangDispatch: string): void {
        if (root.luaConfigManager) {
            Hyprland.dispatch(luaDispatch)
            return
        }
        if (hyprlangDispatch !== "")
            Hyprland.dispatch(hyprlangDispatch)
    }

    readonly property Process configManagerProbe: Process {
        command: ["hyprctl", "eval", "return"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.luaConfigManager = !text.includes(root.hyprlangOnlyAnswer)
        }
    }
}
