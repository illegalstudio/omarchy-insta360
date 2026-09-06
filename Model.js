.pragma library

function asNumber(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? number : fallback
}

function fixed(value, digits) {
  var number = asNumber(value, 0)
  var text = number.toFixed(digits === undefined ? 1 : digits)
  return text.replace(/\.0+$/, "")
}

function control(info, name) {
  var controls = info && Array.isArray(info.controls) ? info.controls : []
  for (var i = 0; i < controls.length; i++) {
    if (String(controls[i].name || "") === name) return controls[i]
  }
  return null
}

function controlValue(info, name, fallback) {
  var item = control(info, name)
  return item && item.value !== null && item.value !== undefined
    ? asNumber(item.value, fallback) : fallback
}

function controlMinimum(info, name, fallback) {
  var item = control(info, name)
  return item ? asNumber(item.min, fallback) : fallback
}

function controlMaximum(info, name, fallback) {
  var item = control(info, name)
  return item ? asNumber(item.max, fallback) : fallback
}

function controlStep(info, name, fallback) {
  var item = control(info, name)
  return item ? Math.max(0.0001, asNumber(item.step, fallback)) : fallback
}

function deviceOptions(devices) {
  var list = []
  var rows = Array.isArray(devices) ? devices : []
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i] || {}
    var label = String(row.model || "Insta360 Link")
    var path = String(row.device || "")
    if (path !== "") list.push({ value: path, label: label + "  " + path })
  }
  return list
}

function mediaDeviceFor(videoInputs, selectedPath) {
  var devices = videoInputs || []
  var fallback = null
  var selected = String(selectedPath || "")
  for (var i = 0; i < devices.length; i++) {
    var device = devices[i]
    var id = String(device.id || "")
    var description = String(device.description || "")
    if (selected !== "" && (id === selected || id.indexOf(selected) !== -1)) return device
    if (!fallback && description.toLowerCase().indexOf("insta360") !== -1) fallback = device
  }
  return fallback
}

function previewFormat(device, configuredResolution) {
  var formats = device && device.videoFormats ? device.videoFormats : []
  if (!formats || formats.length === 0) return null

  var configured = configuredResolution || {}
  var wantedWidth = asNumber(configured.width, 0)
  var wantedHeight = asNumber(configured.height, 0)
  var wantedFps = asNumber(configured.fps, 0)
  if (wantedWidth <= 0 || wantedHeight <= 0) return null

  var best = null
  var bestScore = Number.POSITIVE_INFINITY

  for (var i = 0; i < formats.length; i++) {
    var format = formats[i]
    var width = asNumber(format.resolution.width, 0)
    var height = asNumber(format.resolution.height, 0)
    if (width !== wantedWidth || height !== wantedHeight) continue

    if (wantedFps <= 0) return format
    var minimumFps = asNumber(format.minFrameRate, 0)
    var maximumFps = asNumber(format.maxFrameRate, 0)
    var includesFps = wantedFps >= minimumFps - 0.01
      && wantedFps <= maximumFps + 0.01
    var score = Math.min(Math.abs(wantedFps - minimumFps),
                         Math.abs(wantedFps - maximumFps))
      + (includesFps ? 0 : 10000)
    if (score < bestScore) {
      best = format
      bestScore = score
    }
  }
  return best
}

function formatName(fourcc) {
  var value = String(fourcc || "").toUpperCase()
  if (value === "MJPG") return "MJPEG"
  return value
}

function resolutionValue(format, width, height, fps) {
  return String(format || "").toLowerCase() + "|" + width + "x" + height + "@" + fixed(fps, 2)
}

function resolutionOptions(formats) {
  var result = []
  var groups = Array.isArray(formats) ? formats : []
  for (var i = 0; i < groups.length; i++) {
    var group = groups[i] || {}
    var sizes = Array.isArray(group.sizes) ? group.sizes : []
    for (var j = 0; j < sizes.length; j++) {
      var size = sizes[j] || {}
      var rates = Array.isArray(size.fps) ? size.fps : []
      for (var k = 0; k < rates.length; k++) {
        result.push({
          value: resolutionValue(group.fourcc, size.width, size.height, rates[k]),
          label: size.width + " x " + size.height + "  " + fixed(rates[k], 2)
            + " fps  " + formatName(group.fourcc)
        })
      }
    }
  }
  return result
}

function currentResolutionValue(resolution) {
  if (!resolution || !resolution.width || !resolution.height) return ""
  return resolutionValue(resolution.fourcc, resolution.width,
                         resolution.height, resolution.fps)
}

function parseResolutionValue(value) {
  var parts = String(value || "").split("|")
  if (parts.length !== 2) return null
  var format = parts[0]
  if (format !== "mjpg" && format !== "mjpeg" && format !== "h264") return null
  return {
    format: format === "mjpg" ? "mjpeg" : format,
    spec: parts[1]
  }
}

function statusText(snapshotLoaded, installed, cameraFound, state) {
  if (!snapshotLoaded) return "Checking camera"
  if (!installed) return "linkctl is not installed"
  if (!cameraFound) return "No Insta360 Link detected"
  if (state === "active") return "Camera active"
  return "Camera ready"
}

function errorText(payload, fallback) {
  if (!payload) return fallback || "Unknown error"
  if (payload.message) return String(payload.message)
  if (payload.error && typeof payload.error === "string") return payload.error
  if (payload.error && payload.error.message) return String(payload.error.message)
  return fallback || "Unknown error"
}
