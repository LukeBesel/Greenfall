class_name CrewLooks
extends RefCounted
## Glim's looks and the crew's looks follow Lumi's rule (design spec section 13): every look is a
## piece found in the world, worn only once found, edited only at the Locker. The pieces are in
## data/cosmetics.json under `targets` (glim, crew); which ones a player holds is the same global
## list as Lumi's (Looks.found), and a planet hides them in its `finds` table like any piece.
##
## A target slot names the field it edits by `key`: one of Glim's look slots (data/glim.json
## shells / glows / tops), a Robot Builder slot (data/robot_parts.json), LIVERY (a fleet mark)
## or GLOW (the robots' light colour). A piece names the look it stands for by `option`.
## "Stock" (no part, no mark, the robot's own light) needs no piece.

const GLIM: String = "glim"
const CREW: String = "crew"
const LIVERY: String = "livery"
const GLOW: String = "glow"
## The Glim state field that held looks bought in saves from before found pieces.
const OLD_GLIM_OWNED: String = "owned"


## The slot of a target that edits `key` ({} when none does).
static func slot_for(target: String, key: String) -> Dictionary:
	for s: Dictionary in Looks.target_slots(target):
		if str(s.get("key", "")) == key:
			return s
	return {}


## The piece that stands for `option` in the target's `key` slot ("" when none does).
static func piece(target: String, key: String, option: String) -> String:
	var s: Dictionary = slot_for(target, key)
	return Looks.piece_for(str(s["id"]), "option", option) if not s.is_empty() else ""


## May this look be worn: is its piece found (or a starting piece)?
static func has(target: String, key: String, option: String) -> bool:
	var id: String = piece(target, key, option)
	return id != "" and Looks.has(id)


## The pieces of the target's `key` slot, in data order.
static func pieces_of(target: String, key: String) -> Array[String]:
	var s: Dictionary = slot_for(target, key)
	return Looks.of_slot(str(s["id"])) if not s.is_empty() else ([] as Array[String])


static func option_of(piece_id: String) -> String:
	return str(Looks.def(piece_id).get("option", ""))


## A mark's or a light's own colour (`fallback` for pieces that have none).
static func color_of(piece_id: String, fallback: Color = Color.WHITE) -> Color:
	var c: String = str(Looks.def(piece_id).get("color", ""))
	return Color.html(c) if c != "" else fallback


## The colour a find shows (its tin, its chip, the light of the found moment): a Lumi piece's paint
## or light (a part of a set: its design's light), a mark's or a light's own colour, a Glim
## look's colour; `fallback` for other shapes.
static func tint_of(piece_id: String, fallback: Color = Color.WHITE) -> Color:
	var target: String = Looks.target_of(piece_id)
	if target == Looks.LUMI:
		var design: String = Looks.set_of(piece_id)
		if Looks.def(piece_id).has("option") and design != "":  # a part of a set: its design's light
			return PatchModel.glow_of(design)
		return LumiStyle.piece_tint(piece_id, fallback)
	if target == GLIM:
		var key: String = str(Looks.slot_def(Looks.slot_of(piece_id)).get("key", ""))
		var c: String = str(Glim.look(key, option_of(piece_id)).get("color", ""))
		return Color.html(c) if c != "" else fallback
	return color_of(piece_id, fallback)


## Whether a piece is a light colour (it turns up as a lens chip, not a paint tin).
static func is_light(piece_id: String) -> bool:
	var slot: String = Looks.slot_of(piece_id)
	return slot == LumiStyle.GLOW or bool(Looks.slot_def(slot).get("light", false))


## The pieces of a slot the Locker lists: found ones (and starters), then the ones the planet
## being played hides, as "???" with their hint. Pieces of other worlds are only counted.
## Returns {found: [ids], hidden: [ids], elsewhere: n}.
static func listing(target: String, key: String, def: PlanetDefinition) -> Dictionary:
	var here: Array[String] = Finds.pieces_for(def)
	var found: Array[String] = []
	var hidden: Array[String] = []
	var elsewhere: int = 0
	for id: String in pieces_of(target, key):
		if Looks.has(id):
			found.append(id)
		elif id in here:
			hidden.append(id)
		else:
			elsewhere += 1
	return {"found": found, "hidden": hidden, "elsewhere": elsewhere}


