# DeploymentSystem — 出征命令管理
# Autoload: deployment_system (load order: 6)
# ADR: ADR-0004 (step 1 command intake)
extends Node

# Deployment command struct
class DeploymentCommand:
	var from_planet: int
	var to_planet: int
	var count: int
	var unit_type: int


var _pending_commands: Array[DeploymentCommand] = []
var _unit_stats_cache: Dictionary = {}


# === Public API ===

func deploy(from_id: int, to_id: int, count: int, unit_type: int) -> bool:
	# Validate
	if not GameState.is_playing():
		return false
	if TurnManager.current_phase != DataDef.TurnPhase.DEPLOYMENT:
		return false

	var from_planet := PlanetSystem.get_planet(from_id)
	var to_planet := PlanetSystem.get_planet(to_id)
	if from_planet == null or to_planet == null:
		return false

	# Can only deploy from owned planets
	if from_planet.owner != DataDef.Faction.PLAYER:
		return false

	# Must be adjacent
	if not PlanetSystem.is_adjacent(from_id, to_id):
		return false

	# Can't attack own planets
	if to_planet.owner == DataDef.Faction.PLAYER:
		return false

	# Must have enough troops
	if count < 1 or count > from_planet.garrison:
		return false

	# Deduct troops from source planet (immediate — overdraft protection)
	PlanetSystem.set_garrison(from_id, from_planet.garrison - count)

	# Register command
	var cmd := DeploymentCommand.new()
	cmd.from_planet = from_id
	cmd.to_planet = to_id
	cmd.count = count
	cmd.unit_type = unit_type
	_pending_commands.append(cmd)

	return true


func validate(from_id: int, to_id: int, count: int) -> String:
	var from_planet := PlanetSystem.get_planet(from_id)
	if from_planet == null:
		return "出发星球不存在"

	if from_planet.owner != DataDef.Faction.PLAYER:
		return "只能从己方星球出征"

	if not PlanetSystem.is_adjacent(from_id, to_id):
		return "目标星球不相邻"

	if count < 1:
		return "至少派出 1 兵力"
	if count > from_planet.garrison:
		return "兵力不足"

	return ""


func get_commands_for(planet_id: int) -> Array:
	var arr: Array = []
	for cmd in _pending_commands:
		if cmd.to_planet == planet_id:
			arr.append(cmd)
	return arr


func get_all_pending() -> Array:
	return _pending_commands


func clear_all() -> void:
	_pending_commands.clear()


# === Unit Stats (MVP: hardcoded — later load from .tres) ===

func _ready() -> void:
	# Infantry
	_unit_stats_cache[DataDef.UnitType.INFANTRY] = {"attack": 10, "defense": 8, "speed": 3, "cost": 5}
	# Archer
	_unit_stats_cache[DataDef.UnitType.ARCHER] = {"attack": 12, "defense": 5, "speed": 4, "cost": 6}
	# Cavalry
	_unit_stats_cache[DataDef.UnitType.CAVALRY] = {"attack": 15, "defense": 6, "speed": 5, "cost": 8}


func get_unit_stats(unit_type: int) -> Dictionary:
	return _unit_stats_cache.get(unit_type, {"attack": 10, "defense": 8, "speed": 3, "cost": 5})
