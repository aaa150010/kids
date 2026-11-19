#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
android_root="$project_root/apps/android"
godot_bin="${GODOT_BIN:-godot}"
gradle_bin="${GRADLE_BIN:-gradle}"

if ! command -v "$godot_bin" >/dev/null 2>&1; then
  echo "找不到 Godot。请安装 Godot 4.7.2，并通过 GODOT_BIN 指向可执行文件。" >&2
  exit 1
fi

cd "$project_root"
node scripts/native/author-stories.mjs
node scripts/native/export-content.mjs
node scripts/native/signing.mjs

staging="$(mktemp -d "${TMPDIR:-/tmp}/kids-playground-android.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
rsync -a \
  --exclude='.godot/' \
  --exclude='build/' \
  --exclude='android/plugins/updater/build/' \
  --exclude='android/plugins/updater/.gradle/' \
  "$android_root/" "$staging/"

export_templates="${GODOT_EXPORT_TEMPLATES:-$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable}"
android_source="$export_templates/android_source.zip"
if [[ ! -f "$android_source" ]]; then
  echo "找不到 Godot Android 导出模板：$android_source" >&2
  echo "请安装 Godot 4.7.2 导出模板，或设置 GODOT_EXPORT_TEMPLATES。" >&2
  exit 1
fi
rm -rf "$staging/android/build"
mkdir -p "$staging/android/build"
unzip -q "$android_source" -d "$staging/android/build"
python3 - "$staging/android/build/config.gradle" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
text = text.replace('compileSdk         : 36', 'compileSdk         : 34')
text = text.replace('minSdk             : 24', 'minSdk             : 26')
text = text.replace('targetSdk          : 36', 'targetSdk          : 33')
text = text.replace("buildTools         : '36.1.0'", "buildTools         : '34.0.0'")
path.write_text(text)
PY
touch "$staging/android/build/.gdignore"
printf "4.7.2.stable\n" > "$staging/android/.build_version"

NATIVE_PROJECT_DIR="$staging" node scripts/native/prepare-export.mjs

if [[ "${SKIP_PLUGIN_BUILD:-0}" != "1" ]]; then
  if ! command -v "$gradle_bin" >/dev/null 2>&1; then
    echo "找不到 Gradle。请安装 Gradle 8.9+，或设置 GRADLE_BIN。" >&2
    exit 1
  fi
  (
    cd "$staging/android/plugins/updater"
    "$gradle_bin" --no-daemon assembleRelease
  )
  cp "$staging/android/plugins/updater/build/outputs/aar/updater-release.aar" \
    "$staging/android/plugins/UpdateInstaller.aar"
fi

"$godot_bin" --headless --import --path "$staging"
"$godot_bin" --headless --path "$staging" --editor --quit
mkdir -p "$staging/build"
"$godot_bin" --headless --path "$staging" --export-release "Android" "$staging/build/kids-playground.apk"
"$godot_bin" --headless --path "$staging" --script res://tools/pack_content.gd -- "$staging/build/content.pck"

APK_PATH="$staging/build/kids-playground.apk" PCK_PATH="$staging/build/content.pck" \
  node scripts/native/generate-release.mjs
echo "原生安装包已生成：$project_root/build/native-release"
