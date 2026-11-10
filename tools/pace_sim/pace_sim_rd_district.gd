class_name PaceSimRdDistrict
extends RefCounted
## One district of the redesign model: how much of each pollution kind is cleared, how many hexes
## stand at each regrowth stage, the growing hexes as batches, and the source job.
## Stage numbers: 0 polluted, 1 clean, 2 planted, 3 growing, 4 sustained, 5 thriving.

const TOP_STAGE: int = 5
const PLANTED: int = 2
## Batches closer than this (growth points, seconds of wetness) are merged to keep the list short.
const MERGE_PTS: float = 4.0
const MERGE_S: float = 6.0
## Batch fields: hexes, stage, growth points, wet until, next burst allowed at.
const B_COUNT: int = 0
const B_STAGE: int = 1
const B_PTS: int = 2
const B_WET: int = 3
const B_BURST: int = 4

var row: Dictionary
var index: int = 0
var id: String = ""
var hexes: int = 0
var hex_work: float = 0.0
## Multiplier on the kinds' cube yields here (so one hex's waste is worth the district's hex_cubes
## by hand), the multiplier on the city's stage payouts, and the share of a robot's speed left
## after its trips to this city's base (robots.json distance).
var cube_scale: float = 1.0
var reward_mult: float = 1.0
var crew_reach: float = 1.0
## Buried parts in its cleaned ground that no Scrounger has dug up yet.
var buried_parts: float = 0.0
var mix: Dictionary[String, float] = {}
## Units cleared per kind, and hexes that have every kind cleared.
var done: Dictionary[String, float] = {}
var clean_hexes: int = 0
## Hexes at each stage 0..5.
var count: PackedFloat64Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var batches: Array[Array] = []
var stage: int = 0
var entered_at: float = -1.0
var stage_at: PackedFloat64Array = [0.0, -1.0, -1.0, -1.0, -1.0, -1.0]
## Source job: 0 not started, 1 reached (clearing), 2 cleared (action), 3 shut.
var source_step: int = 0
var source_left: float = 0.0
var source_extra: float = 0.0
var source_at: float = -1.0
## Work units by hand and by crew in this district, and the crew on site when it reached stage 4.
var hand_units: float = 0.0
var crew_units: float = 0.0
var crew_at_stage4: int = -1

var _stage_share: float = 0.8
## Growth points a hex needs to leave each stage, and the stage hexes stop at until the source is shut.
var _need: Array = []
var _cap_stage: int = 3


func _init(district_row: Dictionary, district_index: int, stage_share: float, need: Array, cap_stage: int) -> void:
	_need = need
	_cap_stage = cap_stage
	row = district_row
	index = district_index
	id = str(row["id"])
	hexes = PaceSimRdData.hexes_in(int(row["rings"]))
	hex_work = float(row["hex_work"])
	_stage_share = stage_share
	var kinds: Dictionary = row["mix"]
	for kind: String in kinds:
		mix[kind] = float(kinds[kind])
		done[kind] = 0.0
	count[0] = float(hexes)


func source_shut() -> bool:
	return source_step >= 3


## Units of `kind` still to clear in the district.
func remaining(kind: String) -> float:
	return float(hexes) * hex_work * mix[kind] - done[kind]


## How far a kind is through the district, 0..1.
func progress(kind: String) -> float:
	return done[kind] / (float(hexes) * hex_work * mix[kind])


## The kind furthest behind among `allowed` that still has work, or "".
func bottleneck(allowed: Array[String]) -> String:
	var best: String = ""
	var best_p: float = 2.0
	for kind: String in allowed:
		if not mix.has(kind) or remaining(kind) <= 0.001:
			continue
		var p: float = progress(kind)
		if p < best_p:
			best_p = p
			best = kind
	return best


## Clears up to `units` of `kind`; returns the units used.
func add_units(kind: String, units: float) -> float:
	var used: float = clampf(units, 0.0, remaining(kind))
	done[kind] += used
	return used


## Hexes that became clean since the last call (every kind cleared on them).
func take_new_clean() -> int:
	var lowest: float = 1.0
	for kind: String in mix:
		lowest = minf(lowest, progress(kind))
	var now_clean: int = int(floor(lowest * float(hexes) + 0.0001))
	var fresh: int = now_clean - clean_hexes
	if fresh > 0:
		clean_hexes = now_clean
		count[0] -= float(fresh)
		count[1] += float(fresh)
	return maxi(fresh, 0)


func clean_share() -> float:
	return float(clean_hexes) / float(hexes)


## Share of all the district's cleaning work that is done, 0..1. It rises steadily through a
## city, where the count of fully clean hexes waits on the kind that lags.
func work_share() -> float:
	var total: float = 0.0
	for kind: String in done:
		total += done[kind]
	return total / (float(hexes) * hex_work)


## Share of hexes at `at_stage` or above.
func share_at(at_stage: int) -> float:
	var n: float = 0.0
	for s: int in range(at_stage, TOP_STAGE + 1):
		n += count[s]
	return n / float(hexes)


