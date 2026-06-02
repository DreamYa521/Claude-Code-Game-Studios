# Game — 主游戏入口（自构建场景）
extends Node2D

var _star_map: Node2D
var _turn_control: Control
var _deployment_panel: Control


func _ready() -> void:
	# Create star map view
	_star_map = load("res://src/ui/star_map_view.gd").new()
	_star_map.name = "StarMapView"
	add_child(_star_map)

	# Create turn control UI
	_turn_control = load("res://src/ui/turn_control_ui.gd").new()
	_turn_control.name = "TurnControlUI"
	add_child(_turn_control)

	# Create deployment panel (modal overlay)
	_deployment_panel = load("res://src/ui/deployment_panel.gd").new()
	_deployment_panel.name = "DeploymentPanel"
	add_child(_deployment_panel)

	# Start game
	GameState.transition_to(DataDef.GameStateEnum.PLAYING)

	# Load tutorial level
	var level_data := _create_tutorial_level()
	PlanetSystem.init_from_level(level_data)

	# Begin first deployment phase
	EventBus.deployment_phase_started.emit()


# MVP: hardcoded tutorial level (4 planets, 3 connections)
func _create_tutorial_level():
	var level := RefCounted.new()

	level.set("planets", [
		_make_planet_def(1, "地球", Vector2(200, 350), DataDef.PlanetAttribute.NORMAL, DataDef.Faction.PLAYER, 10),
		_make_planet_def(2, "月球", Vector2(450, 150), DataDef.PlanetAttribute.BARREN, DataDef.Faction.NEUTRAL, 0),
		_make_planet_def(3, "火星", Vector2(500, 500), DataDef.PlanetAttribute.FORTRESS, DataDef.Faction.ENEMY, 8),
		_make_planet_def(4, "火卫一", Vector2(750, 380), DataDef.PlanetAttribute.NORMAL, DataDef.Faction.NEUTRAL, 3),
	])

	level.set("connections", [
		_make_connection(1, 2),
		_make_connection(1, 3),
		_make_connection(3, 4),
	])

	return level


func _make_planet_def(id: int, p_name: String, pos: Vector2, attr: int, owner: int, garrison: int):
	var d := RefCounted.new()
	d.set("id", id)
	d.set("name", p_name)
	d.set("position", pos)
	d.set("attribute", attr)
	d.set("owner", owner)
	d.set("garrison", garrison)
	return d


func _make_connection(from_id: int, to_id: int):
	var c := RefCounted.new()
	c.set("from_id", from_id)
	c.set("to_id", to_id)
	return c
