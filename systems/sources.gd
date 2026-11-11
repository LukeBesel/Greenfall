class_name Sources
extends Node
## The source job of each city (design spec section 4): the thing that still pollutes it, stopped
## by a short job of a few steps that only Lumi can do. Until the job is done the city is held one
## stage short of the table's `gates_stage` (Districts.set_stage_cap), so the last regrowth stage
## and with it the launch point wait for Lumi's own hands.
##
## Everything a job is comes from the planet's "sources" table: its steps, where they stand, what
## they cost and what the job pays. Three step types cover every job: "use" (walk there, use it),
## "work" (use it, then stay in reach for some seconds; faster with mastery of the step's kind)
## and "carry" (pick a part up, pay for it if it has a price, carry it to its place and fit it).
## A planet without the table has no jobs and no hold on any city.
##
## This node is the rules and the state only. Where a step stands in the world, its marker and the
## interact prompt are systems/source_sites.gd; it tells this node when Lumi uses a spot (use) and
## whether she is still in reach of it (in_reach_fn). Robots cannot do either.
##
## Emits on EventBus: source_job_opened(district) the first time a job is offered,
## source_step_done(district, step) and, when the last step is done, source_shut_down(district)
## (the city's source finds, systems/finds.gd, and its landmark listen for it).
##
## State (the planet's save section): per city the step it is at, whether Lumi carries the step's
## part, and whether the source is shut. A save from before source jobs: a city already at the
## gated stage counts as shut down (nothing is paid for it); every other city gets its job.
##
## Use: var s := Sources.new(); add_child(s); s.setup(def, districts, mastery);
## s.load_state(saved, saved_districts); then districts.load_state(...).

## A step, a part pickup or the engaged work changed: presentation refreshes.
signal changed(district: String)

const TABLE: String = "sources"
const TYPE_USE: String = "use"
const TYPE_WORK: String = "work"
const TYPE_CARRY: String = "carry"
const TYPES: Array[String] = [TYPE_USE, TYPE_WORK, TYPE_CARRY]
## The two spots a step may have: where it is done, and where a carried part is picked up.
const SPOT_AT: String = "at"
const SPOT_FROM: String = "from"
const FALLBACK_REACH_M: float = 2.8
## Seconds between looks for a job that has come on offer (a notice cadence, not balance).
const ANNOUNCE_S: float = 0.5

## func(district: String) -> bool: whether Lumi stands in reach of the job's spot right now.
var in_reach_fn: Callable

var _districts: Districts
var _mastery: Mastery
var _specs: Dictionary[String, Dictionary] = {}
var _order: Array[String] = []
var _state: Dictionary[String, Dictionary] = {}
var _gates_stage: int = Districts.MAX_STAGE
var _reach_m: float = FALLBACK_REACH_M
var _engaged: String = ""
var _progress: float = 0.0
var _announce_t: float = 0.0


func _physics_process(delta: float) -> void:
	_announce_t -= delta
	if _announce_t <= 0.0:
		_announce_t = ANNOUNCE_S
		_announce_open()
	if _engaged == "":
		return
	if in_reach_fn.is_valid() and bool(in_reach_fn.call(_engaged)):
		advance(_engaged, delta)
	else:
		_disengage()


# --- Rules (static: the game, the tests and the simulator read the same data) -----------------

## The planet's source jobs in table order, every field filled in: {district, id, name,
## open_stage, reward, toast, steps}. Each step: {id, type, at, from, prop, kind, seconds, cost,
## at_clean, text, text_1, desc, prompt, final_prompt}. Entries with no district or no valid
## step are left out and reported.
static func specs_for(def: PlanetDefinition) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var table: Dictionary = def.table(TABLE) if def and def.has_table(TABLE) else {}
	var open_stage: int = int(table.get("open_stage", 0))
	for raw: Variant in table.get("sources", []):
		if not raw is Dictionary:
			continue
		var src: Dictionary = raw
		var steps: Array[Dictionary] = []
		for s: Variant in src.get("steps", []):
			if s is Dictionary and str((s as Dictionary).get("type", "")) in TYPES:
				steps.append(_step_spec(s))
		if str(src.get("district", "")) == "" or steps.is_empty():
			push_error("Sources: entry '%s' has no district or no valid step" % str(src.get("id", "")))
			continue
		out.append({
			"district": str(src["district"]), "id": str(src.get("id", src["district"])), "name": str(src.get("name", "")),
			"open_stage": int(src.get("open_stage", open_stage)), "reward": src.get("reward", {}),
			"toast": str(src.get("toast", "")), "steps": steps,
		})
	return out


