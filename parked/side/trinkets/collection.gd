class_name Collection
extends RefCounted
## The Collection: trinkets and curios (data/events.json "trinkets") found through world events,
## contracts, streaks and Curio Capsules from the token shop. Found ids persist in
## GameState.flags["trinkets"] (an Array, in the order found). Shown in the Codex "Collection" tab.

const TABLE: String = "events"

static var _defs: Array = []


static func defs() -> Array:
	if _defs.is_empty():
		_defs = Economy.planet_table(TABLE).get("trinkets", [])
		Economy.drop_on_planet_change(_drop_planet_cache)
	return _defs



static func _drop_planet_cache() -> void:
	_defs = []


static func def(id: String) -> Dictionary:
	for t: Dictionary in defs():
		if str(t["id"]) == id:
			return t
	return {}


static func found_list() -> Array:
	var v: Variant = GameState.flags.get("trinkets")
	if not (v is Array):
		v = []
		GameState.flags["trinkets"] = v
	return v


static func has(id: String) -> bool:
	var v: Variant = GameState.flags.get("trinkets")
	return v is Array and id in (v as Array)


static func count() -> int:
	return found_list().size()


static func total() -> int:
	return defs().size()


## Adds a trinket (true if new). Announces it unless quiet.
static func grant(id: String, quiet: bool = false) -> bool:
	if has(id) or def(id).is_empty():
		return false
	found_list().append(id)
	GameState.inc_stat("trinkets_found")
	if not quiet:
		EventBus.toast.emit(TranslationServer.translate("New for your Collection: %s. See it in the Codex (K).") % TranslationServer.translate(str(def(id).get("name", id))), "reward")  # [v4calm] cut
		Audio.play("sparkle", 1.1, -6.0)
	return true


## Ids from a source ("supply_drop", "capsule", ...) not found yet.
static func unfound(source: String) -> Array[String]:
	var out: Array[String] = []
	for t: Dictionary in defs():
		if str(t.get("source", "")) == source and not has(str(t["id"])):
			out.append(str(t["id"]))
	return out


## A random unfound trinket from a source ("" when the source is complete).
static func roll(source: String, r: float) -> String:
	var opts: Array[String] = unfound(source)
	if opts.is_empty():
		return ""
	return opts[clampi(int(r * opts.size()), 0, opts.size() - 1)]


## Human label for where a trinket comes from (Collection page).
static func source_name(source: String) -> String:
	match source:
		"supply_drop": return TranslationServer.translate("Supply Drops")
		"salvage_surge": return TranslationServer.translate("Salvage Glints")
		"rain_shower": return TranslationServer.translate("Rain Showers")
		"robot_hiccup": return TranslationServer.translate("Robot Hiccups")
		"wildlife_visit": return TranslationServer.translate("Wildlife Photos")
		"animal_photos": return TranslationServer.translate("Animal Photos")  # [wild]
		"rare_part_signal": return TranslationServer.translate("Rare Part Signals")
		"ledger_audit": return TranslationServer.translate("Ledger Audits")
		"streak": return TranslationServer.translate("Cleaning Streaks")
		"lumi_level": return TranslationServer.translate("Lumi Levels")  # [hud]
		"contracts": return TranslationServer.translate("Requests")
		"capsule": return TranslationServer.translate("Curio Capsules")
	return source.capitalize()


## Display order of the sources on the Collection page.
static func sources() -> Array[String]:
	var out: Array[String] = []
	for t: Dictionary in defs():
		var s: String = str(t.get("source", ""))
		if not (s in out):
			out.append(s)
	return out
