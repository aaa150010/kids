#!/usr/bin/env bash
set -euo pipefail
export KIDS_PLAYGROUND_AUDIT=1

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
godot_bin="${GODOT_BIN:-$HOME/Library/Caches/KidsPlayground/tools/Godot.app/Contents/MacOS/Godot}"

if [[ ! -x "$godot_bin" ]]; then
  echo "找不到 Godot 4.7.2 桌面运行器：$godot_bin" >&2
  echo "可通过 GODOT_BIN 指向其他官方 4.7.2 可执行文件。" >&2
  exit 1
fi

"$godot_bin" --headless --editor --quit --path "$project_root/apps/android"
"$godot_bin" \
  --path "$project_root/apps/android" \
  --script res://tests/ui_snapshot.gd \
  --rendering-method gl_compatibility

echo "截图与报告：$project_root/build/ui-audit"
