import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Ui

// SuperNotch — the living center "notch" pill. Shows an animated icon + status,
// blooms on hover, and opens the command-center card (a KeyboardPanel) on click.
// The card is a plugin framework: each tab is plugins/<key>/<key>.qml loaded
// dynamically. This BarWidget only draws the pill and reports live state that
// the Panel pushes down via hostWidget.* properties.
BarWidget {
  id: root
  moduleName: "omarchy-supernotch"

  property bool hovering: false

  // Pill width: an explicit user bar width (barW, from notchBarWidth pref)
  // WINS over the hardware notch so the user can shrink it smaller than the
  // physical notch span. Fallback: hardware notch ×3, then a 240px floor.
  property real realNotchW: 0
  property real barW: 0
  property real pillBase: root.barW > 0
    ? Math.max(240, root.barW)
    : Math.max(240, (root.realNotchW > 0 ? root.realNotchW * 3.0 : 0))

  // Live content pushed from Panel.qml:
  property string barIcon: "♪"
  property string barInfo: ""
  property bool barActive: false
  property real barPulse: 1
  // Plugins marked "show in notch" (pushed by Panel.pushBar).
  property var barPlugins: []
  property bool notchInsetEditing: false
  // Width/inset of the notch, pushed from the Panel via pushBar() (root.notchWidth
  // is not directly readable here, so the Panel writes them onto this widget).
  property int notchWidth: 0
  property int notchInset: 0
  property bool darkCenter: false
  onBarIconChanged: { barPulse = 0; Qt.callLater(function () { barPulse = 1 }) }
  onBarInfoChanged: { barPulse = 0; Qt.callLater(function () { barPulse = 1 }) }
  Behavior on barPulse { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

  // Mirrored opened state (required by the bar host's findPanelWidget).
  property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  onOpenedChanged: { if (panelLoader.item) panelLoader.item.opened = root.opened }

  function open(p)  { root.opened = true }
  function close()  { root.opened = false }
  function toggle() { root.opened = !root.opened }

  // Run the helper (same path as SUPER+SHIFT+N) so a click toggles the panel
  // through the verified IPC route.
  readonly property string helper: {
    var d = (typeof manifest !== "undefined" && manifest.__sourceDir) ? manifest.__sourceDir : ""
    if (d) return d.replace(/\/$/, "") + "/bin/omarchy-supernotch"
    return Qt.resolvedUrl(".").toString().replace("file://", "") + "/bin/omarchy-supernotch"
  }
  function run(args, onText) {
    var proc = Qt.createQmlObject(
      "import Quickshell.Io; import QtQuick; Process { " +
      "property string collected: \"\"; property var cb: null; " +
      "stdout: SplitParser { onRead: function(d){ collected += d } } " +
      "onExited: function(){ if (this.cb) this.cb(collected) } }",
      root, "snBarProc")
    if (!proc) return null
    proc.collected = ""; proc.cb = onText
    proc.command = [root.helper].concat(args); proc.running = true
    return proc
  }
  function clickToggle() { run(["toggle"], function () {}) }

  implicitWidth: Math.max(240, pill.width)
  implicitHeight: pill.height
  visible: true
  opacity: 1
  // The bar host hides inactive center widgets by setting opacity:0 when the
  // pointer leaves. The notch must ALWAYS be visible, so force opacity back to
  // 1 whenever the host tries to dim it.
  onOpacityChanged: if (root.opacity !== 1) root.opacity = 1

  // ── ambient accent halo behind the pill (pulses when the notch is live) ──
  Rectangle {
    anchors.centerIn: pill
    width: pill.width * 0.8; height: pill.height * 2.4
    radius: height / 2
    color: Color.accent
    opacity: 0
    z: -1
    layer.enabled: true
    layer.effect: MultiEffect { blurEnabled: true; blurMax: 40; blur: 1.0 }
    SequentialAnimation on opacity {
      loops: Animation.Infinite
      running: root.barActive || root.hovering
      NumberAnimation { to: 0.22; duration: 1300; easing.type: Easing.InOutSine }
      NumberAnimation { to: 0.07; duration: 1500; easing.type: Easing.InOutSine }
      onStopped: opacity = 0
    }
  }

  // ---- the pill ----------------------------------------------------------
  Rectangle {
    id: pill
    property real b: (root.hovering ? 1 : 0) + (root.barActive ? 1 : 0)
    Behavior on b { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

    // The bar pill IS the notch: its width = "Ancho del notch" (slider % → px of
    // monitor), so the FOND + BORDER + ITEMS all scale together across the FULL
    // slider range (notchWidth is itself capped at 90% of the monitor in Panel.qml,
    // so no hard cap is needed here). The content is laid out INSIDE this width
    // (split around the center gap, or one item at a time when it doesn't fit).
    width: root.bar && root.bar.vertical ? 34 : Math.max(160, notchWidth)
    height: root.bar && root.bar.vertical ? Math.max(240, root.pillBase) : 34
    anchors.centerIn: parent
    radius: height / 2
    opacity: 1.0
    border.color: Color.accent
    border.width: 2
    // subtle scale on press (driven by inner clicker)
    scale: bgClicker.pressed ? 0.94 : (1.0 + 0.04 * Math.min(1, b))
    Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }
    Behavior on border.width { NumberAnimation { duration: 200 } }

    // background clicker — behind the rows so mini-widget clicks win
    MouseArea {
      id: bgClicker
      anchors.fill: parent; z: 1
      hoverEnabled: true; acceptedButtons: Qt.LeftButton
      onEntered: root.hovering = true
      onExited: root.hovering = false
      onClicked: root.clickToggle()
    }

    // Plugins marked "show in notch" (pushed by Panel.pushBar).
    readonly property var enabledList: root.barPlugins
    property int tickIdx: 0
    property bool editing: root.notchInsetEditing
    color: editing
      ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.42)
      : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.16)
    Behavior on color { ColorAnimation { duration: 160 } }
    readonly property real usableW: Math.max(0, pill.width - notchInset)
    readonly property bool showAll: pill.enabledList.length > 0 && pill.usableW >= Math.max(1, pill.enabledList.length) * 90
    // Split by user-chosen side (default right); left-aligned vs right-aligned.
    readonly property var leftList: { var l = pill.enabledList; return l.filter(function (x){ return (x.side || "right") === "left" }) }
    readonly property var rightList: { var l = pill.enabledList; return l.filter(function (x){ return (x.side || "right") !== "left" }) }
    Timer {
      interval: 3000; repeat: true
      running: pill.enabledList.length > 1 && !pill.showAll
      onTriggered: { pill.tickIdx = (pill.tickIdx + 1) % pill.enabledList.length; }
    }

    // ── CENTER GAP (the physical notch): content splits to LEFT | RIGHT of
    //    the middle, leaving a hollow `notchInset` px wide in the center ──
    readonly property real gapHalf: notchInset / 2
    Component.onCompleted: { if (root && root.pushBar) root.pushBar() }

    // Optional dark center so the notch hollow is graphically visible.
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      width: root.notchInset
      height: parent.height
      color: Color.background
      visible: root.darkCenter
      z: 0
    }

    // left side: pinned to LEFT edge of pill | gap | right side pinned to RIGHT edge
    // Per-item text budget: the half-width split evenly among items (minus icon+gap).
    readonly property real halfW: Math.max(40, (pill.width - notchInset) / 2 - Style.space(12))
    readonly property real leftItemW: Math.max(60, pill.halfW / Math.max(1, pill.leftList.length) - Style.space(30))
    readonly property real rightItemW: Math.max(60, pill.halfW / Math.max(1, pill.rightList.length) - Style.space(30))
    Item {
      id: leftContainer
      z: 2
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.right: parent.horizontalCenter
      anchors.rightMargin: pill.gapHalf + Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      height: parent.height
      clip: true
      visible: !root.bar.vertical && pill.showAll
      opacity: visible ? 1 : 0
      Row {
        id: leftRow
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(14)
        Repeater {
          model: pill.leftList
          delegate: Item {
            height: childrenRect.height; width: childrenRect.width
            Row {
              spacing: Style.space(6)
              Text { text: (modelData.icon || "◇"); color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.body; anchors.verticalCenter: parent.verticalCenter }
              MarqueeText { text: (modelData.text || modelData.key); color: Color.foreground; fontFamily: Style.fontFamily; fontSize: Style.font.bodySmall; maxW: pill.leftItemW }
            }
            MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (panelLoader.item && panelLoader.item.openPlugin) panelLoader.item.openPlugin(modelData.key); else root.clickToggle() } }
          }
        }
      }
    }
    // right side: pinned to RIGHT edge of pill
    Item {
      id: rightContainer
      z: 2
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.left: parent.horizontalCenter
      anchors.leftMargin: pill.gapHalf + Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      height: parent.height
      clip: true
      visible: !root.bar.vertical && pill.showAll
      opacity: visible ? 1 : 0
      Row {
        id: rightRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(14)
        Repeater {
          model: pill.rightList
          delegate: Item {
            height: childrenRect.height; width: childrenRect.width
            Row {
              spacing: Style.space(6)
              Text { text: (modelData.icon || "◇"); color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.body; anchors.verticalCenter: parent.verticalCenter }
              MarqueeText { text: (modelData.text || modelData.key); color: Color.foreground; fontFamily: Style.fontFamily; fontSize: Style.font.bodySmall; maxW: pill.rightItemW }
            }
            MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (panelLoader.item && panelLoader.item.openPlugin) panelLoader.item.openPlugin(modelData.key); else root.clickToggle() } }
          }
        }
      }
    }
    // ── narrow / ticker: one plugin at a time, parked to ONE side of the gap ──
    Row {
      id: tickRow
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)
      property bool leftSide: (pill.tickIdx % 2) === 0
      anchors.right: leftSide ? parent.horizontalCenter : undefined
      anchors.rightMargin: leftSide ? pill.gapHalf : 0
      anchors.left: leftSide ? undefined : parent.horizontalCenter
      anchors.leftMargin: leftSide ? 0 : pill.gapHalf
      visible: !root.bar.vertical && !pill.showAll
      opacity: (!root.bar.vertical && !pill.showAll) ? 1 : 0
      Repeater {
        model: pill.enabledList.length ? [pill.enabledList[pill.tickIdx]] : []
        Item {
          height: childrenRect.height
          Row {
            spacing: Style.space(6)
            Text { text: (modelData.icon || "◇"); color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.body; anchors.verticalCenter: parent.verticalCenter }
            MarqueeText { text: (modelData.text || modelData.key); color: Color.foreground; fontFamily: Style.fontFamily; fontSize: Style.font.bodySmall; maxW: pill.halfW - Style.space(30) }
          }
          MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (panelLoader.item && panelLoader.item.openPlugin) panelLoader.item.openPlugin(modelData.key); else root.clickToggle() } }
        }
      }
    }

    // ── vertical (notch) mode: icons only, stacked top→bottom ──
    Column {
      anchors.centerIn: parent
      spacing: Style.space(14)
      topPadding: notchInset
      bottomPadding: notchInset
      visible: root.bar.vertical
      opacity: root.bar.vertical ? 1 : 0
      Repeater {
        model: root.bar.vertical
          ? (pill.showAll ? pill.enabledList : (pill.enabledList.length ? [pill.enabledList[pill.tickIdx]] : []))
          : []
        Item {
          Text {
            text: (modelData.icon || "◇")
            color: Color.foreground
            font.family: Style.fontFamily
            font.pixelSize: Style.font.body
            anchors.horizontalCenter: parent.horizontalCenter
          }
          MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openPlugin(modelData.key) }
        }
      }
    }
  }

  // (removed: outer clicker now lives inside pill as bgClicker so mini-widgets receive clicks)

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      var t = panelLoader.item
      if (t && "bar" in t) t.bar = root.bar
      if (t && "anchorItem" in t) t.anchorItem = root
      if (t && "hostWidget" in t) t.hostWidget = root
      Qt.callLater(function () {
        if (panelLoader.item) {
          if ("hostWidget" in panelLoader.item) panelLoader.item.hostWidget = root
          if ("hostWidget" in panelLoader.item) panelLoader.item.pushBar()
        }
      })
    }
  }
}
