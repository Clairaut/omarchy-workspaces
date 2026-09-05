import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Environment- and monitor-aware fork of omarchy.workspaces (see workspaces.lua for the pinning scheme).
BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function currentScreen() {
    return root.QsWindow && root.QsWindow.window ? root.QsWindow.window.screen : null
  }

  function monitorIndex() {
    var screen = root.currentScreen()
    if (!screen) return 0

    var screens = Quickshell.screens.slice().sort(function(a, b) { return a.x - b.x })
    for (var i = 0; i < screens.length; i++) {
      if (screens[i].name === screen.name) return i
    }
    return 0
  }

  // Derived from this monitor's own active workspace, not the global focus.
  function environmentBase() {
    var screen = root.currentScreen()
    var monitor = screen ? Hyprland.monitorFor(screen) : null
    if (!monitor || !monitor.activeWorkspace) return 0
    return Math.floor((monitor.activeWorkspace.id - 1) / 20) * 20
  }

  function blockOffset() {
    return root.environmentBase() + root.monitorIndex() * 10
  }

  function workspaceIds() {
    var offset = root.blockOffset()
    var values = Hyprland.workspaces.values
    var ids = []

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > offset && id <= offset + 10 && values[i].toplevels.values.length > 0 && ids.indexOf(id) === -1) {
        ids.push(id)
      }
    }

    var focusedId = Hyprland.focusedWorkspace !== null ? Hyprland.focusedWorkspace.id : -1
    if (focusedId > offset && focusedId <= offset + 10 && ids.indexOf(focusedId) === -1) {
      ids.push(focusedId)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : Math.max(1, root.workspaceIds().length)
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
        readonly property int labelNumber: ((modelData - 1) % 10) + 1

        bar: root.bar
        text: focused ? "󱓻" : (labelNumber === 10 ? "0" : String(labelNumber))
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }
      }
    }
  }
}
