#!/usr/bin/env bash
set -euo pipefail

sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Caches/KidsPlayground/android-sdk}}"
cmdline_root="$sdk_root/cmdline-tools/latest"
archive="${TMPDIR:-/private/tmp}/commandlinetools-mac-13114758_latest.zip"

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
if [[ -z "$java_home" || ! -x "$java_home/bin/java" ]]; then
  echo "需要 JDK 17。请设置 JAVA_HOME；不要使用 Java 21+ 构建当前 Android 插件。" >&2
  exit 1
fi
export JAVA_HOME="$java_home"

if [[ ! -x "$cmdline_root/bin/sdkmanager" ]]; then
  mkdir -p "$sdk_root/cmdline-tools"
  if [[ ! -f "$archive" ]]; then
    curl -fL --retry 3 --connect-timeout 20 -o "$archive" \
      https://dl.google.com/android/repository/commandlinetools-mac-13114758_latest.zip
  fi
  unzip -q "$archive" -d "$sdk_root/cmdline-tools"
  rm -rf "$cmdline_root"
  mv "$sdk_root/cmdline-tools/cmdline-tools" "$cmdline_root"
fi

yes | "$cmdline_root/bin/sdkmanager" --sdk_root="$sdk_root" --licenses >/dev/null
"$cmdline_root/bin/sdkmanager" --sdk_root="$sdk_root" \
  "platform-tools" "platforms;android-34" "build-tools;34.0.0"

echo "Android SDK 已就绪：$sdk_root"
echo "JDK 17：$JAVA_HOME"

gradle_bin="${GRADLE_BIN:-}"
if [[ -z "$gradle_bin" ]]; then
  gradle_bin="$(find "$HOME/Library/Caches/KidsPlayground/gradle/wrapper/dists" \
    -path '*/bin/gradle' -type f -print 2>/dev/null | sort -V | tail -1)"
fi
if [[ -n "$gradle_bin" ]]; then
  echo "Gradle：$gradle_bin"
else
  echo "未找到 Gradle；下次原生构建会明确提示，不会等到插件编译阶段才失败。" >&2
fi

godot_bin="${GODOT_BIN:-$HOME/Library/Caches/KidsPlayground/tools/Godot.app/Contents/MacOS/Godot}"
if [[ -x "$godot_bin" ]]; then
  echo "Godot：$godot_bin"
else
  echo "未找到 Godot 4.7.2；请设置 GODOT_BIN。" >&2
fi

rm -f "$archive"
