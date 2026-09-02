<p align="center">
  <img src="assets/logo-mark.svg" alt="Omarchy Insta360 logo" width="130">
</p>

<h1 align="center">Omarchy Insta360</h1>

<p align="center">
  <em>Your Insta360 Link, directly from the Omarchy bar.</em>
</p>

<p align="center">
  <a href="https://github.com/illegalstudio/omarchy-insta360/stargazers"><img src="https://img.shields.io/github/stars/illegalstudio/omarchy-insta360?style=flat-square&logo=github&logoColor=white&label=stars&color=FFCC00" alt="Stars"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/illegalstudio/omarchy-insta360?style=flat-square&color=FFCC00" alt="License: MIT"></a>
  <a href="https://omarchy.org"><img src="https://img.shields.io/badge/Omarchy-4.x-FFCC00?style=flat-square" alt="Omarchy 4.x"></a>
  <a href="https://x.com/nahime0"><img src="https://img.shields.io/badge/Follow-%40nahime0-FFCC00?style=flat-square&logo=x&logoColor=white" alt="Follow @nahime0 on X"></a>
</p>

<p align="center">
  <strong>Native Qt preview &middot; Natural drag control &middot; Full camera controls &middot; Powered by linkctl</strong>
</p>

<p align="center">
  A native Omarchy Shell widget for previewing and controlling Insta360 Link webcams without leaving the desktop bar. Move the camera from the live image, manage framing presets, tune image controls, and switch video formats through a focused interface backed by <a href="https://github.com/illegalstudio/linkctl">linkctl</a>.
</p>

<p align="center">
  <a href="https://opensource.nahi.me"><strong>Official Website</strong></a>
</p>

---

## Install

```bash
omarchy plugin add https://github.com/illegalstudio/omarchy-insta360.git --enable
```

The widget is placed in the right section of the bar by default. Move an existing instance with:

```bash
omarchy bar move illegalstudio.omarchy-insta360 --section right
```

## Remove

```bash
omarchy plugin disable illegalstudio.omarchy-insta360
omarchy plugin remove illegalstudio.omarchy-insta360
```

Removing the plugin does not remove `linkctl`. If the plugin installed it through mise and you no longer need it, remove it separately with `mise unuse -g github:illegalstudio/linkctl`.

## Using the widget

Click the camera icon in the bar to open the panel. The live preview stays fixed at the top while the controls scroll underneath it.

- Drag the preview naturally to adjust pan and tilt together. The image follows the pointer.
- Pause or resume the embedded preview from its header.
- Use the directional pad, absolute sliders, or `W`, `A`, `S`, `D` for framing.
- Center the camera, change zoom, or enable experimental AI subject tracking.
- Save, load, and delete named framing presets.
- Control focus, white balance, brightness, contrast, saturation, sharpness, and hue.
- Select a resolution, frame rate, and MJPEG or H.264 video format.
- Right-click the bar icon to refresh camera state.

Natural preview dragging is disabled while AI tracking is active so the two controllers do not compete.

## Native preview

The preview is rendered directly by Qt Multimedia. It does not require ffplay or mpv and is created only while the panel is open, so the camera is released as soon as the panel closes.

The embedded preview uses the resolution and frame rate currently reported by `linkctl`; it does not apply a separate lightweight format. Changing the configured camera output format briefly pauses and restarts the preview with the new values.

## linkctl setup

Every camera operation goes through [linkctl](https://github.com/illegalstudio/linkctl). The plugin searches `PATH`, mise, and the standard mise installation directory.

When `linkctl` is missing and mise is available, the panel offers an explicit installation button that runs:

```bash
mise use -g github:illegalstudio/linkctl@latest
```

Automatic installation on panel open is available as an opt-in setting and is disabled by default. If mise is unavailable, install `linkctl` manually before opening the panel.

## Requirements

- Omarchy 4 or newer with the current shell plugin system.
- An Insta360 Link webcam supported by `linkctl`.
- Qt Multimedia, included with current Omarchy installations.
- Camera device read and write permission for the active desktop session.

## Configuration

Widget settings are stored by Omarchy in `~/.config/omarchy/shell.json`.

| Setting | Default | Purpose |
| --- | ---: | --- |
| `autoInstallLinkctl` | `false` | After explicit opt-in, install `linkctl` through mise when it is missing. |
| `previewEnabled` | `true` | Start the embedded preview when the panel opens. |
| `moveStepDegrees` | `5` | Degrees moved by the directional buttons and keyboard shortcuts. |
| `refreshIntervalSec` | `10` | Interval for background camera state refreshes. |

You can update a setting through Omarchy, for example:

```bash
omarchy bar set illegalstudio.omarchy-insta360 moveStepDegrees 10
```

## Keyboard controls

When the panel has focus:

| Key | Action |
| --- | --- |
| `W`, `A`, `S`, `D` | Move up, left, down, or right. |
| `C` | Center the camera. |
| `T` | Toggle AI tracking. |
| `P` | Pause or resume the preview. |
| `R` | Refresh camera state. |
| `Esc` | Close the panel. |

## Development install

Clone the repository and expose it through the user plugin directory. Do not modify the packaged Omarchy files under `/usr/share/omarchy`.

```bash
git clone https://github.com/illegalstudio/omarchy-insta360.git
ln -s "$PWD/omarchy-insta360" "$HOME/.config/omarchy/plugins/illegalstudio.omarchy-insta360"
omarchy plugin enable illegalstudio.omarchy-insta360 --section right
```

Validate the manifest and run the bridge tests with:

```bash
omarchy plugin validate .
python3 -m unittest discover -s tests -v
```

## Safety

The bridge passes fixed argument arrays directly to `linkctl` and never invokes a shell. It validates every action, number, video format, and preset name before execution.

The plugin deliberately does not expose `linkctl --force`, so the inactive-camera safety guard remains active. Camera commands are asynchronous and coalesced to keep the Omarchy interface responsive during rapid slider or preview interactions.

See the [linkctl Linux permissions documentation](https://github.com/illegalstudio/linkctl#linux-permissions) if the panel reports a device permission error.

## License

[MIT](LICENSE)
