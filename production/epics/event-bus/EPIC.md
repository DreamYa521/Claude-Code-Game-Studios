# Epic: 事件总线

> **Layer**: Foundation
> **GDD**: design/gdd/event-bus.md
> **Architecture Module**: Foundation — 事件总线
> **Status**: Ready
> **Stories**: 3 stories — 2026-05-31 (story-003 追加于对话 5/5)

## Overview

事件总线是星辰之轭所有跨系统通信的**唯一通道**。它通过 `EventBus` autoload 集中管理全部 Signal——系统之间不直接持有对方引用，所有通知（星球沦陷、回合结束、国王去世、战斗完成）统一走 EventBus 发送和订阅。

此 Epic 实现 Foundation 层的通信基础设施，解耦所有后续系统。无 EventBus 则各系统必须互相引用，形成耦合网。

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0001: 事件总线架构 | 集中式 EventBus autoload，基于 Godot 原生 Signal | LOW |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-EVT-001 | EventBus autoload 集中管理全部跨系统 Signal | ADR-0001 ✅ |
| TR-EVT-002 | fire-and-forget 模式，订阅者异常不传播 | ADR-0001 ✅ |
| TR-EVT-003 | subscribe / unsubscribe 管理回调生命周期 | ADR-0001 ✅ |
| TR-EVT-004 | Signal 命名 snake_case 过去式，新增只追加末尾 | ADR-0001 ✅ |
| TR-EVT-005 | 同 Signal 按订阅顺序调用 | ADR-0001 ✅ |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/event-bus.md` are verified
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | [EventBus Core — Signal Declarations](story-001-signal-declarations.md) | Logic | Ready | ADR-0001 |
| 002 | [EventBus Safety — Recursion Guard & Lifecycle](story-002-safety-recursion-guard.md) | Logic | Ready | ADR-0001 |
| 003 | [Presentation 层信号补充](story-003-presentation-signals.md) | Logic | Ready | ADR-0001 |

## Next Step

Run `/story-readiness production/epics/event-bus/story-001-signal-declarations.md` to validate the first story is ready for implementation.
