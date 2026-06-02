# Story 001: Turn Phase Loop & Command Intake

> **Epic**: turn-manager
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Logic
> **Estimate**: 2.5h
> **Manifest Version**: 2026-05-31
> **Last Updated**: —

## Context

**GDD**: `design/gdd/turn-manager.md`
**Requirement**: TR-TRN-001, TR-TRN-002, TR-TRN-005, TR-TRN-008, TR-TRN-009
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0004: 回合结算模型 (primary), ADR-0001: 事件总线架构 (secondary — 阶段切换走 EventBus)
**ADR Decision Summary**: 3 阶段循环 DEPLOYMENT→EXECUTION→CLEANUP→DEPLOYMENT，阶段由 `current_phase` 枚举控制，不可跳转。`submit_command()` 仅在 DEPLOYMENT 阶段接受，`end_turn()` 仅在 DEPLOYMENT 阶段可调用。阶段切换通过 EventBus 广播。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: 纯 GDScript 逻辑，不依赖特定引擎 API。无 post-cutoff API 使用。

**Control Manifest Rules (this layer)**:
- Required: TurnManager 3 阶段循环 DEPLOYMENT→EXECUTION→CLEANUP→DEPLOYMENT，阶段不可跳转
- Required: 阶段切换通过 EventBus 广播 deployment_phase_started → execution_phase_started → turn_ended 严格按序
- Required: submit_command() 后立即扣除出发星驻兵（防止同一批兵重复使用）
- Forbidden: 禁止在 EXECUTION/CLEANUP 阶段调用 submit_command() — 返回 false
- Forbidden: 禁止在 DEPLOYMENT 之外调用 end_turn() — 返回 false + push_warning()
- Forbidden: 禁止已提交指令撤销 — 确认即承诺，无回滚机制
- Guardrail: 回合结算 10星/20指令 < 1ms（纯数据操作）

---

## Acceptance Criteria

*From GDD `design/gdd/turn-manager.md`, scoped to this story:*

- [ ] **AC-1**: 初始状态 `current_phase == DEPLOYMENT`，`turn_number == 0`
- [ ] **AC-2**: `current_phase == DEPLOYMENT` 时 `submit_command(cmd)` 返回 `true`；`current_phase == EXECUTION` 时 `submit_command(cmd)` 返回 `false`
- [ ] **AC-3**: `current_phase == DEPLOYMENT` 时 `end_turn()` 正常执行；`current_phase == EXECUTION` 时 `end_turn()` 返回 false 并 `push_warning()`
- [ ] **AC-4**: 事件序列完整：`deployment_phase_started` → `execution_phase_started` → `turn_ended` → `deployment_phase_started` 严格按序 emit
- [ ] **AC-5**: 步骤 1 收集 AI 指令 `compute_turn()` + 玩家指令 `get_pending()`，合并为 `all_commands`

---

## Implementation Notes

*Derived from ADR-0004:*

**1. 创建 `turn_manager.gd` — autoload: TurnManager**:

```gdscript
# turn_manager.gd — autoload: TurnManager
extends Node

## 回合阶段枚举
enum TurnPhase { DEPLOYMENT, EXECUTION, CLEANUP }

## 当前阶段
var current_phase: TurnPhase = TurnPhase.DEPLOYMENT

## 回合计数
var turn_number: int = 0

## 指令队列（部署阶段收集）
var _pending_commands: Array = []

## 提交出征指令 — 仅在 DEPLOYMENT 阶段接受
func submit_command(cmd) -> bool:
    if current_phase != TurnPhase.DEPLOYMENT:
        return false
    _pending_commands.append(cmd)
    return true

## 获取待结算的玩家指令（由步骤 1 调用）
func get_pending_commands() -> Array:
    return _pending_commands

## 结束回合 — 仅在 DEPLOYMENT 阶段可调用
func end_turn() -> bool:
    if current_phase != TurnPhase.DEPLOYMENT:
        push_warning("TurnManager: end_turn() called outside DEPLOYMENT phase.")
        return false
    _execute_turn()
    return true
```

**2. 阶段推进核心逻辑**:

