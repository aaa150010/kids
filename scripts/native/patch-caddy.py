#!/usr/bin/env python3

from pathlib import Path
import re
import sys


if len(sys.argv) != 2:
    raise SystemExit("用法：patch-caddy.py <Caddyfile 路径>")

path = Path(sys.argv[1])
text = path.read_text()
original = text

retired_marker = "# kids-playground-web-retired"
if retired_marker not in text:
    legacy_pattern = re.compile(
        r"(?ms)"
        r"    # kids-playground-routes\n"
        r"    @play_root path /play\n"
        r"    redir @play_root /play/ 308\n"
        r"\n"
        r"    handle /play/\* \{\n"
        r"        reverse_proxy kids-playground-web:80\n"
        r"    \}\n?"
    )
    replacement = (
        f"    {retired_marker}\n"
        "    @kids_play_legacy path /play /play/*\n"
        "    redir @kids_play_legacy /play-app/ 308\n"
    )
    text, count = legacy_pattern.subn(replacement, text, count=1)
    if count == 0:
        # The legacy route may already have been removed manually. Add the
        # redirect block at the same location without requiring the old route.
        marker = "\n    handle {"
        index = text.rfind(marker)
        if index < 0:
            raise SystemExit("没有找到 Caddy 最终 handle 块，已停止修改")
        text = text[:index] + "\n" + replacement + text[index:]

native_marker = "# kids-playground-native-routes"
if native_marker not in text:
    native_block = (
        "    # kids-playground-native-routes\n"
        "    @kids_download_path path /play-app\n"
        "    redir @kids_download_path /play-app/ 308\n"
        "    handle /play-app/* {\n"
        "        reverse_proxy kids-playground-web:80\n"
        "    }\n"
        "\n"
    )
    marker = "\n    handle {"
    index = text.rfind(marker)
    if index < 0:
        raise SystemExit("没有找到 Caddy 最终 handle 块，已停止修改")
    text = text[:index] + "\n" + native_block + text[index:]

if "handle /play/*" in text:
    raise SystemExit("旧网页版 /play/* 路由仍然存在，已停止修改 Caddy")

if text == original:
    print("Caddy 路由已经是下载页配置。")
else:
    path.write_text(text)
    print("Caddy 路由已改为 APK 下载页。")
