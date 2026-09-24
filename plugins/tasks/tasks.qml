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
  property int selectedIndex: -1
  property bool pluginVisible: root && root.opened && root.activePluginItem === m
  property bool keyboardNavigationBlocked: taskInput.activeFocus

  function selectedTask() {
    return selectedIndex >= 0 && selectedIndex < list.length ? list[selectedIndex] : null
  }
  function moveTaskSelection(delta) {
    if (!list.length) return
    selectedIndex = (selectedIndex + delta + list.length) % list.length
    taskList.contentY = Math.max(0, Math.min(Math.max(0, taskList.contentHeight - taskList.height), selectedIndex * Style.space(34)))
  }
  function toggleSelectedTask() {
    var task = selectedTask()
    if (!task || !root) return
    root.run([task.done ? "tasks-untoggle" : "tasks-toggle", String(selectedIndex)], function () { m.load() })
  }
  function addTask() {
    var value = taskInput.text.trim()
    if (!value || !root) return
    root.run(["tasks-add", value], function () {
      m.load()
      taskInput.text = ""
      taskInput.forceActiveFocus()
    })
  }
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
  onPluginVisibleChanged: if (pluginVisible) Qt.callLater(function () { taskInput.forceActiveFocus() })

  Column {
    id: mainCol
    x: Style.space(16); y: Style.space(16)
    width: parent.width - Style.space(32)
    spacing: Style.space(8)

    TextField {
      id: taskInput
      width: parent.width; height: Style.space(34)
      placeholderText: root ? root.t(root.uiLang, "newTask") : "New task"
      Rectangle { anchors.fill: parent; radius: Style.space(8); color: Color.menu.selectedBackground; border.color: Color.popups.border; border.width: 1 }
      onAccepted: m.addTask()
      Keys.onPressed: function(event) {
        // TextField owns Escape while focused; return it to the panel close action.
        if (event.key === Qt.Key_Escape) {
          if (root && root.close) root.close()
          event.accepted = true
        } else if (event.key === Qt.Key_Down && taskInput.text.length === 0) {
          m.moveTaskSelection(1); event.accepted = true
        } else if (event.key === Qt.Key_Up && taskInput.text.length === 0) {
          m.moveTaskSelection(-1); event.accepted = true
        } else if (event.key === Qt.Key_Space && taskInput.text.length === 0 && m.selectedTask()) {
          m.toggleSelectedTask(); event.accepted = true
        }
      }
    }

    Text {
      text: (root ? root.t(root.uiLang, "tasksLeft") : "%1 left").replace("%1", String(list.filter(function (x){ return !x.done }).length))
      color: Qt.darker(Color.foreground, 1.5); font.pixelSize: Style.font.bodySmall
    }

    Flickable {
      id: taskList
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
              color: modelData.done ? Color.accent : (index === m.selectedIndex ? Color.menu.selectedBackground : "transparent")
              border.color: Color.popups.border; border.width: 1
              Text { anchors.centerIn: parent; text: modelData.done ? "󰄳" : ""; color: Color.background; font.family: Style.fontFamily; font.bold: true; font.pixelSize: Style.font.bodySmall }
              MouseArea { anchors.fill: parent; onClicked: { m.selectedIndex = index; if (root) root.run([modelData.done ? "tasks-untoggle" : "tasks-toggle", String(index)], function(){ load() }) } }
            }
            Text {
              text: modelData.text
              color: modelData.done ? Qt.darker(Color.foreground, 1.5) : Color.foreground
              font.pixelSize: Style.font.body; font.strikeout: modelData.done
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(70); elide: Text.ElideRight
            }
            Button { text: "󰅖"; iconText: "󰅖"; foreground: Qt.darker(Color.foreground, 1.5); width: Style.space(24); height: Style.space(24); onClicked: if (root) root.run(["tasks-del", String(index)], function(){ load() }) }
          }
        }
        Text { visible: m.list.length === 0; text: root ? root.t(root.uiLang, "tasksEmpty") : ""; color: Qt.darker(Color.foreground, 1.5); font.pixelSize: Style.font.body }
      }
    }
  }
}
