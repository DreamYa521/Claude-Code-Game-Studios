# ADR-0005: 星球数据模型

## Status
Accepted

## Date
2026-05-31

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core (星球系统) |
| **Knowledge Risk** | LOW — `Resource`, `Dictionary`, GDScript `class` 在 4.3→4.6 无破坏性变更 |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/current-best-practices.md`, `docs/architecture/architecture.md` Phase 3, Phase 4 |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | None |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0002 (PlanetDef/Connection Resource 类定义), ADR-0004 (快照需要深拷贝星球运行时状态) |
| **Enables** | ADR-0006 (战斗公式 — 防守方星球属性影响伤害), ADR-0007 (AI — 评估星球价值和威胁), 生产系统 GDD, 占领系统 GDD, 出征系统 GDD |
| **Blocks** | 星球系统 GDD, 生产系统 GDD, 占领系统 GDD, 出征系统 GDD, AI 敌人 GDD, 星图数据 GDD |
| **Ordering Note** | Core 层第一个 ADR — 7 个系统依赖星球数据模型，必须优先定稿 |

## Context

### Problem Statement

星球是游戏的**核心实体**——玩家占领星球、从星球发兵、在星球上生产。星球数据模型需要同时服务两类需求：

1. **关卡设计时**：设计师在 Godot 编辑器中摆放星球位置、设置属性、定义连接路线（静态、不可变）
2. **游戏运行时**：系统频繁读写星球的归属方、驻兵数、产量（动态、每回合变）

需要决定：如何清晰分离静态关卡数据和动态运行时状态，同时保证快照模型（ADR-0004）的可深拷贝性。

### Constraints

- MVP 单关卡最多约 10 颗星球，20 条连接
- 星球属性影响驻兵上限和产量（NORMAL / RICH / FORTRESS / BARREN）
- 连接是双向的（A→B 则 B→A），不需要单向路线
- 回合结算的快照必须能深拷贝星球运行时状态（ADR-0004 步骤 2）
- 必须支持按归属方查询（"所有玩家星球" / "所有敌方星球"）
- 星球连接信息用于出征校验（是否相邻）和 AI 寻路

### Requirements

- 静态关卡数据（id, name, position, attribute, connections）定义在 .tres 中，设计师可视化编辑
- 运行时状态（owner, garrison）与静态数据分离，通过 PlanetSystem 管理
- 支持 garrison 增减（`update_garrison(id, delta)`）和归属变更（`set_owner(id, faction)`）
- 每次归属变更广播 `EventBus.planet_owner_changed`
- 快照可深拷贝：snapshot[id] = {garrison, owner, max_garrison, production_rate}
- 支持邻接查询（`get_adjacent_planets(id)`, `are_connected(a, b)`）

## Decision

**静态数据用 PlanetDef Resource（.tres），运行时状态用 RuntimePlanetData GDScript Dictionary。**

### 数据分层

```
PlanetDef (Resource / .tres)          RuntimePlanetData (Dictionary)
┌──────────────────────────┐          ┌──────────────────────────┐
│ id: int                  │          │ id: int                  │
│ name: String             │  加载时   │ name: String             │
│ position: Vector2        │─────────→│ position: Vector2       │
│ attribute: PlanetAttr    │  复制    │ attribute: PlanetAttr    │
│ connections: Array[int]  │          │ garrison: int           │
│                          │          │ owner: Faction          │
│ (关卡设计时定义，不变)     │          │ max_garrison: int       │
└──────────────────────────┘          │ production_rate: float  │
                                      │ adjacent_ids: Array[int]│
                                      │                         │
                                      │ (运行时可变，每回合更新)   │
                                      └──────────────────────────┘
```

**规则**:
- `PlanetDef` (ADR-0002 已定义) 是关卡设计产物，存于 `LevelData.planets`。运行时不修改。
- `RuntimePlanetData` 是 `PlanetSystem` 内部 Dictionary，初始化时从 `PlanetDef` 构建。
- `adjacent_ids` 从 `LevelData.connections` 构建：遍历所有 Connection，若 `from == id` 则 `adjacent_ids.append(to)`，反之亦然。
- 连接是双向的——`LevelData.connections` 中只需定义一次 `Connection{from: 1, to: 2}`，初始化时自动建立双向邻接。

### PlanetSystem API

```gdscript
# planet_system.gd — autoload: PlanetSystem
extends Node

