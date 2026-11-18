#!/usr/bin/env python3
"""Import PVZ-Godot-Dream source resources into the native Godot project."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import struct
import urllib.parse
import urllib.request
import zlib
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path


UPSTREAM_REPO = "hsk-dream/PVZ-Godot-Dream"
UPSTREAM_COMMIT = "740691cf9b0ad02c7021efa4dae2ab5f86207585"
SOURCE_SUFFIXES = {".gd", ".tscn", ".tres", ".gdshader", ".gdshaderinc"}
BINARY_SUFFIXES = {".res"}
CORE_ROOTS = (
    "scripts",
    "scenes",
    "resources",
    "shaders",
    "shader_material",
    "animation",
    "data",
)


def transparent_png() -> bytes:
    def chunk(kind: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + kind
            + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(b"\0\0\0\0\0"))
        + chunk(b"IEND", b"")
    )


def norm(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", value.lower())


class Importer:
    def __init__(self, root: Path, source: Path) -> None:
        self.root = root
        self.source = source
        self.target = root / "apps/android/pvz"
        self.asset_root = root / "apps/android/assets/garden/runtime"
        self.semantic_assets = root / "apps/android/assets/garden"
        self.frame_map: dict[str, dict] = {}
        self.image_map: dict[str, str] = {}
        self.audio_map: dict[str, str] = {}
        self.uid_map: dict[str, str] = {}
        self.generated_textures: dict[str, str] = {}
        self.asset_hits = {"frame": 0, "local": 0, "placeholder": 0}

    def run(self) -> None:
        if not self.source.exists():
            self.download_source()
        self.load_assets()
        self.prepare_target()
        self.write_placeholders()
        self.generate_frame_textures()
        self.build_uid_map()
        self.import_files()
        self.write_report()

    def download_source(self) -> None:
        tree_url = (
            f"https://api.github.com/repos/{UPSTREAM_REPO}/git/trees/"
            f"{UPSTREAM_COMMIT}?recursive=1"
        )
        with urllib.request.urlopen(tree_url, timeout=120) as response:
            tree = json.load(response)["tree"]
        paths = [
            entry["path"]
            for entry in tree
            if entry["type"] == "blob"
            and Path(entry["path"]).suffix in SOURCE_SUFFIXES | BINARY_SUFFIXES
            and not entry["path"].startswith("addons/")
        ]

        def fetch(path: str) -> None:
            output = self.source / path
            output.parent.mkdir(parents=True, exist_ok=True)
            url = (
                f"https://raw.githubusercontent.com/{UPSTREAM_REPO}/"
                f"{UPSTREAM_COMMIT}/{urllib.parse.quote(path)}"
            )
            with urllib.request.urlopen(url, timeout=120) as response:
                output.write_bytes(response.read())

        with ThreadPoolExecutor(max_workers=24) as executor:
            list(executor.map(fetch, paths))

    def load_assets(self) -> None:
        for path in self.asset_root.rglob("*.json"):
            try:
                data = json.loads(path.read_text())
            except (OSError, json.JSONDecodeError):
                continue
            frames = data.get("frames", {}) if isinstance(data, dict) else {}
            if not isinstance(frames, dict):
                continue
            atlas = path.with_suffix(".webp")
            if not atlas.exists():
                continue
            atlas_res = "res://" + str(atlas.relative_to(self.root / "apps/android"))
            for key, region in frames.items():
                if (
                    isinstance(region, list)
                    and len(region) >= 4
                    and all(isinstance(value, (int, float)) for value in region[:4])
                ):
                    self.frame_map.setdefault(
                        norm(key),
                        {"atlas": atlas_res, "region": region[:4], "key": key},
                    )

        for path in self.semantic_assets.rglob("*"):
            if path.suffix.lower() not in {
                ".png",
                ".webp",
                ".jpg",
                ".jpeg",
                ".svg",
                ".otf",
                ".ttf",
                ".mp3",
                ".ogg",
                ".wav",
            }:
                continue
            resource = "res://" + str(path.relative_to(self.root / "apps/android"))
            if path.suffix.lower() in {".mp3", ".ogg", ".wav"}:
                self.audio_map.setdefault(norm(path.stem), resource)
            else:
                self.image_map.setdefault(norm(path.stem), resource)

        self.audio_map.update(
            {
                "frontday": "res://assets/garden/music/day.mp3",
                "frontnight": "res://assets/garden/music/night.mp3",
                "pool": "res://assets/garden/music/pool.mp3",
                "fog": "res://assets/garden/music/fog.mp3",
                "roof": "res://assets/garden/music/roof.mp3",
                "mini game": "res://assets/garden/music/minigame.mp3",
                "minigame": "res://assets/garden/music/minigame.mp3",
                "choosecard": "res://assets/garden/music/choose.mp3",
                "garden": "res://assets/garden/music/menu.mp3",
                "puzzle": "res://assets/garden/music/puzzle.mp3",
            }
        )
        self.image_map.update(
            {
                "seedpacket": "res://assets/garden/runtime/original/seed-packet.webp",
                "seedpacketlarger": "res://assets/garden/runtime/original/seed-packet.webp",
                "seedpacketsilhouette": "res://assets/garden/runtime/ui/seed-silhouette.webp",
                "seedchooserbackground": "res://assets/garden/runtime/ui/seed-chooser.webp",
                "seedchooserbutton2": "res://assets/garden/runtime/ui/seed-start.webp",
                "seedchooserbutton2glow": "res://assets/garden/runtime/ui/seed-start.webp",
                "seedchooserbuttonglow": "res://assets/garden/runtime/ui/seed-start.webp",
                "seedchooserbuttonglow2": "res://assets/garden/runtime/ui/seed-start.webp",
                "seedbank": "res://assets/garden/runtime/original/seedbank.webp",
                "conveyorbelt": "res://assets/garden/runtime/original/conveyor.webp",
                "conveyorbeltbackdrop": "res://assets/garden/runtime/original/conveyor-back.webp",
            }
        )

    def build_uid_map(self) -> None:
        pattern = re.compile(
            r'\[ext_resource[^\]]*uid="(uid://[^"]+)"[^\]]*path="([^"]+)"'
        )
        owner_pattern = re.compile(
            r'\[(?:gd_scene|gd_resource)[^\]]*uid="(uid://[^"]+)"[^\]]*\]'
        )
        for path in self.source.rglob("*"):
            if path.suffix not in SOURCE_SUFFIXES:
                continue
            text = path.read_text(errors="ignore")
            for match in pattern.finditer(text):
                uid, resource_path = match.groups()
                self.uid_map[uid] = self.rewrite_path(resource_path)
            owner = owner_pattern.search(text)
            if owner:
                relative = path.relative_to(self.source)
                if relative.parts and relative.parts[0] in CORE_ROOTS:
                    self.uid_map[owner.group(1)] = (
                        f"res://pvz/{relative.as_posix()}"
                    )

    def prepare_target(self) -> None:
        if self.target.exists():
            shutil.rmtree(self.target)
        (self.target / "assets/atlas").mkdir(parents=True)

    def write_placeholders(self) -> None:
        (self.target / "assets/image-placeholder.png").write_bytes(transparent_png())
        silence = self.target / "assets/audio-placeholder.wav"
        sample_rate = 8000
        samples = b"\0\0" * (sample_rate // 10)
        header = (
            b"RIFF"
            + struct.pack("<I", 36 + len(samples))
            + b"WAVEfmt "
            + struct.pack("<IHHIIHH", 16, 1, 1, sample_rate, sample_rate * 2, 2, 16)
            + b"data"
            + struct.pack("<I", len(samples))
        )
        silence.write_bytes(header + samples)
        empty_animation = self.target / "animation/empty-animation.tres"
        empty_animation.parent.mkdir(parents=True, exist_ok=True)
        empty_animation.write_text(
            "\n".join(
                [
                    '[gd_resource type="Animation" format=3]',
                    "",
                    "[resource]",
                    'resource_name = "empty"',
                    "length = 0.01",
                    "",
                ]
            )
        )

    def generate_frame_textures(self) -> None:
        atlas_dir = self.target / "assets/atlas"
        for key, entry in self.frame_map.items():
            output = atlas_dir / f"{key}.tres"
            region = entry["region"]
            output.write_text(
                "\n".join(
                    [
                        '[gd_resource type="AtlasTexture" load_steps=2 format=3]',
                        "",
                        f'[ext_resource type="Texture2D" path="{entry["atlas"]}" id="1"]',
                        "",
                        "[resource]",
                        'atlas = ExtResource("1")',
                        "region = Rect2(%s, %s, %s, %s)"
                        % (
                            float(region[0]) * 2,
                            float(region[1]) * 2,
                            float(region[2]) * 2,
                            float(region[3]) * 2,
                        ),
                        "",
                    ]
                )
            )
            self.generated_textures[key] = (
                f"res://pvz/assets/atlas/{key}.tres"
            )

    def import_files(self) -> None:
        for path in self.source.rglob("*"):
            if path.suffix not in SOURCE_SUFFIXES:
                continue
            relative = path.relative_to(self.source)
            if relative.parts[0] not in CORE_ROOTS:
                continue
            output = self.target / relative
            output.parent.mkdir(parents=True, exist_ok=True)
            text = path.read_text(errors="ignore")
            text = self.rewrite_text(text)
            relative_card_bg = relative.as_posix().startswith("resources/card_bg/")
            if relative_card_bg:
                text = "\n".join(
                    [
                        '[gd_resource type="AtlasTexture" load_steps=2 format=3]',
                        "",
                        '[ext_resource type="Texture2D" '
                        'path="res://assets/garden/runtime/original/seed-packet.webp" id="1_norm"]',
                        "",
                        "[resource]",
                        'atlas = ExtResource("1_norm")',
                        "region = Rect2(0, 0, 200, 280)",
                        "",
                    ]
                )
            elif '[gd_resource type="CompressedTexture2D"' in text:
                text = "\n".join(
                    [
                        '[gd_resource type="PlaceholderTexture2D" format=3]',
                        "",
                        "[resource]",
                        "size = Vector2(1, 1)",
                        "",
                    ]
                )
            output.write_text(text)

        for path in self.source.rglob("*"):
            if path.suffix not in BINARY_SUFFIXES:
                continue
            relative = path.relative_to(self.source)
            if relative.parts[0] not in CORE_ROOTS:
                continue
            output = self.target / relative
            output.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, output)

        for name in ("LICENSE", "README.md"):
            source = self.source / name
            if source.exists():
                (self.target / f"UPSTREAM-{name}").write_text(source.read_text())
        local_license = self.root / "content-src/licenses/pvz-godot-dream.txt"
        if local_license.exists():
            shutil.copy2(local_license, self.target / "UPSTREAM-LICENSE.txt")

    def rewrite_text(self, text: str) -> str:
        text = re.sub(
            r'\[ext_resource([^\]]*?)\s+uid="uid://[^"]+"([^\]]*)\]',
            r"[ext_resource\1\2]",
            text,
        )
        text = re.sub(r'\[gd_scene([^\]]*?)\s+uid="uid://[^"]+"([^\]]*)\]',
                      r"[gd_scene\1\2]", text)
        text = re.sub(r'\[gd_resource([^\]]*?)\s+uid="uid://[^"]+"([^\]]*)\]',
                      r"[gd_resource\1\2]", text)
        text = re.sub(
            r'^metadata/_custom_type_script = "uid://[^"]+"\n',
            "",
            text,
            flags=re.MULTILINE,
        )
        text = re.sub(
            r'(preload|load)\(&?"(uid://[^"]+)"\)',
            lambda match: (
                f'{match.group(1)}("{self.uid_map.get(match.group(2), match.group(2))}")'
            ),
            text,
        )
        text = re.sub(
            r'"(res://[^"]+)"',
            lambda match: f'"{self.rewrite_path(match.group(1))}"',
            text,
        )
        return text

    def rewrite_path(self, resource_path: str) -> str:
        if resource_path.startswith("res://.godot/imported/"):
            return "res://pvz/assets/image-placeholder.png"
        if resource_path.startswith("res://assets/"):
            return self.map_asset(resource_path)
        for directory in CORE_ROOTS:
            prefix = f"res://{directory}/"
            if resource_path.startswith(prefix):
                return f"res://pvz/{directory}/{resource_path[len(prefix):]}"
        return resource_path

    def map_asset(self, resource_path: str) -> str:
        basename = Path(resource_path).stem
        key = norm(basename)
        suffix = Path(resource_path).suffix.lower()
        if key in self.generated_textures:
            self.asset_hits["frame"] += 1
            return self.generated_textures[key]
        if suffix in {".mp3", ".ogg", ".wav"}:
            mapped = self.audio_map.get(key)
            if mapped:
                self.asset_hits["local"] += 1
                return mapped
            self.asset_hits["placeholder"] += 1
            return "res://pvz/assets/audio-placeholder.wav"
        if suffix in {".png", ".webp", ".jpg", ".jpeg", ".svg"}:
            mapped = self.image_map.get(key)
            if mapped:
                self.asset_hits["local"] += 1
                return mapped
            self.asset_hits["placeholder"] += 1
            return "res://pvz/assets/image-placeholder.png"
        if suffix in {".otf", ".ttf", ".ttc"}:
            return "res://assets/fonts/NotoSansCJKsc-Content.otf"
        return resource_path

    def write_report(self) -> None:
        report = {
            "upstream": f"https://github.com/{UPSTREAM_REPO}",
            "commit": UPSTREAM_COMMIT,
            "frameTextures": len(self.generated_textures),
            "assetHits": self.asset_hits,
            "semanticImageAssets": len(self.image_map),
            "semanticAudioAssets": len(self.audio_map),
        }
        (self.target / "IMPORT-REPORT.json").write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + "\n"
        )
        print(json.dumps(report, ensure_ascii=False, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=Path("/tmp/pvz-src"))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    Importer(root, args.source).run()


if __name__ == "__main__":
    main()
