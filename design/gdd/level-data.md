# 星图/关卡数据 (Level Data)

> **Status**: In Design
> **Author**: Claude + 老大
> **Last Updated**: 2026-05-31
> **Implements Pillar**: ♟️ 从容推演 (星图是棋盘)
> **Architecture**: [ADR-0002](../docs/architecture/adr/adr-0002-data-definition-format.md), [ADR-0005](../docs/architecture/adr/adr-0005-planet-data-model.md)

## Overview

星图/关卡数据系统是关卡设计的"画布"——它定义一个关卡中有哪些星球、它们在什么位置、用什么属性、相互之间如何连接、初始谁占什么星。关卡数据存储在 `.tres` Resource 文件中，设计师在 Godot 编辑器中可视化编辑。

MVP 只有一个关卡：1 颗行星 + 3 颗卫星，总计 4 颗星球。

## Player Fantasy

玩家看到的第一张星图就是游戏的"开场棋盘"——几颗彩色的圆、几条连接线、兵力数字。它不需要教程解释：蓝色是你的，红色是敌人的，数字是兵数。玩家本能地想"我先打哪颗？"

## Detailed Rules

### 规则 1: LevelData Resource 结构

```gdscript
class_name LevelData extends Resource
@export var level_id: String                    # 关卡唯一标识，如 "tutorial_1"
@export var level_name: String                  # 显示名，如 "太阳系"
@export var planets: Array[PlanetDef]           # 星球静态定义数组
@export var connections: Array[Connection]      # 连接路线数组
@export var initial_owner: Dictionary           # {planet_id: int → Faction: int}
@export var initial_garrison: Dictionary        # {planet_id: int → garrison: int}
```

- `planets`: 定义每颗星的静态属性（id, name, position, attribute）
- `connections`: 定义连接路线（from, to），双向自动处理
- `initial_owner`: 初始归属 — 未指定的星默认为 NEUTRAL
- `initial_garrison`: 初始驻兵 — 未指定的星默认为 0

### 规则 2: PlanetDef 结构

```gdscript
class_name PlanetDef extends Resource
@export var id: int                             # 唯一ID（关卡内不可重复）
@export var name: String                        # 显示名
@export var position: Vector2                   # 星图坐标（像素）
@export var attribute: DataDef.PlanetAttribute  # 属性
```

### 规则 3: Connection 结构

```gdscript
class_name Connection extends Resource
@export var from: int    # 源星球 ID
@export var to: int      # 目标星球 ID
```

连接是双向的——`from→to` 同时建立 `to→from`。无需在 .tres 中重复定义。

### 规则 4: MVP 关卡布局

```
太阳系（tutorial_1）:
  planets:
    - id: 1, name: "地球",  position: (200, 200), attribute: NORMAL
    - id: 2, name: "月球",  position: (350, 120), attribute: NORMAL
    - id: 3, name: "火星",  position: (400, 300), attribute: RICH
    - id: 4, name: "火卫一", position: (520, 250), attribute: BARREN
  
  connections:
    - from: 1, to: 2   # 地球↔月球
    - from: 1, to: 3   # 地球↔火星
    - from: 3, to: 4   # 火星↔火卫一
  
  initial_owner:
    1: PLAYER   # 玩家起始星
    3: ENEMY    # AI 起始星
  
  initial_garrison:
    1: 10   # 玩家10兵
    3: 8    # AI 8兵
```

**战术布局意图**:
- 地球(1) 是玩家 HQ，连接月球(2)和火星(3)
- 月球(2) 是中立 NORMAL 星 — 玩家的第一个自然目标
- 火星(3) 是 AI 的 HQ，RICH 属性让它产兵更快 — 玩家必须速攻
- 火卫一(4) 是 BARREN — 价值低但控制火星后必占（连接终点）

### 规则 5: 关卡加载

`init_from_level(level_data)` 在 PlanetSystem 中执行（见星球系统 GDD）：
1. 遍历 planets → 构建 RuntimePlanetData
2. 遍历 connections → 构建双向邻接表
3. 遍历 initial_owner → 设置 owner
4. 遍历 initial_garrison → 设置 garrison

### 规则 6: 关卡切换（MVP 不做）

MVP 只有一个关卡。关卡切换机制延后到 Vertical Slice。

### States and Transitions

不适用 — 关卡数据是纯数据，无运行时状态。

### Interactions with Other Systems

| 消费方 | 操作 |
|--------|------|
| 星球系统 | `init_from_level(level_data)` — 唯一调用方 |
| 数据定义 | 定义 `LevelData`, `PlanetDef`, `Connection` Resource 类 |

## Formulas

不适用 — 无公式，纯数据定义。

## Edge Cases

- **PlanetDef.id 重复**: `init_from_level()` 检测到重复 ID → `push_error()` + 跳过后出现的
- **Connection 引用不存在的星球**: `_build_adjacency()` 跳过该连接 + `push_warning()`
- **initial_owner 和 initial_garrison 的 key 不存在**: 跳过该条目 + `push_warning()`
- **孤立星球（无任何连接）**: 允许——作为"孤岛"装饰或特殊关卡机制。但 MVP 不设计孤立星

## Dependencies

**上游（本系统依赖）**:
| 系统 | 依赖内容 |
|------|---------|
| 数据定义 | `PlanetAttribute`, `Faction`, `LevelData`/`PlanetDef`/`Connection` Resource 类定义 |

**下游（依赖本系统的系统）**:
| 系统 | 依赖类型 | 依赖内容 |
|------|---------|---------|
| 星球系统 | Hard | `init_from_level(level_data)` |
| 星图 UI | Hard | 星球位置、连接路线、归属颜色 |

## Tuning Knobs

| Knob | 位置 | 安全范围 | 说明 |
|------|------|---------|------|
| 星球数量 | .tres | 2 – 10 (MVP) | 太少无策略，太多复杂度超标 |
| 连接密度 | .tres | 平均 1-3 连接/星 | 太密=无地形，太稀=线性 |
| 初始兵力分配 | .tres | 玩家初始 8-15 | 太少无操作空间，太多AI开局被压 |
| 星球属性分布 | .tres | — | 至少1颗RICH让玩家有"必争之地" |

## Acceptance Criteria

- **GIVEN** `level_tutorial.tres` 存在，**WHEN** Godot 编辑器打开，**THEN** Inspector 中可见 planets/connections/initial_owner
- **GIVEN** `PlanetSystem.init_from_level(level_data)` 调用，**WHEN** 完成，**THEN** `get_all_planets().size() == 4`
- **GIVEN** 关卡定义了 3 条 Connection，**WHEN** 初始化完成，**THEN** 共 6 条邻接关系（双向）
- **GIVEN** `initial_owner[1] = PLAYER, initial_owner[3] = ENEMY`，**WHEN** 初始化完成，**THEN** 地球 owner=PLAYER, 火星 owner=ENEMY, 月球+火卫一 owner=NEUTRAL
- **GIVEN** `initial_garrison[1] = 10`，**WHEN** 初始化完成，**THEN** 地球 garrison = 10

## Open Questions

- 是否需要在编辑器中可视化编辑连接路线？（MVP 不需要，Vertical Slice 可加 Godot 插件）
- 是否支持"初始兵种类型"？（MVP 所有初始驻兵都是 INFANTRY）
