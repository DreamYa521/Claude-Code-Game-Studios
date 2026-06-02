# Epic: 出征系统

> **Layer**: Core
> **GDD**: design/gdd/deployment-system.md
> **Architecture Module**: Core — 出征系统
> **Status**: Ready
> **Stories**: 2 stories — TO DO

## Overview

出征系统管理玩家的核心操作——从己方星球选择兵力、选择目标、确认发兵。它是玩家与游戏之间最主要的交互接口：玩家每回合的操作就是在星图上"点选发兵"。出征系统负责校验指令合法性、管理指令队列、在回合结算中提交。

校验规则：源星为己方、目标星相邻、出兵数 ≤ 当前 garrison（需预留防守）。

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0005: 星球数据模型 | 通过 PlanetSystem 查询 garrison 和邻接关系做校验 | LOW |
| ADR-0006: 战斗公式设计 | 出征指令携带 unit_type，战斗结算时作用于克制计算 | LOW |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-DPL-001 | `deploy(from, to, count, unit_type)` 7 项合法性校验：己方星/非己方目标/相邻/≥1兵/≤驻兵/is_playing/DEPLOYMENT阶段 | ADR-0004 ✅ |
| TR-DPL-002 | DeploymentCommand 结构：from_planet/to_planet/count/unit_type/player_owned | ADR-0004 ✅ |
| TR-DPL-003 | submit_command(cmd) 后立即扣除出发星驻兵（防止同一批兵重复使用） | ADR-0004 ✅ |
| TR-DPL-004 | get_pending() 返回当前等待结算的全部玩家指令，在步骤 1 被 TurnManager 调用 | ADR-0004 ✅ |
| TR-DPL-005 | 同星多条指令：每条校验 count<=实时garrison，逐条扣减，自动防超限 | ADR-0004 ✅ |
| TR-DPL-006 | 部署到空旷中立星 (garrison=0) 允许，到达后无战斗即占领 | ADR-0004 ✅ |
| TR-DPL-007 | 已提交指令不可撤销——确认即承诺，无回滚机制 | ADR-0004 ✅ |

## Stories

| # | Story | Type | TR Coverage | Estimate | Status |
|---|-------|------|-------------|----------|--------|
| 001 | [deploy() + validate() + DeploymentCommand 核心](story-001-deploy-validate-core.md) | Logic | TR-DPL-001~003,005~007 | 2h | Ready |
| 002 | [回合管线集成 + get_pending() + PlanetSystem 对接](story-002-deployment-integration.md) | Integration | TR-DPL-004 | 2h | Ready |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/deployment-system.md` are verified
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Next Step

Run `/create-stories deployment-system` to break this epic into implementable stories.
