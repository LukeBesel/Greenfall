class_name LumiStyle
extends RefCounted
## Lumi's look (data/style_parts.json): a dict of slots that a PatchModel reads.
##   colours: paint, trim, accent, side (side modules), eyes, glow (light strips: ear stripes, chest,
##            wrists), hover (thruster ring + hover light), laser (pickup lasers, player/pickup_fx.gd)
##   amounts: wear (0..1; paint coverage follows it)
##   parts:   pattern, eye_shape, head, ears, chest, shoulders, held, hip, companion
##   bonus:   the base design of the look: the design whose paint set it wears (also
##            flags.patch_skin; the model builds from it)
##   hidden:  preset (the design the hidden values came from), lamp, coverage, metal
## The six designs are presets that fill every slot (preset(id) reads PatchModel.VARIANTS, so a
## preset style reproduces the design's look exactly; tests/test_lumi_style.gd checks it).
##
## What may be worn is decided by found pieces alone (systems/looks.gd, data/cosmetics.json; design
## spec section 13). A piece fills one Locker slot: wear_piece() writes it into a style,
## piece_in() reads back which piece a slot holds, allowed() says whether every piece of a style
## has been found, and worn_set() names the design whose every piece is worn (its small bonus
## applies then: systems/designs.gd; a mixed look gives none). The Locker's "paint" slot holds a
## design's paint set (body colours and wear) or a paint tin over it (main paint only); its "glow"
## slot sets every light at once (eyes, strips, hover, laser).
##
## How the model reads it (two tagged hooks in PatchModel._build):
##   var v: Dictionary = LumiStyle.variant_for(self, VARIANTS[variant])   (first line)
##   LumiStyle.after_build(self)                                          (last line)
## variant_for turns the style into a VARIANTS-shaped dict, so PatchModel builds its own native
## add-ons (acc ids), colours and eye shape (the face shader draws every eye_shape; "happy" is the
## crescent resting on smiling arcs); after_build recolours what VARIANTS has no key for (eyes, side
## modules, hover ring), and adds the add-ons PatchModel does not know
## (library meshes from aurora.glb / designs.glb by name, procedural fallbacks otherwise), and
## leaves the laser colour as model meta "lumi_laser" for PickupFx. Every access is defensive
## (get / has_method / null checks), so the hero model can be rebuilt underneath.
##
## Which style a model shows: meta "lumi_style" (the Locker's turntable, title screen) > preset of
## its variant when preview_variant is set (lineups) > the worn style when its base design is the
## model's variant > that variant's preset.
## State (GameState.flags, in the save): lumi_style (the worn style), lumi_looks (the saved looks,
## each a style with a "name"). Emits EventBus.look_changed when the worn look changes.

const PATH: String = "res://data/style_parts.json"
const VERSION: int = 1
const COLOR_SLOTS: Array[String] = ["paint", "trim", "accent", "side", "eyes", "glow", "hover", "laser"]
const PART_SLOTS: Array[String] = ["pattern", "eye_shape", "head", "ears", "chest", "shoulders", "held", "hip", "companion"]
## Part slots whose options carry PatchModel add-on ids ("acc"): a preset fills them from the
## design's acc list, and variant_dict turns them back into one.
const ACC_SLOTS: Array[String] = ["pattern", "head", "ears", "shoulders", "held", "hip", "companion"]
## The colour keys the Locker's "paint" slot owns, and the ones its "glow" slot sets together.
const BODY_SLOTS: Array[String] = ["paint", "trim", "accent", "side"]
const GLOW_SLOTS: Array[String] = ["eyes", "glow", "hover", "laser"]
const PAINT: String = "paint"
const GLOW: String = "glow"
## Owner: unfound pieces are never shown, only "???" and one hint line.
const LOCKED_NAME: String = Looks.UNFOUND_NAME

static var _data: Dictionary = {}


# --- Data -------------------------------------------------------------------------------------

static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_data = d
	return _data


static func slot_defs() -> Array:
	return data().get("slots", [])


static func slot_def(slot: String) -> Dictionary:
	for s: Dictionary in slot_defs():
		if str(s["id"]) == slot:
			return s
	return {}


