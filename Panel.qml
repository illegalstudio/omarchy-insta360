import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root

  moduleName: "illegalstudio.omarchy-insta360"
  ipcTarget: "illegalstudio.omarchy-insta360"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color background: bar ? bar.background : Color.background
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color subtleFill: Style.normalFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property bool previewWanted: true
  property bool previewSuspended: false
  property bool previewReady: false
  property var pendingResolution: null
  property bool previewDragging: false
  property bool previewMoveDirty: false
  property real previewTargetPan: 0
  property real previewTargetTilt: 0

  readonly property bool previewShouldRun: opened && previewWanted
    && previewReady && !previewSuspended
    && backend.installed && backend.cameraFound
  readonly property bool previewRunning: previewLoader.item
    ? previewLoader.item.active === true : false
  readonly property string previewError: previewLoader.item
    ? String(previewLoader.item.errorString || "") : ""
  readonly property bool cameraUsable: backend.installed && backend.cameraFound
  readonly property bool canMove: cameraUsable && (backend.active || previewRunning)
  readonly property bool canReadCamera: cameraUsable
  readonly property bool canDragPreview: previewRunning && canMove
    && !backend.trackingEnabled
  readonly property string statusText: Model.statusText(
    backend.loaded, backend.installed, backend.cameraFound,
    backend.cameraState)
  readonly property string issueText: {
    if (backend.lastError !== "") return backend.lastError
    if (backend.snapshotError !== "") return backend.snapshotError
    if (backend.issues.length > 0) return String(backend.issues[0].message || "")
    return ""
  }
  readonly property string previewMessage: {
    if (!backend.loaded) return "Checking for Insta360 Link"
    if (!backend.installed) return "linkctl is required"
    if (!backend.cameraFound) return "Connect an Insta360 Link camera"
    if (!previewWanted) return "Preview paused"
    if (previewSuspended) return "Applying video format"
    if (!previewReady) return "Checking camera format"
    if (previewError !== "") return previewError
    if (!previewRunning) return "Starting preview"
    return ""
  }

  readonly property real panMinimum: backend.info.pan_range_degrees
    ? Number(backend.info.pan_range_degrees[0]) : -145
  readonly property real panMaximum: backend.info.pan_range_degrees
    ? Number(backend.info.pan_range_degrees[1]) : 145
  readonly property real tiltMinimum: backend.info.tilt_range_degrees
    ? Number(backend.info.tilt_range_degrees[0]) : -90
  readonly property real tiltMaximum: backend.info.tilt_range_degrees
    ? Number(backend.info.tilt_range_degrees[1]) : 100
  readonly property real zoomMinimum: backend.info.zoom_range
    ? Number(backend.info.zoom_range[0]) : 1
  readonly property real zoomMaximum: backend.info.zoom_range
    ? Number(backend.info.zoom_range[1]) : 4

  readonly property real currentPan: backend.status.pan !== undefined
    ? Number(backend.status.pan)
    : Model.controlValue(backend.info, "Pan, Absolute", 0) / 3600
  readonly property real currentTilt: backend.status.tilt !== undefined
    ? Number(backend.status.tilt)
    : Model.controlValue(backend.info, "Tilt, Absolute", 0) / 3600
  readonly property real currentZoom: backend.status.zoom !== undefined
    ? Number(backend.status.zoom)
    : Model.controlValue(backend.info, "Zoom, Absolute", 100) / 100
  readonly property bool focusAuto: Model.controlValue(
    backend.info, "Focus, Automatic Continuous", 1) === 1
  readonly property bool whiteBalanceAuto: Model.controlValue(
    backend.info, "White Balance, Automatic", 1) === 1

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function move(direction) {
    backend.runAction(direction, [backend.moveStepDegrees])
  }

  function bounded(value, minimum, maximum) {
    return Math.max(minimum, Math.min(maximum, value))
  }

  function stagePreviewMove(pan, tilt, immediate) {
    previewTargetPan = bounded(pan, panMinimum, panMaximum)
    previewTargetTilt = bounded(tilt, tiltMinimum, tiltMaximum)
    previewMoveDirty = true
    if (immediate) {
      previewMoveTimer.stop()
      flushPreviewMove()
    } else if (!previewMoveTimer.running) {
      previewMoveTimer.start()
    }
  }

  function flushPreviewMove() {
    if (!previewMoveDirty || !canDragPreview) return
    previewMoveDirty = false
    backend.runAction("move", [
      "--pan", Model.fixed(previewTargetPan, 1),
      "--tilt", Model.fixed(previewTargetTilt, 1)
    ])
  }

  function toggleTracking() {
    backend.runAction("tracking", [backend.trackingEnabled ? "off" : "on"])
  }

  function setResolution(value) {
    var parsed = Model.parseResolutionValue(value)
    if (!parsed || !cameraUsable) return
    pendingResolution = parsed
    previewSuspended = true
    resolutionReleaseTimer.restart()
  }

  function selectDevice(path) {
    previewReady = false
    previewSuspended = false
    backend.selectDevice(path)
  }

  function resetPanel() {
    previewWanted = backend.settingBool("previewEnabled", true)
    previewSuspended = false
    previewReady = false
    pendingResolution = null
    if (panelFlick) panelFlick.contentY = 0
  }

  onOpenedChanged: {
    backend.panelOpen = opened
    if (opened) {
      resetPanel()
      backend.refresh()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      previewSuspended = false
      previewReady = false
      pendingResolution = null
      previewDragging = false
      previewMoveDirty = false
      previewMoveTimer.stop()
      closeRefreshTimer.restart()
    }
  }

  Service {
    id: backend
    settings: root.settings
    panelOpen: root.opened
  }

  Connections {
    target: backend
    function onSnapshotFinished(ok) {
      if (root.opened) root.previewReady = ok
    }
    function onActionFinished(kind, ok) {
      if (kind === "resolution") previewRestartTimer.restart()
    }
  }

  Timer {
    id: resolutionReleaseTimer
    interval: 400
    repeat: false
    onTriggered: {
      if (!root.pendingResolution) {
        root.previewSuspended = false
        return
      }
      var pending = root.pendingResolution
      root.pendingResolution = null
      if (!backend.runAction("resolution", [pending.spec, "--format", pending.format]))
        root.previewSuspended = false
    }
  }

  Timer {
    id: previewRestartTimer
    interval: 500
    repeat: false
    onTriggered: root.previewSuspended = false
  }

  Timer {
    id: closeRefreshTimer
    interval: 650
    repeat: false
    onTriggered: backend.refresh()
  }

  Timer {
    id: previewMoveTimer
    interval: 120
    repeat: false
    onTriggered: root.flushPreviewMove()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { backend.refresh(); return "ok" }
    function center(): string {
      return backend.runAction("center", []) ? "ok" : "busy"
    }
    function tracking(): string {
      return backend.runAction("tracking", [backend.trackingEnabled ? "off" : "on"])
        ? "ok" : "busy"
    }
    function status(): string { return root.statusText }
    function debug(): string {
      return JSON.stringify({
        opened: root.opened,
        previewWanted: root.previewWanted,
        previewSuspended: root.previewSuspended,
        previewReady: root.previewReady,
        previewShouldRun: root.previewShouldRun,
        previewActive: root.previewRunning,
        previewFormat: previewLoader.item
          ? String(previewLoader.item.formatDescription || "") : "",
        cameraState: backend.cameraState
      })
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.statusText
    active: backend.active || root.previewRunning
    iconComponent: Component {
      CameraIcon {
        anchors.centerIn: parent
        iconSize: Style.space(15)
        color: root.foreground
        active: backend.active || root.previewRunning
        tracking: backend.trackingEnabled
        warning: root.issueText !== ""
          || (backend.loaded && (!backend.installed || !backend.cameraFound))
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) backend.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(480))
    contentHeight: panel.fittedContentHeight(
      Math.round(contentWidth * 9 / 16) + Style.space(12) + column.implicitHeight,
      Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: presetNameField.activeFocus || deviceDropdown.popupOpen
        || resolutionDropdown.popupOpen

      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        var key = String(text).toLowerCase()
        if (key === "r") backend.refresh()
        else if (key === "c") backend.runAction("center", [])
        else if (key === "t") root.toggleTracking()
        else if (key === "p") root.previewWanted = !root.previewWanted
        else if (key === "w") root.move("up")
        else if (key === "a") root.move("left")
        else if (key === "s") root.move("down")
        else if (key === "d") root.move("right")
      }

      Column {
        id: panelLayout
        anchors.fill: parent
        spacing: Style.space(12)

        Rectangle {
          id: previewCard
          width: parent.width
          height: Math.round(width * 9 / 16)
          radius: Style.cornerRadius
          color: "#080a0d"
          clip: true

            Loader {
              id: previewLoader
              anchors.fill: parent
              active: root.previewShouldRun
              source: Qt.resolvedUrl("Preview.qml")
              onLoaded: {
                item.devicePath = Qt.binding(function() { return backend.selectedDevice })
                item.configuredResolution = Qt.binding(function() {
                  return backend.resolution
                })
                item.running = Qt.binding(function() { return root.previewShouldRun })
              }
            }

            MouseArea {
              id: previewDragArea
              anchors.fill: parent
              enabled: root.previewRunning
              hoverEnabled: true
              preventStealing: true
              cursorShape: backend.trackingEnabled
                ? Qt.ForbiddenCursor
                : (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)

              property real pressX: 0
              property real pressY: 0
              property real pointerX: 0
              property real pointerY: 0
              property real startPan: 0
              property real startTilt: 0
              property bool hasDragged: false

              function updateTarget(nextX, nextY) {
                var deltaX = nextX - pressX
                var deltaY = nextY - pressY
                var distance = Math.sqrt(deltaX * deltaX + deltaY * deltaY)
                pointerX = nextX
                pointerY = nextY
                if (distance < Style.space(4)) return

                hasDragged = true
                var zoom = Math.max(1, root.currentZoom)
                var pan = startPan - deltaX / Math.max(1, width) * 90 / zoom
                var tilt = startTilt + deltaY / Math.max(1, height) * 55 / zoom
                root.stagePreviewMove(pan, tilt, false)
              }

              onPressed: function(mouse) {
                if (!root.canDragPreview) {
                  mouse.accepted = false
                  return
                }
                pressX = mouse.x
                pressY = mouse.y
                pointerX = mouse.x
                pointerY = mouse.y
                startPan = root.currentPan
                startTilt = root.currentTilt
                hasDragged = false
                root.previewTargetPan = startPan
                root.previewTargetTilt = startTilt
                root.previewDragging = true
              }

              onPositionChanged: function(mouse) {
                if (pressed && root.canDragPreview)
                  updateTarget(mouse.x, mouse.y)
              }

              onReleased: function(mouse) {
                if (hasDragged && root.canDragPreview) {
                  updateTarget(mouse.x, mouse.y)
                  root.stagePreviewMove(root.previewTargetPan,
                    root.previewTargetTilt, true)
                }
                root.previewDragging = false
              }

              onCanceled: {
                root.previewDragging = false
                root.previewMoveDirty = false
                previewMoveTimer.stop()
              }

              Rectangle {
                visible: previewDragArea.containsMouse
                  && !previewDragArea.pressed
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: Style.space(10)
                implicitWidth: dragHint.implicitWidth + Style.space(14)
                implicitHeight: dragHint.implicitHeight + Style.space(7)
                radius: height / 2
                color: "#bb111418"

                Text {
                  id: dragHint
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: backend.trackingEnabled
                    ? "Disable tracking to drag" : "Drag the view"
                  color: "#ffffff"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              Rectangle {
                visible: root.previewDragging && previewDragArea.hasDragged
                x: Math.max(0, Math.min(parent.width - width,
                  previewDragArea.pointerX - width / 2))
                y: Math.max(0, Math.min(parent.height - height,
                  previewDragArea.pointerY - height / 2))
                width: Style.space(28)
                height: width
                radius: width / 2
                color: "#22000000"
                border.color: "#ffffff"
                border.width: Math.max(1, Style.space(2))
              }

              Rectangle {
                visible: root.previewDragging && previewDragArea.hasDragged
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(10)
                implicitWidth: dragPosition.implicitWidth + Style.space(16)
                implicitHeight: dragPosition.implicitHeight + Style.space(8)
                radius: height / 2
                color: "#dd111418"

                Text {
                  id: dragPosition
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: "Pan " + Model.fixed(root.previewTargetPan, 1)
                    + "°  Tilt " + Model.fixed(root.previewTargetTilt, 1) + "°"
                  color: "#ffffff"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              height: Style.space(52)
              color: "#66000000"

              Column {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(14)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(1)

                Text {
                  textFormat: Text.PlainText
                  text: backend.status.model || "Insta360 Link"
                  color: "#ffffff"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.statusText.toUpperCase()
                  color: "#b8ffffff"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.1
                }
              }

              Button {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: root.previewWanted ? "Pause" : "Preview"
                iconText: root.previewWanted ? "󰈈" : "󰄀"
                foreground: "#ffffff"
                background: "#44000000"
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                focusable: false
                onClicked: root.previewWanted = !root.previewWanted
              }
            }

            Text {
              visible: root.previewMessage !== ""
              anchors.centerIn: parent
              width: parent.width - Style.space(48)
              textFormat: Text.PlainText
              text: root.previewMessage
              color: "#d8ffffff"
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            Rectangle {
              visible: backend.trackingEnabled
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(10)
              implicitWidth: trackingText.implicitWidth + Style.space(14)
              implicitHeight: trackingText.implicitHeight + Style.space(7)
              radius: height / 2
              color: "#bb111418"

              Text {
                id: trackingText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "●  TRACKING"
                color: "#ffffff"
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 0.8
              }
            }
        }

        Flickable {
          id: panelFlick
          width: parent.width
          height: Math.max(0, panelLayout.height - previewCard.height - panelLayout.spacing)
          contentWidth: width
          contentHeight: column.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

            onWheel: function(event) {
              var step = event.angleDelta.y
              var maximumY = panelFlick.contentHeight - panelFlick.height
              if (maximumY <= 0) return
              panelFlick.contentY = Math.max(0,
                Math.min(panelFlick.contentY - step, maximumY))
            }
          }

          Column {
            id: column
            width: panelFlick.width
            spacing: Style.space(12)

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(1)

              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: backend.selectedDevice !== "" ? backend.selectedDevice : root.statusText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: backend.linkctlVersion !== "" ? backend.linkctlVersion : "Camera controller"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            PanelActionButton {
              iconText: backend.refreshing ? "󰑐" : "󰑐"
              tooltipText: "Refresh camera state"
              foreground: root.foreground
              enabled: !backend.busy
              onClicked: backend.refresh()
            }
          }

          Notice {
            visible: root.issueText !== ""
            width: parent.width
            tone: root.urgent
            text: root.issueText
          }

          Column {
            visible: backend.loaded && !backend.installed
            width: parent.width
            spacing: Style.space(8)

            Notice {
              width: parent.width
              tone: root.urgent
              text: "linkctl is required. Install it manually using the official instructions, then click Check again."
            }

            RowLayout {
              spacing: Style.space(8)

              Button {
                text: "Installation instructions"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                focusable: false
                onClicked: Qt.openUrlExternally("https://github.com/illegalstudio/linkctl#installation")
              }

              Button {
                text: "Check again"
                iconText: "󰑐"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                focusable: false
                enabled: !backend.busy
                onClicked: backend.refresh()
              }
            }
          }

          Column {
            visible: backend.devices.length > 1
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "CAMERA"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Dropdown {
              id: deviceDropdown
              width: parent.width
              showLabel: false
              options: Model.deviceOptions(backend.devices)
              value: backend.selectedDevice
              foreground: root.foreground
              fontFamily: root.fontFamily
              onChanged: function(value) { root.selectDevice(value) }
            }
          }

          PanelSeparator {
            visible: root.cameraUsable
            foreground: root.foreground
          }

          Column {
            visible: root.cameraUsable
            width: parent.width
            spacing: Style.space(10)

            RowLayout {
              width: parent.width

              PanelSectionHeader {
                text: "FRAMING"
                foreground: root.foreground
                fontFamily: root.fontFamily
                Layout.fillWidth: true
              }

              Text {
                textFormat: Text.PlainText
                text: "W A S D  ·  C to center"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Column {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(5)

              PtzButton {
                anchors.horizontalCenter: parent.horizontalCenter
                iconText: "󰁝"
                tooltipText: "Tilt up " + backend.moveStepDegrees + "°"
                enabled: root.canMove
                onClicked: root.move("up")
              }

              Row {
                spacing: Style.space(5)

                PtzButton {
                  iconText: "󰁍"
                  tooltipText: "Pan left " + backend.moveStepDegrees + "°"
                  enabled: root.canMove
                  onClicked: root.move("left")
                }

                PtzButton {
                  iconText: "󰓤"
                  tooltipText: "Center camera"
                  enabled: root.canMove
                  onClicked: backend.runAction("center", [])
                }

                PtzButton {
                  iconText: "󰁔"
                  tooltipText: "Pan right " + backend.moveStepDegrees + "°"
                  enabled: root.canMove
                  onClicked: root.move("right")
                }
              }

              PtzButton {
                anchors.horizontalCenter: parent.horizontalCenter
                iconText: "󰁅"
                tooltipText: "Tilt down " + backend.moveStepDegrees + "°"
                enabled: root.canMove
                onClicked: root.move("down")
              }
            }

            ControlSlider {
              title: "Pan"
              suffix: "°"
              minimum: root.panMinimum
              maximum: root.panMaximum
              step: 1
              value: root.currentPan
              enabled: root.canMove
              action: "pan"
            }

            ControlSlider {
              title: "Tilt"
              suffix: "°"
              minimum: root.tiltMinimum
              maximum: root.tiltMaximum
              step: 1
              value: root.currentTilt
              enabled: root.canMove
              action: "tilt"
            }

            ControlSlider {
              title: "Zoom"
              suffix: "x"
              minimum: root.zoomMinimum
              maximum: root.zoomMaximum
              step: 0.1
              value: root.currentZoom
              enabled: root.canMove
              action: "zoom"
              digits: 1
            }

            ToggleRow {
              title: "AI subject tracking"
              subtitle: "Experimental Link 2 vendor control"
              checked: backend.trackingEnabled
              enabled: root.canMove
              onToggleRequested: root.toggleTracking()
            }
          }

          PanelSeparator {
            visible: root.cameraUsable
            foreground: root.foreground
          }

          Column {
            visible: root.cameraUsable
            width: parent.width
            spacing: Style.space(9)

            PanelSectionHeader {
              text: "FRAMING PRESETS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              TextField {
                id: presetNameField
                Layout.fillWidth: true
                placeholderText: "Preset name"
                foreground: root.foreground
                font.family: root.fontFamily
                validator: RegularExpressionValidator {
                  regularExpression: /^[A-Za-z0-9_-]{0,64}$/
                }
                onAccepted: if (text !== "" && root.canReadCamera) {
                  backend.runAction("preset", ["save", text])
                  text = ""
                  keyCatcher.forceActiveFocus()
                }
              }

              Button {
                text: "Save"
                iconText: "󰆓"
                bordered: true
                enabled: presetNameField.text !== "" && root.canReadCamera
                foreground: root.foreground
                fontFamily: root.fontFamily
                focusable: false
                onClicked: {
                  backend.runAction("preset", ["save", presetNameField.text])
                  presetNameField.text = ""
                }
              }
            }

            Text {
              visible: backend.presets.length === 0
              width: parent.width
              textFormat: Text.PlainText
              text: "No presets saved yet."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: backend.presets

                PresetRow {
                  required property var modelData
                  width: parent.width
                  preset: modelData
                }
              }
            }
          }

          PanelSeparator {
            visible: root.cameraUsable
            foreground: root.foreground
          }

          Column {
            visible: root.cameraUsable
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "FOCUS AND WHITE BALANCE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ToggleRow {
              title: "Autofocus"
              subtitle: root.focusAuto ? "Continuous focus" : "Manual focus"
              checked: root.focusAuto
              enabled: root.canMove
              onToggleRequested: {
                if (root.focusAuto) backend.runAction("focus", [
                  Model.controlValue(backend.info, "Focus, Absolute", 50)])
                else backend.runAction("focus", ["auto"])
              }
            }

            ControlSlider {
              visible: !root.focusAuto
              title: "Focus"
              minimum: Model.controlMinimum(backend.info, "Focus, Absolute", 0)
              maximum: Model.controlMaximum(backend.info, "Focus, Absolute", 100)
              step: Model.controlStep(backend.info, "Focus, Absolute", 1)
              value: Model.controlValue(backend.info, "Focus, Absolute", 50)
              enabled: root.canMove
              action: "focus"
            }

            ToggleRow {
              title: "Auto white balance"
              subtitle: root.whiteBalanceAuto ? "Automatic temperature" : "Manual temperature"
              checked: root.whiteBalanceAuto
              enabled: root.canMove
              onToggleRequested: {
                if (root.whiteBalanceAuto) backend.runAction("wb", [
                  Model.controlValue(backend.info, "White Balance Temperature", 6400)])
                else backend.runAction("wb", ["auto"])
              }
            }

            ControlSlider {
              visible: !root.whiteBalanceAuto
              title: "Temperature"
              suffix: "K"
              minimum: Model.controlMinimum(backend.info, "White Balance Temperature", 2000)
              maximum: Model.controlMaximum(backend.info, "White Balance Temperature", 10000)
              step: 50
              value: Model.controlValue(backend.info, "White Balance Temperature", 6400)
              enabled: root.canMove
              action: "wb"
            }
          }

          PanelSeparator {
            visible: root.cameraUsable
            foreground: root.foreground
          }

          Column {
            visible: root.cameraUsable
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "IMAGE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ControlSlider {
              title: "Brightness"
              minimum: Model.controlMinimum(backend.info, "Brightness", 0)
              maximum: Model.controlMaximum(backend.info, "Brightness", 100)
              step: Model.controlStep(backend.info, "Brightness", 1)
              value: Model.controlValue(backend.info, "Brightness", 50)
              enabled: root.canMove
              action: "brightness"
            }

            ControlSlider {
              title: "Contrast"
              minimum: Model.controlMinimum(backend.info, "Contrast", 0)
              maximum: Model.controlMaximum(backend.info, "Contrast", 100)
              step: Model.controlStep(backend.info, "Contrast", 1)
              value: Model.controlValue(backend.info, "Contrast", 50)
              enabled: root.canMove
              action: "contrast"
            }

            ControlSlider {
              title: "Saturation"
              minimum: Model.controlMinimum(backend.info, "Saturation", 0)
              maximum: Model.controlMaximum(backend.info, "Saturation", 100)
              step: Model.controlStep(backend.info, "Saturation", 1)
              value: Model.controlValue(backend.info, "Saturation", 50)
              enabled: root.canMove
              action: "saturation"
            }

            ControlSlider {
              title: "Sharpness"
              minimum: Model.controlMinimum(backend.info, "Sharpness", 0)
              maximum: Model.controlMaximum(backend.info, "Sharpness", 100)
              step: Model.controlStep(backend.info, "Sharpness", 1)
              value: Model.controlValue(backend.info, "Sharpness", 50)
              enabled: root.canMove
              action: "sharpness"
            }

            ControlSlider {
              title: "Hue"
              minimum: Model.controlMinimum(backend.info, "Hue", -15)
              maximum: Model.controlMaximum(backend.info, "Hue", 15)
              step: Model.controlStep(backend.info, "Hue", 1)
              value: Model.controlValue(backend.info, "Hue", 0)
              enabled: root.canMove
              action: "hue"
            }
          }

          PanelSeparator {
            visible: root.cameraUsable
            foreground: root.foreground
          }

          Column {
            visible: root.cameraUsable
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "VIDEO FORMAT"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            CameraDropdown {
              id: resolutionDropdown
              width: parent.width
              showLabel: false
              options: Model.resolutionOptions(backend.formats)
              value: Model.currentResolutionValue(backend.resolution)
              foreground: root.foreground
              fontFamily: root.fontFamily
              onChanged: function(value) { root.setResolution(value) }
            }

            Notice {
              width: parent.width
              text: "Changing the format briefly pauses the embedded preview. Browsers and PipeWire may negotiate a different format."
            }
          }

          Item {
            width: 1
            height: Style.space(2)
          }
        }

      }
      }
    }
  }

  component PtzButton: PanelActionButton {
    size: Style.space(42)
    fontSize: Style.font.iconLarge
    foreground: root.foreground
    bordered: true
  }

  component ControlSlider: Column {
    id: control

    property string title: ""
    property string suffix: ""
    property string action: ""
    property real value: 0
    property real minimum: 0
    property real maximum: 100
    property real step: 1
    property int digits: step < 1 ? 1 : 0

    width: parent ? parent.width : 0
    spacing: Style.space(2)
    opacity: enabled ? 1.0 : 0.48

    Row {
      width: parent.width

      Text {
        textFormat: Text.PlainText
        text: control.title
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Item {
        width: Math.max(0, parent.width - parent.children[0].implicitWidth
          - parent.children[2].implicitWidth)
        height: 1
      }

      Text {
        textFormat: Text.PlainText
        text: Model.fixed(cameraSlider.liveValue, control.digits)
          + control.suffix
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    CameraSlider {
      id: cameraSlider
      bar: root.bar
      width: parent.width
      minimum: control.minimum
      maximum: control.maximum
      step: control.step
      integer: control.step >= 1
      value: control.value
      enabled: control.enabled
      onReleased: function(value) {
        var accepted = backend.runAction(control.action,
          [Model.fixed(value, control.digits)])
        if (!accepted) cameraSlider.finishRequest(false)
      }
    }

    Connections {
      target: backend

      function onActionFinished(kind, ok) {
        if (kind === control.action) cameraSlider.finishRequest(ok)
      }
    }
  }

  component ToggleRow: RowLayout {
    id: toggleRow

    property string title: ""
    property string subtitle: ""
    property bool checked: false
    signal toggleRequested()

    width: parent ? parent.width : 0
    spacing: Style.space(8)
    opacity: enabled ? 1.0 : 0.48

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(1)

      Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: toggleRow.title
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        visible: toggleRow.subtitle !== ""
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: toggleRow.subtitle
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    ToggleSwitch {
      checked: toggleRow.checked
      busy: backend.acting && backend.currentAction === "tracking"
      enabled: toggleRow.enabled
      foreground: root.foreground
      Layout.alignment: Qt.AlignVCenter
      onToggled: toggleRow.toggleRequested()
    }
  }

  component Notice: Text {
    property color tone: root.dim

    textFormat: Text.PlainText
    color: tone
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }

  component PresetRow: BorderSurface {
    id: presetRow

    property var preset: ({})

    color: root.subtleFill
    borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
    radius: Style.cornerRadius
    implicitHeight: presetContents.implicitHeight + Style.space(12)

    RowLayout {
      id: presetContents
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: String(presetRow.preset.name || "Preset")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: "Pan " + Model.fixed(presetRow.preset.pan, 1) + "°  ·  Tilt "
            + Model.fixed(presetRow.preset.tilt, 1) + "°  ·  Zoom "
            + Model.fixed(presetRow.preset.zoom, 1) + "x"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        iconText: "󰒭"
        tooltipText: "Load preset"
        foreground: root.foreground
        enabled: root.canMove
        onClicked: backend.runAction("preset", ["load", presetRow.preset.name])
      }

      PanelActionButton {
        iconText: "󰩺"
        tooltipText: "Delete preset"
        foreground: root.foreground
        hoverColor: root.urgent
        enabled: root.canReadCamera
        onClicked: backend.runAction("preset", ["delete", presetRow.preset.name])
      }
    }
  }
}
