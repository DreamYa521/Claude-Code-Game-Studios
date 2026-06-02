# 胜负条件 (Win/Lose Conditions)

> **Status**: In Design
> **Author**: Claude + 老大
> **Last Updated**: 2026-05-31
> **Implements Pillar**: ♟️ 从容推演 (明确的胜负边界)
> **Architecture**: [ADR-0003](../docs/architecture/adr/adr-0003-gamestate-state-machine.md), [ADR-0004](../docs/architecture/adr/adr-0004-turn-resolution-model.md)

## Overview

胜负条件系统在每个回合的 CLEANUP 阶段检查游戏是否结束——玩家是否全歼了敌人（胜利），或者敌人是否全歼了玩家（失败）。它是游戏循环的终点：一旦触发，GameState 切换到 VICTORY 或 DEFEAT。

MVP 的胜负判定极简：检查归属方列表，没有敌人或没有玩家。不需要计分、评级、星数统计。

## Player Fantasy

玩家最后看到敌方最后一颗星球从红色变蓝——"赢了"。不需要复杂的结算画面（MVP），只需要星图上的颜色全部变成玩家蓝 + "胜利"文字。输了同理，但玩家会在输之前明白"我哪里做错了"。

输不是惩罚——国王老死也是一种"完成"。胜负条件的角色不是裁判，而是"这一局算完了"的信号。

## Detailed Rules

### 规则 1: 检查时机

`WinCondition.check()` 在 `TurnManager._cleanup()` 步骤 5 中调用——在生产系统之后、国王寿命消耗之后：

```
步骤 5 顺序:
  1. ProductionSystem.apply_turn()
  2. WinCondition.check()          ← 生产完成后再判胜负
  3. KingSystem.consume_turn()
  4. EventBus.turn_ended.emit()
```

### 规则 2: 胜利条件

```gdscript
func check_victory() -> bool:
    # 玩家胜利 = 敌方星球全部被消灭（无 ENEMY 拥有的星球）
    var enemy_planets = PlanetSystem.get_planets_by_owner(DataDef.Faction.ENEMY)
    return enemy_planets.is_empty()
```

### 规则 3: 失败条件

```gdscript
func check_defeat() -> bool:
    # 玩家失败 = 玩家星球全部丢失
    var player_planets = PlanetSystem.get_planets_by_owner(DataDef.Faction.PLAYER)
    return player_planets.is_empty()
```

### 规则 4: 胜负互斥

当双方同时全灭（所有星球 NEUTRAL）：
- 理论上 `check_victory() == true` 且 `check_defeat() == true`
- 此时判定为 **DEFEAT**（平局算玩家输——玩家有义务守住至少一颗星）
- 实际上几乎不可能：初始至少各有 1 星，同归于尽需要最后一颗星在同一回合被互相攻占。若发生 → 玩家输

### 规则 5: 触发流程

```gdscript
func check() -> void:
    if check_victory():
        GameState.transition_to(GameState.State.VICTORY)
        EventBus.game_ended.emit("victory")
    elif check_defeat():
        GameState.transition_to(GameState.State.DEFEAT)
        EventBus.game_ended.emit("defeat")
```

- 进入 VICTORY/DEFEAT 后，`GameState.is_playing() == false` → 回合管理器不再接受部署
- VICTORY/DEFEAT 状态只能转换到 TITLE（重新开始），玩家在星图 UI 看到结果

### 规则 6: 国王寿命耗尽不算输

国王去世 → 自动继位 → 游戏继续。国王寿命耗尽不触发胜负判定——代际传承是机制不是终点。

### States and Transitions

```
TurnManager.CLEANUP:
  → ProductionSystem.apply_turn()
  → WinCondition.check()
      → check_victory()? → GameState → VICTORY
      → check_defeat()?  → GameState → DEFEAT
      → 否则继续
  → KingSystem.consume_turn()
  → EventBus.turn_ended.emit()
```

### Interactions with Other Systems

| 调用方/被调用方 | 操作 |
|----------------|------|
| 回合管理器 | 在 CLEANUP 调用 `check()` |
| 星球系统 | `get_planets_by_owner()` |
| GameState | `transition_to(VICTORY/DEFEAT)` |
| 事件总线 | `game_ended` 信号 |

## Formulas

不适用 — 纯逻辑判断，无数学公式。

## Edge Cases

- **游戏开始时一方已经无星**: 初始化错误——`initial_owner` 必须至少给 PLAYER 和 ENEMY 各 1 星。若配置错误 → 首回合 CLEANUP 立即触发 DEFEAT/VICTORY
- **所有星球变 NEUTRAL**: 双方全灭 → DEFEAT（见规则 4）
- **新占领星的生产改变了归属方**: 不改变——`check()` 在生产后执行，新生产的兵不影响 owner
- **国王在同回合去世且胜负触发**: 顺序保证先判胜负再消耗寿命——若玩家这回合赢了，国王去世不发生（VICTORY 状态下 `consume_turn()` 跳过）

## Dependencies

**上游（本系统依赖）**:
| 系统 | 依赖内容 |
|------|---------|
| 星球系统 | `get_planets_by_owner()` |
| GameState | `transition_to(VICTORY/DEFEAT)` |
| 事件总线 | `game_ended` 信号 |

**下游（依赖本系统的系统）**:
| 系统 | 依赖类型 | 依赖内容 |
|------|---------|---------|
| 回合管理器 | Hard | 在 CLEANUP 调用 `check()` |
| 星图 UI | Soft | 监听 `game_ended` 显示结果 |

## Tuning Knobs

无 — 胜负条件无独立参数。

## Acceptance Criteria

- **GIVEN** 敌方 0 颗星、玩家 1+ 颗星，**WHEN** `check()`，**THEN** `GameState.current_state == VICTORY`
- **GIVEN** 玩家 0 颗星、敌方 1+ 颗星，**WHEN** `check()`，**THEN** `GameState.current_state == DEFEAT`
- **GIVEN** 双方都有星球，**WHEN** `check()`，**THEN** `GameState.current_state` 不变（仍为 PLAYING）
- **GIVEN** 双方各 0 颗星，**WHEN** `check()`，**THEN** `GameState.current_state == DEFEAT`（平局判负）
- **GIVEN** `check()` 触发 VICTORY，**WHEN** 检查 EventBus，**THEN** `game_ended` 被 emit，参数为 "victory"
- **GIVEN** VICTORY 状态下，**WHEN** 尝试 `deploy()`，**THEN** 返回 false（`is_playing()` gate）
