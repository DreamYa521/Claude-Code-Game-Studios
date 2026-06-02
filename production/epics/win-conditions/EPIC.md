# Epic: 胜负条件

> **Layer**: Feature
> **GDD**: design/gdd/win-conditions.md
> **Architecture Module**: Feature — 胜负条件
> **Status**: Ready
> **Stories**: 2 stories — 2026-05-31 (对话 5/5)

## Overview

胜负条件系统在每个回合的 CLEANUP 阶段检查游戏是否结束——玩家是否全歼了敌人（胜利），或者敌人是否全歼了玩家（失败）。它是游戏循环的终点：一旦触发，GameState 切换到 VICTORY 或 DEFEAT，游戏结束。

MVP 规则极简：全歼敌人 = 胜，被全歼 = 负。无分数、无星级评定、无时间限制。

## Governing ADRs

> Feature 层无独立 ADR。遵循 Foundation ADR 约束。

| ADR | Relevant Decision |
|-----|-------------------|
| ADR-0003 | 触发 GameState.transition_to(VICTORY/DEFEAT) |
| ADR-0004 | 在 CLEANUP 阶段执行检查 |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-WIN-001 | check_victory()：敌方星球全部被消灭（get_planets_by_owner(ENEMY).is_empty()） | ADR-0003 ✅ |
| TR-WIN-002 | check_defeat()：玩家星球全部丢失（get_planets_by_owner(PLAYER).is_empty()） | ADR-0003 ✅ |
| TR-WIN-003 | check() 在 CLEANUP 步骤 5 生产后、国王消耗前执行，触发 VICTORY/DEFEAT 状态转换 | ADR-0004 ✅ |
| TR-WIN-004 | 双方同时全灭 → 判定 DEFEAT（平局算玩家输） | ADR-0003 ✅ |
| TR-WIN-005 | 国王寿命耗尽不算输——代际传承是机制不是终点 | ADR-0008 ✅ |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/win-conditions.md` are verified
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | [check_victory() + check_defeat() + check() 核心逻辑](story-001-win-check-core.md) | Logic | Ready | ADR-0003, ADR-0004, ADR-0008 |
| 002 | [回合管线集成 + GameState + EventBus 连接](story-002-win-turn-integration.md) | Integration | Ready | ADR-0004 |

## Next Step

Run `/story-readiness production/epics/win-conditions/story-001-win-check-core.md` to validate the first story is ready for implementation.
