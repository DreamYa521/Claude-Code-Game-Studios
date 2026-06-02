# Story 003: 状态变更、查询与快照

> **Epic**: 星球系统 (planet-system)
> **Status**: Ready
> **Layer**: Core
> **Type**: Integration
> **Estimate**: 3h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/planet-system.md`
**Requirement**: `TR-PLT-005`, `TR-PLT-006`, `TR-PLT-008`, `TR-PLT-009`, `TR-PLT-010`

**ADR Governing Implementation**: ADR-0005: 星球数据模型 (primary); ADR-0004: 回合结算模型 (secondary — 阶段 gate + 快照接口)
**ADR Decision Summary**: 所有状态变更通过 PlanetSystem API 封装——`update_garrison()` 增减驻兵（阶段 gate），`set_owner()` 变更归属并广播 EventBus。查询返回浅拷贝防外部修改。`take_snapshot()` 用 Dictionary.duplicate(true) 深拷贝供回合结算。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Dictionary.duplicate(true)` 深拷贝行为在 Godot 4.x 全版本一致。不涉及 4.5 变更的 `Resource.duplicate_deep()`。

**Control Manifest Rules (this layer)**:
- Required: `get_planet()` 返回浅拷贝 — 防止外部直接修改内部状态
- Required: `set_owner()` 内部广播 `EventBus.planet_owner_changed`
- Required: `update_garrison()` 阶段 gate — 只在 DEPLOYMENT 和 CLEANUP 阶段接受修改
- Required: `take_snapshot()` 用 `Dictionary.duplicate(true)` 深拷贝
- Forbidden: 禁止 `garrison < 0` — `update_garrison()` delta 导致负数返回 false
- Forbidden: 禁止 NEUTRAL 星球产兵 — 但本 Story 不涉及生产逻辑，仅提供 API

---

## Acceptance Criteria

*From GDD `design/gdd/planet-system.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN `set_owner(1, PLAYER)` 调用，WHEN 完成，THEN `get_planet(1).owner == PLAYER` 且 `EventBus.planet_owner_changed` 被 emit
- [ ] **AC-2**: GIVEN `set_owner(1, PLAYER)` 在非法阶段（非 APPLY 步骤），WHEN 执行，THEN 返回 false，owner 不变
- [ ] **AC-3**: GIVEN `update_garrison(1, +5)` 调用，WHEN 完成，THEN garrison 增加 5
- [ ] **AC-4**: GIVEN garrison = 3, `update_garrison(1, -5)` 调用，WHEN 执行，THEN 返回 false，garrison 保持 3
- [ ] **AC-5**: GIVEN `get_planets_by_owner(PLAYER)` 调用，WHEN 仅 2 颗星属于玩家，THEN 返回长度为 2
- [ ] **AC-6**: GIVEN `get_planet(1)` 返回的 Dictionary 被修改，WHEN 查询 `_planets[1]`，THEN `_planets[1]` 不变（浅拷贝验证）
- [ ] **AC-7**: GIVEN `take_snapshot()` 返回的 Dictionary 被修改，WHEN 查询原始 `_planets`，THEN `_planets` 不变（深拷贝验证）
- [ ] **AC-8**: GIVEN `get_planet(999)`（不存在的 id），WHEN 执行，THEN 返回空 Dictionary `{}`

---

## Implementation Notes

*Derived from ADR-0005 and ADR-0004 Implementation Guidelines:*

### 查询 API

```gdscript
func get_planet(id: int) -> Dictionary:
    if not _planets.has(id):
        return {}
    return _planets[id].duplicate(false)  # 浅拷贝——9个字段全是值类型/基础类型

func get_all_planets() -> Array:
    var result: Array = []
    for planet in _planets.values():
        result.append(planet.duplicate(false))
    return result

func get_planets_by_owner(faction: DataDef.Faction) -> Array:
    var result: Array = []
    for planet in _planets.values():
        if planet.owner == faction:
            result.append(planet.duplicate(false))
    return result
```

### 状态变更 API

```gdscript
func update_garrison(id: int, delta: int) -> bool:
    if not _planets.has(id):
        return false
    
    # 阶段 gate: 只在 DEPLOYMENT 和 CLEANUP 接受修改
    if not _is_mutation_allowed():
        return false
    
    var new_garrison = _planets[id].garrison + delta
    if new_garrison < 0:
        return false
    
    _planets[id].garrison = new_garrison
    return true

func set_owner(id: int, new_owner: DataDef.Faction) -> bool:
    if not _planets.has(id):
        return false
    
    # 阶段 gate: 只在 APPLY 步骤（EXECUTION 阶段内部）接受归属变更
    if not _is_apply_step():
        return false
    
    var old_owner = _planets[id].owner
    if old_owner == new_owner:
        return true  # 无变化，不算失败
    
    _planets[id].owner = new_owner
    EventBus.planet_owner_changed.emit(id, old_owner, new_owner)
    return true

func _is_mutation_allowed() -> bool:
    # DEPLOYMENT（出征扣兵）或 CLEANUP（生产加兵）
    return TurnManager.current_phase == TurnManager.Phase.DEPLOYMENT \
        or TurnManager.current_phase == TurnManager.Phase.CLEANUP

