# 星辰之轭 — Master Architecture

## Document Status

| Field | Value |
|-------|-------|
| **Version** | 1.0 |
| **Last Updated** | 2026-05-31 |
| **Engine** | Godot 4.6 |
| **Language** | GDScript |
| **GDDs Covered** | 0 (尚无 GDD — 基于 game-concept.md + systems-index.md) |
| **ADRs Referenced** | 0 (尚无 ADR) |
| **Technical Director Sign-Off** | Pending |
| **Lead Programmer Feasibility** | Pending |

---

## Engine Knowledge Gap Summary

| 域 | 风险 | 关键变更 |
|---|------|---------|
| GDScript 语言 | 🟢 LOW | 4.5 新增 variadic args、`@abstract` — 纯增量 |
| 2D 渲染 | 🟢 LOW | `draw_*()` 新增可选 oversampling 参数，向后兼容 |
| 2D 物理 | 🟢 LOW | 无变更 |
| TileMapLayer | 🟡 MEDIUM | physics chunking 默认开启；`get_coords_for_body_rid()` 精度降低 |
| AStar2D | 🟡 MEDIUM | 4.6 行为变更：禁用点 `get_point_path()` 返回空数组 |
| Resource 复制 | 🟡 MEDIUM | `duplicate(true)` 语义变更 (4.5)；需用 `duplicate_deep()` |
| FileAccess | 🟡 MEDIUM | `store_*()` 返回 bool (4.4) |
| UI/GUI | 🟢 LOW | 新可选参数，向后兼容 |
| 3D 全部 | 🟢 LOW | 不相关 |

**结论**: 2D GDScript 回合制策略对 Godot 4.6 高度安全。主要关注 TileMapLayer (如需铺格)、AStar2D 空路径检查、Resource 深拷贝。

---

## Architecture Principles

1. **分层隔离** — 上层可依赖下层，下层不可知上层。数据向下流动（UI 读 Core），指令向上升（UI 发 Command 到 Core）。
2. **事件解耦** — 跨系统通知走事件总线。系统之间不直接调用对方方法（Foundation 层被 Core 合法依赖除外）。
3. **数据驱动** — 所有游戏数值（兵种属性、产量公式参数、AI 权重）存储在外部数据文件中（.tres / JSON），不硬编码。
4. **回合内不可变** — 部署阶段收集指令，结算阶段统一执行。结算阶段不产生新指令。
5. **纯逻辑 Core** — Core 层系统无 Godot 场景依赖，纯 GDScript 对象，方便单元测试和平衡调整。

---

## System Layer Map

```
┌─────────────────────────────────────────────────┐
│  PRESENTATION                                   │
│  星图UI | 出征UI | 回合控制UI | 国王UI | 战斗动画   │
├─────────────────────────────────────────────────┤
│  FEATURE                                        │
│  星图/关卡数据 | 胜负条件                          │
├─────────────────────────────────────────────────┤
│  CORE                                           │
│  星球系统 | 兵种系统 | 生产系统 | 战斗结算          │
│  占领系统 | 出征系统 | 国王系统 | AI敌人            │
├─────────────────────────────────────────────────┤
│  FOUNDATION                                     │
│  数据定义 | 事件总线 | GameState管理器 | 回合管理器  │
├─────────────────────────────────────────────────┤
│  PLATFORM (Godot 4.6)                           │
│  GDScript | Node2D | Control | Resource | Signal │
└─────────────────────────────────────────────────┘
```

**规则**:
- Foundation 零外部依赖，只依赖 Godot 标准库
- Core 只依赖 Foundation，不碰 UI
- Feature 依赖 Core + Foundation，组装数据、定义胜负
- Presentation 依赖 Feature + Core，纯展示，不含游戏逻辑

---

## Module Ownership

### Foundation Layer

