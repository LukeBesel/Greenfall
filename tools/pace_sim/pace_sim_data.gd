class_name PaceSimData
extends RefCounted
## Everything the pacing model derives once from the current planet's tables, the shared game
## constants and tools/pace_sim/calibration.json. Nothing here names a planet: the caller switches
## `Planets` to the planet under test before building one of these.

const CALIBRATION_PATH: String = "res://tools/pace_sim/calibration.json"
const GLIM_PATH: String = "res://data/glim.json"
const SIZE_CLASSES: int = 3
## Growth stages of a plant (sprout to bloom); a stage takes the species' grow_s while watered.
const GROW_STAGES: int = 5

## Calibration constants replaced for what-if runs (--set=id=value,id=value). Empty in normal use.
static var overrides: Dictionary[String, float] = {}

## Tables that hold nothing the model can use (reported as "no content").
var missing: PackedStringArray = []
## Volume of junk in one untouched hex of the start district (HexWorth: the planet's districts
## table, else the default weight) and the share that must go before it counts as clean. The first
## hexes may be lighter: hex_work(n) is the n-th hex's own weight.
var hex_vol: float = HexWorth.DEFAULT_WORK
var clean_frac: float = 1.0 - SphereCells.CLEAN_LEFT
## What one cleaned hex of the start district pays when Lumi tips its waste loose.
var hex_cubes: float = 0.0
## The start district's lighter first hexes ({} when it has none) and its city stage payout rule.
var first_hexes: Dictionary = {}
var stage_rule: Dictionary = {}
var stage_share: float = Districts.FALLBACK_STAGE_SHARE
## Junk type id -> share of a hex's volume.
var mix: Dictionary[String, float] = {}
## Cubes per unit of volume for the average mix (before any multiplier).
var avg_value: float = 0.0
## Mean volume one scoop lock takes, and how many takes one hex needs.
var mean_bite: float = 0.0
var bites_per_hex: float = 0.0
## Expected Parts per take (salvage rolls) and per hex (buried finds).
var parts_per_bite: float = 0.0
var finds_per_bite: float = 0.0
var parts_per_hex_buried: float = 0.0
var finds_per_hex_buried: float = 0.0
## Share of a hex's volume by size class (small, medium, large).
var size_share: Array[float] = [1.0, 0.0, 0.0]
## Hexes around the start that only hold small pieces, and hexes in one hub's region.
var starter_hexes: int = 0
var region_hexes: int = 0
## Metres between the centres of neighbouring hexes.
var cell_spacing: float = 0.0
## Garden numbers derived from the "plants" and "regrowth" tables: seeds for a hex to count as
## Planted and to go on to Thriving, seconds from seed to bloom, seeds dropped per bloom.
var seeds_to_plant: float = 0.0
var seeds_to_thrive: float = 0.0
var bloom_s: float = 0.0
var seed_yield: float = 0.0
var objectives: Array[Dictionary] = []
var goals: Array[Dictionary] = []
var goals_visible: int = 3
var hub_levels: Array[Dictionary] = []
var tower_tiers: Array[Dictionary] = []
var bin_levels: Array[Dictionary] = []
var regrowth: Dictionary = {}
var yard_builds: Dictionary = {}
var stations: Dictionary = {}
var story_unlocks: Array[Dictionary] = []
var glim_tracks: Array[Dictionary] = []

var _cal: Dictionary = {}
var _strip_scaled: bool = false
var _district_rings: int = 0


func _init() -> void:
	_cal = Economy.read_json(CALIBRATION_PATH)
	_derive_junk()
	_derive_parts()
	_derive_space()
	_load_chains()


## A named calibration constant (tools/pace_sim/calibration.json "constants").
func k(id: String) -> float:
	if overrides.has(id):
		return overrides[id]
	var row: Variant = (_cal.get("constants", {}) as Dictionary).get(id)
	if row is Dictionary:
		return float((row as Dictionary).get("value", 0.0))
	push_error("pace_sim: calibration constant '%s' is missing" % id)
	return 0.0


## A calibration section that is not a single number (side events, the bot's research order).
func section(id: String) -> Variant:
	return _cal.get(id, {})


## True when the planet has junk to clean and stats to clean it with.
func has_content() -> bool:
	return not mix.is_empty() and not Economy.patch_base.is_empty()


## Distance in metres from the bin to the n-th hex cleaned (0 = the first): hexes go ring by ring.
func hex_distance(n: int) -> float:
	return k("yard_offset_m") + float(ring_of(n)) * cell_spacing


