# Story 002: 交互系统 + 详情面板 + EventBus 事件订阅

> **Epic**: 星图 UI (star-map-ui)
> **Status**: Ready
> **Layer**: Presentation
> **Type**: UI
> **Estimate**: 2h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/star-map-ui.md`
**Requirement**: `TR-SMU-003`, `TR-SMU-004`

**ADR Governing Implementation**: ADR-0001: EventBus 事件驱动刷新，UI 只读不修改数据
**ADR Decision Summary**: 点击星球→选中高亮+显示详情面板。选中己方星→点击相邻敌星→触发出征UI。点击非相邻敌星→无响应。订阅 5 个 EventBus 信号自动刷新。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `_input(event)` 中判断 `event is InputEventMouseButton`。点击判定：计算鼠标位置到各星球圆心的距离 ≤ PLANET_RADIUS。`queue_redraw()` 在事件处理后触发重绘。

**Control Manifest Rules (this layer)**:
- Required: 选中交互：点己方星→高亮相邻敌星→点敌星触发出征UI — source: ADR-0001
- Required: UI 组件全部通过 EventBus 订阅刷新 — 不轮询，不直接读其他系统状态 — source: ADR-0001
- Forbidden: 禁止 UI 直接修改星球状态 — UI 只读和发指令，修改通过系统 API — source: ADR-0001

---

## Acceptance Criteria

*From GDD `design/gdd/star-map-ui.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN 点击己方星球（地球 garrison=10），WHEN 命中判定成功，THEN 该星显示 2px 白色边框高亮，详情面板显示"星球:地球/归属:玩家/属性:NORMAL/驻兵:10/20/..."
- [ ] **AC-2**: GIVEN 已选中己方星，WHEN 点击相邻敌星（火星），THEN 触发出征 UI（发送 `deployment_requested(from, to)` 信号或直接调用）
- [ ] **AC-3**: GIVEN 已选中己方星，WHEN 点击非相邻敌星，THEN 无响应（不触发出征 UI）
- [ ] **AC-4**: GIVEN 星球已选中，WHEN 再次点击同星或点击空白区域，THEN 取消选中，高亮消失
- [ ] **AC-5**: GIVEN `planet_owner_changed(3, ENEMY, PLAYER)` 信号，WHEN UI 监听，THEN 3 号星从红色变为蓝色 + `queue_redraw()`
- [ ] **AC-6**: GIVEN `planet_garrison_changed(1, 10, 7)` 信号，WHEN UI 监听，THEN 地球兵力数字从 10 更新为 7
- [ ] **AC-7**: GIVEN `turn_ended` 信号，WHEN UI 监听，THEN 全部刷新 `queue_redraw()`
- [ ] **AC-8**: GIVEN `game_ended("victory")` 信号，WHEN UI 监听，THEN 显示"胜利"overlay

---

## Implementation Notes

*Derived from ADR-0001, ADR-0005 and GDD star-map-ui.md:*

### 交互逻辑

```gdscript
# star_map_view.gd — 在 story-001 基础上添加

var _selected_planet_id: int = -1  # -1 = 无选中
var _highlighted_planet_ids: Array[int] = []  # 高亮相邻敌星

func _input(event: InputEvent) -> void:
    if not event is InputEventMouseButton:
        return
    if event.button_index != MOUSE_BUTTON_LEFT:
        return
    if not event.pressed:
        return
    
    var clicked_planet = _hit_test(event.position)
    
    if clicked_planet == -1:
        # 点击空白 → 取消选中
        _deselect_all()
        return
    
    if _selected_planet_id == -1:
        # 无选中 → 选中当前
        _select_planet(clicked_planet)
    elif clicked_planet == _selected_planet_id:
        # 再次点击同星 → 取消选中
        _deselect_all()
    elif _is_enemy_or_neutral(clicked_planet) and _can_attack(_selected_planet_id, clicked_planet):
        # 选中己方星 + 点击相邻敌星 → 触发出征
        _trigger_deployment(_selected_planet_id, clicked_planet)
    else:
        # 切换选中的星
        _select_planet(clicked_planet)

func _hit_test(mouse_pos: Vector2) -> int:
    var planets = _planet_system.get_all_planets()
    for planet in planets:
        if mouse_pos.distance_to(planet.position) <= PLANET_RADIUS:
            return planet.id
    return -1
```

### 高亮变色逻辑

```gdscript
func _select_planet(planet_id: int) -> void:
    var planet = _planet_system.get_planet(planet_id)
    
    if planet.owner == DataDef.Faction.PLAYER:
        # 己方星：高亮相邻敌方星
        _selected_planet_id = planet_id
        _highlighted_planet_ids.clear()
        var adjacent = _planet_system.get_adjacent_planets(planet_id)
        for nid in adjacent:
            var neighbor = _planet_system.get_planet(nid)
            if neighbor.owner != DataDef.Faction.PLAYER:
                _highlighted_planet_ids.append(nid)
    else:
        # 敌方/中立星：只选中不高亮
        _selected_planet_id = planet_id
        _highlighted_planet_ids.clear()
    
    queue_redraw()
    _update_detail_panel(planet)

func _deselect_all() -> void:
    _selected_planet_id = -1
    _highlighted_planet_ids.clear()
    _hide_detail_panel()
    queue_redraw()
```