| # | System | Owns | Exposes | Consumes | Godot API |
|---|--------|------|---------|----------|-----------|
| 1 | 数据定义 | 枚举（`UnitType`, `PlanetAttribute`, `Faction`）、常量表（三角克制矩阵、产量公式参数）、全局常量 | `UnitType`/`Faction` enum、`DAMAGE_MATRIX: Dictionary`、`PRODUCTION_BASE_RATE: float` | 无 | `enum`, `const`, `Resource` |
| 2 | 事件总线 | 信号注册表、事件分发队列、订阅/取消订阅逻辑 | `emit(event, payload)`, `subscribe(event, callable)`, `unsubscribe(event, callable)` | 无 | `Signal`, `Callable`, autoload 单例 |
| 3 | GameState | 状态枚举、当前状态、状态转换规则矩阵、状态进入/退出回调 | `current_state: State`, `transition_to(new_state) -> bool`, signal `state_changed(old, new)` | 事件总线 | `enum State {TITLE, PLAYING, PAUSED, VICTORY, DEFEAT}`, `match` |
| 4 | 回合管理器 | 回合计数、回合阶段（部署→结算→收尾）、指令队列、同时结算调度 | `end_turn()`, `turn_number: int`, `submit_command(cmd)`, signal `turn_ended`, signal `execution_phase_started` | 事件总线 | `Signal`，纯逻辑 |

### Core Layer

| # | System | Owns | Exposes | Consumes | Godot API |
|---|--------|------|---------|----------|-----------|
| 5 | 星球系统 ⚠️ | 星球数据（id, name, position, owner, garrison, max_garrison, production_rate, attributes），全星球列表 | `get_planet(id)`, `get_all_planets()`, `get_planets_by_owner(faction)`, `update_garrison(id, delta)`, `set_owner(id, faction)` | 数据定义、事件总线 | `Resource`, `Dictionary` |
| 6 | 兵种系统 | 兵种属性（攻/防/速）、三角克制表、伤害计算公式 | `get_stats(type)`, `calculate_damage(attacker, defender, count)`, `get_counter(type)` | 数据定义 | 纯数据 + 数学 |
| 7 | 生产系统 | 产量公式、驻兵上限执行、每回合自动生产调度 | `calculate_production(planet_id)`, `apply_turn_production()` | 星球系统、兵种系统、回合管理器 | 纯逻辑 |
| 8 | 战斗结算 | 战斗公式、战损计算、`BattleResult` 数据结构 | `resolve(attacker_count, attacker_type, defender_count, defender_type, planet_defense_bonus) -> BattleResult` | 兵种系统 | 纯数学 |
| 9 | 占领系统 | 占领判定规则、战后所有权转移逻辑 | `check_occupation(planet_id, battle_result)`, `transfer(planet_id, new_owner)` | 星球系统、战斗结算 | 纯逻辑 |
| 10 | 出征系统 | 出征指令创建、兵力路径、部署校验 | `deploy(from, to, count, type)`, `validate(cmd)`, `get_pending()` | 星球系统、兵种系统、回合管理器 | 纯逻辑 |
| 11 | 国王系统 | 国王数据（姓名、天赋、剩余寿命/行动次数、年龄）、天赋效果、代际计数 | `consume_action(cost)`, `is_alive()`, `current_king`, signal `king_died`, signal `action_consumed` | 回合管理器、事件总线 | `Resource` |
| 12 | AI 敌人 | AI 决策逻辑（评估威胁、选择目标、计算兵力分配）、防御优先级 | `compute_turn() -> Array[DeploymentCommand]` | 星球系统、兵种系统、出征系统、回合管理器 | 纯逻辑 |

### Feature Layer

| # | System | Owns | Exposes | Consumes | Godot API |
|---|--------|------|---------|----------|-----------|
| 13 | 星图数据 | 关卡布局文件、星球位置坐标、连接路线、初始势力分配 | `load_level(id)`, `get_connections(planet_id)`, `get_planet_position(planet_id)` | 星球系统、数据定义 | `Resource`, `ResourceLoader` |
| 14 | 胜负条件 | 胜利判定、失败判定、游戏结束触发器 | `check_victory()`, `check_defeat()`, `get_result()` | 星球系统、GameState 管理器 | 纯逻辑 |

