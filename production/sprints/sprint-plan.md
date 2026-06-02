# Sprint Plan — 星辰之轭 Part 2

Generated: 2026-06-02
Phase: Pre-Production → Production Gate
Demo Goal: 拖线发兵 + 占点产兵 + 全歼制胜（不含 RPG 阶段）
Total: 19 Epics / 38 Stories / ~53.5h estimated

---

## Dependency Graph (Critical Path)

```
                          ┌─────────────────┐
                          │  data-definitions │ (root)
                          │  event-bus        │ (root)
                          └───┬───────────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
     gamestate-manager   turn-manager    ┌─────────────┐
                              │          │ planet-system│ ⚠️ BOTTLENECK
                              │          └──┬──┬──┬──┬─┘
                              │             │  │  │  │
              ┌───────────────┘    ┌────────┘  │  │  └──────────┐
              │                    │           │  │             │
         unit-system       production-system  │  │    deployment-system
              │                    │          │  │         │
              └──────┬─────────────┘          │  │    ┌────┼────┐
                     │                        │  │    │    │    │
              combat-resolution               │  │  occ  king ai-enemy
                     │                        │  │
                     └────────┬───────────────┘  │
                              │                  │
                         level-data         win-conditions
                              │                  │
                         star-map-ui             │
                              │                  │
                         deployment-ui           │
                                                 │
                    ┌───────────┬────────────────┘
                    │           │           │
              turn-control-ui  king-ui  battle-animation
```

---

## Sprint 1 — Foundation (2026-06-03 ~ 2026-06-09)

**Sprint Goal**: 搭建编译时与运行时基础设施 — 类型系统、事件通信、状态机、回合管线

| Epic | Stories | Est. | Key Output |
|------|---------|------|------------|
| data-definitions | 3 | 4h | GDScript enum/const + .tres Resource class + loader |
| event-bus | 3 | 3h | Signal 声明 + 递归保护 + Presentation 信号 |
| gamestate-manager | 1 | 1.5h | 5 状态 7 转换 enum+match 状态机 |
| turn-manager | 2 | 3h | 3 阶段回路 + 5 步快照引擎 |
| **Total** | **9** | **~11.5h** | |

### Must Have (按依赖顺序)

| ID | Task | Type | Est. | Depends On | AC |
|----|------|------|------|------------|-----|
| S1-001 | data-definitions: Enums & Constants | Logic | 1.5h | — | UnitType/Faction/PlanetAttribute + DAMAGE_MATRIX 定义 |
| S1-002 | data-definitions: Resource Classes | Config | 1.5h | S1-001 | UnitStats/PlanetDef/LevelData .tres 类 |
| S1-003 | data-definitions: Resource Loading | Integration | 1h | S1-001, S1-002 | load() + 缺失文件错误处理 |
| S1-004 | event-bus: Signal Declarations | Logic | 1h | — | 所有系统信号在 EventBus autoload 声明 |
| S1-005 | event-bus: Recursion Guard | Logic | 1h | S1-004 | 递归发射检测 + 发射栈追踪 |
| S1-006 | event-bus: Presentation Signals | Logic | 1h | S1-005 | deployment_requested/animations_complete/king_succession_complete |
| S1-007 | gamestate-manager: State Machine | Logic | 1.5h | S1-004, S1-001 | TITLE→PLAYING→PAUSED/VICTORY/DEFEAT + EventBus 广播 |
| S1-008 | turn-manager: Phase Loop + Command Intake | Logic | 2h | S1-004, S1-007 | DEPLOYMENT→EXECUTION→CLEANUP + end_turn() guard |
| S1-009 | turn-manager: Snapshot Engine | Logic | 2h | S1-008 | 5 步快照 + 顺序无关结算 + 超额截断 |

**Parallel Opportunity**: S1-001/S1-002 完成后，S1-004 可与 S1-003 并行。S1-007 和 S1-008 的前置满足后可并行推进。

