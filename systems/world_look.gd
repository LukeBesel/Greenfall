class_name WorldLook
extends RefCounted
## [worlds2] What a Cradle Mode world looks like (data/world_looks.json): its sky grade, a body in
## the sky, the city's tint and weathering, the base yard's dressing and its landmark, plus what
## the world's modifiers add (Long Nights: darker nights, Heavy Rain: puddles and wet junk, Rich
## Salvage: shiny junk). Pure and static; planet/world_look_view.gd puts it in the scene, and
## CityView / StreetDressing read `current()` while they build.
## Verdance (world 0) has no look: everything stays exactly as the campaign built it.

const PATH: String = "res://data/world_looks.json"

static var _cfg: Dictionary = {}
## Tests and shots can force a look ("" = follow the current world).
static var override_type: String = ""
static var override_mods: Array = []


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(PATH)
	return _cfg


static func type_ids() -> Array:
	return (cfg().get("types", {}) as Dictionary).keys()


## The full look for a world type with its modifiers (pure). {} for Verdance / unknown types
## without modifiers that change anything.
static func look_for(type_id: String, mods: Array = []) -> Dictionary:
	var types: Dictionary = cfg().get("types", {})
	if not types.has(type_id):
		return {}
	var out: Dictionary = (types[type_id] as Dictionary).duplicate(true)
	out["type"] = type_id
	var dress: Dictionary = out.get("dress", {})
	var mcfg: Dictionary = cfg().get("modifiers", {})
	for mid: Variant in mods:
		var m: Dictionary = mcfg.get(str(mid), {})
		if m.is_empty():
			continue
		if m.has("night_dark"):
			out["night_dark"] = maxf(float(out.get("night_dark", 0.0)), float(m["night_dark"]))
		if m.has("puddles_mult"):
			dress["puddles"] = float(dress.get("puddles", 1.0)) * float(m["puddles_mult"])
		if m.has("junk_wet"):
			out["junk_wet"] = float(m["junk_wet"])
		if m.has("junk_shine"):
			out["junk_shine"] = float(m["junk_shine"])
		if m.has("fog_mult") and out.has("grade"):
			var g: Dictionary = out["grade"]
			g["fog_mult"] = float(g.get("fog_mult", 1.0)) * float(m["fog_mult"])
	out["dress"] = dress
	out["mods"] = mods.duplicate()
	return out


## [worlds2] The look of a planet id (data/world_looks.json "planets": planet id -> look type, or
## {"look": type, ...overrides}), so a fixed solar system can map its planets onto these looks.
## A planet id that is itself a look type works too. {} for unknown ids.
static func look_for_planet(planet_id: String, mods: Array = []) -> Dictionary:
	var pl: Variant = (cfg().get("planets", {}) as Dictionary).get(planet_id, planet_id)
	if pl is String:
		return look_for(str(pl), mods)
	if pl is Dictionary:
		var out: Dictionary = look_for(str((pl as Dictionary).get("look", "")), mods)
		if out.is_empty():
			return out
		for k: Variant in pl:
			if str(k) != "look":
				out[k] = (pl as Dictionary)[k]
		out["planet"] = planet_id
		return out
	return {}


# --- Planet registry hook (data/planets.json, planet/planets/<id>/env.gd) -------------------

const PLANETS_PATH: String = "res://data/planets.json"
static var _planets: Dictionary = {}


## The shared planet registry as {id: entry} (accepts {"planets": [{id...}]}, {"planets": {id: {}}}
## or a bare {id: {}} map). {} when the file does not exist.
static func planets() -> Dictionary:
	if _planets.is_empty() and FileAccess.file_exists(PLANETS_PATH):
		var raw: Dictionary = Economy.read_json(PLANETS_PATH)
		var src: Variant = raw.get("planets", raw)
		if src is Array:
			for e: Variant in src:
				if e is Dictionary and (e as Dictionary).has("id"):
					_planets[str(e["id"])] = e
		elif src is Dictionary:
			for k: Variant in src:
				if not str(k).begins_with("_") and src[k] is Dictionary:
					_planets[str(k)] = src[k]
	return _planets


## The current world's planet id: its record's "planet" (or "look") key; "" when it has none.
static func planet_id() -> String:
	if CradleMode.profile.is_empty():
		return ""
	var w: Dictionary = CradleMode.current_world()
	return str(w.get("planet", w.get("look", "")))


## A planet's environment script (its registry "env" path, else planet/planets/<id>/env.gd when
## that file exists); "" when the planet has none and the generic look does everything.
static func env_path(id: String) -> String:
	if id == "":
		return ""
	var e: Dictionary = planets().get(id, {})
	var p: String = str(e.get("env", "res://planet/planets/%s/env.gd" % id))
	return p if ResourceLoader.exists(p) else ""