### Presentation Layer

| # | System | Owns | Consumes | Godot API |
|---|--------|------|----------|-----------|
| 15 | 星图 UI | 星球节点渲染、连接线绘制、兵力数字显示、归属颜色 | 星图数据、星球系统 | `Control`, `Node2D`, `_draw()` |
| 16 | 出征 UI | 兵力滑块、目标高亮、确认/取消按钮 | 出征系统、星球系统 | `Control`, `Slider`, `Button` |
| 17 | 回合控制 UI | 结束回合按钮、回合数标签、状态提示 | 回合管理器、GameState | `Control`, `Button`, `Label` |
| 18 | 国王 UI | 国王名字、天赋标签、剩余行动次数/寿命条 | 国王系统 | `Control`, `Label`, `TextureProgressBar` |
| 19 | 战斗动画 | 兵力短线流动动画、占领闪烁 | 战斗结算、出征系统 | `Tween`, `_draw()` |

---

## Dependency Diagram

```
数据定义 ──┬── 星球系统 ──┬── 生产系统
事件总线 ──┤            ├── 占领系统
GameState ─┤            ├── 出征系统
回合管理器 ─┘            ├── AI敌人
                        ├── 星图数据 ── 星图UI
兵种系统 ──── 战斗结算 ──┘
                        国王系统 ──── 国王UI
                        胜负条件
                        出征UI
                        回合控制UI
                        战斗动画
```

**0 循环依赖** ✅

---

## Data Flow

### 场景 1: 游戏初始化

```
ResourceLoader.load(level.tres)
    → 星图数据.load_level("tutorial_1")
        → 创建 PlanetData × N，设置初始 owner/garrison
    → 星球系统 —emit→ 事件总线: "planets_initialized"
    → 国王系统.create_initial_king()
    → GameState.transition_to(PLAYING)
    → 星图UI.refresh_map()  ← 首次渲染
```

### 场景 2: 玩家部署回合

```
玩家点击星球A → 星图UI.select_planet(A)
玩家拖动兵力滑块 → 出征UI.open(A)
玩家点击目标星球B
    → 出征系统.validate(DeploymentCommand{A→B, N, TYPE}) → bool
    → 出征系统.deploy(A, B, N, TYPE)
    → 回合管理器.submit_command(cmd)   ← 入队，不立即执行
    → 国王系统.consume_action(1)        ← 消耗寿命
    → 国王UI.refresh()
```

### 场景 3: 回合结算

```
玩家点击"结束回合" → 回合管理器.end_turn()

阶段1 — 收集:
    AI.compute_turn() → 生成 AI DeploymentCommand[]
    合并: 玩家指令 + AI 指令 → 全量指令队列

阶段2 — 结算（顺序无关）:
    对每条指令:
        战斗结算.resolve(attacker, defender) → BattleResult
        占领系统.check_occupation(planet_id, battle_result)
            若成功: 占领系统.transfer(planet_id, new_owner)
        星球系统.update_garrison() / set_owner()

阶段3 — 收尾:
    生产系统.apply_turn_production()    ← 每颗己方星自动产兵
    胜负条件.check_victory() / check_defeat()
    国王系统: 年龄+1, 若寿命≤0 → king_died
    → 事件总线.emit("turn_ended", turn_number)
    → 全部 UI 刷新
```

### 场景 4: 国王去世继位 (MVP 简化版)

```
国王系统.consume_action(1)
    → remaining_actions == 0
    → 事件总线 emit "king_died"
    → 回合管理器暂停
    → 国王系统.generate_heir()          ← MVP 暂不做，预留接口
    → 事件总线 emit "king_succeeded"
    → 国王UI.refresh()
    → 回合管理器恢复
```

### 场景 5: 存档/读档 (Production 阶段)

