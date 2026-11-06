class_name Collection
extends RefCounted
## The Collection: trinkets and curios (data/events.json "trinkets") found through world events,
## contracts, streaks and Curio Capsules from the token shop. Found ids persist in
## GameState.flags["trinkets"] (an Array, in the order found). Shown in the Codex "Collection" tab.

const PATH: String = "res://data/events.json"

static var _defs: Array = []


static func defs() -> Array:
	if _defs.is_empty():
		_defs = Economy.read_json(PATH).get("trinkets", [])
	return _defs


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
		EventBus.toast.emit("New for your Collection: %s. See it in the Codex (K)." % str(def(id).get("name", id)), "story")
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
		"supply_drop": return "Supply Drops"
		"salvage_surge": return "Salvage Surges"
		"rain_shower": return "Rain Showers"
		"robot_hiccup": return "Robot Hiccups"
		"wildlife_visit": return "Wildlife Photos"
		"rare_part_signal": return "Rare Part Signals"
		"ledger_audit": return "Ledger Audits"
		"streak": return "Cleaning Streaks"
		"contracts": return "Contracts"
		"capsule": return "Curio Capsules"
	return source.capitalize()


## Display order of the sources on the Collection page.
static func sources() -> Array[String]:
	var out: Array[String] = []
	for t: Dictionary in defs():
		var s: String = str(t.get("source", ""))
		if not (s in out):
			out.append(s)
	return out
