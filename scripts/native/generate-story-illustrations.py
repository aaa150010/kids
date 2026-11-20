#!/usr/bin/env python3
import colorsys
import hashlib
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
STORIES = ROOT / "content-src/data/stories.json"
LAYOUT = ROOT / "content-src/stories/story-layout.json"
SPRITES = ROOT / "content-src/assets/story_sprites"
OUTPUT = ROOT / "content-src/assets/stories"
REPORT = ROOT / "content-src/licenses/story-illustrations.json"
MANIFEST = ROOT / "content-src/data/story-illustrations.json"
REMOTE_BASE = "https://lynote.xyz/play-app/story-images/"
SIZE = (768, 576)
GRID = 4

PALETTES = {
    "idiom": ((244, 234, 203), (139, 103, 63), (92, 118, 68)),
    "myth": ((223, 226, 249), (109, 91, 155), (64, 116, 118)),
    "folk": ((245, 227, 211), (153, 88, 68), (107, 132, 73)),
    "fable": ((226, 242, 221), (83, 124, 82), (190, 139, 67)),
    "history": ((235, 224, 205), (122, 82, 55), (83, 108, 120)),
    "fairy": ((242, 224, 244), (150, 89, 147), (71, 119, 160)),
}

KEYWORDS = [
    (("仙女", "娘娘", "女神", "女娲"), 1, 0),
    (("天神", "天帝", "神人"), 1, 1),
    (("公主",), 1, 2),
    (("王子",), 1, 3),
    (("仙女教母", "仙子", "魔法"), 1, 4),
    (("姑娘", "女子", "织女", "新娘"), 1, 5),
    (("青年", "小伙", "男子", "牛郎"), 1, 6),
    (("将军",), 1, 7),
    (("国王", "皇帝"), 1, 8),
    (("卫士", "守卫", "士兵"), 1, 9),
    (("龙",), 1, 10),
    (("凤凰",), 1, 11),
    (("仙鹤", "鹤"), 1, 12),
    (("鱼", "鲤鱼"), 1, 13),
    (("鸟", "燕子", "喜鹊", "鸽子"), 1, 14),
    (("马",), 1, 15),
    (("农夫", "种地", "庄稼", "锄头"), 0, 0),
    (("提兔", "抱兔", "捡兔", "兔子", "野兔"), 0, 1),
    (("树桩", "守株", "等待"), 0, 2),
    (("奶奶", "老妇", "母亲"), 0, 3),
    (("男孩", "童子", "儿子"), 0, 4),
    (("女孩", "女儿", "小姑娘"), 0, 5),
    (("皇帝", "帝王"), 0, 6),
    (("书生", "学者"), 0, 7),
    (("战士", "勇士", "武将"), 0, 8),
    (("老人", "老翁", "长者"), 0, 9),
    (("兔",), 0, 10),
    (("虎",), 0, 12),
    (("狐",), 0, 13),
    (("蛇",), 0, 14),
    (("龟", "乌"), 0, 15),
]

DEFAULT_SUBJECT = {
    "idiom": (0, 0),
    "myth": (1, 0),
    "folk": (1, 5),
    "fable": (0, 12),
    "history": (1, 7),
    "fairy": (1, 2),
}


def stable_int(text):
    return int(hashlib.sha256(text.encode("utf-8")).hexdigest()[:12], 16)


def mix(a, b, amount):
    return tuple(round(a[index] * (1.0 - amount) + b[index] * amount) for index in range(3))


def shade(color, amount):
    h, l, s = colorsys.rgb_to_hls(*(channel / 255.0 for channel in color))
    return tuple(round(channel * 255) for channel in colorsys.hls_to_rgb(h, max(0, min(1, l + amount)), s))


