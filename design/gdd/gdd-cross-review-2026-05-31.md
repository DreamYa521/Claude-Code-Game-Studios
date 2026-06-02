# Cross-GDD Review Report

**Date**: 2026-05-31
**GDDs Reviewed**: 4 (Foundation 层全部)
**Systems Covered**: 数据定义, 事件总线, GameState 管理器, 回合管理器
**Verdict**: **PASS**

---

## Consistency Issues

### Blocking

无。

### Warnings

⚠️ **Forward References to Undesigned Types**

data-definitions、event-bus、turn-manager 三个 GDD 引用了 Core 层才正式定义的类型：

| 类型 | 被引用于 | 应属于 |
|------|---------|--------|
| `BattleResult` | event-bus (signal payload), turn-manager (步骤3) | 战斗结算 GDD (未写) |
| `DeploymentCommand` | turn-manager (submit_command), event-bus (引用于交互表) | 出征系统 GDD (未写) |
| `KingData` | event-bus (signal payload), turn-manager (步骤5) | 国王系统 GDD (未写) |

这些类型在 `docs/architecture/architecture.md` Phase 4 中有临时定义，但 GDD 层面没有归属。Core GDD 写时必须确认类型定义与 Foundation GDD 的引用一致。

⚠️ **Dependency Bidirectionality Unverifiable**

所有 4 个 GDD 的下游依赖系统均未设计。双向依赖验证需在 Core GDD 写完后重新运行 `/review-all-gdds`。

⚠️ **回合管理器对 Core 系统接口做了假设**

turn-manager.md 步骤 1-5 调用 8 个 Core 层系统方法。接口在 architecture.md 中有定义，但 GDD 层面未正式确认。Core GDD 写时若接口变更，回合管理器 GDD 需同步更新。

---

## Game Design Issues

### Blocking

无。

### Warnings

无 — Foundation 基础设施系统不涉及 progression loops、economy、difficulty curves 等游戏设计维度。

---

## Cross-System Scenario Walkthrough

**场景 1: 游戏初始化** — PASS  
`DataDef._ready()` → EventBus 就绪 → `GameState.transition_to(PLAYING)` → `game_state_changed` → TurnManager DEPLOYMENT  
初始化顺序由 autoload 优先级保证，无 race condition。

**场景 2: 空回合（无任何指令）** — PASS  
`end_turn()` → 步骤1 空队列 → 步骤2 快照 → 步骤3/4 跳过 → 步骤5 产兵照常 → `turn_ended`  
turn-manager Edge Cases 已明确覆盖。

**场景 3: 回合结算中触发胜利** — PASS  
步骤5 `check_victory()` → `GameState.transition_to(VICTORY)` → turn-manager 尝试回到 DEPLOYMENT → `is_playing() == false` gate 阻止  
turn-manager Edge Cases 已明确覆盖。

---

## GDDs Flagged for Revision

无。4 个 GDD 在 Foundation 层范围内内部一致。Warnings 是 Core 层的前向依赖，非当前 GDD 问题。

---

## Recommended Actions

- Core GDD 写完后重新运行 `/review-all-gdds` 验证双向依赖
- 写 战斗结算 GDD 时确认 `BattleResult` 结构
- 写 出征系统 GDD 时确认 `DeploymentCommand` 结构
- 写 国王系统 GDD 时确认 `KingData` 结构
