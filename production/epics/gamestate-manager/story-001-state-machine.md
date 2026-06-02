# Story 001: GameState State Machine

> **Epic**: gamestate-manager
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Logic
> **Estimate**: 2h
> **Manifest Version**: 2026-05-31
> **Last Updated**: —

## Context

**GDD**: `design/gdd/gamestate-manager.md`
**Requirement**: TR-GSM-001, TR-GSM-002, TR-GSM-003, TR-GSM-004, TR-GSM-005
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0003: GameState 状态机设计
**ADR Decision Summary**: 使用 GDScript `enum` + `match` 实现 5 状态 7 转换的状态机。`GameState` autoload 持有 `current_state`（对外只读 getter），唯一写入路径是 `transition_to()`。每次合法转换自动广播 `EventBus.game_state_changed`。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: GDScript `enum` + `match` 是 4.0 基础特性，无破坏性变更。纯逻辑无场景树依赖，可单元测试。

**Control Manifest Rules (this layer)**:
- Required: GameState 用 enum State {TITLE, PLAYING, PAUSED, VICTORY, DEFEAT} + match 实现，5 状态 7 合法转换
- Required: current_state 对外只读 getter，唯一写入路径是 transition_to()，禁止外部直接赋值
- Required: 每次合法转换自动广播 EventBus.game_state_changed.emit(old, new)
- Required: 提供 is_playing() / is_game_over() 快捷查询
- Forbidden: 禁止直接赋值 current_state — 必须通过 transition_to()
- Guardrail: enum 比较 + match 是 O(1)，无测量意义

---

## Acceptance Criteria

*From GDD `design/gdd/gamestate-manager.md`:*

- [ ] **AC-1**: 初始状态为 TITLE，`transition_to(PLAYING)` 返回 `true`，`current_state == PLAYING`，`EventBus.game_state_changed` 被 emit 且参数为 `(TITLE, PLAYING)`
- [ ] **AC-2**: 当前状态为 PLAYING，`transition_to(VICTORY)` 返回 `true`，`is_game_over() == true`
- [ ] **AC-3**: 当前状态为 TITLE，`transition_to(VICTORY)` 返回 `false`，`current_state` 仍为 TITLE，`push_warning()` 被调用
- [ ] **AC-4**: 当前状态为 PLAYING，`transition_to(TITLE)` 返回 `false`（玩到一半不能直接回标题）
- [ ] **AC-5**: 当前状态为 PAUSED，`is_playing()` 返回 `false`
- [ ] **AC-6**: 当前状态为 VICTORY，`is_game_over()` 返回 `true`
- [ ] **AC-7**: 任意代码直接赋值 `GameState.current_state = VICTORY` 编译/运行时报错（getter 无 setter）
- [ ] **AC-8**: 7 条合法转换分别调用 `transition_to()` 全部返回 `true`

---

## Implementation Notes

*Derived from ADR-0003:*

**1. 创建 `game_state.gd` — autoload: GameState**:

```gdscript
# game_state.gd — autoload: GameState
extends Node

## 游戏全局状态枚举
enum State { TITLE, PLAYING, PAUSED, VICTORY, DEFEAT }

## 当前状态 — 对外只读，唯一写入路径是 transition_to()
var current_state: State = State.TITLE:
    get = _get_state

var _state: State = State.TITLE

func _get_state() -> State:
    return _state

## 状态转换 — 验证转换矩阵，合法则执行并广播
func transition_to(new_state: State) -> bool:
    if not _is_valid_transition(_state, new_state):
        push_warning("GameState: Invalid transition — %s → %s" % [_get_state_name(_state), _get_state_name(new_state)])
        return false
    
    var old_state := _state
    _state = new_state
    EventBus.game_state_changed.emit(old_state, new_state)
    return true

## 是否在游戏中（PLAYING 状态）
func is_playing() -> bool:
    return _state == State.PLAYING

## 是否已结束（VICTORY 或 DEFEAT）
func is_game_over() -> bool:
    return _state == State.VICTORY or _state == State.DEFEAT

## === 内部实现 ===

func _is_valid_transition(from: State, to: State) -> bool:
    match [from, to]:
        [State.TITLE, State.PLAYING]:
            return true
        [State.PLAYING, State.PAUSED]:
            return true
        [State.PLAYING, State.VICTORY]:
            return true
        [State.PLAYING, State.DEFEAT]:
            return true
        [State.PAUSED, State.PLAYING]:
            return true
        [State.VICTORY, State.TITLE]:
            return true
        [State.DEFEAT, State.TITLE]:
            return true
        _:
            return false

func _get_state_name(s: State) -> String:
    match s:
        State.TITLE: return "TITLE"
        State.PLAYING: return "PLAYING"
        State.PAUSED: return "PAUSED"
        State.VICTORY: return "VICTORY"
        State.DEFEAT: return "DEFEAT"
    return "UNKNOWN"
```

**2. 状态转换矩阵**（7 条合法转换）:

