import QtQuick
import QtQuick.Effects
import qs.Commons

// Animated card backgrounds. Each background is a self-contained Item that
// fills its parent (the cardSurface). They all read root.cursorNX / cursorNY
// for pointer parallax and root.opened to know when to animate.
//
// Usage: Backgrounds { bg: root.bg; opened: root.opened }
// `bg` is one of: aurora | sand | cubes | nebula | waves
Item {
  id: bgRoot
  property var rootRef: null
  readonly property string bg: bgRoot.rootRef ? bgRoot.rootRef.bg : "aurora"
  readonly property bool opened: bgRoot.rootRef ? bgRoot.rootRef.opened : true
  // cursor parallax (fallback 0 until rootRef is wired in onLoaded)
  readonly property real cx: bgRoot.rootRef ? bgRoot.rootRef.cursorNX : 0
  readonly property real cy: bgRoot.rootRef ? bgRoot.rootRef.cursorNY : 0
  anchors.fill: parent
  clip: true

  // ── AURORA: three blurred accent orbs drifting (the original look) ────────
  Item {
    anchors.fill: parent
    visible: bgRoot.bg === "aurora"
    Rectangle {
      width: parent.width * 0.6; height: parent.height * 0.55
      x: parent.width * 0.05 + driftA.dx + bgRoot.cx * Style.space(46)
      y: parent.height * 0.02 + driftA.dy + bgRoot.cy * Style.space(26)
      radius: width / 2; color: Color.accent; opacity: 0.72
      layer.enabled: true; layer.effect: MultiEffect { blurEnabled: true; blurMax: 90; blur: 1.0 }
      Item { id: driftA; property real dx: 0; property real dy: 0
        SequentialAnimation on dx { loops: Animation.Infinite; running: bgRoot.opened
          NumberAnimation { to: 46; duration: 5200; easing.type: Easing.InOutSine }
          NumberAnimation { to: -20; duration: 6400; easing.type: Easing.InOutSine }
          NumberAnimation { to: 0; duration: 4800; easing.type: Easing.InOutSine } }
        SequentialAnimation on dy { loops: Animation.Infinite; running: bgRoot.opened
          NumberAnimation { to: 30; duration: 6100; easing.type: Easing.InOutSine }
          NumberAnimation { to: -16; duration: 5300; easing.type: Easing.InOutSine }
          NumberAnimation { to: 0; duration: 5900; easing.type: Easing.InOutSine } } }
    }
    Rectangle {
      width: parent.width * 0.5; height: parent.height * 0.48
      x: parent.width * 0.45 + driftB.dx - bgRoot.cx * Style.space(30)
      y: parent.height * 0.42 + driftB.dy - bgRoot.cy * Style.space(18)
      radius: width / 2; color: Qt.lighter(Color.accent, 1.35); opacity: 0.55
      layer.enabled: true; layer.effect: MultiEffect { blurEnabled: true; blurMax: 100; blur: 1.0 }
      Item { id: driftB; property real dx: 0; property real dy: 0
        SequentialAnimation on dx { loops: Animation.Infinite; running: bgRoot.opened
          NumberAnimation { to: -38; duration: 7300; easing.type: Easing.InOutSine }
          NumberAnimation { to: 26; duration: 5800; easing.type: Easing.InOutSine }
          NumberAnimation { to: 0; duration: 6600; easing.type: Easing.InOutSine } }
        SequentialAnimation on dy { loops: Animation.Infinite; running: bgRoot.opened
          NumberAnimation { to: -22; duration: 6700; easing.type: Easing.InOutSine }
          NumberAnimation { to: 20; duration: 7100; easing.type: Easing.InOutSine }
          NumberAnimation { to: 0; duration: 5600; easing.type: Easing.InOutSine } } }
    }
    Rectangle {
      width: parent.width * 0.38; height: parent.height * 0.38
      x: parent.width * 0.32 + driftC.dx + bgRoot.cx * Style.space(24)
      y: parent.height * 0.22 + driftC.dy + bgRoot.cy * Style.space(14)
      radius: width / 2; color: Qt.darker(Color.accent, 1.4); opacity: 0.45
      layer.enabled: true; layer.effect: MultiEffect { blurEnabled: true; blurMax: 80; blur: 1.0 }
      Item { id: driftC; property real dx: 0; property real dy: 0
        SequentialAnimation on dx { loops: Animation.Infinite; running: bgRoot.opened
          NumberAnimation { to: 22; duration: 4500; easing.type: Easing.InOutSine }
          NumberAnimation { to: -28; duration: 6200; easing.type: Easing.InOutSine }
          NumberAnimation { to: 0; duration: 5400; easing.type: Easing.InOutSine } } }
    }
  }

  // ── SAND: warm desert dunes, slow horizontal drift + parallax ──────────────
  Item {
    anchors.fill: parent
    visible: bgRoot.bg === "sand"
    // base warm wash
    Rectangle { anchors.fill: parent; gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.rgba(0.96, 0.78, 0.45, 0.30) }
      GradientStop { position: 1.0; color: Qt.rgba(0.85, 0.55, 0.25, 0.22) } } }
    // dune bands
    Repeater {
      model: 4
      Item {
        property int idx: index
        anchors.fill: parent
        Rectangle {
          width: parent.width * 1.4; height: parent.height * 0.5
          x: -parent.width * 0.2 + dune.dx + bgRoot.cx * Style.space(20 + index * 8)
          y: parent.height * (0.35 + index * 0.16) - height / 2
          radius: height
          color: Qt.rgba(0.82 + index * 0.04, 0.58 + index * 0.05, 0.22 + index * 0.03, 0.72 - index * 0.07)
          layer.enabled: true; layer.effect: MultiEffect { blurEnabled: true; blurMax: 26; blur: 1.0 }
          Item { id: dune; property real dx: 0
            SequentialAnimation on dx { loops: Animation.Infinite; running: bgRoot.opened
              NumberAnimation { to: parent.width * 0.18; duration: 9000 + index * 1400; easing.type: Easing.InOutSine }
              NumberAnimation { to: -parent.width * 0.12; duration: 9000 + index * 1400; easing.type: Easing.InOutSine } } }
        }
      }
    }
    // sun glow
    Rectangle {
      width: parent.width * 0.5; height: parent.width * 0.5
      x: parent.width * 0.7 + bgRoot.cx * Style.space(30); y: -parent.height * 0.25
      radius: width / 2; color: Qt.rgba(1.0, 0.92, 0.6, 0.68)
      layer.enabled: true; layer.effect: MultiEffect { blurEnabled: true; blurMax: 70; blur: 1.0 }
    }
  }

  // ── CUBES: floating rotated-square "cubes" with borders ───────────────────
  Item {
    anchors.fill: parent
    visible: bgRoot.bg === "cubes"
    Repeater {
      model: 7
      Rectangle {
        id: cube
        width: 26 + (index * 7) % 34; height: width
        x: parent.width * (0.08 + (index * 0.13) % 0.8) + bgRoot.cx * Style.space(14 + index * 5)
        y: parent.height * (0.1 + (index * 0.11) % 0.75) + bgRoot.cy * Style.space(10 + index * 4)
        color: index % 3 === 0 ? Color.accent : (index % 3 === 1 ? Qt.lighter(Color.accent, 1.4) : Qt.darker(Color.accent, 1.3))
        opacity: 0.6
        rotation: 45
        radius: width * 0.1
        border.color: Color.foreground; border.width: 1
        NumberAnimation on scale { loops: Animation.Infinite; running: bgRoot.opened
          to: 1.12; duration: 2400 + index * 260; easing.type: Easing.InOutSine }
      }
    }
  }

  // ── NEBULA: deep-space violet/blue cloud with twinkling stars ─────────────
  Item {
    anchors.fill: parent
    visible: bgRoot.bg === "nebula"
    Rectangle { anchors.fill: parent; gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.rgba(0.18, 0.12, 0.34, 0.55) }
      GradientStop { position: 1.0; color: Qt.rgba(0.06, 0.10, 0.28, 0.5) } } }
    Repeater {
      model: 3
      Rectangle {
        width: parent.width * (0.5 + index * 0.12); height: parent.height * (0.5 + index * 0.1)
        x: parent.width * (0.1 + index * 0.28) + nb.dx + bgRoot.cx * Style.space(28 - index * 6)
        y: parent.height * (0.1 + index * 0.2) + nb.dy
        radius: width / 2
        color: index % 2 ? Qt.rgba(0.62, 0.42, 0.97, 0.55) : Qt.rgba(0.33, 0.62, 0.97, 0.5)
        layer.enabled: true; layer.effect: MultiEffect { blurEnabled: true; blurMax: 95; blur: 1.0 }
        Item { id: nb; property real dx: 0; property real dy: 0
          SequentialAnimation on dx { loops: Animation.Infinite; running: bgRoot.opened
            NumberAnimation { to: 40; duration: 8000 + index * 1500; easing.type: Easing.InOutSine }
            NumberAnimation { to: -30; duration: 8000 + index * 1500; easing.type: Easing.InOutSine } }
          SequentialAnimation on dy { loops: Animation.Infinite; running: bgRoot.opened
            NumberAnimation { to: 24; duration: 7000 + index * 1200; easing.type: Easing.InOutSine }
            NumberAnimation { to: -18; duration: 7000 + index * 1200; easing.type: Easing.InOutSine } } }
      }
    }
    // stars
    Repeater {
      model: 18
      Rectangle {
        width: 2 + (index % 3); height: width; radius: width / 2
        x: (index * 97 % 100) / 100 * parent.width
        y: (index * 53 % 100) / 100 * parent.height
        color: "#ffffff"; opacity: 0.2 + (index % 5) * 0.12
        PropertyAnimation on opacity { loops: Animation.Infinite; running: bgRoot.opened
          to: 0.1; duration: 1200 + (index % 7) * 200; easing.type: Easing.InOutSine }
      }
    }
  }

  // ── WAVES: flowing horizontal light waves (audio-visualizer vibe) ──────────
  Item {
    anchors.fill: parent
    visible: bgRoot.bg === "waves"
    Repeater {
      model: 5
      Rectangle {
        width: parent.width * 1.2; height: parent.height * 0.32
        x: -parent.width * 0.1 + wv.dx + bgRoot.cx * Style.space(18 + index * 6)
        y: parent.height * (0.15 + index * 0.16) - height / 2
        radius: height
        color: index % 2 ? Color.accent : Qt.lighter(Color.accent, 1.25)
        opacity: 0.4 + index * 0.04
        transform: Scale { id: wscale; yScale: 1 }
        layer.enabled: true; layer.effect: MultiEffect { blurEnabled: true; blurMax: 30; blur: 1.0 }
        NumberAnimation on scale { loops: Animation.Infinite; running: bgRoot.opened
          to: 1.15; duration: 2600 + index * 300; easing.type: Easing.InOutSine }
        Item { id: wv; property real dx: 0
          SequentialAnimation on dx { loops: Animation.Infinite; running: bgRoot.opened
            NumberAnimation { to: parent.width * 0.14; duration: 5200 + index * 700; easing.type: Easing.InOutSine }
            NumberAnimation { to: -parent.width * 0.1; duration: 5200 + index * 700; easing.type: Easing.InOutSine } } }
      }
    }
  }
}
