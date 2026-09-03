import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// SuperNotch plugin: Weather — UI based on Omarchy's default weather panel.
// Hero: big condition icon + temperature; right: location + FEELS/WIND/HUMID
// stats; divider; 3-day forecast row.
// Data: wttr.in via the helper (reads Omarchy's weather.json for location).
// Icons: Model.iconForCode / Model.dayIcon from Omarchy's Model.js (Nerd Font).
Item {
  id: m
  property var root: null
  property string pluginKey: ""
  width: parent ? parent.width : 100
  implicitHeight: weatherColumn.implicitHeight + Style.space(32)

  function dayName(dateStr) { return Model.dayName(dateStr) }

  function load() {
    if (!root) return
    root.run(["weather-state"], function (out) {
      var lat = "", lon = "", name = ""
      try {
        var j = JSON.parse((out || "").trim())
        if (typeof j.latitude === "number") lat = j.latitude
        if (typeof j.longitude === "number") lon = j.longitude
        if (j.name) name = String(j.name)
      } catch (e) {}
      m.city = name
      if (lat !== "" && lon !== "") m.query = lat + "," + lon
      else m.query = name ? name + ",Chile" : "Santiago,Chile"
      fetchWeather()
    })
  }
  function fetchWeather() {
    if (!root) return
    root.run(["weather-fetch", m.query], function (out) {
      try {
        var d = JSON.parse((out || "").trim())
        var cur = d.current_condition[0]
        var h = new Date().getHours()
        var isNight = (h < 7 || h >= 19)
        m.temp = (cur.temp_C !== undefined) ? cur.temp_C : ""
        m.feels = (cur.FeelsLikeC !== undefined) ? cur.FeelsLikeC + "°" : ""
        m.code = cur.weatherCode
        m.cond = cur.weatherDesc ? cur.weatherDesc[0].value : ""
        m.humidity = cur.humidity || ""
        m.wind = cur.windspeedKmph || ""
        m.icon = Model.iconForCode(m.code, isNight)
        var today = d.weather && d.weather[0]
        if (today) { m.maxC = today.maxtempC; m.minC = today.mintempC }
        var fc = []
        for (var i = 1; i < Math.min(4, d.weather.length); i++) {
          var day = d.weather[i]
          fc.push({
            date: day.date,
            icon: Model.dayIcon(day),
            maxC: day.maxtempC, minC: day.mintempC
          })
        }
        m.forecast = fc
      } catch (e) {}
      pushNotch()
    })
  }
  function pushNotch() {
    m.notchIcon = m.icon || ""
    m.notchText = (m.temp ? m.temp + "° " : "") + (m.city || "")
    if (root && root.updateNotchData) root.updateNotchData(pluginKey, m.notchIcon, m.notchText)
  }
  Component.onCompleted: if (root) load()
  onRootChanged: if (root) load()
  Connections { target: root; function onOpenedChanged() { if (root && root.opened) load() } }
  Timer { interval: 600000; running: root ? root.opened : false; repeat: true; onTriggered: load() }

  property string city: ""
  property string icon: ""
  property string temp: ""
  property string feels: ""
  property string cond: ""
  property string humidity: ""
  property string wind: ""
  property string code: ""
  property string maxC: ""
  property string minC: ""
  property var forecast: []
  property string query: "Santiago,Chile"

  property string notchIcon: icon
  property string notchText: (temp ? temp + "° " : "") + (city || "")
  onNotchIconChanged: if (root && root.updateNotchData) root.updateNotchData(pluginKey, notchIcon, notchText)
  onNotchTextChanged: if (root && root.updateNotchData) root.updateNotchData(pluginKey, notchIcon, notchText)

  // ── UI (mirrors Omarchy weather Panel.qml) ──
  Column {
    id: weatherColumn
    x: Style.space(16); y: Style.space(16)
    width: parent.width - Style.space(32)
    spacing: Style.space(14)

    // Hero: big icon + temp left; location + stats right.
    Item {
      width: parent.width
      height: Math.max(heroLeft.height, heroRight.height)

      Row {
        id: heroLeft
        anchors.left: parent.left
        anchors.leftMargin: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(16)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: 5
          text: m.icon || "—"
          color: Color.foreground
          font.family: Style.fontFamily
          font.pixelSize: 64
        }
        Row {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)
          Text {
            id: tempBig
            text: m.temp || "—"
            color: Color.foreground
            font.family: Style.fontFamily
            font.pixelSize: 56
            font.bold: true
          }
          Text {
            text: m.temp !== "" ? "°C" : ""
            color: Color.foreground
            font.family: Style.fontFamily
            font.pixelSize: Style.font.display
            anchors.top: tempBig.top
            anchors.topMargin: Style.space(10)
          }
        }
      }

      Column {
        id: heroRight
        width: weatherStats.implicitWidth
        anchors.right: parent.right
        anchors.rightMargin: Style.space(20)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(12)

        // Location row
        Row {
          visible: m.city !== ""
          spacing: Style.space(6)
          Text {
            text: ""
            color: Qt.darker(Color.foreground, 1.4)
            font.family: Style.fontFamily
            font.pixelSize: Style.font.body
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: (m.city || "").toUpperCase()
            color: Qt.darker(Color.foreground, 1.4)
            font.family: Style.fontFamily
            font.pixelSize: Style.font.body
            font.letterSpacing: 1
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // Stats row: FEELS / WIND / HUMID
        Row {
          id: weatherStats
          visible: m.temp !== ""
          spacing: Style.space(36)
          Column {
            spacing: Style.space(5)
            Text { text: "FEELS"; color: Qt.darker(Color.foreground, 1.5); font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall; font.letterSpacing: 1 }
            Text { text: m.feels; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.title }
          }
          Column {
            spacing: Style.space(5)
            Text { text: "WIND"; color: Qt.darker(Color.foreground, 1.5); font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall; font.letterSpacing: 1 }
            Text { text: m.wind ? m.wind + " km/h" : ""; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.title }
          }
          Column {
            spacing: Style.space(5)
            Text { text: "HUMID"; color: Qt.darker(Color.foreground, 1.5); font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall; font.letterSpacing: 1 }
            Text { text: m.humidity ? m.humidity + "%" : ""; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.title }
          }
        }
      }
    }

    // "Fetching…" hint
    Text {
      visible: m.temp === ""
      text: "Fetching forecast…"
      color: Qt.darker(Color.foreground, 1.5)
      font.family: Style.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.italic: true
    }

    // Divider
    Rectangle {
      visible: m.forecast.length > 0
      width: parent.width
      height: Style.spacing.hairline
      color: Color.foreground
      opacity: 0.12
    }

    // Forecast row: 3 cells, each icon + day-name + hi/lo.
    Item {
      visible: m.forecast.length > 0
      width: parent.width
      height: forecastRow.height
      Row {
        id: forecastRow
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(44)
        Repeater {
          model: m.forecast
          Row {
            required property var modelData
            spacing: Style.space(10)
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.icon
              color: Color.foreground
              font.family: Style.fontFamily
              font.pixelSize: Style.font.display
            }
            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              Text {
                text: m.dayName(modelData.date).toUpperCase()
                color: Qt.darker(Color.foreground, 1.4)
                font.family: Style.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
              }
              Row {
                spacing: Style.space(6)
                Text { text: modelData.maxC !== undefined ? modelData.maxC + "°" : ""; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.body }
                Text { text: modelData.minC !== undefined ? modelData.minC + "°" : ""; color: Qt.darker(Color.foreground, 1.5); font.family: Style.fontFamily; font.pixelSize: Style.font.body }
              }
            }
          }
        }
      }
    }
  }
}
