import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Item {
  id: monitor
  property var root: null
  property string pluginKey: ""
  width: parent ? parent.width : 100
  implicitHeight: Style.space(550)
  focus: keyboardNavigationBlocked

  property real cpuPercent: 0
  property real ramPercent: 0
  property real memoryTotalKb: 0
  property real memoryUsedKb: 0
  property var loadAverage: [0, 0, 0]
  property int uptimeSeconds: 0
  property var processes: []
  property var cpuHistory: []
  property var ramHistory: []
  property string sortKey: "cpu"
  property bool sortDescending: true
  property int selectedIndex: 0
  property int selectedPid: processes.length ? processes[Math.max(0, Math.min(selectedIndex, processes.length - 1))].pid : -1
  property bool detailVisible: false
  property bool confirmVisible: false
  property var detailData: ({})
  property int actionChoice: 0
  property string resultMessage: ""
  property bool loading: false
  property bool pluginVisible: root && root.opened && root.activePluginItem === monitor
  property bool keyboardNavigationBlocked: filterField.activeFocus
  property string notchIcon: "󰍛"
  property string notchText: "CPU 0% · RAM 0%"

  Behavior on cpuPercent { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
  Behavior on ramPercent { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
  Shortcut {
    sequence: "Escape"
    enabled: detailVisible || confirmVisible
    onActivated: cancelOverlay()
  }

  function appendHistory(history, value) {
    var next = history.slice()
    next.push(value)
    if (next.length > 48) next.shift()
    return next
  }

  function formatMemory(kb) {
    if (kb >= 1048576) return (kb / 1048576).toFixed(1) + " GiB"
    return Math.round(kb / 1024) + " MiB"
  }

  function formatUptime(seconds) {
    var days = Math.floor(seconds / 86400)
    var hours = Math.floor((seconds % 86400) / 3600)
    var mins = Math.floor((seconds % 3600) / 60)
    return (days ? days + "d " : "") + hours + "h " + mins + "m"
  }

  function sortedRows(rows) {
    var copy = rows.slice()
    copy.sort(function(a, b) {
      var av = a[sortKey], bv = b[sortKey]
      if (sortKey === "name") {
        av = String(av).toLowerCase(); bv = String(bv).toLowerCase()
        return sortDescending ? bv.localeCompare(av) : av.localeCompare(bv)
      }
      return sortDescending ? bv - av : av - bv
    })
    return copy
  }

  function refresh() {
    if (!root || !root.opened || !pluginVisible || loading) return
    loading = true
    var keepPid = selectedPid
    root.run(["plugin-exec", pluginKey, "snapshot", sortKey, filterField.text], function(out) {
      loading = false
      try {
        var data = JSON.parse(out.trim())
        cpuPercent = data.cpuPercent || 0
        ramPercent = data.memory.percent || 0
        memoryTotalKb = data.memory.totalKb || 0
        memoryUsedKb = data.memory.usedKb || 0
        loadAverage = data.load || [0, 0, 0]
        uptimeSeconds = data.uptimeSeconds || 0
        // The backend already returns the requested ordering. Keep its first
        // response intact instead of doing a second JS sort while the card maps.
        processes = data.processes || []
        cpuHistory = appendHistory(cpuHistory, cpuPercent)
        ramHistory = appendHistory(ramHistory, ramPercent)
        cpuGraph.requestPaint(); ramGraph.requestPaint()
        selectedIndex = 0
        for (var i = 0; i < processes.length; i++) if (processes[i].pid === keepPid) { selectedIndex = i; break }
        processList.currentIndex = selectedIndex
        if (processes.length) processList.positionViewAtIndex(selectedIndex, ListView.Contain)
        notchText = "CPU " + Math.round(cpuPercent) + "% · RAM " + Math.round(ramPercent) + "%"
        if (root && pluginKey) root.updateNotchData(pluginKey, notchIcon, notchText)
      } catch (e) {
        resultMessage = "Monitor data unavailable"
      }
    })
  }

  function chooseSort(key) {
    if (sortKey === key) sortDescending = !sortDescending
    else { sortKey = key; sortDescending = key !== "name" && key !== "pid" }
    processes = sortedRows(processes)
    refresh()
  }

  function moveSelection(delta) {
    if (!processes.length) return
    selectedIndex = Math.max(0, Math.min(processes.length - 1, selectedIndex + delta))
    processList.currentIndex = selectedIndex
    processList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function openDetail(pid) {
    if (!root || pid < 0) return
    root.run(["plugin-exec", pluginKey, "detail", String(pid)], function(out) {
      try {
        detailData = JSON.parse(out.trim()); detailVisible = true; confirmVisible = false
        actionChoice = 0; resultMessage = ""
      } catch (e) { resultMessage = "Process no longer exists" }
    })
  }

  function openConfirmation(pid, choice) {
    if (pid < 0) return
    if (detailData.pid !== pid || detailData.startTicks === undefined) {
      root.run(["plugin-exec", pluginKey, "detail", String(pid)], function(out) {
        try {
          detailData = JSON.parse(out.trim())
          openConfirmation(pid, choice)
        } catch (e) { resultMessage = "Process no longer exists" }
      })
      return
    }
    detailVisible = true; confirmVisible = true; actionChoice = choice === 2 ? 2 : 1; resultMessage = ""
  }

  function cancelOverlay() {
    if (confirmVisible) { confirmVisible = false; actionChoice = 0; return true }
    if (detailVisible) { detailVisible = false; resultMessage = ""; return true }
    if (filterField.activeFocus) { filterField.focus = false; return true }
    return false
  }

  function signalProcess(signal) {
    var pid = detailData.pid || selectedPid
    if (detailData.startTicks === undefined) { resultMessage = "Process identity unavailable"; return }
    root.run(["plugin-exec", pluginKey, "kill", String(pid), String(detailData.startTicks), signal], function(out) {
      try {
        var reply = JSON.parse(out.trim())
        resultMessage = reply.ok ? (signal === "KILL" ? "Force-kill sent" : "Terminate sent") : "Action failed"
      } catch (e) { resultMessage = "Protected or unavailable process" }
      confirmVisible = false
      refreshDelay.restart()
    })
  }

  function activateChoice() {
    if (confirmVisible) {
      if (actionChoice === 0) cancelOverlay()
      else signalProcess(actionChoice === 2 ? "KILL" : "TERM")
      return
    }
    if (detailVisible) {
      if (actionChoice === 0) cancelOverlay()
      else openConfirmation(detailData.pid, actionChoice)
      return
    }
    openDetail(selectedPid)
  }

  function handleKeyboardAction(action, payload) {
    if (action === "back") return cancelOverlay()
    if (action === "move") {
      if (confirmVisible || detailVisible) {
        var maxChoice = confirmVisible ? 2 : 2
        var step = payload.dx !== 0 ? payload.dx : payload.dy
        actionChoice = Math.max(0, Math.min(maxChoice, actionChoice + (step > 0 ? 1 : -1)))
      } else if (payload.dy !== 0) moveSelection(payload.dy > 0 ? 1 : -1)
      else if (payload.dx !== 0) {
        var keys = ["pid", "name", "cpu", "ram"]
        var at = keys.indexOf(sortKey)
        chooseSort(keys[(at + (payload.dx > 0 ? 1 : -1) + keys.length) % keys.length])
      }
      return true
    }
    if (action === "activate") { activateChoice(); return true }
    if (action === "delete") { if (!detailVisible) openConfirmation(selectedPid); else openConfirmation(detailData.pid); return true }
    if (action === "text" && payload.text && !detailVisible && !confirmVisible) {
      if (payload.text.toLowerCase() === "r") { refresh(); return true }
      if (payload.text.toLowerCase() === "s") { chooseSort(sortKey); return true }
      filterField.text += payload.text
      filterField.forceActiveFocus()
      filterDelay.restart()
      return true
    }
    return false
  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    if ((event.key === Qt.Key_Escape || event.key === Qt.Key_Back) && monitor.cancelOverlay()) {
      event.accepted = true
      return
    }
    if ((detailVisible || confirmVisible) && (event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.text === "h" || event.text === "k")) {
      handleKeyboardAction("move", { dx: -1, dy: 0 }); event.accepted = true; return
    }
    if ((detailVisible || confirmVisible) && (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.text === "l" || event.text === "j")) {
      handleKeyboardAction("move", { dx: 1, dy: 0 }); event.accepted = true; return
    }
    if ((detailVisible || confirmVisible) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
      activateChoice(); event.accepted = true
    }
  }

  onPluginVisibleChanged: if (pluginVisible && root && root.opened) refresh()
  onRootChanged: if (root && root.opened && pluginVisible) refresh()
  Connections {
    target: root
    function onOpenedChanged() { if (root && root.opened && monitor.pluginVisible) monitor.refresh() }
  }
  Timer {
    id: sampleTimer
    interval: 2000
    repeat: true
    running: root && root.opened && monitor.pluginVisible
    triggeredOnStart: true
    onTriggered: monitor.refresh()
  }
  Timer { id: filterDelay; interval: 180; onTriggered: monitor.refresh() }
  Timer { id: refreshDelay; interval: 350; onTriggered: monitor.refresh() }

  Column {
    id: mainColumn
    x: Style.space(16); y: Style.space(14)
    width: parent.width - Style.space(32)
    spacing: Style.space(8)

    Row {
      width: parent.width; spacing: Style.space(8)
      Repeater {
        model: [
          { icon: "󰻠", label: "CPU", value: Math.round(cpuPercent) + "%" },
          { icon: "󰘚", label: "RAM", value: Math.round(ramPercent) + "%" },
          { icon: "󰥔", label: "UP", value: formatUptime(uptimeSeconds) }
        ]
        Rectangle {
          width: (mainColumn.width - Style.space(16)) / 3; height: Style.space(48)
          radius: Style.cornerRadius; color: Color.menu.selectedBackground
          border.color: Color.popups.border; border.width: 1
          Row {
            anchors.centerIn: parent; spacing: Style.space(7)
            Text { text: modelData.icon; font.family: Style.fontFamily; color: Color.accent; font.pixelSize: Style.font.body }
            Column {
              Text { text: modelData.label; color: Qt.darker(Color.foreground, 1.5); font.family: Style.fontFamily; font.pixelSize: Style.font.caption }
              Text { text: modelData.value; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
            }
          }
        }
      }
    }

    Row {
      width: parent.width; spacing: Style.space(8)
      Rectangle {
        width: (parent.width - Style.space(8)) / 2; height: Style.space(76); radius: Style.cornerRadius
        color: Color.menu.selectedBackground; border.color: Color.popups.border; border.width: 1
        Text { x: Style.space(8); y: Style.space(5); text: "CPU"; color: Color.accent; font.family: Style.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
        Canvas {
          id: cpuGraph; anchors.fill: parent; anchors.margins: Style.space(8); anchors.topMargin: Style.space(21)
          onPaint: {
            var ctx = getContext("2d"); ctx.reset(); if (cpuHistory.length < 2) return
            ctx.strokeStyle = Color.accent; ctx.lineWidth = 2; ctx.beginPath()
            for (var i = 0; i < cpuHistory.length; i++) {
              var x = i * width / Math.max(1, cpuHistory.length - 1), y = height * (1 - cpuHistory[i] / 100)
              if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
            }
            ctx.stroke()
          }
        }
      }
      Rectangle {
        width: (parent.width - Style.space(8)) / 2; height: Style.space(76); radius: Style.cornerRadius
        color: Color.menu.selectedBackground; border.color: Color.popups.border; border.width: 1
        Text { x: Style.space(8); y: Style.space(5); text: "RAM " + formatMemory(memoryUsedKb) + " / " + formatMemory(memoryTotalKb); color: Color.accent; font.family: Style.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
        Canvas {
          id: ramGraph; anchors.fill: parent; anchors.margins: Style.space(8); anchors.topMargin: Style.space(21)
          onPaint: {
            var ctx = getContext("2d"); ctx.reset(); if (ramHistory.length < 2) return
            ctx.strokeStyle = Color.foreground; ctx.lineWidth = 2; ctx.beginPath()
            for (var i = 0; i < ramHistory.length; i++) {
              var x = i * width / Math.max(1, ramHistory.length - 1), y = height * (1 - ramHistory[i] / 100)
              if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
            }
            ctx.stroke()
          }
        }
      }
    }

    Row {
      width: parent.width; spacing: Style.space(8)
      TextField {
        id: filterField
        width: parent.width - refreshButton.width - parent.spacing; height: Style.space(32)
        placeholderText: "Filter processes…"
        onTextEdited: filterDelay.restart()
        Keys.onEscapePressed: function(event) {
          filterField.focus = false
          event.accepted = true
        }
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { monitor.cancelOverlay(); event.accepted = true }
        }
        Rectangle { anchors.fill: parent; z: -1; radius: Style.cornerRadius; color: Color.menu.selectedBackground; border.color: filterField.activeFocus ? Color.accent : Color.popups.border; border.width: 1 }
      }
      Button {
        id: refreshButton; width: Style.space(34); height: Style.space(32); iconText: "󰑐"
        onClicked: monitor.refresh()
      }
    }

    Text {
      text: "Load " + Number(loadAverage[0] || 0).toFixed(2) + "  " + Number(loadAverage[1] || 0).toFixed(2) + "  " + Number(loadAverage[2] || 0).toFixed(2) + (resultMessage ? "   ·   " + resultMessage : "")
      color: resultMessage ? Color.accent : Qt.darker(Color.foreground, 1.5)
      font.family: Style.fontFamily
      font.pixelSize: Style.font.caption
    }

    Row {
      width: parent.width; height: Style.space(24)
      Repeater {
        model: [ { key: "pid", label: "PID", w: 0.14 }, { key: "name", label: "NAME", w: 0.47 }, { key: "cpu", label: "CPU %", w: 0.19 }, { key: "ram", label: "RAM %", w: 0.20 } ]
        Rectangle {
          width: mainColumn.width * modelData.w; height: parent.height
          color: sortKey === modelData.key ? Color.menu.selectedBackground : "transparent"
          radius: Style.cornerRadius
          Text { anchors.centerIn: parent; text: modelData.label + (sortKey === modelData.key ? (sortDescending ? " ▼" : " ▲") : ""); color: sortKey === modelData.key ? Color.accent : Qt.darker(Color.foreground, 1.5); font.family: Style.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: chooseSort(modelData.key) }
        }
      }
    }

    ListView {
      id: processList
      width: parent.width; height: Style.space(230); clip: true
      model: processes; currentIndex: selectedIndex; spacing: Style.space(2)
      delegate: Rectangle {
        width: processList.width; height: Style.space(27); radius: Style.cornerRadius
        color: index === selectedIndex ? Color.menu.selectedBackground : "transparent"
        border.color: index === selectedIndex ? Color.accent : "transparent"; border.width: index === selectedIndex ? 1 : 0
        Row {
          anchors.fill: parent
          Text { width: parent.width * 0.14; anchors.verticalCenter: parent.verticalCenter; text: modelData.pid; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.caption; horizontalAlignment: Text.AlignHCenter }
          Text { width: parent.width * 0.47; anchors.verticalCenter: parent.verticalCenter; text: modelData.name; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
          Text { width: parent.width * 0.19; anchors.verticalCenter: parent.verticalCenter; text: Number(modelData.cpu).toFixed(1); color: modelData.cpu > 50 ? Color.accent : Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.caption; horizontalAlignment: Text.AlignHCenter }
          Text { width: parent.width * 0.20; anchors.verticalCenter: parent.verticalCenter; text: Number(modelData.ram).toFixed(1); color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.caption; horizontalAlignment: Text.AlignHCenter }
        }
        MouseArea {
          anchors.fill: parent; cursorShape: Qt.PointingHandCursor
          onClicked: { selectedIndex = index; processList.currentIndex = index }
          onDoubleClicked: { selectedIndex = index; openDetail(modelData.pid) }
        }
      }
      Text { anchors.centerIn: parent; visible: processes.length === 0; text: loading ? "Sampling…" : "No matching processes"; color: Qt.darker(Color.foreground, 1.5); font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall }
    }
    Text {
      text: "↑↓ process   ←→ sort field   R refresh   S sort direction   Enter details   X signal"
      color: Color.muted
      font.family: Style.fontFamily
      font.pixelSize: Style.font.caption
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }
  }

  Rectangle {
    id: overlay
    anchors.fill: parent; z: 20
    opacity: detailVisible || confirmVisible ? 1 : 0
    visible: opacity > 0
    enabled: detailVisible || confirmVisible
    scale: detailVisible || confirmVisible ? 1 : 0.985
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    color: Color.popups.background; radius: Style.cornerRadius
    border.color: Color.popups.border; border.width: 1
    Column {
      anchors.centerIn: parent; width: parent.width - Style.space(56); spacing: Style.space(12)
      Text { text: "󰍛  " + (detailData.name || "Process") + "  ·  PID " + (detailData.pid || ""); font.family: Style.fontFamily; color: Color.foreground; font.pixelSize: Style.font.subtitle; font.bold: true; width: parent.width; elide: Text.ElideRight }
      Rectangle { width: parent.width; height: 1; color: Color.popups.border }
      Text { text: detailData.command || ""; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall; width: parent.width; wrapMode: Text.WrapAnywhere }
      Text { text: "State  " + (detailData.state || "—") + "     Memory  " + formatMemory(detailData.rssKb || 0) + "     Threads  " + (detailData.threads || "—") + "     UID  " + (detailData.uid === undefined ? "—" : detailData.uid); color: Qt.darker(Color.foreground, 1.5); font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall }
      Row {
        anchors.horizontalCenter: parent.horizontalCenter; spacing: Style.space(8)
        Repeater {
          model: [ { label: "Back", icon: "󰁍" }, { label: "Terminate", icon: "󰩹" }, { label: "Force kill", icon: "󰆴" } ]
          Rectangle {
            width: Style.space(105); height: Style.space(34); radius: Style.cornerRadius
            color: actionChoice === index ? Color.menu.selectedBackground : "transparent"
            border.color: actionChoice === index ? Color.accent : Color.popups.border; border.width: 1
            Text { anchors.centerIn: parent; text: modelData.icon + " " + modelData.label; font.family: Style.fontFamily; color: actionChoice === index ? Color.accent : Color.foreground; font.pixelSize: Style.font.caption }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { actionChoice = index; if (index === 0) cancelOverlay(); else openConfirmation(detailData.pid, actionChoice) } }
          }
        }
      }
      Text { visible: resultMessage !== ""; text: resultMessage; color: Color.accent; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall; anchors.horizontalCenter: parent.horizontalCenter }
    }

    Rectangle {
      anchors.fill: parent; anchors.margins: Style.space(36); z: 2
      opacity: confirmVisible ? 1 : 0
      visible: opacity > 0
      enabled: confirmVisible
      scale: confirmVisible ? 1 : 0.94
      Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 190; easing.type: Easing.OutBack } }
      radius: Style.cornerRadius; color: Color.popups.background; border.color: Color.accent; border.width: 1
      Column {
        anchors.centerIn: parent; spacing: Style.space(14)
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Signal " + (detailData.name || "process") + " (PID " + detailData.pid + ")?"; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: actionChoice === 2 ? "Force kill cannot be handled or cleaned up." : "Terminate lets the process shut down cleanly."; color: Qt.darker(Color.foreground, 1.5); font.family: Style.fontFamily; font.pixelSize: Style.font.caption }
        Row {
          anchors.horizontalCenter: parent.horizontalCenter; spacing: Style.space(8)
          Repeater {
            model: [ "Cancel", "Terminate", "Force kill" ]
            Rectangle {
              width: Style.space(96); height: Style.space(34); radius: Style.cornerRadius
              color: actionChoice === index ? Color.menu.selectedBackground : "transparent"
              border.color: actionChoice === index ? Color.accent : Color.popups.border; border.width: 1
              Text { anchors.centerIn: parent; text: modelData; color: actionChoice === index ? Color.accent : Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.caption; font.bold: actionChoice === index }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { actionChoice = index; activateChoice() } }
            }
          }
        }
      }
    }
  }
}
