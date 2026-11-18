# 策略游戏交互 benchmark

研究日期：2026-11-18  
证据索引：[`strategy-interactions.json`](strategy-interactions.json)  
本地实现对照：`apps/android/src/games/`、`apps/android/src/ui/board_surface.gd`

## 计数口径与结果

只计入索引中同时满足 HTTP 200、`readSuccess: true`、有完整 `sourceText`、SHA-256 与行数的独立主题源码文件。仓库数量、许可证文件和摘要条目不作为成功源码数；同仓库不同文件各计一条。`localCode` 用于追踪本地实现差距，不改变抓取成功与否。

| 游戏 | 仓库 | 成功源码文件 | HTTP/正文/摘要 | 本地对照覆盖 |
| --- | --- | ---: | --- | --- |
| 植物大战僵尸 | `hsk-dream/PVZ-Godot-Dream` | 20 | 20/20/20 | 卡牌上下文与冷却、手持状态、种植预览重验、铲子目标、波次和提醒 |
| 斗兽棋 | `neoalienson/animal_chess` | 20 | 20/20/20 | 地形坐标、动作接口、选中与走子、规则聚合、变体创建 |
| 五子棋 | `virgoone/pixi-gomoku` | 20 | 20/20/20 | 自由规则、胜线、连珠禁手、开局约束、落子预览与最后一手 |
| 军棋翻翻乐 | `YuRos2/pengpengjunqi`、`samuelyuan/online-junqi` | 20（各 10） | 20/20/20 | 棋盘输入与绘制、翻棋回合、军衔规则；第二仓库补充公路、铁路与战斗规则参考 |
| **合计** | **5 个仓库** | **80** | **80/80/80** | 每条记录有本地代码位置或明确的待验证状态 |

计数按逐条文档记录重新汇总：garden 20、jungle 20、gomoku 20、military 20。没有将失败请求算入成功数；许可证请求错误不影响源码文件统计。此处的对照属于静态阅读，不代表外部项目运行、性能或功能验收。

## 交互观察与本地差距

- **塔防**：已经对齐选卡/出战槽双向飞行动画、按指针选层铲子、卡片回飞、平滑波内进度、旗标刻度、三段开场、旗波/最终波独立提示、随累计产出变慢的天降阳光、临时卡 15 秒生命周期和自动收集落地后触发。对应 `garden_game.gd`、`garden_field.gd`、`garden_engine.gd` 与 `garden-rules.json`。真机多点触控和声音同步仍需平板上确认。
- **斗兽棋**：规则变体仍以 AGENTS.md 基线为准；已补完整规则小书、敌方陷阱“↓”降级角标和吃子缩小淡出。对应 `board_rules.gd`、`board_game.gd` 与 `board_surface.gd`。
- **五子棋**：已保留自由规则、按住预览、最后一步、胜线动画和残局成对悔棋，并补统一规则小书；不引入参考项目 AI 或网页运行时。
- **军棋翻翻乐**：双人经典局已实现“同一玩家连续两次同色定阵营、异色重置”，候选亮棋按阵营映射；固定残局、悔棋、铁路和战斗规则继续独立测试。对应 `board_rules.gd`、`board_game.gd` 和 `board_surface.gd`。

以上“差距”表示实现对照中的后续核验项，不表示已确认存在缺陷，也不替代自动保存、重新打开恢复、后台恢复及设备交互验收。

## 本地验证（2026-11-18）

- Godot 4.7.2 项目解析退出码 0，无 GDScript 错误。
- 原生综合夹具通过，军棋定阵营/异色重置/旧存档夹具通过。
- 花园夹具 848 项、0 失败，覆盖天空阳光节奏、最终波提示恢复、临时卡过期、手持状态与铲子精确选层。
- 三档 UI 审计完成：3000×2120、3392×2400、1180×800 均无最终可见触摸目标问题，桌面模拟约 120 FPS。
- 尚未在 OPPO Pad 3 Pro 实机验证多指、系统手势、真实音频同步与 APK 覆盖安装。

## 许可核对

| 仓库 | 已保存证据 | 准确标注 | 使用边界 |
| --- | --- | --- | --- |
| `hsk-dream/PVZ-Godot-Dream` | `LICENSE` 原文保存在 `content-src/licenses/pvz-godot-dream.txt`；索引记录上游 `licenseSpdx: NOASSERTION` | 自定义 `Custom Non-Commercial License v1.0`，不是标准 SPDX 许可 | 条款允许非商业研究/教育用途，明确禁止公司内部使用、销售或变现及 SaaS/API 商业服务。本项目仅参考交互与架构，不复制代码或资源；本地 PVZ 素材另有单独授权边界 |
| `neoalienson/animal_chess` | 固定提交 `5de03ecfcd8c90aa0318f9db6c310b6abf69eb85`；未找到/未保存许可文本 | 未声明 | 只作交互研究，不复制代码或素材 |
| `virgoone/pixi-gomoku` | `LICENSE` GPL v3 原文保存在索引；固定提交 `ea9cf9f8eaccb08fd775276cbad61344ced30c21` | GPL-3.0 | 只作交互参考，不复制代码；若未来复用，需另行评估 GPL 对分发的要求 |
| `YuRos2/pengpengjunqi` | `LICENSE` MIT 原文保存在索引；固定提交 `d272ffe324036af124f42fd47a12faef880e454b` | MIT | 如复用代码，需保留版权与许可声明 |
| `samuelyuan/online-junqi` | `LICENSE` MIT 原文保存在索引；固定提交 `f5ba2e8cedaa7e1dc3975349d5bbe097f2d5e13a` | MIT | 如复用代码，需保留版权与许可声明 |

军棋参考汇总条目 `pengpengjunqi` 的旧许可描述已从“未声明”更正为 MIT，并附上证据索引和固定提交。PVZ-Godot-Dream 的上游 API 识别结果仍为 `NOASSERTION`；这不表示无许可，许可类型与边界以保存的自定义 LICENSE 原文为准。斗兽棋仓库没有可确认的许可声明，不得因为源码可下载就推定可以复制。
