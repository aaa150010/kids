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
