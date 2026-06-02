# Story 002: 36 组合测试矩阵与边界覆盖

> **Epic**: 战斗结算 (combat-resolution)
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Estimate**: 2h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/combat-resolution.md`
**Requirement**: `TR-CBT-009`

**ADR Governing Implementation**: ADR-0006: 战斗公式设计
**ADR Decision Summary**: 单元测试覆盖 3×3×4=36 组合（兵种A × 兵种D × 星球属性）+ 边界（0兵/1兵/50兵）。36 组合覆盖全部克制/被克/同类型 + 全部地形场景。边界测试覆盖空输入、极小值、极大值、等力特例。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: GUT (Godot Unit Testing) 框架。测试必须可在 headless 模式运行：`godot --headless --script tests/gdunit4_runner.gd`。

**Control Manifest Rules (this layer)**:
- Required: 战斗公式用比例力量模型 — 测试验证公式正确性 — source: ADR-0006
- Required: `resolve()` 是纯函数 — 所有测试必须确定性通过 — source: ADR-0006
- Forbidden: 禁止战斗中使用随机数 — 测试不需要随机种子 — source: ADR-0006

---

## Acceptance Criteria

*From GDD `design/gdd/combat-resolution.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN 36 种组合测试（兵种A × 兵种D × 星球属性），WHEN 运行测试套件，THEN 全部通过
- [ ] **AC-2**: GIVEN 边界测试（attacker_count=0 / defender_count=0），WHEN 运行，THEN 返回预期边界值
- [ ] **AC-3**: GIVEN 双方各 1 兵测试（3×3=9 种兵种组合），WHEN 运行，THEN 等力特例正确触发
- [ ] **AC-4**: GIVEN 50 兵大数值测试，WHEN 运行，THEN 无浮点溢出，战损不超过总兵力
- [ ] **AC-5**: GIVEN 测试 `resolve()` 在不同调用顺序下，WHEN 同一参数多次调用，THEN 结果不变（纯函数验证）
- [ ] **AC-6**: GIVEN 全部测试，WHEN `godot --headless --script tests/gdunit4_runner.gd` 执行，THEN 无测试失败

---

## Implementation Notes

*Derived from ADR-0006 Testing Requirements:*

### 测试文件结构

```
tests/unit/combat-resolution/
├── combat_resolve_test.gd          # Story 001 的基本测试（AC-1~9）
├── combat_matrix_test.gd           # 本 Story: 36 组合参数化测试
└── combat_boundary_test.gd         # 本 Story: 边界测试
```

### 36 组合矩阵

使用 GUT 参数化测试覆盖全部组合：

```gdscript
# combat_matrix_test.gd
extends GutTest

const UNIT_TYPES = [
    DataDef.UnitType.INFANTRY,
    DataDef.UnitType.ARCHER,
    DataDef.UnitType.CAVALRY,
]

const PLANET_ATTRS = [
    DataDef.PlanetAttribute.NORMAL,
    DataDef.PlanetAttribute.RICH,
    DataDef.PlanetAttribute.FORTRESS,
    DataDef.PlanetAttribute.BARREN,
]

var _combat: CombatSystem

func before_all() -> void:
    _combat = CombatSystem.new()

func test_36_combinations(param_a_type=use_parameters(UNIT_TYPES),
                          param_d_type=use_parameters(UNIT_TYPES),
                          param_attr=use_parameters(PLANET_ATTRS)) -> void:
    var result := _combat.resolve(10, param_a_type, 10, param_d_type, param_attr)
    
    # 验证核心不变式
    assert_between(result.attacker_loss, 1, 10)  # min loss=1, max=count
    assert_between(result.defender_loss, 1, 10)
    assert_eq(result.attacker_survived, 10 - result.attacker_loss)
    assert_eq(result.defender_survived, 10 - result.defender_loss)
    
    # 克制关系验证
    var counter_mult := DataDef.DAMAGE_MATRIX[param_a_type][param_d_type]
    if counter_mult > 1.0:
        # 克制方应有优势
        assert_lt(result.attacker_loss, result.defender_loss,
            "克制方 (%d→%d) 应有更少损失" % [param_a_type, param_d_type])

func test_fortress_defense_bonus() -> void:
    var result_normal := _combat.resolve(10, UNIT_TYPES[0], 10, UNIT_TYPES[0],
        DataDef.PlanetAttribute.NORMAL)
    var result_fortress := _combat.resolve(10, UNIT_TYPES[0], 10, UNIT_TYPES[0],
        DataDef.PlanetAttribute.FORTRESS)
    
    # FORTRESS 防守方损失更小
    assert_lt(result_fortress.defender_loss, result_normal.defender_loss,
        "FORTRESS 防守方损失应小于 NORMAL")
```

