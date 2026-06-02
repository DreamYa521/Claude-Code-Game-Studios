# Epic: 星图 UI

> **Layer**: Presentation
> **GDD**: design/gdd/star-map-ui.md
> **Architecture Module**: Presentation — 星图 UI
> **Status**: Ready
> **Stories**: 2 stories — 2026-05-31 (对话 5/5)

## Overview

星图 UI 是玩家的**主视图**——渲染所有星球节点、连接路线、兵力数字、归属颜色。玩家在星图上完成所有操作（点选星球、查看信息、发起出征）。它是游戏 90% 时间的视觉呈现。

MVP 实现：Node2D + `_draw()` 渲染，星球用圆形节点+归属色填充，连接线为直线，兵力数字在星球上叠加显示。点击选中→高亮→可拖线到相邻星球发起出征。

## Governing ADRs

> Presentation 层无独立 ADR。遵循 Core ADR 约束。

| ADR | Relevant Decision |
|-----|-------------------|
| ADR-0005 | 星球位置、连接信息来自 PlanetSystem |
| ADR-0001 | 星球状态变更通过 EventBus 刷新 UI |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-SMU-001 | 星球节点渲染：圆形24px，PLAYER蓝/ENEMY红/NEUTRAL灰，选中2px白色边框 | ADR-0001 ✅ |
| TR-SMU-002 | 连接线渲染：2px半透明白线，选中星时连接线高亮#FFCC00 | ADR-0001 ✅ |
| TR-SMU-003 | 交互：点击己方星选中→点击相邻敌星触发出征UI，点击非相邻敌星无响应 | ADR-0001 ✅ |
| TR-SMU-004 | 订阅 5 个 EventBus 信号：planets_initialized, planet_owner_changed, planet_garrison_changed, turn_ended, game_ended | ADR-0001 ✅ |
| TR-SMU-005 | 详情面板显示：星球名/归属/属性/驻兵(当前/上限)/产兵速率/连接列表 | ADR-0001 ✅ |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/star-map-ui.md` are verified
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | [星球节点 + 连接线 + 兵力数字渲染](story-001-star-map-render.md) | UI | Ready | ADR-0001, ADR-0005 |
| 002 | [交互系统 + 详情面板 + EventBus 事件订阅](story-002-star-map-interaction.md) | UI | Ready | ADR-0001 |

## Next Step

Run `/story-readiness production/epics/star-map-ui/story-001-star-map-render.md` to validate the first story is ready for implementation.
