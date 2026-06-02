# 事件总线 (Event Bus)

> **Status**: In Design
> **Author**: Claude + 老大
> **Last Updated**: 2026-05-31
> **Implements Pillar**: 间接 — 纯基础设施，所有跨系统通信的基础

## Overview

事件总线是星辰之轭所有跨系统通信的**唯一通道**。它通过 `EventBus` autoload 集中管理全部 Signal——系统之间不直接持有对方引用，所有通知（星球沦陷、回合结束、国王去世、战斗完成）统一走 EventBus 发送和订阅。

架构遵循 [ADR-0001](../docs/architecture/adr/adr-0001-event-bus-architecture.md)：使用 Godot 原生 Signal（非字符串分发），Signal 定义集中在 `event_bus.gd` 一个文件。发送方 `EventBus.signal_name.emit()`，订阅方 `EventBus.signal_name.connect()`。编译期类型安全，全局可追踪。

没有事件总线，19 个系统会通过互相持有引用形成蜘蛛网耦合——调试一个"回合结束"事件需要追踪 8+ 个文件。

## Player Fantasy

事件总线是纯基础设施系统，玩家不直接感知。其价值体现在系统间通信的可靠性和一致性中。玩家感受到的是"回合结束→兵力同时移动→星球同时变色"的流畅反馈，而不是事件分发本身。

## Detailed Design

### Core Rules

**规则 1: EventBus 是唯一跨系统通信通道**

系统间禁止直接 connect：`PlanetSystem.signal.connect()` ❌。所有跨系统通知必须走 `EventBus.signal.connect()`。系统内部通信（同一系统内的信号）不受此限。

**规则 2: Signal 命名规范**

| 规则 | 示例 |
|------|------|
| Signal 名: `snake_case` 过去时或状态描述 | `planet_owner_changed`, `turn_ended` |
| 参数顺序: 主体 ID → 旧值 → 新值 | `(planet_id, old_owner, new_owner)` |
| 无 payload 通知: 动词过去式 | `planets_initialized`, `execution_phase_started` |
| 新增 Signal 只能追加到 EventBus 文件末尾 | 不可删除或重命名已有 Signal 名 |

**规则 3: 完整 Signal 目录**

| Signal | Payload | 发送方 | 订阅方 | 触发时机 |
|--------|---------|--------|--------|---------|
| `planet_garrison_changed` | `(planet_id: int, old: int, new: int)` | 星球系统 | 星图 UI | 驻兵数量变化 |
| `planet_owner_changed` | `(planet_id: int, old: Faction, new: Faction)` | 星球系统 | 星图 UI, 胜负条件 | 星球易主 |
| `planets_initialized` | `()` | 星球系统 | 星图 UI, AI 敌人 | 关卡加载后星球就绪 |
| `turn_ended` | `(turn_number: int)` | 回合管理器 | 星图 UI, 国王 UI, 回合控制 UI | 回合结算全部完成 |
| `execution_phase_started` | `()` | 回合管理器 | 战斗动画 | 开始执行所有出征指令 |
| `deployment_phase_started` | `()` | 回合管理器 | 星图 UI, 出征 UI | 新回合开始，接受玩家操作 |
| `battle_resolved` | `(planet_id: int, result: BattleResult)` | 战斗结算 | 占领系统, 战斗动画 | 单场战斗计算完成 |
| `deployment_executed` | `(from: int, to: int, count: int)` | 出征系统 | 战斗动画 | 单条出征指令执行 |
| `king_died` | `(king: KingData)` | 国王系统 | 回合管理器, 国王 UI | 国王寿命耗尽 |
| `king_succeeded` | `(old: KingData, new: KingData)` | 国王系统 | 国王 UI | 新国王继位完成 |
| `action_consumed` | `(remaining: int)` | 国王系统 | 国王 UI | 国王行动后剩余次数 |
| `game_state_changed` | `(old: State, new: State)` | GameState 管理器 | 回合管理器, 全部 UI | 全局状态转换 |

**规则 4: 订阅生命周期**

- 长期订阅方（autoload、主场景节点）在 `_ready()` 中 `connect()`，无需手动 `disconnect()`——Godot 在节点释放时自动清理
- 短期订阅方（临时弹窗、确认对话框）必须在销毁时显式 `disconnect()`，避免悬空引用
- EventBus 本身不含业务逻辑——它只转发 Signal，不修改 payload，不判断订阅方身份
- 不允许在 EventBus 的 callback 中再次 emit 同一个 Signal（防止无限递归）

### States and Transitions

不适用 — EventBus 是纯转发层，无状态。它不记录任何事件历史，不缓存，不排队。

### Interactions with Other Systems

EventBus 本身不主动与任何系统交互——它是被动转发。所有关系为单向：系统 → EventBus（发送）或 EventBus → 系统（订阅回调）。

