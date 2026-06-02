# 出征系统 (Deployment System)

> **Status**: In Design
> **Author**: Claude + 老大
> **Last Updated**: 2026-05-31
> **Implements Pillar**: ♟️ 从容推演, ⚖️ 抉择之重 (每次发兵都是不可逆的承诺)
> **Architecture**: [ADR-0004](../docs/architecture/adr/adr-0004-turn-resolution-model.md) (submit_command), [ADR-0005](../docs/architecture/adr/adr-0005-planet-data-model.md) (邻接查询)

## Overview

出征系统管理玩家的核心操作——从己方星球选择兵力、选择目标、确认发兵。它是玩家与游戏之间最主要的交互接口：玩家每回合的操作就是在星图上"点选发兵"。出征系统负责校验指令合法性、管理指令队列、在回合结算中提交。

出征指令不是立即执行的——它们排队在 `TurnManager` 中，回合结束时统一结算（ADR-0004 快照模型）。

## Player Fantasy

玩家在星图上看到己方星球 A 有 12 兵，相邻敌方星球 B 有 5 兵。内心计算：留 3 兵防守，出 9 兵应该够。拖动兵力滑块 → 点击 B → 确认。然后去看下一路。这就是星辰之轭的核心操作——每一次"确认"都是一个不可逆的承诺，回合结束时所有承诺同时兑现。

## Detailed Rules

### 规则 1: 部署流程

1. 玩家点击己方星球 A → 星图 UI 高亮 A + 可到达的相邻星球
2. 玩家点击目标星球 B（必须是相邻的敌方或中立星球）
3. 出征 UI 弹出：兵力滑块（1 ~ A.garrison）+ 确认/取消
4. 玩家确认 → `DeploymentSystem.deploy(A, B, count, unit_type)`
5. 指令入队 → 等待回合结束结算

### 规则 2: 合法性校验

`validate(from, to, count)` 检查以下条件：
- `from_planet.owner == PLAYER`（只能从己方星球发兵）
- `to_planet.owner != PLAYER`（不能打自己）
- `are_connected(from, to) == true`（只能打相邻星球）
- `count >= 1`（至少出 1 兵）
- `count <= from_planet.garrison`（不能超出发星驻兵）
- `GameState.is_playing() == true`（只能在游戏中部署）
- `TurnManager.current_phase == DEPLOYMENT`（只能在部署阶段）

任一条件不满足 → 返回 false + 具体拒绝原因。

### 规则 3: 指令入队

`deploy(from, to, count, unit_type)`:
- 通过 `validate()` 后创建 `DeploymentCommand`
- 调用 `TurnManager.submit_command(cmd)`
- 扣除出发星驻兵（立即扣除，防止玩家重复使用同一批兵）: `PlanetSystem.update_garrison(from, -count)`
- MVP 所有玩家指令默认 `unit_type = INFANTRY`

### 规则 4: DeploymentCommand 结构

```gdscript
class DeploymentCommand:
    var from_planet: int
    var to_planet: int
    var count: int
    var unit_type: DataDef.UnitType
    var player_owned: bool  # true=玩家指令, false=AI指令
```

### 规则 5: 指令获取

`get_pending() → Array[DeploymentCommand]`：返回当前等待结算的全部玩家指令。在回合结算步骤 1 被 `TurnManager._collect_commands()` 调用。

### 规则 6: 同星多条指令

玩家可以从同一星球多次发兵（如：A→B 出 5 兵，A→C 出 3 兵）。`validate()` 逐条检查 `count <= garrison`，因此：
- 第 1 条指令：A 有 12 兵 → 出 5 → A 剩 7
- 第 2 条指令：A 有 7 → 出 3 → A 剩 4
- 如果玩家总共想出 10 兵但 A 只有 8 → 第 2 条 `validate()` 失败

不会出现总和超限的情况（因为每步都能看到上一步的 garrison 扣减）。

### States and Transitions

```
玩家操作:
  点 A → 点 B → 确认（count + unit_type）
    → DeploymentSystem.deploy(A, B, count, INFANTRY)
    → validate(A, B, count) → true
    → TurnManager.submit_command(cmd)
    → PlanetSystem.update_garrison(A, -count)
    → KingSystem.consume_action(1)   [MVP: 回合结束统一消耗]

回合结算 (步骤 1):
  → TurnManager._collect_commands()
    → AIEnemy.compute_turn() → ai_commands
    → DeploymentSystem.get_pending() → player_commands
    → all_commands = player_commands + ai_commands
```

### Interactions with Other Systems

| 调用方/被调用方 | 操作 |
|----------------|------|
| 出征 UI | 调用 `deploy()` 创建指令 |
| 星球系统 | `get_planets_by_owner()`, `are_connected()`, `update_garrison()` |
| 回合管理器 | `submit_command()`, `get_pending()` |
| GameState | `is_playing()` gate |

## Formulas

不适用 — 出征系统无公式，纯数据操作和校验。

## Edge Cases

- **玩家取消部署**: 指令不创建，不扣 garrison——UI 关闭即丢弃
- **部署后因故(如国王去世)回合回滚**: MVP 不支持回滚——已提交的指令不可撤销。这是设计意图："确认即承诺"
- **部署到空旷中立星 (garrison=0)**: 允许——`validate()` 不检查目标星 garrison。到达后战斗结算判定 `attacker_wins=true`（无防守方），占领系统接管
- **发兵数量 = 全部 garrison**: 允许——玩家可以选择"倾巢而出"，但出发星变为 0 驻兵。若相邻有敌星，AI 可能趁机拿下空的出发星
- **从被占领或 garrison 不足的星发兵**: `validate()` 实时检查，返回 false

## Dependencies

**上游（本系统依赖）**:
| 系统 | 依赖内容 |
|------|---------|
| 星球系统 | `get_planets_by_owner()`, `are_connected()`, `update_garrison()` |
| 回合管理器 | `submit_command()`, `current_phase` |
| GameState | `is_playing()` |
| 数据定义 | `UnitType` 枚举 |

**下游（依赖本系统的系统）**:
| 系统 | 依赖类型 | 依赖内容 |
|------|---------|---------|
| 回合管理器 | Hard | `get_pending()` 在步骤 1 获取玩家指令 |
| 出征 UI | Hard | `deploy()` 接口 |
| AI 敌人 | Soft | `DeploymentCommand` 结构 |

## Tuning Knobs

无 — 出征系统无独立参数。

## Acceptance Criteria

- **GIVEN** 己方星 A (garrison=10) 邻敌方星 B，**WHEN** `deploy(A, B, 5, INFANTRY)`，**THEN** 返回 true，A.garrison 变为 5
- **GIVEN** 己方星 A (garrison=3)，**WHEN** `deploy(A, B, 5, INFANTRY)`，**THEN** 返回 false，A.garrison 保持 3
- **GIVEN** A 和 B 不相邻，**WHEN** `deploy(A, B, 3, INFANTRY)`，**THEN** 返回 false（不能跳星出兵）
- **GIVEN** 目标星 owner=PLAYER，**WHEN** `deploy(A, B, 3, INFANTRY)`，**THEN** 返回 false（不能打自己）
- **GIVEN** GameState 当前为 PAUSED，**WHEN** `deploy()` 调用，**THEN** 返回 false
- **GIVEN** TurnPhase 为 EXECUTION，**WHEN** `deploy()` 调用，**THEN** 返回 false
- **GIVEN** 从星球 A 发出 2 条指令（5兵→B, 3兵→C），**WHEN** `get_pending()`，**THEN** 返回 2 条指令
