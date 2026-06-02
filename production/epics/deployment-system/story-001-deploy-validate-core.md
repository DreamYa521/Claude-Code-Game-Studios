# Story 001: deploy() + validate() + DeploymentCommand 核心逻辑

> **Epic**: 出征系统 (deployment-system)
> **Status**: Ready
> **Layer**: Core
> **Type**: Logic
> **Estimate**: 2h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/deployment-system.md`
**Requirement**: `TR-DPL-001`, `TR-DPL-002`, `TR-DPL-003`, `TR-DPL-005`, `TR-DPL-006`, `TR-DPL-007`

**ADR Governing Implementation**: ADR-0004: 回合结算模型 (快照步骤1收集指令); ADR-0005: 星球数据模型 (garrison 扣减走 update_garrison)
**ADR Decision Summary**: deploy(from, to, count, unit_type) 创建 DeploymentCommand 并入队，校验通过后立即扣减 garrison 防止同批兵重复使用。同星多条指令逐条校验 `count <= 实时garrison`，自动防超限。MVP 默认步兵。已提交指令不可撤销（确认即承诺）。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: 纯数据操作 + Dictionary 读写，无引擎 API 依赖。DeploymentCommand 用 RefCounted 或 Dictionary。

**Control Manifest Rules (this layer)**:
- Required: deploy() 7 项校验 — 己方星/非己方目标/相邻/≥1兵/≤驻兵/is_playing/DEPLOYMENT阶段 — source: ADR-0004
- Required: submit_command() 后立即扣除出发星驻兵 — 防止同一批兵重复使用 — source: ADR-0004
- Forbidden: 禁止已提交指令撤销 — 确认即承诺，无回滚机制 — source: ADR-0004
- Guardrail: 10星/20指令 < 1ms

---

## Acceptance Criteria

*From GDD `design/gdd/deployment-system.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN 己方星 A (garrison=10) 邻敌方星 B，WHEN `deploy(A, B, 5, INFANTRY)`，THEN 返回 true，A.garrison 变为 5
- [ ] **AC-2**: GIVEN 己方星 A (garrison=3)，WHEN `deploy(A, B, 5, INFANTRY)`，THEN 返回 false（兵力不足），A.garrison 保持 3
- [ ] **AC-3**: GIVEN A 和 B 不相邻，WHEN `deploy(A, B, 3, INFANTRY)`，THEN 返回 false（不能跳星出兵）
- [ ] **AC-4**: GIVEN 目标星 owner=PLAYER，WHEN `deploy(A, B, 3, INFANTRY)`，THEN 返回 false（不能打自己）
- [ ] **AC-5**: GIVEN 出发星 owner 不是 PLAYER（如 NEUTRAL），WHEN `deploy(A, B, 3, INFANTRY)`，THEN 返回 false
- [ ] **AC-6**: GIVEN count < 1（如 0 或 -1），WHEN `deploy(A, B, count, INFANTRY)`，THEN 返回 false
- [ ] **AC-7**: GIVEN 从 A 发出 2 条指令（5兵→B, 3兵→C，初始 garrison=10），WHEN 两条指令都执行，THEN 第1条成功（A剩5），第2条成功（A剩2），get_pending() 返回 2 条
- [ ] **AC-8**: GIVEN 从 A 发出 2 条指令（8兵→B, 5兵→C，初始 garrison=10），WHEN 逐条执行，THEN 第1条成功（A剩2），第2条失败（剩余2不够5），get_pending() 返回 1 条
- [ ] **AC-9**: GIVEN 部署到空旷中立星 B (garrison=0)，WHEN `deploy(A, B, 3, INFANTRY)`，THEN 返回 true（允许发兵到空星）
- [ ] **AC-10**: GIVEN 已提交的指令，WHEN 尝试撤销，THEN 不存在撤销 API（设计意图：不可撤销）

---

## Implementation Notes

*Derived from ADR-0004 and GDD deployment-system.md:*

### 核心结构

```gdscript
# deployment_command.gd
class_name DeploymentCommand extends RefCounted
var from_planet: int
var to_planet: int
var count: int
var unit_type: int          # DataDef.UnitType
var player_owned: bool       # true=玩家指令, false=AI指令
```

### 核心函数

```gdscript
# deployment_system.gd (本 Story 为独立类，不依赖 autoload)
class_name DeploymentSystem

var _pending_commands: Array[DeploymentCommand] = []

## 核心部署接口
## planets: Dictionary[int -> planet_data] — 直接传入 Dictionary 供隔离测试
## connections: Array[Array] — [[from, to], ...] 邻接表
func deploy(from: int, to: int, count: int, unit_type: int,
            planets: Dictionary, connections: Array,
            is_playing: bool, current_phase: int) -> bool:
    
    var reason := ""
    if not _validate(from, to, count, planets, connections, is_playing, current_phase, reason):
        push_warning("deploy rejected: %s" % reason)
        return false
    
    # 创建指令
    var cmd := DeploymentCommand.new()
    cmd.from_planet = from
    cmd.to_planet = to
    cmd.count = count
    cmd.unit_type = unit_type
    cmd.player_owned = true
    
    _pending_commands.append(cmd)
    
    # 立即扣减出发星驻兵
    planets[from].garrison -= count
    
    return true

## 7 项合法性校验
func _validate(from: int, to: int, count: int,
               planets: Dictionary, connections: Array,
               is_playing: bool, current_phase: int,
               out_reason: String) -> bool:
    
    # 1. 只能在游戏中部署
    if not is_playing:
        out_reason = "not in PLAYING state"
        return false
    
    # 2. 只能在 DEPLOYMENT 阶段
    if current_phase != TurnPhase.DEPLOYMENT:  # 由 DataDef 定义
        out_reason = "not in DEPLOYMENT phase"
        return false
    
    # 3. 出发星必须存在且己方
    if not planets.has(from):
        out_reason = "from planet not found"
        return false
    if planets[from].owner != DataDef.Faction.PLAYER:
        out_reason = "from planet not owned by PLAYER"
        return false
    
    # 4. 目标星必须存在且非己方
    if not planets.has(to):
        out_reason = "to planet not found"
        return false
    if planets[to].owner == DataDef.Faction.PLAYER:
        out_reason = "cannot attack own planet"
        return false
    
    # 5. 必须相邻
    if not _are_connected(from, to, connections):
        out_reason = "planets not connected"
        return false
    
    # 6. 至少出 1 兵
    if count < 1:
        out_reason = "count must be >= 1"
        return false
    
    # 7. 不能超出发星驻兵
    if count > planets[from].garrison:
        out_reason = "insufficient garrison"
        return false
    
    return true

func _are_connected(a: int, b: int, connections: Array) -> bool:
    for conn in connections:
        if (conn[0] == a and conn[1] == b) or (conn[0] == b and conn[1] == a):
            return true
    return false

func get_pending() -> Array[DeploymentCommand]:
    return _pending_commands

func clear_pending() -> void:
    _pending_commands.clear()
```

