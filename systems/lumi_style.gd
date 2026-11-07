class_name LumiStyle
extends RefCounted
## Lumi's Character Builder look (data/style_parts.json): a dict of slots that a PatchModel reads.
##   colours: paint, trim, accent, side (side modules), eyes, glow (light strips: ear stripes, chest,
##            wrists), hover (thruster ring + hover light), laser (pickup lasers, player/pickup_fx.gd)
##   amounts: wear (0..1; paint coverage follows it)
##   parts:   pattern, eye_shape, head, chest, shoulders, held, companion
##   bonus:   the unlocked design whose small bonus applies (it is also flags.patch_skin, so
##            Designs.mult keeps working unchanged; "looks only" still turns it off)
##   hidden:  preset (the design the hidden values came from), lamp, coverage, metal
## The six designs are presets that fill every slot (preset(id) reads PatchModel.VARIANTS, so a
## preset style reproduces the design's look exactly; tests/test_lumi_style.gd checks it).
##
## How the model reads it (two tagged hooks in PatchModel._build):
##   var v: Dictionary = LumiStyle.variant_for(self, VARIANTS[variant])   (first line)
##   LumiStyle.after_build(self)                                          (last line)
## variant_for turns the style into a VARIANTS-shaped dict, so PatchModel builds its own native
## add-ons (acc ids) and colours; after_build recolours what VARIANTS has no key for (eyes, side
## modules, hover ring), adds the eye-shape overlay and the add-ons PatchModel does not know
## (library meshes from aurora.glb / designs.glb by name, procedural fallbacks otherwise), and
## leaves the laser colour as model meta "lumi_laser" for PickupFx. Every access is defensive
## (get / has_method / null checks), so the hero model can be rebuilt underneath.
##
## Which style a model shows: meta "lumi_style" (builder preview, title screen) > preset of its
## variant when preview_variant is set (design picker, lineups) > the worn style when its bonus is
## the model's variant > that variant's preset.
## State (GameState.flags, in the save): lumi_style (the worn style), lumi_looks (up to 5 saved
## looks, each a style with a "name"), style_bought (ids bought with cubes/parts/seeds).
## Unlock sources trickle in across the whole game: free starters, Lumi Level, hub level, the six
## designs (their parts and colours), Collection finds, Requests, achievements (early to late), and
## a few cosmetic buys for parts / seeds.

const PATH: String = "res://data/style_parts.json"
const MAX_LOOKS: int = 5
const VERSION: int = 1
const COLOR_SLOTS: Array[String] = ["paint", "trim", "accent", "side", "eyes", "glow", "hover", "laser"]
const PART_SLOTS: Array[String] = ["pattern", "eye_shape", "head", "chest", "shoulders", "held", "companion"]
## Native (PatchModel) eye looks; any other shape is drawn by the overlay (art/shaders/lumi_eyes).
const NATIVE_EYES: Array[String] = ["crescent", "happy"]
const OVERLAY_SHAPES: Dictionary = {"round": 1, "bar": 2, "heart": 3}

static var _data: Dictionary = {}
## Dev (--lumi-parts-all / --lumi-random): every unlock met for this run.
static var dev_all: bool = false


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
		"pattern": "stripes" if float(v.get("stripes", 0.0)) > 0.0 else ("moss" if float(v.get("moss", 0.0)) > 0.0 else "plain"),
		"eye_shape": "happy" if float(v.get("happy", 0.5)) >= 0.99 else "crescent",
		"chest": str(v.get("icon", "recycle")),
	}
	var acc: Array = v.get("acc", [])
	for slot: String in ["head", "shoulders", "held", "companion"]:
		s[slot] = "none"
		for o: Dictionary in options(slot):
			var need: Array = o.get("acc", [])
			if need.is_empty():
				continue
			var all_in: bool = true
			for a: Variant in need:
				all_in = all_in and (a in acc)
			if all_in:
				s[slot] = str(o["id"])
				break
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


