class_name WeeklyChallenge
extends RefCounted
## [extras] "Seed of the Week": a short challenge district that is the same for everyone. The ISO
## week number (UTC) gives the planet seed, the world type and one twist (data/weekly.json); the
## goal is to clean `goal_hexes` hexes, timed in play time (pauses don't count). It reuses the
## normal district builder: CradleMode.world_seed / planet_mix / modifiers return the week's
## values while `active`, the run saves in its own slot (never the main save), and Fleet asks
## `robot_block` for the twist's robot rules. Best time and score per week, and the paint chips
## (one per week finished; they unlock the weekly decorations), live in weekly.save next to the
## Cradle profile, so they are per save profile and survive every world.

const PATH: String = "res://data/weekly.json"
const FILE: String = "weekly.save"

static var active: bool = false
## The record (weeks + chips). Loaded lazily; kept in memory only when CradleMode.persist is off.
static var record: Dictionary = {}
static var _loaded: bool = false
## Tests pin the clock.
static var now_override: float = -1.0
static var path_override: String = ""
static var _cfg: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(PATH)
	return _cfg


static func slot() -> int:
	return int(cfg().get("slot", 9))


static func now() -> float:
	return now_override if now_override >= 0.0 else Time.get_unix_time_from_system()


# --- The week (pure) --------------------------------------------------------------------

