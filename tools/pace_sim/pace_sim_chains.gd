class_name PaceSimChains
extends RefCounted
## The chains that give the player something to aim for: the story objectives (one at a time), the
## goal chain (a few on screen), research (cubes plus real time, a short queue) and the unlocks
## that arrive by themselves. Conditions are read from the planet's tables.

const SEED_FLAG: String = "seed_signal"

var m: PaceSimModel
var data: PaceSimData
var research_done: Array[String] = []
var research_active: String = ""
var research_left: float = 0.0
var research_queue: Array[String] = []
var research_spent: float = 0.0
var notes_cubes: float = 0.0
var objective_index: int = 0
var goals_done: Dictionary[int, bool] = {}
## Goals and objectives the model cannot complete (a stat or flag it does not track).
var unmodelled: Dictionary[String, bool] = {}
## When the card first showed such a step (-1 = never): goal gaps after it mean nothing.
var unmodelled_since: float = -1.0

var _objective_since: float = 0.0


func _init(model: PaceSimModel) -> void:
	m = model
	data = model.data


func step(dt: float) -> void:
	_side_events()
	_research(dt)
	_story_unlocks()
	_objectives()


# --- Conditions ----------------------------------------------------------------------------

## One workbench-style condition: ["stat", key, n], ["hub_level", n], ["tower", n], ...
func cond_ok(c: Array) -> bool:
	match str(c[0]):
		"always", "builds":
			return true
		"bench_tier":
			return m.bench_tier >= int(c[1])
		"tower":
			return m.tower_tier >= int(c[1])
		"earned":
			return m.earned >= float(c[1])
		"stat":
			return m.stat_of(str(c[1])) >= float(c[2])
		"hub_level":
			return m.hub_level >= int(c[1])
		"flag":
			return m.flags.get(str(c[1]), false)
		"since_first_robot":
			return m.first_robot_t >= 0.0 and m.t - m.first_robot_t >= float(c[1])
		"owned":
			return m.count(str(c[1])) >= int(c[2])
	return false


## Progress value of a goal or objective row, or -1 when the model does not track it.
func value_of(row: Dictionary) -> float:
	var key: String = str(row.get("key", ""))
	match str(row.get("type", "stat")):
		"stat":
			var v: float = m.stat_of(key)
			for also: Variant in row.get("also", []):
				v += m.stat_of(str(also))
			return v if m.stats.has(key) or _tracked(key) else -1.0
		"earned":
			return m.earned
		"upgrade":
			return float(m.level_of(key))
		"robot":
			return float(m.robot_total() if key == "any" else m.count(key))
		"tier":
			var best: int = 0
			for id: String in m.robot_tier:
				if key == "any" or key == id:
					best = maxi(best, m.robot_tier[id])
			return float(best)
		"zone":
			# The bot paints zones as soon as a cleaner exists, up to what the goal asks.
			return float(row.get("target", 1)) if m.role_count("clean") > 0 else 0.0
		"hub_level":
			return float(m.hub_level)
		"hex_level":
			return float(m.work.garden_count(int(row.get("key", 1))))
		"flag":
			return (1.0 if m.flags.get(key, false) else 0.0) if m.flags.has(key) or _tracked(key) else -1.0
		"research":
			return 1.0 if has_research(key) else 0.0
		"tower":
			return float(m.tower_tier)
		"bench":
			return float(m.bench_tier)
	return -1.0


## Stats and flags the model raises itself (so a zero is a real zero, not "unknown").
func _tracked(key: String) -> bool:
	return key in ["junk_scooped", "junk_dumps", "upgrades_bought", "cubes_made", "cubes_cashed", "hexes_cleaned", "perfect_cubes",
		"parts_found", "research_done", "robot_bales", "robots_built", "plants_planted", "plants_bloomed", "bales_recycled",
		"garden_stipend", "hexes_restored", "seeds_unlocked", SEED_FLAG] or (data.section("side_events") as Dictionary).has(key) \
		or (data.section("build_sets_flag") as Dictionary).values().has(key)


## Things the model does not simulate but the bot does on the side (reading a shard, petting the
## cat): each stat ticks at the times measured from a bot run (calibration.json "side_events").
func _side_events() -> void:
	var side: Dictionary = data.section("side_events")
	for key: String in side:
		var row: Dictionary = side[key]
		var first: float = float(row.get("first_s", 0.0))
		var every: float = float(row.get("every_s", 0.0))
		if m.t < first:
			continue
		m.stats[key] = 1.0 + (floor((m.t - first) / every) if every > 0.0 else 0.0)


## The step the card shows now: {kind, id} ("" when every objective and goal is done).
func card_step() -> Dictionary:
	var row: Dictionary = current_objective()
	if not row.is_empty():
		return {"kind": "objective", "id": str(row.get("id", ""))}
	var open: Array[int] = current_goals()
	return {"kind": "goal", "id": str(data.goals[open[0]].get("id", ""))} if not open.is_empty() else {"kind": "", "id": ""}


# --- Objectives and goals ------------------------------------------------------------------

func current_objective() -> Dictionary:
	return data.objectives[objective_index] if objective_index < data.objectives.size() else {}


