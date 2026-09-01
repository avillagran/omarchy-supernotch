import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// SuperNotch plugin: Tasks. Receives `root` (the Panel) for root.run()/root.t().
Item {
  id: m
  property var root: null
  property string pluginKey: ""
  width: parent ? parent.width : 100
  implicitHeight: mainCol.implicitHeight + Style.space(32)

  function load() {
    if (!root) return
    root.run(["tasks-get"], function (out) {
      try { m.list = JSON.parse(out.trim()) } catch (e) {}
    })
  }
  Component.onCompleted: if (root) load()
  onRootChanged: if (root) load()
  Connections { target: root; function onOpenedChanged() { if (root && root.opened) load() } }

  property var list: []
  function pushNotch() {
    var left = m.list.filter(function (x) { return !x.done }).length
    m.notchText = left + " pendientes"
    if (root && pluginKey) root.updateNotchData(pluginKey, m.notchIcon, m.notchText)
  }
  // Notch pill mini-status: pending task count.
  property string notchIcon: "󰄳"
  property string notchText: "0 pendientes"
  onListChanged: pushNotch()
  onNotchTextChanged: if (root && pluginKey) root.updateNotchData(pluginKey, notchIcon, notchText)

  Column {
    id: mainCol
    x: Style.space(16); y: Style.space(16)
    width: parent.width - Style.space(32)
    spacing: Style.space(8)

    TextField {
      width: parent.width; height: Style.space(34)
      placeholderText: root ? root.t(root.uiLang, "newTask") : "New task"
      Rectangle { anchors.fill: parent; radius: Style.space(8); color: Color.menu.selectedBackground; border.color: Color.popups.border; border.width: 1 }
      onAccepted: { if (root) root.run(["tasks-add", text], function(){ load() }); text = "" }
    }

    Text {
      text: (root ? root.t(root.uiLang, "tasksLeft") : "%1 left").replace("%1", String(list.filter(function (x){ return !x.done }).length))
      color: Color.muted; font.pixelSize: Style.font.bodySmall
    }

    Flickable {
      width: parent.width; height: Math.min(360, col.implicitHeight)
      contentHeight: col.implicitHeight; clip: true
      Column {
        id: col; spacing: Style.space(4); width: parent.width
        Repeater {
          model: m.list
          Row {
            spacing: Style.space(8); width: parent.width; height: Style.space(30)
            Rectangle {
              width: Style.space(22); height: Style.space(22); radius: Style.space(11)
              anchors.verticalCenter: parent.verticalCenter
              color: modelData.done ? Color.accent : "transparent"
              border.color: Color.popups.border; border.width: 1
              Text { anchors.centerIn: parent; text: modelData.done ? "󰄳" : ""; color: Color.background; font.family: Style.fontFamily; font.bold: true; font.pixelSize: Style.font.bodySmall }
              MouseArea { anchors.fill: parent; onClicked: if (root) root.run([modelData.done ? "tasks-untoggle" : "tasks-toggle", String(index)], function(){ load() }) }
            }
            Text {
              text: modelData.text
              color: modelData.done ? Color.muted : Color.foreground
              font.pixelSize: Style.font.body; font.strikeout: modelData.done
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(70); elide: Text.ElideRight
            }
            Button { text: "✕"; iconText: "✕"; foreground: Color.muted; width: Style.space(24); height: Style.space(24); onClicked: if (root) root.run(["tasks-del", String(index)], function(){ load() }) }
          }
        }
        Text { visible: m.list.length === 0; text: root ? root.t(root.uiLang, "tasksEmpty") : ""; color: Color.muted; font.pixelSize: Style.font.body }
      }
    }
  }
}
