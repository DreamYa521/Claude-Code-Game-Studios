# Story 001: 回合控制界面 — 按钮 + 回合数 + 阶段指示 + 快捷键

> **Epic**: 回合控制 UI (turn-control-ui)
> **Status**: Ready
> **Layer**: Presentation
> **Type**: UI
> **Estimate**: 1h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/turn-control-ui.md`
**Requirement**: `TR-TCU-001`, `TR-TCU-002`, `TR-TCU-003`, `TR-TCU-004`

**ADR Governing Implementation**: ADR-0003: 根据 GameState 显示/隐藏 UI；ADR-0004: 仅在 DEPLOYMENT 阶段启用结束回合按钮
**ADR Decision Summary**: 结束回合按钮在 DEPLOYMENT 可用/EXECUTION 禁用/CLEANUP 禁用/非 PLAYING 隐藏。回合数监听 turn_ended(turn_number) 更新。阶段指示监听 phase 切换信号。Space/E 快捷键结束回合。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Control` + `Button` + `Label`。`Button.disabled` 控制可用性。`_input()` 处理快捷键。

**Control Manifest Rules (this layer)**:
- Required: 回合控制 UI：DEPLOYMENT可用/EXECUTION禁用'结算中...'/CLEANUP禁用'收尾中...'/非PLAYING隐藏 — source: ADR-0003
- Required: 快捷键：Space/E→结束回合 — source: ADR-0003

---

## Acceptance Criteria

*From GDD `design/gdd/turn-control-ui.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN 游戏在 PLAYING + DEPLOYMENT，WHEN 渲染 UI，THEN "结束回合"按钮可用（蓝色，文字"结束回合"）
- [ ] **AC-2**: GIVEN 点击"结束回合"，WHEN 结算中，THEN 按钮禁用（灰色，文字"结算中..."）
- [ ] **AC-3**: GIVEN `turn_ended` 信号，WHEN UI 刷新，THEN 回合数 +1，按钮恢复可用为"结束回合"
- [ ] **AC-4**: GIVEN PAUSED 状态，WHEN 渲染 UI，THEN 按钮隐藏，显示"已暂停"
- [ ] **AC-5**: GIVEN VICTORY/DEFEAT 状态，WHEN 渲染 UI，THEN 按钮隐藏，显示"胜利"/"失败"
- [ ] **AC-6**: GIVEN 在 DEPLOYMENT 阶段按 Space，WHEN UI 响应，THEN 等效点击"结束回合"
- [ ] **AC-7**: GIVEN 玩家双击"结束回合"，WHEN 第一次点击已禁用按钮，THEN 第二次点击无效

---

## Implementation Notes

*Derived from ADR-0003, ADR-0004 and GDD turn-control-ui.md:*

### 场景结构

```
TurnControlUI (Control, 右上角锚定)
├── Background (Panel, 半透明深色背景)
│   ├── TurnLabel ("第 1 回合")
│   ├── EndTurnButton ([结束回合], min_width=120)
│   └── PhaseLabel ("部署阶段")
```

### 核心代码

```gdscript
# turn_control_ui.gd
class_name TurnControlUI extends Control

@onready var _turn_label: Label = $Background/TurnLabel
@onready var _end_turn_btn: Button = $Background/EndTurnButton
@onready var _phase_label: Label = $Background/PhaseLabel
@onready var _background: Panel = $Background

var _turn_manager  # TurnManager autoload 引用

func _ready() -> void:
    # 初始状态
    _turn_label.text = "第 1 回合"
    _update_button_state()
    
    # 事件订阅
    EventBus.deployment_phase_started.connect(_on_deployment_phase)
    EventBus.execution_phase_started.connect(_on_execution_phase)
    EventBus.turn_ended.connect(_on_turn_ended)
    EventBus.game_state_changed.connect(_on_game_state_changed)
    
    _end_turn_btn.pressed.connect(_on_end_turn)

func _on_end_turn() -> void:
    _end_turn_btn.disabled = true
    _end_turn_btn.text = "结算中..."
    _turn_manager.end_turn()

func _on_deployment_phase() -> void:
    _end_turn_btn.disabled = false
    _end_turn_btn.text = "结束回合"
    _phase_label.text = "部署阶段"

func _on_execution_phase() -> void:
    _end_turn_btn.disabled = true
    _end_turn_btn.text = "结算中..."
    _phase_label.text = "结算中..."

func _on_turn_ended(turn_number: int) -> void:
    _turn_label.text = "第 %d 回合" % turn_number

