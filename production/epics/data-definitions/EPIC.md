# Epic: 数据定义

> **Layer**: Foundation
> **GDD**: design/gdd/data-definitions.md
> **Architecture Module**: Foundation — 数据定义
> **Status**: Ready
> **Stories**: 3 stories — 2026-05-31 (TR-ID 回填于对话 5/5)

## Overview

数据定义系统是星辰之轭的**类型系统基础**。它集中管理所有枚举（`UnitType`、`Faction`、`PlanetAttribute`、`TalentType`）、全局常量表（三角克制矩阵、产量参数）以及结构化数据 Resource 类（`UnitStats`、`LevelData`）。所有其他系统通过 `DataDef` autoload 统一访问，不持有独立的数据副本。

此 Epic 实现 Foundation 层的数据定义模块，是后续所有系统的编译依赖——所有代码文件都从 DataDef 引用类型和常量。

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0002: 数据定义格式 | 混合方案：枚举/常量用 GDScript，结构化数据用 Godot Resource (.tres) | LOW |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-DEF-001 | DataDef autoload 作为唯一数据入口，集中管理所有枚举、常量和 Resource 加载 | ADR-0002 ✅ |
| TR-DEF-002 | UnitType 枚举定义 INFANTRY/ARCHER/CAVALRY 三种兵种 | ADR-0002 ✅ |
| TR-DEF-003 | Faction 枚举定义 NEUTRAL/PLAYER/ENEMY 三个势力 | ADR-0002 ✅ |
| TR-DEF-004 | PlanetAttribute 枚举定义 NORMAL/RICH/FORTRESS/BARREN 四种星球属性 | ADR-0002 ✅ |
| TR-DEF-005 | TalentType 枚举定义 CONQUEROR/RESEARCHER/HOARDER/DIPLOMAT 四种国王天赋 | ADR-0002 ✅ |
| TR-DEF-006 | DAMAGE_MATRIX 3×3 三角克制矩阵存储为 GDScript const Dictionary，倍率 1.5/1.0/0.75 | ADR-0002 ✅ |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/data-definitions.md` are verified
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | [Enums & Constants Definition](story-001-enums-constants.md) | Logic | Ready | ADR-0002 |
| 002 | [Resource Classes Definition](story-002-resource-classes.md) | Config/Data | Ready | ADR-0002 |
| 003 | [Resource Loading & Error Handling](story-003-resource-loading.md) | Integration | Ready | ADR-0002 |

## Next Step

Run `/story-readiness production/epics/data-definitions/story-001-enums-constants.md` to validate the first story is ready for implementation.
