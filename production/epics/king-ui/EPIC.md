# Epic: 国王 UI

> **Layer**: Presentation
> **GDD**: design/gdd/king-ui.md
> **Architecture Module**: Presentation — 国王 UI
> **Status**: Ready
> **Stories**: 2 stories — 2026-05-31 (对话 5/5)

## Overview

国王 UI 显示当前国王的名字、天赋标签、剩余行动次数（寿命倒计时）、代际数。它是玩家时刻可见的"倒计时器"——提醒玩家时间有限，每次结束回合都在消耗。国王去世时展示去世/继位信息。

MVP 实现：顶部固定栏，国王名字 + 天赋标签 + 寿命条（ColorRect 手动控制宽度）+ 代际数。国王去世弹窗（全屏遮罩 + 居中模态窗口 + 继续按钮）。

## Governing ADRs

> Presentation 层无独立 ADR。遵循 Core ADR 约束。

| ADR | Relevant Decision |
|-----|-------------------|
| ADR-0008 | 订阅 EventBus.king_died / king_succeeded 刷新 UI |
| ADR-0001 | 通过 EventBus 接收国王状态变更 |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-KUI-001 | 常驻面板显示：代际数/天赋标签/名字/寿命条(长度=remaining/lifespan)+数字 | ADR-0008 ✅ |
| TR-KUI-002 | 寿命条颜色：绿(>50%)→黄(30-50%)→橙(10-30%)→红(<10%)，remaining≤3 闪烁警告 | ADR-0008 ✅ |
| TR-KUI-003 | 去世弹窗：'名字 驾崩，第N代国王，享年N回合'+继承人信息+'继续'按钮→关闭→GameState恢复PLAYING | ADR-0008 ✅ |
| TR-KUI-004 | 订阅 4 个信号：action_consumed/king_died/king_succeeded/game_state_changed | ADR-0008 ✅ |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/king-ui.md` are verified
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | [国王常驻面板 — 代际 + 名字 + 寿命条 + 天赋标签](story-001-king-panel-core.md) | UI | Ready | ADR-0008 |
| 002 | [去世/继位弹窗 + king_died 事件集成](story-002-king-death-popup.md) | UI | Ready | ADR-0008 |

## Next Step

Run `/story-readiness production/epics/king-ui/story-001-king-panel-core.md` to validate the first story is ready for implementation.
