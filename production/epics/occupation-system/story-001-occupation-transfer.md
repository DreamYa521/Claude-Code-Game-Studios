# Story 001: transfer() 占领核心逻辑

> **Epic**: 占领系统 (occupation-system)
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Estimate**: 1.5h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/occupation-system.md`
**Requirement**: `TR-OCC-001`, `TR-OCC-002`, `TR-OCC-004`, `TR-OCC-005`

**ADR Governing Implementation**: ADR-0004: 回合结算模型 (步骤 4 Apply); ADR-0005: 星球数据模型 (set_owner / set_garrison)
**ADR Decision Summary**: 占领系统是"战斗结果→战略影响"的桥梁——`attacker_wins=true` → `transfer(target, attacker_faction)` + `set_garrison(target, attacker_survived)`。`attacker_wins=false` → `set_garrison(target, defender_survived)`。包含防御性检查：禁止占领己方星球。空旷星球无战斗即占领。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: 纯逻辑——调用 PlanetSystem API + 读取 BattleResult 字段。无引擎 API 依赖。

**Control Manifest Rules (this layer)**:
- Required: `set_owner()` 内部广播 EventBus.planet_owner_changed — source: ADR-0005
- Required: 空星球 (defender_count=0) → attacker_wins=true, 双方损失=0 — source: ADR-0006
- Forbidden: 禁止 `new_owner == current_owner` 时重复占领 — source: ADR-0005
- Guardrail: 占领操作 < 0.1ms（只涉及 Dictionary 赋值 + Signal emit）

---

## Acceptance Criteria

*From GDD `design/gdd/occupation-system.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN attacker_wins=true，WHEN `transfer(planet_id, PLAYER)` 调用，THEN `get_planet(planet_id).owner == PLAYER`
- [ ] **AC-2**: GIVEN attacker_wins=true，WHEN 占领完成，THEN 目标星 garrison = attacker_survived（占领部队留守）
- [ ] **AC-3**: GIVEN attacker_wins=false，WHEN 步骤 4 执行，THEN 目标星 owner 不变，garrison = defender_survived（守军继续驻扎）
- [ ] **AC-4**: GIVEN 占领完成，WHEN 检查 EventBus，THEN `planet_owner_changed` 被 emit（由 PlanetSystem.set_owner 内部广播）
- [ ] **AC-5**: GIVEN attacker_wins=true 且 new_owner == current_owner（己方星球），WHEN `transfer()` 调用，THEN 跳过归属变更（防御性检查）
- [ ] **AC-6**: GIVEN defender_count=0（空旷星球），WHEN 部队到达，THEN 归属变为攻击方，驻兵 = 出征兵力（无损占领）

---

## Implementation Notes

*Derived from ADR-0004 and ADR-0005 Implementation Guidelines:*

### OccupationSystem 核心

```gdscript
# occupation_system.gd
class_name OccupationSystem
extends RefCounted

# 处理单场战斗后的占领逻辑
# 返回: 是否发生了归属变更
func apply_battle_result(
    target_planet_id: int,
    result: BattleResult,
    attacker_faction: int,  # Faction enum
    attacker_total: int,    # 攻击方总出征兵力
    planet_system: PlanetSystem
) -> bool:
    if result.attacker_wins:
        var planet = planet_system.get_planet(target_planet_id)
        
        # 防御性检查: 禁止占领己方星球
        if planet.owner == attacker_faction:
            push_warning("OccupationSystem: attempted to occupy own planet %d" % target_planet_id)
            # 即使不占领，也要更新驻兵为攻击方幸存兵力
            planet_system.set_garrison(target_planet_id, result.attacker_survived)
            return false
        
        # 执行归属转移
        planet_system.set_owner(target_planet_id, attacker_faction)
        # 占领部队留守
        planet_system.set_garrison(target_planet_id, result.attacker_survived)
        return true
    else:
        # 攻击失败，防守方驻兵更新为幸存兵力
        planet_system.set_garrison(target_planet_id, result.defender_survived)
        return false
```

### transfer() 便捷方法

```gdscript
# 直接转移归属（不经过战斗——用于空旷星球）
func transfer(planet_id: int, new_owner: int, planet_system: PlanetSystem) -> void:
    var planet = planet_system.get_planet(planet_id)
    if planet.owner == new_owner:
        return  # 防御性检查
    planet_system.set_owner(planet_id, new_owner)
```

