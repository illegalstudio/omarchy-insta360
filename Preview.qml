import QtQuick
import QtMultimedia
import "Model.js" as Model

Item {
  id: root

  property string devicePath: ""
  property bool running: false
  readonly property var mediaDevice: Model.mediaDeviceFor(
    mediaDevices.videoInputs, devicePath)
  readonly property var selectedFormat: Model.previewFormat(mediaDevice, 1280, 720)
  readonly property bool deviceAvailable: mediaDevice !== null
  readonly property bool active: previewCamera.active
  readonly property string errorString: previewCamera.errorString
  readonly property string formatDescription: {
    var format = previewCamera.cameraFormat
    var width = format ? Number(format.resolution.width) : 0
    var height = format ? Number(format.resolution.height) : 0
    var fps = format ? Number(format.maxFrameRate) : 0
    return width > 0 && height > 0
      ? width + "x" + height + "@" + Math.round(fps) : ""
  }

  MediaDevices {
    id: mediaDevices
  }

  Camera {
    id: previewCamera
    cameraDevice: root.mediaDevice || mediaDevices.defaultVideoInput
    cameraFormat: root.selectedFormat
    active: root.running && root.deviceAvailable
  }

  CaptureSession {
    camera: previewCamera
    videoOutput: previewOutput
  }

  VideoOutput {
    id: previewOutput
    anchors.fill: parent
    fillMode: VideoOutput.PreserveAspectCrop
    visible: previewCamera.active && previewCamera.errorString === ""
  }
}
