class_name PaceSimRdWork
extends RefCounted
## One tick of work in the redesign model: what Lumi does (sweep, plant, water, the source job, a
## hop, a wreck), what the crew does, how hexes grow, and the Surge.
## Lumi's choices come from the policy as plain strings: clean, plant, water (dry hexes), boost
## (water again for another burst), source, explore, fit (a rocket part), travel:<district index>, idle.

const MERGE_EVERY_S: float = 5.0

## Surge charge 0..1 and the time the running burst ends.
var surge_charge: float = 0.0
var surge_until: float = -1.0
## Seconds Lumi spent on each kind of action.
var seconds: Dictionary[String, float] = {}

var _m: PaceSimRdModel
var _d: PaceSimRdData
var _load_acc: float = 0.0
var _batch_acc: Dictionary[String, float] = {}
var _promoted_acc: float = 0.0
var _tend_acc: Dictionary[String, float] = {}
var _next_merge: float = 0.0
var _assembly: float = 0.0


func _init(model: PaceSimRdModel) -> void:
	_m = model
	_d = model.data


func zone() -> PaceSimRdDistrict:
	return _m.zones[_m.here]


func tending_open() -> bool:
	return _m.owned.has(str(_d.tables["regrowth"]["unlock"]))


## Kinds of the district Lumi has the tool for (and, for a kind cleared with plants, seeds).
func usable_kinds(z: PaceSimRdDistrict) -> Array[String]:
	var out: Array[String] = []
	for kind: String in z.mix:
		if _m.rates.kind_usable(kind) and _has_seeds_for(kind):
			out.append(kind)
	return out


## Seeds one unit of `kind` costs to clear in `z` (cleansing plants), 0 for most kinds.
func seeds_per_unit(z: PaceSimRdDistrict, kind: String) -> float:
	var per_hex: float = float(_d.kinds[kind].get("seeds_per_hex", 0.0))
	return per_hex / (z.hex_work * z.mix[kind]) if per_hex > 0.0 else 0.0


func _has_seeds_for(kind: String) -> bool:
	return float(_d.kinds[kind].get("seeds_per_hex", 0.0)) <= 0.0 or _m.seeds >= 0.01


## Clears up to `units` of a kind in `z`, paying seeds where the kind costs them; returns units cleared.
func _clear(z: PaceSimRdDistrict, kind: String, units: float) -> float:
	var cost: float = seeds_per_unit(z, kind)
	var used: float = z.add_units(kind, units if cost <= 0.0 else minf(units, _m.seeds / cost))
	if cost > 0.0:
		_m.seeds -= used * cost
		_m.seeds_cleansing += used * cost
	return used


func can_clean(z: PaceSimRdDistrict) -> bool:
	return z.bottleneck(usable_kinds(z)) != ""


func source_open(z: PaceSimRdDistrict) -> bool:
	return not z.source_shut() and z.stage >= int(_d.num("districts.source_available_stage")) and not usable_kinds(z).is_empty()


## The wreck find Lumi can reach in this district now, or {}.
func wreck_here(z: PaceSimRdDistrict) -> Dictionary:
	for row: Variant in _d.tables["finds"]["wreck"]:
		var find: Dictionary = row
		if str(find["district"]) == z.id and not _m.pieces.has(str(find["piece"])) and z.clean_share() >= float(find["at_clean_share"]):
			return find
	return {}


func surge_active() -> bool:
	return _m.t <= surge_until


## Carries out Lumi's choice for this tick.
func act(choice: String) -> void:
	var worked: bool = false
	var key: String = choice.get_slice(":", 0)
	match key:
		"clean":
			worked = _clean()
		"plant":
			worked = _plant()
		"water":
			worked = _water(true)
		"boost":
			worked = _water(false)
		"source":
			worked = _source()
		"explore":
			_explore()
		"fit":
			_m.fit_rocket_part()
			worked = true
		"travel":
			_travel(int(choice.get_slice(":", 1)))
	seconds[key] = seconds.get(key, 0.0) + PaceSimRdModel.TICK_S
	if worked and _m.rates.surge_owned() and not surge_active():
		surge_charge = minf(1.0, surge_charge + PaceSimRdModel.TICK_S / _m.rates.surge_charge_s())
		if surge_charge >= 1.0 and _m.policy.releases_surge(_m, key):
			_release_surge()


## New waste from every open source that is not shut yet: it adds to that source's clearing job.
func trickle() -> void:
	for z: PaceSimRdDistrict in _m.zones:
		if z.entered_at < 0.0 or z.source_shut():
			continue
		var src: Dictionary = z.row["source"]
		var cap: float = float(src["trickle_cap_hexes"]) * z.hex_work
		var add: float = float(src["trickle_hexes_per_min"]) * z.hex_work / 60.0
		if z.source_extra < cap:
			z.source_extra += add
			if z.source_step == 1:
				z.source_left += add


