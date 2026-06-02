# Story 002: 回合管线集成 + get_pending() + PlanetSystem 对接

> **Epic**: 出征系统 (deployment-system)
> **Status**: Ready
> **Layer**: Core
> **Type**: Integration
> **Estimate**: 2h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/deployment-system.md`
**Requirement**: `TR-DPL-004`

**ADR Governing Implementation**: ADR-0004: 回合结算模型 (步骤 1 _collect_commands); ADR-0005: 星球数据模型 (update_garrison + are_connected + get_planets_by_owner)
**ADR Decision Summary**: get_pending() 在步骤 1 被 TurnManager._collect_commands() 调用，返回全部玩家指令。deploy() 内部调用 PlanetSystem.update_garrison() 做实际扣减、are_connected() 做邻接查询。GameState.is_playing() + TurnManager.current_phase 做双重阶段 gate。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: 纯 GDScript 集成代码，通过已有 API 对接。Signal connect 走 EventBus。

**Control Manifest Rules (this layer)**:
- Required: deploy() 7 项校验（其中 is_playing 和 DEPLOYMENT 阶段由本 Story 接入实际 GameState/TurnManager）
- Required: submit_command() 后立即扣除出发星驻兵 — 本 Story 接入 PlanetSystem.update_garrison()
- Forbidden: 禁止在 EXECUTION/CLEANUP 阶段调用 submit_command() — 返回 false — source: ADR-0004
- Forbidden: 禁止已提交指令撤销 — 确认即承诺

---

## Acceptance Criteria

*From GDD `design/gdd/deployment-system.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN GameState 当前为 PAUSED，WHEN `deploy()` 调用，THEN 返回 false（非 PLAYING 拒绝）
- [ ] **AC-2**: GIVEN TurnPhase 为 EXECUTION，WHEN `deploy()` 调用，THEN 返回 false
- [ ] **AC-3**: GIVEN TurnPhase 为 CLEANUP，WHEN `deploy()` 调用，THEN 返回 false
- [ ] **AC-4**: GIVEN deploy() 成功，THEN PlanetSystem.update_garrison(from, -count) 被调用，星球 garrison 实时减少
- [ ] **AC-5**: GIVEN deploy() 成功，THEN 指令出现在 get_pending() 返回列表中
- [ ] **AC-6**: GIVEN deploy() 失败，THEN PlanetSystem.update_garrison() 不被调用，星球状态不变
- [ ] **AC-7**: GIVEN TurnManager 执行步骤 1 _collect_commands()，THEN get_pending() 被调用，指令合并到 all_commands
- [ ] **AC-8**: GIVEN TurnManager 执行步骤 2（拍快照），THEN pending 列表被 clear_pending() 清空
- [ ] **AC-9**: GIVEN 2 条待结算指令，WHEN TurnManager 完成清理，THEN get_pending() 返回空列表

---

## Implementation Notes

*Derived from ADR-0004 and ADR-0005:*

### 集成架构

```
玩家 UI 操作
  → DeploymentSystem.deploy(from, to, count, INFANTRY)
    → GameState.is_playing() — gate 1
    → TurnManager.current_phase == DEPLOYMENT — gate 2
    → PlanetSystem.are_connected(from, to) — 邻接查询
    → PlanetSystem.get_planet(from).owner == PLAYER — 己方检查
    → validate count <= PlanetSystem.get_planet(from).garrison
    → new DeploymentCommand → _pending_commands.append(cmd)
    → PlanetSystem.update_garrison(from, -count) — 实时扣减

TurnManager 步骤 1 (_collect_commands):
  → AIEnemy.compute_turn() → ai_commands
  → DeploymentSystem.get_pending() → player_commands
  → all_commands = player_commands + ai_commands

TurnManager 步骤 2 (拍快照后):
  → DeploymentSystem.clear_pending()
```

### 关键实现要点

