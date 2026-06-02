# Story 002: 多攻方应用顺序与回合管线集成

> **Epic**: 占领系统 (occupation-system)
> **Status**: Ready
> **Layer**: Core
> **Type**: Integration
> **Estimate**: 1h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/occupation-system.md`
**Requirement**: `TR-OCC-003`

**ADR Governing Implementation**: ADR-0004: 回合结算模型 (步骤 4 应用顺序)
**ADR Decision Summary**: 步骤 4 中的应用顺序固定为先玩家指令后 AI 指令。玩家指令之间按提交顺序。这样结果是确定的——即使多条指令攻击同一目标星球，按序应用后最终状态唯一。指令顺序无关的快照模型（步骤 3）保证战斗计算独立于应用顺序。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: 纯逻辑——Array 排序 + 遍历调用 OccupationSystem。无引擎 API 依赖。

**Control Manifest Rules (this layer)**:
- Required: 步骤 4 应用顺序：先玩家指令后 AI 指令 — 保证结果确定性 — source: ADR-0004
- Forbidden: 禁止顺序执行指令（战斗计算阶段） — 计算基于快照，应用按序 — source: ADR-0004
- Guardrail: 20 条指令顺序应用 < 1ms

---

## Acceptance Criteria

*From GDD `design/gdd/occupation-system.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN 玩家指令和 AI 指令攻击同一目标星球，WHEN 步骤 4 按"玩家优先"顺序应用，THEN 玩家指令先于 AI 指令应用
- [ ] **AC-2**: GIVEN 多条玩家指令攻击同一目标星，WHEN 步骤 4 应用，THEN 按提交顺序应用（先提交先处理）
- [ ] **AC-3**: GIVEN 第一条玩家指令占领了目标星，WHEN 第二条 AI 指令应用时，THEN AI 指令的 `attacker_faction` 基于新 owner（玩家）判定
- [ ] **AC-4**: GIVEN 排序逻辑给定同一批 commands + 同一批 battle_results，WHEN 两次运行步骤 4，THEN 最终星球状态完全相同（确定性验证）
- [ ] **AC-5**: GIVEN 步骤 4 应用完成，WHEN 所有占领变更已生效，THEN 出发星驻兵已扣减（`update_garrison(source, -attacker_total)`）

---

## Implementation Notes

*Derived from ADR-0004 Implementation Guidelines:*

### 步骤 4 应用流程

TurnManager 中 `_apply_results()` 方法：

```gdscript
# turn_manager.gd
func _apply_results(
    commands: Array,           # Array[DeploymentCommand]
    battle_results: Array,     # Array[BattleResult]
    snapshot: Dictionary       # 步骤 2 拍摄的星球快照
) -> void:
    # 分离玩家指令和 AI 指令
    var player_entries := []
    var ai_entries := []
    
    for i in range(commands.size()):
        var entry = {
            "cmd": commands[i],
            "result": battle_results[i],
        }
        if commands[i].player_owned:
            player_entries.append(entry)
        else:
            ai_entries.append(entry)
    
    # 按顺序应用: 先玩家，后 AI
    for entry in player_entries + ai_entries:
        _apply_single_result(entry.cmd, entry.result)

func _apply_single_result(cmd: DeploymentCommand, result: BattleResult) -> void:
    # 确定攻击方归属（读取当前实时状态——步骤 4 顺序应用后可能已变更）
    var attacker_faction := _planet_system.get_planet(cmd.from_planet).owner
    
    # 应用占领结果
    _occupation_system.apply_battle_result(
        cmd.to_planet,
        result,
        attacker_faction,
        cmd.count,
        _planet_system
    )
    
    # 扣除出发星驻兵
    _planet_system.update_garrison(cmd.from_planet, -cmd.count)
```

### 排序规则总结

| 优先级 | 指令来源 | 内部排序 |
|--------|---------|---------|
| 1 (先) | 玩家指令 (`player_owned=true`) | 提交顺序（`commands` 数组原始顺序） |
| 2 (后) | AI 指令 (`player_owned=false`) | AI 生成顺序（`commands` 数组原始顺序） |

### 关键实现要点

