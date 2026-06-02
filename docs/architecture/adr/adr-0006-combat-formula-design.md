# ADR-0006: 战斗公式设计

## Status
Accepted

## Date
2026-05-31

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core (战斗结算) |
| **Knowledge Risk** | LOW — 纯数学公式，无引擎 API 依赖 |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/architecture/architecture.md` Phase 3 场景 3, ADR-0002 (UnitStats/DataDef), ADR-0005 (PlanetAttribute 防守加成) |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | None |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0002 (UnitStats attack/defense 数值, DAMAGE_MATRIX), ADR-0004 (快照模型 — 战斗只读快照), ADR-0005 (planet_bonus 防守加成) |
| **Enables** | 兵种系统 GDD, 战斗结算 GDD, 占领系统 GDD, AI 敌人 GDD |
| **Blocks** | 兵种系统 GDD, 战斗结算 GDD, 占领系统 GDD, AI 敌人 GDD |
| **Ordering Note** | 必须在兵种系统和战斗结算 GDD 之前 Accepted |

## Context

### Problem Statement

玩家发兵攻击敌方星球时，系统需要计算战斗结果：双方各损失多少兵力、攻击方是否获胜。公式必须同时满足：

1. **策略可预测** — 玩家看一眼大致能判断输赢（不需要按计算器）
2. **克制有意义** — 步→弓→骑→步的三角关系必须在数值上体现
3. **防守有优势** — 攻打有驻兵的星球比空旷星球更难（尤其 FORTRESS 属性）
4. **确定性** — 同样的输入 → 同样的输出（无随机数）
5. **可测试** — 公式拆出纯函数，单元测试可覆盖各种场景

### Constraints

- 兵种只有 3 种（步/弓/骑），MVP 不扩展
- 攻击方兵力来自一颗出发星，防守方兵力是目标星驻兵
- 战斗是 1v1（一条指令 = 一场独立战斗），不存在多方混战（ADR-0004 已拒绝）
- 所有计算基于快照（ADR-0004 步骤 3），不读实时星球状态
- 整数兵力 — 不会有 3.7 个兵

### Requirements

- 公式接受：`(attacker_count, attacker_type, defender_count, defender_type, planet_attribute)`
- 公式返回：`BattleResult { attacker_loss, defender_loss, attacker_survived, defender_survived, attacker_wins }`
- 结果确定 — 同输入永远同输出
- 克制方（1.5×）有明显优势 — 同等兵力下克制方胜
- FORTRESS 属性防守方有显著加成
- 不存在除零错误（空星球、零兵力边界处理）

## Decision

**使用比例力量模型（Proportional Strength Model）。战斗力 = 兵力 × 攻击/防御 × 克制倍率 × 地形加成。双方按力量比例承担战损。**

### 核心公式

```
步骤 1: 计算有效战斗力
────────────────────────────────────────
A_power = attacker_count × A_attack × counter_mult[A_type][D_type]
D_power = defender_count × D_defense × planet_defense_mult[planet_attr]

步骤 2: 确定优势方
────────────────────────────────────────
power_ratio = max(A_power, D_power) / max(min(A_power, D_power), 1)
// power_ratio ≥ 1.0; 越大 = 越碾压

attacker_stronger = (A_power > D_power)

步骤 3: 计算战损比例
────────────────────────────────────────
// 优势方战损率: 随 ratio 增大趋近 0
// 劣势方战损率: 随 ratio 增大趋近 1

if attacker_stronger:
    D_loss_rate = min(1.0, 0.5 + 0.5 × (1.0 - 1.0/power_ratio))
    A_loss_rate = 0.5 / power_ratio
else:
    A_loss_rate = min(1.0, 0.5 + 0.5 × (1.0 - 1.0/power_ratio))
    D_loss_rate = 0.5 / power_ratio

步骤 4: 转换为实际损失
────────────────────────────────────────
attacker_loss = max(1, round(attacker_count × A_loss_rate))
defender_loss = max(1, round(defender_count × D_loss_rate))
// max(1, ...) 确保只要兵力 > 0 至少损失 1（避免零伤亡）

