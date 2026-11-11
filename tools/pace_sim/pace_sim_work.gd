class_name PaceSimWork
extends RefCounted
## The work that moves a planet forward, per second: Lumi's hand loop (scoop, fill the chest, walk
## to the bin or press and carry bales), the robot crew (cleaners fill bales, haulers cash them)
## and the garden at a coarse level. Rates come from Economy stats; what cannot be derived from
## data is a named constant in calibration.json.

enum Phase { SCOOP, PRESS, TO_BASE, RETURN }

## Bales fill the chest to the middle of the press window (Pace.PRESS_AT to full).
const FILL_AT: float = (Pace.PRESS_AT + 1.0) * 0.5
const GARDEN_TOP: int = 5
## Lumi looks up from his work this often to ask whether the bench is worth a walk.
const TRIP_CHECK_S: int = 5

var m: PaceSimModel
var data: PaceSimData

# Lumi's stats, refreshed after every purchase.
var capacity: float = 0.0
var hand_rate: float = 0.0
## Units of waste in the hex Lumi is working, and what the chest's load pays tipped loose (its
## share of the hexes it came from, as HexWorth counts it).
var hex_vol: float = 0.0
var chest_worth: float = 0.0
var move_speed: float = 1.0
var carry_cap: int = 1
var baler: bool = false
var lift: int = 0

var phase: Phase = Phase.SCOOP
var busy: float = 0.0
var chest: float = 0.0
## Cash value of the bales on Lumi's back, and of the bales lying in the field.
var carried: Array[float] = []
var backlog: Array[float] = []
var hex_left: float = 0.0
var hexes_done: int = 0
## Output so far in hexes, by who did it (the hand-share rule compares them).
var hand_hexes: float = 0.0
var crew_hexes: float = 0.0
## Lumi's mastery of the base kind (the first city holds nothing else): the units her hands have
## cleared, the level they hold (core/mastery_rules.gd), and the seconds cleaner robots stood
## built but shut out because she had not learnt the kind yet.
var mastery_units: float = 0.0
var mastery_level: int = 0
var cleaner_wait_s: float = 0.0
var walk_s: float = 0.0
var stuck_s: float = 0.0
var last_bench_t: float = 0.0
## Hexes at each regrowth level, as the times they got there (oldest first).
var garden: Array[Array] = []

var _crew_part: float = 0.0
var _hopper: Dictionary[String, float] = {}
var _haul_credit: float = 0.0
var _plant_credit: float = 0.0
var _seed_wait: float = 0.0
var _seeds_in: Dictionary[int, float] = {}
var _blooms: PackedFloat64Array = []
var _yard_found: bool = false
var _cashed_by_haulers: int = 0
var _unit_rate: Dictionary[String, float] = {}
var _mastery_cfg: Dictionary = {}
var _base_kind: String = ""
## Whether the trip under way ends at the scale (bales) or at the bin.
var _to_scale: bool = false


func _init(model: PaceSimModel) -> void:
	m = model
	data = model.data
	hex_vol = data.hex_work(0)
	hex_left = hex_vol
	var kinds: Dictionary = Planets.current().table(Pollution.TABLE)
	_mastery_cfg = MasteryRules.config(kinds, Planets.current().table("robots"))
	_base_kind = str(kinds.get("base", ""))
	for i: int in GARDEN_TOP + 1:
		garden.append([])


func refresh_stats() -> void:
	if not data.has_content():
		return
	capacity = Economy.stat("capacity")
	move_speed = maxf(Economy.stat("move_speed"), 0.1)
	carry_cap = maxi(1, int(round(Economy.stat("carry_stack"))))
	baler = Pace.baler_unlocked()
	lift = Pace.lift_class()
	var beam: float = Economy.stat("scoop_width") * Economy.stat("scoop_reach")
	var beam_base: float = maxf(Economy.base_stat("scoop_width") * Economy.base_stat("scoop_reach"), 0.001)
	var beam_gain: float = pow(maxf(beam / beam_base, 0.001), data.k("beam_exponent"))
	# Seconds per unit of volume: the pulse itself, plus finding and facing the next pieces.
	var pulse_s: float = 1.0 / (maxf(Economy.stat("scoop_rate"), 0.5) * hand_bonus() * Pace.pulse_volume() * data.k("hand_duty"))
	hand_rate = 1.0 / (pulse_s + data.k("seek_s_per_volume") / beam_gain)
	for id: String in m.robots:
		_unit_rate[id] = Offline.unit_rate(id, int(m.robot_tier.get(id, 0)))


