# 童心游乐场

面向 4–12 岁儿童的本地多人/亲子益智游戏合集，唯一产品是 Godot 原生安卓 APK，面向 11 英寸与 13 英寸平板横屏，不使用 WebView。

## 游戏

中华智慧岛、斗兽棋、唐诗三百首、数学小练本、中外故事馆、口算碰碰船、汉字拼音找朋友、记忆翻翻乐、图形规律侦探、动物分类馆、五子棋、军棋翻翻乐、植物大战僵尸（本地版）。

中外故事馆提供 600 篇成语、神话、民间、寓言、历史与中外童话，正文和拼音随包，普通话音频按需下载并缓存。其余游戏在原经典模式之外提供单人章节、固定棋局或练习路线；所有答题讲解都要孩子手动点“下一题”，棋类落子与翻牌按各自换手规则保存。

## 目录

- `apps/android/`：Godot 4.7.2 原生安卓工程、游戏、存档、更新服务和 APK 插件。
- `content-src/`：唯一题库、诗词、关卡、图案、字体、素材和授权记录。
- `scripts/native/`：内容生成、素材导入、签名、构建和发布脚本。
- `build/native-release/`：本地构建产物，只有在你明确允许构建后生成。

## 本地准备

安装 Node.js、Godot 4.7.2、JDK 17、Android SDK 和 Gradle 8.9+；首次生成内容：

```bash
pnpm install
pnpm native:content
```

`pnpm native:content` 会先更新故事正文与逐字拼音，再导出所有原生内容。故事音频使用独立的本机制作环境：

```bash
KIDS_STORY_PYTHON=/path/to/python3.12 pnpm native:stories:setup
pnpm native:stories:audio
```

整库 MP3 位于 `content-src/story-audio/`，不会打进 APK 或内容包；服务端上传只在明确发布后执行。

## 构建

```bash
bash scripts/native/build-android.sh
```

或者使用 Docker：

```bash
KIDS_DOCKER_PROXY=http://127.0.0.1:7897 bash scripts/native/build-android-docker.sh
```

构建和测试命令仍须用户明确允许后执行。签名材料位于 `$HOME/Library/Application Support/KidsPlayground/keys/`，不得提交到仓库。

## 更新

内容包只包含数据和素材，APK 通过系统安装器升级；更新入口为 `https://lynote.xyz/play-app/`。发布前请阅读 `apps/android/README.md` 和 `AGENTS.md`。
