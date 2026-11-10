class_name Restoration
extends Node
## The two goals of the planet being played (design spec section 9), from its "restoration" table
## and its districts (systems/districts.gd). Nothing outside the planet enters either measure.
##
## - The launch point, the planet's ending. Launch progress (0..1) is the mean of the districts'
##   values: stage_values[stage] plus the step to the next value times the share toward the next
##   stage. When the launch rule is met (every district at the rule's stage), `launch_ready` fires
##   on EventBus, once per save.
## - The whole planet, the long goal: restored land hexes over all land hexes of the globe, with
##   named steps. `planet_restored` fires if it is ever complete. Never needed for the launch.
##
## A planet with no "restoration" table gets even stage values (stage / last stage), the rule
## "every district at the last stage", no cinematic and no named steps.
##
## Restoration.value() is launch progress of the world being played (0 when there is none): the
## number the bot's pacing marks and the objective measures read.
##
## Use: var r := Restoration.new(); add_child(r); r.setup(def, districts, cells); r.load_state(saved)

const TABLE: String = "restoration"
const WHEN_ALL_DISTRICTS_STAGE: String = "all_districts_stage"
## Seconds between whole-planet checks when the table does not say, and between launch-progress
## change checks (a readout cadence, not balance).
const FALLBACK_CHECK_S: float = 2.0
const VALUE_POLL_S: float = 0.5
const MEASURE_LAUNCH: String = "launch"
const MEASURE_CITY_STAGE: String = "city_stage"
const MEASURE_CITIES_RESTORED: String = "cities_restored"
const MEASURES: Array[String] = [MEASURE_LAUNCH, MEASURE_CITY_STAGE, MEASURE_CITIES_RESTORED]

static var _active: Restoration

var planet_id: String = ""
var districts: Districts

var _cells: SphereCells
var _stage_values: Array[float] = []
var _launch: Dictionary = {}
var _steps: Array[Dictionary] = []
var _check_s: float = FALLBACK_CHECK_S
var _launched: bool = false
var _ending_seen: bool = false
var _restored: bool = false
var _steps_done: Array[String] = []
var _last_value: float = -1.0
var _value_t: float = 0.0
var _planet_t: float = 0.0


func _exit_tree() -> void:
	if _active == self:
		_active = null
	if EventBus.district_stage_changed.is_connected(_on_district_stage):
		EventBus.district_stage_changed.disconnect(_on_district_stage)


func _process(delta: float) -> void:
	_value_t -= delta
	if _value_t <= 0.0:
		_value_t = VALUE_POLL_S
		var v: float = launch_value()
		if not is_equal_approx(v, _last_value):
			_last_value = v
			EventBus.planet_restoration_changed.emit(v)
		check_launch()
	_planet_t -= delta
	if _planet_t <= 0.0:
		_planet_t = _check_s
		check_planet()


# --- The rules (static, pure) -----------------------------------------------------------------

## Launch progress of the world being played, 0..1. 0 outside a world.
static func value() -> float:
	return _active.launch_value() if is_instance_valid(_active) else 0.0


## The live Restoration of the world being played, or null.
static func active() -> Restoration:
	return _active if is_instance_valid(_active) else null


## The value of each district stage toward the launch point, index 0..Districts.MAX_STAGE: the
## planet's `stage_values`, or even steps when it has none.
static func stage_values_for(def: PlanetDefinition) -> Array[float]:
	var out: Array[float] = []
	var raw: Array = def.table(TABLE).get("stage_values", []) if def else []
	for s: int in Districts.MAX_STAGE + 1:
		out.append(clampf(float(raw[s]), 0.0, 1.0) if s < raw.size() else float(s) / float(Districts.MAX_STAGE))
	return out


## One district's value: its stage's value plus `share` of the step to the next stage's value.
static func district_value(stage: int, share: float, stage_values: Array[float]) -> float:
	var last: int = stage_values.size() - 1
	if last < 0:
		return 0.0
	var s: int = clampi(stage, 0, last)
	if s >= last:
		return stage_values[last]
	return stage_values[s] + (stage_values[s + 1] - stage_values[s]) * clampf(share, 0.0, 1.0)


## The mean of the districts' values (0 with no districts).
static func mean_value(stages: PackedInt32Array, shares: PackedFloat32Array, stage_values: Array[float]) -> float:
	if stages.is_empty():
		return 0.0
	var total: float = 0.0
	for i: int in stages.size():
		total += district_value(stages[i], shares[i] if i < shares.size() else 0.0, stage_values)
	return total / float(stages.size())


## Whether a launch rule is met by these district stages. Never with no districts.
static func rule_met(rule: Dictionary, stages: PackedInt32Array) -> bool:
	if stages.is_empty():
		return false
	match str(rule.get("when", WHEN_ALL_DISTRICTS_STAGE)):
		WHEN_ALL_DISTRICTS_STAGE:
			var need: int = int(rule.get("stage", Districts.MAX_STAGE))
			for s: int in stages:
				if s < need:
					return false
			return true
	return false


