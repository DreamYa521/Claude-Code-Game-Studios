# Epic: 回合管理器

> **Layer**: Foundation
> **GDD**: design/gdd/turn-manager.md
> **Architecture Module**: Foundation — 回合管理器
> **Status**: Ready
> **Stories**: 2 stories — 2026-05-31 (TR-ID 回填于对话 5/5)

## Overview

回合管理器是星辰之轭回合制策略的**核心调度引擎**。它驱动 3 阶段循环（`DEPLOYMENT` → `EXECUTION` → `CLEANUP` → `DEPLOYMENT`），在部署阶段收集玩家和 AI 的出征指令，然后通过 5 步骤快照模型统一结算：收集全部指令 → 拍星球快照 → 基于快照计算所有战斗 → 一次性应用结果 → 收尾（生产、胜负、国王寿命）。回合计数器递增，阶段切换通过 EventBus 广播。

此 Epic 是回合制玩法的调度中心——它定义了"一回合"是什么以及回合内发生什么。

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0001: 事件总线架构 | 阶段切换通过 EventBus 广播 | LOW |
| ADR-0004: 回合结算模型 | 快照模型 5 步骤，指令顺序无关性保证 | LOW |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-TRN-001 | 3阶段循环 DEPLOYMENT→EXECUTION→CLEANUP→DEPLOYMENT，不可跳转，阶段由 current_phase 枚举控制 | ADR-0004 ✅ |
| TR-TRN-002 | submit_command() 仅在 DEPLOYMENT 阶段返回 true 并入队，其他阶段返回 false | ADR-0004 ✅ |
| TR-TRN-003 | end_turn() 触发 5 步骤快照模型：收集指令→拍快照→基于快照计算→统一应用→收尾 | ADR-0004 ✅ |
| TR-TRN-004 | 快照模型保证指令结算顺序无关——无论计算顺序，最终星球状态一致 | ADR-0004 ✅ |
| TR-TRN-005 | 阶段切换通过 EventBus 广播 deployment_phase_started/execution_phase_started/turn_ended | ADR-0004 ✅ |
| TR-TRN-006 | 超限兵力按比例削减：ratio = available_garrison / total_outgoing，各指令 count = floor(count × ratio) | ADR-0004 ✅ |
| TR-TRN-007 | 空回合（无任何指令）正常执行，产兵照常，turn_number +1 | ADR-0004 ✅ |
| TR-TRN-008 | DEPLOYMENT 之外调用 end_turn() 返回 false + push_warning() | ADR-0004 ✅ |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/turn-manager.md` are verified
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | [Turn Phase Loop & Command Intake](story-001-phase-loop.md) | Logic | Ready | ADR-0004 |
| 002 | [Snapshot Resolution Engine](story-002-snapshot-engine.md) | Logic | Ready | ADR-0004 |

## Next Step

Run `/story-readiness production/epics/turn-manager/story-001-phase-loop.md` to validate the first story is ready for implementation.
