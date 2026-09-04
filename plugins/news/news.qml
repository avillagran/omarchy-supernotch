pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: m
  property var root: null
  property string pluginKey: ""
  width: parent ? parent.width : Style.space(900)
  implicitHeight: Style.space(510)

  property var sources: []
  property var articles: []
  property string selectedSource: "all"
  property string screen: "articles" // articles | reader | sources | add | confirm
  property int cursor: 0
  property int readerAction: 0
  property int sourceAction: 0
  property int confirmChoice: 0
  property var currentArticle: null
  property string pendingDeleteId: ""
  property string pendingDeleteName: ""
  property bool refreshing: false
  property string statusText: ""
  property double lastRefreshAt: 0
  readonly property bool pluginVisible: root && root.opened && visible && root.activePluginItem === m
  property bool keyboardNavigationBlocked: addUrlField.activeFocus || addNameField.activeFocus || filterField.activeFocus
  property string notchIcon: "󰓰"
  property string notchText: unreadCount + (root && root.uiLang === "es" ? " sin leer" : " unread")
  readonly property int unreadCount: articles.filter(function (article) { return article.unread }).length
  readonly property var filteredArticles: filterArticles()

  function tr(en, es) { return root && root.uiLang === "es" ? es : en }

  function exec(args, callback) {
    if (!root || !pluginKey) return
    root.run(["plugin-exec", pluginKey].concat(args), function (out) {
      if (callback) callback(out || "")
    })
  }

  function parseOutput(out, fallback) {
    try { return JSON.parse((out || "").trim()) } catch (error) { return fallback }
  }

  function pushNotch() {
    if (root && pluginKey) root.updateNotchData(pluginKey, notchIcon, notchText)
  }

  function loadData() {
    exec(["sources"], function (out) { m.sources = m.parseOutput(out, m.sources) })
    exec(["articles"], function (out) {
      m.articles = m.parseOutput(out, m.articles)
      m.clampCursor()
      m.pushNotch()
    })
  }

  function refreshAll() {
    if (!pluginVisible || refreshing) return
    refreshing = true
    statusText = tr("Refreshing…", "Actualizando…")
    exec(["refresh"], function (out) {
      var result = m.parseOutput(out, null)
      m.refreshing = false
      m.lastRefreshAt = Date.now()
      if (!result) {
        m.statusText = m.tr("Refresh failed · showing cache", "Falló la actualización · mostrando caché")
        m.loadData()
        return
      }
      m.sources = result.sources || m.sources
      m.articles = result.articles || []
      var failures = Object.keys(result.errors || {}).length
      m.statusText = failures > 0
        ? m.tr("Some feeds are offline · cached stories kept", "Algunas fuentes no responden · se conservó la caché")
        : m.tr("Updated now", "Actualizado ahora")
      m.clampCursor()
      m.pushNotch()
    })
  }

  function filterArticles() {
    var query = filterField ? filterField.text.trim().toLowerCase() : ""
    return articles.filter(function (article) {
      if (selectedSource !== "all" && article.sourceId !== selectedSource) return false
      if (!query) return true
      return String(article.title + " " + article.summary + " " + article.sourceName).toLowerCase().indexOf(query) >= 0
    })
  }

  function clampCursor() {
    var count = screen === "sources" ? sources.length : filteredArticles.length
    cursor = Math.max(0, Math.min(cursor, Math.max(0, count - 1)))
    if (screen === "articles" && articleList) articleList.positionViewAtIndex(cursor, ListView.Contain)
    if (screen === "sources" && sourceList) sourceList.positionViewAtIndex(cursor, ListView.Contain)
  }

  function cycleSource(delta) {
    var choices = [{ id: "all" }].concat(sources.filter(function (source) { return source.enabled }))
    var index = choices.findIndex(function (source) { return source.id === selectedSource })
    if (index < 0) index = 0
    index = (index + delta + choices.length) % choices.length
    selectedSource = choices[index].id
    cursor = 0
  }

  function revealSelectedSource() {
    if (!sourceStrip || !sourceChips) return
    var enabled = sources.filter(function (source) { return source.enabled })
    var index = enabled.findIndex(function (source) { return source.id === selectedSource })
    var item = selectedSource === "all" ? allChip : sourceRepeater.itemAt(index)
    if (!item) return
    var margin = Style.space(8)
    var target = sourceStrip.contentX
    if (item.x < target + margin) target = Math.max(0, item.x - margin)
    else if (item.x + item.width > target + sourceStrip.width - margin)
      target = Math.min(Math.max(0, sourceStrip.contentWidth - sourceStrip.width), item.x + item.width - sourceStrip.width + margin)
    sourceStripScroll.stop()
    sourceStripScroll.from = sourceStrip.contentX
    sourceStripScroll.to = target
    sourceStripScroll.start()
  }

  function openArticle(index) {
    if (index < 0 || index >= filteredArticles.length) return
    currentArticle = filteredArticles[index]
    screen = "reader"
    readerAction = 0
    readerScroll.contentY = 0
    if (currentArticle.unread) markArticle(currentArticle, false)
  }

  function markArticle(article, unread) {
    if (!article) return
    exec(["mark", article.id, unread ? "unread" : "read"], function () {
      var changed = m.articles.slice()
      for (var index = 0; index < changed.length; index++) {
        if (changed[index].id === article.id) {
          changed[index].unread = unread
          if (m.currentArticle && m.currentArticle.id === changed[index].id) m.currentArticle = changed[index]
          break
        }
      }
      m.articles = changed
      m.pushNotch()
    })
  }

  function canOpenExternal(article) {
    if (!article || !article.link) return false
    return sources.some(function (source) { return source.id === article.sourceId && source.builtin })
  }

  function readerActions() {
    var actions = [tr("Back", "Volver"), currentArticle && currentArticle.unread ? tr("Mark read", "Marcar leída") : tr("Mark unread", "Marcar no leída")]
    if (canOpenExternal(currentArticle)) actions.push(tr("Open original", "Abrir original"))
    return actions
  }

  function openExternal(article) {
    if (!canOpenExternal(article)) return
    exec(["open", article.id], function () {})
  }

  function showArticles() {
    screen = "articles"
    currentArticle = null
    clampCursor()
  }

  function showSources() { screen = "sources"; cursor = 0; sourceAction = 0 }
  function showAdd() { screen = "add"; cursor = 0; addUrlField.text = ""; addNameField.text = ""; statusText = "" }

  function addSource() {
    var url = addUrlField.text.trim()
    if (!url) { statusText = tr("Enter a feed URL", "Ingresa la URL del feed"); return }
    exec(["add-source", url, addNameField.text.trim()], function (out) {
      var added = m.parseOutput(out, null)
      if (!added) { m.statusText = m.tr("Invalid or duplicate URL", "URL inválida o duplicada"); return }
      m.statusText = m.tr("Source added", "Fuente agregada")
      m.showSources()
      m.loadData()
    })
  }

  function activateSource(index, action) {
    if (index < 0 || index >= sources.length) return
    var source = sources[index]
    var selectedAction = action === undefined ? sourceAction : action
    if (selectedAction === 0) {
      exec(["toggle-source", source.id], function (out) { m.sources = m.parseOutput(out, m.sources); m.loadData() })
    } else if (selectedAction === 1 && !source.builtin) {
      exec(["move-source", source.id, "-1"], function (out) { m.sources = m.parseOutput(out, m.sources); m.cursor = Math.max(0, m.cursor - 1) })
    } else if (selectedAction === 2 && !source.builtin) {
      exec(["move-source", source.id, "1"], function (out) { m.sources = m.parseOutput(out, m.sources); m.cursor = Math.min(m.sources.length - 1, m.cursor + 1) })
    } else if (selectedAction === 3 && !source.builtin) {
      beginDelete(source)
    }
  }

  function beginDelete(source) {
    if (!source || source.builtin) return
    pendingDeleteId = source.id
    pendingDeleteName = source.name
    confirmChoice = 0
    screen = "confirm"
  }

  function confirmDelete(accepted) {
    if (!accepted) { screen = "sources"; return }
    exec(["remove-source", pendingDeleteId], function (out) {
      m.sources = m.parseOutput(out, m.sources)
      m.pendingDeleteId = ""
      m.screen = "sources"
      m.clampCursor()
      m.loadData()
    })
  }

  function goBack() {
    if (screen === "articles") return false
    if (screen === "reader") showArticles()
    else if (screen === "confirm") screen = "sources"
    else if (screen === "add") screen = "sources"
    else screen = "articles"
    return true
  }

  function moveCursor(delta) {
    cursor += delta
    clampCursor()
  }

  function activateCurrent() {
    if (screen === "articles") openArticle(cursor)
    else if (screen === "reader") {
      if (readerAction === 0) showArticles()
      else if (readerAction === 1) markArticle(currentArticle, !currentArticle.unread)
      else openExternal(currentArticle)
    } else if (screen === "sources") activateSource(cursor)
    else if (screen === "confirm") confirmDelete(confirmChoice === 1)
    else if (screen === "add") {
      if (cursor === 0) addUrlField.forceActiveFocus()
      else if (cursor === 1) addNameField.forceActiveFocus()
      else if (cursor === 2) addSource()
      else screen = "sources"
    }
  }

  function handleKeyboardAction(action, payload) {
    if (action === "back") return goBack()
    if (action === "move") {
      var dx = payload.dx || 0
      var dy = payload.dy || 0
      if (screen === "articles") {
        if (dy) moveCursor(dy > 0 ? 1 : -1)
        else if (dx) cycleSource(dx > 0 ? 1 : -1)
      } else if (screen === "reader") {
        if (dy) readerScroll.scrollBy(dy > 0 ? Style.space(96) : -Style.space(96))
        else if (dx) {
          var readerCount = readerActions().length
          readerAction = (readerAction + (dx > 0 ? 1 : -1) + readerCount) % readerCount
        }
      } else if (screen === "sources") {
        if (dy) { moveCursor(dy > 0 ? 1 : -1); sourceAction = 0 }
        else if (dx) {
          var actionCount = sources[cursor] && sources[cursor].builtin ? 1 : 4
          sourceAction = (sourceAction + (dx > 0 ? 1 : -1) + actionCount) % actionCount
        }
      } else if (screen === "confirm" && (dx || dy)) confirmChoice = confirmChoice ? 0 : 1
      else if (screen === "add" && (dx || dy)) cursor = (cursor + ((dx > 0 || dy > 0) ? 1 : -1) + 4) % 4
      return true
    }
    if (action === "activate") { activateCurrent(); return true }
    if (action === "delete") {
      if (screen === "sources" && sources[cursor] && !sources[cursor].builtin) beginDelete(sources[cursor])
      return true
    }
    if (action === "text") {
      if (payload.text === "j") return handleKeyboardAction("move", { dx: 0, dy: 1 })
      if (payload.text === "k") return handleKeyboardAction("move", { dx: 0, dy: -1 })
      if (payload.text === "h" || payload.text === "b") { if (!goBack() && screen === "articles") cycleSource(-1); return true }
      if (payload.text === "l") { if (screen === "articles") cycleSource(1); else handleKeyboardAction("move", { dx: 1, dy: 0 }); return true }
      if (payload.text === "x") { return handleKeyboardAction("delete", {}) }
      if (payload.text === "r" && screen === "articles") { refreshAll(); return true }
      if (payload.text === "s" && screen === "articles") { showSources(); return true }
      if (payload.text === "a" && (screen === "articles" || screen === "sources")) { showAdd(); return true }
      if (payload.text === "f" && screen === "articles") { filterField.forceActiveFocus(); return true }
      if (payload.text === "u" && screen === "articles" && filteredArticles[cursor]) { markArticle(filteredArticles[cursor], !filteredArticles[cursor].unread); return true }
      if (payload.text === "o" && screen === "reader") { openExternal(currentArticle); return true }
    }
    return false
  }

  onUnreadCountChanged: pushNotch()
  onPluginVisibleChanged: if (pluginVisible) { loadData(); if (Date.now() - lastRefreshAt > 900000) refreshAll() }
  onSelectedSourceChanged: Qt.callLater(m.revealSelectedSource)
  Component.onCompleted: loadData()

  Timer {
    interval: 15 * 60 * 1000
    running: m.pluginVisible
    repeat: true
    onTriggered: m.refreshAll()
  }

  Rectangle {
    anchors.fill: parent
    color: "transparent"

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(14)
      spacing: Style.space(10)

      Row {
        width: parent.width
        height: Style.space(34)
        spacing: Style.space(8)

        Text {
          width: Style.space(150)
          anchors.verticalCenter: parent.verticalCenter
          text: screen === "articles" ? tr("News", "Noticias") : screen === "reader" ? tr("Reader", "Lector") : tr("Sources", "Fuentes")
          color: Color.foreground
          font.family: Style.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        TextField {
          id: filterField
          visible: screen === "articles"
          width: parent.width - Style.space(430)
          height: parent.height
          placeholderText: m.tr("Filter stories (f)", "Filtrar noticias (f)")
          color: Color.foreground
          font.family: Style.fontFamily
          background: Rectangle { radius: Style.cornerRadius; color: Color.menu.selectedBackground; border.color: filterField.activeFocus ? Color.accent : Color.popups.border }
          onTextChanged: { m.cursor = 0; m.clampCursor() }
          Keys.onEscapePressed: function (event) { filterField.focus = false; event.accepted = true }
        }

        Rectangle {
          visible: screen === "articles"
          width: Style.space(82); height: parent.height; radius: Style.cornerRadius
          color: sourceHeaderMouse.containsMouse ? Color.menu.selectedBackground : "transparent"
          border.color: Color.popups.border
          Text { anchors.centerIn: parent; text: m.tr("Sources", "Fuentes"); color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall }
          MouseArea { id: sourceHeaderMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: m.showSources() }
        }
        Rectangle {
          visible: screen === "articles"
          width: Style.space(78); height: parent.height; radius: Style.cornerRadius
          color: refreshMouse.containsMouse ? Color.menu.selectedBackground : "transparent"
          border.color: Color.popups.border
          Text { anchors.centerIn: parent; text: m.refreshing ? "󰑐" : "󰑐  " + m.tr("Refresh", "Actualizar"); color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall }
          MouseArea { id: refreshMouse; anchors.fill: parent; hoverEnabled: true; enabled: !m.refreshing; cursorShape: Qt.PointingHandCursor; onClicked: m.refreshAll() }
        }
        Rectangle {
          visible: screen !== "articles"
          width: Style.space(74); height: parent.height; radius: Style.cornerRadius
          color: backMouse.containsMouse ? Color.menu.selectedBackground : "transparent"
          border.color: Color.popups.border
          Text { anchors.centerIn: parent; text: "󰁍  " + m.tr("Back", "Volver"); color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall }
          MouseArea { id: backMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: m.goBack() }
        }
      }

      Flickable {
        id: sourceStrip
        visible: screen === "articles"
        width: parent.width
        height: Style.space(28)
        contentWidth: sourceChips.width
        contentHeight: height
        clip: true
        interactive: contentWidth > width
        boundsBehavior: Flickable.StopAtBounds
        Row {
          id: sourceChips
          width: implicitWidth
          height: parent.height
          spacing: Style.space(6)
          Rectangle {
            id: allChip
            width: allLabel.implicitWidth + Style.space(18); height: parent.height; radius: height / 2
            color: selectedSource === "all" ? Color.accent : Color.menu.selectedBackground
            Text { id: allLabel; anchors.centerIn: parent; text: m.tr("All", "Todas"); color: selectedSource === "all" ? Color.background : Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.caption }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { m.selectedSource = "all"; m.cursor = 0 } }
          }
          Repeater {
            id: sourceRepeater
            model: m.sources.filter(function (source) { return source.enabled })
            Rectangle {
              required property var modelData
              width: chipLabel.implicitWidth + Style.space(18); height: sourceChips.height; radius: height / 2
              color: m.selectedSource === modelData.id ? Color.accent : Color.menu.selectedBackground
              Text { id: chipLabel; anchors.centerIn: parent; text: modelData.name; color: m.selectedSource === modelData.id ? Color.background : Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.caption }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { m.selectedSource = modelData.id; m.cursor = 0 } }
            }
          }
        }
        NumberAnimation { id: sourceStripScroll; target: sourceStrip; property: "contentX"; duration: 180; easing.type: Easing.OutCubic }
      }

      Item {
        width: parent.width
        height: parent.height - Style.space(screen === "articles" ? 106 : 68)

        ListView {
          id: articleList
          anchors.fill: parent
          opacity: screen === "articles" ? 1 : 0
          visible: opacity > 0
          enabled: screen === "articles"
          scale: screen === "articles" ? 1 : 0.985
          Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
          Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
          clip: true
          spacing: Style.space(5)
          model: m.filteredArticles
          currentIndex: m.cursor
          delegate: Rectangle {
            required property int index
            required property var modelData
            width: articleList.width
            height: Style.space(70)
            radius: Style.cornerRadius
            color: index === m.cursor ? Color.menu.selectedBackground : (articleMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05) : "transparent")
            border.color: index === m.cursor ? Color.accent : Color.popups.border
            border.width: index === m.cursor ? 1 : 0
            Rectangle { x: Style.space(8); anchors.verticalCenter: parent.verticalCenter; width: Style.space(6); height: Style.space(6); radius: width / 2; color: modelData.unread ? Color.accent : Color.muted }
            Column {
              x: Style.space(24); y: Style.space(8); width: parent.width - Style.space(36); spacing: Style.space(3)
              Text { width: parent.width; text: modelData.title; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.body; font.bold: modelData.unread; elide: Text.ElideRight }
              Text { width: parent.width; text: modelData.sourceName + "  ·  " + m.formatDate(modelData.date); color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
              Text { width: parent.width; text: modelData.summary; visible: text.length > 0; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
            }
            MouseArea { id: articleMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: m.openArticle(index) }
          }
          Text { anchors.centerIn: parent; visible: m.filteredArticles.length === 0; text: m.tr("No cached stories. Refresh to load feeds.", "No hay noticias en caché. Actualiza para cargar fuentes."); color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.body }
        }

        Flickable {
          id: readerScroll
          anchors.fill: parent
          opacity: screen === "reader" ? 1 : 0
          visible: opacity > 0
          enabled: screen === "reader"
          scale: screen === "reader" ? 1 : 0.985
          Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
          Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
          clip: true
          contentHeight: readerColumn.implicitHeight
          boundsBehavior: Flickable.StopAtBounds
          function scrollBy(delta) {
            var maxY = Math.max(0, contentHeight - height)
            readerKeyScroll.stop()
            readerKeyScroll.from = contentY
            readerKeyScroll.to = Math.max(0, Math.min(maxY, contentY + delta))
            readerKeyScroll.start()
          }
          NumberAnimation {
            id: readerKeyScroll
            target: readerScroll
            property: "contentY"
            duration: 160
            easing.type: Easing.OutCubic
          }
          Column {
            id: readerColumn
            width: readerScroll.width
            spacing: Style.space(12)
            Row {
              spacing: Style.space(8)
              Repeater {
                model: m.readerActions()
                Rectangle {
                  required property int index
                  required property string modelData
                  width: actionText.implicitWidth + Style.space(20); height: Style.space(30); radius: Style.cornerRadius
                  color: index === m.readerAction ? Color.accent : Color.menu.selectedBackground
                  Text { id: actionText; anchors.centerIn: parent; text: modelData; color: index === m.readerAction ? Color.background : Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall }
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { m.readerAction = index; m.activateCurrent() } }
                }
              }
            }
            Text { width: parent.width; text: currentArticle ? currentArticle.title : ""; wrapMode: Text.Wrap; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.display; font.bold: true }
            Text { width: parent.width; text: currentArticle ? currentArticle.sourceName + "  ·  " + m.formatDate(currentArticle.date) : ""; color: Color.accent; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall }
            Text { width: parent.width; text: currentArticle ? (currentArticle.content || currentArticle.summary || m.tr("No article text is available. Open the original.", "No hay texto disponible. Abre el original.")) : ""; wrapMode: Text.Wrap; color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.body; lineHeight: 1.3 }
          }
        }

        Column {
          anchors.fill: parent
          opacity: screen === "sources" ? 1 : 0
          visible: opacity > 0
          enabled: screen === "sources"
          scale: screen === "sources" ? 1 : 0.985
          Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
          Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
          spacing: Style.space(8)
          Row {
            spacing: Style.space(8)
            Text { anchors.verticalCenter: parent.verticalCenter; text: m.tr("←/→ action · Enter apply · x delete", "←/→ acción · Enter aplicar · x eliminar"); color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.caption }
            Rectangle {
              width: Style.space(112); height: Style.space(28); radius: Style.cornerRadius; color: Color.accent
              Text { anchors.centerIn: parent; text: "＋ " + m.tr("Add feed", "Agregar fuente"); color: Color.background; font.family: Style.fontFamily; font.pixelSize: Style.font.bodySmall }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: m.showAdd() }
            }
          }
          ListView {
            id: sourceList
            width: parent.width; height: parent.height - Style.space(38); clip: true; spacing: Style.space(4)
            model: m.sources
            currentIndex: m.cursor
            delegate: Rectangle {
              id: sourceDelegate
              required property int index
              required property var modelData
              width: sourceList.width; height: Style.space(48); radius: Style.cornerRadius
              color: index === m.cursor ? Color.menu.selectedBackground : "transparent"
              border.color: index === m.cursor ? Color.accent : Color.popups.border
              Text { x: Style.space(12); anchors.verticalCenter: parent.verticalCenter; width: parent.width - Style.space(260); text: modelData.name + (modelData.builtin ? "  ·  " + m.tr("built-in", "incluida") : ""); color: modelData.enabled ? Color.foreground : Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
              Row {
                anchors.right: parent.right; anchors.rightMargin: Style.space(8); anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(4)
                Repeater {
                  model: [modelData.enabled ? "󰈈" : "󰈉", "󰁝", "󰁅", "󰆴"]
                  Rectangle {
                    required property int index
                    required property string modelData
                    width: Style.space(36); height: Style.space(30); radius: Style.cornerRadius
                    visible: index === 0 || !sourceDelegate.modelData.builtin
                    color: sourceList.currentIndex === sourceDelegate.index && m.sourceAction === index ? Color.accent : Color.menu.selectedBackground
                    Text { anchors.centerIn: parent; text: modelData; color: sourceList.currentIndex === sourceDelegate.index && m.sourceAction === index ? Color.background : Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.body }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { m.cursor = sourceDelegate.index; m.sourceAction = index; m.activateSource(m.cursor, index) } }
                  }
                }
              }
              MouseArea { anchors.left: parent.left; anchors.right: parent.right; anchors.rightMargin: Style.space(180); height: parent.height; onClicked: { m.cursor = index; m.sourceAction = 0; m.activateSource(index, 0) } }
            }
          }
        }

        Column {
          anchors.centerIn: parent
          opacity: screen === "add" ? 1 : 0
          visible: opacity > 0
          enabled: screen === "add"
          scale: screen === "add" ? 1 : 0.96
          Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
          Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
          width: Math.min(parent.width, Style.space(560))
          spacing: Style.space(10)
          Text { text: m.tr("Add RSS or Atom feed", "Agregar fuente RSS o Atom"); color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
          TextField {
            id: addUrlField
            width: parent.width; height: Style.space(38); placeholderText: "https://example.com/feed.xml"
            color: Color.foreground; font.family: Style.fontFamily
            background: Rectangle { radius: Style.cornerRadius; color: Color.menu.selectedBackground; border.color: m.cursor === 0 ? Color.accent : Color.popups.border }
            onAccepted: { focus = false; m.cursor = 1; addNameField.forceActiveFocus() }
            Keys.onEscapePressed: function (event) { addUrlField.focus = false; event.accepted = true }
          }
          TextField {
            id: addNameField
            width: parent.width; height: Style.space(38); placeholderText: m.tr("Name (optional)", "Nombre (opcional)")
            color: Color.foreground; font.family: Style.fontFamily
            background: Rectangle { radius: Style.cornerRadius; color: Color.menu.selectedBackground; border.color: m.cursor === 1 ? Color.accent : Color.popups.border }
            onAccepted: { focus = false; m.cursor = 2; m.addSource() }
            Keys.onEscapePressed: function (event) { addNameField.focus = false; event.accepted = true }
          }
          Row {
            spacing: Style.space(8)
            Rectangle {
              width: Style.space(100); height: Style.space(32); radius: Style.cornerRadius; color: m.cursor === 2 ? Color.accent : Color.menu.selectedBackground
              Text { anchors.centerIn: parent; text: m.tr("Add", "Agregar"); color: m.cursor === 2 ? Color.background : Color.foreground; font.family: Style.fontFamily }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: m.addSource() }
            }
            Rectangle {
              width: Style.space(100); height: Style.space(32); radius: Style.cornerRadius; color: m.cursor === 3 ? Color.accent : Color.menu.selectedBackground
              Text { anchors.centerIn: parent; text: m.tr("Cancel", "Cancelar"); color: m.cursor === 3 ? Color.background : Color.foreground; font.family: Style.fontFamily }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: m.showSources() }
            }
          }
        }

        Rectangle {
          anchors.centerIn: parent
          opacity: screen === "confirm" ? 1 : 0
          visible: opacity > 0
          enabled: screen === "confirm"
          scale: screen === "confirm" ? 1 : 0.94
          Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
          Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
          width: Style.space(420); height: Style.space(150); radius: Style.cornerRadius
          color: Color.background
          border.color: Color.popups.border
          Column {
            anchors.centerIn: parent; spacing: Style.space(14)
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: m.tr("Remove source?", "¿Eliminar fuente?"); color: Color.foreground; font.family: Style.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: m.pendingDeleteName; color: Color.muted; font.family: Style.fontFamily; font.pixelSize: Style.font.body }
            Row {
              anchors.horizontalCenter: parent.horizontalCenter; spacing: Style.space(10)
              Repeater {
                model: [m.tr("Cancel", "Cancelar"), m.tr("Remove", "Eliminar")]
                Rectangle {
                  required property int index
                  required property string modelData
                  width: Style.space(100); height: Style.space(32); radius: Style.cornerRadius
                  color: m.confirmChoice === index ? Color.accent : Color.menu.selectedBackground
                  Text { anchors.centerIn: parent; text: modelData; color: m.confirmChoice === index ? Color.background : Color.foreground; font.family: Style.fontFamily }
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: m.confirmDelete(index === 1) }
                }
              }
            }
          }
        }
      }

      Text {
        width: parent.width
        text: statusText || (screen === "articles" ? tr("j/k move · h/l source · Enter read · f filter · s sources · r refresh", "j/k mover · h/l fuente · Enter leer · f filtrar · s fuentes · r actualizar") : "")
        color: Color.muted
        font.family: Style.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }

  function formatDate(value) {
    if (!value) return tr("No date", "Sin fecha")
    var date = new Date(value)
    if (isNaN(date.getTime())) return value
    return Qt.formatDateTime(date, "dd MMM · HH:mm")
  }
}