## Units of waste in the n-th hex cleaned (0 = the first): hexes go ring by ring from the base,
## whose own hex is the yard, so the first six are ring 1.
func hex_work(n: int) -> float:
	var ring: int = 1
	while 3 * ring * (ring + 1) <= n:
		ring += 1
	return HexWorth.work_at_ring(hex_vol, first_hexes, ring)


## Robot parts found per unit of waste scooped from a hex of `work` units: the table's chance per
## take, scaled as the game scales it (RobotParts.strip_scale).
func finds_per_unit(work: float) -> float:
	return finds_per_bite * RobotParts.strip_scale(1.0, work) if _strip_scaled else finds_per_bite / maxf(mean_bite, 0.001)


## Ring around the start that holds the n-th hex (the first hex is ring 0, the next six ring 1).
static func ring_of(n: int) -> int:
	var ring: int = 0
	while 1 + 3 * ring * (ring + 1) <= n:
		ring += 1
	return ring


## Cells within `rings` of a centre cell, the centre included.
static func cells_in_rings(rings: int) -> int:
	return 1 + 3 * rings * (rings + 1)


## Share of a hex's volume Lumi can lift at this Lift Strength.
func liftable_share(lift_class: int) -> float:
	var out: float = 0.0
	for i: int in mini(lift_class, SIZE_CLASSES - 1) + 1:
		out += size_share[i]
	return out


## Expected Parts paid by one salvaged or dug-up robot part (the rarity table's weighted mean).
static func mean_part_value() -> float:
	var total: float = 0.0
	var weight: float = 0.0
	var rarities: Array = Economy.parts.get("rarities", [])
	for i: int in rarities.size():
		var row: Dictionary = rarities[i]
		total += float(row.get("weight", 0.0)) * RobotParts.value(i)
		weight += float(row.get("weight", 0.0))
	return total / weight if weight > 0.0 else 0.0


func _derive_junk() -> void:
	if Economy.junk_ids.is_empty():
		missing.append("pollution")
		return
	_derive_district()
	var type_w: float = 0.0
	for id: String in Economy.junk_ids:
		type_w += float(Economy.junk_types[id].get("weight", 1.0))
	# Pass 1: the mean raw volume of a piece, which sets the scale that makes a hex hold hex_vol.
	var rows: Array[Array] = []  # [type id, chance of this model, raw volume]
	var mean_raw: float = 0.0
	for id: String in Economy.junk_ids:
		var t: Dictionary = Economy.junk_types[id]
		var models: Array = t.get("models", [])
		var model_w: float = 0.0
		for m: Variant in models:
			model_w += float((m as Dictionary).get("w", 1.0))
		for m: Variant in models:
			var md: Dictionary = m
			var chance: float = float(t.get("weight", 1.0)) / type_w * float(md.get("w", 1.0)) / maxf(model_w, 0.001)
			rows.append([id, chance, float(md.get("vol", 0.5))])
			mean_raw += chance * float(md.get("vol", 0.5))
	if mean_raw <= 0.0:
		missing.append("pollution")
		return
	var scale: float = hex_vol / (SphereField.DRAW_PIECES * mean_raw)
	# Pass 2: volume share by type and size class, and how many takes a piece needs.
	var bites_per_piece: float = 0.0
	var bites_by_type: Dictionary[String, float] = {}
	size_share = [0.0, 0.0, 0.0]
	for row: Array in rows:
		var id: String = row[0]
		var chance: float = row[1]
		var raw: float = row[2]
		var share: float = chance * raw / mean_raw
		mix[id] = mix.get(id, 0.0) + share
		size_share[Pace.size_class(raw)] += share
		var bites: float = _bites(raw * scale)
		bites_per_piece += chance * bites
		bites_by_type[id] = bites_by_type.get(id, 0.0) + chance * bites
	for id: String in mix:
		avg_value += mix[id] * float(Economy.junk_types[id].get("value", 1.0))
	# A scoop pulse lifts a set volume (Pace.pulse_volume) from as many pieces as it takes, so the
	# mean take is the bite itself; bites_per_hex is kept for the printed summary.
	mean_bite = float(Economy.scoop_rules.get("bite_vol", SphereField.FLAT_BITE_VOL))
	bites_per_hex = hex_vol * clean_frac / maxf(mean_bite, 0.001)
	var drops: Dictionary = Economy.robot_cfg.get("part_drop", {})
	_strip_scaled = not is_equal_approx(RobotParts.strip_scale(1.0, hex_vol), 1.0) or RobotParts.salvage_rules().has("ref_take")
	for id: String in mix:
		finds_per_bite += mix[id] * float(drops.get(id, 0.0))
	if hex_cubes <= 0.0:
		hex_cubes = hex_vol * avg_value