## Is the worn look one of the six presets (unchanged)?
static func is_preset(style: Dictionary) -> bool:
	return same(style, preset(str(normalize(style)["preset"])))


## What a model of design `variant` shows when nothing else says (see the class doc).
static func for_variant(variant: String) -> Dictionary:
	var s: Dictionary = current()
	return s if str(s["bonus"]) == variant else preset(variant)


## Wear a style (the builder's Save). Its bonus design becomes the worn design when unlocked.
static func set_current(style: Dictionary) -> void:
	var s: Dictionary = normalize(style)
	if not Designs.is_unlocked(str(s["bonus"])):
		s["bonus"] = Designs.current()
	s.erase("name")
	GameState.flags["lumi_style"] = s
	Designs.select(str(s["bonus"]))


## Wear a design's preset look (the Cosmetics picker).
static func wear_preset(id: String) -> bool:
	if not Designs.select(id):
		return false
	GameState.flags["lumi_style"] = preset(id)
	return true


# --- Saved looks ------------------------------------------------------------------------------

static func looks() -> Array:
	var v: Variant = GameState.flags.get("lumi_looks", [])
	var arr: Array = v if v is Array else []
	while arr.size() < MAX_LOOKS:
		arr.append({})
	if arr.size() > MAX_LOOKS:
		arr.resize(MAX_LOOKS)
	GameState.flags["lumi_looks"] = arr
	return arr


static func look(i: int) -> Dictionary:
	var arr: Array = looks()
	if i < 0 or i >= arr.size() or not (arr[i] is Dictionary) or (arr[i] as Dictionary).is_empty():
		return {}
	return normalize(arr[i])


static func save_look(i: int, style: Dictionary, look_name: String = "") -> bool:
	if i < 0 or i >= MAX_LOOKS:
		return false
	var s: Dictionary = normalize(style)
	s["name"] = look_name if look_name != "" else str(style.get("name", ""))
	looks()[i] = s
	return true


static func delete_look(i: int) -> void:
	if i >= 0 and i < MAX_LOOKS:
		looks()[i] = {}


# --- Unlocks ----------------------------------------------------------------------------------

static func bought() -> Array:
	var v: Variant = GameState.flags.get("style_bought", [])
	var arr: Array = v if v is Array else []
	GameState.flags["style_bought"] = arr
	return arr


## Unlock key for buying ("swatch:coral", "head:halo", "advanced_picker").
static func key_of(slot: String, id: String) -> String:
	return id if slot == "" else "%s:%s" % [slot, id]


static func unlock_met(u: Dictionary, key: String = "") -> bool:
	if u.is_empty() or dev_all:
		return true
	if u.has("design"):
		return Designs.is_unlocked(str(u["design"]))
	if u.has("lumi_level"):
		return LumiLevel.level() >= int(u["lumi_level"])
	if u.has("achievement"):
		return Achievements.is_unlocked(str(u["achievement"]))
	if u.has("cond"):
		var c: Dictionary = u["cond"]
		return Designs.cond_value(c) >= float(c.get("target", 1.0)) - 0.000001
	if u.has("cost"):
		return key != "" and key in bought()
	return false


## 0..1 toward the unlock (cost unlocks: how much of the price you hold).
static func unlock_progress(u: Dictionary, key: String = "") -> float:
	if unlock_met(u, key):
		return 1.0
	if u.has("design"):
		return Designs.progress(str(u["design"]))
	if u.has("lumi_level"):
		return clampf(float(LumiLevel.level()) / maxf(float(u["lumi_level"]), 1.0), 0.0, 1.0)
	if u.has("achievement"):
		return Achievements.progress(str(u["achievement"]))
	if u.has("cond"):
		var c: Dictionary = u["cond"]
		return clampf(Designs.cond_value(c) / maxf(float(c.get("target", 1.0)), 0.0001), 0.0, 1.0)
	if u.has("cost"):
		var best: float = 1.0
		var f: Dictionary = Currencies.fold(u["cost"])
		for id: String in f:
			best = minf(best, GameState.get_currency(id).to_float() / maxf(float(f[id]), 0.0001))
		return clampf(best, 0.0, 1.0)
	return 0.0


