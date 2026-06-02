# Epic: 国王系统

> **Layer**: Core
> **GDD**: design/gdd/king-system.md
> **Architecture Module**: Core — 国王系统
> **Status**: Ready
> **Stories**: 2 stories — TO DO

## Overview

国王系统是星辰之轭的核心 hook——每位国王有有限的寿命（行动次数），玩家每回合消耗 1 次。寿命耗尽时国王去世，继承人自动继位，代际计数递增。MVP 阶段国王天赋仅为标签（不影响机制），但数据结构已预留扩展。

30 回合默认寿命意味着每局约 30 回合的时间压力——"每个行动都有代价"。

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0008: 国王寿命模型 | 基于行动次数的寿命模型，end_turn() 消耗 1，去世→暂停→继位 | LOW |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-KNG-001 | KingData 结构：name/talent/lifespan/actions_used/age/generation/talent_bonus | ADR-0008 ✅ |
| TR-KNG-002 | 每回合消耗 1 寿命（consume_turn() 在 CLEANUP 步骤 5 调用），actions_remaining = lifespan - actions_used | ADR-0008 ✅ |
| TR-KNG-003 | actions_remaining==0 → 国王去世：emit king_died → GameState→PAUSED → 自动继位 → emit king_succeeded → GameState→PLAYING | ADR-0008 ✅ |
| TR-KNG-004 | 自动继位：随机名字+随机天赋，lifespan=30，generation+1，actions_used=0 | ADR-0008 ✅ |
| TR-KNG-005 | init_king() 游戏开始时创建初始国王（随机名字+随机天赋，generation=1），emit king_succeeded(null, king) | ADR-0008 ✅ |
| TR-KNG-006 | MVP 天赋仅为标签（不影响机制），talent_bonus Dictionary 留空，Vertical Slice 填充效果 | ADR-0008 ✅ |
| TR-KNG-007 | actions_remaining() <= 3 时 UI 显示警告'国王年事已高' | ADR-0008 ✅ |
| TR-KNG-008 | 名字池：MALE_NAMES×10 + FEMALE_NAMES×10，随机抽取 | ADR-0008 ✅ |

## Stories

| # | Story | Type | TR Coverage | Estimate | Status |
|---|-------|------|-------------|----------|--------|
| 001 | [KingData 结构 + consume_turn() + 去世/继位核心](story-001-king-core.md) | Logic | TR-KNG-001~006,008 | 2h | Ready |
| 002 | [回合集成 + EventBus + 边界处理](story-002-king-integration.md) | Integration | TR-KNG-003,007 | 2h | Ready |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/king-system.md` are verified
- All Logic and Integration stories have passing test files in `tests/`
- All Visual/Feel and UI stories have evidence docs with sign-off in `production/qa/evidence/`

## Next Step

Run `/create-stories king-system` to break this epic into implementable stories.
