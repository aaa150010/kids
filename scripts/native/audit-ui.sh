#!/usr/bin/env bash
set -euo pipefail
export KIDS_PLAYGROUND_AUDIT=1

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
godot_bin="${GODOT_BIN:-$HOME/Library/Caches/KidsPlayground/tools/Godot.app/Contents/MacOS/Godot}"
audit_home="${KIDS_AUDIT_HOME:-$project_root/build/godot-audit-home}"
mkdir -p "$audit_home"

if [[ ! -x "$godot_bin" ]]; then
  echo "找不到 Godot 4.7.2 桌面运行器：$godot_bin" >&2
  echo "可通过 GODOT_BIN 指向其他官方 4.7.2 可执行文件。" >&2
  exit 1
fi

audit_dir="$project_root/build/ui-audit"
mkdir -p "$audit_dir"

run_audit_stage() {
  local stage_name="$1"
  shift
  local stage_log="$audit_dir/$stage_name.log"
  if ! HOME="$audit_home" "$godot_bin" "$@" 2>&1 | tee "$stage_log"; then
    return 1
  fi
  if rg -q 'SCRIPT ERROR:|Parse Error:|Compile Error:|Failed to load script|Failed to instantiate|Out of bounds' "$stage_log"; then
    echo "原生截图审计失败，请查看：$stage_log" >&2
    return 1
  fi
}

run_audit_stage import --headless --editor --quit --path "$project_root/apps/android"
run_audit_stage capture \
  --path "$project_root/apps/android" \
  --script res://tests/ui_snapshot.gd \
  --rendering-method gl_compatibility

echo "截图与报告：$project_root/build/ui-audit"
