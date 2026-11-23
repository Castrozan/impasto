// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   K E Y B O A R D   B A C K L I G H T   M O D U L E                      │
// │   keyboard backlight · the led's ring, a level when open                 │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick

import "../../theme"
import "../../services"
import "../../components"

Item {
    id: root

    property bool compact: false

    implicitWidth: holder.implicitWidth
    implicitHeight: holder.implicitHeight

    Loader {
        id: holder
        anchors.fill: parent
        sourceComponent: root.compact ? chip : detail
    }

    Component {
        id: chip

        Item {
            Item {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.capsuleHeight
                height: Theme.capsuleHeight

                RingIndicator {
                    anchors.fill: parent
                    thickness: 2.5
                    progress: KeyboardBacklightService.percent / 100
                    trackColor: Theme.indicatorDim
                    fillColor: Theme.indicator

                    Text {
                        anchors.centerIn: parent
                        text: KeyboardBacklightService.icon
                        font.family: Theme.fontMono
                        font.pixelSize: Math.round(Theme.capsuleHeight * 0.38)
                        color: Theme.indicator
                    }
                }
            }
        }
    }

    Component {
        id: detail

        ModuleCard {
            title: Tr.t("Keyboard backlight")
            subtitle: KeyboardBacklightService.detail
            figure: `${KeyboardBacklightService.percent}%`

            mark: RingIndicator {
                anchors.fill: parent
                thickness: 3
                progress: KeyboardBacklightService.percent / 100
                trackColor: Theme.indicatorDim
                fillColor: Theme.indicator

                Text {
                    anchors.centerIn: parent
                    text: KeyboardBacklightService.icon
                    font.family: Theme.fontMono
                    font.pixelSize: 18
                    color: Theme.indicator
                }
            }

            CardLevel {
                glyph: KeyboardBacklightService.icon
                name: Tr.t("Backlight")
                value: KeyboardBacklightService.percent
                onMoved: value => KeyboardBacklightService.setPercent(value)
            }
        }
    }
}
