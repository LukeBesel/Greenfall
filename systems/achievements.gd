class_name Achievements
extends Node
## Achievements (data/achievements.json) checked against GameState.stats / flags, research and the
## codex. Unlocks persist in GameState.flags["achievements"] = {id: unix_time}. The live node
## (added by the slice) also keeps a few extra lifetime stats (hexes_restored) and scans the codex.

const PATH: String = "res://data/achievements.json"

static var _defs: Array = []

var world: Node
var _t: float = 0.0
## Ignore toasts for unlocks found on the first check after loading (old saves catching up).
var _first: bool = true


static func defs() -> Array:
	if _defs.is_empty():
		_defs = Economy.read_json(PATH).get("achievements", [])
	return _defs


static func def(id: String) -> Dictionary:
	for a: Dictionary in defs():
		if str(a["id"]) == id:
			return a
	return {}


static func unlocked_map() -> Dictionary:
	var v: Variant = GameState.flags.get("achievements")
	if not (v is Dictionary):
		v = {}
		GameState.flags["achievements"] = v
	return v


static func is_unlocked(id: String) -> bool:
	var v: Variant = GameState.flags.get("achievements")
	return v is Dictionary and (v as Dictionary).has(id)


static func unlocked_count() -> int:
	return unlocked_map().size()


static func best_hub_level() -> int:
	var best: int = int(GameState.world.get("hub_level", 1))
	for k: Variant in GameState.districts:
		var d: Variant = GameState.districts[k]
		if d is Dictionary:
			best = maxi(best, int((d as Dictionary).get("hub_level", 1)))
	return best


## Current value of an achievement condition (compare with cond.target).
static func value_of(cond: Dictionary) -> float:
	var key: String = str(cond.get("key", ""))
	match str(cond.get("type", "")):
		"stat":
			var v: Variant = GameState.stats.get(key, 0.0)
			return float(v) if (v is float or v is int) else 0.0
		"junk_kg":
			return Codex.junk_kg(key if key != "" else "*")
		"cubes_earned":
			return BigNum.from_serialized(GameState.stats.get("cubes_earned_total", [0.0, 0])).to_float()
		"flag":
			return 1.0 if GameState.flags.get(key, false) else 0.0
		"research":
			return float(Research.done_list().size())
		"research_id":
			return 1.0 if Research.has(key) else 0.0
		"codex":
			return float(Codex.count(key if key != "" else "*"))
		"hub_level":
			return float(best_hub_level())
		"currency":
			return GameState.get_currency(key).to_float()
		"achievements":
			return float(unlocked_count())
		"list":
			var lv: Variant = GameState.flags.get(key, [])
			return float((lv as Array).size()) if lv is Array else 0.0
	return 0.0


static func progress(id: String) -> float:
	var a: Dictionary = def(id)
	if a.is_empty():
		return 0.0
	if is_unlocked(id):
		return 1.0
	var c: Dictionary = a.get("cond", {})
	return clampf(value_of(c) / maxf(float(c.get("target", 1.0)), 0.0001), 0.0, 1.0)


static func met(a: Dictionary) -> bool:
	var c: Dictionary = a.get("cond", {})
	return value_of(c) >= float(c.get("target", 1.0)) - 0.000001


## Unlocks every achievement whose condition is now met. Returns the new ids.
static func check_all(now_unix: float = -1.0) -> Array[String]:
	var out: Array[String] = []
	var t: float = Time.get_unix_time_from_system() if now_unix < 0.0 else now_unix
	# Two passes so the "unlock N achievements" meta achievement can trigger in the same check.
	for _pass: int in 2:
		for a: Dictionary in defs():
			var id: String = str(a["id"])
			if is_unlocked(id) or not met(a):
				continue
			unlocked_map()[id] = t
			out.append(id)
			EventBus.achievement_unlocked.emit(id)
	return out


# --- Live node -------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.hex_restored.connect(func(_h: int) -> void: GameState.inc_stat("hexes_restored"))
	EventBus.research_completed.connect(func(_id: String) -> void: _t = 1.0)
	EventBus.hex_cleaned.connect(func(_h: int, _p: Vector3, _b: BigNum) -> void: _t = maxf(_t, 0.7))
	Designs.dev_hooks(world)  # [skins] --design / --designs-all / --design-unlock
	LumiStyle.dev_hooks(world)  # [style] --lumi-random / --lumi-set / --lumi-builder


func _process(delta: float) -> void:
	_t += delta
	if _t < 1.0:
		return
	_t = 0.0
	var found: Array[String] = Codex.scan(world)
	var got: Array[String] = check_all()
	Designs.check_unlocks(_first)  # [skins] Lumi's unlockable designs (quiet on the first check after loading)
	if _first:
		_first = false
		if got.size() > 3:
			EventBus.toast.emit(tr("%d achievements unlocked. See them in the Codex (K).") % got.size(), "story")
			Audio.play("chime", 1.0, -4.0)
			got.clear()
		if found.size() > 3:
			found.clear()
	for id: String in got:
		var a: Dictionary = def(id)
		EventBus.toast.emit(tr("Achievement: %s. %s") % [tr(str(a.get("name", id))), tr(str(a.get("desc", "")))], "story")
		Audio.play("chime", 1.0, -2.0)
	if SignalTower.tier() == 0 and not DevHooks.has("codex-toasts"):
		found.clear()  # [v3clear] owner item 41: no Codex chatter in the first minutes (the entries are still logged)
	if found.size() > 2:
		EventBus.toast.emit(tr("Codex: %d new entries.") % found.size(), "info")
	else:
		for k: String in found:
			EventBus.toast.emit(tr("Codex entry: %s") % tr(str(Codex.entry(k).get("name", k))), "reward")  # [v4calm] cut
