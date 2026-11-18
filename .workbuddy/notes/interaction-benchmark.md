# 交互对标调研清单（W0）

> 调研日期：2026-11-18。每条 = 细节描述 → 参考来源 → 我们现状差距 → 建议实现要点。
> 现状基于 `apps/android/src/games/` 与 `apps/android/src/ui/` 当前代码（只读分析，未改动）。

---

## 1. 植物大战僵尸（garden，重点）

主参考 **PVZ-Godot-Dream**（Godot 4.7，自定义非商用许可，禁止商用；仅作交互与架构参考，不复制代码与资源）。以下源码路径均指该仓库。

### 1.1 卡片选择状态机

- **细节**：卡片按用途分四种上下文（图鉴 Catalog / 选卡 Selection / 战斗 Battle / 图鉴详情 Almanac），点击行为由 `card_context` 分发；战斗中点击不可用卡片播放 `buzzer` 提示音，可用则发 `main_game_click_card` 事件进入"手持"状态。
  来源：<https://github.com/hsk-dream/PVZ-Godot-Dream/blob/main/scripts/ui/card/card.gd>（`CardContext` 枚举、`_on_button_pressed`）
  现状差距：`garden_game.gd:539 _select_battle_seed` 只是记录 `selectedSeed`，无上下文区分、无不可点击音效。
  实现要点：卡片节点维护 `state = idle/selected/cooling/disabled`；点击冷却中或阳光不足的卡播放闷音 buzzer + 卡片轻微左右抖动（2 次、±4px、共 0.2s），不做其他响应。

- **细节**：手持管理器是真正的三态状态机 `Null / Character / Item(铲子)`，进入新状态前调旧状态的 `exit_status()` 清理预览；右键或左键点空白处取消手持并播放 `tap2`。
  来源：<https://github.com/hsk-dream/PVZ-Godot-Dream/blob/main/scripts/manager/hand_manager/hand_manager.gd>
  现状差距：选中种子与铲子是两个独立布尔字段（`_select_battle_seed` 里手动互斥），点空白不能取消选择。
  实现要点：抽象 `HandState` 状态机（空手/持植物卡/持铲子），统一切换入口保证互斥；触屏上"再次点击已选卡片"或"点草坪外区域"= 取消，取消时播放轻音效。

- **细节**：选卡阶段（开战前）卡片在候选区与出战槽之间用 0.2s Tween 移动，移动期间 `mouse_filter = IGNORE` 屏蔽点击，结束恢复 `PASS`；卡槽满时点击播放 buzzer。
  来源：<https://github.com/hsk-dream/PVZ-Godot-Dream/blob/main/scripts/ui/card/card_slot/card_slot_norm/card_slot_norm.gd>（`move_card_to`）
  现状差距：`_render_seed_picker` 选卡为即时切换，无飞行动画。
  实现要点：选卡页点击候补卡 → 卡片复制一个 TextureRect 残影，Tween global_position 0.2s 飞入出战槽后销毁残影；动画期间锁定输入。

### 1.2 拖拽种植 + 格子高亮

- **细节**：选中卡片后生成两个预览：跟手的不透明静态图 `characte_static`（z_index=1 跟随指针）+ 格子内的半透明虚影 `characte_static_shadow`（`modulate.a = 0.5`）。进入格子时校验种植条件，**可种才显示虚影，不可种虚影 alpha=0**；紫卡（升级卡）还会让可升级的已有植物做明暗呼吸提示。
  来源：<https://github.com/hsk-dream/PVZ-Godot-Dream/blob/main/scripts/manager/hand_manager/hm_character.gd>（`click_card` / `_update_cell_shadow` / `start_preplant_purple_light`）
  现状差距：我们点卡片后没有任何跟手预览，点格子直接尝试种植，失败才 toast 报错（`garden_game.gd:548 _battle_cell`）。
  实现要点：选中卡片后 ① 卡片本身 scale→1.12 + 偏移上浮 4px 表示"已拿起"；② 生成跟手半透明 ghost（alpha 0.85）跟随触摸点；③ 手指/指针所在格做判定：可种 → 格内显示 alpha 0.5 的植物虚影 + 格子描边绿色；不可种 → 虚影隐藏 + 格子描边红色（儿童版建议始终给虚影，用红绿描边区分可/不可）。

