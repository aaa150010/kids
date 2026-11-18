# 原生版界面与动画基线

## 技术基线

- Godot 4.7.2、Compatibility 渲染器、横屏沉浸式全屏；主目标 OPPO Pad 3 Pro 12.1 英寸，逻辑视口 1600×1129 并按 `canvas_items` + `expand` 缩放；目标平板优先 120 FPS，逻辑帧按游戏类型固定。
- `PlaygroundUI` 提供主题、字体、颜色、按钮、圆角面板、标签和转场；游戏只组合组件，保持原生。
- `NativeGameScreen` 统一顶部栏、儿童状态、暂停、说明、声音、系统返回和实时补存；`LobbyGameCard` 负责大厅卡片与拖动。
- 不使用 WebView、DOM、CSS、Vite 或浏览器路由。
- 不引入第三方运行时 UI/动画框架；统一使用 `MotionKit`、Godot Tween/AnimationPlayer、AudioServer 和原生 Control。

## 共享交互框架（2026-11 新增）

- `src/ui/interaction/` 是全局交互层：`GestureRecognizer`（tap/长按/拖拽状态机）、`InteractionController`（输入优先级仲裁：弹窗500>拖拽400>选中300>棋盘100）、`DragController`（跟手 ghost 与落点/回弹）、`SelectableGroup`（选中态）、`DialogManager`（统一弹窗）、`PressFeedback`（按压回弹）、`SfxMap`（语义事件→合成音效映射）。
- main 作为 `main_hub` 组暴露 `ipc` 与 `dialogs`；游戏与自绘表面通过 `get_first_node_in_group("main_hub")` 访问，弹窗打开期间用 `ipc.is_blocked_by_dialog()` 静默游戏输入。
- 弹窗规范：S/M/L 三档按屏幕比例（0.38/0.56/0.74，含像素上限与安全边距），圆角 28、2px 描边、遮罩 0.38、进出 scale+淡入约 200/160ms、按钮高 60 字号 22、双按钮等宽、关闭后焦点还原；返回键统一先关弹窗栈顶。
- 自绘表面（board_surface、quiz_stage）输入统一走手势状态机，触摸与鼠标双通道并去重；触摸抬起/暂停/弹窗时必须清理 hover 与按压残留。PvZ 使用上游 `SubViewport` 的 1066×600 原生输入坐标，由宿主把桌面/平板指针换算进去。
- 大厅：`SmoothScrollContainer` 提供阻尼惯性与边界回弹；封面经 `LobbyCoverCache` 后台线程加载；排序为增量重排（不整树重建），长按进入拖拽排序，普通滑动即滚动。

## 游戏视觉分组

| 分组 | 游戏 | 主要动效 |
| --- | --- | --- |
| 答题练习 | 唐诗、数学小练本、口算、拼音、规律、动物 | 题卡入场、答案按压、知识讲解停留、手动下一题 |
| 记忆棋类 | 记忆翻翻乐、五子棋、军棋、斗兽棋 | 翻牌、棋子落下、移动、合法位置发光、胜负连线与回放 |
| 棋盘冒险 | 中华智慧岛 | 原生 3D 岛屿、逐格移动、骰子、建筑和岛心挑战 |
| 塔防 | 植物大战僵尸 | 原生 2D 场景、植物待机、阳光脉冲、僵尸行走、割草机、旗帜波和首领 |
| 故事听读 | 中外故事馆 | 绛红绘本书架、分段原生自绘拼音、朗读段落高亮、底部固定播放器 |

## 模式与交互