## The start district's hex weight, hex value, first hexes and stage payout (the planet's
## "districts" table; a planet without one keeps the defaults).
func _derive_district() -> void:
	var def: PlanetDefinition = Planets.current()
	if def == null or not def.has_table(Districts.TABLE):
		return
	var table: Dictionary = def.table(Districts.TABLE)
	stage_rule = table.get(CityPayouts.KEY, {})
	stage_share = float(table.get("stage_share", Districts.FALLBACK_STAGE_SHARE))
	for raw: Variant in table.get("districts", []):
		var d: Dictionary = raw
		if str((d.get("unlock", {}) as Dictionary).get("type", Districts.UNLOCK_START)) != Districts.UNLOCK_START:
			continue
		hex_vol = float(d.get("hex_work", hex_vol))
		hex_cubes = float(d.get("hex_cubes", 0.0))
		first_hexes = d.get("first_hexes", {})
		_district_rings = int(d.get("rings", 0))
		return


## Takes Lumi needs for a piece of this volume: the same rule as SphereField.bite().
static func _bites(vol: float) -> float:
	var n: float = 1.0
	var left: float = vol
	while left > SphereField.FLAT_BITE_VOL * 1.25:
		left -= SphereField.FLAT_BITE_VOL
		n += 1.0
	return n


func _derive_parts() -> void:
	var each: float = mean_part_value()
	parts_per_bite = finds_per_bite * each
	finds_per_hex_buried = RobotParts.buried_per_hex()
	parts_per_hex_buried = finds_per_hex_buried * each


func _derive_space() -> void:
	var def: PlanetDefinition = Planets.current()
	# Hexes of circumradius hex_size sit hex_size x sqrt(3) apart (the crew's ring step, SphereCrew.claim_dirty).
	var hex_size: float = float((Economy.planet.get("slice_field", {}) as Dictionary).get("hex_size", 10.0))
	cell_spacing = hex_size * sqrt(3.0)
	starter_hexes = cells_in_rings(int(floor(YardKeepOut.SMALL_ONLY_M / cell_spacing)))
	if def != null:
		region_hexes = cells_in_rings(_district_rings if _district_rings > 0 else SphereOffline.region_rings(def.cell_count(), def.hub_count))
	_derive_garden(1.5 * sqrt(3.0) * hex_size * hex_size)


## Plant slots in a hex (its area over the slot spacing squared), the species mix that needs no
## research, and what the regrowth levels ask of them.
func _derive_garden(hex_area: float) -> void:
	var plants: Dictionary = Economy.planet_table("plants")
	var spacing: float = float(plants.get("slot_spacing", 0.0))
	if spacing <= 0.0:
		return
	var slots: float = hex_area / (spacing * spacing)
	var planted: float = float(regrowth_table().get("planted_min_frac", 0.25))
	seeds_to_plant = ceilf(slots * planted)
	seeds_to_thrive = ceilf(slots * maxf(float(regrowth_table().get("thriving_life", 0.8)) - planted, 0.0))
	var weight: float = 0.0
	for row: Variant in plants.get("species", []):
		var sp: Dictionary = row
		if sp.has("requires_research") or sp.has("biomes"):
			continue
		var w: float = float(sp.get("weight", 1.0))
		weight += w
		bloom_s += w * float(sp.get("grow_s", 60.0)) * (GROW_STAGES - 1)
		seed_yield += w * float(sp.get("seed_yield", 0.0))
	if weight > 0.0:
		bloom_s /= weight
		seed_yield /= weight


func regrowth_table() -> Dictionary:
	return Economy.planet_table("regrowth")


func _load_chains() -> void:
	objectives = _rows("tutorial", "objectives")
	goals.assign(_rows("goals", "goals"))
	goals_visible = int(Economy.planet_table("goals").get("visible", 3))
	hub_levels = _rows("hub", "levels")
	tower_tiers = _rows("signal_tower", "tiers")
	bin_levels = _rows("trash_bin", "levels")
	story_unlocks = _rows("research", "story_unlocks")
	regrowth = Economy.planet_table("regrowth")
	yard_builds = Economy.planet_table("yard").get("builds", {})
	stations = Economy.planet_table("stations")
	if Economy.upgrade_order.is_empty():
		missing.append("upgrades")
	if Economy.patch_base.is_empty():
		missing.append("player")
	if (regrowth.get("levels", []) as Array).is_empty():
		missing.append("regrowth")
	for t: Variant in Economy.read_json(GLIM_PATH).get("tracks", []):
		glim_tracks.append(t as Dictionary)


func _rows(table: String, key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Variant in Economy.planet_table(table).get(key, []):
		if row is Dictionary:
			out.append(row as Dictionary)
	if out.is_empty() and not table in missing:
		missing.append(table)
	return out
