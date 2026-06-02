# EventBus — 全局信号中转站
# Autoload: event_bus (load order: 2 — no dependencies)
# ADR: ADR-0001
extends Node

# === Planet Events ===
signal planets_initialized()
signal planet_owner_changed(planet_id: int, old_owner: int, new_owner: int)
signal planet_garrison_changed(planet_id: int, old_val: int, new_val: int)

# === Turn Phase Events ===
signal deployment_phase_started()
signal execution_phase_started()
signal turn_ended(turn_number: int)

# === Game State Events ===
signal game_state_changed(old_state: int, new_state: int)
signal game_ended(result: String)

# === Deployment Events ===
signal deployment_requested(from_planet: int, to_planet: int)

# === Presentation Events ===
signal animations_complete()
signal king_succession_complete(old_king_id: int, new_king_id: int)
signal action_consumed(remaining: int)
signal king_died(king_name: String, generation: int)
signal king_succeeded(new_king_name: String, generation: int, talent: int)


# === Recursion Guard ===
var _emit_stack: Array[String] = []
var max_recursion_depth: int = 10


func _emit_safe(signal_name: String, callable: Callable) -> void:
	if _emit_stack.count(signal_name) >= max_recursion_depth:
		push_error("[EventBus] Recursion detected on signal '%s' (depth=%d)" % [signal_name, max_recursion_depth])
		return

	_emit_stack.append(signal_name)
	callable.call()
	_emit_stack.erase(signal_name)


func reset_emit_stack() -> void:
	_emit_stack.clear()