### 边界测试

```gdscript
# combat_boundary_test.gd
extends GutTest

var _combat: CombatSystem

func before_all() -> void:
    _combat = CombatSystem.new()

# --- 零兵力边界 ---

func test_zero_attacker() -> void:
    var r := _combat.resolve(0, DataDef.UnitType.INFANTRY, 5,
        DataDef.UnitType.ARCHER, DataDef.PlanetAttribute.NORMAL)
    assert_false(r.attacker_wins)
    assert_eq(r.attacker_loss, 0)
    assert_eq(r.defender_loss, 0)
    assert_eq(r.attacker_survived, 0)
    assert_eq(r.defender_survived, 5)

func test_zero_defender() -> void:
    var r := _combat.resolve(10, DataDef.UnitType.INFANTRY, 0,
        DataDef.UnitType.INFANTRY, DataDef.PlanetAttribute.NORMAL)
    assert_true(r.attacker_wins)
    assert_eq(r.attacker_loss, 0)
    assert_eq(r.defender_loss, 0)

# --- 极小兵力 ---

func test_one_vs_one_all_combos(param_a=use_parameters(UNIT_TYPES),
                                 param_d=use_parameters(UNIT_TYPES)) -> void:
    var r := _combat.resolve(1, param_a, 1, param_d, DataDef.PlanetAttribute.NORMAL)
    
    # 不变式：损失不超过兵力
    assert_between(r.attacker_loss, 0, 1)
    assert_between(r.defender_loss, 0, 1)
    assert_eq(r.attacker_survived, 1 - r.attacker_loss)
    assert_eq(r.defender_survived, 1 - r.defender_loss)

# --- 大数值 ---

func test_large_count_50() -> void:
    var r := _combat.resolve(50, DataDef.UnitType.INFANTRY, 50,
        DataDef.UnitType.ARCHER, DataDef.PlanetAttribute.NORMAL)
    assert_between(r.attacker_loss, 1, 50)
    assert_between(r.defender_loss, 1, 50)
    assert_eq(r.attacker_survived + r.attacker_loss, 50)
    assert_eq(r.defender_survived + r.defender_loss, 50)

# --- 纯函数验证 ---

func test_pure_function_consistency() -> void:
    var params := [10, DataDef.UnitType.CAVALRY, 15, DataDef.UnitType.INFANTRY,
        DataDef.PlanetAttribute.FORTRESS]
    var first := _combat.resolve(params[0], params[1], params[2], params[3], params[4])
    for i in range(10):
        var again := _combat.resolve(params[0], params[1], params[2], params[3], params[4])
        assert_eq(again.attacker_loss, first.attacker_loss)
        assert_eq(again.defender_loss, first.defender_loss)
        assert_eq(again.attacker_wins, first.attacker_wins)

# --- 大数值碾压 ---

func test_overwhelming_force() -> void:
    # 100 步 vs 1 弓（步克弓，100×10×1.5=1500 vs 1×5×1=5, ratio=300）
    var r := _combat.resolve(100, DataDef.UnitType.INFANTRY, 1,
        DataDef.UnitType.ARCHER, DataDef.PlanetAttribute.NORMAL)
    assert_eq(r.attacker_loss, 1)   # 优势方最小损失
    assert_eq(r.defender_loss, 1)   # 防守方全灭
    assert_true(r.attacker_wins)
```

