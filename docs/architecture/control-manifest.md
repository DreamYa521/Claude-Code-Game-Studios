# Control Manifest

> **Engine**: Godot 4.6
> **Last Updated**: 2026-05-31
> **Manifest Version**: 2026-05-31
> **ADRs Covered**: ADR-0001, ADR-0002, ADR-0003, ADR-0004, ADR-0005, ADR-0006, ADR-0007, ADR-0008
> **Status**: Active — regenerate with `/create-control-manifest` when ADRs change

This manifest is a programmer's quick-reference extracted from all Accepted ADRs,
technical preferences, and engine reference docs. For the reasoning behind each
rule, see the referenced ADR.

---

## Foundation Layer Rules

*Applies to: DataDef, EventBus, GameState, TurnManager*

### Required Patterns

- **DataDef autoload 是唯一数据入口** — 所有系统通过 `DataDef` 访问枚举/常量/Resource，禁止在系统文件中重复定义 — source: ADR-0002
- **枚举和常量用 GDScript，可调数值用 .tres Resource** — DAMAGE_MATRIX/全局常量放 GDScript const；UnitStats/LevelData 放 .tres — source: ADR-0002
- **DataDef 设为 autoload 列表第一位** — `_ready()` 中一次性 `load()` 所有 .tres，缓存为成员变量 — source: ADR-0002
- **EventBus autoload 集中管理全部跨系统 Signal** — 系统间禁止直接 connect（`PlanetSystem.signal.connect()` ❌），必须走 `EventBus.signal.connect()` — source: ADR-0001
- **Signal 命名：snake_case 过去时** — 参数顺序：主体ID → 旧值 → 新值；新增 Signal 只追加到文件末尾，不删除不重命名 — source: ADR-0001
- **12 个 Signal 目录已在 ADR-0001 定义** — 实现时必须全部声明，不可遗漏 — source: ADR-0001
- **长期订阅在 _ready() 中 connect()，短期订阅在 _exit_tree() 中显式 disconnect()** — source: ADR-0001
- **GameState 用 enum State {TITLE, PLAYING, PAUSED, VICTORY, DEFEAT} + match 实现** — 5 状态 7 条合法转换 — source: ADR-0003
- **current_state 对外只读 getter** — 唯一写入路径是 `transition_to()`，禁止外部直接赋值 — source: ADR-0003
- **每次合法转换自动广播 `EventBus.game_state_changed.emit(old, new)`** — source: ADR-0003
- **TurnManager 3 阶段循环 DEPLOYMENT→EXECUTION→CLEANUP→DEPLOYMENT** — 阶段不可跳转，`current_phase` 枚举控制 — source: ADR-0004
- **5 步骤快照模型：收集指令→拍快照→基于快照计算→统一应用→收尾** — `end_turn()` 触发，步骤 2-4 保证顺序无关 — source: ADR-0004
- **超限兵力按比例削减** — `ratio = available_garrison / total_outgoing`，各指令 `count = floor(count × ratio)` — source: ADR-0004
- **阶段切换通过 EventBus 广播** — `deployment_phase_started` → `execution_phase_started` → `turn_ended` 严格按序 — source: ADR-0004

### Forbidden Approaches

- **禁止在系统文件中重复定义枚举或硬编码数值** — 一切通过 DataDef 引用 — source: ADR-0002
- **禁止跨系统直接 connect** — `PlanetSystem.signal.connect()` ❌，必须走 EventBus — source: ADR-0001
- **禁止使用字符串分发事件** — `EventBus.emit("planet_owner_changed", {})` ❌，用 Godot 原生 Signal — source: ADR-0001
- **禁止修改 EventBus 中已有 Signal 名或参数类型** — 破坏性变更影响所有订阅方 — source: ADR-0001
- **禁止在 EventBus 的 callback 中再次 emit 同一 Signal** — 防止无限递归 — source: ADR-0001
- **禁止直接赋值 `current_state`** — 必须通过 `transition_to()` — source: ADR-0003
- **禁止在 EXECUTION/CLEANUP 阶段调用 `submit_command()`** — 返回 false — source: ADR-0004
- **禁止在 DEPLOYMENT 之外调用 `end_turn()`** — 返回 false + push_warning() — source: ADR-0004
- **禁止顺序执行指令** — 必须基于快照同时计算，保证顺序无关 — source: ADR-0004
- **禁止 Signal 参数使用裸 String/int 做系统类型** — 全部类型来自 DataDef（Faction, KingData, BattleResult, GameState.State） — source: ADR-0001

