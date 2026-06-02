# Story 001: resolve() 纯函数 — 战斗公式与 BattleResult

> **Epic**: 战斗结算 (combat-resolution)
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Estimate**: 2.5h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/combat-resolution.md`
**Requirement**: `TR-CBT-001`, `TR-CBT-002`, `TR-CBT-003`, `TR-CBT-004`, `TR-CBT-005`, `TR-CBT-006`, `TR-CBT-007`, `TR-CBT-008`

**ADR Governing Implementation**: ADR-0006: 战斗公式设计
**ADR Decision Summary**: 比例力量模型——`A_power = count × attack × counter_mult`，`D_power = count × defense × planet_defense_mult`。双方按力量比例承担战损：优势方 `loss_rate = 0.5/power_ratio`，劣势方 `loss_rate = 0.5+0.5×(1-1/ratio)`。`resolve()` 是纯函数——不访问全局状态，同输入永远同输出。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: 纯数学公式，无引擎 API 依赖。`round()` / `max()` / `min()` 是 GDScript 内置函数。

**Control Manifest Rules (this layer)**:
- Required: 战斗公式用比例力量模型 — source: ADR-0006
- Required: `resolve()` 是纯函数 — 不访问全局状态，同输入永远同输出 — source: ADR-0006
- Required: 1v1 等力特例 — 双方各 1 兵且 A_power==D_power → 防守方胜 — source: ADR-0006
- Required: 空星球 → attacker_wins=true, 双方损失=0 — source: ADR-0006
- Required: 最小损失为 1 — `max(1, round(count × loss_rate))` — source: ADR-0006
- Forbidden: 禁止战斗中使用随机数 — source: ADR-0006
- Guardrail: 每场 ~10 浮点运算，MVP 最多 20 场/回合 < 1ms — source: ADR-0006

---

## Acceptance Criteria

*From GDD `design/gdd/combat-resolution.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN 相同参数调用 `resolve()` 两次，WHEN 完成，THEN 返回完全相同的 BattleResult（纯函数验证）
- [ ] **AC-2**: GIVEN 10 步 vs 8 弓（克制+数量优势），WHEN `resolve(10, INFANTRY, 8, ARCHER, NORMAL)`，THEN `attacker_loss < defender_loss`
- [ ] **AC-3**: GIVEN attacker_count=0，WHEN `resolve(0, INFANTRY, 5, ARCHER, NORMAL)`，THEN `attacker_wins == false`, `attacker_loss == 0`
- [ ] **AC-4**: GIVEN defender_count=0，WHEN `resolve(10, INFANTRY, 0, INFANTRY, NORMAL)`，THEN `attacker_wins == true`, `attacker_loss == 0`, `defender_loss == 0`
- [ ] **AC-5**: GIVEN defender_count=0，WHEN `resolve()`，THEN `defender_survived == 0`
- [ ] **AC-6**: GIVEN FORTRESS vs NORMAL（其他条件相同: 10步 vs 10步），WHEN 比较 `defender_loss`，THEN FORTRESS 的 defender_loss 更小
- [ ] **AC-7**: GIVEN 1v1 等力（双方各 1 步兵，NORMAL 星），WHEN `resolve(1, INFANTRY, 1, INFANTRY, NORMAL)`，THEN `attacker_wins == false`（防守方胜特例）
- [ ] **AC-8**: GIVEN 被克制方攻击（弓打步），WHEN `resolve(10, ARCHER, 10, INFANTRY, NORMAL)`，THEN `attacker_loss > defender_loss`（被克方损失更大）
- [ ] **AC-9**: GIVEN 任何合法参数，WHEN `resolve()` 返回，THEN `attacker_survived == attacker_count - attacker_loss` 且均 ≥ 0

---

## Implementation Notes

*Derived from ADR-0006 Implementation Guidelines:*

### BattleResult 结构

```gdscript
# combat_system.gd
class_name BattleResult
extends RefCounted

var attacker_loss: int
var defender_loss: int
var attacker_survived: int
var defender_survived: int
var attacker_wins: bool

func _init(a_loss: int, d_loss: int, a_count: int, d_count: int) -> void:
    attacker_loss = a_loss
    defender_loss = d_loss
    attacker_survived = maxi(0, a_count - a_loss)
    defender_survived = maxi(0, d_count - d_loss)
    attacker_wins = (defender_survived <= 0)
```

