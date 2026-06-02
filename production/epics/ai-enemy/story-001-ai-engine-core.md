# Story 001: compute_turn() 三阶段规则引擎核心

> **Epic**: AI 敌人 (ai-enemy)
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Estimate**: 3h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/ai-enemy.md`
**Requirement**: `TR-AIE-001`, `TR-AIE-002`, `TR-AIE-003`, `TR-AIE-004`, `TR-AIE-005`, `TR-AIE-007`, `TR-AIE-008`, `TR-AIE-009`, `TR-AIE-010`

**ADR Governing Implementation**: ADR-0007: AI 决策架构 (分阶段规则引擎、确定性决策、参数化难度)
**ADR Decision Summary**: compute_turn() 在 TurnManager 步骤 1 调用，返回 Array[DeploymentCommand]。三阶段：防御评估 → 进攻规划 → 冲突消解。防御阶段按威胁比率分级处理，进攻阶段按价值评分贪心分配。AI 不使用国王系统（无寿命约束）。intelligence=1.0 时确定性输出（同输入→同指令）。

**Engine**: Godot 4.6 | **Risk**: MEDIUM
**Engine Notes**: 纯 GDScript 逻辑，无引擎 API 依赖。最坏 10星×3邻×3兵种 = 90 次 resolve() 调用 < 2ms。需调用 CombatSystem.resolve() 做战斗预估。

**Control Manifest Rules (this layer)**:
- Required: AI 分阶段规则引擎 — 防御→进攻→冲突消解，compute_turn() 在步骤 1 调用 — source: ADR-0007
- Required: AI 用 CombatSystem.resolve() 预估战斗 — 与真实结算同一公式 — source: ADR-0007
- Required: AI 不使用国王系统 — 无寿命约束，无代际传承 — source: ADR-0008
- Forbidden: 禁止 AI 读取玩家未提交指令 — AI 只读实时星球状态 — source: ADR-0007
- Forbidden: 禁止 AI 从 garrison=0 的星球发兵 — source: ADR-0007
- Guardrail: 最坏 10星×3邻×3兵种 = 90 次 resolve() < 2ms — source: ADR-0007

---

## Acceptance Criteria

*From GDD `design/gdd/ai-enemy.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN AI 拥有 3 颗星球（garrison=10, 8, 5），邻近 2 颗玩家星（garrison=4, 6），WHEN `compute_turn()`，THEN 返回非空 Array[DeploymentCommand]
- [ ] **AC-2**: GIVEN AI 全部星球 garrison=0，WHEN `compute_turn()`，THEN 返回空数组
- [ ] **AC-3**: GIVEN AI 无相邻敌星（全部隔离），WHEN `compute_turn()`，THEN 返回空数组
- [ ] **AC-4**: GIVEN AI 某星球受 HIGH 威胁（threat_ratio > 1.0），WHEN 防御阶段执行，THEN 尝试从非受胁星球调兵支援
- [ ] **AC-5**: GIVEN AI 某星球受 MEDIUM 威胁（threat_ratio 0.5-1.0），WHEN 防御阶段执行，THEN 不从该星发起进攻
- [ ] **AC-6**: GIVEN AI 某星球有富余兵力（garrison > defense_min），WHEN 进攻阶段执行，THEN 评估所有相邻非 AI 目标并生成候选
- [ ] **AC-7**: GIVEN 进攻候选按价值公式排序，WHEN 贪心分配，THEN 高价值目标优先获得兵力
- [ ] **AC-8**: GIVEN 同一出发星被分配 2 条进攻指令且总出兵 > 当前 garrison，WHEN 冲突消解执行，THEN sum(count) <= garrison（低优先级被削减或取消）
- [ ] **AC-9**: GIVEN intelligence=1.0 + 固定星球状态，WHEN 两次 `compute_turn()`，THEN 返回完全相同的指令列表（确定性验证）
- [ ] **AC-10**: GIVEN AI 星球，WHEN compute_turn() 任何阶段，THEN AI 不调用 KingSystem 任何方法（AI 无国王）

---

## Implementation Notes

*Derived from ADR-0007 and GDD ai-enemy.md:*

### 三阶段架构

