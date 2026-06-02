# ADR-0002: 数据定义格式

## Status
Accepted

## Date
2026-05-31

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core (数据/Resource 系统) |
| **Knowledge Risk** | LOW — `Resource`, `enum`, `const` 在 4.3→4.6 无破坏性变更 |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md`, `docs/engine-reference/godot/deprecated-apis.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | `Resource.duplicate(true)` 语义变更 (4.5) — 如需深拷贝用 `duplicate_deep(DEEP_DUPLICATE_ALL)` |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (EventBus signal 参数类型依赖数据定义的类型系统) |
| **Enables** | ADR-0005 (星球数据模型), ADR-0006 (战斗公式设计) |
| **Blocks** | 数据定义 GDD, 兵种系统 GDD, 星图数据 GDD |
| **Ordering Note** | 必须在写数据定义和兵种系统 GDD 之前 Accepted |

## Context

### Problem Statement

星辰之轭的游戏数据分为两类：**不变的结构定义**（枚举、克制关系表）和**可调的游戏数值**（兵种属性、产量参数、关卡布局）。这两类数据的存储方式不同——前者需要编译期类型安全，后者需要设计师方便调整。需要决定：哪种数据用哪种格式？

### Constraints

- 枚举（`UnitType`, `Faction`, `PlanetAttribute`）必须在代码中有编译期类型检查
- 设计师应该能不碰代码就调整数值（兵种攻击力、产量公式参数）
- 必须符合架构原则 #3: 数据驱动
- 不引入第三方序列化库
- Godot 4.6 原生能力

### Requirements

- 类型安全的枚举和常量，IDE 自动补全
- 兵种属性表可独立于代码修改
- 关卡数据可在 Godot 编辑器中可视化编辑
- 新数据类型加入时不破坏已有格式

## Decision

**混合方案：枚举/常量用 GDScript，结构化数据用 Godot Resource (.tres)。**

### 数据分层

```
data_definitions.gd (autoload: DataDef)
├── enum UnitType { INFANTRY, ARCHER, CAVALRY }
├── enum Faction { NEUTRAL, PLAYER, ENEMY }
├── enum PlanetAttribute { NORMAL, RICH, FORTRESS, BARREN }
├── const DAMAGE_MATRIX: Dictionary   ← 3×3 克制表
├── const PRODUCTION_BASE_RATE: float ← 全局常量
└── const GARRISON_DEFAULT_MAX: int

unit_stats.tres (Resource)
├── infantry: UnitStats { attack=10, defense=8, move_speed=1.0 }
├── archer:   UnitStats { attack=12, defense=5, move_speed=1.2 }
└── cavalry:  UnitStats { attack=15, defense=6, move_speed=1.5 }

level_*.tres (Resource)
├── planets: Array[PlanetDef] { id, name, position, attribute }
├── connections: Array[Connection] { from, to }
└── initial_owners: Dictionary { planet_id: Faction }
```

**规则**:
- **GDScript `enum`/`const`**: 用于结构定义——不会在游戏运行中被修改的值。枚举、克制矩阵、全局常量。
- **`.tres` Resource**: 用于可调数值——兵种属性、关卡布局、平衡参数。设计师在 Godot 编辑器中直接改。
- 两类数据都通过 `DataDef` autoload 暴露统一访问接口。

### Key Interfaces

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

# === Resource 加载（缓存）===
var unit_stats: UnitStatsTable
var level_data: LevelData

func _ready() -> void:
    unit_stats = load("res://resources/unit_stats.tres") as UnitStatsTable
```

```gdscript
# unit_stats.gd — Resource 类定义
class_name UnitStatsTable extends Resource

@export var infantry: UnitStats
@export var archer: UnitStats
@export var cavalry: UnitStats

# unit_stats_entry.gd
class_name UnitStats extends Resource
@export var unit_type: DataDef.UnitType
@export var attack: float = 10.0
@export var defense: float = 8.0
@export var move_speed: float = 1.0
```

```gdscript
# level_data.gd — Resource 类定义
class_name LevelData extends Resource
@export var level_id: String
@export var planets: Array[PlanetDef]
@export var connections: Array[Connection]
@export var initial_owner: Dictionary  # {planet_id: Faction}

class_name PlanetDef extends Resource
@export var id: int
@export var name: String
@export var position: Vector2
@export var attribute: DataDef.PlanetAttribute

class_name Connection extends Resource
@export var from: int
@export var to: int
```

### 访问模式

所有系统通过 `DataDef` autoload 统一访问：

```gdscript
# 枚举 — 编译期检查
var unit_type: DataDef.UnitType = DataDef.UnitType.INFANTRY

# 常量 — 直接引用
var bonus = DataDef.DAMAGE_MATRIX[attacker][defender]

