# Epic: 星图/关卡数据

> **Layer**: Feature
> **GDD**: design/gdd/level-data.md
> **Architecture Module**: Feature — 星图数据
> **Status**: Ready
> **Stories**: 2 stories — 2026-05-31 (对话 5/5)

## Overview

星图/关卡数据系统是关卡设计的"画布"——它定义一个关卡中有哪些星球、它们在什么位置、用什么属性、相互之间如何连接、初始谁占什么星。关卡数据存储在 `.tres` Resource 文件中，设计师在 Godot 编辑器中可视化编辑。

MVP 关卡：1 颗行星 + 3 颗卫星，4 条连接路线，2 个玩家起始星 + 1 个敌方星 + 1 个中立星。

## Governing ADRs

> Feature 层无独立 ADR。遵循 Foundation/Core ADR 约束。

| ADR | Relevant Decision |
|-----|-------------------|
| ADR-0002 | LevelData 定义为 `.tres` Resource |
| ADR-0005 | PlanetDef + Connection 为关卡静态数据单元 |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-LVL-001 | LevelData Resource 结构：level_id/level_name/planets/connections/initial_owner/initial_garrison | ADR-0002 ✅ |
| TR-LVL-002 | MVP 关卡 tutorial_1：4 颗星（地球/月球/火星/火卫一），3 条连接，初始 PLAYER 占1 + ENEMY 占1 | ADR-0005 ✅ |
| TR-LVL-003 | PlanetDef.id 重复检测→push_error()；Connection 引用不存在星球→push_warning()+跳过 | ADR-0005 ✅ |
| TR-LVL-004 | 关卡数据存储在 .tres 文件中，设计师在 Godot 编辑器中可视化编辑 | ADR-0002 ✅ |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/level-data.md` are verified
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | [LevelData / PlanetDef / Connection Resource 类 + tutorial_1.tres](story-001-level-data-resource-classes.md) | Logic + Config/Data | Ready | ADR-0002, ADR-0005 |
| 002 | [init_from_level() 集成 + 边界校验](story-002-level-init-integration.md) | Integration | Ready | ADR-0005 |

## Next Step

Run `/story-readiness production/epics/level-data/story-001-level-data-resource-classes.md` to validate the first story is ready for implementation.