# === 内部数据 ===
var _planets: Dictionary = {}  # {planet_id: RuntimePlanetData}

# === 查询 ===
func get_planet(id: int) -> Dictionary
# 返回 RuntimePlanetData 的浅拷贝（防止外部直接修改内部状态）

func get_all_planets() -> Array[Dictionary]
# 返回全部星球的浅拷贝数组

func get_planets_by_owner(faction: DataDef.Faction) -> Array[Dictionary]
# 按归属方筛选

func get_adjacent_planets(id: int) -> Array[int]
# 返回相邻星球 ID 列表

func are_connected(a: int, b: int) -> bool
# O(1) 检查 a 的 adjacent_ids 是否包含 b

# === 状态变更（仅在合法阶段执行）===
func update_garrison(id: int, delta: int) -> bool
# delta 可正可负；返回 false 若 garrison 会变负数或被 stage gate 拒绝

func set_owner(id: int, new_owner: DataDef.Faction) -> bool
# 变更归属 → 内部更新 → EventBus.planet_owner_changed.emit(id, old, new)

# === 初始化 ===
func init_from_level(level_data: LevelData) -> void
# 清空 _planets → 遍历 level_data.planets → 构建 RuntimePlanetData → 构建邻接表
# → EventBus.planets_initialized.emit()
```

### RuntimePlanetData 结构

```gdscript
# planet_system.gd 内部
#
# _planets[id] = {
#     "id": int,
#     "name": String,
#     "position": Vector2,
#     "attribute": DataDef.PlanetAttribute,
#     "garrison": int,
#     "owner": DataDef.Faction,
#     "max_garrison": int,
#     "production_rate": float,
#     "adjacent_ids": Array[int],
# }
```

**为什么用 Dictionary 而非 Resource？**

- 快照（ADR-0004）需要深拷贝星球状态。Dictionary 的 `.duplicate(true)` 是原生、零成本、无歧义的操作。
- Resource 的 `duplicate(true)` 在 Godot 4.5 语义变更，需用 `duplicate_deep()` 替代——增加知识点。
- MVP 10 颗星的数据量下 Dictionary 和 Resource 性能无差异。
- 若未来扩展到 100+ 星球且有性能压力，可切换到 `class RuntimePlanetData extends RefCounted`——API 不变。

### 星球属性效果

属性影响 `max_garrison` 和 `production_rate`，公式在 `init_from_level()` 中应用：

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

func _build_runtime_planet(def: PlanetDef) -> Dictionary:
    return {
        "id": def.id,
        "name": def.name,
        "position": def.position,
        "attribute": def.attribute,
        "garrison": 0,  # 由 LevelData.initial_owner 和初始兵力设置
        "owner": DataDef.Faction.NEUTRAL,  # 默认中立，后续由初始化覆盖
        "max_garrison": int(DataDef.GARRISON_DEFAULT_MAX * ATTR_GARRISON_MULT[def.attribute]),
        "production_rate": DataDef.PRODUCTION_BASE_RATE * ATTR_PRODUCTION_MULT[def.attribute],
        "adjacent_ids": [],  # 由 _build_adjacency() 填充
    }
```

属性效果设计意图：

| 属性 | 驻兵上限 | 产兵速率 | 战术含义 |
|------|---------|---------|---------|
| NORMAL | 1.0× | 1.0× | 基准 |
| RICH | 1.0× | 1.5× | 经济重心——产出高但防守薄，优先攻占目标 |
| FORTRESS | 1.5× | 0.75× | 天然要塞——难啃但产出低，适合防守囤兵 |
| BARREN | 0.75× | 0.5× | 垃圾星——拿下意义有限，但连接关键路线时不得不占 |

### 邻接表构建

```gdscript
func _build_adjacency(planets: Dictionary, connections: Array[Connection]) -> void:
    for conn in connections:
        if planets.has(conn.from) and planets.has(conn.to):
            planets[conn.from].adjacent_ids.append(conn.to)
            planets[conn.to].adjacent_ids.append(conn.from)
        else:
            push_warning("Connection references non-existent planet: %d <-> %d" % [conn.from, conn.to])
```

