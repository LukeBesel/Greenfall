class_name PaceSimRdData
extends RefCounted
## The redesign model's numbers: a PROPOSAL folder of JSON tables (tools/pace_sim/proposals/<name>)
## plus the few tables the redesign keeps unchanged, which are read from the planet through
## `Planets`. Nothing here names a planet: the proposal's balance table says which planet it is for.

const PROPOSALS_DIR: String = "res://tools/pace_sim/proposals"
const TABLES: PackedStringArray = ["balance", "districts", "pollution", "upgrades", "rigs", "research", "regrowth",
	"restoration", "robots", "goals", "finds"]
## Marker in a kind's yield: take the value from the planet's current pollution table.
const KEPT_POLLUTION: String = "kept:pollution"

var ok: bool = true
var error: String = ""
var tables: Dictionary[String, Dictionary] = {}
var districts: Array[Dictionary] = []
var kinds: Dictionary[String, Dictionary] = {}
var tracks: Dictionary[String, Dictionary] = {}
var unlocks: Dictionary[String, Dictionary] = {}
var nodes: Dictionary[String, Dictionary] = {}
var robot_types: Dictionary[String, Dictionary] = {}
var modules: Dictionary[String, Dictionary] = {}
var beats: Array[Dictionary] = []
## Average cubes per unit of litter and the perfect-press multiplier, from the planet's own tables.
var kept_litter_value: float = 0.0
var kept_bale_mult: float = 1.0

var _num_cache: Dictionary[String, float] = {}


## Loads proposal `name` and applies `overrides` (dotted path -> number, e.g.
## "upgrades.tier_ratio.0" or "districts.districts.2.hex_work"). The planet named by the proposal
## must already be the current planet.
func _init(proposal: String, overrides: Dictionary = {}) -> void:
	for table: String in TABLES:
		var path: String = "%s/%s/%s.json" % [PROPOSALS_DIR, proposal, table]
		if not FileAccess.file_exists(path):
			ok = false
			error = "proposal table missing: %s" % path
			return
		tables[table] = Economy.read_json(path)
	for path: String in overrides:
		if not _set_path(path, float(overrides[path])):
			ok = false
			error = "override path not found: %s" % path
			return
	_read_kept()
	_index()


## The planet this proposal is written for.
static func planet_of(proposal: String) -> StringName:
	var path: String = "%s/%s/balance.json" % [PROPOSALS_DIR, proposal]
	if not FileAccess.file_exists(path):
		return &""
	return StringName(str(Economy.read_json(path).get("planet_id", "")))


## A number by dotted path ("balance.hand.capacity").
func num(path: String) -> float:
	if _num_cache.has(path):
		return _num_cache[path]
	var at: Variant = tables
	for key: String in path.split("."):
		if at is Dictionary and (at as Dictionary).has(key):
			at = (at as Dictionary)[key]
		elif at is Array and key.is_valid_int() and int(key) < (at as Array).size():
			at = (at as Array)[int(key)]
		else:
			push_error("pace_sim redesign: no value at '%s'" % path)
			return 0.0
	_num_cache[path] = float(at)
	return float(at)


## Hexes in a district of `rings` rings.
static func hexes_in(rings: int) -> int:
	return 1 + 3 * rings * (rings + 1)


## Cubes for level `level` (0 = the first) of a track, or -1 when the planet has no such level.
func track_cost(id: String, level: int) -> float:
	var row: Dictionary = tracks[id]
	var up: Dictionary = tables["upgrades"]
	var tier_levels: Array = up["tier_levels"]
	var tier: int = int(row.get("first_tier", 0))
	var pos: int = level
	while tier < tier_levels.size() and pos >= int(tier_levels[tier]):
		pos -= int(tier_levels[tier])
		tier += 1
	if tier >= tier_levels.size():
		return -1.0
	var first: float = float(row["first_cost"]) if tier == 0 else float(row.get("weight", 1.0)) * float((up["tier_cost"] as Array)[tier])
	return first * pow(float((up["tier_ratio"] as Array)[tier]), float(pos))


## The district tier that holds `level` of a track (the district that must be open to buy it).
func track_tier(id: String, level: int) -> int:
	var tier_levels: Array = tables["upgrades"]["tier_levels"]
	var tier: int = int(tracks[id].get("first_tier", 0))
	var pos: int = level
	while tier < tier_levels.size() and pos >= int(tier_levels[tier]):
		pos -= int(tier_levels[tier])
		tier += 1
	return tier


## Units of a kind Lumi must clear by hand in total to hold mastery `level`.
func mastery_units(kind: String, level: int) -> float:
	return float(kinds[kind]["mastery_level1_units"]) * pow(num("balance.mastery.growth"), float(level - 1))


## Index of a district by id, or -1.
func district_index(id: String) -> int:
	for i: int in districts.size():
		if str(districts[i]["id"]) == id:
			return i
	return -1


func _read_kept() -> void:
	var junk := PaceSimData.new()
	kept_litter_value = junk.avg_value
	kept_bale_mult = float((Economy.planet_table("player").get("cube", {}) as Dictionary).get("perfect_mult", 1.0))
	if kept_litter_value <= 0.0:
		ok = false
		error = "the planet's pollution table has no junk values to keep"


func _index() -> void:
	for row: Variant in tables["districts"].get("districts", []):
		districts.append(row as Dictionary)
	_index_into(kinds, tables["pollution"].get("kinds", {}))
	_index_into(tracks, tables["upgrades"].get("tracks", {}))
	_index_into(unlocks, tables["upgrades"].get("unlocks", {}))
	_index_into(nodes, tables["research"].get("nodes", {}))
	_index_into(robot_types, tables["robots"].get("types", {}))
	_index_into(modules, tables["rigs"].get("modules", {}))
	for row: Variant in tables["goals"].get("beats", []):
		beats.append(row as Dictionary)
	for id: String in kinds:
		var y: Dictionary = kinds[id]["yield"]
		if str(y.get("cubes", "")) == KEPT_POLLUTION:
			y["cubes"] = kept_litter_value


static func _index_into(out: Dictionary[String, Dictionary], from: Variant) -> void:
	var rows: Dictionary = from
	for id: String in rows:
		out[id] = rows[id]


func _set_path(path: String, value: float) -> bool:
	var keys: PackedStringArray = path.split(".")
	var at: Variant = tables
	for i: int in keys.size():
		var key: String = keys[i]
		var last: bool = i == keys.size() - 1
		if at is Dictionary and (at as Dictionary).has(key):
			if last:
				(at as Dictionary)[key] = value
			else:
				at = (at as Dictionary)[key]
		elif at is Array and key.is_valid_int() and int(key) < (at as Array).size():
			if last:
				(at as Array)[int(key)] = value
			else:
				at = (at as Array)[int(key)]
		else:
			return false
	return true