static func options(slot: String) -> Array:
	return (data().get("options", {}) as Dictionary).get(slot, [])


static func option(slot: String, id: String) -> Dictionary:
	for o: Dictionary in options(slot):
		if str(o["id"]) == id:
			return o
	return {}


static func swatches() -> Array:
	return data().get("swatches", [])


static func swatch(id: String) -> Dictionary:
	for s: Dictionary in swatches():
		if str(s["id"]) == id:
			return s
	return {}


static func swatch_color(s: Dictionary) -> Color:
	return Color(str(s.get("color", "#ffffff")))


## The swatch whose colour this is (within ~1/255), or {}.
static func swatch_for(c: Color) -> Dictionary:
	for s: Dictionary in swatches():
		if _close(swatch_color(s), c, 0.006):
			return s
	return {}


# --- Colours ----------------------------------------------------------------------------------

static func to_arr(c: Color) -> Array:
	return [snappedf(c.r, 0.0001), snappedf(c.g, 0.0001), snappedf(c.b, 0.0001)]


static func to_color(v: Variant, fallback: Color = Color.WHITE) -> Color:
	if v is Color:
		return v
	if v is Array and (v as Array).size() >= 3:
		var a: Array = v
		return Color(float(a[0]), float(a[1]), float(a[2]))
	if v is String and Color.html_is_valid(v):
		return Color(str(v))
	return fallback


static func col(style: Dictionary, slot: String) -> Color:
	return to_color(style.get(slot), Color.WHITE)


static func _close(a: Color, b: Color, eps: float = 0.002) -> bool:
	return absf(a.r - b.r) <= eps and absf(a.g - b.g) <= eps and absf(a.b - b.b) <= eps


# --- Presets ----------------------------------------------------------------------------------

static func _variants() -> Dictionary:
	return PatchModel.VARIANTS


static func preset_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in Designs.ids():
		if _variants().has(id):
			out.append(id)
	return out


## The design's look as a style (every slot filled from PatchModel.VARIANTS[id]).
static func preset(id: String) -> Dictionary:
	var vs: Dictionary = _variants()
	if not vs.has(id):
		id = Designs.DEFAULT
	var v: Dictionary = vs.get(id, {})
	var glow: Color = v.get("glow", Color(0.3, 0.88, 1.0))
	var accent: Color = v.get("accent", Color(1.0, 0.5, 0.12))
	var trim: Color = v.get("trim", Color(0.36, 0.38, 0.42))
	var s: Dictionary = {
		"v": VERSION,
		"preset": id,
		"bonus": id,
		"paint": to_arr(v.get("paint", Color(0.9, 0.88, 0.83))),
		"trim": to_arr(trim),
		"accent": to_arr(accent),
		"side": to_arr(trim),
		"eyes": to_arr(glow),
		"glow": to_arr(glow),
		"hover": to_arr(glow),
		"laser": to_arr(glow),
		"lamp": to_arr(v.get("lamp", accent)),
		"wear": float(v.get("grime", 0.6)),
		"coverage": float(v.get("coverage", 0.9)),
		"metal": float(v.get("metal", 0.0)),
		"eye_shape": "happy" if float(v.get("happy", 0.5)) >= 0.99 else "crescent",
		"chest": str(v.get("icon", "recycle")),
	}
	var acc: Array = v.get("acc", [])
	for slot: String in ACC_SLOTS:
		# The slot's first option is its empty one (none / plain); else the option whose pieces are
		# all on the design, the one with the most pieces winning.
		var opts: Array = options(slot)
		s[slot] = str((opts[0] as Dictionary)["id"]) if not opts.is_empty() else "none"
		var best: int = 0
		for o: Dictionary in opts:
			var need: Array = o.get("acc", [])
			var all_in: bool = need.size() > best
			for a: Variant in need:
				all_in = all_in and (a in acc)
			if all_in:
				s[slot] = str(o["id"])
				best = need.size()
	return s