连接是双向的——`Connection{from: 1, to: 2}` 等价于 1↔2。无需在 .tres 中定义两次。

### 初始化流程

```
LevelData (.tres)
  ├── planets: Array[PlanetDef]   ← 星球静态定义
  ├── connections: Array[Connection] ← 连接路线
  └── initial_owner: Dictionary   ← {planet_id: Faction}

PlanetSystem.init_from_level(level_data):
  1. _planets.clear()
  2. for each PlanetDef in level_data.planets:
       _planets[def.id] = _build_runtime_planet(def)
  3. _build_adjacency(_planets, level_data.connections)
  4. for planet_id, faction in level_data.initial_owner:
       _planets[planet_id].owner = faction
       _planets[planet_id].garrison = _get_initial_garrison(faction, planet_id)
  5. EventBus.planets_initialized.emit()
```

`initial_owner` 中未指定的星球默认为 `NEUTRAL`，初始 garrison = 0。

### 与 ADR-0004 快照的接口

```gdscript
# TurnManager._take_snapshot() 调用:
func take_snapshot() -> Dictionary:
    var snap = {}
    for id in _planets:
        snap[id] = _planets[id].duplicate(true)  # 深拷贝 Dictionary
    return snap
```

Dictionary 的 `.duplicate(true)` 原生深拷贝，无 Godot 版本兼容风险。

## Alternatives Considered

### Alternative 1: 全 Resource 方案（PlanetDef + RuntimePlanetData 都是 Resource）

- **Description**: 运行时星球也定义为 `class RuntimePlanetData extends Resource`，`@export` 字段在编辑器中可见
- **Pros**: 类型安全强（`planet.garrison` 编译期检查 vs `planet["garrison"]` 运行时查找）；Godot Inspector 可调试
- **Cons**: Resource 深拷贝语义在 4.5 变更（`duplicate(true)` → `duplicate_deep()`）；10 颗星的 Dictionary 已经够用；Resource 对象的 `@export` 调试优势在运行时数据上意义有限
- **Rejection Reason**: ADR-0004 快照模型要求深拷贝星球状态。Dictionary `.duplicate(true)` 在整个 Godot 4.x 生命周期内行为一致。Resource 深拷贝的 API 变更（4.5）引入不必要风险。待项目进入 Production 且引擎版本锁定后可重新评估。

### Alternative 2: Array[RuntimePlanetData] 而非 Dictionary

- **Description**: `_planets: Array[Dictionary]`，按索引访问
- **Pros**: 序列化时自然保序；遍历略快
- **Cons**: `get_planet(id)` 需要 O(N) 查找；删除星球后索引断档
- **Rejection Reason**: `planet_id` 是关卡数据中的稳定标识符。Dictionary 提供 O(1) 按 ID 查找。MVP 10 颗星 O(N) 也可接受，但 Dictionary 语义更清晰（"查第 3 号星球" vs "查数组第 3 个"）。

### Alternative 3: 单向连接 + 方向性移动规则

- **Description**: `Connection` 只定义 `from → to`，移动只能沿连接方向
- **Pros**: 支持"单向传送门"式关卡设计
- **Cons**: MVP 不需要单向路线；增加出征校验复杂度；AI 寻路需处理有向图
- **Rejection Reason**: MVP 所有路线双向通行。若未来需要单向路线（如"只能进不能出的黑洞星"），可在 Connection 中增加 `is_bidirectional: bool` 字段——不影响当前数据结构。

## Consequences

### Positive

- **静态/动态分离清晰**: `PlanetDef` 是关卡设计产物（不变），`_planets[id]` 是运行时状态（可变）。修改关卡布局不影响运行时逻辑，反之亦然。
- **快照零风险**: Dictionary `.duplicate(true)` 深拷贝行为在 Godot 4.x 全版本一致，无 4.5 破坏性变更影响。
- **邻接查询 O(1)**: `are_connected(a, b)` 只需检查 `a.adjacent_ids.has(b)`，不需要遍历全连接表。
- **属性效果可调**: `ATTR_GARRISON_MULT` 和 `ATTR_PRODUCTION_MULT` 定义在 PlanetSystem 常量中，后续可迁至 .tres。
- **归属变更可追踪**: 每次 `set_owner()` 通过 EventBus 广播，UI 和 AI 自动收到更新。

