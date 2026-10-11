import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import qs.services

// App Picker: a full-screen (or centered, windowed) grid of every app the
// Omarchy Apps menu shows. Apps can be sorted A-Z / Z-A, filtered by typing,
// and ranked as favorites by dragging them into the Favorites box.
//
// Opened with `omarchy-shell shell toggle mulcahyio.app-picker`.
// Favorites, sort order, view and window mode are kept in
// ~/.local/state/omarchy-app-picker.json (outside the plugin folder, because
// saving inside it would make the shell reload the plugin).
Item {
  id: root

  // Injected by omarchy-shell.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  // The shell hands menu plugins an app-library facade, but for third-party
  // plugins it currently arrives as null (Omarchy 4.0.4). Fall back to a
  // private copy of Omarchy's own AppLibrary, which gives the same app list,
  // hidden-app rules, icons and launch behaviour as the Apps menu.
  readonly property var appLibrary: root.shell && root.shell.appLibrary ? root.shell.appLibrary : ownLibrary
  AppLibrary { id: ownLibrary }

  // Lifecycle hooks called by the shell.
  function open(payloadJson) {
    root.filterText = ""
    root.cancelDrag()
    if (root.appLibrary) root.appLibrary.refreshIcons()
    root.rebuildAll()
    root.currentIndex = 0
    root.hoverX = -1
    root.hoverY = -1
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.cancelDrag()
    root.opened = false
  }

  // Close from inside the picker (Esc, launch, ✕). Going through the shell
  // keeps its open/closed bookkeeping in step with ours.
  property bool hiding: false
  function dismiss() {
    root.close()
    if (root.hiding || !root.shell || typeof root.shell.hide !== "function") return
    root.hiding = true
    root.shell.hide("mulcahyio.app-picker")
    root.hiding = false
  }

  function ping() { return "ok" }

  property bool opened: false

  // Saved preferences.
  property string sortOrder: "asc"      // "asc" (A-Z) or "desc" (Z-A)
  property string view: "all"           // "all" or "favorites"
  property bool fullscreen: true
  property var favorites: []            // desktop ids, rank 1 first

  // Derived lists. Each app is {id, name, icon, subtext}.
  property var allApps: []
  property var apps: []                 // what the grid shows
  property var favoriteApps: []         // favorites that are installed, in rank order
  property var favoriteRanks: ({})      // id -> rank (1-based)
  property string appIdsKey: ""
  property string filterText: ""
  property int currentIndex: 0

  // Drag state. Coordinates are in dragLayer space.
  property bool dragPending: false
  property bool dragging: false
  property var dragApp: null
  property bool dragFromFavorites: false
  property real pressX: 0
  property real pressY: 0
  property real dragX: 0
  property real dragY: 0
  property int dropIndex: -1            // insertion index in Favorites, -1 = not over it
  readonly property int dragThreshold: Style.space(8)

  // Look: follows the theme's [menu] colors like the Omarchy menu.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color accent: Color.accent
  readonly property int cornerRadius: Style.cornerRadius
  readonly property int pad: Style.spacing.panelPadding
  property string fontFamily: Style.font.menuFamily

  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy-app-picker.json"

  // ---- State file -------------------------------------------------------

  FileView {
    id: stateFile
    path: root.statePath
    blockLoading: true
    printErrors: false
    atomicWrites: true
    onLoaded: root.loadState(text())
  }

  function loadState(raw) {
    var s = ({})
    try { s = JSON.parse(raw || "{}") } catch (e) { s = ({}) }
    if (s.sortOrder === "asc" || s.sortOrder === "desc") root.sortOrder = s.sortOrder
    if (s.view === "all" || s.view === "favorites") root.view = s.view
    if (typeof s.fullscreen === "boolean") root.fullscreen = s.fullscreen
    if (Array.isArray(s.favorites)) root.favorites = s.favorites.map(String)
    root.rebuildView()
  }

  function saveState() {
    stateFile.setText(JSON.stringify({
      version: 1,
      sortOrder: root.sortOrder,
      view: root.view,
      fullscreen: root.fullscreen,
      favorites: root.favorites
    }, null, 2) + "\n")
  }

  // ---- App lists ----------------------------------------------------------

  Connections {
    target: root.appLibrary
    ignoreUnknownSignals: true
    function onAppsChanged() { root.rebuildAll() }
  }

  onAppLibraryChanged: rebuildAll()

  function appFromRow(row) {
    var entry = row && row.entry ? row.entry : row
    var id = String(entry && entry.id || "")
    if (!id) return null
    return {
      id: id,
      name: root.appLibrary.entryName(entry),
      icon: String(entry.icon || ""),
      subtext: root.appLibrary.entrySubtext(entry)
    }
  }

  function rebuildAll() {
    var list = []
    if (root.appLibrary) {
      var rows = root.appLibrary.sortedEntries("")
      for (var i = 0; i < rows.length; i++) {
        var app = appFromRow(rows[i])
        if (app) list.push(app)
      }
    }
    root.allApps = list
    root.rebuildView()
  }

  function compareNames(a, b) {
    var r = a.name.localeCompare(b.name, undefined, { sensitivity: "base", numeric: true })
    return root.sortOrder === "desc" ? -r : r
  }

  function rebuildView() {
    var byId = ({})
    for (var i = 0; i < root.allApps.length; i++) byId[root.allApps[i].id] = root.allApps[i]

    // Favorites that are still installed, in rank order.
    var favs = []
    var ranks = ({})
    for (var f = 0; f < root.favorites.length; f++) {
      var fav = byId[root.favorites[f]]
      if (fav && ranks[fav.id] === undefined) {
        favs.push(fav)
        ranks[fav.id] = favs.length
      }
    }
    root.favoriteApps = favs
    root.favoriteRanks = ranks

    // Search uses the same matching as the Omarchy Apps menu.
    var matched = null
    if (root.filterText && root.appLibrary) {
      matched = ({})
      var rows = root.appLibrary.sortedEntries(root.filterText)
      for (var m = 0; m < rows.length; m++) {
        var app = appFromRow(rows[m])
        if (app) matched[app.id] = true
      }
    }

    var list
    if (root.view === "favorites") {
      list = favs.slice()
    } else {
      list = root.allApps.slice()
      list.sort(root.compareNames)
    }
    if (matched) list = list.filter(function(a) { return matched[a.id] === true })

    // Only replace the grid model when the visible apps changed, so ranking a
    // favorite doesn't reset the grid or its scroll position.
    var ids = list.map(function(a) { return a.id }).join("\n")
    if (ids !== root.appIdsKey) {
      root.appIdsKey = ids
      root.apps = list
    }
    root.currentIndex = Math.max(0, Math.min(root.currentIndex, list.length - 1))
  }

  onFilterTextChanged: { root.currentIndex = 0; rebuildView() }

  // ---- Actions ------------------------------------------------------------

  function launch(app) {
    if (!app || !root.appLibrary) return
    root.appLibrary.launch(app.id, app.name)
    root.dismiss()
  }

  function setSort(order) {
    if (root.sortOrder === order) return
    root.sortOrder = order
    saveState()
    rebuildView()
  }

  function setView(v) {
    if (root.view === v) return
    root.view = v
    root.currentIndex = 0
    saveState()
    rebuildView()
  }

  function toggleFullscreen() {
    root.fullscreen = !root.fullscreen
    saveState()
  }

  function setFavorites(ids) {
    root.favorites = ids
    saveState()
    rebuildView()
  }

  function visibleFavoriteIds() {
    return root.favoriteApps.map(function(a) { return a.id })
  }

  // Put `id` at rank `index + 1`, moving it if it is already a favorite.
  function placeFavorite(id, index) {
    var ids = visibleFavoriteIds()
    var from = ids.indexOf(id)
    if (from !== -1) {
      ids.splice(from, 1)
      if (from < index) index--
    }
    index = Math.max(0, Math.min(index, ids.length))
    ids.splice(index, 0, id)
    setFavorites(ids)
  }

  function removeFavorite(id) {
    setFavorites(visibleFavoriteIds().filter(function(x) { return x !== id }))
  }

  function toggleFavorite(app) {
    if (!app) return
    if (root.favoriteRanks[app.id] !== undefined) removeFavorite(app.id)
    else placeFavorite(app.id, root.favoriteApps.length)
  }

  function moveFavorite(app, delta) {
    if (!app || root.favoriteRanks[app.id] === undefined) return
    var target = root.favoriteRanks[app.id] - 1 + delta
    if (target < 0 || target >= root.favoriteApps.length) return
    placeFavorite(app.id, delta > 0 ? target + 1 : target)
    if (root.view === "favorites") {
      var at = root.apps.map(function(a) { return a.id }).indexOf(app.id)
      if (at >= 0) root.currentIndex = at
    }
  }

  // ---- Drag and drop ------------------------------------------------------

  function pressOn(app, fromFavorites, point) {
    root.dragApp = app
    root.dragFromFavorites = fromFavorites
    root.pressX = point.x
    root.pressY = point.y
    root.dragPending = true
  }

  // Returns true when the press turned into a drag.
  function moveOn(point) {
    if (!root.dragPending && !root.dragging) return false
    root.dragX = point.x
    root.dragY = point.y
    if (!root.dragging) {
      if (Math.abs(point.x - root.pressX) + Math.abs(point.y - root.pressY) < root.dragThreshold) return false
      root.dragging = true
    }
    root.dropIndex = favoritesDropIndex(point)
    return true
  }

  // Returns true when a drag was dropped (so the release is not a click).
  function releaseOn() {
    var wasDragging = root.dragging
    if (wasDragging && root.dragApp) {
      // Applied after the release handler returns: changing favorites
      // rebuilds the chips, and the chip being released may be one of them.
      var id = root.dragApp.id
      var index = root.dropIndex
      var fromFavorites = root.dragFromFavorites
      Qt.callLater(function() {
        if (index >= 0) root.placeFavorite(id, index)
        else if (fromFavorites) root.removeFavorite(id)
      })
    }
    cancelDrag()
    return wasDragging
  }

  function cancelDrag() {
    root.dragPending = false
    root.dragging = false
    root.dragApp = null
    root.dropIndex = -1
  }

  // Insertion index in the Favorites box for a point in dragLayer space,
  // or -1 when the point is outside the box.
  function favoritesDropIndex(point) {
    var p = favBox.mapFromItem(dragLayer, point.x, point.y)
    if (p.x < 0 || p.y < 0 || p.x > favBox.width || p.y > favBox.height) return -1
    var local = favFlow.mapFromItem(dragLayer, point.x, point.y)
    for (var i = 0; i < favRepeater.count; i++) {
      var chip = favRepeater.itemAt(i)
      if (!chip) continue
      var sameRowOrAbove = local.y < chip.y + chip.height
      if (sameRowOrAbove && (local.y < chip.y || local.x < chip.x + chip.width / 2)) return i
    }
    return favRepeater.count
  }

  // Rank the dragged app will get if dropped now (moving an existing
  // favorite later in the list frees up its old slot first).
  function dropRank() {
    if (root.dropIndex < 0 || !root.dragApp) return 0
    var from = root.favoriteRanks[root.dragApp.id]
    return from !== undefined && from - 1 < root.dropIndex ? root.dropIndex : root.dropIndex + 1
  }

  // Where to draw the insertion marker, in favFlow space.
  function dropMarker(index, _count) {
    if (index < 0) return null
    if (favRepeater.count === 0) return { x: 0, y: 0, h: chipHeight }
    if (index < favRepeater.count) {
      var chip = favRepeater.itemAt(index)
      if (chip) return { x: chip.x - favFlow.spacing / 2, y: chip.y, h: chip.height }
    }
    var last = favRepeater.itemAt(favRepeater.count - 1)
    if (!last) return null
    return { x: last.x + last.width + favFlow.spacing / 2, y: last.y, h: last.height }
  }

  // Hover only moves the selection when the pointer really moved. Tiles are
  // recreated when the list changes, and a new tile under a resting pointer
  // reports a position too; that must not steal the keyboard selection.
  property real hoverX: -1
  property real hoverY: -1
  function pointerMoved(point) {
    var first = root.hoverX < 0
    var moved = Math.abs(point.x - root.hoverX) + Math.abs(point.y - root.hoverY) > 1
    root.hoverX = point.x
    root.hoverY = point.y
    return moved && !first
  }

  // ---- Keyboard -------------------------------------------------------------

  function moveCursor(delta) {
    if (root.apps.length === 0) return
    root.currentIndex = Math.max(0, Math.min(root.apps.length - 1, root.currentIndex + delta))
    grid.positionViewAtIndex(root.currentIndex, GridView.Contain)
  }

  function handleKey(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var app = root.apps[root.currentIndex]
    if (event.key === Qt.Key_Escape) {
      if (root.dragging || root.dragPending) cancelDrag()
      else if (root.filterText) root.filterText = ""
      else root.dismiss()
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      launch(app)
    } else if (event.key === Qt.Key_Left) {
      if (ctrl) moveFavorite(app, -1); else moveCursor(-1)
    } else if (event.key === Qt.Key_Right) {
      if (ctrl) moveFavorite(app, 1); else moveCursor(1)
    } else if (event.key === Qt.Key_Up) {
      moveCursor(-grid.columns)
    } else if (event.key === Qt.Key_Down) {
      moveCursor(grid.columns)
    } else if (event.key === Qt.Key_PageUp) {
      moveCursor(-grid.columns * Math.max(1, grid.visibleRows - 1))
    } else if (event.key === Qt.Key_PageDown) {
      moveCursor(grid.columns * Math.max(1, grid.visibleRows - 1))
    } else if (event.key === Qt.Key_Home && ctrl) {
      moveCursor(-root.apps.length)
    } else if (event.key === Qt.Key_End && ctrl) {
      moveCursor(root.apps.length)
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      setView(root.view === "all" ? "favorites" : "all")
    } else if (ctrl && event.key === Qt.Key_F) {
      toggleFavorite(app)
    } else if (ctrl && event.key === Qt.Key_S) {
      setSort(root.sortOrder === "asc" ? "desc" : "asc")
    } else if (ctrl && event.key === Qt.Key_M) {
      toggleFullscreen()
    } else if (event.key === Qt.Key_Backspace) {
      if (ctrl) root.filterText = ""
      else root.filterText = root.filterText.slice(0, -1)
    } else if (!ctrl && event.text && event.text.length === 1
               && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
      root.filterText += event.text
    } else {
      return
    }
    event.accepted = true
  }

  // ---- Sizes ----------------------------------------------------------------

  readonly property int chipHeight: Math.max(Style.space(34), Style.font.body + Style.space(18))
  readonly property int headerHeight: Math.max(Style.space(40), Style.font.heading + Style.space(20))

  // ---- Small building blocks ----------------------------------------------

  component PickerButton: Rectangle {
    id: btn
    property string label: ""
    property string tip: ""
    property bool selected: false
    signal clicked()

    implicitWidth: btnText.implicitWidth + Style.space(24)
    implicitHeight: Math.max(Style.space(30), btnText.implicitHeight + Style.space(12))
    radius: Math.min(root.cornerRadius, height / 2)
    color: selected ? root.selectedBackground : (btnMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06) : "transparent")
    border.width: 1
    border.color: selected ? root.selectedText : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)

    Text {
      id: btnText
      anchors.centerIn: parent
      text: btn.label
      color: btn.selected ? root.selectedText : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: btnMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.clicked()
    }
  }

  component AppIcon: Item {
    id: iconItem
    property string icon: ""
    readonly property string source: root.appLibrary && icon ? root.appLibrary.iconSource(icon) : ""

    Image {
      id: iconImage
      anchors.fill: parent
      fillMode: Image.PreserveAspectFit
      // Decode at physical pixels so icons stay sharp on HiDPI screens.
      sourceSize.width: width * Screen.devicePixelRatio
      sourceSize.height: height * Screen.devicePixelRatio
      source: iconItem.source
      asynchronous: true
      visible: status === Image.Ready
    }

    Text {
      anchors.centerIn: parent
      visible: iconImage.status !== Image.Ready
      text: "󰀻"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Math.round(iconItem.height * 0.8)
    }
  }

  // ---- Window -----------------------------------------------------------------

  PanelWindow {
    id: panel

    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "mulcahyio-app-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.fullscreen ? root.background : root.scrim
    }

    // Clicking outside the card (windowed mode) closes the picker.
    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Rectangle {
      id: card
      readonly property bool windowed: !root.fullscreen
      width: windowed ? Math.round(Math.max(Math.min(parent.width, Style.space(560)), parent.width * 0.72)) : parent.width
      height: windowed ? Math.round(Math.max(Math.min(parent.height, Style.space(420)), parent.height * 0.78)) : parent.height
      anchors.centerIn: parent
      color: root.background
      radius: windowed ? root.cornerRadius : 0
      border.width: windowed ? 1 : 0
      border.color: root.border

      MouseArea { anchors.fill: parent; onClicked: keyCatcher.forceActiveFocus() }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) { root.handleKey(event) }
      }

      // Header: title, search, view, sort, window mode, close.
      Item {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: root.pad }
        height: root.headerHeight

        Text {
          id: title
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "App Picker"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          font.bold: true
        }

        Rectangle {
          id: searchBox
          anchors.left: title.right
          anchors.leftMargin: Style.space(20)
          anchors.right: controls.left
          anchors.rightMargin: Style.space(20)
          anchors.verticalCenter: parent.verticalCenter
          height: Math.max(Style.space(32), Style.font.body + Style.space(16))
          radius: Math.min(root.cornerRadius, height / 2)
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, root.filterText ? 0.5 : 0.2)

          Text {
            id: searchIcon
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            anchors.left: searchIcon.right
            anchors.leftMargin: Style.space(8)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText ? root.filterText + "▏" : "Type to search apps"
            color: root.foreground
            opacity: root.filterText ? 1 : 0.5
            elide: Text.ElideLeft
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }

        Row {
          id: controls
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)

          PickerButton {
            label: "All apps"
            selected: root.view === "all"
            onClicked: root.setView("all")
          }
          PickerButton {
            label: "★ Favorites" + (root.favoriteApps.length ? " (" + root.favoriteApps.length + ")" : "")
            selected: root.view === "favorites"
            onClicked: root.setView("favorites")
          }
          Item { width: Style.space(8); height: 1 }
          PickerButton {
            label: "A → Z"
            selected: root.sortOrder === "asc"
            opacity: root.view === "favorites" ? 0.45 : 1
            onClicked: root.setSort("asc")
          }
          PickerButton {
            label: "Z → A"
            selected: root.sortOrder === "desc"
            opacity: root.view === "favorites" ? 0.45 : 1
            onClicked: root.setSort("desc")
          }
          Item { width: Style.space(8); height: 1 }
          PickerButton {
            label: root.fullscreen ? "󰊔  Window" : "󰊓  Full screen"
            onClicked: root.toggleFullscreen()
          }
          PickerButton {
            label: "✕"
            onClicked: root.dismiss()
          }
        }
      }

      // Favorites ranking box: drag apps in, drag to reorder, drag out or ✕ to remove.
      Rectangle {
        id: favBox
        anchors { top: header.bottom; left: parent.left; right: parent.right; topMargin: Style.space(12); leftMargin: root.pad; rightMargin: root.pad }
        height: favLabel.height + Style.space(10) + Math.max(root.chipHeight, favFlow.implicitHeight) + Style.space(20)
        radius: root.cornerRadius
        color: root.dropIndex >= 0
          ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.10)
          : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)
        border.width: 1
        border.color: root.dropIndex >= 0 ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

        Text {
          id: favLabel
          anchors { top: parent.top; left: parent.left; topMargin: Style.space(10); leftMargin: Style.space(12) }
          text: "★ Favorites — drag apps here to rank them; drag to reorder; drag out or ✕ to remove"
          color: root.foreground
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          anchors { left: parent.left; leftMargin: Style.space(14); top: favLabel.bottom; topMargin: Style.space(10) }
          height: root.chipHeight
          verticalAlignment: Text.AlignVCenter
          visible: root.favoriteApps.length === 0 && root.dropIndex < 0
          text: "No favorites yet. Drag an app from the grid into this box (or select it and press Ctrl+F)."
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Flow {
          id: favFlow
          anchors { top: favLabel.bottom; left: parent.left; right: parent.right; topMargin: Style.space(10); leftMargin: Style.space(12); rightMargin: Style.space(12) }
          spacing: Style.space(10)

          Repeater {
            id: favRepeater
            model: root.favoriteApps

            delegate: Rectangle {
              id: chip
              required property int index
              required property var modelData
              readonly property bool isDragSource: root.dragging && root.dragApp && root.dragApp.id === modelData.id

              width: chipRow.implicitWidth + Style.space(16)
              height: root.chipHeight
              radius: Math.min(root.cornerRadius, height / 2)
              opacity: isDragSource ? 0.35 : 1
              color: chipMouse.containsMouse ? root.selectedBackground : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
              border.width: 1
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)

              MouseArea {
                id: chipMouse
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                onPressed: function(mouse) {
                  if (mouse.button === Qt.LeftButton) root.pressOn(chip.modelData, true, mapToItem(dragLayer, mouse.x, mouse.y))
                }
                onPositionChanged: function(mouse) {
                  if (pressed) root.moveOn(mapToItem(dragLayer, mouse.x, mouse.y))
                }
                onReleased: function(mouse) {
                  if (mouse.button === Qt.RightButton) { var rid = chip.modelData.id; Qt.callLater(function() { root.removeFavorite(rid) }); return }
                  if (!root.releaseOn()) root.launch(chip.modelData)
                }
                onCanceled: root.cancelDrag()
              }

              Row {
                id: chipRow
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(8)

                Rectangle {
                  width: Math.max(Style.space(20), rankText.implicitWidth + Style.space(8))
                  height: Style.space(20)
                  radius: height / 2
                  anchors.verticalCenter: parent.verticalCenter
                  color: root.accent
                  Text {
                    id: rankText
                    anchors.centerIn: parent
                    text: String(chip.index + 1)
                    color: root.background
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }

                AppIcon {
                  width: Style.space(20)
                  height: Style.space(20)
                  anchors.verticalCenter: parent.verticalCenter
                  icon: chip.modelData.icon
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.min(implicitWidth, Style.space(160))
                  text: chip.modelData.name
                  elide: Text.ElideRight
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Text {
                  id: removeX
                  anchors.verticalCenter: parent.verticalCenter
                  text: "✕"
                  color: removeMouse.containsMouse ? root.selectedText : root.foreground
                  opacity: removeMouse.containsMouse ? 1 : 0.55
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption

                  MouseArea {
                    id: removeMouse
                    anchors.fill: parent
                    anchors.margins: -Style.space(6)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { var rid = chip.modelData.id; Qt.callLater(function() { root.removeFavorite(rid) }) }
                  }
                }
              }
            }
          }
        }

        // Insertion marker while dragging over the box.
        Rectangle {
          readonly property var marker: root.dropMarker(root.dropIndex, root.favoriteApps.length)
          visible: marker !== null
          x: marker ? favFlow.x + marker.x - width / 2 : 0
          y: marker ? favFlow.y + marker.y : 0
          width: Style.space(3)
          height: marker ? marker.h : 0
          radius: width / 2
          color: root.accent
        }
      }

      // App grid. Columns divide the width evenly, so the grid stays
      // symmetrical on any screen size, orientation or scale.
      Item {
        id: gridArea
        anchors { top: favBox.bottom; left: parent.left; right: parent.right; bottom: footer.top; topMargin: Style.space(12); leftMargin: root.pad; rightMargin: root.pad; bottomMargin: Style.space(6) }

        readonly property real targetTile: Math.max(Style.space(110), Math.min(Style.space(180), Math.min(card.width, card.height * 16 / 9) / 11))
        readonly property int columns: Math.max(1, Math.floor(width / targetTile))
        readonly property int cell: Math.floor(width / columns)

        GridView {
          id: grid
          readonly property int columns: gridArea.columns
          readonly property int visibleRows: Math.max(1, Math.floor(height / cellHeight))
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.horizontalCenter: parent.horizontalCenter
          width: gridArea.cell * gridArea.columns
          cellWidth: gridArea.cell
          cellHeight: Math.round(gridArea.cell * 0.92)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: !root.dragging
          model: root.apps
          currentIndex: root.currentIndex

          delegate: Item {
            id: tile
            required property int index
            required property var modelData
            readonly property bool current: index === root.currentIndex
            readonly property int rank: root.favoriteRanks[modelData.id] || 0
            readonly property int iconSize: Math.round(Math.max(Style.space(32), Math.min(Style.space(88), grid.cellWidth * 0.42)))

            width: grid.cellWidth
            height: grid.cellHeight
            opacity: root.dragging && root.dragApp && root.dragApp.id === modelData.id ? 0.35 : 1

            Rectangle {
              anchors.fill: parent
              anchors.margins: Style.space(5)
              radius: root.cornerRadius
              color: tile.current ? root.selectedBackground : "transparent"
              border.width: tile.current ? 1 : 0
              border.color: Qt.rgba(root.selectedText.r, root.selectedText.g, root.selectedText.b, 0.6)
            }

            AppIcon {
              id: tileIcon
              width: tile.iconSize
              height: tile.iconSize
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.verticalCenter
              anchors.bottomMargin: -Math.round(tile.iconSize * 0.15)
              icon: tile.modelData.icon
            }

            Text {
              anchors.top: tileIcon.bottom
              anchors.topMargin: Style.space(8)
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              text: tile.modelData.name
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
              maximumLineCount: 2
              elide: Text.ElideRight
              color: tile.current ? root.selectedText : root.foreground
              font.family: root.fontFamily
              font.pixelSize: grid.cellWidth >= Style.space(150) ? Style.font.subtitle : Style.font.body
            }

            Rectangle {
              visible: tile.rank > 0
              anchors.top: parent.top
              anchors.right: parent.right
              anchors.margins: Style.space(12)
              width: Math.max(Style.space(22), badgeText.implicitWidth + Style.space(10))
              height: Style.space(22)
              radius: height / 2
              color: root.accent
              Text {
                id: badgeText
                anchors.centerIn: parent
                text: "★" + tile.rank
                color: root.background
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              preventStealing: true
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
              onPositionChanged: function(mouse) {
                var point = mapToItem(dragLayer, mouse.x, mouse.y)
                if (pressed) root.moveOn(point)
                else if (!root.dragging && root.pointerMoved(point)) root.currentIndex = tile.index
              }
              onPressed: function(mouse) {
                if (mouse.button === Qt.LeftButton) root.pressOn(tile.modelData, false, mapToItem(dragLayer, mouse.x, mouse.y))
              }
              onReleased: function(mouse) {
                if (mouse.button === Qt.RightButton) { var tapp = tile.modelData; Qt.callLater(function() { root.toggleFavorite(tapp) }); return }
                if (!root.releaseOn()) root.launch(tile.modelData)
              }
              onCanceled: root.cancelDrag()
            }
          }
        }

        Text {
          anchors.centerIn: parent
          visible: root.apps.length === 0
          text: root.view === "favorites" && root.favoriteApps.length === 0
            ? "No favorites yet. Switch to All apps and drag apps into the Favorites box."
            : "No apps match \"" + root.filterText + "\""
          color: root.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
        }
      }

      Text {
        id: footer
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; bottomMargin: Style.space(10); leftMargin: root.pad; rightMargin: root.pad }
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        text: root.apps.length + (root.apps.length === 1 ? " app" : " apps")
          + "   ·   Enter launch   ·   Arrows move   ·   Tab All/Favorites   ·   Ctrl+F favorite   ·   Ctrl+←/→ change rank   ·   Ctrl+S sort   ·   Ctrl+M window/full screen   ·   Right-click toggle favorite   ·   Esc close"
        color: root.foreground
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      // Floating copy of the app being dragged.
      Item {
        id: dragLayer
        anchors.fill: parent
        z: 1000

        Rectangle {
          visible: root.dragging && root.dragApp !== null
          x: root.dragX - width / 2
          y: root.dragY - height / 2
          width: ghostRow.implicitWidth + Style.space(20)
          height: root.chipHeight + Style.space(4)
          radius: Math.min(root.cornerRadius, height / 2)
          color: root.background
          border.width: 2
          border.color: root.accent
          opacity: 0.95

          Row {
            id: ghostRow
            anchors.centerIn: parent
            spacing: Style.space(8)
            AppIcon {
              width: Style.space(22)
              height: Style.space(22)
              anchors.verticalCenter: parent.verticalCenter
              icon: root.dragApp ? root.dragApp.icon : ""
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: (root.dragApp ? root.dragApp.name : "")
                + (root.dropIndex >= 0 ? "   → ★" + root.dropRank() : (root.dragFromFavorites ? "   (release to remove)" : ""))
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }
        }
      }
    }
  }
}
