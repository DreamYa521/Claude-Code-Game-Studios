# Story 003: Resource Loading & Error Handling

> **Epic**: data-definitions
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Integration
> **Estimate**: 2h
> **Manifest Version**: 2026-05-31
> **Last Updated**: —

## Context

**GDD**: `design/gdd/data-definitions.md`
**Requirement**: TR-DEF-010, TR-DEF-011
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0002: 数据定义格式
**ADR Decision Summary**: DataDef `_ready()` 中一次性 `load()` 所有 .tres 文件，缓存为成员变量。所有其他系统通过 `DataDef.unit_stats` / `DataDef.level_data` 直接访问缓存。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `load()` 是 Godot 内置 ResourceLoader 的同步方法，在 autoload `_ready()` 中调用安全。Resource 加载失败返回 `null` 或报错。

**Control Manifest Rules (this layer)**:
- Required: DataDef._ready() 中一次性 load() 所有 .tres，缓存为成员变量
- Required: .tres 文件加载失败时 push_error() 输出具体文件名 + 游戏不进入 PLAYING 状态
- Required: DataDef 设为 autoload 列表第一位，确保其他 autoload 初始化时数据已可用
- Guardrail: 运行时不产生额外文件 I/O
- Guardrail: DataDef load() 在 _ready() 中一次性完成

---

## Acceptance Criteria

*From GDD `design/gdd/data-definitions.md`, scoped to this story:*

- [ ] **AC-1**: 游戏启动，DataDef autoload 初始化完成，`DataDef.unit_stats` 非 null，`DataDef.level_data` 非 null
- [ ] **AC-2**: 修改 `unit_stats.tres` 中步兵 `attack` 从 10.0 改为 12.0，重启游戏，`DataDef.unit_stats.infantry.attack` 返回 12.0
- [ ] **AC-3**: LevelData .tres 定义了 4 颗星球和 4 条连接，`DataDef.level_data.planets.size()` 返回 4
- [ ] **AC-4**: 加载的 .tres 文件格式损坏或缺失，`push_error()` 输出具体文件名 + 游戏不进入 PLAYING 状态

---

## Implementation Notes

*Derived from ADR-0002:*

**1. 扩展 `data_definitions.gd` — 添加 Resource 加载逻辑**:

```gdscript
# data_definitions.gd — autoload: DataDef (追加内容，Story 001 已有枚举/常量部分)

# === Resource 缓存（运行时只读）===
var unit_stats: UnitStatsTable
var level_data: LevelData

func _ready() -> void:
    _load_resources()

func _load_resources() -> void:
    # 加载兵种属性表
    unit_stats = load("res://resources/unit_stats.tres") as UnitStatsTable
    if unit_stats == null:
        push_error("DataDef: Failed to load res://resources/unit_stats.tres — file missing or corrupt")
        return
    
    # 加载关卡数据
    level_data = load("res://resources/levels/tutorial_1.tres") as LevelData
    if level_data == null:
        push_error("DataDef: Failed to load res://resources/levels/tutorial_1.tres — file missing or corrupt")
        return
    
    print("DataDef: All resources loaded successfully.")
```

**2. 创建具体 .tres 实例文件**:

**`resources/unit_stats.tres`** — 在 Godot 编辑器中创建:
1. 右键 `resources/` 文件夹 → New Resource
2. 选择 `UnitStatsTable`
3. 分别设置 infantry/archer/cavalry 的 `UnitStats` 子资源:
   - infantry: unit_type=INFANTRY, attack=10.0, defense=8.0, move_speed=1.0
   - archer: unit_type=ARCHER, attack=12.0, defense=5.0, move_speed=1.2
   - cavalry: unit_type=CAVALRY, attack=15.0, defense=6.0, move_speed=1.5
4. 保存为 `unit_stats.tres`

**`resources/levels/tutorial_1.tres`** — 在 Godot 编辑器中创建:
1. 创建目录 `resources/levels/`
2. 右键 → New Resource → LevelData
3. 配置 4 颗星球和 3 条连接（MVP 关卡数据）:
   - 地球 (id=1, PLAYER, NORMAL), 月球 (id=2, NEUTRAL, NORMAL), 火星 (id=3, ENEMY, NORMAL), 火卫一 (id=4, NEUTRAL, NORMAL)
   - 连接: 地→月, 月→火, 火→火卫一
4. 保存为 `tutorial_1.tres`

**3. 错误处理策略**:
- `load()` 返回 `null` → `push_error()` + 提前返回（不继续加载后续文件）
- 所有 .tres 加载完毕后检查完整性 → 任一失败则 `GameState` 不进入 `PLAYING`
- 不在 `_ready()` 中调用 `GameState.transition_to()` — 由外部初始化流程检查 DataDef 就绪状态

**4. 访问模式**:
- 所有系统通过 `DataDef.unit_stats` / `DataDef.level_data` 读取缓存
- 运行时无文件 I/O — 只在 `_ready()` 中 load 一次
- Resource 缓存对外只读（约定，非语言强制）

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: 枚举定义（UnitType, Faction, DAMAGE_MATRIX, 全局常量）
- Story 002: Resource 类定义（UnitStatsTable, LevelData 等 .gd 文件）
- 多关卡切换（MVP 只加载一个 `tutorial_1.tres`）

---

## QA Test Cases

- **AC-1**: 启动加载验证
  - Given: 所有 .tres 文件存在于正确路径
  - When: 游戏启动，DataDef._ready() 执行完毕
  - Then: `DataDef.unit_stats != null` 且 `DataDef.level_data != null`；`DataDef.unit_stats.infantry.attack == 10.0`
  - Edge cases: 检查所有三种兵种属性均加载（infantry/archer/cavalry 非 null）

- **AC-2**: .tres 数值热更新验证
  - Given: `unit_stats.tres` 中步兵 attack = 10.0
  - When: 在 Godot 编辑器中改为 12.0，重启游戏
  - Then: `DataDef.unit_stats.infantry.attack == 12.0`（反映修改后的值）
  - Edge cases: 修改 defense、move_speed 等其他字段 → 同样反映新值

- **AC-3**: LevelData 内容验证
  - Given: `tutorial_1.tres` 定义了 4 颗星球和 3 条连接
  - When: 读取 `DataDef.level_data.planets.size()` 和 `DataDef.level_data.connections.size()`
  - Then: planets.size() == 4, connections.size() == 3
  - Edge cases: 验证第一颗星球 id==1, name=="地球"；验证 connections[0] 的 from/to 对应存在的 planet id

- **AC-4**: 损坏文件错误处理
  - Given: `resources/unit_stats.tres` 文件被删除或内容损坏
  - When: 游戏启动，DataDef._ready() 执行
  - Then: `push_error()` 输出包含具体文件名 `res://resources/unit_stats.tres`；游戏启动但不进入 PLAYING 状态
  - Edge cases: 文件存在但格式错误（如手动编辑 .tres 破坏了结构）→ 同样触发 push_error

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- Integration: `tests/integration/data-definitions/test_resource_loading.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 002 (Resource Classes Definition) — 需要 UnitStatsTable/LevelData 等 Resource 类已定义为 class_name
- Depends on: Story 001 (Enums & Constants Definition) — 需要 DataDef autoload 骨架
- Unlocks: None（Foundation data-definitions 最后一个 Story；解锁下游所有需要 DataDef 的系统）