```gdscript
# ai_enemy.gd (本 Story 为独立类)
class_name AIEnemy

const DEFENSE_RESERVE_RATIO := 0.3
const THREAT_HIGH := 1.0
const THREAT_MEDIUM := 0.5

# 进攻价值权重（MVP 硬编码，后续 Story 可配置化）
const VALUE_PRODUCTION_WEIGHT := 3.0
const VALUE_GARRISON_WEIGHT := 0.5
const VALUE_EFFICIENCY_WEIGHT := 2.0
const VALUE_POSITION_WEIGHT := 0.5

# 星球属性价值加成
const ATTR_VALUE := {
    PlanetAttribute.RICH: 4.0,
    PlanetAttribute.NORMAL: 2.0,
    PlanetAttribute.FORTRESS: 1.0,
    PlanetAttribute.BARREN: 0.0,
}

## 主入口：生成 AI 本回合全部指令
## planets: Dictionary[int -> planet_data]
## connections: Array[Array] — [[from, to], ...]
## resolve_fn: Callable — CombatSystem.resolve() 或测试桩
func compute_turn(planets: Dictionary, connections: Array,
                  resolve_fn: Callable) -> Array[DeploymentCommand]:
    
    var ai_planet_ids := _get_ai_planet_ids(planets)
    if ai_planet_ids.is_empty():
        return []
    
    var commands: Array[DeploymentCommand] = []
    
    # Phase 1: 防御评估
    var defense_commands := _defense_phase(planets, connections, ai_planet_ids, resolve_fn)
    commands.append_array(defense_commands)
    
    # 应用防御指令到工作副本（模拟兵力变化）
    var working_planets := _copy_planets(planets)
    _apply_commands(working_planets, defense_commands)
    
    # Phase 2: 进攻规划
    var offense_commands := _offense_phase(working_planets, connections, ai_planet_ids, resolve_fn)
    commands.append_array(offense_commands)
    
    # Phase 3: 冲突消解
    commands = _resolve_overdraft(commands, planets)
    
    return commands

## --- Phase 1: 防御评估 ---

func _defense_phase(planets: Dictionary, connections: Array,
                    ai_ids: Array, resolve_fn: Callable) -> Array[DeploymentCommand]:
    var commands: Array[DeploymentCommand] = []
    var defended_ids := {}  # 已受援的星球 ID 集合
    
    for planet_id in ai_ids:
        var planet := planets[planet_id]
        var threat_ratio := _calc_threat_ratio(planet_id, planet, planets, connections)
        var def_min := _calc_defense_min(planet)
        
        if threat_ratio > THREAT_HIGH:
            # 高威胁：寻找最近的、非受胁的己方星调兵支援
            var needed := def_min - planet.garrison
            if needed > 0:
                var source := _find_reinforcement_source(planet_id, ai_ids, planets,
                                                          connections, def_min, defended_ids)
                if source != -1:
                    var available := planets[source].garrison - _calc_defense_min(planets[source])
                    var to_send := mini(needed, available)
                    if to_send > 0:
                        var cmd := _make_command(source, planet_id, to_send)
                        commands.append(cmd)
                        defended_ids[source] = true
        
        elif threat_ratio > THREAT_MEDIUM:
            # 中威胁：不从该星进攻
            pass
    
    return commands

## --- Phase 2: 进攻规划 ---

func _offense_phase(planets: Dictionary, connections: Array,
                    ai_ids: Array, resolve_fn: Callable) -> Array[DeploymentCommand]:
    var candidates: Array[Dictionary] = []
    
    for planet_id in ai_ids:
        var planet := planets[planet_id]
        var def_min := _calc_defense_min(planet)
        var spare := planet.garrison - def_min
        
        if spare <= 0:
            continue
        
        # 获取相邻非 AI 星球
        var adjacent := _get_adjacent_planets(planet_id, connections)
        for adj_id in adjacent:
            var target := planets[adj_id]
            if target.owner == DataDef.Faction.ENEMY:
                continue  # 不攻击自己
            
            # 预估战斗结果（尝试全部 3 种兵种）
            for unit_type in [DataDef.UnitType.INFANTRY, DataDef.UnitType.ARCHER, DataDef.UnitType.CAVALRY]:
                var max_send := mini(spare, planet.garrison)
                if max_send <= 0:
                    break
                
                # 预估：发送 spare 兵力时的战斗结果
                var result = resolve_fn.call(planet_id, adj_id, max_send, unit_type, planets)
                if result.attacker_wins:
                    var value := _calc_offense_value(target, result, connections)
                    candidates.append({
                        "from": planet_id,
                        "to": adj_id,
                        "count": max_send,
                        "unit_type": unit_type,
                        "value": value,
                    })
    
    # 按价值降序排序
    candidates.sort_custom(func(a, b): return a.value > b.value)
    
    # 贪心分配
    var commands: Array[DeploymentCommand] = []
    var used_garrison := {}  # planet_id -> 已分配兵力
    
    for cand in candidates:
        var from_id := cand.from
        var planet := planets[from_id]
        var already_used := used_garrison.get(from_id, 0)
        var available := planet.garrison - _calc_defense_min(planet) - already_used
        
        if available >= cand.count:
            var cmd := _make_command(cand.from, cand.to, cand.count, cand.unit_type)
            commands.append(cmd)
            used_garrison[from_id] = already_used + cand.count
    
    return commands

## --- Phase 3: 冲突消解 ---

func _resolve_overdraft(commands: Array[DeploymentCommand],
                        planets: Dictionary) -> Array[DeploymentCommand]:
    # 统计每个出发星的总出兵
    var by_source := {}  # planet_id -> [commands]
    for cmd in commands:
        if not by_source.has(cmd.from_planet):
            by_source[cmd.from_planet] = []
        by_source[cmd.from_planet].append(cmd)
    
    var resolved: Array[DeploymentCommand] = []
    
    for source_id in by_source:
        var cmds: Array = by_source[source_id]
        var total_out := 0
        for c in cmds:
            total_out += c.count
        
        var garrison := planets[source_id].garrison
        if total_out <= garrison:
            resolved.append_array(cmds)
        else:
            # 按 value 排序削减低价值指令
            # （进攻指令已在 Phase 2 按 value 排序，保留防御指令优先）
            var remaining := garrison
            for c in cmds:
                if remaining >= c.count:
                    resolved.append(c)
                    remaining -= c.count
                elif remaining > 0:
                    # 部分削减
                    var trimmed := _make_command(c.from_planet, c.to_planet, remaining, c.unit_type)
                    resolved.append(trimmed)
                    remaining = 0
                # else: 指令完全取消
    
    return resolved

## --- 辅助计算 ---

func _calc_threat_ratio(planet_id: int, planet: Dictionary,
                        planets: Dictionary, connections: Array) -> float:
    var enemy_power := 0.0
    var adjacent := _get_adjacent_planets(planet_id, connections)
    for adj_id in adjacent:
        var adj := planets[adj_id]
        if adj.owner == DataDef.Faction.PLAYER:  # MVP 敌对方为 PLAYER
            enemy_power += adj.garrison
    return enemy_power / (planet.garrison + 1.0)

func _calc_defense_min(planet: Dictionary) -> int:
    return maxi(1, int(planet.max_garrison * DEFENSE_RESERVE_RATIO))

func _calc_offense_value(target: Dictionary, battle_result,
                         connections: Array) -> float:
    var production := target.get("production_rate", 0.0)
    var garrison := target.get("garrison", 0)
    var attr := target.get("attribute", PlanetAttribute.NORMAL)
    var adj_count := _get_adjacent_planets(target.get("id", 0), connections).size()
    
    var efficiency := 0.0
    if battle_result.total_attacker > 0:
        efficiency = float(battle_result.attacker_survived) / float(battle_result.total_attacker)
    
    return (production * VALUE_PRODUCTION_WEIGHT
            + garrison * VALUE_GARRISON_WEIGHT
            + efficiency * VALUE_EFFICIENCY_WEIGHT
            + ATTR_VALUE.get(attr, 0.0)
            + adj_count * VALUE_POSITION_WEIGHT)

## --- 内部工具 ---

func _get_ai_planet_ids(planets: Dictionary) -> Array[int]:
    var ids: Array[int] = []
    for id in planets:
        if planets[id].owner == DataDef.Faction.ENEMY:
            ids.append(id)
    return ids

func _get_adjacent_planets(planet_id: int, connections: Array) -> Array[int]:
    var adj: Array[int] = []
    for conn in connections:
        if conn[0] == planet_id:
            adj.append(conn[1])
        elif conn[1] == planet_id:
            adj.append(conn[0])
    return adj

func _find_reinforcement_source(threatened_id: int, ai_ids: Array,
                                 planets: Dictionary, connections: Array,
                                 def_min: int, defended_ids: Dictionary) -> int:
    # 找最近的非受胁己方星（排除已受援的）
    # 简化：找 garrison > def_min 的最近己方星
    var best_id := -1
    var best_spare := 0
    for id in ai_ids:
        if id == threatened_id or defended_ids.has(id):
            continue
        var planet := planets[id]
        var spare := planet.garrison - _calc_defense_min(planet)
        var threat := _calc_threat_ratio(id, planet, planets, connections)
        if spare > 0 and threat <= THREAT_HIGH:
            if spare > best_spare:
                best_spare = spare
                best_id = id
    return best_id

func _make_command(from: int, to: int, count: int,
                   unit_type: int = DataDef.UnitType.INFANTRY) -> DeploymentCommand:
    var cmd := DeploymentCommand.new()
    cmd.from_planet = from
    cmd.to_planet = to
    cmd.count = count
    cmd.unit_type = unit_type
    cmd.player_owned = false
    return cmd

func _copy_planets(planets: Dictionary) -> Dictionary:
    # 浅拷贝足够（内部 Dictionary 值只读修改 garrison 时覆盖）
    var copy := {}
    for id in planets:
        copy[id] = planets[id].duplicate()
    return copy

func _apply_commands(planets: Dictionary, commands: Array[DeploymentCommand]) -> void:
    for cmd in commands:
        planets[cmd.from_planet].garrison -= cmd.count
```