func _on_game_state_changed(old_state: int, new_state: int) -> void:
    match new_state:
        GameState.State.PLAYING:
            _background.show()
            _update_button_state()
        GameState.State.PAUSED:
            _background.show()
            _end_turn_btn.hide()
            _phase_label.text = "已暂停"
        GameState.State.VICTORY:
            _background.show()
            _end_turn_btn.hide()
            _phase_label.text = "胜利"
        GameState.State.DEFEAT:
            _background.show()
            _end_turn_btn.hide()
            _phase_label.text = "失败"
        _:
            _background.hide()

func _update_button_state() -> void:
    if _turn_manager.current_phase == _turn_manager.TurnPhase.DEPLOYMENT:
        _end_turn_btn.show()
        _end_turn_btn.disabled = false
        _end_turn_btn.text = "结束回合"
    elif _turn_manager.current_phase == _turn_manager.TurnPhase.EXECUTION:
        _end_turn_btn.show()
        _end_turn_btn.disabled = true
        _end_turn_btn.text = "结算中..."
    elif _turn_manager.current_phase == _turn_manager.TurnPhase.CLEANUP:
        _end_turn_btn.show()
        _end_turn_btn.disabled = true
        _end_turn_btn.text = "收尾中..."

# 快捷键
func _input(event: InputEvent) -> void:
    if not GameState.is_playing():
        return
    if _turn_manager.current_phase != _turn_manager.TurnPhase.DEPLOYMENT:
        return
    if event.is_action_pressed("end_turn_space") or event.is_action_pressed("end_turn_e"):
        _on_end_turn()
        get_viewport().set_input_as_handled()
```

### Input Map 配置

在 Project Settings → Input Map 中添加：
- `end_turn_space` — Key: Space
- `end_turn_e` — Key: E

### 关键实现要点

- UI 锚定右上角 — `anchor_left=1.0, anchor_right=1.0, anchor_top=0.0`
- 双击防重：按钮在 `_on_end_turn()` 第一行即 `disabled = true` → 第二次点击无效
- `game_state_changed` 处理所有非 PLAYING 状态 — TITLE/VICTORY/DEFEAT 隐藏按钮
- `_update_button_state()` 在 `_ready()` 和 `game_state_changed→PLAYING` 时调用
- 快捷键在 `_input()` 中做 gate 检查（is_playing + DEPLOYMENT）
- MVP 不做 CLEANUP 阶段的可感知延迟 — UI 从 EXECUTION 直接跳到下一个 DEPLOYMENT（速度 < 1ms）
- `end_turn()` 返回 bool — 但 UI 不需要处理返回值（gate 已防）

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- TurnManager.end_turn() 实现 — 属于 turn-manager epic
- GameState 状态机 — 属于 gamestate-manager epic
- 阶段动画/过渡效果
- 回合历史记录/日志

---

## QA Test Cases

*Derived from GDD acceptance criteria.*

- **AC-1**: 部署阶段按钮可用
  - Given: PLAYING, DEPLOYMENT
  - When: UI renders
  - Then: button enabled, text="结束回合", phase="部署阶段", turn="第 1 回合"

- **AC-2**: 点击后禁用
  - Given: button enabled
  - When: click EndTurnButton
  - Then: button disabled immediately, text="结算中..."

- **AC-3**: 回合结束恢复
  - Given: turn=5, button disabled during execution
  - When: turn_ended(6) emitted
  - Then: turn_label="第 6 回合", button enabled with "结束回合"

- **AC-4**: PAUSED 状态
  - Given: PLAYING → PAUSED
  - When: game_state_changed(PLAYING, PAUSED) emitted
  - Then: button hidden, phase_label="已暂停"

- **AC-5**: VICTORY 状态
  - Given: PLAYING → VICTORY
  - When: game_state_changed emitted
  - Then: button hidden, phase_label="胜利"

- **AC-6**: Space 快捷键
  - Given: PLAYING + DEPLOYMENT
  - When: press Space
  - Then: _on_end_turn() called

- **AC-7**: 双击防护
  - Given: button enabled
  - When: click twice rapidly
  - Then: end_turn() called exactly once (second click hits disabled button)

---

## Test Evidence

**Story Type**: UI
**Required evidence**:
- Manual walkthrough doc: `production/qa/evidence/turn-control-ui-walkthrough.md` — must exist
- Screenshots: enabled button, disabled button, paused state, victory state

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Foundation turn-manager (end_turn(), current_phase, turn_number) — must be DONE
- Depends on: Foundation gamestate-manager (State enum, is_playing()) — must be DONE
- Depends on: Foundation event-bus (turn_ended, deployment_phase_started, execution_phase_started, game_state_changed) — must be DONE
