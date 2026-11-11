class_name PaceSimModel
extends RefCounted
## The economy of one planet as a state machine: no world, no nodes, no physics. It steps in
## one-second ticks and uses the game's own stat and cost code (Economy, Pace, Offline, Research)
## on a private copy of the progress state (see PaceSim, which swaps GameState in and out).
##
## This file holds the state, the purchases a policy can make and the progress rules. The work
## itself (Lumi's hand loop, the crew, the garden) is PaceSimWork; goals, objectives and research
## are PaceSimChains.

const TICK_S: float = 1.0
## This model plays one city: the first (crew cap and tier offers read it).
const CITIES_OPEN: int = 1

## Payouts that are Lumi's own loads: the side income (calibration side_income_share) rides on them.
const HAND_WINS: Array[String] = ["dump", "bale_sold", "haul"]

var data: PaceSimData
var policy: PaceSimPolicy
var work: PaceSimWork
var chains: PaceSimChains
var record: PaceSimLog

var t: float = 0.0
var cubes: float = 0.0
var parts: float = 0.0
var seeds: float = 0.0
var earned: float = 0.0
## Lifetime counters under the game's own stat names (goals and objectives read them).
var stats: Dictionary[String, float] = {}
var flags: Dictionary[String, bool] = {}
var hub_level: int = 1
var bench_tier: int = 1
var tower_tier: int = 0
var bin_level: int = 1
## Robot type id -> how many, and -> Mk tier (0 = Mk I).
var robots: Dictionary[String, int] = {}
var robot_tier: Dictionary[String, int] = {}
var first_robot_t: float = -1.0
## The most cubes ever in the purse (the "currency stays small" rule reads it).
var most_held: float = 0.0
var built: Dictionary[String, bool] = {}
var glim_tier: Dictionary[String, int] = {}
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## 0 = expected values everywhere; any other seed rolls salvage finds with that seed.
var seed_value: int = 0


func _init(p_policy: PaceSimPolicy, p_seed: int = 0) -> void:
	data = PaceSimData.new()
	policy = p_policy
	seed_value = p_seed
	rng.seed = p_seed
	record = PaceSimLog.new()
	work = PaceSimWork.new(self)
	chains = PaceSimChains.new(self)
	GameState.world["hub_level"] = hub_level
	GameState.world["stations"] = {}
	GameState.flags["research"] = {"done": chains.research_done}
	work.refresh_stats()


## Advances the model to `until_s` seconds of play.
func run(until_s: float) -> void:
	if not data.has_content():
		return
	while t < until_s:
		t += TICK_S
		work.step(TICK_S)
		chains.step(TICK_S)
		record.sample(self)


## Call when the run is over: drops the links back to this model so nothing is kept alive in a
## reference cycle. The state (work, chains, log) stays readable.
func seal() -> void:
	work.m = null
	chains.m = null
	policy = null


# --- Money ---------------------------------------------------------------------------------

## Cubes coming in. `win` names the small win it counts as ("" = none, e.g. a trickle).
func pay(amount: float, win: String = "") -> void:
	if amount <= 0.0:
		return
	if win in HAND_WINS:
		# Level rewards, salvage surges and weather, spread over the loads. They start small and grow
		# through the first minutes (a Lumi level pays 23 cubes at minute 1 and 89 at minute 10).
		amount *= 1.0 + data.k("side_income_share") * clampf(t / maxf(data.k("side_income_ramp_s"), 1.0), 0.0, 1.0)
	cubes += amount
	earned += amount
	most_held = maxf(most_held, cubes)
	if win != "":
		record.win(t, win)
		record.beat("first_payout", t)


func add_stat(key: String, amount: float = 1.0) -> void:
	stats[key] = stats.get(key, 0.0) + amount


func stat_of(key: String) -> float:
	return stats.get(key, 0.0)


## True when the purse covers a {cubes, parts, seeds} cost times `margin`.
func can_pay(cost: Dictionary, margin: float = 1.0) -> bool:
	return cubes >= float(cost.get("cubes", 0.0)) * margin and parts >= float(cost.get("parts", 0.0)) * margin \
		and seeds >= float(cost.get("seeds", 0.0)) * margin


func _spend(cost: Dictionary, kind: String, id: String) -> bool:
	if not can_pay(cost):
		return false
	cubes -= float(cost.get("cubes", 0.0))
	parts -= float(cost.get("parts", 0.0))
	seeds -= float(cost.get("seeds", 0.0))
	record.purchase(t, kind, id, float(cost.get("cubes", 0.0)))
	return true


# --- Upgrades ------------------------------------------------------------------------------

