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
    scale: clicker.pressed ? 0.94 : (1.0 + 0.04 * Math.min(1, b))
    Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }
    Behavior on border.width { NumberAnimation { duration: 200 } }

    // Plugins marked "show in notch" (pushed by Panel.pushBar).
    readonly property var enabledList: root.barPlugins
    property int tickIdx: 0
    property bool editing: root.notchInsetEditing
    // Pill fill brightens while the user drags "Notch interior" (editing feedback).
    color: editing
      ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.42)
      : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.16)
    Behavior on color { ColorAnimation { duration: 160 } }
    // Show side-by-side (split around the center gap) when the AVAILABLE space
    // fits all plugins: available = pill width − notchInset (the hollow center).
    // Otherwise tick one at a time. Use a compact per-item budget so the default
    // 20% width on a 3456px monitor shows all 4 plugins side-by-side.
    readonly property real usableW: Math.max(0, pill.width - notchInset)
    readonly property bool showAll: pill.enabledList.length > 0 && pill.usableW >= Math.max(1, pill.enabledList.length) * 90
    function leftHalf()  { var l = pill.enabledList, n = l.length, cut = Math.ceil(n / 2); return l.slice(0, cut) }
    function rightHalf() { var l = pill.enabledList, n = l.length, cut = Math.ceil(n / 2); return l.slice(cut) }
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

    // left side: hugs the center gap from the left ([0][1] reading left→right)
    Row {
      id: leftRow
      z: 2
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: parent.horizontalCenter
      anchors.rightMargin: pill.gapHalf
      spacing: Style.space(14)
      visible: !root.bar.vertical && pill.showAll
      opacity: (!root.bar.vertical && pill.showAll) ? 1 : 0
      Repeater {
        model: pill.leftHalf()
        Item {
          height: childrenRect.height
          Row {
            spacing: Style.space(6)
            Text { text: (modelData.icon || "◇"); color: Color.foreground; font.family: "monospace"; font.pixelSize: Style.font.body; anchors.verticalCenter: parent.verticalCenter }
            Text { text: (modelData.text || modelData.key); color: Color.foreground; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
          }
          MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openPlugin(modelData.key) }
        }
      }
    }
    // right side: hugs the center gap from the right
    Row {
      id: rightRow
      z: 2
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.horizontalCenter
      anchors.leftMargin: pill.gapHalf
      spacing: Style.space(14)
      visible: !root.bar.vertical && pill.showAll
      opacity: (!root.bar.vertical && pill.showAll) ? 1 : 0
      Repeater {
        model: pill.rightHalf()
        Item {
          height: childrenRect.height
          Row {
            spacing: Style.space(6)
            Text { text: (modelData.icon || "◇"); color: Color.foreground; font.family: "monospace"; font.pixelSize: Style.font.body; anchors.verticalCenter: parent.verticalCenter }
            Text { text: (modelData.text || modelData.key); color: Color.foreground; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
          }
          MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openPlugin(modelData.key) }
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
            Text { text: (modelData.icon || "◇"); color: Color.foreground; font.family: "monospace"; font.pixelSize: Style.font.body; anchors.verticalCenter: parent.verticalCenter }
            Text { text: (modelData.text || modelData.key); color: Color.foreground; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
          }
          MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openPlugin(modelData.key) }
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
            font.family: "monospace"
            font.pixelSize: Style.font.body
            anchors.horizontalCenter: parent.horizontalCenter
          }
          MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openPlugin(modelData.key) }
        }
      }
    }
  }

  // single input layer on top
  MouseArea {
    id: clicker
    anchors.fill: parent; z: 5
    hoverEnabled: true; acceptedButtons: Qt.LeftButton
    onEntered: root.hovering = true
    onExited: root.hovering = false
    onClicked: root.clickToggle()
  }

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
