# Story 002: 回合集成 + EventBus + 边界处理

> **Epic**: 国王系统 (king-system)
> **Status**: Ready
> **Layer**: Core
> **Type**: Integration
> **Estimate**: 2h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/king-system.md`
**Requirement**: `TR-KNG-003`, `TR-KNG-007`

**ADR Governing Implementation**: ADR-0008: 国王寿命模型 (CLEANUP 步骤 5 调用 consume_turn); ADR-0004: 回合结算模型 (CLEANUP 步骤 5 顺序); ADR-0001: EventBus (king_died / king_succeeded / action_consumed)
**ADR Decision Summary**: consume_turn() 由 TurnManager 在 CLEANUP 步骤 5 调用。去世流程：emit king_died → GameState→PAUSED → 自动继位 → emit king_succeeded → GameState→PLAYING。action_consumed 每回合 emit。actions_remaining ≤ 3 时 UI 警告。MVP 不做演出动画。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Signal connect 走 EventBus autoload。GameState.transition_to() 为已有 API。

**Control Manifest Rules (this layer)**:
- Required: 国王去世流程 — emit king_died → GameState→PAUSED → 自动继位 → emit king_succeeded → GameState→PLAYING — source: ADR-0008
- Required: 每回合消耗 1 寿命 — consume_turn() 在 CLEANUP 步骤 5 调用 — source: ADR-0008
- Forbidden: 国王寿命耗尽不算输 — 代际传承是机制不是终点 — source: ADR-0008
- Guardrail: KingSystem 字段更新 + 条件检查，不可测量 < 1ms

---

## Acceptance Criteria

*From GDD `design/gdd/king-system.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN TurnManager 进入 CLEANUP 步骤 5，WHEN 执行 cleanup，THEN KingSystem.consume_turn() 被调用 1 次
- [ ] **AC-2**: GIVEN consume_turn() 完成，THEN EventBus.action_consumed.emit(remaining) 被触发（含当前剩余次数）
- [ ] **AC-3**: GIVEN actions_remaining 降到 0，WHEN consume_turn() 返回 DIED，THEN EventBus.king_died.emit(old_king) 被触发
- [ ] **AC-4**: GIVEN king_died 被 emit，THEN GameState.transition_to(PAUSED) 被调用
- [ ] **AC-5**: GIVEN GameState 变为 PAUSED 后，WHEN generate_heir() 完成，THEN EventBus.king_succeeded.emit(old_king, new_king) 被触发
- [ ] **AC-6**: GIVEN king_succeeded 被 emit，THEN GameState.transition_to(PLAYING) 被调用
- [ ] **AC-7**: GIVEN king_succeeded 被 emit，THEN old_king != null（有前任）且 new_king.generation == old_king.generation + 1
- [ ] **AC-8**: GIVEN init_king() 完成（游戏开始时），THEN EventBus.king_succeeded.emit(null, king) 被触发（null 表示初始）
- [ ] **AC-9**: GIVEN actions_remaining() == 3，WHEN UI 查询，THEN 应显示警告状态（不在此 Story 实现 UI，只验证 KingSystem 提供 `is_warning()` 查询接口）
- [ ] **AC-10**: GIVEN lifespan 被配置为 1，WHEN 连续 3 回合，THEN 发生 3 次去世-继位循环，generation 正确递增到 4

---

## Implementation Notes

*Derived from ADR-0001, ADR-0004, ADR-0008:*

### 集成架构

```
TurnManager._cleanup() — 步骤 5:
  → ProductionSystem.apply_turn(planets)
  → WinConditions.check()
  → KingSystem.consume_turn()
    → current_king.actions_used += 1
    → EventBus.action_consumed.emit(remaining)
    → if not is_alive():
        → EventBus.king_died.emit(old_king)
        → GameState.transition_to(PAUSED)
        → KingSystem.generate_heir()
        → EventBus.king_succeeded.emit(old_king, new_king)
        → GameState.transition_to(PLAYING)

游戏初始化时:
  → KingSystem.init_king()
    → EventBus.king_succeeded.emit(null, king)
```

### 关键修改点

**KingSystem (扩展现有)**:
- `consume_turn()` 现在触发 EventBus 和 GameState 过渡
- 新增 `handle_death_and_succession()` — 去世→继位完整流程
- 新增 `is_warning() -> bool` — `actions_remaining() <= 3`
- 新增 `get_warning_threshold() -> int` — 返回 3（可配置）
- `init_king()` 完成后 emit `king_succeeded(null, king)`