attacker_loss = min(attacker_loss, attacker_count)
defender_loss = min(defender_loss, defender_count)

步骤 5: 判定胜负
────────────────────────────────────────
attacker_survived = attacker_count - attacker_loss
defender_survived = defender_count - defender_loss
attacker_wins = (defender_survived <= 0)
```

### 常量定义

```gdscript
# combat_system.gd
# 克制倍率 — 引用 DataDef.DAMAGE_MATRIX
# | A\D  | INF  | ARC  | CAV  |
# | INF  | 1.0  | 1.5  | 0.75 |
# | ARC  | 0.75 | 1.0  | 1.5  |
# | CAV  | 1.5  | 0.75 | 1.0  |

# 星球防守加成
const PLANET_DEFENSE_MULT: Dictionary = {
    DataDef.PlanetAttribute.NORMAL:   1.0,
    DataDef.PlanetAttribute.RICH:     1.0,   # 富星产出高但防守无加成
    DataDef.PlanetAttribute.FORTRESS: 1.5,   # 要塞星——防守显著增强
    DataDef.PlanetAttribute.BARREN:   0.75,  # 不毛星——防守弱势
}

# 基础战损率 — 双方等力量时的损失比例
const BASE_LOSS_RATE: float = 0.5
```

### 战损曲线特性

power_ratio = 1.0 (势均力敌):
  → 双方各损失约 50%
  → 攻击方不赢（除非防守方只有 1 兵）

power_ratio = 2.0 (一方强两倍):
  → 强方损失 ~25%, 弱方损失 ~75%
  → 进攻方需要在数量或克制上有明显优势才能赢

power_ratio = 4.0 (一方强四倍):
  → 强方损失 ~12.5%, 弱方损失 ~87.5%
  → 强方稳赢

power_ratio → ∞ (碾压):
  → 弱方全灭, 强方仅损失 1（max(1, ...) 规则）

### 演算示例

**例 1: 均势 — 10 步兵 vs 10 步兵，NORMAL 星**
```
A_power = 10 × 10.0 × 1.0 = 100.0
D_power = 10 × 8.0 × 1.0  = 80.0
power_ratio = 100/80 = 1.25
attacker_stronger = true

D_loss_rate = 0.5 + 0.5 × (1.0 - 1.0/1.25) = 0.5 + 0.5 × 0.2 = 0.6
A_loss_rate = 0.5 / 1.25 = 0.4

A_loss = round(10 × 0.4) = 4
D_loss = round(10 × 0.6) = 6

结果: A 剩 6, D 剩 4, attacker_wins = false
```

**例 2: 克制 — 10 步兵 vs 8 弓兵，NORMAL 星**
```
A_power = 10 × 10.0 × 1.5 = 150.0    ← 步克弓
D_power = 8 × 5.0 × 1.0  = 40.0
power_ratio = 150/40 = 3.75
attacker_stronger = true

D_loss_rate = 0.5 + 0.5 × (1.0 - 1.0/3.75) = 0.5 + 0.5 × 0.733 = 0.867
A_loss_rate = 0.5 / 3.75 = 0.133

A_loss = round(10 × 0.133) = 1
D_loss = round(8 × 0.867) = 7

结果: A 剩 9, D 剩 1, attacker_wins = false
→ 克制带来显著优势但未全歼。需再补一轮。
```

**例 3: 数量碾压 — 20 步兵 vs 5 弓兵，NORMAL 星**
```
A_power = 20 × 10.0 × 1.5 = 300.0
D_power = 5 × 5.0 × 1.0   = 25.0
power_ratio = 300/25 = 12.0
attacker_stronger = true

D_loss_rate = 0.5 + 0.5 × (1.0 - 1.0/12.0) = 0.5 + 0.5 × 0.917 = 0.958
A_loss_rate = 0.5 / 12.0 = 0.042

A_loss = round(20 × 0.042) = 1
D_loss = round(5 × 0.958) = 5

结果: A 剩 19, D 剩 0, attacker_wins = true ✓
```

**例 4: FORTRESS — 10 步兵 vs 8 步兵，FORTRESS 星**
```
A_power = 10 × 10.0 × 1.0 = 100.0
D_power = 8 × 8.0 × 1.5  = 96.0     ← FORTRESS +50% 防守
power_ratio = 100/96 = 1.042
attacker_stronger = true  (但优势极小)