## Native add-on ids in a VARIANTS acc list that no option maps (tests: should stay empty, so the
## presets reproduce every add-on; a rename on the hero side shows up here).
static func unmapped_acc(id: String) -> Array:
	var known: Array = []
	for slot: String in PART_SLOTS:
		for o: Dictionary in options(slot):
			known.append_array(o.get("acc", []))
	var out: Array = []
	for a: Variant in (_variants().get(id, {}) as Dictionary).get("acc", []):
		if not (a in known):
			out.append(a)
	return out


## Fill missing or bad slots (from the style's preset), so any saved dict is safe to apply.
static func normalize(d: Variant) -> Dictionary:
	var src: Dictionary = d if d is Dictionary else {}
	var base_id: String = str(src.get("preset", src.get("bonus", Designs.DEFAULT)))
	var out: Dictionary = preset(base_id)
	if src.is_empty():
		return out
	var b: String = str(src.get("bonus", out["bonus"]))
	out["bonus"] = b if _variants().has(b) else out["bonus"]
	for slot: String in COLOR_SLOTS + ["lamp"]:
		if src.has(slot):
			out[slot] = to_arr(to_color(src[slot], col(out, slot)))
	for k: String in ["wear", "coverage", "metal"]:
		if src.has(k):
			out[k] = clampf(float(src[k]), 0.0, 1.0)
	for slot: String in PART_SLOTS:
		var id: String = str(src.get(slot, out[slot]))
		if not option(slot, id).is_empty():
			out[slot] = id
	if src.has("name"):
		out["name"] = str(src["name"])
	return out


## Same look (colours within rounding, same parts, same bonus). Ignores the look's name.
static func same(a: Dictionary, b: Dictionary) -> bool:
	var x: Dictionary = normalize(a)
	var y: Dictionary = normalize(b)
	if x["bonus"] != y["bonus"]:
		return false
	for slot: String in COLOR_SLOTS + ["lamp"]:
		if not _close(col(x, slot), col(y, slot)):
			return false
	for k: String in ["wear", "coverage", "metal"]:
		if absf(float(x[k]) - float(y[k])) > 0.001:
			return false
	for slot: String in PART_SLOTS:
		if x[slot] != y[slot]:
			return false
	return true


## Change one slot, with its knock-on hidden values: accent also sets the small accent lamps;
## wear also sets paint coverage (more wear = more bare metal showing).
static func set_value(style: Dictionary, slot: String, value: Variant) -> void:
	if slot in COLOR_SLOTS:
		var c: Color = to_color(value, col(style, slot))
		style[slot] = to_arr(c)
		if slot == "accent":
			style["lamp"] = to_arr(c)
	elif slot == "wear":
		var w: float = clampf(float(value), 0.0, 1.0)
		style["wear"] = w
		style["coverage"] = clampf(0.98 - w * 0.2, 0.75, 0.98)
	elif slot == "bonus":
		if _variants().has(str(value)):
			style["bonus"] = str(value)
	elif slot in PART_SLOTS:
		if not option(slot, str(value)).is_empty():
			style[slot] = str(value)


# --- Worn style -------------------------------------------------------------------------------

## The worn look (the stored custom style, or the worn design's preset).
static func current() -> Dictionary:
	var st: Variant = GameState.flags.get("lumi_style")
	if st is Dictionary and not (st as Dictionary).is_empty():
		var s: Dictionary = normalize(st)
		if str(s["bonus"]) == Designs.current():
			return s
	return preset(Designs.current())


## Is the look one of the six designs, unchanged?
static func is_preset(style: Dictionary) -> bool:
	return same(style, preset(str(normalize(style)["preset"])))


## What a model of design `variant` shows when nothing else says (see the class doc).
static func for_variant(variant: String) -> Dictionary:
	var s: Dictionary = current()
	return s if str(s["bonus"]) == variant else preset(variant)


## Wear a style (the Locker). Its base design falls back to the worn one when that paint set is
## not found. Emits look_changed.
static func set_current(style: Dictionary) -> void:
	var s: Dictionary = normalize(style)
	if not Designs.has_base(str(s["bonus"])):
		s["bonus"] = Designs.current()
	s.erase("name")
	GameState.flags["lumi_style"] = s
	GameState.flags["patch_skin"] = str(s["bonus"])
	GameState.flags[Designs.SET_FLAG] = worn_set(s)
	EventBus.look_changed.emit()