## The chain: Scroungers carry buried parts from cleaned ground to the base, Assemblers turn
## Parts into robots one at a time, in the mix the policy sets.
func chain_tick() -> void:
	var chain: Dictionary = _d.tables["robots"]["chain"]
	var finder: String = str(chain["scrounger"])
	var n: float = float(_m.robots.get(finder, 0))
	if n > 0.0:
		var z: PaceSimRdDistrict = _richest_ground()
		if z != null:
			var trip_s: float = float(chain["trip_s"]) + float(chain["trip_s_per_ring"]) * float(z.row["rings"])
			var carried: float = minf(z.buried_parts, n * float(chain["carry"]) * _m.rates.tier_mult(finder) * _m.rates.stat("scrounge") / trip_s * PaceSimRdModel.TICK_S)
			z.buried_parts -= carried
			_m.gain_parts(carried)
			_m.scrounged += carried
	var builders: float = float(_m.assemblers())
	if builders <= 0.0:
		return
	var line_speed: float = _m.rates.tier_mult(str(chain["assembler"]))
	# A rocket part on the line takes one Assembler until it is done.
	if _m.rocket_left_s > 0.0:
		builders -= 1.0
		_m.rocket_left_s -= line_speed * PaceSimRdModel.TICK_S
		if _m.rocket_left_s <= 0.0:
			_m.rocket_left_s = 0.0
			_m.rocket_ready = true
			_m.emit("rocket_part_made")
			_m.record.win(_m.t)
	_assembly = minf(_assembly + builders * line_speed / float(chain["assembly_s"]) * PaceSimRdModel.TICK_S, maxf(1.0, builders))
	while _assembly >= 1.0:
		var type: String = _m.policy.next_build(_m)
		if type == "" or not _m.assemble(type):
			break
		_assembly -= 1.0


## The open district with the most buried parts waiting, or null.
func _richest_ground() -> PaceSimRdDistrict:
	var best: PaceSimRdDistrict = null
	for z: PaceSimRdDistrict in _m.zones:
		if z.index < _m.unlocked and z.buried_parts > 0.01 and (best == null or z.buried_parts > best.buried_parts):
			best = z
	return best


func crew_tick() -> void:
	for type: String in _m.robots:
		var n: float = float(_m.robots[type])
		if n <= 0.0:
			continue
		var row: Dictionary = _d.robot_types[type]
		_crew_clean(type, row, n)
		for field: String in ["plant_rate", "water_rate"]:
			if float(row.get(field, 0.0)) > 0.0:
				_crew_tend(type, field, n)


func grow_tick() -> void:
	var regrowth: Dictionary = _d.tables["regrowth"]
	var merge: bool = _m.t >= _next_merge
	if merge:
		_next_merge = _m.t + MERGE_EVERY_S
	var bloom: float = float(regrowth["seeds"].get("bloom_per_hex_min", 0.0)) / 60.0 * PaceSimRdModel.TICK_S
	for z: PaceSimRdDistrict in _m.zones:
		# Thriving ground keeps blooming: a slow, steady source of seeds that cannot run dry.
		if bloom > 0.0 and z.count[PaceSimRdDistrict.TOP_STAGE] > 0.0:
			_m.gain_seeds(z.count[PaceSimRdDistrict.TOP_STAGE] * bloom)
		if z.batches.is_empty():
			continue
		var promoted: PackedFloat64Array = z.grow(PaceSimRdModel.TICK_S, _m.t, float(regrowth["dry_rate"]))
		for s: int in range(PaceSimRdDistrict.PLANTED + 1, PaceSimRdDistrict.TOP_STAGE + 1):
			if promoted[s] > 0.0:
				_stage_reward(z, s, promoted[s])
		if merge:
			z.merge()


func _stage_reward(z: PaceSimRdDistrict, s: int, n: float) -> void:
	var reward: Dictionary = _d.tables["regrowth"]["stage_reward"]
	_m.gain_seeds(n * float((_d.tables["regrowth"]["seeds"]["from_stage"] as Array)[s]))
	_m.add_data(n * float((reward["data"] as Array)[s]))
	_m.record.win(_m.t)
	if z.index == _m.here:
		_promoted_acc += n
		if _promoted_acc >= 1.0:
			_promoted_acc = fmod(_promoted_acc, 1.0)
			_m.record.now_goal(_m.t)


func _surge_mult() -> float:
	return _d.num("balance.surge.mult") * _m.rates.stat("surge_power") if surge_active() else 1.0