static func _step_spec(s: Dictionary) -> Dictionary:
	return {
		"id": str(s.get("id", "")), "type": str(s["type"]), "at": _v2(s.get("at", [])), "from": _v2(s.get("from", [])),
		"prop": str(s.get("prop", "")), "kind": str(s.get("kind", "")), "seconds": maxf(0.0, float(s.get("seconds", 0.0))),
		"cost": s.get("cost", {}), "at_clean": clampf(float(s.get("at_clean", 0.0)), 0.0, 1.0),
		"text": str(s.get("text", "")), "text_1": str(s.get("text_1", s.get("text", ""))), "desc": str(s.get("desc", "")),
		"prompt": str(s.get("prompt", "")), "final_prompt": str(s.get("final_prompt", s.get("prompt", ""))),
	}


static func _v2(raw: Variant) -> Vector2:
	var a: Array = raw if raw is Array else []
	return Vector2(float(a[0]), float(a[1])) if a.size() >= 2 else Vector2.ZERO


## The stage a city cannot reach until its source is shut down.
static func gates_stage_for(def: PlanetDefinition) -> int:
	var table: Dictionary = def.table(TABLE) if def and def.has_table(TABLE) else {}
	return clampi(int(table.get("gates_stage", Districts.MAX_STAGE)), 1, Districts.MAX_STAGE)