def load_sprite_sheet(path):
    image = Image.open(path).convert("RGBA")
    cell_w = image.width / GRID
    cell_h = image.height / GRID
    sprites = []
    for row in range(GRID):
        for col in range(GRID):
            box = (
                round(col * cell_w),
                round(row * cell_h),
                round((col + 1) * cell_w),
                round((row + 1) * cell_h),
            )
            cell = image.crop(box)
            bbox = cell.getchannel("A").getbbox()
            sprites.append(cell.crop(bbox) if bbox else cell)
    return sprites


def scene_text(story, illustration, scene_index):
    paragraphs = story.get("paragraphs", [])
    paragraph_id = str(illustration.get("paragraphId", ""))
    for paragraph in paragraphs:
        if str(paragraph.get("id", "")) == paragraph_id:
            return " ".join([
                str(story.get("title", "")),
                str(illustration.get("alt", "")),
                str(paragraph.get("text", "")),
            ])
    if paragraphs:
        paragraph = paragraphs[min(scene_index, len(paragraphs) - 1)]
        return str(paragraph.get("text", ""))
    return str(story.get("searchText", story.get("title", "")))


def subject_indexes(text, category):
    picked = []
    for words, sheet, index in KEYWORDS:
        if any(word in text for word in words) and (sheet, index) not in picked:
            picked.append((sheet, index))
        if len(picked) >= 2:
            break
    if not picked:
        picked.append(DEFAULT_SUBJECT.get(category, (0, 9)))
    return picked


def draw_cloud(draw, x, y, scale, color):
    for dx, dy, w, h in ((-55, 10, 75, 42), (-18, -8, 86, 55), (35, 8, 72, 42)):
        draw.ellipse((x + dx * scale, y + dy * scale, x + (dx + w) * scale, y + (dy + h) * scale), fill=color)


