# GameState 管理器 (GameState Manager)

> **Status**: In Design
> **Author**: Claude + 老大
> **Last Updated**: 2026-05-31
> **Implements Pillar**: 间接 — 基础设施，控制整个游戏的生命周期

## Overview

GameState 管理器控制游戏的全局生命周期。它维护一个包含 5 个状态的枚举状态机（`TITLE`, `PLAYING`, `PAUSED`, `VICTORY`, `DEFEAT`），通过 `transition_to()` 验证并执行状态转换，每次合法转换通过 EventBus 的 `game_state_changed` Signal 广播给所有订阅系统。所有其他系统通过 `is_playing()` / `is_game_over()` 查询当前状态来决定是否运行自己的逻辑。

遵循 [ADR-0003](../docs/architecture/adr/adr-0003-gamestate-state-machine.md)：使用 GDScript `enum` + `match` 实现，7 条合法转换，非法转换返回 `false` 并 `push_warning()`。纯逻辑，无场景树依赖。

没有这个系统，任何代码都可以在任何时候修改游戏状态——暂停中还能发兵、胜利画面后还能操作。

## Player Fantasy

GameState 管理器是纯基础设施系统，玩家不直接感知。其价值体现在游戏流程的清晰性和一致性——"标题→开战→暂停→胜负→重来"的循环始终可靠。玩家感受到的是"游戏知道我现在在哪个阶段"，而不是状态机本身。

## Detailed Design

### Core Rules

**规则 1: GameState 是 `current_state` 的唯一持有者**

`current_state` 对外只读（getter），唯一写入路径是 `transition_to()`。禁止外部直接赋值。

**规则 2: 状态转换必须通过验证**

`transition_to(new_state)` 检查转换矩阵，合法则执行并广播，非法则 `push_warning()` + 返回 `false`。调用方检查返回值决定后续行为。

**规则 3: 每次合法转换自动广播**

`EventBus.game_state_changed.emit(old_state, new_state)` — 所有订阅系统（UI、回合管理器等）在 callback 中响应。

**规则 4: 提供快捷状态查询**

- `is_playing() -> bool`: `current_state == State.PLAYING`
- `is_game_over() -> bool`: `current_state in [State.VICTORY, State.DEFEAT]`

### States and Transitions

**5 个状态**:

| 状态 | 含义 | 哪些系统运行 |
|------|------|------------|
| `TITLE` | 标题画面 | 菜单系统 |
| `PLAYING` | 游戏中 | 全部游戏系统（星球、兵种、出征、AI、国王） |
| `PAUSED` | 暂停 | 全部游戏系统暂停，暂停菜单显示 |
| `VICTORY` | 玩家胜利 | 胜利画面 |
| `DEFEAT` | 玩家失败 | 失败画面 |

**7 条合法转换**:

| # | 从 | 到 | 触发者 | 触发条件 |
|---|----|----|--------|---------|
| 1 | TITLE | PLAYING | 菜单 UI | 玩家点击"开始游戏" |
| 2 | PLAYING | PAUSED | 回合控制 UI | 玩家按 ESC 或点击暂停 |
| 3 | PAUSED | PLAYING | 暂停菜单 UI | 玩家点击"继续" |
| 4 | PLAYING | VICTORY | 胜负条件 | `check_victory() == true` |
| 5 | PLAYING | DEFEAT | 胜负条件 | `check_defeat() == true` |
| 6 | VICTORY | TITLE | 胜利画面 UI | 玩家点击"返回标题" |
| 7 | DEFEAT | TITLE | 失败画面 UI | 玩家点击"返回标题" |

**转换矩阵（完整）**:

| 从 \ 到 | TITLE | PLAYING | PAUSED | VICTORY | DEFEAT |
|---------|-------|---------|--------|---------|--------|
| TITLE   | —     | ✅      | ❌     | ❌      | ❌     |
| PLAYING | ❌    | —       | ✅     | ✅      | ✅     |
| PAUSED  | ❌    | ✅      | —      | ❌      | ❌     |
| VICTORY | ✅    | ❌      | ❌     | —       | ❌     |
| DEFEAT  | ✅    | ❌      | ❌     | ❌      | —      |

**转换约束**:
- 不可从 TITLE 直接跳到 VICTORY/DEFEAT（必须先进入 PLAYING）
- 不可从 PAUSED 直接跳到 VICTORY/DEFEAT（必须先回到 PLAYING）
- 不可从 VICTORY/DEFEAT 回到 PLAYING（只能回 TITLE 开始新游戏）
- 非法转换不抛异常，返回 `false` + `push_warning()`，便于开发阶段排查

### Interactions with Other Systems