### 关键实现要点

- `resolve_fn` 通过 Callable 注入 — 测试时传入桩函数，生产时传 `CombatSystem.resolve`
- AI 只读 `planets` 字典（不修改原数据），防御阶段在 `working_planets` 副本上模拟
- `intelligence=1.0` 时的确定性：所有分支基于固定公式和排序，不调用 `randf()`
- 兵种选择：本 Story 在进攻阶段遍历所有 3 种兵种 — Story 002 引入 intelligence 参数做智能/随机选择
- AI 不使用 KingSystem — 无需引用，不调用任何国王相关 API
- `_calc_threat_ratio()` 分母 `+1` 防止除零
- 防御指令优先于进攻指令分配兵力（防御先执行，占领 working_planets 中的 garrison）
- 冲突消解按指令顺序削减 — 高价值进攻指令（先加入）优先保留

### 测试数据构造

```gdscript
var test_planets = {
    1: {"id": 1, "garrison": 10, "max_garrison": 20, "owner": DataDef.Faction.ENEMY,
        "production_rate": 1.0, "attribute": PlanetAttribute.NORMAL},
    2: {"id": 2, "garrison": 6, "max_garrison": 15, "owner": DataDef.Faction.PLAYER,
        "production_rate": 1.0, "attribute": PlanetAttribute.NORMAL},
    3: {"id": 3, "garrison": 8, "max_garrison": 20, "owner": DataDef.Faction.ENEMY,
        "production_rate": 1.5, "attribute": PlanetAttribute.RICH},
}

var test_connections = [[1, 2], [1, 3]]

# 战斗预估桩
func mock_resolve(attacker_id, defender_id, count, unit_type, planets):
    return {"attacker_wins": count > planets[defender_id].garrison,
            "attacker_survived": maxi(0, count - planets[defender_id].garrison),
            "total_attacker": count}
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: AI 参数（aggression/defensiveness/intelligence）可配置、intelligence 控制兵种选择（智能/随机）、TurnManager 步骤 1 集成、PlanetSystem 真实 API 对接、CombatSystem.resolve() 实际调用、测试矩阵
- CombatSystem: `resolve()` 实现（已在 combat-resolution stories 中完成）
- DeploymentCommand: 结构定义（已在 deployment-system stories 中完成）
- 回合管理器: 步骤 1 `_collect_commands()` 调用 AI（已在 Foundation turn-manager 中完成）

---

## QA Test Cases

- **AC-1**: AI 有目标可攻击
  - Given: AI 3星(10/8/5), 玩家 2星(4/6), 相邻
  - When: compute_turn()
  - Then: 返回非空数组; 每条指令 player_owned == false

- **AC-2**: AI 全部 garrison=0
  - Given: AI 2星 garrison 全为 0
  - When: compute_turn()
  - Then: 返回空数组

- **AC-3**: AI 无相邻敌星
  - Given: AI 星无相邻非 AI 星球
  - When: compute_turn()
  - Then: 返回空数组

- **AC-4**: HIGH 威胁触发防御
  - Given: AI星A garrison=3, 相邻玩家星 garrison=10 (threat=10/4=2.5 > 1.0)
  - When: defense_phase
  - Then: 生成防御增援指令（从其他 AI 星向 A 调兵）

- **AC-5**: MEDIUM 威胁不进攻
  - Given: AI星A threat_ratio=0.7 (0.5-1.0)
  - When: offense_phase
  - Then: 不从 A 发起进攻

- **AC-7**: 价值排序贪心分配
  - Given: 2 个进攻候选，value=[8.5, 2.0]
  - When: 贪心分配
  - Then: value=8.5 的目标优先获得兵力

- **AC-8**: 冲突消解
  - Given: AI星A garrison=10, 3条指令总出兵 18
  - When: _resolve_overdraft
  - Then: sum(count) <= 10; 低价值被削减或取消

- **AC-9**: 确定性验证
  - Given: 固定 planets + connections + mock_resolve（始终返回相同结果）
  - When: compute_turn() × 2
  - Then: 两次结果完全相同（指令数量、顺序、from/to/count 一致）

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- Logic: `tests/unit/ai-enemy/ai_engine_core_test.gd` — must exist and pass
- Logic: `tests/unit/ai-enemy/ai_determinism_test.gd` — 确定性专测

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Foundation data-definitions (TR-DEF-002 UnitType, TR-DEF-003 Faction) — must be DONE
- Depends on: Core combat-resolution (TR-CBT-001 resolve 纯函数) — must be DONE（通过 Callable 注入，代码层面松耦合）
- Depends on: Core deployment-system (DeploymentCommand 结构) — must be DONE
- Unlocks: Story 002 (ai-integration)
