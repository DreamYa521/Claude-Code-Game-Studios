# Story 002: 克制查询与 MVP 兵种选择

> **Epic**: 兵种系统 (unit-system)
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Estimate**: 1.5h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/unit-system.md`
**Requirement**: `TR-UNT-002`, `TR-UNT-003`, `TR-UNT-005`

**ADR Governing Implementation**: ADR-0006: 战斗公式设计
**ADR Decision Summary**: 三角克制链 INF→ARC→CAV→INF，通过 `DAMAGE_MATRIX[attacker][defender]` 查表返回克制倍率（1.5/1.0/0.75）。`get_counter()` 和 `get_weak_against()` 提供便捷克制查询。MVP 阶段玩家出征默认使用 INFANTRY。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: 纯逻辑函数，无引擎 API 依赖。DAMAGE_MATRIX 是 GDScript `const Dictionary`。

**Control Manifest Rules (this layer)**:
- Required: 战斗公式用比例力量模型 — DAMAGE_MATRIX 是公式的克制乘数来源
- Forbidden: 禁止战斗中使用随机数 — 克制查询是确定性查表
- Guardrail: 克制查询 O(1) Dictionary 查找，不可测量

---

## Acceptance Criteria

*From GDD `design/gdd/unit-system.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN `DAMAGE_MATRIX[INFANTRY][ARCHER]` 查找，WHEN 执行，THEN 返回 1.5（步克弓）
- [ ] **AC-2**: GIVEN `DAMAGE_MATRIX[CAVALRY][INFANTRY]` 查找，WHEN 执行，THEN 返回 1.5（骑克步）
- [ ] **AC-3**: GIVEN `DAMAGE_MATRIX[ARCHER][CAVALRY]` 查找，WHEN 执行，THEN 返回 1.5（弓克骑）
- [ ] **AC-4**: GIVEN 查找 `get_counter(INFANTRY)`，WHEN 执行，THEN 返回 ARCHER
- [ ] **AC-5**: GIVEN 查找 `get_counter(CAVALRY)`，WHEN 执行，THEN 返回 INFANTRY（骑克步，克制目标为步 = 闭环）
- [ ] **AC-6**: GIVEN 查找 `get_weak_against(ARCHER)`，WHEN 执行，THEN 返回 CAVALRY（弓被骑克）
- [ ] **AC-7**: GIVEN 同类型对战 `DAMAGE_MATRIX[INFANTRY][INFANTRY]`，WHEN 执行，THEN 返回 1.0
- [ ] **AC-8**: GIVEN MVP 模式，WHEN 玩家发兵不指定 unit_type，THEN `resolve_deployment()` 默认使用 `UnitType.INFANTRY`

---

## Implementation Notes

*Derived from ADR-0006 Implementation Guidelines:*

### DAMAGE_MATRIX 验证

DAMAGE_MATRIX 常量已在 Foundation data-definitions (TR-DEF-006) 中定义。本 Story 不重复定义——只验证其正确性并通过辅助函数封装访问：

```gdscript
# 常量位置: data_def.gd (Foundation)
# const DAMAGE_MATRIX: Dictionary = {
#     UnitType.INFANTRY: {UnitType.INFANTRY: 1.0, UnitType.ARCHER: 1.5, UnitType.CAVALRY: 0.75},
#     UnitType.ARCHER:   {UnitType.INFANTRY: 0.75, UnitType.ARCHER: 1.0, UnitType.CAVALRY: 1.5},
#     UnitType.CAVALRY:  {UnitType.INFANTRY: 1.5, UnitType.ARCHER: 0.75, UnitType.CAVALRY: 1.0},
# }
```

### 克制查询辅助方法

在 `data_def.gd` 或独立的 `unit_system.gd` 中实现：

```gdscript
# 推荐位置: data_def.gd（与其他数据访问方法一致）
# 或 unit_system.gd autoload（如果兵种系统需要独立 autoload）

func get_counter(type: DataDef.UnitType) -> DataDef.UnitType:
    match type:
        DataDef.UnitType.INFANTRY:
            return DataDef.UnitType.ARCHER
        DataDef.UnitType.ARCHER:
            return DataDef.UnitType.CAVALRY
        DataDef.UnitType.CAVALRY:
            return DataDef.UnitType.INFANTRY
        _:
            return type  # fallback — 不应到达

func get_weak_against(type: DataDef.UnitType) -> DataDef.UnitType:
    match type:
        DataDef.UnitType.INFANTRY:
            return DataDef.UnitType.CAVALRY
        DataDef.UnitType.ARCHER:
            return DataDef.UnitType.INFANTRY
        DataDef.UnitType.CAVALRY:
            return DataDef.UnitType.ARCHER
        _:
            return type
```

### 克制链验证