- `DeploymentSystem` 注册为 autoload 或由 TurnManager 持有引用
- `deploy()` 内部调用 `GameState.is_playing()` 和 `TurnManager.current_phase`（替代 Story 001 的参数传入）
- 实际扣减走 `PlanetSystem.update_garrison(from, -count)` 而非直接操作 Dictionary
- 邻接检查走 `PlanetSystem.are_connected(from, to)` 而非本地邻接表
- `clear_pending()` 在 TurnManager 步骤 2 拍完快照后调用 — 确保快照拍摄前指令完整
- 所有集成点通过已有 API，不修改 PlanetSystem/TurnManager/GameState 的公开接口
- 集成测试需要完整系统链：PlanetSystem + GameState + TurnManager + DeploymentSystem

### 回合管线时序

```
DEPLOYMENT 阶段:
  玩家操作: deploy() × N → pending 增长 → garrison 逐次扣除
  玩家点击 "结束回合"

TurnManager.end_turn():
  → transition_to(EXECUTION)
  → 步骤 1: _collect_commands()  ← 本 Story 集成点
      → ai_cmds = AIEnemy.compute_turn()
      → player_cmds = DeploymentSystem.get_pending()
      → all = player_cmds + ai_cmds
  → 步骤 2: snapshot = PlanetSystem.take_snapshot()
      → DeploymentSystem.clear_pending()  ← 清空已快照指令
  → 步骤 3: 基于快照计算所有战斗
  → 步骤 4: 统一 apply 战斗结果
  → transition_to(CLEANUP)
  → 步骤 5: cleanup（生产/占领/国王）
  → transition_to(DEPLOYMENT) — 玩家可以部署下一回合
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: deploy() / validate() / DeploymentCommand 核心逻辑（本 Story 在其基础上集成）
- TurnManager: `_collect_commands()` / `end_turn()` 实现（已在 Foundation turn-manager stories 中完成）
- PlanetSystem: `update_garrison()` / `are_connected()` / `get_planet()`（已在 Core planet-system stories 中完成）
- GameState: `is_playing()`（已在 Foundation gamestate-manager 中完成）
- AI 敌人: `compute_turn()`（由 ai-enemy stories 实现）
- 出征 UI: 交互层（presentation layer）

---

## QA Test Cases

*Integration tests — require full system chain:*

- **AC-4~AC-6**: deploy → update_garrison 联动
  - Given: PlanetSystem 初始化 (A:PLAYER,garrison=10; B:ENEMY)
  - When: `DeploymentSystem.deploy(A, B, 5, INFANTRY)`
  - Then: PlanetSystem.get_planet(A).garrison == 5; get_pending().size() == 1
  - Error case: deploy(1,2,20) → returns false → garrison unchanged

- **AC-1~AC-3**: 阶段 gate 集成
  - Given: TurnManager.current_phase = EXECUTION
  - When: `DeploymentSystem.deploy(A, B, 5, INFANTRY)`
  - Then: returns false
  - Test all 3 non-DEPLOYMENT phases (EXECUTION, CLEANUP) + non-PLAYING states (PAUSED, VICTORY, DEFEAT)

- **AC-7~AC-9**: 回合管线端到端
  - Given: player submits 2 commands via deploy()
  - When: TurnManager.end_turn() → _collect_commands()
  - Then: all_commands includes both player commands; after clear_pending(), get_pending().is_empty()

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- Integration: `tests/integration/deployment-system/deployment_turn_integration_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (deploy-validate-core) — must be DONE
- Depends on: Foundation turn-manager (TR-TRN-001~004, TurnPhase + _collect_commands) — must be DONE
- Depends on: Core planet-system (TR-PLT-001~006, update_garrison + are_connected + get_planet) — must be DONE
- Depends on: Foundation gamestate-manager (TR-GSM-004, is_playing) — must be DONE
- Unlocks: 出征 UI (deployment-ui, presentation layer), AI 敌人 (通过 DeploymentCommand 结构体)