```
存档:
    各系统 serialize() → Dictionary
    → SaveManager.pack() → 合并存档数据
    → FileAccess.store_var(save_data)   ← Godot 4.4+: 检查返回 bool

读档:
    FileAccess.get_var() → Dictionary
    → SaveManager.unpack() → 分发到各系统
    → 各系统 deserialize(data)
    → 全部 UI 刷新

存档版本号: 必须含 version 字段，向后兼容检查
```

---

## API Boundaries

### 核心数据结构

```gdscript
class PlanetData:
    var id: int
    var name: String
    var position: Vector2
    var owner: Faction
    var garrison: int
    var max_garrison: int
    var production_rate: float
    var attribute: PlanetAttribute

class DeploymentCommand:
    var from_planet: int
    var to_planet: int
    var count: int
    var unit_type: UnitType

class BattleResult:
    var attacker_loss: int
    var defender_loss: int
    var attacker_survived: int
    var defender_survived: int
    var attacker_wins: bool

class KingData:
    var name: String
    var talent: TalentType
    var lifespan: int
    var actions_remaining: int
    var age: int
    var generation: int
```

### Foundation 层契约要点

**数据定义**: 纯声明文件，不含逻辑。修改任何值 = 全局影响。所有枚举和常量集中管理。

**事件总线**: `emit()` 是 fire-and-forget。发送者不等待、不感知订阅者。订阅者内部异常不传播到总线（总线 catch 并 log）。同名事件按订阅顺序调用。

**GameState 管理器** — 状态转换矩阵:

| 从 \ 到 | TITLE | PLAYING | PAUSED | VICTORY | DEFEAT |
|---------|-------|---------|--------|---------|--------|
| TITLE   | —     | ✅      | ❌     | ❌      | ❌     |
| PLAYING | ❌    | —       | ✅     | ✅      | ✅     |
| PAUSED  | ❌    | ✅      | —      | ❌      | ❌     |
| VICTORY | ✅    | ❌      | ❌     | —       | ❌     |
| DEFEAT  | ✅    | ❌      | ❌     | ❌      | —      |

**回合管理器**: 三阶段不可跳转（DEPLOYMENT → EXECUTION → CLEANUP → DEPLOYMENT）。执行阶段指令顺序不能影响结果。`submit_command()` 仅在 DEPLOYMENT 阶段接受。

### 完整 API 签名

详见本会话 Phase 4 讨论。实现时以架构文档 + 对应 GDD 为准。

---

## ADR 审计

### 当前状态: 8 ADR (4 Foundation + 4 Core)

### Foundation 层 — 全部 Accepted ✅

| ADR | 标题 | 状态 |
|-----|------|------|
| ADR-0001 | 事件总线架构 | Accepted |
| ADR-0002 | 数据定义格式 | Accepted |
| ADR-0003 | GameState 状态机设计 | Accepted |
| ADR-0004 | 回合结算模型 | Accepted |

### Core 层 — 全部 Accepted ✅

| ADR | 标题 | 状态 |
|-----|------|------|
| ADR-0005 | 星球数据模型 | Accepted |
| ADR-0006 | 战斗公式设计 | Accepted |
| ADR-0007 | AI 决策架构 | Accepted |
| ADR-0008 | 国王寿命模型 | Accepted |

### 生产阶段延后

#### 🔴 Must Have — Foundation 层（写任何 GDD 前必须定）

| ADR | 标题 | 覆盖决策 | 阻塞什么 |
|-----|------|---------|---------|
| ADR-0001 | 事件总线架构 | 全局单例 vs 场景树信号；事件命名规范；payload 类型约束 | 所有系统间通信 |
| ADR-0002 | 数据定义格式 | `.tres` Resource vs JSON vs 硬编码 const；枚举定义规范 | 所有系统的数据引用 |
| ADR-0003 | GameState 状态机设计 | enum + match vs 节点状态机；状态转换矩阵；非法转换处理 | 回合管理、UI 切换 |
| ADR-0004 | 回合结算模型 | 两阶段提交（收集→同时结算）；指令顺序无关性；回滚策略 | 出征、战斗、生产 |

