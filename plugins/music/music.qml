import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import qs.Commons
import qs.Ui

// SuperNotch plugin: Medios (MPRIS media control).
// Polls the helper's `mpris` command (proven, same source as the bar).
// Controls via helper: mpris-toggle, mpris-play, mpris-pause, mpris-next, mpris-prev, mpris-setpos.
Item {
  id: media
  property var root: null
  property string pluginKey: ""
  width: parent ? parent.width : 100
  implicitHeight: mainCol.implicitHeight + Style.space(40)

  function load() {
    if (!root) return
    root.run(["mpris"], function (out) {
      try {
        var s = JSON.parse((out || "").trim())
        state = {
          playing: !!s.playing,
          title: s.title || "",
          artist: s.artist || "",
          album: s.album || "",
          art: s.art || "",
          length: s.length || 0,
          position: s.position || 0,
          player: s.player || "",
          hasPlayer: !!s.hasPlayer,
          canPlay: !!s.canPlay,
          canPause: !!s.canPause,
          canGoNext: !!s.canGoNext,
          canGoPrev: !!s.canGoPrev,
          canTogglePlaying: !!(s.canPlay || s.canPause)
        }
      } catch (e) {}
      pushNotch()
    })
  }
  Component.onCompleted: if (root) { load(); pushNotch() }
  onRootChanged: if (root) { load(); pushNotch() }
  Connections { target: root; function onOpenedChanged() { if (root && root.opened) load() } }
  Timer { interval: 1000; running: root && root.opened; repeat: true; onTriggered: load() }

  property var state: ({ playing:false, title:"", artist:"", album:"", art:"", length:0, position:0, player:"", hasPlayer:false, canPlay:false, canPause:false, canGoNext:false, canGoPrev:false, canTogglePlaying:false })
  readonly property bool idle: !state.title || state.title === ""

  // ── notch pill — live track ──
  property string notchIcon: state.playing ? "󰏤" : "󰝚"
  property string notchText: media.idle ? "" : (state.title + (state.artist ? " · " + state.artist : ""))
  function pushNotch() {
    if (root && pluginKey) root.updateNotchData(pluginKey, notchIcon, notchText)
  }
  onNotchIconChanged: pushNotch()
  onNotchTextChanged: pushNotch()
  onStateChanged: pushNotch()

  function fmt(s) {
    s = Math.max(0, Math.round(s || 0))
    return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2)
  }

  Column {
    id: mainCol
    x: Style.space(20); y: Style.space(20)
    width: parent.width - Style.space(40)
    spacing: Style.space(16)

    // header: status + player chip
    Row {
      width: parent.width
      spacing: Style.space(8)
      Text { text: "󰝚"; font.family: Style.fontFamily; font.pixelSize: Style.font.body; anchors.verticalCenter: parent.verticalCenter }
      Text {
        text: media.idle ? root.t(root.uiLang, "noPlayer") : root.t(root.uiLang, "nowPlaying")
        color: Color.muted; font.pixelSize: Style.font.bodySmall; font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }
      Rectangle {
        visible: !!(state.hasPlayer && state.player && state.player !== "")
        height: Style.space(18); radius: Style.space(9)
        width: playerChip.implicitWidth + Style.space(14)
        color: Color.menu.selectedBackground
        border.color: Color.accent; border.width: 1
        anchors.verticalCenter: parent.verticalCenter
        Text {
          id: playerChip
          anchors.centerIn: parent
          text: state.player
          color: Color.accent; font.pixelSize: Style.font.caption; font.bold: true
        }
      }
    }

    // ══ IDLE: big music note ══
    Item {
      visible: media.idle
      width: parent.width; height: Style.space(120)
      Text {
        anchors.centerIn: parent; text: "󰝚"
        color: Color.accent; font.family: Style.fontFamily; font.pixelSize: Style.font.display * 1.5
        opacity: 0.4
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        text: root.t(root.uiLang, "noPlayer")
        color: Color.muted; font.pixelSize: Style.font.body
      }
    }

    // ══ PLAYING: album art + track + progress ══
    Rectangle {
      visible: !media.idle
      width: Style.space(88); height: Style.space(88); radius: Style.space(20)
      color: Color.menu.selectedBackground
      anchors.horizontalCenter: parent.horizontalCenter
      border.color: Color.accent; border.width: 1
      clip: true
      Image {
        anchors.fill: parent
        source: state.art || ""
        fillMode: Image.PreserveAspectCrop
        visible: state.art !== ""
        asynchronous: true
      }
      Text {
        anchors.centerIn: parent; text: "󰎆"
        color: Color.accent; font.family: Style.fontFamily; font.pixelSize: Style.font.title
        visible: state.art === ""
      }
    }

    Column {
      visible: !media.idle
      spacing: Style.space(4); width: parent.width
      Text {
        text: state.title || ""
        color: Color.foreground; font.pixelSize: Style.font.subtitle; font.bold: true
        horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; width: parent.width
      }
      Text {
        text: state.artist || ""
        color: Color.muted; font.pixelSize: Style.font.bodySmall
        horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; width: parent.width
      }
      Text {
        visible: !!(state.album && state.album !== "")
        text: state.album || ""
        color: Color.muted; font.pixelSize: Style.font.caption; font.italic: true
        horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; width: parent.width
      }
    }

    // progress with time labels
    Row {
      visible: !media.idle
      width: parent.width; spacing: Style.space(8)
      Text {
        text: media.fmt(state.position)
        color: Color.muted; font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }
      Rectangle {
        id: progressTrack
        width: parent.width - Style.space(72); height: Style.space(6); radius: Style.space(3)
        color: Color.menu.selectedBackground
        anchors.verticalCenter: parent.verticalCenter
        Rectangle {
          width: parent.width * Math.min(1, (state.length > 0 ? state.position / state.length : 0))
          height: parent.height; radius: parent.height / 2
          color: Color.accent
          Behavior on width { NumberAnimation { duration: 250 } }
        }
        MouseArea {
          anchors.fill: parent
          anchors.margins: -Style.space(6)
          cursorShape: Qt.PointingHandCursor
          property bool dragging: false
          onPressed: dragging = true
          onPositionChanged: if (dragging && pressed) {
            if (state.length <= 0) return
            var ratio = Math.max(0, Math.min(1, mouse.x / progressTrack.width))
            var ns = state; ns.position = Math.round(ratio * state.length); state = ns
          }
          onReleased: {
            dragging = false
            if (!root || state.length <= 0) return
            var ratio = Math.max(0, Math.min(1, mouse.x / progressTrack.width))
            root.run(["mpris-setpos", String(Math.round(ratio * state.length))], load)
          }
        }
      }
      Text {
        text: media.fmt(state.length)
        color: Color.muted; font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    // ══ transport controls — magnetic, bouncy ══
    Row {
      spacing: Style.space(20); anchors.horizontalCenter: parent.horizontalCenter
      // PREV
      Rectangle {
        width: Style.space(44); height: Style.space(44); radius: Style.space(22)
        color: Color.menu.selectedBackground
        border.color: prevMa.containsMouse ? Color.accent : Color.popups.border
        border.width: 1
        opacity: state.canGoPrev ? 1 : 0.4
        scale: prevMa.pressed ? 0.8 : (prevMa.containsMouse ? 1.08 : 1.0)
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 2.6 } }
        Behavior on border.color { ColorAnimation { duration: 130 } }
        Text { anchors.centerIn: parent; text: "󰒮"; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.body }
        MouseArea { id: prevMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
          onClicked: if (root) root.run(["mpris-prev"], load) }
      }
      // PLAY/PAUSE
      Item {
        width: Style.space(60); height: Style.space(60)
        Rectangle {
          anchors.centerIn: parent
          width: Style.space(54); height: Style.space(54); radius: Style.space(27)
          color: Color.accent; opacity: 0.4
          layer.enabled: true
          layer.effect: MultiEffect { blurEnabled: true; blurMax: 28; blur: 1.0 }
          scale: playBtn.scale
        }
        Rectangle {
          id: playBtn
          anchors.centerIn: parent
          width: Style.space(50); height: Style.space(50); radius: Style.space(25)
          color: Color.accent
          scale: playMa.pressed ? 0.82 : (playMa.containsMouse ? 1.08 : 1.0)
          Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }
          Text {
            anchors.centerIn: parent
            text: state.playing ? "󰏤" : "󰐊"
            color: Color.background; font.family: Style.fontFamily; font.pixelSize: Style.font.subtitle; font.bold: true
          }
        }
        MouseArea { id: playMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
          onClicked: if (root) root.run(["mpris-toggle"], load) }
      }
      // NEXT
      Rectangle {
        width: Style.space(44); height: Style.space(44); radius: Style.space(22)
        color: Color.menu.selectedBackground
        border.color: nextMa.containsMouse ? Color.accent : Color.popups.border
        border.width: 1
        opacity: state.canGoNext ? 1 : 0.4
        scale: nextMa.pressed ? 0.8 : (nextMa.containsMouse ? 1.08 : 1.0)
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 2.6 } }
        Behavior on border.color { ColorAnimation { duration: 130 } }
        Text { anchors.centerIn: parent; text: "󰒭"; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.body }
        MouseArea { id: nextMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
          onClicked: if (root) root.run(["mpris-next"], load) }
      }
    }
  }
}
