import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Transparent card host for SuperNotch.
//
// A drop-in replacement for Omarchy's KeyboardPanel that does NOT paint an
// opaque popup background (KeyboardPanel's internal BorderSurface uses
// Color.popups.background, which made real transparency impossible). This
// window is fully transparent; the plugin's own cardSurface (which respects
// bgOpacity) is the only thing drawn, so the desktop shows through.
//
// Replicates the bar-anchoring math from Ui/KeyboardPanel.qml (cardOrigin) and
// a simple outside-click dismiss + focus hand-off.

PanelWindow {
  id: root

  required property Item anchorItem
  required property var bar
  property var owner: null
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property bool open: false
  property bool centerOnBar: true
  property int gap: Style.gapsOut
  property int margin: Style.gapsOut
  property Item focusTarget: null

  // REAL transparency: the window itself is transparent.
  color: "transparent"
  screen: anchorWindow ? anchorWindow.screen : null
  visible: root.open
  // Full-screen layer-shell (like KeyboardPanel) so cardOrigin maps to screen
  // coordinates; only the cardSurface child is painted (translucent).
  anchors.top: true; anchors.left: true; anchors.right: true; anchors.bottom: true
  mask: Region { width: root.screenW; height: root.screenH }

  // Keyboard focus: without this the layer-shell never receives key events
  // from the compositor, so PanelKeyCatcher's Keys.onPressed never fires.
  // OnDemand routes keys here while open (the forceActiveFocus in the existing
  // onOpenChanged below gives Qt the in-surface focus target).
  WlrLayershell.namespace: "omarchy-supernotch"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
  readonly property string barPos: bar ? bar.position : "top"
  readonly property real barW: anchorWindow ? anchorWindow.width : (screen ? screen.width : 0)
  readonly property real barH: anchorWindow ? anchorWindow.height : 0
  readonly property real screenW: screen ? screen.width : 0
  readonly property real screenH: screen ? screen.height : 0

  readonly property point anchorScreenPos: {
    if (!anchorItem || !anchorWindow) return Qt.point(0, 0)
    return anchorItem.mapToItem(anchorWindow.contentItem, 0, 0)
  }
  readonly property real anchorW: anchorItem ? anchorItem.width : 0
  readonly property real anchorH: anchorItem ? anchorItem.height : 0

  // Desired top-left of the card in screen coordinates (copied from KeyboardPanel).
  readonly property point cardOrigin: {
    if (!anchorItem || !bar) return Qt.point(margin, margin)
    var x = 0, y = 0
    if (centerOnBar && (barPos === "top" || barPos === "bottom")) {
      x = screenW / 2 - contentWidth / 2
      y = barPos === "bottom" ? screenH - barH - contentHeight - gap : barH + gap
    } else if (centerOnBar) {
      x = barPos === "left" ? barW + gap : screenW - barW - contentWidth - gap
      y = screenH / 2 - contentHeight / 2
    } else if (barPos === "bottom") {
      x = anchorScreenPos.x + anchorW / 2 - contentWidth / 2
      y = screenH - barH - contentHeight - gap
    } else if (barPos === "left") {
      x = barW + gap
      y = anchorScreenPos.y + anchorH / 2 - contentHeight / 2
    } else if (barPos === "right") {
      x = screenW - barW - contentWidth - gap
      y = anchorScreenPos.y + anchorH / 2 - contentHeight / 2
    } else { // "top" (default)
      x = anchorScreenPos.x + anchorW / 2 - contentWidth / 2
      y = barH + gap
    }
    x = Math.max(margin, Math.min(x, screenW - contentWidth - margin))
    y = Math.max(margin, Math.min(y, screenH - contentHeight - margin))
    return Qt.point(Math.round(x), Math.round(y))
  }

  function close() {
    if (owner && "close" in owner) owner.close()
    else root.open = false
  }

  onOpenChanged: {
    if (root.open && root.focusTarget) Qt.callLater(function () {
      if (root.open && root.focusTarget) root.focusTarget.forceActiveFocus()
    })
  }

  // Outside-click dismissal.
  MouseArea {
    anchors.fill: parent
    onClicked: root.close()
  }

  // The card content (plugin's cardSurface) is placed at cardOrigin.
  default property alias contentItem: cardHolder.children
  Item {
    id: cardHolder
    x: root.cardOrigin.x
    y: root.cardOrigin.y
    width: root.contentWidth
    height: root.contentHeight
    // Swallow clicks so they don't reach the dismissal layer behind.
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
  }
}
