# AI 敌人 (AI Enemy)

> **Status**: In Design
> **Author**: Claude + 老大
> **Last Updated**: 2026-05-31
> **Implements Pillar**: ♟️ 从容推演 (AI 是棋盘对面的对手)
> **Architecture**: [ADR-0007](../docs/architecture/adr/adr-0007-ai-decision-architecture.md), [ADR-0004](../docs/architecture/adr/adr-0004-turn-resolution-model.md) (步骤 1)

## Overview

AI 敌人模拟一个对手玩家——在每回合部署阶段，从己方星球发兵、攻击玩家和中立星球、防守受威胁的领土。AI 在回合结算步骤 1 被调用，其指令与玩家指令合并后统一结算。

MVP 只有一个 AI 对手（单势力 `Faction.ENEMY`），使用分阶段规则引擎（防御 → 进攻 → 冲突消解）。AI 强度通过 `aggression`、`defensiveness`、`intelligence` 三个参数调节。

## Player Fantasy

玩家不直接感知 AI 的内部运作，但感到"对面有一个认真的对手"——AI 会趁玩家倾巢而出时偷袭后方，会集中兵力攻打关键星球，会在劣势时收缩防守。胜利不是免费的——玩家必须比 AI 更聪明地分配兵力。

MVP AI 不会"碾压"也不会"放水"——它是诚实的对手，用和玩家一样的规则战斗。

## Detailed Rules

### 规则 1: AI 三阶段决策

`compute_turn()` 每回合在 TurnManager 步骤 1 被调用，返回 `Array[DeploymentCommand]`：

**Phase 1 — 防御评估**: 识别受威胁的己方星球，调兵增援
**Phase 2 — 进攻规划**: 评估所有可能的攻击目标，按价值排序
**Phase 3 — 冲突消解**: 确保同一出发星的总出兵 ≤ 驻兵

### 规则 2: 防御阶段

对于每颗 AI 拥有的星球：

1. 计算威胁等级：`threat_ratio = 敌邻星总驻兵 / (己方驻兵 + 1)`
2. `threat_ratio > 1.0` → 高威胁：寻找最近的、非受胁的己方星，调 min(缺额, 来源星富余) 的兵力支援
3. `threat_ratio 0.5-1.0` → 中威胁：保留现有驻兵，不从该星进攻
4. `threat_ratio < 0.5` → 低威胁：可从此星进攻

**防御保留**: 每颗星最少保留 `max(1, max_garrison × DEFENSE_RESERVE_RATIO)` 作为防守兵力。`DEFENSE_RESERVE_RATIO` 默认 0.3（= 保留 30% 上限）。

### 规则 3: 进攻阶段

对于每颗有富余兵力（`garrison - defense_min > 0`）的己方星：

1. 遍历所有相邻非 AI 星球
2. 对每个目标，尝试全部 3 种兵种（或仅根据 intelligence 选最佳克制）
3. 调用 `CombatSystem.resolve()` 预估战斗结果
4. 若 `estimate.attacker_wins` → 加入候选列表

**进攻价值评分**:
```
value = target.production_rate × 3.0       # 目标产量
      + target.garrison × 0.5              # 目标威胁
      + casualty_ratio × 2.0               # 战损效率
      + ATTR_VALUE[target.attribute]        # 属性价值 (RICH=4, FORTRESS=1)
      + target.adjacent_ids.size() × 0.5   # 战略位置
```

候选按 value 降序排序 → 贪心分配（源星有富余就发兵，否则跳过）。

### 规则 4: AI 参数

三个可调参数控制 AI 风格：

| 参数 | 范围 | 默认 | 效果 |
|------|------|------|------|
| `aggression` | 0.0–1.0 | 0.5 | 提高 → 进攻门槛降低，更少防守 |
| `defensiveness` | 0.0–1.0 | 0.5 | 提高 → 保留更多防守兵力 |
| `intelligence` | 0.0–1.0 | 0.5 | 提高 → 倾向选择克制兵种；降低 → 随机兵种 |

MVP 使用默认值（全 0.5）。后续关卡可逐关调高。

### 规则 5: 兵种选择

```gdscript
func _select_attack_type(target: Dictionary) -> DataDef.UnitType:
    if randf() < intelligence:
        # 智能：选择克制目标驻兵类型的兵种
        var defender_type = _guess_defender_type(target)
        return DataDef.get_counter(defender_type)
    else:
        # 低智能：随机选
        return _random_unit_type()
```

MVP 所有玩家兵种为 INFANTRY，因此 AI 用 `intelligence=0.5` 时有一半概率选骑兵（克步兵）。

### 规则 6: AI 不使用国王系统

AI 无国王概念——不受寿命约束，无代际传承。这是设计意图：国王系统是玩家的独特机制（Pillar 1），AI 是"无限迭代的对手"，形成非对称对比。

### States and Transitions