- **细节**：点击格子确认种植前**重验**一次卡片可用性（冷却、阳光、条件），任何一步失败播 buzzer 且不扣阳光不进冷却；成功后发一次 `signal_card_use_end` 统一结算（扣阳光 + 开始冷却）。
  来源：<https://github.com/hsk-dream/PVZ-Godot-Dream/blob/main/scripts/manager/hand_manager/hm_character.gd>（`click_cell`）、<https://github.com/hsk-dream/PVZ-Godot-Dream/blob/main/scripts/ui/card/card_slot/card_slot_norm/card_slot_battle.gd>（`card_use_end`）
  现状差距：我们的失败提示是 toast 文字，成人化；结算散落在 engine 里。
  实现要点：种植动作走"预校验 → 执行 → 统一结算"三步；失败反馈 = buzzer 音效 + 目标格红色闪烁 0.3s（不用文字 toast，儿童不认字）。

- **细节**：种植地形条件用位掩码（草地 2 / 花盆 4 / 水 8 / 睡莲 16 / 屋顶 32），格子初始化时按类型赋 `curr_condition`，植物条件与之按位与判定。
  来源：<https://github.com/hsk-dream/PVZ-Godot-Dream/blob/main/scripts/main_game_item/plant_cell.gd>（`init_condition`）
  现状差距：`garden_engine.gd` 的种植校验逻辑较散。
  实现要点：格子持有一个 condition 位掩码字段，种植校验 = `(plant.need & cell.condition) != 0`，方便后续加泳池/屋顶。

### 1.3 阳光收集

- **细节**：阳光点击后 ① 立即 `collected = true` 防重复点击并销毁 Button（防连点）② 播放 `points` 音效 ③ Tween 0.3s EASE_OUT 飞向左上角卡槽阳光位（`marker_2d_sun_target`，含摄像机偏移修正）④ 到达后 0.5s 渐隐再 free。天降阳光未收集 10s 后 1s 渐隐消失；阳光面值决定 scale（value/25）。
  来源：<https://github.com/hsk-dream/PVZ-Godot-Dream/blob/main/scripts/ui/main_game_ui/sun.gd>
  现状差距：`_collect_sun` 点击即消失入账，无飞行动画、无自然消失机制不明。
  实现要点：阳光点击 → 禁用输入 → 飞向 HUD 阳光数字（0.3s EASE_OUT）→ 到达瞬间数字跳动放大 1.3 倍回弹 + 入账；未被点击的阳光 8~10s 后渐隐消失。开启自动收集时等下落 tween 结束自动触发同一流程（参考 `on_sun_tween_finished` + `auto_collect_sun` 配置）。

- **细节**：天降阳光间隔随已产出总量递增（`A = 10×总量+425`ms，上限 950+rand(274)），即越到后期天降越慢，逼玩家种向日葵。
  来源：<https://github.com/hsk-dream/PVZ-Godot-Dream/blob/main/scripts/manager/day_suns_manager.gd>（`change_production_interval`）
  现状差距：需确认我们天降阳光是否恒定节奏。
  实现要点：儿童版可降低强度但保留"递减"节奏，避免后期躺平。

### 1.4 铲子流程

- **细节**：点 UI 铲子 → 铲子图标从槽位消失、真实铲子跟随指针；悬停有植物的格子时目标植物做"预铲"高亮（`be_shovel_look`），同格多棵植物按指针位置选择预铲目标；点击确认铲除播 `plant2` 音效；取消（点空白/右键）后铲子图标回到槽位。
  来源：<https://github.com/hsk-dream/PVZ-Godot-Dream/blob/main/scripts/manager/hand_manager/hm_item.gd>、<https://github.com/hsk-dream/PVZ-Godot-Dream/blob/main/scripts/ui/card/shovel_in_ui.gd>
  现状差距：`_toggle_shovel` 是开关式，无悬停预铲高亮、无跟手铲子。
  实现要点：铲子激活 = 跟手铲子图标 + 悬停格子中有植物时植物做白描边/微颤（预铲高亮）；点击即铲；再点空白或铲子槽取消，铲子 Tween 飞回槽位 0.2s。