# Resource — 通过 DataDef 获取
var stats = DataDef.unit_stats.infantry
var planets = DataDef.level_data.planets
```

## Alternatives Considered

### Alternative 1: 全 GDScript 硬编码

- **Description**: 所有数据都写成 GDScript `const`，包括兵种属性、关卡布局
- **Pros**: 零文件 I/O，编译期类型检查全覆盖，不需要 ResourceLoader
- **Cons**: 改一个数值就要改代码重新编译；关卡数据硬编码导致每关一个 .gd 文件；不符合"数据驱动"架构原则
- **Rejection Reason**: 违背架构原则 #3。设计师改兵种属性不能要求他们改 GDScript。

### Alternative 2: 全 `.tres` Resource

- **Description**: 连枚举也用 Resource 表示（如 `UnitType` Resource 里存 type_name 字符串）
- **Pros**: 所有数据编辑器可见；设计师可完全独立于代码工作
- **Cons**: 枚举变成字符串比较，失去编译期类型检查；`DAMAGE_MATRIX` 这种纯逻辑表也要放 Resource，调试时不如代码直观；性能差（load() + 类型转换）
- **Rejection Reason**: 牺牲编译期类型安全换来的"编辑器可见"对枚举和常量无意义——它们不需要设计调整。

### Alternative 3: 全 JSON

- **Description**: 所有数据存在 `.json` 文件，运行时用 `JSON.parse_string()` 加载
- **Pros**: 纯文本，易 diff，易版本控制；任何文本编辑器都能改
- **Cons**: 零类型安全——拼错字段名运行时才报；Godot 编辑器中不可见；手写 JSON 易出错；每次访问要 cast 类型
- **Rejection Reason**: JSON 没有类型系统，对 19 系统的项目来说维护风险太高。Godot Resource 提供同样的外部化收益且类型安全。

## Consequences

### Positive

- **类型安全**: 枚举在代码中是编译期检查，IDE 自动补全 `DataDef.UnitType.` 会列出所有选项
- **设计友好**: 兵种属性、关卡布局在 Godot 编辑器中可视化调整，设计师不碰代码
- **统一入口**: 所有系统通过 `DataDef` 访问数据，修改存储格式不影响调用方
- **符合 Godot 习惯**: Resource 系统是 Godot 核心机制，编辑器原生支持

### Negative

- **两种格式**: 新人需要知道"什么数据在哪儿"——但规则简单（改不改 → GDScript vs .tres）
- **Resource 文件是二进制**: `.tres` 虽是人类可读文本格式，但 `.res` 是二进制。缓解：对 MVP 只用 `.tres`（文本格式，可 diff）
- **Resource 加载顺序**: `DataDef._ready()` 中 `load()` Resource 文件，自动加载顺序依赖 Godot autoload 优先级。缓解：`DataDef` 设为 autoload 列表第一位

### Risks

- **Resource 格式变更**: 修改 Resource 类字段名后，旧 `.tres` 文件会加载失败。缓解：Resource 类字段只增不删；旧字段加 `@deprecated` 标记后保留
- **`duplicate(true)` 语义变更 (4.5)**: 如果运行时需要复制 Resource 数据，不能用旧版 `duplicate(true)`。缓解：用 `duplicate_deep(DEEP_DUPLICATE_ALL)`

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| 数据定义 | 集中管理所有枚举和常量 | `DataDef` autoload 统一入口，GDScript enum + const |
| 兵种系统 | 兵种属性表外部化 | `UnitStatsTable` Resource，`@export` 字段编辑器可视 |
| 星图数据 | 关卡布局外部化 | `LevelData` Resource，星球位置/连接线在编辑器中配置 |
| 所有系统 | 类型安全的数据引用 | `DataDef.UnitType.INFANTRY` 编译期检查 |

## Performance Implications

- **CPU**: `load()` Resource 在 `_ready()` 中一次性完成，运行时不产生额外开销
- **Memory**: Resource 在内存中 < 50KB（枚举+常量+兵种属性+关卡数据）
- **Load Time**: `load()` 在 autoload 初始化时执行，不影响游戏启动感知
- **Network**: 不适用

## Migration Plan

不适用 — 新项目。

## Validation Criteria

- `DataDef` autoload 在游戏启动后 `unit_stats` 和 `level_data` 非 null
- `DataDef.UnitType.INFANTRY` 在 GDScript 中有 IDE 自动补全
- 修改 `unit_stats.tres` 中步兵攻击力 → 重启游戏 → `DataDef.unit_stats.infantry.attack` 反映新值
- 所有系统文件 `grep` 不包含硬编码数值（如 `attack = 10`），数值全部通过 `DataDef` 引用

## Related Decisions

- ADR-0001: 事件总线架构 — Signal 参数类型引用 DataDef 的枚举和 Resource 类型
- ADR-0005: 星球数据模型 — `PlanetData` Resource 格式
- ADR-0006: 战斗公式设计 — 公式参数从 `UnitStatsTable` 读取
- `docs/architecture/architecture.md` — Module Ownership: 数据定义系统
