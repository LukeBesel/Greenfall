class_name Looks
extends RefCounted
## The pieces Lumi's looks are made of (data/cosmetics.json; design spec section 13) and which of
## them the player has found. A piece can be worn only after it is found in the world: nothing is
## bought and nothing opens from a counter. A design is a set of pieces; collecting every piece of
## one completes the set.
##
## Found pieces are global progress: they live in the save's `global` section (GameState.global
## "pieces", in the order found) and stay with the player on every planet. Where pieces are hidden
## is planet data (systems/finds.gd reads the planet's `finds` table and calls grant()).
##
## Emits on EventBus: piece_found(piece_id, source) for every new piece, and
## set_completed(design_id) when the last piece of a set is found.

const PATH: String = "res://data/cosmetics.json"
const KEY: String = "pieces"
## The save flag set by the first found piece: the Locker is offered from then on.
const FIRST_FLAG: String = "first_piece"
const STAT_FOUND: String = "pieces_found"
## Owner: an unfound piece never shows its name or its look, only this and one hint line.
const UNFOUND_NAME: String = "???"
const DEFAULT_PRESETS: int = 3

static var _data: Dictionary = {}
static var _by_id: Dictionary = {}
## Dev (--lumi-parts-all, lineups): every piece counts as found for this run. Never saved.
static var dev_all: bool = false


# --- Data -------------------------------------------------------------------------------------

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_data = parsed
		for p: Dictionary in _data.get("pieces", []):
			_by_id[str(p["id"])] = p
	return _data


static func defs() -> Array:
	return data().get("pieces", [])


static func def(id: String) -> Dictionary:
	data()
	return _by_id.get(id, {})


static func exists(id: String) -> bool:
	return not def(id).is_empty()


static func ids() -> Array[String]:
	var out: Array[String] = []
	for p: Dictionary in defs():
		out.append(str(p["id"]))
	return out


## The Locker's slots in display order: {id, name, hint}.
static func slot_defs() -> Array:
	return data().get("slots", [])


static func slot_def(slot: String) -> Dictionary:
	for s: Dictionary in slot_defs():
		if str(s["id"]) == slot:
			return s
	return {}


static func slot_ids() -> Array[String]:
	var out: Array[String] = []
	for s: Dictionary in slot_defs():
		out.append(str(s["id"]))
	return out


## How many saved looks the Locker keeps.
static func preset_count() -> int:
	return int(data().get("presets", DEFAULT_PRESETS))


static func slot_of(id: String) -> String:
	return str(def(id).get("slot", ""))


## The design this piece belongs to ("" for a loose piece).
static func set_of(id: String) -> String:
	return str(def(id).get("set", ""))


static func is_starter(id: String) -> bool:
	return bool(def(id).get("starter", false))


## Every piece of a slot, in data order.
static func of_slot(slot: String) -> Array[String]:
	var out: Array[String] = []
	for p: Dictionary in defs():
		if str(p["slot"]) == slot:
			out.append(str(p["id"]))
	return out


## The pieces that make up a design.
static func set_ids(design: String) -> Array[String]:
	var out: Array[String] = []
	if design == "":
		return out
	for p: Dictionary in defs():
		if str(p.get("set", "")) == design:
			out.append(str(p["id"]))
	return out


## The piece of `slot` that carries this option / swatch / design ("" when none does).
static func piece_for(slot: String, field: String, value: String) -> String:
	for p: Dictionary in defs():
		if str(p["slot"]) == slot and str(p.get(field, "")) == value:
			return str(p["id"])
	return ""


## The English name; whoever shows it passes it through tr().
static func name_of(id: String) -> String:
	return str(def(id).get("name", id))


## Name for the player: the piece's name once found, "???" before.
static func display_name(id: String) -> String:
	return TranslationServer.translate(name_of(id) if has(id) else UNFOUND_NAME)


## One general line about where this kind of thing turns up (the piece's own, else its slot's),
## in English. Where a planet hides the piece is that planet's to say: Finds.hint_for.
static func hint(id: String) -> String:
	var own: String = str(def(id).get("hint", ""))
	return own if own != "" else str(slot_def(slot_of(id)).get("hint", ""))


# --- State ------------------------------------------------------------------------------------

## The found pieces, in the order found (starters are not listed: they are always held).
static func found() -> Array:
	var v: Variant = GameState.global.get(KEY)
	if not (v is Array):
		v = []
		GameState.global[KEY] = v
	return v


static func has(id: String) -> bool:
	if not exists(id):
		return false
	return dev_all or is_starter(id) or id in found()


## How many pieces the player has found (starters do not count).
static func found_count() -> int:
	var n: int = 0
	for id: Variant in found():
		if exists(str(id)):
			n += 1
	return n


