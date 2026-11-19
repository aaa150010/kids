# 交互对标调研清单（W0）

> 调研日期：2026-11-18。每条 = 细节描述 → 参考来源 → 我们现状差距 → 建议实现要点。
> 现状基于 `apps/android/src/games/` 与 `apps/android/src/ui/` 当前代码（只读分析，未改动）。

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
  现状差距：返回处理分散在各游戏页面，尚未完全统一。
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
| 斗兽棋 | neoalienson/animal_chess、Layheng-Hok/Jungle-Chess、zhengxuan666/animal_chess、Wikipedia Jungle | 4 |
| 五子棋 | virgoone/pixi-gomoku、Algovate/Gomoku、Javawan1976/gomoku-game、V2EX 介绍帖 | 4 |
| 军棋翻翻乐 | 天天军棋官方、YuRos2/pengpengjunqi、Youchenjiang/app-dark-chess、910JQK/GwanKei、Pacer-9/army-chest-game | 5 |
| 记忆翻翻乐 | justincalleja 教程、godot-memory-madness、matheuscoradinimf/godot-memory-game、Stranne.EcsMemory、Dilumo/micro-memory_game | 5 |
| 答题类 | Plume Studio 案例、everydaypsy、Zap Code、刷刷题、OriginUX | 5 |
| 智慧岛 | monopoly_godot、riley_dice_game、zondug/dice_roll、Syndicate、Dice_Roll 插件 | 5 |
| 唐诗抽背 | 国学闪卡、玄机兔点唐诗（小米商店+百科）、我爱古诗文 | 3（4 URL） |
| 大厅/弹窗 | BounceBox、适龄设计规范、Roblox obby 指南、ExodeUI、drimlike | 5 |
