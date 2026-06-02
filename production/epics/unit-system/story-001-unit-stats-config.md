# Story 001: 兵种属性数据配置

> **Epic**: 兵种系统 (unit-system)
> **Status**: Ready
> **Layer**: Core
> **Type**: Config/Data
> **Estimate**: 1.5h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/unit-system.md`
**Requirement**: `TR-UNT-001`, `TR-UNT-004`

**ADR Governing Implementation**: ADR-0002: 数据定义格式 (primary — Resource 类定义与 .tres 加载); ADR-0006: 战斗公式设计 (secondary — 兵种属性被战斗公式消费)
**ADR Decision Summary**: 兵种属性存储在 `unit_stats.tres` Resource 中（设计师可编辑），通过 `DataDef.unit_stats` 访问。Resource 类（`UnitStats`, `UnitStatsTable`）已在 DataDef 中定义（TR-DEF-008），本 Story 创建实例文件。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `.tres` Resource 文件格式在 Godot 4.x 稳定。`@export` 字段在编辑器中可视化编辑。

**Control Manifest Rules (this layer)**:
- Required: 可调数值用 .tres Resource — `unit_stats.tres` 中的 attack/defense/move_speed 设计师可调
- Required: DataDef autoload 是唯一数据入口 — 所有系统通过 `DataDef.unit_stats` 访问兵种属性
- Forbidden: 禁止在系统文件中硬编码兵种数值 — 一切通过 DataDef 引用
- Guardrail: DataDef `load()` 在 `_ready()` 中一次性完成

---

## Acceptance Criteria

*From GDD `design/gdd/unit-system.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN 游戏启动，WHEN DataDef 初始化完成，THEN `DataDef.unit_stats.infantry.attack == 10.0`
- [ ] **AC-2**: GIVEN `DataDef.unit_stats.archer.defense` 查询，WHEN 执行，THEN 返回 5.0
- [ ] **AC-3**: GIVEN `DataDef.unit_stats.cavalry` 查询，WHEN 执行，THEN attack=15.0, defense=6.0, move_speed=1.5
- [ ] **AC-4**: GIVEN 修改 `unit_stats.tres` 中步兵 attack 为 12.0，WHEN 重启游戏，THEN `DataDef.unit_stats.infantry.attack` 返回 12.0

---

## Implementation Notes

*Derived from ADR-0002 and ADR-0006 Implementation Guidelines:*

### 创建 .tres 文件

在 Godot 编辑器中（或手动文本）创建 `assets/data/unit_stats.tres`：

```gdscript
[gd_resource type="Resource" script_class="UnitStatsTable" load_steps=5 format=3 uid="uid://c0ffee0001"]

[ext_resource type="Script" path="res://src/core/data/unit_stats.gd" id="1_units"]
[ext_resource type="Script" path="res://src/core/data/unit_stats_table.gd" id="2_table"]

[sub_resource type="Resource" script="1_units" id="infantry"]
unit_type = 0  # INFANTRY
attack = 10.0
defense = 8.0
move_speed = 1.0

[sub_resource type="Resource" script="1_units" id="archer"]
unit_type = 1  # ARCHER
attack = 12.0
defense = 5.0
move_speed = 1.2

[sub_resource type="Resource" script="1_units" id="cavalry"]
unit_type = 2  # CAVALRY
attack = 15.0
defense = 6.0
move_speed = 1.5

[resource]
script = "res://src/core/data/unit_stats_table.gd"
infantry = SubResource("infantry")
archer = SubResource("archer")
cavalry = SubResource("cavalry")
```

> ⚠️ 以上为手动 .tres 文本格式。推荐在 Godot 编辑器中通过 Inspector 创建，可避免 UID 和路径错误。

### DataDef 加载

在 `data_def.gd` 的 `_ready()` 中添加（此代码可能已在 Foundation data-definitions 中实现——本 Story 验证它）：

```gdscript
# DataDef autoload
var unit_stats: UnitStatsTable

func _ready() -> void:
    unit_stats = load("res://assets/data/unit_stats.tres") as UnitStatsTable
    if unit_stats == null:
        push_error("Failed to load unit_stats.tres")
```

### 数值参考表

| 兵种 | UnitType | attack | defense | move_speed |
|------|----------|--------|---------|------------|
| 步兵 | INFANTRY (0) | 10.0 | 8.0 | 1.0 |
| 弓兵 | ARCHER (1) | 12.0 | 5.0 | 1.2 |
| 骑兵 | CAVALRY (2) | 15.0 | 6.0 | 1.5 |

### 关键实现要点

- `UnitStats` 和 `UnitStatsTable` Resource 类由 Foundation data-definitions (TR-DEF-008) 定义。本 Story 不重新定义这些类——只创建 `.tres` 实例文件
- `unit_stats.tres` 文件路径建议 `assets/data/unit_stats.tres`（或 `res://data/unit_stats.tres`，与项目目录约定一致）
- `move_speed` 在 MVP 中不影响战斗（回合制同时到达），保留为 Vertical Slice 扩展
- `.tres` 加载失败 → `push_error()` + 游戏不进入 PLAYING 状态（遵循 TR-DEF-011 规则）
- 如果 Foundation data-definitions Story 尚未实现 `UnitStatsTable`/`UnitStats` 类，本 Story BLOCKED——必须先完成 TR-DEF-008

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: `get_counter()` / `get_weak_against()` 克制查询函数、DAMAGE_MATRIX 验证、MVP 默认 INFANTRY 规则
- Foundation data-definitions: `UnitStats` / `UnitStatsTable` Resource 类定义、`UnitType` 枚举、`DAMAGE_MATRIX` 常量
- 战斗结算: 使用 `unit_stats` 进行实际战斗计算

---

## QA Test Cases

*Derived from GDD acceptance criteria. The developer implements against these.*

- **AC-1**: 步兵属性加载验证
  - Given: 游戏启动，DataDef._ready() 完成
  - When: 访问 `DataDef.unit_stats.infantry`
  - Then: `attack == 10.0`, `defense == 8.0`, `move_speed == 1.0`, `unit_type == UnitType.INFANTRY`

- **AC-2**: 弓兵防御力验证
  - Given: DataDef 初始化完成
  - When: 访问 `DataDef.unit_stats.archer.defense`
  - Then: 返回 5.0

- **AC-3**: 骑兵全属性验证
  - Given: DataDef 初始化完成
  - When: 访问 `DataDef.unit_stats.cavalry`
  - Then: `attack == 15.0`, `defense == 6.0`, `move_speed == 1.5`

- **AC-4**: .tres 热重载验证
  - Given: 修改 `unit_stats.tres` 中 infantry.attack = 12.0，重启游戏
  - When: 访问 `DataDef.unit_stats.infantry.attack`
  - Then: 返回 12.0（证明数值来自 .tres 而非硬编码）
  - Edge cases: .tres 文件缺失 → `push_error()` + 游戏不启动

---

## Test Evidence

**Story Type**: Config/Data
**Required evidence**:
- Config/Data: smoke check pass (`production/qa/smoke-*.md`)

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Foundation data-definitions — TR-DEF-002 (UnitType 枚举), TR-DEF-008 (UnitStats/UnitStatsTable Resource 类), TR-DEF-012 (DataDef autoload) — must be DONE
- Unlocks: Story 002 (unit-counter-mvp)
