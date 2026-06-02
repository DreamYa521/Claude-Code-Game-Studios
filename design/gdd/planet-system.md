# 星球系统 (Planet System)

> **Status**: In Design
> **Author**: Claude + 老大
> **Last Updated**: 2026-05-31
> **Implements Pillar**: ♟️ 从容推演, ⚖️ 抉择之重
> **Architecture**: [ADR-0005](../docs/architecture/adr/adr-0005-planet-data-model.md)

## Overview

星球系统管理游戏中所有星球的运行时状态——归属方、驻兵数、产量、邻接关系。它是 Core 层的**瓶颈系统**（7 个系统直接依赖），为出征校验、生产调度、AI 评估、战斗结算提供统一的数据访问接口。

星球系统不包含关卡设计数据（那是星图/关卡数据的职责）——它只管理从关卡数据加载后产生的**可变运行时状态**。静态关卡定义（`PlanetDef`）在 `DataDef.level_data` 中，运行时状态（`RuntimePlanetData`）在 `PlanetSystem._planets` 中。

## Player Fantasy

玩家不直接感知星球系统的存在。它的价值体现在"我点这颗星能看到它连着哪些星、驻了多少兵、产兵有多快"——这些信息让星图不再是图片，而是一个可以推演的棋盘。星球归属颜色变化（蓝→红→蓝）是回合制策略最原始的爽感来源。

## Detailed Rules

### 规则 1: 星球运行时数据

每颗星球在运行时维护以下状态（Dictionary，内部存储）：

| 字段 | 类型 | 可变 | 说明 |
|------|------|------|------|
| `id` | int | ❌ | 星球唯一标识，来自 PlanetDef |
| `name` | String | ❌ | 星球名，来自 PlanetDef |
| `position` | Vector2 | ❌ | 星图坐标，来自 PlanetDef |
| `attribute` | PlanetAttribute | ❌ | 属性，来自 PlanetDef |
| `garrison` | int | ✅ | 当前驻兵数 |
| `owner` | Faction | ✅ | 当前归属方 |
| `max_garrison` | int | ❌ | 驻兵上限（由 attribute 和 GARRISON_DEFAULT_MAX 计算） |
| `production_rate` | float | ❌ | 每回合产兵速率 |
| `adjacent_ids` | Array[int] | ❌ | 相邻星球 ID 列表（从 Connection 构建） |

### 规则 2: 属性效果

星球属性影响 `max_garrison` 和 `production_rate`：

| 属性 | 驻兵上限乘数 | 产兵速率乘数 | 战术含义 |
|------|------------|------------|---------|
| NORMAL | 1.0× | 1.0× | 基准 |
| RICH | 1.0× | 1.5× | 经济星——优先占领目标，防守无加成 |
| FORTRESS | 1.5× | 0.75× | 要塞星——难攻，适合囤兵防守 |
| BARREN | 0.75× | 0.5× | 不毛星——战略价值低，但关键路线不得不占 |

