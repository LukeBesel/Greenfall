class_name PaceSimPolicyGreedy
extends PaceSimPolicy
## The buying order of the full-game bot (tools/autoplay.gd, _shopping_list and _shop), so the
## simulator and the bot can be compared: the story card's purchase first, then research, the
## slow-start unlocks, robots, the base level, stations, and last the cheapest useful upgrade
## while keeping a reserve for the next big thing. Robots are chosen by role, not by name.

const RICH_FACTOR: float = 3.0
const LEAK_SHARE: float = 0.15
const TOWER_MARGIN: float = 1.5
const BUDDY_MARGIN: float = 1.5


func wants_trip(m: PaceSimModel) -> bool:
	var plan: Dictionary = _plan(m)
	if plan["trip"]:
		return true
	if _research_pick(m) != "" or _unlock_upgrade(m) != "":
		return true
	if m.bench_ready() and m.can_pay(m.next_bench().get("cost", {})):
		return true
	var up: String = _best_upgrade(m, float(plan["reserve"]), float(plan["hub_save"]) <= 0.0)
	return up != "" and (_goal_upgrade(m) != "" or m.upgrade_cost(up) * RICH_FACTOR < m.cubes)


func shop(m: PaceSimModel) -> void:
	var plan: Dictionary = _plan(m)
	if m.tower_tier < mini(m.data.tower_tiers.size(), maxi(1, m.hub_level)):
		m.buy_tower(TOWER_MARGIN)
	m.buy_bench()
	var obj: Dictionary = m.chains.current_objective()
	if str(obj.get("type", "")) == "upgrade":
		m.buy_upgrade(str(obj.get("key", "")))
	for i: int in 4:
		var rid: String = _research_pick(m)
		if rid == "" or not m.chains.start_research(rid):
			break
	var goal_up: String = _goal_upgrade(m)
	if goal_up != "":
		m.buy_upgrade(goal_up)
	var unlock: String = _unlock_upgrade(m)
	if unlock != "":
		m.buy_upgrade(unlock)
	for id: String in (m.data.section("build_sets_flag") as Dictionary):
		m.build_yard(id)
	for track: Variant in _mirror(m, "buddy_tracks"):
		m.buy_glim(str(track), BUDDY_MARGIN)
	_shop_robots(m, plan)
	if not (str(obj.get("type", "")) == "bench" and m.bench_ready()):
		m.raise_hub()
	for id: String in m.data.stations:
		if m.station_open(id) and _mats_spare(m, (m.data.stations[id] as Dictionary).get("cost", {}), id == "recycler"):
			m.build_station(id)
	_shop_upgrades(m, plan)


func _shop_robots(m: PaceSimModel, plan: Dictionary) -> void:
	var robot: String = plan["robot"]
	var hub_save: float = plan["hub_save"]
	if robot != "":
		var cost: Dictionary = m.robot_cost(robot)
		var must: bool = _robot_goal(m, robot) or _essential(m, robot)
		var ok: bool = hub_save <= 0.0 or m.cubes - float(cost["cubes"]) >= hub_save or must
		if ok and (must or hub_save <= 0.0 or _mats_spare(m, cost, false)):
			m.build_robot(robot)
	for id: String in Economy.robot_order:
		var cost: Dictionary = m.tier_cost(id)
		if m.count(id) > 0 and not cost.is_empty() and m.can_pay(cost) and _mats_spare(m, cost, false) \
				and m.cubes - float(cost["cubes"]) >= hub_save * 0.5:
			m.raise_tier(id)


func _shop_upgrades(m: PaceSimModel, plan: Dictionary) -> void:
	var robot: String = plan["robot"]
	var reserve: float = plan["reserve"]
	var hub_save: float = plan["hub_save"]
	if robot == "" or m.can_pay(m.robot_cost(robot)):
		reserve = hub_save
	var helper: String = _helper_research(m)
	if helper != "":
		reserve = maxf(reserve, m.chains.research_cost(helper))
	if m.upgrade_open(Pace.UP_BALER):
		reserve = maxf(reserve, m.upgrade_cost(Pace.UP_BALER))
	if m.bench_ready():
		reserve = maxf(reserve, float((m.next_bench().get("cost", {}) as Dictionary).get("cubes", 0.0)))
	for i: int in 20:
		var up: String = _best_upgrade(m, reserve, hub_save <= 0.0)
		if up == "" or not m.buy_upgrade(up):
			break


