class_name PaceSimRdModel
extends RefCounted
## The redesign model (--model=redesign): Planet 1 as the design spec describes it, played in
## one-second ticks at the level of rates and events. State, purchases and progression live here;
## the work of each tick is in PaceSimRdWork, the rates in PaceSimRdRates. Every number comes from
## a proposal folder (PaceSimRdData), never from game data for the new mechanics.

const TICK_S: float = 1.0
## The list of things on offer is rebuilt at least this often (counters open new offers).
const ITEMS_REFRESH_S: float = 5.0

var data: PaceSimRdData
var policy: PaceSimRdPolicy
var record := PaceSimRdLog.new()
var rates: PaceSimRdRates
var work: PaceSimRdWork

var t: float = 0.0
var cubes: float = 0.0
var parts: float = 0.0
var earned: float = 0.0
var parts_earned: float = 0.0
var seeds: float = 0.0
## Seeds gained (the kit and blooming plants), spent on planting and spent on cleansing plants
## (blight), and seconds blight work stood still for want of seeds.
var seeds_earned: float = 0.0
var seeds_planted: float = 0.0
var seeds_cleansing: float = 0.0
var seed_short_s: float = 0.0
## Parts the Scroungers carried in, and robots the Assemblers built.
var scrounged: float = 0.0
## Parts spent on new robots and on robot type upgrades.
var parts_on_robots: float = 0.0
var parts_on_repairs: float = 0.0
var assembled: int = 0
## Ids owned: unlocks, finished research nodes, grants, rig modules.
var owned: Dictionary[String, bool] = {}
var levels: Dictionary[String, int] = {}
var robots: Dictionary[String, int] = {}
## Robot type -> how many of them are repaired (the second tier).
var repaired: Dictionary[String, int] = {}
var mastery: Dictionary[String, int] = {}
var mastery_units: Dictionary[String, float] = {}
## Counters that conditions read: bales, hexes, pieces, mastery_<kind>.
var counters: Dictionary[String, float] = {}
## Slot -> fitted module.
var rig: Dictionary[String, String] = {}
var zones: Array[PaceSimRdDistrict] = []
var here: int = 0
var unlocked: int = 1
var base_level: int = 1
## Seconds Lumi is tied up (landing, a purchase, a hop, a source step).
var busy_s: float = 0.0
var ended_at: float = -1.0
var research_active: String = ""
## Field data not yet spent: it banks while no node is active and fills the active node's bar.
var data_bank: float = 0.0
var data_earned: float = 0.0
## The launch capstone: parts of the rocket fitted so far, seconds of assembly left on the part
## being made (0 = none), and whether a finished part waits for Lumi to fit it.
var rocket_fitted: int = 0
var rocket_left_s: float = 0.0
var rocket_ready: bool = false
var pieces: PackedStringArray = []
## Cleaning output so far, in work units and in hexes' worth, by hand and by crew.
var hand_units: float = 0.0
var crew_units: float = 0.0
var hand_hexes: float = 0.0
var crew_hexes: float = 0.0
var hexes_clean: int = 0
var items_dirty: bool = true
var rig_dirty: bool = false

var _items: Array[Dictionary] = []
var _items_at: float = -100.0
var _auto_unlocks: PackedStringArray = []
var _next_buried: int = 0


func _init(model_data: PaceSimRdData, player: PaceSimRdPolicy) -> void:
	data = model_data
	policy = player
	rates = PaceSimRdRates.new(self)
	work = PaceSimRdWork.new(self)
	var need: Array = data.tables["regrowth"]["points_to_leave"]
	for i: int in data.districts.size():
		var z := PaceSimRdDistrict.new(data.districts[i], i, data.num("districts.stage_share"), need, int(data.num("districts.source_caps_stage")))
		var loose: float = 0.0
		for kind: String in z.mix:
			loose += z.mix[kind] * float(data.kinds[kind]["yield"]["cubes"]) * z.hex_work
		z.cube_scale = data.hex_cubes(i, loose) / loose
		z.reward_mult = data.hex_cubes(i, loose) / data.num("districts.stage_reward_ref_cubes")
		z.crew_reach = rates.reach_over(int(z.row["rings"]))
		zones.append(z)
	for kind: String in data.kinds:
		mastery[kind] = 0
		mastery_units[kind] = 0.0
	for id: String in data.unlocks:
		if bool(data.unlocks[id].get("auto", false)):
			_auto_unlocks.append(id)
	zones[0].entered_at = 0.0


