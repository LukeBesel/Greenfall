class_name CityPayouts
extends Node
## The city stage payout: cubes paid once when a district itself reaches a regrowth stage (design
## spec section 16.1). With robots earning nothing, this and Lumi's own loads and bales are the
## only cube income.
##
## Data: the planet's "districts" table, stage_reward {ref_cubes, cubes: [per stage 0..5]}. A
## district at stage s pays cubes[s] x its hex_cubes / ref_cubes, so a richer city pays more.
## A planet without the table or the key pays nothing.
##
## Each stage is paid once per district: the highest stage paid is kept in the planet's save
## (save_state / load_state). A save from before stage payouts existed starts from the stage each
## district already stands at: only stages reached from then on pay.
##
## Emits EventBus.district_stage_paid(district_id, stage, cubes).
##
## Use: var p := CityPayouts.new(); add_child(p); p.setup(def, districts); p.load_state(saved)

const KEY: String = "stage_reward"

var _districts: Districts
var _rule: Dictionary = {}
var _hex_cubes: Dictionary[String, float] = {}
var _paid: Dictionary[String, int] = {}


func _exit_tree() -> void:
	if EventBus.district_stage_changed.is_connected(_on_stage_changed):
		EventBus.district_stage_changed.disconnect(_on_stage_changed)


# --- Rules (static: tests and the simulator read the same numbers) ---------------------------

## Cubes a district worth `hex_cubes` a hex is paid on reaching `stage` ({ref_cubes, cubes}).
static func reward_for(rule: Dictionary, hex_cubes: float, stage: int) -> float:
	var cubes: Array = rule.get("cubes", [])
	var ref: float = float(rule.get("ref_cubes", 0.0))
	if stage < 0 or stage >= cubes.size() or ref <= 0.0:
		return 0.0
	return round(float(cubes[stage]) * hex_cubes / ref)


## The stage payout rule of a planet ({} when it has none).
static func rule_of(def: PlanetDefinition) -> Dictionary:
	if def == null or not def.has_table(Districts.TABLE):
		return {}
	return def.table(Districts.TABLE).get(KEY, {})


## district id -> what one of its hexes is worth, from the planet's districts table.
static func hex_cubes_of(def: PlanetDefinition) -> Dictionary[String, float]:
	var out: Dictionary[String, float] = {}
	if def == null or not def.has_table(Districts.TABLE):
		return out
	for raw: Variant in def.table(Districts.TABLE).get("districts", []):
		if raw is Dictionary and (raw as Dictionary).has("hex_cubes"):
			out[str((raw as Dictionary).get("id", ""))] = float((raw as Dictionary)["hex_cubes"])
	return out


# --- Setup and state --------------------------------------------------------------------------

func setup(def: PlanetDefinition, districts: Districts) -> void:
	_districts = districts
	_rule = rule_of(def)
	_hex_cubes = hex_cubes_of(def)
	_start_from_now()
	if not EventBus.district_stage_changed.is_connected(_on_stage_changed):
		EventBus.district_stage_changed.connect(_on_stage_changed)


func save_state() -> Dictionary:
	return {"paid": _paid.duplicate()}


## Restores save_state(). An empty dictionary (a save from before payouts) keeps every district at
## the stage it stands at now, so nothing is paid for the past.
func load_state(d: Dictionary) -> void:
	_start_from_now()
	var paid: Dictionary = d.get("paid", {})
	for id: String in _paid:
		if paid.has(id):
			_paid[id] = int(paid[id])


## The highest stage `district_id` has been paid for.
func paid_stage(district_id: String) -> int:
	return _paid.get(district_id, 0)


func _start_from_now() -> void:
	_paid.clear()
	if _districts == null:
		return
	for id: String in _districts.ids():
		_paid[id] = _districts.stage_of(id)


func _on_stage_changed(district_id: String, stage: int) -> void:
	if not _paid.has(district_id):
		return
	for s: int in range(_paid[district_id] + 1, stage + 1):
		_paid[district_id] = s
		var cubes: float = reward_for(_rule, _hex_cubes.get(district_id, 0.0), s)
		if cubes <= 0.0:
			continue
		var paid: float = Economy.pay_whole_cubes(cubes)
		GameState.inc_stat("city_stage_cubes", paid)
		EventBus.district_stage_paid.emit(district_id, s, paid)
