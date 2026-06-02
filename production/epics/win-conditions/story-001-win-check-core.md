# Story 001: check_victory() + check_defeat() + check() 核心逻辑

> **Epic**: 胜负条件 (win-conditions)
> **Status**: Ready
> **Layer**: Feature
> **Type**: Logic
> **Estimate**: 1h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/win-conditions.md`
**Requirement**: `TR-WIN-001`, `TR-WIN-002`, `TR-WIN-004`, `TR-WIN-005`

**ADR Governing Implementation**: ADR-0003: 触发 GameState.transition_to(VICTORY/DEFEAT)；ADR-0004: 在 CLEANUP 阶段执行检查；ADR-0008: 国王寿命耗尽不算输
**ADR Decision Summary**: check_victory() = 所有 ENEMY 星球被消灭。check_defeat() = 所有 PLAYER 星球丢失。双方同时全灭 → DEFEAT。胜利/失败触发 GameState 转换 + EventBus.game_ended 广播。国王寿命耗尽由国王系统独立处理，不触发胜负。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: 纯逻辑判断，无引擎 API 依赖。依赖 PlanetSystem.get_planets_by_owner() 和 GameState.transition_to()。

**Control Manifest Rules (this layer)**:
- Required: check_victory()：get_planets_by_owner(ENEMY).is_empty() — source: ADR-0003
- Required: check_defeat()：get_planets_by_owner(PLAYER).is_empty() — source: ADR-0003
- Required: 双方同时全灭 → DEFEAT — 平局算玩家输 — source: ADR-0003
- Required: 国王寿命耗尽不算输 — 代际传承是机制不是终点 — source: ADR-0008
- Guardrail: check() 是纯查询操作，不在步骤内修改星球状态

---

## Acceptance Criteria

*From GDD `design/gdd/win-conditions.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN 敌方 0 颗星、玩家 1+ 颗星，WHEN `check()`，THEN `GameState.current_state == VICTORY`
- [ ] **AC-2**: GIVEN 玩家 0 颗星、敌方 1+ 颗星，WHEN `check()`，THEN `GameState.current_state == DEFEAT`
- [ ] **AC-3**: GIVEN 双方都有星球，WHEN `check()`，THEN `GameState.current_state` 不变（仍为 PLAYING）
- [ ] **AC-4**: GIVEN 双方各 0 颗星（所有星球 NEUTRAL），WHEN `check()`，THEN `GameState.current_state == DEFEAT`（平局判负）
- [ ] **AC-5**: GIVEN `check()` 触发 VICTORY，WHEN 检查 EventBus，THEN `game_ended` 被 emit，参数为 `"victory"`
- [ ] **AC-6**: GIVEN VICTORY 状态下，WHEN 尝试 `deploy()`，THEN 返回 false（`is_playing()` gate 自动拒绝）
- [ ] **AC-7**: GIVEN 国王寿命耗尽但玩家仍有星球，WHEN `check()`，THEN 返回不触发胜负（国王去世由 KingSystem 独立处理）

---

## Implementation Notes

*Derived from ADR-0003, ADR-0004, ADR-0008 and GDD win-conditions.md:*

### 核心结构

```gdscript
# win_condition.gd — src/feature/win_condition.gd
class_name WinCondition extends RefCounted

## 检查玩家是否胜利
## 条件：无任何星球 owner == ENEMY
## planet_system: 通过参数注入，不依赖 autoload（可单元测试）
func check_victory(planet_system) -> bool:
    var enemy_planets = planet_system.get_planets_by_owner(DataDef.Faction.ENEMY)
    return enemy_planets.is_empty()

## 检查玩家是否失败
## 条件：无任何星球 owner == PLAYER
func check_defeat(planet_system) -> bool:
    var player_planets = planet_system.get_planets_by_owner(DataDef.Faction.PLAYER)
    return player_planets.is_empty()

## 执行胜负判定
## planet_system: PlanetSystem 实例（参数注入）
## game_state: GameState autoload 引用（参数注入）
## 返回: void — 副作用通过 GameState.transition_to 和 EventBus 产生
func check(planet_system, game_state) -> void:
    # 规则 5: 国王寿命耗尽不算输 — 此函数只检查星球归属
    # 国王去世由 KingSystem 独立处理
    
    if check_victory(planet_system):
        game_state.transition_to(GameState.State.VICTORY)
        EventBus.game_ended.emit("victory")
    elif check_defeat(planet_system):
        game_state.transition_to(GameState.State.DEFEAT)
        EventBus.game_ended.emit("defeat")
    # else: 不触发任何转换，游戏继续
```