```gdscript
# 克制链闭环验证（可在 _ready() 中或测试中断言）
func _verify_counter_chain() -> bool:
    for type in [UnitType.INFANTRY, UnitType.ARCHER, UnitType.CAVALRY]:
        var counter = get_counter(type)
        var weak = get_weak_against(counter)
        assert(weak == type, "Counter chain broken at %d" % type)
    return true
```

### MVP 默认兵种规则

在出征系统的 `deploy()` 函数中应用默认值（此逻辑可能在 deployment-system Story 中实现——本 Story 只定义常量）：

```gdscript
# 常量定义 (data_def.gd 或 unit_system.gd)
const MVP_DEFAULT_UNIT_TYPE = DataDef.UnitType.INFANTRY
```

如果出征系统 (deployment-system) 尚未实现，本 Story 仅需：
1. 定义 `MVP_DEFAULT_UNIT_TYPE` 常量
2. 确保 `get_counter()` / `get_weak_against()` 函数可用

### 关键实现要点

- `get_counter()` 和 `get_weak_against()` 是**纯函数**——同输入永远同输出，无副作用
- 克制链必须闭环：`get_counter(get_counter(get_counter(type))) == type`（三步回到原点）
- DAMAGE_MATRIX 非对称（克制 1.5 ≠ 被克 0.75），但逻辑对称：`DAMAGE_MATRIX[A][B] == 1.5` ↔ `DAMAGE_MATRIX[B][A] == 0.75`
- 如果 Foundation data-definitions 尚未定义 `DAMAGE_MATRIX`，本 Story **BLOCKED**——克制查询依赖矩阵数据
- 如果 Foundation data-definitions 已将 `get_counter()` / `get_weak_against()` 作为 DataDef 方法实现，本 Story 降级为**验证 Story**（只写测试，不写新代码）

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: `unit_stats.tres` 创建、UnitStats Resource 实例化、DataDef 加载 .tres
- Foundation data-definitions: `DAMAGE_MATRIX` 常量定义、`UnitType` 枚举定义
- 战斗结算: 使用 DAMAGE_MATRIX 和 UnitStats 进行实际 `resolve()` 计算
- 出征系统: `deploy()` 中的兵种参数传递和 UI
- AI 敌人: 兵种选择策略（TR-AIE-007）

---

## QA Test Cases

*Derived from GDD acceptance criteria. The developer implements against these.*

- **AC-1**: 步克弓 — 克制倍率验证
  - Given: DAMAGE_MATRIX 已定义
  - When: 访问 `DAMAGE_MATRIX[UnitType.INFANTRY][UnitType.ARCHER]`
  - Then: 返回 1.5

- **AC-2**: 骑克步 — 克制倍率验证
  - Given: DAMAGE_MATRIX 已定义
  - When: 访问 `DAMAGE_MATRIX[UnitType.CAVALRY][UnitType.INFANTRY]`
  - Then: 返回 1.5

- **AC-3**: 弓克骑 — 克制倍率验证
  - Given: DAMAGE_MATRIX 已定义
  - When: 访问 `DAMAGE_MATRIX[UnitType.ARCHER][UnitType.CAVALRY]`
  - Then: 返回 1.5

- **AC-4**: get_counter(INFANTRY) → ARCHER
  - Given: `get_counter()` 函数已实现
  - When: 调用 `get_counter(UnitType.INFANTRY)`
  - Then: 返回 `UnitType.ARCHER`
  - Edge cases: 克制链三步闭环验证

- **AC-5**: get_counter(CAVALRY) → INFANTRY
  - Given: `get_counter()` 函数已实现
  - When: 调用 `get_counter(UnitType.CAVALRY)`
  - Then: 返回 `UnitType.INFANTRY`

- **AC-6**: get_weak_against(ARCHER) → CAVALRY
  - Given: `get_weak_against()` 函数已实现
  - When: 调用 `get_weak_against(UnitType.ARCHER)`
  - Then: 返回 `UnitType.CAVALRY`
  - Edge cases: `get_weak_against(get_counter(type)) == type` 对称性

- **AC-7**: 同类型倍率 = 1.0
  - Given: DAMAGE_MATRIX 已定义
  - When: 访问 `DAMAGE_MATRIX[INFANTRY][INFANTRY]`, `[ARCHER][ARCHER]`, `[CAVALRY][CAVALRY]`
  - Then: 全部返回 1.0

- **AC-8**: MVP 默认兵种常量
  - Given: `MVP_DEFAULT_UNIT_TYPE` 常量已定义
  - When: 读取其值
  - Then: 等于 `UnitType.INFANTRY`

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- Logic: `tests/unit/unit-system/unit_counter_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (unit-stats-config) — `unit_stats.tres` 必须可加载
- Also depends on: Foundation data-definitions — TR-DEF-002 (UnitType), TR-DEF-006 (DAMAGE_MATRIX) — must be DONE
- Unlocks: combat-resolution (战斗结算使用克制倍率), ai-enemy (AI 兵种选择), deployment-system (MVP 默认兵种)
