class_name SurgeRules
extends RefCounted
## The rules of the Surge (design spec section 8) as pure functions over a planet's "balance"
## table, block "surge". systems/surge.gd holds the state; tests and tools read the same numbers.
##
##   charge needed in district n   charge.units[n - 1] units of hand work (the last entry for any
##                                 district past the end of the list)
##   one pressed bale              charge.per_bale of a full charge
##   one seed planted / one pour   charge.per_plant / charge.per_water of a full charge
##   fastest a core can fill       charge.min_fill_s seconds, however fast Lumi works
##   a stat during a Surge         x (1 + (stats[stat] - 1) x power(n)),
##                                 power(n) = 1 + power_per_district x (n - 1)
##   output during a Surge         scoop_rate x pickup_count of the above (pulses a second x
##                                 waste a pulse)
##   chest room of swept waste     chest_pack / output: at chest_pack 1 the chest fills as fast
##                                 as in plain sweeping, below 1 slower
##   the growth wave               from wave.from_district on: wave.rings + wave.rings_per_district
##                                 x (n - from_district) rings of hexes round Lumi
##
## n is the district's place in the planet's play order, from 1. A planet with no "surge" block
## has no Surge.

const TABLE: String = "balance"
const BLOCK: String = "surge"
const STAT_RATE: String = "scoop_rate"
const STAT_BITE: String = "pickup_count"


## The planet's Surge numbers in one dictionary ({enabled: false} when it has none).
static func config(balance: Dictionary) -> Dictionary:
	var block: Dictionary = balance.get(BLOCK, {})
	if block.is_empty():
		return {"enabled": false}
	var charge: Dictionary = block.get("charge", {})
	var wave: Dictionary = block.get("wave", {})
	var stats: Dictionary[String, float] = {}
	var listed: Dictionary = block.get("stats", {})
	for id: Variant in listed:
		stats[str(id)] = float(listed[id])
	return {
		"enabled": true,
		"units": _floats(charge.get("units", [])),
		"per_bale": float(charge.get("per_bale", 0.0)),
		"per_plant": float(charge.get("per_plant", 0.0)),
		"per_water": float(charge.get("per_water", 0.0)),
		"min_fill_s": float(charge.get("min_fill_s", 0.0)),
		"duration_s": float(block.get("duration_s", 0.0)),
		"stats": stats,
		"power_per_district": float(block.get("power_per_district", 0.0)),
		"chest_pack": float(block.get("chest_pack", 1.0)),
		"wave_from": int(wave.get("from_district", 0)),
		"wave_rings": float(wave.get("rings", 0.0)),
		"wave_rings_per_district": float(wave.get("rings_per_district", 0.0)),
		"wave_water_s": float(wave.get("water_s", 0.0)),
		"wave_stages": float(wave.get("stages", 0.0)),
	}


static func enabled(cfg: Dictionary) -> bool:
	return bool(cfg.get("enabled", false)) and units_needed(cfg, 1) > 0.0 and float(cfg.get("duration_s", 0.0)) > 0.0


## Units of hand work that fill the core in district `n` (from 1).
static func units_needed(cfg: Dictionary, n: int) -> float:
	var list: Array = cfg.get("units", [])
	return float(list[clampi(n, 1, list.size()) - 1]) if not list.is_empty() else 0.0


## Share of a full charge that `units` of hand work are worth in district `n`.
static func gain_for_units(cfg: Dictionary, n: int, units: float) -> float:
	var need: float = units_needed(cfg, n)
	return maxf(units, 0.0) / need if need > 0.0 else 0.0


## How much stronger a Surge is in district `n` than in the first.
static func power(cfg: Dictionary, n: int) -> float:
	return 1.0 + float(cfg.get("power_per_district", 0.0)) * float(maxi(n, 1) - 1)


## What a Surge multiplies a stat of Lumi's by in district `n` (1.0 for a stat it leaves alone).
static func stat_mult(cfg: Dictionary, stat_id: String, n: int) -> float:
	var stats: Dictionary = cfg.get("stats", {})
	if not stats.has(stat_id):
		return 1.0
	return 1.0 + (float(stats[stat_id]) - 1.0) * power(cfg, n)


## Lumi's hand output during a Surge against the same hands without it.
static func output_mult(cfg: Dictionary, n: int) -> float:
	return stat_mult(cfg, STAT_RATE, n) * stat_mult(cfg, STAT_BITE, n)


## Share of its volume that waste swept during a Surge in district `n` takes in the chest.
static func chest_pack(cfg: Dictionary, n: int) -> float:
	return clampf(float(cfg.get("chest_pack", 1.0)) / maxf(output_mult(cfg, n), 1.0), 0.01, 1.0)


## Whether a Surge released in district `n` also pushes a wave of growth.
static func has_wave(cfg: Dictionary, n: int) -> bool:
	return int(cfg.get("wave_from", 0)) > 0 and n >= int(cfg.get("wave_from", 0))


## Rings of hexes round Lumi the wave reaches in district `n` (0 = no wave there).
static func wave_rings(cfg: Dictionary, n: int) -> int:
	if not has_wave(cfg, n):
		return 0
	return maxi(1, int(floor(float(cfg.get("wave_rings", 0.0)) + float(cfg.get("wave_rings_per_district", 0.0)) * float(n - int(cfg.get("wave_from", 0))))))


## A table entry as a list of numbers: a list as it is, a single number as a list of one.
static func _floats(value: Variant) -> Array[float]:
	var out: Array[float] = []
	if value is Array:
		for v: Variant in (value as Array):
			out.append(float(v))
	elif value is float or value is int:
		out.append(float(value))
	return out
