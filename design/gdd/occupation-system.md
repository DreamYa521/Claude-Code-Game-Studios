# 占领系统 (Occupation System)

> **Status**: In Design
> **Author**: Claude + 老大
> **Last Updated**: 2026-05-31
> **Implements Pillar**: ⚖️ 抉择之重 (占星改变力量平衡)
> **Architecture**: [ADR-0004](../docs/architecture/adr/adr-0004-turn-resolution-model.md) (步骤 4 Apply), [ADR-0005](../docs/architecture/adr/adr-0005-planet-data-model.md) (set_owner)

## Overview

占领系统处理战斗后的星球归属转移——攻击方歼灭全部防守兵力后，星球从原归属方转入攻击方名下。它是"战斗结果→战略影响"的桥梁：打赢了不能只是"对方少了几兵"，而是要"这颗星归我了，从此它为我产兵"。

占领系统极简——只有一个判断（攻击方赢了吗？）和一个操作（改归属）。

## Player Fantasy

玩家看着自己颜色的星球从 1 颗变成 2 颗、3 颗、5 颗——帝国在星图上扩张。每一颗新星都是"我的"，每回合为我产兵。敌方星球变少的那一瞬间是策略游戏最原始的"我能赢"信号。

## Detailed Rules

### 规则 1: 占领触发条件

在回合结算步骤 4（Apply），遍历所有战斗结果：

```gdscript
if result.attacker_wins:
    # 确定攻击方归属
    var attacker_faction = PlanetSystem.get_planet(cmd.from_planet).owner
    OccupationSystem.transfer(cmd.to_planet, attacker_faction)
    # 更新目标星驻兵为攻击方存活兵力
    PlanetSystem.set_garrison(cmd.to_planet, result.attacker_survived)
else:
    # 攻击失败，目标星驻兵更新为防守方存活兵力
    PlanetSystem.set_garrison(cmd.to_planet, result.defender_survived)
```

### 规则 2: 归属转移

`transfer(planet_id, new_owner)`:
- 调用 `PlanetSystem.set_owner(planet_id, new_owner)`
- `set_owner()` 内部广播 `EventBus.planet_owner_changed`
- 归属转移不额外修改 garrison——garrison 由 `set_garrison()` 另行设置

### 规则 3: 占领后驻兵处理

- 攻击方胜利 → 目标星驻兵 = 攻击方存活兵力（占领部队留守）
- 攻击方失败 → 目标星驻兵 = 防守方存活兵力（守军继续驻扎）
- 出发星驻兵减少已在战斗结果的应用阶段处理

### 规则 4: 空旷星球

`defender_count == 0` → `attacker_wins == true` → 无需战斗即占领。到达空旷星球的部队直接接管该星，驻兵 = 出征兵力（无损）。

### 规则 5: 禁止占领己方星球

防御性检查：若 `new_owner == current_owner`，跳过（不应发生，但作为安全网）。

### States and Transitions

```
TurnManager 步骤 4 (Apply):
  for each battle_result in computed_results:
    if result.attacker_wins:
      OccupationSystem.transfer(target_planet, attacker_faction)
      PlanetSystem.set_garrison(target_planet, result.attacker_survived)
    else:
      PlanetSystem.set_garrison(target_planet, result.defender_survived)
    
    PlanetSystem.update_garrison(source_planet, -result.attacker_total)
```

### Interactions with Other Systems

| 调用方/被调用方 | 操作 |
|----------------|------|
| 回合管理器 | 步骤 4 中调用 `transfer()` |
| 星球系统 | `set_owner()`, `set_garrison()`, `update_garrison()` |
| 事件总线 | `planet_owner_changed` 由 PlanetSystem 广播 |
| 战斗结算 | 读取 `BattleResult.attacker_wins`, `attacker_survived` |

## Formulas

不适用 — 占领系统无公式，只有条件判断。

## Edge Cases

- **攻击方存活 0 兵但 attacker_wins=true**: 不应发生（`defender_survived==0` 但 `attacker_survived==0` 只在双方各 1 兵等力时发生——该情况由 combat resolution 的特殊规则处理为 defender_wins: `attacker_survived=0` 且 `attacker_wins=false`）
- **同时多条指令攻击同一星球**: 每条指令独立战斗、独立判定占领。如果第一条指令的 AI 攻下了该星，第二条指令（玩家）攻击的是刚被 AI 占领的星——需要读取最新 ownership。这发生在步骤 4 顺序应用时——**第一条指令先应用（星变 AI 的），第二条指令按新 ownership 打**。这引入了顺序依赖。

**处理方案**: 步骤 4 中的应用顺序固定为先玩家指令后 AI 指令。玩家指令之间按提交顺序。这样结果是确定的。

- **归属变更为 NEUTRAL**: 占领系统只能将星球转给 PLAYER 或 ENEMY。中立星无主人，不会"被占领回中立"。

## Dependencies

**上游（本系统依赖）**:
| 系统 | 依赖内容 |
|------|---------|
| 星球系统 | `set_owner()`, `set_garrison()` |
| 战斗结算 | `BattleResult.attacker_wins`, `attacker_survived`, `defender_survived` |

**下游（依赖本系统的系统）**:
| 系统 | 依赖类型 | 依赖内容 |
|------|---------|---------|
| 回合管理器 | Hard | 调用 `transfer()` |
| 生产系统 | Soft | 生产系统读取新 owner 决定为谁产兵 |
| 胜负条件 | Soft | 读取 owner 检查是否全歼 |

## Tuning Knobs

无 — 占领系统无独立参数。

## Acceptance Criteria

- **GIVEN** attacker_wins=true，**WHEN** `transfer(planet_id, PLAYER)` 调用，**THEN** `get_planet(planet_id).owner == PLAYER`
- **GIVEN** attacker_wins=false，**WHEN** 步骤 4 执行，**THEN** 目标星 owner 不变
- **GIVEN** defender_count=0，**WHEN** 部队到达空旷星，**THEN** 该星归属变为攻击方，驻兵 = 出征兵力
- **GIVEN** 占领完成，**WHEN** 检查 EventBus，**THEN** `planet_owner_changed` 被 emit
- **GIVEN** 同颗星被两条指令攻击（玩家和 AI），**WHEN** 步骤 4 按"玩家优先"顺序应用，**THEN** 结果确定且可复现
