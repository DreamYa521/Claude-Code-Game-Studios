# Epic: 回合控制 UI

> **Layer**: Presentation
> **GDD**: design/gdd/turn-control-ui.md
> **Architecture Module**: Presentation — 回合控制 UI
> **Status**: Ready
> **Stories**: 1 story — 2026-05-31 (对话 5/5)

## Overview

回合控制 UI 提供"结束回合"按钮、当前回合数显示、游戏状态标签。它是玩家主动推进游戏节奏的唯一入口——"我的部署做完了，让回合结算吧"。

MVP 极简：一个按钮（结束回合）+ 回合数标签 + DEPLOYMENT/EXECUTION 阶段指示。按钮在执行阶段禁用，仅在部署阶段可点击。

## Governing ADRs

> Presentation 层无独立 ADR。遵循 Foundation ADR 约束。

| ADR | Relevant Decision |
|-----|-------------------|
| ADR-0003 | 根据 GameState 显示/隐藏 UI |
| ADR-0004 | 仅在 DEPLOYMENT 阶段启用结束回合按钮 |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-TCU-001 | 结束回合按钮状态：DEPLOYMENT可用/EXECUTION禁用'结算中...'/CLEANUP禁用'收尾中...'/非PLAYING隐藏 | ADR-0003 ✅ |
| TR-TCU-002 | 回合数显示监听 turn_ended(turn_number)，初始第1回合 | ADR-0004 ✅ |
| TR-TCU-003 | 阶段指示：监听 deployment_phase_started/execution_phase_started 更新文本 | ADR-0004 ✅ |
| TR-TCU-004 | 快捷键 Space/E → 结束回合（仅 PLAYING+DEPLOYMENT），双击防重复点击 | ADR-0003 ✅ |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/turn-control-ui.md` are verified
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | [回合控制界面 — 按钮 + 回合数 + 阶段指示 + 快捷键](story-001-turn-control-panel.md) | UI | Ready | ADR-0003, ADR-0004 |

## Next Step

Run `/story-readiness production/epics/turn-control-ui/story-001-turn-control-panel.md` to validate the first story is ready for implementation.