## How to unlock, translated ("Unlock the Bolt design", "Achievement: Gardener", "40 parts").
static func unlock_text(u: Dictionary) -> String:
	if u.is_empty():
		return ""
	if u.has("design"):
		var dn: String = TranslationServer.translate(str(Designs.def(str(u["design"])).get("name", u["design"])))
		return TranslationServer.translate("Unlock the %s design") % dn
	if u.has("lumi_level"):
		return TranslationServer.translate("Reach Lumi Level %d") % int(u["lumi_level"])
	if u.has("achievement"):
		var an: String = TranslationServer.translate(str(Achievements.def(str(u["achievement"])).get("name", u["achievement"])))
		return TranslationServer.translate("Achievement: %s") % an
	if u.has("cond"):
		return TranslationServer.translate(str(u.get("text", "")))
	if u.has("cost"):
		return TranslationServer.translate("Buy for %s") % Currencies.cost_text(u["cost"])
	return ""


static func option_unlocked(slot: String, id: String) -> bool:
	var o: Dictionary = option(slot, id)
	return not o.is_empty() and unlock_met(o.get("unlock", {}), key_of(slot, id))


static func swatch_unlocked(id: String) -> bool:
	var s: Dictionary = swatch(id)
	return not s.is_empty() and unlock_met(s.get("unlock", {}), key_of("swatch", id))


static func advanced_unlocked() -> bool:
	var a: Dictionary = data().get("advanced", {})
	return unlock_met(a.get("unlock", {}), str(a.get("id", "advanced_picker")))


## Pay a cost unlock once. `slot` = "swatch", a part slot, or "" for the advanced picker.
static func buy(slot: String, id: String) -> bool:
	var u: Dictionary
	if slot == "":
		u = (data().get("advanced", {}) as Dictionary).get("unlock", {})
	elif slot == "swatch":
		u = swatch(id).get("unlock", {})
	else:
		u = option(slot, id).get("unlock", {})
	var key: String = key_of(slot, id)
	if not u.has("cost") or key in bought():
		return false
	if not GameState.spend_all(u["cost"]):
		return false
	bought().append(key)
	return true


## Can this colour be worn (an unlocked swatch, or anything with the advanced picker)?
static func color_allowed(c: Color) -> bool:
	if advanced_unlocked():
		return true
	var s: Dictionary = swatch_for(c)
	return not s.is_empty() and swatch_unlocked(str(s["id"]))


## Is every part of the style unlocked? Colours that came from an unlocked preset are allowed
## too (the designs' own colours are always wearable).
static func allowed(style: Dictionary) -> bool:
	var s: Dictionary = normalize(style)
	for slot: String in PART_SLOTS:
		if not option_unlocked(slot, str(s[slot])):
			return false
	if not Designs.is_unlocked(str(s["bonus"])):
		return false
	var preset_cols: Array[Color] = []
	for id: String in preset_ids():
		if Designs.is_unlocked(id):
			var p: Dictionary = preset(id)
			for slot: String in COLOR_SLOTS:
				preset_cols.append(col(p, slot))
	for slot: String in COLOR_SLOTS:
		var c: Color = col(s, slot)
		if color_allowed(c):
			continue
		var ok: bool = false
		for pc: Color in preset_cols:
			ok = ok or _close(pc, c)
		if not ok:
			return false
	return true


