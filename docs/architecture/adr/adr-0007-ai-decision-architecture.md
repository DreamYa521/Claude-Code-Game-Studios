# ADR-0007: AI 决策架构

## Status
Accepted

## Date
2026-05-31

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core (AI 敌人) |
| **Knowledge Risk** | LOW — 纯 GDScript 逻辑，无引擎 API 依赖 |
| **References Consulted** | `docs/architecture/architecture.md` Phase 3 场景 3, ADR-0004 (快照模型), ADR-0005 (星球查询 API), ADR-0006 (resolve() 预估战斗) |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | None |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0004 (AI `compute_turn()` 在回合结算步骤 1 调用), ADR-0005 (通过 PlanetSystem API 读取星球状态), ADR-0006 (调用 `resolve()` 预估战斗结果) |
| **Enables** | AI 敌人 GDD |
| **Blocks** | AI 敌人 GDD |
| **Ordering Note** | Core 层最后一个 ADR — AI 依赖所有其他 Core 系统的接口 |

## Context

### Problem Statement

AI 敌人需要在每个回合的部署阶段，模拟"玩家"做决策——从哪些星球出兵、打哪个目标、出多少兵。AI 的行为质量直接决定游戏的可玩性：太弱让征服无趣，太强让玩家挫败。

MVP 只需要一个 AI 敌人（单势力），决策空间有限（10 颗星、20 条连接）。

需要决定：AI 的决策架构——怎么从"当前星图状态"推导出"一组出兵指令"。

### Constraints

- AI 在回合结算**步骤 1**被调用，与玩家指令合并（ADR-0004）
- AI 读取快照前的实时星球状态做决策（AI 看到的是玩家刚部署完的真实状态）
- MVP 单 AI 对手，难度不分区，参数化控制强度
- AI 不能"作弊"——不读取玩家未提交的指令、不修改自己的兵力
- 决策必须在回合粒度下完成（< 100ms，不需要每帧运行）

### Requirements

- AI 每回合生成 `Array[DeploymentCommand]`
- 决策逻辑：防守优先（保护己方薄弱星球），再进攻
- AI 不会派超出驻兵的兵力（像玩家一样受兵力约束）
- AI 不会同时从同一星球发兵导致兵力超限（使用 ADR-0004 的 overdraft 安全网）
- AI 强度可通过参数调节（为后续难度曲线留接口）

## Decision

**使用分阶段规则引擎（Phased Rule Engine）。AI 决策分为两个阶段：防御 → 进攻。每个阶段用贪心规则生成指令，最后冲突消解。**

### 架构概览

```
AI.compute_turn() → Array[DeploymentCommand]

Phase 1: 防御评估
  for each AI-owned planet:
    if 相邻有敌方星球且有驻兵 → 评估威胁
    if 当前驻兵 < 安全阈值 → 从最近的非受胁星球调兵支援

Phase 2: 进攻规划
  for each AI-owned planet with spare garrison:
    for each adjacent non-AI planet:
      预估战斗结果 (调用 CombatSystem.resolve)
      计算进攻价值
      若预估胜率高 → 加入候选列表
  
  候选列表按价值排序 → 贪心分配兵力

Phase 3: 冲突消解
  同一出发星的多条进攻指令若总和 > 驻兵:
    按优先级排序，低优先级指令被削减或取消
    (由 ADR-0004 _resolve_overdraft() 做最终安全网)
```

### 防御阶段 (Phase 1)

```gdscript
func _defense_phase() -> Array[DeploymentCommand]:
    var commands: Array[DeploymentCommand] = []
    var my_planets = PlanetSystem.get_planets_by_owner(DataDef.Faction.ENEMY)
    
    for planet in my_planets:
        var threat = _assess_threat(planet)
        if threat.level >= THREAT_HIGH:
            var reinforcement = _find_reinforcement(planet, threat, my_planets)
            if reinforcement:
                commands.append(reinforcement)
    
    return commands

func _assess_threat(planet: Dictionary) -> ThreatAssessment:
    var adjacent_ids = PlanetSystem.get_adjacent_planets(planet.id)
    var total_enemy_nearby = 0
    for adj_id in adjacent_ids:
        var adj = PlanetSystem.get_planet(adj_id)
        if adj.owner != DataDef.Faction.ENEMY and adj.garrison > 0:
            total_enemy_nearby += adj.garrison
    
    var threat_level = total_enemy_nearby / float(planet.garrison + 1)
    # 威胁等级：敌邻兵 / (己驻兵 + 1)
    # > 1.0: HIGH (敌多我少)
    # 0.5-1.0: MEDIUM
    # < 0.5: LOW
    return ThreatAssessment.new(threat_level)
```

