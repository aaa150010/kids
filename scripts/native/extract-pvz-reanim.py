#!/usr/bin/env python3
"""Build the flat reanim textures required by the two compiled upstream animations."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "apps/android/assets/garden/runtime/actor-motion"
OUTPUT = ROOT / "content-src/assets/reanim"

DIGGER_FRAMES = {
    "Zombie_digger_body.png": "ZOMBIE_DIGGER_BODY",
    "Zombie_digger_dig5.png": "ZOMBIE_DIGGER_DIG5",
    "Zombie_digger_dirt.png": "ZOMBIE_DIGGER_DIRT",
    "Zombie_digger_head.png": "ZOMBIE_DIGGER_HEAD",
    "Zombie_digger_head2.png": "ZOMBIE_DIGGER_HEAD",
    "Zombie_digger_innerarm_hand.png": "ZOMBIE_DIGGER_INNERARM_HAND",
    "Zombie_digger_innerarm_lower.png": "ZOMBIE_DIGGER_INNERARM_LOWER",
    "Zombie_digger_innerarm_upper.png": "ZOMBIE_DIGGER_INNERARM_UPPER",
    "Zombie_digger_innerleg_foot.png": "ZOMBIE_DIGGER_INNERLEG_FOOT",
    "Zombie_digger_innerleg_lower.png": "ZOMBIE_DIGGER_INNERLEG_LOWER",
    "Zombie_digger_innerleg_upper.png": "ZOMBIE_DIGGER_INNERLEG_UPPER",
    "Zombie_digger_jaw.png": "ZOMBIE_DIGGER_JAW",
    "Zombie_digger_outerarm_hand.png": "ZOMBIE_DIGGER_OUTERARM_HAND",
    "Zombie_digger_outerarm_lower.png": "ZOMBIE_DIGGER_OUTERARM_LOWER",
    "Zombie_digger_outerarm_upper.png": "ZOMBIE_DIGGER_OUTERARM_UPPER",
    "Zombie_digger_outerleg_fool.png": "ZOMBIE_DIGGER_OUTERLEG_FOOL",
    "Zombie_digger_outerleg_lower.png": "ZOMBIE_DIGGER_OUTERLEG_LOWER",
    "Zombie_digger_outerleg_upper.png": "ZOMBIE_DIGGER_OUTERLEG_UPPER",
    "Zombie_digger_pickaxe.png": "ZOMBIE_DIGGER_PICKAXE",
    "Zombie_digger_rise2.png": "ZOMBIE_DIGGER_RISE2",
    "Zombie_digger_rise3.png": "ZOMBIE_DIGGER_RISE3",
    "Zombie_digger_rise4.png": "ZOMBIE_DIGGER_RISE4",
    "Zombie_digger_rise5.png": "ZOMBIE_DIGGER_RISE5",
    "Zombie_digger_rise6.png": "ZOMBIE_DIGGER_RISE6",
}


def crop_frames(atlas_name: str, mapping: dict[str, str]) -> None:
    atlas_path = RUNTIME / f"{atlas_name}.webp"
    frames_path = RUNTIME / f"{atlas_name}.json"
    atlas = Image.open(atlas_path).convert("RGBA")
    frames = json.loads(frames_path.read_text())["frames"]
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for filename, frame_name in mapping.items():
        x, y, width, height = frames[frame_name][:4]
        # 花园图集按上游 2× 像素保存，JSON 区域是 1× 逻辑坐标。
        frame = atlas.crop(
            (
                round(x * 2),
                round(y * 2),
                round((x + width) * 2),
                round((y + height) * 2),
            )
        )
        frame.save(OUTPUT / filename)


def main() -> None:
    crop_frames("zombie_digger", DIGGER_FRAMES)
    crop_frames("pumpkin", {"Pumpkin_back.png": "PUMPKIN_BACK"})
    transparent = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
    transparent.save(OUTPUT / "Zombie_digger_head_eye.png")
    print(f"Wrote {len(DIGGER_FRAMES) + 2} reanim textures to {OUTPUT}")


if __name__ == "__main__":
    main()
