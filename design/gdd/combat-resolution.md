# 战斗结算 (Combat Resolution)

> **Status**: In Design
> **Author**: Claude + 老大
> **Last Updated**: 2026-05-31
> **Implements Pillar**: ⚖️ 抉择之重 (每场战斗有代价)
> **Architecture**: [ADR-0006](../docs/architecture/adr/adr-0006-combat-formula-design.md), [ADR-0004](../docs/architecture/adr/adr-0004-turn-resolution-model.md)

## Overview

战斗结算系统执行单场战斗的胜负计算——攻击方和防守方的兵力碰撞后，各损失多少兵、攻击方是否获胜。它是回合结算步骤 3 的核心计算引擎：纯函数，基于快照，确定性结果。

战斗结算不修改星球状态——它只返回 `BattleResult`。修改由回合管理器（步骤 4）和占领系统执行。

## Player Fantasy

玩家在出征界面看到"预测：我方损失约 X 兵，敌方损失约 Y 兵"（MVP 暂不做预测界面，但公式的结构保证了这个功能可以实现）。战斗结果是确定的——玩家的满足感来自"我算准了，刚好够打下"。

## Detailed Rules

### 规则 1: 战斗公式

采用比例力量模型（Proportional Strength Model），详见 ADR-0006。核心流程：

1. 计算有效战斗力
2. 确定优势方，计算力量比
3. 按比例分配战损
4. 转换为整数损失 → 判定胜负

### 规则 2: 战斗力计算

```
A_power = attacker_count × A_attack × DAMAGE_MATRIX[attacker_type][defender_type]
D_power = defender_count × D_defense × PLANET_DEFENSE_MULT[planet_attribute]
```

- `A_attack` / `D_defense` 从 `DataDef.unit_stats` 读取
- `DAMAGE_MATRIX` 从 `DataDef.DAMAGE_MATRIX` 读取
- `PLANET_DEFENSE_MULT` 在 CombatSystem 中定义：NORMAL=1.0, RICH=1.0, FORTRESS=1.5, BARREN=0.75

### 规则 3: 战损分配

```
power_ratio = max(A_power, D_power) / max(min(A_power, D_power), 1)
attacker_stronger = (A_power > D_power)

若 attacker_stronger:
    D_loss_rate = min(1.0, 0.5 + 0.5 × (1.0 - 1.0/power_ratio))
    A_loss_rate = 0.5 / power_ratio
否则:
    A_loss_rate = min(1.0, 0.5 + 0.5 × (1.0 - 1.0/power_ratio))
    D_loss_rate = 0.5 / power_ratio

A_loss = max(1, round(attacker_count × A_loss_rate))  若 attacker_count > 0
D_loss = max(1, round(defender_count × D_loss_rate))  若 defender_count > 0
```

### 规则 4: 胜负判定

```gdscript
attacker_survived = attacker_count - attacker_loss
defender_survived = defender_count - defender_loss
attacker_wins = (defender_survived <= 0)
```

- 攻击方获胜 = 防守方全灭
- 即使攻击方只剩 1 兵，只要防守方全灭就算赢

### 规则 5: 空星球和边界

- `defender_count == 0`: 无战斗，`attacker_wins=true, attacker_loss=0`
- `attacker_count == 0`: 无效输入，`attacker_wins=false, attacker_loss=0`
- 最小损失为 1（双方都 > 0 时）——确保每场战斗都有代价
- 最大损失不超过总兵力

### 规则 6: 纯函数

`CombatSystem.resolve()` 是纯函数——不访问全局状态，不写任何数据，同样的 5 个参数永远返回同样的 `BattleResult`。这保证：
- 在快照模型（ADR-0004）的步骤 3 中，多条指令无论以什么顺序计算，结果一致
- 单元测试可全覆盖

### States and Transitions

不适用 — 无状态，纯函数。

### Interactions with Other Systems

| 调用方 | 操作 | 上下文 |
|--------|------|--------|
| 回合管理器 | 在步骤 3 遍历 all_commands，每条调用 `resolve()` | 快照模型 |
| AI 敌人 | 预估战斗结果，判断"够不够打" | `compute_turn()` |

战斗结算本身不调用任何系统——它是纯计算引擎。

## Formulas

完整公式见 ADR-0006。此处列出关键常量：

| 常量 | 值 | 位置 |
|------|-----|------|
| `DAMAGE_MATRIX[克制]` | 1.5 | DataDef |
| `DAMAGE_MATRIX[被克]` | 0.75 | DataDef |
| `DAMAGE_MATRIX[同类型]` | 1.0 | DataDef |
| `PLANET_DEFENSE_MULT[NORMAL]` | 1.0 | CombatSystem |
| `PLANET_DEFENSE_MULT[RICH]` | 1.0 | CombatSystem |
| `PLANET_DEFENSE_MULT[FORTRESS]` | 1.5 | CombatSystem |
| `PLANET_DEFENSE_MULT[BARREN]` | 0.75 | CombatSystem |