计算公式：见 [Formulas](#formulas) 节。

### 规则 3: 初始化流程

`PlanetSystem.init_from_level(level_data)` 一次性初始化全部星球：

1. 清空 `_planets`
2. 遍历 `level_data.planets`：为每个 `PlanetDef` 构建 `RuntimePlanetData`，初始 garrison=0, owner=NEUTRAL
3. 遍历 `level_data.connections`：构建双向邻接表（`A.adjacent_ids` 含 B 且 `B.adjacent_ids` 含 A）
4. 应用 `level_data.initial_owner`：设置初始归属方和初始驻兵
5. `EventBus.planets_initialized.emit()`

### 规则 4: 驻兵变更

`update_garrison(id, delta)`:
- `delta > 0`：增兵（生产、支援到达）
- `delta < 0`：减兵（出征调走、战斗损失）
- 不允许 `garrison < 0` ——若 delta 导致负数，返回 false
- 通过 ADR-0004 的阶段 gate：只在 DEPLOYMENT 和 CLEANUP 阶段接受修改

### 规则 5: 归属变更

`set_owner(id, new_owner)`:
- 变更 `_planets[id].owner`
- 广播 `EventBus.planet_owner_changed.emit(id, old_owner, new_owner)`
- 通过阶段 gate：只在 APPLY 步骤（步骤 4）中由占领系统调用

### 规则 6: 邻接查询

- `get_adjacent_planets(id) → Array[int]`：返回相邻星球 ID 列表
- `are_connected(a, b) → bool`：O(1) 检查 a 的 adjacent_ids 是否包含 b
- 邻接表在初始化时构建，运行时不修改（关卡布局不变）

### 规则 7: 归属方筛选

`get_planets_by_owner(faction) → Array[Dictionary]`：按势力筛选，用于：
- 出征系统：列出己方可发兵的星球
- AI 敌人：评估己方/敌方星球分布
- 胜负条件：检查"全歼敌人"

### States and Transitions

星球系统自身无状态机。星球的状态通过以下事件流转：

```
初始加载 (NEUTRAL/无兵)
  → init_from_level() → 设 owner + 初始 garrison
  → 生产系统 → update_garrison(id, +N) → 驻兵增加
  → 出征系统 → update_garrison(id, -N) → 驻兵减少
  → 战斗结算 → update_garrison(id, -loss) → 驻兵减少
  → 占领系统 → set_owner(id, new) → 归属变更
```

### Interactions with Other Systems

星球系统是**被调用方**——它提供数据，其他系统发起操作：

| 调用方 | 操作 | 频率 |
|--------|------|------|
| 星图数据 | `init_from_level(level_data)` | 游戏开始时 1 次 |
| 出征系统 | `get_planets_by_owner(PLAYER)`, `are_connected(a, b)` | 每次部署 |
| 生产系统 | `get_planets_by_owner(PLAYER)`, `update_garrison(id, +N)` | 每回合 CLEANUP |
| 回合管理器 | `get_all_planets()` → `take_snapshot()` | 每回合 EXECUTION |
| 战斗结算 | `get_planet(id)` (读 attribute 做防守加成) | 每场战斗 |
| 占领系统 | `set_owner(id, new)` | 占领发生时 |
| AI 敌人 | `get_planets_by_owner()`, `get_adjacent_planets()` | 每回合 AI 决策 |
| 胜负条件 | `get_planets_by_owner(ENEMY)` | 每回合 CLEANUP |
| 星图 UI | `get_all_planets()` | 每帧渲染 |

## Formulas

### 驻兵上限

```
max_garrison = int(GARRISON_DEFAULT_MAX × ATTR_GARRISON_MULT[attribute])
```

其中 `GARRISON_DEFAULT_MAX = 20`（DataDef 常量）

| attribute | 乘数 | 结果 |
|-----------|------|------|
| NORMAL | 1.0 | 20 |
| RICH | 1.0 | 20 |
| FORTRESS | 1.5 | 30 |
| BARREN | 0.75 | 15 |

### 产兵速率

```
production_rate = PRODUCTION_BASE_RATE × ATTR_PRODUCTION_MULT[attribute]
```

其中 `PRODUCTION_BASE_RATE = 1.0`（DataDef 常量）

| attribute | 乘数 | 结果 |
|-----------|------|------|
| NORMAL | 1.0 | 1.0 |
| RICH | 1.5 | 1.5 |
| FORTRESS | 0.75 | 0.75 |
| BARREN | 0.5 | 0.5 |

产兵速率由生产系统在 CLEANUP 阶段应用：`new_garrison = min(max_garrison, garrison + ceil(production_rate))`

## Edge Cases

- **无连接的孤立星球**: `adjacent_ids` 为空。该星无法发兵也无法被攻击——仅作为"装饰"或"首都"存在。关卡设计时应避免（除非故意用作 HQ）
- **`initial_owner` 指定了不存在的 planet_id**: `init_from_level()` 中跳过并 `push_warning()`
- **`Connection` 引用了不存在的 planet_id**: `_build_adjacency()` 中跳过该连接并 `push_warning()`
- **归属变更在非法阶段**: `set_owner()` 返回 false，不修改状态
- **驻兵超过上限**: 允许（通过生产时 cap 到 max_garrison 处理），但生产系统不再增加直到降回上限以下
- **归属变更后驻兵处理**: `set_owner()` 不修改 garrison——占领系统的职责是计算战后剩余兵力

## Dependencies

**上游（本系统依赖）**:
| 系统 | 依赖内容 |
|------|---------|
| 数据定义 | `Faction` 枚举, `PlanetAttribute` 枚举, `GARRISON_DEFAULT_MAX` 常量, `PRODUCTION_BASE_RATE` 常量, `PlanetDef` Resource 类, `Connection` Resource 类, `LevelData` Resource 类 |
| 事件总线 | `planet_owner_changed`, `planets_initialized` 信号 |

**下游（依赖本系统的系统）**:
| 系统 | 依赖类型 | 依赖内容 |
|------|---------|---------|
| 生产系统 | Hard | `get_planets_by_owner()`, `update_garrison()` |
| 占领系统 | Hard | `set_owner()` |
| 出征系统 | Hard | `get_planets_by_owner()`, `are_connected()` |
| 战斗结算 | Hard | `get_planet()` (读 attribute) |
| 回合管理器 | Hard | `get_all_planets()` (快照) |
| AI 敌人 | Hard | `get_planets_by_owner()`, `get_adjacent_planets()` |
| 星图数据 | Soft | `init_from_level()` 的调用方 |
| 星图 UI | Hard | `get_all_planets()` |

## Tuning Knobs

| Knob | 位置 | 安全范围 | 过高后果 | 过低后果 |
|------|------|---------|---------|---------|
| `GARRISON_DEFAULT_MAX` | DataDef | 10 – 50 | 防守过强，进攻困难 | 驻兵无策略意义 |
| `PRODUCTION_BASE_RATE` | DataDef | 0.5 – 5.0 | 暴兵太快 | 节奏拖沓 |
| `ATTR_GARRISON_MULT` | PlanetSystem | 0.5 – 2.0 | 属性差距过大 | 属性无感知 |
| `ATTR_PRODUCTION_MULT` | PlanetSystem | 0.25 – 3.0 | RICH 星决定一切 | 占什么星都一样 |

## Acceptance Criteria

- **GIVEN** `init_from_level()` 调用，**WHEN** LevelData 含 4 个 PlanetDef，**THEN** `get_all_planets().size() == 4`
- **GIVEN** 初始化完毕，**WHEN** 查询每个星球的 adjacent_ids，**THEN** 双向一致（若 A 邻 B 则 B 邻 A）
- **GIVEN** `set_owner(1, PLAYER)` 调用，**WHEN** 完成，**THEN** `get_planet(1).owner == PLAYER` 且 `EventBus.planet_owner_changed` 被 emit
- **GIVEN** `update_garrison(1, +5)` 调用，**WHEN** 完成，**THEN** garrison 增加 5
- **GIVEN** garrison = 3, `update_garrison(1, -5)` 调用，**WHEN** 执行，**THEN** 返回 false，garrison 保持 3
- **GIVEN** `get_planets_by_owner(PLAYER)` 调用，**WHEN** 仅 2 颗星属于玩家，**THEN** 返回长度为 2
- **GIVEN** `are_connected(1, 2)` 为 true，**WHEN** 调用 `are_connected(2, 1)`，**THEN** 返回 true
- **GIVEN** `take_snapshot()` 返回的 Dictionary 被修改，**WHEN** 查询原始 `_planets`，**THEN** `_planets` 不变（深拷贝验证）