func _release_surge() -> void:
	surge_charge = 0.0
	surge_until = _m.t + _d.num("balance.surge.duration_s")
	_m.emit("first_surge")
	_m.record.win(_m.t)
	var wave: Dictionary = _d.tables["balance"]["surge"]["wave"]
	if _m.owned.has(str(wave["unlock"])):
		zone().boost(float(wave["hexes"]) * _m.rates.stat("tend"), float(wave["burst_pts"]))


func _clean() -> bool:
	var z: PaceSimRdDistrict = zone()
	var kind: String = z.bottleneck(usable_kinds(z))
	if kind == "":
		return false
	var units: float = _clear(z, kind, _m.rates.throughput(kind) * _surge_mult() * PaceSimRdModel.TICK_S)
	_hand_output(z, kind, units)
	return true


## Pays for and records `units` of a kind cleared by Lumi's own hands.
func _hand_output(z: PaceSimRdDistrict, kind: String, units: float) -> void:
	var row: Dictionary = _d.kinds[kind]
	_m.pay(units * _m.rates.unit_value(kind))
	_m.gain_parts(units * _m.rates.unit_parts(kind))
	_m.hand_units += units
	_m.hand_hexes += units / z.hex_work
	z.hand_units += units
	if bool(row.get("loads", false)):
		_load_acc += units / _m.rates.capacity()
		if _load_acc >= 1.0:
			if _m.rates.has_baler():
				_m.bump("bales", floor(_load_acc))
				if _m.record.first_bale_value <= 0.0:
					_m.record.first_bale_value = _m.rates.capacity() * _m.rates.unit_value(kind)
			_load_acc = fmod(_load_acc, 1.0)
			_m.emit("first_payout")
			_m.record.win(_m.t)
	else:
		_batch_acc[kind] = _batch_acc.get(kind, 0.0) + units / float(row.get("batch", 1.0))
		if _batch_acc[kind] >= 1.0:
			_batch_acc[kind] = fmod(_batch_acc[kind], 1.0)
			_m.record.win(_m.t)
	_gain_mastery(kind, units * float(row.get("mastery_per_unit", 1.0)))


func _gain_mastery(kind: String, amount: float) -> void:
	if not _m.owned.has(str(_d.tables["balance"]["mastery"]["unlock"])):
		return
	_m.mastery_units[kind] += amount
	while _m.mastery[kind] < int(_d.num("balance.mastery.max_level")) and _m.mastery_units[kind] >= _d.mastery_units(kind, _m.mastery[kind] + 1):
		_m.mastery[kind] += 1
		_m.counters["mastery_" + kind] = float(_m.mastery[kind])
		_m.emit("first_mastery")
		_m.emit("mastery:%s:%d" % [kind, _m.mastery[kind]])
		_m.record.district_goal(_m.t, "mastery:%s:%d" % [kind, _m.mastery[kind]])
		_m.record.win(_m.t)
		_m.add_data(_d.num("research.data_rewards.mastery_level"))
		_m.items_dirty = true


func _plant() -> bool:
	var used: float = _plant_in(zone(), _m.rates.plant_rate() * PaceSimRdModel.TICK_S)
	if used > 0.0:
		_m.emit("first_plant")
		_stage_reward(zone(), PaceSimRdDistrict.PLANTED, used)
	return used > 0.0


func _water(only_dry: bool) -> bool:
	var regrowth: Dictionary = _d.tables["regrowth"]
	var used: float = zone().water(_m.rates.water_rate() * PaceSimRdModel.TICK_S, _m.t, float(regrowth["burst_pts"]),
		float(regrowth["wet_s"]), float(regrowth["rewater_s"]), only_dry)
	if used > 0.0:
		_m.record.win(_m.t)
	return used > 0.0


## Plants up to `n` hexes of a district with the seeds on hand; returns hexes planted.
func _plant_in(z: PaceSimRdDistrict, n: float) -> float:
	var per_hex: float = _d.num("regrowth.seeds.per_hex")
	var used: float = z.plant(minf(n, _m.seeds / per_hex))
	_m.seeds -= used * per_hex
	_m.seeds_planted += used * per_hex
	return used


