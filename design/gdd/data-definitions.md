# 数据定义 (Data Definitions)

> **Status**: In Design
> **Author**: Claude + 老大
> **Last Updated**: 2026-05-31
> **Implements Pillar**: 间接 — 纯基础设施，支撑所有系统

## Overview

数据定义系统是星辰之轭的**类型系统基础**。它集中管理所有枚举（`UnitType`、`Faction`、`PlanetAttribute`、`TalentType`）、全局常量表（三角克制矩阵、产量参数）以及结构化数据 Resource 类（`UnitStats`、`LevelData`）。所有其他系统通过 `DataDef` autoload 统一访问，不持有独立的数据副本。

数据格式遵循 [ADR-0002](../docs/architecture/adr/adr-0002-data-definition-format.md)：结构定义（枚举、常量表）使用 GDScript 编译期类型安全；可调数值（兵种属性、关卡布局）使用 Godot `.tres` Resource，设计师可在编辑器中独立调整。

没有这个系统，每个模块会各自定义自己的 `UnitType` 枚举和伤害公式——出现不一致时极难排查。

## Player Fantasy

数据定义是纯基础设施系统，玩家不直接感知。其价值体现在它支撑的系统（兵种克制、星球属性、关卡多样性）的一致性和可维护性中。玩家感受到的是"规则清晰、数值合理"，而不是数据定义本身。

## Detailed Design

### Core Rules

**规则 1: DataDef autoload 是唯一数据入口**

所有系统通过 `DataDef` autoload 访问游戏数据。禁止在系统文件中重复定义枚举或硬编码数值。枚举和常量在 GDScript 中定义（编译期类型安全），可调数值存储在 `.tres` Resource 文件中（设计师可在编辑器中独立调整）。

**规则 2: 枚举定义**

| 枚举 | 值 | 说明 |
|------|-----|------|
| `UnitType` | `INFANTRY`, `ARCHER`, `CAVALRY` | 三种基础兵种，MVP 不变 |
| `Faction` | `NEUTRAL`, `PLAYER`, `ENEMY` | MVP 两个势力 + 中立星 |
| `PlanetAttribute` | `NORMAL`, `RICH`, `FORTRESS`, `BARREN` | 影响产量和防守加成 |
| `TalentType` | `CONQUEROR`, `RESEARCHER`, `HOARDER`, `DIPLOMAT` | 国王天赋类型 |

**规则 3: 三角克制矩阵**

```
DAMAGE_MATRIX[attacker][defender]:
               INF  ARC  CAV
    INFANTRY   1.0  1.5  0.75
    ARCHER     0.75 1.0  1.5
    CAVALRY    1.5  0.75 1.0
```

- 克制链: 步 → 弓 → 骑 → 步
- 有利: 1.5× (50% 增伤)
- 不利: 0.75× (25% 减伤)
- 同类型: 1.0× (无修正)
- 矩阵以 `Dictionary` 形式存储在 GDScript `const` 中，不放入 .tres（它是逻辑规则，不是可调数值）

**规则 4: 全局常量**

| 常量 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `PRODUCTION_BASE_RATE` | float | 1.0 | 每回合基础产兵数 |
| `GARRISON_DEFAULT_MAX` | int | 20 | 星球默认驻兵上限 |
| `KING_DEFAULT_LIFESPAN` | int | 30 | 初始国王寿命（回合数） |

**规则 5: Resource 类定义**

以下类定义为 Godot `Resource` 脚本（`.gd` 文件），实例化为 `.tres` 文件，设计师在 Godot 编辑器的 Inspector 中直接调整数值：

```gdscript
# UnitStatsTable — 兵种属性表
class_name UnitStatsTable extends Resource
@export var infantry: UnitStats
@export var archer: UnitStats
@export var cavalry: UnitStats

# UnitStats — 单个兵种属性
class_name UnitStats extends Resource
@export var unit_type: DataDef.UnitType
@export var attack: float = 10.0
@export var defense: float = 8.0
@export var move_speed: float = 1.0

# LevelData — 关卡定义
class_name LevelData extends Resource
@export var level_id: String
@export var planets: Array[PlanetDef]
@export var connections: Array[Connection]
@export var initial_owner: Dictionary  # {planet_id: Faction}

# PlanetDef — 星球定义
class_name PlanetDef extends Resource
@export var id: int
@export var name: String
@export var position: Vector2
@export var attribute: DataDef.PlanetAttribute

# Connection — 星球间连接
class_name Connection extends Resource
@export var from: int
@export var to: int
```