## Plays until the ending or `max_s` seconds.
func run(max_s: float) -> void:
	busy_s = data.num("balance.start.delay_s")
	emit("start")
	emit("enter:" + zones[0].id)
	while t < max_s and ended_at < 0.0:
		_tick()


## Breaks the reference cycles between the model and its helpers once a run is reported.
func seal() -> void:
	rates = null
	work = null
	policy = null


## Records an event. The first time an event named by an authored district-sized goal happens
## (goals.json district_goals), that goal is done.
func emit(event: String) -> void:
	if not record.events.has(event):
		for row: Variant in data.tables["goals"].get("district_goals", []):
			if str((row as Dictionary)["event"]) == event:
				record.district_goal(t, "goal:" + str((row as Dictionary)["id"]))
				record.win(t)
	record.event(event, t)


func pay(amount: float) -> void:
	cubes += amount
	earned += amount


func gain_parts(amount: float) -> void:
	parts += amount
	parts_earned += amount


## The crew: every robot. A building that builds robots (the Assembler) is not one of them.
func robot_total() -> int:
	var n: int = 0
	for type: String in robots:
		if not bool(data.robot_types[type].get("building", false)):
			n += robots[type]
	return n


func is_building(type: String) -> bool:
	return bool(data.robot_types[type].get("building", false))


## The rocket's parts in build order (restoration.json launch.rocket.parts), or [] with no capstone.
func rocket_parts() -> Array:
	return (data.tables["restoration"]["launch"].get("rocket", {}) as Dictionary).get("parts", [])


func rocket_done() -> bool:
	return rocket_fitted >= rocket_parts().size()


## Index of the district the rocket stands in, or -1.
func rocket_district() -> int:
	var rocket: Dictionary = data.tables["restoration"]["launch"].get("rocket", {})
	return data.district_index(str(rocket.get("district", "")))


## The rocket part that can be ordered now, or {}: one at a time, in order, each once that
## share of the launch city is clean (and its source shut where the part says so).
func rocket_next() -> Dictionary:
	if rocket_done() or rocket_left_s > 0.0 or rocket_ready or assemblers() <= 0:
		return {}
	var at: int = rocket_district()
	if at < 0 or at >= unlocked or zones[at].entered_at < 0.0:
		return {}
	var part: Dictionary = rocket_parts()[rocket_fitted]
	if zones[at].clean_share() + 0.0001 < float(part.get("at_clean_share", 0.0)) or (bool(part.get("after_source", false)) and not zones[at].source_shut()):
		return {}
	return part


## Lumi fits the finished rocket part by hand.
func fit_rocket_part() -> void:
	if not rocket_ready:
		return
	var part: Dictionary = rocket_parts()[rocket_fitted]
	rocket_ready = false
	rocket_fitted += 1
	busy_s += float(part["fit_s"])
	emit("first_rocket_part")
	emit("rocket_fit:%d" % rocket_fitted)
	record.district_goal(t, "rocket:%s" % str(part["id"]))
	record.now_goal(t)
	record.win(t)
	if rocket_done():
		emit("rocket_complete")
	items_dirty = true


## Robots of the type that builds robots.
func assemblers() -> int:
	return robots.get(str(data.tables["robots"]["chain"]["assembler"]), 0)


## Parts one robot of a type costs now (a repaired type costs more to build).
func robot_parts(type: String) -> float:
	var cfg: Dictionary = data.tables["robots"]
	var row: Dictionary = data.robot_types[type]
	var price: float = float(row["parts"]) + float(row.get("parts_step", 0.0)) * float(robots.get(type, 0))
	return price * (float(cfg["repaired_build_mult"]) if repaired.get(type, 0) > 0 else 1.0)


## An Assembler finishes a robot of `type`: Parts are spent, no bench visit. False when it cannot.
func assemble(type: String) -> bool:
	if is_building(type) or robot_total() >= crew_cap() or parts < robot_parts(type) or not conditions_met(data.robot_types[type]):
		return false
	parts -= robot_parts(type)
	parts_on_robots += robot_parts(type)
	robots[type] = robots.get(type, 0) + 1
	assembled += 1
	emit("robot:" + type)
	record.builds.append(t)
	record.win(t)
	rates.dirty = true
	items_dirty = true
	return true


## The most robots the base can run at its level.
func crew_cap() -> int:
	return int((data.tables["robots"]["crew_cap"] as Array)[base_level - 1])


## A one-off reward (a district stage, a source): paid at once and measured against income.
func reward(amount: float) -> void:
	record.lump(self, amount)
	pay(amount)