### Performance Guardrails

- **回合结算**: 10星/20指令 < 1ms（纯数据操作） — source: ADR-0004
- **EventBus**: Signal emit + 回调链，回合粒度下事件量 < 100/回合，无性能压力 — source: ADR-0001
- **DataDef load()**: 在 `_ready()` 中一次性完成，运行时不产生额外开销 — source: ADR-0002
- **GameState**: enum 比较 + match 是 O(1)，无测量意义 — source: ADR-0003

---

## Core Layer Rules

*Applies to: PlanetSystem, UnitSystem, ProductionSystem, CombatSystem, OccupationSystem, DeploymentSystem, KingSystem, AIEnemy*

### Required Patterns

- **RuntimePlanetData 用 Dictionary 存储，静态 PlanetDef 用 .tres Resource** — 静态/动态分离 — source: ADR-0005
- **邻接表初始化时构建，运行时只读** — `are_connected(a, b)` O(1)，`get_adjacent_planets(id)` 返回 Array[int] — source: ADR-0005
- **get_planet() 返回浅拷贝** — 防止外部直接修改内部状态；修改走 `update_garrison()` / `set_owner()` — source: ADR-0005
- **take_snapshot() 用 Dictionary.duplicate(true) 深拷贝** — Dictionary 深拷贝在 Godot 4.x 全版本一致 — source: ADR-0005
- **set_owner() 内部广播 EventBus.planet_owner_changed** — source: ADR-0005
- **update_garrison() 阶段 gate** — 只在 DEPLOYMENT 和 CLEANUP 阶段接受修改 — source: ADR-0005
- **战斗公式用比例力量模型** — `A_power = count × attack × counter_mult`，`D_power = count × defense × planet_defense_mult` — source: ADR-0006
- **CombatSystem.resolve() 是纯函数** — 不访问全局状态，同输入永远同输出 — source: ADR-0006
- **1v1 等力特例** — 双方各 1 兵且 A_power==D_power → 防守方胜 — source: ADR-0006
- **空星球 (defender_count=0) → attacker_wins=true, 双方损失=0** — source: ADR-0006
- **最小损失为 1** — `max(1, round(count × loss_rate))`，确保每场战斗都有代价 — source: ADR-0006
- **累积产量模型** — `accumulated_production += production_rate`，`floor()≥1` 时产兵 — source: ADR-0005
- **生产在 CLEANUP 步骤 5 执行** — 在占领变更后，确保新占星参与当回合生产 — source: ADR-0004
- **步骤 4 应用顺序：先玩家指令后 AI 指令** — 保证结果确定性 — source: ADR-0004
- **deploy() 7 项校验** — 己方星/非己方目标/相邻/≥1兵/≤驻兵/is_playing/DEPLOYMENT阶段 — source: ADR-0004
- **submit_command() 后立即扣除出发星驻兵** — 防止同一批兵重复使用 — source: ADR-0004
- **AI 分阶段规则引擎：防御→进攻→冲突消解** — `compute_turn()` 在步骤 1 调用 — source: ADR-0007
- **AI 三参数可调：aggression/defensiveness/intelligence** — 默认全 0.5 — source: ADR-0007
- **AI 用 CombatSystem.resolve() 预估战斗** — 与真实结算同一公式 — source: ADR-0007
- **KingData 结构：name/talent/lifespan/actions_used/age/generation/talent_bonus** — source: ADR-0008
- **每回合消耗 1 寿命** — `consume_turn()` 在 CLEANUP 步骤 5 调用 — source: ADR-0008
- **国王去世流程：emit king_died → GameState→PAUSED → 自动继位 → emit king_succeeded → GameState→PLAYING** — source: ADR-0008
- **MVP 天赋仅为标签** — talent_bonus Dictionary 留空 `{}` — source: ADR-0008
- **AI 不使用国王系统** — 无寿命约束，无代际传承 — source: ADR-0008

### Forbidden Approaches

