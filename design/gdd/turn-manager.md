# 回合管理器 (Turn Manager)

> **Status**: In Design
> **Author**: Claude + 老大
> **Last Updated**: 2026-05-31
> **Implements Pillar**: ♟️ 从容推演 — 回合制的心脏

## Overview

回合管理器是星辰之轭回合制策略的**核心调度引擎**。它驱动 3 阶段循环（`DEPLOYMENT` → `EXECUTION` → `CLEANUP` → `DEPLOYMENT`），在部署阶段收集玩家和 AI 的出征指令，然后通过 5 步骤快照模型统一结算：收集全部指令 → 拍星球快照 → 基于快照计算所有战斗 → 一次性应用结果 → 收尾（生产、胜负、国王寿命）。回合计数器递增，阶段切换通过 EventBus 广播。

遵循 [ADR-0004](../docs/architecture/adr/adr-0004-turn-resolution-model.md)：快照模型保证指令结算顺序无关——无论以什么顺序计算，最终星球状态一致。纯逻辑系统，无场景树依赖。

没有回合管理器，游戏只是"玩家可以随意移动兵力"的沙盒——没有"同时结算"就没有策略深度，没有"结束回合"就没有抉择之重。

## Player Fantasy

回合管理器直接服务于 ♟️ 从容推演 和 ⚖️ 抉择之重 两根支柱。玩家感受的是"这是我深思熟虑后的回合——部署完毕，点击结束，然后看一切同时发生"。没有倒计时催促，没有"操作快的人占便宜"。每一步都有分量，因为每次结束回合后发生的事情不可撤销。

## Detailed Design

### Core Rules

**规则 1: 三阶段循环不可跳转**

`DEPLOYMENT → EXECUTION → CLEANUP → DEPLOYMENT`。不允许从 DEPLOYMENT 直接跳到 CLEANUP，也不允许在 EXECUTION 中途回到 DEPLOYMENT。阶段由 `current_phase` 枚举控制。

**规则 2: 部署阶段接受指令**

`submit_command(cmd: DeploymentCommand) -> bool`。仅在 `DEPLOYMENT` 阶段返回 `true` 并入队；其他阶段返回 `false`。指令在入队时不校验兵力充足性（校验在出征系统 `deploy()` 时完成），只校验阶段正确性。

**规则 3: end_turn() 触发 5 步骤快照模型**

玩家点击"结束回合"或 AI 回合自动触发。步骤 2-4 在 `EXECUTION` 阶段内执行，各系统检查此 gate 拒绝修改星球。

**规则 4: 阶段切换通过 EventBus 广播**

- `deployment_phase_started` — 新回合开始，接受玩家操作
- `execution_phase_started` — 开始执行指令（战斗动画的触发点）
- `turn_ended` — 回合完全结束（UI 刷新、数据同步的触发点）

**规则 5: 回合生命周期**

```
玩家操作阶段 (DEPLOYMENT)
  ├── 玩家: deploy(from, to, count, type) × N
  ├── 玩家: submit_command(cmd) × N
  └── 玩家: 点击"结束回合"
        │
        ▼
      end_turn()
        │
        ├── 阶段切换到 EXECUTION
        │   EventBus.execution_phase_started.emit()
        │
        ├── 步骤 1: 收集全部指令
        │   ai_commands = AI.compute_turn()
        │   player_commands = DeploymentSystem.get_pending_commands()
        │   all_commands = player_commands + ai_commands
        │
        ├── 步骤 2: 拍快照
        │   snapshot = {planet_id: {garrison, owner, max, prod_rate}}
        │
        ├── 步骤 3: 基于快照计算所有战斗
        │   for cmd in all_commands:
        │       results.append(CombatSystem.resolve(cmd, snapshot))
        │   results = _resolve_overdraft(results, snapshot)
        │
        ├── 步骤 4: 统一应用结果
        │   for result in results:
        │       PlanetSystem.update_garrison(result.from, -result.attacker_total)
        │       PlanetSystem.update_garrison(result.to, result.defender_survived - old_def)
        │       if result.attacker_wins:
        │           OccupationSystem.transfer(result.to, attacker_faction)
        │
        ├── 阶段切换到 CLEANUP
        │
        ├── 步骤 5: 收尾
        │   ProductionSystem.apply_turn()
        │   胜负条件.check_victory() / check_defeat()
        │   KingSystem.consume_turn()
        │   turn_number += 1
        │
        ├── EventBus.turn_ended.emit(turn_number)
        │
        └── 阶段切换到 DEPLOYMENT
            EventBus.deployment_phase_started.emit()
```

