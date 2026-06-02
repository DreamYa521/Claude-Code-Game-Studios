# ADR-0004: 回合结算模型

## Status
Accepted

## Date
2026-05-31

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core (回合逻辑) |
| **Knowledge Risk** | LOW — 纯 GDScript 逻辑，不依赖特定引擎 API |
| **References Consulted** | `docs/architecture/architecture.md` Phase 3, Phase 4 |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | None |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (阶段切换走 EventBus), ADR-0003 (PLAYING 状态 gate) |
| **Enables** | ADR-0005 (星球数据模型), ADR-0006 (战斗公式), ADR-0007 (AI 架构) |
| **Blocks** | 回合管理器 GDD, 出征系统 GDD, 战斗结算 GDD, AI 敌人 GDD |
| **Ordering Note** | Foundation ADR 最后一个，完成后方可开始 Core 层 |

## Context

### Problem Statement

回合结束时，所有出征指令必须**同时**结算。如果按顺序逐个执行，先执行的指令会改变星球状态（兵力减少、归属变更），从而影响后执行的指令结果。这违背"回合制同时结算"的核心设计。

需要确保：无论指令以什么顺序计算，结果都相同。

### Constraints

- 玩家指令和 AI 指令在同一回合中混合结算
- 同一个星球可以是多条指令的出发地或目的地
- 星球可能在结算过程中易主（被打下），但占领只在结算末尾生效
- 提交阶段已校验兵力充足，但多条指令从同一星球出发时总兵力可能超出
- MVP 阶段单关卡最多约 10 颗星、20 条指令/回合

### Requirements

- 指令结算顺序不影响最终结果
- 从同一星球出发的多条指令公平分配兵力（若总量超出则按比例削减）
- 结算中被打下的星球在当回合不产兵（归属还未生效）
- 每回合分三个阶段：部署 → 结算 → 收尾，阶段不可跳转

## Decision

**使用快照模型：Snapshot → Compute All → Apply All。**

回合结算分为 5 个子步骤，其中步骤 2-4 保证顺序无关性：

1. **收集全部指令** — 玩家指令 + AI `compute_turn()` 输出
2. **拍快照** — 深拷贝所有星球当前状态（garrison, owner, production_rate）
3. **基于快照计算所有战斗** — 只读快照，不碰实时星球
4. **统一应用结果** — 将所有战斗的兵力增减和归属变更一次性写入星球
5. **收尾** — 生产、胜负判定、国王寿命

### Architecture Diagram

```
回合开始 (deployment_phase_started)
  │
  │ 玩家操作: deploy(), submit_command()
  │
  ▼
玩家点击 "结束回合"
  │
  ▼
┌─────────────────────────────────────────────┐
│ 步骤 1: 收集指令                              │
│                                             │
│ AI.compute_turn() → ai_commands             │
│ DeploymentSystem.get_pending() → player_cmds │
│ all_commands = player_cmds + ai_commands    │
│                                             │
├─────────────────────────────────────────────┤
│ 步骤 2: 拍快照                                │
│                                             │
│ snapshot = {}                                │
│ for each planet:                            │
│   snapshot[id] = {garrison, owner,          │
│     max_garrison, production_rate}          │
│                                             │
├─────────────────────────────────────────────┤
│ 步骤 3: 基于快照计算所有战斗 (顺序无关)         │
│                                             │
│ results = []                                 │
│ for cmd in all_commands:                    │
│   # 所有读取来自 snapshot，不碰真实 planet    │
│   result = CombatSystem.resolve(cmd, snapshot) │
│   results.append(result)                    │
│                                             │
│ # 去重处理：同一出发星的多条指令兵力超限        │
│ results = _resolve_overdraft(results, snapshot) │
│                                             │
├─────────────────────────────────────────────┤
│ 步骤 4: 统一应用                              │
│                                             │
│ for result in results:                      │
│   PlanetSystem.update_garrison(from, delta)  │
│   PlanetSystem.update_garrison(to, delta)    │
│   if result.attacker_wins:                  │
│       OccupationSystem.transfer(to, faction) │
│                                             │
├─────────────────────────────────────────────┤
│ 步骤 5: 收尾                                  │
│                                             │
│ ProductionSystem.apply_turn()               │
│ WinCondition.check_victory() / check_defeat()│
│ KingSystem.consume_action()                 │
│ EventBus.turn_ended.emit(turn_number)       │
└─────────────────────────────────────────────┘
  │
  ▼
EventBus.deployment_phase_started.emit()
  │
  ▼
下一回合开始
```

### Key Interfaces

```gdscript
# turn_manager.gd — autoload: TurnManager

enum TurnPhase { DEPLOYMENT, EXECUTION, CLEANUP }

var turn_number: int = 0
var current_phase: TurnPhase = TurnPhase.DEPLOYMENT

func submit_command(cmd: DeploymentCommand) -> bool
# 返回 false 若不在部署阶段

func end_turn() -> void:
    if current_phase != TurnPhase.DEPLOYMENT:
        return
    _execute_turn()

func _execute_turn() -> void:
    current_phase = TurnPhase.EXECUTION
    EventBus.execution_phase_started.emit()
    
    # 1. 收集
    var commands = _collect_commands()
    
    # 2. 快照
    var snapshot = _take_snapshot()
    
    # 3. 计算
    var results = _compute_battles(commands, snapshot)
    
    # 4. 应用
    _apply_results(results)
    
    # 5. 收尾
    current_phase = TurnPhase.CLEANUP
    _cleanup()
    
    current_phase = TurnPhase.DEPLOYMENT
    turn_number += 1
    EventBus.turn_ended.emit(turn_number)
    EventBus.deployment_phase_started.emit()

func _take_snapshot() -> Dictionary:
    var snap = {}
    for planet in PlanetSystem.get_all_planets():
        snap[planet.id] = {
            "garrison": planet.garrison,
            "owner": planet.owner,
            "max_garrison": planet.max_garrison,
            "production_rate": planet.production_rate,
        }
    return snap
```

