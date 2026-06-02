# ADR-0008: 国王寿命模型

## Status
Accepted

## Date
2026-05-31

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core (国王系统) |
| **Knowledge Risk** | LOW — 纯 GDScript 数据模型，Resource 序列化无破坏性变更 |
| **References Consulted** | `docs/architecture/architecture.md` Phase 3 场景 4, ADR-0001 (EventBus 通知), ADR-0002 (DataDef 常量) |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | None |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (king_died / action_consumed 信号), ADR-0002 (TalentType 枚举, KING_DEFAULT_LIFESPAN) |
| **Enables** | 国王系统 GDD, 国王 UI GDD |
| **Blocks** | 国王系统 GDD, 国王 UI GDD |
| **Ordering Note** | Core 层最后一个 ADR，与其他 Core 系统无技术依赖。可与 ADR-0005/0006/0007 并行编写 |

## Context

### Problem Statement

星辰之轭的核心 hook 是"国王代际系统"——每个国王有生之年能做的事极其有限，玩家必须在征服、研发、囤积之间选择。国王去世后，继承人继位，未竟的事业交给下一代。

需要决定：国王寿命如何度量？消耗模型如何设计？去世/继位流程如何处理？

### Constraints

- MVP 只有一个国王类型，天赋标签存在但不影响机制
- 游戏是回合制——国王寿命的消耗应该在"玩家做决策"时触发
- 国王去世是自然的停止点（session-level loop），不应打断游戏流程
- 去世/继位后的过渡必须清晰但简洁（MVP 不做演出动画）
- 必须可扩展到多种天赋类型（Vertical Slice）

### Requirements

- 国王有一个有限的"行动次数"上限（lifespan），每次出兵消耗 1 次
- 行动次数耗尽时国王去世，触发继位
- 去世/继位通过 EventBus 广播
- MVP 新国王自动生成（随机名字+固定 stats），不需要玩家选择
- 代际计数累加

## Decision

**使用基于行动次数的寿命模型（Action-Based Lifespan）。国王 lifespan 递减由回合管理器在收尾阶段触发（每次 `end_turn()` 消耗 1），国王去世时暂停游戏、自动继位、广播通知。**

### 寿命模型

```
KingData:
  name: String            # 国王名字
  talent: TalentType      # 天赋类型（MVP 标签，不影响机制）
  lifespan: int           # 初始行动次数（默认 30）
  actions_used: int       # 已消耗行动次数
  age: int                # 代际内年龄（= actions_used）
  generation: int         # 第几代国王
  talent_bonus: Dictionary # 天赋效果（MVP 空，Vertical Slice 启用）

actions_remaining = lifespan - actions_used
```

**消耗规则**:
- 玩家每次点击"结束回合"，`actions_used += 1`（无论该回合是否有出兵）
- `actions_remaining == 0` → 国王在下回合开始前去世
- MVP 只有"结束回合"消耗寿命——出兵不额外消耗（简化）

**为什么是"每回合消耗 1"而不是"每次出兵消耗 1"？**

- 出兵次数不可预测——如果玩家一回合出 5 路兵，寿命消耗与不出兵时差异太大，导致玩家惩罚性规避出兵
- "每回合 1 次"给玩家一个清晰的倒计时——"我还有 N 回合，必须在这之前拿下那个要塞"
- 结合 Pillar 3（抉择之重）——每回合都是一个不可回收的资源，思考"这回合做什么"本身就是重量

### 关键接口

```gdscript
# king_system.gd — autoload: KingSystem
extends Node

var current_king: KingData:
    get

func init_king(name: String = "", talent: DataDef.TalentType = DataDef.TalentType.CONQUEROR) -> void:
    # 游戏开始时创建初始国王
    # name 为空则从名字池随机抽取
    var king = KingData.new()
    king.name = name if name else _random_name()
    king.talent = talent
    king.lifespan = DataDef.KING_DEFAULT_LIFESPAN
    king.generation = 1
    current_king = king
    EventBus.king_succeeded.emit(null, king)  # null old_king = 初始国王

func consume_turn() -> void:
    # TurnManager 在 CLEANUP 阶段调用
    if not is_alive():
        return
    current_king.actions_used += 1
    current_king.age += 1
    EventBus.action_consumed.emit(actions_remaining())
    if not is_alive():
        _on_king_death()

func is_alive() -> bool:
    return current_king and current_king.actions_used < current_king.lifespan

func actions_remaining() -> int:
    return current_king.lifespan - current_king.actions_used if current_king else 0

func _on_king_death() -> void:
    var old = current_king
    EventBus.king_died.emit(old)
    _generate_heir(old)

func _generate_heir(previous: KingData) -> void:
    var heir = KingData.new()
    heir.name = _random_name()
    heir.talent = _random_talent()  # MVP 随机选，Vertical Slice 可选
    heir.lifespan = DataDef.KING_DEFAULT_LIFESPAN
    heir.generation = previous.generation + 1
    current_king = heir
    EventBus.king_succeeded.emit(previous, heir)
```