- 每款游戏先选模式，再选儿童；模式、参与者和阶段一起进入会话键。
- 单人闯关有章节地图、星级和逐关保存；棋类残局使用固定局面和提示，不调用运行时 AI。
- 答题讲解与答案保留到手动点击“下一题/查看成绩”；棋类和记忆游戏按各自换手规则转换。
- 所有主要按钮至少 56dp，辅助触摸至少 48dp；密集棋盘提供按住预览。游戏内返回为左上 52dp 紧凑按钮，不再使用全宽大返回层。
- 动画服务于操作反馈：按钮约 70–130ms，弹窗约 120–180ms，翻牌约 260ms，棋子移动约 240–400ms。
- 暂停停止逻辑计时和场景 Tween；恢复后不重复执行动作或结算。
- 故事馆采用单人自由听读，正文与逐字拼音内置，MP3 按需下载后缓存；播放完保留正文，不自动换篇。后台和锁屏暂停，回来手动接着听；播放与阅读位置、字号、拼音、收藏按儿童实时保存。
- `StoryText` 按段缓存字形布局，用原生 Canvas 绘制正文与拼音，不为每个字建立节点；字号、拼音或宽度改变时重排。书架每页最多 18 篇，避免同时建立整库卡片。
- 中文固定使用随包 Noto CJK，Emoji 才走系统彩色字体；封面和图案启用 mipmap 与线性过滤。
- 卡片和任何 `Container` 子节点禁止用位置动画入场；只动画透明度、缩放或独立浮层。
- 游戏优先 120 FPS；持续掉帧时降低粒子和 3D 质量，不主动降低目标刷新率。岛屿 3D 静止时停止刷新。

## 目标平板与开场

- 主要目标：OPPO Pad 3 Pro 横屏。官方 OPD2402 参数为 12.1 英寸、3000×2120、7:5、最高 144Hz、303 PPI、LCD；13.2 英寸 3392×2400 平板只作为可选回归兼容目标。
- 运行时读取 `DisplayServer.screen_get_size()`，以实际屏幕为准；布局使用安全边距与弹性容器，不硬编码 3000 或 3392 像素。OPPO Pad 3 Pro 主基线是 1600×1129 逻辑视口，用于覆盖 3000×2120 物理分辨率。
- 启动序列：`LYNOTE / 童心制作` 厂牌入场 → 标题/副标题与光环动效 → 淡入大厅。约 3–4 秒，可触摸或确认键跳过。
- 开场动画使用原创文字、圆环、星点和合成的 `studio`/`title` 音效，不复制腾讯、TiMi 或任何现成游戏的商标和素材。

## 来源与素材

- `content-src/references.json` 记录参考项目、查询时的 Star 数、授权和采用方式。
- `content-src/licenses/` 保存 Kenney、OpenMoji、Noto 和植物大战僵尸本地来源记录。
- Kenney UI、棋盘和动物包为 CC0；OpenMoji 图案为 CC-BY-SA-4.0；Noto CJK 字体为 OFL-1.1。
- 植物大战僵尸当前角色与关卡素材只用于本地个人版，公开分发前必须替换标题、角色和素材。
- 植物大战僵尸的固定版本素材由 `node scripts/native/import-garden.mjs` 下载并按 Git blob 与 SHA-256 校验；表现索引由 `content-src/data/garden-presentation.json` 描述，规则数据由 `content-src/data/garden-rules.json` 描述。
- 战斗实现固定为 `hsk-dream/PVZ-Godot-Dream@740691cf9b0ad02c7021efa4dae2ab5f86207585` 的导入副本 `apps/android/pvz/`。`PvZLevelFactory` 只把本项目的 50 关转换成上游 `ResourceLevelData`，`PvZBattleHost` 只负责视口、触摸、暂停、倍速、胜负和快照；不得再维护第二套塔防引擎。
- 卡牌、植物、僵尸、弹道、阳光、割草机、波次、迷你模式和 Boss 均由上游状态机与动画资源驱动。`scripts/native/extract-pvz-reanim.py` 负责补齐两个编译动画依赖的扁平贴图。
- PvZ 审计入口为 `KIDS_PLAYGROUND_AUDIT=1` 下的 `tests/pvz_smoke.gd` 与 `tests/ui_snapshot.gd`；前者覆盖 50 关映射、五类特殊关启动、种植、僵尸/阳光/罐子/植物快照恢复，后者生成三档尺寸截图和性能报告。
- Godot 升级前在独立分支运行规则、存档、两档平板和更新回归，不直接覆盖稳定版本。
