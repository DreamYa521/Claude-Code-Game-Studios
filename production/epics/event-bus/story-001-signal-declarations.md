# Story 001: EventBus Core — Signal Declarations & Autoload Setup

> **Epic**: event-bus
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Logic
> **Estimate**: 2h
> **Manifest Version**: 2026-05-31
> **Last Updated**: —

## Context

**GDD**: `design/gdd/event-bus.md`
**Requirement**: TR-EVT-001, TR-EVT-002, TR-EVT-003, TR-EVT-006, TR-EVT-007
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0001: 事件总线架构
**ADR Decision Summary**: 使用集中式 EventBus autoload，基于 Godot 原生 Signal。系统间禁止直接 connect — 全部跨系统通信走 EventBus 中转。12 个 Signal 集中定义在一个文件。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: GDScript Signal 在 4.3→4.6 无破坏性变更。使用 Godot 原生 Signal（非字符串分发），编译期参数类型检查。

**Control Manifest Rules (this layer)**:
- Required: EventBus autoload 集中管理全部跨系统 Signal，系统间禁止直接 connect
- Required: 12 个 Signal 目录全部声明，不可遗漏
- Required: Signal 命名 snake_case 过去时，参数顺序主体ID→旧值→新值，新增只追加不删除不重命名
- Required: Signal 参数类型全部来自 DataDef，无裸 String/int
- Required: EventBus 设为 autoload 第一位（与 DataDef 同为最高优先级），不含业务逻辑
- Forbidden: 禁止跨系统直接 connect（`PlanetSystem.signal.connect()` ❌）
- Forbidden: 禁止使用字符串分发事件
- Forbidden: 禁止修改已有 Signal 名或参数类型
- Guardrail: Signal emit + 回调链，回合粒度下事件量 < 100/回合，无性能压力

---

## Acceptance Criteria

*From GDD `design/gdd/event-bus.md`, scoped to this story:*

- [ ] **AC-1**: 游戏启动，EventBus autoload 就绪，`EventBus.planet_owner_changed.connect(callback)` 可正常调用不报错
- [ ] **AC-2**: `event_bus.gd` 文件统计 `signal` 声明数 ≥ 12 个（与 Signal 目录一致）
- [ ] **AC-3**: EventBus 中任意 Signal 检查参数类型，所有类型来自 DataDef（`Faction`, `KingData`, `BattleResult`, `GameState.State`），无裸 `String`/`int` 做系统类型
- [ ] **AC-4**: Signal 命名符合 snake_case 过去时规范，参数顺序符合主体→旧值→新值

---

## Implementation Notes

*Derived from ADR-0001:*

**1. 创建 `event_bus.gd` — autoload: EventBus**:

```gdscript
# event_bus.gd — autoload: EventBus
extends Node

## ============================================================================
## 星球事件
## ============================================================================
signal planet_garrison_changed(planet_id: int, old_count: int, new_count: int)
signal planet_owner_changed(planet_id: int, old_owner: DataDef.Faction, new_owner: DataDef.Faction)
signal planets_initialized()

## ============================================================================
## 回合事件
## ============================================================================
signal turn_ended(turn_number: int)
signal execution_phase_started()
signal deployment_phase_started()

## ============================================================================
## 战斗事件
## ============================================================================
signal battle_resolved(planet_id: int, result: BattleResult)
signal deployment_executed(from_planet: int, to_planet: int, count: int)

## ============================================================================
## 国王事件
## ============================================================================
signal king_died(king: KingData)
signal king_succeeded(old_king: KingData, new_king: KingData)
signal action_consumed(remaining_actions: int)

## ============================================================================
## 游戏状态事件
## ============================================================================
signal game_state_changed(old_state: GameState.State, new_state: GameState.State)
```

**2. 12 个 Signal 分类**:
- 星球事件（3）: `planet_garrison_changed`, `planet_owner_changed`, `planets_initialized`
- 回合事件（3）: `turn_ended`, `execution_phase_started`, `deployment_phase_started`
- 战斗事件（2）: `battle_resolved`, `deployment_executed`
- 国王事件（3）: `king_died`, `king_succeeded`, `action_consumed`
- 游戏状态事件（1）: `game_state_changed`

