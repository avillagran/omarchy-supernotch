import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui

// SuperNotch plugin: Medios (MPRIS media control — music, video, any player).
// Receives `root` (the Panel) for root.run()/root.t().
Item {
  id: media
  property var root: null
  property string pluginKey: ""
  width: parent ? parent.width : 100
  implicitHeight: mainCol.implicitHeight + Style.space(40)

  function load() {
    // Prefer native Quickshell Mpris (same source as Omarchy bar) — instant & reliable.
    // Fallback to helper gdbus if no Mpris player yet (e.g. during startup).
    if (syncFromMpris()) return
    if (!root) return
    root.run(["mpris"], function (out) {
      try { state = JSON.parse(out.trim()); pushNotch() } catch (e) {}
    })
  }
  // ── native Mpris (Quickshell.Services.Mpris) — mirrors omarchy.media Service ──
  readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []
  readonly property var activeMprisPlayer: {
    var pls = mprisPlayers
    if (!pls || pls.length === 0) return null
    for (var i = 0; i < pls.length; i++) if (pls[i] && pls[i].isPlaying) return pls[i]
    for (var j = 0; j < pls.length; j++) if (pls[j] && pls[j].trackTitle) return pls[j]
    return pls[0]
  }
  function syncFromMpris() {
    var p = activeMprisPlayer
    if (!p) return false
    var len = p.length || 0
    var pos = p.position || 0
    // Quickshell reports seconds (float < 10000), helper uses microseconds.
    // Normalize to microseconds for fmt() and progress math.
    if (len > 0 && len < 10000) len = Math.round(len * 1000000)
    if (pos >= 0 && pos < 10000) pos = Math.round(pos * 1000000)
    // artUrl may be file:// — Image handles it directly
    state = {
      playing: !!p.isPlaying,
      title: p.trackTitle || "",
      artist: p.trackArtist || "",
      album: p.trackAlbum || "",
      art: p.trackArtUrl || "",
      length: len,
      position: pos,
      player: p.identity || p.desktopEntry || p.busName || "",
      hasPlayer: true,
      canPlay: !!p.canPlay,
      canPause: !!p.canPause,
      canGoNext: !!p.canGoNext,
      canGoPrev: !!(p.canGoPrevious || p.canGoNext),
      canGoPrevious: !!(p.canGoPrevious || p.canGoNext)
    }
    pushNotch()
    return true
  }
  onActiveMprisPlayerChanged: syncFromMpris()
  Connections { target: Mpris; function onPlayersChanged() { media.syncFromMpris() } }
  Component.onCompleted: if (root) { syncFromMpris(); load(); pushNotch() }
  onRootChanged: if (root) { syncFromMpris(); load(); pushNotch() }
  Connections { target: root; function onOpenedChanged() { if (root && root.opened) { media.syncFromMpris(); load() } } }
  Timer { interval: 1000; running: root && root.opened; repeat: true; onTriggered: { if (!media.syncFromMpris()) load() } }

  property var state: ({ playing:false, title:"", artist:"", album:"", art:"", length:0, position:0, player:"", hasPlayer:false, canPlay:false, canPause:false, canGoNext:false, canGoPrev:false })
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

  function fmt(us) {
    var s = Math.max(0, Math.round((us || 0) / 1000000))
    return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2)
  }

  Column {
    id: mainCol
    x: Style.space(20); y: Style.space(20)
    width: parent.width - Style.space(40)
    spacing: Style.space(14)

    // header: status + player chip
    Row {
      width: parent.width
      anchors.horizontalCenter: parent.horizontalCenter
      Item { width: Math.max(0, (parent.width - headRow.implicitWidth) / 2); height: 1 }
      Row {
        id: headRow; spacing: Style.space(8)
        Text { text: "󰝚"; font.family: Style.fontFamily; font.pixelSize: Style.font.body; anchors.verticalCenter: parent.verticalCenter }
        Text {
          text: media.idle ? root.t(root.uiLang, "noPlayer") : root.t(root.uiLang, "nowPlaying")
          color: Color.muted; font.pixelSize: Style.font.bodySmall; font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }
        // player chip (Spotify, Firefox, mpv…)
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
            text: state.player ? state.player : ""
            color: Color.accent; font.pixelSize: Style.font.caption; font.bold: true
          }
        }
      }
      Item { width: Math.max(0, (parent.width - headRow.implicitWidth) / 2); height: 1 }
    }

    // ══ IDLE: living equalizer bars with gradient ══
    Item {
      visible: media.idle
      width: parent.width; height: Style.space(110)
      Row {
        anchors.centerIn: parent; spacing: Style.space(7); height: parent.height
        Repeater {
          model: 7
          Item {
            width: Style.space(5); height: parent.height
            Rectangle {
              width: parent.width; radius: Style.space(2.5)
              y: parent.height - height
              height: Style.space(10)
              gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25) }
                GradientStop { position: 1.0; color: Color.accent }
              }
              opacity: 0.5 + 0.12 * Math.abs(3 - index)
              SequentialAnimation on height {
                loops: Animation.Infinite; running: visible
                NumberAnimation { to: Style.space(16 + (index % 4) * 12); duration: 480 + index * 137; easing.type: Easing.InOutSine }
                NumberAnimation { to: Style.space(8); duration: 520 + index * 113; easing.type: Easing.InOutSine }
              }
            }
          }
        }
      }
    }

    // ══ PLAYING: album art + track + clickable progress ══
    Rectangle {
      visible: !media.idle
      width: Style.space(84); height: Style.space(84); radius: Style.space(18)
      color: Color.menu.selectedBackground
      anchors.horizontalCenter: parent.horizontalCenter
      border.color: Color.accent; border.width: 1
      clip: true
      layer.enabled: true
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
      // mini equalizer overlay while actually playing
      Row {
        visible: !!state.playing
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: Style.space(8)
        spacing: Style.space(2.5); height: Style.space(14)
        Repeater {
          model: 3
          Item {
            width: Style.space(3); height: parent.height
            Rectangle {
              width: parent.width; radius: Style.space(1.5)
              y: parent.height - height; height: Style.space(4)
              color: Color.foreground
              SequentialAnimation on height {
                loops: Animation.Infinite; running: !!state.playing
                NumberAnimation { to: Style.space(6 + (index % 3) * 4); duration: 380 + index * 120; easing.type: Easing.InOutSine }
                NumberAnimation { to: Style.space(3); duration: 420 + index * 90; easing.type: Easing.InOutSine }
              }
            }
          }
        }
      }
    }

    Column {
      visible: !media.idle
      spacing: Style.space(4); width: parent.width
      Text {
        text: state.title ? state.title : ""
        color: Color.foreground; font.pixelSize: Style.font.subtitle; font.bold: true
        horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; width: parent.width
      }
      Text {
        text: state.artist ? state.artist : ""
        color: Color.muted; font.pixelSize: Style.font.bodySmall
        horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; width: parent.width
      }
      Text {
        visible: !!(state.album && state.album !== "")
        text: state.album ? state.album : ""
        color: Color.muted; font.pixelSize: Style.font.caption; font.italic: true
        horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; width: parent.width
      }
    }

    // progress with time labels; click to seek
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
          Behavior on width { NumberAnimation { duration: 400 } }
        }
        MouseArea {
          anchors.fill: parent
          anchors.margins: -Style.space(6)
          cursorShape: Qt.PointingHandCursor
          property bool dragging: false
          onPressed: dragging = true
          onPositionChanged: if (dragging && pressed) {
            if (!root || state.length <= 0) return
            var ratio = Math.max(0, Math.min(1, mouse.x / progressTrack.width))
            var us = Math.round(ratio * state.length)
            var ns = state; ns.position = us; state = ns
          }
          onReleased: {
            dragging = false
            if (!root || state.length <= 0) return
            var ratio = Math.max(0, Math.min(1, mouse.x / progressTrack.width))
            root.run(["mpris-setpos", String(Math.round(ratio * state.length))], load)
          }
          onClicked: {
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
      spacing: Style.space(18); anchors.horizontalCenter: parent.horizontalCenter
      Rectangle {
        width: Style.space(42); height: Style.space(42); radius: Style.space(21)
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
      Item {
        width: Style.space(56); height: Style.space(56)
        Rectangle {
          anchors.centerIn: parent
          width: Style.space(52); height: Style.space(52); radius: Style.space(26)
          color: Color.accent; opacity: 0.4
          layer.enabled: true
          layer.effect: MultiEffect { blurEnabled: true; blurMax: 28; blur: 1.0 }
          scale: playBtn.scale
        }
        Rectangle {
          id: playBtn
          anchors.centerIn: parent
          width: Style.space(48); height: Style.space(48); radius: Style.space(24)
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
      Rectangle {
        width: Style.space(42); height: Style.space(42); radius: Style.space(21)
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
