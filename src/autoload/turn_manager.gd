# TurnManager — 回合管线
# Autoload: turn_manager (load order: 4 — depends on event_bus, game_state)
# ADR: ADR-0004 (snapshot model, 5-step resolution)
extends Node

var current_phase: int = DataDef.TurnPhase.DEPLOYMENT
var turn_number: int = 1
var _snapshot: Dictionary = {}
var _end_turn_requested: bool = false


func end_turn() -> bool:
	if not GameState.is_playing():
		return false
	if current_phase != DataDef.TurnPhase.DEPLOYMENT:
		return false
	if _end_turn_requested:
		return false  # double-click guard

	_end_turn_requested = true
	_run_execution()
	return true


func _run_execution() -> void:
	# Phase: EXECUTION
	current_phase = DataDef.TurnPhase.EXECUTION
	EventBus.execution_phase_started.emit()

	# 5-step resolution
	# Step 1: Apply production
	_apply_production()

	# Step 2: Resolve all combats
	_resolve_combats()

	# Step 3: Apply occupation results
	_apply_occupation()

	# Step 4: King lifespan update (MVP: simplified — stub for now)
	# _consume_king_turn()

	# Step 5: Check win conditions
	_check_win_conditions()

	# Phase: CLEANUP → next DEPLOYMENT
	current_phase = DataDef.TurnPhase.CLEANUP
	turn_number += 1
	current_phase = DataDef.TurnPhase.DEPLOYMENT

	_end_turn_requested = false
	EventBus.turn_ended.emit(turn_number)
	EventBus.deployment_phase_started.emit()


func _apply_production() -> void:
	for planet in PlanetSystem.get_all_planets():
		if planet.owner == DataDef.Faction.NEUTRAL:
			continue
		var rate := DataDef.PLANET_PRODUCTION_RATE.get(planet.attribute, 1)
		var max_g := DataDef.PLANET_MAX_GARRISON.get(planet.attribute, 20)
		var new_g := min(planet.garrison + rate, max_g)
		if new_g != planet.garrison:
			PlanetSystem.set_garrison(planet.id, new_g)


func _resolve_combats() -> void:
	var all_planets := PlanetSystem.get_all_planets()
	var pending_transfers: Array = []

	for planet in all_planets:
		var attackers := _get_attackers_for(planet.id)
		if attackers.is_empty():
			continue

		for cmd in attackers:
			var result := _resolve_single(cmd, planet)
			pending_transfers.append(result)

	for transfer in pending_transfers:
		PlanetSystem.transfer_ownership(transfer["planet_id"], transfer["new_owner"], transfer["new_garrison"])


func _resolve_single(cmd, defender_planet) -> Dictionary:
	var atk_stats := _get_unit_stats(cmd.unit_type)
	var def_stats := _get_unit_stats(DataDef.UnitType.INFANTRY)  # defender always infantry for MVP

	var counter_mult := DataDef.DAMAGE_MATRIX[cmd.unit_type][DataDef.UnitType.INFANTRY]
	var defense_mult := DataDef.PLANET_DEFENSE_MULT.get(defender_planet.attribute, 1.0)

	var atk_power := cmd.count * atk_stats.attack * counter_mult
	var def_power := defender_planet.garrison * def_stats.defense * defense_mult

	var remaining: int
	var new_owner: int

	if atk_power > def_power:
		remaining = max(0, cmd.count - int(ceil(float(defender_planet.garrison) * def_stats.defense * defense_mult / (atk_stats.attack * counter_mult))))
		new_owner = PlanetSystem.get_planet(cmd.from_planet).owner
	else:
		remaining = max(0, defender_planet.garrison - int(ceil(atk_power / (def_stats.defense * defense_mult))))
		new_owner = defender_planet.owner

	return {"planet_id": defender_planet.id, "new_owner": new_owner, "new_garrison": remaining}


func _get_attackers_for(planet_id: int) -> Array:
	return DeploymentSystem.get_commands_for(planet_id)


func _apply_occupation() -> void:
	# Handled inside _resolve_combats via transfer_ownership
	# Empty neutral planets with attackers → immediate occupation
	for cmd in DeploymentSystem.get_all_pending():
		var planet := PlanetSystem.get_planet(cmd.to_planet)
		if planet.owner == DataDef.Faction.NEUTRAL and planet.garrison == 0:
			PlanetSystem.set_owner(cmd.to_planet, PlanetSystem.get_planet(cmd.from_planet).owner)
			PlanetSystem.set_garrison(cmd.to_planet, cmd.count)

	DeploymentSystem.clear_all()


func _check_win_conditions() -> void:
	var player_planets := PlanetSystem.get_planets_by_owner(DataDef.Faction.PLAYER)
	var enemy_planets := PlanetSystem.get_planets_by_owner(DataDef.Faction.ENEMY)

	if enemy_planets.is_empty():
		GameState.transition_to(DataDef.GameStateEnum.VICTORY)
		EventBus.game_ended.emit("victory")
	elif player_planets.is_empty():
		GameState.transition_to(DataDef.GameStateEnum.DEFEAT)
		EventBus.game_ended.emit("defeat")


func _get_unit_stats(unit_type: int):
	return DeploymentSystem._unit_stats_cache.get(unit_type, {"attack": 10, "defense": 8})


func phase_name(phase: int = -1) -> String:
	var p := current_phase if phase == -1 else phase
	match p:
		DataDef.TurnPhase.DEPLOYMENT: return "部署阶段"
		DataDef.TurnPhase.EXECUTION: return "结算中..."
		DataDef.TurnPhase.CLEANUP: return "收尾中..."
	return "未知"