| 系统 | 关系 | 内容 |
|------|------|------|
| 事件总线 | 下游（发送） | `game_state_changed(old, new)` — 每次合法转换后发送 |
| 回合管理器 | 被查询 | 部署阶段前检查 `is_playing()`；接收 `end_turn()` 后可能触发 VICTORY/DEFEAT |
| 回合控制 UI | 订阅 | 监听 `game_state_changed` 更新按钮状态（如 PLAYING 外禁用"结束回合"） |
| 星图 UI | 订阅 | 监听 `game_state_changed` — TITLE/PAUSED 时隐藏，PLAYING 时显示 |
| 国王 UI | 订阅 | 同上，根据状态显示/隐藏 |
| 胜负条件 | 调用方 | 调用 `transition_to(VICTORY)` 或 `transition_to(DEFEAT)` |
| 菜单 UI | 调用方 | 调用 `transition_to(PLAYING)` 开始游戏 |

**数据流**: 单向 — 外部调用 `transition_to()` → GameState 验证 → EventBus 广播 → 订阅系统响应。

## Formulas

不适用 — GameState 管理器不含计算或公式。状态转换是布尔逻辑，不是数学公式。

## Edge Cases

- **非法转换请求**: `transition_to()` 返回 `false`，`push_warning()` 输出 "Invalid transition: [from] → [to]"。当前状态不变。调用方应检查返回值并忽略或提示用户。
- **快速连续调用 `transition_to()`**: 每次调用独立验证当前状态。例如 `transition_to(PAUSED)` 立即 `transition_to(PLAYING)` — 只要 PAUSED→PLAYING 合法即可通过。无冷却时间，不排队。
- **在 VICTORY/DEFEAT 状态下收到 `end_turn()`**: 回合管理器应检查 `GameState.is_playing()` 并拒绝执行。如果回合管理器未检查，GameState 不负责阻止——这是回合管理器的职责。
- **在 PLAYING 之外的状态收到部署指令**: 出征系统应检查 `GameState.is_playing()` 并拒绝 `submit_command()`。GameState 不主动拒绝——各系统自行 gate。
- **从 TITLE 重新进入 PLAYING（二周目）**: `VICTORY→TITLE→PLAYING` 路径畅通。回合计数器和星球数据由回合管理器和星球系统各自重置，GameState 不参与。

## Dependencies

**上游（本系统依赖）**:
- 事件总线 (Hard): 需要 `EventBus.game_state_changed` 广播状态转换

**下游（依赖本系统的系统）**:

| 系统 | 类型 | 说明 |
|------|------|------|
| 回合管理器 | Hard (查询) | 部署阶段和结算前 gate `is_playing()` |
| 回合控制 UI | Hard (订阅) | 监听状态变化更新按钮 |
| 星图 UI | Hard (订阅) | 根据状态显示/隐藏游戏画面 |
| 出征 UI | Hard (查询) | 部署前 gate `is_playing()` |
| 国王 UI | Hard (订阅) | 根据状态显示/隐藏 |
| 战斗动画 | Hard (订阅) | 根据状态播放/停止 |
| 胜负条件 | Hard (调用) | 调用 `transition_to(VICTORY/DEFEAT)` |
| 国王系统 | Hard (调用) | 国王去世时调用 `transition_to(PAUSED)`，继位后调用 `transition_to(PLAYING)` |

全部为 Hard — 没有 GameState，所有系统不知道"游戏现在在哪个阶段"。

## Tuning Knobs

无可调参数。状态集和转换矩阵是设计时决定的架构约束。

## Visual/Audio Requirements

不适用 — GameState 管理器无视觉或音频输出。

## UI Requirements

不适用 — GameState 管理器无用户界面。其状态变化驱动 UI 切换，但 UI 由各 UI 系统自行管理。

## Acceptance Criteria

- **GIVEN** 初始状态为 TITLE，**WHEN** `transition_to(PLAYING)`，**THEN** 返回 `true`，`current_state == PLAYING`，`EventBus.game_state_changed` 被 emit 且参数为 `(TITLE, PLAYING)`
- **GIVEN** 当前状态为 PLAYING，**WHEN** `transition_to(VICTORY)`，**THEN** 返回 `true`，`is_game_over() == true`
- **GIVEN** 当前状态为 TITLE，**WHEN** `transition_to(VICTORY)`，**THEN** 返回 `false`，`current_state` 仍为 TITLE，`push_warning()` 被调用
- **GIVEN** 当前状态为 PLAYING，**WHEN** `transition_to(TITLE)`，**THEN** 返回 `false`（玩到一半不能直接回标题）
- **GIVEN** 当前状态为 PAUSED，**WHEN** `is_playing()`，**THEN** 返回 `false`
- **GIVEN** 当前状态为 VICTORY，**WHEN** `is_game_over()`，**THEN** 返回 `true`
- **GIVEN** 任意代码直接赋值 `GameState.current_state = VICTORY`，**WHEN** 编译/运行，**THEN** 报错（getter 无 setter）
- **GIVEN** 7 条合法转换分别调用 `transition_to()`，**WHEN** 逐个执行，**THEN** 全部返回 `true`

## Open Questions

无 — MVP 范围完整覆盖。延后：
- LOADING 状态（从标题到游戏中需要加载关卡资源）→ Vertical Slice 考虑
- 状态进入/退出动画过渡（如淡入淡出）→ Presentation 层的转场系统负责，不由 GameState 管理
