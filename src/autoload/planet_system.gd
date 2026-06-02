# PlanetSystem — 星球运行时数据管理
# Autoload: planet_system (load order: 5)
# ADR: ADR-0005 (RuntimePlanetData + adjacency)
extends Node

# Runtime planet data (mutable during gameplay)
class RuntimePlanet:
	var id: int
	var name: String
	var position: Vector2
	var attribute: int  # PlanetAttribute
	var owner: int       # Faction
	var garrison: int
	var production_rate: int
	var max_garrison: int
	var accumulated_production: float = 0.0

	func _init(_id: int, _name: String, _pos: Vector2, _attr: int, _owner: int, _garrison: int) -> void:
		id = _id
		name = _name
		position = _pos
		attribute = _attr
		owner = _owner
		garrison = _garrison
		production_rate = DataDef.PLANET_PRODUCTION_RATE.get(_attr, 2)
		max_garrison = DataDef.PLANET_MAX_GARRISON.get(_attr, 20)


# Internal storage
var _planets: Dictionary = {}  # id → RuntimePlanet
var _adjacency: Dictionary = {}  # id → Array[id]


# === Public API ===

func init_from_level(level_data) -> void:
	_planets.clear()
	_adjacency.clear()
	for def in level_data.planets:
		var planet := RuntimePlanet.new(def.id, def.name, def.position, def.attribute, def.owner, def.garrison)
		_planets[planet.id] = planet
	for conn in level_data.connections:
		if not _adjacency.has(conn.from_id):
			_adjacency[conn.from_id] = []
		if not _adjacency.has(conn.to_id):
			_adjacency[conn.to_id] = []
		_adjacency[conn.from_id].append(conn.to_id)
		_adjacency[conn.to_id].append(conn.from_id)
	EventBus.planets_initialized.emit()


func get_planet(id: int) -> RuntimePlanet:
	return _planets.get(id)


func get_all_planets() -> Array:
	var arr: Array = []
	for p in _planets.values():
		arr.append(p)
	return arr


func get_adjacent_planets(id: int) -> Array:
	return _adjacency.get(id, [])


func get_planets_by_owner(owner: int) -> Array:
	var arr: Array = []
	for p in _planets.values():
		if p.owner == owner:
			arr.append(p)
	return arr


# === Mutations (with EventBus notification) ===

func set_garrison(planet_id: int, new_val: int) -> void:
	var planet := _planets.get(planet_id)
	if planet == null:
		return
	var old := planet.garrison
	planet.garrison = clamp(new_val, 0, planet.max_garrison)
	EventBus.planet_garrison_changed.emit(planet_id, old, planet.garrison)


func set_owner(planet_id: int, new_owner: int) -> void:
	var planet := _planets.get(planet_id)
	if planet == null:
		return
	var old := planet.owner
	planet.owner = new_owner
	EventBus.planet_owner_changed.emit(planet_id, old, new_owner)


func transfer_ownership(planet_id: int, new_owner: int, new_garrison: int) -> void:
	set_owner(planet_id, new_owner)
	set_garrison(planet_id, new_garrison)


# === Snapshot (for deterministic resolution) ===

func snapshot() -> Dictionary:
	var snap := {}
	for id in _planets:
		var p := _planets[id]
		snap[id] = {"owner": p.owner, "garrison": p.garrison, "attribute": p.attribute}
	return snap


func restore(snap: Dictionary) -> void:
	for id in snap:
		var p := _planets.get(id)
		if p:
			var s := snap[id]
			p.owner = s["owner"]
			p.garrison = s["garrison"]


# === Query Helpers ===

func is_adjacent(from_id: int, to_id: int) -> bool:
	var adj := _adjacency.get(from_id, [])
	return to_id in adj


func planet_count() -> int:
	return _planets.size()
