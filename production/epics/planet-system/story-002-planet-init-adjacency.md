# Story 002: 初始化流程与邻接表构建

> **Epic**: 星球系统 (planet-system)
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Estimate**: 2h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/planet-system.md`
**Requirement**: `TR-PLT-004`, `TR-PLT-007`, `TR-PLT-011`, `TR-PLT-012`

**ADR Governing Implementation**: ADR-0005: 星球数据模型
**ADR Decision Summary**: `init_from_level()` 一次性初始化全部星球——遍历 PlanetDef 构建 RuntimePlanetData → 从 Connections 构建双向邻接表 → 应用初始归属和驻兵 → emit `planets_initialized`。邻接表初始化时构建，运行时只读。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `push_warning()` 在 Godot 4.x 无破坏性变更。Dictionary 操作稳定。

**Control Manifest Rules (this layer)**:
- Required: 邻接表初始化时构建，运行时只读 — `are_connected(a, b)` O(1)
- Required: 连接双向自动处理：`Connection{from:A, to:B}` 等价于 A↔B
- Forbidden: 禁止连接单向假设 — `are_connected(a,b) == are_connected(b,a)` 始终成立
- Forbidden: 禁止 PlanetDef.id 重复（虽然 init_from_level 不做此事—那是关卡数据校验的职责）
- Guardrail: `init_from_level()` 遍历 10 个 PlanetDef < 1ms

---

## Acceptance Criteria

*From GDD `design/gdd/planet-system.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN `init_from_level()` 调用，WHEN LevelData 含 4 个 PlanetDef，THEN `get_all_planets().size() == 4`
- [ ] **AC-2**: GIVEN 初始化完毕，WHEN 查询每个星球的 adjacent_ids，THEN 双向一致（若 A 邻 B 则 B 邻 A）
- [ ] **AC-3**: GIVEN `are_connected(1, 2)` 为 true，WHEN 调用 `are_connected(2, 1)`，THEN 返回 true
- [ ] **AC-4**: GIVEN LevelData 含 3 条 Connection，WHEN 初始化完毕，THEN 所有连接的星球双向 adjacent_ids 正确
- [ ] **AC-5**: GIVEN Connection 引用不存在的 planet_id，WHEN `_build_adjacency()` 执行，THEN `push_warning()` 被调用 + 该连接被跳过
- [ ] **AC-6**: GIVEN `initial_owner` 指定了不存在的 planet_id，WHEN `init_from_level()` 执行，THEN `push_warning()` 被调用 + 该条目被跳过
- [ ] **AC-7**: GIVEN 初始化完毕，WHEN 调用 `EventBus.planets_initialized`，THEN Signal 被 emit 一次

---

## Implementation Notes

*Derived from ADR-0005 Implementation Guidelines:*

### init_from_level() 完整流程

```gdscript
func init_from_level(level_data: LevelData) -> void:
    _planets.clear()
    
    # Step 1: 构建 RuntimePlanetData
    for def in level_data.planets:
        _planets[def.id] = _build_runtime_planet(def)
    
    # Step 2: 构建双向邻接表
    _build_adjacency(_planets, level_data.connections)
    
    # Step 3: 应用初始归属和驻兵
    for planet_id in level_data.initial_owner:
        if not _planets.has(planet_id):
            push_warning("initial_owner references non-existent planet: %d" % planet_id)
            continue
        _planets[planet_id].owner = level_data.initial_owner[planet_id]
        _planets[planet_id].garrison = level_data.initial_garrison.get(planet_id, 0)
    
    # Step 4: 广播初始化完成
    EventBus.planets_initialized.emit()
```

### 邻接表构建

```gdscript
func _build_adjacency(planets: Dictionary, connections: Array) -> void:
    for conn in connections:
        if planets.has(conn.from) and planets.has(conn.to):
            planets[conn.from].adjacent_ids.append(conn.to)
            planets[conn.to].adjacent_ids.append(conn.from)
        else:
            push_warning("Connection references non-existent planet: %d <-> %d" % [conn.from, conn.to])
```

