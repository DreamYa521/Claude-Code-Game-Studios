# Epic: 出征 UI

> **Layer**: Presentation
> **GDD**: design/gdd/deployment-ui.md
> **Architecture Module**: Presentation — 出征 UI
> **Status**: Ready
> **Stories**: 1 story — 2026-05-31 (对话 5/5)

## Overview

出征 UI 是玩家发兵的交互面板——在星图上选中己方星后点击相邻敌星时弹出。包含兵力滑块、目标信息、确认/取消按钮。MVP 不做兵种选择（默认步兵），极简设计。

交互流程：点击己方星（选中）→ 点击相邻敌星 → 弹出面板（兵力滑块 + 目标星名 + 确认/取消）→ 确认→提交 DeploymentCommand → 关闭面板。

## Governing ADRs

> Presentation 层无独立 ADR。遵循 Core ADR 约束。

| ADR | Relevant Decision |
|-----|-------------------|
| ADR-0005 | 通过 PlanetSystem 获取 garrison 上限、校验兵力 |
| ADR-0006 | MVP 默认步兵，不做兵种选择 |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-DUI-001 | 面板元素：标题(出发星→目标星)/目标信息(名/属性/驻兵)/兵力滑块(1~garrison)+确认+取消按钮 | ADR-0001 ✅ |
| TR-DUI-002 | 滑块默认值=全部驻兵，拖动实时更新数字和'出发星剩余' | ADR-0001 ✅ |
| TR-DUI-003 | 确认→调用 deploy()，成功关闭面板/失败显示红色提示；取消→关闭面板零指令 | ADR-0004 ✅ |
| TR-DUI-004 | 快捷键：ESC取消/Enter确认 | ADR-0001 ✅ |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/deployment-ui.md` are verified
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | [出征面板 — 滑块 + 确认/取消 + deploy() 调用](story-001-deployment-panel.md) | UI | Ready | ADR-0001, ADR-0004 |

## Next Step

Run `/story-readiness production/epics/deployment-ui/story-001-deployment-panel.md` to validate the first story is ready for implementation.
