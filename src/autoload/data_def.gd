# DataDef — 全局枚举和常量定义
# Autoload: data_def (load order: 1 — no dependencies)
# ADR: ADR-0002
extends Node

# === Unit Types ===
enum UnitType {
	INFANTRY = 0,
	ARCHER = 1,
	CAVALRY = 2,
}

# === Factions ===
enum Faction {
	PLAYER = 0,
	ENEMY = 1,
	NEUTRAL = 2,
}

# === Planet Attributes ===
enum PlanetAttribute {
	NORMAL = 0,
	RICH = 1,
	FORTRESS = 2,
	BARREN = 3,
}

# === Game States ===
enum GameStateEnum {
	TITLE = 0,
	PLAYING = 1,
	PAUSED = 2,
	VICTORY = 3,
	DEFEAT = 4,
}

# === Turn Phases ===
enum TurnPhase {
	DEPLOYMENT = 0,
	EXECUTION = 1,
	CLEANUP = 2,
}

# === King Talents ===
enum TalentType {
	WARLORD = 0,
	SCIENTIST = 1,
	HOARDER = 2,
	DIPLOMAT = 3,
}

# === Damage Matrix (attacker row → defender column) ===
# INFANTRY vs ARCHER vs CAVALRY
const DAMAGE_MATRIX := {
	UnitType.INFANTRY: {UnitType.INFANTRY: 1.0, UnitType.ARCHER: 0.5, UnitType.CAVALRY: 2.0},
	UnitType.ARCHER:  {UnitType.INFANTRY: 2.0, UnitType.ARCHER: 1.0,  UnitType.CAVALRY: 0.5},
	UnitType.CAVALRY: {UnitType.INFANTRY: 0.5, UnitType.ARCHER: 2.0,  UnitType.CAVALRY: 1.0},
}

# === Planet Defense Multipliers ===
const PLANET_DEFENSE_MULT := {
	PlanetAttribute.NORMAL: 1.0,
	PlanetAttribute.RICH: 1.0,
	PlanetAttribute.FORTRESS: 1.5,
	PlanetAttribute.BARREN: 0.75,
}

# === Production Rates (per turn) ===
const PLANET_PRODUCTION_RATE := {
	PlanetAttribute.NORMAL: 2,
	PlanetAttribute.RICH: 3,
	PlanetAttribute.FORTRESS: 1,
	PlanetAttribute.BARREN: 1,
}

# === Max Garrison by Attribute ===
const PLANET_MAX_GARRISON := {
	PlanetAttribute.NORMAL: 20,
	PlanetAttribute.RICH: 30,
	PlanetAttribute.FORTRESS: 25,
	PlanetAttribute.BARREN: 15,
}