**防御兵力安全阈值**:
```
defense_min = max(1, planet.max_garrison × DEFENSE_RESERVE_RATIO)
// DEFENSE_RESERVE_RATIO = 0.3 — 至少保留 30% 上限驻守
```

若 `planet.garrison < defense_min`，且存在受威胁的邻星，AI 从非受胁的后方星球调兵支援。支援量 = `min(defense_min - garrison, source_planet.garrison - source_defense_min)`。

### 进攻阶段 (Phase 2)

```gdscript
func _offense_phase(existing_commands: Array[DeploymentCommand]) -> Array[DeploymentCommand]:
    var candidates: Array[AttackCandidate] = []
    var my_planets = PlanetSystem.get_planets_by_owner(DataDef.Faction.ENEMY)
    
    # 先扣除已分配的防御兵力
    var available_garrison = _calculate_available(my_planets, existing_commands)
    
    for planet in my_planets:
        var spare = available_garrison[planet.id]
        if spare < OFFENSE_MIN_GARRISON:  # 至少保留一些兵才进攻
            continue
        
        for adj_id in PlanetSystem.get_adjacent_planets(planet.id):
            var target = PlanetSystem.get_planet(adj_id)
            if target.owner == DataDef.Faction.ENEMY:
                continue  # 不攻击己方
            
            # 预估战斗
            for unit_type in [DataDef.UnitType.INFANTRY, DataDef.UnitType.ARCHER, DataDef.UnitType.CAVALRY]:
                var estimate = CombatSystem.resolve(
                    spare, unit_type,
                    target.garrison, _best_defender_type(target),
                    target.attribute,
                )
                if estimate.attacker_wins:
                    var value = _score_attack(planet, target, estimate, unit_type)
                    candidates.append(AttackCandidate.new(planet.id, target.id, spare, unit_type, value, estimate))
    
    # 按价值排序 → 贪心分配
    candidates.sort_custom(func(a, b): return a.value > b.value)
    
    var commands: Array[DeploymentCommand] = []
    var committed: Dictionary = {}  # {source_id: total_deployed}
    
    for c in candidates:
        var remaining = available_garrison[c.source_id] - committed.get(c.source_id, 0)
        if remaining < OFFENSE_MIN_GARRISON:
            continue
        var deploy_count = min(remaining, c.count)
        commands.append(DeploymentCommand.new(c.source_id, c.target_id, deploy_count, c.unit_type))
        committed[c.source_id] = committed.get(c.source_id, 0) + deploy_count
    
    return commands
```

### 进攻价值评分

```gdscript
func _score_attack(
    source: Dictionary, target: Dictionary,
    estimate: BattleResult, unit_type: DataDef.UnitType,
) -> float:
    var value = 0.0
    
    # 因子 1: 目标价值 — 产量越高的星球越值得打
    value += target.production_rate * PRODUCTION_WEIGHT  # 默认 3.0
    
    # 因子 2: 目标威胁 — 敌兵多的优先清掉
    value += target.garrison * THREAT_WEIGHT  # 默认 0.5
    
    # 因子 3: 战损比 — 我损失越少越好
    var casualty_ratio = float(estimate.attacker_survived) / max(1, c.source_garrison)
    value += casualty_ratio * EFFICIENCY_WEIGHT  # 默认 2.0
    
    # 因子 4: 属性加成 — 优先攻 RICH > NORMAL > FORTRESS > BARREN
    value += ATTR_VALUE[target.attribute]  # RICH=4, NORMAL=2, FORTRESS=1, BARREN=0
    
    # 因子 5: 战略位置 — 连接数多的星球控制价值高
    value += PlanetSystem.get_adjacent_planets(target.id).size() * POSITION_WEIGHT  # 默认 0.5
    
    return value
```

### AI 难度参数化

所有带 `WEIGHT` 后缀的系数定义为 AI 系统的导出变量，可从关卡配置覆盖：