## ISO 8601 week of a unix time (UTC): Vector2i(year, week). Weeks start on Monday and week 1
## holds the year's first Thursday.
static func iso_week(unix: float) -> Vector2i:
	var days: int = int(floor(unix / 86400.0))
	var wd: int = posmod(days + 3, 7)  # 1970-01-01 was a Thursday; Monday = 0
	var thursday: int = days - wd + 3
	var year: int = int(Time.get_date_dict_from_unix_time(thursday * 86400)["year"])
	var jan1: int = int(Time.get_unix_time_from_datetime_dict({"year": year, "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0}) / 86400)
	return Vector2i(year, (thursday - jan1) / 7 + 1)


static func week_id(w: Vector2i = Vector2i.ZERO) -> String:
	if w == Vector2i.ZERO:
		w = iso_week(now())
	return "%d-W%02d" % [w.x, w.y]


## FNV-1a over the week id: the same number on every machine and Godot version.
static func _fnv(s: String) -> int:
	var h: int = 2166136261
	for b: int in s.to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return h


static func seed_for(id: String) -> int:
	return 20011 + (_fnv("greenfall_week_" + id) % 900000)


static func twist_for(w: Vector2i) -> Dictionary:
	var tw: Array = cfg().get("twists", [])
	if tw.is_empty():
		return {}
	return tw[posmod(w.x * 53 + w.y, tw.size())]


static func twist() -> Dictionary:
	return twist_for(iso_week(now()))


static func world_type_for(w: Vector2i) -> Dictionary:
	var types: Array = WorldGen.cfg().get("world_types", [])
	return types[posmod(w.x + w.y * 7, types.size())] if not types.is_empty() else {}


static func current_seed() -> int:
	return seed_for(week_id())


static func planet_mix() -> Dictionary:
	var w: Vector2i = iso_week(now())
	var mix: Dictionary = (world_type_for(w).get("mix", {}) as Dictionary).duplicate(true)
	var r := RandomNumberGenerator.new()
	r.seed = current_seed()
	mix["city_names"] = WorldGen.city_names(r)
	return mix


static func twist_modifiers() -> Array:
	return twist().get("modifiers", [])


## "" if this robot type may be built under this week's twist (always "" outside the challenge).
static func robot_block(type_id: String) -> String:
	if not active:
		return ""
	return robot_block_for(twist(), type_id)


static func robot_block_for(t: Dictionary, type_id: String) -> String:
	var only: Array = t.get("only", [])
	if (not only.is_empty() and not (type_id in only)) or type_id in (t.get("ban", []) as Array):
		return TranslationServer.translate("Not this week: %s") % TranslationServer.translate(str(t.get("name", "")))
	return ""


## Score for a finished (or running) challenge (pure).
static func score(hexes: int, blooms: int, cubes_earned: float, time_s: float, finished: bool) -> int:
	var sc: Dictionary = cfg().get("score", {})
	var v: float = float(sc.get("per_hex", 100)) * hexes + float(sc.get("per_bloom", 25)) * blooms \
		+ float(sc.get("per_100_cubes", 2)) * floorf(cubes_earned / 100.0)
	if finished:
		var lim: float = float(sc.get("time_bonus_s", 3600))
		v += float(sc.get("time_bonus_max", 1500)) * clampf((lim - time_s) / lim, 0.0, 1.0)
	return int(round(v))


static func goal_hexes() -> int:
	return int(cfg().get("goal_hexes", 30))


static func clock_text(s: float) -> String:
	var t: int = int(s)
	return "%d:%02d:%02d" % [t / 3600, (t / 60) % 60, t % 60] if t >= 3600 else "%d:%02d" % [t / 60, t % 60]


# --- Record (weekly.save) ---------------------------------------------------------------

static func file_path() -> String:
	return path_override if path_override != "" else SaveManager.save_dir().path_join(FILE)


static func rec() -> Dictionary:
	if not _loaded:
		_loaded = true
		record = {}
		if CradleMode.persist and FileAccess.file_exists(file_path()):
			record = SaveManager.read_dict(file_path())
	if not (record.get("weeks") is Dictionary):
		record["weeks"] = {}
	if not (record.get("chips") is Array):
		record["chips"] = []
	return record


static func save_record() -> bool:
	if not CradleMode.persist:
		return false
	DirAccess.make_dir_recursive_absolute(file_path().get_base_dir())
	return SaveManager.write_dict(file_path(), rec())


## Forget the in-memory record (a profile switch, tests).
static func reset_cache() -> void:
	_loaded = false
	record = {}


static func week_rec(id: String = "") -> Dictionary:
	var k: String = id if id != "" else week_id()
	var wk: Dictionary = rec()["weeks"]
	if not (wk.get(k) is Dictionary):
		wk[k] = {"best_time": 0.0, "best_score": 0, "runs": 0, "done": false}
	return wk[k]


static func chips() -> Array:
	return rec()["chips"]


static func chip_count() -> int:
	return chips().size()


## Records a finished run. Returns {best_time, best_score, new_time, new_score, chip} (chip = colour or "").
static func record_finish(time_s: float, sc: int) -> Dictionary:
	var w: Dictionary = week_rec()
	var out: Dictionary = {"new_time": false, "new_score": false, "chip": ""}
	if float(w.get("best_time", 0.0)) <= 0.0 or time_s < float(w["best_time"]):
		w["best_time"] = time_s
		out["new_time"] = true
	if sc > int(w.get("best_score", 0)):
		w["best_score"] = sc
		out["new_score"] = true
	if not bool(w.get("done", false)):
		w["done"] = true
		var cols: Array = cfg().get("chips", ["#e8a33d"])
		var col: String = str(cols[posmod(iso_week(now()).y, cols.size())])
		chips().append({"week": week_id(), "color": col, "twist": str(twist().get("id", ""))})
		out["chip"] = col
	out["best_time"] = float(w["best_time"])
	out["best_score"] = int(w["best_score"])
	save_record()
	return out


# --- Going there and back -----------------------------------------------------------------

## Is there a run of this week waiting in the challenge slot?
static func has_run() -> bool:
	var p: String = SaveManager.slot_path(slot())
	if not FileAccess.file_exists(p):
		return false
	var d: Dictionary = SaveManager.read_dict(p)
	return str((d.get("flags", {}) as Dictionary).get("weekly_id", "")) == week_id()


## The challenge's fresh GameState: the kit (robots filtered by the twist), basics researched,
## no intro or tutorial (Lumi knows the job), the meta flags carried over.
static func prepare_state() -> void:
	var carry: Dictionary = CradleMode._carry_flags()
	GameState.new_game()
	for k: String in carry:
		GameState.flags[k] = carry[k]
	var kit: Dictionary = cfg().get("kit", {})
	GameState.flags["intro_done"] = true
	GameState.flags["tutorial_step"] = 99
	GameState.flags["seeds_unlocked"] = true
	GameState.flags["weekly_id"] = week_id()
	GameState.flags["weekly_intro"] = true
	GameState.flags["weekly_t0"] = 0.0
	var bots: Array = []
	for t: Variant in kit.get("robots", []):
		var tid: String = str(t)
		if robot_block_for(twist(), tid) != "":
			tid = str((twist().get("only", ["scoopie"]) as Array)[0]) if not (twist().get("only", []) as Array).is_empty() else "scoopie"
		bots.append(tid)
	GameState.flags["weekly_kit_robots"] = bots
	GameState.add_currency("cubes", BigNum.from_float(float(kit.get("cubes", 1000))))
	GameState.add_currency("seeds", BigNum.from_float(float(kit.get("seeds", 10))))
	for rid: String in Research.ids():
		if int(Research.def(rid).get("tier", 0)) < 1:
			Research.grant(rid)


## Leaves the current world (saved first) for this week's challenge.
static func start(tree: SceneTree = null) -> bool:
	if active:
		return false
	if tree:
		SaveManager.save_game()
	active = true
	SaveManager.slot = slot()
	Economy.planet["name"] = TranslationServer.translate("Seed of the Week")
	if has_run() and SaveManager.load_game():
		pass
	else:
		prepare_state()
	week_rec()["runs"] = int(week_rec().get("runs", 0)) + 1
	save_record()
	GameState.reload_in_memory = true
	print("[weekly] %s seed=%d twist=%s slot=%d" % [week_id(), current_seed(), str(twist().get("id", "")), SaveManager.slot])
	CradleMode._change_scene(tree)
	return true


## Back to the world Lumi came from (the challenge is saved and can be resumed this week).
static func leave(tree: SceneTree = null) -> bool:
	if not active:
		return false
	if tree:
		SaveManager.save_game()
	active = false
	CradleMode.apply_current()
	if SaveManager.has_save() and SaveManager.load_game():
		pass
	else:
		GameState.new_game()
	GameState.reload_in_memory = true
	CradleMode._change_scene(tree)
	return true


## A fresh start of this week's run (the old run in the slot is dropped).
static func restart(tree: SceneTree = null) -> void:
	if active:
		SaveManager.delete_save(slot())
		prepare_state()
		GameState.reload_in_memory = true
		CradleMode._change_scene(tree)
	else:
		SaveManager.delete_save(slot())
		start(tree)
