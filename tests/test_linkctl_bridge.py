from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock


BRIDGE_PATH = Path(__file__).parents[1] / "scripts/linkctl_bridge.py"
SPEC = importlib.util.spec_from_file_location("linkctl_bridge", BRIDGE_PATH)
BRIDGE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(BRIDGE)


FAKE_LINKCTL = r'''#!/usr/bin/env python3
import json
import sys

args = sys.argv[1:]
if args == ["--version"]:
    print("linkctl 9.9.9")
    raise SystemExit(0)
if args and args[0] == "--json":
    args.pop(0)
if len(args) >= 2 and args[0] == "--device":
    args = args[2:]

payloads = {
    ("devices",): [{"model": "Insta360 Link 2", "device": "/dev/video8"}],
    ("status",): {"model": "Insta360 Link 2", "device": "/dev/video8", "state": "active", "pan": 2.0, "tilt": 3.0, "zoom": 1.5},
    ("info", "--controls"): {"pan_range_degrees": [-145.0, 145.0], "tilt_range_degrees": [-90.0, 100.0], "zoom_range": [1.0, 4.0], "controls": []},
    ("formats",): [{"fourcc": "MJPG", "sizes": [{"width": 1280, "height": 720, "fps": [30.0]}]}],
    ("resolution",): {"fourcc": "MJPG", "width": 1280, "height": 720, "fps": 30.0},
    ("preset", "list"): [{"name": "desk", "pan": 2.0, "tilt": 3.0, "zoom": 1.5}],
    ("tracking", "status"): {"tracking": True, "raw": 1},
}
key = tuple(args)
if key in payloads:
    print(json.dumps(payloads[key]))
    raise SystemExit(0)
if key and key[0] in {"center", "pan", "tilt", "move", "zoom", "focus", "wb", "brightness", "contrast", "saturation", "sharpness", "hue", "tracking", "preset", "resolution", "left", "right", "up", "down"}:
    print(json.dumps({"applied": list(key)}))
    raise SystemExit(0)
print(json.dumps({"error": "unsupported", "message": "unsupported"}), file=sys.stderr)
raise SystemExit(2)
'''


class BridgeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.binary = Path(self.temp_dir.name) / "linkctl"
        self.binary.write_text(FAKE_LINKCTL)
        self.binary.chmod(0o755)
        self.env = mock.patch.dict(
            os.environ,
            {"OMARCHY_INSTA360_LINKCTL": str(self.binary)},
            clear=False,
        )
        self.env.start()

    def tearDown(self) -> None:
        self.env.stop()
        self.temp_dir.cleanup()

    def test_probe_finds_explicit_binary(self) -> None:
        result = BRIDGE.probe()
        self.assertTrue(result["installed"])
        self.assertEqual(result["version"], "linkctl 9.9.9")

    def test_executable_preserves_a_shim_path(self) -> None:
        shim = Path(self.temp_dir.name) / "linkctl-shim"
        shim.symlink_to(self.binary)
        result = BRIDGE.executable(shim)
        self.assertEqual(result, str(shim.absolute()))

    def test_snapshot_combines_read_only_commands(self) -> None:
        result = BRIDGE.snapshot("")
        self.assertTrue(result["ok"])
        self.assertEqual(result["selectedDevice"], "/dev/video8")
        self.assertEqual(result["status"]["zoom"], 1.5)
        self.assertEqual(result["presets"][0]["name"], "desk")
        self.assertTrue(result["tracking"]["tracking"])

    def test_actions_are_closed_and_validated(self) -> None:
        ok = BRIDGE.action("/dev/video8", ["pan", "-10"])
        self.assertTrue(ok["ok"])
        bad = BRIDGE.action("/dev/video8", ["preset", "load", "../desk"])
        self.assertFalse(bad["ok"])
        unsupported = BRIDGE.action("", ["preview"])
        self.assertFalse(unsupported["ok"])

    def test_resolution_action_uses_known_format(self) -> None:
        result = BRIDGE.action(
            "/dev/video8",
            ["resolution", "1920x1080@30", "--format", "mjpeg"],
        )
        self.assertTrue(result["ok"])
        bad = BRIDGE.action(
            "/dev/video8",
            ["resolution", "1920x1080@30", "--format", "raw"],
        )
        self.assertFalse(bad["ok"])

    def test_move_action_sets_pan_and_tilt_together(self) -> None:
        result = BRIDGE.action(
            "/dev/video8",
            ["move", "--pan", "12.5", "--tilt", "-7.5"],
        )
        self.assertTrue(result["ok"])
        self.assertEqual(
            result["payload"]["applied"],
            ["move", "--pan", "12.5", "--tilt", "-7.5"],
        )

        invalid = BRIDGE.action(
            "/dev/video8",
            ["move", "--pan", "left", "--tilt", "-7.5"],
        )
        self.assertFalse(invalid["ok"])

    def test_install_uses_the_official_mise_channel(self) -> None:
        with (
            mock.patch.object(
                BRIDGE,
                "locate_linkctl",
                side_effect=[None, str(self.binary)],
            ),
            mock.patch.object(BRIDGE, "locate_mise", return_value="/usr/bin/mise"),
            mock.patch.object(
                BRIDGE,
                "run_process",
                return_value={"ok": True, "exitCode": 0, "payload": None},
            ) as process,
            mock.patch.object(BRIDGE, "version_of", return_value="linkctl 9.9.9"),
        ):
            result = BRIDGE.install()

        self.assertTrue(result["ok"])
        self.assertEqual(
            process.call_args.args[0],
            [
                "/usr/bin/mise",
                "use",
                "-g",
                "github:illegalstudio/linkctl@latest",
            ],
        )


if __name__ == "__main__":
    unittest.main()