### 1.5 冷却遮罩与费用状态

- **细节**：冷却用 `_cool_mask`（进度遮罩）从上到下消退，`judge_card_ready` 综合"是否出战卡 / 阳光够不够 / 冷却中 / 紫卡前置"四项决定 `is_can_click`；不可用 = 遮罩常显；冷却结束瞬间若阳光够则遮罩隐藏变亮。
  来源：<https://github.com/hsk-dream/PVZ-Godot-Dream/blob/main/scripts/ui/card/card.gd>（`judge_card_ready` / `card_cool` / `_process`）
  现状差距：需确认卡片是否有冷却进度可视化（当前 `_battle_seed_button` 只有三态 stylebox）。
  实现要点：卡片上叠一个深色半透明遮罩 Control，高度 = 剩余冷却比例（每帧或 0.1s 刷新）；阳光不足时整卡饱和度降低（modulate 变灰暗）但无遮罩——两种不可用状态视觉可区分。

- **细节**：阳光变化时遍历所有出战卡调 `judge_sun_enough` 刷新可用态；紫卡价格 = 基础价 + 50×场上同种数量，每次植物数量变化后下一帧刷新。
  来源：<https://github.com/hsk-dream/PVZ-Godot-Dream/blob/main/scripts/ui/card/card_slot/card_slot_norm/card_slot_battle.gd>（`sun_value` setter、`update_card_purple_sun_cost`）
  实现要点：阳光入账/扣除都走 setter 统一广播刷新卡片状态，不要在各处手动刷 UI。

### 1.6 波次 / HUD / 提示

- **细节**：波次分四类（普通/旗前/旗帜/最终），`curr_wave % 10 == 8` 旗前、`==9` 旗帜；旗帜波前播 4s "一大波僵尸正在接近" 大字 + `hugewave` 音效，最终波再追加 3s 红字 "最后一波" + `finalwave` 音效；开局依次显示 准备→放置→开始 各 0.6s。
  来源：<https://github.com/hsk-dream/PVZ-Godot-Dream/blob/main/scripts/manager/zombie_manager/zm_zombie_wave_manager.gd>、<https://github.com/hsk-dream/PVZ-Godot-Dream/blob/main/scripts/ui/main_game_ui/ui_remind_word.gd>
  现状差距：`_wave_text` 只是 HUD 文本，无全屏大字提示。
  实现要点：旗帜波触发全屏居中大字（scale 0.8→1.0 弹入，停留 2~3s，渐隐）+ 音效；开局 Ready-Set-Plant 三段各 0.6s 顺序显示。

- **细节**：关卡进度条每波占 `100/(max_wave-1)`，旗帜波在该处显示旗帜图标；每秒按当波预算时间推进进度。
  来源：<https://github.com/hsk-dream/PVZ-Godot-Dream/blob/main/scripts/manager/zombie_manager/zm_zombie_wave_manager.gd>（`set_progress_bar`）、`scripts/ui/main_game_ui/ui_flag_progress_bar.gd`
  现状差距：需确认我们是否有可视化进度条。
  实现要点：右下角（手机版布局）横向进度条 + 旗帜刻度，平滑每秒推进；旗帜到达时旗帜图标弹跳一次。

- **细节**：手持临时卡期间屏蔽其他卡片输入（`mouse_filter_stop`），防止多点触控误触；全局有 `tree_pause_manager` 保证暂停时冷却/波次计时全部冻结。
  来源：<https://github.com/hsk-dream/PVZ-Godot-Dream/blob/main/scripts/ui/card/card.gd>（`mouse_filter_start/stop`）
  实现要点：任何"拿起"状态期间锁其他卡片输入；所有计时器用 `create_timer(x, false)`（process_always=false）保证暂停一致。