### States and Transitions

**3 个阶段状态**:

| 阶段 | 玩家可操作 | 系统执行 | 星球状态 |
|------|----------|---------|---------|
| `DEPLOYMENT` | 发兵、结束回合 | — | 只读 |
| `EXECUTION` | 无 | 快照→计算→应用 | 写入中（外部禁止） |
| `CLEANUP` | 无 | 生产→胜负→寿命 | 写入中 |

**阶段转换**:

```
DEPLOYMENT ──(end_turn)──→ EXECUTION ──(结算完毕)──→ CLEANUP ──(自动)──→ DEPLOYMENT
```

转换不可逆。只有 DEPLOYMENT→EXECUTION 由玩家触发，其余自动。

### Interactions with Other Systems

**上游（回合管理器调用）**:

| 系统 | 调用 | 阶段 |
|------|------|------|
| AI 敌人 | `compute_turn() -> Array[DeploymentCommand]` | 步骤 1 |
| 出征系统 | `get_pending_commands() -> Array[DeploymentCommand]` | 步骤 1 |
| 战斗结算 | `resolve(cmd, snapshot) -> BattleResult` | 步骤 3 |
| 星球系统 | `update_garrison(id, delta)`, `set_owner(id, faction)`, `get_all_planets()` | 步骤 2, 4 |
| 占领系统 | `check_occupation(id, result)`, `transfer(id, faction)` | 步骤 4 |
| 生产系统 | `apply_turn()` | 步骤 5 |
| 胜负条件 | `check_victory() -> bool`, `check_defeat() -> bool` | 步骤 5 |
| 国王系统 | `consume_turn()` | 步骤 5 |

**下游（外部查询回合管理器）**:

| 系统 | 查询内容 | 用途 |
|------|---------|------|
| GameState | `is_playing()` gate | 非 PLAYING 状态下暂停回合 |
| 出征系统 | `current_phase` | 仅在 DEPLOYMENT 接受 `deploy()` |
| 回合控制 UI | `turn_number`, `current_phase` | 显示回合数、按钮状态 |
| 所有系统 | EventBus 事件 | 同步刷新 |

## Formulas

回合管理器自身不含数学公式。它调用其他系统的公式（战斗结算、生产计算），但作为调度器不拥有公式。

**超限兵力削减公式**（步骤 3 安全网）:

```
ratio = available_garrison / total_outgoing

Variables:
| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| available_garrison | G | int | 0–max | 出发星球在 snapshot 中的驻兵数 |
| total_outgoing | T | int | 1–N | 从该星球出发的所有指令兵力总和 |
| ratio | r | float | 0.0–1.0 | 每条指令的削减比例 |

Each command: adjusted_count = floor(count × ratio)
Combat recalculated with adjusted_count afterward.

Example: Planet A has G=10 garrison. Two commands from A: cmd1 count=5, cmd2 count=10.
T = 15 > G = 10 → r = 10/15 = 0.666
cmd1: floor(5 × 0.666) = 3, cmd2: floor(10 × 0.666) = 6
Total outgoing: 3+6=9 ≤ 10 ✓
```

该情况不应频繁出现 — 出征系统 `deploy()` 已校验 `count <= current garrison`。仅在玩家发出多条指令后 garrison 未刷新（因为结算时才扣）时触发，作为公平安全网。

## Edge Cases