### 演算示例

**10 步兵 vs 8 弓兵，NORMAL 星（步克弓）**:
```
A_power = 10 × 10.0 × 1.5 = 150.0
D_power = 8 × 5.0 × 1.0  = 40.0
ratio = 150/40 = 3.75, attacker_stronger

D_loss_rate = 0.5 + 0.5 × (1.0 - 1.0/3.75) = 0.867
A_loss_rate = 0.5/3.75 = 0.133

A_loss = max(1, round(10 × 0.133)) = 1
D_loss = max(1, round(8 × 0.867)) = 7

结果: A剩9, D剩1, attacker_wins=false
```

**10 步兵 vs 8 步兵，FORTRESS 星**:
```
A_power = 10 × 10.0 × 1.0 = 100.0
D_power = 8 × 8.0 × 1.5  = 96.0
ratio = 100/96 = 1.042, attacker_stronger (极小优势)

A_loss = round(10 × 0.48) = 5
D_loss = round(8 × 0.52) = 4

结果: A剩5, D剩4, attacker_wins=false
→ FORTRESS 几乎抹平数量劣势
```

## Edge Cases

- **攻击方 0 兵**: 返回全 0 的 BattleResult, `attacker_wins=false`
- **防守方 0 兵（空旷星球）**: 返回 `attacker_wins=true`, 双方损失均为 0
- **power_ratio 极大（碾压）**: 优势方仅损失 1（`max(1, ...)` 保底），劣势方全灭
- **双方各 1 兵**: A_loss=1, D_loss=1（若 A_power > D_power 则 defender_survived=0，攻击方胜；若等力则双方全灭... 等力时 power_ratio=1, D_loss_rate=0.5→D_loss=1, A_loss=1, 双方全灭？）

**修正**: 等力 1v1 时 `D_loss=max(1, round(1×0.5))=1`, `A_loss=max(1, round(1×0.5))=1`, 双方全灭→`defender_survived=0`→`attacker_wins=true`。这不符合直觉——势均力敌时攻击方不应该赢。需要特殊规则：

```gdscript
# 特例: 双方兵力各 1 且等力 → 防守方胜
if attacker_count == 1 and defender_count == 1 and A_power == D_power:
    attacker_wins = false
    attacker_survived = 0
    defender_survived = 1
```

- **取整导致的 `defender_survived < 0`**: `min(defender_loss, defender_count)` 确保不会负数

## Dependencies

**上游（本系统依赖）**:
| 系统 | 依赖内容 |
|------|---------|
| 数据定义 | `UnitStats.attack/defense`, `DAMAGE_MATRIX` |
| 星球系统 | (间接 — 星球 attribute 作为参数传入，不直接调用) |

**下游（依赖本系统的系统）**:
| 系统 | 依赖类型 | 依赖内容 |
|------|---------|---------|
| 回合管理器 | Hard | `resolve()` 在步骤 3 调用 |
| AI 敌人 | Hard | `resolve()` 预估战斗 |
| 占领系统 | Hard | `BattleResult.attacker_wins` 判定是否占领 |

## Tuning Knobs

| Knob | 位置 | 安全范围 | 过高后果 | 过低后果 |
|------|------|---------|---------|---------|
| `PLANET_DEFENSE_MULT[FORTRESS]` | CombatSystem | 1.25 – 2.0 | 要塞无法攻克 | 要塞无意义 |
| `DAMAGE_MATRIX` 克制倍率 | DataDef | 1.25 – 2.0 | 克制=必胜 | 克制无感知 |
| 基础战损率 (当前 0.5) | CombatSystem | 0.3 – 0.7 | 战斗太血腥，没人敢打 | 战斗无代价，策略无重量 |

## Acceptance Criteria

- **GIVEN** 相同参数调用 `resolve()` 两次，**WHEN** 完成，**THEN** 返回完全相同的 BattleResult
- **GIVEN** 10 步 vs 8 弓（克制+数量优势），**WHEN** `resolve()`，**THEN** `attacker_loss < defender_loss`
- **GIVEN** attacker_count=0，**WHEN** `resolve()`，**THEN** `attacker_wins == false`
- **GIVEN** defender_count=0，**WHEN** `resolve()`，**THEN** `attacker_wins == true, attacker_loss == 0`
- **GIVEN** defender_count=0，**WHEN** `resolve()`，**THEN** `defender_survived == 0`
- **GIVEN** FORTRESS vs NORMAL（其他条件相同），**WHEN** 比较 defender_loss，**THEN** FORTRESS 的 defender_loss 更小
- **单元测试**: 3×3×4=36 个 (兵种A × 兵种D × 星球属性) + 边界 (0兵, 1兵, 50兵)
