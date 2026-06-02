# Epic: 兵种系统

> **Layer**: Core
> **GDD**: design/gdd/unit-system.md
> **Architecture Module**: Core — 兵种系统
> **Status**: Ready
> **Stories**: 2 stories — Ready

## Overview

兵种系统定义三种基础兵种（步兵/弓兵/骑兵）的属性、三角克制关系和兵种选择逻辑。它是战斗结算的数据基础——不执行战斗，但提供战斗公式所需的全部参数（攻击力、防御力、克制倍率）。

MVP 阶段锁定步兵（出征 UI 不做兵种选择），但克制表和属性结构必须完整实现，为后续扩展预留。

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0006: 战斗公式设计 | 三角克制矩阵定义在 DataDef，克制倍率用于战斗力计算 | LOW |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-UNT-001 | 三种兵种属性：步兵(10/8/1.0)、弓兵(12/5/1.2)、骑兵(15/6/1.5) | ADR-0006 ✅ |
| TR-UNT-002 | 三角克制链 INF→ARC→CAV→INF，DAMAGE_MATRIX 查表 | ADR-0006 ✅ |
| TR-UNT-003 | `get_counter(type)` 和 `get_weak_against(type)` 克制查询辅助方法 | ADR-0006 ✅ |
| TR-UNT-004 | 兵种属性存储在 unit_stats.tres Resource，设计师可调整 | ADR-0002 ✅ |
| TR-UNT-005 | MVP 玩家出征默认使用 INFANTRY，AI 可使用全部三种兵种 | ADR-0006 ✅ |

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | 兵种属性数据配置 | Config/Data | Ready | ADR-0002, ADR-0006 |
| 002 | 克制查询与 MVP 兵种选择 | Logic | Ready | ADR-0006 |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/unit-system.md` are verified
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Next Step

Run `/story-readiness production/epics/unit-system/story-001-unit-stats-config.md` then `/dev-story` to begin implementation.
