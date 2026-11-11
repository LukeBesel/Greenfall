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
## A carried part marked "built" is made first: Lumi orders it at the pickup spot, paying its
## price, and it is built on the Assembler's line (set_line), which builds no robot meanwhile. With
## no Assembler standing the workbench builds it, slower, so no player is stranded. When it is
## done it waits at the pickup spot.
## A planet without the table has no jobs and no hold on any city.
##
## This node is the rules and the state only. Where a step stands in the world, its marker and the
## interact prompt are systems/source_sites.gd; it tells this node when Lumi uses a spot (use) and
## whether she is still in reach of it (in_reach_fn). Robots cannot do either.
##
## Emits on EventBus: source_job_opened(district) the first time a job is offered,
## source_part_ordered(district, step) and source_part_built(district, step) for a built part,
## source_step_done(district, step) and, when the last step is done, source_shut_down(district)
## (the city's source finds, systems/finds.gd, and its landmark listen for it).
##
## State (the planet's save section): per city the step it is at, whether its part is being built
## (and how far) or stands ready, whether Lumi carries it, and whether the source is shut. A save from before source jobs: a city already at the
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
## Seconds a built part takes when the table gives none: on the line, and at the workbench.
const FALLBACK_LINE_S: float = 45.0
const FALLBACK_BENCH_S: float = 135.0
## How far a carry step is once its part is in hand or stands ready, as a share of the step.
const SHARE_BUILT: float = 0.5

## func(district: String) -> bool: whether Lumi stands in reach of the job's spot right now.
var in_reach_fn: Callable

var _districts: Districts
var _mastery: Mastery
var _specs: Dictionary[String, Dictionary] = {}
var _order: Array[String] = []
var _state: Dictionary[String, Dictionary] = {}
var _gates_stage: int = Districts.MAX_STAGE
var _reach_m: float = FALLBACK_REACH_M
var _hold_share: float = 0.0
var _engaged: String = ""
var _progress: float = 0.0
var _announce_t: float = 0.0
## The Assembler's line (null: this world has none, parts are built at the workbench).
var _line: CrewChain
## The table's "build" block: the card's lines while a part is built and when it is ready.
var _build_text: Dictionary = {}


func _exit_tree() -> void:
	_release_line()


func _physics_process(delta: float) -> void:
	_announce_t -= delta
	if _announce_t <= 0.0:
		_announce_t = ANNOUNCE_S
		_announce_open()
	_tick_builds(delta)
	if _engaged == "":
		return
	if in_reach_fn.is_valid() and bool(in_reach_fn.call(_engaged)):
		advance(_engaged, delta)
	else:
		_disengage()


# --- Rules (static: the game, the tests and the simulator read the same data) -----------------

## The planet's source jobs in table order, every field filled in: {district, id, name,
## open_stage, reward, toast, steps}. Each step: {id, type, at, from, prop, kind, seconds, cost,
## at_clean, built, line_s, bench_s, text, text_1, desc, prompt, final_prompt}. Entries with no
## district or no valid step are left out and reported.
static func specs_for(def: PlanetDefinition) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var table: Dictionary = def.table(TABLE) if def and def.has_table(TABLE) else {}
	var open_stage: int = int(table.get("open_stage", 0))
	var build: Dictionary = table.get("build", {}) if table.get("build") is Dictionary else {}
	for raw: Variant in table.get("sources", []):
		if not raw is Dictionary:
			continue
		var src: Dictionary = raw
		var list: Array[Dictionary] = []
		for s: Variant in src.get("steps", []):
			if s is Dictionary and str((s as Dictionary).get("type", "")) in TYPES:
				list.append(_step_spec(s, build))
		if str(src.get("district", "")) == "" or list.is_empty():
			push_error("Sources: entry '%s' has no district or no valid step" % str(src.get("id", "")))
			continue
		out.append({
			"district": str(src["district"]), "id": str(src.get("id", src["district"])), "name": str(src.get("name", "")),
			"open_stage": int(src.get("open_stage", open_stage)), "reward": src.get("reward", {}),
			"toast": str(src.get("toast", "")), "steps": list,
		})
	return out


