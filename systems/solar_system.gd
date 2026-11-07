class_name SolarSystem
extends RefCounted
## [home] The Verdance system's binary star, the single source of truth for every sky
## (data/solar_system.json, docs/DECISIONS.md "Binary suns"). Every planet sees the same two suns,
## the warm primary Hearth and the small orange companion Ember; size and light fall off with the
## planet's orbital distance. Use:
##   SolarSystem.suns_for(id, primary_dir) -> {a: {dir, color, size, energy}, b: {...}}
##     dir: unit vector FROM the ground TOWARD the sun. a.dir = primary_dir (the sky director's sun
##     path); b.dir = a.dir turned by the planet's separation, so the pair rises and sets together.
##   SolarSystem.planet(id) -> the planet's entry (orbit_au, tilt_deg, day_length_s, moons, ...)
## Missing file or planet: the defaults below (the same ones the other helpers fall back to).

const PATH: String = "res://data/solar_system.json"
const DEFAULT_A := {"color": [1.0, 0.95, 0.85], "size": 1.0, "energy": 1.0}
const DEFAULT_B := {"color": [1.0, 0.62, 0.38], "size": 0.55, "energy": 0.25}
const DEFAULT_SEP: float = 14.0

static var _cfg: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		if FileAccess.file_exists(PATH):
			var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
			_cfg = d if d is Dictionary else {}
		if _cfg.is_empty():
			_cfg = {"star_a": DEFAULT_A, "star_b": DEFAULT_B, "planets": {}}
	return _cfg


static func planet(id: String) -> Dictionary:
	var p: Dictionary = cfg().get("planets", {})
	return p.get(id, p.get("verdance", {}))


static func orbit_au(id: String) -> float:
	return maxf(0.1, float(planet(id).get("orbit_au", 1.0)))


static func day_length(id: String, fallback: float = 1200.0) -> float:
	return float(planet(id).get("day_length_s", fallback))


static func _col(a: Variant, fb: Color) -> Color:
	if a is Array and (a as Array).size() >= 3:
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return fb


## The planet id of the current world: a fixed system planet, else Verdance's sky.
static func current_id() -> String:
	var k: int = Homeward.current_planet()
	return str(Homeward.planet_def(k).get("id", "verdance")) if k >= 0 else "verdance"


## The companion's direction from the primary's (pure).
static func companion_dir(primary: Vector3, sep_deg: float, sep_angle_deg: float) -> Vector3:
	var a: Vector3 = primary.normalized()
	if a.length() < 0.5:
		a = Vector3(0, 1, 0)
	var side: Vector3 = a.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var up: Vector3 = side.cross(a).normalized()
	var ang: float = deg_to_rad(sep_angle_deg)
	var tangent: Vector3 = (side * cos(ang) + up * sin(ang)).normalized()
	return a.rotated(a.cross(tangent).normalized(), -deg_to_rad(sep_deg)).normalized()


## What to render for planet `id` (see the class doc).
static func suns_for(id: String, primary_dir: Vector3 = Vector3(0.3, 0.8, -0.5)) -> Dictionary:
	var c: Dictionary = cfg()
	var p: Dictionary = planet(id)
	var au: float = orbit_au(id)
	var sa: Dictionary = c.get("star_a", DEFAULT_A)
	var sb: Dictionary = c.get("star_b", DEFAULT_B)
	var lo: float = float(c.get("min_energy", 0.35))
	var hi: float = float(c.get("max_energy", 1.6))
	var fall: float = 1.0 / (au * au)
	var a_dir: Vector3 = primary_dir.normalized()
	var b_dir: Vector3 = companion_dir(a_dir, float(p.get("sep_deg", DEFAULT_SEP)), float(p.get("sep_angle_deg", 30.0)))
	return {
		"a": {"dir": a_dir, "color": _col(sa.get("color"), Color(1.0, 0.95, 0.85)), "size": float(sa.get("size", 1.0)) / au,
			"energy": clampf(float(sa.get("energy", 1.0)) * fall, lo, hi)},
		"b": {"dir": b_dir, "color": _col(sb.get("color"), Color(1.0, 0.62, 0.38)), "size": float(sb.get("size", 0.55)) / au,
			"energy": clampf(float(sb.get("energy", 0.25)) * fall, lo * 0.25, hi * 0.4)},
		"orbit_au": au, "day_stars": bool(p.get("day_stars", false)),
	}