## Wear every piece of a design over the worn look. False until the whole set is found.
static func wear_set(id: String) -> bool:
	if not Looks.set_collected(id):
		return false
	set_current(with_set(current(), id))
	return true


# --- Saved looks ------------------------------------------------------------------------------

## The saved looks: as many slots as the data asks for (Looks.preset_count). A save from when
## there were more keeps the extra ones it filled until they are cleared.
static func looks() -> Array:
	var v: Variant = GameState.flags.get("lumi_looks", [])
	var arr: Array = v if v is Array else []
	var want: int = Looks.preset_count()
	while arr.size() < want:
		arr.append({})
	while arr.size() > want and not (arr[-1] is Dictionary and not (arr[-1] as Dictionary).is_empty()):
		arr.pop_back()
	GameState.flags["lumi_looks"] = arr
	return arr


static func look(i: int) -> Dictionary:
	var arr: Array = looks()
	if i < 0 or i >= arr.size() or not (arr[i] is Dictionary) or (arr[i] as Dictionary).is_empty():
		return {}
	return normalize(arr[i])


static func save_look(i: int, style: Dictionary, look_name: String = "") -> bool:
	if i < 0 or i >= looks().size():
		return false
	var s: Dictionary = normalize(style)
	s["name"] = look_name if look_name != "" else str(style.get("name", ""))
	looks()[i] = s
	return true


static func delete_look(i: int) -> void:
	if i >= 0 and i < looks().size():
		looks()[i] = {}


# --- Pieces -----------------------------------------------------------------------------------

## Put a piece into a style (no check that it is found: allowed() is the gate).
static func wear_piece(style: Dictionary, piece: String) -> void:
	var p: Dictionary = Looks.def(piece)
	if p.is_empty():
		return
	var slot: String = str(p["slot"])
	if p.has("option"):
		set_value(style, slot, str(p["option"]))
	elif slot == PAINT:
		if p.has("design"):
			_wear_paint_set(style, str(p["design"]))
		else:
			set_value(style, PAINT, swatch_color(swatch(str(p.get("swatch", "")))))
	elif slot == GLOW:
		for k: String in GLOW_SLOTS:
			set_value(style, k, _piece_color(p))


## A design's paint set: its body colours and wear, and it becomes the look's base design.
static func _wear_paint_set(style: Dictionary, design: String) -> void:
	var src: Dictionary = preset(design)
	for k: String in BODY_SLOTS + ["lamp", "wear", "coverage", "metal"]:
		style[k] = src[k]
	style["bonus"] = str(src["bonus"])
	style["preset"] = str(src["preset"])


static func _piece_color(p: Dictionary) -> Color:
	if p.has("design"):
		return col(preset(str(p["design"])), GLOW if str(p["slot"]) == GLOW else PAINT)
	return swatch_color(swatch(str(p.get("swatch", ""))))


## The colour a piece shows in a list: its own for a paint or light piece, `fallback` for a part.
static func piece_tint(piece: String, fallback: Color = Color.WHITE) -> Color:
	var p: Dictionary = Looks.def(piece)
	if p.is_empty() or p.has("option"):
		return fallback
	return _piece_color(p)


## Can a slot be left empty (its first option is "none" / "plain" and no piece stands for it)?
static func can_clear(slot: String) -> bool:
	if not (slot in PART_SLOTS):
		return false
	var opts: Array = options(slot)
	return not opts.is_empty() and Looks.piece_for(slot, "option", str((opts[0] as Dictionary)["id"])) == ""


## Empty a slot (only the ones can_clear allows).
static func clear_slot(style: Dictionary, slot: String) -> void:
	if can_clear(slot):
		style[slot] = str((options(slot)[0] as Dictionary)["id"])


## The piece a slot of the style holds ("" for an empty slot, or for a value no piece stands for:
## a colour mixed in a save from before found pieces).
static func piece_in(style: Dictionary, slot: String) -> String:
	return _piece_in(normalize(style), slot)


