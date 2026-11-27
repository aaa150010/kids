#!/usr/bin/env python3

from pathlib import Path
import re
import sys


if len(sys.argv) != 2:
    raise SystemExit("用法：patch-caddy.py <Caddyfile 路径>")

path = Path(sys.argv[1])
text = path.read_text()
original = text

# Normalize every previously generated route block. This makes the patch
# idempotent even if an earlier deploy wrote a route before Caddy validation.
old_legacy = re.compile(
    r"(?ms)"
    r"    # kids-playground-routes\n"
    r"    @play_root path /play\n"
    r"    redir @play_root /play/ 308\n"
    r"\n"
    r"    handle /play/\* \{\n"
    r"        reverse_proxy kids-playground-web:80\n"
    r"    \}\n?"
)
legacy_block = re.compile(
    r"(?m)"
    r"^    (?:# kids-playground-web-retired\n    )?"
    r"@kids_play_legacy path /play /play/\*\n"
    r"    redir @kids_play_legacy /play-app/ 308\n"
)
native_block = re.compile(
    r"(?m)"
    r"^    (?:# kids-playground-native-routes\n    )?"
    r"@kids_download_path path /play-app\n"
    r"    redir @kids_download_path /play-app/ 308\n"
    r"    handle /play-app/\* \{\n"
    r"        reverse_proxy kids-playground-web:80\n"
    r"    \}\n?"
)
marker_comment = re.compile(r"(?m)^    # kids-playground-(?:web-retired|native-routes)\n")

text = old_legacy.sub("", text)
text = legacy_block.sub("", text)
text = native_block.sub("", text)
text = marker_comment.sub("", text)

marker = "\n    handle {"
index = text.rfind(marker)
if index < 0:
    raise SystemExit("没有找到 Caddy 最终 handle 块，已停止修改")
canonical = (
    "    # kids-playground-web-retired\n"
    "    @kids_play_legacy path /play /play/*\n"
    "    redir @kids_play_legacy /play-app/ 308\n"
    "\n"
    "    # kids-playground-native-routes\n"
    "    @kids_download_path path /play-app\n"
    "    redir @kids_download_path /play-app/ 308\n"
    "    handle /play-app/* {\n"
    "        reverse_proxy kids-playground-web:80\n"
    "    }\n"
    "\n"
)
text = text[:index] + "\n" + canonical + text[index:]

if "handle /play/*" in text:
    raise SystemExit("旧网页版 /play/* 路由仍然存在，已停止修改 Caddy")

if text == original:
    print("Caddy 路由已经是下载页配置。")
else:
    path.write_text(text)
    print("Caddy 路由已改为 APK 下载页。")
