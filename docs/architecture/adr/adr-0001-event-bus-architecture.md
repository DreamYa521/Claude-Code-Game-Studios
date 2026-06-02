# ADR-0001: 事件总线架构

## Status
Accepted

## Date
2026-05-31

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core (事件通信) |
| **Knowledge Risk** | LOW — GDScript Signal 在 4.3→4.6 无破坏性变更 |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md`, `docs/engine-reference/godot/current-best-practices.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | None |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None |
| **Enables** | ADR-0002 (数据定义格式), ADR-0003 (GameState 状态机), ADR-0004 (回合结算模型) |
| **Blocks** | 全部 19 个系统的 GDD — 事件命名规范必须先定 |
| **Ordering Note** | 必须在 ADR-0002/0003/0004 之前创建 |

## Context

### Problem Statement

星辰之轭有 19 个系统分布在 4 层架构中。系统间需要通信（星球沦陷→UI刷新、国王去世→回合暂停、战斗结束→占领判定、回合结束→生产触发），但必须保持解耦——系统不能直接持有其他系统的引用。

需要决定：跨系统通信的统一模式。

### Constraints

- 必须是 Godot 原生机制，不引入第三方依赖
- 必须支持 19 个系统间的任意通信（Foundation→Core→Feature→Presentation）
- 回合制游戏，无实时性能压力（每秒事件量 < 100）
- 发送者不感知订阅者（fire-and-forget）
- 必须可以在单一位置追踪全部事件流（调试需求）
- 必须保留 GDScript 类型安全

### Requirements

- 一个文件即可查看所有系统间事件
- 新系统接入时不需要修改已有系统代码
- 事件可被多个订阅者同时监听
- 编译期参数类型检查

## Decision

**使用集中式 EventBus autoload，基于 Godot 原生 Signal。**

创建一个 `EventBus` autoload 单例，将所有跨系统 Signal 集中定义在此文件中。
各系统通过 `EventBus.signal_name.emit()` 发送事件，通过 `EventBus.signal_name.connect()` 订阅事件。

系统之间不直接持有对方引用——所有通信走 EventBus。

### Architecture Diagram

```
发送方（任意系统）                  订阅方（任意系统）
┌──────────────┐                  ┌──────────────┐
│ PlanetSystem │                  │  StarMapUI   │
│              │                  │              │
│ set_owner()  │                  │ _ready():    │
│   ↓          │                  │  EventBus.   │
│ EventBus.    │                  │  owner_changed│
│ owner_changed│                  │  .connect()  │
│ .emit()      │                  │              │
└──────┬───────┘                  └──────▲───────┘
       │                                 │
       │    ┌──────────────────┐         │
       └───→│    EventBus      │─────────┘
            │  (autoload)      │
            │                  │
            │ signal owner_    │
            │ changed(...)     │
            │ signal turn_     │
            │ ended(...)       │
            │ signal king_     │
            │ died(...)        │
            │ ...              │
            └──────────────────┘
                     ↑
            ┌────────┴────────┐
            │  任何系统都可订阅  │
            │  任何系统都可发送  │
            └─────────────────┘
```

### Key Interfaces

```gdscript
# event_bus.gd — autoload: EventBus
extends Node

## 星球事件
signal planet_garrison_changed(planet_id: int, old_count: int, new_count: int)
signal planet_owner_changed(planet_id: int, old_owner: Faction, new_owner: Faction)
signal planets_initialized()

## 回合事件
signal turn_ended(turn_number: int)
signal execution_phase_started()
signal deployment_phase_started()

## 战斗事件
signal battle_resolved(planet_id: int, result: BattleResult)
signal deployment_executed(from_planet: int, to_planet: int, count: int)

## 国王事件
signal king_died(king: KingData)
signal king_succeeded(old_king: KingData, new_king: KingData)
signal action_consumed(remaining_actions: int)

## 游戏状态事件
signal game_state_changed(old_state: GameState, new_state: GameState)
```

**使用示例**:

```gdscript
# 发送方 — planet_system.gd
func set_owner(id: int, new_owner: Faction) -> void:
    var old = planets[id].owner
    planets[id].owner = new_owner
    EventBus.planet_owner_changed.emit(id, old, new_owner)

# 订阅方 — star_map_ui.gd
func _ready() -> void:
    EventBus.planet_owner_changed.connect(_on_owner_changed)
    EventBus.turn_ended.connect(_on_turn_ended)

func _on_owner_changed(planet_id: int, old_owner: Faction, new_owner: Faction) -> void:
    refresh_planet_color(planet_id, new_owner)
```

### 命名规范

| 规则 | 示例 |
|------|------|
| Signal 名: `snake_case` 过去时或状态描述 | `planet_owner_changed`, `turn_ended` |
| 参数顺序: 主体 → 旧值 → 新值 | `(planet_id, old_owner, new_owner)` |
| 无 payload 通知: 动词过去式 | `planets_initialized`, `execution_phase_started` |
| 新增 Signal 只能追加到 EventBus，不可删除或重命名已有 Signal | — |

## Alternatives Considered

### Alternative 1: 分散式 Signal（每个系统暴露自己的 Signal）