static func _piece_in(s: Dictionary, slot: String) -> String:
	if slot in PART_SLOTS:
		return Looks.piece_for(slot, "option", str(s[slot]))
	if slot == PAINT:
		var base: Dictionary = preset(str(s["bonus"]))
		for k: String in ["trim", "accent", "side"]:
			if not _close(col(s, k), col(base, k)):
				return ""
		if _close(col(s, PAINT), col(base, PAINT)):
			return Looks.piece_for(PAINT, "design", str(s["bonus"]))
		return _swatch_piece(PAINT, col(s, PAINT))
	if slot == GLOW:
		var c: Color = col(s, GLOW)
		for k: String in GLOW_SLOTS:
			if not _close(col(s, k), c):
				return ""
		for id: String in Looks.of_slot(GLOW):
			var p: Dictionary = Looks.def(id)
			if p.has("design") and _close(_piece_color(p), c):
				return id
		return _swatch_piece(GLOW, c)
	return ""


static func _swatch_piece(slot: String, c: Color) -> String:
	var sw: Dictionary = swatch_for(c)
	return Looks.piece_for(slot, "swatch", str(sw["id"])) if not sw.is_empty() else ""


## Slot -> the piece worn there ("" where none).
static func worn_pieces(style: Dictionary) -> Dictionary:
	var s: Dictionary = normalize(style)
	var out: Dictionary = {}
	for slot: String in Looks.slot_ids():
		out[slot] = _piece_in(s, slot)
	return out


## The design whose every piece the style wears ("" for a mixed look). Slots the set does not
## use may hold anything.
static func worn_set(style: Dictionary) -> String:
	var s: Dictionary = normalize(style)
	var design: String = str(s["bonus"])
	var pieces: Array[String] = Looks.set_ids(design)
	if pieces.is_empty():
		return ""
	for id: String in pieces:
		if _piece_in(s, Looks.slot_of(id)) != id:
			return ""
	return design


## The style with every piece of a design worn over it.
static func with_set(style: Dictionary, design: String) -> Dictionary:
	var s: Dictionary = normalize(style)
	s.erase("name")
	for id: String in Looks.set_ids(design):
		wear_piece(s, id)
	return s


## Is the slot's value the same in two styles?
static func _slot_same(a: Dictionary, b: Dictionary, slot: String) -> bool:
	if slot in PART_SLOTS:
		return a[slot] == b[slot]
	for k: String in (BODY_SLOTS if slot == PAINT else GLOW_SLOTS):
		if not _close(col(a, k), col(b, k)):
			return false
	return true


## A value no piece stands for may stay only where the player already had it: in the worn look
## or in a saved look (a save from before found pieces keeps what it wore).
static func _carried_over(s: Dictionary, slot: String) -> bool:
	if _slot_same(s, current(), slot):
		return true
	for i: int in looks().size():
		var lk: Dictionary = look(i)
		if not lk.is_empty() and _slot_same(s, lk, slot):
			return true
	return false


## May this style be worn: is every piece in it found?
static func allowed(style: Dictionary) -> bool:
	var s: Dictionary = normalize(style)
	if not Designs.has_base(str(s["bonus"])):
		return false
	for slot: String in Looks.slot_ids():
		var piece: String = _piece_in(s, slot)
		if piece != "":
			if not Looks.has(piece):
				return false
		elif not (can_clear(slot) and s[slot] == str((options(slot)[0] as Dictionary)["id"])) and not _carried_over(s, slot):
			return false
	return true


## The pieces the looks in a save's flags are made of (the worn look and the saved ones): what
## the save migration grants so an old save keeps what it wore (Looks.migrate_save).
static func pieces_in_save(flags: Dictionary) -> Array[String]:
	var styles: Array = [flags.get("lumi_style")]
	if flags.get("lumi_looks") is Array:
		styles.append_array(flags["lumi_looks"])
	var out: Array[String] = []
	for st: Variant in styles:
		if not (st is Dictionary) or (st as Dictionary).is_empty():
			continue
		var s: Dictionary = normalize(st)
		var ids: Array = worn_pieces(s).values()
		ids.append(Looks.piece_for(PAINT, "design", str(s["bonus"])))
		for id: Variant in ids:
			if str(id) != "" and not (str(id) in out):
				out.append(str(id))
	return out