func count_of(counter: String) -> float:
	return counters.get(counter, 0.0)


func bump(counter: String, by: float = 1.0) -> void:
	counters[counter] = counters.get(counter, 0.0) + by


## Planet restoration 0..1: the mean of the districts' values.
func restoration() -> float:
	var total: float = 0.0
	for z: PaceSimRdDistrict in zones:
		total += z.value(data.tables["restoration"]["stage_values"])
	return total / float(zones.size())


## Field data from play is banked. The active research node is done as soon as the bank holds
## its field-data cost, which is then spent; with no node active the bank just grows.
func add_data(amount: float) -> void:
	data_bank += amount
	data_earned += amount
	if research_active == "":
		return
	var cost: float = float(data.nodes[research_active]["cost"]["data"])
	if data_bank >= cost:
		var id: String = research_active
		research_active = ""
		data_bank -= cost
		grant(id)
		record.win(t)


func gain_seeds(amount: float) -> void:
	seeds += amount
	seeds_earned += amount


## Makes an id owned (an unlock, a finished node, a source's grant, a module).
func grant(id: String) -> void:
	if owned.has(id):
		return
	owned[id] = true
	if data.unlocks.has(id):
		var sets: Dictionary = data.unlocks[id].get("set", {})
		base_level = maxi(base_level, int(sets.get("base_level", base_level)))
	if data.modules.has(id):
		rig_dirty = true
	if id == str(data.tables["regrowth"]["unlock"]):
		gain_seeds(data.num("regrowth.seeds.kit"))
	emit("own:" + id)
	rates.dirty = true
	items_dirty = true


func piece_found(piece: String) -> void:
	pieces.append(piece)
	bump("pieces")
	emit("first_piece")
	emit("piece:" + piece)
	record.win(t)
	add_data(data.num("research.data_rewards.piece_found"))
	for wanted: Variant in data.tables["finds"]["set"]["pieces"]:
		if not pieces.has(str(wanted)):
			return
	emit("set_complete")


## Fits an owned module into its slot (free, at the bench). Returns false when it cannot be fitted.
func fit(module: String) -> bool:
	if not owned.has(module) or not data.modules.has(module):
		return false
	var slot: String = str(data.modules[module]["slot"])
	if not owned.has(str(data.tables["rigs"]["slot_unlock"][slot])):
		return false
	if rig.get(slot, "") != module:
		rig[slot] = module
		rates.dirty = true
		emit("first_module")
	return true


## True when the row's requires, district and when conditions all hold.
func conditions_met(row: Dictionary) -> bool:
	var needs: Variant = row.get("requires", [])
	for id: Variant in needs if needs is Array else [needs]:
		if not owned.has(str(id)):
			return false
	if int(row.get("district", 0)) >= unlocked:
		return false
	var when: Dictionary = row.get("when", {})
	for counter: String in when:
		if count_of(counter) < float(when[counter]):
			return false
	return true


## Everything on offer now: {type, id, cubes, parts, gate, crew}. Types: track, unlock, research,
## robot, repair, module.
func items() -> Array[Dictionary]:
	if items_dirty or t - _items_at >= ITEMS_REFRESH_S:
		_items = PaceSimRdOffers.build(self)
		_items_at = t
		items_dirty = false
	return _items


func can_afford(item: Dictionary) -> bool:
	return cubes >= float(item["cubes"]) and parts >= float(item["parts"])


func any_affordable() -> bool:
	for item: Dictionary in items():
		if can_afford(item):
			return true
	return false


## Buys an offered item, enforcing its cost. Each purchase costs Lumi a moment at the bench.
func buy(item: Dictionary) -> bool:
	if not can_afford(item):
		return false
	var income_before: float = rates.income_now()
	cubes -= float(item["cubes"])
	parts -= float(item["parts"])
	_apply(item, 1)
	var id: String = str(item["id"])
	match str(item["type"]):
		"track":
			emit("first_upgrade")
		"unlock", "module":
			grant(id)
		"research":
			research_active = id
			emit("first_research")
			add_data(0.0)
		"robot":
			emit("robot:" + id)
			if not is_building(id):
				emit("first_robot")
				record.builds.append(t)
				parts_on_robots += float(item["parts"])
		"repair":
			emit("first_repair")
			parts_on_repairs += float(item["parts"])
		"rocket":
			rocket_left_s = float(rocket_parts()[rocket_fitted]["assembly_s"])
			emit("first_rocket_order")
	busy_s += data.num("balance.hand.shop_s")
	record.purchase(t, str(item["type"]), id, float(item["cubes"]), float(item["parts"]))
	rates.dirty = true
	items_dirty = true
	record.income_jump(self, str(item["type"]) + ":" + id, income_before, rates.income_now())
	return true