### 空旷星球处理

空旷星球（`defender_count == 0`）的 BattleResult 由 `CombatSystem.resolve()` 返回 `attacker_wins=true, attacker_loss=0`，因此 `attacker_survived == attacker_count`——攻击方全部兵力留守。OccupationSystem 无需特殊处理空旷星球，公式自动覆盖。

### 关键实现要点

- `apply_battle_result()` 接收 `attacker_faction` 参数——调用方（TurnManager）从 `PlanetSystem.get_planet(cmd.from_planet).owner` 获取
- 攻击失败时只更新 garrison，不改变 owner——通过 `planet_system.set_garrison()` 而非直接赋值
- `set_owner()` 内部广播 `EventBus.planet_owner_changed.emit(planet_id, old_owner, new_owner)`——已在 PlanetSystem 中实现（planet-system Story 003）
- `set_garrison()` 直接赋值 `planet.garrison = value`（不是 `update_garrison(id, delta)`）——因为战斗结果已确定最终值，不需要 delta 校验
- 防御性检查 `planet.owner == attacker_faction` 使用 `push_warning()` 而非 `push_error()`——这是安全网，不是致命错误
- OccupationSystem 不持有 PlanetSystem 引用——通过参数传入（依赖注入，可单元测试）

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: 多攻方应用顺序（先玩家后 AI）、与 TurnManager 步骤 4 的完整集成
- TurnManager: 步骤 3 收集战斗结果、步骤 4 遍历应用
- PlanetSystem: `set_owner()` / `set_garrison()` 实现（已在 planet-system Story 003）
- CombatSystem: `BattleResult` 结构定义（已在 combat-resolution Story 001）
- 出发星驻兵扣除——由 TurnManager 步骤 4 通过 `update_garrison(source, -attacker_total)` 处理

---

## QA Test Cases

*Derived from GDD acceptance criteria. The developer implements against these.*

- **AC-1**: 占领成功 → owner 变更
  - Given: planet_id=2, owner=ENEMY, garrison=5; BattleResult(attacker_wins=true, attacker_survived=8)
  - When: `apply_battle_result(2, result, PLAYER, 10, planet_system)`
  - Then: `get_planet(2).owner == PLAYER`

- **AC-2**: 占领后驻兵 = 攻击方幸存
  - Given: 同上场景
  - When: 占领完成
  - Then: `get_planet(2).garrison == 8`（attacker_survived）
  - Edge cases: attacker_survived=0（不应出现，但若出现则 garrison=0）

- **AC-3**: 攻击失败 → owner 不变
  - Given: planet_id=3, owner=ENEMY; BattleResult(attacker_wins=false, defender_survived=4)
  - When: `apply_battle_result(3, result, PLAYER, 10, planet_system)`
  - Then: `get_planet(3).owner == ENEMY`（不变），`garrison == 4`

- **AC-4**: EventBus 广播
  - Given: 占领场景（owner 从 ENEMY 变为 PLAYER）
  - When: `set_owner()` 被调用
  - Then: `EventBus.planet_owner_changed` 被 emit（由 PlanetSystem 内部触发）
  - Edge cases: 连接临时 Signal 监听验证 emit 参数 (planet_id, old_owner, new_owner)

- **AC-5**: 己方星球防御性检查
  - Given: planet_id=1, owner=PLAYER; BattleResult(attacker_wins=true)
  - When: `apply_battle_result(1, result, PLAYER, 10, planet_system)`
  - Then: push_warning() 被调用，owner 不变（保持 PLAYER），garrison 更新为 attacker_survived
  - Edge cases: 此场景不应在正常游戏流程中发生（玩家不会攻击己方星）

- **AC-6**: 空旷星球无损占领
  - Given: planet_id=4, owner=ENEMY; BattleResult(attacker_wins=true, attacker_survived=10, attacker_loss=0)
  - When: 占领完成
  - Then: owner=PLAYER, garrison=10（全部兵力存活留守）

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- Logic: `tests/unit/occupation-system/occupation_transfer_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: planet-system Story 003 (planet-mutation-snapshot) — `set_owner()` / `set_garrison()` / `get_planet()` 必须 DONE
- Depends on: combat-resolution Story 001 (combat-resolve-function) — `BattleResult` 类必须可用
- Unlocks: Story 002 (occupation-ordering), TurnManager 步骤 4 集成