```gdscript
# ai_enemy.gd — autoload: AIEnemy
extends Node

# 进攻性 — 越高越倾向进攻（影响 OFFENSE_MIN_GARRISON 和进攻权重）
@export var aggression: float = 0.5  # [0.0, 1.0]

# 防御性 — 越高越倾向保留防守兵力
@export var defensiveness: float = 0.5  # [0.0, 1.0]

# 智能度 — 越高越倾向选择克制兵种（低智能时随机选兵种）
@export var intelligence: float = 0.5  # [0.0, 1.0]

# 实际使用的阈值从参数计算
func _get_offense_min_garrison() -> int:
    return int(lerp(5.0, 1.0, aggression))  # 激进时只需 1 兵就进攻

func _get_defense_reserve_ratio() -> float:
    return lerp(0.1, 0.5, defensiveness)  # 保守时保留 50% 防守

func _select_attack_type(target: Dictionary) -> DataDef.UnitType:
    if randf() < intelligence:
        return _best_counter_type(target)  # 智能选克制
    else:
        return _random_unit_type()  # 随机（模拟低智能）
```

MVP 使用默认值（全 0.5），后续关卡可逐关调高。这些参数定义了 AI 的"个性"，也是难度曲线的唯一入口。

### 关键接口

```gdscript
# ai_enemy.gd — autoload: AIEnemy
extends Node

func compute_turn() -> Array[DeploymentCommand]:
    # 由 TurnManager 在步骤 1 调用
    # 返回 AI 本回合的全部出兵指令
    # 纯逻辑 — 不修改星球状态

class ThreatAssessment:
    var level: int  # 0=LOW, 1=MEDIUM, 2=HIGH
    var nearby_enemy_count: int
    var ratio: float

class AttackCandidate:
    var source_id: int
    var target_id: int
    var count: int
    var unit_type: DataDef.UnitType
    var value: float
    var estimate: BattleResult
```

### 决策流程图

```
compute_turn()
  │
  ├─ Phase 1: 防御
  │   for each AI planet:
  │     threat = assess_threat(planet)
  │     if threat >= HIGH and garrison < defense_min:
  │       reinforce from nearest safe planet
  │
  ├─ Phase 2: 进攻
  │   for each AI planet with spare garrison:
  │     for each adjacent non-AI planet:
  │       for each unit_type (filtered by intelligence):
  │         estimate = CombatSystem.resolve(...)
  │         if estimate.attacker_wins:
  │           candidates.append(...)
  │   candidates.sort(by value desc)
  │   greedy assign: for each candidate,
  │     if source still has spare → deploy
  │
  └─ return all commands (defense + offense)
```

## Alternatives Considered

### Alternative 1: 效用函数 AI（Utility-Based AI）

- **Description**: 每个可能的行动计算效用分数 = `Σ(weight_i × consideration_i)`，选最高分行动执行
- **Pros**: 行为"涌现"而非预设——调权重就变风格；学术界有充分研究；易于扩展多目标
- **Cons**: 设计和调试权重的认知负担大——"AI 为什么不进攻？"需要反推 6 个加权因子；小规模场景下与规则引擎差距不大
- **Rejection Reason**: MVP 只有 10 颗星的决策空间，效用函数的优势体现不出来。规则引擎的透明性更适合快速迭代和调试。

### Alternative 2: 行为树（Behavior Tree）

- **Description**: 节点树结构，从 root 遍历到 leaf，条件节点控制分支，行动节点执行
- **Pros**: 可视化的决策结构；Godot 社区有成熟的行为树插件；适合复杂多层次 AI
- **Cons**: 引入插件依赖；10 颗星的决策深度只需要 2 层（防御/进攻），行为树是牛刀；BP 调试工具链在 GDScript 生态不够成熟
- **Rejection Reason**: MVP AI 只需要条件→行动，不需要 Sequence/Selector/Decorator 的完整行为树抽象。

### Alternative 3: Minimax / MCTS（博弈树搜索）

- **Description**: AI 向前搜索 N 步，模拟双方最优走法，选择最大化胜率的行动
- **Pros**: 理论最优——如果算到底必胜
- **Cons**: 分支因子大（10 星 × 3 邻 × 3 兵种 = 90 分支/回合）；深度 2 就有 8100 个节点需要评估；回合制策略的对手是"时间"不是"搜索深度"
- **Rejection Reason**: 回合制策略不需要博弈树——AI 的目标不是"赢你"而是"给你有挑战的对手"。规则引擎可以表现得"聪明"但不会"碾压"，更适合难度调节。

