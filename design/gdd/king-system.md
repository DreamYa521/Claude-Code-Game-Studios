# 国王系统 (King System)

> **Status**: In Design
> **Author**: Claude + 老大
> **Last Updated**: 2026-05-31
> **Implements Pillar**: 🕯️ 代际接力, ⚖️ 抉择之重
> **Architecture**: [ADR-0008](../docs/architecture/adr/adr-0008-king-lifespan-model.md)

## Overview

国王系统是星辰之轭的核心 hook——每位国王有有限的寿命（行动次数），玩家每回合消耗 1 次。寿命耗尽时国王去世，继承人自动继位，代际计数递增。MVP 阶段国王天赋仅为标签（不影响机制），但数据结构已预留扩展。

国王系统让每一回合成为不可回收的资源——"我还有 8 回合，够不够打下这个星系？" 这是 Pillar 1（代际接力）和 Pillar 3（抉择之重）的数值基础。

## Player Fantasy

玩家看到国王 UI 显示"第 1 代：征服者 阿尔萨斯，剩余 12 回合"。每点一次"结束回合"，数字减少 1。当它降到 3 时 UI 开始警告"国王年事已高"。降到 0 时，国王去世——游戏暂停——"第 1 代国王驾崩，享年 30 回合。继承人 伊莎贝尔 继位。" 代际计数变为 2，倒计时重置。

玩家会记住"第三任国王那个天才少年可惜 25 回合就病死了"，这是 Pillar 4（自创史诗）的实现。

## Detailed Rules

### 规则 1: KingData 结构

```gdscript
class KingData:
    var name: String              # 国王名字
    var talent: TalentType        # 天赋类型（MVP 标签）
    var lifespan: int             # 初始寿命 = KING_DEFAULT_LIFESPAN (30)
    var actions_used: int         # 已消耗回合数
    var age: int                  # = actions_used
    var generation: int           # 第几代
    var talent_bonus: Dictionary  # MVP 空，Vertical Slice 填入效果
```

### 规则 2: 寿命消耗

`consume_turn()` 由 `TurnManager` 在 CLEANUP 阶段（步骤 5）调用：
- `actions_used += 1`
- 广播 `EventBus.action_consumed.emit(actions_remaining())`
- 若 `actions_used >= lifespan` → 触发国王去世

**MVP 简化**: 每回合固定消耗 1，无论是否出兵。这让寿命成为"回合倒计时"而非"出兵惩罚"。

### 规则 3: 国王去世

`_on_king_death()`:
1. 广播 `EventBus.king_died.emit(current_king)`
2. `GameState.transition_to(PAUSED)` — 暂停游戏
3. （留给 UI 展示"国王驾崩"信息）
4. 调用 `_generate_heir(previous_king)`
5. 广播 `EventBus.king_succeeded.emit(old, new)`
6. `GameState.transition_to(PLAYING)` — 恢复游戏

MVP 不做演出动画——国王 UI 显示文字信息，玩家点击"继续"后恢复。

### 规则 4: 自动继位

`_generate_heir(previous)`:
- 从名字池随机抽取新名字
- 从 `TalentType` 随机选天赋（MVP 无效果）
- `lifespan = KING_DEFAULT_LIFESPAN`（固定 30，不继承）
- `generation = previous.generation + 1`
- `actions_used = 0`

MVP 玩家无法选择继承人——自动生成。

### 规则 5: 初始国王

`init_king()` 在游戏开始时调用（`init_from_level` 之后）:
- 随机名字 + 随机天赋
- `generation = 1`, `lifespan = 30`
- 广播 `EventBus.king_succeeded.emit(null, king)` — null old_king 表示初始

### 规则 6: 天赋类型（MVP 标签）

| 天赋 | MVP 效果 | Vertical Slice 扩展 |
|------|---------|-------------------|
| CONQUEROR | 无 | 战斗伤害 +10% |
| RESEARCHER | 无 | 科技积累 +1/回合 |
| HOARDER | 无 | 产量 +20% |
| DIPLOMAT | 无 | 中立星归附概率 |

`talent_bonus` Dictionary 留空（`{}`），Vertical Slice 填充为 `{"combat_damage": 0.10}` 等。

### 规则 7: 去世警告

当 `actions_remaining() <= 3` 时，UI 显示警告"国王年事已高"。纯 UI 功能，不影响机制。

