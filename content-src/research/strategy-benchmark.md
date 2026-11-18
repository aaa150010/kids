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

- **塔防**：参考项目按用途隔离卡牌目录、选卡与战斗状态；手持对象统一处理取消、拖动及放置；放置前重新检查格子条件。对应本地 `garden_game.gd` 的卡牌/手持处理与 `garden_engine.gd` 的预览提交逻辑。应继续核对拖拽反馈、触屏点选路径和连续操作后的存档恢复。
- **斗兽棋**：参考实现把地图常量、行动、规则和规则变体拆开，并向界面提供合法走子。对应本地 `board_rules.gd` 与 `board_game.gd`。差距核对重点是规则变体覆盖及触屏合法落点提示；本项目规则仍以 AGENTS.md 的规则基线为准。
- **五子棋**：参考涵盖自由规则、连珠禁手、开局约束及棋盘落子预览。对应本地 `board_rules.gd`、`board_game.gd` 和 `board_surface.gd`。单人练习使用固定残局，不把参考项目的 AI 或网页运行时带入原生端；残局解答正确性需独立核验。
- **军棋翻翻乐**：两个 Godot 仓库分别提供棋盘输入/绘制与翻棋、走棋状态参考，以及公路、铁路和战斗参考。对应本地 `board_surface.gd`、`board_rules.gd` 和 `board_game.gd`。玩法是本地固定残局，不依赖运行时 AI；铁路路径、行营和翻走互斥状态需继续按项目规则逐项核验。

以上“差距”表示实现对照中的后续核验项，不表示已确认存在缺陷，也不替代自动保存、重新打开恢复、后台恢复及设备交互验收。

## 许可核对

| 仓库 | 已保存证据 | 准确标注 | 使用边界 |
| --- | --- | --- | --- |
| `hsk-dream/PVZ-Godot-Dream` | `LICENSE` 原文保存在 `content-src/licenses/pvz-godot-dream.txt`；索引记录上游 `licenseSpdx: NOASSERTION` | 自定义 `Custom Non-Commercial License v1.0`，不是标准 SPDX 许可 | 条款允许非商业研究/教育用途，明确禁止公司内部使用、销售或变现及 SaaS/API 商业服务。本项目仅参考交互与架构，不复制代码或资源；本地 PVZ 素材另有单独授权边界 |
| `neoalienson/animal_chess` | 固定提交 `5de03ecfcd8c90aa0318f9db6c310b6abf69eb85`；未找到/未保存许可文本 | 未声明 | 只作交互研究，不复制代码或素材 |
| `virgoone/pixi-gomoku` | `LICENSE` GPL v3 原文保存在索引；固定提交 `ea9cf9f8eaccb08fd775276cbad61344ced30c21` | GPL-3.0 | 只作交互参考，不复制代码；若未来复用，需另行评估 GPL 对分发的要求 |
| `YuRos2/pengpengjunqi` | `LICENSE` MIT 原文保存在索引；固定提交 `d272ffe324036af124f42fd47a12faef880e454b` | MIT | 如复用代码，需保留版权与许可声明 |
| `samuelyuan/online-junqi` | `LICENSE` MIT 原文保存在索引；固定提交 `f5ba2e8cedaa7e1dc3975349d5bbe097f2d5e13a` | MIT | 如复用代码，需保留版权与许可声明 |

军棋参考汇总条目 `pengpengjunqi` 的旧许可描述已从“未声明”更正为 MIT，并附上证据索引和固定提交。PVZ-Godot-Dream 的上游 API 识别结果仍为 `NOASSERTION`；这不表示无许可，许可类型与边界以保存的自定义 LICENSE 原文为准。斗兽棋仓库没有可确认的许可声明，不得因为源码可下载就推定可以复制。
