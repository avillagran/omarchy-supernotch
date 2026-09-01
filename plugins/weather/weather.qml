import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// SuperNotch plugin: Weather — Apple/Xiaomi style.
// Large condition icon + big temperature + city + condition text.
//
// Data source: Omarchy's REAL weather state (~/.local/state/omarchy/settings/
// weather.json) which holds the user's configured location as name + latitude/
// longitude. We query wttr.in with those COORDINATES (not the bare city name,
// which wttr.in resolves to the wrong place — e.g. "Castro" → a hot sunny
// Castro instead of the user's actual cold/rainy one). This guarantees the
// temperature and icon reflect the real local weather. Celsius is used.
Item {
  id: m
  property var root: null
  property string pluginKey: ""
  width: parent ? parent.width : 100
  implicitHeight: row.implicitHeight + Style.space(32)

  // ── wttr.in weatherCode → nerd-font glyph (mirrors Omarchy's Model.js) ──
  function glyphForCode(code, night) {
    var c = parseInt(String(code || "0"), 10)
    switch (c) {
      case 113: return night ? "" : ""
      case 116: return night ? "" : ""
      case 119: case 122: return ""
      case 143: case 248: case 260: return night ? "" : ""
      case 176: case 263: case 353: return night ? "" : ""
      case 179: case 227: case 230: case 323: case 326: case 368: return night ? "" : ""
      case 182: case 185: case 281: case 284: case 311: case 314:
      case 317: case 320: case 350: case 362: case 365: case 374: case 377: return ""
      case 200: case 386: case 389: case 392: case 395: return ""
      case 266: case 293: case 296: case 299: case 302: case 305: case 308: case 356: case 359: return ""
      case 329: case 332: case 335: case 338: case 371: return ""
      default: return ""
    }
  }
  // Animation kind for the rich tab (rain / snow / storm / cloud / sun / wind).
  function kindForCode(code, windKmh) {
    var c = parseInt(String(code || "0"), 10)
    if (c >= 200 && c <= 395) return "storm"
    if (c >= 176 && c <= 377) return (c >= 179 && c <= 371) ? "snow" : "rain"
    if (c === 119 || c === 122 || c === 248 || c === 260) return "cloud"
    if (windKmh >= 25) return "wind"
    return "sun"
  }
  // Emoji fallback for places where a Nerd Font glyph may not render.
  function emojiForCode(code, night) {
    var c = parseInt(String(code || "0"), 10)
    if (c >= 200 && c <= 395) return "⛈"
    if (c >= 176 && c <= 377) return (c >= 179 && c <= 371) ? "❄" : "🌧"
    if (c === 119 || c === 122 || c === 248 || c === 260) return "☁"
    if (c >= 266 && c <= 359) return "🌧"
    return night ? "🌙" : "☀"
  }

  function load() {
    if (!root) return
    // 1) read the real location (name + coords) from Omarchy's weather state
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
      else m.query = name ? name + ",Chile" : "Santiago,Chile"  // fallback for CL user
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
        m.temp = (cur.temp_C !== undefined) ? cur.temp_C + "°C" : ""
        m.code = cur.weatherCode
        m.cond = cur.weatherDesc ? cur.weatherDesc[0].value : ""
        m.humidity = cur.humidity || ""
        m.wind = cur.windspeedKmph || ""
        m.kind = m.kindForCode(m.code, parseFloat(m.wind) || 0)
        m.icon = m.glyphForCode(m.code, isNight)
        var today = d.weather && d.weather[0]
        if (today) { m.maxC = today.maxtempC; m.minC = today.mintempC }
        // next 3 days forecast (nearest noon entry)
        var fc = []
        for (var i = 1; i < Math.min(4, d.weather.length); i++) {
          var day = d.weather[i]
          var hr = day.hourly && day.hourly.length > 12 ? day.hourly[11] : (day.hourly && day.hourly[0])
          fc.push({
            day: day.date,
            icon: m.glyphForCode(hr ? hr.weatherCode : day.hourly[0].weatherCode, false),
            maxC: day.maxtempC, minC: day.mintempC
          })
        }
        m.forecast = fc
      } catch (e) {}
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
  property string humidity: ""
  property string wind: ""
  property string code: ""
  property string kind: "sun"
  property string maxC: ""
  property string minC: ""
  property var forecast: []
  property string query: "Santiago,Chile"

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
      font.family: Style.fontFamily
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
    // small stats (humidity / wind) — phase 2e will expand into the rich card
    Column {
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      Text { text: m.humidity ? "💧 " + m.humidity + "%" : ""; color: Color.muted; font.pixelSize: Style.font.bodySmall }
      Text { text: m.wind ? "🌬 " + m.wind + "km/h" : ""; color: Color.muted; font.pixelSize: Style.font.bodySmall }
    }
  }
}
