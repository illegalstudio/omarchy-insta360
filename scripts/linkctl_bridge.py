#!/usr/bin/env python3
"""Bounded JSON bridge between the Omarchy QML plugin and linkctl."""

from __future__ import annotations

import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from typing import Any


MAX_OUTPUT = 512 * 1024
PRESET_NAME = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
NUMBER = re.compile(r"^-?(?:\d+(?:\.\d*)?|\.\d+)$")
RESOLUTION = re.compile(r"^[1-9]\d*x[1-9]\d*(?:@(?:\d+(?:\.\d*)?|\.\d+))?$")


def compact(text: str, limit: int = 600) -> str:
    value = " ".join((text or "").split())
    return value if len(value) <= limit else value[: limit - 3] + "..."


def emit(payload: dict[str, Any]) -> int:
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    return 0 if payload.get("ok") is not False else 1


def executable(path: str | Path | None) -> str | None:
    if not path:
        return None
    candidate = Path(path).expanduser()
    if candidate.is_file() and os.access(candidate, os.X_OK):
        # Keep the invoked path intact. A mise shim is commonly a symlink to
        # the mise executable and dispatches from its argv[0] name. Resolving
        # that symlink would turn a valid linkctl shim into a direct mise call.
        return str(candidate.absolute())
    return None


def locate_mise() -> str | None:
    override = executable(os.environ.get("OMARCHY_INSTA360_MISE"))
    return override or shutil.which("mise")


def locate_linkctl() -> str | None:
    override = executable(os.environ.get("OMARCHY_INSTA360_LINKCTL"))
    if override:
        return override

    found = shutil.which("linkctl")
    if found:
        return executable(found)

    mise = locate_mise()
    if mise:
        try:
            result = subprocess.run(
                [mise, "which", "linkctl"],
                check=False,
                capture_output=True,
                text=True,
                timeout=8,
            )
            if result.returncode == 0:
                managed = executable(result.stdout.strip())
                if managed:
                    return managed
        except (OSError, subprocess.TimeoutExpired):
            pass

    data_home = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    install_root = data_home / "mise/installs/github-illegalstudio-linkctl"
    candidates = [install_root / "latest/linkctl"]
    if install_root.is_dir():
        candidates.extend(sorted(install_root.glob("*/linkctl"), reverse=True))
    for candidate in candidates:
        managed = executable(candidate)
        if managed:
            return managed
    return None


