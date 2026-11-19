#!/usr/bin/env python3
"""从内容唯一源生成封面与字体；原件保留，导出时按清单排除重复打包。"""
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "build/resource-tools"))
import PIL
import fontTools
from PIL import Image, ImageOps
from fontTools import subset
from fontTools.ttLib import TTFont

SOURCE = ROOT / "content-src"
ASSETS = SOURCE / "assets"
REPORT = SOURCE / "licenses/asset-optimization.json"
FONT = ASSETS / "fonts/NotoSansCJKsc-Regular.otf"
SUBSET = ASSETS / "fonts/NotoSansCJKsc-Content.otf"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, list):
        for item in value:
            yield from strings(item)
    elif isinstance(value, dict):
        for key, item in value.items():
            yield key
            yield from strings(item)


# 收集全部 JSON 字符及 GDScript 全文（包含全部 UI 字面量）；不以常用字表截断。
inputs = sorted(SOURCE.rglob("*.json")) + sorted((ROOT / "apps/android/src").rglob("*.gd"))
inputs = [path for path in inputs if path != REPORT and path.name != "motion_kit.gd"]
characters = set(chr(value) for value in range(32, 127))
for path in inputs:
    text = path.read_text(encoding="utf-8")
    if path.suffix == ".json":
        text = "".join(strings(json.loads(text)))
    characters.update(text)
font = TTFont(FONT, recalcTimestamp=False)
cmap = font.getBestCmap()
requested = {ord(character) for character in characters}
covered = requested.intersection(cmap)
options = subset.Options()
options.recalc_timestamp = False
options.canonical_order = True
subsetter = subset.Subsetter(options=options)
subsetter.populate(unicodes=sorted(covered))
subsetter.subset(font)
font.save(SUBSET)
with TTFont(SUBSET) as generated:
    if not covered.issubset(generated.getBestCmap()):
        raise RuntimeError("字体子集遗漏来源字体已有的内容字符")
entries = [{"source": str(FONT.relative_to(ASSETS)), "output": str(SUBSET.relative_to(ASSETS)),
            "sourceBytes": FONT.stat().st_size, "outputBytes": SUBSET.stat().st_size,
            "sourceSha256": sha(FONT), "outputSha256": sha(SUBSET)}]
config = SOURCE / "data/games.json"
text = config.read_text(encoding="utf-8")
for game in json.loads(text):
    cover = game.get("cover", "")
    if not cover.startswith("res://assets/covers/"):
        continue
    original = ASSETS / cover.removeprefix("res://assets/")
    if original.suffix == ".webp":
        original = original.with_suffix(".png")
    if original.suffix != ".png" or not original.exists():
        continue
    output = original.with_suffix(".webp")
    with Image.open(original) as image:
        icc = image.info.get("icc_profile")
        image = ImageOps.exif_transpose(image)
        image = image.convert("RGBA" if "A" in image.getbands() or "transparency" in image.info else "RGB")
        before = list(image.size)
        image.thumbnail((1100, 1100), Image.Resampling.LANCZOS)
        image.save(output, "WEBP", lossless=True, exact=True, method=6, **({"icc_profile": icc} if icc else {}))
        entries.append({"source": str(original.relative_to(ASSETS)), "output": str(output.relative_to(ASSETS)),
                        "sourceBytes": original.stat().st_size, "outputBytes": output.stat().st_size,
                        "sourceDimensions": before, "outputDimensions": list(image.size),
                        "alpha": image.mode == "RGBA", "sourceSha256": sha(original), "outputSha256": sha(output)})
    text = text.replace(cover, "res://assets/" + str(output.relative_to(ASSETS)))
config.write_text(text, encoding="utf-8")
report = {
    "schemaVersion": 1,
    "tools": {"Pillow": PIL.__version__, "fontTools": fontTools.__version__},
    "method": "WebP 无损编码，最长边 1100px，保留透明通道与 ICC；字体按全部源 JSON 与全部原生 GDScript 字符取并集",
    "originalPolicy": "原件保留在 content-src/assets，清单 excludedAssets 指定仅排除原件导出，不删除原件",
    "dynamicNameFallback": "字体 allow_system_fallback 与中文 SystemFont 回退；设备系统字体缺失的扩展汉字仍受设备字库限制",
    "fontRequestedCodepoints": len(requested), "fontIncludedCodepoints": len(covered),
    "fontMissingFromOriginal": [f"U+{value:04X}" for value in sorted(requested - set(cmap)) if value >= 32],
    "fontInputs": [str(path.relative_to(ROOT)) for path in inputs],
    "entries": entries, "excludedAssets": [entry["source"] for entry in entries],
    "beforeBytes": sum(entry["sourceBytes"] for entry in entries),
    "afterBytes": sum(entry["outputBytes"] for entry in entries),
}
outputs = {entry["output"] for entry in entries}
excluded = set(report["excludedAssets"])
files = {str(path.relative_to(ASSETS)): path.stat().st_size for path in ASSETS.rglob("*") if path.is_file()}
report["allAssetsBeforeBytes"] = sum(size for path, size in files.items() if path not in outputs)
report["allAssetsAfterBytes"] = sum(size for path, size in files.items() if path not in excluded)
report["savedBytes"] = report["beforeBytes"] - report["afterBytes"]
REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({key: report[key] for key in ["beforeBytes", "afterBytes", "fontRequestedCodepoints", "fontIncludedCodepoints"]}, ensure_ascii=False))
print("已保留来源原件，写入资源排除清单；随后运行 node scripts/native/export-content.mjs 同步安卓生成物。")