## The source job: walk in, clear its surroundings by hand, then the hands-on action.
func _source() -> bool:
	var z: PaceSimRdDistrict = zone()
	var src: Dictionary = z.row["source"]
	if z.source_step == 0:
		z.source_step = 1
		z.source_left = float(src["clear_hexes"]) * z.hex_work + z.source_extra
		_m.busy_s += float(src["reach_s"])
		_source_step_done(z, 1)
		return false
	if z.source_step == 1:
		var kind: String = _best_kind(z)
		var units: float = minf(z.source_left, _m.rates.throughput(kind) * _surge_mult() * PaceSimRdModel.TICK_S)
		z.source_left -= units
		_hand_output(z, kind, units)
		if z.source_left <= 0.001:
			z.source_step = 2
			_source_step_done(z, 2)
		return true
	_m.busy_s += float(src["action_s"])
	z.source_step = 3
	z.source_at = _m.t
	_source_step_done(z, 3)
	_m.emit("source_shut:" + z.id)
	_m.gain_parts(float(src["payout"]["parts"]))
	_m.add_data(float(src["payout"]["data"]))
	for id: Variant in src.get("grants", []):
		_m.grant(str(id))
	for row: Variant in _d.tables["finds"]["source"]:
		if str((row as Dictionary)["district"]) == z.id:
			_m.piece_found(str((row as Dictionary)["piece"]))
	return true


func _source_step_done(z: PaceSimRdDistrict, step: int) -> void:
	var id: String = "source_step:%s:%d" % [z.id, step]
	_m.emit(id)
	_m.record.district_goal(_m.t, id)
	_m.record.now_goal(_m.t)
	_m.record.win(_m.t)


## The usable kind of the district Lumi clears fastest (the waste round a source is a mix).
func _best_kind(z: PaceSimRdDistrict) -> String:
	var best: String = ""
	var best_rate: float = -1.0
	for kind: String in usable_kinds(z):
		var rate: float = _m.rates.throughput(kind)
		if rate > best_rate:
			best_rate = rate
			best = kind
	return best


func _explore() -> void:
	var find: Dictionary = wreck_here(zone())
	if find.is_empty():
		return
	_m.busy_s += float(find["explore_s"])
	_m.piece_found(str(find["piece"]))


func _travel(to: int) -> void:
	if to < 0 or to >= _m.unlocked or to == _m.here:
		return
	var z: PaceSimRdDistrict = _m.zones[to]
	_m.here = to
	if z.entered_at < 0.0:
		z.entered_at = _m.t
		if _m.record.d1_hand_hexes <= 0.0:
			_m.record.d1_parts = _m.parts_earned
			_m.record.d1_hand_hexes = _m.hand_hexes
		_m.busy_s += float(z.row["arrival_s"])
		_m.emit("enter:" + z.id)
		_m.record.win(_m.t)
	else:
		_m.busy_s += _d.num("districts.hop_s")
	_m.rig_dirty = true
	_m.rates.dirty = true


## Robots clear waste and earn nothing: no cubes, no Parts.
func _crew_clean(type: String, row: Dictionary, n: float) -> void:
	var allowed: Array[String] = []
	for kind: Variant in row.get("kinds", []):
		if _m.mastery.get(str(kind), 0) >= int(_d.num("robots.mastery_speed.min_level")) and _has_seeds_for(str(kind)):
			allowed.append(str(kind))
	if allowed.is_empty():
		return
	var z: PaceSimRdDistrict = _crew_zone(allowed)
	if z == null:
		return
	var kind: String = z.bottleneck(allowed)
	var near: bool = z.index == _m.here
	var units: float = _clear(z, kind, n * _m.rates.robot_rate(type, kind, z, near) * PaceSimRdModel.TICK_S)
	_m.crew_units += units
	_m.crew_hexes += units / z.hex_work
	z.crew_units += units


## Where a crew works: Lumi's district if it has work for them, else the oldest district that does.
func _crew_zone(allowed: Array[String]) -> PaceSimRdDistrict:
	if zone().bottleneck(allowed) != "":
		return zone()
	for z: PaceSimRdDistrict in _m.zones:
		if z.index < _m.unlocked and z.entered_at >= 0.0 and z.bottleneck(allowed) != "":
			return z
	return null


## Tender robots plant or water whole hexes, oldest district first, dry hexes before wet ones.
func _crew_tend(type: String, field: String, n: float) -> void:
	if not tending_open():
		return
	var key: String = type + field
	var regrowth: Dictionary = _d.tables["regrowth"]
	var budget: float = _tend_acc.get(key, 0.0) + float(_d.robot_types[type][field]) * n * _m.rates.tier_mult(type) * _m.rates.stat("crew_rate")
	for z: PaceSimRdDistrict in _m.zones:
		if budget < 1.0 or z.index >= _m.unlocked:
			break
		if field == "plant_rate":
			var planted: float = _plant_in(z, floor(budget))
			budget -= planted
			if planted > 0.0:
				_stage_reward(z, PaceSimRdDistrict.PLANTED, planted)
		else:
			for only_dry: bool in [true, false]:
				budget -= z.water(floor(budget), _m.t, float(regrowth["burst_pts"]), float(regrowth["wet_s"]), float(regrowth["rewater_s"]), only_dry)
	_tend_acc[key] = minf(budget, 1.0 + float(_d.robot_types[type][field]) * n)