- **禁止 Resource 用于运行时星球数据** — Resource 深拷贝语义在 4.5 变更（`duplicate(true)` → `duplicate_deep()`） — source: ADR-0005
- **禁止 `Resource.duplicate(true)` 做深拷贝** — 4.5+ 只复制内部资源。用 `duplicate_deep(DEEP_DUPLICATE_ALL)` — source: ADR-0002
- **禁止战斗中使用随机数** — 违背"从容推演"Pillar，不可复现 — source: ADR-0006
- **禁止固定交换比战斗公式** — 线性缩放在策略游戏中缺乏深度 — source: ADR-0006
- **禁止兰彻斯特平方律** — 对玩家不直观，小数值离散误差大 — source: ADR-0006
- **禁止连接单向假设** — 所有连接双向，`are_connected(a,b) == are_connected(b,a)` — source: ADR-0005
- **禁止 NEUTRAL 星球产兵** — 只等待被占领 — source: ADR-0005
- **禁止已提交指令撤销** — 确认即承诺，无回滚机制 — source: ADR-0004
- **禁止 AI 读取玩家未提交指令** — AI 只读实时星球状态 — source: ADR-0007
- **禁止 AI 从 garrison=0 的星球发兵** — source: ADR-0007
- **禁止 `garrison < 0`** — update_garrison() delta 导致负数返回 false — source: ADR-0005

### Performance Guardrails

- **战斗结算**: 每场 ~10 浮点运算，MVP 最多 20 场/回合 < 1ms — source: ADR-0006
- **AI 决策**: 最坏 10星×3邻×3兵种 = 90 次 resolve()，< 2ms — source: ADR-0007
- **PlanetSystem**: 10星规模所有操作 O(1) 或 O(N)（N≤10），无测量意义 — source: ADR-0005
- **KingSystem**: 字段更新 + 条件检查，不可测量 — source: ADR-0008

---

## Feature Layer Rules

*Applies to: LevelData, WinConditions*

### Required Patterns

- **LevelData Resource 存储在 .tres** — 设计师在 Godot 编辑器中可视化编辑 — source: ADR-0002
- **MVP 关卡 tutorial_1：4星+3连接** — 地球(PLAYER)/月球(NEUTRAL)/火星(ENEMY)/火卫一(NEUTRAL) — source: ADR-0005
- **关卡初始化：PlanetSystem.init_from_level(level_data)** — 遍历 planets→connections→initial_owner→initial_garrison — source: ADR-0005
- **check_victory()：get_planets_by_owner(ENEMY).is_empty()** — source: ADR-0003
- **check_defeat()：get_planets_by_owner(PLAYER).is_empty()** — source: ADR-0003
- **check() 在生产后、国王消耗前执行** — 顺序保证：先判胜负再消耗寿命 — source: ADR-0004
- **双方同时全灭 → DEFEAT** — 平局算玩家输 — source: ADR-0003
- **国王寿命耗尽不算输** — 代际传承是机制不是终点 — source: ADR-0008

### Forbidden Approaches

- **禁止 PlanetDef.id 重复** — init_from_level() 检测到重复 push_error() — source: ADR-0005
- **禁止 Connection 引用不存在星球** — 跳过 + push_warning() — source: ADR-0005

---

## Presentation Layer Rules

*Applies to: StarMapUI, DeploymentUI, TurnControlUI, KingUI, BattleAnimation*

### Required Patterns

- **UI 组件全部通过 EventBus 订阅刷新** — 不轮询，不直接读其他系统状态 — source: ADR-0001
- **星图 UI 渲染：圆形节点(24px) + 颜色区分(蓝/红/灰) + 2px连接线 + 兵力数字** — source: ADR-0001
- **选中交互：点己方星→高亮相邻敌星→点敌星触发出征UI** — source: ADR-0001
- **出征 UI：兵力滑块(1~garrison, 默认全量) + 动态'出发星剩余' + 确认/取消** — source: ADR-0001
- **回合控制 UI：DEPLOYMENT可用/EXECUTION禁用'结算中...'/CLEANUP禁用'收尾中...'/非PLAYING隐藏** — source: ADR-0003
- **快捷键：Space/E→结束回合，ESC→取消出征，Enter→确认发兵** — source: ADR-0003
- **国王 UI 常驻面板：代际+天赋标签+名字+寿命条+数字，左上角固定** — source: ADR-0008
- **寿命条颜色：绿(>50%)→黄(30-50%)→橙(10-30%)→红(<10%)，≤3时闪烁** — source: ADR-0008
- **战斗动画：并行播放移动短线(400px/s)→到达时占领闪烁(3次×150ms)→全部完成emit turn_ended** — source: ADR-0004
- **动画期间星图不接受点击** — 全部完成后恢复操作 — source: ADR-0004
- **跳过动画选项：点击屏幕瞬移→单次闪→立即进入步骤5** — source: ADR-0004

