# Cross-GDD Review Report

**Date**: 2026-05-31
**GDDs Reviewed**: 19
**Systems Covered**: 全部 4 层（Foundation 4 + Core 8 + Feature 2 + Presentation 5）
**Entity Registry**: 不存在 — 一致性检查基于全文阅读

---

## Consistency Issues

### Blocking (must resolve before architecture → Epic)

#### 🔴 B-01: 方法名不一致 — `consume_action()` vs `consume_turn()`

- **turn-manager.md** 步骤 5 调用: `国王系统.consume_action()`
- **king-system.md** 定义: `consume_turn()`
- **影响**: 实现时方法名不匹配会导致运行时错误

**修正**: `turn-manager.md` 中统一为 `consume_turn()`

#### 🔴 B-02: 方法名不一致 — `apply_turn_production()` vs `apply_turn()`

- **turn-manager.md** 步骤 5 调用: `ProductionSystem.apply_turn_production()`
- **production-system.md** 定义: `apply_turn()`
- **影响**: 同上，方法名不匹配

**修正**: `turn-manager.md` 中统一为 `apply_turn()`

#### 🔴 B-03: 缺少依赖声明 — GameState ← KingSystem

- **king-system.md** 国王去世流程中调用: `GameState.transition_to(PAUSED)` 和 `transition_to(PLAYING)`
- **gamestate-manager.md** 下游依赖表中**未列出 KingSystem**
- **影响**: gamestate-manager.md 的下游依赖不完整，`transition_to()` 被 KingSystem 调用但未记录

**修正**: `gamestate-manager.md` 下游依赖表中追加 `国王系统 | Hard (调用) | 国王去世时调用 transition_to(PAUSED/PLAYING)`

### Warnings (should resolve, but won't block)

#### ⚠️ W-01: MVP 步兵锁定策略 — 无兵种多样性

- **unit-system.md** 规则 5: MVP 所有玩家出征默认 INFANTRY
- **ai-enemy.md** 规则 5: AI 可选择全部 3 种兵种
- **design concern**: 玩家只能用步兵，AI 能用全部兵种——骑兵对步兵 1.5× 克制。若 AI `intelligence` 较高，会倾向选骑兵反制玩家，玩家却无法反制。这造成非对称不公平。

**建议**: MVP 要么 AI 也只用步兵（对称公平），要么允许玩家选择兵种（但增加 UI 复杂度）。建议 AI `intelligence` 在初始关卡设为 0（随机兵种），避免 AI 总是选骑兵碾压玩家步兵。

#### ⚠️ W-02: 回合结算步骤 5 的顺序在各 GDD 间描述不一致

- **turn-manager.md**: 生产 → 胜负 → 国王
- **win-conditions.md**: 生产 → 胜负 → 国王 ✅ 一致
- **king-system.md**: 只提"在 CLEANUP 步骤 5 调用"，未说明在胜负之后
- **production-system.md**: 只提"在 CLEANUP 调用"，未说明顺序

**建议**: 每个参与步骤 5 的 GDD 都应该明确自己的顺序位置和前/后置步骤。当前只有 win-conditions.md 完整说明了顺序。

#### ⚠️ W-03: 前置 ADR 状态的引用问题

所有 Core 层 GDD 的 Architecture 字段引用 ADR 状态为 "Accepted"，但对应 ADR 文件中的 Status 字段为 "Proposed"。Foundation 层 GDD 同样如此。

**建议**: 将 8 个 ADR 文件的 Status 统一更新为 "Accepted"（或 GDD 中引用改为 "Proposed"）。当前不一致但不影响功能。

#### ⚠️ W-04: 战斗公式"等力 1v1"特殊规则未在 ADR-0006 完整覆盖

- **combat-resolution.md** Edge Cases: 1v1 等力时 defender wins（特殊规则）
- **ADR-0006**: 未提及此特殊规则
- **影响**: 实现者只看 ADR 会漏掉这个 edge case

**建议**: ADR-0006 补充 1v1 等力特殊规则，或在 combat-resolution.md 中标注"此规则补充 ADR-0006"。

#### ⚠️ W-05: BARREN 星累积产量逻辑分散在两处

