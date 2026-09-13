import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// SuperNotch plugin: Clipboard. Receives `root` (the Panel) for root.run()/root.t().
Item {
  id: m
  property var root: null
  property string pluginKey: ""
  width: parent ? parent.width : 100
  implicitHeight: mainCol.implicitHeight + Style.space(32)

  function load() {
    if (!root) return
    root.run(["clip-list"], function (out) {
      try { list = JSON.parse(out.trim()) } catch (e) { list = [] }
    })
    root.run(["clip-enabled"], function (out) { m.recordingEnabled = (out || "").trim() !== "false" })
  }
  Component.onCompleted: if (root) load()
  onRootChanged: if (root) load()
  Connections { target: root; function onOpenedChanged() { if (root && root.opened) load() } }

  property var list: []
  property bool recordingEnabled: true
  function setRecordingEnabled(enabled) {
    recordingEnabled = enabled
    if (root) root.run(["clip-set-enabled", enabled ? "true" : "false"])
  }
  // New-clip counter: how many clips appeared since the card was last opened
  // (i.e. since the user last "reviewed" the clipboard).
  property int seenCount: 0
  property int newCount: 0
  function pushNotch() {
    m.newCount = Math.max(0, m.list.length - m.seenCount)
    m.notchText = m.newCount > 0 ? "+" + m.newCount : ""
    if (root && pluginKey) root.updateNotchData(pluginKey, m.notchIcon, m.notchText)
  }
  onListChanged: pushNotch()
  onNotchTextChanged: if (root && pluginKey) root.updateNotchData(pluginKey, notchIcon, notchText)
  // When the card opens, the user is reviewing → reset the "new" baseline.
  Connections { target: root; function onOpenedChanged() { if (root && root.opened) { m.seenCount = m.list.length; m.pushNotch() } } }
  // Notch pill mini-status: clipboard icon + "+N" new badge.
  property string notchIcon: "󰅇"
  property string notchText: ""

  Column {
    id: mainCol
    x: Style.space(20); y: Style.space(20)
    width: parent.width - Style.space(40)
    spacing: Style.space(10)
    Row {
      width: parent.width
      Text {
        width: Math.max(0, parent.width - recordingToggle.width - Style.space(12))
        text: root.t(root.uiLang, "clipboard")
        elide: Text.ElideRight
        color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.body; font.bold: true
      }
      Rectangle {
        id: recordingToggle
        width: recordingLabel.implicitWidth + Style.space(16); height: Style.space(26)
        radius: Style.cornerRadius
        color: recordingMouse.containsMouse ? Color.menu.selectedBackground : "transparent"
        border.color: m.recordingEnabled ? Color.accent : Color.popups.border; border.width: 1
        Text {
          id: recordingLabel; anchors.centerIn: parent
          text: m.recordingEnabled ? "󰐊 " + (root.uiLang === "es" ? "Registrando" : "Recording") : "󰏤 " + (root.uiLang === "es" ? "Pausado" : "Paused")
          color: m.recordingEnabled ? Color.accent : Color.muted
          font.family: Style.fontFamily; font.pixelSize: Style.font.caption
        }
        MouseArea { id: recordingMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: m.setRecordingEnabled(!m.recordingEnabled) }
      }
    }
    Rectangle { width: parent.width; height: 1; color: Color.popups.border; opacity: 0.5 }
    Flickable {
      width: parent.width; height: Math.min(360, col.height)
      contentHeight: col.height; clip: true
      Column {
        id: col; width: parent.width; spacing: Style.space(6)
        Repeater {
          model: list
          Rectangle {
            width: parent.width; radius: Style.space(8)
            color: Color.menu.selectedBackground
            height: Style.space(34)
            Text {
              anchors.centerIn: parent
              text: (modelData.sensitive ? "󰌾 " : "󰧮 ") +
                    (modelData.txt.length > 46 ? modelData.txt.slice(0, 44) + "…" : modelData.txt)
              color: modelData.sensitive ? Qt.darker(Color.foreground, 1.5) : Color.foreground
              font.family: Style.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight; width: parent.width - Style.space(20)
            }
            MouseArea {
              anchors.fill: parent; cursorShape: Qt.PointingHandCursor
              onClicked: if (root) root.run(["clip-copy", String(index)])
            }
          }
        }
        Column {
          visible: list.length === 0
          width: parent.width
          spacing: Style.space(8)
          topPadding: Style.space(48)
          Text {
            text: "󰅇"; font.family: Style.fontFamily; font.pixelSize: Style.font.display * 1.4
            color: Color.accent; opacity: 0.25
            anchors.horizontalCenter: parent.horizontalCenter
          }
          Text {
            text: root.t(root.uiLang, "clipboardEmpty")
            color: Qt.darker(Color.foreground, 1.5); font.pixelSize: Style.font.caption
            anchors.horizontalCenter: parent.horizontalCenter
          }
        }
      }
    }
  }
}
