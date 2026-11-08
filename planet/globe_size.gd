class_name GlobeSize
extends RefCounted
## [orbE] How big each planet's walkable globe is (owner, Nov 8: planets differ in size). Read
## from data/planets.json `<id>.globe` ({"radius_scale": f} or {"radius_m": m}) when orbB has
## added it, else the owner's numbers relative to Verdance (R 1,840 m, 163,842 hexes). Maps and
## the sky read this instead of assuming Verdance's size.

const VERDANCE_R: float = 1840.0
const DEFAULT_SCALE: Dictionary = {"verdance": 1.0, "ochre": 0.85, "tidewell": 1.1, "rime": 1.2, "anvil": 1.35}
const PATH: String = "res://data/planets.json"

static var _cache: Dictionary = {}


## Radius relative to Verdance's globe.
static func scale_of(id: String) -> float:
	id = id.to_lower()
	if _cache.has(id):
		return float(_cache[id])
	var s: float = float(DEFAULT_SCALE.get(id, 1.0))
	if FileAccess.file_exists(PATH):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary and (d as Dictionary).get(id) is Dictionary:
			var g: Variant = ((d as Dictionary)[id] as Dictionary).get("globe")
			if g is Dictionary:
				if (g as Dictionary).has("radius_scale"):
					s = float(g["radius_scale"])
				elif (g as Dictionary).has("radius_m"):
					s = float(g["radius_m"]) / VERDANCE_R
	_cache[id] = s
	return s


static func radius_m(id: String) -> float:
	return VERDANCE_R * scale_of(id)


## Hex count at the same 10 m hexes (area grows with the square of the radius).
static func cells_of(id: String) -> int:
	return int(round(163842.0 * pow(scale_of(id), 2.0)))
