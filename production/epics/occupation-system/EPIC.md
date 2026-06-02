# Epic: 占领系统

> **Layer**: Core
> **GDD**: design/gdd/occupation-system.md
> **Architecture Module**: Core — 占领系统
> **Status**: Ready
> **Stories**: 2 stories — Ready

## Overview

占领系统处理战斗后的星球归属转移——攻击方歼灭全部防守兵力后，星球从原归属方转入攻击方名下。它是"战斗结果→战略影响"的桥梁：打赢了不能只是"对方少了几兵"，而是要"这颗星归我了，从此它为我产兵"。

多支军队同时攻入同一星球时，按玩家优先顺序应用结果。

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0005: 星球数据模型 | 归属变更走 `set_owner()` → EventBus 广播 | LOW |
| ADR-0004: 回合结算模型 | 步骤 4 应用顺序：先玩家后 AI，保证确定性 | LOW |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-OCC-001 | `attacker_wins=true` → `transfer(target, attacker_faction)` + `set_garrison(target, attacker_survived)` | ADR-0004 ✅ |
| TR-OCC-002 | `attacker_wins=false` → 目标星驻兵更新为防守方幸存兵力，owner 不变 | ADR-0004 ✅ |
| TR-OCC-003 | 步骤 4 应用顺序固定：先玩家指令后 AI 指令，保证结果确定性 | ADR-0004 ✅ |
| TR-OCC-004 | 防御性检查：`new_owner==current_owner` 时跳过（禁止占领己方星球） | ADR-0005 ✅ |
| TR-OCC-005 | 空旷星球 (defender_count=0) 无需战斗即占领，驻兵=出征兵力（无损） | ADR-0006 ✅ |

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | transfer() 占领核心逻辑 | Logic | Ready | ADR-0004, ADR-0005 |
| 002 | 多攻方应用顺序与回合管线集成 | Integration | Ready | ADR-0004 |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/occupation-system.md` are verified
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Next Step

Run `/create-stories occupation-system` to break this epic into implementable stories.
