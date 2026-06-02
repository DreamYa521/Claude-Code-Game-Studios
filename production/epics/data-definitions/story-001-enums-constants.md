# Story 001: Enums & Constants Definition

> **Epic**: data-definitions
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Logic
> **Estimate**: 2h
> **Manifest Version**: 2026-05-31
> **Last Updated**: —

## Context

**GDD**: `design/gdd/data-definitions.md`
**Requirement**: TR-DEF-001, TR-DEF-002, TR-DEF-003, TR-DEF-004, TR-DEF-005, TR-DEF-006, TR-DEF-007, TR-DEF-012, TR-DEF-013
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0002: 数据定义格式
**ADR Decision Summary**: 混合方案 — 枚举/常量用 GDScript（编译期类型安全），结构化数据用 Godot Resource (.tres)（设计师可视化编辑）。DataDef autoload 是唯一数据入口。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: GDScript `enum`/`const` 在 4.3→4.6 无破坏性变更。无 post-cutoff API 使用。

**Control Manifest Rules (this layer)**:
- Required: DataDef autoload 是唯一数据入口，枚举和常量用 GDScript，DataDef 设为 autoload 列表第一位
- Required: DAMAGE_MATRIX/全局常量放 GDScript const
- Forbidden: 禁止在系统文件中重复定义枚举或硬编码数值
- Forbidden: Resource 类字段只增不删不重命名，旧字段 `@deprecated` 标记保留
- Guardrail: DataDef `load()` 在 `_ready()` 中一次性完成，运行时不产生额外开销

---

## Acceptance Criteria

*From GDD `design/gdd/data-definitions.md`, scoped to this story:*

- [ ] **AC-1**: GDScript 代码中引用 `DataDef.UnitType.INFANTRY`，编译无类型错误，IDE 自动补全列出全部 3 种兵种
- [ ] **AC-2**: `DAMAGE_MATRIX[INFANTRY][ARCHER]` 返回 1.5（步克弓有利）；`DAMAGE_MATRIX[ARCHER][INFANTRY]` 返回 0.75（弓被步克不利）
- [ ] **AC-3**: `DataDef.Faction.PLAYER`、`DataDef.PlanetAttribute.RICH`、`DataDef.TalentType.CONQUEROR` 引用正常，IDE 自动补全列出所有枚举值
- [ ] **AC-4**: `DataDef.PRODUCTION_BASE_RATE == 1.0`、`DataDef.GARRISON_DEFAULT_MAX == 20`、`DataDef.KING_DEFAULT_LIFESPAN == 30`
- [ ] **AC-5**: 任意系统 `.gd` 文件搜索硬编码数值模式，所有游戏数值均通过 `DataDef` 引用（无裸 `attack = 10.0`）
- [ ] **AC-6**: DataDef 在 autoload 列表中注册为第一位（或与 EventBus 同为最高优先级）

---

## Implementation Notes

*Derived from ADR-0002:*

**1. 创建 `data_definitions.gd` — autoload: DataDef**

```gdscript
# data_definitions.gd — autoload: DataDef
extends Node

# === 枚举（编译期类型安全）===
enum UnitType { INFANTRY, ARCHER, CAVALRY }
enum Faction { NEUTRAL, PLAYER, ENEMY }
enum PlanetAttribute { NORMAL, RICH, FORTRESS, BARREN }
enum TalentType { CONQUEROR, RESEARCHER, HOARDER, DIPLOMAT }

# === 常量表 ===
const DAMAGE_MATRIX: Dictionary = {
    UnitType.INFANTRY: {UnitType.INFANTRY: 1.0, UnitType.ARCHER: 1.5, UnitType.CAVALRY: 0.75},
    UnitType.ARCHER:   {UnitType.INFANTRY: 0.75, UnitType.ARCHER: 1.0, UnitType.CAVALRY: 1.5},
    UnitType.CAVALRY:  {UnitType.INFANTRY: 1.5, UnitType.ARCHER: 0.75, UnitType.CAVALRY: 1.0},
}

# === 全局常量 ===
const PRODUCTION_BASE_RATE: float = 1.0
const GARRISON_DEFAULT_MAX: int = 20
const KING_DEFAULT_LIFESPAN: int = 30
```