### 关键实现要点

- `DeploymentCommand` 用 `RefCounted` 而不是 `Resource` — 避免深拷贝语义问题（ADR-0005 禁止 Resource 用于运行时数据）
- `_validate()` 参数显式传入所有依赖（planets, connections, is_playing, current_phase）— 纯函数化，可隔离单元测试
- `_are_connected()` 检查双向邻接 — `are_connected(a,b) == are_connected(b,a)`
- 校验顺序：先检查全局状态（is_playing/phase），再检查数据完整性，最后检查数值边界 — 性能最优
- `deploy()` 返回 bool 并输出 warning — 调用方（UI）可直接用返回值判断成功/失败
- `_pending_commands` 是内部列表，通过 `get_pending()` 对外暴露只读访问
- 本 Story 不集成 TurnManager/PlanetSystem/GameState — 通过参数传入所有依赖，在 story-002 中集成

### 测试数据构造

```gdscript
var test_planets = {
    1: {"garrison": 10, "owner": DataDef.Faction.PLAYER},
    2: {"garrison": 5, "owner": DataDef.Faction.ENEMY},
    3: {"garrison": 3, "owner": DataDef.Faction.PLAYER},
}

var test_connections = [
    [1, 2],   # A-B 相邻
    [1, 3],   # A-C 相邻（己方-己方，不可攻击）
]
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: `get_pending()` 与 TurnManager 步骤 1 集成、PlanetSystem.update_garrison() 实际调用、GameState.is_playing() 实际接入、TurnManager.current_phase 实际接入、EventBus 广播
- 出征 UI: 兵力滑块、确认/取消交互、星图点击路由
- 回合管理器: `submit_command()` 方法、`_collect_commands()`
- AI 敌人: 生成 `DeploymentCommand`（通过同一结构体）

---

## QA Test Cases

*Derived from GDD acceptance criteria. The developer implements against these.*

- **AC-1**: 基本部署成功
  - Given: planets[1] owner=PLAYER garrison=10; planets[2] owner=ENEMY; connections=[[1,2]]; is_playing=true; phase=DEPLOYMENT
  - When: `deploy(1, 2, 5, INFANTRY, planets, connections, true, DEPLOYMENT)`
  - Then: returns true, planets[1].garrison == 5, pending count == 1

- **AC-2**: 兵力不足
  - Given: planets[1] garrison=3
  - When: `deploy(1, 2, 5, INFANTRY, ...)`
  - Then: returns false, planets[1].garrison == 3 (unchanged), pending count == 0

- **AC-3**: 不相邻
  - Given: connections 不包含 [1, 2]
  - When: `deploy(1, 2, 3, INFANTRY, ...)`
  - Then: returns false

- **AC-4**: 攻击己方
  - Given: planets[2] owner=PLAYER
  - When: `deploy(1, 2, 3, INFANTRY, ...)`
  - Then: returns false

- **AC-5**: 非己方出发星
  - Given: planets[1] owner=NEUTRAL
  - When: `deploy(1, 2, 3, INFANTRY, ...)`
  - Then: returns false

- **AC-6**: 无效兵数
  - Given: count=0 or count=-1
  - When: `deploy(1, 2, count, INFANTRY, ...)`
  - Then: returns false

- **AC-7**: 同星多条成功
  - Given: planets[1] garrison=10
  - When: deploy(1,2,5,...) → deploy(1,3,3,...)
  - Then: both return true; garrison=2; pending count=2

- **AC-8**: 同星第二条失败
  - Given: planets[1] garrison=10
  - When: deploy(1,2,8,...) → deploy(1,3,5,...)
  - Then: 1st returns true; 2nd returns false; garrison=2; pending count=1

- **AC-9**: 部署到空星
  - Given: planets[2] garrison=0 owner=NEUTRAL
  - When: `deploy(1, 2, 3, INFANTRY, ...)`
  - Then: returns true (空星允许部署，战斗结算时 attacker_wins=true)

- **AC-10**: 非 DEPLOYMENT 阶段拒绝
  - Given: current_phase=EXECUTION
  - When: `deploy(1, 2, 3, INFANTRY, ...)`
  - Then: returns false

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- Logic: `tests/unit/deployment-system/deploy_validate_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Foundation data-definitions (TR-DEF-002 UnitType, TR-DEF-003 Faction) — must be DONE
- Depends on: Foundation turn-manager (TurnPhase 枚举) — must be DONE
- Unlocks: Story 002 (deployment-integration)
