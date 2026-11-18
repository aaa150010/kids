#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$project_root"
story_python="${KIDS_STORY_PYTHON:-python3}"
"$story_python" -c 'import sys; sys.exit("故事音频制作需要 Python 3.10 或以上版本。") if sys.version_info < (3, 10) else None'
"$story_python" -m venv build/story-tools/venv
build/story-tools/venv/bin/python -m pip install --disable-pip-version-check \
  --cache-dir build/story-tools/pip-cache -r scripts/native/story-audio-requirements.txt
printf '故事音频隔离环境已准备。运行 pnpm native:stories:audio 制作 MP3。\n'
