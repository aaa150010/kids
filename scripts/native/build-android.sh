#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
android_root="$project_root/apps/android"
user_home="$HOME"

godot_bin="${GODOT_BIN:-$user_home/Library/Caches/KidsPlayground/tools/Godot.app/Contents/MacOS/Godot}"
if [[ ! -x "$godot_bin" ]] && command -v godot >/dev/null 2>&1; then
  godot_bin="$(command -v godot)"
fi

gradle_bin="${GRADLE_BIN:-}"
if [[ -z "$gradle_bin" ]]; then
  if command -v gradle >/dev/null 2>&1; then
    gradle_bin="$(command -v gradle)"
  else
    gradle_bin="$(find "$user_home/Library/Caches/KidsPlayground/gradle/wrapper/dists" \
      -path '*/bin/gradle' -type f -print 2>/dev/null | sort -V | tail -1)"
  fi
fi

java_home="${JAVA_HOME:-}"
if [[ -z "$java_home" || ! -x "$java_home/bin/java" ]]; then
  for candidate in \
    "/Applications/HBuilderX.app/Contents/HBuilderX/plugins/amazon-corretto" \
    "/Applications/Android Studio.app/Contents/jbr/Contents/Home"; do
    if [[ -x "$candidate/bin/java" ]] && "$candidate/bin/java" -version 2>&1 | rg -q 'version "17\.'; then
      java_home="$candidate"
      break
    fi
  done
fi

android_sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$user_home/Library/Caches/KidsPlayground/android-sdk}}"
gradle_user_home="${KIDS_PLAYGROUND_GRADLE_USER_HOME:-$project_root/build/gradle-user-home}"

if ! command -v "$godot_bin" >/dev/null 2>&1; then
  echo "找不到 Godot。请安装 Godot 4.7.2，并通过 GODOT_BIN 指向可执行文件。" >&2
  exit 1
fi
if [[ -z "$gradle_bin" || ! -x "$gradle_bin" ]]; then
  echo "找不到 Gradle 8.9+。请设置 GRADLE_BIN，或先运行原生构建工具准备脚本。" >&2
  exit 1
fi
if [[ -z "$java_home" || ! -x "$java_home/bin/java" ]]; then
  echo "找不到 JDK 17。请设置 JAVA_HOME；Android Gradle Plugin 8.7.3 不使用 Java 21+。" >&2
  exit 1
fi
if [[ ! -x "$android_sdk/platform-tools/adb" || \
      ! -x "$android_sdk/build-tools/34.0.0/apksigner" || \
      ! -f "$android_sdk/platforms/android-34/android.jar" ]]; then
  echo "Android SDK 不完整：需要 platform-tools 与 build-tools 34.0.0。" >&2
  echo "设置 ANDROID_HOME，或运行 scripts/native/setup-android-build-tools.sh。" >&2
  exit 1
fi
export_templates="${GODOT_EXPORT_TEMPLATES:-$user_home/Library/Application Support/Godot/export_templates/4.7.2.stable}"
android_source="$export_templates/android_source.zip"
if [[ ! -f "$android_source" ]]; then
  echo "找不到 Godot Android 导出模板：$android_source" >&2
  echo "请安装 Godot 4.7.2 导出模板，或设置 GODOT_EXPORT_TEMPLATES。" >&2
  exit 1
fi
if [[ ! -f "$user_home/Library/Application Support/KidsPlayground/keys/release.env" ]]; then
  echo "缺少发布签名材料；先运行 node scripts/native/signing.mjs。" >&2
  exit 1
fi

export JAVA_HOME="$java_home"
export ANDROID_HOME="$android_sdk"
export ANDROID_SDK_ROOT="$android_sdk"
export GRADLE_USER_HOME="$gradle_user_home"
export PATH="$JAVA_HOME/bin:$android_sdk/platform-tools:$android_sdk/build-tools/34.0.0:$PATH"