- **production-system.md** 定义了累积产量取整逻辑（`accumulated_production` 字段）
- **planet-system.md** RuntimePlanetData 结构中包含 `accumulated_production` 字段
- **但** planet-system.md 的字段表中未列出 `accumulated_production`

**建议**: `planet-system.md` 的字段表补充 `accumulated_production: float` 字段。

#### ⚠️ W-06: 占领系统步骤 4 顺序依赖未在 ADR-0004 中覆盖

- **occupation-system.md** Edge Cases: 同颗星被多条指令攻击时，"玩家优先"应用顺序
- **ADR-0004**: 未提及此顺序规则
- **impact**: 这是一个重要的确定性保证——若 ADR 不写，实现者可能按其他顺序（如指令提交顺序）应用

**建议**: ADR-0004 补充"步骤 4 应用顺序：玩家指令优先，AI 指令在后，玩家指令之间按提交顺序"。

---

## Game Design Issues

### Warnings

#### ⚠️ W-07: Pillar 3（抉择之重）— 每回合消耗寿命的"空回合"成本

- **king-system.md**: 每回合固定消耗 1，无论是否出兵
- **Pillar 3**: "每个行动消耗国王寿命...没有免费的决策"
- **design tension**: "什么都不做"也消耗寿命——这是设计意图（"什么都不做也是一种决策"），但可能导致玩家焦虑。特别是新玩家在早期回合可能只想"看看 AI 怎么走"。
- **verdict**: 不是问题——king-system.md 的 Consequences 已明确解释。但建议在 playtest 中关注"空回合焦虑"。

#### ⚠️ W-08: 无经济 catch-up 机制

- 游戏没有逆风翻盘机制——落后的玩家没有获得额外资源或 buff 的途径
- 在 MVP 10 颗星规模下，先丢一颗星可能意味着经济雪崩（对方多产兵→更易攻占→更多星→更多兵）
- **verdict**: 不阻塞——MVP 验证核心循环即可。但应在 Vertical Slice 考虑 catch-up 机制（如"国王去世后新国王获得短暂 buff"）

#### ⚠️ W-09: 星球系统是单一故障点

- 7 个系统直接 Hard 依赖星球系统，1 个星球系统 bug 会导致半数的 Core 层系统无法运作
- **verdict**: 架构层面已识别——systems-index.md 标注为 ⚠️ 瓶颈系统。建议在实现时优先对 `planet_system.gd` 写完整单元测试。

#### ℹ️ W-10: MVP 全部 19 系统都是 MVP Priority

- systems-index.md 中全部 19 个系统标记为 MVP
- 实际 gameplay 角度看，Presentation 层的"战斗动画"在 MVP 可以先做极简版（甚至只做"数字直接变"），不应该和其他系统同等优先级
- **verdict**: 不影响架构，但建议 Epic 拆分时做优先级二次筛选

### Pillar Alignment

| 系统 | 🕯️ 代际接力 | ♟️ 从容推演 | ⚖️ 抉择之重 | 🌌 自创史诗 |
|------|:--:|:--:|:--:|:--:|
| 数据定义 | — | — | — | — |
| 事件总线 | — | — | — | — |
| GameState | — | ✅ | — | — |
| 回合管理器 | — | ✅ | — | — |
| **星球系统** | — | ✅ | ✅ | — |
| **兵种系统** | — | — | ✅ | — |
| **生产系统** | — | ✅ | — | — |
| **战斗结算** | — | — | ✅ | — |
| **占领系统** | — | — | ✅ | — |
| **出征系统** | — | — | ✅ | — |
| **国王系统** | ✅ | — | ✅ | ✅ |
| **AI 敌人** | — | ✅ | — | — |
| 星图数据 | — | ✅ | — | — |
| 胜负条件 | — | ✅ | — | — |
| 星图 UI | — | ✅ | — | — |
| 出征 UI | — | — | ✅ | — |
| 回合控制 UI | — | ✅ | — | — |
| 国王 UI | ✅ | — | — | ✅ |
| 战斗动画 | — | ✅ | — | — |

