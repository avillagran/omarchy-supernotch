import QtQuick
import qs.Commons

// MarqueeText — Text that scrolls horizontally when wider than maxW.
// Fits: behaves like a normal Text. Overflow: seamless left→right loop.
Item {
  id: root
  property string text: ""
  property color color: Color.foreground
  property string fontFamily: Style.fontFamily
  property int fontSize: Style.font.bodySmall
  property bool bold: false
  property real maxW: 200

  readonly property real textW: textMetrics.width
  readonly property bool fits: textW <= maxW

  width: fits ? textW : maxW
  height: textMetrics.height
  clip: true

  TextMetrics {
    id: textMetrics
    text: root.text
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    font.bold: root.bold
  }

  Text {
    id: label
    text: root.text
    color: root.color
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    font.bold: root.bold
    anchors.verticalCenter: parent.verticalCenter
  }

  SequentialAnimation {
    id: marqueeLoop
    running: !root.fits && root.text.length > 0
    loops: Animation.Infinite
    NumberAnimation {
      target: label; property: "x"
      to: -(Math.max(0, root.textW - root.maxW) + Style.space(16))
      duration: Math.max(2000, root.textW * 22)
      easing.type: Easing.Linear
    }
    PauseAnimation { duration: 1000 }
    NumberAnimation {
      target: label; property: "x"
      to: 0
      duration: Math.max(2000, root.textW * 22)
      easing.type: Easing.Linear
    }
    PauseAnimation { duration: 600 }
  }
}