### 1.7 其他 PVZ 参考

- jspvz wiki「卡片」词条：确认原版规则——点卡→点格种植、点空白取消、传送带/种子雨卡片一次性且 15s 未用消失（剩 5s 开始闪烁）。<https://jspvz.fandom.com/zh/wiki/%E5%8D%A1%E7%89%87>
  实现要点：临时卡（如有奖励卡）消失前 5s 开始 alpha 0.5↔1.0 正弦闪烁（参考 `card.gd` 的 `card_blink_start`）。
- 手机版操作确认：支持"点选卡片再点格子"与"拖拽到格子"两种方式，拖拽在密集布防时效率更高。<https://www.tpzpw.com/yxgju06/992.html>
  实现要点：两种手势都支持：点-点（选中→点格）为默认，按住卡片拖出超过 24px 视为拖拽，松手在格子上即种植、松在空处即取消。
- PVZ 中文 wiki（机制数值参考）：<https://wiki.pvz1.com/doku.php?id=home>
- HYTommm/Godot-PVZ（C# 版，粒子特效参考，樱桃炸弹爆炸）：<https://github.com/HYTommm/Godot-PVZ>
- 信号总线/随机选择器模式参考 LiGameAcademy/godot_core_system：<https://github.com/LiGameAcademy/godot_core_system>
- B 站 Godot4.3 PVZ 制作教程（已完结，逐集对应模块）：<https://www.bilibili.com/video/BV1AdBtY9Ec5/>
- 已有素材来源 pvz-web（本地个人版，公开分发前需替换，见 references.json）。

---

## 2. 斗兽棋（board，animal）

- **细节**：Flutter 版 animal_chess 把规则做成可插拔 variant（鼠入兽穴、狮虎跳河、狗入河等开关），棋子组件与棋盘组件分离，选中后由 controller 计算合法落点。
  来源：<https://github.com/neoalienson/animal_chess>
  现状差距：`board_game.gd` 已有"点亮起的位置移动"，规则在 `board_rules.gd`。
  实现要点：选中棋子 = 棋子 scale 1.15 + 底座光圈；合法格绿色圆点、可吃格红色圆环；点非法位置播闷音并取消选中。

- **细节**：Jungle-Chess（SUSTech CS109 满分项目）明确移动端选中态：tap 选中 → 高亮可走格 → tap 目标格移动/吃子；陷阱中棋子等级临时变 0 的提示、三次重复走子禁手。
  来源：<https://github.com/Layheng-Hok/Jungle-Chess>
  实现要点：吃子反馈 = 被吃棋子缩小淡出 0.25s + 吃子方棋子弹跳落位（TRANS_BACK）；进陷阱的棋子加"↓"小角标表示等级失效。

- **细节**：HTML5 版强调触屏友好：Canvas 渲染 + 响应式，移动端点按精度通过放大棋子命中区解决。
  来源：<https://github.com/zhengxuan666/animal_chess>
  实现要点：棋子命中区 ≥ 64×64 逻辑像素，比可视棋子大一圈（外扩 12px）。

- 规则权威参考：Jungle (board game) Wikipedia <https://en.wikipedia.org/wiki/Jungle_(board_game)>；已有参考 zyxyuanxiao/jungle（MIT，见 references.json）。

---

## 3. 五子棋（board，gomoku）

- **细节**：pixi-gomoku（接入 Rapfi 引擎，GPL-3.0）移动端要点：禁手点标红叉、最后一手高亮、悔棋区分人机/在线、落子音效、结算开宝箱动效；引擎放 Web Worker 避免卡 UI。
  来源：<https://github.com/virgoone/pixi-gomoku/>、介绍帖 <https://www.v2ex.com/t/1245909>
  现状差距：我们是"点空交叉点落子，按住可以预览"（`board_game.gd:147`）。
  实现要点：按住预览 = 半透明棋子（alpha 0.5）跟随手指所在交叉点，松手落子——符合儿童"先看到再放下"；最后一手棋子加红圈/亮点标记；落子瞬间棋子 scale 1.3→1.0 回弹（0.15s）+ 木质音效。