### 关键实现要点

- `WinCondition` 用 `RefCounted` 而不是 `Resource` — ADR-0005 禁止 Resource 用于运行时数据
- 所有外部依赖通过参数注入 — `planet_system` 和 `game_state` 显式传入，可隔离单元测试
- **双方全灭判定逻辑**：`check_victory()` 先检查，若 `true`（无 ENEMY 星球），同时 `check_defeat()` 也为 `true`（无 PLAYER 星球）。代码顺序 `if victory elif defeat` 会错误地判定 VICTORY。需要用 `check_defeat()` 先检或显式的"双方全灭→DEFEAT"分支：
  ```gdscript
  func check(planet_system, game_state) -> void:
      var has_enemy = not planet_system.get_planets_by_owner(DataDef.Faction.ENEMY).is_empty()
      var has_player = not planet_system.get_planets_by_owner(DataDef.Faction.PLAYER).is_empty()
      
      if not has_enemy and not has_player:
          # 双方全灭 → DEFEAT（平局判负）
          game_state.transition_to(GameState.State.DEFEAT)
          EventBus.game_ended.emit("defeat")
      elif not has_enemy:
          # 只有玩家 → VICTORY
          game_state.transition_to(GameState.State.VICTORY)
          EventBus.game_ended.emit("victory")
      elif not has_player:
          # 只有敌人 → DEFEAT
          game_state.transition_to(GameState.State.DEFEAT)
          EventBus.game_ended.emit("defeat")
  ```
- check() 不修改星球状态 — 只读查询
- `game_ended` 信号在 `EventBus` 中已声明（ADR-0001 12 信号之一），参数为 String ("victory"/"defeat")
- 本 Story 不集成 TurnManager — check() 的调用时机在 story-002 中集成

### 测试 mock

```gdscript
# 单元测试用 mock PlanetSystem
class MockPlanetSystem:
    var _planets_by_owner: Dictionary = {}  # {Faction: Array}

    func add_planet(owner: int, id: int) -> void:
        if not _planets_by_owner.has(owner):
            _planets_by_owner[owner] = []
        _planets_by_owner[owner].append(id)

    func get_planets_by_owner(owner: int) -> Array:
        return _planets_by_owner.get(owner, [])
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: 回合管线集成（TurnManager 步骤 5 调用 check()）、GameState 实际接入、EventBus 实际连接
- 胜利/失败 UI overlay
- 国王去世流程（KingSystem 独立处理）
- 计分/评级/星数统计（MVP 不做）

---

## QA Test Cases

*Derived from GDD acceptance criteria.*

- **AC-1**: 玩家胜利
  - Given: mock has ENEMY=[], PLAYER=[1,2]
  - When: check()
  - Then: game_state.current == VICTORY, game_ended emit "victory"

- **AC-2**: 玩家失败
  - Given: mock has ENEMY=[3], PLAYER=[]
  - When: check()
  - Then: game_state.current == DEFEAT, game_ended emit "defeat"

- **AC-3**: 游戏继续
  - Given: mock has ENEMY=[3], PLAYER=[1,2]
  - When: check()
  - Then: game_state unchanged (PLAYING), game_ended NOT emitted

- **AC-4**: 双方全灭
  - Given: mock has ENEMY=[], PLAYER=[]
  - When: check()
  - Then: game_state.current == DEFEAT (not VICTORY), game_ended emit "defeat"

- **AC-5**: 空星图（初始化前）
  - Given: mock has ENEMY=[], PLAYER=[] (no planets initialized)
  - When: check()
  - Then: game_state.current == DEFEAT (双方全灭→DEFEAT)

- **AC-6**: VICTORY 状态 gate
  - Given: game_state == VICTORY
  - When: call deploy()
  - Then: returns false (is_playing() gate)

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- Logic: `tests/unit/win-conditions/win_check_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Foundation data-definitions (TR-DEF-004 Faction.PLAYER/ENEMY/NEUTRAL) — must be DONE
- Depends on: Foundation gamestate-manager (GameState.State + transition_to()) — must be DONE
- Depends on: Foundation event-bus (game_ended signal) — must be DONE
- Depends on: Core planet-system (get_planets_by_owner()) — must be DONE
- Unlocks: Story 002 (回合管线集成)
