class_name LifeCfg
extends RefCounted
## [v6life] How the world comes back to life where Lumi cleans (owner items 58 and 62), from
## data/life.json: the green on clean ground (plants/cell_verdure.gd), the town stages
## (planet/sites/town_life.gd) and the butterflies (plants/flutter.gd). "_default" holds every
## value; a planet block ("verdance", "ochre", ...) repeats only what it changes. The sound bed
## that follows the ground is in data/sound.json (planets.<id>.ambience.life). See docs/ADJUSTING.md.

const PATH: String = "res://data/life.json"

static var planet_id: String = "verdance"
static var _cfg: Dictionary = {}
static var _loaded: bool = false


static func cfg() -> Dictionary:
	if not _loaded:
		_loaded = true
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f:
			var v: Variant = JSON.parse_string(f.get_as_text())
			if v is Dictionary:
				_cfg = v
			else:
				push_warning("[life] %s does not parse; using the built-in values" % PATH)
	return _cfg


## Picks the planet whose block overrides "_default" (the globe calls this before the life layers start).
static func use_planet(id: String) -> void:
	planet_id = id if id != "" else "verdance"


## One section ("ground", "town", "flutter") for the current planet: "_default" with the planet's keys on top.
static func section(sec: String) -> Dictionary:
	var planets: Variant = cfg().get("planets")
	if not (planets is Dictionary):
		return {}
	var out: Dictionary = {}
	for pid: String in ["_default", planet_id]:
		var p: Variant = (planets as Dictionary).get(pid)
		if p is Dictionary and (p as Dictionary).get(sec) is Dictionary:
			out.merge((p as Dictionary)[sec], true)
	return out


static func num(sec: String, key: String, fallback: float) -> float:
	var v: Variant = section(sec).get(key)
	return float(v) if (v is float or v is int) else fallback


static func integer(sec: String, key: String, fallback: int) -> int:
	return int(num(sec, key, float(fallback)))


## A list of numbers; the fallback unless the data gives `size` of them (any length when size is 0).
static func floats(sec: String, key: String, fallback: Array[float], size: int = 0) -> Array[float]:
	var v: Variant = section(sec).get(key)
	if not (v is Array) or (v as Array).is_empty() or (size > 0 and (v as Array).size() != size):
		return fallback
	var out: Array[float] = []
	for x: Variant in v:
		out.append(float(x) if (x is float or x is int) else 0.0)
	return out


static func ints(sec: String, key: String, fallback: Array[int], size: int = 0) -> Array[int]:
	var out: Array[int] = []
	for x: float in floats(sec, key, [], size):
		out.append(int(x))
	return out if not out.is_empty() else fallback


## Colours as [r, g, b] lists (0..1) or "#rrggbb" strings.
static func colors(sec: String, key: String, fallback: Array[Color]) -> Array[Color]:
	var v: Variant = section(sec).get(key)
	if not (v is Array) or (v as Array).is_empty():
		return fallback
	var out: Array[Color] = []
	for x: Variant in v:
		if x is String:
			out.append(Color.from_string(x, Color.WHITE))
		elif x is Array and (x as Array).size() >= 3:
			out.append(Color(float(x[0]), float(x[1]), float(x[2])))
	return out if not out.is_empty() else fallback