func level_of(id: String) -> int:
	return int(GameState.upgrades.get(id, 0))


func upgrade_open(id: String) -> bool:
	return Economy.upgrade_defs.has(id) and Economy.is_unlocked(id) and not Economy.is_maxed(id) and _tab_open(id)


func upgrade_cost(id: String) -> float:
	return Economy.upgrade_cost(id).to_float()


func buy_upgrade(id: String) -> bool:
	if not upgrade_open(id) or not _spend({Economy.upgrade_currency(id): upgrade_cost(id)}, "upgrade", id):
		return false
	GameState.upgrades[id] = level_of(id) + 1
	add_stat("upgrades_bought")
	record.beat("first_upgrade", t)
	if Economy.upgrade_max(id) == 1:
		record.mechanic(t, "upgrade:" + id)
	work.refresh_stats()
	return true


## Fleet upgrades sit on the Bots tab, which opens with a workbench tier.
func _tab_open(id: String) -> bool:
	var tab: String = str(Economy.upgrade_defs[id].get("tab", ""))
	return tab != "bots" or tab_open("bots")


## Whether a workbench tab is open: the first tier that lists it has been bought.
func tab_open(tab: String) -> bool:
	var tiers: Array = BenchTiers.tiers()
	for i: int in tiers.size():
		if tab in ((tiers[i] as Dictionary).get("tabs", []) as Array):
			return bench_tier >= i + 1
	return true


# --- The base: workbench tiers, tower, base level, yard builds, stations ----------------------

func next_bench() -> Dictionary:
	return BenchTiers.def(bench_tier + 1)


func bench_ready() -> bool:
	var nd: Dictionary = next_bench()
	if nd.is_empty():
		return false
	for c: Variant in nd.get("requires", []):
		if not chains.cond_ok(c as Array):
			return false
	return true


func buy_bench() -> bool:
	if not bench_ready() or not _spend(next_bench().get("cost", {}), "bench", str(bench_tier + 1)):
		return false
	bench_tier += 1
	record.mechanic(t, "bench_tier:%d" % bench_tier)
	for rid: Variant in BenchTiers.def(bench_tier).get("grants_research", []):
		chains.grant_research(str(rid))
	chains.check_story()
	return true


func next_tower_cost() -> Dictionary:
	return data.tower_tiers[tower_tier].get("cost", {}) if tower_tier < data.tower_tiers.size() else {}


func buy_tower(margin: float = 1.0) -> bool:
	if tower_tier >= data.tower_tiers.size() or not can_pay(next_tower_cost(), margin):
		return false
	_spend(next_tower_cost(), "tower", str(tower_tier + 1))
	tower_tier += 1
	return true


func next_hub() -> Dictionary:
	for d: Dictionary in data.hub_levels:
		if int(d.get("level", 0)) == hub_level + 1:
			return d
	return {}


## Whether the next base level's own conditions hold (the hub table's "requires", the same
## workbench conditions the game reads in Hub.block_reason).
func hub_ready() -> bool:
	for c: Variant in next_hub().get("requires", []):
		if not chains.cond_ok(c as Array):
			return false
	return not next_hub().is_empty()


func raise_hub() -> bool:
	var nd: Dictionary = next_hub()
	if nd.is_empty() or not hub_ready() or not _spend(nd.get("cost", {}), "base", str(hub_level + 1)):
		return false
	hub_level += 1
	GameState.world["hub_level"] = hub_level
	record.beat("base_%d" % hub_level, t)
	work.refresh_stats()
	return true


func hub_sell_bonus() -> float:
	for d: Dictionary in data.hub_levels:
		if int(d.get("level", 0)) == hub_level:
			return float((d.get("bonus", {}) as Dictionary).get("sell_mult", 0.0))
	return 0.0


## What a bale sells for at the scale relative to its value (Depot.sell_factor without a frontier).
func sell_factor() -> float:
	var bin: float = float(data.bin_levels[bin_level - 1].get("value_mult", 1.0)) if bin_level <= data.bin_levels.size() else 1.0
	return bin + hub_sell_bonus()


func yard_open(id: String) -> bool:
	if built.has(id) or not data.yard_builds.has(id):
		return false
	var d: Dictionary = data.yard_builds[id]
	var flag: String = str(d.get("requires_flag", ""))
	return hub_level >= int(d.get("requires_level", 1)) and (flag == "" or flags.get(flag, false))


func build_yard(id: String) -> bool:
	if not yard_open(id) or not _spend((data.yard_builds[id] as Dictionary).get("cost", {}), "build", id):
		return false
	built[id] = true
	var sets: Dictionary = data.section("build_sets_flag")
	if sets.has(id):
		flags[str(sets[id])] = true
	return true


