import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// SuperNotch plugin: Clock — Apple-style large time + full date.
// Time updates every second via a local Timer (no network needed).
Item {
  id: m
  property var root: null
  property string pluginKey: ""
  width: parent ? parent.width : 100
  implicitHeight: col.implicitHeight + Style.space(32)

  function fmt(t, lang) {
    // t = Date(); return [timeStr, dateStr] in es/en
    var h = t.getHours(), m = t.getMinutes()
    var hh = (h < 10 ? "0" : "") + h
    var mm = (m < 10 ? "0" : "") + m
    var timeStr = hh + ":" + mm
    var days = lang === "es"
      ? ["domingo","lunes","martes","miércoles","jueves","viernes","sábado"]
      : ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
    var months = lang === "es"
      ? ["ene","feb","mar","abr","may","jun","jul","ago","sep","oct","nov","dic"]
      : ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
    var dateStr = days[t.getDay()] + " " + t.getDate() + " " + months[t.getMonth()]
    return [timeStr, dateStr]
  }

  property var now: new Date()
  function tick() {
    m.now = new Date()
    m.pushNotch()
  }
  Timer { id: clk; interval: 1000; running: true; repeat: true; onTriggered: tick() }

  // Notch pill mini-status: show the time, rotating with the date (ticker).
  property bool showDate: false
  Timer { id: flip; interval: 2000; running: true; repeat: true; onTriggered: { m.showDate = !m.showDate; m.pushNotch() } }
  property string notchIcon: "󰥔"
  property string notchText: (function () {
    var f = m.fmt(m.now, (root ? root.uiLang : "en"))
    return m.showDate ? f[1] : f[0]
  })()
  onNotchTextChanged: if (root && pluginKey) root.updateNotchData(pluginKey, notchIcon, notchText)
  function pushNotch() {
    var f = m.fmt(m.now, (root ? root.uiLang : "en"))
    m.notchText = m.showDate ? f[1] : f[0]
    if (root && pluginKey) root.updateNotchData(pluginKey, notchIcon, notchText)
  }
  Component.onCompleted: { tick(); m.pushNotch() }

  Column {
    id: col
    x: Style.space(16); y: Style.space(16)
    width: parent.width - Style.space(32)
    spacing: Style.space(10)
    padding: Style.space(8)

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: fmt(m.now, (root ? root.uiLang : "en"))[0]
      color: Color.foreground
      font.pixelSize: Style.font.displayLarge
      font.bold: true
      font.family: "Inter"
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: fmt(m.now, (root ? root.uiLang : "en"))[1]
      color: Color.foreground
      font.pixelSize: Style.font.title
    }
  }
}