D_loss_rate = 0.5 + 0.5 × (1.0 - 1.0/1.042) = 0.5 + 0.5 × 0.04 = 0.52
A_loss_rate = 0.5 / 1.042 = 0.48

A_loss = round(10 × 0.48) = 5
D_loss = round(8 × 0.52) = 4

结果: A 剩 5, D 剩 4, attacker_wins = false
→ 同等兵力下 FORTRESS 几乎抹平攻击方数量优势。需要更多兵或克制。
```

### 关键接口

```gdscript
# combat_system.gd — autoload: CombatSystem
extends Node

class BattleResult:
    var attacker_loss: int
    var defender_loss: int
    var attacker_survived: int
    var defender_survived: int
    var attacker_wins: bool

func resolve(
    attacker_count: int,
    attacker_type: DataDef.UnitType,
    defender_count: int,
    defender_type: DataDef.UnitType,
    planet_attribute: DataDef.PlanetAttribute,
) -> BattleResult:
    # 纯函数 — 不依赖外部状态，输入相同则输出相同
    # 快照模型中在步骤 3 被 TurnManager 调用
```

### 空星球 / 零兵力处理

```gdscript
# 攻击空旷星球 (defender_count = 0):
if defender_count <= 0:
    return BattleResult.new(
        attacker_loss = 0,
        defender_loss = 0,
        attacker_survived = attacker_count,
        defender_survived = 0,
        attacker_wins = true,
    )
# 占领系统在战斗后触发 transfer() —— 无战斗即占

# 攻击方 0 兵 (不该发生，但防御性处理):
if attacker_count <= 0:
    return BattleResult.new(
        attacker_loss = 0,
        defender_loss = 0,
        attacker_survived = 0,
        defender_survived = defender_count,
        attacker_wins = false,
    )
