# TurnControlUI — 回合控制面板（自构建 UI）
extends Control

var _turn_label: Label
var _end_turn_btn: Button
var _phase_label: Label
var _panel: Panel


func _ready() -> void:
	# Anchor top-right
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -180
	offset_right = -16
	offset_top = 16
	offset_bottom = 120

	# Build UI
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.size_flags_horizontal = Control.SIZE_FILL
	_panel.size_flags_vertical = Control.SIZE_FILL
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	_turn_label = Label.new()
	_turn_label.text = "第 1 回合"
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_turn_label)

	_end_turn_btn = Button.new()
	_end_turn_btn.text = "结束回合"
	_end_turn_btn.custom_minimum_size = Vector2(140, 36)
	_end_turn_btn.pressed.connect(_on_end_turn)
	vbox.add_child(_end_turn_btn)

	var shortcut_label := Label.new()
	shortcut_label.text = "Space / E"
	shortcut_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shortcut_label.add_theme_font_size_override("font_size", 10)
	shortcut_label.add_theme_color_override("font_color", Color(0.53, 0.6, 0.67))
	vbox.add_child(shortcut_label)

	_phase_label = Label.new()
	_phase_label.text = "部署阶段"
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_phase_label)

	# Connect signals
	EventBus.deployment_phase_started.connect(_on_deployment_phase)
	EventBus.execution_phase_started.connect(_on_execution_phase)
	EventBus.turn_ended.connect(_on_turn_ended)
	EventBus.game_state_changed.connect(_on_game_state_changed)

	_update_button_state()


func _on_end_turn() -> void:
	_end_turn_btn.disabled = true
	_end_turn_btn.text = "结算中..."
	TurnManager.end_turn()


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


func _on_game_state_changed(_old: int, new_state: int) -> void:
	match new_state:
		DataDef.GameStateEnum.PLAYING:
			show()
			_update_button_state()
		DataDef.GameStateEnum.PAUSED:
			show()
			_end_turn_btn.hide()
			_phase_label.text = "已暂停"
		DataDef.GameStateEnum.VICTORY:
			show()
			_end_turn_btn.hide()
			_phase_label.text = "胜利!"
		DataDef.GameStateEnum.DEFEAT:
			show()
			_end_turn_btn.hide()
			_phase_label.text = "失败"
		_:
			hide()


func _update_button_state() -> void:
	if TurnManager.current_phase == DataDef.TurnPhase.DEPLOYMENT:
		_end_turn_btn.show()
		_end_turn_btn.disabled = false
		_end_turn_btn.text = "结束回合"
	else:
		_end_turn_btn.show()
		_end_turn_btn.disabled = true
		_end_turn_btn.text = "结算中..."


func _input(event: InputEvent) -> void:
	if not GameState.is_playing():
		return
	if TurnManager.current_phase != DataDef.TurnPhase.DEPLOYMENT:
		return
	if event.is_action_pressed("end_turn_space") or event.is_action_pressed("end_turn_e"):
		_on_end_turn()
		get_viewport().set_input_as_handled()
