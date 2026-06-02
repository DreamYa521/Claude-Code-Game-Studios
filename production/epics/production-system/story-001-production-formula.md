# Story 001: 累积产量公式与 apply_turn() 核心逻辑

> **Epic**: 生产系统 (production-system)
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Estimate**: 2h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/production-system.md`
**Requirement**: `TR-PRD-001`, `TR-PRD-002`, `TR-PRD-003`, `TR-PRD-005`, `TR-PRD-006`

**ADR Governing Implementation**: ADR-0005: 星球数据模型 (production_rate 字段); ADR-0004: 回合结算模型 (CLEANUP 步骤 5)
**ADR Decision Summary**: 累积产量模型——`accumulated_production += production_rate`，`floor() ≥ 1` 时产兵并扣减累积值。`new_garrison = min(max_garrison, garrison + produced)`。NEUTRAL 星球不产兵，AI 星球使用相同公式。CLEANUP 步骤 5 执行，在占领变更后、国王消耗前。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: 纯数学计算 + Dictionary 读写，无引擎 API 依赖。`floor()` / `min()` 是 GDScript 内置函数。

**Control Manifest Rules (this layer)**:
- Required: 累积产量模型 — `accumulated_production += production_rate`，`floor()≥1` 时产兵 — source: ADR-0005
- Required: 生产在 CLEANUP 步骤 5 执行 — 在占领变更后，确保新占星参与当回合生产 — source: ADR-0004
- Forbidden: 禁止 NEUTRAL 星球产兵 — source: ADR-0005
- Guardrail: 10星遍历 < 0.1ms

---

## Acceptance Criteria

*From GDD `design/gdd/production-system.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN 玩家拥有 2 颗 NORMAL 星（garrison=5, max_garrison=20, production_rate=1.0），WHEN `apply_turn()` 执行，THEN 每颗星 garrison += 1
- [ ] **AC-2**: GIVEN 玩家拥有 1 颗 RICH 星（production_rate=1.5），WHEN 连续 2 回合 `apply_turn()`，THEN 第 1 回合 +1（累积 0.5），第 2 回合 +2（累积 1.0→产出 1，剩余 0.5→再累积 1.5→产出 1... 等等需要验证）

  > ⚠️ 修正计算: RICH rate=1.5。回合1: acc=1.5, floor=1→产1, acc=0.5。回合2: acc=0.5+1.5=2.0, floor=2→产2, acc=0。所以回合1产1，回合2产2。第3回合: acc=0+1.5=1.5, floor=1→产1。模式: 1,2,1,2...

- [ ] **AC-3**: GIVEN 星球 garrison 已达 max_garrison，WHEN `apply_turn()` 执行，THEN garrison 不变
- [ ] **AC-4**: GIVEN 星球 garrison = max_garrison - 1，production_rate = 1.5（本回合应产 2 兵），WHEN `apply_turn()` 执行，THEN garrison = max_garrison（不超出上限，累积值保留溢出部分）
- [ ] **AC-5**: GIVEN 中立星球（owner=NEUTRAL），WHEN `apply_turn()` 执行，THEN garrison 不变，accumulated_production 不变
- [ ] **AC-6**: GIVEN AI 拥有 1 颗 NORMAL 星（garrison=3, production_rate=1.0），WHEN `apply_turn()` 执行，THEN AI 星球 garrison += 1（与玩家相同公式）
- [ ] **AC-7**: GIVEN 星球 garrison < max_garrison 且 accumulated_production 因多回合满上限累积了 3.0，WHEN garrison 降至上限以下后 `apply_turn()`，THEN 一次性产出 floor(3.0)=3 兵（不超出上限）

---

## Implementation Notes

*Derived from ADR-0005 and ADR-0004 Implementation Guidelines:*

### 核心函数

```gdscript
# production_system.gd
func apply_turn(planets: Dictionary) -> int:
    var total_produced := 0
    for planet_id in planets:
        var planet = planets[planet_id]
        
        # 跳过中立星球
        if planet.owner == DataDef.Faction.NEUTRAL:
            continue
        
        # 累积产量
        planet.accumulated_production += planet.production_rate
        var produced := floori(planet.accumulated_production)
        
        if produced >= 1:
            # 不超出驻兵上限
            var space := planet.max_garrison - planet.garrison
            var actual := mini(produced, space)
            
            if actual > 0:
                planet.garrison += actual
                total_produced += actual
            
            # 扣除已产出的累积值（含被上限截断的部分）
            planet.accumulated_production -= produced
        
        # 若 produced >= 1 但 space <= 0，累积值保留等待 garrison 下降
    
    return total_produced
```

