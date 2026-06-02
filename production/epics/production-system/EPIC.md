# Epic: 生产系统

> **Layer**: Core
> **GDD**: design/gdd/production-system.md
> **Architecture Module**: Core — 生产系统
> **Status**: Ready
> **Stories**: 2 stories — Ready

## Overview

生产系统在每个回合的 CLEANUP 阶段自动为玩家拥有的星球增加驻兵——让占领有经济意义。没有生产系统，玩家占星纯粹是为了消灭敌人，缺少"发展领土"的正反馈。

产量由星球属性决定（RICH 1.5× / BARREN 0.5×），累积产量取整——每回合未满 1 的部分累积到下一回合。

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0005: 星球数据模型 | `production_rate` 字段由属性乘数计算，存储在 RuntimePlanetData | LOW |
| ADR-0004: 回合结算模型 | 生产在 CLEANUP 步骤 5 执行，在占领变更后 | LOW |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-PRD-001 | `apply_turn()` 在 CLEANUP 步骤 5 调用，遍历所有非 NEUTRAL 星球产兵 | ADR-0004 ✅ |
| TR-PRD-002 | 累积产量模型：`accumulated_production += production_rate`，`floor()≥1`时产兵并扣减累积值 | ADR-0005 ✅ |
| TR-PRD-003 | `new_garrison = min(max_garrison, garrison + produced)`，不超出驻兵上限 | ADR-0005 ✅ |
| TR-PRD-004 | `accumulated_production` 存储在 RuntimePlanetData 中（新增字段，初始值 0） | ADR-0005 ✅ |
| TR-PRD-005 | NEUTRAL 星球不产兵，AI 星球使用相同公式产兵 | ADR-0004 ✅ |
| TR-PRD-006 | 驻兵达上限时 `accumulated_production` 继续累积，降至上限以下后下一回合一次性产出 | ADR-0005 ✅ |

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | 累积产量公式与 apply_turn() 核心逻辑 | Logic | Ready | ADR-0005, ADR-0004 |
| 002 | accumulated_production 字段集成与回合管线接入 | Integration | Ready | ADR-0005, ADR-0004 |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/production-system.md` are verified
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Next Step

Run `/create-stories production-system` to break this epic into implementable stories.