def run_process(argv: list[str], timeout: int = 12) -> dict[str, Any]:
    try:
        result = subprocess.run(
            argv,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return {"ok": False, "exitCode": None, "error": "Command timed out"}
    except OSError as error:
        return {"ok": False, "exitCode": None, "error": compact(str(error))}

    stdout = result.stdout[:MAX_OUTPUT]
    stderr = result.stderr[:MAX_OUTPUT]
    source = stdout.strip() if result.returncode == 0 else (stderr.strip() or stdout.strip())
    payload: Any = None
    if source:
        try:
            payload = json.loads(source)
        except json.JSONDecodeError:
            payload = None

    response: dict[str, Any] = {
        "ok": result.returncode == 0,
        "exitCode": result.returncode,
        "payload": payload,
    }
    if result.returncode != 0:
        message = ""
        if isinstance(payload, dict):
            message = str(payload.get("message") or payload.get("error") or "")
        response["error"] = compact(message or stderr or stdout or "linkctl failed")
    return response


def linkctl_command(binary: str, tokens: list[str], device: str = "") -> dict[str, Any]:
    argv = [binary, "--json"]
    if device:
        argv.extend(["--device", device])
    argv.extend(tokens)
    return run_process(argv)


def version_of(binary: str) -> str:
    result = run_process([binary, "--version"], timeout=5)
    payload = result.get("payload")
    if isinstance(payload, str):
        return payload
    try:
        raw = subprocess.run(
            [binary, "--version"], check=False, capture_output=True,
            text=True, timeout=5
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return compact(raw.stdout or raw.stderr, 120)


def probe() -> dict[str, Any]:
    binary = locate_linkctl()
    return {
        "ok": True,
        "installed": binary is not None,
        "path": binary or "",
        "version": version_of(binary) if binary else "",
    }


def pick_device(devices: list[dict[str, Any]], requested: str) -> str:
    paths = [str(item.get("device", "")) for item in devices]
    if requested and requested in paths:
        return requested
    return paths[0] if paths else ""


def snapshot(requested_device: str) -> dict[str, Any]:
    binary = locate_linkctl()
    if not binary:
        return {
            "ok": True,
            "installed": False,
            "path": "",
            "version": "",
            "cameraFound": False,
            "devices": [],
        }

    device_result = linkctl_command(binary, ["devices"])
    devices_payload = device_result.get("payload")
    devices = devices_payload if isinstance(devices_payload, list) else []
    if not device_result["ok"]:
        return {
            "ok": False,
            "installed": True,
            "path": binary,
            "version": version_of(binary),
            "cameraFound": False,
            "devices": [],
            "error": device_result.get("error", "Could not list cameras"),
            "exitCode": device_result.get("exitCode"),
        }

    selected = pick_device(devices, requested_device)
    base: dict[str, Any] = {
        "ok": True,
        "installed": True,
        "path": binary,
        "version": version_of(binary),
        "cameraFound": bool(selected),
        "devices": devices,
        "selectedDevice": selected,
        "status": {},
        "info": {},
        "formats": [],
        "resolution": {},
        "presets": [],
        "tracking": {},
        "issues": [],
    }
    if not selected:
        return base

    requests = {
        "status": ["status"],
        "info": ["info", "--controls"],
        "formats": ["formats"],
        "resolution": ["resolution"],
        "presets": ["preset", "list"],
        "tracking": ["tracking", "status"],
    }
    for key, tokens in requests.items():
        result = linkctl_command(binary, tokens, selected)
        if result["ok"]:
            base[key] = result.get("payload")
        else:
            base["issues"].append({
                "source": key,
                "exitCode": result.get("exitCode"),
                "message": result.get("error", "linkctl failed"),
            })

    base["formats"] = base["formats"] if isinstance(base["formats"], list) else []
    base["presets"] = base["presets"] if isinstance(base["presets"], list) else []
    return base


def finite_number(value: str, minimum: float, maximum: float) -> str | None:
    if not NUMBER.fullmatch(value):
        return None
    number = float(value)
    if not math.isfinite(number) or number < minimum or number > maximum:
        return None
    return value


def validate_action(tokens: list[str]) -> tuple[list[str] | None, str]:
    if not tokens:
        return None, "Missing camera action"
    command, args = tokens[0], tokens[1:]

    if command == "center" and not args:
        return [command], ""
    if command in {"left", "right", "up", "down"} and len(args) == 1:
        value = finite_number(args[0], 0.1, 360.0)
        return ([command, value], "") if value else (None, "Invalid movement step")
    if command in {"pan", "tilt"} and len(args) == 1:
        value = finite_number(args[0], -360.0, 360.0)
        return ([command, value], "") if value else (None, "Invalid angle")
    if (
        command == "move"
        and len(args) == 4
        and args[0] == "--pan"
        and args[2] == "--tilt"
    ):
        pan = finite_number(args[1], -360.0, 360.0)
        tilt = finite_number(args[3], -360.0, 360.0)
        if pan and tilt:
            return [command, "--pan", pan, "--tilt", tilt], ""
        return None, "Invalid camera position"
    if command == "zoom" and len(args) == 1:
        value = finite_number(args[0], 0.1, 20.0)
        return ([command, value], "") if value else (None, "Invalid zoom")
    if command == "focus" and len(args) == 1:
        if args[0] == "auto":
            return [command, "auto"], ""
        value = finite_number(args[0], 0.0, 65535.0)
        return ([command, value], "") if value else (None, "Invalid focus")
    if command == "wb" and len(args) == 1:
        if args[0] == "auto":
            return [command, "auto"], ""
        value = finite_number(args[0], 1000.0, 20000.0)
        return ([command, value], "") if value else (None, "Invalid white balance")
    if command in {"brightness", "contrast", "saturation", "sharpness", "hue"} and len(args) == 1:
        value = finite_number(args[0], -65535.0, 65535.0)
        return ([command, value], "") if value else (None, "Invalid image control")
    if command == "tracking" and len(args) == 1 and args[0] in {"on", "off", "toggle"}:
        return [command, args[0]], ""
    if command == "preset" and len(args) == 2 and args[0] in {"save", "load", "delete"}:
        if PRESET_NAME.fullmatch(args[1]):
            return [command, args[0], args[1]], ""
        return None, "Preset names may contain letters, digits, hyphens, and underscores"
    if command == "resolution" and len(args) == 3 and args[1] == "--format":
        if not RESOLUTION.fullmatch(args[0]):
            return None, "Invalid resolution"
        if args[2] not in {"mjpeg", "h264"}:
            return None, "Invalid pixel format"
        return [command, args[0], "--format", args[2]], ""
    return None, "Unsupported camera action"


def action(device: str, tokens: list[str]) -> dict[str, Any]:
    binary = locate_linkctl()
    if not binary:
        return {"ok": False, "error": "linkctl is not installed", "exitCode": 127}
    validated, error = validate_action(tokens)
    if not validated:
        return {"ok": False, "error": error, "exitCode": 2}
    result = linkctl_command(binary, validated, device)
    result["command"] = validated[0]
    return result


def parse_device(args: list[str]) -> tuple[str, list[str]]:
    if len(args) >= 2 and args[0] == "--device":
        return args[1], args[2:]
    return "", args


def main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[1] in {"-h", "--help", "help"}:
        return emit({
            "ok": True,
            "usage": "linkctl_bridge.py probe|snapshot|action",
        })

    command = argv[1]
    args = argv[2:]
    if command == "probe" and not args:
        return emit(probe())
    if command == "snapshot":
        device, rest = parse_device(args)
        if rest:
            return emit({"ok": False, "error": "Unexpected snapshot arguments"})
        return emit(snapshot(device))
    if command == "action":
        device, rest = parse_device(args)
        if rest and rest[0] == "--":
            rest = rest[1:]
        return emit(action(device, rest))
    return emit({"ok": False, "error": "Unknown bridge command"})


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv))
    except Exception as error:
        raise SystemExit(emit({"ok": False, "error": compact(str(error))}))
