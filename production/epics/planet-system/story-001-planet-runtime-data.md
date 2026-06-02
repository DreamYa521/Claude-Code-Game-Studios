# Story 001: 星球运行时数据结构与属性计算

> **Epic**: 星球系统 (planet-system)
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Estimate**: 2h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/planet-system.md`
**Requirement**: `TR-PLT-001`, `TR-PLT-002`, `TR-PLT-003`

**ADR Governing Implementation**: ADR-0005: 星球数据模型
**ADR Decision Summary**: 静态 PlanetDef 用 .tres Resource，运行时 RuntimePlanetData 用 GDScript Dictionary。属性乘数（NORMAL/RICH/FORTRESS/BARREN）影响 max_garrison 和 production_rate，计算公式在 `_build_runtime_planet()` 中应用。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Dictionary 操作在 Godot 4.x 全版本无破坏性变更。不使用需要 Godot 4.5+ 的 API。

**Control Manifest Rules (this layer)**:
- Required: RuntimePlanetData 用 Dictionary 存储，静态 PlanetDef 用 .tres Resource — 静态/动态分离
- Required: 属性乘数定义在 PlanetSystem 常量中（`ATTR_GARRISON_MULT`, `ATTR_PRODUCTION_MULT`）
- Forbidden: 禁止 Resource 用于运行时星球数据
- Forbidden: 禁止 `garrison < 0`
- Guardrail: 10星规模所有操作 O(1) 或 O(N)（N≤10），无测量意义

---

## Acceptance Criteria

*From GDD `design/gdd/planet-system.md`, scoped to this story:*

- [ ] **AC-1**: `_build_runtime_planet(def)` 构建的 Dictionary 包含全部 9 个字段：id/name/position/attribute/garrison/owner/max_garrison/production_rate/adjacent_ids
- [ ] **AC-2**: NORMAL 属性星球 `max_garrison = 20`（`GARRISON_DEFAULT_MAX × 1.0`）
- [ ] **AC-3**: FORTRESS 属性星球 `max_garrison = 30`（`GARRISON_DEFAULT_MAX × 1.5`）
- [ ] **AC-4**: BARREN 属性星球 `max_garrison = 15`（`GARRISON_DEFAULT_MAX × 0.75`）
- [ ] **AC-5**: RICH 属性星球 `production_rate = 1.5`（`PRODUCTION_BASE_RATE × 1.5`）
- [ ] **AC-6**: BARREN 属性星球 `production_rate = 0.5`（`PRODUCTION_BASE_RATE × 0.5`）
- [ ] **AC-7**: 新构建的 RuntimePlanetData 默认 `garrison = 0`, `owner = NEUTRAL`, `adjacent_ids = []`

---

## Implementation Notes

*Derived from ADR-0005 Implementation Guidelines:*

### 数据常量定义

在 `planet_system.gd` 顶部定义属性乘数常量：

```gdscript
const ATTR_GARRISON_MULT: Dictionary = {
    DataDef.PlanetAttribute.NORMAL:   1.0,
    DataDef.PlanetAttribute.RICH:     1.0,
    DataDef.PlanetAttribute.FORTRESS: 1.5,
    DataDef.PlanetAttribute.BARREN:   0.75,
}

const ATTR_PRODUCTION_MULT: Dictionary = {
    DataDef.PlanetAttribute.NORMAL:   1.0,
    DataDef.PlanetAttribute.RICH:     1.5,
    DataDef.PlanetAttribute.FORTRESS: 0.75,
    DataDef.PlanetAttribute.BARREN:   0.5,
}
```

### RuntimePlanetData 构建函数

```gdscript
func _build_runtime_planet(def: PlanetDef) -> Dictionary:
    return {
        "id": def.id,
        "name": def.name,
        "position": def.position,
        "attribute": def.attribute,
        "garrison": 0,
        "owner": DataDef.Faction.NEUTRAL,
        "max_garrison": int(DataDef.GARRISON_DEFAULT_MAX * ATTR_GARRISON_MULT[def.attribute]),
        "production_rate": DataDef.PRODUCTION_BASE_RATE * ATTR_PRODUCTION_MULT[def.attribute],
        "adjacent_ids": [],
    }
```

### 关键实现要点

- `max_garrison` 使用 `int()` 强制取整（`GARRISON_DEFAULT_MAX × 乘数` 可能产生浮点）
- `production_rate` 保留为 float（生产系统用累积模型需要小数精度）
- `adjacent_ids` 初始化为空数组，由 Story 002 的 `_build_adjacency()` 填充
- 内部存储为 `_planets: Dictionary = {}`，key 为 planet_id (int)
- 此 Story 不实现 `init_from_level()` 完整流程——只实现单个 RuntimePlanetData 的构建逻辑
- 属性乘数目前定义在 PlanetSystem 中（降低 DataDef 修改频率）。若后续被多系统引用，迁至 DataDef

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: `init_from_level()` 完整初始化流程、邻接表构建、`are_connected()` / `get_adjacent_planets()`
- Story 003: `update_garrison()` / `set_owner()` 状态变更、`get_planet()` / `get_planets_by_owner()` 查询、`take_snapshot()` 快照

---

## QA Test Cases

*Derived from GDD acceptance criteria. The developer implements against these.*

- **AC-1**: RuntimePlanetData 包含全部 9 字段
  - Given: 一个有效的 PlanetDef (id=1, name="地球", position=Vector2(100,200), attribute=NORMAL)
  - When: 调用 `_build_runtime_planet(def)`
  - Then: 返回的 Dictionary 包含全部 9 个 key（id/name/position/attribute/garrison/owner/max_garrison/production_rate/adjacent_ids）
  - Edge cases: 四种属性各测试一次（NORMAL/RICH/FORTRESS/BARREN）

- **AC-2~4**: max_garrison 属性乘数计算
  - Given: GARRISON_DEFAULT_MAX = 20
  - When: 分别用 NORMAL, FORTRESS, BARREN 属性构建 RuntimePlanetData
  - Then: max_garrison 分别为 20, 30, 15
  - Edge cases: RICH 的 max_garrison 应为 20（与 NORMAL 相同，无防守加成）

- **AC-5~6**: production_rate 属性乘数计算
  - Given: PRODUCTION_BASE_RATE = 1.0
  - When: 分别用 RICH, BARREN 属性构建 RuntimePlanetData
  - Then: production_rate 分别为 1.5, 0.5
  - Edge cases: NORMAL=1.0, FORTRESS=0.75

- **AC-7**: 默认值验证
  - Given: 任意有效的 PlanetDef
  - When: 调用 `_build_runtime_planet(def)`
  - Then: garrison=0, owner=NEUTRAL, adjacent_ids=[]

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- Logic: `tests/unit/planet-system/planet_data_structure_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Foundation data-definitions (TR-DEF-003 Faction, TR-DEF-004 PlanetAttribute, TR-DEF-007 GARRISON_DEFAULT_MAX/PRODUCTION_BASE_RATE, TR-DEF-009 PlanetDef) — must be DONE
- Unlocks: Story 002 (planet-init-adjacency)
