# 童心游乐场 · 原生安卓版

Godot 4.7.2 Compatibility 渲染器的原生 APK。界面只使用 Godot Control/Theme、原生 2D 和 Godot 3D，不使用 WebView、DOM、CSS 或浏览器路由。

## 结构与内容

- `content/` 与 `assets/` 由 `content-src/` 生成，不手工维护。
- `src/core/`：存档、内容读取、音频、朗读、更新服务。
- `src/games/`：12 款游戏和中外故事馆的会话、书架、阅读器与音频互动状态。
- `src/ui/`：共享组件、大厅卡片、棋盘、答题场景、翻牌和成长雷达。
- `tests/test_runner.gd`：原生内容、规则和存档夹具。
- `tools/pack_content.gd`：只把数据和素材写入热更新包，拒绝脚本和场景。

## 生成与构建

```bash
pnpm native:content
GODOT_BIN=/path/to/godot bash scripts/native/build-android.sh
```

构建机需要 Android SDK、JDK 17、Gradle 8.9+ 和 Godot 4.7.2 Android 导出模板。首次构建会下载 Gradle 依赖并编译 `UpdateInstaller.aar`。签名材料在 `$HOME/Library/Application Support/KidsPlayground/keys/`，必须单独备份。

Docker 构建并发布：

```bash
pnpm native:release:docker
```

发布不会让用户打开网页版游戏。固定入口 `https://lynote.xyz/play-app/` 是 APK 下载页，`https://lynote.xyz/play-app/latest.apk` 是当前最新安装包；旧 `/play/` 地址会自动跳到下载页。

## 测试

按项目约定，测试须用户明确允许：

```bash
godot --headless --path apps/android --script res://tests/test_runner.gd
```

本机 UI 截图与 120 FPS 审计：

```bash
pnpm native:audit
```

默认使用 `$HOME/Library/Caches/KidsPlayground/tools/Godot.app/Contents/MacOS/Godot`，输出到 `build/ui-audit/`。包含 3000×2120、3392×2400、1180×800 三组大厅、游戏和暂停弹窗截图，以及布局和帧耗时报告。

## 中外故事馆

- 600 篇正文和逐字拼音由 `pnpm native:stories` 从 `content-src/stories/` 生成。
- 600 篇普通话 MP3 由 Qwen 在制作阶段生成，存放在 `content-src/story-audio/`，不进入 APK 或内容 PCK。
- App 首次播放时按需下载，最多并行两项；逐篇校验 SHA-256 后写入 `user://story-audio/`，之后离线播放。
- 服务端路径为 `https://lynote.xyz/play-app/stories/audio/`，只有用户明确发布后才运行上传脚本。

## 品牌图标

- 唯一 SVG 源文件：`content-src/assets/branding/app-icon.svg`。
- 自适应前景和背景：同目录的 foreground / background SVG。
- 修改图标后运行 `pnpm native:icons:brand`，会重新生成 Android 启动图标、启动页和下载页需要的 PNG。

## 更新

- APK 签名与版本：`version.json`，当前为 `1.3.0 (4)`。
- 内容版本：`content/version.json`，当前版本与最低兼容 App 版本均为 4。
- 更新清单：`latest.json` + Base64 `latest.sig`，App 校验 RSA-SHA256、大小和 SHA-256。
- 内容包下载后下次启动切换，校验失败自动回退。
- 人工下载页和 App 更新共用 `https://lynote.xyz/play-app/`；构建脚本会自动更新下载页上的版本、大小、日期和 APK 链接。