- **Description**: 每个 autoload 系统定义自己的 signal，订阅方直接 `SystemName.signal.connect()`
- **Pros**: 每个系统的 signal 紧邻其逻辑，符合"就近原则"
- **Cons**: 订阅方需要持有发送方引用（耦合）；信号散落 19 个文件，全局事件流不可见；新系统接入需要 import 多个 autoload
- **Rejection Reason**: 19 系统规模下，分散式 Signal 导致蜘蛛网耦合。调试回合结算时需要在 8+ 个文件中追踪事件链。集中式 EventBus 的全局可见性收益远大于"就近原则"损失。

### Alternative 2: 自定义事件系统（字符串分发 + Dictionary）

- **Description**: `EventBus.emit("planet_owner_changed", {id: 1, old: 0, new: 1})`，字符串匹配订阅
- **Pros**: 完全动态，运行时可增删事件类型
- **Cons**: 零编译期类型检查；payload 是 Variant/Dictionary，参数拼写错误运行时才报；非 Godot 习惯，每个新开发者都要学一套
- **Rejection Reason**: 牺牲了 GDScript Signal 的类型安全。Godot 原生 Signal 已满足需求，没必要再造轮子。

### Alternative 3: 混合模式（高频走直接 Signal，通知走 EventBus）

- **Description**: 需要每帧调用的路径（如战斗动画更新）直连系统，其他走 EventBus
- **Pros**: 兼顾性能和可追踪性
- **Cons**: 两套规则，新人困惑"这个事件该走哪条路"
- **Rejection Reason**: 回合制游戏无高频路径。所有事件都在回合粒度（秒级）触发，不需要区分"高频"和"低频"。混合模式增加认知负担但无收益。

## Consequences

### Positive

- **全局可见**: 一个文件看完全部跨系统事件，新成员 5 分钟理解系统间通信
- **零耦合**: 系统只依赖 `EventBus`，不持有其他系统引用。单元测试可独立运行
- **调试友好**: 在 EventBus 加 `print()` 即可追踪所有事件流，不需要在 19 个文件里找 connect
- **类型安全保留**: 仍是 Godot 原生 Signal，参数类型编译期检查
- **可扩展**: 新增系统只需追加 signal 到 EventBus + connect 即可，不修改已有代码

### Negative

- **EventBus 文件较长**: 随着系统增加，`event_bus.gd` 会累积大量 signal 声明。缓解：signal 只是声明不含逻辑，用注释分区（`## 星球事件`, `## 回合事件` 等）
- **Signal 与逻辑分离**: 一个系统的 signal 定义在 EventBus 而非该系统文件中，查找时需要跨文件。缓解：系统 GDD 中写明"本系统发送的 Signal: 见 EventBus.xxx"
- **不能强制"谁可以发"**: 任何系统都能 emit 任何 EventBus signal，没有编译期"仅 PlanetSystem 可发 owner_changed"的约束。缓解：命名规范 + code review 执行

### Risks

- **命名冲突**: 两个系统可能想要同名 signal。缓解：Signal 以主体命名（`planet_owner_changed` 而非 `owner_changed`），code review 时检查
- **EventBus 成瓶颈**: 如果未来有高频事件需求，所有事件走 EventBus 可能不够。缓解：当前回合制无此风险；若未来需要，可在 EventBus 中分离"高频 channel"和"通知 channel"而不改架构

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| 全部 19 系统 | 系统间解耦通信 | EventBus 集中式 Signal 中转，零直接耦合 |
| 回合管理器 | 回合结束通知所有系统 | `turn_ended` signal，UI + AI + 生产 同时收到 |
| 国王系统 | 国王去世全局通知 | `king_died` signal，回合管理器 + UI 收到 |
| 战斗结算 | 战斗结果通知占领系统 | `battle_resolved` signal，占领系统订阅 |
| 数据定义 | 数据变更不直接通知 | 数据定义不含逻辑，不发送事件（数据被引用，不被订阅） |

## Performance Implications

- **CPU**: 无影响。Signal emit + 回调链是 Godot 原生路径，回合粒度下事件量 < 100/回合
- **Memory**: EventBus 是一个 Node，内存占用 ~1KB
- **Load Time**: autoload 在引擎启动时加载，无额外成本
- **Network**: 不适用（单机游戏）

## Migration Plan

不适用 — 这是新项目，不存在已有代码需要迁移。

## Validation Criteria

- EventBus 在 autoload 列表中注册，游戏启动可用
- 新增一个测试信号 `test_event`，两个独立系统分别 subscribe → emit → 两个回调均触发
- `docs/architecture/architecture.md` 中的 8 个事件名与 EventBus 中的 signal 名一致
- 任意系统文件的 `grep` 中不出现 `PlanetSystem.` 形式的跨系统 connect（只出现 `EventBus.`）

## Related Decisions

- ADR-0002: 数据定义格式 — 事件 payload 中的数据类型由数据定义统一
- ADR-0003: GameState 状态机 — 状态转换通过 EventBus 广播
- ADR-0004: 回合结算模型 — 回合各阶段通过 EventBus 通知
- `docs/architecture/architecture.md` — 架构文档 Phase 3 数据流 5 个场景均使用 EventBus
