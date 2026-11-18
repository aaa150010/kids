#!/usr/bin/env python3
"""Build the upstream SoundManager option-to-audio map from the extracted PCK resources."""

from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
UPSTREAM = Path("/tmp/pvz-src/scripts/autoload/sound_manager.gd")
MANIFEST = ROOT / "content-src/assets/garden/pvz-audio/manifest.json"
OUTPUT = ROOT / "apps/android/pvz/data/kids_audio_map.json"


def block(text: str, name: str) -> str:
    match = re.search(rf"const {name} := \{{", text)
    if not match:
        return ""
    start = match.end() - 1
    depth = 0
    for index in range(start, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1 : index]
    return ""


def entries(chunk: str, key_pattern: str) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    pattern = re.compile(
        rf"{key_pattern}\s*:\s*(.*?)(?=\n\s*(?:{key_pattern})|\Z)",
        re.DOTALL,
    )
    for matched in pattern.finditer(chunk):
        key = matched.group(1)
        paths = re.findall(r'preload\("(res://assets/audio/[^"]+)"\)', matched.group(2))
        if paths:
            result[key] = paths
    return result


def main() -> None:
    source = UPSTREAM.read_text()
    manifest = json.loads(MANIFEST.read_text())
    output: dict[str, dict[str, list[str]]] = {}
    groups = {
        "character": ("SFXCharacterMap", r'&"([^"]+)"'),
        "dave": ("SFXCarzyDaveMap", r'&"([^"]+)"'),
        "other": ("SFXOtherMap", r'&"([^"]+)"'),
    }
    for group, (name, key_pattern) in groups.items():
        chunk = block(source, name)
        parsed: dict[str, list[str]] = {}
        pattern = re.compile(
            rf"{key_pattern}\s*:\s*(.*?)(?=\n\s*{key_pattern}|\Z)",
            re.DOTALL,
        )
        for matched in pattern.finditer(chunk):
            key = matched.group(1)
            paths = re.findall(r'preload\("(res://assets/audio/[^"]+)"\)', matched.group(2))
            resources = [
                manifest[path.removeprefix("res://")]
                for path in paths
                if path.removeprefix("res://") in manifest
            ]
            if resources:
                parsed[key] = resources
        output[group] = parsed
    for group, enum_name in [("be_attack", "TypeBeAttackSFX"), ("bullet", "TypeBulletSFX")]:
        chunk = block(source, "SFXBeAttackMap" if group == "be_attack" else "SFXBulletMap")
        parsed: dict[str, list[str]] = {}
        pattern = re.compile(
            rf"{enum_name}\.(\w+)\s*:\s*(.*?)(?=\n\s*{enum_name}\.|\Z)",
            re.DOTALL,
        )
        for matched in pattern.finditer(chunk):
            paths = re.findall(r'preload\("(res://assets/audio/[^"]+)"\)', matched.group(2))
            resources = [
                manifest[path.removeprefix("res://")]
                for path in paths
                if path.removeprefix("res://") in manifest
            ]
            if resources:
                parsed[matched.group(1)] = resources
        output[group] = parsed
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n")
    print(f"Wrote {sum(len(v) for v in output.values())} audio option groups to {OUTPUT}")


if __name__ == "__main__":
    main()