func station_open(id: String) -> bool:
	if built.has(id) or not data.stations.has(id) or not data.stations[id] is Dictionary:
		return false
	var d: Dictionary = data.stations[id]
	return hub_level >= int(d.get("requires_level", 1)) and chains.has_research(id)


func build_station(id: String) -> bool:
	if not station_open(id) or not _spend((data.stations[id] as Dictionary).get("cost", {}), "station", id):
		return false
	built[id] = true
	(GameState.world["stations"] as Dictionary)["baler" if id == "auto_baler" else id] = true
	record.mechanic(t, "station:" + id)
	return true


## The buddy's tracks (planet-independent data): a cube sink the bot pays for early.
func glim_cost(track: String) -> Dictionary:
	for tr_def: Dictionary in data.glim_tracks:
		if str(tr_def.get("id", "")) != track:
			continue
		var req: Dictionary = tr_def.get("requires", {})
		for other: String in req:
			if int(glim_tier.get(other, 0)) < int(req[other]):
				return {}
		var tiers: Array = tr_def.get("tiers", [])
		var have: int = int(glim_tier.get(track, 0))
		return (tiers[have] as Dictionary).get("cost", {}) if have < tiers.size() else {}
	return {}


func buy_glim(track: String, margin: float = 1.0) -> bool:
	var cost: Dictionary = glim_cost(track)
	var repaired: String = str((data.section("build_sets_flag") as Dictionary).get(GlimDirector.BUILD_ID, ""))
	if repaired != "" and not flags.get(repaired, false):
		return false  # Glim's tracks open once he is repaired, as Glim.block_reason has it
	if cost.is_empty() or not can_pay(cost, margin):
		return false
	_spend(cost, "buddy", track)
	glim_tier[track] = int(glim_tier.get(track, 0)) + 1
	return true


# --- Robots --------------------------------------------------------------------------------

func count(type_id: String) -> int:
	return int(robots.get(type_id, 0))


func robot_total() -> int:
	var n: int = 0
	for id: String in robots:
		n += robots[id]
	return n


func role_of(type_id: String) -> String:
	return Fleet.crew_of_type(type_id)


func role_count(role: String) -> int:
	var n: int = 0
	for id: String in robots:
		if role_of(id) == role:
			n += robots[id]
	return n


## The most robots in all (core/crew_rules.gd). This model plays one city.
func crew_cap() -> int:
	return CrewRules.cap(Economy.robot_cfg, hub_level, CITIES_OPEN)


func robot_unlocked(type_id: String) -> bool:
	var need: String = str((Economy.robots.get(type_id, {}) as Dictionary).get("requires_research", ""))
	return need == "" or chains.has_research(need)


func robot_cost(type_id: String) -> Dictionary:
	var def: Dictionary = Economy.robots[type_id]
	var n: int = count(type_id)
	return {"cubes": CrewRules.build_cubes(Economy.robot_cfg, def, n),
		"parts": CrewRules.build_parts(Economy.robot_cfg, def, n, int(robot_tier.get(type_id, 0)))}


func robot_open(type_id: String) -> bool:
	return Economy.robots.has(type_id) and tab_open("bots") and robot_unlocked(type_id) and robot_total() < crew_cap()


func build_robot(type_id: String) -> bool:
	if not robot_open(type_id) or not _spend(robot_cost(type_id), "robot", type_id):
		return false
	robots[type_id] = count(type_id) + 1
	add_stat("robots_built")
	if first_robot_t < 0.0:
		first_robot_t = t
		record.beat("first_robot", t)
	if count(type_id) == 1:
		record.mechanic(t, "robot:" + type_id)
	work.refresh_stats()
	return true


func tier_cost(type_id: String) -> Dictionary:
	var tier: int = int(robot_tier.get(type_id, 0))
	if tier + 1 >= Economy.robot_tiers.size() or not CrewRules.tiers_open(Economy.robot_cfg, CITIES_OPEN):
		return {}
	var def: Dictionary = Economy.robots[type_id]
	return {"cubes": CrewRules.tier_cubes(Economy.robot_cfg, def, tier), "parts": CrewRules.tier_parts(Economy.robot_cfg, def, tier, count(type_id))}


func raise_tier(type_id: String) -> bool:
	var cost: Dictionary = tier_cost(type_id)
	if cost.is_empty() or count(type_id) == 0 or not _spend(cost, "tier", type_id):
		return false
	robot_tier[type_id] = int(robot_tier.get(type_id, 0)) + 1
	work.refresh_stats()
	return true
