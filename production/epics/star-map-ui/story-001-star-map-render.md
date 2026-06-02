# Story 001: 星球节点 + 连接线 + 兵力数字渲染

> **Epic**: 星图 UI (star-map-ui)
> **Status**: Ready
> **Layer**: Presentation
> **Type**: UI
> **Estimate**: 2h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/star-map-ui.md`
**Requirement**: `TR-SMU-001`, `TR-SMU-002`, `TR-SMU-005`

**ADR Governing Implementation**: ADR-0005: 星球位置、连接信息来自 PlanetSystem；ADR-0001: 通过 EventBus 接收 planets_initialized 信号
**ADR Decision Summary**: 星球节点渲染为圆形（24px）+ 归属色填充（PLAYER蓝/ENEMY红/NEUTRAL灰）。连接线为2px半透明白线，从圆心到圆心。每个星球显示名字（上方8px）和兵力数字（居中14px白色）。MVP 用 Node2D + _draw() 实现，控制清单禁止 UI 直接修改星球状态。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Node2D._draw()` + `draw_circle()`/`draw_line()`/`draw_string()`。`queue_redraw()` 触发重绘。`draw_string()` 需要 Font，MVP 可用 `ThemeDB.fallback_font` 或 `SystemFont`。

**Control Manifest Rules (this layer)**:
- Required: 星图 UI 渲染：圆形节点(24px) + 颜色区分(蓝/红/灰) + 2px连接线 + 兵力数字 — source: ADR-0001
- Forbidden: 禁止 UI 直接修改星球状态 — UI 只读和发指令，修改通过系统 API — source: ADR-0001
- Guardrail: MVP 4 星 < 10 draw calls

---

## Acceptance Criteria

*From GDD `design/gdd/star-map-ui.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN `planets_initialized` 信号（4 星已加载），WHEN 星图 UI 渲染，THEN 4 个圆形节点可见（位置匹配 PlanetDef.position）
- [ ] **AC-2**: GIVEN planet 1 owner=PLAYER, planet 3 owner=ENEMY，WHEN 渲染，THEN 地球蓝色(#4488FF)、火星红色(#FF4444)、月球+火卫一灰色(#888888)
- [ ] **AC-3**: GIVEN 3 条 Connection 存在，WHEN 渲染，THEN 3 条 2px 半透明白线(#FFFFFF 50%)连接对应星球圆心
- [ ] **AC-4**: GIVEN planet 1 garrison=10，WHEN 渲染，THEN 地球上方显示"地球"(8px)，圆心中央显示"10"(14px 白色)
- [ ] **AC-5**: GIVEN 详情面板渲染，WHEN 未选中任何星球，THEN 面板不显示或显示"点击星球查看详情"

---

## Implementation Notes

*Derived from ADR-0001, ADR-0005 and GDD star-map-ui.md:*

### 核心结构

```gdscript
# star_map_view.gd — 挂载到 StarMapView (Node2D) 场景
class_name StarMapView extends Node2D

const PLANET_RADIUS := 24.0
const LINE_WIDTH := 2.0
const COLOR_PLAYER := Color("#4488FF")
const COLOR_ENEMY := Color("#FF4444")
const COLOR_NEUTRAL := Color("#888888")
const COLOR_CONNECTION := Color(1.0, 1.0, 1.0, 0.5)  # 半透明白
const COLOR_CONNECTION_HIGHLIGHT := Color("#FFCC00")

var _planet_system  # PlanetSystem autoload 引用
var _font: Font

func _ready() -> void:
    _font = ThemeDB.fallback_font
    EventBus.planets_initialized.connect(_on_planets_initialized)

func _on_planets_initialized() -> void:
    queue_redraw()

func _draw() -> void:
    var planets = _planet_system.get_all_planets()
    if planets.is_empty():
        return
    
    # 1. 绘制连接线
    _draw_connections(planets)
    
    # 2. 绘制星球节点
    for planet in planets:
        _draw_planet(planet)

