# Story 002: init_from_level() 集成 + 边界校验

> **Epic**: 星图/关卡数据 (level-data)
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Estimate**: 1h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/level-data.md`
**Requirement**: `TR-LVL-003`

**ADR Governing Implementation**: ADR-0005: 关卡初始化走 PlanetSystem.init_from_level()，构建双向邻接表 + RuntimePlanetData；ADR-0002: PlanetDef.id 重复检测 push_error
**ADR Decision Summary**: init_from_level(level_data) 由 PlanetSystem 调用，遍历 planets→connections→initial_owner→initial_garrison。Connection 双向自动镜像。id 重复 skip+push_error。引用不存在星球的 Connection skip+push_warning。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: 纯 Dictionary 操作 + Array 遍历，无引擎 API 依赖。邻接表用 `Dictionary[int, Array[int]]`。

**Control Manifest Rules (this layer)**:
- Required: 关卡初始化：PlanetSystem.init_from_level(level_data) — 遍历 planets→connections→initial_owner→initial_garrison — source: ADR-0005
- Required: 邻接表构建双向 — are_connected(a,b) == are_connected(b,a) — source: ADR-0005
- Forbidden: 禁止 PlanetDef.id 重复 — init_from_level() 检测到重复 push_error() — source: ADR-0005
- Forbidden: 禁止 Connection 引用不存在星球 — 跳过 + push_warning() — source: ADR-0005

---

## Acceptance Criteria

*From GDD `design/gdd/level-data.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN `tutorial_1.tres` (4星+3连接), WHEN `PlanetSystem.init_from_level(level_data)`，THEN `get_all_planets().size() == 4`
- [ ] **AC-2**: GIVEN 3 条 Connection，WHEN 初始化完成，THEN 邻接表包含 6 条邻接关系（双向），`are_connected(1,2)==true && are_connected(2,1)==true`
- [ ] **AC-3**: GIVEN `initial_owner[1]=PLAYER, initial_owner[3]=ENEMY`，WHEN 初始化完成，THEN 地球 owner=PLAYER, 火星 owner=ENEMY, 月球+火卫一 owner=NEUTRAL
- [ ] **AC-4**: GIVEN `initial_garrison[1]=10, initial_garrison[3]=8`，WHEN 初始化完成，THEN 地球 garrison=10, 火星 garrison=8, 其余 garrison=0
- [ ] **AC-5**: GIVEN PlanetDef 含重复 id=1（两次），WHEN `init_from_level()`，THEN push_error + 跳过重复项，只保留第一个
- [ ] **AC-6**: GIVEN Connection 引用 `from=1, to=99`（不存在的星球），WHEN `init_from_level()`，THEN push_warning + 跳过该 Connection
- [ ] **AC-7**: GIVEN `initial_owner` 的 key 不存在于任何 PlanetDef.id，WHEN `init_from_level()`，THEN push_warning + 跳过该条目

---

## Implementation Notes

*Derived from ADR-0005 and GDD level-data.md:*

### 核心函数签名

```gdscript
# 在 PlanetSystem 中添加
class_name PlanetSystem
# ... existing code ...

## 从 LevelData Resource 初始化星球系统
## 步骤顺序：planets → connections → initial_owner → initial_garrison
## 每步独立处理边界错误，不因单条数据失败而中断整体
func init_from_level(level_data: LevelData) -> void:
    _clear_all()  # 清空旧数据（如果有）
    
    # Step 1: 构建星球
    var seen_ids := {}
    for planet_def in level_data.planets:
        if seen_ids.has(planet_def.id):
            push_error("init_from_level: duplicate planet id=%d, skipping" % planet_def.id)
            continue
        seen_ids[planet_def.id] = true
        _create_runtime_planet(planet_def)
    
    # Step 2: 构建双向邻接
    for conn in level_data.connections:
        if not _planets.has(conn.from):
            push_warning("init_from_level: connection references unknown planet id=%d, skipping" % conn.from)
            continue
        if not _planets.has(conn.to):
            push_warning("init_from_level: connection references unknown planet id=%d, skipping" % conn.to)
            continue
        _add_bidirectional_edge(conn.from, conn.to)
    
    # Step 3: 设置初始归属
    for planet_id in level_data.initial_owner:
        if not _planets.has(planet_id):
            push_warning("init_from_level: initial_owner key %d not a valid planet, skipping" % planet_id)
            continue
        _planets[planet_id].owner = level_data.initial_owner[planet_id]
    
    # Step 4: 设置初始驻兵
    for planet_id in level_data.initial_garrison:
        if not _planets.has(planet_id):
            push_warning("init_from_level: initial_garrison key %d not a valid planet, skipping" % planet_id)
            continue
        _planets[planet_id].garrison = level_data.initial_garrison[planet_id]
    
    EventBus.planets_initialized.emit()
```

### 辅助函数

