class_name Restoration
extends RefCounted
## How restored the current planet is, 0..1: the one number the planet readout, the bot's pacing
## marks and the ending read. Today it is the Bloom Core's stored charge (story/core_charge.gd),
## and exactly 1.0 once the ark has come home. Callers only use value(); the rule behind it is
## due to become a data rule from the PlanetDefinition (task M1-10).


static func value() -> float:
	if GameState.flags.get("cradle_returned", false):
		return 1.0
	return clampf(float(GameState.flags.get("core_charge", 0.0)), 0.0, 1.0)