**访问模式**: DataDef `_ready()` 中一次性 `load()` 所有 .tres 文件，缓存为成员变量。运行时不产生额外文件 I/O。

### States and Transitions

不适用 — 数据定义是纯声明系统，无状态。

### Interactions with Other Systems

数据流向为**单向只读**。DataDef 不订阅任何事件，不持有任何逻辑，不主动修改数据。

| 消费方 | 访问内容 | 访问方式 |
|--------|---------|---------|
| 兵种系统 | `UnitType`, `DAMAGE_MATRIX`, `UnitStatsTable` | `DataDef.UnitType.INFANTRY`, `DataDef.DAMAGE_MATRIX[...]`, `DataDef.unit_stats.infantry` |
| 星球系统 | `Faction`, `PlanetAttribute`, `GARRISON_DEFAULT_MAX` | `DataDef.Faction.PLAYER`, `DataDef.PlanetAttribute.RICH` |
| 战斗结算 | `DAMAGE_MATRIX`, `UnitStatsTable` | 通过兵种系统间接引用（不直接访问 DataDef） |
| 生产系统 | `PRODUCTION_BASE_RATE` | `DataDef.PRODUCTION_BASE_RATE` |
| 星图数据 | `LevelData`, `PlanetDef`, `Connection` | `DataDef.level_data` |
| 国王系统 | `TalentType`, `KING_DEFAULT_LIFESPAN` | `DataDef.TalentType.CONQUEROR`, `DataDef.KING_DEFAULT_LIFESPAN` |
| AI 敌人 | `Faction`, `UnitType` | 通过兵种和星球系统间接引用 |

**加载顺序**: `DataDef` 设为 autoload 列表第一位。`_ready()` 中 `load()` 所有 `.tres` 文件，确保其他 autoload 初始化时数据已可用。

## Formulas

数据定义本身不含公式——它提供公式所需的**输入值**：

- `DAMAGE_MATRIX[attacker][defender]` → 战斗结算系统引用为伤害倍率
- `PRODUCTION_BASE_RATE` → 生产系统引用为基础产兵速率
- `UnitStats.attack / defense` → 战斗结算系统引用为攻防基础值

具体公式（伤害计算、产量计算）属于各消费系统的 GDD，不在此定义。

## Edge Cases

- **若枚举新增值**（如新增 `UnitType.MAGE`）：必须在 `DAMAGE_MATRIX` 中为新类型添加一行一列；必须创建对应的 `UnitStats` Resource。MVP 阶段不新增兵种类型。
- **若 Resource 类新增字段**：旧 `.tres` 文件加载时新字段使用 `@export var` 的默认值。已有字段不可删除或重命名——用 `@deprecated` 标记废弃字段，保留原字段直到确认所有 .tres 文件已迁移。
- **若 DAMAGE_MATRIX 被修改为不对称矩阵**：设计评审必须验证克制链仍然闭合并有清晰的博弈逻辑。MVP 使用对称矩阵（1.5 / 1.0 / 0.75），修改需 `game-designer` 签字。
- **若 DataDef `_ready()` 中 load() 失败**：`.tres` 文件缺失或损坏 → `push_error()` 输出具体文件名 + 游戏不启动（而非静默加载空数据）。
- **Resource.duplicate() 深拷贝 (4.5 行为变更)**：如需运行时复制 Resource，使用 `duplicate_deep(DEEP_DUPLICATE_ALL)` 而非旧版 `duplicate(true)`。见 ADR-0002 Engine Compatibility。

## Dependencies

**上游（本系统依赖）**: 无。数据定义是 Foundation 层第一个系统，零依赖。

**下游（依赖本系统的系统）**:

| 系统 | 依赖类型 | 依赖内容 |
|------|---------|---------|
| 星球系统 | Hard | `Faction`, `PlanetAttribute`, `GARRISON_DEFAULT_MAX` |
| 兵种系统 | Hard | `UnitType`, `DAMAGE_MATRIX`, `UnitStatsTable` |
| 生产系统 | Hard | `PRODUCTION_BASE_RATE` |
| 战斗结算 | Soft | `DAMAGE_MATRIX`（通过兵种系统间接访问） |
| AI 敌人 | Soft | `UnitType`, `Faction`（通过星球和兵种系统间接访问） |
| 星图数据 | Hard | `LevelData`, `PlanetDef`, `Connection` Resource 类定义 |
| 国王系统 | Hard | `TalentType`, `KING_DEFAULT_LIFESPAN` |

**Hard vs Soft**: Hard = 系统无法运行缺少该数据。Soft = 可通过其他系统间接获取。

## Tuning Knobs

| Knob | 位置 | 安全范围 | 过高后果 | 过低后果 |
|------|------|---------|---------|---------|
| `UnitStats.attack` | .tres | 5.0 – 30.0 | 某兵种碾压一切，克制无意义 | 战斗永远打不完 |
| `UnitStats.defense` | .tres | 3.0 – 20.0 | 防守方无敌，进攻无意义 | 任何攻击都是秒杀 |
| `UnitStats.move_speed` | .tres | 0.5 – 3.0 | 无影响（回合制同时到达） | 无影响 |
| `PRODUCTION_BASE_RATE` | GDScript const | 0.5 – 5.0 | 暴兵太快，策略沦为堆量 | 产兵太慢，节奏拖沓 |
| `GARRISON_DEFAULT_MAX` | GDScript const | 10 – 50 | 防守过强，无人进攻 | 驻兵上限无策略意义 |
| `DAMAGE_MATRIX` 倍率 | GDScript const | 1.25× – 2.0× (有利) | 克制 = 必赢，无战术空间 | 克制无感知，兵种选择无差异 |
| `LevelData` 中星球位置 | .tres | — | 位置重叠导致视觉混乱 | 间距过大星图空旷 |

**格式选择原则**: `DAMAGE_MATRIX` 和全局常量放 GDScript —— 修改它们意味着核心规则变更，应走 code review。`UnitStats` 和 `LevelData` 放 `.tres` —— 修改它们是平衡调整和关卡设计，设计师应能直接在编辑器中操作。

## Visual/Audio Requirements

不适用 — 数据定义无视觉或音频输出。

## UI Requirements

不适用 — 数据定义无用户界面。

## Acceptance Criteria

- **GIVEN** 游戏启动，**WHEN** DataDef autoload 初始化完成，**THEN** `DataDef.unit_stats` 非 null，`DataDef.level_data` 非 null
- **GIVEN** GDScript 代码中引用 `DataDef.UnitType.INFANTRY`，**WHEN** 编译，**THEN** 无类型错误，IDE 自动补全列出全部 3 种兵种
- **GIVEN** 修改 `unit_stats.tres` 中步兵 `attack` 从 10.0 改为 12.0，**WHEN** 重启游戏，**THEN** `DataDef.unit_stats.infantry.attack` 返回 12.0
- **GIVEN** `DAMAGE_MATRIX[INFANTRY][ARCHER]` 查找，**WHEN** 执行，**THEN** 返回 1.5（步克弓有利）
- **GIVEN** 任意系统 `.gd` 文件，**WHEN** 搜索硬编码数值模式，**THEN** 所有游戏数值均通过 `DataDef` 引用（无裸 `attack = 10.0`）
- **GIVEN** LevelData .tres 定义了 4 颗星球和 4 条连接，**WHEN** `DataDef.level_data.planets.size()`，**THEN** 返回 4
- **GIVEN** 加载的 .tres 文件格式损坏或缺失，**WHEN** DataDef `_ready()` 执行，**THEN** `push_error()` 输出具体文件名 + 游戏不进入 PLAYING 状态

## Open Questions

无 — MVP 范围的数据定义已完整覆盖。以下延后到 Vertical Slice：
- 是否需要 `UnitType` 之外的兵种子类型？
- `TalentType` 的具体天赋效果（由国王系统 GDD 定义，DataDef 只提供枚举）
- 是否支持多关卡文件切换？（MVP 只有一个 `level_tutorial.tres`）
