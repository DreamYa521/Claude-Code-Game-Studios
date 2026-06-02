# Systems Index: 星辰之轭（暂定名）

> **Status**: Draft
> **Created**: 2026-05-31
> **Last Updated**: 2026-05-31
> **Source Concept**: design/gdd/game-concept.md

---

## Overview

星辰之轭 Part 2 是一个回合制领地策略游戏。玩家从一张星图开始，点选发兵、占点产兵、与 AI 敌人争夺星球控制权，回合结束时同时结算所有出征指令。国王代际系统为核心 hook——每位国王天赋不同、寿命有限、每个行动都有代价。

MVP 聚焦于验证核心循环：**点选发兵 → 占点产兵 → 国王寿命约束 → 全歼敌人**。共 19 个系统，分层搭建。

---

## Systems Enumeration

| # | System Name | Category | Priority | Status | Design Doc | Depends On |
|---|-------------|----------|----------|--------|------------|------------|
| 1 | 数据定义 | Foundation | MVP | Designed | data-definitions.md | — |
| 2 | 事件总线 | Foundation | MVP | Designed | event-bus.md | — |
| 3 | GameState 管理器 | Foundation | MVP | Designed | gamestate-manager.md | 事件总线 |
| 4 | 回合管理器 | Foundation | MVP | Designed | turn-manager.md | 事件总线 |
| 5 | 星球系统 | Core | MVP | Designed | [planet-system.md](planet-system.md) | 数据定义, 事件总线 |
| 6 | 兵种系统 | Core | MVP | Designed | [unit-system.md](unit-system.md) | 数据定义, 事件总线 |
| 7 | 生产系统 | Core | MVP | Designed | [production-system.md](production-system.md) | 星球系统, 兵种系统, 回合管理器 |
| 8 | 战斗结算 | Core | MVP | Designed | [combat-resolution.md](combat-resolution.md) | 兵种系统 |
| 9 | 占领系统 | Core | MVP | Designed | [occupation-system.md](occupation-system.md) | 星球系统, 战斗结算 |
| 10 | 出征系统 | Core | MVP | Designed | [deployment-system.md](deployment-system.md) | 星球系统, 兵种系统, 回合管理器 |
| 11 | 国王系统 | Core | MVP | Designed | [king-system.md](king-system.md) | 回合管理器, 事件总线 |
| 12 | AI 敌人 | Core | MVP | Designed | [ai-enemy.md](ai-enemy.md) | 星球系统, 兵种系统, 出征系统, 回合管理器 |
| 13 | 星图/关卡数据 | Feature | MVP | Designed | [level-data.md](level-data.md) | 星球系统, 数据定义 |
| 14 | 胜负条件 | Feature | MVP | Designed | [win-conditions.md](win-conditions.md) | 星球系统, GameState 管理器 |
| 15 | 星图 UI | Presentation | MVP | Designed | [star-map-ui.md](star-map-ui.md) | 星图数据, 星球系统 |
| 16 | 出征 UI | Presentation | MVP | Designed | [deployment-ui.md](deployment-ui.md) | 出征系统, 星球系统 |
| 17 | 回合控制 UI | Presentation | MVP | Designed | [turn-control-ui.md](turn-control-ui.md) | 回合管理器, GameState 管理器 |
| 18 | 国王 UI | Presentation | MVP | Designed | [king-ui.md](king-ui.md) | 国王系统 |
| 19 | 战斗动画 | Presentation | MVP | Designed | [battle-animation.md](battle-animation.md) | 战斗结算, 出征系统 |

---

## Categories

| Category | Description | Systems |
|----------|-------------|---------|
| **Foundation** | 基础设施，零依赖 | 数据定义, 事件总线, GameState, 回合管理器 |
| **Core** | 玩法核心，依赖 Foundation | 星球, 兵种, 生产, 战斗, 占领, 出征, 国王, AI |
| **Feature** | 依赖 Core，组装可用玩法 | 星图数据, 胜负条件 |
| **Presentation** | UI 和视觉反馈 | 星图 UI, 出征 UI, 回合控制 UI, 国王 UI, 战斗动画 |

---

## Priority Tiers

| Tier | Definition | Target Milestone | Systems |
|------|------------|------------------|---------|
| **MVP** | 核心循环可跑通、可验证"这好玩吗" | 1个月 | 全部 19 个（MVP 简化版） |
| **Vertical Slice** | 太阳系完整 + 1 外星系 | 2-3个月 | 多层星图、多种国王类型 |
| **Alpha** | 3-5 星系、科技积累 | 6个月 | 科技系统、外交雏形 |
| **Full Vision** | 完整代际系统、先王汇报 | 1-2年 | 完整动画演出、Part 1 合并 |

---

## Dependency Map

### Foundation Layer（零依赖 — 设计和搭建最先）

1. **数据定义** — 兵种枚举、三角克制表、星球属性等所有常量。一切引用的起点。
2. **事件总线** — 系统间解耦通信。没有它各模块会直接耦合。
3. **GameState 管理器** — 状态机：标题 → 游戏中 → 暂停 → 胜利/失败。
4. **回合管理器** — 回合计数、结束回合指令、同时结算调度。回合制的心脏。

### Core Layer（依赖 Foundation）

