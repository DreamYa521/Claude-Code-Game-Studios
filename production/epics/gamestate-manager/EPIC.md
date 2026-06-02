# Epic: GameState 管理器

> **Layer**: Foundation
> **GDD**: design/gdd/gamestate-manager.md
> **Architecture Module**: Foundation — GameState
> **Status**: Ready
> **Stories**: 1 story — 2026-05-31 (TR-ID 回填于对话 5/5)

## Overview

GameState 管理器控制游戏的全局生命周期。它维护一个包含 5 个状态的枚举状态机（`TITLE`, `PLAYING`, `PAUSED`, `VICTORY`, `DEFEAT`），通过 `transition_to()` 验证并执行状态转换，每次合法转换通过 EventBus 的 `game_state_changed` Signal 广播给所有订阅系统。所有其他系统通过 `is_playing()` / `is_game_over()` 查询当前状态来决定是否运行自己的逻辑。

此 Epic 实现 Foundation 层的全局状态控制——没有它，游戏不知道"现在能操作吗？"、"游戏结束了吗？"。

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0003: GameState 状态机设计 | GDScript `enum` + `match` 实现状态机，5 状态 7 合法转换 | LOW |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-GSM-001 | 5 状态枚举 TITLE/PLAYING/PAUSED/VICTORY/DEFEAT，current_state 对外只读 getter | ADR-0003 ✅ |
| TR-GSM-002 | transition_to() 验证转换矩阵（7条合法转换），非法返回 false + push_warning() | ADR-0003 ✅ |
| TR-GSM-003 | 每次合法转换自动广播 EventBus.game_state_changed.emit(old, new) | ADR-0003 ✅ |
| TR-GSM-004 | 提供 is_playing() 和 is_game_over() 快捷查询方法 | ADR-0003 ✅ |
| TR-GSM-005 | 使用 GDScript enum + match 实现，纯逻辑无场景树依赖，可单元测试 | ADR-0003 ✅ |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/gamestate-manager.md` are verified
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | [GameState State Machine](story-001-state-machine.md) | Logic | Ready | ADR-0003 |

## Next Step

Run `/story-readiness production/epics/gamestate-manager/story-001-state-machine.md` to validate the first story is ready for implementation.
