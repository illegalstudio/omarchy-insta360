import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Item {
  id: root

  property string label: ""
  property string value: ""
  property var options: []
  property color foreground: Color.popups.text
  property color background: Color.popups.background
  property color popupBorder: Color.popups.border
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property int rowHeight: Style.spacing.controlHeight
  property int popupRowHeight: Style.spacing.popupRowHeight
  property bool showLabel: true

  readonly property var popupBorderSpec: Border.localOrSurfaceSpec(
    "popups", "border", popupBorder, Color.popups.border,
    Style.normalBorderWidth)
  readonly property bool popupOpen: popup.opened

  signal changed(string value)

  function open() { popup.open() }
  function close() { popup.close() }
  function toggle() { popup.opened ? popup.close() : popup.open() }

  function optionValue(option) {
    return option && typeof option === "object"
      ? String(option.value) : String(option)
  }

  function optionLabel(option) {
    return option && typeof option === "object"
      ? String(option.label) : String(option)
  }

  function currentLabel() {
    for (var index = 0; index < options.length; index++) {
      if (optionValue(options[index]) === value)
        return optionLabel(options[index])
    }
    return value
  }

  implicitWidth: Style.spacing.dropdownWidth
  implicitHeight: showLabel && label !== ""
    ? rowHeight + Style.spacing.huge : rowHeight

  Column {
    anchors.fill: parent
    spacing: Style.spacing.labelGap

    Text {
      visible: root.showLabel && root.label !== ""
      textFormat: Text.PlainText
      text: root.label
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    BorderSurface {
      id: trigger
      width: parent.width
      height: root.rowHeight
      radius: Style.cornerRadius
      color: Style.controlFill(activeFocus, triggerHover.hovered,
        root.foreground, root.accent)
      borderSpec: Border.controlSpec(activeFocus
        ? "focus" : (triggerHover.hovered ? "hover-cursor" : "normal"),
        root.foreground, root.accent)
      activeFocusOnTab: true

      HoverHandler { id: triggerHover }

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
            || event.key === Qt.Key_Space || event.key === Qt.Key_Down) {
          root.toggle()
          event.accepted = true
        } else if (event.key === Qt.Key_Escape && popup.opened) {
          popup.close()
          event.accepted = true
        }
      }

      Text {
        anchors.left: parent.left
        anchors.right: chevron.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: trigger.borderLeft
          + Style.spacing.controlPaddingX
        anchors.rightMargin: trigger.borderRight + Style.spacing.md
        textFormat: Text.PlainText
        text: root.currentLabel()
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        id: chevron
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: trigger.borderRight + Style.spacing.controlGap
        text: "󰅀"
        color: Qt.darker(root.foreground, 1.2)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          trigger.forceActiveFocus()
          root.toggle()
        }
      }

      Popup {
        id: popup
        x: 0
        y: trigger.height + Style.spacing.xxs
        width: trigger.width
        implicitHeight: Math.min(
          root.options.length * root.popupRowHeight
            + Math.max(0, root.options.length - 1)
              * Style.spacing.labelGap + Style.spacing.xxs,
          root.popupRowHeight * 8 + 7 * Style.spacing.labelGap
            + Style.spacing.xxs)
        padding: Style.spacing.hairline
        leftPadding: Border.left(root.popupBorderSpec)
          + Style.spacing.hairline
        rightPadding: Border.right(root.popupBorderSpec)
          + Style.spacing.hairline
        topPadding: Border.top(root.popupBorderSpec)
          + Style.spacing.hairline
        bottomPadding: Border.bottom(root.popupBorderSpec)
          + Style.spacing.hairline
        focus: true

        background: BorderSurface {
          color: root.background
          borderSpec: root.popupBorderSpec
          radius: Style.cornerRadius
        }

        onOpened: {
          optionList.currentIndex = Math.max(0,
            optionList.indexOfValue(root.value))
          optionList.forceActiveFocus()
        }

        contentItem: ListView {
          id: optionList
          spacing: Style.spacing.labelGap
          implicitHeight: contentHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: root.options
          currentIndex: -1

          WheelHandler {
            target: null
            blocking: true
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

            onWheel: function(event) {
              var minimumY = optionList.originY
              var maximumY = minimumY + optionList.contentHeight
                - optionList.height
              if (maximumY <= minimumY) return
              optionList.contentY = Math.max(minimumY,
                Math.min(optionList.contentY - event.angleDelta.y, maximumY))
              event.accepted = true
            }
          }

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              popup.close()
              event.accepted = true
            } else if (event.key === Qt.Key_Down || event.text === "j") {
              optionList.currentIndex = Math.min(root.options.length - 1,
                optionList.currentIndex + 1)
              event.accepted = true
            } else if (event.key === Qt.Key_Up || event.text === "k") {
              optionList.currentIndex = Math.max(0,
                optionList.currentIndex - 1)
              event.accepted = true
            } else if (event.key === Qt.Key_Return
                       || event.key === Qt.Key_Enter) {
              optionList.selectCurrent()
              event.accepted = true
            }
          }

          function indexOfValue(selectedValue) {
            for (var index = 0; index < root.options.length; index++) {
              if (root.optionValue(root.options[index]) === selectedValue)
                return index
            }
            return -1
          }

          function selectCurrent() {
            if (currentIndex < 0 || currentIndex >= root.options.length) return
            var selectedValue = root.optionValue(root.options[currentIndex])
            root.value = selectedValue
            root.changed(selectedValue)
            popup.close()
          }

          delegate: Rectangle {
            required property var modelData
            required property int index

            width: optionList.width
            height: root.popupRowHeight
            color: index === optionList.currentIndex
              ? Style.hoverFillFor(root.foreground, root.accent)
              : "transparent"

            Text {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.spacing.controlPaddingX
              anchors.rightMargin: Style.spacing.controlPaddingX
              textFormat: Text.PlainText
              text: root.optionLabel(modelData)
              color: parent.index === optionList.currentIndex
                ? Style.hoverStateColor(root.foreground, root.accent)
                : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onPositionChanged: optionList.currentIndex = parent.index
              onClicked: optionList.selectCurrent()
            }
          }
        }
      }
    }
  }
}
