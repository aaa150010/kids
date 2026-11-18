#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$project_root"
node scripts/native/prepare-story-audio-release.mjs
remote_root='/opt/kids-playground/dist/play-app/stories'
ssh aliyun "mkdir -p '$remote_root/audio'"
COPYFILE_DISABLE=1 tar --no-xattrs -czf - -C build/story-audio-release audio |
  ssh aliyun "tar -xzf - -C '$remote_root'"
scp build/story-audio-release/inventory.json "aliyun:$remote_root/inventory.json"
printf '故事音频已上传；随后发布包含对应音频索引的 APK 或签名内容包。\n'
