# Epic: AI 敌人

> **Layer**: Core
> **GDD**: design/gdd/ai-enemy.md
> **Architecture Module**: Core — AI 敌人
> **Status**: Ready
> **Stories**: 2 stories — TO DO

## Overview

AI 敌人模拟一个对手玩家——在每回合部署阶段，从己方星球发兵、攻击玩家和中立星球、防守受威胁的领土。AI 在回合结算步骤 1 被调用，其指令与玩家指令合并后统一结算。

决策架构为三阶段规则引擎：防御（评估威胁、分配防守兵力）→ 进攻（选择最优目标、计算发兵量）→ 冲突消解（同源星多发指令时选择最优）。参数化难度：aggression、defensiveness、intelligence 可配置。

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0007: AI 决策架构 | 分阶段规则引擎，参数化难度，确定性决策 | LOW |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-AIE-001 | compute_turn() 在 TurnManager 步骤 1 调用，返回 Array[DeploymentCommand] | ADR-0007 ✅ |
| TR-AIE-002 | 分阶段规则引擎：Phase 1 防御评估 → Phase 2 进攻规划 → Phase 3 冲突消解 | ADR-0007 ✅ |
| TR-AIE-003 | 威胁评估：threat_ratio = Σ(adj_enemy_garrison) / (planet.garrison + 1)，三级阈值 | ADR-0007 ✅ |
| TR-AIE-004 | 防守保留：defense_min = max(1, max_garrison × DEFENSE_RESERVE_RATIO)，默认 0.3 | ADR-0007 ✅ |
| TR-AIE-005 | 进攻价值评分 5 因子：目标产量×3.0 + 威胁×0.5 + 战损效率×2.0 + 属性价值 + 战略位置×0.5 | ADR-0007 ✅ |
| TR-AIE-006 | 三个可调 AI 参数：aggression(0-1)/defensiveness(0-1)/intelligence(0-1)，默认全 0.5 | ADR-0007 ✅ |
| TR-AIE-007 | 兵种选择：intelligence≥randf() 时选克制兵种，否则随机选 | ADR-0007 ✅ |
| TR-AIE-008 | AI 不使用国王系统——无寿命约束，无代际传承 | ADR-0008 ✅ |
| TR-AIE-009 | 同一出发星的总出兵 ≤ 驻兵（Phase 3 冲突消解 + ADR-0004 overdraft 安全网） | ADR-0007 ✅ |
| TR-AIE-010 | intelligence=1.0 时 AI 确定性输出（同输入→同指令），可单元测试 | ADR-0007 ✅ |

## Stories

| # | Story | Type | TR Coverage | Estimate | Status |
|---|-------|------|-------------|----------|--------|
| 001 | [compute_turn() 三阶段规则引擎核心](story-001-ai-engine-core.md) | Logic | TR-AIE-001~005,007~010 | 3h | Ready |
| 002 | [AI 参数化 + 回合集成 + 测试矩阵](story-002-ai-integration.md) | Integration | TR-AIE-006 | 2h | Ready |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/ai-enemy.md` are verified
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Next Step

Run `/create-stories ai-enemy` to break this epic into implementable stories.
