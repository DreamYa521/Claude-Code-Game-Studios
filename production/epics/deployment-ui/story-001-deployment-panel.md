# Story 001: 出征面板 — 滑块 + 确认/取消 + deploy() 调用

> **Epic**: 出征 UI (deployment-ui)
> **Status**: Ready
> **Layer**: Presentation
> **Type**: UI
> **Estimate**: 1.5h
> **Manifest Version**: 2026-05-31
> **Last Updated**: 2026-05-31

## Context

**GDD**: `design/gdd/deployment-ui.md`
**Requirement**: `TR-DUI-001`, `TR-DUI-002`, `TR-DUI-003`, `TR-DUI-004`

**ADR Governing Implementation**: ADR-0001: UI 通过 EventBus 订阅刷新；ADR-0004: submit_command 后立即扣除出发星驻兵
**ADR Decision Summary**: 兵力滑块范围 1~garrison，默认全量。确认→调用 deploy()，返回 true 关闭面板/返回 false 显示红色提示。ESC 取消/Enter 确认。面板不直接修改数据，通过 DeploymentSystem.deploy() 提交。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Control` 节点 + `HSlider` + `Label` + `Button`。`HSlider.value_changed` 信号连接更新 Label。

**Control Manifest Rules (this layer)**:
- Required: 出征 UI：兵力滑块(1~garrison, 默认全量) + 动态'出发星剩余' + 确认/取消 — source: ADR-0001
- Required: 快捷键：ESC→取消出征，Enter→确认发兵 — source: ADR-0003
- Forbidden: 禁止 UI 直接修改星球状态 — source: ADR-0001

---

## Acceptance Criteria

*From GDD `design/gdd/deployment-ui.md`, scoped to this story:*

- [ ] **AC-1**: GIVEN 选中己方星(garrison=10) + 点击相邻敌星，WHEN UI 弹出，THEN 显示标题"出征：地球 → 火星"，滑块范围 1-10，默认值 10
- [ ] **AC-2**: GIVEN 滑块拖到 5 + 点击确认，WHEN `deploy()` 返回 true，THEN 面板关闭 + 出发星 garison 更新为 5（星图自动刷新）
- [ ] **AC-3**: GIVEN 滑块拖到 15（> garrison），WHEN 滑块范围限制，THEN 不能拖到 15（滑块 max = garrison = 10），deploy() 额外校验拦截
- [ ] **AC-4**: GIVEN 面板打开，WHEN 按 ESC，THEN 面板关闭，零指令生成
- [ ] **AC-5**: GIVEN 面板打开，WHEN 按 Enter，THEN 等效点击确认按钮
- [ ] **AC-6**: GIVEN 确认后 deploy() 返回 false（兵力不足），WHEN 错误处理，THEN 面板保持打开 + 显示红色错误提示

---

## Implementation Notes

*Derived from ADR-0001, ADR-0004 and GDD deployment-ui.md:*

### 场景结构

```
DeploymentPanel (Control)
├── Panel (背景容器, 300px宽)
│   ├── TitleLabel (出征：{from_name} → {to_name})
│   ├── TargetInfoLabel (目标：{to_name} ({attribute_text}))
│   ├── EnemyGarrisonLabel (敌方驻兵：{to_garrison})
│   ├── SliderContainer (HBoxContainer)
│   │   ├── HSlider (DeploySlider, 1~garrison, default=garrison)
│   │   └── CountLabel ("8")
│   ├── RemainingLabel (出发星剩余：{from_garrison - slider_value})
│   └── ButtonContainer (HBoxContainer)
│       ├── CancelButton ([取消])
│       └── ConfirmButton ([确认发兵])
└── ErrorLabel (红色错误提示，默认隐藏)
```

### 核心代码

```gdscript
# deployment_panel.gd
class_name DeploymentPanel extends Control

@onready var _slider: HSlider = $Panel/SliderContainer/DeploySlider
@onready var _count_label: Label = $Panel/SliderContainer/CountLabel
@onready var _remaining_label: Label = $Panel/RemainingLabel
@onready var _title_label: Label = $Panel/TitleLabel
@onready var _target_info: Label = $Panel/TargetInfoLabel
@onready var _enemy_garrison: Label = $Panel/EnemyGarrisonLabel
@onready var _error_label: Label = $Panel/ErrorLabel

var _from_planet_id: int = -1
var _to_planet_id: int = -1
var _deployment_system  # DeploymentSystem autoload 引用

func open(from_id: int, to_id: int) -> void:
    _from_planet_id = from_id
    _to_planet_id = to_id
    
    var from_planet = PlanetSystem.get_planet(from_id)
    var to_planet = PlanetSystem.get_planet(to_id)
    
    # 设置范围
    _slider.min_value = 1
    _slider.max_value = from_planet.garrison
    _slider.value = from_planet.garrison  # 默认全量
    
    # 设置文字
    _title_label.text = "出征：%s → %s" % [from_planet.name, to_planet.name]
    _target_info.text = "目标星球：%s (%s)" % [to_planet.name, _attribute_text(to_planet.attribute)]
    _enemy_garrison.text = "敌方驻兵：%d" % to_planet.garrison
    
    _update_labels(from_planet.garrison)
    _error_label.hide()
    
    visible = true
    _slider.grab_focus()

