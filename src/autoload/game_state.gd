# GameState — 游戏状态机
# Autoload: game_state (load order: 3 — depends on event_bus)
# ADR: ADR-0003 (5 states, 7 legal transitions)
extends Node

var current_state: int = DataDef.GameStateEnum.TITLE


# === Legal Transition Map ===
const _LEGAL_TRANSITIONS := {
	DataDef.GameStateEnum.TITLE: [DataDef.GameStateEnum.PLAYING],
	DataDef.GameStateEnum.PLAYING: [DataDef.GameStateEnum.PAUSED, DataDef.GameStateEnum.VICTORY, DataDef.GameStateEnum.DEFEAT],
	DataDef.GameStateEnum.PAUSED: [DataDef.GameStateEnum.PLAYING],
	DataDef.GameStateEnum.VICTORY: [DataDef.GameStateEnum.TITLE],
	DataDef.GameStateEnum.DEFEAT: [DataDef.GameStateEnum.TITLE],
}


func transition_to(new_state: int) -> bool:
	if new_state == current_state:
		return false  # no-op

	var allowed := _LEGAL_TRANSITIONS.get(current_state, [])
	if new_state not in allowed:
		push_warning("[GameState] Illegal transition: %d → %d" % [current_state, new_state])
		return false

	var old := current_state
	current_state = new_state
	EventBus.game_state_changed.emit(old, new_state)
	return true


func is_playing() -> bool:
	return current_state == DataDef.GameStateEnum.PLAYING


func is_game_over() -> bool:
	return current_state == DataDef.GameStateEnum.VICTORY or current_state == DataDef.GameStateEnum.DEFEAT


func state_name(state: int = -1) -> String:
	var s := current_state if state == -1 else state
	match s:
		DataDef.GameStateEnum.TITLE: return "TITLE"
		DataDef.GameStateEnum.PLAYING: return "PLAYING"
		DataDef.GameStateEnum.PAUSED: return "PAUSED"
		DataDef.GameStateEnum.VICTORY: return "VICTORY"
		DataDef.GameStateEnum.DEFEAT: return "DEFEAT"
	return "UNKNOWN"
