class_name RobotParts
extends RefCounted
## [ui2] Salvaged robot parts are Parts now. The detector, robot salvage, events, Lumi Level
## rewards and the Requests track still roll a part type and a rarity (for the toast and the
## "parts_found" stat), but what the player gets is Parts at the rarity's value
## (data/parts.json rarities[].parts: Rusty 10, Worn 25, Restored 60, Vintage 150, Legendary 450).
## Robot builds and Mk tiers cost Parts (+ cubes) instead of a recipe of items (robots/fleet.gd).
##
## GameState.parts (the old item list) is kept as an empty array for older code: fold_items()
## turns anything still appended to it into Parts (save v3 migration, and every fleet tick, so a
## caller from a parallel branch that still appends items loses nothing).


## Parts paid for one salvaged robot part of this rarity.
static func value(rarity: int) -> float:
	return float(Economy.rarity(clampi(rarity, 0, 4)).get("parts", 10))


## A salvaged robot part: pays Parts, counts as a find. Returns the Parts paid.
## `announce` emits EventBus.part_found (the stat, achievements, Requests and the Maker
## Fragment roll listen to it).
static func salvage(type_idx: int, rarity: int, announce: bool = true) -> float:
	var v: float = value(rarity)
	GameState.add_currency("parts", BigNum.from_float(v))
	if announce:
		EventBus.part_found.emit(type_idx, rarity)
	return v


## "+25 parts" line for a find's toast.
static func gain_text(rarity: int) -> String:
	return L10nFmt.amount("parts", value(rarity), true)


## Folds an item list ([{type, rarity}]) into its Parts value.
static func items_value(items: Array) -> float:
	var total: float = 0.0
	for p: Variant in items:
		if p is Dictionary:
			total += value(int((p as Dictionary).get("rarity", 0)))
	return total


## Anything left in GameState.parts becomes Parts. Returns the Parts added.
static func fold_items() -> float:
	if GameState.parts.is_empty():
		return 0.0
	var v: float = items_value(GameState.parts)
	GameState.parts.clear()
	if v > 0.0:
		GameState.add_currency("parts", BigNum.from_float(v))
	return v
