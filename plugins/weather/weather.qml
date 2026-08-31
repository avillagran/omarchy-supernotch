import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// SuperNotch plugin: Weather — Apple/Xiaomi style.
// Large condition icon + big temperature + city + condition text.
// Data from Omarchy's weather helpers (weather-status/icon/location),
// which pull from wttr.in (no API key needed).
Item {
  id: m
  property var root: null
  property string pluginKey: ""
  width: parent ? parent.width : 100
  implicitHeight: row.implicitHeight + Style.space(32)

  function load() {
    if (!root) return
    root.run(["weather-location"], function (loc) {
      m.city = (loc || "").trim()
      pushNotch()
    })
    root.run(["weather-icon"], function (ic) {
      m.icon = (ic || "").trim()
      pushNotch()
    })
    root.run(["weather-status"], function (out) {
      var s = (out || "").trim()
      m.status = s
      var mtemp = s.match(/Temp\s*([+-]?\d+°C)/)
      m.temp = mtemp ? mtemp[1] : ""
      var parts = s.split("·")
      m.cond = parts.length > 1 ? parts[1].replace(/Temp.*/, "").trim() : ""
      pushNotch()
    })
  }
  function pushNotch() {
    m.notchIcon = m.icon || ""
    m.notchText = (m.temp ? m.temp + " " : "") + (m.city || "")
    if (root && root.updateNotchData) root.updateNotchData(pluginKey, m.notchIcon, m.notchText)
  }
  Component.onCompleted: if (root) load()
  onRootChanged: if (root) load()
  Connections { target: root; function onOpenedChanged() { if (root && root.opened) load() } }
  Timer { interval: 600000; running: root ? root.opened : false; repeat: true; onTriggered: load() }

  property string city: ""
  property string icon: ""
  property string temp: ""
  property string cond: ""
  property string status: ""

  // Notch pill mini-status: weather icon + temperature + city.
  property string notchIcon: icon
  property string notchText: (temp ? temp + " " : "") + (city || "")
  onNotchIconChanged: if (root && root.updateNotchData) root.updateNotchData(pluginKey, notchIcon, notchText)
  onNotchTextChanged: if (root && root.updateNotchData) root.updateNotchData(pluginKey, notchIcon, notchText)

  Row {
    id: row
    x: Style.space(16); y: Style.space(16)
    width: parent.width - Style.space(32)
    height: implicitHeight
    spacing: Style.space(20)
    anchors.centerIn: undefined

    Text {
      id: wIcon
      text: m.icon || ""
      font.pixelSize: Style.font.displayLarge
      font.family: "Symbols Nerd Font"
      color: Color.foreground
      anchors.verticalCenter: parent.verticalCenter
    }
    Column {
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      Text {
        id: wTemp
        text: m.temp || "--°"
        color: Color.foreground
        font.pixelSize: Style.font.displayLarge
        font.bold: true
        font.family: "Inter"
      }
      Text {
        id: wCity
        text: (m.city ? m.city + "  ·  " : "") + (m.cond || "")
        color: Color.foreground
        font.pixelSize: Style.font.body
      }
    }
  }
}
