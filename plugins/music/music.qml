import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui

// SuperNotch plugin: Medios (MPRIS media control).
// Uses Quickshell.Services.Mpris directly (same source as Omarchy's Media bar
// widget). Controls call player methods directly — no helper needed.
Item {
  id: media
  property var root: null
  property string pluginKey: ""
  width: parent ? parent.width : 100
  implicitHeight: mainCol.implicitHeight + Style.space(40)

  // ── player discovery ──
  readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []
  readonly property var activePlayer: {
    var pls = mprisPlayers
    if (!pls || pls.length === 0) return null
    for (var i = 0; i < pls.length; i++) {
      var p = pls[i]
      if (p && p.isPlaying && p.trackTitle) return p
    }
    for (var j = 0; j < pls.length; j++) {
      var q = pls[j]
      if (q && q.trackTitle) return q
    }
    return pls[0]
  }

  // Live Connections — re-targets automatically when activePlayer changes.
  Connections {
    target: media.activePlayer
    function onIsPlayingChanged() { media.sync() }
    function onTrackTitleChanged() { media.sync() }
    function onTrackArtistChanged() { media.sync() }
    function onTrackAlbumChanged() { media.sync() }
    function onTrackArtUrlChanged() { media.sync() }
    function onPositionChanged() { media.sync() }
    function onLengthChanged() { media.sync() }
    function onVolumeChanged() { media.sync() }
    function onCanPlayChanged() { media.sync() }
    function onCanPauseChanged() { media.sync() }
    function onCanGoNextChanged() { media.sync() }
    function onCanGoPreviousChanged() { media.sync() }
    function onCanSeekChanged() { media.sync() }
    function onCanTogglePlayingChanged() { media.sync() }
    function onIdentityChanged() { media.sync() }
  }

  // ── individual properties (guaranteed QML reactivity) ──
  property bool playing: false
  property string title: ""
  property string artist: ""
  property string album: ""
  property string art: ""
  property real trackLength: 0
  property real trackPosition: 0
  property string playerName: ""
  property bool hasPlayer: false
  property bool canPlayP: false
  property bool canPauseP: false
  property bool canGoNextP: false
  property bool canGoPrevP: false
  property bool canSeekP: false
  property real volume: 0
  property bool volumeSupported: false

  readonly property bool idle: !title || title === ""

  function sync() {
    var p = activePlayer
    if (!p) {
      playing = false; title = ""; artist = ""; album = ""; art = ""
      trackLength = 0; trackPosition = 0; playerName = ""; hasPlayer = false
      canPlayP = false; canPauseP = false; canGoNextP = false; canGoPrevP = false
      canSeekP = false; volume = 0; volumeSupported = false
      pushNotch()
      return
    }
    playing = !!p.isPlaying
    title = p.trackTitle || ""
    artist = p.trackArtist || ""
    album = p.trackAlbum || ""
    art = p.trackArtUrl || ""
    trackLength = p.length || 0
    trackPosition = p.position || 0
    playerName = p.identity || p.desktopEntry || ""
    hasPlayer = true
    canPlayP = !!p.canPlay
    canPauseP = !!p.canPause
    canGoNextP = !!p.canGoNext
    canGoPrevP = !!p.canGoPrevious
    canSeekP = !!p.canSeek
    volume = p.volume || 0
    volumeSupported = !!p.volumeSupported
    pushNotch()
  }

  Component.onCompleted: { sync(); pushNotch() }
  onRootChanged: { sync(); pushNotch() }
  Connections { target: root; function onOpenedChanged() { if (root && root.opened) media.sync() } }
  Timer { interval: 1000; running: root && root.opened; repeat: true; onTriggered: media.sync() }

  // ── notch pill — live track ──
  property string notchIcon: playing ? "󰏤" : "󰝚"
  property string notchText: idle ? "" : (title + (artist ? " · " + artist : ""))
  function pushNotch() {
    if (root && pluginKey) root.updateNotchData(pluginKey, notchIcon, notchText)
  }
  onNotchIconChanged: pushNotch()
  onNotchTextChanged: pushNotch()

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
        color: Qt.darker(Color.foreground, 1.5); font.pixelSize: Style.font.bodySmall; font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }
      Rectangle {
        visible: media.hasPlayer && media.playerName !== ""
        height: Style.space(18); radius: Style.space(9)
        width: playerChip.implicitWidth + Style.space(14)
        color: Color.menu.selectedBackground
        border.color: Color.accent; border.width: 1
        anchors.verticalCenter: parent.verticalCenter
        Text {
          id: playerChip
          anchors.centerIn: parent
          text: media.playerName
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
        color: Qt.darker(Color.foreground, 1.5); font.pixelSize: Style.font.body
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
        source: media.art || ""
        fillMode: Image.PreserveAspectCrop
        visible: media.art !== ""
        asynchronous: true
      }
      Text {
        anchors.centerIn: parent; text: "󰎆"
        color: Color.accent; font.family: Style.fontFamily; font.pixelSize: Style.font.title
        visible: media.art === ""
      }
    }

    // title / artist / album — Marquee for long titles
    Column {
      visible: !media.idle
      spacing: Style.space(4); width: parent.width

      // Marquee title: scrolls horizontally when wider than the panel
      Item {
        width: parent.width; height: Style.space(28)
        clip: true
        Text {
          id: titleText
          text: media.title
          color: Color.foreground; font.pixelSize: Style.font.subtitle; font.bold: true
          font.family: Style.fontFamily

          SequentialAnimation on x {
            running: titleText.width > parent.width
            loops: Animation.Infinite
            NumberAnimation { to: -(titleText.width); duration: Math.max(3000, titleText.width * 20); easing.type: Easing.Linear }
            PauseAnimation { duration: 800 }
            NumberAnimation { to: 0; duration: 1 }
            PauseAnimation { duration: 400 }
          }
        }
      }

      Text {
        text: media.artist
        color: Qt.darker(Color.foreground, 1.5); font.pixelSize: Style.font.bodySmall
        horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; width: parent.width
        visible: media.artist !== ""
      }
      Text {
        visible: media.album !== ""
        text: media.album
        color: Qt.darker(Color.foreground, 1.5); font.pixelSize: Style.font.caption; font.italic: true
        horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; width: parent.width
      }
    }

    // progress with time labels; drag to seek (native player.position)
    Row {
      visible: !media.idle && media.trackLength > 0
      width: parent.width; spacing: Style.space(8)
      Text {
        text: media.fmt(media.trackPosition)
        color: Qt.darker(Color.foreground, 1.5); font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }
      Rectangle {
        id: progressTrack
        width: parent.width - Style.space(72); height: Style.space(6); radius: Style.space(3)
        color: Color.menu.selectedBackground
        anchors.verticalCenter: parent.verticalCenter
        Rectangle {
          width: parent.width * Math.min(1, (media.trackLength > 0 ? media.trackPosition / media.trackLength : 0))
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
            if (!media.activePlayer || media.trackLength <= 0) return
            var ratio = Math.max(0, Math.min(1, mouse.x / progressTrack.width))
            media.trackPosition = ratio * media.trackLength
          }
          onReleased: {
            dragging = false
            if (!media.activePlayer || media.trackLength <= 0) return
            var ratio = Math.max(0, Math.min(1, mouse.x / progressTrack.width))
            media.activePlayer.position = ratio * media.trackLength
          }
        }
      }
      Text {
        text: media.fmt(media.trackLength)
        color: Qt.darker(Color.foreground, 1.5); font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    // volume slider (if supported by the player)
    Row {
      visible: !media.idle && media.volumeSupported
      width: parent.width; spacing: Style.space(8)
      Text {
        text: "󰕾"; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall
        color: Qt.darker(Color.foreground, 1.5); anchors.verticalCenter: parent.verticalCenter
      }
      Rectangle {
        id: volTrack
        width: parent.width - Style.space(48); height: Style.space(6); radius: Style.space(3)
        color: Color.menu.selectedBackground
        anchors.verticalCenter: parent.verticalCenter
        Rectangle {
          width: parent.width * Math.min(1, Math.max(0, media.volume))
          height: parent.height; radius: parent.height / 2
          color: Color.accent
          Behavior on width { NumberAnimation { duration: 200 } }
        }
        MouseArea {
          anchors.fill: parent
          anchors.margins: -Style.space(6)
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (!media.activePlayer) return
            var ratio = Math.max(0, Math.min(1, mouse.x / volTrack.width))
            media.activePlayer.volume = ratio
          }
          onPositionChanged: if (pressed && media.activePlayer) {
            var ratio = Math.max(0, Math.min(1, mouse.x / volTrack.width))
            media.activePlayer.volume = ratio
          }
        }
      }
      Text {
        text: Math.round(media.volume * 100) + "%"
        color: Qt.darker(Color.foreground, 1.5); font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    // ══ transport controls — magnetic, bouncy ══
    Row {
      spacing: Style.space(20); anchors.horizontalCenter: parent.horizontalCenter
      Rectangle {
        width: Style.space(44); height: Style.space(44); radius: Style.space(22)
        color: Color.menu.selectedBackground
        border.color: prevMa.containsMouse ? Color.accent : Color.popups.border
        border.width: 1
        opacity: media.canGoPrevP ? 1 : 0.4
        scale: prevMa.pressed ? 0.8 : (prevMa.containsMouse ? 1.08 : 1.0)
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 2.6 } }
        Behavior on border.color { ColorAnimation { duration: 130 } }
        Text { anchors.centerIn: parent; text: "󰒮"; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.body }
        MouseArea { id: prevMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
          onClicked: if (media.activePlayer) media.activePlayer.previous() }
      }
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
            text: media.playing ? "󰏤" : "󰐊"
            color: Color.background; font.family: Style.fontFamily; font.pixelSize: Style.font.subtitle; font.bold: true
          }
        }
        MouseArea { id: playMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
          onClicked: if (media.activePlayer) media.activePlayer.togglePlaying() }
      }
      Rectangle {
        width: Style.space(44); height: Style.space(44); radius: Style.space(22)
        color: Color.menu.selectedBackground
        border.color: nextMa.containsMouse ? Color.accent : Color.popups.border
        border.width: 1
        opacity: media.canGoNextP ? 1 : 0.4
        scale: nextMa.pressed ? 0.8 : (nextMa.containsMouse ? 1.08 : 1.0)
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 2.6 } }
        Behavior on border.color { ColorAnimation { duration: 130 } }
        Text { anchors.centerIn: parent; text: "󰒭"; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.body }
        MouseArea { id: nextMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
          onClicked: if (media.activePlayer) media.activePlayer.next() }
      }
    }
  }
}