```gdscript
func _execute_turn() -> void:
    # 阶段切换: DEPLOYMENT → EXECUTION
    current_phase = TurnPhase.EXECUTION
    EventBus.execution_phase_started.emit()
    
    # 步骤 1: 收集全部指令
    var ai_commands = _collect_ai_commands()
    var player_commands = _pending_commands
    var all_commands = player_commands + ai_commands
    
    # 步骤 2-4: 快照计算 → Story 002 实现
    # _resolve_turn(all_commands)
    
    # 阶段切换: EXECUTION → CLEANUP
    current_phase = TurnPhase.CLEANUP
    
    # 步骤 5: 收尾 → Story 002 实现
    # _cleanup()
    
    # 回合结束 → 回到 DEPLOYMENT
    _pending_commands.clear()
    turn_number += 1
    EventBus.turn_ended.emit(turn_number)
    
    current_phase = TurnPhase.DEPLOYMENT
    EventBus.deployment_phase_started.emit()

## 收集 AI 指令（占位 — Core 层 AI 系统实现后替换）
func _collect_ai_commands() -> Array:
    # MVP: AI 系统尚未实现时返回空数组
    # 后续 Story 替换为: AIEnemy.compute_turn()
    return []
```

**3. 阶段 Gate 模式**:
- 所有系统方法在修改星球状态前检查 `TurnManager.current_phase`
- EXECUTION 和 CLEANUP 阶段拒绝外部修改 — 只有步骤 2-4 内部有权写入
- GameState 额外检查: `is_playing()` → 非 PLAYING 状态下暂停回合

**4. EventBus 广播顺序（严格按序）**:
```
deployment_phase_started  (新一轮开始)
    ↓
[玩家操作: deploy + submit_command]
    ↓
end_turn() 调用
    ↓
execution_phase_started  (执行开始 — 触发战斗动画)
    ↓
[步骤 1-4 执行]
    ↓
turn_ended               (结算完成 — 触发 UI 刷新)
    ↓
deployment_phase_started  (下一轮开始)
```

**5. autoload 注册**:
- 在 Project Settings → Autoload 中注册 `turn_manager.gd`，名称 `TurnManager`
- 优先级：DataDef > EventBus > GameState > TurnManager

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: 5 步骤快照模型（_take_snapshot, _compute_battles, _apply_results, _cleanup, _resolve_overdraft）
- 出征系统的 `deploy()` 7 项校验 — 属于出征系统 Epic
- AI `compute_turn()` 实现 — 属于 AI 敌人 Epic（本 Story 仅留占位）
- 战斗动画触发和播放 — 属于 Presentation 层 BattleAnimation Epic

---

## QA Test Cases

- **AC-1**: 初始状态
  - Given: TurnManager autoload 初始化完成
  - When: 读取 current_phase 和 turn_number
  - Then: current_phase == DEPLOYMENT, turn_number == 0
  - Edge cases: N/A

- **AC-2**: submit_command() 阶段 Gate
  - Given: current_phase == DEPLOYMENT
  - When: submit_command(valid_cmd)
  - Then: 返回 true, cmd 入队
  - Given: current_phase 切换到 EXECUTION
  - When: submit_command(valid_cmd)
  - Then: 返回 false, cmd 不入队
  - Edge cases: CLEANUP 阶段同样返回 false

- **AC-3**: end_turn() 阶段 Gate
  - Given: current_phase == DEPLOYMENT
  - When: end_turn()
  - Then: 返回 true, 阶段推进到 EXECUTION
  - Given: current_phase == EXECUTION
  - When: end_turn()
  - Then: 返回 false, push_warning() 被调用
  - Edge cases: CLEANUP 阶段同样返回 false

- **AC-4**: 阶段广播序列
  - Given: 从 DEPLOYMENT 调用 end_turn()
  - When: 记录 EventBus 事件序列
  - Then: 依次收到 execution_phase_started → turn_ended → deployment_phase_started
  - Edge cases: 验证每个事件在正确的 phase 值区间 emit；turn_ended 参数 turn_number 为递增后的值

- **AC-5**: 指令收集合并
  - Given: 玩家提交 2 条指令，占位 AI 返回空数组
  - When: 步骤 1 执行 _collect_commands()
  - Then: all_commands 包含玩家 2 条指令，顺序为 player_cmds + ai_cmds
  - Edge cases: 空回合（无任何指令）→ all_commands 为空数组

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- Logic: `tests/unit/turn-manager/test_phase_loop.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: GameState Story 001 (State Machine) — 需要 GameState 提供 is_playing() gate
- Depends on: EventBus Story 001 (Signal Declarations) — 需要 execution_phase_started, deployment_phase_started, turn_ended Signal
- Unlocks: TurnManager Story 002 (Snapshot Resolution Engine)
