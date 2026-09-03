import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// SuperNotch plugin: Settings — live tuning for the notch + card.
// Writes persist via root.run(["set-pref", key, value]) and apply instantly.
// Layout is compact: one row per plugin (reorder + side + toggle), sliders in
// two columns, so the whole page fits on the laptop panel without scrolling.
Item {
  id: cfg
  property var root: null
  property string pluginKey: ""
  onRootChanged: if (root) notchRep.model = root.plugins
  width: parent ? parent.width : 100
  implicitHeight: mainCol.implicitHeight + Style.space(40)

  function save(key, val) { if (root) root.run(["set-pref", key, String(val)], function () {}) }
  function notchIndex(key) {
    if (!root) return -1
    var l = root.notchList || []
    for (var i = 0; i < l.length; i++) if (l[i].key === key) return i
    return -1
  }

  component ThemedSlider: Slider {
    id: s
    property var onApply: null
    width: parent ? parent.width : 100
    implicitHeight: Style.space(24)
    background: Rectangle {
      implicitWidth: 100; implicitHeight: Style.space(7)
      x: s.leftPadding; y: s.topPadding + s.availableHeight / 2 - height / 2
      width: s.availableWidth; height: Style.space(7); radius: Style.space(4)
      color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.9)
      border.color: Color.popups.border; border.width: 1
      Rectangle {
        width: s.visualPosition * parent.width; height: parent.height
        radius: parent.height / 2; color: Color.accent
      }
    }
    handle: Rectangle {
      implicitWidth: Style.space(16); implicitHeight: Style.space(16)
      x: s.leftPadding + s.visualPosition * (s.availableWidth - width)
      y: s.topPadding + s.availableHeight / 2 - height / 2
      width: Style.space(16); height: Style.space(16); radius: Style.space(8)
      color: Color.foreground
      border.color: Color.accent; border.width: 2
      scale: s.pressed ? 1.25 : 1.0
      Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
    }
    onMoved: if (onApply) onApply(value)
  }

  component ToggleRow: Item {
    id: tr
    property string label: ""
    property bool checked: false
    property var onToggle: null
    width: parent ? parent.width : 100
    height: Style.space(26)
    Text {
      text: tr.label
      color: Color.foreground; font.pixelSize: Style.font.bodySmall
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      elide: Text.ElideRight
      width: parent.width - Style.space(52)
    }
    Rectangle {
      anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
      width: Style.space(42); height: Style.space(23); radius: Style.space(12)
      color: tr.checked ? Color.accent : Color.menu.selectedBackground
      border.color: tr.checked ? Color.accent : Color.popups.border; border.width: 1
      Behavior on color { ColorAnimation { duration: 160 } }
      Rectangle {
        width: Style.space(16); height: Style.space(16); radius: Style.space(8)
        y: Style.space(3.5)
        x: tr.checked ? parent.width - width - Style.space(3.5) : Style.space(3.5)
        color: tr.checked ? Color.background : Qt.darker(Color.foreground, 1.5)
        Behavior on x { NumberAnimation { duration: 170; easing.type: Easing.OutBack } }
        Behavior on color { ColorAnimation { duration: 160 } }
      }
      MouseArea {
        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
        onClicked: if (tr.onToggle) tr.onToggle(!tr.checked)
      }
    }
  }

  // small square button with a glyph (reorder arrows / center action)
  component GlyphBtn: Item {
    id: gb
    property string glyph: ""
    property bool enabled: true
    property var onTap: null
    property string tip: ""
    width: Style.space(20); height: Style.space(20)
    opacity: gb.enabled ? 1.0 : 0.28
    Rectangle {
      anchors.fill: parent; radius: Style.space(5)
      color: ma.containsMouse ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18) : "transparent"
      border.color: Color.popups.border; border.width: 1
      Behavior on color { ColorAnimation { duration: 120 } }
    }
    Text {
      anchors.centerIn: parent; text: gb.glyph
      color: gb.enabled ? Color.foreground : Color.popups.border
      font.pixelSize: Style.font.caption; font.family: Style.fontFamily
    }
    MouseArea {
      id: ma
      anchors.fill: parent; hoverEnabled: true
      cursorShape: gb.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (gb.enabled && gb.onTap) gb.onTap()
    }
  }

  // side selector: compact ◀ | ▶ segmented control (fits any language)
  component SideSelect: Item {
    id: ss
    property string sideKey: ""
    width: Style.space(58); height: Style.space(20)
    Rectangle {
      anchors.fill: parent; radius: height / 2
      color: Color.popups.background
      border.color: Color.popups.border; border.width: 1
      Row {
        anchors.centerIn: parent
        Rectangle {
          width: Style.space(26); height: Style.space(15); radius: Style.space(7.5)
          color: (root && root.sideOf(ss.sideKey) === "left") ? Color.accent : "transparent"
          Text { anchors.centerIn: parent; text: "◀"; color: (root && root.sideOf(ss.sideKey) === "left") ? Color.background : Qt.darker(Color.foreground, 1.5); font.pixelSize: Style.font.caption; font.family: Style.fontFamily }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root) root.setSide(ss.sideKey, "left") }
        }
        Rectangle {
          width: Style.space(26); height: Style.space(15); radius: Style.space(7.5)
          color: (root && root.sideOf(ss.sideKey) !== "left") ? Color.accent : "transparent"
          Text { anchors.centerIn: parent; text: "▶"; color: (root && root.sideOf(ss.sideKey) !== "left") ? Color.background : Qt.darker(Color.foreground, 1.5); font.pixelSize: Style.font.caption; font.family: Style.fontFamily }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root) root.setSide(ss.sideKey, "right") }
        }
      }
    }
  }

  Column {
    id: mainCol
    x: Style.space(20); y: Style.space(20)
    width: parent.width - Style.space(40)
    spacing: Style.space(10)

    Text {
      text: "⚙ " + (root ? root.t(root.uiLang, "settings") : "Settings")
      color: Color.foreground; font.pixelSize: Style.font.body; font.bold: true
    }
    Rectangle { width: parent.width; height: 1; color: Color.popups.border; opacity: 0.5 }

    // ── Mostrar en el notch: one compact row per plugin ──
    Text {
      text: root ? root.t(root.uiLang, "showInNotch") : "Mostrar en el notch"
      color: Color.foreground; font.pixelSize: Style.font.caption; font.bold: true
    }
    Repeater {
      id: notchRep
      model: []
      Item {
        width: parent.width; height: Style.space(24)
        // reorder (only meaningful for plugins shown in the notch)
        Row {
          id: reorderRow
          anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)
          visible: root ? root.isNotch(modelData.key) : false
          GlyphBtn {
            glyph: "▲"
            enabled: cfg.notchIndex(modelData.key) > 0
            onTap: function () { if (root) root.moveInNotch(modelData.key, -1) }
          }
          GlyphBtn {
            glyph: "▼"
            enabled: cfg.notchIndex(modelData.key) >= 0 && cfg.notchIndex(modelData.key) < (root ? (root.notchList || []).length - 1 : 0)
            onTap: function () { if (root) root.moveInNotch(modelData.key, 1) }
          }
        }
        Text {
          anchors.left: reorderRow.visible ? reorderRow.right : parent.left
          anchors.leftMargin: reorderRow.visible ? Style.space(8) : 0
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: sideSel.left; anchors.rightMargin: Style.space(8)
          text: (modelData.label && (modelData.label[root.uiLang] || modelData.label.en)) || modelData.key
          color: Color.foreground; font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }
        SideSelect {
          id: sideSel
          anchors.right: tg.left; anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          sideKey: modelData.key
          visible: root ? root.isNotch(modelData.key) : false
        }
        Rectangle {
          id: tg
          anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
          width: Style.space(42); height: Style.space(23); radius: Style.space(12)
          color: (root && root.isNotch(modelData.key)) ? Color.accent : Color.menu.selectedBackground
          border.color: (root && root.isNotch(modelData.key)) ? Color.accent : Color.popups.border; border.width: 1
          Behavior on color { ColorAnimation { duration: 160 } }
          Rectangle {
            width: Style.space(16); height: Style.space(16); radius: Style.space(8)
            y: Style.space(3.5)
            x: (root && root.isNotch(modelData.key)) ? parent.width - width - Style.space(3.5) : Style.space(3.5)
            color: (root && root.isNotch(modelData.key)) ? Color.background : Qt.darker(Color.foreground, 1.5)
            Behavior on x { NumberAnimation { duration: 170; easing.type: Easing.OutBack } }
          }
          MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            onClicked: if (root) root.toggleNotch(modelData.key)
          }
        }
      }
    }

    // ── Centrar: restore the bar's center anchor (drag can move the pill) ──
    Rectangle {
      width: parent.width; height: Style.space(30); radius: Style.space(8)
      color: centerMa.containsMouse ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.16) : "transparent"
      border.color: Color.accent; border.width: 1
      Behavior on color { ColorAnimation { duration: 140 } }
      Row {
        anchors.centerIn: parent; spacing: Style.space(8)
        Text { text: "⌖"; color: Color.accent; font.pixelSize: Style.font.bodySmall; font.family: Style.fontFamily }
        Text {
          text: root ? root.t(root.uiLang, "centerNotch") : "Center notch"
          color: Color.accent; font.pixelSize: Style.font.bodySmall; font.bold: true
        }
      }
      MouseArea {
        id: centerMa
        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: if (root) root.run(["center-bar"], function () {})
      }
    }

    // ── widths: two columns ──
    Row {
      width: parent.width; spacing: Style.space(16)
      Column {
        width: (parent.width - Style.space(16)) / 2; spacing: Style.space(4)
        Item {
          width: parent.width; height: lab1.implicitHeight
          Text { id: lab1; anchors.left: parent.left; text: root ? root.t(root.uiLang, "notchWidth") : "Notch width"; color: Color.foreground; font.pixelSize: Style.font.caption }
          Text { anchors.right: parent.right; text: Math.round(cardWSlider.value) + " %"; color: Color.accent; font.pixelSize: Style.font.caption; font.bold: true }
        }
        ThemedSlider {
          id: cardWSlider
          from: root ? root.minNotchPct : 5; to: 90
          value: root ? root.notchWidthPct : 20
          onApply: function (v) {
            if (!root) return
            root.notchWidthPct = Math.round(v)
            cfg.save("notchWidth", Math.round(v))
            root.pushBar()
          }
        }
      }
      Column {
        width: (parent.width - Style.space(16)) / 2; spacing: Style.space(4)
        Item {
          width: parent.width; height: lab2.implicitHeight
          Text { id: lab2; anchors.left: parent.left; text: root ? root.t(root.uiLang, "cardW") : "Panel width"; color: Color.foreground; font.pixelSize: Style.font.caption }
          Text { anchors.right: parent.right; text: Math.round(panelWSlider.value) + " %"; color: Color.accent; font.pixelSize: Style.font.caption; font.bold: true }
        }
        ThemedSlider {
          id: panelWSlider
          from: 5; to: 90
          value: root ? root.panelWidthPct : 70
          onApply: function (v) {
            if (!root) return
            root.panelWidthPct = Math.round(v)
            cfg.save("panelWidth", Math.round(v))
            if (root.opened) root.recompute()
          }
        }
      }
    }
    // interior: full row (it pairs with the pill geometry)
    Column {
      width: parent.width; spacing: Style.space(4)
      Item {
        width: parent.width; height: labI.implicitHeight
        Text { id: labI; anchors.left: parent.left; text: root ? root.t(root.uiLang, "notchInset") : "Notch interior"; color: Color.foreground; font.pixelSize: Style.font.caption }
        Text { anchors.right: parent.right; text: Math.round(insetSlider.value) + " %"; color: Color.accent; font.pixelSize: Style.font.caption; font.bold: true }
      }
      ThemedSlider {
        id: insetSlider
        from: 0; to: 80
        value: root ? root.notchInsetPct : 0
        onPressedChanged: if (root) { root.notchInsetEditing = pressed; root.pushBar() }
        onApply: function (v) {
          if (!root) return
          root.notchInsetPct = Math.round(v)
          cfg.save("notchInset", Math.round(v))
          root.pushBar()
        }
      }
    }

    // ── animated background picker ──
    Column {
      width: parent.width; spacing: Style.space(4)
      Text { text: root ? root.t(root.uiLang, "background") : "Background"; color: Color.foreground; font.pixelSize: Style.font.caption }
      Flow {
        width: parent.width; spacing: Style.space(6)
        Repeater {
          model: [
            { key: "aurora", icon: "🌌" },
            { key: "sand",   icon: "🏜" },
            { key: "cubes",  icon: "🔲" },
            { key: "nebula", icon: "✦" },
            { key: "waves",  icon: "🌊" }
          ]
          Rectangle {
            width: Style.space(44); height: Style.space(34); radius: Style.space(8)
            color: (root && root.bg === modelData.key) ? Color.accent : Color.menu.selectedBackground
            border.color: (root && root.bg === modelData.key) ? Color.accent : Color.popups.border
            border.width: (root && root.bg === modelData.key) ? 2 : 1
            Behavior on color { ColorAnimation { duration: 160 } }
            Text {
              anchors.centerIn: parent; text: modelData.icon
              font.pixelSize: Style.font.bodySmall; opacity: (root && root.bg === modelData.key) ? 1 : 0.7
            }
            MouseArea {
              anchors.fill: parent; cursorShape: Qt.PointingHandCursor
              onClicked: { if (!root) return; root.bg = modelData.key; cfg.save("bg", modelData.key) }
            }
          }
        }
      }
    }

    // ── blur + opacity: two columns ──
    Row {
      width: parent.width; spacing: Style.space(16)
      Column {
        width: (parent.width - Style.space(16)) / 2; spacing: Style.space(4)
        Item {
          width: parent.width; height: labB.implicitHeight
          Text { id: labB; anchors.left: parent.left; text: root ? root.t(root.uiLang, "bgBlur") : "Blur"; color: Color.foreground; font.pixelSize: Style.font.caption; elide: Text.ElideRight; width: parent.width - Style.space(50) }
          Text { anchors.right: parent.right; text: Math.round(blurSlider.value) + " / 20"; color: Color.accent; font.pixelSize: Style.font.caption; font.bold: true }
        }
        ThemedSlider {
          id: blurSlider
          from: 0; to: 20
          value: root ? root.bgBlur : 0
          onApply: function (v) { if (!root) return; root.bgBlur = v; cfg.save("bgBlur", Math.round(v)) }
        }
      }
      Column {
        width: (parent.width - Style.space(16)) / 2; spacing: Style.space(4)
        Item {
          width: parent.width; height: labO.implicitHeight
          Text { id: labO; anchors.left: parent.left; text: root ? root.t(root.uiLang, "bgOpacity") : "Transparency"; color: Color.foreground; font.pixelSize: Style.font.caption; elide: Text.ElideRight; width: parent.width - Style.space(50) }
          Text { anchors.right: parent.right; text: Math.round(opacitySlider.value) + "%"; color: Color.accent; font.pixelSize: Style.font.caption; font.bold: true }
        }
        ThemedSlider {
          id: opacitySlider
          from: 0; to: 100
          value: root ? Math.round((1.0 - root.bgOpacity) / 0.5 * 100) : 0
          onApply: function (v) {
            if (!root) return
            root.bgOpacity = 1.0 - (v / 100.0) * 0.5
            cfg.save("bgOpacity", Number(root.bgOpacity.toFixed(2)))
          }
        }
      }
    }

    // ── toggles: two columns where they fit ──
    Row {
      width: parent.width; spacing: Style.space(16)
      ToggleRow {
        width: (parent.width - Style.space(16)) / 2
        label: root ? root.t(root.uiLang, "darkCenter") : "Dark notch center"
        checked: root ? root.darkCenter : false
        onToggle: function (v) {
          if (!root) return
          root.darkCenter = v
          cfg.save("notchDarkCenter", v)
          root.pushBar()
        }
      }
      ToggleRow {
        width: (parent.width - Style.space(16)) / 2
        label: root ? root.t(root.uiLang, "autoHide") : "Auto-hide"
        checked: root ? root.autoHide : true
        onToggle: function (v) { if (root) { root.autoHide = v; cfg.save("autoHide", v) } }
      }
    }
    ToggleRow {
      label: root ? root.t(root.uiLang, "clipMask") : "Mask secrets"
      checked: root ? root.clipMask : true
      onToggle: function (v) { if (root) { root.clipMask = v; cfg.save("clipMask", v) } }
    }
  }
}
