# StarMapView — 星图渲染和交互
# Attached to: StarMapView (Node2D)
extends Node2D

const PLANET_RADIUS := 24.0
const LINE_WIDTH := 2.0
const COLOR_PLAYER := Color("#4488FF")
const COLOR_ENEMY := Color("#FF4444")
const COLOR_NEUTRAL := Color("#888888")
const COLOR_CONNECTION := Color(1.0, 1.0, 1.0, 0.5)
const COLOR_HIGHLIGHT_SELECTED := Color.WHITE
const COLOR_HIGHLIGHT_ATTACKABLE := Color("#FFCC00")

var _font: Font
var _selected_planet_id: int = -1
var _highlighted_planet_ids: Array[int] = []


func _ready() -> void:
	_font = ThemeDB.fallback_font
	EventBus.planets_initialized.connect(_on_planets_initialized)
	EventBus.planet_owner_changed.connect(_on_data_changed)
	EventBus.planet_garrison_changed.connect(_on_data_changed)
	EventBus.turn_ended.connect(_on_turn_ended)
	EventBus.game_ended.connect(_on_game_ended)


func _on_planets_initialized() -> void:
	queue_redraw()


func _on_data_changed(_a=0, _b=0, _c=0) -> void:
	queue_redraw()


func _on_turn_ended(_turn: int) -> void:
	_deselect_all()
	queue_redraw()


func _on_game_ended(_result: String) -> void:
	_deselect_all()
	queue_redraw()


# === Drawing ===

func _draw() -> void:
	var planets := PlanetSystem.get_all_planets()
	if planets.is_empty():
		return

	_draw_connections(planets)
	for planet in planets:
		_draw_planet(planet)


func _draw_connections(planets: Array) -> void:
	var drawn := {}
	for planet in planets:
		var adjacent := PlanetSystem.get_adjacent_planets(planet.id)
		for neighbor_id in adjacent:
			var key := "%d-%d" % [min(planet.id, neighbor_id), max(planet.id, neighbor_id)]
			if drawn.has(key):
				continue
			drawn[key] = true
			var other := PlanetSystem.get_planet(neighbor_id)
			if other:
				draw_line(planet.position, other.position, COLOR_CONNECTION, LINE_WIDTH)


func _draw_planet(planet) -> void:
	var color := COLOR_NEUTRAL
	match planet.owner:
		DataDef.Faction.PLAYER: color = COLOR_PLAYER
		DataDef.Faction.ENEMY: color = COLOR_ENEMY

	var pos := planet.position

	# Planet circle
	draw_circle(pos, PLANET_RADIUS, color)
	draw_arc(pos, PLANET_RADIUS, 0, TAU, 32, Color(1, 1, 1, 0.3), 1.0)

	# Selection / highlight rings
	if planet.id == _selected_planet_id:
		draw_arc(pos, PLANET_RADIUS + 3, 0, TAU, 32, COLOR_HIGHLIGHT_SELECTED, 2.0)
	if planet.id in _highlighted_planet_ids:
		draw_arc(pos, PLANET_RADIUS + 3, 0, TAU, 32, COLOR_HIGHLIGHT_ATTACKABLE, 2.0)

	# Name (above)
	var name_pos := pos + Vector2(0, -PLANET_RADIUS - 10)
	draw_string(_font, name_pos, planet.name, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color.WHITE)

	# Garrison count (centered)
	var g_text := str(planet.garrison)
	var g_pos := pos + Vector2(0, -7)
	draw_string(_font, g_pos, g_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color.WHITE)


# === Interaction ===

func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not event.pressed:
		return
	if not GameState.is_playing():
		return
	if TurnManager.current_phase != DataDef.TurnPhase.DEPLOYMENT:
		return

	var clicked := _hit_test(event.position)

	if clicked == -1:
		_deselect_all()
		return

	if _selected_planet_id == -1:
		_select_planet(clicked)
	elif clicked == _selected_planet_id:
		_deselect_all()
	else:
		var clicked_planet := PlanetSystem.get_planet(clicked)
		var selected_planet := PlanetSystem.get_planet(_selected_planet_id)

		if selected_planet.owner == DataDef.Faction.PLAYER and clicked_planet.owner != DataDef.Faction.PLAYER and PlanetSystem.is_adjacent(_selected_planet_id, clicked):
			# Trigger deployment panel
			EventBus.deployment_requested.emit(_selected_planet_id, clicked)
		else:
			# Switch selection
			_select_planet(clicked)


func _hit_test(mouse_pos: Vector2) -> int:
	for planet in PlanetSystem.get_all_planets():
		if mouse_pos.distance_to(planet.position) <= PLANET_RADIUS:
			return planet.id
	return -1


func _select_planet(planet_id: int) -> void:
	_selected_planet_id = planet_id
	_highlighted_planet_ids.clear()

	var planet := PlanetSystem.get_planet(planet_id)
	if planet.owner == DataDef.Faction.PLAYER:
		for nid in PlanetSystem.get_adjacent_planets(planet_id):
			var neighbor := PlanetSystem.get_planet(nid)
			if neighbor.owner != DataDef.Faction.PLAYER:
				_highlighted_planet_ids.append(nid)

	queue_redraw()


func _deselect_all() -> void:
	_selected_planet_id = -1
	_highlighted_planet_ids.clear()
	queue_redraw()