### 渲染扩展（在 _draw_planet 中添加）

```gdscript
func _draw_planet(planet) -> void:
    # ... 原有渲染代码 ...
    
    # 选中高亮
    if planet.id == _selected_planet_id:
        draw_arc(pos, PLANET_RADIUS + 2, 0, TAU, 32, Color.WHITE, 2.0)
    
    # 相邻敌星高亮
    if planet.id in _highlighted_planet_ids:
        draw_arc(pos, PLANET_RADIUS + 2, 0, TAU, 32, COLOR_CONNECTION_HIGHLIGHT, 2.0)
```

### EventBus 事件订阅

```gdscript
func _ready() -> void:
    # ... 原有 planets_initialized 连接 ...
    EventBus.planet_owner_changed.connect(_on_owner_changed)
    EventBus.planet_garrison_changed.connect(_on_garrison_changed)
    EventBus.turn_ended.connect(_on_turn_ended)
    EventBus.game_ended.connect(_on_game_ended)

func _on_owner_changed(planet_id: int, old_owner: int, new_owner: int) -> void:
    queue_redraw()

func _on_garrison_changed(planet_id: int, old_val: int, new_val: int) -> void:
    queue_redraw()

func _on_turn_ended(_turn: int) -> void:
    _deselect_all()
    queue_redraw()

func _on_game_ended(result: String) -> void:
    _show_game_over_overlay(result)
```

### 关键实现要点

- `_hit_test()` 遍历所有星球判断距离 — MVP 4 星 O(4) 无性能问题
- `_can_attack(from, to)` 检查：from 是己方星 + to 非己方 + 相邻
- `turn_ended` 时主动取消选中 — 防止旧选中状态跨回合残留
- 详情面板用 `Control` 节点（Label 排列），与 StarmapView 分离
- `game_ended` overlay 为半透明全屏 Control + "胜利"/"失败" 大字
- 出征触发方式：通过 EventBus 新增 signal 或直接调用 DeploymentUI.open(from, to)
- MVP 用 `EventBus.deployment_requested.emit(from, to)` 解耦星图和出征面板

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: 星球节点/连接线/兵力数字基础渲染
- 出征 UI 面板实现（deployment-ui epic）
- 拖线发兵交互（MVP 用点击两步操作）
- Godot 4.x `_input()` 与 `Control._gui_input()` 的冲突处理（简单场景无冲突）

---

## QA Test Cases

*Derived from GDD acceptance criteria.*

- **AC-1**: 点击选中己方星
  - Given: 星图渲染正常
  - When: mouse click at position(200, 200) (地球圆心)
  - Then: _selected_planet_id=1, 地球显示白边框, 详情面板显示地球信息

- **AC-2**: 选中后点击相邻敌星
  - Given: 已选中地球(id=1), 火星(id=3)相邻且 owner=ENEMY
  - When: click at mars position
  - Then: deployment_requested(1, 3) emitted

- **AC-3**: 点击非相邻敌星
  - Given: 已选中地球(id=1), 火卫一(id=4)不相邻于地球
  - When: click at phobos position
  - Then: 不触发出征，切换选中到火卫一

- **AC-4**: 取消选中
  - Given: 已选中地球
  - When: click at empty space (distance > PLANET_RADIUS to any planet)
  - Then: _selected_planet_id=-1, all highlights removed

- **AC-5**: owner_change 刷新
  - Given: planet 3 owner=ENEMY (红)
  - When: planet_owner_changed(3, ENEMY, PLAYER) emitted
  - Then: planet 3 now blue on next _draw()

- **AC-6**: garrison_change 刷新
  - Given: planet 1 shows "10"
  - When: planet_garrison_changed(1, 10, 7) emitted
  - Then: planet 1 now shows "7"

- **AC-7**: game_ended overlay
  - Given: game in progress
  - When: game_ended("victory") emitted
  - Then: semi-transparent overlay with "胜利" text displayed

---

## Test Evidence

**Story Type**: UI
**Required evidence**:
- Manual walkthrough doc: `production/qa/evidence/star-map-ui-interaction.md` — must exist
- Screenshots: planet selected state, detail panel visible, game-over overlay

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (planet render + connection lines) — must be DONE
- Depends on: Core planet-system (get_planet/get_adjacent_planets) — must be DONE
- Depends on: Foundation event-bus (planet_owner_changed, planet_garrison_changed, turn_ended, game_ended) — must be DONE
- Unlocks: deployment-ui (deployment_requested signal trigger)
