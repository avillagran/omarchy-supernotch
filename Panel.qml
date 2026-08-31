import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// SuperNotch — the animated command-center card. PLUGIN FRAMEWORK: every tab is
// plugins/<key>/<key>.qml discovered at runtime via the helper `plugins-list`.
// The card blooms from the center notch like a Dynamic Island. Each plugin
// receives `root` (this Panel) and may call root.run(cmd,cb) and root.t(lang,key).
Panel {
  id: root
  moduleName: "omarchy-supernotch"
  property var anchorItem: null
  property var hostWidget: null

  property bool opened: false
  function open(p)  { root.opened = true }
  function close()  { root.opened = false }
  function toggle() { root.opened = !root.opened }

  // ---- i18n --------------------------------------------------------------
  readonly property string uiLang: {
    var p = (Qt.locale().name || "en_US").toLowerCase().split("_")[0]
    var sup = ["en","es","pt","fr","de","it","nl","pl","ru","ja","ko","zh","tr","sv"]
    return sup.indexOf(p) >= 0 ? p : "en"
  }
  function t(lang, key) {
    var table = i18nData[lang] || i18nData.en
    return (table && table[key] !== undefined) ? table[key] : ((i18nData.en && i18nData.en[key] !== undefined) ? i18nData.en[key] : key)
  }
  property var i18nData: ({
    en: { settings:"Settings", idle:"SuperNotch", notchWidth:"Notch width", autoHide:"Auto-hide when idle", clipMask:"Mask clipboard secrets", noPlugins:"No modules installed", nowPlaying:"Now Playing", noPlayer:"Nothing playing", newTask:"New task", tasksLeft:"%1 left", tasksEmpty:"No tasks" },
    es: { settings:"Ajustes", idle:"SuperNotch", notchWidth:"Ancho del notch", autoHide:"Ocultar solo si inactivo", clipMask:"Ocultar contraseñas del portapapeles", noPlugins:"No hay módulos", nowPlaying:"Sonando ahora", noPlayer:"Nada sonando", newTask:"Nueva tarea", tasksLeft:"quedan %1", tasksEmpty:"Sin tareas" }
  })
  Process {
    id: i18nLoader
    running: true
    command: ["bash", "-lc", "cat '" + Qt.resolvedUrl("i18n.json").toString().replace("file://", "") + "'"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: { try { root.i18nData = JSON.parse(text) } catch (e) {} } }
  }

  // ---- helper ------------------------------------------------------------
  readonly property string helper: {
    var d = (typeof manifest !== "undefined" && manifest.__sourceDir) ? manifest.__sourceDir : ""
    if (d) return d.replace(/\/$/, "") + "/bin/omarchy-supernotch"
    return Qt.resolvedUrl(".").toString().replace("file://", "") + "/bin/omarchy-supernotch"
  }
  function run(args, onText) {
    var proc = Qt.createQmlObject(
      "import Quickshell.Io; import QtQuick; Process { " +
      "property string collected: \"\"; property var cb: null; " +
      "stdout: SplitParser { onRead: function(d){ collected += d } } " +
      "onExited: function(){ if (this.cb) this.cb(collected) } }",
      root, "snProc")
    if (!proc) return null
    proc.collected = ""; proc.cb = onText
    proc.command = [root.helper].concat(args); proc.running = true
    return proc
  }

  // ---- prefs (stored as PERCENT of the current monitor width, never px) ----
  // Deriving the pixel size from the live monitor width means the notch
  // automatically re-sizes (and re-appears) when you switch monitors/resolutions.
  readonly property int monitorW: (panel && panel.screenW) ? panel.screenW : (Screen.width > 0 ? Screen.width : 1920)
  property real notchWidthPct: 42   // % of monitor width → the BAR WIDGET (pill)
  property int notchWidth: Math.max(160, Math.min(90, notchWidthPct) / 100 * monitorW)
  property real panelWidthPct: 70    // % of monitor width → the OPENED CARD (independent)
  property int panelWidth: Math.max(160, Math.min(90, panelWidthPct) / 100 * monitorW)
  property int notchHeight: 388
  property real barWPref: 0
  property bool autoHide: true
  property bool clipMask: true
  property string bg: "aurora"
  property real bgBlur: 0
  property real bgOpacity: 1.0
  property real notchInsetPct: 0   // % of notch width
  property int notchInset: Math.round(notchWidth * notchInsetPct / 100)
  property bool notchInsetEditing: false
  property var pluginOrder: []
  property var notchPlugins: []
  function loadPrefs() {
    run(["get-prefs"], function (out) {
      try {
        var p = JSON.parse(out.trim())
        if (p.notchWidth) {
          var nw = p.notchWidth
          if (nw > 100) nw = Math.round(nw / 1920 * 100)  // legacy px → pct (assume ~1920 baseline)
          root.notchWidthPct = Math.max(5, Math.min(90, nw))
          run(["set-pref", "notchWidth", String(root.notchWidthPct)])  // persist as pct
        }
        if (typeof p.panelWidth === "number") {
          var pw = p.panelWidth
          if (pw > 100) pw = Math.round(pw / 1920 * 100)  // legacy px → pct
          root.panelWidthPct = Math.max(5, Math.min(90, pw))
          run(["set-pref", "panelWidth", String(root.panelWidthPct)])  // persist as pct
        }
        if (p.notchHeight) root.notchHeight = p.notchHeight
        if (typeof p.autoHide === "boolean") root.autoHide = p.autoHide
        if (typeof p.clipMask === "boolean") root.clipMask = p.clipMask
        if (p.notchBarWidth && p.notchBarWidth > 0) root.barWPref = p.notchBarWidth
        if (p.bg) root.bg = p.bg
        if (typeof p.bgBlur === "number") root.bgBlur = p.bgBlur
        if (typeof p.bgOpacity === "number") root.bgOpacity = p.bgOpacity
        if (typeof p.notchInset === "number") {
          var ni = p.notchInset
          if (ni > 100) ni = Math.round(ni / 1920 * 100)  // legacy px → pct (assume ~1920 baseline)
          root.notchInsetPct = Math.max(0, Math.min(90, ni))
          run(["set-pref", "notchInset", String(root.notchInsetPct)])  // persist as pct
        }
        if (Array.isArray(p.pluginOrder)) root.pluginOrder = p.pluginOrder
        if (Array.isArray(p.notchPlugins)) root.notchPlugins = p.notchPlugins
        root.recomputeNotch()
        root.pushBar()
      } catch (e) {}
    })
    run(["notch-detect"], function (out) {
      try {
        var d = JSON.parse(out.trim())
        if (d.scaled && root.hostWidget) root.hostWidget.realNotchW = d.scaled
      } catch (e) {}
    })
  }

  // ---- plugins -----------------------------------------------------------
  property var plugins: []          // all discovered plugins (ALWAYS shown as tabs)
  property var notchList: []        // plugins filtered by notchPlugins (pill content)
  property var tabRefs: []
  // Live mini-status each plugin pushes for the notch pill (icon + short text).
  property var notchData: ({})
  function updateNotchData(key, ic, tx) {
    var d = root.notchData; d[key] = { icon: ic, text: tx }; root.notchData = d
    root.recomputeNotch()
  }
  function recomputeNotch() {
    var all = root.plugins
    var en = root.notchPlugins || []
    var vis = (en.length === 0) ? all.slice() : all.filter(function (p) { return en.indexOf(p.key) >= 0 })
    // enrich each with its live mini-status (fall back to static barIcon/label)
    vis = vis.map(function (p) {
      var nd = root.notchData[p.key] || {}
      var lang = root.uiLang
      return {
        key: p.key,
        dir: p.dir,
        icon: nd.icon || p.barIcon || p.icon || "◇",   // bar-widget glyph
        panelIcon: p.icon || "◇",                       // tab glyph (panel)
        text: nd.text || ((p.label && (p.label[lang] || p.label.en)) || p.key),
        label: p.label
      }
    })
    root.notchList = vis
  }
  function isNotch(key) {
    var en = root.notchPlugins || []
    return en.length === 0 || en.indexOf(key) >= 0
  }
  function toggleNotch(key) {
    var en = (root.notchPlugins || []).slice()
    var i = en.indexOf(key)
    if (i >= 0) en.splice(i, 1); else en.push(key)
    root.notchPlugins = en
    root.run(["set-notch", JSON.stringify(en)], function () {})
    root.recomputeNotch()
    root.pushBar()
  }
  function reorderPlugin(fromKey, toIdx) {
    var all = root.plugins
    // reorder over ALL plugins (tabs are always visible); pluginOrder drives tab order
    var vis = root.plugins.slice()
    var from = -1
    for (var a = 0; a < vis.length; a++) if (vis[a].key === fromKey) from = a
    if (from < 0) return
    var moved = vis.splice(from, 1)[0]
    if (toIdx < 0) toIdx = 0
    if (toIdx > vis.length) toIdx = vis.length
    vis.splice(toIdx, 0, moved)
    var newOrder = []; for (var d = 0; d < vis.length; d++) newOrder.push(vis[d].key)
    root.pluginOrder = newOrder
    root.run(["set-order", JSON.stringify(newOrder)], function () {})
    root.recomputeNotch()
  }
  function loadPlugins() {
    run(["plugins-list"], function (out) {
      try {
        root.plugins = JSON.parse(out.trim())
        root.recomputeNotch()
        root.pushBar()
      } catch (e) { root.plugins = []; root.notchList = [] }
    })
  }

  // ---- bloom / entrance choreography ------------------------------------
  property real enterT: 0
  Behavior on enterT { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }

  onOpenedChanged: {
    if (root.hostWidget && "opened" in root.hostWidget) root.hostWidget.opened = root.opened
    root.enterT = root.opened ? 1 : 0
    root.pushBar()
    if (root.opened) {
      root.cardH = root.fullH
      loadPrefs(); loadPlugins(); refreshAll()
    }
  }
  Component.onCompleted: { loadPrefs(); Qt.callLater(function () { loadPlugins() }) }

  // Card width tracks the notch width (% of monitor), never a fixed px.
  property int cardW: root.fullW
  property int cardH: Style.space(52) + 360
  // Dynamic height: the card grows to fit the active plugin's real content
  // height (each plugin reports its own implicitHeight; no manual slider).
  property var contentRefs: []
  function pluginHeight() {
    var item = root.contentRefs[root.current]
    var h = (item && item.implicitHeight > 0) ? item.implicitHeight : 360
    return Style.space(52) + h
  }
  readonly property int fullW: root.panelWidth
  readonly property int fullH: root.pluginHeight()
  Behavior on cardW { SpringAnimation { spring: 2.6; damping: 0.24; mass: 0.9 } }
  Behavior on cardH { SpringAnimation { spring: 2.6; damping: 0.24; mass: 0.9 } }

  property int current: 0
  property real contentOpacity: 1
  Behavior on contentOpacity { NumberAnimation { duration: 150 } }
  property int _pending: 0
  Timer { id: switchTimer; interval: 150; onTriggered: { root.current = root._pending; root.contentOpacity = 1; root.cardH = root.fullH; root.pushBar() } }
  function setModule(i) {
    if (i === root.current) { if (!root.opened) root.open(); return }
    root.contentOpacity = 0; root._pending = i; switchTimer.restart()
  }

  // ---- cursor tracking (aurora parallax) --------------------------------
  property real cursorNX: 0   // -1..1 from card center
  property real cursorNY: 0
  Behavior on cursorNX { SmoothedAnimation { velocity: 3.2 } }
  Behavior on cursorNY { SmoothedAnimation { velocity: 3.2 } }

  function pushBar() {
    var w = root.hostWidget
    if (!w) return
    w.barW = root.barWPref
    w.barPlugins = root.notchList
    w.notchInset = root.notchInset
    w.notchWidth = root.notchWidth
    w.notchInsetEditing = root.notchInsetEditing
    if (root.opened) {
      var mod = root.plugins[root.current]
      if (mod) { w.barIcon = mod.icon || "◇"; w.barInfo = (mod.label && (mod.label[root.uiLang] || mod.label.en)) || mod.key; w.barActive = true; return }
    }
    w.barActive = false; w.barIcon = "♪"; w.barInfo = root.t(root.uiLang, "idle")
  }
  function refreshAll() {}

  // ---- the card ----------------------------------------------------------
  CardWindow {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: (root.anchorItem ? root.anchorItem.bar : root.bar)
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: root.cardW
    contentHeight: root.cardH

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (d) { var n = Math.max(1, root.plugins.length); root.setModule((root.current + d + n) % n) }
    }

    // ══ CARD WRAP — shadow + surface scale/fade TOGETHER (no ghost rect) ══
    Item {
      id: cardWrap
      width: panel.contentWidth; height: panel.contentHeight
      transformOrigin: Item.Top
      scale: 0.92 + 0.08 * root.enterT
      opacity: root.enterT

      // drop shadow (follows the wrap's transform and the THEME radius)
      Rectangle {
        anchors.fill: cardSurface
        anchors.margins: -Style.space(6)
        radius: cardSurface.radius + Style.space(2)
        color: "#000000"; opacity: 0.45 * root.bgOpacity; z: -1
        layer.enabled: true
        layer.effect: MultiEffect { blurEnabled: true; blurMax: 34; blur: 1.0 }
      }

    // ══ CARD SURFACE — translucent glass with a living aurora INSIDE ═══════
    // radius FOLLOWS THE THEME: Style.cornerRadius mirrors Hyprland's
    // decoration:rounding — square system ⇒ square card, rounded ⇒ rounded.
    Rectangle {
      id: cardSurface
      readonly property color bg: Color.popups.background
      width: parent.width; height: parent.height
      radius: Style.cornerRadius
      border.color: Color.popups.border; border.width: 1
      clip: true
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(Qt.lighter(cardSurface.bg, 1.3).r, Qt.lighter(cardSurface.bg, 1.3).g, Qt.lighter(cardSurface.bg, 1.3).b, 1.0 * root.bgOpacity) }
        GradientStop { position: 0.3; color: Qt.rgba(cardSurface.bg.r, cardSurface.bg.g, cardSurface.bg.b, 0.98 * root.bgOpacity) }
        GradientStop { position: 1.0; color: Qt.rgba(Qt.darker(cardSurface.bg, 1.1).r, Qt.darker(cardSurface.bg, 1.1).g, Qt.darker(cardSurface.bg, 1.1).b, 1.0 * root.bgOpacity) }
      }

      // ══ ANIMATED BACKGROUND — selectable per `root.bg` pref ═════════════════
      // All backgrounds live in Backgrounds.qml (aurora/sand/cubes/nebula/waves)
      // and share the cursor-parallax tracker below.
      MouseArea {
        id: cursorTrack
        anchors.fill: parent
        z: -1
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        propagateComposedEvents: true
        onPositionChanged: function (m) {
          root.cursorNX = (m.x / width) * 2 - 1
          root.cursorNY = (m.y / height) * 2 - 1
        }
        onExited: { root.cursorNX = 0; root.cursorNY = 0 }
      }

      Item {
        id: bgLayer
        anchors.fill: parent
        z: -1
        // Real transparency: the animated background fades with bgOpacity so the
        // desktop shows through when you lower it (the KeyboardPanel window is
        // transparent, see `background: "transparent"` below).
        opacity: root.bgOpacity
        layer.enabled: root.bgBlur > 0.01
        layer.effect: MultiEffect { blurEnabled: true; blurMax: 20; blur: root.bgBlur }
        Loader {
          anchors.fill: parent
          source: Qt.resolvedUrl("Backgrounds.qml")
          onLoaded: { item.rootRef = root }
        }
      }

      // inner top glass highlight
      Rectangle {
        width: parent.width - Style.space(28); height: 1
        x: Style.space(14); y: 1
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: "transparent" }
          GradientStop { position: 0.5; color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.18) }
          GradientStop { position: 1.0; color: "transparent" }
        }
      }

      // film-grain texture — makes the glass self-sufficient on plain wallpapers
      Canvas {
        id: grain
        width: root.fullW; height: root.fullH
        anchors.centerIn: parent
        opacity: 0.05
        Component.onCompleted: requestPaint()
        onPaint: {
          var ctx = getContext("2d")
          ctx.clearRect(0, 0, width, height)
          var fr = Math.round(Color.foreground.r * 255)
          var fg = Math.round(Color.foreground.g * 255)
          var fb = Math.round(Color.foreground.b * 255)
          for (var i = 0; i < 2600; i++) {
            var a = Math.random() * 0.6
            ctx.fillStyle = "rgba(" + fr + "," + fg + "," + fb + "," + a.toFixed(2) + ")"
            ctx.fillRect(Math.random() * width, Math.random() * height, 1, 1)
          }
        }
      }

      Column {
        id: cardCol
        width: parent.width; height: parent.height
        spacing: 0

        // ── toolbar: floating indicator + staggered tabs ──────────────────
        Item {
          width: parent.width; height: Style.space(52)

          // floating active pill (springy, morphs between tabs)
          Rectangle {
            id: activePill
            property var tgt: (root.tabRefs && root.tabRefs[root.current]) ? root.tabRefs[root.current] : null
            visible: tgt !== null && root.enterT > 0.5
            x: tgt ? (tabRow.x + tgt.x - Style.space(2)) : 0
            y: tabRow.y + (tgt ? tgt.y : 0) - Style.space(2)
            width: tgt ? tgt.width + Style.space(4) : 0
            height: tgt ? tgt.height + Style.space(4) : 0
            radius: Style.cornerRadius + Style.space(2)
            color: Color.menu.selectedBackground
            border.color: Color.accent; border.width: 1
            Behavior on x { SpringAnimation { spring: 4.2; damping: 0.30; mass: 0.7 } }
            Behavior on width { SpringAnimation { spring: 4.2; damping: 0.30; mass: 0.7 } }
          }

          Row {
            id: tabRow
            height: Style.space(38)
            anchors.left: parent.left; anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
            Repeater {
              model: root.plugins
              Item {
                id: tab
                height: Style.space(38)
                width: tabLayout.implicitWidth + Style.space(40)
                opacity: root.enterT
                transform: Translate { y: (1 - root.enterT) * -10 }
                Behavior on opacity { SequentialAnimation { PauseAnimation { duration: index * 45 } NumberAnimation { duration: 240 } } }
                Component.onCompleted: { var a = root.tabRefs.slice(); a[index] = tab; root.tabRefs = a }
                DragHandler {
                  id: tabDrag
                  xAxis.enabled: true; yAxis.enabled: false
                  dragThreshold: 8
                  onActiveChanged: {
                    if (!tabDrag.active) {
                      // dropped: compute target index by x position
                      var avg = tabRow.width / Math.max(1, root.plugins.length)
                      var to = Math.max(0, Math.min(root.plugins.length - 1, Math.round(tab.x / avg)))
                      root.reorderPlugin(modelData.key, to)
                    }
                  }
                }
                // hover wash for inactive tabs (so they read against the aurora)
                Rectangle {
                  anchors.fill: parent
                  radius: Style.cornerRadius + Style.space(2)
                  color: Color.menu.selectedBackground
                  opacity: (root.current !== index && tabMa.containsMouse) ? 0.55 : 0
                  Behavior on opacity { NumberAnimation { duration: 140 } }
                }
                Row {
                  id: tabLayout
                  anchors.centerIn: parent
                  spacing: Style.space(8)
                  Text {
                    text: modelData.panelIcon || modelData.icon || "◇"
                    color: root.current === index ? Color.accent : Color.foreground
                    opacity: root.current === index ? 1 : (tabMa.containsMouse ? 1 : 0.78)
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                    scale: root.current === index ? 1.15 : 1.0
                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
                    Behavior on color { ColorAnimation { duration: 160 } }
                    Behavior on opacity { NumberAnimation { duration: 140 } }
                  }
                  Text {
                    id: tabLabel
                    text: modelData.label[root.uiLang] || modelData.label.en || modelData.key
                    color: Color.foreground
                    // ICON-ONLY tabs: text appears (animated) only on hover
                    opacity: tabMa.containsMouse ? 1 : 0
                    width: tabMa.containsMouse ? tabLabel.implicitWidth : 0
                    clip: true
                    font.pixelSize: Style.font.bodySmall
                    font.bold: root.current === index
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                  }
                }
                MouseArea { id: tabMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setModule(index) }
              }
            }
          }

          // close button (magnetic hover + press bounce)
          Rectangle {
            width: Style.space(34); height: Style.space(34)
            anchors.right: parent.right; anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            radius: Style.cornerRadius + Style.space(2)
            color: closeMa.containsMouse ? Color.menu.selectedBackground : "transparent"
            opacity: root.enterT
            scale: closeMa.pressed ? 0.82 : 1.0
            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 2.5 } }
            Behavior on color { ColorAnimation { duration: 140 } }
            Text { anchors.centerIn: parent; text: "✕"; color: Color.muted; font.pixelSize: Style.font.body }
            MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.close() }
          }
        }

        // hairline under toolbar
        Rectangle {
          width: parent.width - Style.space(24); height: 1
          anchors.horizontalCenter: parent.horizontalCenter
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) }
            GradientStop { position: 1.0; color: "transparent" }
          }
        }

        // ── plugin content (crossfade + subtle rise) ──────────────────────
        Item {
          id: contentRoot
          width: parent.width; height: parent.height - Style.space(53)
          opacity: root.contentOpacity * root.enterT
          transform: Translate { y: (1 - root.contentOpacity) * 8 }
          clip: true
          Repeater {
            model: root.plugins
            Loader {
              active: true
              visible: root.current === index
              source: Qt.resolvedUrl(modelData.dir + "/" + (modelData.ui || (modelData.key + ".qml")))
              anchors.fill: parent
              onLoaded: {
                if (item && "root" in item) item.root = root
                if (item) item.pluginKey = modelData.key
                var a = root.contentRefs.slice(); a[index] = item; root.contentRefs = a
                root.cardH = root.fullH
              }
              // keep card height synced to the active plugin's real content height
              Binding {
                target: root
                property: "cardH"
                value: root.fullH
                when: item && root.current === index
              }
            }
          }
          Text {
            visible: root.plugins.length === 0
            anchors.centerIn: parent
            text: root.t(root.uiLang, "noPlugins")
            color: Color.muted; font.pixelSize: Style.font.body
          }
        }
      }
    }
    }
  }
}