| # | 从 | 到 | 触发者 |
|---|----|----|--------|
| 1 | TITLE | PLAYING | 菜单 UI（点击"开始游戏"）|
| 2 | PLAYING | PAUSED | 回合控制 UI（ESC/暂停按钮）|
| 3 | PAUSED | PLAYING | 暂停菜单 UI（点击"继续"）|
| 4 | PLAYING | VICTORY | 胜负条件（check_victory()==true）|
| 5 | PLAYING | DEFEAT | 胜负条件（check_defeat()==true）|
| 6 | VICTORY | TITLE | 胜利画面 UI（点击"返回标题"）|
| 7 | DEFEAT | TITLE | 失败画面 UI（点击"返回标题"）|

**3. 关键设计要点**:
- `current_state` 使用 setter/getter 模式：`var current_state: State = ...: get` — 编译期阻止外部直接赋值
- 注意：GDScript 中 `: get` 语法阻止外部写入。`current_state` 对外只读
- `transition_to()` 是唯一写入路径
- 非法转换不抛异常，返回 `false` + `push_warning()`，调用方检查返回值决定后续行为
- 每次合法转换自动 emit `EventBus.game_state_changed`，订阅系统在 callback 中响应
- 无状态进入/退出回调钩子 — 订阅系统各自监听 `game_state_changed` 自行处理（事件解耦的设计意图）

**4. autoload 注册**:
- 在 Project Settings → Autoload 中注册 `game_state.gd`，名称 `GameState`
- 优先级：DataDef > EventBus > GameState（GameState 依赖 EventBus 的 game_state_changed Signal）

---

## Out of Scope

*Handled by other systems — do not implement here:*

- LOADING 状态 — Vertical Slice 考虑
- 状态进入/退出动画过渡 — Presentation 层转场系统负责
- 各系统如何响应 `game_state_changed` — 属于各系统自己的 Story
- 胜负条件的判定逻辑 — 属于 Feature 层 WinConditions Epic

---

## QA Test Cases

- **AC-1**: TITLE → PLAYING 转换
  - Given: current_state == TITLE
  - When: transition_to(PLAYING)
  - Then: 返回 true, current_state == PLAYING, EventBus.game_state_changed emit 参数为 (TITLE, PLAYING)
  - Edge cases: 重复调用 transition_to(PLAYING) → 返回 false（PLAYING→PLAYING 不在转换矩阵中）

- **AC-2**: PLAYING → VICTORY 转换
  - Given: current_state == PLAYING（先执行 AC-1）
  - When: transition_to(VICTORY)
  - Then: 返回 true, is_game_over() == true
  - Edge cases: 从 VICTORY 再调 transition_to(DEFEAT) → 返回 false

- **AC-3**: TITLE → VICTORY 非法转换
  - Given: current_state == TITLE
  - When: transition_to(VICTORY)
  - Then: 返回 false, current_state 仍为 TITLE, push_warning() 被调用
  - Edge cases: push_warning 消息包含 "TITLE → VICTORY" 文本

- **AC-4**: PLAYING → TITLE 非法转换
  - Given: current_state == PLAYING（先执行 AC-1）
  - When: transition_to(TITLE)
  - Then: 返回 false（玩到一半不能直接回标题，必须先 PAUSED 或游戏结束）
  - Edge cases: 验证 VICTORY→TITLE 和 DEFEAT→TITLE 是合法的（AC-8 包含）

- **AC-5**: PAUSED 状态下 is_playing() == false
  - Given: current_state == PLAYING → transition_to(PAUSED) → current_state == PAUSED
  - When: is_playing()
  - Then: 返回 false
  - Edge cases: is_game_over() 也返回 false

- **AC-6**: VICTORY 状态下 is_game_over() == true
  - Given: current_state == VICTORY
  - When: is_game_over()
  - Then: 返回 true
  - Edge cases: DEFEAT 状态下 is_game_over() 也返回 true

- **AC-7**: current_state 只读保护
  - Given: game_state.gd 中 current_state 声明为只读 getter
  - When: 外部代码尝试 `GameState.current_state = GameState.State.VICTORY`
  - Then: 编译错误或运行时无法赋值（GDScript 的 `: get` 阻止外部 set）
  - Edge cases: 验证内部 `_state` 变量不暴露给外部

- **AC-8**: 全部 7 条合法转换
  - Given: 依次设置初始状态
  - When: 逐一执行 7 条转换（TITLE→PLAYING, PLAYING→PAUSED, PAUSED→PLAYING, PLAYING→VICTORY, (reset)TITLE→PLAYING→DEFEAT, VICTORY→TITLE, DEFEAT→TITLE）
  - Then: 全部返回 true
  - Edge cases: 至少测试 3 条非法转换：TITLE→PAUSED, PLAYING→PLAYING, PAUSED→VICTORY

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- Logic: `tests/unit/gamestate-manager/test_state_machine.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: EventBus Story 001 (Signal Declarations) — 需要 `EventBus.game_state_changed` Signal
- Unlocks: TurnManager, 所有 UI 系统（需要 is_playing() gate 和 game_state_changed 订阅）