func _is_apply_step() -> bool:
    # 归属变更只在 EXECUTION 阶段的 APPLY 步骤
    return TurnManager.current_phase == TurnManager.Phase.EXECUTION
```

### 快照

```gdscript
func take_snapshot() -> Dictionary:
    var snap: Dictionary = {}
    for id in _planets:
        snap[id] = _planets[id].duplicate(true)  # 深拷贝
    return snap
```

### 关键实现要点

- `get_planet()` 返回浅拷贝：`duplicate(false)` 对 9 个基础类型字段（int/String/Vector2/enum/float）足够——它们都是值类型。`adjacent_ids` Array 是引用类型，但浅拷贝后修改不影响内部 `_planets[id].adjacent_ids` 的元素追加（浅拷贝的 Array 是独立引用）
  - ⚠️ 注意：浅拷贝后的 `adjacent_ids` 和原 `_planets[id].adjacent_ids` 是**同一个** Array 引用！`duplicate(false)` 只复制 Dictionary 本身，不复制嵌套的 Array。需要在 `get_planet()` 中也复制 `adjacent_ids`：`result["adjacent_ids"] = _planets[id].adjacent_ids.duplicate()`
- `EventBus.planet_owner_changed` 参数签名：`(planet_id: int, old_owner: int, new_owner: int)` — 使用 DataDef.Faction 的 int 值
- 阶段 gate 依赖 `TurnManager` autoload — 需确认 Foundation turn-manager 已实现 Phase 枚举
- `update_garrison()` 不广播 Signal（驻兵变化频繁，由调用方决定是否通知）。若需 UI 刷新，调用方自行 emit `planet_garrison_changed`

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: `_build_runtime_planet()` 构建逻辑、属性乘数常量
- Story 002: `init_from_level()` 初始化流程、`_build_adjacency()` 邻接表构建
- 生产系统: `accumulated_production` 字段的维护（TR-PRD-004）——那是生产系统 Story 的职责
- 回合管理器: 阶段切换的实际逻辑——本 Story 只**检查** `TurnManager.current_phase`，不控制它

---

## QA Test Cases

*Derived from GDD acceptance criteria. The developer implements against these.*

- **AC-1**: set_owner 成功 + EventBus 广播
  - Given: planet_id=1 当前 owner=NEUTRAL, TurnManager 处于 EXECUTION 阶段
  - When: 调用 `set_owner(1, PLAYER)`
  - Then: 返回 true, `get_planet(1).owner == PLAYER`, `EventBus.planet_owner_changed` 被 emit 且参数为 (1, NEUTRAL, PLAYER)
  - Edge cases: 设置为相同 owner 时返回 true，不 emit Signal

- **AC-2**: set_owner 阶段 gate 拒绝
  - Given: planet_id=1 当前 owner=NEUTRAL, TurnManager 处于 DEPLOYMENT 阶段
  - When: 调用 `set_owner(1, PLAYER)`
  - Then: 返回 false, owner 仍为 NEUTRAL

- **AC-3**: update_garrison 增兵成功
  - Given: planet_id=1 garrison=10, TurnManager 处于 CLEANUP 阶段
  - When: 调用 `update_garrison(1, +5)`
  - Then: 返回 true, `get_planet(1).garrison == 15`

- **AC-4**: update_garrison 负数拒绝
  - Given: planet_id=1 garrison=3, TurnManager 处于 DEPLOYMENT 阶段
  - When: 调用 `update_garrison(1, -5)`
  - Then: 返回 false, garrison 保持 3

- **AC-5**: get_planets_by_owner 筛选正确
  - Given: 4 颗星——2 颗 PLAYER, 1 颗 ENEMY, 1 颗 NEUTRAL
  - When: 调用 `get_planets_by_owner(PLAYER)`
  - Then: 返回 Array 长度为 2，每项的 owner 均为 PLAYER
  - Edge cases: `get_planets_by_owner(NEUTRAL)` 长度=1; 不存在势力时返回空数组

- **AC-6**: get_planet 浅拷贝隔离
  - Given: planet_id=1 在 `_planets` 中
  - When: `var p = get_planet(1); p["garrison"] = 999`
  - Then: `_planets[1].garrison` 不变

- **AC-7**: take_snapshot 深拷贝隔离
  - Given: 初始化后的 `_planets`
  - When: `var snap = take_snapshot(); snap[1]["garrison"] = 999`
  - Then: `_planets[1].garrison` 不变
  - Edge cases: 修改快照中的 adjacent_ids 不影响原始数据

- **AC-8**: 查询不存在的星球
  - Given: planet_id=999 不存在
  - When: 调用 `get_planet(999)`
  - Then: 返回空 Dictionary `{}`
  - Edge cases: `are_connected(999, 1)` → false, `update_garrison(999, 1)` → false

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- Integration: `tests/integration/planet-system/planet_mutation_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 002 (planet-init-adjacency) — `init_from_level()` 必须 DONE（测试需要先初始化）
- Also depends on: Foundation turn-manager (TR-TRN-001 Phase 枚举, TurnManager autoload) — must be DONE
- Also depends on: Foundation event-bus (TR-EVT-003 `planet_owner_changed` Signal) — must be DONE
- Unlocks: production-system, occupation-system, deployment-system, combat-resolution, ai-enemy, star-map-ui (all downstream systems that depend on PlanetSystem API)