**2. DAMAGE_MATRIX 结构**:
- 外层 key: attacker `UnitType`
- 内层 key: defender `UnitType`
- 值: float 倍率（1.5=有利, 1.0=同类型, 0.75=不利）
- 克制链: 步→弓→骑→步
- 存储为 GDScript `const Dictionary`，不放入 .tres（它是逻辑规则，不是可调数值）

**3. 命名空间访问模式**:
- 枚举: `DataDef.UnitType.INFANTRY`（IDE 自动补全）
- 常量: `DataDef.DAMAGE_MATRIX[a][d]`、`DataDef.PRODUCTION_BASE_RATE`
- 类型安全: `var t: DataDef.UnitType = DataDef.UnitType.INFANTRY`

**4. autoload 注册**:
- 在 Project Settings → Autoload 中注册 `data_definitions.gd`，名称 `DataDef`
- 设为 autoload 列表第一位（优先级最高）

**5. 字段演化规则（编码规范，非运行时逻辑）**:
- Resource 类字段只增不删不重命名
- 旧字段用 `@deprecated` 标记保留，直到确认所有 .tres 已迁移

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: UnitStatsTable/UnitStats、LevelData/PlanetDef/Connection Resource 类定义
- Story 003: `_ready()` 中 load() 所有 .tres 文件、缓存、错误处理

---

## QA Test Cases

*Written by qa-lead at story creation. The developer implements against these — do not invent new test cases during implementation.*

- **AC-1**: 枚举类型安全与 IDE 自动补全
  - Given: GDScript 文件中声明 `var t: DataDef.UnitType`
  - When: 键入 `DataDef.UnitType.` 触发自动补全
  - Then: 列出 INFANTRY、ARCHER、CAVALRY 三个选项；编译无类型错误
  - Edge cases: 尝试赋非法值（如 `DataDef.Faction.PLAYER`）→ 编译期类型错误

- **AC-2**: DAMAGE_MATRIX 克制关系正确
  - Given: DAMAGE_MATRIX 已定义为 const Dictionary
  - When: 查询 `DAMAGE_MATRIX[UnitType.INFANTRY][UnitType.ARCHER]`
  - Then: 返回 1.5（步克弓有利）
  - Edge cases: 查询所有 9 种组合，验证 3 种同类型=1.0, 3 种有利=1.5, 3 种不利=0.75；克制链闭（步→弓→骑→步）

- **AC-3**: 所有枚举值可引用
  - Given: DataDef autoload 已注册
  - When: 在任意 .gd 文件中引用 `DataDef.Faction.ENEMY`、`DataDef.PlanetAttribute.FORTRESS`、`DataDef.TalentType.HOARDER`
  - Then: 编译通过，值正确（分别为 2、2、2，按枚举定义顺序）
  - Edge cases: Faction 枚举顺序必须为 NEUTRAL=0, PLAYER=1, ENEMY=2

- **AC-4**: 全局常量值正确
  - Given: DataDef autoload 已初始化
  - When: 读取 `PRODUCTION_BASE_RATE`、`GARRISON_DEFAULT_MAX`、`KING_DEFAULT_LIFESPAN`
  - Then: 分别返回 1.0、20、30
  - Edge cases: 常量类型验证 — `PRODUCTION_BASE_RATE` 为 float, 其余为 int

- **AC-5**: 无硬编码数值（代码审查检查）
  - Given: 本 Story 实现完成后的 `data_definitions.gd`
  - When: grep 搜索硬编码游戏数值模式
  - Then: 游戏数值全部通过 const/enum 定义，无裸数字字面量（`.tres` 文件中的默认值除外）

- **AC-6**: autoload 注册正确
  - Given: Project Settings autoload 列表
  - When: 检查列表顺序
  - Then: DataDef 在列表第一位

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- Logic: `tests/unit/data-definitions/test_enums_constants.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: None（Foundation 层第一个系统，零依赖）
- Unlocks: Story 002 (Resource Classes Definition), Story 003 (Resource Loading & Error Handling)