static func _step_spec(s: Dictionary, build: Dictionary) -> Dictionary:
	return {
		"built": bool(s.get("built", false)) and str(s["type"]) == TYPE_CARRY,
		"line_s": maxf(0.1, float(s.get("line_s", build.get("line_s", FALLBACK_LINE_S)))),
		"bench_s": maxf(0.1, float(s.get("bench_s", build.get("bench_s", FALLBACK_BENCH_S)))),
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
	_hold_share = clampf(float(table.get("hold_share", 0.0)), 0.0, 1.0)
	_build_text = table.get("build", {}) if table.get("build") is Dictionary else {}
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
			st["ready"] = bool(d.get("ready", false)) and not st["shut"] and not st["carrying"]
			st["building"] = bool(d.get("building", false)) and not st["shut"] and not st["carrying"] and not st["ready"]
			st["build"] = clampf(float(d.get("build", 0.0)), 0.0, 1.0) if st["building"] else 0.0
			st["opened"] = bool(d.get("opened", false))
		elif saved.is_empty() and int(old_stages.get(id, 0)) >= _gates_stage:
			st["shut"] = true
			st["opened"] = true
		if st["shut"]:
			st["step"] = steps(id).size()
		else:  # a job that lost steps since the save still has its last one to do
			st["step"] = mini(int(st["step"]), steps(id).size() - 1)
		_state[id] = st
	_apply_caps()


static func _fresh_state() -> Dictionary:
	return {"step": 0, "carrying": false, "shut": false, "opened": false, "building": false, "build": 0.0, "ready": false}


func _apply_caps() -> void:
	if _districts == null:
		return
	for id: String in _order:
		_districts.set_hold_share(id, _hold_share, job_share(id))
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


## Whether the step's part is being built right now (ordered and paid, not done yet).
func is_building(district: String) -> bool:
	return _state.has(district) and bool(_state[district]["building"])


## Whether the step's built part stands ready at the pickup spot.
func is_ready(district: String) -> bool:
	return _state.has(district) and bool(_state[district]["ready"])


## How far the part being built is, 0..1 (0 when none is).
func build_share(district: String) -> float:
	return float(_state[district]["build"]) if is_building(district) else 0.0


## Whether the part being built is on the Assembler's line (false: the workbench builds it).
func on_line(district: String) -> bool:
	return is_building(district) and _line != null and _line.built


## Seconds the part being built still needs where it is being built now (0 when none is).
func build_left_s(district: String) -> float:
	if not is_building(district):
		return 0.0
	var st: Dictionary = current_step(district)
	return (1.0 - build_share(district)) * float(st["line_s"] if on_line(district) else st["bench_s"])


## Whether the job's current step is on offer: the city is unlocked, has reached the job's stage
## and is clean enough for this step. A part Lumi has paid for or carries is always hers to fit.
func is_open(district: String) -> bool:
	var st: Dictionary = current_step(district)
	if st.is_empty() or _districts == null or not _districts.is_unlocked(district):
		return false
	if _paid(district):
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
	return st.is_empty() or _paid(district) or (st["cost"] as Dictionary).is_empty() or GameState.can_afford_all(st["cost"])


## The current step's price is behind Lumi: its part is ordered, ready or in her hands.
func _paid(district: String) -> bool:
	return is_carrying(district) or is_building(district) or is_ready(district)


## Whether Lumi is at work on the job's current step right now (a "work" step, or fitting a part).
func is_engaged(district: String) -> bool:
	return _engaged == district and district != ""


## Seconds of work the current step needs in all, and the share of it done (0..1).
func work_share(district: String) -> float:
	var st: Dictionary = current_step(district)
	if st.is_empty() or float(st["seconds"]) <= 0.0:
		return 0.0
	return clampf(_progress / float(st["seconds"]), 0.0, 1.0) if _engaged == district else 0.0


## How far the whole job is, 0..1: steps done, a picked-up or finished part as half its step (one
## being built: its share of that half), and the share of the work under way.
func job_share(district: String) -> float:
	var n: int = steps(district).size()
	if n <= 0:
		return 0.0
	if is_shut(district):
		return 1.0
	var st: Dictionary = current_step(district)
	var within: float = work_share(district)
	if st["type"] == TYPE_CARRY:
		if is_carrying(district):
			within = SHARE_BUILT + (1.0 - SHARE_BUILT) * within
		else:
			within = SHARE_BUILT if is_ready(district) else SHARE_BUILT * build_share(district)
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
		n += step_index(id) * 4 + (3 if is_carrying(id) else (2 if is_ready(id) else (1 if is_building(id) else 0)))
	return n


## The card's lines for the job's current step, in English: {text, desc, cost, affordable}, where
## `cost` is what the step still asks Lumi to pay ({} when nothing). Empty when the job is not on
## offer.
func card(district: String) -> Dictionary:
	if not is_open(district):
		return {}
	var st: Dictionary = current_step(district)
	var text: String = str(st["text"])
	var desc: String = str(st["desc"])
	if is_carrying(district):
		text = str(st["text_1"])
	elif is_ready(district):
		text = str(_build_text.get("text_1", text))
	elif is_building(district):
		text = str(_build_text.get("text", text))
		desc = str(_build_text.get("desc" if on_line(district) else "hint", desc))
	return {"text": text, "desc": desc, "cost": {} if _paid(district) else st["cost"], "affordable": can_afford(district)}


## The prompt at the job's active spot, in English ("" when there is nothing to use: no open
## step, Lumi is already at work on it, or its part is still being built).
func prompt(district: String) -> String:
	var spot: String = active_spot(district)
	if spot == "" or is_engaged(district) or is_building(district):
		return ""
	var st: Dictionary = current_step(district)
	if is_ready(district):
		return str(_build_text.get("prompt", st["prompt"]))
	return str(st["prompt"]) if spot == SPOT_FROM or st["type"] != TYPE_CARRY else str(st["final_prompt"])


# --- Lumi's hands -------------------------------------------------------------------------------

## Lumi uses the job's active spot. A "use" step is done at once; a "work" step starts (advance
## carries it on while she stays in reach); a "carry" step first hands her the part, paying its
## price, then starts the fitting. A "built" part is ordered with the first use (paying its
## price) and picked up with the next, once it is done. Returns false when there is nothing to
## use, she cannot pay, or the part is still being built.
func use(district: String) -> bool:
	var spot: String = active_spot(district)
	if spot == "" or is_engaged(district) or is_building(district):
		return false
	var st: Dictionary = current_step(district)
	if spot == SPOT_FROM:
		var cost: Dictionary = st["cost"]
		if not is_ready(district) and not cost.is_empty() and not GameState.spend_all(cost):
			return false
		if bool(st["built"]) and not is_ready(district):
			_state[district]["building"] = true
			_state[district]["build"] = 0.0
			EventBus.source_part_ordered.emit(district, step_index(district))
		else:
			_state[district]["ready"] = false
			_state[district]["carrying"] = true
		_told(district)
		return true
	if float(st["seconds"]) <= 0.0:
		_finish_step(district)
		return true
	_engaged = district
	_progress = 0.0
	_told(district)
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


## Gives the jobs the Assembler's line (after setup; null = none): a built part takes the line
## while the Assembler stands, and the line builds no robot until the part is done.
func set_line(line: CrewChain) -> void:
	_release_line()
	_line = line


## The part being built for `district` gets `seconds` more of work: on the Assembler's line when
## it stands, else at the workbench, which is slower (the node calls this every physics tick).
func advance_build(district: String, seconds: float) -> void:
	if not is_building(district):
		return
	var st: Dictionary = current_step(district)
	if st.is_empty():
		_state[district]["building"] = false
		return
	var need: float = float(st["line_s"] if on_line(district) else st["bench_s"])
	_state[district]["build"] = minf(1.0, float(_state[district]["build"]) + maxf(seconds, 0.0) / need)
	if float(_state[district]["build"]) + 0.00001 < 1.0:
		return
	_state[district]["building"] = false
	_state[district]["build"] = 0.0
	_state[district]["ready"] = true
	EventBus.source_part_built.emit(district, step_index(district))
	_told(district)


## Carries every part being built on, and tells the line whether a part holds it. One part has
## the line at a time: the first city in table order that is building.
func _tick_builds(delta: float) -> void:
	var holder: String = ""
	for id: String in _order:
		if not is_building(id):
			continue
		advance_build(id, delta)
		if holder == "" and is_building(id):
			holder = str(current_step(id)["id"])
	if _line != null:
		_line.part = holder if _line.built else ""


func _release_line() -> void:
	if _line != null:
		_line.part = ""


## Shuts a source down without its steps (dev flags, tests): the gate lifts and the events fire;
## the reward is paid only when `pay` is set. False when it has no job or is shut already.
func force_shut(district: String, pay: bool = false) -> bool:
	if not has(district) or is_shut(district):
		return false
	_state[district]["step"] = steps(district).size()
	_shut_down(district, pay)
	return true


## A job moved on: the city's readout follows, and presentation refreshes.
func _told(district: String) -> void:
	if _districts:
		_districts.set_hold_share(district, _hold_share, job_share(district))
	changed.emit(district)


func _disengage() -> void:
	var was: String = _engaged
	_engaged = ""
	_progress = 0.0
	if was != "":
		_told(was)


func _finish_step(district: String) -> void:
	var i: int = step_index(district)
	_engaged = ""
	_progress = 0.0
	_state[district]["carrying"] = false
	_state[district]["building"] = false
	_state[district]["ready"] = false
	_state[district]["step"] = i + 1
	GameState.inc_stat("source_steps_done", 1)
	EventBus.source_step_done.emit(district, i)
	if i + 1 >= steps(district).size():
		_shut_down(district, true)
	_told(district)


func _shut_down(district: String, pay: bool) -> void:
	_state[district]["shut"] = true
	_state[district]["carrying"] = false
	_state[district]["building"] = false
	_state[district]["ready"] = false
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
