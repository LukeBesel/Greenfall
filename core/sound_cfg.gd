class_name SoundCfg
extends RefCounted
## [v6sound] The mix and the per-planet ambience from data/sound.json: slider defaults, bus trims,
## which bus a sound plays on, per-sound trims and shortest gaps, the voice duck, and each planet's
## score theme and ambience bed. See docs/ADJUSTING.md, "Music and sound".

const PATH: String = "res://data/sound.json"
const BUSES: Array[String] = ["Music", "Songs", "Ambience", "SFX", "UI"]

static var _cfg: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():  # read here, not through Economy: Settings asks before that autoload is up
		var f := FileAccess.open(PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text()) if f else null
		if parsed is Dictionary:
			_cfg = parsed
		else:
			push_error("Missing or bad data file: %s" % PATH)
			_cfg = {"_missing": true}
	return _cfg


static func _d(key: String) -> Dictionary:
	var v: Variant = cfg().get(key)
	return v if v is Dictionary else {}


## Where a Settings slider starts for a new player: master, music, ambience, sfx, ui.
static func volume_default(slider: String, fallback: float) -> float:
	return clampf(float(_d("volumes").get(slider, fallback)), 0.0, 1.0)


static func bus_trim_db(bus: String) -> float:
	return float(_d("bus_trim_db").get(bus, 0.0))


## The bus a named sound plays on ("SFX" unless bus_of says otherwise).
static func bus_of(sound: String) -> String:
	return str(_d("bus_of").get(sound, "SFX"))


static func sound_db(sound: String) -> float:
	return float(_d("sound_db").get(sound, 0.0))


## Shortest time (game seconds) between two plays of `sound`; 0 = no limit.
static func min_gap(sound: String) -> float:
	var g: Dictionary = _d("min_gap_s")
	return maxf(0.0, float(g.get(sound, g.get("_default", 0.0))))


static func duck(key: String, fallback: float) -> float:
	return float(_d("duck").get(key, fallback))


static func planet(id: String) -> Dictionary:
	var v: Variant = _d("planets").get(id)
	return v if v is Dictionary else {}


## The built-in score theme a planet uses ("" when it names none).
static func theme_of(id: String) -> String:
	return str(planet(id).get("theme", ""))


## A planet's ambience bed: {level_db, loops, events} ({} when it has none).
static func ambience(id: String) -> Dictionary:
	var v: Variant = planet(id).get("ambience")
	return v if v is Dictionary else {}