## Whole-planet share: land hexes whose pollution is gone over all land hexes (water is not land).
## Two native passes over the state bytes, so it is cheap on the largest globe.
static func share_of_cells(cells: SphereCells) -> float:
	if cells == null:
		return 0.0
	var land: int = cells.n - cells.state.count(PlanetData.State.WATER)
	if land <= 0:
		return 0.0
	return float(land - cells.state.count(PlanetData.State.JUNK)) / float(land)


## The planet measures a goal or objective can ask for, of the world being played:
## "launch" = launch progress 0..1, "city_stage" = the regrowth stage of district `key` ("" = the
## one the readout shows), "cities_restored" = districts at the launch rule's stage.
## -1 for any other kind (the caller has its own measures).
static func measure(kind: String, key: String = "") -> float:
	if not kind in MEASURES:
		return -1.0
	var r: Restoration = active()
	if r == null or r.districts == null:
		return 0.0
	match kind:
		MEASURE_LAUNCH:
			return r.launch_value()
		MEASURE_CITY_STAGE:
			return float(r.districts.stage_of(key if key != "" else r.districts.focus_id()))
	return float(r.districts_restored())


# --- Setup and state --------------------------------------------------------------------------

func setup(def: PlanetDefinition, p_districts: Districts, cells: SphereCells) -> void:
	planet_id = String(def.id) if def else ""
	districts = p_districts
	_cells = cells
	var table: Dictionary = def.table(TABLE) if def else {}
	_stage_values = stage_values_for(def)
	_launch = table.get("launch", {})
	var planet: Dictionary = table.get("planet", {})
	_check_s = maxf(0.1, float(planet.get("check_s", FALLBACK_CHECK_S)))
	for raw: Variant in planet.get("steps", []):
		if raw is Dictionary and str((raw as Dictionary).get("id", "")) != "":
			_steps.append(raw)
	_active = self
	if not EventBus.district_stage_changed.is_connected(_on_district_stage):
		EventBus.district_stage_changed.connect(_on_district_stage)


func save_state() -> Dictionary:
	return {"launched": _launched, "ending_seen": _ending_seen, "restored": _restored, "steps": _steps_done.duplicate()}


## Restores a save_state() dictionary. Silent: a step the globe already passes and a launch rule
## already met are marked by the next check, which then emits as for any new progress.
func load_state(d: Dictionary) -> void:
	_launched = bool(d.get("launched", false))
	_ending_seen = bool(d.get("ending_seen", false))
	_restored = bool(d.get("restored", false))
	_steps_done.clear()
	for id: Variant in d.get("steps", []):
		_steps_done.append(str(id))


# --- Queries ----------------------------------------------------------------------------------

## Launch progress, 0..1: the mean of the districts' values.
func launch_value() -> float:
	if districts == null:
		return 0.0
	var stages := PackedInt32Array()
	var shares := PackedFloat32Array()
	for id: String in districts.ids():
		stages.append(districts.stage_of(id))
		shares.append(districts.share_of(id))
	return mean_value(stages, shares, _stage_values)


## The district stage the launch rule asks for.
func launch_stage() -> int:
	return int(_launch.get("stage", Districts.MAX_STAGE))


## Districts that have reached the launch rule's stage ("N of 6 cities restored").
func districts_restored() -> int:
	return districts.count_at_stage(launch_stage()) if districts else 0


## The id of the cinematic the launch plays before the end screen, or "".
func launch_sequence() -> String:
	return str(_launch.get("sequence", ""))


## Whether launch_ready has fired for this save.
func is_launched() -> bool:
	return _launched


## Whether the ending (the cinematic and the end screen) has been shown for this save.
func is_ending_seen() -> bool:
	return _ending_seen


func mark_ending_seen() -> void:
	_ending_seen = true


## Whole-planet share, 0..1.
func planet_share() -> float:
	return share_of_cells(_cells)


## The planet's named steps in order: [{id, name, share, done}].
func planet_steps() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for step: Dictionary in _steps:
		out.append({"id": str(step["id"]), "name": str(step.get("name", "")), "share": float(step.get("share", 1.0)),
			"done": str(step["id"]) in _steps_done})
	return out


func is_planet_restored() -> bool:
	return _restored


# --- Checks -----------------------------------------------------------------------------------

## Fires launch_ready the first time the launch rule is met. Returns whether it fired now.
func check_launch() -> bool:
	if _launched or districts == null:
		return false
	var stages := PackedInt32Array()
	for id: String in districts.ids():
		stages.append(districts.stage_of(id))
	if not rule_met(_launch, stages):
		return false
	_launched = true
	print("[restoration] launch_ready %s" % planet_id)
	EventBus.launch_ready.emit(planet_id)
	return true


## Marks the whole-planet steps the globe has reached, and the planet restored at share 1.
func check_planet() -> void:
	var share: float = planet_share()
	for step: Dictionary in _steps:
		var id: String = str(step["id"])
		if id in _steps_done or share < float(step.get("share", 1.0)) - 0.0000001:
			continue
		_steps_done.append(id)
		EventBus.planet_step_reached.emit(planet_id, id)
	if not _restored and share >= 1.0:
		_restored = true
		print("[restoration] planet_restored %s" % planet_id)
		EventBus.planet_restored.emit(planet_id)


func _on_district_stage(_district_id: String, _stage: int) -> void:
	check_launch()