**3. 信号命名规范**:
- Signal 名: `snake_case` 过去时或状态描述（`planet_owner_changed`, `turn_ended`）
- 参数顺序: 主体 ID → 旧值 → 新值（如 `(planet_id, old_owner, new_owner)`）
- 无 payload 通知: 动词过去式（`planets_initialized`, `execution_phase_started`）
- 新增 Signal 只能追加到文件末尾，不可删除或重命名已有 Signal

**4. 类型引用约定**:
- `DataDef.Faction` — EventBus 依赖 DataDef 的类型定义（Soft 依赖）
- `BattleResult` — 由战斗结算系统定义（先声明 class_name，再在 EventBus 中引用）
- `KingData` — 由国王系统定义
- `GameState.State` — 由 GameState 管理器定义

**处理前向引用**: 对于尚未实现的类型（`BattleResult`, `KingData`, `GameState.State`），有两种方案：
- 方案 A（推荐）: Signal 先声明为无类型参数，在对应系统实现后再加类型注解 — Godot Signal 允许无类型声明
- 方案 B: 提前创建类型占位文件（如 `battle_result.gd` 只含 `class_name BattleResult extends RefCounted`）

选择方案 A 以避免 Story 间强依赖链。在每个系统的 Story 中明确标注"实现后更新 EventBus 中的 Signal 类型"。

**实际上**: 由于 4 个 Foundation Story 在本轮对话同时创建，建议在 GameState 实现后立即为 `game_state_changed` 加类型。对于 Core 层的类型（`BattleResult`, `KingData`），先用无类型参数，在对应 Story 中标注回填类型。

**5. autoload 注册**:
- 在 Project Settings → Autoload 中注册 `event_bus.gd`，名称 `EventBus`
- 与 DataDef 同为最高优先级（前两位）
- EventBus 不含业务逻辑 — 只声明 Signal，不实现方法

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: 递归 emit 检测 + 订阅生命周期管理规则
- 实际订阅/发送逻辑（属于各消费系统的 Story）
- `BattleResult`/`KingData` 类型定义（属于 Core 层对应 Epic）

---

## QA Test Cases

- **AC-1**: EventBus autoload 可连接性
  - Given: EventBus autoload 已注册，游戏启动
  - When: 在测试脚本中调用 `EventBus.planet_owner_changed.connect(test_callback)`
  - Then: 连接成功，`test_callback` 被添加到 Signal 的订阅列表中；无 runtime error
  - Edge cases: disconnect 后再次 connect → 只触发一次（无重复订阅）

- **AC-2**: 12 个 Signal 声明完整
  - Given: `event_bus.gd` 文件
  - When: 统计 `signal` 关键字声明数
  - Then: ≥ 12 个（planet_garrison_changed, planet_owner_changed, planets_initialized, turn_ended, execution_phase_started, deployment_phase_started, battle_resolved, deployment_executed, king_died, king_succeeded, action_consumed, game_state_changed）
  - Edge cases: Signal 按分区组织（星球/回合/战斗/国王/游戏状态），每个分区有注释分隔

- **AC-3**: Signal 参数类型约束
  - Given: EventBus 中所有 Signal 声明
  - When: 检查每个 Signal 的参数类型标注
  - Then: 所有非基础类型参数引用 DataDef 枚举或明确类型；无 `String`/`int` 做系统标识类型（如 Faction 用 `DataDef.Faction` 不用 `int`）
  - Edge cases: 对于尚未定义的类型（BattleResult, KingData），允许无类型注解但需在注释中标注预期类型

- **AC-4**: Signal 命名规范验证
  - Given: EventBus 中所有 Signal 名
  - When: 逐个检查命名
  - Then: 全部符合 snake_case；通知类 Signal 使用过去时（`_changed`, `_ended`, `_died`, `_resolved`）；参数顺序符合主体→旧值→新值
  - Edge cases: `planets_initialized` 为无参数通知，命名正确（过去分词）

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- Logic: `tests/unit/event-bus/test_signal_declarations.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: DataDef Story 001 (Enums & Constants) — EventBus 引用 `DataDef.Faction` 类型（Soft 依赖，仅类型引用）
- Unlocks: EventBus Story 002 (Safety — Recursion Guard & Lifecycle)、所有下游系统的跨系统通信