func _on_slider_value_changed(value: float) -> void:
    _update_labels(int(value))

func _update_labels(count: int) -> void:
    _count_label.text = str(count)
    var from_planet = PlanetSystem.get_planet(_from_planet_id)
    _remaining_label.text = "出发星剩余：%d" % (from_planet.garrison - count)

func _on_confirm() -> void:
    var count = int(_slider.value)
    var from_planet = PlanetSystem.get_planet(_from_planet_id)
    
    var ok = _deployment_system.deploy(
        _from_planet_id, _to_planet_id, count, DataDef.UnitType.INFANTRY,
        PlanetSystem.get_all_planets_dict(),
        PlanetSystem.get_connections_array(),
        GameState.is_playing(),
        TurnManager.current_phase
    )
    
    if ok:
        close()
    else:
        _error_label.text = "出兵失败：兵力不足或条件不满足"
        _error_label.show()

func _on_cancel() -> void:
    close()

func close() -> void:
    visible = false
    _from_planet_id = -1
    _to_planet_id = -1

func _input(event: InputEvent) -> void:
    if not visible:
        return
    if event.is_action_pressed("ui_cancel"):
        _on_cancel()
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("ui_accept"):
        _on_confirm()
        get_viewport().set_input_as_handled()

func _attribute_text(attr: int) -> String:
    match attr:
        DataDef.PlanetAttribute.NORMAL: return "普通"
        DataDef.PlanetAttribute.RICH: return "富饶"
        DataDef.PlanetAttribute.FORTRESS: return "要塞"
        DataDef.PlanetAttribute.BARREN: return "贫瘠"
        _: return "未知"
```

### 集成入口

```gdscript
# 在 star_map_view.gd 或 SceneManager 中：
EventBus.deployment_requested.connect(_on_deployment_requested)

func _on_deployment_requested(from: int, to: int) -> void:
    $DeploymentPanel.open(from, to)
```

### 关键实现要点

- `_slider.max_value` 在 open() 时动态设置 — 不能写死
- 确认按钮直接调用 `DeploymentSystem.deploy()` — 参数显式传入（纯函数风格）
- 快捷键用 `_input()` + `is_action_pressed("ui_cancel"/"ui_accept")` — 兼容 Godot 内置 Input Map
- 错误提示用红色 Label + `hide()/show()` — 不用 popup
- 面板关闭时 `_from_planet_id` 设为 -1 — 防止残留引用
- 本 Story 不负责 deploy() 内部逻辑（属于 deployment-system epic）
- MVP 不显示兵种选择 — 默认 `DataDef.UnitType.INFANTRY`

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- DeploymentSystem.deploy() 实现 — 属于 deployment-system epic
- 预测显示（"预计损失约 2，剩余 6"）— MVP 不做
- 兵种选择下拉框 — MVP 默认步兵
- 面板弹出动画

---

## QA Test Cases

*Derived from GDD acceptance criteria.*

- **AC-1**: 面板弹出
  - Given: from=地球(garrison=10), to=火星(garrison=5)
  - When: open(1, 3)
  - Then: title="出征：地球 → 火星", slider max=10 value=10, count="10", remaining="出发星剩余：0"

- **AC-2**: 确认成功
  - Given: slider=5, deploy() returns true
  - When: _on_confirm()
  - Then: panel hidden, from garrison reduced

- **AC-3**: 滑块边界
  - Given: slider min=1 max=10
  - When: try to drag below 1 or above 10
  - Then: slider clamps to range

- **AC-4**: ESC 取消
  - Given: panel visible
  - When: press Esc
  - Then: panel hidden, no deploy() called

- **AC-5**: Enter 确认
  - Given: panel visible, slider=8
  - When: press Enter
  - Then: same as clicking confirm button

- **AC-6**: 确认失败
  - Given: slider=12 but garrison=8 (edge case irrelevant due to slider max)
  - Actually test: deploy() returns false via mocked system
  - When: _on_confirm()
  - Then: panel stays open, red error shown

---

## Test Evidence

**Story Type**: UI
**Required evidence**:
- Manual walkthrough doc: `production/qa/evidence/deployment-ui-walkthrough.md` — must exist
- Screenshots: panel open with slider, error state, confirm success

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Core deployment-system (deploy() function) — must be DONE
- Depends on: Core planet-system (get_planet) — must be DONE
- Depends on: Foundation event-bus (deployment_requested signal) — must be DONE
- Depends on: Presentation star-map-ui (interaction triggers deployment_requested) — must be DONE