# --- Old saves --------------------------------------------------------------------------------

## Save migration (v5 -> v6): Glim's looks and the crew's parts, marks and lights used to be bought,
## won from the Requests track, or opened by a counter. A save from then keeps what it had as
## found pieces: every piece whose old rule (`legacy`) it met, and every look it wore. Pure: works
## on the save dictionary alone.
static func migrate_save(d: Dictionary) -> Dictionary:
	var flags: Dictionary = d.get("flags", {}) if d.get("flags") is Dictionary else {}
	var global: Dictionary = d.get("global", {}) if d.get("global") is Dictionary else {}
	var have: Array = global.get(Looks.KEY, []) if global.get(Looks.KEY) is Array else []
	var worn: Array[String] = _worn_in_save(flags)
	for t: String in Looks.target_ids():
		for p: Dictionary in Looks.target_defs(t):
			var id: String = str(p["id"])
			if bool(p.get("starter", false)) or id in have:
				continue
			if id in worn or _legacy_met(p.get("legacy", {}), d):
				have.append(id)
	global[Looks.KEY] = have
	d["global"] = global
	var glim: Variant = flags.get(GLIM)
	if glim is Dictionary:
		(glim as Dictionary).erase(OLD_GLIM_OWNED)
	var builder: Variant = flags.get("builder")
	if builder is Dictionary:
		(builder as Dictionary).erase("inv")
	flags.erase("shop_owned")
	d["flags"] = flags
	return d


## The pieces a save's crew designs and Glim wear now.
static func _worn_in_save(flags: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var glim: Variant = flags.get(GLIM)
	if glim is Dictionary:
		for s: Dictionary in Looks.target_slots(GLIM):
			var key: String = str(s["key"])
			if (glim as Dictionary).has(key):
				out.append(piece(GLIM, key, str(glim[key])))
	var fleet_mark: String = str(flags.get("livery", ""))
	if fleet_mark != "":
		out.append(piece(CREW, LIVERY, fleet_mark))
	var designs: Variant = flags.get("robot_designs")
	if designs is Dictionary:
		for v: Variant in (designs as Dictionary).values():
			if not (v is Dictionary):
				continue
			var dd: Dictionary = v
			if dd.get("parts") is Dictionary:
				for slot: String in (dd["parts"] as Dictionary):
					out.append(piece(CREW, slot, str(dd["parts"][slot])))
			for key: String in [LIVERY, GLOW]:
				if str(dd.get(key, "")) != "":
					out.append(piece(CREW, key, str(dd[key])))
	return out


static func _legacy_met(rule: Variant, d: Dictionary) -> bool:
	if not (rule is Dictionary) or (rule as Dictionary).is_empty():
		return false
	var r: Dictionary = rule
	var flags: Dictionary = d.get("flags", {}) if d.get("flags") is Dictionary else {}
	if bool(r.get("free", false)):
		return true
	if r.has("stat"):
		var stats: Dictionary = d.get("stats", {}) if d.get("stats") is Dictionary else {}
		var v: Variant = stats.get(str(r["stat"]), 0.0)
		return (v is float or v is int) and float(v) >= float(r.get("target", 1.0))
	var glim: Dictionary = flags.get(GLIM, {}) if flags.get(GLIM) is Dictionary else {}
	if r.has("glim_tier"):
		var total: int = 0
		var tiers: Variant = glim.get("tiers", {})
		if tiers is Dictionary:
			for k: Variant in (tiers as Dictionary).values():
				total += int(k)
		return total >= int(r["glim_tier"])
	if r.has("glim_bought"):
		var owned: Variant = glim.get(OLD_GLIM_OWNED, [])
		return owned is Array and str(r["glim_bought"]) in (owned as Array)
	if r.has("builder_part"):
		var b: Variant = flags.get("builder")
		var inv: Variant = (b as Dictionary).get("inv", {}) if b is Dictionary else {}
		return inv is Dictionary and int((inv as Dictionary).get(str(r["builder_part"]), 0)) > 0
	if r.has(LIVERY):
		var shop: Variant = flags.get("shop_owned", [])
		return shop is Array and str(r[LIVERY]) in (shop as Array)
	return false