#### 🟡 Should Have — Core 层（对应系统 GDD 写之前）

| ADR | 标题 | 覆盖决策 | 阻塞什么 |
|-----|------|---------|---------|
| ADR-0005 | 星球数据模型 | `PlanetData` 用 Resource 还是 Dictionary；属性系统扩展性 | 星球系统、生产系统、星图数据 |
| ADR-0006 | 战斗公式设计 | 伤害公式选定；三角克制矩阵；战损取整规则 | 兵种系统、战斗结算、AI |
| ADR-0007 | AI 决策架构 | 规则驱动 vs 效用函数；威胁评估算法；行为树可行性 | AI 敌人 |
| ADR-0008 | 国王寿命模型 | 行动消耗公式；天赋系统扩展性；去世/继位流程 | 国王系统 |

#### 🟢 Can Defer — Production 阶段

| ADR | 标题 | 覆盖决策 |
|-----|------|---------|
| ADR-0009 | 存档序列化格式 | JSON vs Godot 二进制；版本号策略；向后兼容 |
| ADR-0010 | UI 架构模式 | 信号驱动 vs 直接调用；Control 节点层级规范 |

---

## GDD 缺口清单

| 顺序 | 系统 | 层 | 前置 ADR | 可并行 |
|------|------|----|---------|--------|
| 1 | 数据定义 | Foundation | ADR-0001, ADR-0002 | — |
| 2 | 事件总线 | Foundation | ADR-0001 | ✅ 与 #1 并行 |
| 3 | GameState 管理器 | Foundation | ADR-0003 | ✅ 与 #1, #2 并行 |
| 4 | 回合管理器 | Foundation | ADR-0001, ADR-0004 | 在 #1, #2 完成后 |
| 5 | 星球系统 | Core | ADR-0005 | — |
| 6 | 兵种系统 | Core | ADR-0006 | ✅ 与 #5 并行 |
| 7 | 生产系统 | Core | ADR-0005 | ❌ |
| 8 | 战斗结算 | Core | ADR-0006 | ❌ |
| 9 | 占领系统 | Core | ADR-0005 | ❌ |
| 10 | 出征系统 | Core | ADR-0005, ADR-0006 | ❌ |
| 11 | 国王系统 | Core | ADR-0008 | ❌ |
| 12 | AI 敌人 | Core | ADR-0007 | ❌ |
| 13 | 星图数据 | Feature | — | ❌ |
| 14 | 胜负条件 | Feature | — | ❌ |
| 15-19 | UI ×5 | Presentation | ADR-0010 | ✅ 5 个间可并行 |

---

## 推荐执行路线

```
Step 1: ✅ /architecture-decision ×8
        → ADR-0001~0004 Foundation 层 (4 ADRs)
        → ADR-0005~0008 Core 层 (4 ADRs)

Step 2: ✅ Foundation 层 GDD ×4 (数据定义, 事件总线, GameState管理器, 回合管理器)
        ✅ Core 层 GDD ×8 (星球, 兵种, 生产, 战斗结算, 占领, 出征, 国王, AI)

Step 3: /review-all-gdds → Core 层 GDD 验证

Step 4: /create-epics layer: core

Step 5: /create-stories → 拆任务

Step 6: /sprint-plan → 排期

Step 7: /dev-story → 开工写代码
```

---

## Open Questions

| ID | 问题 | 优先级 | 解决路径 |
|----|------|--------|---------|
| QQ-01 | 事件总线用 Godot 原生 Signal 还是自定义 Dictionary 分发？ | High | ADR-0001 |
| QQ-02 | 星球间连接路线用图数据结构还是关卡数据手配？ | Medium | ADR-0005 + 星图数据 GDD |
| QQ-03 | AI 强度参数暴露给关卡配置还是硬编码？ | Medium | ADR-0007 |
| QQ-04 | 回合结算时若 A→B 和 C→A 同时执行，更新顺序是否影响结果？ | High | ADR-0004 |
