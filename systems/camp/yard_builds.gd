class_name YardBuilds
extends RefCounted
## [camp] Things built into the yard from the Hub tab (ui/yard_builds_panel.gd): the lean-to,
## generator, yard lamps, compost press, CD player and robot nursery. Nothing here exists on a fresh base. Data: data/camp.json "builds".
## State (per district): GameState.world["camp"] = {"bench": bool (repaired), "built": {id: true}}.

const TABLE: String = "yard"
const IDS: Array[String] = ["shack", "generator", "lamps", "composter", "radio", "locker", "camera_bot", "nursery"]  # [camp2] [ui6] [camp3]

static var _cfg: Dictionary = {}
static var events: YardEvents = YardEvents.new()


class YardEvents:
	extends RefCounted
	@warning_ignore("unused_signal")
	signal built(id: String)


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.planet_table(TABLE)
		Economy.drop_on_planet_change(_drop_planet_cache)
	return _cfg



static func _drop_planet_cache() -> void:
	_cfg = {}


static func def(id: String) -> Dictionary:
	return (cfg().get("builds", {}) as Dictionary).get(id, {})


static func state() -> Dictionary:
	var v: Variant = GameState.world.get("camp")
	if not (v is Dictionary):
		v = {}
		GameState.world["camp"] = v
	var d: Dictionary = v
	if not (d.get("built") is Dictionary):
		d["built"] = {}
	return d


static func built(id: String) -> bool:
	if bool(def(id).get("global", false)):  # [camp3] one build for the whole game (the camera bot)
		return bool(_global().get(id, false))
	return bool((state()["built"] as Dictionary).get(id, false))


static func mark_built(id: String) -> void:
	if bool(def(id).get("global", false)):  # [camp3]
		_global()[id] = true
		return
	(state()["built"] as Dictionary)[id] = true


static func _global() -> Dictionary:
	if not (GameState.flags.get("yard_global") is Dictionary):
		GameState.flags["yard_global"] = {}
	return GameState.flags["yard_global"]


## [camp3] Whether a build's unlock condition (hub level, or play time for or_played_s) holds.
static func unlocked(id: String, hub_level: int) -> bool:
	var d: Dictionary = def(id)
	var flag: String = str(d.get("requires_flag", ""))
	if flag != "" and not bool(GameState.flags.get(flag, false)):
		return false
	if hub_level >= int(d.get("requires_level", 1)):
		return true
	return d.has("or_played_s") and float(GameState.stats.get("time_played", 0.0)) >= float(d["or_played_s"])


static func pos(id: String, fallback: Vector3) -> Vector3:
	var p: Array = def(id).get("pos", [])
	return Vector3(float(p[0]), 0.0, float(p[1])) if p.size() >= 2 else fallback


static func block_reason(id: String, hub_level: int) -> String:
	var d: Dictionary = def(id)
	if d.is_empty():
		return "?"
	if built(id):
		return TranslationServer.translate("Built.")
	if bool(d.get("requires_bench", false)) and not Camp.bench_ok():
		return TranslationServer.translate("Repair the workbench first.")
	var req: int = int(d.get("requires_level", 1))
	if hub_level < req and not unlocked(id, hub_level):
		return TranslationServer.translate("Requires hub level %d.") % req
	var flag: String = str(d.get("requires_flag", ""))
	if flag != "" and not bool(GameState.flags.get(flag, false)):
		return TranslationServer.translate("Grow your first seed first.") if flag == "first_sprout" else TranslationServer.translate("Not yet.")
	if not Hub.can_pay(d.get("cost", {})):
		return TranslationServer.translate("Not enough materials.")
	return ""


## True while it's worth listing in the Hub tab (built, or its flag is met: no spoilers before).
static func listed(id: String, hub_level: int = -1) -> bool:
	var flag: String = str(def(id).get("requires_flag", ""))
	if bool(def(id).get("hidden_until_unlocked", false)) and not built(id):  # [camp3]
		return unlocked(id, hub_level if hub_level >= 0 else int(GameState.world.get("hub_level", 1)))
	return built(id) or flag == "" or bool(GameState.flags.get(flag, false))


static func build(id: String, hub_level: int) -> bool:
	if block_reason(id, hub_level) != "" or not Hub.pay(def(id).get("cost", {})):
		return false
	mark_built(id)
	GameState.inc_stat("yard_builds")
	events.built.emit(id)
	return true
