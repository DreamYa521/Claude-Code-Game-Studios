# Story 002: Resource Classes Definition

> **Epic**: data-definitions
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Config/Data
> **Estimate**: 2h
> **Manifest Version**: 2026-05-31
> **Last Updated**: —

## Context

**GDD**: `design/gdd/data-definitions.md`
**Requirement**: TR-DEF-008, TR-DEF-009, TR-DEF-014
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0002: 数据定义格式
**ADR Decision Summary**: 混合方案 — 可调数值（兵种属性、关卡布局）使用 Godot `.tres` Resource，设计师在 Inspector 中直接调整。Resource 类定义在 GDScript 中 (`class_name extends Resource`)，实例化为 `.tres` 文件。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Resource.duplicate(true)` 语义在 4.5 变更 — 运行时复制 Resource 必须用 `duplicate_deep(DEEP_DUPLICATE_ALL)` 替代旧版 `duplicate(true)`。

**Control Manifest Rules (this layer)**:
- Required: UnitStats/LevelData 等结构化数据定义为 Resource 类
- Required: Runtime Resource 深拷贝使用 `duplicate_deep(DEEP_DUPLICATE_ALL)`
- Forbidden: 禁止 `Resource.duplicate(true)` 做深拷贝 — 4.5+ 只复制内部资源
- Forbidden: Resource 类字段只增不删不重命名
- Guardrail: Resource 内存占用 < 50KB

---

## Acceptance Criteria

*From GDD `design/gdd/data-definitions.md`, scoped to this story:*

- [ ] **AC-1**: `UnitStatsTable` 和 `UnitStats` Resource 类定义存在，`UnitStats` 包含 `unit_type`、`attack`、`defense`、`move_speed` 四个 `@export` 字段
- [ ] **AC-2**: `LevelData`、`PlanetDef`、`Connection` Resource 类定义存在，字段与 GDD 规则 5 一致
- [ ] **AC-3**: 所有 `@export` 字段有默认值（符合 GDD 中规定的默认值）
- [ ] **AC-4**: Resource 类注释中包含 `duplicate_deep(DEEP_DUPLICATE_ALL)` 使用提醒（为后续运行时复制场景留文档）

---

## Implementation Notes

*Derived from ADR-0002:*

**1. 创建 `resources/` 目录**（如尚未存在），编写以下 Resource 类 .gd 文件：

**unit_stats.gd — UnitStatsTable**:
```gdscript
# unit_stats_table.gd
class_name UnitStatsTable extends Resource
## 兵种属性表 — 包含三种兵种的完整属性
@export var infantry: UnitStats
@export var archer: UnitStats
@export var cavalry: UnitStats
```

**unit_stats_entry.gd — UnitStats**:
```gdscript
# unit_stats.gd
class_name UnitStats extends Resource
## 单个兵种属性 — attack/defense 用于战斗公式，move_speed 预留
@export var unit_type: DataDef.UnitType
@export var attack: float = 10.0
@export var defense: float = 8.0
@export var move_speed: float = 1.0
```

**level_data.gd — LevelData**:
```gdscript
# level_data.gd
class_name LevelData extends Resource
## 关卡定义 — 包含星球列表、连接线、初始归属
@export var level_id: String = ""
@export var planets: Array[PlanetDef] = []
@export var connections: Array[Connection] = []
@export var initial_owner: Dictionary = {}  # {planet_id: Faction}
```

**planet_def.gd — PlanetDef**:
```gdscript
# planet_def.gd
class_name PlanetDef extends Resource
## 星球静态定义 — id/name/position/attribute 在 .tres 中配置
@export var id: int = 0
@export var name: String = ""
@export var position: Vector2 = Vector2.ZERO
@export var attribute: DataDef.PlanetAttribute = DataDef.PlanetAttribute.NORMAL
```

**connection.gd — Connection**:
```gdscript
# connection.gd
class_name Connection extends Resource
## 星球间连接线 — from/to 对应 PlanetDef.id
@export var from: int = 0
@export var to: int = 0
```

**2. 深拷贝规范**:
- 如需运行时复制 Resource，使用 `resource.duplicate_deep(DEEP_DUPLICATE_ALL)`
- 禁止使用 `duplicate(true)`（Godot 4.5+ 行为不同）
- 在代码注释中标注此规则，确保所有开发者知晓

**3. .tres 实例化**（本 Story 只定义类，实例 .tres 在 Story 003 中创建）:
- `resources/unit_stats.tres` — UnitStatsTable 实例
- `resources/levels/tutorial_1.tres` — LevelData 实例

**4. 文件组织**:
```
src/data/
├── data_definitions.gd       # Story 001 产物（autoload: DataDef）
├── unit_stats_table.gd       # UnitStatsTable Resource 类
├── unit_stats.gd             # UnitStats Resource 类
├── level_data.gd             # LevelData Resource 类
├── planet_def.gd             # PlanetDef Resource 类
└── connection.gd             # Connection Resource 类

resources/
├── unit_stats.tres           # 实例化（Story 003）
└── levels/
    └── tutorial_1.tres       # 实例化（Story 003）
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: 枚举定义和常量表（UnitType, Faction, DAMAGE_MATRIX 等）
- Story 003: `DataDef._ready()` 中 load() 所有 .tres 文件、创建具体 .tres 实例、错误处理
- 具体的 `unit_stats.tres` 实例化数据和 `tutorial_1.tres` 关卡数据 — 属于 Story 003

---

## QA Test Cases

- **AC-1**: UnitStatsTable/UnitStats 类定义完整性
  - Given: `src/data/unit_stats_table.gd` 和 `src/data/unit_stats.gd` 存在
  - When: Godot 编辑器加载项目
  - Then: `UnitStatsTable` 和 `UnitStats` 在 classdb 中可识别；Inspector 中创建新 Resource 时可选择这两个类型
  - Edge cases: `UnitStats.unit_type` 字段类型为 `DataDef.UnitType`，在 Inspector 中应显示为下拉菜单选择 INFANTRY/ARCHER/CAVALRY

- **AC-2**: LevelData/PlanetDef/Connection 类定义完整性
  - Given: `src/data/level_data.gd`、`src/data/planet_def.gd`、`src/data/connection.gd` 存在
  - When: 在 Godot 编辑器中创建新 `LevelData` Resource
  - Then: Inspector 显示 `level_id`(String)、`planets`(Array[PlanetDef])、`connections`(Array[Connection])、`initial_owner`(Dictionary) 四个字段
  - Edge cases: `PlanetDef.position` 类型为 `Vector2`，Inspector 中显示 x/y 两个子字段

- **AC-3**: 默认值验证
  - Given: 新建 `UnitStats` Resource 实例
  - When: 查看 Inspector
  - Then: `attack=10.0`, `defense=8.0`, `move_speed=1.0`
  - Edge cases: `LevelData.level_id` 默认为空字符串 `""`, `PlanetDef.attribute` 默认为 `NORMAL`

- **AC-4**: 深拷贝文档标注
  - Given: Resource 类 .gd 文件或邻近注释
  - When: 搜索 `duplicate_deep` 关键字
  - Then: 存在注释说明运行时深拷贝使用 `duplicate_deep(DEEP_DUPLICATE_ALL)` 而非 `duplicate(true)`
  - Edge cases: N/A（文档约定检查）

---

## Test Evidence

**Story Type**: Config/Data
**Required evidence**:
- Config/Data: smoke check pass (`production/qa/smoke-*.md`)

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (Enums & Constants Definition) — 需要 `DataDef.UnitType`、`DataDef.PlanetAttribute` 枚举类型
- Unlocks: Story 003 (Resource Loading & Error Handling)
