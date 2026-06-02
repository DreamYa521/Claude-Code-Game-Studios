# 生产系统 (Production System)

> **Status**: In Design
> **Author**: Claude + 老大
> **Last Updated**: 2026-05-31
> **Implements Pillar**: ♟️ 从容推演 (自动产兵，无需操作)
> **Architecture**: [ADR-0004](../docs/architecture/adr/adr-0004-turn-resolution-model.md) (CLEANUP 步骤 5), [ADR-0005](../docs/architecture/adr/adr-0005-planet-data-model.md) (production_rate)

## Overview

生产系统在每个回合的 CLEANUP 阶段自动为玩家拥有的星球增加驻兵——让占领有经济意义。没有生产系统，玩家占星纯粹是为了消灭敌人，缺少"发展领土"的正反馈。

生产受两个约束：驻兵上限（`max_garrison`）和产量速率（`production_rate`），两者均由星球属性决定（见星球系统 GDD）。

## Player Fantasy

玩家不直接操作生产——它是"种田"的自动化体现。玩家在占领一颗 RICH 星后，每回合看到它的驻兵自动增长，感受到"我的帝国在呼吸"。FORTRESS 星虽然产出慢，但驻兵上限高——它是"囤兵待发"的地方。

## Detailed Rules

### 规则 1: 生产触发时机

`ProductionSystem.apply_turn()` 在 `TurnManager._cleanup()` 步骤 5 中调用——即所有战斗结算和占领变更完成后。这确保：
- 本回合刚被占领的星球立即开始产兵（归属已变更）
- 本回合刚被夺取的星球不产兵（归属已变走）

### 规则 2: 生产公式

对于每颗 `owner == PLAYER` 的星球：

```
new_garrison = min(max_garrison, garrison + ceil(production_rate))
delta = new_garrison - garrison
if delta > 0:
    PlanetSystem.update_garrison(planet_id, +delta)
```

- 使用 `ceil()` 向上取整——确保 `production_rate < 1.0` 的星球（如 BARREN 0.5）也能每两回合产 1 兵
- 不超过 `max_garrison`——到达上限后不再增长

### 规则 3: AI 敌人生产

AI 拥有的星球同样在 CLEANUP 阶段生产，使用相同公式。AI 的生产不影响玩家决策（玩家看不到 AI 的后方生产细节），但 AI 的驻兵增长让玩家的进攻窗口有限。

### 规则 4: NEUTRAL 星球不生产

中立星球不产兵——它们只是等待被占领的"空白点"。NEUTRAL 星的 garrison 在初始化时设为 0，不增长。

### States and Transitions

```
TurnManager.CLEANUP
  → ProductionSystem.apply_turn()
    → for each planet with owner != NEUTRAL:
        → calculate: min(max_garrison, garrison + ceil(production_rate))
        → PlanetSystem.update_garrison(id, +delta)
    → EventBus.turn_ended 之后 UI 刷新可见
```

### Interactions with Other Systems

| 调用方/被调用方 | 操作 |
|----------------|------|
| 回合管理器 | 在 CLEANUP 步骤 5 调用 `apply_turn()` |
| 星球系统 | 读 `get_planets_by_owner()` → 遍历；写 `update_garrison(id, +delta)` |

## Formulas

### 单星球产量

```
production = ceil(planet.production_rate)
```

其中 `production_rate` 由星球属性决定（见星球系统 GDD）：
- NORMAL: 1.0 → 1 兵/回合
- RICH: 1.5 → 2 兵/回合
- FORTRESS: 0.75 → 1 兵/回合
- BARREN: 0.5 → 1 兵/2回合（ceil(0.5)=1, 每回合都是 1? 不对...）

**修正**: `ceil(0.5) = 1` 意味着 BARREN 星每回合也产 1 兵？这不对——BARREN 的设计意图是每两回合产 1 兵。

需要使用**累积产量**而非每回合独立取整：

```
planet.accumulated_production += planet.production_rate
produced = floor(planet.accumulated_production)
if produced >= 1:
    new_garrison = min(max_garrison, garrison + produced)
    planet.accumulated_production -= produced
```

这样 BARREN (0.5/回合): 第1回合累积 0.5→floor=0 不产, 第2回合累积 1.0→floor=1 产1兵。

`accumulated_production` 存储在 RuntimePlanetData 中（新增字段，初始值 0）。

### 多星球总产量

```
total_produced = Σ produced_i  (for all player-owned planets)
```

用于 UI 显示"本回合产出 N 兵"。

## Edge Cases

- **驻兵已达上限**: `garrison >= max_garrison` → 不产兵，`accumulated_production` 继续累积（但不产生兵）。当驻兵因出征降至上限以下时，下一回合一次性产出累积值
- **刚被占领的星**: 归属变更在步骤 4，生产在步骤 5——新占领星参与当回合生产
- **刚丢失的星**: 归属已变走，生产跳过
- **所有星满驻兵**: `apply_turn()` 无操作，返回 total=0

## Dependencies

**上游（本系统依赖）**:
| 系统 | 依赖内容 |
|------|---------|
| 星球系统 | `get_planets_by_owner()`, `update_garrison()` |
| 数据定义 | `PRODUCTION_BASE_RATE` 常量, `Faction` 枚举 |

**下游（依赖本系统的系统）**:
| 系统 | 依赖类型 | 依赖内容 |
|------|---------|---------|
| 回合管理器 | Hard | 调用 `apply_turn()` |
| (无其他系统直接依赖生产——它是终点消费方) | | |

## Tuning Knobs

| Knob | 位置 | 安全范围 | 过高后果 | 过低后果 |
|------|------|---------|---------|---------|
| `PRODUCTION_BASE_RATE` | DataDef | 0.5 – 5.0 | 暴兵太快，策略变堆量 | 产兵太少，节奏拖沓 |
| `ATTR_PRODUCTION_MULT` | PlanetSystem | 0.25 – 3.0 | RICH 星产出碾压一切 | 占什么星都一样 |

## Acceptance Criteria

- **GIVEN** 玩家拥有 2 颗 NORMAL 星（garrison=5, 上限=20），**WHEN** `apply_turn()` 执行，**THEN** 每颗星 garrison += 1
- **GIVEN** 玩家拥有 1 颗 RICH 星（production_rate=1.5），**WHEN** 连续 2 回合 `apply_turn()`，**THEN** 第 1 回合 +1, 第 2 回合 +2（累积取整验证）
- **GIVEN** 星球 garrison 已达 max_garrison，**WHEN** `apply_turn()` 执行，**THEN** garrison 不变
- **GIVEN** 星球 garrison = max_garrison - 1，**WHEN** 本回合应产 2 兵，**THEN** garrison = max_garrison（不超出上限）
- **GIVEN** 中立星球（owner=NEUTRAL），**WHEN** `apply_turn()` 执行，**THEN** garrison 不变
- **GIVEN** 本回合刚被玩家占领的星球，**WHEN** `apply_turn()` 执行，**THEN** 该星参与生产