## What to save for: the next robot and, once its Parts are in, the next base level.
func _plan(m: PaceSimModel) -> Dictionary:
	var out: Dictionary = {"trip": false, "reserve": 0.0, "hub_save": 0.0, "robot": _next_robot(m)}
	if out["robot"] != "":
		var cost: Dictionary = m.robot_cost(str(out["robot"]))
		out["reserve"] = float(cost["cubes"])
		out["trip"] = m.can_pay(cost)
	var hub: Dictionary = m.next_hub().get("cost", {})
	if not m.next_hub().is_empty() and m.parts >= float(hub.get("parts", 0.0)):
		out["hub_save"] = float(hub.get("cubes", 0.0))
		out["reserve"] = maxf(float(out["reserve"]), float(out["hub_save"]))
		out["trip"] = out["trip"] or m.can_pay(hub)
	return out


func _type_for(role: String) -> String:
	for id: String in Economy.robot_order:
		if str((Economy.robots[id] as Dictionary).get("role", "")) == role:
			return id
	return ""


## The robot to work toward next, in the bot's order: waterers for the garden, the first cleaner,
## a hauler per two cleaners, a planter, more cleaners, then general helpers.
func _next_robot(m: PaceSimModel) -> String:
	var garden: bool = m.work.garden_open()
	var cleaners: int = m.role_count("clean")
	var haulers: int = m.role_count("haul")
	var order: Array[String] = _goal_robots(m)
	if garden and m.role_count("water") < maxi(1, m.work.garden_count(2)):
		order.append(_type_for("water"))
	if cleaners == 0:
		order.append(_type_for("clean"))
	if haulers * 2 < cleaners:
		order.append(_type_for("haul"))
	if garden and m.role_count("plant") == 0 and m.seeds > 8.0:
		order.append(_type_for("plant"))
	order.append(_type_for("clean"))
	if garden:
		order.append(_type_for("water"))
	order.append(_type_for("any"))
	if haulers < cleaners:
		order.append(_type_for("haul"))
	var hub: Dictionary = m.next_hub()
	var saving: bool = not hub.is_empty() and m.parts >= float((hub.get("cost", {}) as Dictionary).get("parts", 0.0))
	for id: String in order:
		if id == "" or not m.robot_open(id):
			continue
		if saving and not _essential(m, id) and not _robot_goal(m, id):
			continue
		return id
	return ""


## Robot types a goal on screen asks for and the fleet is still short of.
func _goal_robots(m: PaceSimModel) -> Array[String]:
	var out: Array[String] = []
	for i: int in m.chains.current_goals():
		var g: Dictionary = m.data.goals[i]
		var id: String = str(g.get("key", ""))
		if str(g.get("type", "")) == "robot" and Economy.robots.has(id) and m.count(id) < int(g.get("target", 1)):
			out.append(id)
	return out


## Robots a person buys even while saving for the base: the first of a kind, a small cleaning
## crew, enough waterers for the garden, a hauler per two cleaners.
func _essential(m: PaceSimModel, id: String) -> bool:
	if m.count(id) == 0:
		return true
	match m.role_of(id):
		"water":
			return m.role_count("water") < m.work.garden_count(2)
		"clean":
			return m.count(id) < 3
		"haul":
			return m.role_count("haul") * 2 < m.role_count("clean")
	return false


func _robot_goal(m: PaceSimModel, id: String) -> bool:
	var obj: Dictionary = m.chains.current_objective()
	if str(obj.get("type", "")) == "robot" and str(obj.get("key", "")) in [id, "any"]:
		return true
	for i: int in m.chains.current_goals():
		var g: Dictionary = m.data.goals[i]
		if str(g.get("type", "")) == "robot" and str(g.get("key", "")) == id:
			return true
	return false


## True if paying `cost` leaves the Parts the next base level needs (or `force`).
func _mats_spare(m: PaceSimModel, cost: Dictionary, force: bool) -> bool:
	var need: float = float((m.next_hub().get("cost", {}) as Dictionary).get("parts", 0.0))
	return force or m.parts - float(cost.get("parts", 0.0)) >= need


func _goal_upgrade(m: PaceSimModel) -> String:
	for i: int in m.chains.current_goals():
		var g: Dictionary = m.data.goals[i]
		var key: String = str(g.get("key", ""))
		match str(g.get("type", "")):
			"upgrade":
				if m.upgrade_open(key) and m.cubes >= m.upgrade_cost(key):
					return key
			"stat":
				if key == "upgrades_bought":
					var up: String = _best_upgrade(m, 0.0, true)
					if up != "":
						return up
	return ""


