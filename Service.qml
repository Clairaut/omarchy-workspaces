import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Custom picker for workspace zones, replacing the dmenu-style
// omarchy-menu-select flow. Self-contained PanelWindow (not the bar-anchored
// KeyboardPanel) since this always opens via hotkey/IPC, never a bar click --
// same shape as omarchy.menu's own popup.
Panel {
  id: root
  moduleName: "clairaut.workspaces"
  ipcTarget: "clairaut.workspaces"
  manageIpc: false

  property bool moveMode: false
  property string screenState: "main"   // main | pickTarget | name | icon | customGlyph
  property string pendingAction: ""     // create | edit | delete
  property int targetSlot: -1
  property string pendingName: ""
  property var rawData: ({ zones: [], lastWorkspace: {} })
  property var zones: []
  property var currentRows: []
  property int selectedIndex: -1

  readonly property string stateFile: Quickshell.env("HOME") + "/.local/state/omarchy/workspaces/zones.json"
  readonly property string switchBin: Quickshell.env("HOME") + "/.config/omarchy/plugins/clairaut.workspaces/bin/omarchy-workspaces-switch"

  // nameField/glyphField grab activeFocus on click and never give it back on
  // their own -- leaving keyCatcher.blocked stuck true (arrow keys dead) on
  // every later open once either field has ever been focused. Reclaim focus
  // whenever we land back on a list screen.
  onScreenStateChanged: {
    if (root.screenState !== "name" && root.screenState !== "customGlyph")
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function openFromHotkey(move) {
    root.moveMode = !!move
    root.pendingAction = ""
    root.targetSlot = -1
    root.pendingName = ""
    root.screenState = "main"
    zoneFile.reload()
    root.controller.show()
    // Declaring `focus: true` isn't enough once the PanelWindow has already
    // toggled visible once -- force it explicitly, same as omarchy.menu.
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() { root.controller.hide() }

  function parseMove(payload) {
    if (!payload) return false
    try { return !!JSON.parse(payload).move } catch (e) { return false }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(payload: string): void { root.openFromHotkey(root.parseMove(payload)) }
    function show(payload: string): void { root.openFromHotkey(root.parseMove(payload)) }
    function toggle(payload: string): void { root.opened ? root.close() : root.openFromHotkey(root.parseMove(payload)) }
    function close(): void { root.close() }
  }

  FileView {
    id: zoneFile
    path: root.stateFile
    printErrors: false
    atomicWrites: true
    onLoaded: {
      try {
        root.rawData = JSON.parse(text())
      } catch (e) {
        root.rawData = { zones: [], lastWorkspace: {} }
      }
      if (!root.rawData.zones) root.rawData.zones = []
      if (!root.rawData.lastWorkspace) root.rawData.lastWorkspace = {}
      root.zones = root.rawData.zones
      root.rebuildRows()
    }
    // First run: no state file yet. Fall back to empty state instead of
    // leaving currentRows at its initial [] forever (no onLoaded ever fires).
    onLoadFailed: {
      root.rawData = { zones: [], lastWorkspace: {} }
      root.zones = []
      root.rebuildRows()
    }
  }

  function persist() {
    zoneFile.setText(JSON.stringify(root.rawData, null, 2))
  }

  Process {
    id: switchProc
    onExited: root.close()
  }

  function runSwitch(slot) {
    switchProc.command = [root.switchBin, root.moveMode ? "--move-slot" : "--switch-slot", String(slot)]
    switchProc.running = true
  }

  function findZoneBySlot(slot) {
    for (var i = 0; i < root.zones.length; i++) {
      if (root.zones[i].slot === slot) return root.zones[i]
    }
    return null
  }

  function nextFreeSlot() {
    var used = {}
    for (var i = 0; i < root.zones.length; i++) used[root.zones[i].slot] = true
    for (var s = 1; s <= 10; s++) if (!used[s]) return s
    return -1
  }

  function createZone(name, icon) {
    if (name.length === 0) return
    for (var i = 0; i < root.zones.length; i++) {
      if (root.zones[i].name === name) return
    }
    var slot = root.nextFreeSlot()
    if (slot === -1) return
    root.rawData.zones.push({ slot: slot, name: name, icon: icon })
    root.zones = root.rawData.zones
    root.persist()
    root.runSwitch(slot)
  }

  function updateZone(slot, name, icon) {
    for (var i = 0; i < root.rawData.zones.length; i++) {
      if (root.rawData.zones[i].slot === slot) {
        root.rawData.zones[i].name = name
        root.rawData.zones[i].icon = icon
      }
    }
    root.zones = root.rawData.zones
    root.persist()
    root.close()
  }

  function deleteZone(slot) {
    var filtered = []
    for (var i = 0; i < root.rawData.zones.length; i++) {
      if (root.rawData.zones[i].slot !== slot) filtered.push(root.rawData.zones[i])
    }
    root.rawData.zones = filtered
    if (root.rawData.lastWorkspace) delete root.rawData.lastWorkspace[String(slot)]
    root.zones = root.rawData.zones
    root.persist()
    root.close()
  }

  // Row model: {type:"row", icon, label, action, slot?, value?} | {type:"divider"}
  function mainRows() {
    var rows = []
    for (var i = 0; i < root.zones.length; i++) {
      var e = root.zones[i]
      rows.push({ type: "row", icon: e.icon, label: e.name, action: "switch", slot: e.slot })
    }
    if (root.zones.length > 0) rows.push({ type: "divider" })
    rows.push({ type: "row", icon: "", label: "Create zone", action: "create" })
    rows.push({ type: "row", icon: "", label: "Edit zone", action: "edit" })
    rows.push({ type: "row", icon: "", label: "Delete zone", action: "delete" })
    return rows
  }

  function targetRows() {
    var rows = []
    for (var i = 0; i < root.zones.length; i++) {
      var e = root.zones[i]
      rows.push({ type: "row", icon: e.icon, label: e.name, action: "target", slot: e.slot })
    }
    return rows
  }

  function iconRows() {
    return [
      { type: "row", icon: "", label: "Person", action: "icon", value: "" },
      { type: "row", icon: "", label: "Briefcase", action: "icon", value: "" },
      { type: "row", icon: "", label: "House", action: "icon", value: "" },
      { type: "row", icon: "", label: "Game controller", action: "icon", value: "" },
      { type: "row", icon: "", label: "Code", action: "icon", value: "" },
      { type: "row", icon: "", label: "Globe", action: "icon", value: "" },
      { type: "row", icon: "", label: "Custom glyph...", action: "customIcon" }
    ]
  }

  function firstSelectableIndex() {
    for (var i = 0; i < root.currentRows.length; i++) if (root.currentRows[i].type === "row") return i
    return -1
  }

  // The zone the currently-focused workspace belongs to, so the picker can default to it.
  readonly property int currentSlot: Hyprland.focusedWorkspace ? Math.floor((Hyprland.focusedWorkspace.id - 1) / 20) + 1 : -1

  function indexForSlot(slot) {
    for (var i = 0; i < root.currentRows.length; i++) {
      if (root.currentRows[i].type === "row" && root.currentRows[i].slot === slot) return i
    }
    return -1
  }

  function rebuildRows() {
    if (root.screenState === "main") root.currentRows = root.mainRows()
    else if (root.screenState === "pickTarget") root.currentRows = root.targetRows()
    else if (root.screenState === "icon") root.currentRows = root.iconRows()
    else root.currentRows = []

    var currentIdx = root.screenState === "main" ? root.indexForSlot(root.currentSlot) : -1
    root.selectedIndex = currentIdx >= 0 ? currentIdx : root.firstSelectableIndex()
  }

  function moveSelection(dy) {
    if (root.currentRows.length === 0) return
    var idx = root.selectedIndex < 0 ? 0 : root.selectedIndex
    for (var step = 0; step < root.currentRows.length; step++) {
      idx = (idx + dy + root.currentRows.length) % root.currentRows.length
      if (root.currentRows[idx].type === "row") { root.selectedIndex = idx; return }
    }
  }

  function activateSelected() {
    if (root.selectedIndex < 0 || root.selectedIndex >= root.currentRows.length) return
    root.handleAction(root.currentRows[root.selectedIndex])
  }

  function goBackToMain() {
    root.screenState = "main"
    root.rebuildRows()
  }

  function handleAction(row) {
    switch (row.action) {
      case "switch":
        root.runSwitch(row.slot)
        break
      case "create":
        root.pendingAction = "create"
        root.pendingName = ""
        root.screenState = "name"
        break
      case "edit":
        root.pendingAction = "edit"
        root.screenState = "pickTarget"
        root.rebuildRows()
        break
      case "delete":
        root.pendingAction = "delete"
        root.screenState = "pickTarget"
        root.rebuildRows()
        break
      case "target":
        root.targetSlot = row.slot
        if (root.pendingAction === "delete") {
          root.deleteZone(root.targetSlot)
        } else {
          var env = root.findZoneBySlot(root.targetSlot)
          root.pendingName = env ? env.name : ""
          root.screenState = "name"
        }
        break
      case "icon":
        root.finishCreateOrEdit(row.value)
        break
      case "customIcon":
        root.screenState = "customGlyph"
        break
    }
  }

  function finishCreateOrEdit(icon) {
    if (root.pendingAction === "create") root.createZone(root.pendingName, icon)
    else if (root.pendingAction === "edit") root.updateZone(root.targetSlot, root.pendingName, icon)
  }

  function titleFor() {
    if (root.screenState === "main") return root.moveMode ? "Move window to zone" : "Switch zone"
    if (root.screenState === "pickTarget") return root.pendingAction === "delete" ? "Delete which zone?" : "Edit which zone?"
    if (root.screenState === "name") return root.pendingAction === "edit" ? "Rename zone" : "New zone"
    if (root.screenState === "icon") return "Choose an icon"
    if (root.screenState === "customGlyph") return "Custom icon glyph"
    return ""
  }

  PanelWindow {
    id: win
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "clairaut-workspaces-panel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.35)
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: Style.space(420)
      height: Math.min(contentColumn.implicitHeight, win.height - Style.space(80))
      anchors.horizontalCenter: parent.horizontalCenter
      y: Math.round((win.height - height) / 2)
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius

      MouseArea { anchors.fill: parent; onClicked: {} }

      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        blocked: nameField.activeFocus || glyphField.activeFocus
        onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveSelection(dy) }
        onActivateRequested: root.activateSelected()
        onCloseRequested: root.screenState === "main" ? root.close() : root.goBackToMain()

        Column {
          id: contentColumn
          width: parent.width
          spacing: 0

          Item {
            width: parent.width
            height: titleText.implicitHeight + Style.space(24)

            Text {
              id: titleText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Style.space(16)
              anchors.rightMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              text: root.titleFor()
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
              font.bold: true
              color: Color.popups.text
            }
          }

          PanelSeparator { foreground: Color.popups.text }

          Column {
            id: rowsColumn
            width: parent.width
            spacing: Style.space(2)
            topPadding: Style.space(6)
            bottomPadding: Style.space(6)
            visible: root.screenState !== "name" && root.screenState !== "customGlyph"

            Repeater {
              model: root.currentRows

              Item {
                required property var modelData
                required property int index
                width: rowsColumn.width - Style.space(12)
                anchors.horizontalCenter: parent.horizontalCenter
                height: modelData.type === "divider" ? Style.space(13) : Style.space(38)

                PanelSeparator {
                  visible: modelData.type === "divider"
                  anchors.verticalCenter: parent.verticalCenter
                  foreground: Color.popups.text
                }

                CursorSurface {
                  visible: modelData.type === "row"
                  anchors.fill: parent
                  hasCursor: index === root.selectedIndex
                  radius: Style.cornerRadius

                  readonly property bool isCurrentZone: root.screenState === "main" && modelData.type === "row" && modelData.slot === root.currentSlot

                  Rectangle {
                    visible: parent.isCurrentZone
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(3)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(3)
                    height: parent.height - Style.space(14)
                    radius: width / 2
                    color: Color.accent
                  }

                  Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(12)

                    Text {
                      width: Style.space(20)
                      horizontalAlignment: Text.AlignHCenter
                      text: modelData.type === "row" ? modelData.icon : ""
                      font.family: Style.font.family
                      font.pixelSize: Style.font.iconLarge
                      color: index === root.selectedIndex ? Color.accent : Color.popups.text
                    }

                    Text {
                      text: modelData.type === "row" ? modelData.label : ""
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      font.bold: true
                      color: Color.popups.text
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    onClicked: { root.selectedIndex = index; root.activateSelected() }
                  }
                }
              }
            }
          }

          Item {
            width: parent.width
            height: nameField.implicitHeight + Style.space(24)
            visible: root.screenState === "name"

            TextField {
              id: nameField
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(14)
              anchors.rightMargin: Style.space(14)
              placeholderText: "Zone name"
              text: root.screenState === "name" ? root.pendingName : ""
              onVisibleChanged: if (visible) { forceActiveFocus(); selectAll() }
              Keys.onEscapePressed: root.goBackToMain()
              onAccepted: {
                if (text.length === 0) return
                root.pendingName = text
                root.screenState = "icon"
                root.rebuildRows()
              }
            }
          }

          Item {
            width: parent.width
            height: glyphField.implicitHeight + Style.space(24)
            visible: root.screenState === "customGlyph"

            TextField {
              id: glyphField
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(14)
              anchors.rightMargin: Style.space(14)
              placeholderText: "Paste a glyph"
              onVisibleChanged: if (visible) { text = ""; forceActiveFocus() }
              Keys.onEscapePressed: root.goBackToMain()
              onAccepted: root.finishCreateOrEdit(text.length > 0 ? text : "")
            }
          }

          PanelSeparator { foreground: Color.popups.text }

          Item {
            width: parent.width
            height: Style.space(34)

            Row {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(16)

              Text { text: "↑↓ navigate"; font.family: Style.font.family; font.pixelSize: Style.font.caption; color: Color.muted }
              Text { text: "↵ select"; font.family: Style.font.family; font.pixelSize: Style.font.caption; color: Color.muted }
              Text { text: "esc back"; font.family: Style.font.family; font.pixelSize: Style.font.caption; color: Color.muted }
            }
          }
        }
      }
    }
  }
}
