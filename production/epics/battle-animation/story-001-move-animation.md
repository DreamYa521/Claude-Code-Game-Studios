# Story 001: 兵力移动动画 — 短线沿连接线移动 + 并行播放 + 跳过

> **Epic**: 战斗动画 (battle-animation)
> **Status**: Ready
> **Layer**: Presentation
> **Type**: Visual/Feel
> **Estimate**: 2h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/battle-animation.md`
**Requirement**: `TR-BAN-001`, `TR-BAN-004`, `TR-BAN-005`

**ADR Governing Implementation**: ADR-0004: EXECUTION 阶段动画在步骤 3-4 之间播放，全部完成后 emit turn_ended
**ADR Decision Summary**: 每条 DeploymentCommand 渲染一条移动短线沿连接线从 from 到 to。颜色=出发方颜色（蓝=玩家，红=AI）。速度 400px/s。所有指令动画并行播放。提供跳过选项（点击屏幕瞬移→立即结束）。动画期间星图不接受点击。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Node2D._draw()` + `_process(delta)` 做逐帧动画。`Tween` 可简化但 `_process()` 更灵活（支持并行+跳过）。MVP 极简实现：`_process()` 中更新每条线的进度 `t`。

**Control Manifest Rules (this layer)**:
- Required: 战斗动画：并行播放移动短线(400px/s)→到达时占领闪烁(3次×150ms)→全部完成emit turn_ended — source: ADR-0004
- Required: 动画期间星图不接受点击 — 全部完成后恢复操作 — source: ADR-0004
- Required: 跳过动画选项：点击屏幕瞬移→单次闪→立即进入步骤5 — source: ADR-0004
- Forbidden: 禁止动画期间接受玩家操作 — source: ADR-0004
- Guardrail: 20 条指令并行，每条 ≤ 0.75s，总时长 < 1s

---

## Acceptance Criteria

*From GDD `design/gdd/battle-animation.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN `execution_phase_started` 信号 + 有 2 条指令（玩家从地球→火星，AI从火星→月球），WHEN 动画播放，THEN 看到 2 条短线分别沿各自连接线移动（蓝色从地球→火星，红色从火星→月球）
- [ ] **AC-2**: GIVEN 动画播放中 + 短线从(200,200)到(400,300)距离 ~224px，WHEN 以 400px/s 移动，THEN 约 0.56s 到达（实际范围 0.5-0.6s）
- [ ] **AC-3**: GIVEN 动画播放中点击屏幕，WHEN 响应，THEN 全部动画瞬移到终点（跳过动画）
- [ ] **AC-4**: GIVEN 0 条指令（空回合），WHEN `execution_phase_started`，THEN 无动画，直接 `turn_ended`
- [ ] **AC-5**: GIVEN 动画播放期间，WHEN 尝试点击星图卫星，THEN 不响应（动画期间不接受操作）

---

## Implementation Notes

*Derived from ADR-0004 and GDD battle-animation.md:*

### 核心结构

```gdscript
# battle_animator.gd — Node2D 子节点，挂载到星图场景
class_name BattleAnimator extends Node2D

const ANIMATION_SPEED := 400.0  # px/s
const LINE_SIZE := 8.0          # 短线尺寸（三角形边长）

var _animations: Array = []     # [{from_pos, to_pos, color, t}]
var _is_playing: bool = false
var _skipped: bool = false
var _planet_system  # PlanetSystem autoload

func _ready() -> void:
    EventBus.execution_phase_started.connect(_on_execution_start)

func _on_execution_start() -> void:
    var commands = DeploymentSystem.get_all_commands()  # 当前回合所有指令
    if commands.is_empty():
        # 空回合：无动画，直接通知完成
        EventBus.animations_complete.emit()
        return
    
    _setup_animations(commands)
    _is_playing = true
    _skipped = false

func _setup_animations(commands: Array) -> void:
    _animations.clear()
    for cmd in commands:
        var from_planet = _planet_system.get_planet(cmd.from_planet)
        var to_planet = _planet_system.get_planet(cmd.to_planet)
        
        var color = COLOR_PLAYER if cmd.player_owned else COLOR_ENEMY
        
        _animations.append({
            "from_pos": from_planet.position,
            "to_pos": to_planet.position,
            "color": color,
            "t": 0.0,               # 进度 0.0~1.0
            "duration": _calc_duration(from_planet.position, to_planet.position),
            "completed": false,
        })

func _calc_duration(from_pos: Vector2, to_pos: Vector2) -> float:
    var distance = from_pos.distance_to(to_pos)
    return min(distance / ANIMATION_SPEED, 1.0)  # 上限 1s

func _process(delta: float) -> void:
    if not _is_playing:
        return
    
    var all_done = true
    for anim in _animations:
        if anim.completed:
            continue
        anim.t += delta / anim.duration
        if anim.t >= 1.0:
            anim.t = 1.0
            anim.completed = true
        else:
            all_done = false
    
    queue_redraw()
    
    if all_done:
        _on_all_completed()