## A random look from unlocked parts and swatches (the bonus stays).
static func randomized(rng: RandomNumberGenerator, base: Dictionary = {}) -> Dictionary:
	var s: Dictionary = normalize(base) if not base.is_empty() else current()
	var sw: Array = []
	for x: Dictionary in swatches():
		if swatch_unlocked(str(x["id"])):
			sw.append(swatch_color(x))
	if sw.is_empty():
		sw.append(Color.WHITE)
	# Paint light or dark, trim the other way, a bright glow; eyes/hover/laser usually match it.
	var paint: Color = sw[rng.randi() % sw.size()]
	var trim: Color = sw[rng.randi() % sw.size()]
	var tries: int = 0
	while absf(trim.get_luminance() - paint.get_luminance()) < 0.18 and tries < 12:
		trim = sw[rng.randi() % sw.size()]
		tries += 1
	var bright: Array = sw.filter(func(c: Color) -> bool: return c.s > 0.4 and c.v > 0.75)
	if bright.is_empty():
		bright = sw
	var glow: Color = bright[rng.randi() % bright.size()]
	set_value(s, "paint", paint)
	set_value(s, "trim", trim)
	set_value(s, "side", trim if rng.randf() < 0.6 else sw[rng.randi() % sw.size()])
	set_value(s, "accent", bright[rng.randi() % bright.size()])
	set_value(s, "glow", glow)
	set_value(s, "eyes", glow if rng.randf() < 0.75 else bright[rng.randi() % bright.size()])
	set_value(s, "hover", glow if rng.randf() < 0.7 else bright[rng.randi() % bright.size()])
	set_value(s, "laser", glow if rng.randf() < 0.6 else bright[rng.randi() % bright.size()])
	set_value(s, "wear", snappedf(rng.randf_range(0.2, 0.85), 0.05))
	for slot: String in PART_SLOTS:
		var ok: Array = []
		for o: Dictionary in options(slot):
			if option_unlocked(slot, str(o["id"])):
				ok.append(str(o["id"]))
		if not ok.is_empty():
			s[slot] = ok[rng.randi() % ok.size()]
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
	v["happy"] = 1.0 if s["eye_shape"] == "happy" else 0.5
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
	for slot: String in ["head", "shoulders", "held", "companion"]:
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
##   --lumi-random=SEED       wear a random look (every part unlocked first)
##   --lumi-set=slot:value,.. set slots (colours as hex without #, e.g. laser:ff3d8a)
##   --lumi-look=N            wear saved look N (0-4)
##   --lumi-builder           open the Character Builder (after --lumi-builder-at=S seconds, default 3)
##   --lumi-parts-all         unlock every part, swatch and the advanced picker
static func dev_hooks(world: Node) -> void:
	if DevHooks.has("lumi-parts-all") or DevHooks.has("lumi-random"):
		_dev_unlock_all()
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
			if p.size() == 2:
				set_value(s, p[0], ("#" + p[1]) if p[0] in COLOR_SLOTS else (float(p[1]) if p[0] == "wear" else p[1]))
		changed = true
	if changed:
		set_current(s)
		refresh_player(world)
	if DevHooks.has("lumi-builder") and world:
		var at: float = DevHooks.get_f("lumi-builder-at", 3.0)
		world.get_tree().create_timer(at, true).timeout.connect(func() -> void:
			LumiBuilder.open(world, world))


static func _dev_unlock_all() -> void:
	for id: String in Designs.ids():
		if not (id in Designs.unlocked()):
			Designs.unlocked().append(id)
	var b: Array = bought()
	for x: Dictionary in swatches():
		if (x.get("unlock", {}) as Dictionary).has("cost") and not (key_of("swatch", str(x["id"])) in b):
			b.append(key_of("swatch", str(x["id"])))
	for slot: String in PART_SLOTS:
		for o: Dictionary in options(slot):
			if (o.get("unlock", {}) as Dictionary).has("cost"):
				b.append(key_of(slot, str(o["id"])))
	b.append(str((data().get("advanced", {}) as Dictionary).get("id", "advanced_picker")))
	# Non-cost unlocks (achievements, conditions) are met for this run only (not saved).
	dev_all = true