### PLANET_DEFENSE_MULT 常量

```gdscript
const PLANET_DEFENSE_MULT: Dictionary = {
    DataDef.PlanetAttribute.NORMAL:   1.0,
    DataDef.PlanetAttribute.RICH:     1.0,
    DataDef.PlanetAttribute.FORTRESS: 1.5,
    DataDef.PlanetAttribute.BARREN:   0.75,
}
```

### resolve() 核心函数

```gdscript
# combat_system.gd
class_name CombatSystem
extends RefCounted

func resolve(
    attacker_count: int,
    attacker_type: int,    # UnitType enum
    defender_count: int,
    defender_type: int,    # UnitType enum
    planet_attribute: int  # PlanetAttribute enum
) -> BattleResult:
    # 边界: 攻击方 0 兵
    if attacker_count <= 0:
        return BattleResult.new(0, 0, 0, defender_count)
    
    # 边界: 防守方 0 兵（空旷星球）
    if defender_count <= 0:
        return BattleResult.new(0, 0, attacker_count, 0)
    
    var attacker_stats = DataDef.unit_stats.get_by_type(attacker_type)
    var defender_stats = DataDef.unit_stats.get_by_type(defender_type)
    
    # 步骤 1: 计算有效战斗力
    var counter_mult := DataDef.DAMAGE_MATRIX[attacker_type][defender_type]
    var terrain_mult := PLANET_DEFENSE_MULT[planet_attribute]
    
    var A_power := float(attacker_count) * attacker_stats.attack * counter_mult
    var D_power := float(defender_count) * defender_stats.defense * terrain_mult
    
    # 步骤 2: 确定优势方
    var min_power := maxf(minf(A_power, D_power), 1.0)
    var power_ratio := maxf(A_power, D_power) / min_power
    var attacker_stronger := (A_power > D_power)
    
    # 1v1 等力特例
    if attacker_count == 1 and defender_count == 1 and is_equal_approx(A_power, D_power):
        return BattleResult.new(1, 0, attacker_count, defender_count)
    
    # 步骤 3: 计算战损比例
    var A_loss_rate: float
    var D_loss_rate: float
    
    if attacker_stronger:
        D_loss_rate = minf(1.0, 0.5 + 0.5 * (1.0 - 1.0 / power_ratio))
        A_loss_rate = 0.5 / power_ratio
    else:
        A_loss_rate = minf(1.0, 0.5 + 0.5 * (1.0 - 1.0 / power_ratio))
        D_loss_rate = 0.5 / power_ratio
    
    # 步骤 4: 整数战损（最小损失 1）
    var A_loss := maxi(1, roundi(attacker_count * A_loss_rate))
    var D_loss := maxi(1, roundi(defender_count * D_loss_rate))
    
    # 损失不超过总兵力
    A_loss = mini(A_loss, attacker_count)
    D_loss = mini(D_loss, defender_count)
    
    return BattleResult.new(A_loss, D_loss, attacker_count, defender_count)
```

### 关键实现要点

- `BattleResult` 使用 `RefCounted` 而非 `Resource`——它是瞬态计算结果，不需要持久化
- `is_equal_approx()` 用于浮点等力比较（避免 `==` 精度问题）
- `minf()` / `maxf()` 用于 float 比较；`maxi()` / `mini()` 用于 int
- `roundi()` 返回 int（Godot 4.x 内置），比 `int(round())` 更清晰
- `PLANET_DEFENSE_MULT` 定义在 CombatSystem 中（不放在 DataDef——只有战斗系统使用这些常量）
- `DataDef.unit_stats.get_by_type(type)` 辅助方法需在 unit-system Story 001 中实现。若尚未实现，本 Story 可直接访问 `DataDef.unit_stats.infantry` 等具名字段
- 所有数学运算显式转为 `float()` 避免整数除法截断
- 战斗力计算不取整——保留浮点精度到战损率计算

### 演算验证（GDD 提供的示例）