func step(dt: float) -> void:
	if not _yard_found and m.t >= data.k("yard_finds_s"):
		_yard_found = true  # the buried parts in the start yard, dug up in the first minutes
		m.parts += data.k("yard_parts")
		m.add_stat("parts_found", data.k("yard_finds"))
	_crew(dt)
	_haul(dt)
	_garden(dt)
	_hand(dt)


## Lumi's rate on the base kind from her mastery of it (Patch pulses that much sooner).
func hand_bonus() -> float:
	return MasteryRules.hand_bonus(_mastery_cfg, mastery_level) if MasteryRules.tracks(_mastery_cfg, _base_kind) else 1.0


## A cleaner robot's rate against its own: Lumi's mastery of the base kind, and the bonus for
## the share of the crew's work done alongside her. 0 while robots may not work the kind.
func crew_factor() -> float:
	var near: float = 1.0 + (MasteryRules.near_factor(_mastery_cfg, 0.0) - 1.0) * data.k("crew_near_share")
	return MasteryRules.robot_factor(_mastery_cfg, _base_kind, mastery_level) * near


## Lumi's own hands cleared `units`: mastery of the base kind, and a beat for each level.
func _learn(units: float) -> void:
	mastery_units += MasteryRules.gain(_mastery_cfg, _base_kind, units)
	var level: int = MasteryRules.level_for(_mastery_cfg, _base_kind, mastery_units)
	if level == mastery_level:
		return
	mastery_level = level
	m.record.beat("mastery_%d" % level, m.t)
	refresh_stats()


## Metres from the bin to where Lumi is working.
func distance() -> float:
	return _reach(data.hex_distance(hexes_done))


## Lumi works a hex from its near edge to its far one, so the walk grows with the share cleaned:
## the middle's distance, less half the hex's span at the start and plus half at the end.
func _reach(middle_m: float) -> float:
	var done: float = 1.0 - hex_left / maxf(hex_vol, 0.001)
	return maxf(middle_m + (done - 0.5) * data.k("hex_span_m"), 0.0)


func region_done() -> bool:
	return data.region_hexes > 0 and hexes_done >= data.region_hexes


func haulers() -> int:
	return m.role_count("haul")


func garden_count(level: int) -> int:
	var n: int = 0
	for l: int in range(level, GARDEN_TOP + 1):
		n += garden[l].size()
	return n


# --- Lumi ----------------------------------------------------------------------------------

func _hand(dt: float) -> void:
	if m.t <= data.k("start_delay_s"):
		return  # the landing: the pod, WREN's message, the first steps to the junk
	var left: float = dt
	var guard: int = 0
	while left > 0.0001 and guard < 12:
		guard += 1
		if busy > 0.0:
			var use: float = minf(left, busy)
			busy -= use
			left -= use
			if phase == Phase.TO_BASE or phase == Phase.RETURN:
				walk_s += use
			if busy <= 0.0:
				_phase_done()
			continue
		if _leave_for_base():
			continue
		left = _scoop(left)


## One way between the work and the base: to the scale with bales on Lumi's back, to the bin
## (and the bench beside it) otherwise.
func _travel_s() -> float:
	# Lumi tips from anywhere within the bin's reach and sells from the weigh plate's edge.
	var metres: float = _reach(data.scale_distance(hexes_done)) - Depot.PAD_RADIUS if _to_scale else distance() - Pace.bin_radius()
	if metres <= 0.0:
		return 0.0  # the junk lies inside the bin's reach: the load tips where Lumi stands
	return metres * data.k("path_factor") / move_speed + data.k("trip_overhead_s") * 0.5


## Reasons to stop scooping and go: a full stack of bales, or something worth buying at the bench.
func _leave_for_base() -> bool:
	var full_stack: bool = carried.size() >= carry_cap
	var bench: bool = m.t - last_bench_t >= data.k("bench_gap_s") and int(m.t) % TRIP_CHECK_S == 0 and m.policy.wants_trip(m)
	if not full_stack and not bench:
		return false
	phase = Phase.TO_BASE
	_to_scale = not carried.is_empty()
	busy = _travel_s()
	return true