### 关键实现要点

- 使用 GUT 的 `use_parameters()` 实现参数化测试——36 组合在一个测试函数中覆盖
- 每个测试验证**不变式**而非具体数值——具体数值在演算示例中验证（Story 001）
- `assert_between()` 验证值在合法范围内
- 大数值测试（50/100 兵）验证无浮点溢出和整数截断错误
- 纯函数一致性测试多次调用验证确定性
- 测试文件命名：`combat_matrix_test.gd` + `combat_boundary_test.gd`
- GUT 配置 (`gutconfig.json`) 应包含 `"include_subdirs": true` 以发现所有测试

### 覆盖清单

| 维度 | 覆盖 |
|------|------|
| 兵种A × 兵种D | 3×3 = 9 种（克制/被克/同类型） |
| 星球属性 | 4 种（NORMAL/RICH/FORTRESS/BARREN） |
| 总组合 | 9 × 4 = 36 |
| 边界: 0 兵 | attacker=0, defender=0, 双方=0 |
| 边界: 1 兵 | 3×3=9 种兵种组合 |
| 边界: 大数值 | 50 兵, 100 兵 |
| 纯函数 | 同参数 10 次调用一致性 |
| 防守加成 | NORMAL vs FORTRESS 对比 |

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: `resolve()` 函数实现、BattleResult 类——本 Story 只写测试，不修改实现
- combat-resolution 之外的测试（回合集成、占领集成）——由各系统自己的 Story 覆盖

---

## QA Test Cases

*Derived from GDD acceptance criteria. The developer implements against these.*

- **AC-1**: 36 组合全部通过
  - Given: `use_parameters(UNIT_TYPES)` × `use_parameters(UNIT_TYPES)` × `use_parameters(PLANET_ATTRS)`
  - When: `godot --headless --script tests/gdunit4_runner.gd`
  - Then: 36 个参数化测试全部 PASS
  - Edge cases: 每个组合验证 invariants（损失范围、幸存一致性）

- **AC-2**: 零兵力边界
  - Given: attacker_count=0 或 defender_count=0
  - When: 运行边界测试
  - Then: 返回值匹配边界规则（空攻→false/0损失; 空防→true/0损失）

- **AC-3**: 1v1 全兵种组合
  - Given: attacker_count=1, defender_count=1
  - When: 遍历 3×3 兵种组合
  - Then: 等力特例正确触发，损失 ≤ 1

- **AC-4**: 大数值无溢出
  - Given: attacker_count=50, defender_count=50
  - When: 遍历全部兵种组合 + 星球属性
  - Then: 损失 ≤ 总兵力，无负数，无 NaN

- **AC-5**: 纯函数确定性
  - Given: 任意参数组合
  - When: 连续 10 次调用 `resolve()`
  - Then: 每次结果完全相同

- **AC-6**: Headless 全量通过
  - Given: 完整的测试文件 `combat_matrix_test.gd` + `combat_boundary_test.gd`
  - When: `godot --headless --script tests/gdunit4_runner.gd`
  - Then: exit code = 0，无 FAILED

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- Logic: `tests/unit/combat-resolution/combat_matrix_test.gd` — must exist and pass
- Logic: `tests/unit/combat-resolution/combat_boundary_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (combat-resolve-function) — `resolve()` 函数必须 DONE 且通过基本测试
- Depends on: Foundation data-definitions (TR-DEF-002, TR-DEF-004, TR-DEF-006) — 枚举和矩阵必须可用
- Depends on: unit-system Story 001 (unit_stats.tres) — 兵种 attack/defense 数值必须可访问
- Depends on: Foundation test-setup — GUT 框架已配置 (`tests/gdunit4_runner.gd`, `gutconfig.json`)
- Unlocks: combat-resolution epic 完成 gate
