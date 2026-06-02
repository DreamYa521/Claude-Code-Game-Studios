# Story 002: accumulated_production 字段集成与回合管线接入

> **Epic**: 生产系统 (production-system)
> **Status**: Ready
> **Layer**: Core
> **Type**: Integration
> **Estimate**: 1.5h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/production-system.md`
**Requirement**: `TR-PRD-004`

**ADR Governing Implementation**: ADR-0005: 星球数据模型 (RuntimePlanetData 字段扩展); ADR-0004: 回合结算模型 (CLEANUP 步骤 5 集成点)
**ADR Decision Summary**: `accumulated_production` 存储在 RuntimePlanetData 中（新增第 10 个字段，初始值 0.0）。生产系统在 TurnManager CLEANUP 步骤 5 被调用，传入 `PlanetSystem` 的内部 `_planets` Dictionary 引用以直接修改（避免通过 `update_garrison()` 逐星调用的 O(N²) 开销）。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Dictionary 动态字段无 Schema 约束——添加新 key 不需要修改类定义。GDScript 允许直接 `planet.accumulated_production = 0.0`。

**Control Manifest Rules (this layer)**:
- Required: 累积产量模型 — `accumulated_production += production_rate` — source: ADR-0005
- Required: 生产在 CLEANUP 步骤 5 执行 — 在占领变更后 — source: ADR-0004
- Forbidden: 禁止 Resource 用于运行时星球数据 — accumulated_production 放在 Dictionary 中 — source: ADR-0005
- Guardrail: `apply_turn()` 在 CLEANUP 中调用，总耗时 < 0.1ms（10星）

---

## Acceptance Criteria

*From GDD `design/gdd/production-system.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN 星球系统 `init_from_level()` 完成，WHEN 检查 RuntimePlanetData，THEN 每个星球包含 `accumulated_production` 字段且初始值为 0.0
- [ ] **AC-2**: GIVEN 生产系统 `apply_turn()` 执行后，WHEN 读取星球的 `accumulated_production`，THEN 值已按累积公式更新（非负浮点数）
- [ ] **AC-3**: GIVEN TurnManager CLEANUP 步骤 5，WHEN 检查执行顺序，THEN 生产在占领变更（步骤 4）之后执行
- [ ] **AC-4**: GIVEN 刚被占领的星球（步骤 4 归属变更），WHEN `apply_turn()` 在步骤 5 执行，THEN 该星参与生产（新 owner 受益）
- [ ] **AC-5**: GIVEN 刚丢失的星球，WHEN `apply_turn()` 在步骤 5 执行，THEN 该星不产兵（旧 owner 不再拥有）

---

## Implementation Notes

*Derived from ADR-0005 and ADR-0004 Implementation Guidelines:*

### 1. 扩展 RuntimePlanetData

在 `planet_system.gd` 的 `_build_runtime_planet()` 中添加第 10 个字段：

```gdscript
func _build_runtime_planet(def: PlanetDef) -> Dictionary:
    return {
        "id": def.id,
        "name": def.name,
        "position": def.position,
        "attribute": def.attribute,
        "garrison": 0,
        "owner": DataDef.Faction.NEUTRAL,
        "max_garrison": int(DataDef.GARRISON_DEFAULT_MAX * ATTR_GARRISON_MULT[def.attribute]),
        "production_rate": DataDef.PRODUCTION_BASE_RATE * ATTR_PRODUCTION_MULT[def.attribute],
        "adjacent_ids": [],
        "accumulated_production": 0.0,   # 新增: 累积产量浮点
    }
```

### 2. 更新 PlanetSystem 字段文档

在 `planet_system.gd` 头部注释中将 RuntimePlanetData 字段数从 9 更新为 10：

```gdscript
# RuntimePlanetData Dictionary 字段（共 10 个）:
#   - id, name, position, attribute, garrison, owner,
#     max_garrison, production_rate, adjacent_ids, accumulated_production
```

### 3. ProductionSystem 集成

`production_system.gd` 在 CLEANUP 步骤被 TurnManager 调用：

```gdscript
# production_system.gd
class_name ProductionSystem
extends RefCounted

func apply_turn(planets: Dictionary) -> int:
    # ... (Story 001 实现的逻辑)
```