## A random look from the found pieces (the Locker's shuffle, dev shots).
static func randomized(rng: RandomNumberGenerator, base: Dictionary = {}) -> Dictionary:
	var s: Dictionary = normalize(base) if not base.is_empty() else current()
	s.erase("name")
	for slot: String in Looks.slot_ids():
		var have: Array[String] = []
		for id: String in Looks.of_slot(slot):
			if Looks.has(id):
				have.append(id)
		var pick: int = rng.randi() % (have.size() + (1 if can_clear(slot) else 0)) if not have.is_empty() or can_clear(slot) else -1
		if pick < 0:
			continue
		if pick >= have.size():
			clear_slot(s, slot)
		else:
			wear_piece(s, have[pick])
	return s


# --- Model ------------------------------------------------------------------------------------

## The style a model shows (see the class doc).
static func style_for_model(model: Node) -> Dictionary:
	if model == null:
		return current()
	if model.has_meta("lumi_style"):
		return normalize(model.get_meta("lumi_style"))
	var variant: String = str(model.get("variant")) if model.get("variant") != null else Designs.DEFAULT
	if str(model.get("preview_variant")) not in ["", "<null>"]:
		return preset(variant)
	return for_variant(variant)


## The style as a PatchModel.VARIANTS entry. Keys the hero adds later stay as in `base`; base acc
## ids that no option knows are kept too.
static func variant_dict(style: Dictionary, base: Dictionary = {}) -> Dictionary:
	var s: Dictionary = normalize(style)
	var v: Dictionary = base.duplicate(true)
	v["paint"] = col(s, "paint")
	v["trim"] = col(s, "trim")
	v["accent"] = col(s, "accent")
	v["glow"] = col(s, "glow")
	v["lamp"] = col(s, "lamp")
	v["grime"] = float(s["wear"])
	v["coverage"] = float(s["coverage"])
	v["metal"] = float(s["metal"])
	v["moss"] = 0.6 if s["pattern"] == "moss" else 0.0
	v["stripes"] = 1.0 if s["pattern"] == "stripes" else 0.0
	# One eye path: the face shader's shapes. "happy" rests the crescent on smiling arcs.
	var shape: String = str(s["eye_shape"])
	v["happy"] = 1.0 if shape == "happy" else 0.5
	v["smile"] = 1.0 if shape == "happy" else 0.0  # the small visor smile belongs to the smiling arcs
	v["eyes"] = "crescent" if shape == "happy" or not (shape in PatchModel.EYE_SHAPES) else shape
	var ic: String = str(s["chest"])
	v["icon"] = ic if ic in ["recycle", "leaf", "cross"] else "recycle"
	var known: Array = []
	for slot: String in PART_SLOTS:
		for o: Dictionary in options(slot):
			known.append_array(o.get("acc", []))
	var acc: Array = []
	for a: Variant in base.get("acc", []):
		if not (a in known):
			acc.append(a)
	for slot: String in ACC_SLOTS:
		for a: Variant in option(slot, str(s[slot])).get("acc", []):
			if not (a in acc):
				acc.append(a)
	v["acc"] = acc
	return v


## Hook at the top of PatchModel._build: the variant dict to build from.
static func variant_for(model: Node, base: Dictionary) -> Dictionary:
	var s: Dictionary = style_for_model(model)
	model.set_meta("lumi_style_live", s)
	return variant_dict(s, base)


## Hook at the end of PatchModel._build: everything VARIANTS cannot say.
static func after_build(model: Node) -> void:
	var s: Dictionary = model.get_meta("lumi_style_live") if model.has_meta("lumi_style_live") else style_for_model(model)
	if model.has_meta("lumi_silhouette"):
		model.remove_meta("lumi_silhouette")  # a rebuild has fresh materials
	model.set_meta("lumi_laser", col(s, "laser"))
	model.set_meta("lumi_eyes", col(s, "eyes"))
	model.set_meta("lumi_glow", col(s, "glow"))
	model.set_meta("lumi_hover", col(s, "hover"))
	_recolor(model, s)
	var rig := LumiStyleRig.new()
	rig.name = "LumiStyleRig"
	model.add_child(rig)
	rig.setup(model, s)