## Consequences

### Positive

- **透明可调试**: 每回合 AI 的决策可打印："AI 从星球 3 派 5 步打星球 5——价值 8.2"。设计者一眼看懂 AI 为什么这么走。
- **行为可控**: 调 `aggression` 一个参数就能改变 AI 风格——激进 AI 倾巢而出，保守 AI 龟缩防守。
- **不会做出愚蠢决策**: 防御优先保证 AI 不会"倾巢进攻后被偷家"。贪心分配保证 AI 不会超限出兵。
- **可测试**: 每个阶段独立可测——给一组星球状态，断言防御指令正确、进攻候选排序正确。

### Negative

- **无长期规划**: 贪心策略只看当前回合——AI 不会"这回合调兵到前线、下回合总攻"。缓解：MVP 单关规模下贪心已足够；通过防御阶段的预留兵力机制，AI 会自然集中兵力到前线。
- **兵种选择简单**: MVP AI 只选克制目标驻兵的兵种，不会做"诱敌换兵种"这种高级策略。缓解：`intelligence` 参数为低智能 AI 加入随机兵种选择，产生行为变化。
- **无适应性**: AI 行为不随玩家策略变化——同一个局面永远产同样的指令。缓解：`intelligence < 1.0` 时随机兵种选择引入变化；长期可通过提高 `aggression` 模拟"AI 学会了"。

### Risks

- **性能边界**: 最坏情况 10 星 × 3 邻 × 3 兵种 = 90 次 `resolve()` 调用，每次 ~10 浮点运算 ≈ < 1ms。无风险。
- **AI 行为被玩家摸透**: 玩家学会"AI 永远留 30% 防守"后可以针对。缓解：`defensiveness` 参数在不同关卡取不同值 → 不同 AI "个性"。

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| AI 敌人 | 决策逻辑：进攻哪个星、从哪出兵、出多少、防守优先级 | 分阶段规则引擎：防御→进攻→冲突消解 |
| AI 敌人 | 强度可调节 | `aggression`, `defensiveness`, `intelligence` 参数 |
| AI 敌人 | 不做出超限出兵 | Phase 3 冲突消解 + ADR-0004 overdraft 安全网 |
| 回合管理器 | AI 指令在步骤 1 与玩家指令合并 | `compute_turn()` 在 `_collect_commands()` 中调用 |

## Performance Implications

- **CPU**: 防御阶段 O(N) + 进攻阶段 O(N × M × T)（N=AI 星球数 ≤ 10, M=邻星数 ≤ 4, T=兵种数=3）≈ 120 次 `resolve()`。每次 10 FLOP → < 2ms
- **Memory**: AttackCandidate 临时列表 < 1KB
- **Load Time**: 无
- **Network**: 不适用

## Migration Plan

不适用 — 新项目。未来扩展路径：
- 多 AI 对手：为每个 AI 势力创建独立的参数配置（不同"个性"）
- 学习型 AI：在 `aggression` 参数中加入"根据玩家行为调整"的逻辑
- 多层决策：Feature 层可添加"战役级 AI"选星系、Core 层 AI 选星球

## Validation Criteria

- `compute_turn()` 返回的指令每个 `from_planet` 的 `owner == ENEMY`
- AI 不会从 garrison = 0 的星球发兵
- 防守阶段：受 HIGH 威胁且 garrison < defense_min 的星球收到支援指令
- 进攻阶段：所有进攻指令的 `estimate.attacker_wins == true`
- 同一出发星多条指令的总兵力 ≤ 该星驻兵（冲突消解生效）
- 单元测试：给定固定星球状态 → AI 输出固定指令（确定性，当 intelligence=1.0）
- AI 在全部 10 颗星被玩家占领时返回空指令列表

## Related Decisions

- ADR-0004: 回合结算模型 — AI `compute_turn()` 在步骤 1 收集阶段调用
- ADR-0005: 星球数据模型 — AI 通过 PlanetSystem API 读取星球状态
- ADR-0006: 战斗公式设计 — AI 调用 `CombatSystem.resolve()` 预估战斗结果
- ADR-0008: 国王寿命模型 — AI 无国王概念（只有玩家有国王）
- `docs/architecture/architecture.md` — Module Ownership: AI 敌人系统
