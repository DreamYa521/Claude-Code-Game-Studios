# 兵种系统 (Unit System)

> **Status**: In Design
> **Author**: Claude + 老大
> **Last Updated**: 2026-05-31
> **Implements Pillar**: ⚖️ 抉择之重 (选什么兵种有后果)
> **Architecture**: [ADR-0006](../docs/architecture/adr/adr-0006-combat-formula-design.md)

## Overview

兵种系统定义三种基础兵种（步兵/弓兵/骑兵）的属性、三角克制关系和兵种选择逻辑。它是战斗结算的数据基础——不执行战斗，但提供战斗公式所需的全部参数（攻击力、防御力、克制倍率）。

兵种属性定义为 `.tres` Resource（设计师可在编辑器中调整），克制矩阵定义为 GDScript `const`（逻辑规则，不随意改）。

## Player Fantasy

玩家在出兵时选择兵种——"这批兵用什么兵种打过去？"。三角克制让这个选择有策略重量：选步兵克弓兵但被骑兵反克。兵种不对可能导致数量优势被抵消。玩家逐渐学会"侦查敌方驻兵兵种 → 选克制兵种出击"。

MVP 简化：所有出征默认用步兵（玩家不选兵种），克制只影响 AI 和后续版本。兵种系统的核心价值在 MVP 是**定义数据**而非**玩家选择**。

## Detailed Rules

### 规则 1: 三种兵种

| 兵种 | 角色 | 攻击 | 防御 | 速度 |
|------|------|------|------|------|
| **步兵** (INFANTRY) | 均衡型 | 10.0 | 8.0 | 1.0 |
| **弓兵** (ARCHER) | 攻击型 | 12.0 | 5.0 | 1.2 |
| **骑兵** (CAVALRY) | 突击型 | 15.0 | 6.0 | 1.5 |

- 速度在 MVP 回合制"同时到达"模型下不影响战斗，保留为 Vertical Slice 扩展
- 数值存储在 `unit_stats.tres` Resource 中，通过 `DataDef.unit_stats` 访问

### 规则 2: 三角克制

```
步兵 ──克──→ 弓兵 ──克──→ 骑兵 ──克──→ 步兵

DAMAGE_MATRIX[attacker][defender]:
              INF   ARC   CAV
INFANTRY     1.0   1.5   0.75
ARCHER       0.75  1.0   1.5
CAVALRY      1.5   0.75  1.0
```

- **克制 (1.5×)**: 攻击方伤害 +50%
- **被克 (0.75×)**: 攻击方伤害 -25%
- **同类型 (1.0×)**: 无修正
- 矩阵存储为 GDScript `const Dictionary`，不可在编辑器中修改（修改 = 核心规则变更，走 code review）

### 规则 3: 兵种数据访问

所有系统通过 `DataDef` autoload 访问兵种数据：

```gdscript
# 枚举
var unit_type = DataDef.UnitType.INFANTRY

# 属性
var attack = DataDef.unit_stats.infantry.attack
var defense = DataDef.unit_stats.archer.defense

# 克制倍率
var mult = DataDef.DAMAGE_MATRIX[attacker][defender]

# 查克制关系
var counter_type = DataDef.get_counter(DataDef.UnitType.INFANTRY)  # → ARCHER
```

### 规则 4: 兵种属性表 (.tres 格式)

```gdscript
# unit_stats_table.gd
class_name UnitStatsTable extends Resource
@export var infantry: UnitStats
@export var archer: UnitStats
@export var cavalry: UnitStats

# unit_stats.gd
class_name UnitStats extends Resource
@export var unit_type: DataDef.UnitType
@export var attack: float = 10.0
@export var defense: float = 8.0
@export var move_speed: float = 1.0
```

设计师在 Godot 编辑器中直接修改 `.tres` 文件的 `@export` 字段，不需要碰代码。

### 规则 5: MVP 兵种选择简化

MVP 阶段玩家不手动选择兵种：
- 所有玩家出征默认使用 **步兵**（`UnitType.INFANTRY`）
- AI 可使用全部三种兵种（在 AI `intelligence` 参数控制下）
- 兵种选择 UI 在 Vertical Slice 阶段添加

### States and Transitions

不适用 — 兵种系统是纯数据系统，无状态。