### Negative

- **Dictionary 无编译期字段检查**: `planet["garrsion"]`（拼写错误）编译期不报错。缓解：所有访问通过 `get_planet()` / `update_garrison()` 封装方法，内部用常量 key 名（`const KEY_GARRISON = "garrison"`）。
- **get_planet() 返回浅拷贝有分配开销**: 每次查询创建新 Dictionary。缓解：MVP 10 星球、每回合 ~20 次查询，开销可忽略。高频路径（如 AI 遍历评估）可使用 `get_all_planets()` 一次获取全量。
- **属性乘数散落在 PlanetSystem 而非 DataDef**: 它们本质上是全局常量，理想位置是 DataDef。缓解：当前放 PlanetSystem 以降低 DataDef 的修改频率；若被多个系统引用则迁至 DataDef。

### Risks

- **`get_planet()` 返回浅拷贝，嵌套结构可能被意外修改**: `get_planet(id).adjacent_ids.append(x)` 会修改 `_planets[id].adjacent_ids`（Array 是引用类型）。缓解：文档明确 `get_planet()` 返回值只读；需要修改走 `update_garrison()` / `set_owner()`。
- **RuntimePlanetData 字段随系统增加而膨胀**: 若未来添加新字段（如 `tech_level`, `is_under_siege`），所有引用 Dictionary 的代码需检查。缓解：字段增删通过 PlanetSystem API 封装，不直接暴露 `_planets`。

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| 星球系统 | 星球数据模型定义 | PlanetDef (静态) + RuntimePlanetData Dictionary (动态) 双结构 |
| 生产系统 | 每回合按星球属性产兵 | `production_rate` 字段，由属性乘数计算 |
| 占领系统 | 战后归属变更 | `set_owner(id, faction)` → EventBus 广播 |
| 出征系统 | 校验出征目标相邻 | `are_connected(a, b)` O(1) 邻接查询 |
| AI 敌人 | 评估星球价值和可达性 | `get_planets_by_owner()` + `get_adjacent_planets()` |
| 星图数据 | 关卡布局定义 | `PlanetDef` + `Connection` Resource (.tres) |

## Performance Implications

- **CPU**: 10 星规模下所有操作 O(1) 或 O(N)（N ≤ 10），无测量意义
- **Memory**: RuntimePlanetData ×10 ≈ 2KB；快照同样大小，回合结束即释放
- **Load Time**: `init_from_level()` 遍历 10 个 PlanetDef + 构建邻接表 < 1ms
- **Network**: 不适用

## Migration Plan

不适用 — 新项目。

## Validation Criteria

- `init_from_level(level_data)` 后 `_planets.size()` = `level_data.planets.size()`
- 每个 RuntimePlanetData 的 `adjacent_ids` 与 LevelData.connections 一致（双向）
- `set_owner(id, faction)` 后 `get_planet(id).owner == faction`，且 `EventBus.planet_owner_changed` 被 emit
- `update_garrison(id, +5)` 后 garrison 增加 5；`update_garrison(id, -999)` 返回 false（不会负数）
- `are_connected(a, b)` → `are_connected(b, a)` 始终一致
- `take_snapshot()` 返回的 Dictionary 修改不影响 `_planets`（深拷贝验证）
- `get_planets_by_owner(PLAYER)` 只返回玩家拥有的星球

## Related Decisions

- ADR-0002: 数据定义格式 — `PlanetDef`, `Connection` Resource 类定义在 DataDef 中
- ADR-0004: 回合结算模型 — `take_snapshot()` 深拷贝 RuntimePlanetData
- ADR-0006: 战斗公式设计 — 防守方星球 FORTRESS 属性影响伤害计算
- ADR-0007: AI 决策架构 — AI 通过 `get_planets_by_owner()` 和 `get_adjacent_planets()` 评估局势
- `docs/architecture/architecture.md` — Module Ownership: 星球系统, Phase 3 数据流场景 1-3