### Definition of Done
- [ ] 所有 9 个 Story AC 通过
- [ ] 4 个 Logic 类型 Story 有 GUT 单元测试
- [ ] EventBus 递归保护有专门测试用例
- [ ] TurnManager 快照确定性测试（同输入→同输出）

---

## Sprint 2 — Core War Systems (2026-06-10 ~ 2026-06-20)

**Sprint Goal**: 核心战争逻辑完整可运行 — 星球/兵种/生产/战斗/占领/出征/国王/AI

| Epic | Stories | Est. | Key Output |
|------|---------|------|------------|
| planet-system | 3 | 4h | RuntimePlanetData + 邻接表 + 快照 |
| unit-system | 2 | 2h | UnitStats .tres + 克制查询/MVP |
| production-system | 2 | 2.5h | 累积产量公式 + apply_turn() |
| combat-resolution | 2 | 3h | resolve() 纯函数 + 36 组合测试 |
| deployment-system | 2 | 4h | deploy() + validate() + 回合集成 |
| occupation-system | 2 | 2.5h | transfer() + 多攻方排序 |
| king-system | 2 | 4h | KingData + consume_turn() + 继位 |
| ai-enemy | 2 | 5h | 三阶段规则引擎 + 参数化 |
| **Total** | **17** | **~27h** | |

### Must Have (按依赖阶段)

**Phase A — 数据基础（可并行）**

| ID | Task | Type | Est. | Depends On | AC |
|----|------|------|------|------------|-----|
| S2-001 | planet-system: Runtime Data + Attribute Calc | Logic | 1.5h | Sprint 1 | RuntimePlanetData + getter/setter |
| S2-002 | planet-system: Init + Adjacency | Logic | 1.5h | S2-001 | init_from_def() + _adjacency 构建 |
| S2-003 | unit-system: Stats Config | Config | 1h | Sprint 1 | UnitStats .tres × 3 兵种 |
| S2-004 | unit-system: Counter Query + MVP | Logic | 1h | S2-003 | get_counter() + pick_best_unit() |

**Phase B — 公式系统（需 S2-001）**

| ID | Task | Type | Est. | Depends On | AC |
|----|------|------|------|------------|-----|
| S2-005 | planet-system: State Mutation + Snapshot | Integration | 1h | S2-002 | snapshot()/restore() + 变更追踪 |
| S2-006 | production-system: Formula + apply_turn() | Logic | 1.5h | S2-001 | 累积公式 + 上限截断 |
| S2-007 | combat-resolution: resolve() Pure Function | Logic | 1.5h | S2-001, S2-004 | BattleResult + 比例力量 |
| S2-008 | combat-resolution: 36-Combo Test Matrix | Logic | 1.5h | S2-007 | 36 用例 + 边界 0/1/50 兵 |

**Phase C — 集成系统（需 Phase B）**

| ID | Task | Type | Est. | Depends On | AC |
|----|------|------|------|------------|-----|
| S2-009 | production-system: Integration + Pipeline | Integration | 1h | S2-006, S2-005 | CLEANUP step 5 接入 |
| S2-010 | deployment-system: deploy() + validate() | Logic | 2h | S2-001 | DeploymentCommand + 校验 + 兵力扣减 |
| S2-011 | deployment-system: Integration + Pipeline | Integration | 2h | S2-010 | TurnManager step 1 接入 + get_pending() |
| S2-012 | occupation-system: transfer() Core | Logic | 1.5h | S2-010 | 空星球即时占领 + 有主星球战后占领 |
| S2-013 | occupation-system: Ordering + Pipeline | Integration | 1h | S2-012 | 多攻方顺序 + step 4 接入 |
| S2-014 | king-system: KingData + consume_turn() | Logic | 2h | Sprint 1 | 名字生成 + 寿命扣减 + 天赋 |
| S2-015 | king-system: Turn Integration + EventBus | Integration | 2h | S2-014 | step 5 接入 + king_died/king_succeeded 广播 |
| S2-016 | ai-enemy: compute_turn() Engine | Logic | 3h | S2-010 | 三阶段：评估→排序→冲突解决 |
| S2-017 | ai-enemy: Parameterization + Test Matrix | Integration | 2h | S2-016 | 难度参数 + AI 行为测试矩阵 |

