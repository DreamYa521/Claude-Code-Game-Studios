# Story 001: LevelData / PlanetDef / Connection Resource 类 + tutorial_1.tres

> **Epic**: 星图/关卡数据 (level-data)
> **Status**: Ready
> **Layer**: Feature
> **Type**: Logic + Config/Data
> **Estimate**: 1.5h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/level-data.md`
**Requirement**: `TR-LVL-001`, `TR-LVL-002`, `TR-LVL-004`

**ADR Governing Implementation**: ADR-0002: Resource 类定义走 .tres 混合格式；ADR-0005: PlanetDef + Connection 为关卡静态数据单元
**ADR Decision Summary**: LevelData/PlanetDef/Connection 均定义为 `extends Resource` 类，用 `@export var` 暴露字段。关卡数据存储在 `.tres` 文件中，设计师在 Godot 编辑器中可视化编辑。MVP 只有一个关卡 tutorial_1：4星+3连接+初始分配。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Resource class_name + @export var，纯 Godot 标准模式。.tres 文件手工编写或编辑器创建均可。`@export var planets: Array[PlanetDef]` 需要 PlanetDef 先于 LevelData 定义。

**Control Manifest Rules (this layer)**:
- Required: LevelData Resource 存储在 .tres — 设计师可视化编辑 — source: ADR-0002
- Required: MVP 关卡 tutorial_1：4星+3连接 — 地球(PLAYER)/月球(NEUTRAL)/火星(ENEMY)/火卫一(NEUTRAL) — source: ADR-0005
- Required: PlanetDef.id 关卡内不可重复 — source: ADR-0005
- Guardrail: 2-10 星 MVP，平均 1-3 连接/星

---

## Acceptance Criteria

*From GDD `design/gdd/level-data.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN Godot 编辑器打开，WHEN 查看 `level_data.gd`，THEN 包含 `class_name LevelData extends Resource` 及所有 @export 字段
- [ ] **AC-2**: GIVEN Godot 编辑器打开，WHEN 查看 `planet_def.gd`，THEN 包含 `class_name PlanetDef extends Resource`（id/name/position/attribute）
- [ ] **AC-3**: GIVEN Godot 编辑器打开，WHEN 查看 `connection.gd`，THEN 包含 `class_name Connection extends Resource`（from/to）
- [ ] **AC-4**: GIVEN `tutorial_1.tres` 存在，WHEN 用文本编辑器查看，THEN 包含 4 个 PlanetDef 子资源 + 3 个 Connection 子资源 + initial_owner/initial_garrison
- [ ] **AC-5**: GIVEN `tutorial_1.tres` 加载，WHEN 读取 planets，THEN planets[0].id=1(地球/PLAYER/NORMAL), planets[1].id=2(月球/NEUTRAL/NORMAL), planets[2].id=3(火星/ENEMY/RICH), planets[3].id=4(火卫一/NEUTRAL/BARREN)

---

## Implementation Notes

*Derived from ADR-0002, ADR-0005 and GDD level-data.md:*

### 核心 Resource 类

```gdscript
# planet_def.gd — src/core/planet_def.gd
class_name PlanetDef extends Resource
@export var id: int = 0
@export var name: String = ""
@export var position: Vector2 = Vector2.ZERO
@export var attribute: int = 0  # DataDef.PlanetAttribute.NORMAL
```

```gdscript
# connection.gd — src/core/connection.gd
class_name Connection extends Resource
@export var from: int = 0
@export var to: int = 0
```

```gdscript
# level_data.gd — src/feature/level_data.gd
class_name LevelData extends Resource
@export var level_id: String = ""
@export var level_name: String = ""
@export var planets: Array[PlanetDef] = []
@export var connections: Array[Connection] = []
@export var initial_owner: Dictionary = {}   # {planet_id: int → Faction: int}
@export var initial_garrison: Dictionary = {} # {planet_id: int → garrison: int}
```

### MVP 关卡 .tres

创建 `assets/data/levels/tutorial_1.tres`：