```
TurnManager 步骤 1 (收集指令):
  → AIEnemy.compute_turn()
    → Phase 1: _defense_phase()
        → for each AI planet: assess threat
        → if HIGH threat: find reinforcement
        → commands += reinforcement_cmds
    → Phase 2: _offense_phase(existing_commands)
        → for each AI planet with spare:
            → evaluate all adjacent targets
            → estimate battle outcome
            → if win → add to candidates
        → candidates.sort(by value desc)
        → greedy assign
        → commands += offense_cmds
    → Phase 3: _resolve_overdraft(commands)
    → return commands
```

### Interactions with Other Systems

| 调用方/被调用方 | 操作 |
|----------------|------|
| 回合管理器 | 在步骤 1 调用 `compute_turn()` |
| 星球系统 | `get_planets_by_owner()`, `get_adjacent_planets()`, `get_planet()` |
| 战斗结算 | `resolve()` 预估战斗结果 |
| 数据定义 | `UnitType`, `DAMAGE_MATRIX` |
| 出征系统 | 生成 `DeploymentCommand` |

## Formulas

### 威胁评估

```
threat_ratio = Σ(adj_enemy_garrison_i) / (planet.garrison + 1)

威胁等级:
  ratio > 1.0  → HIGH
  ratio 0.5-1.0 → MEDIUM
  ratio < 0.5  → LOW
```

### 防守安全阈值

```
defense_min = max(1, planet.max_garrison × DEFENSE_RESERVE_RATIO)
```

### 进攻价值

```
value = production × 3.0 + enemy_garrison × 0.5 + efficiency × 2.0
      + attr_bonus + connections × 0.5
```

其中 `attr_bonus`: RICH=4, NORMAL=2, FORTRESS=1, BARREN=0
`efficiency`: `attacker_survived / total_attacker_count`

## Edge Cases

- **AI 全部星球 garrison=0**: `compute_turn()` 返回空列表 —— AI 无力行动
- **AI 无相邻敌星（全部隔离或已消灭玩家）**: 返回空列表 —— AI 不行动
- **进攻候选排序相同时**: 保持原序（稳定排序），通常由遍历顺序决定
- **预估战斗结果和实际不一致**: AI 预估时使用的 garrison 是与玩家部署后、回合结算前的实时值。若玩家在 AI 预估后才发兵（但在同一回合），AI 不会重算。这是设计意图：AI 看到的是"它自己那刻的画面"，和真实战争一样有"情报延迟"
- **多个进攻候选竞争同一源星兵力**: 贪心算法按 value 排序依次分配，高价值目标先得兵。低价值目标可能因为兵力不足被跳过

## Dependencies

**上游（本系统依赖）**:
| 系统 | 依赖内容 |
|------|---------|
| 星球系统 | `get_planets_by_owner()`, `get_adjacent_planets()`, `get_planet()` |
| 战斗结算 | `resolve()` |
| 数据定义 | `UnitType`, `DAMAGE_MATRIX`, `Faction` |
| 出征系统 | `DeploymentCommand` 结构 |

**下游（依赖本系统的系统）**:
| 系统 | 依赖类型 | 依赖内容 |
|------|---------|---------|
| 回合管理器 | Hard | `compute_turn()` |

## Tuning Knobs

| Knob | 位置 | 安全范围 | 过高后果 | 过低后果 |
|------|------|---------|---------|---------|
| `aggression` | AIEnemy | 0.0–1.0 | AI 倾巢而出，后方空虚 | AI 永远不打 |
| `defensiveness` | AIEnemy | 0.0–1.0 | AI 龟缩，游戏无挑战 | AI 裸星无防 |
| `intelligence` | AIEnemy | 0.0–1.0 | AI 永远选最优克制 | AI 随机兵，无策略感 |
| `DEFENSE_RESERVE_RATIO` | AIEnemy | 0.1–0.5 | 见 defensiveness | 见 defensiveness |
| 进攻价值权重 | AIEnemy | — | 影响 AI 目标选择优先级 | — |

## Acceptance Criteria

- **GIVEN** AI 拥有 3 颗星球（garrison=10, 8, 5），邻近 2 颗玩家星（garrison=4, 6），**WHEN** `compute_turn()`，**THEN** 返回非空指令列表
- **GIVEN** AI 全部星球 garrison=0，**WHEN** `compute_turn()`，**THEN** 返回空列表
- **GIVEN** `intelligence=1.0`，**WHEN** AI 攻击 INFANTRY 驻兵星，**THEN** 选 CAVALRY（克步兵）
- **GIVEN** AI 某颗星的驻兵 = `defense_min`，**WHEN** 该星在受 HIGH 威胁时，**THEN** 不从该星发起进攻
- **GIVEN** 同一出发星被分配 2 条进攻指令，总出兵 = 驻兵，**WHEN** `compute_turn()` 完成，**THEN** sum(count) <= garrison
- **GIVEN** 固定的星球状态 + `intelligence=1.0`，**WHEN** 两次 `compute_turn()`，**THEN** 返回完全相同的指令列表（确定性验证）
- **单元测试**: 给定固定星球状态 → AI 输出固定指令；防御阶段独立测试；进攻排序独立测试