## What every price of a job adds up to, by currency (the rocket's Parts).
static func total_cost(spec: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for st: Dictionary in spec.get("steps", []):
		var cost: Dictionary = st["cost"]
		for k: Variant in cost:
			out[str(k)] = float(out.get(str(k), 0.0)) + float(cost[k])
	return out


# --- Setup and state --------------------------------------------------------------------------

## Reads the planet's jobs and holds every city that has one below the gated stage. Call before
## Districts.load_state, so a loaded city is held too. Jobs of cities the globe does not have are
## left out.
func setup(def: PlanetDefinition, districts: Districts, mastery: Mastery = null) -> void:
	_districts = districts
	_mastery = mastery
	_gates_stage = gates_stage_for(def)
	var table: Dictionary = def.table(TABLE) if def and def.has_table(TABLE) else {}
	_reach_m = float(table.get("reach_m", FALLBACK_REACH_M))
	for spec: Dictionary in specs_for(def):
		var id: String = str(spec["district"])
		if districts == null or not districts.has(id) or _specs.has(id):
			continue
		_specs[id] = spec
		_order.append(id)
		_state[id] = _fresh_state()
	_apply_caps()


func save_state() -> Dictionary:
	var out: Dictionary = {}
	for id: String in _order:
		out[id] = (_state[id] as Dictionary).duplicate()
	return out


## Restores save_state(). `saved_districts` is the districts' own saved section: with no saved
## jobs at all (a save from before them) a city that had already reached the gated stage counts
## as shut down, silently and unpaid. Silent: no events.
func load_state(saved: Dictionary, saved_districts: Dictionary = {}) -> void:
	var old_stages: Dictionary = saved_districts.get("stages", {}) if saved_districts.get("stages") is Dictionary else {}
	_disengage()
	for id: String in _order:
		var st: Dictionary = _fresh_state()
		var raw: Variant = saved.get(id)
		if raw is Dictionary:
			var d: Dictionary = raw
			st["shut"] = bool(d.get("shut", false))
			st["step"] = clampi(int(d.get("step", 0)), 0, steps(id).size())
			st["carrying"] = bool(d.get("carrying", false)) and not st["shut"]
			st["opened"] = bool(d.get("opened", false))
		elif saved.is_empty() and int(old_stages.get(id, 0)) >= _gates_stage:
			st["shut"] = true
			st["opened"] = true
		if st["shut"]:
			st["step"] = steps(id).size()
		_state[id] = st
	_apply_caps()


static func _fresh_state() -> Dictionary:
	return {"step": 0, "carrying": false, "shut": false, "opened": false}


func _apply_caps() -> void:
	if _districts == null:
		return
	for id: String in _order:
		_districts.set_stage_cap(id, Districts.MAX_STAGE if is_shut(id) else _gates_stage - 1)


# --- Queries ----------------------------------------------------------------------------------

## The cities that have a source job, in table order.
func ids() -> Array[String]:
	return _order


func has(district: String) -> bool:
	return _specs.has(district)


## The job's data ({} for a city without one): see specs_for.
func spec_of(district: String) -> Dictionary:
	return _specs.get(district, {})


func steps(district: String) -> Array:
	return spec_of(district).get("steps", [])


## The step the job is at (its count of steps once it is shut down).
func step_index(district: String) -> int:
	return int(_state[district]["step"]) if _state.has(district) else 0


## The step to do now ({} when the city has no job or it is shut down).
func current_step(district: String) -> Dictionary:
	var list: Array = steps(district)
	var i: int = step_index(district)
	return list[i] if i < list.size() and not is_shut(district) else {}


## True once the job is done. A city without a job has nothing to shut down: false.
func is_shut(district: String) -> bool:
	return _state.has(district) and bool(_state[district]["shut"])


func is_carrying(district: String) -> bool:
	return _state.has(district) and bool(_state[district]["carrying"])


## The stage the planet's jobs gate, and how close Lumi must stand to a step's spot.
func gates_stage() -> int:
	return _gates_stage


func reach_m() -> float:
	return _reach_m


## Whether the job's current step is on offer: the city is unlocked, has reached the job's stage
## and is clean enough for this step. A part already in Lumi's hands is always hers to fit.
func is_open(district: String) -> bool:
	var st: Dictionary = current_step(district)
	if st.is_empty() or _districts == null or not _districts.is_unlocked(district):
		return false
	if is_carrying(district):
		return true
	return _districts.stage_of(district) >= int(spec_of(district)["open_stage"]) \
		and _districts.clean_share_of(district) + 0.0001 >= float(st["at_clean"])


## The spot Lumi must go to now: SPOT_FROM while a carried part is still to be picked up, else
## SPOT_AT ("" when the job is not on offer).
func active_spot(district: String) -> String:
	if not is_open(district):
		return ""
	var st: Dictionary = current_step(district)
	return SPOT_FROM if st["type"] == TYPE_CARRY and not is_carrying(district) else SPOT_AT


## Whether Lumi can pay for the current step (true when it has no price or it is already paid).
func can_afford(district: String) -> bool:
	var st: Dictionary = current_step(district)
	return st.is_empty() or is_carrying(district) or (st["cost"] as Dictionary).is_empty() or GameState.can_afford_all(st["cost"])


## Whether Lumi is at work on the job's current step right now (a "work" step, or fitting a part).
func is_engaged(district: String) -> bool:
	return _engaged == district and district != ""


## Seconds of work the current step needs in all, and the share of it done (0..1).
func work_share(district: String) -> float:
	var st: Dictionary = current_step(district)
	if st.is_empty() or float(st["seconds"]) <= 0.0:
		return 0.0
	return clampf(_progress / float(st["seconds"]), 0.0, 1.0) if _engaged == district else 0.0


## How far the whole job is, 0..1: steps done, a picked-up part as half its step, and the share
## of the work under way.
func job_share(district: String) -> float:
	var n: int = steps(district).size()
	if n <= 0:
		return 0.0
	if is_shut(district):
		return 1.0
	var st: Dictionary = current_step(district)
	var within: float = work_share(district)
	if st["type"] == TYPE_CARRY:
		within = (0.5 + 0.5 * within) if is_carrying(district) else 0.0
	return (float(step_index(district)) + within) / float(n)


## How many jobs are done, and how many steps over all jobs (a counter that only rises).
func shut_count() -> int:
	var n: int = 0
	for id: String in _order:
		n += 1 if is_shut(id) else 0
	return n


func steps_done() -> int:
	var n: int = 0
	for id: String in _order:
		n += step_index(id) * 2 + (1 if is_carrying(id) else 0)
	return n


## The card's lines for the job's current step, in English: {text, desc, cost, affordable}, where
## `cost` is what the step still asks Lumi to pay ({} when nothing). Empty when the job is not on
## offer.
func card(district: String) -> Dictionary:
	if not is_open(district):
		return {}
	var st: Dictionary = current_step(district)
	var carrying: bool = is_carrying(district)
	return {"text": str(st["text_1"]) if carrying else str(st["text"]), "desc": str(st["desc"]),
		"cost": {} if carrying else st["cost"], "affordable": can_afford(district)}


## The prompt at the job's active spot, in English ("" when there is nothing to use: no open
## step, or Lumi is already at work on it).
func prompt(district: String) -> String:
	var spot: String = active_spot(district)
	if spot == "" or is_engaged(district):
		return ""
	var st: Dictionary = current_step(district)
	return str(st["prompt"]) if spot == SPOT_FROM or st["type"] != TYPE_CARRY else str(st["final_prompt"])


# --- Lumi's hands -------------------------------------------------------------------------------

## Lumi uses the job's active spot. A "use" step is done at once; a "work" step starts (advance
## carries it on while she stays in reach); a "carry" step first hands her the part, paying its
## price, then starts the fitting. Returns false when there is nothing to use or she cannot pay.
func use(district: String) -> bool:
	var spot: String = active_spot(district)
	if spot == "" or is_engaged(district):
		return false
	var st: Dictionary = current_step(district)
	if spot == SPOT_FROM:
		var cost: Dictionary = st["cost"]
		if not cost.is_empty() and not GameState.spend_all(cost):
			return false
		_state[district]["carrying"] = true
		changed.emit(district)
		return true
	if float(st["seconds"]) <= 0.0:
		_finish_step(district)
		return true
	_engaged = district
	_progress = 0.0
	changed.emit(district)
	return true


## Lumi works `seconds` longer on the step she is engaged in (the node calls this every physics
## tick while she stays in reach). Work on a step with a pollution kind runs at her hand bonus
## for that kind.
func advance(district: String, seconds: float) -> void:
	if _engaged != district or district == "":
		return
	var st: Dictionary = current_step(district)
	if st.is_empty():
		_disengage()
		return
	_progress += seconds * work_speed(st)
	if _progress + 0.0001 >= float(st["seconds"]):
		_finish_step(district)


## How fast Lumi works a step: her hand bonus for the step's pollution kind (1 = no bonus).
func work_speed(step: Dictionary) -> float:
	var kind: String = str(step.get("kind", ""))
	return maxf(1.0, _mastery.hand_bonus(kind)) if _mastery != null and kind != "" else 1.0


## Shuts a source down without its steps (dev flags, tests): the gate lifts and the events fire;
## the reward is paid only when `pay` is set. False when it has no job or is shut already.
func force_shut(district: String, pay: bool = false) -> bool:
	if not has(district) or is_shut(district):
		return false
	_state[district]["step"] = steps(district).size()
	_shut_down(district, pay)
	return true


func _disengage() -> void:
	var was: String = _engaged
	_engaged = ""
	_progress = 0.0
	if was != "":
		changed.emit(was)


func _finish_step(district: String) -> void:
	var i: int = step_index(district)
	_engaged = ""
	_progress = 0.0
	_state[district]["carrying"] = false
	_state[district]["step"] = i + 1
	GameState.inc_stat("source_steps_done", 1)
	EventBus.source_step_done.emit(district, i)
	if i + 1 >= steps(district).size():
		_shut_down(district, true)
	changed.emit(district)


func _shut_down(district: String, pay: bool) -> void:
	_state[district]["shut"] = true
	_state[district]["carrying"] = false
	_state[district]["opened"] = true
	if pay:
		_pay(spec_of(district)["reward"])
	GameState.inc_stat("sources_shut", 1)
	if DevHooks.has("autoplay"):  # pacing log
		print("[sources] %s shut down at %.1f min" % [district, float(GameState.stats.get("time_played", 0.0)) / 60.0])
	EventBus.source_shut_down.emit(district)
	var toast: String = str(spec_of(district)["toast"])
	if toast != "":
		EventBus.toast.emit(tr(toast), "reward")
	if _districts:
		_districts.set_stage_cap(district, Districts.MAX_STAGE)
	changed.emit(district)


func _pay(reward: Dictionary) -> void:
	for k: Variant in reward:
		var amount: float = float(reward[k])
		if amount <= 0.0:
			continue
		if str(k) == "cubes":
			Economy.pay_whole_cubes(amount)
		else:
			GameState.add_currency(str(k), BigNum.from_float(amount))


## Tells the player once, per job, that it is on offer.
func _announce_open() -> void:
	for id: String in _order:
		if bool(_state[id]["opened"]) or not is_open(id):
			continue
		_state[id]["opened"] = true
		EventBus.source_job_opened.emit(id)
		changed.emit(id)