func _draw_connections(planets: Array) -> void:
    var drawn := {}  # 防止双向重复绘制
    for planet in planets:
        var adjacent = _planet_system.get_adjacent_planets(planet.id)
        for neighbor_id in adjacent:
            var key = _edge_key(planet.id, neighbor_id)
            if drawn.has(key):
                continue
            drawn[key] = true
            
            var to_planet = _planet_system.get_planet(neighbor_id)
            draw_line(planet.position, to_planet.position, COLOR_CONNECTION, LINE_WIDTH)

func _draw_planet(planet) -> void:
    var color = _get_owner_color(planet.owner)
    var pos = planet.position
    
    # 星球圆形
    draw_circle(pos, PLANET_RADIUS, color)
    
    # 圆形边框（细线）
    draw_arc(pos, PLANET_RADIUS, 0, TAU, 32, Color(1, 1, 1, 0.3), 1.0)
    
    # 星球名（上方 8px）
    var name_pos = pos + Vector2(0, -PLANET_RADIUS - 8)
    draw_string(_font, name_pos, planet.name, HORIZONTAL_ALIGNMENT_CENTER, -1, 8)
    
    # 兵力数字（居中）
    var garrison_text = str(planet.garrison)
    var text_pos = pos + Vector2(0, -7)  # 垂直居中偏移
    draw_string(_font, text_pos, garrison_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, COLOR_WHITE)

func _get_owner_color(owner: int) -> Color:
    match owner:
        DataDef.Faction.PLAYER:
            return COLOR_PLAYER
        DataDef.Faction.ENEMY:
            return COLOR_ENEMY
        _:
            return COLOR_NEUTRAL

func _edge_key(a: int, b: int) -> String:
    return "%d-%d" % [mini(a, b), max(a, b)]
```

### 关键实现要点

- 用 `Node2D` 而不是 `Control` — 星图是游戏世界视图，不是 UI 控件
- `_draw()` 中先画连接线再画星球 — 星球覆盖在线交叉点上，视觉正确
- `_edge_key()` 防止双向连接重复绘制 — `are_connected(1,3)` 和 `are_connected(3,1)` 都返回 true
- 颜色常量用 `Color()` 构造函数 — 十六进制 `Color("#4488FF")` 在 Godot 4.x 中有效
- 字体用 `ThemeDB.fallback_font` — MVP 不加载自定义字体
- 本 Story 只做渲染，不含交互 — 点击选中/高亮在 story-002 中实现
- `draw_string()` 的 `HORIZONTAL_ALIGNMENT_CENTER` 需要 Godot 4.x — 对应值为 1

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: 交互系统（点击选中/取消/高亮/详情面板/事件刷新/出征路由）
- 详情面板详细布局
- 窗口缩放/响应式
- 自定义字体加载
- 星球位置重叠检测/连接线交叉避免

---

## QA Test Cases

*Derived from GDD acceptance criteria.*

- **AC-1**: 4 星渲染
  - Given: planets_initialized emitted, 4 planets loaded
  - When: _draw() executes
  - Then: 4 circles drawn at correct positions (200,200/350,120/400,300/520,250)

- **AC-2**: 归属色
  - Given: planet 1 owner=PLAYER, planet 3 owner=ENEMY, others NEUTRAL
  - When: rendered
  - Then: planet 1 blue(#4488FF), planet 3 red(#FF4444), planets 2/4 gray(#888888)

- **AC-3**: 连接线
  - Given: connections [[1,2],[1,3],[3,4]]
  - When: rendered
  - Then: 3 distinct lines, each 2px, semi-transparent white

- **AC-4**: 文字标注
  - Given: planet 1 name="地球" garrison=10
  - When: rendered
  - Then: "地球" above circle, "10" centered in circle, both white

---

## Test Evidence

**Story Type**: UI
**Required evidence**:
- Manual walkthrough doc: `production/qa/evidence/star-map-ui-render.md` — must exist
- Screenshot of rendered star map with 4 planets — advisory

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Core planet-system (get_all_planets/get_adjacent_planets/get_planet) — must be DONE
- Depends on: Foundation event-bus (planets_initialized signal) — must be DONE
- Depends on: Feature level-data (tutorial_1.tres + init_from_level) — must be DONE
- Unlocks: Story 002 (interaction + event refresh)
- Unlocks: deployment-ui (click route to deployment panel)