### 名字池

```gdscript
const MALE_NAMES = [
    "阿尔萨斯", "凯恩", "达里安", "伊耿", "罗德里克",
    "塞巴斯蒂安", "维克托", "亚历山大", "雷欧", "马克西姆",
]
const FEMALE_NAMES = [
    "艾琳娜", "伊莎贝尔", "莉安娜", "维多利亚", "凯瑟琳",
    "塞琳娜", "安娜斯塔西娅", "奥莉维亚", "索菲亚", "埃莉诺",
]
```

MVP 随机从两个池中抽一个（不区分性别逻辑），后续可加家族名、称号等。

### 去世/继位流程时序

```
TurnManager._cleanup():          # 步骤 5
  KingSystem.consume_turn()       # 消耗 1 回合寿命
    if actions_remaining == 0:
      EventBus.king_died.emit(old)
      GameState.transition_to(PAUSED)  # 暂停游戏
      # 国王 UI 展示"国王去世"信息
      # 玩家点击"继续"或自动延迟 3 秒:
      KingSystem._generate_heir(old)
      EventBus.king_succeeded.emit(old, new)
      GameState.transition_to(PLAYING)  # 恢复游戏
```

MVP 不做演出动画——国王 UI 显示文字"第 N 代国王 [名字] 驾崩，享年 N 回合。继承人 [新名字] 继位。"，玩家点击确认后继续。

### 天赋类型（MVP 仅标签）

```gdscript
enum TalentType { CONQUEROR, RESEARCHER, HOARDER, DIPLOMAT }
```

| 天赋 | MVP 效果 | Vertical Slice 扩展 |
|------|---------|-------------------|
| CONQUEROR | 无（标签） | 战斗伤害 +10% |
| RESEARCHER | 无（标签） | 科技积累 +1/回合 |
| HOARDER | 无（标签） | 产量 +20% |
| DIPLOMAT | 无（标签） | 中立星归附概率 |

MVP 天赋不影响游戏机制——它只是 UI 上的一个标签，告诉玩家"这一代国王的出身"。天赋效果在 Vertical Slice 阶段作为 `talent_bonus` Dictionary 注入，`KingData` 结构已预留该字段。

### 代际计数与显示

```gdscript
func get_dynasty_summary() -> String:
    # 用于"先王汇报"（Full Vision）
    return "第 %d 代：%s (%s)，执政 %d 回合" % [
        current_king.generation,
        current_king.name,
        TALENT_LABELS[current_king.talent],
        current_king.actions_used,
    ]
```

## Alternatives Considered

### Alternative 1: 基于年龄的寿命模型（Age-Based）

- **Description**: 国王有年龄（每回合 +1），寿命上限固定（如 60 岁），死亡不可预测（随机波动 ±10）
- **Pros**: 更"真实"——没人知道自己什么时候死；可以加入"病逝"等叙事事件
- **Cons**: 不可预测 = 玩家无法规划——"我算好了 5 回合后打下来，结果国王提前死了"；随机性违背 Pillar 2（从容推演）；调试困难
- **Rejection Reason**: 星辰之轭是下棋不是模拟人生。玩家需要能看着倒计时做决策。确定性寿命 = 确定性策略。

### Alternative 2: 每次出兵消耗 1 寿命（Deploy-Based）

- **Description**: 国王 lifespan 仅在玩家发兵时消耗，结束回合不消耗
- **Pros**: "每个行动都有代价"最直白的体现；玩家会仔细权衡每次出兵
- **Cons**: 惩罚性太强——不出兵就不会死，玩家可能消极游戏；一回合多次出兵导致寿命消耗不可预测
- **Rejection Reason**: 与"每回合结束消耗 1"相比，deploy-based 把寿命消耗绑定到"出兵频次"而非"回合推进"。玩家可能为了省寿命而不发兵——但这违背核心循环"点选发兵占点"。

### Alternative 3: 混合模型（Hybrid — 回合 + 行动消耗）