```tres
[gd_resource type="Resource" script_class="LevelData" load_steps=9 format=3 uid=""]

[ext_resource type="Script" path="res://src/feature/level_data.gd" id="1_level_data"]

[sub_resource type="Resource" script="res://src/core/planet_def.gd" id="1_earth"]
id = 1
name = "地球"
position = Vector2(200, 200)
attribute = 0

[sub_resource type="Resource" script="res://src/core/planet_def.gd" id="2_moon"]
id = 2
name = "月球"
position = Vector2(350, 120)
attribute = 0

[sub_resource type="Resource" script="res://src/core/planet_def.gd" id="3_mars"]
id = 3
name = "火星"
position = Vector2(400, 300)
attribute = 1

[sub_resource type="Resource" script="res://src/core/planet_def.gd" id="4_phobos"]
id = 4
name = "火卫一"
position = Vector2(520, 250)
attribute = 3

[sub_resource type="Resource" script="res://src/core/connection.gd" id="c1_2"]
from = 1
to = 2

[sub_resource type="Resource" script="res://src/core/connection.gd" id="c1_3"]
from = 1
to = 3

[sub_resource type="Resource" script="res://src/core/connection.gd" id="c3_4"]
from = 3
to = 4

[resource]
script = ext_resource("1_level_data")
level_id = "tutorial_1"
level_name = "太阳系"
planets = Array[Resource]([SubResource("1_earth"), SubResource("2_moon"), SubResource("3_mars"), SubResource("4_phobos")])
connections = Array[Resource]([SubResource("c1_2"), SubResource("c1_3"), SubResource("c3_4")])
initial_owner = {1: 0, 3: 1}
initial_garrison = {1: 10, 3: 8}
```

### 关键实现要点

- `PlanetDef.attribute` 存 int（对应 `DataDef.PlanetAttribute` 枚举值），不用 String
- `Connection` 不需定义双向 — 邻接表构建在 story-002 `init_from_level()` 中自动镜像
- `@export var planets: Array[PlanetDef]` 用 typed array（Godot 4.5+ 语法）
- `initial_owner` 值为 `DataDef.Faction.PLAYER(0)` / `ENEMY(1)` / `NEUTRAL(2)`
- 未在 initial_owner/initial_garrison 中列出的星球 → 默认 NEUTRAL, garrison=0
- .tres `load_steps` 数 = 1 script + 1 resource + 7 subresources = 9

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: `init_from_level()` 实现（边界校验 + PlanetSystem 集成）
- PlanetSystem 的 `RuntimePlanetData` 构建逻辑
- 关卡切换（MVP 不做）
- Godot 编辑器可视化编辑插件

---

## QA Test Cases

*Derived from GDD acceptance criteria.*

- **AC-1**: LevelData Resource class exists
  - Given: `level_data.gd` compiled
  - When: check class_name
  - Then: `LevelData extends Resource` with fields level_id/level_name/planets/connections/initial_owner/initial_garrison

- **AC-2**: PlanetDef Resource class exists
  - Given: `planet_def.gd` compiled
  - When: check class_name
  - Then: `PlanetDef extends Resource` with fields id/name/position/attribute

- **AC-3**: Connection Resource class exists
  - Given: `connection.gd` compiled
  - When: check class_name
  - Then: `Connection extends Resource` with fields from/to

- **AC-4**: tutorial_1.tres can be loaded
  - Given: `tutorial_1.tres` exists at assets/data/levels/
  - When: `ResourceLoader.load("res://assets/data/levels/tutorial_1.tres")`
  - Then: returns LevelData, planets.size()==4, connections.size()==3

- **AC-5**: tutorial_1 data integrity
  - Given: level_data loaded
  - When: read planets[0-3]
  - Then: id=1 地球 PLAYER/NORMAL(200,200), id=2 月球 NEUTRAL/NORMAL(350,120), id=3 火星 ENEMY/RICH(400,300), id=4 火卫一 NEUTRAL/BARREN(520,250)

---

## Test Evidence

**Story Type**: Logic + Config/Data
**Required evidence**:
- Logic: `tests/unit/level-data/resource_classes_test.gd` — must exist and pass
- Config: `assets/data/levels/tutorial_1.tres` — must exist

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Foundation data-definitions (TR-DEF-003 PlanetAttribute 枚举, TR-DEF-004 Faction 枚举) — must be DONE
- Unlocks: Story 002 (init_from_level integration)