- **细节**：Algovate/Gomoku 分模式处理悔棋（比赛模式禁悔棋、教学模式 AI 实时提示最佳点），打谱模式逐步回放。
  来源：<https://github.com/Algovate/Gomoku>
  实现要点：教学模式在儿童思考超 N 秒后在建议落点显示呼吸光圈（呼应我们已有的 `hintSeconds` 闲置提示机制 `board_game.gd:306`）。

- **细节**：防抖与误触—— quiz/棋类通用做法：选中后禁用其他选项直到状态复位；五子棋落子即提交但提供悔棋按钮（撤销双方各一步）。
  来源：<https://github.com/Javawan1976/gomoku-game>（U 键悔棋、最后一步红圈）
  实现要点：落子动画期间（0.2s）锁棋盘输入；悔棋按钮一次撤两步（我方+AI）并播撤销音效。

- 已有参考 lihongxun945/gobang（见 references.json）。

---

## 4. 军棋翻翻乐（board，military）

- **细节**：天天军棋翻翻棋官方规则交互：开局全背面朝上，轮流点翻；**连续两次翻出同色者定阵营**；每回合只能"翻棋"或"走棋"一次；存活棋子以点亮图标陈列在角色名下方。
  来源：<https://ttjq.qq.com/webplat/info/news_version3/21963/21964/21965/21967/m14277/201607/489540.shtml>
  现状差距：`board_game.gd:147` 提示语"先翻暗棋，或选自己的亮棋"已有雏形。
  实现要点：翻牌 = 0.2s scale.x→0 换面→scale.x→1（同记忆翻牌曲线）；定阵营时刻连续两次同色的第二张牌做金色描边 + 横幅"你执红方！"；存活棋子面板用点亮/熄灭的军衔图标条。

- **细节**：Godot 4.7 单机 3D 军棋翻翻棋（pengpengjunqi）：棋盘棋子全程序化生成，暗棋点击翻开即揭示；与本项目同引擎同版本，可直接对照场景组织方式。
  来源：<https://github.com/YuRos2/pengpengjunqi>
  实现要点：重点参考其翻棋输入路由（翻/走二选一的状态机）而非 3D 表现。

- **细节**：Banqi 类暗棋实现（Youchenjiang/app-dark-chess，Clean Architecture）：翻开第一子定色、翻/移/吃三种操作互斥、UI 层与规则层完全分离。
  来源：<https://github.com/Youchenjiang/app-dark-chess>
  实现要点：我们 engine 已分离（`board_rules.gd`），保持 UI 只读 state 不内嵌规则。

- 其他参考：910JQK/GwanKei（Qt 四国军棋）<https://github.com/910JQK/GwanKei>；Pacer-9/army-chest-game（翻翻棋事件协议 FLIP_PIECE/MOVE_PIECE）<https://github.com/Pacer-9/army-chest-game>；已有 samuelyuan/online-junqi（MIT，见 references.json）。

---

## 5. 记忆翻翻乐（memory）

- **细节**：Godot 标准翻牌曲线：scale.x 0.11s 压到 0.04 → 换贴图 → TRANS_BACK/EASE_OUT 弹回 1.0；配对成功叠加一次金黄闪光（0.08s 亮 + 0.15s 恢复）。
  来源：justincalleja Godot 翻牌教程 <https://justincalleja.com/blog/posts/godot-card-flipping>；thelastbucuc/godot-memory-madness（Tween scale 1.1 + rotation 10° 翻牌手感）<https://github.com/thelastbucuc/Godot-Memory-Madness>
  现状差距：`memory_card.gd:97-102` 已实现几乎一致的曲线（压扁 0.11s + BACK 弹出 + 配对金黄闪），属于已达标签。
  实现要点：可补充：翻开瞬间加轻微旋转（±8°）增加"纸片感"；不匹配时两张卡先停顿 0.6s（让儿童看清图案）再同时翻回，翻回前各做一次左右摇头（rotation ±6°×2）。

