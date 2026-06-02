# Story 002: 回合管线集成 + GameState + EventBus 连接

> **Epic**: 胜负条件 (win-conditions)
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Estimate**: 0.5h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/win-conditions.md`
**Requirement**: `TR-WIN-003`

**ADR Governing Implementation**: ADR-0004: check() 在 CLEANUP 步骤 5 生产后、国王消耗前执行
**ADR Decision Summary**: TurnManager._cleanup() 中调用 ProductionSystem.apply_turn() → WinCondition.check() → KingSystem.consume_turn() → EventBus.turn_ended.emit()。此顺序确保生产完成后判胜负，VICTORY/DEFEAT 状态下跳过国王消耗。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: 集成代码在 TurnManager 中添加 2 行调用。WinCondition 实例作为 TurnManager 成员。

**Control Manifest Rules (this layer)**:
- Required: check() 在生产后、国王消耗前执行 — 顺序保证：先判胜负再消耗寿命 — source: ADR-0004
- Required: 触发时调用 GameState.transition_to(VICTORY/DEFEAT) — source: ADR-0003

---

## Acceptance Criteria

*From GDD `design/gdd/win-conditions.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN 回合结算进入 CLEANUP，WHEN `_cleanup()` 执行，THEN `WinCondition.check()` 在 `ProductionSystem.apply_turn()` 之后被调用
- [ ] **AC-2**: GIVEN `WinCondition.check()` 触发 VICTORY，WHEN 后续 `KingSystem.consume_turn()` 执行，THEN `consume_turn()` 被跳过（GameState 已非 PLAYING）
- [ ] **AC-3**: GIVEN 正常回合（双方都有星），WHEN `_cleanup()` 完成，THEN 正常流程：生产→判胜负→国王→turn_ended
- [ ] **AC-4**: GIVEN check() 触发 VICTORY/DEFEAT，WHEN 后续回合的 `end_turn()` 被调用，THEN 返回 false + push_warning()

---

## Implementation Notes

*Derived from ADR-0004 and GDD win-conditions.md:*

### TurnManager 集成点

```gdscript
# turn_manager.gd — 修改 _cleanup() 方法

var _win_condition: WinCondition = WinCondition.new()

func _cleanup() -> void:
    current_phase = TurnPhase.CLEANUP
    
    # 1. 生产
    ProductionSystem.apply_turn()
    
    # 2. 胜负判定（在生产后、国王消耗前）
    _win_condition.check(PlanetSystem, GameState)
    
    # 3. 国王寿命消耗
    # 注意：若步骤 2 触发 VICTORY/DEFEAT，KingSystem.consume_turn()
    # 内部检查 GameState.is_playing() 返回 false，自行跳过
    KingSystem.consume_turn()
    
    # 4. 回合结束广播
    EventBus.turn_ended.emit(turn_number)
```

### 防御性 gate

```gdscript
# in TurnManager.end_turn():
func end_turn() -> bool:
    if current_phase != TurnPhase.DEPLOYMENT:
        push_warning("end_turn: not in DEPLOYMENT phase")
        return false
    if not GameState.is_playing():
        push_warning("end_turn: game is not in PLAYING state")
        return false
    _execute_turn()
    return true
```

### 关键实现要点

- `_win_condition` 作为 TurnManager 成员 — 每个会话创建一次
- 调用顺序严格：`apply_turn()` → `check()` → `consume_turn()` → `turn_ended.emit()`
- 若 `check()` 触发 VICTORY/DEFEAT，`GameState.is_playing()` 变为 false：
  - `KingSystem.consume_turn()` 内部检查 `is_playing()` gate，自行 return
  - 下一回合 `end_turn()` 检查 `is_playing()` gate，拒绝执行
- 本 Story 不需要修改 WinCondition 核心逻辑（story-001 已完成）
- `end_turn()` 返回值 bool — 供 UI 判断操作是否成功

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: check_victory/check_defeat/check 核心逻辑
- VICTORY/DEFEAT UI overlay（star-map-ui 处理）
- 国王系统 consume_turn 实现

---

## QA Test Cases

*Derived from GDD acceptance criteria.*

- **AC-1**: 调用顺序验证
  - Given: mock 生产系统记录调用, mock 胜负系统记录调用
  - When: _cleanup() 执行
  - Then: 生产先于胜负被调用（可通过调用序列数组验证）

- **AC-2**: VICTORY 后跳过国王
  - Given: check() 触发 VICTORY
  - When: _cleanup() 继续执行
  - Then: KingSystem.consume_turn() 内部 gate 返回（不修改状态）

- **AC-3**: 正常回合完整流程
  - Given: 双方都有星
  - When: _cleanup() 完成
  - Then: 4 步全部执行（生产→判胜负→国王→turn_ended），turn_ended emit

- **AC-4**: 结束后拒绝新回合
  - Given: GameState == VICTORY
  - When: call end_turn()
  - Then: returns false + push_warning

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- Integration: `tests/integration/win-conditions/turn_integration_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (WinCondition.check() 核心逻辑) — must be DONE
- Depends on: Foundation turn-manager (TurnManager._cleanup() 步骤 5) — must be DONE
- Depends on: Foundation gamestate-manager (is_playing() gate) — must be DONE
- Depends on: Core production-system (apply_turn()) — must be DONE
- Depends on: Core king-system (consume_turn()) — must be DONE
- Unlocks: star-map-ui (game_ended 信号驱动胜利/失败 overlay)
