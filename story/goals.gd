class_name Goals
extends Node
## The goal chain (data/goals.json): always a few next things to do, in an order that teaches
## clean -> bale -> upgrade -> robots -> command zones -> plant -> watering robots -> sustain ->
## base levels -> rocket. The first `visible` unfinished goals are current; a current goal whose
## condition holds completes (one per beat, so a backlog cascades), pays its reward and the next
## one slides in. Completed ids persist in GameState.flags["goals_done"].

signal completed(index: int)

const BEAT_S: float = 0.7

var world: Node
var cfg: Dictionary
var chain: Array = []
var visible_count: int = 3
var _done: Dictionary = {}
var _tick: float = 0.0


func _ready() -> void:
	load_chain()
	EventBus.junk_scooped.connect(func(_t: String, _p: Vector3) -> void: GameState.inc_stat("junk_scooped"))


func load_chain() -> void:
	cfg = Economy.read_json("res://data/goals.json")
	chain = cfg.get("goals", [])
	visible_count = int(cfg.get("visible", 3))
	_done.clear()
	for id: Variant in GameState.flags.get("goals_done", []):
		_done[str(id)] = true


func is_done(i: int) -> bool:
	return _done.has(str(chain[i]["id"]))


func done_count() -> int:
	var n: int = 0
	for g: Dictionary in chain:
		if _done.has(str(g["id"])):
			n += 1
	return n


## Chain indices of the current goals (first `visible_count` unfinished ones).
func current() -> Array[int]:
	var out: Array[int] = []
	for i: int in chain.size():
		if not is_done(i):
			out.append(i)
			if out.size() >= visible_count:
				break
	return out


func target_of(i: int) -> float:
	return float(chain[i].get("target", 1))


func value_of(i: int) -> float:
	var g: Dictionary = chain[i]
	var key: String = str(g.get("key", ""))
	match str(g.get("type", "stat")):
		"stat":
			var v: Variant = GameState.stats.get(key, 0.0)
			return float(v) if (v is float or v is int) else 0.0
		"earned":
			return BigNum.from_serialized(GameState.stats.get("cubes_earned_total", [0.0, 0])).to_float()
		"upgrade":
			return float(GameState.level_of(key))
		"robot":
			var fl: Node = world.get("fleet") if world else null
			if fl == null:
				return 0.0
			return float(fl.call("robots").size()) if key == "any" else float(fl.call("count", key))
		"tier":
			var best: int = 0
			for k: String in GameState.flags:
				if k.begins_with("tier_") and (key == "any" or k == "tier_" + key):
					best = maxi(best, int(GameState.flags[k]))
			return float(best)
		"zone":
			return float(zone_hex_count())
		"hub_level":
			return float(GameState.world.get("hub_level", 1))
		"hex_level":
			var hl: HexLevels = (world.get("hex_levels") as HexLevels) if world else null
			return float(hl.count_at_least(int(g.get("key", 1)))) if hl else 0.0
		"flag":
			return 1.0 if GameState.flags.get(key, false) else 0.0
		"districts":
			return float(GameState.districts.size())
		# [beat] late-game goals (frontiers, the Cradle)
		"research":
			return 1.0 if Research.has(key) else 0.0
		"bases_l5":
			return float(Frontiers.bases_at_level(5))
		"frontier_base":
			var fh: Dictionary = _frontier_hubs()
			return float(Frontiers.base_level(int(fh[key]))) if fh.has(key) else 0.0
		"frontier_growing":
			var fh2: Dictionary = _frontier_hubs()
			var worst: float = 1.0
			for fid: String in ["dust_flats", "frozen_port", "sunken_city"]:
				var hi: int = int(fh2.get(fid, -1))
				var gf: float = Frontiers.growing_frac(hi) if hi >= 0 else 0.0
				var fr: Variant = world.get("frontier") if world else null
				if hi == GameState.current_hub and fr is FrontierDistrict:
					gf = (fr as FrontierDistrict).growing_frac
				worst = minf(worst, gf)
			return worst
	return 0.0


## [beat] Frontier kind id -> hub index (empty before the planet is built).
func _frontier_hubs() -> Dictionary:
	var pl: Variant = world.get("planet") if world else null
	return (pl as PlanetData).frontier_hubs if pl is PlanetData else {}


## Distinct hexes painted into any Command zone (crew or single robot) in this district.
static func zone_hex_count() -> int:
	var o: Dictionary = GameState.world.get("orders", {})
	var seen: Dictionary = {}
	for kind: String in ["groups", "bots"]:
		var d: Dictionary = o.get(kind, {})
		for k: Variant in d:
			var ord: Variant = d[k]
			if ord is Dictionary:
				for h: Variant in (ord as Dictionary).get("zone", []):
					seen[int(h)] = true
	return seen.size()


func progress(i: int) -> float:
	return clampf(value_of(i) / maxf(target_of(i), 0.0001), 0.0, 1.0)


func reward_of(i: int) -> Dictionary:
	return chain[i].get("reward", {})


func _process(delta: float) -> void:
	_tick += delta
	if _tick >= BEAT_S:
		_tick = 0.0
		check()


## Completes at most one current goal whose condition holds. Returns its index or -1.
func check() -> int:
	for i: int in current():
		if value_of(i) >= target_of(i):
			complete(i)
			return i
	return -1


func complete(i: int) -> void:
	if is_done(i):
		return
	var id: String = str(chain[i]["id"])
	_done[id] = true
	var arr: Array = GameState.flags.get("goals_done", [])
	arr.append(id)
	GameState.flags["goals_done"] = arr
	var r: Dictionary = reward_of(i)
	for k: String in r:
		if float(r[k]) > 0.0:
			GameState.add_currency(k, BigNum.from_float(float(r[k])))
	GameState.inc_stat("goals_completed")
	Audio.play("coin", 1.15, -6.0)
	Audio.play("chime", 1.3, -10.0)
	completed.emit(i)