**Parallel Opportunities**:
- Phase A: S2-001/S2-002（planet）∥ S2-003/S2-004（unit）完全独立
- Phase B: S2-005 ∥ S2-006 ∥ S2-007（各自独立前置满足后）
- Phase C: S2-009 ∥ S2-014（各自独立）; S2-012 ∥ S2-015 ∥ S2-016（各自独立）

### Definition of Done
- [ ] 所有 17 个 Story AC 通过
- [ ] combat-resolution: 36 测试全部 Green
- [ ] ai-enemy: 行为矩阵覆盖 3 难度 × 5 场景
- [ ] 所有 Logic 类型 Story 有 GUT 单元测试
- [ ] 回合管线端到端：deploy → execute → cleanup 完整走通

---

## Sprint 3 — Playable Demo (2026-06-21 ~ 2026-06-28)

**Sprint Goal**: 可玩 Demo 完整循环 — 关卡数据 + 胜负条件 + 全 UI + 动画

| Epic | Stories | Est. | Key Output |
|------|---------|------|------------|
| level-data | 2 | 2.5h | LevelData Resource + tutorial_1.tres |
| win-conditions | 2 | 1.5h | check_victory/defeat + 管线集成 |
| star-map-ui | 2 | 4h | 星球节点 + 连线 + 兵力 + 交互 |
| deployment-ui | 1 | 1.5h | 滑块面板 + deploy() 调用 |
| turn-control-ui | 1 | 1h | 回合按钮 + 阶段指示 + 快捷键 |
| king-ui | 2 | 2.5h | 国王面板 + 去世/继位弹窗 |
| battle-animation | 2 | 3h | 移动动画 + 占领闪烁 |
| **Total** | **12** | **~16h** | |

### Must Have (按依赖阶段)

**Phase A — Feature 层（需 Core 完成）**

| ID | Task | Type | Est. | Depends On | AC |
|----|------|------|------|------------|-----|
| S3-001 | level-data: Resource Classes | Logic+Config | 1.5h | Sprint 1, S2-005 | LevelData/PlanetDef/Connection .tres + tutorial_1 |
| S3-002 | level-data: init_from_level() | Integration | 1h | S3-001, S2-005 | 根据 LevelData 构造 PlanetSystem + 边界校验 |
| S3-003 | win-conditions: check_victory/defeat | Logic | 1h | Sprint 1, S2-005 | 全歼/被全歼检测 |
| S3-004 | win-conditions: Pipeline + GameState + EventBus | Integration | 0.5h | S3-003, S2-009, S2-015 | CLEANUP step 5 接入 + game_ended 广播 |

**Phase B — Presentation 层（需 Phase A）**

| ID | Task | Type | Est. | Depends On | AC |
|----|------|------|------|------------|-----|
| S3-005 | star-map-ui: Planet Nodes + Lines + Garrison | UI | 2h | S3-002, S2-005 | 节点渲染 + 连线 + 兵力数字 + planets_initialized 订阅 |
| S3-006 | star-map-ui: Interaction + Detail Panel | UI | 2h | S3-005 | 点击星球→详情面板 + EventBus 刷新 |
| S3-007 | deployment-ui: Panel + Slider + deploy() | UI | 1.5h | S3-006, S2-010 | 滑块 0~max + 确认/取消 + 快捷键 |
| S3-008 | turn-control-ui: Button + Phase + Hotkeys | UI | 1h | Sprint 1 (turn-mgr) | end_turn 按钮 + 回合数/阶段文本 + Space 快捷键 |
| S3-009 | king-ui: King Panel | UI | 1.5h | S2-014 | 国王头像区 + 寿命条 + 天赋标签 |
| S3-010 | king-ui: Death/Succession Popup | UI | 1h | S3-009, S2-015 | 去世弹窗 + 继位展示 + 暂停/恢复 |
| S3-011 | battle-animation: Move Animation | Visual | 2h | S2-010, S2-005 | 部队沿连线移动 + 并行播放 + Skip |
| S3-012 | battle-animation: Occupation Flash | Visual | 1h | S3-011, S2-007 | 占领闪烁 + 动画序列编排 |