1. **星球系统** ⚠️ *瓶颈系统（7 个依赖）* — 归属方、生产力、驻兵上限、星球属性。设计时优先定稿。
2. **兵种系统** — 步/弓/骑三种兵，三角克制（步→弓→骑→步），属性定义。
3. **生产系统** — 占星自动产兵，驻兵上限控制。让占领有经济意义。
4. **战斗结算** — 双方兵力碰撞后的胜负计算、战损公式。
5. **占领系统** — 攻击方打赢 → 星球易主。触发生产变更。
6. **出征系统** — 点己方星 → 调兵数 → 选目标 → 确认。玩家每回合核心操作。
7. **国王系统** — 一个国王 + 天赋 + 有限寿命 + 行动消耗寿命。代际概念 MVP 验证。
8. **AI 敌人** — 决策逻辑：进攻哪个星、从哪出兵、出多少、防守优先级。

### Feature Layer（依赖 Core）

1. **星图/关卡数据** — 1 行星 + 3 卫星的初始布局、连接路线、初始归属。
2. **胜负条件** — 每回合结束后检查：全歼敌人 = 胜；被全歼 = 负。

### Presentation Layer（依赖 Feature + Core）

1. **星图 UI** — 星球节点 + 连接线 + 兵力数字 + 归属颜色。玩家所见即所得。
2. **出征 UI** — 兵力滑块 + 目标星球高亮 + 确认/取消。
3. **回合控制 UI** — 结束回合按钮 + 回合数 + 状态提示。
4. **国王 UI** — 国王名字 + 天赋标签 + 剩余行动次数/寿命。
5. **战斗动画** — 兵力短线流动，简洁不花哨。

---

## Recommended Design Order

| Order | System | Priority | Layer | Est. Effort |
|-------|--------|----------|-------|-------------|
| 1 | 数据定义 | MVP | Foundation | S |
| 2 | 事件总线 | MVP | Foundation | S |
| 3 | GameState 管理器 | MVP | Foundation | S |
| 4 | 回合管理器 | MVP | Foundation | S |
| **5** | **星球系统** ⚠️ | MVP | Core | M |
| 6 | 兵种系统 | MVP | Core | M |
| 7 | 生产系统 | MVP | Core | S |
| 8 | 战斗结算 | MVP | Core | M |
| 9 | 占领系统 | MVP | Core | S |
| 10 | 出征系统 | MVP | Core | M |
| 11 | 国王系统 | MVP | Core | M |
| 12 | AI 敌人 | MVP | Core | M |
| 13 | 星图/关卡数据 | MVP | Feature | S |
| 14 | 胜负条件 | MVP | Feature | S |
| 15 | 星图 UI | MVP | Presentation | M |
| 16 | 出征 UI | MVP | Presentation | M |
| 17 | 回合控制 UI | MVP | Presentation | S |
| 18 | 国王 UI | MVP | Presentation | S |
| 19 | 战斗动画 | MVP | Presentation | S |

> **Effort**: S = 1 session, M = 2-3 sessions, L = 4+ sessions
> Foundation 的 4 个系统体量小、可快速完成。
> Foundation 完成后，星球系统和兵种系统可**并行**设计（两者不互相依赖）。

---

## Circular Dependencies

- **None found** ✅

所有依赖都是单向分层，从 Foundation → Core → Feature → Presentation 逐层推进。

---

## High-Risk Systems

| System | Risk Type | Risk Description | Mitigation |
|--------|-----------|-----------------|------------|
| **星球系统** | Design | 7 个系统依赖它。产量公式或驻兵上限定义模糊会导致大量返工 | 优先设计、尽早定稿；公式参数化方便后期调 |
| **AI 敌人** | Design | 太弱=无聊，太强=挫败。需在"有挑战"和"能打赢"之间平衡 | 先做简单规则 AI（进攻最近敌星+保留一定防守兵力），跑起来再调 |
| **国王系统** | Design | 行动消耗寿命的平衡——太宽松没约束感，太严苛玩家觉得被限制 | 数值先拍、跑起来再调。公式写在设计文档里，方便改 |
| **回合管理器** | Technical | 同时结算逻辑——所有出征指令在同一刻执行，顺序不能影响结果 | 先收集所有指令 → 统一计算 → 再更新状态，严格两阶段 |

---

## Progress Tracker

| Metric | Count |
|--------|-------|
| Total systems identified | 19 |
| Design docs started | 19 |
| Design docs reviewed | 19 |
| Design docs approved | 0 |
| MVP systems designed | 19 / 19 |

---

## Next Steps

- [x] Foundation 层 GDD ×4 完成（数据定义, 事件总线, GameState, 回合管理器）
- [x] Core 层 GDD ×8 完成（星球, 兵种, 生产, 战斗, 占领, 出征, 国王, AI）
- [x] Feature 层 GDD ×2 完成（星图/关卡数据, 胜负条件）
- [x] Presentation 层 GDD ×5 完成（星图UI, 出征UI, 回合控制UI, 国王UI, 战斗动画）
- [x] Core 层 ADR ×4 完成（ADR-0005~0008）
- [ ] 运行 `/review-all-gdds` 验证全部 GDD
- [ ] `/create-epics` 打包为 Epic
- [ ] `/create-stories` 按 Epic 拆任务
- [ ] `/sprint-plan` 排期
- [ ] `/dev-story` 开工
