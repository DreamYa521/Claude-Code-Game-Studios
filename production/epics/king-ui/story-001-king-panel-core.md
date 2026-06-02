# Story 001: 国王常驻面板 — 代际 + 名字 + 寿命条 + 天赋标签

> **Epic**: 国王 UI (king-ui)
> **Status**: Ready
> **Layer**: Presentation
> **Type**: UI
> **Estimate**: 1.5h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/king-ui.md`
**Requirement**: `TR-KUI-001`, `TR-KUI-002`

**ADR Governing Implementation**: ADR-0008: KingData 结构（name/talent/lifespan/actions_used/age/generation/talent_bonus）；ADR-0001: 通过 EventBus 接收国王状态变更
**ADR Decision Summary**: 常驻面板固定在屏幕左上角，显示代际数+天赋标签+名字+寿命条+剩余/总量数字。寿命条颜色按比例切换（绿→黄→橙→红），remaining≤3 时闪烁警告。订阅 action_consumed 信号更新寿命条。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Control` + `Label` + `TextureProgressBar`（或 `ColorRect` 手动控制宽度）。`_process()` 中做闪烁逻辑（`sin(Time.get_ticks_msec())` 控制 alpha）。

**Control Manifest Rules (this layer)**:
- Required: 国王 UI 常驻面板：代际+天赋标签+名字+寿命条+数字，左上角固定 — source: ADR-0008
- Required: 寿命条颜色：绿(>50%)→黄(30-50%)→橙(10-30%)→红(<10%)，≤3时闪烁 — source: ADR-0008
- Forbidden: 禁止 UI 直接修改星球状态 — source: ADR-0001

---

## Acceptance Criteria

*From GDD `design/gdd/king-ui.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN 游戏开始，WHEN 国王 UI 渲染，THEN 显示"第 1 代：征服者 阿尔萨斯"，寿命条全满，数字 "30/30"
- [ ] **AC-2**: GIVEN `action_consumed(25)` 信号（actions_used=5, lifespan=30），WHEN UI 刷新，THEN 显示"25/30"，寿命条长度为 25/30（约 83% 绿色）
- [ ] **AC-3**: GIVEN actions_used=10 (remaining=20/30=67%)，WHEN UI 刷新，THEN 寿命条绿色
- [ ] **AC-4**: GIVEN actions_used=16 (remaining=14/30=47%)，WHEN UI 刷新，THEN 寿命条黄色
- [ ] **AC-5**: GIVEN actions_used=22 (remaining=8/30=27%)，WHEN UI 刷新，THEN 寿命条橙色
- [ ] **AC-6**: GIVEN actions_used=28 (remaining=2/30=7%)，WHEN UI 刷新，THEN 寿命条红色 + 闪烁
- [ ] **AC-7**: GIVEN TITLE 状态，WHEN 渲染 UI，THEN 国王面板隐藏

---

## Implementation Notes

*Derived from ADR-0008 and GDD king-ui.md:*

### 场景结构

```
KingPanel (Control, 左上角锚定)
├── Background (Panel, 半透明深色背景)
│   ├── GenerationLabel ("👑 第 1 代")
│   ├── KingInfoLabel ("征服者 阿尔萨斯")
│   ├── LifeBar (ColorRect, 寿命条背景框)
│   │   └── LifeFill (ColorRect, 寿命条填充，宽度动态变化)
│   └── LifeLabel ("30/30")
```

### 核心代码

```gdscript
# king_panel.gd
class_name KingPanel extends Control

const COLOR_GREEN := Color("#44CC44")
const COLOR_YELLOW := Color("#CCCC00")
const COLOR_ORANGE := Color("#FF8800")
const COLOR_RED := Color("#FF2222")
const BAR_MAX_WIDTH := 200.0

@onready var _gen_label: Label = $Background/GenerationLabel
@onready var _info_label: Label = $Background/KingInfoLabel
@onready var _life_fill: ColorRect = $Background/LifeBar/LifeFill
@onready var _life_label: Label = $Background/LifeLabel

var _king_system  # KingSystem autoload 引用
var _blink_timer: float = 0.0
var _is_warning: bool = false

func _ready() -> void:
    EventBus.action_consumed.connect(_on_action_consumed)
    EventBus.king_succeeded.connect(_on_king_changed)
    EventBus.game_state_changed.connect(_on_game_state_changed)
    
    # 初始隐藏（king_initialized 信号后再显示）
    hide()
    EventBus.planets_initialized.connect(_on_game_ready)

func _on_game_ready() -> void:
    _refresh_all()

func _process(delta: float) -> void:
    if not _is_warning:
        return
    _blink_timer += delta
    # 闪烁：每 0.5 秒切换 alpha
    _life_fill.modulate.a = 0.3 + 0.7 * abs(sin(_blink_timer * PI * 2.0))

