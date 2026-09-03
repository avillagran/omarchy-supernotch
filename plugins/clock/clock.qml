import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// SuperNotch plugin: Clock — calendar panel based on Omarchy's default clock.
// Hero date + year progress + month grid with ISO week numbers + month nav.
Item {
  id: m
  property var root: null
  property string pluginKey: ""
  width: parent ? parent.width : 100
  implicitHeight: calendarColumn.implicitHeight + Style.space(32)

  // ---- Today. SystemClock keeps this honest across midnight. ----
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)

  // Month on screen. Stepping moves only this.
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()
  readonly property date viewDate: new Date(viewYear, viewMonth, 1)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

  readonly property int weekStart: Model.normalizedWeekStart(null, Qt.locale().firstDayOfWeek)
  readonly property var labelLocale: Qt.locale("en_US")
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey)

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(34)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)

  function weekdayLabel(weekday) {
    return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase()
  }
  function goToToday() { viewYear = today.getFullYear(); viewMonth = today.getMonth() }
  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    viewYear = next.year; viewMonth = next.month
  }
  function moveYear(delta) { moveMonth(delta * 12) }

  // ── World clocks: local capital + user-added cities ──
  // Data comes from the helper: `worldclock-list` prints JSON
  // [{name, tz, time, local}] — local first (system timezone).
  property var worldClocks: []
  property bool editingClocks: false
  property var zoneMatches: []

  function loadClocks() {
    if (!root) return
    root.run(["worldclock-list"], function (out) {
      try { m.worldClocks = JSON.parse(out.trim()) } catch (e) {}
    })
  }
  function searchZones(q) {
    if (!root) return
    if (!q) { m.zoneMatches = []; return }
    root.run(["worldclock-zones", q], function (out) {
      var lines = (out || "").trim().split("\n").filter(function (s) { return s.length > 0 })
      m.zoneMatches = lines.slice(0, 8)
    })
  }
  function addClock(tz) {
    if (!root) return
    root.run(["worldclock-add", tz], function () { m.zoneMatches = []; m.loadClocks() })
  }
  function removeClock(tz) {
    if (!root) return
    root.run(["worldclock-del", tz], function () { m.loadClocks() })
  }
  Component.onCompleted: if (root) { loadClocks(); pushNotch() }
  onRootChanged: if (root) loadClocks()
  Connections { target: root; function onOpenedChanged() { if (root && root.opened) loadClocks() } }
  Timer { interval: 30000; running: root ? root.opened : false; repeat: true; onTriggered: loadClocks() }

  // Notch pill mini-status: time, alternating with date.
  property var now: new Date()
  property bool showDate: false
  Timer { interval: 1000; running: true; repeat: true; onTriggered: { m.now = new Date(); m.pushNotch() } }
  Timer { id: flip; interval: 2000; running: true; repeat: true; onTriggered: { m.showDate = !m.showDate; m.pushNotch() } }

  property string notchIcon: ""
  property string notchText: {
    var lang = root ? root.uiLang : "en"
    var d = m.now
    var hh = (d.getHours() < 10 ? "0" : "") + d.getHours()
    var mm = (d.getMinutes() < 10 ? "0" : "") + d.getMinutes()
    var timeStr = hh + ":" + mm
    if (m.showDate) {
      if (lang === "es") {
        var days = ["dom","lun","mar","mié","jue","vie","sáb"]
        return days[d.getDay()] + " " + d.getDate()
      }
      return Qt.formatDate(d, "ddd d")
    }
    return timeStr
  }
  onNotchTextChanged: pushNotch()
  function pushNotch() {
    if (root && pluginKey) root.updateNotchData(pluginKey, notchIcon, notchText)
  }

  SystemClock {
    precision: SystemClock.Minutes
    onDateChanged: {
      if (Model.keyForDate(date) === String(m.todayKey)) return
      var follow = m.viewingCurrentMonth
      m.today = date
      if (follow) m.goToToday()
    }
  }

  // ── UI (mirrors Omarchy clock Panel.qml) ──
  Flickable {
    id: calendarScroll
    anchors.fill: parent
    anchors.margins: Style.space(16)
    contentWidth: calendarColumn.width
    contentHeight: calendarColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height || contentWidth > width

    Column {
      id: calendarColumn
      width: Math.max(calendarScroll.width, gridColumn.width)
      spacing: Style.space(8)

      // Hero: today, centered.
      Item {
        width: parent.width
        height: heroRow.height
        Row {
          id: heroRow
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(22)
          Text {
            anchors.baseline: heroDate.baseline
            text: ""
            color: heroMouse.containsMouse
              ? Style.hoverStateColor(Color.foreground, Color.accent)
              : Color.foreground
            font.family: Style.fontFamily
            font.pixelSize: 48
          }
          Text {
            id: heroDate
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDate(m.today, "MMMM d")
            color: heroMouse.containsMouse
              ? Style.hoverStateColor(Color.foreground, Color.accent)
              : Color.foreground
            font.family: Style.fontFamily
            font.pixelSize: 52
            font.bold: true
          }
        }
        MouseArea {
          id: heroMouse
          x: heroRow.x; y: heroRow.y
          width: heroRow.width; height: heroRow.height
          enabled: !m.viewingCurrentMonth
          hoverEnabled: enabled
          cursorShape: Qt.PointingHandCursor
          onClicked: m.goToToday()
        }
      }

      // ── World clocks row: local capital + added cities ──
      Item {
        width: parent.width
        height: worldClockCol.height
        Column {
          id: worldClockCol
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(8)

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(30)

            Repeater {
              model: m.worldClocks
              Column {
                required property var modelData
                spacing: Style.space(2)

                Item {
                  width: cityTime.implicitWidth
                  height: cityTime.implicitHeight
                  anchors.horizontalCenter: parent.horizontalCenter

                  Text {
                    id: cityTime
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.time
                    color: modelData.local ? Color.accent : Color.foreground
                    font.family: Style.fontFamily
                    font.pixelSize: Style.font.display
                    font.bold: modelData.local
                  }

                  // remove button (hover, non-local only)
                  Text {
                    anchors.left: cityTime.right
                    anchors.leftMargin: Style.space(4)
                    anchors.verticalCenter: cityTime.verticalCenter
                    text: "×"
                    visible: !modelData.local && clockHover.containsMouse
                    color: Style.hoverStateColor(Color.foreground, Color.accent)
                    font.family: Style.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    MouseArea {
                      anchors.fill: parent
                      anchors.margins: -Style.space(4)
                      onClicked: m.removeClock(modelData.tz)
                    }
                  }

                  MouseArea {
                    id: clockHover
                    anchors.fill: parent
                    hoverEnabled: true
                  }
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: modelData.name.toUpperCase()
                  color: Qt.darker(Color.foreground, 1.5)
                  font.family: Style.fontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                }
              }
            }

            // "+" add-city chip
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "+"
              color: addMouse.containsMouse ? Style.hoverStateColor(Color.foreground, Color.accent) : Qt.darker(Color.foreground, 1.5)
              font.family: Style.fontFamily
              font.pixelSize: Style.font.title
              MouseArea {
                id: addMouse
                anchors.fill: parent
                anchors.margins: -Style.space(6)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { m.editingClocks = !m.editingClocks; if (!m.editingClocks) m.zoneMatches = [] }
              }
            }
          }

          // inline add-city editor
          Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(4)
            visible: m.editingClocks

            TextField {
              id: zoneField
              width: Style.space(240)
              height: Style.space(30)
              placeholderText: root ? root.t(root.uiLang, "addCity") : "Add city"
              Rectangle { anchors.fill: parent; radius: Style.space(8); color: Color.menu.selectedBackground; border.color: Color.popups.border; border.width: 1 }
              onTextChanged: m.searchZones(text.trim())
            }

            Flow {
              anchors.horizontalCenter: parent.horizontalCenter
              width: Style.space(360)
              spacing: Style.space(6)
              Repeater {
                model: m.zoneMatches
                Text {
                  required property var modelData
                  padding: Style.space(6)
                  text: modelData
                  color: zoneMouse.containsMouse ? Style.hoverStateColor(Color.foreground, Color.accent) : Qt.darker(Color.foreground, 1.4)
                  font.family: Style.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  Rectangle { anchors.fill: parent; radius: Style.space(6); color: Color.menu.selectedBackground; border.color: Color.popups.border; border.width: 1 }
                  MouseArea {
                    id: zoneMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { m.addClock(modelData); zoneField.text = "" }
                  }
                }
              }
            }
          }
        }
      }

      // Year progress rail
      Item {
        width: parent.width
        height: yearBlock.y + yearBlock.height
        Item {
          id: yearBlock
          y: Style.space(6)
          anchors.horizontalCenter: parent.horizontalCenter
          width: gridColumn.width
          height: Math.max(yearLabel.implicitHeight, Style.space(10))
          Text {
            id: yearLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: m.today.getFullYear()
            color: Qt.darker(Color.foreground, 1.5)
            font.family: Style.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.letterSpacing: 1
          }
          Text {
            id: yearPercent
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: m.yearDonePercent + "%"
            color: Color.foreground
            font.family: Style.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Rectangle {
            id: yearTrack
            anchors.left: yearLabel.right
            anchors.right: yearPercent.left
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(6)
            radius: Style.cornerRadius > 0 ? height / 2 : 0
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
            Rectangle {
              width: Math.round(parent.width * m.yearDone)
              height: parent.height
              radius: parent.radius
              color: Style.selectedStateColor(Color.foreground, Color.accent)
              Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }
          }
        }
      }

      // Month grid: week numbers left, then 7 day columns. Always 6 rows.
      Item {
        width: parent.width
        height: gridColumn.y + gridColumn.height
        WheelHandler {
          onWheel: function(event) {
            if (event.angleDelta.y === 0) return
            m.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
          }
        }
        Column {
          id: gridColumn
          y: Style.space(18)
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(3)
          Row {
            id: headerRow
            spacing: m.cellSpacing
            Item { width: m.weekColumnWidth; height: Style.space(16) }
            Item { width: m.gutterWidth; height: Style.space(16) }
            Repeater {
              model: m.weekdays
              Text {
                required property var modelData
                width: m.cellWidth; height: Style.space(16)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: m.weekdayLabel(modelData)
                color: Qt.darker(Color.foreground, 1.5)
                font.family: Style.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
                font.bold: true
              }
            }
          }
          Repeater {
            model: m.weeks
            Row {
              required property var modelData
              spacing: m.cellSpacing
              Text {
                width: m.weekColumnWidth; height: m.cellHeight
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: modelData.week
                color: Qt.darker(Color.foreground, 1.9)
                font.family: Style.fontFamily
                font.pixelSize: Style.font.caption
              }
              Item { width: m.gutterWidth; height: m.cellHeight }
              Repeater {
                model: modelData.days
                Rectangle {
                  required property var modelData
                  width: m.cellWidth; height: m.cellHeight
                  radius: Style.cornerRadius
                  color: "transparent"
                  border.width: modelData.today ? Style.spacing.hairline : 0
                  border.color: Style.normalBorderFor(Color.foreground, Color.accent)
                  Text {
                    anchors.centerIn: parent
                    text: modelData.day
                    color: modelData.inMonth
                      ? (modelData.weekend ? Qt.darker(Color.foreground, 1.45) : Color.foreground)
                      : Qt.darker(Color.foreground, 2.2)
                    font.family: Style.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: modelData.today
                  }
                }
              }
            }
          }
        }
        // Hairline down the week-number gutter
        Rectangle {
          x: gridColumn.x + m.weekColumnWidth + m.cellSpacing + Math.round((m.gutterWidth - width) / 2)
          y: gridColumn.y + headerRow.height + gridColumn.spacing
          width: Style.spacing.hairline
          height: gridColumn.height - headerRow.height - gridColumn.spacing
          color: Color.foreground
          opacity: 0.1
        }
      }

      // Month stepping
      Item {
        width: parent.width
        height: monthNav.height
        Item {
          id: monthNav
          anchors.horizontalCenter: parent.horizontalCenter
          width: gridColumn.width
          height: monthLabel.implicitHeight + Style.space(10)
          Text {
            id: monthLabel
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(130)
            horizontalAlignment: Text.AlignHCenter
            text: Qt.formatDate(m.viewDate, "MMMM yyyy").toUpperCase()
            color: Qt.darker(Color.foreground, 1.4)
            font.family: Style.fontFamily
            font.pixelSize: Style.font.body
            font.letterSpacing: 1
          }
          Text {
            anchors.left: parent.left
            anchors.leftMargin: -Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: prevMonthMouse.containsMouse
              ? Style.hoverStateColor(Color.foreground, Color.accent)
              : Qt.darker(Color.foreground, 1.5)
            font.family: Style.fontFamily
            font.pixelSize: Style.font.title
            MouseArea {
              id: prevMonthMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: m.moveMonth(-1)
            }
          }
          Text {
            anchors.right: parent.right
            anchors.rightMargin: -Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: nextMonthMouse.containsMouse
              ? Style.hoverStateColor(Color.foreground, Color.accent)
              : Qt.darker(Color.foreground, 1.5)
            font.family: Style.fontFamily
            font.pixelSize: Style.font.title
            MouseArea {
              id: nextMonthMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: m.moveMonth(1)
            }
          }
        }
      }
    }
  }
}