### Forbidden Approaches

- **禁止 UI 直接修改星球状态** — UI 只读和发指令，修改通过系统 API — source: ADR-0001
- **禁止动画期间接受玩家操作** — source: ADR-0004

### Performance Guardrails

- **星图渲染**: MVP 4 星 < 10 draw calls — source: ADR-0001
- **动画**: 20 条指令并行，每条 ≤ 0.75s，总时长 < 1s — source: ADR-0004
- **设置默认跳过动画** → false（首次体验不跳过） — source: ADR-0004

---

## Global Rules (All Layers)

### Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Classes | PascalCase | `PlayerController` |
| Variables | snake_case | `move_speed` |
| Functions | snake_case | `take_damage()` |
| Signals | snake_case past tense | `health_changed` |
| Files | snake_case matching class | `player_controller.gd` |
| Scenes | PascalCase matching root | `PlayerController.tscn` |
| Constants | UPPER_SNAKE_CASE | `MAX_HEALTH` |

Source: `.claude/docs/technical-preferences.md`

### Performance Budgets

| Target | Value |
|--------|-------|
| Framerate | 60fps |
| Frame budget | 16.6ms |
| Draw calls | 500 (2D pixel art) |
| Memory ceiling | 512MB |

Source: `.claude/docs/technical-preferences.md`

### Forbidden GDScript APIs (Godot 4.6)

| ❌ Don't Use | ✅ Use Instead |
|-------------|---------------|
| `yield()` | `await` |
| `instance()` | `instantiate()` |
| `connect("signal", obj, "method")` | `signal.connect(callable)` |
| `get_world()` | `get_world_2d()` / `get_world_3d()` |
| `OS.get_ticks_msec()` | `Time.get_ticks_msec()` |
| `VisibilityNotifier2D` | `VisibleOnScreenNotifier2D` |
| `YSort` node | `Node2D.y_sort_enabled` property |
| `TileMap` (multi-layer) | `TileMapLayer` (one per layer) |
| `Resource.duplicate(true)` for deep copy | `Resource.duplicate_deep(DEEP_DUPLICATE_ALL)` |
| `@export_file` for res:// paths | `@export_file_path` |
| `JSONRPC.set_scope()` | `JSONRPC.set_method()` |
| String-based signal connections | Typed `signal.connect(callable)` |
| Untyped `Array` / `Dictionary` | `Array[Type]`, typed variables |

Source: `docs/engine-reference/godot/deprecated-apis.md`, `docs/engine-reference/godot/breaking-changes.md`

### Patterns to Avoid (All Layers)

| ❌ Pattern | ✅ Better |
|-----------|----------|
| `$NodePath` inside `_process()` | `@onready var` cached reference |
| Hardcoded game values | Reference via `DataDef` |
| Signals with bare String/int types | Use DataDef types |
| `ProjectSettings.add_property_info()` with `usage` key | Use `set_as_basic()`/`set_restart_if_changed()`/`set_as_internal()` |
| `FileAccess.store_*()` without checking return | Always check `bool` return value |

### GDScript 4.5+ Features (Available for Use)

- **`@abstract` class + method** — enforce subclass implementation
- **Variadic arguments** — `func log(prefix: String, values: Variant...) -> void`
- **Typed Arrays** — `func process(items: Array[int]) -> void`
- **Script backtracing** — available in Release builds since 4.5

### Cross-Cutting Constraints

- **数据驱动**: 所有游戏数值通过 DataDef 引用，禁止硬编码 — source: ADR-0002
- **EventBus 唯一通道**: 系统间通信只走 EventBus — source: ADR-0001
- **快照模型**: 回合结算必须基于快照，保证指令顺序无关 — source: ADR-0004
- **确定性**: 战斗/AI(intelligence=1.0) 必须同输入→同输出 — source: ADR-0006, ADR-0007
- **阶段 Gate**: 所有系统检查 TurnManager.current_phase 和 GameState.is_playing() — source: ADR-0003, ADR-0004
- **Resource 字段只增不删不重命名** — 旧字段 @deprecated 标记保留 — source: ADR-0002
