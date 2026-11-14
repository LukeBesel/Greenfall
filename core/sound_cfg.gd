class_name SoundCfg
extends RefCounted
## [v6sound] The mix and the per-planet ambience from data/sound.json: slider defaults, bus trims,
## which bus a sound plays on, per-sound trims and shortest gaps, the voice duck, and each planet's
## score theme and ambience bed. See docs/ADJUSTING.md, "Music and sound".

const PATH: String = "res://data/sound.json"
const BUSES: Array[String] = ["Music", "Songs", "Ambience", "SFX", "UI"]
const OFF_DB: float = -80.0  # a sound_db trim this low mutes the sound

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


## Trim of a sound in dB. With a tag (where it plays from: "scoop", "lumi"...), "tag:sound" wins
## over "sound". OFF_DB or lower mutes it.
static func sound_db(sound: String, tag: String = "") -> float:
	var d: Dictionary = _d("sound_db")
	if tag != "" and d.has(tag + ":" + sound):
		return float(d[tag + ":" + sound])
	return float(d.get(sound, 0.0))


## Shortest time (game seconds) between two plays of `sound`; 0 = no limit. With a tag,
## "tag:sound" wins over "sound", and its plays are counted apart from the others.
static func min_gap(sound: String, tag: String = "") -> float:
	var g: Dictionary = _d("min_gap_s")
	if tag != "" and g.has(tag + ":" + sound):
		return maxf(0.0, float(g[tag + ":" + sound]))
	return maxf(0.0, float(g.get(sound, g.get("_default", 0.0))))


## [v9s] data/sound.json "variety": per sound ("tag:sound" wins over "sound", then "_default").
static func _variety(block: String, sound: String, tag: String) -> Variant:
	var v: Variant = _d("variety").get(block)
	if not (v is Dictionary):
		return null
	var d: Dictionary = v
	if tag != "" and d.has(tag + ":" + sound):
		return d[tag + ":" + sound]
	return d.get(sound, d.get("_default"))


## At most this many of one sound at once (0 = no cap).
static func max_voices(sound: String, tag: String = "") -> int:
	var v: Variant = _variety("max_voices", sound, tag)
	return int(v) if v != null else 0


## [window_s, dB per repeat, max dB]: the 2nd..nth play within window_s of the last comes softer.
static func soften(sound: String, tag: String = "") -> Array:
	var v: Variant = _variety("soften", sound, tag)
	return v if v is Array and (v as Array).size() >= 3 else []


## The least random pitch spread (+-, as a share) a play of the sound gets.
static func pitch_spread(sound: String, tag: String = "") -> float:
	var v: Variant = _variety("pitch_spread", sound, tag)
	return clampf(float(v), 0.0, 0.5) if v != null else 0.0


## Roots (semitones) a new scoop combo's ladder starts on, one picked per combo.
static func ladder_roots() -> Array:
	var v: Variant = _d("variety").get("ladder_roots")
	return v if v is Array else []


static func duck(key: String, fallback: float) -> float:
	return float(_d("duck").get(key, fallback))


## [v7planet] A planet's block. A planet of data/planets.json with no block gets planets._default; a block (or the
## default) with "like": "<other id>" starts from that planet's block and changes only the keys it
## gives (top level: theme, ambience). Blocks without "like" are used as they are.
static func planet(id: String) -> Dictionary:
	var ps: Dictionary = _d("planets")
	var own: Variant = ps.get(id)
	if own is Dictionary and not (own as Dictionary).has("like"):
		return own
	# planets._default only for a planet of data/planets.json: an unknown id still has no block (ignored).
	var src: Variant = own if own is Dictionary else (ps.get("_default") if PlanetCfg.has(id) else null)
	if not (src is Dictionary):
		return {}
	var out: Dictionary = {}
	var like: String = str((src as Dictionary).get("like", ""))
	if like != "" and like != id and ps.get(like) is Dictionary and not (ps[like] as Dictionary).has("like"):
		out = (ps[like] as Dictionary).duplicate(true)
	for k: Variant in src:
		if str(k) != "like" and not str(k).begins_with("_"):
			out[k] = (src as Dictionary)[k]
	return out


## The built-in score theme a planet uses ("" when it names none).
static func theme_of(id: String) -> String:
	return str(planet(id).get("theme", ""))


## A planet's ambience bed: {level_db, loops, events} ({} when it has none).
static func ambience(id: String) -> Dictionary:
	var v: Variant = planet(id).get("ambience")
	return v if v is Dictionary else {}
