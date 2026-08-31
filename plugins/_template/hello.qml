import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// TEMPLATE plugin for SuperNotch.
// Copy this folder to plugins/<your-key>/ and edit. The card loads every
// plugin/<key>/plugin.json automatically — no core changes needed.
//
// Your plugin receives `root` (the Panel). Use:
//   root.run(["some-helper-cmd", arg], function(out){ ... })  // run a shell command, get stdout
//   root.t(root.uiLang, "key")                                 // translate a string
//   root.uiLang                                               // "en" | "es"
//   Color.* / Style.*                                         // theme tokens (never hardcode colors)
//
// Keep all visuals themed (Color.*). The panel crossfades your content in/out.

Item {
  property var root: null
  anchors.fill: parent
  anchors.margins: Style.space(20)

  Column {
    anchors.centerIn: parent
    spacing: Style.space(12)
    Text { text: "✦"; color: Color.accent; font.pixelSize: Style.font.display; anchors.horizontalCenter: parent.horizontalCenter }
    Text {
      text: root ? root.t(root.uiLang, "helloMsg") : "Hello"
      color: Color.foreground; font.pixelSize: Style.font.subtitle; font.bold: true
      anchors.horizontalCenter: parent.horizontalCenter
    }
  }
}