- `DeploymentCommand.player_owned` 字段（bool）由 deployment-system 在 `submit_command()` 时设置
- 玩家指令之间保持提交顺序——不额外排序，`player_entries` 保持 `commands` 中的原始相对顺序
- AI 指令之间保持生成顺序——同理
- 步骤 3 的战斗计算**不依赖应用顺序**（基于快照）——顺序只在步骤 4 应用阶段重要
- 步骤 4 中 `attacker_faction` 读取**实时** owner（非快照）——因为前面的指令可能已改变归属
- 出发星驻兵扣减在每次应用后执行——保证多指令从同一星发兵时后续指令的校验正确

### 确定性保证

```
给定: commands = [cmd1, cmd2, cmd3] (排序后)
      battle_results = [r1, r2, r3] (基于快照计算)
应用顺序: cmd1→r1, cmd2→r2, cmd3→r3

确定性来源:
1. 排序规则固定（玩家优先，提交顺序）
2. 战斗结果基于快照（不受应用顺序影响）
3. 应用时读取实时状态（受前面应用的影响——但这是期望行为）
4. 同一输入总是产生同一应用序列 → 最终状态唯一
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: `apply_battle_result()` / `transfer()` 核心逻辑
- TurnManager: 步骤 1 收集指令、步骤 2 拍摄快照、步骤 3 计算战斗、步骤 5 收尾
- DeploymentSystem: `DeploymentCommand` 结构定义、`submit_command()` 实现
- AI: `compute_turn()` 生成 AI 指令

---

## QA Test Cases

*Derived from GDD acceptance criteria. The developer implements against these.*

- **AC-1**: 玩家优先于 AI
  - Given: 玩家指令 cmd_P (to_planet=2) + AI 指令 cmd_A (to_planet=2)，双方都 attacker_wins
  - When: 步骤 4 按玩家优先顺序应用
  - Then: 先应用 cmd_P（目标星 owner→PLAYER），后应用 cmd_A（目标星 owner 已为 PLAYER→触发防御性检查）
  - Edge cases: AI 先打赢但玩家后打赢 → 最终 owner=PLAYER

- **AC-2**: 玩家指令提交顺序
  - Given: cmd1 (to_planet=2, 提交第1) + cmd2 (to_planet=2, 提交第2)
  - When: 步骤 4 应用
  - Then: cmd1 先应用，cmd2 后应用
  - Edge cases: cmd1 占领成功 → cmd2 攻击己方星 → 防御性检查跳过

- **AC-3**: 动态归属读取
  - Given: cmd1(玩家)→星球2(ENEMY)，cmd2(AI)→星球2；cmd1 先应用占领成功
  - When: cmd2 应用
  - Then: `attacker_faction` 读取 cmd2.from_planet.owner（实时，可能仍为 ENEMY），`get_planet(2).owner` 已为 PLAYER（被 cmd1 改变）

- **AC-4**: 确定性验证
  - Given: 固定的 commands + battle_results
  - When: 两次独立运行步骤 4（重置星球状态到相同初始值）
  - Then: 两次最终星球状态完全一致（owner + garrison）
  - Edge cases: 验证步骤 4 逻辑中无随机数、无时间依赖

- **AC-5**: 出发星驻兵扣减
  - Given: cmd(from=1, to=2, count=5)，attacker_wins=true
  - When: 步骤 4 应用完成
  - Then: `get_planet(1).garrison` 减少 5（通过 `update_garrison(1, -5)`）
  - Edge cases: 多条指令从同一星出发 → 逐条扣减，后续指令受前面影响

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- Integration: `tests/integration/occupation-system/occupation_ordering_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (occupation-transfer) — `apply_battle_result()` 必须 DONE
- Depends on: planet-system (TR-PLT-005 `update_garrison()`, TR-PLT-006 `set_owner()`, TR-PLT-008 `get_planets_by_owner()`) — must be DONE
- Depends on: combat-resolution Story 001 — `BattleResult` 结构必须可用
- Depends on: deployment-system — `DeploymentCommand` 结构（含 `player_owned` 字段）必须可用
- Unlocks: TurnManager 步骤 4 完整集成、回合结算 end-to-end 测试
