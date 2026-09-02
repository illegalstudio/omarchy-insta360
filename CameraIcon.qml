import QtQuick
import qs.Commons

Item {
  id: root

  property color color: Color.foreground
  property bool active: false
  property bool tracking: false
  property bool warning: false
  property real iconSize: Style.bar.iconCanvas

  width: iconSize
  height: iconSize

  Rectangle {
    id: body
    width: root.iconSize * 0.86
    height: root.iconSize * 0.58
    radius: root.iconSize * 0.12
    anchors.centerIn: parent
    color: "transparent"
    border.width: Math.max(1, root.iconSize * 0.08)
    border.color: root.warning ? Color.urgent : root.color
    opacity: root.active ? 1.0 : 0.62

    Rectangle {
      width: parent.height * 0.45
      height: width
      radius: width / 2
      anchors.centerIn: parent
      color: root.tracking ? root.color : "transparent"
      border.width: Math.max(1, root.iconSize * 0.07)
      border.color: root.warning ? Color.urgent : root.color
    }
  }

  Rectangle {
    width: root.iconSize * 0.25
    height: Math.max(1, root.iconSize * 0.08)
    radius: height / 2
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: body.bottom
    anchors.topMargin: root.iconSize * 0.08
    color: root.warning ? Color.urgent : root.color
    opacity: root.active ? 1.0 : 0.62
  }

  Rectangle {
    visible: root.active
    width: Math.max(3, root.iconSize * 0.18)
    height: width
    radius: width / 2
    anchors.right: parent.right
    anchors.top: parent.top
    color: root.warning ? Color.urgent : (root.tracking ? Color.accent : root.color)
  }
}
