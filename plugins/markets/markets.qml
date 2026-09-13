pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Item {
  id: m
  property var root: null
  property string pluginKey: ""
  width: parent ? parent.width : 100
  implicitHeight: Style.space(560)
  readonly property bool pluginVisible: root && root.activePluginItem === m

  property string mode: "pulse"
  property string previousMode: "pulse"
  property bool loading: false
  property bool refreshing: false
  property string errorMessage: ""
  property var assets: []
  property var favorites: []
  property var holdings: ({})
  readonly property bool hasPositions: {
    for (var ticker in holdings)
      if ((holdings[ticker] || []).length > 0) return true
    return false
  }
  property var portfolioByCurrency: []
  property bool portfolioComplete: true
  property var unavailablePositions: []
  property var searchResults: []
  property int searchSelection: 0
  property bool searching: false
  property string searchError: ""
  property string selectedSymbol: ""
  property string selectedRange: "1M"
  property var chartPoints: []
  property bool chartStale: false
  property var chartMetadata: ({})
  property string chartError: ""
  property int listSelection: 0
  property int detailSelection: 0
  property int formSelection: 0
  property int confirmSelection: 0
  property string formKind: "symbol"
  property string editingLotId: ""
  property string removalKind: ""
  property string removalId: ""
  property string removalLabel: ""
  property string removalSymbol: ""
  property int actionSelection: 0
  property int refreshGeneration: 0
  property int chartGeneration: 0
  property string notchIcon: "󰄪"
  property bool notchShowValue: false
  property var notchFavoriteAssets: []
  property string notchText: assets.length > 0 && !assets[0].error
                                      ? assets[0].symbol + " " + formatPrice(assets[0].price, assets[0].currency)
                                      : assets.length + " assets"
  readonly property var ranges: ["1D", "1W", "1M", "1Y", "5Y"]
  readonly property bool compact: width < Style.space(680)
  readonly property bool reducedMotion: root && root.reducedMotion === true
  readonly property int motionDuration: reducedMotion ? 0 : 180
  property bool keyboardNavigationBlocked: symbolField.activeFocus || quantityField.activeFocus || dateField.activeFocus || priceField.activeFocus

  component Sparkline: Canvas {
    property var values: []
    property bool large: false
    onValuesChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      if (!values || values.length < 2) return
      var low = Math.min.apply(Math, values)
      var high = Math.max.apply(Math, values)
      var span = Math.max(0.000001, high - low)
      var rising = values[values.length - 1] >= values[0]
      var tone = rising ? Color.accent : Color.foreground
      // A quiet grid plus translucent area gives the chart depth without
      // hard-coded colors, so it remains native to every Omarchy theme.
      ctx.strokeStyle = Color.popups.border
      ctx.lineWidth = 1
      ctx.globalAlpha = 0.55
      for (var g = 1; g < 4; ++g) {
        var gy = g * height / 4
        ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(width, gy); ctx.stroke()
      }
      ctx.globalAlpha = 0.16
      ctx.fillStyle = tone
      ctx.beginPath()
      for (var areaIndex = 0; areaIndex < values.length; areaIndex++) {
        var areaX = areaIndex * width / Math.max(1, values.length - 1)
        var areaY = height - Style.space(3) - ((values[areaIndex] - low) / span) * (height - Style.space(6))
        if (areaIndex === 0) ctx.moveTo(areaX, areaY)
        else ctx.lineTo(areaX, areaY)
      }
      ctx.lineTo(width, height); ctx.lineTo(0, height); ctx.closePath(); ctx.fill()
      ctx.globalAlpha = 1
      ctx.strokeStyle = tone
      ctx.lineWidth = large ? 2.5 : 1.5
      ctx.beginPath()
      for (var i = 0; i < values.length; i++) {
        var x = i * width / Math.max(1, values.length - 1)
        var y = height - Style.space(3) - ((values[i] - low) / span) * (height - Style.space(6))
        if (i === 0) ctx.moveTo(x, y)
        else ctx.lineTo(x, y)
      }
      ctx.stroke()
    }
  }

  function exec(args, callback) {
    if (!root || !pluginKey) return
    root.run(["plugin-exec", pluginKey].concat(args), callback || function () {})
  }

  function parseResult(out, callback) {
    try {
      var result = JSON.parse((out || "").trim())
      errorMessage = ""
      callback(result)
    } catch (e) {
      errorMessage = "Unable to read market data"
    }
  }

  function captureViewContext() {
    var ticker = selectedSymbol
    if (!ticker && listSelection >= 2 && assets[listSelection - 2]) ticker = assets[listSelection - 2].symbol
    return { symbol: ticker, contentY: assetScroll ? assetScroll.contentY : 0 }
  }

  function restoreViewContext(context) {
    if (!context || mode !== "pulse") return
    if (context.symbol) {
      selectedSymbol = context.symbol
      for (var i = 0; i < assets.length; i++)
        if (assets[i].symbol === context.symbol) { listSelection = i + 2; break }
    }
    Qt.callLater(function () {
      if (!assetScroll) return
      assetScroll.contentY = Math.max(0, Math.min(Math.max(0, assetScroll.contentHeight - assetScroll.height), context.contentY || 0))
    })
  }

  function applyPulse(result, context) {
    var incoming = result.assets || []
    var allFailed = incoming.length > 0 && incoming.every(function (asset) { return !!asset.error })
    if (!allFailed || assets.length === 0) assets = incoming
    favorites = result.favorites || []
    holdings = result.holdings || ({})
    if (!allFailed) portfolioByCurrency = result.portfolioByCurrency || []
    portfolioComplete = result.portfolioComplete !== false
    unavailablePositions = result.unavailablePositions || []
    if (allFailed) errorMessage = "Unable to refresh prices · preserving the last snapshot"
    listSelection = Math.min(listSelection, assets.length + 1)
    restoreViewContext(context)
    pushNotch()
  }

  function refreshMarkets(force) {
    if (!root || !root.opened || !m.pluginVisible || refreshing) return
    var generation = ++refreshGeneration
    var context = captureViewContext()
    loading = assets.length === 0
    refreshing = true
    errorMessage = ""
    exec(["snapshot"], function (cachedOut) {
      if (generation !== refreshGeneration) return
      parseResult(cachedOut, function (cached) {
        m.loading = false
        m.applyPulse(cached, context)
      })
      if (!root || !root.opened || !m.pluginVisible) { loading = false; refreshing = false; return }
      var refreshArgs = ["refresh"]
      if (force) refreshArgs.push("--force")
      exec(refreshArgs, function (out) {
        if (generation !== refreshGeneration) return
        loading = false
        refreshing = false
        try {
          var result = JSON.parse((out || "").trim())
          m.applyPulse(result, context)
        } catch (e) {
          errorMessage = "Live refresh failed · showing the last snapshot"
        }
      })
    })
  }

  function invalidateRefresh() {
    refreshGeneration++
    refreshing = false
  }

  function pushNotch() {
    if (root && pluginKey && root.updateNotchData)
      root.updateNotchData(pluginKey, m.notchIcon, m.notchText)
  }

  function refreshNotch() {
    // Cached data is local: it lets the enabled bar widget show favorites
    // before this tab is opened, without issuing a background network refresh.
    if (!root || !pluginKey) return
    exec(["snapshot"], function (out) {
      try {
        var snapshot = JSON.parse((out || "").trim())
        m.notchFavoriteAssets = (snapshot.assets || []).filter(function (asset) { return asset.favorite && !asset.error })
        m.updateNotchTicker()
      } catch (error) {}
    })
  }

  function updateNotchTicker() {
    m.notchText = (m.notchFavoriteAssets || []).map(function (asset) {
      return asset.symbol + " " + (m.notchShowValue
        ? m.formatPrice(asset.price, asset.currency)
        : m.signed(asset.dayChangePct, "%"))
    }).join("  ·  ")
    m.pushNotch()
  }

  function selectedAsset() {
    for (var i = 0; i < assets.length; i++) if (assets[i].symbol === selectedSymbol) return assets[i]
    return null
  }

  function selectedLots() {
    return holdings[selectedSymbol] || []
  }

  function isFavorite(ticker) {
    return favorites.indexOf(ticker) >= 0
  }

  function favoriteSymbols() {
    return favorites.length > 0 ? favorites.join("  ·  ") : "Choose a star from an asset's actions"
  }

  function formatTimestamp(value) {
    if (!value) return "Time unavailable"
    return Qt.formatDateTime(new Date(Number(value) * 1000), "MMM d · h:mm AP")
  }

  function marketStateLabel(asset) {
    var state = asset ? String(asset.marketState || "").toUpperCase() : ""
    return state && state !== "UNKNOWN" ? state : ""
  }

  function provenanceText(asset) {
    if (!asset) return "Source unavailable"
    var parts = []
    if (asset.stale) parts.push("CACHED")
    parts.push(asset.source || "Yahoo Finance")
    parts.push(asset.currency || "Currency unavailable")
    var marketState = marketStateLabel(asset)
    if (marketState) parts.push(marketState)
    parts.push("As of " + formatTimestamp(asset.asOf))
    parts.push("Fetched " + formatTimestamp(asset.fetchedAt))
    return parts.join("  ·  ")
  }

  function formatPrice(value, currency) {
    if (value === null || value === undefined) return "—"
    return (currency ? currency + " " : "") + Number(value).toFixed(2)
  }

  function signed(value, suffix) {
    if (value === null || value === undefined) return "—"
    return (value >= 0 ? "+" : "") + Number(value).toFixed(2) + (suffix || "")
  }

  function mutate(args, after) {
    invalidateRefresh()
    loading = true
    exec(args, function (out) {
      loading = false
      parseResult(out, function (state) {
        holdings = state.holdings || ({})
        if (after) after(state)
        refreshMarkets(true)
      })
    })
  }

  function toggleFavorite() {
    if (!selectedSymbol) return
    invalidateRefresh()
    loading = true
    exec(["toggle-favorite", selectedSymbol], function (out) {
      loading = false
      parseResult(out, function (state) {
        favorites = state.favorites || []
        refreshMarkets(true)
      })
    })
  }

  function openSymbolForm() {
    previousMode = "pulse"
    formKind = "symbol"
    formSelection = 0
    symbolField.text = ""
    searchResults = []
    searchSelection = 0
    searchError = ""
    mode = "form"
    Qt.callLater(function () { if (m.mode === "form" && m.formKind === "symbol") symbolField.forceActiveFocus() })
  }

  function searchAssets() {
    if (!root || !root.opened || !m.pluginVisible) return
    var query = symbolField.text.trim()
    if (query.length < 2) { searchResults = []; searchSelection = 0; searching = false; searchError = ""; return }
    searching = true
    searchError = ""
    exec(["search", query], function (out) {
      if (symbolField.text.trim() !== query) return
      searching = false
      try {
        searchResults = JSON.parse((out || "").trim()) || []
        searchSelection = Math.min(searchSelection, Math.max(0, searchResults.length - 1))
        if (searchResults.length === 0) searchError = "No assets found"
      } catch (e) {
        searchResults = []
        searchError = "Unable to search assets"
      }
    })
  }

  function moveSearchSelection(delta) {
    if (searchResults.length === 0) return
    searchSelection = (searchSelection + delta + searchResults.length) % searchResults.length
    if (searchList) searchList.positionViewAtIndex(searchSelection, ListView.Contain)
  }

  function chooseSearchResult(index) {
    if (index < 0 || index >= searchResults.length) return
    symbolField.text = searchResults[index].symbol
    symbolField.focus = false
    saveForm()
  }

  function openLotForm(lot) {
    previousMode = "detail"
    formKind = lot ? "editLot" : "addLot"
    editingLotId = lot ? lot.id : ""
    quantityField.text = lot ? String(lot.quantity) : ""
    dateField.text = lot && lot.date ? lot.date : ""
    priceField.text = lot && lot.price !== null && lot.price !== undefined ? String(lot.price) : ""
    formSelection = 0
    mode = "form"
  }

  function saveForm() {
    if (formKind === "symbol") {
      if (!symbolField.text.trim()) { errorMessage = "Enter a symbol"; return }
      mutate(["add-symbol", symbolField.text], function () { mode = "pulse" })
      return
    }
    if (!quantityField.text.trim()) { errorMessage = "Quantity is required"; return }
    var args = [formKind === "editLot" ? "edit-lot" : "add-lot", selectedSymbol]
    if (formKind === "editLot") args.push(editingLotId)
    args.push(quantityField.text, dateField.text, priceField.text)
    mutate(args, function () { mode = "detail" })
  }

  function openDetail(ticker) {
    selectedSymbol = ticker
    selectedRange = "1M"
    chartPoints = []
    chartMetadata = ({})
    chartError = ""
    detailSelection = 0
    mode = "detail"
    loadChart(false)
  }

  function openActions() {
    previousMode = "detail"
    actionSelection = 0
    mode = "action"
  }

  function loadChart(force) {
    if (!root || !root.opened || !m.pluginVisible || !selectedSymbol) return
    var generation = ++chartGeneration
    loading = true
    chartError = ""
    var args = ["chart", selectedSymbol, selectedRange]
    if (force) args.push("--force")
    exec(args, function (out) {
      if (generation !== chartGeneration) return
      loading = false
      try {
        var result = JSON.parse((out || "").trim())
        if (result.symbol !== selectedSymbol || result.range !== selectedRange) return
        chartPoints = (result.points || []).map(function (point) { return point.value })
        chartStale = !!result.stale
        chartMetadata = result
        chartError = result.warning || ""
      } catch (error) {
        chartStale = true
        chartError = "Chart unavailable · showing the previous valid chart"
      }
    })
  }

  function chooseRange(value) {
    selectedRange = value
    loadChart(false)
  }

  function reorderSelected(delta) {
    var row = listSelection - 2
    if (row < 0 || row >= assets.length) return
    invalidateRefresh()
    exec(["reorder", assets[row].symbol, String(delta)], function () { refreshMarkets(true) })
  }

  function requestRemoval(kind, id, label) {
    previousMode = mode
    removalKind = kind
    removalId = id || ""
    removalLabel = label || ""
    removalSymbol = selectedSymbol || (kind === "symbol" ? removalLabel : "")
    confirmSelection = 0
    mode = "confirm"
  }

  function confirmRemoval() {
    if (removalKind === "symbol")
      mutate(["remove-symbol", removalSymbol, "confirm"], function () { selectedSymbol = ""; mode = "pulse" })
    else if (removalKind === "lot")
      mutate(["remove-lot", removalSymbol, removalId], function () { mode = "detail" })
  }

  function goBack() {
    if (mode === "confirm") mode = previousMode
    else if (mode === "form") mode = previousMode
    else if (mode === "action") mode = "detail"
    else if (mode === "detail") mode = "pulse"
    else return false
    return true
  }

  function revealAssetSelection() {
    if (!assetScroll) return
    var row = listSelection - 2
    var rowStep = Style.space(74)
    var rowHeight = Style.space(68)
    var top = row < 0 ? 0 : row * rowStep
    var bottom = top + rowHeight
    var target = assetScroll.contentY
    if (row < 0 || top < target) target = top
    else if (bottom > target + assetScroll.height) target = bottom - assetScroll.height
    target = Math.max(0, Math.min(Math.max(0, assetScroll.contentHeight - assetScroll.height), target))
    assetScrollAnim.stop()
    assetScrollAnim.from = assetScroll.contentY
    assetScrollAnim.to = target
    assetScrollAnim.start()
  }

  function revealLotSelection() {
    if (!lotScroll) return
    var row = Math.floor((detailSelection - 7) / 2)
    var rowStep = Style.space(44)
    var rowHeight = Style.space(40)
    var top = row < 0 ? 0 : row * rowStep
    var bottom = top + rowHeight
    var target = lotScroll.contentY
    if (row < 0 || top < target) target = top
    else if (bottom > target + lotScroll.height) target = bottom - lotScroll.height
    target = Math.max(0, Math.min(Math.max(0, lotScroll.contentHeight - lotScroll.height), target))
    lotScrollAnim.stop()
    lotScrollAnim.from = lotScroll.contentY
    lotScrollAnim.to = target
    lotScrollAnim.start()
  }

  function moveListSelection(dx, dy) {
    if (dx !== 0 && listSelection >= 2) { reorderSelected(dx > 0 ? 1 : -1); return true }
    var step = dy !== 0 ? (dy > 0 ? 1 : -1) : (dx > 0 ? 1 : -1)
    listSelection = (listSelection + step + assets.length + 2) % (assets.length + 2)
    revealAssetSelection()
    return true
  }

  function moveDetailSelection(dx, dy) {
    var count = 7 + selectedLots().length * 2
    var step = (dy !== 0 ? dy : dx) > 0 ? 1 : -1
    detailSelection = (detailSelection + step + count) % count
    revealLotSelection()
    return true
  }

  function moveFormSelection(dx, dy) {
    var count = formKind === "symbol" ? 3 : 5
    var step = (dy !== 0 ? dy : dx) > 0 ? 1 : -1
    formSelection = (formSelection + step + count) % count
    return true
  }

  function moveActionSelection(dx, dy) {
    var step = (dy !== 0 ? dy : dx) > 0 ? 1 : -1
    actionSelection = (actionSelection + step + 4) % 4
    return true
  }

  function activateList() {
    if (listSelection === 0) openSymbolForm()
    else if (listSelection === 1) refreshMarkets(true)
    else if (assets[listSelection - 2]) openDetail(assets[listSelection - 2].symbol)
  }

  function activateDetail() {
    if (detailSelection === 0) { goBack(); return }
    if (detailSelection >= 1 && detailSelection <= 5) { chooseRange(ranges[detailSelection - 1]); return }
    if (detailSelection === 6) { openActions(); return }
    var lotIndex = Math.floor((detailSelection - 7) / 2)
    var lots = selectedLots()
    if (!lots[lotIndex]) return
    if ((detailSelection - 7) % 2 === 0) openLotForm(lots[lotIndex])
    else requestRemoval("lot", lots[lotIndex].id, "holding lot")
  }

  function activateAction() {
    if (actionSelection === 0) goBack()
    else if (actionSelection === 1) toggleFavorite()
    else if (actionSelection === 2) openLotForm(null)
    else requestRemoval("symbol", "", selectedSymbol)
  }

  function activateForm() {
    if (formKind === "symbol") {
      if (formSelection === 0) symbolField.forceActiveFocus()
      else if (formSelection === 1) goBack()
      else saveForm()
    } else {
      if (formSelection === 0) quantityField.forceActiveFocus()
      else if (formSelection === 1) dateField.forceActiveFocus()
      else if (formSelection === 2) priceField.forceActiveFocus()
      else if (formSelection === 3) goBack()
      else saveForm()
    }
  }

  function handleKeyboardAction(action, payload) {
    payload = payload || ({})
    if (action === "back" || action === "escape") return goBack()
    if (action === "delete") {
      if (mode === "pulse" && listSelection >= 2) {
        selectedSymbol = assets[listSelection - 2].symbol
        requestRemoval("symbol", "", selectedSymbol)
        return true
      }
      if (mode === "detail") {
        if (detailSelection >= 7) {
          var deleteLotIndex = Math.floor((detailSelection - 7) / 2)
          var deleteLots = selectedLots()
          if (deleteLots[deleteLotIndex]) {
            requestRemoval("lot", deleteLots[deleteLotIndex].id, "holding lot")
            return true
          }
        }
        requestRemoval("symbol", "", selectedSymbol)
        return true
      }
    }
    if (action === "text") {
      var text = String(payload.text || "").toLowerCase()
      if (text === "x") return handleKeyboardAction("delete", {})
      if ("hjkl".indexOf(text) >= 0) {
        var dx = text === "h" ? -1 : (text === "l" ? 1 : 0)
        var dy = text === "k" ? -1 : (text === "j" ? 1 : 0)
        return handleKeyboardAction("move", { dx: dx, dy: dy })
      }
      return false
    }
    if (action === "move") {
      if (mode === "pulse") return moveListSelection(payload.dx || 0, payload.dy || 0)
      if (mode === "detail") return moveDetailSelection(payload.dx || 0, payload.dy || 0)
      if (mode === "form") return moveFormSelection(payload.dx || 0, payload.dy || 0)
      if (mode === "action") return moveActionSelection(payload.dx || 0, payload.dy || 0)
      if (mode === "confirm") { confirmSelection = confirmSelection === 0 ? 1 : 0; return true }
    }
    if (action === "activate") {
      if (mode === "pulse") activateList()
      else if (mode === "detail") activateDetail()
      else if (mode === "form") activateForm()
      else if (mode === "action") activateAction()
      else if (mode === "confirm") { if (confirmSelection === 0) goBack(); else confirmRemoval() }
      return true
    }
    return false
  }

  onNotchTextChanged: pushNotch()
  onRootChanged: {
    if (!root) return
    refreshNotch()
    if (root.opened && m.pluginVisible) refreshMarkets(false)
  }
  onPluginVisibleChanged: if (m.pluginVisible && root && root.opened) refreshMarkets(false)
  Connections {
    target: root
    function onOpenedChanged() {
      if (root && root.opened && m.pluginVisible) m.refreshMarkets(false)
    }
  }
  Timer {
    interval: 300000
    repeat: true
    running: m.pluginVisible && root && root.opened
    onTriggered: m.refreshMarkets(false)
  }
  Timer {
    interval: 300000
    repeat: true
    running: root && !!pluginKey
    onTriggered: m.refreshNotch()
  }
  Timer {
    interval: 4000
    repeat: true
    running: root && !!pluginKey && m.notchFavoriteAssets.length > 0
    onTriggered: { m.notchShowValue = !m.notchShowValue; m.updateNotchTicker() }
  }
  Timer {
    id: searchTimer
    interval: 300
    repeat: false
    onTriggered: m.searchAssets()
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: Style.space(12)
    color: "transparent"

    Column {
      anchors.fill: parent
      spacing: Style.space(10)

      Row {
        width: parent.width
        height: Style.space(38)
        spacing: Style.space(8)
        Text { text: "󰄪"; color: Color.accent; font.family: Style.fontFamily; font.pixelSize: Style.font.title; anchors.verticalCenter: parent.verticalCenter }
        Column {
          anchors.verticalCenter: parent.verticalCenter
          Text { text: mode === "pulse" ? "MARKET PULSE" : (mode === "detail" || mode === "action" ? selectedSymbol : (formKind === "symbol" ? "ADD TO WATCHLIST" : "PORTFOLIO")); color: Color.accent; font.family: Style.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
          Text { text: mode === "pulse" ? "Your market at a glance" : (mode === "action" ? "Choose what to do next" : (mode === "detail" ? "Price, context and position" : (formKind === "symbol" ? "Find an asset" : "Record a purchase"))); color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
        }
        Item { width: Math.max(0, parent.width - Style.space(260)); height: 1 }
        Text { visible: loading || refreshing; text: loading ? "Loading…" : "Refreshing…"; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
      }

      Item {
        width: parent.width
        height: parent.height - Style.space(48)

        Column {
          opacity: m.mode === "pulse" ? 1 : 0
          visible: opacity > 0
          enabled: m.mode === "pulse"
          scale: m.mode === "pulse" ? 1 : 0.985
          Behavior on opacity { NumberAnimation { duration: m.motionDuration; easing.type: Easing.OutCubic } }
          Behavior on scale { NumberAnimation { duration: m.motionDuration; easing.type: Easing.OutCubic } }
          anchors.fill: parent
          spacing: Style.space(8)

          Row {
            width: parent.width
            height: Style.space(34)
            spacing: Style.space(8)
            ActionButton { label: "󰐕 Add symbol"; selected: m.listSelection === 0; onTriggered: m.openSymbolForm() }
            ActionButton { label: "󰑐 Refresh"; selected: m.listSelection === 1; onTriggered: m.refreshMarkets(true) }
            Text { width: Math.max(0, parent.width - Style.space(280)); text: m.compact ? "↑/↓ · Enter · x" : "↑/↓ navigate  ·  Enter opens asset  ·  x removes"; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
          }

          Rectangle {
            visible: m.assets.length > 0
            width: parent.width
            height: m.compact ? Style.space(116) : Style.space(138)
            radius: Style.cornerRadius * 1.5
            color: Color.popups.background
            border.color: Color.popups.border
            border.width: 1
            property var featured: m.assets.filter(function (asset) { return asset.favorite && !asset.error })[0] || m.assets[0]
            Text { x: Style.space(12); y: Style.space(9); text: parent.featured ? parent.featured.symbol + "  ·  " + m.signed(parent.featured.dayChangePct, "%") : ""; color: Color.accent; font.family: Style.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
            Sparkline { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: Style.space(10); anchors.topMargin: Style.space(28); height: parent.height - Style.space(38); values: parent.featured ? parent.featured.sparkline || [] : []; large: true }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (parent.featured) m.openDetail(parent.featured.symbol) } }
          }

          Flow {
            width: parent.width
            spacing: Style.space(8)

            Rectangle {
              visible: m.hasPositions
              width: m.compact ? parent.width : (parent.width - Style.space(8)) / 2
              height: Style.space(78)
              radius: Style.cornerRadius * 1.5
              color: Color.popups.background
              border.color: Color.popups.border
              border.width: 1
              Column {
                anchors.fill: parent; anchors.margins: Style.space(10); spacing: Style.space(4)
                Text { text: "PORTFOLIO"; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                Text { visible: !m.portfolioComplete; width: parent.width; text: "Portfolio totals incomplete · unavailable: " + m.unavailablePositions.join(", "); color: Color.accent; font.family: Style.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
                Row {
                  visible: m.portfolioByCurrency.length > 0; spacing: Style.space(14)
                  Repeater {
                    model: m.portfolioByCurrency
                    Column {
                      required property var modelData
                      Text { text: m.formatPrice(modelData.value, modelData.currency); color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
                      Text { text: modelData.gain === null ? "Cost basis incomplete" : "Gain " + m.signed(modelData.gain, "") + " " + modelData.currency; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.caption }
                    }
                  }
                }
              }
            }

            Rectangle {
              visible: m.favorites.length > 0
              width: m.compact ? parent.width : (parent.width - Style.space(8)) / 2
              height: Style.space(78)
              radius: Style.cornerRadius * 1.5
              color: Color.popups.background
              border.color: Color.popups.border
              border.width: 1
              Column {
                anchors.fill: parent; anchors.margins: Style.space(10); spacing: Style.space(4)
                Text { text: "FAVORITES  ·  " + m.favorites.length; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                Text { width: parent.width; text: m.favoriteSymbols(); color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
              }
            }
          }

          Text { visible: errorMessage !== ""; text: errorMessage + (assets.length ? " · showing cached data where available" : ""); color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall }
          Text { visible: !loading && assets.length === 0; text: "Your watchlist is empty. Add a symbol to begin."; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.body }
          Text { text: "WATCHLIST  ·  " + assets.length; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }

          Flickable {
            id: assetScroll
            width: parent.width
            height: Math.max(0, parent.height - y - Style.space(24))
            contentHeight: assetColumn.implicitHeight
            clip: true
            NumberAnimation { id: assetScrollAnim; target: assetScroll; property: "contentY"; duration: 160; easing.type: Easing.OutCubic }
            Column {
              id: assetColumn
              width: parent.width
              spacing: Style.space(6)
              Repeater {
                model: m.assets
                Rectangle {
                  required property var modelData
                  required property int index
                  width: assetColumn.width
                  height: Style.space(68)
                  radius: Style.cornerRadius
                  color: m.listSelection === index + 2 ? Color.menu.selectedBackground : Color.popups.background
                  border.color: m.listSelection === index + 2 || modelData.stale ? Color.accent : Color.popups.border
                  border.width: m.listSelection === index + 2 ? 2 : 1

                  MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: m.openDetail(modelData.symbol) }
                  Row {
                    anchors.fill: parent
                    anchors.margins: Style.space(9)
                    spacing: Style.space(12)
                    Column {
                      width: m.compact ? Style.space(66) : Style.space(92); anchors.verticalCenter: parent.verticalCenter
                      Text { text: (modelData.favorite ? "󰓎 " : "") + modelData.symbol; color: modelData.favorite ? Color.accent : Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
                      Text { text: modelData.stale ? "cached" : (modelData.error ? "unavailable" : modelData.currency); color: modelData.stale ? Color.accent : Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.caption }
                    }
                    // Every listed instrument gets a chart, including on narrow
                    // panels. The compact version is smaller, never omitted.
                    Sparkline { width: m.compact ? Style.space(72) : Style.space(128); height: Style.space(42); anchors.verticalCenter: parent.verticalCenter; values: modelData.sparkline || [] }
                    Column {
                      width: m.compact ? Style.space(88) : Style.space(112); anchors.verticalCenter: parent.verticalCenter
                      Text { text: m.formatPrice(modelData.price, modelData.currency); color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
                      Text { text: modelData.error ? modelData.error : m.signed(modelData.dayChangePct, "% today"); color: modelData.dayChange >= 0 ? Color.accent : Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight; width: parent.width }
                    }
                    Column {
                      visible: modelData.quantity > 0 && !m.compact
                      width: Style.space(150); anchors.verticalCenter: parent.verticalCenter
                      Text { text: "Position " + m.formatPrice(modelData.marketValue, modelData.currency); color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall }
                      Text { text: modelData.gain === null ? "Cost basis incomplete" : "Gain " + m.signed(modelData.gain, "") + " " + modelData.currency + " (" + m.signed(modelData.gainPct, "%") + ")"; color: modelData.gain >= 0 ? Color.accent : Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.caption }
                    }
                    ActionButton { visible: !m.compact; label: "󰁝"; selected: false; onTriggered: { m.listSelection = index + 2; m.reorderSelected(-1) } }
                    ActionButton { visible: !m.compact; label: "󰁅"; selected: false; onTriggered: { m.listSelection = index + 2; m.reorderSelected(1) } }
                    Text { text: "󰁔"; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.body; anchors.verticalCenter: parent.verticalCenter }
                  }
                }
              }
            }
          }
          Text { text: "Unofficial Yahoo Finance chart data · best-effort availability · cached fallback"; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.caption }
        }

        Column {
          opacity: m.mode === "detail" ? 1 : 0
          visible: opacity > 0
          enabled: m.mode === "detail"
          scale: m.mode === "detail" ? 1 : 0.985
          Behavior on opacity { NumberAnimation { duration: m.motionDuration; easing.type: Easing.OutCubic } }
          Behavior on scale { NumberAnimation { duration: m.motionDuration; easing.type: Easing.OutCubic } }
          anchors.fill: parent
          spacing: Style.space(8)
          Flow {
            width: parent.width; height: Style.space(32); spacing: Style.space(6)
            ActionButton {
              label: root && root.uiLang === "es" ? "󰁍 Índice" : "󰁍 Index"
              selected: m.detailSelection === 0
              onTriggered: {
                // Always return to the complete watchlist; canceling an
                // in-flight chart prevents a late response from re-opening it.
                m.chartGeneration++
                m.selectedSymbol = ""
                m.mode = "pulse"
              }
            }
            Repeater {
              model: m.ranges
              ActionButton { required property string modelData; required property int index; label: modelData; selected: m.selectedRange === modelData || m.detailSelection === index + 1; onTriggered: m.chooseRange(modelData) }
            }
            ActionButton { label: "󰒓 Actions"; selected: m.detailSelection === 6; onTriggered: m.openActions() }
          }

          Text { visible: m.chartError !== ""; text: m.chartError; color: Color.accent; font.family: Style.fontFamily; font.pixelSize: Style.font.caption }
          Text { visible: m.chartStale && m.chartError === ""; text: "Chart is cached; live provider unavailable."; color: Color.accent; font.family: Style.fontFamily; font.pixelSize: Style.font.caption }
          Sparkline { width: parent.width; height: m.compact ? Style.space(150) : Style.space(190); values: m.chartPoints; large: true }
          Text {
            width: parent.width
            text: m.provenanceText(m.chartMetadata)
            color: m.chartMetadata && m.chartMetadata.stale ? Color.accent : Color.muted
            font.family: Style.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight
          }

          Row {
            width: parent.width; height: Style.space(48); spacing: Style.space(30)
            Column {
              Text { text: "CURRENT"; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.caption }
              Text {
                text: { var asset = m.selectedAsset(); return asset ? m.formatPrice(asset.price, asset.currency) : "—" }
                color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.title
              }
            }
            Column {
              Text { text: "DAY VARIATION"; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.caption }
              Text {
                text: { var asset = m.selectedAsset(); return asset ? m.signed(asset.dayChangePct, "%") : "—" }
                color: Color.accent; font.family: Style.fontFamily; font.pixelSize: Style.font.title
              }
            }
            Column {
              Text { text: "PORTFOLIO GAIN / LOSS"; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.caption }
              Text {
                text: { var asset = m.selectedAsset(); return asset && asset.gain !== null ? m.signed(asset.gain, "") + " " + asset.currency + " (" + m.signed(asset.gainPct, "%") + ")" : "Cost basis unavailable" }
                color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.title
              }
            }
          }

          Text { text: "Purchase lots"; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
          Text { visible: m.selectedLots().length === 0; text: "No holdings recorded for this asset."; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall }
          Flickable {
            id: lotScroll
            width: parent.width; height: Style.space(150); contentHeight: lotsColumn.implicitHeight; clip: true
            NumberAnimation { id: lotScrollAnim; target: lotScroll; property: "contentY"; duration: 160; easing.type: Easing.OutCubic }
            Column {
              id: lotsColumn; width: parent.width; spacing: Style.space(4)
              Repeater {
                model: m.selectedLots()
                Rectangle {
                  required property var modelData; required property int index
                  width: lotsColumn.width; height: Style.space(40); radius: Style.cornerRadius
                  color: Color.popups.background; border.color: Color.popups.border; border.width: 1
                  Row {
                    anchors.fill: parent; anchors.margins: Style.space(6); spacing: Style.space(12)
                    Text { width: Style.space(90); text: modelData.quantity + " units"; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
                    Text { width: Style.space(130); text: modelData.date || "Date not set"; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
                    Text { width: Style.space(140); text: modelData.price === null ? "Price not set" : "Cost " + modelData.price; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
                    ActionButton { label: "󰏫 Edit"; selected: m.detailSelection === 7 + index * 2; onTriggered: m.openLotForm(modelData) }
                    ActionButton { label: "󰆴 Remove"; selected: m.detailSelection === 8 + index * 2; onTriggered: m.requestRemoval("lot", modelData.id, "holding lot") }
                  }
                }
              }
            }
          }
        }

        Rectangle {
          opacity: m.mode === "action" ? 1 : 0
          visible: opacity > 0
          enabled: m.mode === "action"
          scale: m.mode === "action" ? 1 : 0.97
          Behavior on opacity { NumberAnimation { duration: m.motionDuration; easing.type: Easing.OutCubic } }
          Behavior on scale { NumberAnimation { duration: m.motionDuration; easing.type: Easing.OutCubic } }
          anchors.centerIn: parent
          width: Math.min(parent.width - Style.space(24), Style.space(520))
          height: actionColumn.implicitHeight + Style.space(28)
          radius: Style.cornerRadius * 2
          color: Color.popups.background
          border.color: Color.popups.border
          border.width: 1

          Column {
            id: actionColumn
            anchors.centerIn: parent
            width: parent.width - Style.space(28)
            spacing: Style.space(9)
            Text { text: "ASSET ACTIONS"; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
            Text { text: m.selectedSymbol; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
            Text { text: "Keep the overview calm; reveal changes only when you need them."; width: parent.width; wrapMode: Text.WordWrap; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall }
            ActionRow { label: "󰁍  Back to asset"; detail: "Return without changing anything"; selected: m.actionSelection === 0; onTriggered: m.goBack() }
            ActionRow { label: m.isFavorite(m.selectedSymbol) ? "󰓎  Remove favorite" : "󰓏  Add favorite"; detail: "Pin this asset in Market Pulse"; selected: m.actionSelection === 1; onTriggered: m.toggleFavorite() }
            ActionRow { label: "󰐕  Record purchase"; detail: "Add quantity, date and optional cost"; selected: m.actionSelection === 2; onTriggered: m.openLotForm(null) }
            ActionRow { label: "󰆴  Remove from Watchlist"; detail: "Requires confirmation and removes portfolio lots"; selected: m.actionSelection === 3; destructive: true; onTriggered: m.requestRemoval("symbol", "", m.selectedSymbol) }
          }
        }

        Column {
          opacity: m.mode === "form" ? 1 : 0
          visible: opacity > 0
          enabled: m.mode === "form"
          scale: m.mode === "form" ? 1 : 0.985
          Behavior on opacity { NumberAnimation { duration: m.motionDuration; easing.type: Easing.OutCubic } }
          Behavior on scale { NumberAnimation { duration: m.motionDuration; easing.type: Easing.OutCubic } }
          anchors.centerIn: parent
          width: Math.min(parent.width, Style.space(460))
          spacing: Style.space(10)
          Text { text: formKind === "symbol" ? "Add to watchlist" : (formKind === "editLot" ? "Edit purchase lot" : "Record purchase lot"); color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
          Text { visible: formKind !== "symbol"; text: selectedSymbol + " · quantity is required; date and purchase price are optional"; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall }

          TextField {
            id: symbolField
            visible: formKind === "symbol"
            width: parent.width; placeholderText: "Search company or symbol, e.g. Apple or AAPL"
            font.family: Style.fontFamily
            background: FieldBackground { selected: m.formSelection === 0 }
            onTextEdited: { m.searchResults = []; m.searchSelection = 0; m.searchError = ""; searchTimer.restart() }
            onAccepted: { if (m.searchResults.length > 0) m.chooseSearchResult(m.searchSelection); else m.searchAssets() }
            Keys.onDownPressed: function(event) { m.moveSearchSelection(1); event.accepted = true }
            Keys.onUpPressed: function(event) { m.moveSearchSelection(-1); event.accepted = true }
            Keys.onEscapePressed: function(event) { searchTimer.stop(); symbolField.focus = false; event.accepted = true }
          }
          ListView {
            id: searchList
            visible: formKind === "symbol" && searchResults.length > 0
            width: parent.width
            height: Math.min(contentHeight, Style.space(190))
            clip: true
            spacing: Style.space(4)
            model: m.searchResults
            currentIndex: m.searchSelection
            delegate: Rectangle {
              required property var modelData
              required property int index
              width: searchList.width
              height: Style.space(38)
              radius: Style.cornerRadius
              color: index === m.searchSelection ? Color.menu.selectedBackground : "transparent"
              border.color: index === m.searchSelection ? Color.accent : Color.popups.border
              border.width: 1
              Row {
                anchors.fill: parent
                anchors.margins: Style.space(7)
                spacing: Style.space(10)
                Text { width: Style.space(86); text: modelData.symbol; color: Color.accent; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true; elide: Text.ElideRight }
                Text { width: Math.max(0, parent.width - Style.space(230)); text: modelData.name; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall; elide: Text.ElideRight }
                Text { width: Style.space(110); text: modelData.exchange + (modelData.type ? " · " + modelData.type : ""); color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight; horizontalAlignment: Text.AlignRight }
              }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: m.chooseSearchResult(index) }
            }
          }
          Text {
            visible: formKind === "symbol" && (searching || searchError !== "")
            text: searching ? "Searching assets…" : searchError
            color: searchError ? Color.foreground : Color.muted
            font.family: Style.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          TextField {
            id: quantityField
            visible: formKind !== "symbol"
            width: parent.width; placeholderText: "Quantity (required; comma or dot decimal)"
            font.family: Style.fontFamily; inputMethodHints: Qt.ImhFormattedNumbersOnly
            background: FieldBackground { selected: m.formSelection === 0 }
            Keys.onEscapePressed: function(event) { quantityField.focus = false; event.accepted = true }
          }
          TextField {
            id: dateField
            visible: formKind !== "symbol"
            width: parent.width; placeholderText: "Purchase date (optional, YYYY-MM-DD)"
            font.family: Style.fontFamily
            background: FieldBackground { selected: m.formSelection === 1 }
            Keys.onEscapePressed: function(event) { dateField.focus = false; event.accepted = true }
          }
          TextField {
            id: priceField
            visible: formKind !== "symbol"
            width: parent.width; placeholderText: "Purchase price (optional; comma or dot decimal)"
            font.family: Style.fontFamily; inputMethodHints: Qt.ImhFormattedNumbersOnly
            background: FieldBackground { selected: m.formSelection === 2 }
            Keys.onEscapePressed: function(event) { priceField.focus = false; event.accepted = true }
          }
          Text { visible: errorMessage !== ""; text: errorMessage; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall }
          Row {
            spacing: Style.space(8)
            ActionButton { label: "Cancel"; selected: m.formSelection === (formKind === "symbol" ? 1 : 3); onTriggered: m.goBack() }
            ActionButton { label: formKind === "editLot" ? "Save changes" : "Save"; selected: m.formSelection === (formKind === "symbol" ? 2 : 4); onTriggered: m.saveForm() }
          }
        }

        Rectangle {
          opacity: m.mode === "confirm" ? 1 : 0
          visible: opacity > 0
          enabled: m.mode === "confirm"
          scale: m.mode === "confirm" ? 1 : 0.96
          Behavior on opacity { NumberAnimation { duration: m.motionDuration; easing.type: Easing.OutCubic } }
          Behavior on scale { NumberAnimation { duration: m.motionDuration; easing.type: Easing.OutBack } }
          anchors.centerIn: parent
          width: Math.min(parent.width - Style.space(40), Style.space(420))
          height: confirmColumn.implicitHeight + Style.space(28)
          radius: Style.cornerRadius
          color: Color.popups.background
          border.color: Color.accent
          border.width: 1
          Column {
            id: confirmColumn
            anchors.centerIn: parent
            width: parent.width - Style.space(28)
            spacing: Style.space(12)
            Text { text: "Confirm removal"; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
            Text { width: parent.width; wrapMode: Text.WordWrap; text: removalKind === "symbol" ? "Remove " + removalLabel + " and all of its purchase lots?" : "Remove this purchase lot?"; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.body }
            Text { text: "This destructive action cannot be undone."; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall }
            Row {
              spacing: Style.space(8)
              ActionButton { label: "Cancel"; selected: m.confirmSelection === 0; onTriggered: m.goBack() }
              ActionButton { label: "Remove"; selected: m.confirmSelection === 1; onTriggered: m.confirmRemoval() }
            }
          }
        }
      }
    }
  }

  component FieldBackground: Rectangle {
    property bool selected: false
    radius: Style.cornerRadius
    color: Color.menu.selectedBackground
    border.color: selected ? Color.accent : Color.popups.border
    border.width: 1
  }

  component ActionRow: Rectangle {
    id: actionRow
    property string label: ""
    property string detail: ""
    property bool selected: false
    property bool destructive: false
    signal triggered()
    width: parent ? parent.width : Style.space(320)
    height: Style.space(54)
    radius: Style.cornerRadius
    color: selected || rowMouse.containsMouse ? Color.menu.selectedBackground : "transparent"
    border.color: selected ? Color.accent : Color.popups.border
    border.width: selected ? 2 : 1
    Behavior on color { ColorAnimation { duration: m.motionDuration } }
    Column {
      anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(11); anchors.rightMargin: Style.space(11); spacing: Style.space(2)
      Text { text: actionRow.label; color: actionRow.destructive && actionRow.selected ? Color.accent : Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
      Text { width: parent.width; text: actionRow.detail; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
    }
    MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: actionRow.triggered() }
  }

  component ActionButton: Rectangle {
    id: actionButton
    property string label: ""
    property bool selected: false
    signal triggered()
    width: actionLabel.implicitWidth + Style.space(18)
    height: Style.space(30)
    radius: Style.cornerRadius
    color: selected || actionMouse.containsMouse ? Color.menu.selectedBackground : Color.popups.background
    border.color: selected ? Color.accent : Color.popups.border
    border.width: 1
    Text { id: actionLabel; anchors.centerIn: parent; text: actionButton.label; color: actionButton.selected ? Color.accent : Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall }
    MouseArea { id: actionMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: actionButton.triggered() }
  }
}