## Plants up to `n` clean hexes; returns how many.
func plant(n: float) -> float:
	var used: float = minf(n, count[1])
	if used <= 0.0:
		return 0.0
	count[1] -= used
	count[PLANTED] += used
	if not batches.is_empty():
		var last: Array = batches[batches.size() - 1]
		if int(last[B_STAGE]) == PLANTED and float(last[B_PTS]) < MERGE_PTS and float(last[B_BURST]) <= 0.0:
			last[B_COUNT] = float(last[B_COUNT]) + used
			return used
	batches.append([used, PLANTED, 0.0, 0.0, 0.0])
	return used


## Hexes that can take a watering burst now (`only_dry`: only those not growing at full rate).
## Hexes held at the source's cap are left out.
func thirsty(t: float, only_dry: bool) -> float:
	var n: float = 0.0
	for b: Array in batches:
		if float(b[B_BURST]) <= t and not (only_dry and float(b[B_WET]) > t) and not _capped(b):
			n += float(b[B_COUNT])
	return n


## Waters up to `n` hexes, lowest stage first: a burst of growth now, full growth for `wet_s`.
## `only_dry` leaves hexes that are still wet alone.
func water(n: float, t: float, burst: float, wet_s: float, rewater_s: float, only_dry: bool) -> float:
	var left: float = n
	for s: int in range(PLANTED, TOP_STAGE):
		var i: int = 0
		while i < batches.size() and left > 0.0001:
			var b: Array = batches[i]
			i += 1
			if int(b[B_STAGE]) != s or float(b[B_BURST]) > t or (only_dry and float(b[B_WET]) > t) or _capped(b):
				continue
			if float(b[B_COUNT]) > left:
				b[B_COUNT] = float(b[B_COUNT]) - left
				batches.append([left, s, float(b[B_PTS]) + burst, t + wet_s, t + rewater_s])
				left = 0.0
			else:
				left -= float(b[B_COUNT])
				b[B_PTS] = float(b[B_PTS]) + burst
				b[B_WET] = t + wet_s
				b[B_BURST] = t + rewater_s
	return n - left


## Adds growth points to up to `n` hexes without wetting them (a Surge's wave).
func boost(n: float, pts: float) -> void:
	var left: float = n
	for b: Array in batches:
		if left <= 0.0:
			return
		if _capped(b):
			continue
		var share: float = minf(1.0, left / float(b[B_COUNT]))
		b[B_PTS] = float(b[B_PTS]) + pts * share
		left -= float(b[B_COUNT]) * share


## Grows every batch for `dt` seconds. Returns hexes promoted into each stage (index = stage).
func grow(dt: float, t: float, dry_rate: float) -> PackedFloat64Array:
	var promoted: PackedFloat64Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var i: int = 0
	while i < batches.size():
		var b: Array = batches[i]
		var s: int = int(b[B_STAGE])
		var pts: float = float(b[B_PTS]) + (1.0 if float(b[B_WET]) > t else dry_rate) * dt
		while s < TOP_STAGE and pts >= float(_need[s]) and (s < _cap_stage or source_shut()):
			pts -= float(_need[s])
			count[s] -= float(b[B_COUNT])
			s += 1
			count[s] += float(b[B_COUNT])
			promoted[s] += float(b[B_COUNT])
		if s < TOP_STAGE and pts > float(_need[s]):
			pts = float(_need[s])
		b[B_STAGE] = s
		b[B_PTS] = pts
		if s >= TOP_STAGE:
			batches.remove_at(i)
		else:
			i += 1
	return promoted


## Joins batches that are in the same state, so the list stays short.
func merge() -> void:
	var i: int = 0
	while i < batches.size():
		var a: Array = batches[i]
		var j: int = i + 1
		while j < batches.size():
			var b: Array = batches[j]
			if int(a[B_STAGE]) == int(b[B_STAGE]) and absf(float(a[B_PTS]) - float(b[B_PTS])) < MERGE_PTS \
					and absf(float(a[B_WET]) - float(b[B_WET])) < MERGE_S and absf(float(a[B_BURST]) - float(b[B_BURST])) < MERGE_S:
				a[B_COUNT] = float(a[B_COUNT]) + float(b[B_COUNT])
				batches.remove_at(j)
			else:
				j += 1
		i += 1


## The district's stage: the highest stage held by at least the stage share of its hexes.
func update_stage(t: float) -> bool:
	var now_stage: int = 0
	for s: int in range(1, TOP_STAGE + 1):
		if share_at(s) + 0.00001 >= _stage_share:
			now_stage = s
	if now_stage <= stage:
		return false
	for s: int in range(stage + 1, now_stage + 1):
		stage_at[s] = t
	stage = now_stage
	return true


## Restoration value 0..1 from the stage and the share toward the next one.
func value(stage_values: Array) -> float:
	var v: float = float(stage_values[stage])
	if stage < TOP_STAGE:
		v += (float(stage_values[stage + 1]) - v) * minf(1.0, share_at(stage + 1) / _stage_share)
	return v


## True for a batch that already holds all the growth it can until the source is shut.
func _capped(b: Array) -> bool:
	return int(b[B_STAGE]) >= _cap_stage and not source_shut() and float(b[B_PTS]) >= float(_need[int(b[B_STAGE])]) - 0.001