func _scoop(left: float) -> float:
	if hand_rate <= 0.0 or region_done():
		return 0.0
	var must_stay: float = hex_vol * (1.0 - data.clean_frac)
	var cannot_lift: float = 0.0 if hexes_done < data.starter_hexes else hex_vol * (1.0 - data.liftable_share(lift))
	var avail: float = hex_left - maxf(must_stay, cannot_lift)
	if avail <= 0.0001:
		stuck_s += left  # every piece left is too heavy: Lumi waits for Lift Strength
		return 0.0
	var room: float = capacity * FILL_AT - chest
	if room <= 0.0001:
		_chest_full()
		return left
	var rate: float = hand_rate * (1.0 - _garden_share())
	var take: float = minf(minf(rate * left, room), avail)
	chest += take
	chest_worth += HexWorth.share_of(data.hex_cubes, take, hex_left, hex_vol, data.clean_frac)
	hex_left -= take
	hand_hexes += take / (hex_vol * data.clean_frac)
	_learn(take)
	_salvage(take)
	if garden_open():
		_seed_finds(take / data.mean_bite, take / rate)
	if hex_left <= must_stay + 0.0001:
		hex_cleaned(true)
		hex_vol = data.hex_work(hexes_done)
		hex_left = hex_vol
	if capacity * FILL_AT - chest <= 0.0001:
		_chest_full()
	elif not baler and carried.is_empty() and distance() <= Pace.bin_radius():
		_tip()  # inside the bin's reach the chest empties as it fills, with no walk at all
	return left - take / rate


## Robot parts stripped from `units` of scooped waste: Parts, at the rarity table's average value.
func _salvage(units: float) -> void:
	m.add_stat("junk_scooped", units / maxf(data.mean_bite, 0.001))
	var finds: float = units * data.finds_per_unit(hex_vol) * data.k("parts_luck")
	if m.seed_value != 0:
		var whole: float = floor(finds)
		finds = whole + (1.0 if m.rng.randf() < finds - whole else 0.0)
	m.parts += finds * PaceSimData.mean_part_value()
	m.add_stat("parts_found", finds)


func _chest_full() -> void:
	if baler:
		phase = Phase.PRESS
		busy = Patch.CUBE_TIME + data.k("bale_handle_s")
	else:
		phase = Phase.TO_BASE
		_to_scale = false
		busy = _travel_s()


func _contents() -> Dictionary:
	var out: Dictionary = {}
	for id: String in data.mix:
		out[id] = chest * data.mix[id]
	return out


func _phase_done() -> void:
	match phase:
		Phase.PRESS:
			var info: Dictionary = Economy.evaluate_cube(_contents(), capacity, -1.0, chest_worth)
			chest = 0.0
			chest_worth = 0.0
			m.add_stat("cubes_made")
			if info["perfect"]:
				m.add_stat("perfect_cubes")
			m.record.win(m.t, "bale")
			var value: float = (info["value"] as BigNum).to_float() * m.sell_factor()
			if haulers() > 0:
				backlog.append(value)
			else:
				carried.append(value)
				# Crew bales lying close by ride along in the spare stack slots.
				while carried.size() < carry_cap and not backlog.is_empty():
					carried.append(backlog.pop_front())
			phase = Phase.SCOOP
		Phase.TO_BASE:
			_at_base()
			phase = Phase.RETURN
			busy = _travel_s()
		Phase.RETURN:
			phase = Phase.SCOOP


func _tip() -> void:
	m.pay(Pace.dump_value(_contents(), chest_worth), "dump")
	m.add_stat("junk_dumps")
	chest = 0.0
	chest_worth = 0.0


func _at_base() -> void:
	if chest > 0.0 and not baler:
		_tip()
	for value: float in carried:
		m.pay(value, "bale_sold")
		m.add_stat("cubes_cashed")
	carried.clear()
	last_bench_t = m.t
	m.policy.shop(m)


# --- Hexes ---------------------------------------------------------------------------------

## A hex reached the clean rule: the field note and the regrowth reward (a clean hex pays no cubes
## by itself), and the city's first stage payout when enough of the district is clean.
func hex_cleaned(by_hand: bool) -> void:
	hexes_done += 1
	m.add_stat("hexes_cleaned")
	m.pay(field_note("hex_cleaned") + _level_reward(1), "hex")
	if hexes_done == Districts.hexes_needed(PackedInt32Array([maxi(data.region_hexes - 1, 0)]), data.stage_share):
		m.pay(CityPayouts.reward_for(data.stage_rule, data.hex_cubes, 1), "city_stage")
	garden[1].append(m.t)
	if by_hand:
		m.parts += data.parts_per_hex_buried * data.k("buried_find_share")
		m.add_stat("parts_found", data.finds_per_hex_buried * data.k("buried_find_share"))
	m.record.hex(m.t, hexes_done)