### Interactions with Other Systems

| 消费方 | 访问内容 | 访问方式 |
|--------|---------|---------|
| 战斗结算 | `UnitStats.attack/defense`, `DAMAGE_MATRIX` | `resolve()` 函数参数 |
| AI 敌人 | `UnitType` 枚举, `DAMAGE_MATRIX` | 选兵种、预估战斗 |
| 出征系统 | `UnitType` 枚举 | 创建 `DeploymentCommand` |
| 生产系统 | (间接 — 不直接访问) | — |

## Formulas

### 克制查询

```
克制链: INF → ARC → CAV → INF
被克链: INF ← ARC ← CAV ← INF

get_counter(type):
    match type:
        INFANTRY → ARCHER
        ARCHER  → CAVALRY
        CAVALRY → INFANTRY

get_weak_against(type):
    match type:
        INFANTRY → CAVALRY
        ARCHER  → INFANTRY
        CAVALRY → ARCHER
```

克制倍率由 `DAMAGE_MATRIX[attacker][defender]` 直接查表，不在兵种系统中重复定义公式。

## Edge Cases

- **新增兵种类型**: 必须在 `DAMAGE_MATRIX` 中为新类型添加一行一列；必须创建对应 `UnitStats` Resource。MVP 只有 3 种兵，不新增。
- **attack/defense 被设为 0**: 战斗公式中除零保护——`max(1.0, attack)` 确保最小攻击力为 1
- **Resource 加载失败**: `DataDef._ready()` 中 `load()` 失败 → `push_error()` + 游戏不启动
- **克制矩阵不对称**: 矩阵当前对称（1.5/1.0/0.75），若被修改为不对称需 game-designer 签字确认克制链仍闭合

## Dependencies

**上游（本系统依赖）**:
| 系统 | 依赖内容 |
|------|---------|
| 数据定义 | `UnitType` 枚举, `DAMAGE_MATRIX` 常量, `UnitStatsTable` Resource, `UnitStats` Resource |

**下游（依赖本系统的系统）**:
| 系统 | 依赖类型 | 依赖内容 |
|------|---------|---------|
| 战斗结算 | Hard | `UnitStats.attack/defense`, `DAMAGE_MATRIX` |
| AI 敌人 | Hard | `UnitType`, `DAMAGE_MATRIX` |
| 出征系统 | Soft | `UnitType` 枚举 |

## Tuning Knobs

| Knob | 位置 | 安全范围 | 过高后果 | 过低后果 |
|------|------|---------|---------|---------|
| `UnitStats.attack` | .tres | 5.0 – 30.0 | 该兵种碾压一切 | 永远打不死人 |
| `UnitStats.defense` | .tres | 3.0 – 20.0 | 防守无敌 | 碰一下就死 |
| `DAMAGE_MATRIX` 克制倍率 | DataDef const | 1.25× – 2.0× | 克制 = 必胜 | 克制无感知 |
| `DAMAGE_MATRIX` 被克倍率 | DataDef const | 0.5× – 0.9× | 被克 = 必败 | 被克无代价 |

## Acceptance Criteria

- **GIVEN** 游戏启动，**WHEN** DataDef 初始化完成，**THEN** `DataDef.unit_stats.infantry.attack == 10.0`
- **GIVEN** `DAMAGE_MATRIX[INFANTRY][ARCHER]` 查找，**WHEN** 执行，**THEN** 返回 1.5
- **GIVEN** `DAMAGE_MATRIX[CAVALRY][INFANTRY]` 查找，**WHEN** 执行，**THEN** 返回 1.5（骑克步）
- **GIVEN** 修改 `unit_stats.tres` 中步兵 attack 为 12.0，**WHEN** 重启游戏，**THEN** `DataDef.unit_stats.infantry.attack` 返回 12.0
- **GIVEN** 查找 `get_counter(INFANTRY)`，**WHEN** 执行，**THEN** 返回 ARCHER
- **GIVEN** 查找 `get_weak_against(ARCHER)`，**WHEN** 执行，**THEN** 返回 CAVALRY（弓被骑克）

## Open Questions

- Vertical Slice: 玩家如何选择出征兵种？在出征 UI 中加兵种切换按钮，还是根据星球自动选最佳克制？
