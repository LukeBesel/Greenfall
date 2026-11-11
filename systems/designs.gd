class_name Designs
extends RefCounted
## Lumi's six designs (data/designs.json): Aurora (the starting one), Bolt, Sprout, Pixel, Nova,
## Patch. A design is a set of pieces (systems/looks.gd): the player wears it by finding its
## pieces in the world. Nothing here unlocks from a counter. The looks live in
## PatchModel.VARIANTS; this owns the gameplay side: the set's small themed bonus, which applies
## only while every piece of the set is worn, and the "looks only" switch.
## State (GameState.flags): patch_skin (the base design of the worn look: its paint set),
## look_set (the complete set being worn, "" for a mixed look), designs_looks_only (no bonuses).

const PATH: String = "res://data/designs.json"
const DEFAULT: String = "aurora"
const SET_FLAG: String = "look_set"

static var _defs: Array = []
static var _by_id: Dictionary = {}


static func defs() -> Array:
	if _defs.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_defs = (parsed as Dictionary).get("designs", [])
		for e: Dictionary in _defs:
			_by_id[str(e["id"])] = e
	return _defs


static func def(id: String) -> Dictionary:
	defs()
	return _by_id.get(id, {})


static func ids() -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in defs():
		out.append(str(e["id"]))
	return out


## The English name; whoever shows it passes it through tr().
static func name_of(id: String) -> String:
	return str(def(id).get("name", id))


# --- State ------------------------------------------------------------------------------------

## The base design of the worn look: the design whose paint set Lumi wears (Aurora for unknown
## ids). The model builds from it; it says nothing about the bonus.
static func current() -> String:
	var id: String = str(GameState.flags.get("patch_skin", DEFAULT))
	return id if not def(id).is_empty() else DEFAULT


## Every piece of the design has been found.
static func is_collected(id: String) -> bool:
	return Looks.set_collected(id)


## The design's paint set has been found, so a look may be built on it.
static func has_base(id: String) -> bool:
	return Looks.has(Looks.piece_for("paint", "design", id))


## Make `id` the base design of the worn look. Returns false when its paint set is not found.
static func select(id: String) -> bool:
	if def(id).is_empty() or not has_base(id):
		return false
	GameState.flags["patch_skin"] = id
	return true


## The complete set Lumi is wearing ("" for a mixed look). Kept in a flag so the stat code does
## not match pieces on every read; LumiStyle rewrites it whenever the worn look changes.
static func worn_set() -> String:
	if not GameState.flags.has(SET_FLAG):
		GameState.flags[SET_FLAG] = LumiStyle.worn_set(LumiStyle.current())
	var id: String = str(GameState.flags[SET_FLAG])
	return id if not def(id).is_empty() else ""


static func looks_only() -> bool:
	return bool(GameState.flags.get("designs_looks_only", false))


static func set_looks_only(on: bool) -> void:
	GameState.flags["designs_looks_only"] = on


# --- Bonus ------------------------------------------------------------------------------------

static func buff(id: String) -> Dictionary:
	return def(id).get("buff", {})


static func buff_text(id: String) -> String:
	return TranslationServer.translate(str(buff(id).get("text", "")))


## Multiplier the worn set adds to a stat (1.0 for a mixed look, a stat it does not touch, or
## with looks only on).
static func mult(stat_id: String) -> float:
	if looks_only():
		return 1.0
	var worn: String = worn_set()
	if worn == "":
		return 1.0
	var b: Dictionary = buff(worn)
	var s: String = str(b.get("stat", ""))
	if s == "":
		return 1.0
	if s == stat_id or (s.begins_with("*.") and stat_id.ends_with(s.substr(1))):
		return 1.0 + float(b.get("amount", 0.0))
	return 1.0


static func apply(stat_id: String, value: float) -> float:
	var m: float = mult(stat_id)
	return value * m if m != 1.0 else value


## Breakdown row for the stat tooltip ([] when the worn set does not touch the stat).
static func breakdown(stat_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var m: float = mult(stat_id)
	if m != 1.0:
		out.append({"source": TranslationServer.translate("Set: %s") % TranslationServer.translate(name_of(worn_set())), "text": "x%.2f" % m})
	return out


# --- Dev hooks (screenshots) --------------------------------------------------------------------
##   --design=ID        find every piece of a design and wear the set
##   --designs-all      find every piece of every design
##   --pieces=ID,ID     hold these pieces from the start (no found moment)
##   --piece-find=ID    find one piece after --piece-find-at=S seconds (default 4): the found moment
static func dev_hooks(world: Node) -> void:
	if DevHooks.has("designs-all"):
		for id: String in ids():
			_dev_collect(id)
	for held: String in DevHooks.get_s("pieces", "").split(",", false):
		Looks.grant(held, "", true)
	var want: String = DevHooks.get_s("design", "")
	if want != "" and not def(want).is_empty():
		_dev_collect(want)
		LumiStyle.set_current(LumiStyle.with_set(LumiStyle.current(), want))
		LumiStyle.refresh_player(world)
	var piece: String = DevHooks.get_s("piece-find", "")
	if piece != "" and Looks.exists(piece) and world:
		var grant := func() -> void: Looks.grant(piece, "buried")
		world.get_tree().create_timer(DevHooks.get_f("piece-find-at", 4.0)).timeout.connect(grant)


static func _dev_collect(id: String) -> void:
	for piece: String in Looks.set_ids(id):
		Looks.grant(piece, "", true)