def background(story, text, category, scene_index):
    seed = stable_int(f"{story.get('id')}:{scene_index}")
    palette = PALETTES.get(category, PALETTES["folk"])
    top, middle, ground_tint = palette
    canvas = Image.new("RGB", SIZE, top)
    draw = ImageDraw.Draw(canvas)
    for y in range(SIZE[1]):
        ratio = y / SIZE[1]
        color = mix(top, (255, 249, 237), max(0.0, 0.55 - ratio * 0.7))
        draw.line((0, y, SIZE[0], y), fill=color)

    sun_x = 620 if seed % 2 == 0 else 130
    draw.ellipse((sun_x - 38, 66, sun_x + 38, 142), fill=(247, 205, 95))
    draw_cloud(draw, 180 + seed % 90, 95, 0.7, (255, 254, 246))
    draw_cloud(draw, 540 - seed % 60, 136, 0.56, (255, 254, 246))

    if any(word in text for word in ("夜", "月", "星")):
        draw.rectangle((0, 0, SIZE[0], 420), fill=(54, 66, 104))
        draw.ellipse((580, 54, 670, 144), fill=(248, 226, 156))
        for index in range(28):
            x = (seed + index * 149) % 740 + 14
            y = (seed // 7 + index * 83) % 300 + 20
            draw.ellipse((x, y, x + 4, y + 4), fill=(255, 244, 198))
        ground_tint = mix(ground_tint, (45, 65, 54), 0.45)

    mountain_color = mix(middle, (255, 249, 237), 0.35)
    draw.polygon(((0, 345), (150, 176), (310, 350)), fill=mountain_color)
    draw.polygon(((180, 350), (385, 130), (590, 350)), fill=mix(mountain_color, middle, 0.25))
    draw.polygon(((455, 350), (650, 190), (790, 350)), fill=mountain_color)

    draw.rectangle((0, 340, SIZE[0], SIZE[1]), fill=ground_tint)
    draw.ellipse((-140, 305, 700, 620), fill=shade(ground_tint, 0.08))
    draw.ellipse((330, 285, 940, 610), fill=shade(ground_tint, -0.04))

    if any(word in text for word in ("田", "庄稼", "农夫", "种地", "树桩", "守株")):
        perspective_y = 352
        for index in range(7):
            x = 130 + index * 82
            draw.line((x, perspective_y, x - 85, 540), fill=(112, 87, 54), width=9)
            draw.line((x + 7, perspective_y, 760, 530), fill=(139, 106, 62), width=4)
        for row in range(4):
            for col in range(10):
                x = 54 + col * 72 + (row % 2) * 18
                y = 374 + row * 44
                draw.line((x, y + 22, x, y), fill=(63, 112, 55), width=3)
                draw.ellipse((x - 8, y + 3, x - 1, y + 13), fill=(98, 156, 73))
                draw.ellipse((x + 1, y + 6, x + 9, y + 15), fill=(79, 138, 62))

    if any(word in text for word in ("森林", "树林", "大树", "老树", "虎", "狐", "猴")):
        for index in range(7):
            x = 24 + index * 120 + (seed + index * 17) % 35
            height = 130 + (seed >> index) % 85
            trunk = (101, 73, 48)
            outline = (70, 55, 40)
            draw.rectangle((x - 9, 320 - height, x + 9, 375), fill=trunk, outline=outline, width=3)
            draw.ellipse((x - 65, 320 - height - 35, x + 65, 320 - height + 70), fill=(61, 118, 65), outline=outline, width=3)
            draw.ellipse((x - 48, 285 - height, x + 62, 350 - height), fill=(82, 145, 72), outline=outline, width=3)

    if any(word in text for word in ("河", "江", "海", "湖", "溪", "池塘", "水面", "洪水", "渡河", "岸边", "龙宫")):
        water = (98, 179, 196)
        draw.polygon(((0, 390), (768, 348), (768, 576), (0, 576)), fill=water)
        for index in range(14):
            x = 20 + index * 58
            y = 410 + (index % 4) * 38
            draw.arc((x, y, x + 90, y + 30), 190, 350, fill=(224, 247, 244), width=3)

    if any(word in text for word in ("宫", "殿", "国王", "皇帝", "王子", "公主", "城堡")):
        wall = (225, 203, 168)
        roof = (120, 69, 57)
        draw.rectangle((420, 225, 720, 392), fill=wall, outline=(91, 67, 50), width=3)
        draw.polygon(((385, 228), (570, 120), (755, 228)), fill=roof, outline=(91, 67, 50))
        for x in (455, 555, 655):
            draw.rectangle((x, 232, x + 24, 392), fill=(166, 106, 74))
        draw.rectangle((542, 300, 598, 392), fill=(113, 78, 56))

    if any(word in text for word in ("村", "家", "屋", "农舍")):
        draw.rectangle((520, 270, 690, 390), fill=(235, 215, 171), outline=(91, 67, 50), width=3)
        draw.polygon(((490, 278), (605, 190), (720, 278)), fill=(129, 82, 58), outline=(91, 67, 50))
        draw.rectangle((585, 318, 630, 390), fill=(121, 82, 55), outline=(91, 67, 50), width=2)

    for index in range(34):
        x = (seed + index * 97) % 760
        y = 430 + (seed // 5 + index * 53) % 130
        color = (242, 186, 99) if index % 3 == 0 else (247, 222, 129) if index % 3 == 1 else (244, 247, 222)
        draw.line((x, y, x, y - 12), fill=(70, 112, 55), width=2)
        draw.ellipse((x - 5, y - 16, x + 5, y - 6), fill=color)
    return canvas


def place_subject(canvas, sprite, x, ground_y, target_height, flip=False):
    scale = target_height / sprite.height
    resized = sprite.resize((max(1, round(sprite.width * scale)), target_height), Image.Resampling.LANCZOS)
    if flip:
        resized = resized.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    canvas.alpha_composite(resized, (round(x - resized.width / 2), round(ground_y - resized.height)))


def build_image(story, illustration, scene_index, sheets):
    category = str(story.get("category", "folk"))
    text = scene_text(story, illustration, scene_index)
    image = background(story, text, category, scene_index).convert("RGBA")
    draw = ImageDraw.Draw(image, "RGBA")
    picked = subject_indexes(text, category)
    positions = [(330, 508)] if len(picked) == 1 else [(270, 510), (535, 505)]
    for order, (sheet, index) in enumerate(picked[:2]):
        sprite = sheets[sheet][index]
        height = 285 if len(picked) == 1 else 235 if order == 0 else 220
        place_subject(image, sprite, positions[order][0], positions[order][1], height, order == 1)
    if scene_index >= 1:
        for index in range(9):
            x = 640 - index * 36
            y = 190 + (index % 3) * 28
            draw.line((x, y, x + 14, y + 7), fill=(221, 161, 56, 190), width=4)
    image = image.filter(ImageFilter.SMOOTH)
    return image.convert("RGB")


def illustration_specs(story, layout):
    entry = layout.get(str(story.get("id", "")), {})
    illustrations = entry.get("illustrations", [])
    if illustrations:
        return illustrations[:3]
    paragraphs = story.get("paragraphs", [])
    indexes = [0, max(0, len(paragraphs) // 2), max(0, len(paragraphs) - 1)]
    return [
        {"id": f"scene-{index + 1}", "paragraphId": str(paragraphs[idx].get("id", idx)), "side": "right" if index % 2 == 0 else "left", "alt": str(paragraphs[idx].get("text", ""))}
        for index, idx in enumerate(indexes)
    ]


def main():
    if not STORIES.exists():
        raise SystemExit(f"missing stories: {STORIES}")
    stories = json.loads(STORIES.read_text(encoding="utf-8"))
    layout = json.loads(LAYOUT.read_text(encoding="utf-8")) if LAYOUT.exists() else {}
    sheets = [
        load_sprite_sheet(SPRITES / "people_animals.png"),
        load_sprite_sheet(SPRITES / "myth_fairy.png"),
    ]
    OUTPUT.mkdir(parents=True, exist_ok=True)
    generated = []
    manifest = {}
    total_bytes = 0
    for story in stories:
        specs = illustration_specs(story, layout)
        if not 2 <= len(specs) <= 3:
            raise SystemExit(f"story needs two or three scenes: {story.get('title')}")
        story_dir = OUTPUT / str(story["id"])
        story_dir.mkdir(parents=True, exist_ok=True)
        expected = set()
        for index, illustration in enumerate(specs):
            filename = f"{index + 1:02d}.webp"
            expected.add(filename)
            path = story_dir / filename
            image = build_image(story, illustration, index, sheets)
            image.save(path, "WEBP", quality=82, method=5)
            data = path.read_bytes()
            digest = hashlib.sha256(data).hexdigest()
            total_bytes += len(data)
            generated.append({
                "storyId": str(story["id"]),
                "title": str(story.get("title", "")),
                "file": str(path.relative_to(ROOT)),
                "alt": str(illustration.get("alt", "")),
            })
            manifest[f"{story['id']}/{filename}"] = {
                "sha256": digest,
                "size": len(data),
            }
        for old in story_dir.glob("*.webp"):
            if old.name not in expected:
                old.unlink()
    report = {
        "createdAt": "2026-11-20",
        "project": "童心游乐场",
        "style": "清楚线条二维儿童绘本；原创角色素材表与程序化场景组合",
        "count": len(generated),
        "stories": len(stories),
        "totalBytes": total_bytes,
        "assets": generated,
    }
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    MANIFEST.write_text(json.dumps({
        "schema": 1,
        "version": int(hashlib.sha256(json.dumps(manifest, sort_keys=True).encode("utf-8")).hexdigest()[:8], 16),
        "baseUrl": REMOTE_BASE,
        "assets": manifest,
    }, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"已生成 {len(generated)} 张故事插画，覆盖 {len(stories)} 篇；总大小 {total_bytes / 1024 / 1024:.1f} MB")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"故事插画生成失败：{error}", file=sys.stderr)
        raise
