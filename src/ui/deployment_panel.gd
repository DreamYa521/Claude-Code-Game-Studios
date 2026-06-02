# DeploymentPanel — 出征面板（自构建 UI，模态弹出）
extends Control

var _panel: Panel
var _title_label: Label
var _target_info: Label
var _enemy_garrison: Label
var _slider: HSlider
var _count_label: Label
var _remaining_label: Label
var _confirm_btn: Button
var _cancel_btn: Button
var _error_label: Label

var _from_planet_id: int = -1
var _to_planet_id: int = -1


func _ready() -> void:
	# Full-screen modal overlay
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Dim background
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	# Center panel
	_panel = Panel.new()
	_panel.custom_minimum_size = Vector2(320, 240)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_title_label)

	_target_info = Label.new()
	_target_info.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_target_info)

	_enemy_garrison = Label.new()
	_enemy_garrison.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_enemy_garrison)

	# Slider container
	var slider_box := HBoxContainer.new()
	vbox.add_child(slider_box)

	_slider = HSlider.new()
	_slider.custom_minimum_size = Vector2(200, 20)
	_slider.step = 1
	_slider.value_changed.connect(_on_slider_value_changed)
	slider_box.add_child(_slider)

	_count_label = Label.new()
	_count_label.custom_minimum_size = Vector2(40, 20)
	_count_label.add_theme_font_size_override("font_size", 16)
	slider_box.add_child(_count_label)

	_remaining_label = Label.new()
	_remaining_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_remaining_label)

	# Buttons
	var btn_box := HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_box)

	_cancel_btn = Button.new()
	_cancel_btn.text = "取消 (Esc)"
	_cancel_btn.pressed.connect(_on_cancel)
	btn_box.add_child(_cancel_btn)

	_confirm_btn = Button.new()
	_confirm_btn.text = "确认发兵 (Enter)"
	_confirm_btn.pressed.connect(_on_confirm)
	btn_box.add_child(_confirm_btn)

	_error_label = Label.new()
	_error_label.add_theme_color_override("font_color", Color(1, 0.27, 0.27))
	_error_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_error_label)

	# Connect deployment signal
	EventBus.deployment_requested.connect(_on_deployment_requested)
	hide()


func _on_deployment_requested(from_id: int, to_id: int) -> void:
	open(from_id, to_id)


func open(from_id: int, to_id: int) -> void:
	_from_planet_id = from_id
	_to_planet_id = to_id

	var from_planet := PlanetSystem.get_planet(from_id)
	var to_planet := PlanetSystem.get_planet(to_id)
	if from_planet == null or to_planet == null:
		return

	_slider.min_value = 1
	_slider.max_value = from_planet.garrison
	_slider.value = from_planet.garrison

	_title_label.text = "出征：%s → %s" % [from_planet.name, to_planet.name]
	_target_info.text = "目标：%s (%s)" % [to_planet.name, _attr_name(to_planet.attribute)]
	_enemy_garrison.text = "敌方驻兵：%d" % to_planet.garrison

	_update_labels(int(_slider.value))
	_error_label.hide()

	show()
	_slider.grab_focus()


func _on_slider_value_changed(value: float) -> void:
	_update_labels(int(value))


func _update_labels(count: int) -> void:
	_count_label.text = str(count)
	var from_planet := PlanetSystem.get_planet(_from_planet_id)
	_remaining_label.text = "出发星剩余：%d" % (from_planet.garrison - count)


func _on_confirm() -> void:
	var count := int(_slider.value)
	var ok := DeploymentSystem.deploy(_from_planet_id, _to_planet_id, count, DataDef.UnitType.INFANTRY)

	if ok:
		close()
	else:
		_error_label.text = "出兵失败：兵力不足或条件不满足"
		_error_label.show()


func _on_cancel() -> void:
	close()


func close() -> void:
	hide()
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


func _attr_name(attr: int) -> String:
	match attr:
		DataDef.PlanetAttribute.NORMAL: return "普通"
		DataDef.PlanetAttribute.RICH: return "富饶"
		DataDef.PlanetAttribute.FORTRESS: return "要塞"
		DataDef.PlanetAttribute.BARREN: return "贫瘠"
	return "未知"
