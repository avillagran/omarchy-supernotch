import QtQuick
import qs.Commons

// Static when it fits; otherwise two copies form one continuous ticker belt.
Item {
  id: root
  property string text: ""
  property color color: Color.foreground
  property string fontFamily: Style.fontFamily
  property int fontSize: Style.font.bodySmall
  property bool bold: false
  property real maxW: 200
  property real pixelsPerSecond: 28
  property real scrollX: 0

  readonly property real textW: textMetrics.width
  readonly property bool fits: textW <= maxW
  readonly property real copyGap: Style.space(18)
  readonly property real cycleW: textW + copyGap

  width: fits ? textW : maxW
  height: textMetrics.height
  clip: true

  onTextChanged: scrollX = 0
  onMaxWChanged: scrollX = 0

  TextMetrics {
    id: textMetrics
    text: root.text
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    font.bold: root.bold
  }

  Text {
    id: firstCopy
    x: root.fits ? 0 : root.scrollX
    anchors.verticalCenter: parent.verticalCenter
    text: root.text
    color: root.color
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    font.bold: root.bold
  }

  Text {
    id: secondCopy
    visible: !root.fits
    x: root.scrollX + root.cycleW
    anchors.verticalCenter: parent.verticalCenter
    text: root.text
    color: root.color
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    font.bold: root.bold
  }

  NumberAnimation on scrollX {
    id: marqueeLoop
    running: !root.fits && root.text.length > 0
    from: 0
    to: -root.cycleW
    duration: Math.max(2600, Math.round(root.cycleW / root.pixelsPerSecond * 1000))
    loops: Animation.Infinite
    easing.type: Easing.Linear
  }
}