echo "工具链检查通过："
echo "  Godot=$godot_bin"
echo "  Gradle=$gradle_bin"
echo "  JAVA_HOME=$JAVA_HOME"
echo "  ANDROID_HOME=$ANDROID_HOME"
echo "  GRADLE_USER_HOME=$GRADLE_USER_HOME"
echo "  ExportTemplates=$export_templates"
if [[ "${CHECK_ONLY:-0}" == "1" ]]; then
  exit 0
fi

cd "$project_root"
node scripts/native/audit-stories.mjs
node scripts/native/generate-story-layout.mjs
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
  (
    cd "$staging/android/plugins/updater"
    plugin_gradle_args=(--no-daemon assembleRelease)
    if [[ -d "$GRADLE_USER_HOME/caches/modules-2" ]]; then
      plugin_gradle_args=(--offline "${plugin_gradle_args[@]}")
    fi
    GODOT_LIB_AAR="$staging/android/build/libs/release/godot-lib.template_release.aar" \
      "$gradle_bin" "${plugin_gradle_args[@]}"
  )
  cp "$staging/android/plugins/updater/build/outputs/aar/updater-release.aar" \
    "$staging/android/plugins/UpdateInstaller.aar"
fi

godot_home="$project_root/build/godot-build-home"
rm -rf "$godot_home"
godot_settings_dir="$godot_home/Library/Application Support/Godot"
mkdir -p "$godot_settings_dir/export_templates"
ln -s "$export_templates" "$godot_settings_dir/export_templates/4.7.2.stable"

godot_run() {
  HOME="$godot_home" GODOT_EXPORT_TEMPLATES="$export_templates" "$godot_bin" "$@"
}

godot_run --headless --import --path "$staging"
godot_run --headless --path "$staging" --editor --quit
python3 - "$godot_settings_dir/editor_settings-4.7.tres" "$android_sdk" "$java_home" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
sdk = sys.argv[2]
java_home = sys.argv[3]
if not path.exists():
    raise SystemExit(f"Godot editor settings were not created: {path}")
text = path.read_text()
replacements = {
    "export/android/android_sdk_path": sdk,
    "export/android/java_sdk_path": java_home,
}
for key, value in replacements.items():
    import re
    pattern = rf'^{re.escape(key)}\s*=\s*".*"$'
    line = f'{key} = "{value}"'
    text, count = re.subn(pattern, line, text, flags=re.MULTILINE)
    if count == 0:
        text += f'\n{line}\n'
path.write_text(text)
PY
mkdir -p "$staging/build"
godot_run --headless --path "$staging" --export-release "Android" "$staging/build/kids-playground.apk"
godot_run --headless --path "$staging" --script res://tools/pack_content.gd -- "$staging/build/content.pck"

APK_PATH="$staging/build/kids-playground.apk" PCK_PATH="$staging/build/content.pck" \
  node scripts/native/generate-release.mjs

apk_path="$project_root/build/native-release/kids-playground-$(node -e "console.log(require('./apps/android/version.json').versionCode)").apk"
apk_entries="$(unzip -Z1 "$apk_path")"
if rg -q '^lib/armeabi-v7a/' <<<"$apk_entries"; then
  echo "发布 APK 不应包含 ARM32 运行库。" >&2
  exit 1
fi
if ! rg -q '^lib/arm64-v8a/libgodot_android\.so$' <<<"$apk_entries"; then
  echo "发布 APK 缺少 ARM64 Godot 运行库。" >&2
  exit 1
fi
if rg -q '^assets/(assets/)?stories/' <<<"$apk_entries"; then
  echo "发布 APK 不得内置故事插画。" >&2
  exit 1
fi
if rg -q '\.(mp3|m4a|aac|wav|ogg)$' <<<"$apk_entries"; then
  echo "故事音频应由系统 TTS 生成，发布 APK 不得内置音频文件。" >&2
  exit 1
fi
apk_bytes="$(wc -c < "$apk_path" | tr -d '[:space:]')"
if (( apk_bytes > 100 * 1024 * 1024 )); then
  echo "APK 体积 ${apk_bytes} 字节，超过 100 MiB 发布上限。" >&2
  exit 1
fi
echo "原生安装包已生成：$project_root/build/native-release"
