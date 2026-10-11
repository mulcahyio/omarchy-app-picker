import QtQuick
import qs.Ui

// Bar icon for the App Picker. Left click toggles the full-screen picker,
// the same way the Omarchy icon toggles the Omarchy menu.
BarWidget {
  id: root
  moduleName: "mulcahyio.app-picker"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰀻"
    tooltipText: "App Picker"
    horizontalMargin: 7.5
    onPressed: function(button) {
      if (!root.bar) return
      if (button === Qt.LeftButton) root.bar.run("omarchy-shell shell toggle mulcahyio.app-picker")
    }
  }
}
