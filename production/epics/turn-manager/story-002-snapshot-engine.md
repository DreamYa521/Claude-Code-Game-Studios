# Story 002: Snapshot Resolution Engine

> **Epic**: turn-manager
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Logic
> **Estimate**: 3h
> **Manifest Version**: 2026-05-31
> **Last Updated**: —

## Context

**GDD**: `design/gdd/turn-manager.md`
**Requirement**: TR-TRN-003, TR-TRN-004, TR-TRN-006, TR-TRN-007, TR-TRN-010
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0004: 回合结算模型 (primary), ADR-0001: 事件总线架构 (secondary)
**ADR Decision Summary**: 5 步骤快照模型 — 收集指令→拍快照→基于快照计算→统一应用→收尾。步骤 2-4 保证指令结算顺序无关。超限兵力按比例削减。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: 纯数据操作，Dictionary.duplicate(true) 深拷贝在 Godot 4.x 全版本一致。MVP 10星/20指令 < 1ms。

**Control Manifest Rules (this layer)**:
- Required: 5 步骤快照模型：收集指令→拍快照→基于快照计算→统一应用→收尾
- Required: 快照基于"回合前"状态计算，统一应用 — 保证顺序无关
- Required: 超限兵力按比例削减 — ratio = available_garrison / total_outgoing, count = floor(count × ratio)
- Required: 步骤 4 应用顺序：先玩家指令后 AI 指令 — 保证结果确定性
- Required: 生产在 CLEANUP 步骤 5 执行 — 在占领变更后，确保新占星参与当回合生产
- Forbidden: 禁止顺序执行指令 — 必须基于快照同时计算
- Guardrail: 回合结算 10星/20指令 < 1ms（纯数据操作）

---

## Acceptance Criteria

*From GDD `design/gdd/turn-manager.md`, scoped to this story:*

- [ ] **AC-1**: `end_turn()` 执行步骤 1-5 完整流程，`turn_number` 增加 1，`EventBus.turn_ended` 被 emit
- [ ] **AC-2**: 玩家 1 条指令（A→B, 5人）+ AI 1 条指令（C→A, 3人），计算顺序不影响最终星球 garrison（交换两部指令顺序 → 相同结果）
- [ ] **AC-3**: 同一星出发 2 条指令总兵力 15、snapshot garrison=10，两条指令分别按 10/15 比例削减，削减后总和 ≤ 10
- [ ] **AC-4**: 空回合（无任何指令）正常执行，产兵照常，`turn_number` +1
- [ ] **AC-5**: 玩家指令和 AI 指令攻击同一目标星球时各自独立计算（基于同一 snapshot），先应用玩家结果再应用 AI 结果

---

## Implementation Notes

*Derived from ADR-0004:*

**1. 完整 `_execute_turn()` 流程**（扩展 Story 001 的骨架）:

```gdscript
func _execute_turn() -> void:
    # 阶段切换: DEPLOYMENT → EXECUTION
    current_phase = TurnPhase.EXECUTION
    EventBus.execution_phase_started.emit()
    
    # === 步骤 1: 收集全部指令 ===
    var ai_commands = _collect_ai_commands()
    var player_commands = _pending_commands
    var all_commands = player_commands + ai_commands
    
    # === 步骤 2: 拍快照 ===
    var snapshot = _take_snapshot()
    
    # === 步骤 3: 基于快照计算所有战斗（顺序无关）===
    var results = _compute_battles(all_commands, snapshot)
    results = _resolve_overdraft(results, snapshot)
    
    # === 步骤 4: 统一应用结果 ===
    _apply_results(results)
    
    # === 阶段切换: EXECUTION → CLEANUP ===
    current_phase = TurnPhase.CLEANUP
    
    # === 步骤 5: 收尾 ===
    _cleanup()
    
    # === 回合结束 ===
    _pending_commands.clear()
    turn_number += 1
    EventBus.turn_ended.emit(turn_number)
    current_phase = TurnPhase.DEPLOYMENT
    EventBus.deployment_phase_started.emit()
```

**2. 步骤 2: 拍快照**:

```gdscript
func _take_snapshot() -> Dictionary:
    # 深拷贝当前所有星球状态
    # 依赖 PlanetSystem.get_all_planets() — Core 层提供
    # MVP 实现: 假设 PlanetSystem 提供 get_snapshot() 方法
    # 本 Foundation 层 Story 实现骨架，Core 层接入后填充
    var snap = {}
    # 伪代码:
    # for planet in PlanetSystem.get_all_planets():
    #     snap[planet.id] = {
    #         "garrison": planet.garrison,
    #         "owner": planet.owner,
    #         "max_garrison": planet.max_garrison,
    #         "production_rate": planet.production_rate,
    #     }
    return snap
```

**3. 步骤 3: 计算战斗**:

```gdscript
func _compute_battles(commands: Array, snapshot: Dictionary) -> Array:
    # 所有读取来自 snapshot，不碰真实 planet
    # 调用 CombatSystem.resolve(cmd, snapshot) — Core 层提供
    var results = []
    # 伪代码:
    # for cmd in commands:
    #     var result = CombatSystem.resolve(cmd, snapshot)
    #     results.append(result)
    return results
```

**4. 超限兵力削减（步骤 3 安全网）**:

```gdscript
func _resolve_overdraft(results: Array, snapshot: Dictionary) -> Array:
    # 按出发星分组
    var by_source = {}
    for r in results:
        var src = r.from_planet
        if not by_source.has(src):
            by_source[src] = []
        by_source[src].append(r)
    
    for source_id in by_source:
        var total_outgoing = 0
        for r in by_source[source_id]:
            total_outgoing += r.attacker_total
        
        var available = snapshot.get(source_id, {}).get("garrison", 0)
        if total_outgoing > available and total_outgoing > 0:
            var ratio = available / float(total_outgoing)
            for r in by_source[source_id]:
                r.attacker_total = int(floor(r.attacker_total * ratio))
                # r.recalculate() — 重新计算战斗结果
                # 实际实现取决于 BattleResult 结构
    
    return results
```

