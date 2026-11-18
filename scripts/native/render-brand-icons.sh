#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
branding="$project_root/content-src/assets/branding"

if ! command -v sips >/dev/null 2>&1; then
  echo "缺少 macOS sips，无法从 SVG 重新生成品牌图标。" >&2
  exit 1
fi

sips -s format png "$branding/app-icon.svg" --out "$branding/app-icon-1024.png"
sips -z 512 512 "$branding/app-icon-1024.png" --out "$branding/app-icon-512.png"
sips -z 192 192 "$branding/app-icon-1024.png" --out "$branding/app-icon-192.png"
sips -s format png "$branding/app-icon-foreground.svg" --out "$branding/app-icon-foreground-432.png"
sips -z 432 432 "$branding/app-icon-foreground-432.png" --out "$branding/app-icon-foreground-432.png"
sips -s format png "$branding/app-icon-background.svg" --out "$branding/app-icon-background-432.png"
sips -z 432 432 "$branding/app-icon-background-432.png" --out "$branding/app-icon-background-432.png"

node "$project_root/scripts/native/export-content.mjs"
echo "品牌图标已重新生成并导出到 apps/android/assets/branding。"