## [have, total] pieces of a design.
static func set_progress(design: String) -> Array[int]:
	var have: int = 0
	var all: Array[String] = set_ids(design)
	for id: String in all:
		if has(id):
			have += 1
	return [have, all.size()]


static func set_collected(design: String) -> bool:
	var p: Array[int] = set_progress(design)
	return p[1] > 0 and p[0] == p[1]


## The player found a piece. Returns false when it is unknown or already held. `source` says how
## it was found ("buried", "wreck", "source", "secret", ...): presentation may word the moment
## by it. quiet: keep the piece but raise no event (old saves, dev).
static func grant(id: String, source: String = "", quiet: bool = false) -> bool:
	if not exists(id) or is_starter(id) or id in found():
		return false
	var design: String = set_of(id)
	var was_complete: bool = design != "" and set_collected(design)
	found().append(id)
	if quiet:
		return true
	GameState.flags[FIRST_FLAG] = true
	GameState.inc_stat(STAT_FOUND)
	EventBus.piece_found.emit(id, source)
	if design != "" and not was_complete and set_collected(design):
		EventBus.set_completed.emit(design)
	return true


# --- Old saves --------------------------------------------------------------------------------

## Save migration (v4 -> v5): looks used to open from counters, levels, achievements and prices.
## A save from then keeps what it had, as found pieces: every piece of each design it had
## unlocked, every piece whose old rule (the piece's `legacy`) it had met, and whatever its worn
## look and saved looks are made of. Pure: works on the save dictionary alone.
static func migrate_save(d: Dictionary) -> Dictionary:
	var flags: Dictionary = d.get("flags", {}) if d.get("flags") is Dictionary else {}
	var global: Dictionary = d.get("global", {}) if d.get("global") is Dictionary else {}
	var have: Array = global.get(KEY, []) if global.get(KEY) is Array else []
	var skins: Array = flags.get("skins_unlocked", []) if flags.get("skins_unlocked") is Array else []
	for p: Dictionary in defs():
		var id: String = str(p["id"])
		if bool(p.get("starter", false)) or id in have:
			continue
		if str(p.get("set", "")) in skins or _legacy_met(p.get("legacy", {}), d):
			have.append(id)
	for id: String in LumiStyle.pieces_in_save(flags):
		if exists(id) and not is_starter(id) and not (id in have):
			have.append(id)
	global[KEY] = have
	d["global"] = global
	if not have.is_empty():
		flags[FIRST_FLAG] = true
	for old: String in ["skins_unlocked", "style_bought"]:
		flags.erase(old)
	d["flags"] = flags
	return d


static func _legacy_met(rule: Variant, d: Dictionary) -> bool:
	if not (rule is Dictionary) or (rule as Dictionary).is_empty():
		return false
	var r: Dictionary = rule
	var flags: Dictionary = d.get("flags", {}) if d.get("flags") is Dictionary else {}
	if bool(r.get("free", false)):
		return true
	if r.has("lumi_level"):
		var lumi: Variant = flags.get("lumi")
		return lumi is Dictionary and int((lumi as Dictionary).get("level", 1)) >= int(r["lumi_level"])
	if r.has("achievement"):
		var ach: Variant = flags.get("achievements")
		return ach is Dictionary and (ach as Dictionary).has(str(r["achievement"]))
	if r.has("stat"):
		var stats: Dictionary = d.get("stats", {}) if d.get("stats") is Dictionary else {}
		var v: Variant = stats.get(str(r["stat"]), 0.0)
		return (v is float or v is int) and float(v) >= float(r.get("target", 1.0))
	if r.has("hub_level"):
		return _best_hub_level(d) >= int(r["hub_level"])
	if r.has("bought"):
		var bought: Variant = flags.get("style_bought")
		return bought is Array and str(r["bought"]) in (bought as Array)
	return false


## The highest base level anywhere in a save: the flat districts and the globe's hub sites.
static func _best_hub_level(d: Dictionary) -> int:
	var best: int = 1
	var worlds: Array = [d.get("world", {})]
	if d.get("districts") is Dictionary:
		worlds.append_array((d["districts"] as Dictionary).values())
	var orbit: Variant = d.get("orbit")
	if orbit is Dictionary:
		var hubs: Variant = (orbit as Dictionary).get("hubs")
		if hubs is Dictionary:
			worlds.append_array((hubs as Dictionary).values())
	for w: Variant in worlds:
		if w is Dictionary:
			best = maxi(best, maxi(int((w as Dictionary).get("hub_level", 1)), int((w as Dictionary).get("level", 1))))
	return best
