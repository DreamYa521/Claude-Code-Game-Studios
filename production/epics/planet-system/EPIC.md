# Epic: 星球系统

> **Layer**: Core
> **GDD**: design/gdd/planet-system.md
> **Architecture Module**: Core — 星球系统 ⚠️ 瓶颈
> **Status**: Ready
> **Stories**: 3 stories — Ready

## Overview

星球系统管理游戏中所有星球的运行时状态——归属方、驻兵数、产量、邻接关系。它是 Core 层的**瓶颈系统**（7 个系统直接依赖），为出征校验、生产调度、AI 评估、战斗结算提供统一的数据访问接口。

数据分层：`PlanetDef` Resource (.tres) 存储关卡设计静态数据（位置、属性、连接），`RuntimePlanetData` Dictionary 存储运行时动态状态（owner, garrison）。所有变更通过 PlanetSystem API 封装，归属变更广播 `EventBus.planet_owner_changed`。

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0005: 星球数据模型 | PlanetDef(.tres)静态 + RuntimePlanetData(Dictionary)动态，快照用 `.duplicate(true)` | LOW |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-PLT-001 | RuntimePlanetData Dictionary 维护 9 个字段 | ADR-0005 ✅ |
| TR-PLT-002 | `max_garrison = int(GARRISON_DEFAULT_MAX × ATTR_GARRISON_MULT[attribute])` | ADR-0005 ✅ |
| TR-PLT-003 | `production_rate = PRODUCTION_BASE_RATE × ATTR_PRODUCTION_MULT[attribute]` | ADR-0005 ✅ |
| TR-PLT-004 | `init_from_level(level_data)` 一次性初始化：清空→构建→邻接→初始归属→emit | ADR-0005 ✅ |
| TR-PLT-005 | `update_garrison(id, delta)`：delta可正可负，不允许负数，阶段 gate | ADR-0005 ✅ |
| TR-PLT-006 | `set_owner(id, faction)`：变更归属 → 广播 EventBus，阶段 gate | ADR-0005 ✅ |
| TR-PLT-007 | `are_connected(a, b)` O(1) + `get_adjacent_planets(id)` | ADR-0005 ✅ |
| TR-PLT-008 | `get_planets_by_owner(faction)` 按归属方筛选 | ADR-0005 ✅ |
| TR-PLT-009 | `take_snapshot()` Dictionary.duplicate(true) 深拷贝 | ADR-0004 ✅ |
| TR-PLT-010 | `get_planet(id)` 返回浅拷贝防外部修改 | ADR-0005 ✅ |
| TR-PLT-011 | Connection 双向自动处理：A↔B | ADR-0005 ✅ |
| TR-PLT-012 | 无效引用 push_warning()（Connection/initial_owner） | ADR-0005 ✅ |

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | 星球运行时数据结构与属性计算 | Logic | Ready | ADR-0005 |
| 002 | 初始化流程与邻接表构建 | Logic | Ready | ADR-0005 |
| 003 | 状态变更、查询与快照 | Integration | Ready | ADR-0005, ADR-0004 |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/planet-system.md` are verified
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Next Step

Run `/story-readiness production/epics/planet-system/story-001-planet-runtime-data.md` then `/dev-story` to begin implementation.
