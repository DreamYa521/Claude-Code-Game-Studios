# Epic: 战斗动画

> **Layer**: Presentation
> **GDD**: design/gdd/battle-animation.md
> **Architecture Module**: Presentation — 战斗动画
> **Status**: Ready
> **Stories**: 2 stories — 2026-05-31 (对话 5/5)

## Overview

战斗动画系统在回合结算的 EXECUTION 阶段提供视觉反馈——兵力短线沿连接路线流动、星球占领时闪烁。MVP 不做复杂特效，只做"让玩家看到发生了什么的"极简动画。所有动画在 Godot 的 `_process()` + `_draw()` 中实现。

MVP 范围：出兵线（短线从源星到目标星沿连接线移动）、占领闪烁（归属变更时星球闪烁 3 次）、可跳过（点击屏幕跳过全部动画）。

## Governing ADRs

> Presentation 层无独立 ADR。遵循 Core ADR 约束。

| ADR | Relevant Decision |
|-----|-------------------|
| ADR-0005 | 星球位置/连接来自 PlanetSystem |
| ADR-0006 | 战斗结果动画触发基于 BattleResult |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-BAN-001 | 兵力移动动画：短线沿连接线移动，颜色=出发方颜色，速度400px/s，每条指令1条短线 | ADR-0004 ✅ |
| TR-BAN-002 | 动画序列：execution_phase_started→所有指令并行播放移动动画→到达时占领闪烁→全部完成→turn_ended | ADR-0004 ✅ |
| TR-BAN-003 | 占领闪烁：3次(旧色↔新色交替)，每次150ms，总~900ms | ADR-0004 ✅ |
| TR-BAN-004 | 跳过选项：点击屏幕→全部动画瞬移到终点；设置可勾选'跳过战斗动画' | ADR-0004 ✅ |
| TR-BAN-005 | 动画期间星图不接受点击，全部完成后 turn_ended 恢复操作 | ADR-0004 ✅ |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/battle-animation.md` are verified
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | [兵力移动动画 — 短线沿连接线移动 + 并行播放 + 跳过](story-001-move-animation.md) | Visual/Feel | Ready | ADR-0004 |
| 002 | [占领闪烁 + 动画序列集成](story-002-occupation-flash.md) | Visual/Feel | Ready | ADR-0004 |

## Next Step

Run `/story-readiness production/epics/battle-animation/story-001-move-animation.md` to validate the first story is ready for implementation.