**削减公式**:
```
ratio = available_garrison / total_outgoing
adjusted_count = floor(count × ratio)
```

**5. 步骤 4: 统一应用**:

```gdscript
func _apply_results(results: Array) -> void:
    # 先应用玩家指令结果，后应用 AI 指令结果
    # 保证确定性：同一批指令总是同样顺序应用
    for result in results:
        # PlanetSystem.update_garrison(result.from, -result.attacker_total)
        # PlanetSystem.update_garrison(result.to, delta)
        # if result.attacker_wins:
        #     OccupationSystem.transfer(result.to, attacker_faction)
        pass  # Core 层接入后填充
```

**6. 步骤 5: 收尾**:

```gdscript
func _cleanup() -> void:
    # 生产系统产兵（在占领变更后，确保新占星参与）
    # ProductionSystem.apply_turn()
    
    # 胜负判定
    # if WinCondition.check_victory():
    #     GameState.transition_to(GameState.State.VICTORY)
    # elif WinCondition.check_defeat():
    #     GameState.transition_to(GameState.State.DEFEAT)
    
    # 国王寿命消耗
    # KingSystem.consume_turn()
    pass  # Core/Feature 层接入后填充
```

**7. 顺序无关性保证**:
- 步骤 3 所有战斗计算只读快照（Dictionary），不读实时星球
- 步骤 4 一次性应用所有结果（先后顺序仅影响双方同时攻击同一目标的情况）
- 同目标竞争: 先应用玩家结果，再应用 AI 结果（后到达的覆盖先到达的）— 确定性策略
- 单元测试验证: 固定 snapshot + 固定 commands → 固定 results，与 command 遍历顺序无关

---

## Out of Scope

*Handled by other systems — do not implement here:*

- Story 001: 阶段循环枚举、submit_command() gate、end_turn() gate、EventBus 阶段广播
- PlanetSystem.get_all_planets() / update_garrison() / set_owner() — Core 层 PlanetSystem
- CombatSystem.resolve() — Core 层 CombatSystem
- ProductionSystem.apply_turn() — Core 层 ProductionSystem
- WinCondition.check_victory() / check_defeat() — Feature 层 WinConditions
- KingSystem.consume_turn() — Core 层 KingSystem
- AI.compute_turn() — Core 层 AIEnemy

---

## QA Test Cases

- **AC-1**: 完整回合流程
  - Given: current_phase==DEPLOYMENT, 有 1 条玩家指令
  - When: end_turn()
  - Then: turn_number 增加 1, EventBus.turn_ended emit 参数为新的 turn_number, current_phase 回到 DEPLOYMENT
  - Edge cases: 验证事件序列 deployment_phase_started 在新回合开始时 emit

- **AC-2**: 顺序无关性验证
  - Given: 固定 snapshot (星球 A, B, C 的状态)，commands 列表 [cmd1(A→B), cmd2(C→A)]
  - When: 分别以 [cmd1, cmd2] 和 [cmd2, cmd1] 顺序调用 _compute_battles()
  - Then: 两个顺序产生相同的 results（每场战斗的 BattleResult 各字段一致）
  - Edge cases: 三指令循环 A→B, B→C, C→A — 任意排列得到相同最终状态

- **AC-3**: 超限兵力削减
  - Given: snapshot 中 Planet X garrison=10, 两条指令从 X 出发: cmd1 count=5, cmd2 count=10
  - When: 计算 total_outgoing=15 > 10 → ratio=10/15=0.666
  - Then: cmd1 adjusted=floor(5×0.666)=3, cmd2 adjusted=floor(10×0.666)=6 → 总和 9 ≤ 10
  - Edge cases: garrison=0 → total_outgoing > 0 → ratio=0 → 所有指令 count=0（被削减为空）

- **AC-4**: 空回合正常执行
  - Given: current_phase==DEPLOYMENT, 无任何待结算指令
  - When: end_turn()
  - Then: 步骤 1-5 正常执行（步骤 3 跳过，步骤 4 跳过），turn_number +1
  - Edge cases: _cleanup() 中的产兵仍照常执行（无指令不妨碍生产）

- **AC-5**: 同时攻击同一目标星球
  - Given: snapshot 中 Planet B garrison=5 owner=ENEMY, cmd_player(A→B, 3 PLAYER), cmd_ai(C→B, 4 ENEMY)
  - When: 独立计算两场战斗（均基于 snapshot 中 B garrison=5）
  - Then: 应用时先 player_result 后 ai_result；最终 B 状态由后应用的指令结果决定
  - Edge cases: 两方兵力均 > 守军 → 先应用的占领 B，后应用的从先应用的夺回 B

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- Logic: `tests/unit/turn-manager/test_snapshot_engine.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: TurnManager Story 001 (Phase Loop & Command Intake) — 在本 Story 的骨架基础上实现快照步骤
- Depends on: GameState Story 001 (State Machine) — 步骤 5 胜负判定调用 GameState.transition_to()
- Depends on: EventBus Story 001 (Signal Declarations) — 阶段事件广播
- Soft Depends on: PlanetSystem, CombatSystem, ProductionSystem, WinConditions, KingSystem, AIEnemy — 本 Story 定义接口契约和骨架，Core/Feature 层 Story 实现后回填
- Unlocks: None（Foundation 层 turn-manager 最后一个 Story；解锁 Core 层全部系统）
