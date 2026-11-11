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


## Parts paid for one salvaged robot part of this rarity: the planet's own scale (its "robots"
## table, salvage.rarity_parts, one value per rarity) or the shared list's (data/parts.json).
static func value(rarity: int) -> float:
	var own: Array = salvage_rules().get("rarity_parts", [])
	var r: int = clampi(rarity, 0, 4)
	if r < own.size():
		return float(own[r])
	return float(Economy.rarity(r).get("parts", 10))


## How salvage is scaled on this planet (its "robots" table, key "salvage"; {} when it has none).
static func salvage_rules() -> Dictionary:
	return Economy.robot_cfg.get("salvage", {})


## Buried parts per hex: the planet's own number, else the shared list's.
static func buried_per_hex() -> float:
	return float(salvage_rules().get("buried_per_hex", Economy.parts.get("chance_per_hex", 0.14)))


## A rarity index for `roll` (0..1) by the rarity weights.
static func roll_rarity(roll: float) -> int:
	var rar: Array = Economy.parts.get("rarities", [])
	var total: float = 0.0
	for r: Dictionary in rar:
		total += float(r.get("weight", 0.0))
	var x: float = roll * total
	for i: int in rar.size():
		x -= float(rar[i].get("weight", 0.0))
		if x <= 0.0:
			return i
	return 0


## Scales the chance that a take of `vol` units from a hex of `hex_total` units holds a part worth
## stripping. The table's part_drop is the chance for a take of salvage.ref_take units on a hex of
## salvage.ref_work units, so a hex yields the same parts however heavy it is and however big the
## scoop. 1.0 on a planet without those numbers (the chance is then per take).
static func strip_scale(vol: float, hex_total: float) -> float:
	var rules: Dictionary = salvage_rules()
	var ref_take: float = float(rules.get("ref_take", 0.0))
	var ref_work: float = float(rules.get("ref_work", 0.0))
	if ref_take <= 0.0 or ref_work <= 0.0 or hex_total <= 0.0:
		return 1.0
	return (vol / ref_take) * (ref_work / hex_total)


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