## Colours that need no rebuild (paint, trim, accent, side, eyes, hover; laser is meta).
static func _recolor(model: Node, s: Dictionary) -> void:
	var mats: Variant = model.get("_mats")
	if mats is Dictionary:
		var m: Dictionary = mats
		_paint_col(m.get("paint"), col(s, "paint").darkened(0.04))
		_paint_col(m.get("trim"), col(s, "trim").darkened(0.45))
		_paint_col(m.get("accent"), col(s, "accent"))
		if m.has("side"):
			_paint_col(m.get("side"), col(s, "side").darkened(0.45))
		var hv: Color = col(s, "hover")
		for k: String in ["thruster"]:
			if m.get(k) is StandardMaterial3D:
				(m[k] as StandardMaterial3D).emission = hv
				(m[k] as StandardMaterial3D).albedo_color = hv.darkened(0.3)
		if m.get("thruster_core") is StandardMaterial3D:
			(m["thruster_core"] as StandardMaterial3D).emission = hv.lightened(0.4)
			(m["thruster_core"] as StandardMaterial3D).albedo_color = hv.lightened(0.4).darkened(0.3)
	var ring: Variant = model.get("_ring_mat")
	if ring is StandardMaterial3D:
		(ring as StandardMaterial3D).emission = col(s, "hover")
	var fl: Variant = model.get("_float")
	if fl is Node3D:
		for c: Node in (fl as Node3D).get_children():
			# The hover light: the one omni light not limited to the hero layer.
			if c is OmniLight3D and (c as OmniLight3D).omni_range < 1.8 and (c as OmniLight3D).light_cull_mask != PatchModel.HERO_LAYER:
				(c as OmniLight3D).light_color = col(s, "hover")
	var face: Variant = model.get("_face_mat")
	if face is ShaderMaterial:
		(face as ShaderMaterial).set_shader_parameter("eye_color", col(s, "eyes"))
	_side_surfaces(model, s)


static func _paint_col(m: Variant, c: Color) -> void:
	if m is ShaderMaterial:
		(m as ShaderMaterial).set_shader_parameter("paint_color", c)
	elif m is StandardMaterial3D:
		(m as StandardMaterial3D).albedo_color = c


## Side modules: surfaces whose source material is named "side" (the hero's rebuild) get their own
## paint; until then the side pods use trim and follow the trim colour.
static func _side_surfaces(model: Node, s: Dictionary) -> void:
	var mats: Variant = model.get("_mats")
	if mats is Dictionary and (mats as Dictionary).has("side"):
		return
	var side_mat: ShaderMaterial = null
	for n: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		if mi.mesh == null:
			continue
		for i: int in mi.mesh.get_surface_count():
			var src: Material = mi.mesh.surface_get_material(i)
			if src == null or src.resource_name != "side":
				continue
			if side_mat == null:
				var trim: Variant = (mats as Dictionary).get("trim") if mats is Dictionary else null
				side_mat = (trim as ShaderMaterial).duplicate() if trim is ShaderMaterial else ShaderMaterial.new()
				_paint_col(side_mat, col(s, "side").darkened(0.45))
			mi.set_surface_override_material(i, side_mat)


## Show a style on a model (builder preview, title): stores it as meta and rebuilds when parts or
## the light-strip colour changed; colour-only edits are applied in place.
static func apply(model: Node, style: Dictionary) -> void:
	if model == null:
		return
	var s: Dictionary = normalize(style)
	var live: Dictionary = model.get_meta("lumi_style_live") if model.has_meta("lumi_style_live") else {}
	model.set_meta("lumi_style", s)
	var rebuild: bool = live.is_empty() or not model.is_inside_tree()
	if not rebuild:
		for k: String in PART_SLOTS + ["glow", "lamp", "wear", "coverage", "metal", "bonus"]:
			if str(live.get(k)) != str(s.get(k)):
				rebuild = true
				break
	if rebuild:
		if model.is_inside_tree() and model.has_method("set_variant"):
			model.call("set_variant", str(s["bonus"]))
		return
	model.set_meta("lumi_style_live", s)
	model.set_meta("lumi_laser", col(s, "laser"))
	model.set_meta("lumi_eyes", col(s, "eyes"))
	model.set_meta("lumi_hover", col(s, "hover"))
	_recolor(model, s)
	var rig: Node = model.get_node_or_null("LumiStyleRig")
	if rig and rig.has_method("restyle"):
		rig.call("restyle", s)


