import QtQuick
import QtQuick.Layouts
import Quickshell

import "../../theme"
import "../../services"
import "../../components"

FocusScope {
    id: root

    signal wallpaperRequested()

    function apply(): void {
        const palette = ThemeService.availableThemes[palettes.current]
        if (palette)
            ThemeService.setTheme(palette.id)
    }

    function daubsOf(theme: var): var {
        const colors = theme.adaptive ? ThemeService.dynamicColors : theme.colors
        return colors
            ? [colors.accent, colors.green, colors.yellow, colors.red, colors.blue]
            : [Theme.accent, Theme.green, Theme.yellow, Theme.red, Theme.blue]
    }

    Component.onCompleted: root.forceActiveFocus()

    Keys.onLeftPressed: palettes.step(-1)
    Keys.onRightPressed: palettes.step(1)
    Keys.onUpPressed: root.wallpaperRequested()
    Keys.onReturnPressed: root.apply()
    Keys.onEnterPressed: root.apply()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Home)
            palettes.goTo(0)
        else if (event.key === Qt.Key_End)
            palettes.goTo(palettes.count - 1)
        else if (event.key === Qt.Key_PageUp)
            palettes.step(-5)
        else if (event.key === Qt.Key_PageDown)
            palettes.step(5)
        else
            return
        event.accepted = true
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        Carousel {
            id: palettes

            Layout.fillWidth: true
            Layout.fillHeight: true
            current: Math.max(0, ThemeService.availableThemes.findIndex(
                entry => entry.id === ThemeService.activeId))
            model: ThemeService.availableThemes
            tileWidth: 160
            tileHeight: 100
            centreScale: 1.25
            gap: 12
            onActivated: root.apply()

            delegate: CarouselTile {
                id: card

                readonly property bool applied: card.modelData.id === ThemeService.activeId

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusMedium
                    color: card.hovered ? Theme.surfaceHoverIn(QsWindow.window) : Theme.surfaceIn(QsWindow.window)
                    border.color: card.centred ? Theme.accent : Theme.borderIn(QsWindow.window)
                    border.width: card.centred ? 2 : 1

                    Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                    Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

                    Column {
                        anchors.centerIn: parent
                        spacing: 10

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 6

                            Repeater {
                                model: root.daubsOf(card.modelData)

                                Rectangle {
                                    required property var modelData

                                    width: 12
                                    height: 12
                                    radius: width / 2
                                    color: modelData
                                    border.color: Theme.hairline
                                    border.width: 1

                                    Behavior on color { ColorAnimation { duration: Theme.paletteTransition } }
                                }
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Tr.t(card.modelData.name)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: card.centred ? Font.DemiBold : Font.Normal
                            color: card.centred ? Theme.text : Theme.textMuted
                        }
                    }

                    AppliedMark { visible: card.applied }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Text {
                Layout.fillWidth: true
                text: Tr.t(ThemeService.availableThemes[palettes.current]?.badge ?? "")
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textMuted
            }

            Text {
                visible: palettes.count > 0
                text: `${palettes.current + 1}/${palettes.count}`
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.textMuted
            }

            Text {
                text: Tr.t("Wallpapers")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: wallpaperHover.hovered ? Theme.text : Theme.textMuted

                HoverHandler {
                    id: wallpaperHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler { onTapped: root.wallpaperRequested() }
            }
        }
    }

    // The check on what is applied, distinct from the accent ring, which
    // marks the position in the strip.
    component AppliedMark: Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 6
        width: 18
        height: 18
        radius: width / 2
        color: Theme.accent

        Text {
            anchors.centerIn: parent
            text: "󰄬"
            font.family: Theme.fontMono
            font.pixelSize: 10
            color: Theme.accentText
        }
    }
}