**EventBus (新增信号)**:
```gdscript
# event_bus.gd — 追加以下 Signal（仅追加，不删不改）
signal king_died(old_king: KingData)
signal king_succeeded(old_king: KingData, new_king: KingData)
signal action_consumed(remaining: int)
```

**TurnManager (修改)**:
- CLEANUP 步骤 5 添加 `KingSystem.consume_turn()` 调用
- 调用顺序：生产 → 胜负判定 → 国王消耗（符合 ADR-0004 顺序）

### 回合管线 CLEANUP 顺序

```
CLEANUP 步骤 5:
  1. ProductionSystem.apply_turn()     — 所有星球产兵
  2. WinConditions.check()              — 先判胜负
  3. KingSystem.consume_turn()          — 再消耗寿命
     └─ if died → handle_death_and_succession()
```

顺序保证：先判胜负再消耗寿命 — 如果玩家本回合获胜，VICTORY 状态阻止国王继续消耗。

### 关键实现要点

- `consume_turn()` 内部在 `is_alive()==false` 时自动调用 `handle_death_and_succession()`
- `handle_death_and_succession()` 封装的完整流程：emit king_died → PAUSED → generate_heir() → emit king_succeeded → PLAYING
- MVP 无演出 — PAUSED→PLAYING 在同一帧内完成（UI 通过 king_succeeded signal 触发文字提示）
- `action_consumed` 每回合 emit（即使国王去世也先 emit 0）
- Signal 参数全部使用强类型 (`KingData`, `int`)
- EventBus signal 追加到文件末尾，遵循 ADR-0001 "不删除不重命名" 规则

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: KingData 结构、init_king()、consume_turn()、generate_heir() 核心逻辑
- 国王 UI: 常驻面板、寿命条、警告闪烁、去世/继位信息（presentation layer, king-ui）
- TurnManager: CLEANUP 步骤 5 调用 `KingSystem.consume_turn()` 本身（需在 TurnManager 中加一行调用；若 TurnManager 已完成则在本 Story 中追加）
- 胜负条件: `check()` 实现（feature layer）

---

## QA Test Cases

*Integration tests — require EventBus + GameState + TurnManager:*

- **AC-1**: 回合管线触发
  - Given: TurnManager 完成 EXECUTION，进入 CLEANUP
  - When: 步骤 5 执行
  - Then: KingSystem.consume_turn() 被调用，actions_remaining 减少 1

- **AC-2**: EventBus.action_consumed
  - Given: actions_remaining == 25
  - When: consume_turn()
  - Then: EventBus.action_consumed(24) 被 emit

- **AC-3~AC-7**: 去世→继位完整链路
  - Given: actions_remaining == 1, init_king 完成 gen=1
  - When: consume_turn() → remaining=0
  - Then: 
    1. EventBus.king_died(old) emit, old.generation == 1
    2. GameState.current_state == PAUSED
    3. EventBus.king_succeeded(old, new) emit, new.generation == 2
    4. GameState.current_state == PLAYING
    5. new.actions_remaining() == 30

- **AC-8**: 初始国王 signal
  - Given: GameState 初始化
  - When: KingSystem.init_king()
  - Then: EventBus.king_succeeded(null, king) emit, null old_king 表示初始

- **AC-9**: 警告阈值
  - Given: actions_remaining == 3
  - When: KingSystem.is_warning()
  - Then: returns true
  - Given: actions_remaining == 4
  - When: KingSystem.is_warning()
  - Then: returns false

- **AC-10**: 快速连续去世
  - Given: lifespan 设为 1
  - When: 连续 3 回合 consume_turn()
  - Then: generation 递增到 4; 每回合都发生去世→继位

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- Integration: `tests/integration/king-system/king_turn_integration_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (king-core) — must be DONE
- Depends on: Foundation event-bus (TR-EVT-001~004, king_died/king_succeeded/action_consumed signals) — 需在本 Story 追加 3 个 Signal
- Depends on: Foundation gamestate-manager (TR-GSM-003, transition_to) — must be DONE
- Depends on: Core planet-system (TR-PLT-001~006) — 间接依赖（通过 TurnManager）
- Unlocks: 国王 UI (king-ui, presentation layer)