- **从同一星球出发多条指令总和超限**: 按比例削减（见公式），floor 取整后重新计算战斗。每条指令受到的削减比例相同。
- **玩家指令和 AI 指令攻击同一目标星球**: 各自独立计算战斗，均基于 snapshot 中目标星的 garrison。双方兵力分别与 snapshot 守军交战。应用时 garrison 变化叠加。可能出现"打完守军后双方同时占领"——先应用玩家结果，再应用 AI 结果（后到达的重新占领）。
- **空回合（无任何指令）**: 正常执行步骤 1-5。步骤 3 无指令可计算（跳过），步骤 4 无结果可应用（跳过），步骤 5 产兵照常。回合数 +1。
- **回合结算中 GameState 变化**: 步骤 5 胜负判定触发 `GameState.transition_to(VICTORY/DEFEAT)`。在 CLEANUP→DEPLOYMENT 之前发生，新 DEPLOYMENT 不会进入（GameState 不再是 PLAYING）。
- **AI compute_turn() 超时或异常**: MVP 阶段 AI 是同步简单规则，不会超时。若未来复杂 AI 需要异步，增加超时保护——2 秒后返回已有结果或空数组。
- **DEPLOYMENT 之外调用 end_turn()**: 返回 false + `push_warning()`，回合不推进。
- **回合结算中玩家强制退出**: 步骤 2-4 为同步操作（< 1ms），不存在"结算中退出"的窗口。若在 DEPLOYMENT 阶段退出，指令队列不持久化——丢失当前回合未提交的指令（预期行为）。

## Dependencies

**上游（本系统依赖）**:
- 事件总线 (Hard): 发送阶段事件，订阅 `game_state_changed` 和 `king_died`
- GameState (Hard): gate `is_playing()` 检查
- 数据定义 (Soft): 引用 `DeploymentCommand` 类型

**下游（依赖本系统的系统）**:

| 系统 | 类型 | 说明 |
|------|------|------|
| 出征系统 | Hard (被调用) | 提供玩家指令队列 |
| AI 敌人 | Hard (被调用) | 提供 AI 指令 |
| 战斗结算 | Hard (被调用) | 计算战斗结果 |
| 星球系统 | Hard (被调用) | 读写星球状态 |
| 占领系统 | Hard (被调用) | 战后所有权转移 |
| 生产系统 | Hard (被调用) | 回合收尾产兵 |
| 胜负条件 | Hard (被调用) | 检查游戏是否结束 |
| 国王系统 | Hard (被调用) | 消耗回合寿命 |
| 回合控制 UI | Hard (查询) | 显示回合数和按钮状态 |

全部为 Hard — 回合管理器是游戏循环的唯一驱动者。

## Tuning Knobs

无可调数值参数。回合逻辑是设计时决定的流程，不是运行时调整的数值。

## Visual/Audio Requirements

不适用 — 回合管理器无视觉或音频输出。其阶段事件触发战斗动画，但动画由战斗动画系统独立管理。

## UI Requirements

不适用 — 回合管理器无用户界面。回合控制 UI 独立订阅 EventBus 事件来显示回合数。

## Acceptance Criteria

- **GIVEN** `current_phase == DEPLOYMENT`，**WHEN** 调用 `end_turn()`，**THEN** 执行步骤 1-5 完整流程，`turn_number` 增加 1，`EventBus.turn_ended` 被 emit
- **GIVEN** `current_phase == EXECUTION`，**WHEN** 调用 `submit_command(cmd)`，**THEN** 返回 `false`
- **GIVEN** 玩家 1 条指令（A→B, 5人）+ AI 1 条指令（C→A, 3人），**WHEN** `end_turn()`，**THEN** 计算顺序不影响最终星球 garrison（交换两部指令顺序 → 相同结果）
- **GIVEN** 同一星出发 2 条指令总兵力 15、snapshot garrison=10，**WHEN** 步骤 3 执行，**THEN** 两条指令分别按 10/15 比例削减，削减后总和 ≤ 10
- **GIVEN** 空回合（无任何指令），**WHEN** `end_turn()`，**THEN** 正常执行，产兵照常，`turn_number` +1
- **GIVEN** 回合结算后 `check_victory() == true`，**WHEN** 步骤 5 调用，**THEN** `GameState.transition_to(VICTORY)` 被调用，下一 DEPLOYMENT 不进入
- **GIVEN** 事件序列，**WHEN** 一个完整回合，**THEN** `deployment_phase_started` → `execution_phase_started` → `turn_ended` → `deployment_phase_started` 严格按序 emit

## Open Questions

无 — MVP 范围完整覆盖。延后：
- AI 异步计算超时保护 → Core 层 AI 敌人系统设计时考虑
- 多回合动画并行（如前一回合动画未播完就进入下一回合）→ Presentation 层战斗动画系统设计时考虑
- 回合历史回放（replay）→ Production 阶段考虑