func _refresh_all() -> void:
    if not GameState.is_playing():
        hide()
        return
    
    var king = _king_system.current_king()
    if king == null:
        hide()
        return
    
    show()
    
    # 代际
    _gen_label.text = "👑 第 %d 代" % king.generation
    
    # 天赋 + 名字
    var talent_text = _talent_name(king.talent)
    _info_label.text = "%s %s" % [talent_text, king.name]
    
    # 寿命条
    var remaining = king.lifespan - king.actions_used
    var ratio = float(remaining) / float(king.lifespan)
    
    _life_fill.size.x = BAR_MAX_WIDTH * ratio
    _life_fill.color = _life_color(ratio)
    
    _life_label.text = "%d/%d" % [remaining, king.lifespan]
    
    # 闪烁警告
    _is_warning = remaining <= 3
    if not _is_warning:
        _life_fill.modulate.a = 1.0

func _life_color(ratio: float) -> Color:
    if ratio > 0.5:
        return COLOR_GREEN
    elif ratio > 0.3:
        return COLOR_YELLOW
    elif ratio > 0.1:
        return COLOR_ORANGE
    else:
        return COLOR_RED

func _talent_name(talent: int) -> String:
    match talent:
        DataDef.TalentType.CONQUEROR: return "征服者"
        DataDef.TalentType.RESEARCHER: return "科研者"
        DataDef.TalentType.HOARDER: return "囤积者"
        DataDef.TalentType.DIPLOMAT: return "外交者"
        _: return "未知"

func _on_action_consumed(_remaining: int) -> void:
    _refresh_all()

func _on_king_changed(_old: KingData, _new: KingData) -> void:
    _refresh_all()

func _on_game_state_changed(_old: int, new_state: int) -> void:
    if new_state == GameState.State.PLAYING:
        _refresh_all()
    else:
        hide()
```

### 关键实现要点

- 面板锚定左上角 — `anchor_left=0, anchor_top=0,` margin 提供边距
- `ColorRect` 手动控制 `size.x` 实现寿命条 — 不用 `TextureProgressBar`（更轻量）
- 闪烁通过 `_process()` + `sin()` 控制 alpha — 只在 warning 模式时启用
- 天赋标签 MVP 只是文字显示 — 无机制效果（ADR-0008: talent_bonus 留空 {}）
- 名字过长处理：设置 `Label.clip_text = true` 或手动截断
- `_refresh_all()` 在多个事件中调用 — 是幂等的（重复调用不产生副作用）
- 初始隐藏 → `planets_initialized` 后再检查 `GameState.is_playing()` 决定显示
- 本 Story 只做常驻面板，不含去世弹窗（story-002）

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: 去世/继位弹窗 + king_died/king_succeeded 事件集成
- KingSystem 核心逻辑（king-system epic 已实现）
- 天赋机制效果（MVP 不做）

---

## QA Test Cases

*Derived from GDD acceptance criteria.*

- **AC-1**: 初始显示
  - Given: 游戏开始, king={generation=1, talent=CONQUEROR, name="阿尔萨斯", lifespan=30, actions_used=0}
  - When: _refresh_all()
  - Then: "👑 第 1 代", "征服者 阿尔萨斯", 寿命条满格绿色, "30/30"

- **AC-2**: action_consumed 更新
  - Given: actions_used=5 → remaining=25
  - When: action_consumed(25) emitted
  - Then: "25/30", 寿命条 83% 宽

- **AC-3**: 绿色阈值
  - Given: remaining=20 (67%)
  - When: _refresh_all()
  - Then: life_fill.color == COLOR_GREEN

- **AC-4**: 黄色阈值
  - Given: remaining=14 (47%)
  - When: _refresh_all()
  - Then: life_fill.color == COLOR_YELLOW

- **AC-5**: 橙色阈值
  - Given: remaining=8 (27%)
  - When: _refresh_all()
  - Then: life_fill.color == COLOR_ORANGE

- **AC-6**: 红色 + 闪烁
  - Given: remaining=2 (7%)
  - When: _refresh_all()
  - Then: _is_warning=true, life_fill.color==COLOR_RED, alpha oscillating

- **AC-7**: TITLE 隐藏
  - Given: game_state_changed→TITLE
  - When: UI handles
  - Then: panel hidden

---

## Test Evidence

**Story Type**: UI
**Required evidence**:
- Manual walkthrough doc: `production/qa/evidence/king-ui-panel-walkthrough.md` — must exist
- Screenshots: full bar green, half bar yellow, low bar red with warning

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Core king-system (current_king(), KingData 结构) — must be DONE
- Depends on: Foundation event-bus (action_consumed, king_succeeded, game_state_changed, planets_initialized) — must be DONE
- Depends on: Foundation gamestate-manager (is_playing()) — must be DONE
- Unlocks: Story 002 (death/succession popup)