**10 步 vs 8 弓，NORMAL 星（步克弓 1.5×）**:
```
A_power = 10 × 10.0 × 1.5 = 150.0
D_power = 8 × 5.0 × 1.0 = 40.0
ratio = 150/40 = 3.75, attacker_stronger

D_loss_rate = 0.5 + 0.5 × (1 - 1/3.75) = 0.5 + 0.5 × 0.733 = 0.867
A_loss_rate = 0.5/3.75 = 0.133

A_loss = max(1, round(10 × 0.133)) = max(1, 1) = 1
D_loss = max(1, round(8 × 0.867)) = max(1, 7) = 7

→ attacker_survived=9, defender_survived=1, attacker_wins=false
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: 36 组合自动化测试矩阵 + 边界测试（0兵/1兵/50兵）
- 回合管理器: 步骤 3 调用 `resolve()` 的快照模型集成
- 占领系统: `BattleResult.attacker_wins` 消费方
- AI 敌人: `resolve()` 预估战斗结果

---

## QA Test Cases

*Derived from GDD acceptance criteria. The developer implements against these.*

- **AC-1**: 纯函数验证
  - Given: `resolve(10, INFANTRY, 8, ARCHER, NORMAL)`
  - When: 连续调用 3 次
  - Then: 3 次结果完全相同（所有字段值相等）
  - Edge cases: 不同参数组合也应各自稳定

- **AC-2**: 克制+数量优势
  - Given: `resolve(10, INFANTRY, 8, ARCHER, NORMAL)`
  - When: 计算结果
  - Then: attacker_loss=1, defender_loss=7, attacker_wins=false（差距不够大）
  - Note: 虽然克制+数量优势，但 10 vs 8 不足以全歼

- **AC-3**: 攻击方 0 兵
  - Given: `resolve(0, INFANTRY, 5, ARCHER, NORMAL)`
  - When: 计算结果
  - Then: attacker_wins=false, attacker_loss=0, defender_loss=0

- **AC-4**: 空旷星球
  - Given: `resolve(10, INFANTRY, 0, INFANTRY, NORMAL)`
  - When: 计算结果
  - Then: attacker_wins=true, attacker_loss=0, defender_loss=0, attacker_survived=10

- **AC-5**: defender_count=0 → defender_survived=0
  - Given: `resolve(5, CAVALRY, 0, INFANTRY, NORMAL)`
  - When: 计算结果
  - Then: defender_survived=0, attacker_wins=true

- **AC-6**: FORTRESS 防守加成
  - Given: `resolve(10, INFANTRY, 10, INFANTRY, FORTRESS)` vs `resolve(10, INFANTRY, 10, INFANTRY, NORMAL)`
  - When: 比较两次 defender_loss
  - Then: FORTRESS 的 defender_loss 更小（防守方损失更少）
  - Edge cases: FORTRESS(1.5) > NORMAL(1.0) → D_power 更大 → 防守方优势

- **AC-7**: 1v1 等力特例
  - Given: `resolve(1, INFANTRY, 1, INFANTRY, NORMAL)`
  - When: 计算结果（A_power = 1×10×1 = 10, D_power = 1×8×1 = 8）

  > ⚠️ 注意：1v1 等力指的是 A_power == D_power。同一兵种时 A_power=10, D_power=8 不等力。需要用自定义参数构造等力场景（如双方都用相同 attack/defense 的兵种）

  - Then: 当 A_power == D_power 时，attacker_wins=false, attacker_survived=0, defender_survived=1
  - Edge cases: 此边界情况需要特殊测试数据构造

- **AC-8**: 被克制方更大损失
  - Given: `resolve(10, ARCHER, 10, INFANTRY, NORMAL)`（弓被步克: counter_mult=0.75）
  - When: 计算结果
  - Then: attacker_loss > defender_loss
  - Edge cases: 若双方都选克制对方的兵种（不可能——三角是单向克制链）

- **AC-9**: 幸存兵力一致性
  - Given: 任意合法输入
  - When: `resolve()` 返回 result
  - Then: `result.attacker_survived == attacker_count - result.attacker_loss` 且 `result.defender_survived == defender_count - result.defender_loss`

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- Logic: `tests/unit/combat-resolution/combat_resolve_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Foundation data-definitions — TR-DEF-002 (UnitType 枚举), TR-DEF-004 (PlanetAttribute 枚举), TR-DEF-006 (DAMAGE_MATRIX), TR-DEF-008 (UnitStats 属性) — must be DONE
- Depends on: unit-system Story 001 (unit_stats.tres 加载) — 兵种 attack/defense 数值必须可用
- Unlocks: Story 002 (combat-test-matrix), occupation-system (消费 BattleResult)