### 邻接查询 API

```gdscript
func get_adjacent_planets(id: int) -> Array:
    if not _planets.has(id):
        return []
    return _planets[id].adjacent_ids.duplicate()  # 返回副本防止外部修改

func are_connected(a: int, b: int) -> bool:
    if not _planets.has(a):
        return false
    return b in _planets[a].adjacent_ids
```

### 关键实现要点

- `get_all_planets()` 返回 `_planets.values()` 的浅拷贝数组（此函数在本 Story 中作为辅助实现，完整 API 在 Story 003）
- `_build_adjacency()` 应该幂等——多次调用不应重复追加（本 Story 只在 `init_from_level()` 中调用一次，但防御性编程建议先清空 `adjacent_ids`）
- Connection 的 `from`/`to` 字段来自 `DataDef.Connection` Resource 类（ADR-0002 / TR-DEF-009）
- `initial_owner` 中未指定的星球默认为 NEUTRAL，garrison=0（已在 Story 001 默认值中处理）
- `initial_garrison` 是 `Dictionary[int, int]`，key 为 planet_id

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: `_build_runtime_planet()` 单星构建逻辑、属性乘数常量
- Story 003: `get_planet()` / `get_planets_by_owner()` 完整查询 API、`update_garrison()` / `set_owner()` 状态变更、`take_snapshot()` 快照

---

## QA Test Cases

*Derived from GDD acceptance criteria. The developer implements against these.*

- **AC-1**: 初始化后星球数量正确
  - Given: LevelData 含 4 个 PlanetDef（id=1,2,3,4）
  - When: 调用 `init_from_level(level_data)`
  - Then: `_planets.size() == 4`，每个 id 都存在

- **AC-2**: 邻接表双向一致性
  - Given: LevelData 含 Connection{from:1, to:2}, Connection{from:2, to:3}
  - When: 调用 `init_from_level(level_data)`
  - Then: 1.adjacent_ids 含 2; 2.adjacent_ids 含 1 和 3; 3.adjacent_ids 含 2

- **AC-3**: are_connected 对称性
  - Given: 1 和 2 相邻（Connection 已定义）
  - When: 分别调用 `are_connected(1, 2)` 和 `are_connected(2, 1)`
  - Then: 两者都返回 true
  - Edge cases: 两个不相邻的星球（如 1 和 3 之间无连接）→ 都返回 false

- **AC-4**: 多条 Connection 全部正确处理
  - Given: LevelData 含 3 条 Connection（1-2, 2-3, 3-4）
  - When: 初始化完成
  - Then: 1↔2, 2↔3, 3↔4 全部双向建立

- **AC-5**: Connection 无效引用处理
  - Given: LevelData 含 Connection{from:1, to:999}，planet_id=999 不存在
  - When: 调用 `_build_adjacency()`
  - Then: push_warning() 被调用，1.adjacent_ids 不含 999，其他连接不受影响

- **AC-6**: initial_owner 无效 key 处理
  - Given: LevelData.initial_owner = {999: PLAYER}，planet_id=999 不存在
  - When: 调用 `init_from_level()`
  - Then: push_warning() 被调用，其他星球初始化不受影响

- **AC-7**: planets_initialized Signal
  - Given: 任意有效 LevelData
  - When: `init_from_level()` 完成
  - Then: `EventBus.planets_initialized` 被 emit 一次
  - Edge cases: 两次调用 `init_from_level()` → Signal emit 两次（第二次覆盖第一次）

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- Logic: `tests/unit/planet-system/planet_init_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (planet-runtime-data) — `_build_runtime_planet()` 必须 DONE
- Also depends on: Foundation event-bus (TR-EVT-003 `planets_initialized` Signal) — must be DONE
- Unlocks: Story 003 (planet-mutation-snapshot)
