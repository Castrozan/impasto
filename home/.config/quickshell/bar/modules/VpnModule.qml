// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   V P N   M O D U L E                                                    │
// │   vpn · the connection's state, a switch when open                       │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import QtQuick.Layouts

import "../../theme"
import "../../services"
import "../../components"

Item {
    id: root

    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight

    ModuleCard {
        id: card

        anchors.fill: parent
        title: Tr.t("VPN")
        subtitle: VpnService.detail

        mark: RingIndicator {
            anchors.fill: parent
            thickness: 3
            progress: 0
            trackColor: Theme.indicatorDim

            Text {
                anchors.centerIn: parent
                text: VpnService.icon
                font.family: Theme.fontMono
                font.pixelSize: 18
                color: VpnService.connected ? Theme.indicator : Theme.textMuted
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.cardRow
            spacing: 10

            Text {
                Layout.fillWidth: true
                text: Tr.t("Connection")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textMuted
            }

            ToggleSwitch {
                checked: VpnService.connected
                onToggled: VpnService.toggle()
            }
        }

        CardFact {
            name: Tr.t("Unit")
            value: VpnService.unit
        }
    }
}