## The current world's look ({} on Verdance). A world record may name its look ("look": a planet
## id or look type); otherwise its world type is used.
static func current() -> Dictionary:
	if override_type != "":
		return look_for(override_type, override_mods)
	if CradleMode.profile.is_empty() or CradleMode.current_index() <= 0:
		return {}
	var w: Dictionary = CradleMode.current_world()
	var mods: Array = w.get("modifiers", [])
	if DevHooks.has("world-mods"):  # dev (shots): --world-mods=heavy_rain+long_nights
		mods = Array(DevHooks.get_s("world-mods", "").split("+", false))
	var pid: String = str(w.get("planet", w.get("look", w.get("type", ""))))
	var lk: Dictionary = look_for_planet(pid, mods)
	if lk.is_empty() and planets().has(pid):  # a registry planet: its "look" type, else its world type
		lk = look_for_planet(str((planets()[pid] as Dictionary).get("look", w.get("type", ""))), mods)
	if not lk.is_empty() and planets().has(pid):
		lk["planet"] = pid
	return lk


static func is_active() -> bool:
	return not current().is_empty()


## How far this district has come, 0 (ruined) to 1 (restored): the base level or the share of the
## field cleaned, whichever is further along (pure).
static func progress(hub_level: int, clean_frac: float) -> float:
	return clampf(maxf(float(hub_level - 1) / 4.0, clean_frac), 0.0, 1.0)


## The world's sky grade strength at this progress: full at first, easing toward clear air (pure).
static func grade_amount(look: Dictionary, prog: float) -> float:
	return clampf(1.0 - float(look.get("restore_ease", 0.4)) * clampf(prog, 0.0, 1.0), 0.0, 1.0)


## Weathering on the city: heavy when ruined, about half when restored (pure).
static func weather_amount(prog: float) -> float:
	return lerpf(1.0, 0.5, clampf(prog, 0.0, 1.0))


static func col(a: Variant, fallback: Color = Color.WHITE) -> Color:
	if a is Array and (a as Array).size() >= 3:
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return fallback


## City facade tint (white when there is no look).
static func city_tint(look: Dictionary) -> Color:
	return col((look.get("city", {}) as Dictionary).get("tint", []), Color.WHITE)


static func city_style(look: Dictionary) -> String:
	return str((look.get("city", {}) as Dictionary).get("style", ""))


static func landmark(look: Dictionary) -> String:
	return str(look.get("landmark", ""))


## The junk coat for this world (systems/late_director.gd): the world type's coat from
## data/cradle.json (or Heavy Rain's), made wetter by Heavy Rain and shinier by Rich Salvage.
## Returns {} when nothing should coat the junk. Keys: coat (Color), top, film, roughness, metal, spec.
static func junk_coat(type_coat: Array, look: Dictionary, rain_coat: Array = []) -> Dictionary:
	var c: Array = type_coat if type_coat.size() >= 6 else rain_coat
	var wet: float = float(look.get("junk_wet", 0.0))
	var shine: float = float(look.get("junk_shine", 0.0))
	if c.size() < 6 and shine <= 0.0 and wet <= 0.0:
		return {}
	var bare: bool = c.size() < 6
	if bare:
		c = [0.62, 0.64, 0.66, 0.0, 0.12, 0.5]  # no cover: a thin film that carries the finish
	var out: Dictionary = {"coat": Color(float(c[0]), float(c[1]), float(c[2])), "top": float(c[3]), "film": float(c[4]),
		"roughness": float(c[5]), "metal": 0.0, "spec": 0.3}
	if wet > 0.0:
		out["roughness"] = minf(float(out["roughness"]), lerpf(float(out["roughness"]), 0.3, wet))
		out["film"] = float(out["film"]) + 0.08 * wet
		out["spec"] = 0.45
	if shine > 0.0:
		# Better stuff: less grime over it and a clean metallic glint (the coat thins out).
		out["top"] = float(out["top"]) * lerpf(1.0, 0.55, shine)
		if bare:
			out["coat"] = Color(0.8, 0.8, 0.82)
			out["film"] = 0.24 * shine
		else:
			out["film"] = maxf(float(out["film"]) * 0.6, 0.16)
		out["roughness"] = minf(float(out["roughness"]), 0.2)
		out["metal"] = (0.7 if bare else 0.35) * shine
		out["spec"] = 0.75
	return out


## Unit direction to a sky body from its yaw/elevation in degrees (pure; yaw 180 = -Z, the
## default view from the base).
static func sky_dir(body: Dictionary) -> Vector3:
	var yaw: float = deg_to_rad(float(body.get("yaw", 180.0)))
	var el: float = deg_to_rad(float(body.get("elev", 25.0)))
	return Vector3(sin(yaw) * cos(el), sin(el), cos(yaw) * cos(el)).normalized()
