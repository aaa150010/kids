#!/usr/bin/env python3
"""Extract the upstream release's imported audio resources from its PCK."""

from __future__ import annotations

import argparse
import json
import re
import struct
from pathlib import Path


PCK_MAGIC = b"GDPC"
AUDIO_EXTENSIONS = (".ogg", ".mp3", ".wav")


def read_entries(pck: bytes) -> dict[str, tuple[int, int]]:
    if pck[:4] != PCK_MAGIC:
        raise ValueError("not a Godot PCK file")
    file_base = struct.unpack_from("<Q", pck, 24)[0]
    count = struct.unpack_from("<I", pck, 96)[0]
    cursor = 100
    entries: dict[str, tuple[int, int]] = {}
    for _ in range(count):
        path_length = struct.unpack_from("<I", pck, cursor)[0]
        cursor += 4
        path = pck[cursor : cursor + path_length].decode("utf-8", "replace").split("\x00", 1)[0]
        cursor += path_length
        offset, size = struct.unpack_from("<QQ", pck, cursor)
        cursor += 36
        entries[path] = (file_base + offset, size)
    return entries


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pck", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    pck = args.pck.read_bytes()
    entries = read_entries(pck)
    manifest: dict[str, str] = {}
    args.output.mkdir(parents=True, exist_ok=True)
    for name, (offset, size) in entries.items():
        if not name.startswith("assets/audio/") or not name.endswith(".import"):
            continue
        text = pck[offset : offset + size].decode("utf-8", "replace")
        matched = re.search(r'path="res://([^"]+)"', text)
        if not matched:
            continue
        imported_name = matched.group(1)
        imported = entries.get(imported_name)
        if imported is None:
            continue
        source_name = name.removesuffix(".import")
        if not source_name.endswith(AUDIO_EXTENSIONS):
            continue
        relative = Path(source_name).relative_to("assets/audio")
        output = args.output / relative.with_suffix(relative.suffix + ".res")
        output.parent.mkdir(parents=True, exist_ok=True)
        imported_offset, imported_size = imported
        output.write_bytes(pck[imported_offset : imported_offset + imported_size])
        manifest[source_name] = (
            "res://assets/garden/pvz-audio/" + output.relative_to(args.output).as_posix()
        )
    (args.output / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
    )
    print(f"Extracted {len(manifest)} audio resources to {args.output}")


if __name__ == "__main__":
    main()