### States and Transitions

```
游戏初始化:
  KingSystem.init_king()
    → random name + talent
    → generation = 1
    → EventBus.king_succeeded(null, king)

每回合 CLEANUP:
  TurnManager._cleanup()
    → KingSystem.consume_turn()
      → actions_used += 1
      → EventBus.action_consumed(remaining)
      → if remaining == 0:
          → EventBus.king_died(old)
          → GameState → PAUSED
          → KingSystem._generate_heir(old)
          → EventBus.king_succeeded(old, new)
          → GameState → PLAYING
```

### Interactions with Other Systems

| 调用方/被调用方 | 操作 |
|----------------|------|
| 回合管理器 | 调用 `consume_turn()` |
| GameState | `transition_to(PAUSED/PLAYING)` |
| 事件总线 | 发送 `king_died`, `king_succeeded`, `action_consumed` |
| 国王 UI | 读取 `current_king` 全部字段 |
| 数据定义 | 读取 `TalentType`, `KING_DEFAULT_LIFESPAN` |

## Formulas

### 剩余行动次数

```
actions_remaining() = lifespan - actions_used
```

### 代际年龄

```
age = actions_used  （国王从 0 开始，每个回合 +1）
```

## Edge Cases

- **初始国王 lifespan=0**: 不应发生（`KING_DEFAULT_LIFESPAN >= 1`），但若配置错误 → `init_king()` 后立即 `is_alive() == false` → 立即继位
- **连续快速去世**: 若 lifespan 被配为 1 → 每回合去世一次。这会导致游戏陷入去世-继位循环。缓解：`KING_DEFAULT_LIFESPAN` 最小值至少为 5
- **名字池耗尽**: MVP 有 20 个名字，最多 20 代。若玩家打到 20+ 代 → 名字重复使用（附加记号如"阿尔萨斯二世"）。MVP 20 代远超预期（30×20=600 回合），暂不处理
- **回合管理器未初始化时调用 consume_turn()**: 防御性检查 `current_king != null`，若空则跳过
- **PAUSED 状态下不应调用 consume_turn()**: TurnManager 只在 PLAYING 状态执行结算，不触发消耗

## Dependencies

**上游（本系统依赖）**:
| 系统 | 依赖内容 |
|------|---------|
| 数据定义 | `TalentType` 枚举, `KING_DEFAULT_LIFESPAN` 常量 |
| 事件总线 | `king_died`, `king_succeeded`, `action_consumed` 信号 |
| GameState | `transition_to(PAUSED)`, `transition_to(PLAYING)` |

**下游（依赖本系统的系统）**:
| 系统 | 依赖类型 | 依赖内容 |
|------|---------|---------|
| 回合管理器 | Hard | `consume_turn()` |
| 国王 UI | Hard | `current_king` 数据 |
| 胜负条件 | Soft | （未来可能因国王去世触发特殊结局） |

## Tuning Knobs

| Knob | 位置 | 安全范围 | 过高后果 | 过低后果 |
|------|------|---------|---------|---------|
| `KING_DEFAULT_LIFESPAN` | DataDef | 10 – 60 | 寿命太长，代际概念无感知 | 频繁去世，玩家被节奏打断 |
| 去世警告阈值 (当前 3) | KingSystem | 2 – 8 | — | — |

## Acceptance Criteria

- **GIVEN** 游戏启动，**WHEN** `init_king()` 完成，**THEN** `current_king != null`, `generation == 1`, `actions_remaining() == 30`
- **GIVEN** `consume_turn()` 调用 1 次，**WHEN** 完成，**THEN** `actions_remaining()` 减少 1
- **GIVEN** `consume_turn()` 调用 30 次，**WHEN** 完成，**THEN** `is_alive() == false`，`EventBus.king_died` 被 emit
- **GIVEN** 国王去世，**WHEN** `_generate_heir()` 完成，**THEN** `generation == 2`, `actions_remaining() == 30`
- **GIVEN** 继位完成，**WHEN** 检查 EventBus，**THEN** `king_succeeded` 在 `king_died` 之后被 emit
- **GIVEN** `actions_remaining() == 3`，**WHEN** UI 检查，**THEN** 显示警告状态
- **单元测试**: init → consume × 30 → death → heir → consume × 30 → death → 验证 generation=3