## What-if for a policy: applies an item's effect without paying (`undo` takes it back).
func peek(item: Dictionary, undo: bool = false) -> void:
	_apply(item, -1 if undo else 1)
	var id: String = str(item["id"])
	if str(item["type"]) in ["unlock", "module"]:
		if undo:
			owned.erase(id)
		else:
			owned[id] = true
	rates.dirty = true


func _apply(item: Dictionary, by: int) -> void:
	var id: String = str(item["id"])
	match str(item["type"]):
		"track":
			levels[id] = levels.get(id, 0) + by
		"robot":
			robots[id] = robots.get(id, 0) + by
		"repair":
			repaired[id] = repaired.get(id, 0) + by


func _tick() -> void:
	t += TICK_S
	_triggers()
	if busy_s > 0.0:
		busy_s -= TICK_S
	else:
		policy.shop(self)
		if busy_s <= 0.0:
			work.act(policy.choose(self))
	work.crew_tick()
	work.chain_tick()
	work.grow_tick()
	_after_work()
	record.offers(self)
	record.sample(self)


func _triggers() -> void:
	for id: String in _auto_unlocks:
		if not owned.has(id) and conditions_met(data.unlocks[id]):
			grant(id)
	var buried: Array = data.tables["finds"]["buried"]
	while _next_buried < buried.size() and hexes_clean >= int(buried[_next_buried]["after_hexes"]):
		piece_found(str(buried[_next_buried]["piece"]))
		_next_buried += 1
	work.trickle()


func _after_work() -> void:
	for z: PaceSimRdDistrict in zones:
		if z.index >= unlocked:
			break
		for i: int in z.take_new_clean():
			_hex_cleaned(z)
		var before: int = z.stage
		if z.update_stage(t):
			for s: int in range(before + 1, z.stage + 1):
				_district_stage(z, s)
	if ended_at < 0.0 and _all_at(int(data.num("restoration.launch.stage"))):
		emit("all_cities_thriving")
		if rocket_done():
			ended_at = t
			emit("launch_ready")
	_seed_watch()


## Counts the seconds a kind that costs seeds had work left in an open district and no seeds.
func _seed_watch() -> void:
	if seeds >= 0.01:
		return
	for z: PaceSimRdDistrict in zones:
		if z.index >= unlocked or z.entered_at < 0.0:
			continue
		for kind: String in z.mix:
			if float(data.kinds[kind].get("seeds_per_hex", 0.0)) > 0.0 and z.remaining(kind) > 0.001 and rates.kind_usable(kind):
				seed_short_s += TICK_S
				return


## A hex is clean: field data and buried parts, no cubes (cubes come from Lumi's bales).
func _hex_cleaned(z: PaceSimRdDistrict) -> void:
	hexes_clean += 1
	z.buried_parts += float(z.row.get("buried_parts_per_hex", 0.0))
	bump("hexes")
	add_data(data.num("districts.hex_bonus.data"))
	record.hex(t)
	record.win(t)
	emit("hexes_%d" % hexes_clean)
	if z.index == here:
		record.now_goal(t)


func _district_stage(z: PaceSimRdDistrict, s: int) -> void:
	var stage_reward: Dictionary = data.tables["regrowth"]["district_stage_reward"]
	reward(float((stage_reward["cubes"] as Array)[s]) * z.reward_mult)
	add_data(float((stage_reward["data"] as Array)[s]))
	emit("stage:%s:%d" % [z.id, s])
	record.district_goal(t, "stage:%s:%d" % [z.id, s])
	record.win(t)
	if s == 1:
		record.rig_best[z.id] = policy.best_modules(self, z)
		for id: String in data.modules:
			if str(data.modules[id]["source"]) == "find:" + z.id:
				grant(id)
	if s == 4:
		z.crew_at_stage4 = robot_total()
	for i: int in range(unlocked, zones.size()):
		var rule: Dictionary = zones[i].row["unlock"]
		if str(rule.get("type", "")) != "district_stage" or str(rule["district"]) != z.id or z.stage < int(rule["stage"]):
			break
		unlocked = i + 1
		emit("unlocked:" + zones[i].id)
		items_dirty = true


func _all_at(stage: int) -> bool:
	for z: PaceSimRdDistrict in zones:
		if z.stage < stage:
			return false
	return true