- **Description**: 每回合固定消耗 1，每次出兵额外消耗 1
- **Pros**: "时间流逝" + "决策代价"两层约束
- **Cons**: 双消耗模型导致寿命结束更快；玩家困惑"为什么我寿命掉这么快"
- **Rejection Reason**: MVP 数值未经测试，双消耗可能让寿命过快耗尽。单消耗已足够传递"抉择之重"。可日后调优加入。

## Consequences

### Positive

- **可预测**: 玩家始终能看到 `actions_remaining`，能规划"我还有 8 回合，够不够打下那个要塞？"
- **节奏控制**: lifespan = 30 意味着大约 30 回合一代国王。结合 MVP 10 颗星的规模，一代国王足够打完一个关卡
- **自然停止点**: 国王去世时游戏暂停——这是 session-level loop 的天然断点。"这代结束了，下次继续"或"再来一代"
- **可扩展**: `KingData` 已预留 `talent_bonus` Dictionary，Vertical Slice 添加天赋效果不需要改数据模型

### Negative

- **国王去世可能打断战斗节奏**: 玩家正在乘胜追击，国王突然去世。缓解：去世前 3 回合 UI 显示警告"国王年事已高"（`actions_remaining <= 3`）
- **每回合消耗让"观察回合"也有成本**: 玩家不想出兵只想看 AI 怎么走，也消耗寿命。缓解：这是设计意图——"什么都不做"也是一种决策，同样消耗时间。
- **天赋在 MVP 无效果**: 玩家看到"征服者"标签但感受不到差异。缓解：UI 上明确 MVP 是"标签模式"；天赋效果是 Vertical Slice 的核心 feature。

### Risks

- **lifespan=30 可能太长或太短**: 未经实际测试。缓解：`KING_DEFAULT_LIFESPAN` 在 DataDef 中，可即时调整。
- **继位后玩家可能失去节奏**: "新国王在哪？我现在该干什么？"。缓解：继位后立即恢复 PLAYING 状态 + UI 刷新，无缝继续。

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| 国王系统 | 国王寿命有限，行动消耗 | Action-based lifespan，每回合消耗 1 |
| 国王系统 | 代际传承 | `_generate_heir()` 自动继位，generation 递增 |
| 国王系统 | 天赋类型（MVP 标签） | `TalentType` 枚举预留，`talent_bonus` 字段预留 |
| 回合管理器 | CLEANUP 阶段触发寿命消耗 | `consume_turn()` 在步骤 5 调用 |
| 国王 UI | 显示名字、天赋、剩余次数 | `current_king` 暴露全部字段 |

## Performance Implications

- **CPU**: 不可测量 — 字段更新 + 条件检查
- **Memory**: `KingData` Resource ≈ 100 bytes, 名字池 ≈ 500 bytes
- **Load Time**: 无
- **Network**: 不适用

## Migration Plan

不适用 — 新项目。扩展路径：
- Vertical Slice: 填充 `talent_bonus`，多种国王类型
- Alpha: 添加先王历史列表（`Array[KingData]`），支持"先王墓地"查询
- Full Vision: Part 1 的主角血脉信息传入 Part 2，初始国王继承 Part 1 结局

## Validation Criteria

- `init_king()` 后 `current_king != null`, `actions_remaining() == KING_DEFAULT_LIFESPAN`
- `consume_turn()` 一次后 `actions_remaining()` 减少 1
- `consume_turn()` 连续 KING_DEFAULT_LIFESPAN 次后 `is_alive() == false`
- 国王去世时 `EventBus.king_died` 和 `EventBus.king_succeeded` 按顺序 emit
- 继位后 `current_king.generation` 递增 1，`actions_remaining()` 重置为 KING_DEFAULT_LIFESPAN
- `old_king`（king_died payload）的 `actions_used == lifespan`
- 单元测试：模拟完整生命周期（init → consume × N → death → heir → consume × N → death）

## Related Decisions

- ADR-0001: 事件总线 — `king_died`, `king_succeeded`, `action_consumed` 信号
- ADR-0002: 数据定义 — `TalentType` 枚举, `KING_DEFAULT_LIFESPAN` 常量
- ADR-0003: GameState — 去世时 `transition_to(PAUSED)`, 继位后 `transition_to(PLAYING)`
- ADR-0004: 回合结算模型 — `consume_turn()` 在 CLEANUP 步骤 5 调用
- `docs/architecture/architecture.md` — Module Ownership: 国王系统, Phase 3 场景 4
