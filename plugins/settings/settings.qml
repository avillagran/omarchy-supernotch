import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// SuperNotch plugin: Settings — live tuning for the notch + card.
// Writes persist via root.run(["set-pref", key, value]) and apply instantly.
Item {
  id: cfg
  property var root: null
  property string pluginKey: ""
  onRootChanged: if (root) notchRep.model = root.plugins
  width: parent ? parent.width : 100
  implicitHeight: mainCol.implicitHeight + Style.space(40)

  function save(key, val) { if (root) root.run(["set-pref", key, String(val)], function () {}) }

  component ThemedSlider: Slider {
    id: s
    property var onApply: null
    width: parent ? parent.width : 100
    implicitHeight: Style.space(28)
    background: Rectangle {
      implicitWidth: 100; implicitHeight: Style.space(8)
      x: s.leftPadding; y: s.topPadding + s.availableHeight / 2 - height / 2
      width: s.availableWidth; height: Style.space(8); radius: Style.space(4)
      color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.9)
      border.color: Color.popups.border; border.width: 1
      Rectangle {
        width: s.visualPosition * parent.width; height: parent.height
        radius: parent.height / 2; color: Color.accent
      }
    }
    handle: Rectangle {
      implicitWidth: Style.space(18); implicitHeight: Style.space(18)
      x: s.leftPadding + s.visualPosition * (s.availableWidth - width)
      y: s.topPadding + s.availableHeight / 2 - height / 2
      width: Style.space(18); height: Style.space(18); radius: Style.space(9)
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
    height: Style.space(28)
    Text {
      text: tr.label
      color: Color.foreground; font.pixelSize: Style.font.bodySmall
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
    }
    Rectangle {
      anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
      width: Style.space(46); height: Style.space(26); radius: Style.space(13)
      color: tr.checked ? Color.accent : Color.menu.selectedBackground
      border.color: tr.checked ? Color.accent : Color.popups.border; border.width: 1
      Behavior on color { ColorAnimation { duration: 160 } }
      Rectangle {
        width: Style.space(18); height: Style.space(18); radius: Style.space(9)
        y: Style.space(4)
        x: tr.checked ? parent.width - width - Style.space(4) : Style.space(4)
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

  Column {
    id: mainCol
    x: Style.space(20); y: Style.space(20)
    width: parent.width - Style.space(40)
    spacing: Style.space(16)

    Text {
      text: "⚙ " + (root ? root.t(root.uiLang, "settings") : "Settings")
      color: Color.foreground; font.pixelSize: Style.font.body; font.bold: true
    }
    Rectangle { width: parent.width; height: 1; color: Color.popups.border; opacity: 0.5 }

    // ── Mostrar en el notch (plugin visibility) ──
    Text {
      text: root ? root.t(root.uiLang, "showInNotch") : "Mostrar en el notch"
      color: Color.foreground; font.pixelSize: Style.font.caption; font.bold: true
    }
    Repeater {
      id: notchRep
      model: []
      Column {
        width: parent.width
        spacing: Style.space(4)
        ToggleRow {
          label: (modelData.label && (modelData.label[root.uiLang] || modelData.label.en)) || modelData.key
          checked: root ? root.isNotch(modelData.key) : true
          onToggle: function (v) { if (root) root.toggleNotch(modelData.key) }
        }
        // side selector (only when shown in notch)
        Item {
          width: parent.width; height: Style.space(26)
          visible: root ? root.isNotch(modelData.key) : false
          Text {
            text: root ? root.t(root.uiLang, "notchSide") + ":" : "Side:"
            color: Qt.darker(Color.foreground, 1.5); font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left; anchors.leftMargin: Style.space(2)
          }
          // Left / Right segmented buttons
          Rectangle {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            width: Style.space(92); height: Style.space(22); radius: Style.space(11)
            color: Color.popups.background
            border.color: Color.popups.border; border.width: 1
            Row {
              anchors.centerIn: parent; anchors.margins: 1
              Rectangle {
                width: Style.space(44); height: Style.space(18); radius: Style.space(9)
                color: (root && root.sideOf(modelData.key) === "left") ? Color.accent : "transparent"
                Text { anchors.centerIn: parent; text: root ? root.t(root.uiLang, "sideLeft") : "L"; color: (root && root.sideOf(modelData.key) === "left") ? Color.background : Qt.darker(Color.foreground, 1.5); font.pixelSize: Style.font.caption; font.family: Style.fontFamily }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root) root.setSide(modelData.key, "left") }
              }
              Rectangle {
                width: Style.space(44); height: Style.space(18); radius: Style.space(9)
                color: (root && root.sideOf(modelData.key) !== "left") ? Color.accent : "transparent"
                Text { anchors.centerIn: parent; text: root ? root.t(root.uiLang, "sideRight") : "R"; color: (root && root.sideOf(modelData.key) !== "left") ? Color.background : Qt.darker(Color.foreground, 1.5); font.pixelSize: Style.font.caption; font.family: Style.fontFamily }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root) root.setSide(modelData.key, "right") }
              }
            }
          }
        }
      }
    }

    // ── notch width (% of monitor; the BAR WIDGET) ──
    Column {
      width: parent.width; spacing: Style.space(6)
      Item {
        width: parent.width; height: lab1.implicitHeight
        Text {
          id: lab1
          anchors.left: parent.left
          text: root ? root.t(root.uiLang, "notchWidth") : "Notch width"
          color: Color.foreground; font.pixelSize: Style.font.caption
        }
        Text {
          anchors.right: parent.right
          text: Math.round(cardWSlider.value) + " %"
          color: Color.accent; font.pixelSize: Style.font.caption; font.bold: true
        }
      }
      ThemedSlider {
        id: cardWSlider
        from: root ? root.minNotchPct : 5; to: 90
        value: root ? root.notchWidthPct : 20
        onApply: function (v) {
          if (!root) return
          root.notchWidthPct = Math.round(v)
          cfg.save("notchWidth", Math.round(v))
          root.pushBar()  // propagate live to the bar widget
        }
      }
    }

    // ── panel width (% of monitor; the OPENED CARD) — independent from the notch ──
    Column {
      width: parent.width; spacing: Style.space(6)
      Item {
        width: parent.width; height: lab2.implicitHeight
        Text {
          id: lab2
          anchors.left: parent.left
          text: root ? root.t(root.uiLang, "cardW") : "Panel width"
          color: Color.foreground; font.pixelSize: Style.font.caption
        }
        Text {
          anchors.right: parent.right
          text: Math.round(panelWSlider.value) + " %"
          color: Color.accent; font.pixelSize: Style.font.caption; font.bold: true
        }
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
      // ── notch interior margin (right after width, same group) ──
      Item {
        width: parent.width; height: labI.implicitHeight
        Text {
          id: labI
          anchors.left: parent.left
          text: root ? root.t(root.uiLang, "notchInset") : "Notch interior"
          color: Color.foreground; font.pixelSize: Style.font.caption
        }
        Text {
          anchors.right: parent.right
          text: Math.round(insetSlider.value) + " %"
          color: Color.accent; font.pixelSize: Style.font.caption; font.bold: true
        }
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
          root.pushBar()  // propagate live to the pill while dragging
        }
      }

    // ── animated background picker ──
    Column {
      width: parent.width; spacing: Style.space(6)
      Text {
        text: root ? root.t(root.uiLang, "background") : "Background"
        color: Color.foreground; font.pixelSize: Style.font.caption
      }
      Flow {
        width: parent.width; spacing: Style.space(8)
        Repeater {
          model: [
            { key: "aurora", icon: "🌌" },
            { key: "sand",   icon: "🏜" },
            { key: "cubes",  icon: "🔲" },
            { key: "nebula", icon: "✦" },
            { key: "waves",  icon: "🌊" }
          ]
          Rectangle {
            width: Style.space(56); height: Style.space(44); radius: Style.space(10)
            color: (root && root.bg === modelData.key) ? Color.accent : Color.menu.selectedBackground
            border.color: (root && root.bg === modelData.key) ? Color.accent : Color.popups.border
            border.width: (root && root.bg === modelData.key) ? 2 : 1
            Behavior on color { ColorAnimation { duration: 160 } }
            Text {
              anchors.centerIn: parent; text: modelData.icon
              font.pixelSize: Style.font.body; opacity: (root && root.bg === modelData.key) ? 1 : 0.7
            }
            MouseArea {
              anchors.fill: parent; cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (!root) return
                root.bg = modelData.key
                cfg.save("bg", modelData.key)
              }
            }
          }
        }
      }
    }

    // ── background blur ──
    Column {
      width: parent.width; spacing: Style.space(6)
      Item {
        width: parent.width; height: labB.implicitHeight
        Text {
          id: labB
          anchors.left: parent.left
          text: root ? root.t(root.uiLang, "bgBlur") : "Blur"
          color: Color.foreground; font.pixelSize: Style.font.caption
        }
        Text {
          anchors.right: parent.right
          text: Math.round(blurSlider.value) + " / 20"
          color: Color.accent; font.pixelSize: Style.font.caption; font.bold: true
        }
      }
      ThemedSlider {
        id: blurSlider
        from: 0; to: 20
        value: root ? root.bgBlur : 0
        onApply: function (v) {
          if (!root) return
          root.bgBlur = v
          cfg.save("bgBlur", Math.round(v))
        }
      }
    }

    // ── background opacity (transparency) ──
    Column {
      width: parent.width; spacing: Style.space(6)
      Item {
        width: parent.width; height: labO.implicitHeight
        Text {
          id: labO
          anchors.left: parent.left
          text: root ? root.t(root.uiLang, "bgOpacity") : "Transparency"
          color: Color.foreground; font.pixelSize: Style.font.caption
        }
        Text {
          anchors.right: parent.right
          text: Math.round(opacitySlider.value) + "%"
          color: Color.accent; font.pixelSize: Style.font.caption; font.bold: true
        }
      }
      ThemedSlider {
        id: opacitySlider
        from: 0; to: 100
        // 0% = fully opaque (bgOpacity 1.0); 100% = 50% transparency (bgOpacity 0.5, the cap)
        value: root ? Math.round((1.0 - root.bgOpacity) / 0.5 * 100) : 0
        onApply: function (v) {
          if (!root) return
          root.bgOpacity = 1.0 - (v / 100.0) * 0.5
          cfg.save("bgOpacity", Number(root.bgOpacity.toFixed(2)))
        }
      }
    }

    // ── toggles ──
    ToggleRow {
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
      label: root ? root.t(root.uiLang, "autoHide") : "Auto-hide"
      checked: root ? root.autoHide : true
      onToggle: function (v) { if (root) { root.autoHide = v; cfg.save("autoHide", v) } }
    }
    ToggleRow {
      label: root ? root.t(root.uiLang, "clipMask") : "Mask secrets"
      checked: root ? root.clipMask : true
      onToggle: function (v) { if (root) { root.clipMask = v; cfg.save("clipMask", v) } }
    }
  }
}