## The slow-start unlocks before anything else: the Baler (save for it), then Lift Strength.
func _unlock_upgrade(m: PaceSimModel) -> String:
	for id: String in [Pace.UP_BALER, Pace.UP_LIFT]:
		if not m.upgrade_open(id):
			continue
		if m.cubes >= m.upgrade_cost(id):
			return id
		if id == Pace.UP_BALER:
			return ""
	return ""


func _useful(m: PaceSimModel, id: String) -> bool:
	var def: Dictionary = Economy.upgrade_defs[id]
	if def.has("robot"):
		return m.count(str(def["robot"])) > 0
	# A taller bale stack is wasted once haulers carry the bales.
	return str(def.get("stat", "")) != "carry_stack" or m.role_count("haul") == 0


## Cheapest useful upgrade affordable while keeping `reserve` (or, with leak, a small share of the purse).
func _best_upgrade(m: PaceSimModel, reserve: float, leak: bool) -> String:
	var best: String = ""
	var best_cost: float = INF
	for id: String in Economy.upgrade_order:
		if not m.upgrade_open(id) or not _useful(m, id):
			continue
		var c: float = m.upgrade_cost(id)
		if c < best_cost:
			best_cost = c
			best = id
	if best == "" or best_cost > m.cubes:
		return ""
	return best if m.cubes - best_cost >= reserve or (leak and best_cost <= m.cubes * LEAK_SHARE) else ""


# --- Research ------------------------------------------------------------------------------

## A list the bot hardcodes, kept in calibration.json "bot_mirror" so this script names no content.
func _mirror(m: PaceSimModel, key: String) -> Array:
	return (m.data.section("bot_mirror") as Dictionary).get(key, [])


## The helper and automation research the bot saves for, then the garden chain at a base level
## (ids a planet does not have are skipped).
func _helper_research(m: PaceSimModel) -> String:
	var lists: Array = [_mirror(m, "research_first")]
	if m.hub_level >= int((m.data.section("bot_mirror") as Dictionary).get("garden_chain_base_level", 3)):
		lists.append(_mirror(m, "research_garden_chain"))
	for list: Array in lists:
		for raw: Variant in list:
			var id: String = str(raw)
			if not Research.exists(id) or m.chains.has_research(id) or m.chains.research_busy(id):
				continue
			return id if m.chains.research_available(id) else ""
	return ""


func _research_ok(m: PaceSimModel, id: String) -> bool:
	var c: float = m.chains.research_cost(id)
	if (id in _mirror(m, "research_first") or id in _mirror(m, "research_garden_chain")) and m.cubes >= c:
		return true
	var hub_cubes: float = float((m.next_hub().get("cost", {}) as Dictionary).get("cubes", 0.0))
	var reserve: float = hub_cubes * 0.5 + 1000.0 if m.hub_level >= 2 else hub_cubes * 1.5 + 2000.0
	return c <= m.chains.notes_cubes - m.chains.research_spent or m.cubes > maxf(c * 4.0, reserve)


func _goal_research(m: PaceSimModel) -> String:
	for i: int in m.chains.current_goals():
		var g: Dictionary = m.data.goals[i]
		var want: String = ""
		match str(g.get("type", "")):
			"robot":
				if Economy.robots.has(str(g.get("key", ""))) and not m.robot_unlocked(str(g["key"])):
					want = str((Economy.robots[str(g["key"])] as Dictionary).get("requires_research", ""))
			"research":
				want = str(g.get("key", ""))
		var guard: int = 0
		while want != "" and Research.exists(want) and not m.chains.has_research(want) and guard < 8:
			guard += 1
			if m.chains.research_busy(want):
				break
			if m.chains.research_available(want):
				if m.cubes >= m.chains.research_cost(want):
					return want
				break
			var next: String = ""
			for r: String in Research.requires(want):
				if not m.chains.has_research(r):
					next = r
					break
			want = next
	return ""


func _research_pick(m: PaceSimModel) -> String:
	if not m.tab_open("research") or not m.chains.research_room():
		return ""
	var goal: String = _goal_research(m)
	if goal != "":
		return goal
	var helper: String = _helper_research(m)
	if helper != "":
		return helper if _research_ok(m, helper) and m.cubes >= m.chains.research_cost(helper) else ""
	for raw: Variant in _mirror(m, "research_priority"):
		if _can_start(m, str(raw)):
			return str(raw)
	var best: String = ""
	var best_cost: float = INF
	for id: String in Research.ids():
		if _can_start(m, id) and m.chains.research_cost(id) < best_cost:
			best_cost = m.chains.research_cost(id)
			best = id
	return best


func _can_start(m: PaceSimModel, id: String) -> bool:
	return m.chains.research_available(id) and m.cubes >= m.chains.research_cost(id) and _research_ok(m, id)