### 4. TurnManager 集成点

在 `turn_manager.gd` 的 `_cleanup()` 方法中：

```gdscript
func _cleanup() -> void:
    # 步骤 4: 应用战斗结果 + 占领变更 (由 OccupationSystem 处理)
    # ... (已在 OccupationSystem/TurnManager 中实现)
    
    # 步骤 5a: 生产
    var total_produced := _production_system.apply_turn(_planet_system._planets)
    
    # 步骤 5b: 国王消耗
    # ... (由 KingSystem 处理)
    
    # 步骤 5c: 胜负判定
    # ... (由 WinConditions 处理)
```

### 关键实现要点

- `accumulated_production` 初始值 `0.0`（float），不是 `0`（int）——避免后续 `+= production_rate` 时的类型升级
- PlanetSystem 的 `take_snapshot()` 必须包含 `accumulated_production` 字段——深拷贝 Dictionary 自动处理新字段
- `PlanetSystem.update_garrison()` 阶段 gate 允许在 CLEANUP 阶段修改（已在 planet-system 中实现）
- ProductionSystem 直接操作 `_planets` Dictionary 引用——不通过 `update_garrison()` 逐星调用（性能优化 + 避免逐星阶段 gate 检查开销）
- 若 `planet` Dictionary 缺少 `accumulated_production` 字段（旧存档兼容），使用 `planet.get("accumulated_production", 0.0)` 防御
- TurnManager 中 `_production_system` 在 `_ready()` 中构造：`_production_system = ProductionSystem.new()`

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: `apply_turn()` 核心算法（累积取整、上限截断、NEUTRAL 跳过）
- TurnManager: CLEANUP 步骤 3（战斗计算）、步骤 4（占领应用）——这些由 combat-resolution + occupation-system 实现
- KingSystem: CLEANUP 步骤 5b 国王寿命消耗
- WinConditions: CLEANUP 步骤 5c 胜负判定

---

## QA Test Cases

*Derived from GDD acceptance criteria. The developer implements against these.*

- **AC-1**: RuntimePlanetData 包含 accumulated_production
  - Given: LevelData 含 1 个 PlanetDef
  - When: `init_from_level(level_data)` 完成
  - Then: `_planets[1].accumulated_production == 0.0`（不是 null 或 0）
  - Edge cases: 所有星球初始化后该字段都存在

- **AC-2**: apply_turn() 后累积值正确
  - Given: 1 颗 NORMAL 星，acc=0, rate=1.0
  - When: `apply_turn()` 执行
  - Then: garrison += 1, acc = 0.0（floor(1.0)=1 全部产出）
  - Edge cases: rate=0.5 → acc=0.5, garrison 不变

- **AC-3**: 步骤 4→5 顺序正确
  - Given: 星球 A 在步骤 4 从 ENEMY 转给 PLAYER
  - When: 步骤 5 `apply_turn()` 执行
  - Then: 星球 A 为 PLAYER 生产（以新 owner 身份参与）
  - Edge cases: 验证步骤 4 丢失的星球不参与步骤 5 生产

- **AC-4**: 新占星当回合生产
  - Given: 回合开始时星球 A owner=ENEMY, garrison=3；玩家攻下后步骤 4 owner→PLAYER
  - When: 步骤 5 执行
  - Then: 星球 A 按 PLAYER 身份生产
  - Edge cases: 新占星 accumulated_production 从 0 开始

- **AC-5**: 丢失星不生产
  - Given: 回合开始时星球 B owner=PLAYER；被 AI 攻下后步骤 4 owner→ENEMY
  - When: 步骤 5 执行
  - Then: 星球 B 不参与 PLAYER 生产遍历

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- Integration: `tests/integration/production-system/production_pipeline_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (production-formula) — `apply_turn()` 核心逻辑必须 DONE
- Depends on: planet-system (TR-PLT-001 `_build_runtime_planet()`, TR-PLT-005 `update_garrison()` 阶段 gate, TR-PLT-009 `take_snapshot()`) — must be DONE
- Depends on: occupation-system (步骤 4 占领变更) — must be DONE（若未完成则本 Story 的 AC-3/4/5 无法验证）
- Unlocks: TurnManager CLEANUP 步骤 5 完整集成