- **细节**：不匹配反馈节奏——Stranne.EcsMemory："不匹配则短暂延迟后翻回"；matheuscoradinimf/godot-memory-game 用信号驱动 + 音效区分匹配/不匹配，步数统计进结算页。
  来源：<https://github.com/stranne/Stranne.EcsMemory>、<https://github.com/matheuscoradinimf/godot-memory-game>
  现状差距：需确认不匹配延迟时长与是否有专用音效。
  实现要点：匹配 = 上扬双音 + 卡片微弹跳后淡化/留在原位发亮；不匹配 = 低沉单音 + 停顿 0.6s + 翻回；第二张翻开后 0.3s 内锁输入防连点第三张。

- **细节**：难度进阶用网格尺寸阶梯（2x2 → 6x7），结算页展示步数。
  来源：<https://github.com/matheuscoradinimf/godot-memory-game>
  实现要点：保持我们现有难度梯度；结算页展示"用了 N 步 / 最少 M 步"。

- 已有参考 sromku/memory-game（Apache-2.0，见 references.json）；Dilumo/micro-memory_game（MIT，计时+自定义图片）<https://github.com/Dilumo/micro-memory_game>。

---

## 6. 答题/练习类（quiz：口算、拼音、图形规律、动物分类、数学练本）

- **细节**：选项反馈即时且"错误不惩罚"：答对播欢快音效 + 动画庆祝；答错用 "Let's try again!"、"Almost there!" 式鼓励语 + 箭头/高亮/脉冲指向正确答案，不用文字批评（5 岁以下不认字）。
  来源：everydaypsy 儿童教育 App 最佳实践 <https://everydaypsy.com/best-practices-for-creating-interactive-content-in-educational-apps-for-younger-students>；OriginUX 儿童 UX <https://www.originux.com/resources/blog/ux-design-for-kids-how-to-make-a-product-kids-will-love/>
  现状差距：`quiz_game.gd:189` 已有"答对啦！/一起看一看，学会就好"鼓励文案 + 讲解面板，方向正确。
  实现要点：答错时错误选项做左右摇头（0.3s）后灰掉不可再点，正确选项呼吸高亮引导重选；答对 = 选项变绿 + 星星粒子 + 角色庆祝动作。

- **细节**：防双击/连点——首次选择后禁用全部选项，反馈播完出现"下一题"按钮；微交互 150~250ms 不拖慢节奏；题目是视觉主角（题干 2rem、选项 1.5rem 的字级层级）。
  来源：Zap Code quiz UX <https://www.zapcode.dev/learn/quiz-trivia-with-ui-ux-design>
  现状差距：`quiz_game.gd:187` 反馈面板 0.16s 淡入已达标。
  实现要点：确认选项在 feedback 阶段 disabled；题间过渡 = 旧题整体左滑出 + 新题右滑入（0.25s），不要硬切。

- **细节**：输入方式要匹配考察点——日期用滑块、比大小用缩放手势、分类用拖拽/滑动分拣；儿童注意力约 30s，题型要常换。接近正确答案应被奖励而非判错（滑块容差带）。
  来源：Plume Studio 儿童答题案例 <https://plumestudio.com/case-studies/kids-quiz>
  现状差距：我们都是选择题。
  实现要点：图形规律题用"拖拽正确图形到空位"；动物分类用左右滑动/拖入篮子；口算保留选项但加大按钮。

- **细节**：错题自动归集到错题本，按遗忘曲线推送重做；错题重做通关给小贴纸奖励。
  来源：刷刷题产品说明 <https://m.shuashuati.com/v/21147651.html>
  现状差距：`quiz_game.gd:70` 已有 `wrongIds` 错题池。
  实现要点：错题复习模式入口放结算页（"把答错的再练一次"）；连续答对 2 次才从错题池移除。

- **细节**：感官负荷控制——可关音效、可减少动效；大字体（≥24px）、高对比、一次只做一件事。
  来源：everydaypsy（同上）
  实现要点：设置页提供"安静模式"（关音效）与"简单动效"开关，并持久化。