```gdscript
func _create_runtime_planet(def: PlanetDef) -> void:
    var data = RuntimePlanetData.new()
    data.id = def.id
    data.name = def.name
    data.position = def.position
    data.attribute = def.attribute
    data.owner = DataDef.Faction.NEUTRAL  # 默认中立
    data.garrison = 0                     # 默认 0 兵
    data.max_garrison = _calc_max_garrison(def.attribute)
    data.production_rate = _calc_production_rate(def.attribute)
    _planets[def.id] = data

func _add_bidirectional_edge(a: int, b: int) -> void:
    if not _adjacency.has(a):
        _adjacency[a] = []
    if not _adjacency.has(b):
        _adjacency[b] = []
    if b not in _adjacency[a]:
        _adjacency[a].append(b)
    if a not in _adjacency[b]:
        _adjacency[b].append(a)

func _clear_all() -> void:
    _planets.clear()
    _adjacency.clear()
```

### 关键实现要点

- 初始化顺序：planets → connections → owner → garrison — owner 在 garrison 之前，逻辑正确
- `_clear_all()` 在 init_from_level 开头调用 — 防止重复初始化累积
- 双向邻接自动镜像 — 设计师只需定义单向 Connection
- 邻接表排重 — `b not in _adjacency[a]` 防止重复连接累积
- 错误隔离：单条数据失败不影响其他 — 每个边界校验独立 skip+log
- 未指定的星球 owner=NEUTRAL, garrison=0 — 默认值在 `_create_runtime_planet()` 中设置
- 初始化完成后 emit `planets_initialized` — 星图 UI 监听此信号首次渲染
- `_calc_max_garrison()` 和 `_calc_production_rate()` 已由 planet-system 实现

### 测试数据

```gdscript
# 正常数据：tutorial_1.tres（由 story-001 提供）

# 异常数据：手工构造含重复 id 的 LevelData
var bad_level = LevelData.new()
var p1 = PlanetDef.new(); p1.id = 1; p1.name = "重复星A"
var p2 = PlanetDef.new(); p2.id = 1; p2.name = "重复星B"  # 重复 ID
bad_level.planets = [p1, p2]
bad_level.connections = []
bad_level.initial_owner = {}
bad_level.initial_garrison = {}

# 异常数据：Connection 引用不存在的星
var bad_conn = LevelData.new()
var p3 = PlanetDef.new(); p3.id = 1; p3.name = "唯一星"
bad_conn.planets = [p3]
bad_conn.connections = [make_connection(1, 99)]  # 99 不存在
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: LevelData/PlanetDef/Connection Resource 类定义 + tutorial_1.tres
- Godot 编辑器可视化编辑关卡
- 关卡切换（MVP 不做）
- `_calc_max_garrison()` / `_calc_production_rate()` — 已由 planet-system 实现

---

## QA Test Cases

*Derived from GDD acceptance criteria.*

- **AC-1**: 4 星加载成功
  - Given: tutorial_1.tres (4 planets)
  - When: PlanetSystem.init_from_level(level_data)
  - Then: get_all_planets().size() == 4

- **AC-2**: 双向邻接
  - Given: tutorial_1.tres (3 connections)
  - When: init_from_level()
  - Then: are_connected(1,2)==true, are_connected(2,1)==true, are_connected(2,4)==false

- **AC-3**: 初始归属
  - Given: tutorial_1.tres (initial_owner[1]=PLAYER, [3]=ENEMY)
  - When: init_from_level()
  - Then: planet 1 owner=PLAYER, planet 3 owner=ENEMY, planet 2/4 owner=NEUTRAL

- **AC-4**: 初始驻兵
  - Given: tutorial_1.tres (initial_garrison[1]=10, [3]=8)
  - When: init_from_level()
  - Then: planet 1 garrison=10, planet 3 garrison=8, planet 2/4 garrison=0

- **AC-5**: 重复 id 检测
  - Given: LevelData with two PlanetDef both id=1
  - When: init_from_level()
  - Then: push_error emitted, only first PlanetDef(id=1) kept

- **AC-6**: 无效 Connection
  - Given: Connection from=1 to=99, planet 99 doesn't exist
  - When: init_from_level()
  - Then: push_warning emitted, connection skipped

- **AC-7**: 无效 initial_owner key
  - Given: initial_owner[99]=PLAYER, planet 99 doesn't exist
  - When: init_from_level()
  - Then: push_warning emitted, entry skipped

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- Integration: `tests/integration/level-data/init_from_level_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (LevelData/PlanetDef/Connection Resource classes) — must be DONE
- Depends on: Core planet-system (RuntimePlanetData, _planets/_adjacency 内部结构) — must be DONE
- Depends on: Foundation event-bus (planets_initialized signal) — must be DONE
- Unlocks: star-map-ui (planets_initialized 信号驱动首次渲染)