### 超限兵力处理

当多条指令从同一星球出发、总兵力超出该星球驻兵时：

```gdscript
func _resolve_overdraft(results: Array, snapshot: Dictionary) -> Array:
    var by_source = {}
    for r in results:
        by_source.get_or_add(r.from_planet, []).append(r)
    
    for source_id in by_source:
        var total_outgoing = 0
        for r in by_source[source_id]:
            total_outgoing += r.attacker_total
        
        var available = snapshot[source_id].garrison
        if total_outgoing > available:
            var ratio = available / float(total_outgoing)
            for r in by_source[source_id]:
                r.attacker_total = int(floor(r.attacker_total * ratio))
                r.recalculate()
    
    return results
```

该情况不应频繁出现 — 提交阶段已校验 `count <= planet.garrison`。只在多条指令从同一星出发且总和超限时触发，作为安全网。

## Alternatives Considered

### Alternative 1: 顺序执行

- **Description**: 指令按提交顺序或遍历顺序逐个执行，每条指令更新星球后下一条读最新状态
- **Pros**: 实现极简，不需要快照和结果数组
- **Cons**: 顺序不同 → 结果不同。玩家操作顺序变成策略的一部分，违背"同时结算"设计意图
- **Rejection Reason**: 对回合制策略游戏的公平性破坏太大。玩家不应该通过改变提交顺序来获取优势。

### Alternative 2: 优先级排序

- **Description**: 指令按优先级排序后顺序执行（如：防守优先 → 进攻 → 转移）
- **Pros**: 确定性结果；优先级规则可成为策略深度
- **Cons**: 引入"优先级"概念 → 玩家需学习优先级；规则可能与直觉冲突
- **Rejection Reason**: MVP 不需要优先级系统。快照模型更简单、更直观。

### Alternative 3: 并发出征合并为大混战

- **Description**: 多条指令攻击同一星球 → 合并为一场多方混战
- **Pros**: 最"真实"的同时结算模拟
- **Cons**: 战斗公式复杂度指数增长；三方混战定义不清晰
- **Rejection Reason**: MVP 多条指令攻击同一星球是稀有情况。当前简化为各自独立战斗。

## Consequences

### Positive

- **确定性**: 同输入 → 同输出。指令计算顺序无关
- **公平**: 所有指令同时生效，符合回合制直觉
- **可测试**: 快照 → 计算 → 应用 三步分离，每步可独立单元测试
- **调试友好**: 每步状态可打印

### Negative

- **不能表现"途中拦截"**: 所有部队同时出发同时到达。缓解：MVP 不需要；若未来需要可在 Feature 层加拦截系统
- **超限兵力按比例削减**: 可能产生非整数兵力（floor 取整）。缓解：提交阶段校验已防绝大多数情况

### Risks

- **快照与实际不同步**: 如果步骤 2-4 之间有系统修改了星球，结果错误。缓解：`current_phase = EXECUTION` gate 拒绝修改
- **大型关卡性能**: 100+ 星/500+ 指令时 O(N)。缓解：MVP 10 星/20 指令完全没问题

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| 回合管理器 | 回合结束时同时结算 | 5 步骤快照模型，`end_turn()` 触发 |
| 出征系统 | 指令同时执行 | 快照基于"回合前"状态计算，统一应用 |
| 战斗结算 | 伤害计算脱离顺序依赖 | 所有战斗基于同一个快照 |
| AI 敌人 | AI 指令与玩家指令合并 | 步骤 1 收集合并为 `all_commands` |
| 生产系统 | 收尾阶段产兵 | 步骤 5 在所有战斗应用后执行 |

## Performance Implications

- **CPU**: 10 星/20 指令 → < 1ms（纯数据操作）
- **Memory**: 快照 < 1KB per 回合，即时释放
- **Load Time**: 无
- **Network**: 不适用

## Migration Plan

不适用 — 新项目。

## Validation Criteria

- 两条指令 A→B, C→A → 无论计算顺序，A 的最终 garrison 相同
- 同一出发星多条指令总量超限 → 按比例削减，削减后总量 = snapshot garrison
- 回合结算中修改星球被拒绝（`current_phase == EXECUTION` gate）
- `deployment_phase_started` → `execution_phase_started` → `turn_ended` → `deployment_phase_started` 序列完整
- 单元测试：固定 snapshot + 固定 commands → 固定 results

## Related Decisions

- ADR-0001: 事件总线 — 阶段切换信号通过 EventBus 广播
- ADR-0003: GameState — 结算在 PLAYING 状态内执行
- ADR-0005: 星球数据模型 — 快照需要深拷贝星球状态
- ADR-0006: 战斗公式 — 步骤 3 调用的 `CombatSystem.resolve()`
- `docs/architecture/architecture.md` — Phase 3 数据流场景 3（回合结算）