- 已有参考 GCompris（见 references.json）。

---

## 7. 智慧岛（island，大富翁类）

- **细节**：monopoly_godot（Godot 4.6，面向 Android 导出）：骰子滚动动画、棋子沿 40 格棋盘移动、金钱数字用动画标签变化、回合制 UI 状态消息。
  来源：<https://github.com/buhtig47/monopoly_godot>
  现状差距：`island_game.gd:205 roll_dice` + `moveRemaining` 逐格定时移动已有雏形。
  实现要点：掷骰 = 骰子快速换面 0.6s（30fps 逐帧）后定格并弹跳；棋子移动 = 逐格跳跃（每格 0.18~0.25s，TRANS_QUAD 小跳弧），经过的格子依次点亮；金钱/分数变化用数字滚动 tween 而不是直接换文本。

- **细节**：2D 骰子组件 riley_dice_game：滚动时从 spritesheet 顺序取面、30fps step 动画、滚完发 `on_rolled_dice` 信号供移动逻辑订阅——表现与逻辑解耦。
  来源：<https://github.com/rebellehr1010/riley_dice_game>
  实现要点：骰子结果先由逻辑层产生，动画层只"表演"该结果（最后一帧定格到目标面），避免动画帧与随机数不同步。

- **细节**：物理骰子（zondug/dice_roll）：抛掷时 scale 动画 + 随机力方向 + 自然减速停稳。
  来源：<https://github.com/zondug/dice_roll>
  实现要点：儿童版不必上物理引擎，用"旋转+缩放+缓动停稳"的 2D tween 模拟即可。

- 其他参考：VargaDot/Syndicate（Godot 4 大富翁 C#）<https://github.com/VargaDot/Syndicate>；Rebelion-Board-game/Dice_Roll（Godot 4 骰子插件，roll_finished 信号）<https://github.com/Rebelion-Board-game/Dice_Roll>。

---

## 8. 唐诗抽背（poetry）

- **细节**：闪卡式交互——上下滑动切卡、点击卡片翻转看译文/答案；按遗忘曲线推送复习；家长可看学习记录。
  来源：国学闪卡 App Store 介绍 <https://apps.apple.com/cn/app/id6772121595>
  现状差距：`poetry_game.gd`（442 行）为现有实现。
  实现要点：抽背卡 = 正面诗句（缺句）、点卡或"想不起来了"按钮 0.2s 翻面显示答案；翻卡曲线复用记忆翻牌（scale.x + BACK 弹出）；左右滑切换下一张（带跟手位移 + 松手吸附）。

- **细节**：抽卡仪式感——每句诗一个趣味闯关、每句配场景图（"诗中有画"），跟读录制可回放；一首诗走"玩→听→看→读"闭环，单首约 10 分钟。
  来源：玄机兔点唐诗 <https://baike.baidu.com/item/玄机兔点唐诗/63266732>、<https://app.mi.com/details?id=com.mojuetang.company>
  实现要点：抽卡动作 = 卡片从牌堆顶部抽出（0.3s 抛物线 tween）+ 翻牌音效；背对后卡片翻面金色边框归入"已会"牌堆；跟读环节如已有 TTS（`Speech.speak` 已在 quiz 使用）可复用。

- **细节**：快速点划勾选考字的背诵方式（点选正确的字填空格）。
  来源：我爱古诗文 App <https://apps.apple.com/cn/app/id1096444935>
  实现要点：抽背可增加"点字成句"变体：打乱的字块按序点选，点错字块摇头、点对飞入句子槽。

- 已有参考 hefengbao/jingmo（GPL-3.0 排版）、chinese-poetry/chinese-poetry（MIT 内容核对），见 references.json。

---

## 9. 大厅 / 弹窗（lobby / UI 通用）