**结论**: 
- 全部系统至少服务 1 个 Pillar ✅（数据定义和事件总线是纯基础设施，免于此要求）
- 4 个 Pillar 被覆盖：代际接力(2系统)、从容推演(9系统)、抉择之重(7系统)、自创史诗(2系统)
- 无 Pillar Drift ✅
- 无 Anti-Pillar 违规 ✅

### Anti-Pillar Audit

| Anti-Pillar | 是否有系统违反 | 
|-------------|:--:|
| 不做多人 | ✅ 无违反 |
| 不做 3D | ✅ 无违反 |
| 不做限时 | ✅ 无违反 |
| 不做硬核操作 | ✅ 无违反 |

---

## Cross-System Scenario Issues

### Scenarios Walked: 4

**S1**: 游戏初始化 (星图数据 → 星球系统 → 国王系统 → GameState → 星图 UI)
**S2**: 玩家部署回合 (星图 UI → 出征 UI → 出征系统 → 回合管理器)
**S3**: 回合结算 (回合管理器 → AI → 战斗 → 占领 → 生产 → 胜负 → 国王)
**S4**: 国王去世继位 (国王系统 → GameState → 国王 UI)

### Blockers

无。

### Warnings

#### ⚠️ S3-W1: 回合结算中生产 → 胜负 → 国王的顺序性

- 如果胜负触发 VICTORY，国王寿命消耗被跳过（win-conditions.md 规则明确）
- 如果国王去世（PAUSED），胜负判定已在前一步完成——不受影响
- **verdict**: 顺序正确，但 king-system.md 和 production-system.md 未明确自己在步骤 5 中的相对位置。见 W-02。

#### ⚠️ S3-W2: AI 情报延迟 — AI 看不到玩家在同一回合的部署

- AI 在步骤 1 决策，玩家指令在此之前已提交（通过 `submit_command()`）
- 但 AI 读取的是"玩家已扣除 garrison 后的实时星球状态"
- 所以 AI 可以**间接**感知到玩家的部署（因为 garrison 已经减少了），但它不会知道那些兵**去了哪里**
- **design implication**: AI 看到某玩家星 garrison 下降 → 可能认为那是"防守薄弱"而进攻——即使那些兵正在前往 AI 星球的路上
- **verdict**: 不阻塞。这是"同时结算"的自然结果——AI 和玩家一样面临战争迷雾。但这也意味着 AI 的"削弱时机判断"可能偏乐观。

#### ℹ️ S4-I1: 国王去世 → PAUSED → 继位 → PLAYING 的 UI 刷新时序

- king-system.md: 去世 → PAUSED → 弹窗 → 玩家确认 → 继位 → PLAYING
- king-ui.md: 弹窗包含新国王信息
- **question**: 国王 UI 弹窗在 PAUSED 状态显示，但 king-ui.md 规则 5 说 "PAUSED 时隐藏面板"
- **clarification**: "隐藏面板"指的是常驻面板（左上角）；弹窗是独立于面板的模态窗口。当前描述可导致歧义。

---

## GDDs Flagged for Revision

| GDD | Reason | Severity | Priority |
|-----|--------|----------|----------|
| turn-manager.md | B-01: `consume_action()` → `consume_turn()`; B-02: `apply_turn_production()` → `apply_turn()` | Blocking | High |
| gamestate-manager.md | B-03: 下游依赖表缺少 KingSystem | Blocking | High |
| ADR-0006 | W-04: 1v1 等力特殊规则未覆盖 | Warning | Medium |
| ADR-0004 | W-06: 步骤 4 应用顺序规则未覆盖 | Warning | Medium |
| planet-system.md | W-05: 字段表缺少 `accumulated_production` | Warning | Low |
| king-ui.md | S4-I1: PAUSED 状态下面板隐藏 vs 弹窗显示的描述歧义 | Info | Low |

---

## Verdict: **PASS** ✅

3 个 Blocking 已修正：
1. ✅ `turn-manager.md`: `consume_action()` → `consume_turn()`, `apply_turn_production()` → `apply_turn()`
2. ✅ `gamestate-manager.md`: 下游依赖表追加 KingSystem 行

6 个 Warning 建议在实现阶段按需处理，均不阻塞 /create-epics。