```

## Alternatives Considered

### Alternative 1: 兰彻斯特平方律（Lanchester's Square Law）

- **Description**: 远程战斗模型 — `A_remaining = sqrt(A_count² - D_count²)`, 战斗力与数量的平方成正比
- **Pros**: 经典军事运筹学模型，学术上有依据；集中兵力优势被平方放大——策略深度高
- **Cons**: 对玩家不直观——"为什么 20 个兵打 10 个不是剩 10 而是剩 17？"；战斗力被数量平方放大，小数值下的离散取整误差严重影响结果
- **Rejection Reason**: MVP 兵力规模小（1-20），平方律的连续数学假设不成立。玩家无法心算 sqrt，违背"策略可预测"原则。

### Alternative 2: 固定交换比（Fixed Kill Ratio）

- **Description**: 每个攻击方单位固定消灭 N 个防守方单位，反之亦然。如：1 步兵杀 0.8 弓兵，1 弓兵杀 0.6 步兵
- **Pros**: 极简单，玩家一眼算出"我需要 13 个步兵才能打下 10 个弓兵"
- **Cons**: 兵力越多战斗力线性增长——20 个兵打 5 个兵和 4 个兵打 1 个兵结果一样（缩放不变）；无法表现"大军团的协同优势"；小兵力场景的离散误差大
- **Rejection Reason**: 线性缩放在策略游戏中缺乏深度——玩家最优策略永远是"每回合把所有兵派出去"，没有集中兵力的回报。

### Alternative 3: 随机伤害（Damage Range + Random）

- **Description**: 每次攻击伤害在 `[base × 0.8, base × 1.2]` 之间随机取值，战斗结果有波动
- **Pros**: 增加戏剧性和"赌一把"的刺激感；避免"算出来一定输所以不打了"
- **Cons**: 违背回合制策略的确定性期望——玩家无法接受"我算好了能赢结果随机数坑了我"；不可复现，测试困难
- **Rejection Reason**: 星辰之轭的核心 Pillar 2 是"从容推演"——这是下棋，不是赌场。随机伤害直接违背这一原则。

## Consequences

### Positive

- **可预测**: 力量比 → 战损比，单调关系，玩家可以"大约估一下"。克制和地形加成都是乘法，心算有难度但直觉明确。
- **可调优**: 三个参数独立可调 — `DAMAGE_MATRIX`（克制强度）、`PLANET_DEFENSE_MULT`（地形优势）、`BASE_LOSS_RATE`（整体血腥度）。
- **确定性**: 纯函数，同输入同输出。单元测试可全覆盖。
- **不利于进攻**: FORTRESS 1.5× 防守加成让攻打要塞需要谨慎决策，符合"抉择之重"（Pillar 3）。
- **克制不无敌**: 克制方 1.5× 有明显优势但不保证赢——兵力差距可逆克制。

### Negative

- **非直觉**: 玩家不查表无法精确知道 `power_ratio = 2.0` 意味着 `D_loss_rate = 0.75`。缓解：MVP 阶段战斗前显示"预测胜率"UI（Presentation 层），不需要玩家心算。
- **公式不连续**: `round()` 在小数兵力时产生阶梯效应——`ceil` vs `floor` 的差异可能改变结果。缓解：兵力 ≥ 10 时阶梯效应 < 5%。
- **`max(1, ...)` 导致 1 兵也能杀敌**: 1 个步兵攻击 20 个驻兵时，`A_loss_rate ≈ 0` 但 `max(1, ...)` → `A_loss = 1`。不符合直觉（1 个兵不可能杀敌）。缓解：这需要大量兵力差距才触发（power_ratio > 100），实际游戏中几乎不发生。1 兵出征本身也不合理。

### Risks

- **数值平衡**: 初始数值（attack=10, defense=8, BASE_LOSS_RATE=0.5）未经实际测试，可能需多轮调整。缓解：所有参数在 DataDef 中可调，balance check 后修正。
- **极端值**: power_ratio 极大时（如 100 个步兵打 1 个骑兵），`D_loss = round(1 × 0.995) = 1`（防守方全灭）。但 `A_loss = max(1, round(100 × 0.005)) = 1`（进攻方也损失 1）。进攻方只损失 1 合理——流矢、意外等。

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| 兵种系统 | 兵种属性 + 三角克制生效 | `counter_mult` 引用 DAMAGE_MATRIX, attack/defense 引用 UnitStats |
| 战斗结算 | 双方兵力碰撞后胜负+战损计算 | `resolve()` 纯函数，公式完整定义 |
| 占领系统 | 攻击方打赢 → 触发占领 | `attacker_wins` 判定条件为 `defender_survived <= 0` |
| AI 敌人 | 评估"够不够打" | AI 用同样的 `resolve()` 预估战斗结果（可预计算） |

## Performance Implications

- **CPU**: 每场战斗约 10 次浮点运算。MVP 最多 20 场/回合 < 1ms
- **Memory**: `BattleResult` 5 个 int + 1 bool ≈ 24 bytes，即时释放
- **Load Time**: 无
- **Network**: 不适用

## Migration Plan

不适用 — 新项目。

## Validation Criteria

- 同输入两次 `resolve()` 返回完全相同的 `BattleResult`（确定性验证）
- 克制方在同等兵力下 `attacker_loss < defender_loss` 始终成立
- FORTRESS 星上防守方损失的兵数 ≤ NORMAL 星上同条件损失
- 空旷星球 (`defender_count = 0`) → `attacker_wins = true, attacker_loss = 0`
- 攻击方 0 兵 → `attacker_wins = false, attacker_loss = 0`
- 单元测试覆盖：3 兵种 × 3 克制 × 4 星球属性 = 36 个组合 + 边界（0 兵、1 兵、50 兵）

## Related Decisions

- ADR-0002: 数据定义格式 — `DAMAGE_MATRIX` 和 `UnitStats` 在 DataDef 中
- ADR-0004: 回合结算模型 — `resolve()` 在步骤 3 基于快照调用
- ADR-0005: 星球数据模型 — `planet_defense_mult` 按 PlanetAttribute 取值
- ADR-0007: AI 决策架构 — AI 调用 `resolve()` 预估战斗结果
- `docs/architecture/architecture.md` — Module Ownership: 战斗结算系统