- **细节**：儿童界面硬指标——按钮 ≥44px（建议 88 逻辑像素）触控目标、药丸形大圆角（24px+）、按钮有 pressed 下沉 + 音效的即时反馈、不依赖 hover、不用纯颜色传达对错（图标+音效双通道）。
  来源：BounceBox 儿童设计系统 <https://huggingface.co/spaces/VISHAL18for4/buildai/resolve/main/designs/bouncebox-DESIGN.md>；适龄设计规范（中文，含"按钮≥88 逻辑像素、命中区外扩 12px、随时可退出+确认层、家长页长按 3 秒进入"等可直接照抄的清单）<https://znlgis.github.io/others/CHAGS/第15章-适龄设计规范与实现>
  现状差距：`lobby_card.gd` 已有大厅卡片；`ui_kit.gd` 为通用组件。
  实现要点：大厅整张卡片可点（非只点按钮）；卡片滚动用吸附式分页（ScrollContainer + 惯性）+ 当前页指示圆点；所有弹窗 = 背景半透明遮罩 + 面板 scale 0.8→1.0 弹入（TRANS_BACK 0.25s）+ 关闭时缩回。

- **细节**：弹窗与退出——游戏内左上角返回 + 确认层（"现在回去吗？/ 再玩一会"），防止误触中断；破坏性操作（清档）长按 3 秒。
  来源：同上适龄设计规范
  现状差距：`garden_game.gd:878 _handle_back` 有返回处理。
  实现要点：所有游戏统一封装"确认弹窗"组件：大图标 + 两个超大按钮（继续玩 / 回去），误触遮罩不关闭（防小孩乱点关掉）。

- **细节**：开始页要点——超大 PLAY 按钮（≥200×80）、点击后 0.3s 淡出过渡再进游戏（遮盖加载）、角标按钮（设置/商店）≥64×64 放角落不放汉堡菜单。
  来源：Roblox obby start screen 指南 <https://roblox-gui-maker.online/use-cases/obby-start-screen>
  实现要点：大厅进入游戏 = 卡片放大到全屏的 0.3s 过渡动画 + 音效，再切换场景。

- **细节**：儿童会乱点——每次点击都要给可见反馈（哪怕无功能也做个小涟漪）；加载要快，必须有明显进度指示；家长功能（设置/购买）放"家长门"（长按或算数题）后面。
  来源：ExodeUI 儿童 UI <https://www.exodeui.com/learn/designing-ui-for-kids>；drimlike 儿童界面十则 <https://www.drimlike.com/en/blog/10-golden-rules-of-interface-design-for.html>；Nielsen Norman Group 儿童可用性研究（被 ExodeUI 引用）。

---

## 附：本调研新增参考清单（同步进 references.json）

| 模块 | 参考 | 数量 |
|---|---|---|
| PVZ | PVZ-Godot-Dream（主）、HYTommm/Godot-PVZ、jspvz wiki、PVZ 中文 wiki、触屏版操作文章×2、godot_core_system、B 站教程 | 8 |
| 斗兽棋 | neoalienson/animal_chess、Layheng-Hok/Jungle-Chess、zhengxuan666/animal_chess、Wikipedia Jungle | 4 |
| 五子棋 | virgoone/pixi-gomoku、Algovate/Gomoku、Javawan1976/gomoku-game、V2EX 介绍帖 | 4 |
| 军棋翻翻乐 | 天天军棋官方、YuRos2/pengpengjunqi、Youchenjiang/app-dark-chess、910JQK/GwanKei、Pacer-9/army-chest-game | 5 |
| 记忆翻翻乐 | justincalleja 教程、godot-memory-madness、matheuscoradinimf/godot-memory-game、Stranne.EcsMemory、Dilumo/micro-memory_game | 5 |
| 答题类 | Plume Studio 案例、everydaypsy、Zap Code、刷刷题、OriginUX | 5 |
| 智慧岛 | monopoly_godot、riley_dice_game、zondug/dice_roll、Syndicate、Dice_Roll 插件 | 5 |
| 唐诗抽背 | 国学闪卡、玄机兔点唐诗（小米商店+百科）、我爱古诗文 | 3（4 URL） |
| 大厅/弹窗 | BounceBox、适龄设计规范、Roblox obby 指南、ExodeUI、drimlike | 5 |
