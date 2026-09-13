pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: m
  property var root: null
  property string pluginKey: ""
  width: parent ? parent.width : Style.space(900)
  implicitHeight: Style.space(430)

  property var cities: []
  property string activeId: ""
  property int selectedCityIndex: 0
  property string mode: "cards" // cards | search | remove | nearby
  property string searchPurpose: "add" // add | edit
  property string editingCityId: ""
  property var suggestions: []
  property int suggestionIndex: 0
  property int confirmationChoice: 0
  property var pendingCandidate: null
  property string statusText: ""
  property var requestTokens: ({ search: 0 })
  readonly property bool pluginVisible: root && root.opened && visible && root.activePluginItem === m
  readonly property var currentCity: activeCity()
  property bool keyboardNavigationBlocked: searchField.activeFocus
  property string notchIcon: ""
  property string notchText: ""

  function tr(en, es) { return root && root.uiLang === "es" ? es : en }

  function exec(args, callback) {
    if (!root || !pluginKey) return
    root.run(["plugin-exec", pluginKey].concat(args), function(out) {
      if (callback) callback(out || "")
    })
  }

  function parseOutput(out, fallback) {
    try { return JSON.parse((out || "").trim()) } catch (error) { return fallback }
  }

  function activeCity() {
    for (var index = 0; index < cities.length; ++index)
      if (cities[index].id === activeId) return cities[index]
    return cities.length ? cities[0] : null
  }

  function runtimeCity(identifier) {
    for (var index = 0; index < cities.length; ++index)
      if (cities[index].id === identifier) return cities[index]
    return null
  }

  function applyState(state) {
    if (!state || !Array.isArray(state.cities)) return false
    var next = []
    for (var index = 0; index < state.cities.length; ++index) {
      var persisted = state.cities[index]
      var previous = runtimeCity(persisted.id)
      var city = {}
      var key
      for (key in persisted) city[key] = persisted[key]
      city.weather = previous ? previous.weather : null
      city.loading = previous ? previous.loading : false
      city.error = previous ? previous.error : ""
      next.push(city)
    }
    cities = next
    activeId = state.activeId || (next.length ? next[0].id : "")
    selectedCityIndex = Math.max(0, Math.min(selectedCityIndex, Math.max(0, next.length - 1)))
    pushNotch()
    return true
  }

  function loadState(refreshAfter) {
    exec(["state"], function(out) {
      if (!m.applyState(m.parseOutput(out, null))) return
      if (refreshAfter && m.pluginVisible) m.refreshAll()
    })
  }

  function nextRequest(key) {
    var tokens = {}
    var existing
    for (existing in requestTokens) tokens[existing] = requestTokens[existing]
    tokens[key] = (tokens[key] || 0) + 1
    requestTokens = tokens
    return tokens[key]
  }

  function todayString() { return new Date().toISOString().slice(0, 10) }

  function reportDate(report) {
    var localTime = report && report.current ? String(report.current.time || "") : ""
    return /^\d{4}-\d{2}-\d{2}/.test(localTime) ? localTime.slice(0, 10) : todayString()
  }

  function refreshCity(city) {
    if (!pluginVisible || !city) return
    var requestId = nextRequest(city.id)
    cities = Model.updateCityRuntime(cities, city.id, { loading: true, error: "" })
    exec(["forecast", String(city.latitude), String(city.longitude)], function(out) {
      if (!Model.responseIsCurrent(m.requestTokens, city.id, requestId)) return
      var report = m.parseOutput(out, null)
      var weather = report ? Model.cityWeather(report, m.reportDate(report)) : null
      if (!weather) {
        m.cities = Model.updateCityRuntime(m.cities, city.id, {
          loading: false, error: m.tr("Weather unavailable", "Clima no disponible")
        })
      } else {
        m.cities = Model.updateCityRuntime(m.cities, city.id, {
          weather: weather, loading: false, error: ""
        })
      }
      m.pushNotch()
    })
  }

  function refreshAll() {
    if (!pluginVisible) return
    for (var index = 0; index < cities.length; ++index) refreshCity(cities[index])
  }

  function pushNotch() {
    var active = activeCity()
    if (!active) {
      notchIcon = ""
      notchText = tr("Add a city", "Agrega una ciudad")
    } else if (active.weather) {
      notchIcon = active.weather.icon || ""
      notchText = (active.weather.temp !== "" ? active.weather.temp + "° " : "") + active.name
      if (root && root.updateNotchData) root.updateNotchData(pluginKey, active.weather.icon || notchIcon, notchText)
      return
    } else {
      notchIcon = ""
      notchText = active.name
    }
    if (root && root.updateNotchData) root.updateNotchData(pluginKey, notchIcon, notchText)
  }

  function startCitySearch(purpose, city) {
    if (!pluginVisible || (purpose === "add" && cities.length >= 8)) return
    searchPurpose = purpose
    editingCityId = city ? city.id : ""
    mode = "search"
    suggestions = []
    suggestionIndex = 0
    statusText = ""
    nextRequest("search")
    Qt.callLater(function() {
      searchField.text = city ? city.name : ""
      if (city) searchField.selectAll()
      searchField.forceActiveFocus()
    })
  }

  function beginAddCity() { startCitySearch("add", null) }

  function beginEditCity() {
    var city = activeCity()
    if (city) startCitySearch("edit", city)
  }

  function cancelOverlay() {
    if (mode === "cards") return false
    searchDebounce.stop()
    nextRequest("search")
    mode = "cards"
    suggestions = []
    pendingCandidate = null
    statusText = ""
    searchField.focus = false
    return true
  }

  function performSearch() {
    if (!pluginVisible) return
    var query = searchField.text.trim()
    if (query.length < 2) return
    var requestId = nextRequest("search")
    statusText = tr("Searching…", "Buscando…")
    exec(["search", query], function(out) {
      if (!m.pluginVisible || !Model.responseIsCurrent(m.requestTokens, "search", requestId)) return
      var result = m.parseOutput(out, null)
      if (!result) {
        m.suggestions = []
        m.statusText = m.tr("Search unavailable", "Búsqueda no disponible")
        return
      }
      m.suggestions = result
      m.suggestionIndex = Math.max(0, Math.min(m.suggestionIndex, Math.max(0, result.length - 1)))
      m.statusText = result.length ? "" : m.tr("No matching cities", "No hay ciudades coincidentes")
    })
  }

  function addSuggestion(suggestion, confirmed) {
    if (!pluginVisible || !suggestion) return
    pendingCandidate = suggestion
    var args = searchPurpose === "edit"
      ? ["replace-city", editingCityId, JSON.stringify(suggestion)]
      : ["add-city", JSON.stringify(suggestion)]
    if (confirmed) args.push("confirm")
    exec(args, function(out) {
      var result = m.parseOutput(out, null)
      if (!result) {
        m.statusText = m.searchPurpose === "edit"
          ? m.tr("Could not edit city", "No se pudo editar la ciudad")
          : m.tr("Could not add city", "No se pudo agregar la ciudad")
        return
      }
      if (result.requiresConfirmation) {
        m.mode = "nearby"
        m.confirmationChoice = 0
        m.statusText = result.message || m.tr("A nearby city already exists", "Ya existe una ciudad cercana")
        return
      }
      if (result.duplicate) {
        m.statusText = m.tr("That city is already added", "Esa ciudad ya está agregada")
        return
      }
      if (!m.applyState(result)) return
      m.mode = "cards"
      searchField.focus = false
      for (var index = 0; index < m.cities.length; ++index) {
        if ((m.searchPurpose === "edit" && m.cities[index].id === m.editingCityId)
            || (m.searchPurpose === "add" && m.cities[index].name === suggestion.name && m.cities[index].latitude === suggestion.latitude))
          m.selectedCityIndex = index
      }
      m.refreshCity(m.cities[m.selectedCityIndex])
    })
  }

  function confirmNearby(accepted) {
    if (accepted) addSuggestion(pendingCandidate, true)
    else cancelOverlay()
  }

  function activateSelected() {
    var city = cities[selectedCityIndex]
    if (!pluginVisible || !city) return
    exec(["activate", city.id], function(out) {
      if (!m.applyState(m.parseOutput(out, null))) return
      m.refreshCity(m.activeCity())
    })
  }

  function reorderSelected(delta) {
    var city = cities[selectedCityIndex]
    if (!pluginVisible || !city) return
    var identifier = city.id
    exec(["reorder", identifier, String(delta)], function(out) {
      if (!m.applyState(m.parseOutput(out, null))) return
      for (var index = 0; index < m.cities.length; ++index)
        if (m.cities[index].id === identifier) m.selectedCityIndex = index
    })
  }

  function beginRemoveConfirmation() {
    if (!cities[selectedCityIndex]) return
    confirmationChoice = 0
    mode = "remove"
  }

  function removeSelected(accepted) {
    if (!accepted) { mode = "cards"; return }
    var city = cities[selectedCityIndex]
    if (!pluginVisible || !city) return
    exec(["remove", city.id], function(out) {
      m.mode = "cards"
      m.applyState(m.parseOutput(out, null))
      if (m.pluginVisible && m.activeCity() && !m.activeCity().weather) m.refreshCity(m.activeCity())
    })
  }

  function handleKeyboardAction(action, payload) {
    payload = payload || ({})
    if (action === "back") return cancelOverlay()
    if (action === "move") {
      var dx = payload.dx || 0
      var dy = payload.dy || 0
      if (mode === "remove" || mode === "nearby") confirmationChoice = confirmationChoice ? 0 : 1
      else if (mode === "cards" && cities.length) {
        var delta = (dx > 0 || dy > 0) ? 1 : -1
        selectedCityIndex = (selectedCityIndex + delta + cities.length) % cities.length
        cityCards.positionViewAtIndex(selectedCityIndex, ListView.Contain)
      }
      return true
    }
    if (action === "activate") {
      if (mode === "remove") removeSelected(confirmationChoice === 1)
      else if (mode === "nearby") confirmNearby(confirmationChoice === 1)
      else if (mode === "cards") activateSelected()
      return true
    }
    if (action === "delete") { if (mode === "cards") beginRemoveConfirmation(); return true }
    if (action === "text") {
      var text = String(payload.text || "").toLowerCase()
      if (text === "e") { beginEditCity(); return true }
      if (text === "a") { beginAddCity(); return true }
      if (text === "r") { refreshAll(); return true }
      if (text === "u") { reorderSelected(-1); return true }
      if (text === "d") { reorderSelected(1); return true }
      if (text === "x") { beginRemoveConfirmation(); return true }
      if (text === "h" || text === "k") return handleKeyboardAction("move", { dx: -1, dy: 0 })
      if (text === "l" || text === "j") return handleKeyboardAction("move", { dx: 1, dy: 0 })
    }
    return false
  }

  onPluginVisibleChanged: {
    if (pluginVisible) loadState(true)
    else cancelOverlay()
  }
  Component.onCompleted: loadState(false)

  Timer {
    id: searchDebounce
    interval: 250
    onTriggered: m.performSearch()
  }

  Timer {
    interval: 10 * 60 * 1000
    running: m.pluginVisible
    repeat: true
    onTriggered: m.refreshAll()
  }

  Column {
    id: weatherColumn
    anchors.fill: parent
    anchors.margins: Style.space(16)
    spacing: Style.space(12)

    Item {
      width: parent.width
      height: Style.space(112)

      Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(14)
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: m.currentCity && m.currentCity.weather ? m.currentCity.weather.icon : ""
          color: Color.foreground
          font.family: Style.fontFamily
          font.pixelSize: 58
        }
        Row {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)
          Text {
            text: m.currentCity && m.currentCity.weather ? m.currentCity.weather.temp : "—"
            color: Color.foreground
            font.family: Style.fontFamily
            font.pixelSize: 50
            font.bold: true
          }
          Text {
            text: m.currentCity && m.currentCity.weather ? "°C" : ""
            color: Color.foreground
            font.family: Style.fontFamily
            font.pixelSize: Style.font.title
          }
        }
      }

      Column {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(parent.width * 0.58, Style.space(470))
        spacing: Style.space(9)

        Rectangle {
          visible: m.mode === "cards"
          width: parent.width
          height: Style.space(32)
          radius: Style.cornerRadius
          color: cityNameMouse.containsMouse ? Color.menu.selectedBackground : "transparent"
          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(8)
            width: parent.width - Style.space(16)
            text: m.currentCity ? ((m.currentCity.displayName || m.currentCity.name) + "  󰏌") : m.tr("Add a city", "Agregar ciudad")
            color: Color.foreground
            elide: Text.ElideRight
            font.family: Style.fontFamily
            font.pixelSize: Style.font.body
          }
          MouseArea {
            id: cityNameMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: m.beginEditCity()
          }
        }

        TextField {
          id: searchField
          visible: m.mode === "search"
          width: parent.width
          height: Style.space(32)
          placeholderText: m.searchPurpose === "edit" ? m.tr("Edit city", "Editar ciudad") : m.tr("Add city", "Agregar ciudad")
          color: Color.foreground
          font.family: Style.fontFamily
          background: Rectangle { radius: Style.cornerRadius; color: Color.menu.selectedBackground; border.color: Color.accent }
          onTextChanged: {
            searchDebounce.stop()
            if (searchField.text.trim().length < 2) {
              m.nextRequest("search")
              m.suggestions = []
              m.statusText = ""
            } else if (m.pluginVisible) searchDebounce.restart()
          }
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Down && m.suggestions.length) {
              m.suggestionIndex = Math.min(m.suggestions.length - 1, m.suggestionIndex + 1); event.accepted = true
            } else if (event.key === Qt.Key_Up && m.suggestions.length) {
              m.suggestionIndex = Math.max(0, m.suggestionIndex - 1); event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              if (m.suggestions[m.suggestionIndex]) m.addSuggestion(m.suggestions[m.suggestionIndex], false)
              event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
              m.cancelOverlay(); event.accepted = true
            }
          }
        }

        Row {
          visible: m.mode === "cards" && m.currentCity && m.currentCity.weather
          spacing: Style.space(24)
          Text { text: m.currentCity && m.currentCity.weather ? m.tr("FEELS", "SENSACIÓN") + "  " + m.currentCity.weather.feels + "°" : ""; color: Qt.darker(Color.foreground, 1.35); font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall }
          Text { text: m.currentCity && m.currentCity.weather ? m.tr("WIND", "VIENTO") + "  " + m.currentCity.weather.wind + " km/h" : ""; color: Qt.darker(Color.foreground, 1.35); font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall }
          Text { text: m.currentCity && m.currentCity.weather ? m.tr("HUMID", "HUMEDAD") + "  " + m.currentCity.weather.humidity + "%" : ""; color: Qt.darker(Color.foreground, 1.35); font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall }
        }
      }
    }

    ListView {
      id: suggestionList
      visible: m.mode === "search"
      width: parent.width
      height: visible ? Math.min(Style.space(144), contentHeight) : 0
      clip: true
      spacing: Style.space(4)
      model: m.suggestions
      currentIndex: m.suggestionIndex
      delegate: Rectangle {
        required property int index
        required property var modelData
        width: suggestionList.width
        height: Style.space(32)
        radius: Style.cornerRadius
        color: index === m.suggestionIndex ? Color.menu.selectedBackground : "transparent"
        Row {
          anchors.fill: parent
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          spacing: Style.space(8)
          Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.38; text: modelData.name; color: Color.foreground; elide: Text.ElideRight; font.family: Style.fontFamily; font.pixelSize: Style.font.body }
          Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.29; text: modelData.region; color: Qt.darker(Color.foreground, 1.35); elide: Text.ElideRight; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall }
          Text { anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.25; text: modelData.country; color: Qt.darker(Color.foreground, 1.35); elide: Text.ElideRight; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: m.addSuggestion(modelData, false) }
      }
    }

    ListView {
      id: cityCards
      visible: m.mode === "cards"
      width: parent.width
      height: Style.space(78)
      orientation: ListView.Horizontal
      spacing: Style.space(7)
      clip: true
      model: m.cities
      currentIndex: m.selectedCityIndex
      delegate: Rectangle {
        required property int index
        required property var modelData
        width: Style.space(132)
        height: cityCards.height
        radius: Style.cornerRadius
        color: cityCardMouse.containsMouse || index === m.selectedCityIndex
          ? Color.menu.selectedBackground : "transparent"
        // Weather city cards stay borderless in both resting and hover states,
        // matching the clock presentation.
        border.width: 0
        Column {
          anchors.centerIn: parent
          width: parent.width - Style.space(12)
          spacing: Style.space(3)
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(7)
            Text { text: modelData.weather ? modelData.weather.icon : (modelData.loading ? "󰑐" : ""); color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.title }
            Text { text: modelData.weather ? modelData.weather.temp + "°" : "—"; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
          }
          Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: modelData.name; color: Color.foreground; elide: Text.ElideRight; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall }
          Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: modelData.error || (modelData.loading ? m.tr("Updating…", "Actualizando…") : ""); color: Color.accent; elide: Text.ElideRight; font.family: Style.fontFamily; font.pixelSize: Style.font.caption }
        }
        MouseArea {
          id: cityCardMouse
          anchors.fill: parent
          z: 0
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: { m.selectedCityIndex = index; m.activateSelected() }
        }
        Button {
          id: removeCityButton
          anchors.top: parent.top
          anchors.right: parent.right
          anchors.margins: Style.space(5)
          // Keep the action present for the selected city as well as on hover.
          // A separate Button owns the click, rather than a nested MouseArea
          // competing with the card's activate area.
          visible: cityCardMouse.containsMouse || index === m.selectedCityIndex
          width: Style.space(20)
          height: Style.space(20)
          iconText: "󰅖"
          z: 3
          onClicked: {
            // This Button owns the event above the card's activation area.
            m.selectedCityIndex = index
            m.beginRemoveConfirmation()
          }
        }
      }
      footer: Rectangle {
        visible: m.cities.length < 8
        width: Style.space(70)
        height: cityCards.height
        radius: Style.cornerRadius
        color: addMouse.containsMouse ? Color.menu.selectedBackground : "transparent"
        border.width: 0
        Text { anchors.centerIn: parent; text: "󰐕"; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.display }
        MouseArea { id: addMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: m.beginAddCity() }
      }
    }

    Row {
      visible: m.mode === "cards" && m.currentCity && m.currentCity.weather
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(34)
      Repeater {
        model: m.currentCity && m.currentCity.weather ? m.currentCity.weather.forecast : []
        Row {
          required property var modelData
          spacing: Style.space(8)
          Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.icon; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.display }
          Column {
            Text { text: Model.dayName(modelData.date).toUpperCase(); color: Qt.darker(Color.foreground, 1.35); font.family: Style.fontFamily; font.pixelSize: Style.font.caption }
            Text { text: modelData.maxC + "°  " + modelData.minC + "°"; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.body }
          }
        }
      }
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: m.statusText || (m.mode === "cards" ? "←/→ " + m.tr("switch", "cambiar") + "  ·  Enter " + m.tr("activate", "activar") + "  ·  E edit  ·  A add  ·  U/D reorder  ·  Del remove  ·  R refresh" : "")
      color: Qt.darker(Color.foreground, 1.4)
      font.family: Style.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Rectangle {
    anchors.fill: parent
    visible: m.mode === "remove" || m.mode === "nearby"
    z: 10
    color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.92)
    Column {
      anchors.centerIn: parent
      spacing: Style.space(14)
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: m.mode === "remove" ? m.tr("Remove city?", "¿Eliminar ciudad?") : m.tr("Add nearby city anyway?", "¿Agregar la ciudad cercana de todos modos?")
        color: Color.foreground
        font.family: Style.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }
      Text { anchors.horizontalCenter: parent.horizontalCenter; text: m.mode === "nearby" ? m.statusText : (m.cities[m.selectedCityIndex] ? m.cities[m.selectedCityIndex].displayName || m.cities[m.selectedCityIndex].name : ""); color: Qt.darker(Color.foreground, 1.3); font.family: Style.fontFamily; font.pixelSize: Style.font.body }
      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(8)
        Repeater {
          model: [m.tr("Cancel", "Cancelar"), m.mode === "remove" ? m.tr("Remove", "Eliminar") : m.tr("Add", "Agregar")]
          Rectangle {
            required property int index
            required property string modelData
            width: Style.space(112); height: Style.space(34); radius: Style.cornerRadius
            color: index === m.confirmationChoice ? Color.accent : Color.menu.selectedBackground
            Text { anchors.centerIn: parent; text: modelData; color: index === m.confirmationChoice ? Color.background : Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.body }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { m.confirmationChoice = index; if (m.mode === "remove") m.removeSelected(index === 1); else m.confirmNearby(index === 1) } }
          }
        }
      }
    }
  }
}