## Re-dress the player's model after the worn style changed.
static func refresh_player(world: Node) -> void:
	if world == null or world.get("patch") == null:
		return
	var m: Variant = (world.get("patch") as Node).get("model")
	if m is Node and (m as Node).has_method("set_variant"):
		(m as Node).call("set_variant", Designs.current())


## A flat dark shape of the model (locked designs in previews): no colours, lights, eyes or icon.
static func silhouette(model: Node) -> void:
	if model == null:
		return
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.17, 0.18, 0.21)
	for n: Node in model.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).material_override = m
		(n as MeshInstance3D).material_overlay = null
	for n: Node in model.find_children("*", "Light3D", true, false):
		(n as Light3D).visible = false
	for n: Node in model.find_children("*", "Label3D", true, false):
		(n as Label3D).visible = false
	model.set_meta("lumi_silhouette", true)


## Colour helpers for other systems (photo mode, pickup FX): the model's live style colours.
static func laser_of(model: Node) -> Color:
	if model == null:
		return Color(0.35, 0.9, 1.0)
	return model.get_meta("lumi_laser", PatchModel.glow_of(str(model.get("variant"))))


static func eyes_of(model: Node) -> Color:
	if model == null:
		return Color(0.3, 0.88, 1.0)
	return model.get_meta("lumi_eyes", PatchModel.glow_of(str(model.get("variant"))))


static func glow_of_model(model: Node) -> Color:
	if model == null:
		return Color(0.3, 0.88, 1.0)
	return model.get_meta("lumi_glow", PatchModel.glow_of(str(model.get("variant"))))


## Title screen: the style stored in a save's flags for the worn design `skin`.
static func from_save_flags(flags: Dictionary, skin: String) -> Dictionary:
	var st: Variant = flags.get("lumi_style")
	if st is Dictionary and str((st as Dictionary).get("bonus", "")) == skin:
		return normalize(st)
	return preset(skin if skin != "" else Designs.DEFAULT)


# --- Dev hooks --------------------------------------------------------------------------------
##   --lumi-parts-all         every piece counts as found for this run
##   --lumi-random=SEED       wear a random look (every piece found first)
##   --lumi-set=slot:value,.. set style keys (colours as hex without #, e.g. laser:ff3d8a)
##   --lumi-look=N            wear saved look N
## The Locker itself opens with --open-locker (systems/camp/locker_cabinet.gd).
static func dev_hooks(world: Node) -> void:
	if DevHooks.has("lumi-parts-all") or DevHooks.has("lumi-random"):
		Looks.dev_all = true
	var changed: bool = false
	var s: Dictionary = current()
	if DevHooks.has("lumi-random"):
		var rng := RandomNumberGenerator.new()
		rng.seed = int(DevHooks.get_f("lumi-random", 1.0))
		s = randomized(rng, s)
		changed = true
	var lk: int = int(DevHooks.get_f("lumi-look", -1.0))
	if lk >= 0 and not look(lk).is_empty():
		s = look(lk)
		changed = true
	var sets: String = DevHooks.get_s("lumi-set", "")
	if sets != "":
		for kv: String in sets.split(","):
			var p: PackedStringArray = kv.split(":")
			if p.size() != 2:
				continue
			var value: Variant = p[1]
			if p[0] in COLOR_SLOTS:
				value = "#" + p[1]
			elif p[0] == "wear":
				value = float(p[1])
			set_value(s, p[0], value)
		changed = true
	if changed:
		set_current(s)
		refresh_player(world)
