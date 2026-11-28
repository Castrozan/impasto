import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

import "../services"
import "../theme"

PanelWindow {
    id: root

    signal paletteRequested()

    property bool shown: false
    property bool online: false
    property bool favouritesOnly: false
    property bool motion: false
    property string localMedia: "all"
    property string motionProvider: "motionbgs"
    property string localQuery: ""
    property string onlineQuery: ""
    property var onlineItems: []
    property int page: 1
    property bool hasMore: false
    property string searchError: ""
    property string previewError: ""
    property string downloadError: ""
    property var selection: null
    property string previewPath: ""
    property int searchRevision: 0
    property int selectionRevision: 0
    property bool searchPending: false
    property bool previewPending: false

    readonly property string provider: root.motion ? root.motionProvider : "wallhaven"
    readonly property string providerName: root.provider === "wallhaven" ? "Wallhaven"
        : root.provider === "motionbgs" ? "MotionBGs" : "MoeWalls"
    readonly property var localItems: {
        if (!root.shown || root.online)
            return []
        const query = root.localQuery.trim().toLowerCase()
        const library = root.favouritesOnly ? WallpaperService.favourites : WallpaperService.collection
        return library.filter(entry => (root.localMedia === "all"
            || WallpaperService.isMotion(entry.path) === (root.localMedia === "animated"))
            && (!query || [entry.name, entry.folder, entry.path.split("/").pop()]
                .some(value => (value ?? "").toLowerCase().includes(query))))
    }
    readonly property var items: root.online ? root.onlineItems : root.localItems
    readonly property bool selectedMotion: root.selection !== null
        && (root.online ? root.selection.motion : WallpaperService.isMotion(root.selection.path))
    readonly property bool gifPreview: root.selectedMotion && root.previewPath.toLowerCase().endsWith(".gif")
    readonly property bool selectedFavourite: !root.online && root.selection !== null
        && WallpaperService.favourites.some(entry => entry.path === root.selection.path)

    visible: root.shown
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "impasto-wallpaper"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    function open(): void {
        root.shown = true
    }

    function close(): void {
        root.shown = false
    }

    onShownChanged: {
        if (root.shown) {
            WallpaperService.scan()
            if (root.online)
                root.search(1)
            searchField.forceActiveFocus()
        } else {
            searchDelay.stop()
            root.searchRevision++
            root.searchPending = false
            root.onlineItems = []
            root.clearSelection()
        }
    }

    onLocalItemsChanged: {
        if (!root.online && root.selection && !root.localItems.some(entry => entry.path === root.selection.path))
            root.clearSelection()
    }

    function fileUrl(path: string): string {
        return "file://" + path.split("/").map(encodeURIComponent).join("/")
    }

    function clearSelection(): void {
        previewDelay.stop()
        root.selectionRevision++
        root.previewPending = false
        root.selection = null
        root.previewPath = ""
        root.previewError = ""
        root.downloadError = ""
        gallery.currentIndex = -1
    }

    function showOnline(value: bool): void {
        if (root.online === value || downloadProcess.running)
            return
        root.clearSelection()
        root.online = value
        if (value)
            root.search(1)
        else {
            searchDelay.stop()
            root.searchRevision++
            root.searchPending = false
        }
        searchField.forceActiveFocus()
    }

    function search(targetPage: int): void {
        root.clearSelection()
        root.page = targetPage
        root.onlineItems = []
        root.hasMore = false
        root.searchError = ""
        root.searchRevision++
        root.searchPending = true
        searchDelay.restart()
    }

    function runSearch(): void {
        if (!root.shown || !root.online || !root.searchPending || searchProcess.running)
            return
        searchProcess.revision = root.searchRevision
        searchProcess.command = root.catalogCommand(["search", "--", root.provider, root.onlineQuery.trim(), String(root.page)])
        searchProcess.running = true
    }

    function select(index: int): void {
        if (index < 0 || index >= root.items.length || downloadProcess.running)
            return
        root.selection = root.items[index]
        gallery.currentIndex = index
        root.selectionRevision++
        root.previewPath = root.online ? "" : root.selection.path
        root.previewPending = root.online
        root.previewError = ""
        root.downloadError = ""
        if (root.online)
            previewDelay.restart()
    }

    function runPreview(): void {
        if (!root.shown || !root.online || !root.previewPending || previewProcess.running)
            return
        previewProcess.revision = root.selectionRevision
        previewProcess.command = root.catalogCommand(["preview", root.provider, root.selection.id, root.selection.pageUrl])
        previewProcess.running = true
    }

    function applySelection(): void {
        if (!root.selection || downloadProcess.running)
            return
        if (!root.online) {
            WallpaperService.apply(root.selection.path)
            root.close()
            return
        }
        root.downloadError = ""
        downloadProcess.revision = root.selectionRevision
        downloadProcess.command = root.catalogCommand(["download", root.provider, root.selection.id, root.selection.pageUrl])
        downloadProcess.running = true
    }

    function catalogCommand(argumentsList: var): var {
        return ["python3", Quickshell.shellPath("scripts/wallpaper_catalog.py")].concat(argumentsList)
    }

    function parseResult(output: string): var {
        try {
            return JSON.parse(output)
        } catch (error) {
            return null
        }
    }

    function errorMessage(details: string, fallback: string): string {
        const firstLine = details.trim().split("\n")[0]
        return firstLine ? firstLine.slice(0, 260) : fallback
    }

    Timer {
        id: searchDelay

        interval: 280
        onTriggered: root.runSearch()
    }

    Timer {
        id: previewDelay

        interval: 180
        onTriggered: root.runPreview()
    }

    Process {
        id: searchProcess

        property int revision: -1

        stdout: StdioCollector { id: searchOutput; waitForEnd: true }
        stderr: StdioCollector { id: searchErrors; waitForEnd: true }
        onExited: exitCode => {
            if (root.shown && root.online && revision === root.searchRevision) {
                root.searchPending = false
                const result = exitCode === 0 ? root.parseResult(searchOutput.text) : null
                if (Array.isArray(result?.items)) {
                    root.onlineItems = result.items
                    root.hasMore = result.hasMore === true
                    gallery.positionViewAtBeginning()
                } else {
                    root.searchError = root.errorMessage(searchErrors.text, Tr.t("Wallpaper search failed."))
                }
            }
            if (root.searchPending && !searchDelay.running)
                Qt.callLater(root.runSearch)
        }
    }

    Process {
        id: previewProcess

        property int revision: -1

        stdout: StdioCollector { id: previewOutput; waitForEnd: true }
        stderr: StdioCollector { id: previewErrors; waitForEnd: true }
        onExited: exitCode => {
            if (root.shown && root.online && revision === root.selectionRevision) {
                root.previewPending = false
                const result = exitCode === 0 ? root.parseResult(previewOutput.text) : null
                if (typeof result?.path === "string" && result.path.startsWith("/"))
                    root.previewPath = result.path
                else
                    root.previewError = root.errorMessage(previewErrors.text, Tr.t("Preview unavailable."))
            }
            if (root.previewPending && !previewDelay.running)
                Qt.callLater(root.runPreview)
        }
    }

    Process {
        id: downloadProcess

        property int revision: -1

        stdout: StdioCollector { id: downloadOutput; waitForEnd: true }
        stderr: StdioCollector { id: downloadErrors; waitForEnd: true }
        onExited: exitCode => {
            if (!root.shown || !root.online || revision !== root.selectionRevision)
                return
            const result = exitCode === 0 ? root.parseResult(downloadOutput.text) : null
            if (typeof result?.path !== "string" || !result.path.startsWith("/")) {
                root.downloadError = root.errorMessage(downloadErrors.text, Tr.t("Wallpaper download failed."))
                return
            }
            WallpaperService.apply(result.path)
            root.close()
        }
    }

    component Caption: Text {
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeRegular
        textFormat: Text.PlainText
    }

    component ActionButton: Controls.Button {
        id: action

        property bool emphasized: false

        implicitHeight: 34
        horizontalPadding: 12
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeRegular

        contentItem: Caption {
            text: action.text
            font: action.font
            color: action.emphasized ? Theme.accentText : Theme.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            opacity: action.enabled ? 1 : 0.45
        }

        background: Rectangle {
            radius: Theme.radiusSmall
            color: action.emphasized ? Theme.accent
                : action.hovered || action.down ? Theme.islandSurfaceHover : Theme.islandSurface
            border.color: action.visualFocus ? Theme.accent : Theme.islandBorder
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.captureWash

        TapHandler {
            onTapped: (eventPoint) => {
                const point = panel.mapFromItem(parent, eventPoint.position.x, eventPoint.position.y)
                if (!panel.contains(point))
                    root.close()
            }
        }
    }

    Rectangle {
        id: panel

        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 1570)
        height: Math.min(parent.height - 48, 1000)
        radius: Theme.radiusLarge
        color: Theme.island
        border.color: Theme.islandBorder

        Shortcut {
            sequence: "Escape"
            enabled: root.shown
            onActivated: root.close()
        }

        Shortcut {
            sequence: "Ctrl+F"
            enabled: root.shown
            onActivated: {
                searchField.forceActiveFocus()
                searchField.selectAll()
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 14

            RowLayout {
                spacing: 8

                Caption {
                    Layout.fillWidth: true
                    text: Tr.t("Wallpapers")
                    font.pixelSize: 24
                    font.weight: Font.DemiBold
                }

                ActionButton {
                    text: Tr.t("Local")
                    enabled: !downloadProcess.running
                    emphasized: !root.online
                    onClicked: root.showOnline(false)
                }

                ActionButton {
                    text: Tr.t("Online")
                    enabled: !downloadProcess.running
                    emphasized: root.online
                    onClicked: root.showOnline(true)
                }

                ActionButton {
                    text: Tr.t("Palette")
                    onClicked: {
                        root.close()
                        root.paletteRequested()
                    }
                }

                ActionButton {
                    text: downloadProcess.running ? Tr.t("Cancel apply") : Tr.t("Close")
                    onClicked: root.close()
                }
            }

            RowLayout {
                spacing: 8
                enabled: !downloadProcess.running

                Controls.TextField {
                    id: searchField

                    Layout.fillWidth: true
                    implicitHeight: 34
                    leftPadding: 12
                    rightPadding: 12
                    color: Theme.text
                    placeholderTextColor: Theme.textMuted
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.accentText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeRegular
                    placeholderText: root.online ? Tr.t("Search online wallpapers") : Tr.t("Search names and folders")
                    text: root.online ? root.onlineQuery : root.localQuery

                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: Theme.islandSurface
                        border.color: searchField.activeFocus ? Theme.accent : Theme.islandBorder
                    }

                    onTextEdited: {
                        if (root.online) {
                            root.onlineQuery = text
                            root.search(1)
                        } else {
                            root.localQuery = text
                            gallery.positionViewAtBeginning()
                        }
                    }

                    Keys.onDownPressed: {
                        gallery.forceActiveFocus()
                        if (gallery.currentIndex < 0)
                            root.select(0)
                    }
                }

                ActionButton {
                    visible: !root.online
                    text: Tr.t("Favourites")
                    emphasized: root.favouritesOnly
                    onClicked: {
                        root.favouritesOnly = !root.favouritesOnly
                        gallery.positionViewAtBeginning()
                    }
                }

                Repeater {
                    model: root.online ? [] : [
                        { id: "all", label: Tr.t("All") },
                        { id: "static", label: Tr.t("Static") },
                        { id: "animated", label: Tr.t("Animated") }
                    ]

                    delegate: ActionButton {
                        required property var modelData

                        text: modelData.label
                        emphasized: root.localMedia === modelData.id
                        onClicked: {
                            root.localMedia = modelData.id
                            gallery.positionViewAtBeginning()
                        }
                    }
                }

                ActionButton {
                    visible: root.online
                    text: Tr.t("Static")
                    emphasized: !root.motion
                    onClicked: {
                        if (!root.motion)
                            return
                        root.motion = false
                        root.search(1)
                    }
                }

                ActionButton {
                    visible: root.online
                    text: Tr.t("Animated")
                    emphasized: root.motion
                    onClicked: {
                        if (root.motion)
                            return
                        root.motion = true
                        root.search(1)
                    }
                }

                ActionButton {
                    visible: root.online && root.motion
                    text: "MotionBGs"
                    emphasized: root.motionProvider === "motionbgs"
                    onClicked: {
                        if (root.motionProvider === "motionbgs")
                            return
                        root.motionProvider = "motionbgs"
                        root.search(1)
                    }
                }

                ActionButton {
                    visible: root.online && root.motion
                    text: "MoeWalls"
                    emphasized: root.motionProvider === "moewalls"
                    onClicked: {
                        if (root.motionProvider === "moewalls")
                            return
                        root.motionProvider = "moewalls"
                        root.search(1)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 16

                ColumnLayout {
                    Layout.preferredWidth: 550
                    Layout.minimumWidth: 200
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 10

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        GridView {
                            id: gallery

                            anchors.fill: parent
                            model: root.shown ? root.items : []
                            enabled: !downloadProcess.running
                            clip: true
                            currentIndex: -1
                            cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 142)))
                            cellHeight: Math.round(cellWidth * 0.58) + 43
                            cacheBuffer: cellHeight
                            boundsBehavior: Flickable.StopAtBounds

                            Controls.ScrollBar.vertical: Controls.ScrollBar {}

                            onCurrentIndexChanged: {
                                if (activeFocus && currentIndex >= 0 && currentItem
                                    && root.selection !== root.items[currentIndex])
                                    root.select(currentIndex)
                            }

                            Keys.onReturnPressed: root.select(currentIndex)
                            Keys.onEnterPressed: root.select(currentIndex)

                            delegate: Item {
                                id: tile

                                required property var modelData
                                required property int index

                                width: gallery.cellWidth - 8
                                height: gallery.cellHeight - 8

                                readonly property bool animated: root.online ? modelData.motion : WallpaperService.isMotion(modelData.path)
                                readonly property bool selected: root.selection !== null && (root.online
                                    ? root.selection.id === modelData.id : root.selection.path === modelData.path)

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.radiusSmall
                                    color: hover.hovered ? Theme.islandSurfaceHover : Theme.islandSurface
                                    border.color: tile.selected ? Theme.accent : Theme.islandBorder
                                    border.width: tile.selected ? 2 : 1
                                }

                                HoverHandler { id: hover }

                                TapHandler {
                                    onTapped: {
                                        root.select(tile.index)
                                        gallery.forceActiveFocus()
                                    }
                                }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 3

                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        clip: true

                                        Caption {
                                            anchors.centerIn: parent
                                            width: parent.width
                                            horizontalAlignment: Text.AlignHCenter
                                            visible: thumbnail.status !== Image.Ready
                                            text: thumbnail.status === Image.Loading ? Tr.t("Loading…")
                                                : tile.animated ? Tr.t("Animated") : Tr.t("No thumbnail")
                                            color: Theme.textMuted
                                            font.pixelSize: Theme.fontSizeSmall
                                            elide: Text.ElideRight
                                        }

                                        Image {
                                            id: thumbnail

                                            anchors.fill: parent
                                            source: root.online ? tile.modelData.thumbnail
                                                : tile.animated && !tile.modelData.poster ? ""
                                                : root.fileUrl(tile.modelData.poster || tile.modelData.path)
                                            asynchronous: true
                                            fillMode: Image.PreserveAspectCrop
                                            sourceSize.width: 320
                                            sourceSize.height: 192
                                        }
                                    }

                                    Caption {
                                        Layout.fillWidth: true
                                        text: root.online ? tile.modelData.title : tile.modelData.name
                                        elide: Text.ElideRight
                                        font.weight: tile.selected ? Font.DemiBold : Font.Normal
                                    }

                                    Caption {
                                        Layout.fillWidth: true
                                        text: root.online ? (tile.animated ? Tr.t("Animated") : root.providerName)
                                            : (tile.modelData.folder || Tr.t("Library"))
                                        color: Theme.textMuted
                                        font.pixelSize: Theme.fontSizeSmall
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }

                        Caption {
                            anchors.centerIn: parent
                            width: parent.width - 20
                            visible: root.items.length === 0
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            color: Theme.textMuted
                            text: root.online
                                ? (root.searchPending ? Tr.t("Searching…") : root.searchError || Tr.t("No wallpapers found."))
                                : (WallpaperService.scanning ? Tr.t("Scanning…")
                                    : root.favouritesOnly && !root.localQuery ? Tr.t("No favourites yet.") : Tr.t("No wallpapers found."))
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.online
                        enabled: !downloadProcess.running

                        Caption {
                            Layout.fillWidth: true
                            text: root.providerName + " · " + Tr.t("Page") + " " + root.page
                            color: Theme.textMuted
                        }

                        ActionButton {
                            text: Tr.t("Retry")
                            visible: root.searchError !== ""
                            onClicked: root.search(root.page)
                        }

                        ActionButton {
                            text: Tr.t("Previous")
                            enabled: !root.searchPending && root.page > 1
                            onClicked: root.search(root.page - 1)
                        }

                        ActionButton {
                            text: Tr.t("Next")
                            enabled: !root.searchPending && root.hasMore
                            onClicked: root.search(root.page + 1)
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 840
                    Layout.minimumWidth: 220
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.radiusMedium
                    color: Theme.islandSurface
                    border.color: Theme.islandBorder

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 10

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: Theme.island
                            radius: Theme.radiusSmall
                            clip: true

                            Image {
                                id: stillPreview

                                anchors.fill: parent
                                source: root.shown && !root.selectedMotion && root.previewPath
                                    ? root.fileUrl(root.previewPath) : ""
                                asynchronous: true
                                fillMode: Image.PreserveAspectFit
                                sourceSize.width: Math.round(width * 2)
                                sourceSize.height: Math.round(height * 2)
                            }

                            AnimatedImage {
                                id: animatedPreview

                                anchors.fill: parent
                                source: root.shown && root.gifPreview ? root.fileUrl(root.previewPath) : ""
                                playing: root.shown && root.gifPreview
                                asynchronous: true
                                cache: false
                                fillMode: Image.PreserveAspectFit
                            }

                            Loader {
                                id: videoPreview

                                anchors.fill: parent
                                active: root.shown && root.selectedMotion && !root.gifPreview && root.previewPath !== ""
                                sourceComponent: Video {
                                    source: root.fileUrl(root.previewPath)
                                    autoPlay: true
                                    loops: MediaPlayer.Infinite
                                    muted: true
                                    fillMode: VideoOutput.PreserveAspectFit
                                }
                            }

                            Caption {
                                anchors.centerIn: parent
                                width: parent.width - 24
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                color: Theme.textMuted
                                text: {
                                    if (!root.selection)
                                        return Tr.t("Select a wallpaper to preview")
                                    if (root.previewPending || stillPreview.status === Image.Loading || animatedPreview.status === Image.Loading)
                                        return Tr.t("Loading preview…")
                                    if (root.previewError)
                                        return root.previewError
                                    if (stillPreview.status === Image.Error || animatedPreview.status === Image.Error || videoPreview.item?.error)
                                        return Tr.t("Preview unavailable.")
                                    return ""
                                }
                            }
                        }

                        Caption {
                            Layout.fillWidth: true
                            visible: root.selection !== null
                            text: root.selection ? (root.online ? root.selection.title : root.selection.name) : ""
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Caption {
                                Layout.fillWidth: true
                                text: {
                                    if (root.downloadError)
                                        return root.downloadError
                                    if (!root.selection)
                                        return ""
                                    if (!root.online)
                                        return root.selection.path === WallpaperService.chosen ? Tr.t("Current wallpaper")
                                            : root.selection.folder || Tr.t("Library")
                                    if (root.selection.width && root.selection.height)
                                        return root.providerName + " · " + root.selection.width + " × " + root.selection.height
                                    return root.providerName
                                }
                                color: Theme.textMuted
                                wrapMode: Text.WordWrap
                            }

                            ActionButton {
                                visible: !root.online && root.selection !== null
                                text: root.selectedFavourite ? Tr.t("Remove favourite") : Tr.t("Add favourite")
                                onClicked: WallpaperService.toggleFavourite(root.selection.path)
                            }

                            ActionButton {
                                visible: root.online && root.previewError !== ""
                                enabled: !downloadProcess.running
                                text: Tr.t("Retry preview")
                                onClicked: root.select(gallery.currentIndex)
                            }

                            ActionButton {
                                text: downloadProcess.running ? Tr.t("Downloading…") : Tr.t("Apply")
                                enabled: root.selection !== null && !downloadProcess.running
                                emphasized: enabled
                                onClicked: root.applySelection()
                            }
                        }
                    }
                }
            }
        }
    }
}