func _draw() -> void:
    if not _is_playing:
        return
    for anim in _animations:
        if not anim.completed or (anim.t >= 1.0 and not _skipped):
            _draw_moving_line(anim)

func _draw_moving_line(anim: Dictionary) -> void:
    var pos = anim.from_pos.lerp(anim.to_pos, anim.t)
    var direction = (anim.to_pos - anim.from_pos).normalized()
    var perpendicular = Vector2(-direction.y, direction.x) * (LINE_SIZE * 0.5)
    
    # 小三角形：尖头朝移动方向
    var tip = pos + direction * LINE_SIZE * 0.5
    var base_left = pos - direction * LINE_SIZE * 0.5 + perpendicular
    var base_right = pos - direction * LINE_SIZE * 0.5 - perpendicular
    
    var points = PackedVector2Array([tip, base_left, base_right])
    draw_colored_polygon(points, anim.color)

func _input(event: InputEvent) -> void:
    if not _is_playing:
        return
    if event is InputEventMouseButton and event.pressed:
        _skip_all()

func _skip_all() -> void:
    _skipped = true
    for anim in _animations:
        anim.t = 1.0
        anim.completed = true
    _on_all_completed()

func _on_all_completed() -> void:
    _is_playing = false
    _animations.clear()
    queue_redraw()
    EventBus.animations_complete.emit()
```

### 动画序列集成

TurnManager 中集成（参考，由回合管理器 epic 实现）：

```gdscript
# turn_manager.gd — EXECUTION 阶段修改
func _execute_turn() -> void:
    current_phase = TurnPhase.EXECUTION
    EventBus.execution_phase_started.emit()
    
    # 步骤 1-3: 收集 + 快照 + 计算
    var commands = _collect_commands()
    var snapshot = _take_snapshot()
    var results = _compute_battles(commands, snapshot)
    
    # 步骤 4: 应用（但不立即 turn_ended）
    _apply_results(results)
    
    # 等待动画完成
    # 动画协程/信号回调 → _on_animations_done()
    await EventBus.animations_complete
    
    # 步骤 5: 收尾
    current_phase = TurnPhase.CLEANUP
    _cleanup()
    
    current_phase = TurnPhase.DEPLOYMENT
    turn_number += 1
    EventBus.turn_ended.emit(turn_number)
    EventBus.deployment_phase_started.emit()
```

### 关键实现要点

- 用 `_process(delta)` 而不是 Tween — 更灵活，支持统一跳过
- `anim.t` 是归一化进度 0.0~1.0，`pos = from.lerp(to, t)`
- `_calc_duration()` 上限 1s — 防止长距离动画拖慢节奏
- 小三角形方向指向移动方向 — 用 `direction` 计算 tip 偏移
- `_skipped` 标记跳过行为 — 跳过时所有线瞬移到终点
- `animations_complete` 信号通知 TurnManager 动画结束 → 进入步骤 5
- 本 Story 只做移动动画，占领闪烁在 story-002 中实现
- 动画期间 `_input()` 拦截所有鼠标点击 — 防止玩家在结算中操作

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: 占领闪烁动画（planet_owner_changed 触发）
- 动画序列与 TurnManager.await 集成（回合管理器 epic 中实现）
- 设置面板"跳过战斗动画"开关
- 粒子效果 / 音效

---

## QA Test Cases

*Derived from GDD acceptance criteria.*

- **AC-1**: 2 条指令动画播放
  - Given: 2 commands ([地球→火星, 玩家] + [火星→月球, AI])
  - When: execution_phase_started → _setup_animations()
  - Then: 2 moving triangles visible, one blue one red, moving along respective paths

- **AC-2**: 到达时间
  - Given: distance ~224px, speed 400px/s
  - When: animation starts
  - Then: t reaches 1.0 at ~0.56s (±0.1s)

- **AC-3**: 跳过
  - Given: animation playing, t ≈ 0.3
  - When: click screen
  - Then: all animations t=1.0 immediately, animations_complete emitted

- **AC-4**: 空回合
  - Given: DeploymentSystem.get_all_commands() returns []
  - When: execution_phase_started
  - Then: animations_complete emitted immediately, no _process() loop

- **AC-5**: 动画期间禁止操作
  - Given: _is_playing=true
  - When: click on planet position
  - Then: click consumed by BattleAnimator._input(), not passed to StarMapView

---

## Test Evidence

**Story Type**: Visual/Feel
**Required evidence**:
- Screenshot of mid-animation (triangles on paths) + lead sign-off
- Evidence directory: `production/qa/evidence/battle-animation-move.md`

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Core deployment-system (get_all_commands() / get_pending()) — must be DONE
- Depends on: Core planet-system (get_planet for position) — must be DONE
- Depends on: Foundation event-bus (execution_phase_started signal) — must be DONE
- Unlocks: Story 002 (occupation flash + animation sequence integration)
