class_name YardBuilds
extends RefCounted
## [camp] Things built into the yard from the Hub tab (ui/yard_builds_panel.gd): the lean-to,
## generator, yard lamps, compost press, CD player and robot nursery. Nothing here exists on a fresh base. Data: data/camp.json "builds".
## State (per district): GameState.world["camp"] = {"bench": bool (repaired), "built": {id: true}}.

const PATH: String = "res://data/camp.json"
const IDS: Array[String] = ["shack", "generator", "lamps", "composter", "radio", "nursery"]  # [camp2]

static var _cfg: Dictionary = {}
static var events: YardEvents = YardEvents.new()


class YardEvents:
	extends RefCounted
	@warning_ignore("unused_signal")
	signal built(id: String)


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(PATH)
	return _cfg


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
	return bool((state()["built"] as Dictionary).get(id, false))


static func mark_built(id: String) -> void:
	(state()["built"] as Dictionary)[id] = true


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
	if hub_level < req:
		return TranslationServer.translate("Requires hub level %d.") % req
	var flag: String = str(d.get("requires_flag", ""))
	if flag != "" and not bool(GameState.flags.get(flag, false)):
		return TranslationServer.translate("Grow your first seed first.") if flag == "first_sprout" else TranslationServer.translate("Not yet.")
	if not Hub.can_pay(d.get("cost", {})):
		return TranslationServer.translate("Not enough materials.")
	return ""


## True while it's worth listing in the Hub tab (built, or its flag is met: no spoilers before).
static func listed(id: String) -> bool:
	var flag: String = str(def(id).get("requires_flag", ""))
	return built(id) or flag == "" or bool(GameState.flags.get(flag, false))


static func build(id: String, hub_level: int) -> bool:
	if block_reason(id, hub_level) != "" or not Hub.pay(def(id).get("cost", {})):
		return false
	mark_built(id)
	GameState.inc_stat("yard_builds")
	events.built.emit(id)
	return true
