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

  property string mode: "list"
  property string previousMode: "list"
  property bool loading: false
  property string errorMessage: ""
  property var assets: []
  property var holdings: ({})
  property string selectedSymbol: ""
  property string selectedRange: "1M"
  property var chartPoints: []
  property bool chartStale: false
  property int listSelection: 0
  property int detailSelection: 0
  property int formSelection: 0
  property int confirmSelection: 0
  property string formKind: "symbol"
  property string editingLotId: ""
  property string removalKind: ""
  property string removalId: ""
  property string removalLabel: ""
  property string notchIcon: "󰄪"
  property string notchText: assets.length > 0 && !assets[0].error
                                      ? assets[0].symbol + " " + formatPrice(assets[0].price, assets[0].currency)
                                      : assets.length + " assets"
  readonly property var ranges: ["1D", "1W", "1M", "3M", "1Y"]
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
      ctx.strokeStyle = Color.accent
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

  function refreshMarkets(force) {
    if (!root || !root.opened || !m.visible || loading) return
    loading = true
    errorMessage = ""
    exec(force ? ["refresh", "--force"] : ["refresh"], function (out) {
      loading = false
      parseResult(out, function (result) {
        assets = result.assets || []
        holdings = result.holdings || ({})
        if (assets.length > 0 && assets.every(function (asset) { return !!asset.error }))
          errorMessage = "Unable to refresh prices"
        listSelection = Math.min(listSelection, assets.length + 1)
        pushNotch()
      })
    })
  }

  function pushNotch() {
    if (root && pluginKey && root.updateNotchData)
      root.updateNotchData(pluginKey, m.notchIcon, m.notchText)
  }

  function selectedAsset() {
    for (var i = 0; i < assets.length; i++) if (assets[i].symbol === selectedSymbol) return assets[i]
    return null
  }

  function selectedLots() {
    return holdings[selectedSymbol] || []
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

  function openSymbolForm() {
    previousMode = "list"
    formKind = "symbol"
    formSelection = 0
    symbolField.text = ""
    mode = "form"
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
      mutate(["add-symbol", symbolField.text], function () { mode = "list" })
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
    detailSelection = 0
    mode = "detail"
    loadChart(false)
  }

  function loadChart(force) {
    if (!root || !root.opened || !m.visible || !selectedSymbol) return
    loading = true
    var args = ["chart", selectedSymbol, selectedRange]
    if (force) args.push("--force")
    exec(args, function (out) {
      loading = false
      parseResult(out, function (result) {
        chartPoints = (result.points || []).map(function (point) { return point.value })
        chartStale = !!result.stale
      })
    })
  }

  function chooseRange(value) {
    selectedRange = value
    loadChart(false)
  }

  function reorderSelected(delta) {
    var row = listSelection - 2
    if (row < 0 || row >= assets.length) return
    exec(["reorder", assets[row].symbol, String(delta)], function () { refreshMarkets(true) })
  }

  function requestRemoval(kind, id, label) {
    previousMode = mode
    removalKind = kind
    removalId = id || ""
    removalLabel = label || ""
    confirmSelection = 0
    mode = "confirm"
  }

  function confirmRemoval() {
    if (removalKind === "symbol")
      mutate(["remove-symbol", selectedSymbol || removalLabel, "confirm"], function () { selectedSymbol = ""; mode = "list" })
    else if (removalKind === "lot")
      mutate(["remove-lot", selectedSymbol, removalId], function () { mode = "detail" })
  }

  function goBack() {
    if (mode === "confirm") mode = previousMode
    else if (mode === "form") mode = previousMode
    else if (mode === "detail") mode = "list"
    else return false
    return true
  }

  function moveListSelection(dx, dy) {
    if (dx !== 0 && listSelection >= 2) { reorderSelected(dx > 0 ? 1 : -1); return true }
    var step = dy !== 0 ? (dy > 0 ? 1 : -1) : (dx > 0 ? 1 : -1)
    listSelection = (listSelection + step + assets.length + 2) % (assets.length + 2)
    return true
  }

  function moveDetailSelection(dx, dy) {
    var count = 7 + selectedLots().length * 2
    var step = (dy !== 0 ? dy : dx) > 0 ? 1 : -1
    detailSelection = (detailSelection + step + count) % count
    return true
  }

  function moveFormSelection(dx, dy) {
    var count = formKind === "symbol" ? 3 : 5
    var step = (dy !== 0 ? dy : dx) > 0 ? 1 : -1
    formSelection = (formSelection + step + count) % count
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
    if (detailSelection === 6) { openLotForm(null); return }
    var lotIndex = Math.floor((detailSelection - 7) / 2)
    var lots = selectedLots()
    if (!lots[lotIndex]) return
    if ((detailSelection - 7) % 2 === 0) openLotForm(lots[lotIndex])
    else requestRemoval("lot", lots[lotIndex].id, "holding lot")
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
      if (mode === "list" && listSelection >= 2) {
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
      if (mode === "list") return moveListSelection(payload.dx || 0, payload.dy || 0)
      if (mode === "detail") return moveDetailSelection(payload.dx || 0, payload.dy || 0)
      if (mode === "form") return moveFormSelection(payload.dx || 0, payload.dy || 0)
      if (mode === "confirm") { confirmSelection = confirmSelection === 0 ? 1 : 0; return true }
    }
    if (action === "activate") {
      if (mode === "list") activateList()
      else if (mode === "detail") activateDetail()
      else if (mode === "form") activateForm()
      else if (mode === "confirm") { if (confirmSelection === 0) goBack(); else confirmRemoval() }
      return true
    }
    return false
  }

  onNotchTextChanged: pushNotch()
  onRootChanged: if (root && root.opened && m.visible) refreshMarkets(false)
  onVisibleChanged: if (visible && root && root.opened) refreshMarkets(false)
  Connections {
    target: root
    function onOpenedChanged() {
      if (root && root.opened && m.visible) m.refreshMarkets(false)
    }
  }
  Timer {
    interval: 300000
    repeat: true
    running: m.visible && root && root.opened
    onTriggered: m.refreshMarkets(false)
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
        Text { text: mode === "detail" ? selectedSymbol : (mode === "form" ? (formKind === "symbol" ? "Add symbol" : "Purchase lot") : "Markets"); color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.title; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
        Item { width: Math.max(0, parent.width - Style.space(260)); height: 1 }
        Text { visible: loading; text: "Loading…"; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
      }

      Item {
        width: parent.width
        height: parent.height - Style.space(48)

        Column {
          visible: m.mode === "list"
          anchors.fill: parent
          spacing: Style.space(8)

          Row {
            width: parent.width
            height: Style.space(34)
            spacing: Style.space(8)
            ActionButton { label: "＋ Add symbol"; selected: m.listSelection === 0; onTriggered: m.openSymbolForm() }
            ActionButton { label: "󰑐 Refresh"; selected: m.listSelection === 1; onTriggered: m.refreshMarkets(true) }
            Text { text: "←/→ reorder  ·  Enter details  ·  x remove"; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
          }

          Text { visible: errorMessage !== ""; text: errorMessage + (assets.length ? " · showing cached data where available" : ""); color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall }
          Text { visible: !loading && assets.length === 0; text: "Your watchlist is empty. Add a symbol to begin."; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.body }

          Flickable {
            width: parent.width
            height: parent.height - Style.space(100)
            contentHeight: assetColumn.implicitHeight
            clip: true
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
                  border.color: modelData.stale ? Color.accent : Color.popups.border
                  border.width: 1

                  MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: m.openDetail(modelData.symbol) }
                  Row {
                    anchors.fill: parent
                    anchors.margins: Style.space(9)
                    spacing: Style.space(12)
                    Column {
                      width: Style.space(92); anchors.verticalCenter: parent.verticalCenter
                      Text { text: modelData.symbol; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
                      Text { text: modelData.stale ? "cached" : (modelData.error ? "unavailable" : modelData.currency); color: modelData.stale ? Color.accent : Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.caption }
                    }
                    Sparkline { width: Style.space(128); height: Style.space(42); anchors.verticalCenter: parent.verticalCenter; values: modelData.sparkline || [] }
                    Column {
                      width: Style.space(112); anchors.verticalCenter: parent.verticalCenter
                      Text { text: m.formatPrice(modelData.price, modelData.currency); color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
                      Text { text: modelData.error ? modelData.error : m.signed(modelData.dayChangePct, "% today"); color: modelData.dayChange >= 0 ? Color.accent : Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight; width: parent.width }
                    }
                    Column {
                      visible: modelData.quantity > 0
                      width: Style.space(150); anchors.verticalCenter: parent.verticalCenter
                      Text { text: "Position " + m.formatPrice(modelData.marketValue, modelData.currency); color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall }
                      Text { text: modelData.gain === null ? "Cost basis incomplete" : "Gain " + m.signed(modelData.gain, "") + " " + modelData.currency + " (" + m.signed(modelData.gainPct, "%") + ")"; color: modelData.gain >= 0 ? Color.accent : Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.caption }
                    }
                    ActionButton { label: "󰁝"; selected: false; onTriggered: { m.listSelection = index + 2; m.reorderSelected(-1) } }
                    ActionButton { label: "󰁅"; selected: false; onTriggered: { m.listSelection = index + 2; m.reorderSelected(1) } }
                    Text { text: "󰁔"; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.body; anchors.verticalCenter: parent.verticalCenter }
                  }
                }
              }
            }
          }
          Text { text: "Unofficial Yahoo Finance chart data · best-effort availability · cached fallback"; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.caption }
        }

        Column {
          visible: m.mode === "detail"
          anchors.fill: parent
          spacing: Style.space(8)
          Row {
            width: parent.width; height: Style.space(32); spacing: Style.space(6)
            ActionButton { label: "󰁍 Back"; selected: m.detailSelection === 0; onTriggered: m.goBack() }
            Repeater {
              model: m.ranges
              ActionButton { required property string modelData; required property int index; label: modelData; selected: m.selectedRange === modelData || m.detailSelection === index + 1; onTriggered: m.chooseRange(modelData) }
            }
            ActionButton { label: "＋ Purchase"; selected: m.detailSelection === 6; onTriggered: m.openLotForm(null) }
            ActionButton { label: "󰆴 Asset"; selected: false; onTriggered: m.requestRemoval("symbol", "", m.selectedSymbol) }
          }

          Text { visible: m.chartStale; text: "Chart is cached; live provider unavailable."; color: Color.accent; font.family: Style.fontFamily; font.pixelSize: Style.font.caption }
          Sparkline { width: parent.width; height: Style.space(190); values: m.chartPoints; large: true }

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
            width: parent.width; height: Style.space(150); contentHeight: lotsColumn.implicitHeight; clip: true
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

        Column {
          visible: m.mode === "form"
          anchors.centerIn: parent
          width: Math.min(parent.width, Style.space(460))
          spacing: Style.space(10)
          Text { text: formKind === "symbol" ? "Add to watchlist" : (formKind === "editLot" ? "Edit purchase lot" : "Record purchase lot"); color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
          Text { visible: formKind !== "symbol"; text: selectedSymbol + " · quantity is required; date and purchase price are optional"; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall }

          TextField {
            id: symbolField
            visible: formKind === "symbol"
            width: parent.width; placeholderText: "Symbol, e.g. AAPL"
            font.family: Style.fontFamily
            background: FieldBackground { selected: m.formSelection === 0 }
            onAccepted: m.saveForm()
            Keys.onEscapePressed: function(event) { symbolField.focus = false; event.accepted = true }
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
          visible: m.mode === "confirm"
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