## Cubes one field note of this kind pays (Research.award_data without the side effects). The
## total is the bot's research fund, so it is counted.
func field_note(kind: String) -> float:
	var paid: float = Research.stat_mod("data_gain", 1.0) * Research.reward(kind) * Research.note_pay()
	m.chains.notes_cubes += paid
	return paid


func _level_reward(level: int) -> float:
	for row: Variant in data.regrowth.get("levels", []):
		var d: Dictionary = row
		if int(d.get("level", -1)) == level:
			var reward: Dictionary = d.get("reward", {})
			m.seeds += float(reward.get("seeds", 0.0))
			return float(reward.get("cubes", 0.0))
	return 0.0


# --- The crew ------------------------------------------------------------------------------

func _crew(dt: float) -> void:
	if region_done():
		return
	var per_hex: float = SphereOffline.UNITS_PER_CELL * data.clean_frac
	var learnt: float = crew_factor()
	for id: String in m.robots:
		if m.role_of(id) != "clean":
			continue
		if learnt <= 0.0:
			cleaner_wait_s += dt * float(m.robots[id])
			continue
		var tier: int = int(m.robot_tier.get(id, 0))
		# Seconds a cleaner needs for a hex: the work at its unit rate, plus driving, which grows
		# with the distance of the frontier from the base.
		var rate: float = float(_unit_rate.get(id, 0.0)) * learnt
		if rate <= 0.0:
			continue
		var hex_s: float = per_hex / rate + data.k("crew_travel_s_per_ring") * float(PaceSimData.ring_of(hexes_done))
		var units: float = float(m.robots[id]) * per_hex / hex_s * dt
		_crew_part += units / per_hex
		crew_hexes += units / per_hex
		var cap: float = Economy.robot_stat(id, "capacity", tier)
		cap = cap if cap > 0.0 else per_hex
		_hopper[id] = _hopper.get(id, 0.0) + units
		while _hopper[id] >= cap:
			_hopper[id] -= cap
			backlog.append(0.0)  # a robot's bale is waste on its way out: robots earn no cubes
			m.add_stat("robot_bales")
			m.pay(field_note("robot_bale"))
	while _crew_part >= 1.0:
		_crew_part -= 1.0
		hex_cleaned(false)


func _haul(dt: float) -> void:
	for id: String in m.robots:
		if m.role_of(id) != "haul":
			continue
		var tier: int = int(m.robot_tier.get(id, 0))
		var speed: float = maxf(Economy.robot_stat(id, "speed", tier), 0.1)
		var carry: float = maxf(1.0, floor(Economy.robot_stat(id, "carry", tier)))
		_haul_credit += float(m.robots[id]) * carry / (2.0 * distance() / speed + data.k("haul_overhead_s")) * dt
	while _haul_credit >= 1.0 and not backlog.is_empty():
		_haul_credit -= 1.0
		_cash_hauled(backlog.pop_front())
	_haul_credit = minf(_haul_credit, 1.0)


## A hauled bale: sold at the scale, or fed to the recycler for Parts on the bot's every-n-th rule.
func _cash_hauled(value: float) -> void:
	_cashed_by_haulers += 1
	var every: int = int(data.k("recycle_every"))
	if m.built.has("recycler") and every > 0 and _cashed_by_haulers % every == 0:
		var rc: Dictionary = data.stations.get("recycler", {})
		m.parts += float(rc.get("parts_per_bale", 0.0)) * Economy.stat("recycler_yield") * (0.5 + FILL_AT)
		m.pay(value * float(rc.get("cube_mult", 0.0)), "haul")
		m.add_stat("bales_recycled")
		return
	m.pay(value, "haul")


# --- The garden (coarse) -------------------------------------------------------------------

func garden_open() -> bool:
	return m.flags.get("seeds_unlocked", false)


## Share of Lumi's time the garden takes once it is open (planting and watering by hand).
func _garden_share() -> float:
	return data.k("garden_time_share") if garden_open() else 0.0


## Seeds that turn up in scooped junk (the planet's "plants" table, seed_finds): each take has a
## small chance, then the finder rests for cooldown_s. Expected seeds for this much scooping.
func _seed_finds(bites: float, seconds: float) -> void:
	var finds: Dictionary = Economy.planet_table("plants").get("seed_finds", {})
	var chance: float = float(finds.get("chance", 0.0))
	if chance <= 0.0 or bites <= 0.0:
		return
	var wait_s: float = seconds / (bites * chance)  # scooping time until the roll succeeds
	m.seeds += seconds / (float(finds.get("cooldown_s", 0.0)) + wait_s)