| 系统 | 关系 | 使用的 Signal |
|------|------|-------------|
| 数据定义 | 依赖（类型引用） | 无 — 只引用 `Faction`, `BattleResult`, `KingData`, `GameState.State` 类型 |
| 星球系统 | 发送方 | `planet_garrison_changed`, `planet_owner_changed`, `planets_initialized` |
| 回合管理器 | 发送方 + 订阅方 | 发送: `turn_ended`, `execution_phase_started`, `deployment_phase_started` / 订阅: `game_state_changed`, `king_died` |
| 战斗结算 | 发送方 | `battle_resolved` |
| 出征系统 | 发送方 | `deployment_executed` |
| 国王系统 | 发送方 | `king_died`, `king_succeeded`, `action_consumed` |
| GameState | 发送方 | `game_state_changed` |
| 星图 UI | 订阅方 | `planet_garrison_changed`, `planet_owner_changed`, `planets_initialized`, `turn_ended`, `deployment_phase_started`, `game_state_changed` |
| 出征 UI | 订阅方 | `deployment_phase_started` |
| 回合控制 UI | 订阅方 | `turn_ended`, `game_state_changed` |
| 国王 UI | 订阅方 | `king_died`, `king_succeeded`, `action_consumed`, `turn_ended` |
| 战斗动画 | 订阅方 | `execution_phase_started`, `battle_resolved`, `deployment_executed` |
| 占领系统 | 订阅方 | `battle_resolved` |
| 胜负条件 | 订阅方 | `planet_owner_changed` |
| AI 敌人 | 订阅方 | `planets_initialized` |

## Formulas

不适用 — 事件总线不含计算或公式。

## Edge Cases

- **若 Signal 回调中再次 emit 同一 Signal**: EventBus 检测递归并 `push_error()` + 阻止第二次 emit。防止 `turn_ended` → callback → `turn_ended` 无限循环。
- **若订阅方在回调中 disconnect 自己**: 安全 — Godot Signal 的 `emit()` 遍历订阅列表的快照，回调中 disconnect 不影响当前遍历。
- **若新增 Signal 名与已有 Signal 冲突**: code review 阶段拒绝。Signal 名以主体前缀命名（`planet_xxx`, `king_xxx`），主体不同不会命名冲突。
- **若发送方在 EventBus 未就绪时 emit**: EventBus 设为 autoload 第一位，在其他系统初始化前已就绪。不会出现此情况。
- **若订阅方忘记 disconnect 短期连接**: 临时 UI 销毁时若仍保持连接，Godot 在后续 callback 调用时检测到已释放对象并报错。缓解：短期订阅方必须在 `_exit_tree()` 或销毁前显式 `disconnect()`。
- **Signal 参数类型变更**: 破坏性变更 — 所有订阅方需同步修改函数签名。ADR-0001 规定 Signal 参数只增不减，已有参数类型不可变。

## Dependencies

**上游（本系统依赖）**:
- 数据定义 (Soft): 仅引用类型定义（`Faction`, `BattleResult`, `KingData`, `GameState.State`），不调用其方法

**下游（依赖本系统的系统）**:

| 系统 | 类型 | 说明 |
|------|------|------|
| 星球系统 | Hard (发送) | 通过 EventBus 广播 garrison/owner 变更 |
| 回合管理器 | Hard (发送+订阅) | 广播阶段切换，订阅状态变更和国王去世 |
| 战斗结算 | Hard (发送) | 广播战斗结果 |
| 出征系统 | Hard (发送) | 广播出征执行 |
| 国王系统 | Hard (发送) | 广播去世/继位/行动消耗 |
| GameState | Hard (发送) | 广播状态转换 |
| 全部 UI (×5) | Hard (订阅) | 监听变化以刷新显示 |
| 占领系统 | Hard (订阅) | 监听战斗结果以判断占领 |
| 胜负条件 | Hard (订阅) | 监听星球易主以判定胜负 |
| AI 敌人 | Hard (订阅) | 监听星球初始化以启动 AI |

全部为 Hard 依赖 — 没有 EventBus，任何跨系统通信都无法进行。

## Tuning Knobs

事件总线无可调参数。Signal 列表和命名规范是设计时决定的架构约束，不是运行时调整的数值。

## Visual/Audio Requirements

不适用 — 事件总线无视觉或音频输出。

## UI Requirements

不适用 — 事件总线无用户界面。

## Acceptance Criteria

- **GIVEN** 游戏启动，**WHEN** EventBus autoload 就绪，**THEN** `EventBus.planet_owner_changed.connect(callback)` 可正常调用不报错
- **GIVEN** 星球系统调用 `EventBus.planet_owner_changed.emit(1, PLAYER, ENEMY)`，**WHEN** 星图 UI 已 connect 该 Signal，**THEN** 星图 UI callback 被调用，参数为 `(1, PLAYER, ENEMY)`
- **GIVEN** 任意系统 `.gd` 文件，**WHEN** 搜索 `[SystemName].[signal_name].connect(` 模式（跨系统直连），**THEN** 无匹配结果
- **GIVEN** `event_bus.gd` 文件，**WHEN** 统计 `signal` 声明数，**THEN** ≥ 12 个（与 Signal 目录一致）
- **GIVEN** Signal callback 中再次 emit 同一 Signal，**WHEN** EventBus 检测递归，**THEN** `push_error()` 触发 + 第二次 emit 被阻止
- **GIVEN** 两个独立系统 A 和 B，**WHEN** A 发送事件、B 接收事件，**THEN** A 不持有 B 的引用（B 只 connect EventBus）
- **GIVEN** EventBus 中任意 Signal，**WHEN** 检查其参数类型，**THEN** 所有类型来自 DataDef（`Faction`, `KingData`, `BattleResult`, `GameState.State`），无裸 `String`/`int` 做系统类型

## Open Questions

无 — MVP 范围的 12 个 Signal 已完整覆盖。以下延后：
- 是否需要调试模式（每个 emit 自动 print signal 名 + payload）？→ 实现时加 `DEBUG` 条件编译
- 是否需要事件历史记录（用于 replay/debug）？→ Vertical Slice 考虑