### 关键实现要点

- `accumulated_production` 字段由 Story 002 添加到 RuntimePlanetData。本 Story 假设该字段已存在（通过 `planets` Dictionary 参数传入）
- 使用 `floori()` 返回 int（Godot 4.x 内置），避免 float→int 隐式转换警告
- `total_produced` 返回值供 UI 显示"本回合产出 N 兵"（MVP 可选）
- 遍历所有非 NEUTRAL 星球——不区分 PLAYER/ENEMY，统一公式
- 驻兵达上限时 `accumulated_production` 继续累积，不归零——保证上限解除后一次性产出
- 上限截断时 `accumulated_production -= produced`（不是 `-= actual`）——截断部分视为"已生产但无法容纳"，不退回累积池
- 本 Story 实现为独立函数，不依赖 autoload 或场景树——纯数据操作，可直接单元测试

### 测试数据构造

测试时直接构造模拟 Dictionary（无需完整 PlanetSystem）：

```gdscript
var test_planets = {
    1: {"garrison": 5, "max_garrison": 20, "production_rate": 1.0, "accumulated_production": 0.0, "owner": DataDef.Faction.PLAYER},
    2: {"garrison": 20, "max_garrison": 20, "production_rate": 1.0, "accumulated_production": 0.0, "owner": DataDef.Faction.PLAYER},
}
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: `accumulated_production` 字段添加到 RuntimePlanetData（修改 PlanetSystem）、`apply_turn()` 与 TurnManager CLEANUP 步骤 5 的集成、EventBus 广播
- 回合管理器: CLEANUP 步骤 5 的调用方代码
- 星球系统: `get_planets_by_owner()` / `update_garrison()` 调用（本 Story 直接操作 Dictionary 做纯逻辑验证）

---

## QA Test Cases

*Derived from GDD acceptance criteria. The developer implements against these.*

- **AC-1**: NORMAL 星基本生产
  - Given: 2 颗 NORMAL 星，garrison=5, max=20, rate=1.0, acc=0, owner=PLAYER
  - When: `apply_turn(planets)`
  - Then: 两颗星 garrison 都 = 6, acc 都 = 0.0, total_produced = 2

- **AC-2**: RICH 星累积取整
  - Given: 1 颗 RICH 星，garrison=5, max=20, rate=1.5, acc=0, owner=PLAYER
  - When: 第1次 `apply_turn()` → 第2次 `apply_turn()`
  - Then: 第1次后 garrison=6, acc=0.5; 第2次后 garrison=8, acc=0.0
  - Edge cases: 第3次 → garrison=9, acc=0.5

- **AC-3**: 驻兵已达上限
  - Given: 1 颗星，garrison=20, max=20, rate=1.0, acc=0, owner=PLAYER
  - When: `apply_turn(planets)`
  - Then: garrison 仍 = 20, acc = 1.0（累积但无法产出）

- **AC-4**: 上限截断
  - Given: garrison=19, max=20, rate=1.5, acc=0（第2回合场景，将产2兵）
  - When: `apply_turn(planets)`
  - Then: garrison=20, acc=0.5（溢出部分不退回，计为已生产但无法容纳）

- **AC-5**: 中立星球不产兵
  - Given: 1 颗 NEUTRAL 星 + 1 颗 PLAYER 星
  - When: `apply_turn(planets)`
  - Then: NEUTRAL 星 garrison 和 acc 不变；PLAYER 星正常生产

- **AC-6**: AI 星球同等生产
  - Given: 1 颗 ENEMY 星 + 1 颗 PLAYER 星，条件相同（rate=1.0, garrison=3）
  - When: `apply_turn(planets)`
  - Then: 两颗星 garrison 增幅相同（都 +1）

- **AC-7**: 累积释放
  - Given: garrison=18, max=20, rate=1.0, acc=3.0（模拟满上限积压 3 回合）
  - When: `apply_turn(planets)`
  - Then: garrison=20（+2，因为 space=2）, acc=1.0（3.0+1.0-3.0=1.0，截断的1兵不退回）

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- Logic: `tests/unit/production-system/production_formula_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Foundation data-definitions (TR-DEF-003 Faction 枚举) — must be DONE
- Depends on: Foundation gamestate-manager (TR-GSM-004 is_playing) — 仅集成时需要，本 Story 纯逻辑不需要
- Unlocks: Story 002 (production-integration)