func _garden(dt: float) -> void:
	if not garden_open():
		_wait_for_seeds(dt)
		return
	_plant(dt)
	_bloom()
	# Growing once the first plants are part-grown; Sustained needs a waterer per drip_hexes.
	_age(2, data.bloom_s * float(data.regrowth.get("growing_life", 0.35)), 1 << 30)
	_age(3, float(data.regrowth.get("sustain_window_s", 180.0)), m.role_count("water") * int(data.k("drip_hexes")) - garden_count(4))
	_stipend(dt)


## One seed at a time goes into the oldest clean hex until it counts as Planted; spare seeds then
## fill Sustained hexes up to Thriving. Planter robots add their own planting speed.
func _plant(dt: float) -> void:
	_plant_credit = minf(_plant_credit + dt * (_garden_share() / maxf(data.k("plant_seed_s"), 0.1)
		+ float(m.role_count("plant")) / maxf(data.k("robot_plant_seed_s"), 0.1)), 4.0)
	while _plant_credit >= 1.0 and m.seeds >= 1.0:
		var level: int = 1 if not garden[1].is_empty() else (4 if not garden[4].is_empty() else 0)
		if level == 0:
			return
		_plant_credit -= 1.0
		m.seeds -= 1.0
		m.add_stat("plants_planted")
		_blooms.append(m.t + data.bloom_s / maxf(Economy.stat("plant_growth"), 0.1))
		_seeds_in[level] = float(_seeds_in.get(level, 0.0)) + 1.0
		var need: float = data.seeds_to_plant if level == 1 else data.seeds_to_thrive
		if _seeds_in[level] >= need:
			_seeds_in[level] = 0.0
			_promote(level)


## Planted seeds bloom once and drop seeds (species seed_yield x the seed_yield stat).
func _bloom() -> void:
	while not _blooms.is_empty() and _blooms[0] <= m.t:
		_blooms.remove_at(0)
		m.add_stat("plants_bloomed")
		m.seeds += data.seed_yield * Economy.stat("seed_yield")
		m.pay(field_note("plant_bloomed"))


## The garden opens once enough hexes are clean (the planet's "plants" table) and Lumi has fetched
## the first seeds, which takes seed_fetch_s.
func _wait_for_seeds(dt: float) -> void:
	var plants: Dictionary = Economy.planet_table("plants")
	if plants.is_empty():
		return
	var first: Dictionary = plants.get("first_seed", {})
	if not m.flags.get("seed_signal", false):
		if hexes_done >= int(first.get("hexes_needed", 5)):
			m.flags["seed_signal"] = true
		return
	_seed_wait += dt
	if _seed_wait >= data.k("seed_fetch_s"):
		m.flags["seeds_unlocked"] = true
		m.seeds += float(first.get("seeds_given", 0.0))
		m.record.mechanic(m.t, "garden")
		m.record.beat("garden_open", m.t)


func _age(level: int, after_s: float, room: int) -> void:
	var moved: int = 0
	while not garden[level].is_empty() and moved < room and m.t - float(garden[level][0]) >= after_s:
		_promote(level)
		moved += 1


func _promote(level: int) -> void:
	garden[level].pop_front()
	garden[level + 1].append(m.t)
	m.pay(_level_reward(level + 1), "hex_level")
	m.record.beat("hex_level_%d" % (level + 1), m.t)
	if level + 1 >= 4:
		m.add_stat("hexes_restored")
		m.pay(field_note("hex_restored"))


func _stipend(dt: float) -> void:
	var per_min: float = 0.0
	for row: Variant in data.regrowth.get("levels", []):
		var d: Dictionary = row
		var bonus: Dictionary = d.get("bonus", {})
		var level: int = int(d.get("level", 0))
		if level >= 1 and level <= GARDEN_TOP:
			per_min += float(bonus.get("cubes_per_min", 0.0)) * garden[level].size()
	var cap: float = float((data.regrowth.get("bonus_caps", {}) as Dictionary).get("cubes_per_min", per_min))
	var paid: float = minf(per_min, cap) / 60.0 * dt
	m.pay(paid)
	m.add_stat("garden_stipend", paid)