## The card shows one step at a time: the story objectives in order, then the goal chain. When a
## step is done, every goal whose condition already holds is completed with it (Goals.absorb).
func _objectives() -> void:
	var guard: int = 0
	while guard < 40:
		guard += 1
		var row: Dictionary = current_objective()
		var goal_index: int = -1
		if row.is_empty():
			var open: Array[int] = current_goals()
			if open.is_empty():
				return
			goal_index = open[0]
			row = data.goals[goal_index]
		_open_the_way(row)
		var v: float = value_of(row)
		if v < 0.0:
			unmodelled[("objective:" if goal_index < 0 else "goal:") + str(row.get("id", ""))] = true
			if unmodelled_since < 0.0:
				unmodelled_since = m.t
			return
		if v < float(row.get("target", 1)):
			return
		if goal_index < 0:
			m.log.objective(m.t, str(row.get("id", "")))
			objective_index += 1
		_objective_since = m.t
		_absorb()


## What the game does when a step comes up: the seed signal's hint timer, and the yard build
## that sets the flag the step waits for becomes buyable.
func _open_the_way(row: Dictionary) -> void:
	var wait: String = str(row.get("wait_flag", ""))
	if wait == SEED_FLAG and not m.flags.get(wait, false) and m.t - _objective_since >= FirstSeed.HINT_AFTER_S:
		m.flags[wait] = true
	if str(row.get("type", "")) != "flag":
		return
	var sets: Dictionary = data.section("build_sets_flag")
	for build: String in sets:
		if str(sets[build]) == str(row.get("key", "")) and data.yard_builds.has(build):
			var need: String = str((data.yard_builds[build] as Dictionary).get("requires_flag", ""))
			if need != "":
				m.flags[need] = true


## Indexes of the goals on screen: the first few not done yet, in order.
func current_goals() -> Array[int]:
	var out: Array[int] = []
	for i: int in data.goals.size():
		if out.size() >= data.goals_visible:
			break
		if not goals_done.has(i):
			out.append(i)
	return out


func _absorb() -> void:
	for i: int in data.goals.size():
		if goals_done.has(i):
			continue
		var row: Dictionary = data.goals[i]
		if value_of(row) < float(row.get("target", 1)):
			continue
		goals_done[i] = true
		var reward: Dictionary = row.get("reward", {})
		m.parts += float(reward.get("parts", 0.0))
		m.seeds += float(reward.get("seeds", 0.0))
		m.log.goal(m.t, str(row.get("id", "")))
		m.pay(float(reward.get("cubes", 0.0)), "goal")


# --- Research ------------------------------------------------------------------------------

func has_research(id: String) -> bool:
	return id in research_done


func research_busy(id: String) -> bool:
	return research_active == id or id in research_queue


## A node the player could start now: not a story unlock, prerequisites done, base level reached.
func research_available(id: String) -> bool:
	if not Research.exists(id) or Research.is_story(id) or has_research(id) or research_busy(id):
		return false
	var def: Dictionary = Research.def(id)
	if m.hub_level < int(def.get("min_base_level", 0)) or str(def.get("requires_tech", "")) != "":
		return false
	for r: String in Research.requires(id):
		if not has_research(r):
			return false
	return true


func research_cost(id: String) -> float:
	return Research.cost(id).to_float()


func research_room() -> bool:
	return research_active == "" or research_queue.size() < Research.max_queue()


func start_research(id: String) -> bool:
	if not m.tab_open("research") or not research_available(id) or not research_room() or m.cubes < research_cost(id):
		return false
	m.cubes -= research_cost(id)
	research_spent += research_cost(id)
	m.log.purchase(m.t, "research", id, research_cost(id))
	if research_active == "":
		research_active = id
		research_left = Research.duration(id)
	else:
		research_queue.append(id)
	return true


## Research that arrives without being started (a workbench tier's gift, a story unlock).
func grant_research(id: String) -> void:
	if has_research(id) or not Research.exists(id):
		return
	research_done.append(id)
	m.flags[id] = true
	m.work.refresh_stats()


func _research(dt: float) -> void:
	if research_active == "":
		return
	research_left -= dt
	if research_left > 0.0:
		return
	var id: String = research_active
	research_active = ""
	grant_research(id)
	m.add_stat("research_done")
	m.log.win(m.t, "research")
	m.log.beat("first_research", m.t)
	if not research_queue.is_empty():
		research_active = research_queue.pop_front()
		research_left = Research.duration(research_active)


func _story_unlocks() -> void:
	for row: Dictionary in data.story_unlocks:
		var id: String = str(row.get("id", ""))
		if has_research(id) or not _all_researched(row.get("requires", [])):
			continue
		var when: Array = row.get("when", [])
		var all_ok: bool = not when.is_empty()
		for c: Variant in when:
			all_ok = all_ok and cond_ok(c as Array)
		var any_ok: bool = false
		for c: Variant in row.get("any", []):
			any_ok = any_ok or cond_ok(c as Array)
		if all_ok or any_ok:
			grant_research(id)
			m.log.mechanic(m.t, "story:" + id)


func _all_researched(ids: Array) -> bool:
	for id: Variant in ids:
		if not has_research(str(id)):
			return false
	return true
