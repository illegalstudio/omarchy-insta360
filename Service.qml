import QtQuick
import Quickshell.Io

Item {
  id: root

  property var settings: ({})
  property bool panelOpen: false

  readonly property string bridgePath: {
    var value = String(Qt.resolvedUrl("scripts/linkctl_bridge.py"))
    return value.indexOf("file://") === 0
      ? decodeURIComponent(value.substring(7)) : value
  }

  property bool loaded: false
  property bool installed: false
  property bool miseAvailable: false
  property bool cameraFound: false
  property string linkctlPath: ""
  property string linkctlVersion: ""
  property var devices: []
  property string selectedDevice: ""
  property var status: ({})
  property var info: ({})
  property var formats: []
  property var resolution: ({})
  property var presets: []
  property var tracking: ({})
  property var issues: []

  property string snapshotError: ""
  property string lastError: ""
  property string actionStatus: ""
  property bool installAttempted: false
  property string currentAction: ""
  property var _actionQueue: []

  readonly property bool refreshing: snapshotProcess.running
  readonly property bool installing: installProcess.running
  readonly property bool acting: actionProcess.running
  readonly property bool actionBusy: installing || acting || _actionQueue.length > 0
  readonly property bool busy: refreshing || actionBusy
  readonly property string cameraState: status && status.state ? String(status.state) : "inactive"
  readonly property bool active: cameraState === "active"
  readonly property bool trackingEnabled: tracking && tracking.tracking === true
  readonly property bool autoInstallLinkctl: settingBool("autoInstallLinkctl", false)
  readonly property int refreshIntervalSec: settingInt("refreshIntervalSec", 10, 2, 60)
  readonly property int moveStepDegrees: settingInt("moveStepDegrees", 5, 1, 45)

  signal actionFinished(string kind, bool ok)

  function settingValue(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function settingBool(name, fallback) {
    var value = settingValue(name, fallback)
    if (typeof value === "boolean") return value
    return String(value).toLowerCase() === "true"
  }

  function settingInt(name, fallback, minimum, maximum) {
    var value = parseInt(String(settingValue(name, fallback)), 10)
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  function _append(which, data) {
    var text = String(data || "")
    var limit = 768 * 1024
    if (which === "snapshot") _snapshotOutput = (_snapshotOutput + text).substring(0, limit)
    else if (which === "snapshotError") _snapshotErrorOutput = (_snapshotErrorOutput + text).substring(0, limit)
    else if (which === "action") _actionOutput = (_actionOutput + text).substring(0, limit)
    else if (which === "actionError") _actionErrorOutput = (_actionErrorOutput + text).substring(0, limit)
    else if (which === "install") _installOutput = (_installOutput + text).substring(0, limit)
    else if (which === "installError") _installErrorOutput = (_installErrorOutput + text).substring(0, limit)
  }

  function _payload(output, errorOutput) {
    var text = String(output || "").trim()
    if (text === "") text = String(errorOutput || "").trim()
    if (text === "") return null
    try {
      return JSON.parse(text)
    } catch (error) {
      return null
    }
  }

  function _cleanError(value, fallback) {
    var text = String(value || fallback || "Unknown error").replace(/\s+/g, " ").trim()
    return text.length > 240 ? text.substring(0, 237) + "..." : text
  }

  function _snapshotCommand() {
    var command = [bridgePath, "snapshot"]
    if (selectedDevice !== "") command.push("--device", selectedDevice)
    return command
  }

  function refresh() {
    if (snapshotProcess.running || installProcess.running || actionProcess.running
        || _actionQueue.length > 0) return
    snapshotProcess.command = _snapshotCommand()
    snapshotProcess.running = true
  }

  function ensureReady() {
    if (loaded && !installed && autoInstallLinkctl && miseAvailable && !installAttempted) {
      installLinkctl()
      return
    }
    refresh()
  }

  function installLinkctl() {
    if (snapshotProcess.running || installProcess.running || actionProcess.running) return
    installAttempted = true
    lastError = ""
    actionStatus = "Installing linkctl with mise"
    installProcess.command = [bridgePath, "install"]
    installProcess.running = true
  }

  function selectDevice(path) {
    var value = String(path || "")
    if (value === selectedDevice) return
    selectedDevice = value
    status = ({})
    info = ({})
    formats = []
    resolution = ({})
    tracking = ({})
    refresh()
  }

  function runAction(kind, args) {
    if (installProcess.running) return false
    var request = {
      kind: String(kind),
      args: Array.isArray(args) ? args.slice() : []
    }
    if (snapshotProcess.running || actionProcess.running || _actionQueue.length > 0) {
      if (!_enqueueAction(request)) return false
      Qt.callLater(_startNextAction)
      return true
    }
    _startAction(request)
    return true
  }

  function _coalesces(kind) {
    return kind === "pan" || kind === "tilt" || kind === "move"
      || kind === "zoom"
      || kind === "focus" || kind === "wb" || kind === "brightness"
      || kind === "contrast" || kind === "saturation" || kind === "sharpness"
      || kind === "hue" || kind === "tracking" || kind === "resolution"
  }

  function _enqueueAction(request) {
    var queue = _actionQueue.slice()
    if (_coalesces(request.kind)) {
      for (var i = queue.length - 1; i >= 0; i--) {
        if (queue[i].kind === request.kind) queue.splice(i, 1)
      }
    }
    if (queue.length >= 32) {
      lastError = "Camera command queue is full"
      return false
    }
    queue.push(request)
    _actionQueue = queue
    return true
  }

  function _startNextAction() {
    if (snapshotProcess.running || installProcess.running || actionProcess.running
        || _actionQueue.length === 0) return
    var queue = _actionQueue.slice()
    var request = queue.shift()
    _actionQueue = queue
    _startAction(request)
  }

  function _startAction(request) {
    var command = [bridgePath, "action"]
    if (selectedDevice !== "") command.push("--device", selectedDevice)
    command.push("--", request.kind)
    var values = request.args
    for (var i = 0; i < values.length; i++) command.push(String(values[i]))
    currentAction = request.kind
    lastError = ""
    actionStatus = actionLabel(currentAction)
    actionProcess.command = command
    actionProcess.running = true
  }

  function actionLabel(kind) {
    if (kind === "preset") return "Updating presets"
    if (kind === "resolution") return "Changing video format"
    if (kind === "tracking") return "Updating tracking"
    if (kind === "center" || kind === "left" || kind === "right"
        || kind === "up" || kind === "down" || kind === "pan"
        || kind === "tilt" || kind === "move") return "Moving camera"
    return "Updating camera"
  }

  function _applySnapshot(payload) {
    if (!payload) {
      snapshotError = "The linkctl bridge returned invalid data"
      loaded = true
      return
    }

    installed = payload.installed === true
    miseAvailable = payload.miseAvailable === true
    cameraFound = payload.cameraFound === true
    linkctlPath = String(payload.path || "")
    linkctlVersion = String(payload.version || "")
    devices = Array.isArray(payload.devices) ? payload.devices : []
    if (payload.selectedDevice) selectedDevice = String(payload.selectedDevice)
    status = payload.status && typeof payload.status === "object" ? payload.status : ({})
    info = payload.info && typeof payload.info === "object" ? payload.info : ({})
    formats = Array.isArray(payload.formats) ? payload.formats : []
    resolution = payload.resolution && typeof payload.resolution === "object"
      ? payload.resolution : ({})
    presets = Array.isArray(payload.presets) ? payload.presets : []
    tracking = payload.tracking && typeof payload.tracking === "object"
      ? payload.tracking : ({})
    issues = Array.isArray(payload.issues) ? payload.issues : []
    snapshotError = payload.ok === false
      ? _cleanError(payload.error, "Could not read camera state") : ""
    loaded = true

    if (!installed && panelOpen && autoInstallLinkctl && miseAvailable && !installAttempted)
      Qt.callLater(installLinkctl)
  }

  property string _snapshotOutput: ""
  property string _snapshotErrorOutput: ""
  property string _actionOutput: ""
  property string _actionErrorOutput: ""
  property string _installOutput: ""
  property string _installErrorOutput: ""

  Process {
    id: snapshotProcess
    running: false
    command: []
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) { root._append("snapshot", data) }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(data) { root._append("snapshotError", data) }
    }
    onStarted: {
      root._snapshotOutput = ""
      root._snapshotErrorOutput = ""
    }
    onExited: function(exitCode) {
      var payload = root._payload(root._snapshotOutput, root._snapshotErrorOutput)
      root._applySnapshot(payload)
      if (!payload && exitCode !== 0)
        root.snapshotError = "Could not run the linkctl bridge"
      if (root._actionQueue.length > 0) Qt.callLater(root._startNextAction)
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) { root._append("action", data) }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(data) { root._append("actionError", data) }
    }
    onStarted: {
      root._actionOutput = ""
      root._actionErrorOutput = ""
    }
    onExited: function(exitCode) {
      var kind = root.currentAction
      var payload = root._payload(root._actionOutput, root._actionErrorOutput)
      var ok = payload && payload.ok === true && exitCode === 0
      root.actionStatus = ""
      root.lastError = ok ? "" : root._cleanError(
        payload ? payload.error : root._actionErrorOutput,
        "linkctl could not apply the change")
      root.currentAction = ""
      root.actionFinished(kind, ok)
      if (root._actionQueue.length > 0) Qt.callLater(root._startNextAction)
      else refreshDelay.restart()
    }
  }

  Process {
    id: installProcess
    running: false
    command: []
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) { root._append("install", data) }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(data) { root._append("installError", data) }
    }
    onStarted: {
      root._installOutput = ""
      root._installErrorOutput = ""
    }
    onExited: function(exitCode) {
      var payload = root._payload(root._installOutput, root._installErrorOutput)
      var ok = payload && payload.ok === true && payload.installed === true
      root.actionStatus = ""
      root.lastError = ok ? "" : root._cleanError(
        payload ? payload.error : root._installErrorOutput,
        "mise could not install linkctl")
      if (ok) {
        root.installed = true
        root.linkctlPath = String(payload.path || "")
        root.linkctlVersion = String(payload.version || "")
      }
      root.actionFinished("install", ok && exitCode === 0)
      refreshDelay.restart()
    }
  }

  Timer {
    id: refreshDelay
    interval: 250
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!root.panelOpen || !root.active) root.refresh()
    }
  }
}