**Parallel Opportunities**:
- Phase A: S3-001 ∥ S3-003
- Phase B: S3-008 可与 S3-005/S3-006 并行（不依赖 level-data）
- Phase B: S3-009 可与 S3-005/S3-006 并行
- Phase B: S3-011 可与 S3-005 并行（各自独立前置）

### Should Have（Demo 可裁减）

| ID | Task | Est. | Notes |
|----|------|------|-------|
| S3-010 | king-ui: Death Popup | 1h | Demo 单局短，国王可能不换代 |
| S3-012 | battle-animation: Occupation Flash | 1h | 核心移动动画 S3-011 足够 |

### Definition of Done
- [ ] 所有 Must Have Story AC 通过
- [ ] 完整 Demo 循环可运行：启动→看星图→拖线发兵→结束回合→观看动画→胜负判定
- [ ] UI 交互测试（点击、快捷键）通过
- [ ] Animation skip 功能正常
- [ ] Smoke check 通过

---

## Sprint Overview

| Sprint | Dates | Stories | Est. Hours | Key Risk |
|--------|-------|---------|------------|----------|
| S1 — Foundation | 06/03 ~ 06/09 | 9 | ~11.5h | TurnManager 快照引擎复杂度 |
| S2 — Core War | 06/10 ~ 06/20 | 17 | ~27h | planet-system 瓶颈阻塞 7 个下游系统 |
| S3 — Playable | 06/21 ~ 06/28 | 12 | ~16h | star-map-ui 是 UI 层瓶颈 |
| **Total** | **26 days** | **38** | **~53.5h** | |

---

## Risk Register

| Risk | Prob | Impact | Mitigation | Sprint |
|------|------|--------|------------|--------|
| planet-system 阻塞下游 | M | HIGH | Phase A 优先冲刺，unit-system 并行推进不等待 | S2 |
| AI 规则引擎过度复杂 | M | MEDIUM | 三阶段可降级为单阶段权宜实现 | S2 |
| Godot 4.6 API 与 LLM 知识差距 | L | MEDIUM | 参考 engine-reference docs + WebSearch 验证 | All |
| star-map-ui 渲染性能 | L | LOW | 2D 像素风 500 draw call 预算充足 | S3 |
| Demo 时间不足 | M | MEDIUM | S3 Should Have 可裁减；king 系统可降级为 stub | S3 |

---

## Story Type Distribution

| Type | Count | % | Blocking Gate |
|------|-------|---|---------------|
| Logic | 17 | 45% | GUT 单元测试必须 PASS |
| Integration | 10 | 26% | 集成测试或 playtest 文档 |
| UI | 7 | 18% | 手动 walkthrough 或交互测试 |
| Config/Data | 2 | 5% | Smoke check |
| Visual/Feel | 2 | 5% | 截图 + 主观验收 |
| **Total** | **38** | **100%** | |

---

## External Dependencies

| Dependency | Status | Impact if Delayed | Contingency |
|------------|--------|-------------------|-------------|
| Godot 4.6 Engine | ✅ Installed | N/A | — |
| GUT Test Framework | ⚠️ Not yet scaffolded | Blocks all Logic story DoD | S1-001 之后立即 /test-setup |
| Git Repo | ❌ Not initialized | 无版本控制风险 | S1 开始前 init |

---

## Next Steps After Sprint 3

1. `/vertical-slice` — Pre-Production → Production gate check
2. 若 PROCEED → `/sprint-plan` 规划 Production 阶段 Sprint 4+
3. 若 PIVOT → 回到设计迭代
