# Epic: 战斗结算

> **Layer**: Core
> **GDD**: design/gdd/combat-resolution.md
> **Architecture Module**: Core — 战斗结算
> **Status**: Ready
> **Stories**: 2 stories — Ready

## Overview

战斗结算系统执行单场战斗的胜负计算——攻击方和防守方的兵力碰撞后，各损失多少兵、攻击方是否获胜。它是回合结算步骤 3 的核心计算引擎：纯函数，基于快照，确定性结果。

公式采用比例力量模型：战斗力 = 兵力 × 攻击/防御 × 克制倍率 × 地形加成。双方按力量比例承担战损。36 组兵种匹配组合必须有自动化测试覆盖。

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0006: 战斗公式设计 | 比例力量模型，确定性纯函数，36 组合测试 | LOW |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-CBT-001 | 比例力量模型：`A_power = count × attack × counter_mult`，`D_power = count × defense × planet_defense_mult` | ADR-0006 ✅ |
| TR-CBT-002 | 战损分配：`power_ratio = max(A,D)/max(min(A,D),1)`，优势方 loss_rate=0.5/ratio，劣势方=0.5+0.5×(1-1/ratio) | ADR-0006 ✅ |
| TR-CBT-003 | 最小损失为 1（双方兵力 >0 时），`max(1, round(count × loss_rate))` | ADR-0006 ✅ |
| TR-CBT-004 | 胜负判定：`attacker_wins = (defender_survived <= 0)` | ADR-0006 ✅ |
| TR-CBT-005 | 1v1 等力特例：双方各 1 兵且 A_power==D_power → 防守方胜 | ADR-0006 ✅ |
| TR-CBT-006 | 空星球 (defender_count=0) → attacker_wins=true, attacker_loss=0, defender_loss=0 | ADR-0006 ✅ |
| TR-CBT-007 | `resolve()` 是纯函数——不访问全局状态，同输入永远同输出，可单元测试 | ADR-0006 ✅ |
| TR-CBT-008 | `PLANET_DEFENSE_MULT`: NORMAL=1.0, RICH=1.0, FORTRESS=1.5, BARREN=0.75 | ADR-0006 ✅ |
| TR-CBT-009 | 单元测试覆盖 3×3×4=36 组合（兵种A×兵种D×星球属性）+ 边界（0兵/1兵/50兵） | ADR-0006 ✅ |

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | resolve() 纯函数 — 战斗公式与 BattleResult | Logic | Ready | ADR-0006 |
| 002 | 36 组合测试矩阵与边界覆盖 | Logic | Ready | ADR-0006 |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/combat-resolution.md` are verified
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Next Step

Run `/create-stories combat-resolution` to break this epic into implementable stories.
