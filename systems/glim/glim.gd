class_name Glim
extends RefCounted
## [buddy] Glim, the little lantern bot that follows Lumi: pure state and rules (data/glim.json).
## State lives in GameState.flags["glim"] (saved with the game):
##   {found: bool, tiers: {track_id: int}, shells, glows, tops: String (the worn look ids)}
## Looks are found pieces like Lumi's (CrewLooks), worn and changed only at the Locker.
## The scene side is systems/glim/glim_director.gd (bot, scanner, magnet, panel).

const FLAG: String = "glim"
const SLOTS: Array[String] = ["shells", "glows", "tops"]
const DEFAULT_LOOK: Dictionary = {"shells": "pearl", "glows": "cyan", "tops": "antenna"}

## Player-facing reasons and hints returned in English below (translated where shown).
# l10n:begin
const STRINGS: Array[String] = ["Find Glim first", "Maxed", "Needs %s %d", "Glim", "Find the little lantern bot in the junk"]
# l10n:end

static var _data: Dictionary = {}
## Dev / tests: every look counts as found.
static var dev_all: bool = false


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/glim.json", FileAccess.READ)
		if f:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_data = d
	return _data


static func st() -> Dictionary:
	var s: Variant = GameState.flags.get(FLAG)
	if not (s is Dictionary):
		s = {}
		GameState.flags[FLAG] = s
	var d: Dictionary = s
	if not d.has("found"):
		d["found"] = false
	if not (d.get("tiers") is Dictionary):
		d["tiers"] = {}
	for slot: String in SLOTS:
		if not d.has(slot):
			d[slot] = DEFAULT_LOOK[slot]
	return d


static func is_found() -> bool:
	return bool(st()["found"])


static func set_found(v: bool = true) -> void:
	st()["found"] = v


# --- Discovery ------------------------------------------------------------------------------

## Glim turns up in the junk once Lumi has played long enough AND scooped enough pieces.
static func ready_to_find(time_played_s: float, pieces: int) -> bool:
	var f: Dictionary = data().get("found", {})
	return time_played_s >= float(f.get("min_time_s", 300.0)) and pieces >= int(f.get("min_pieces", 25))


## Clock speed while Glim is still lost: longer days, quicker nights (planet/sky_director.gd).
static func clock_mult(time_of_day: float) -> float:
	if is_found():
		return 1.0
	var c: Dictionary = data().get("clock", {})
	return float(c.get("night_before", 1.5)) if is_night(time_of_day) else float(c.get("day_before", 0.6))


static func is_night(time_of_day: float) -> bool:
	return time_of_day < 0.24 or time_of_day > 0.76


# --- Upgrade tracks -------------------------------------------------------------------------

static func tracks() -> Array:
	return data().get("tracks", [])


static func track(id: String) -> Dictionary:
	for t: Variant in tracks():
		if str((t as Dictionary).get("id", "")) == id:
			return t
	return {}


static func tier(id: String) -> int:
	return int((st()["tiers"] as Dictionary).get(id, 0))


static func max_tier(id: String) -> int:
	return (track(id).get("tiers", []) as Array).size()


static func total_tiers() -> int:
	var n: int = 0
	for t: Variant in tracks():
		n += tier(str((t as Dictionary)["id"]))
	return n


## The track's value dict at its current tier (index 0 = not upgraded).
static func values(id: String) -> Dictionary:
	var v: Array = track(id).get("values", [])
	if v.is_empty():
		return {}
	return v[clampi(tier(id), 0, v.size() - 1)]


static func value(id: String, key: String, fallback: float = 0.0) -> float:
	return float(values(id).get(key, fallback))


## Cost of the next tier ({} when maxed).
static func next_cost(id: String) -> Dictionary:
	var tiers: Array = track(id).get("tiers", [])
	var t: int = tier(id)
	if t >= tiers.size():
		return {}
	return (tiers[t] as Dictionary).get("cost", {})


## "" when the track can be bought now (ignoring money), else why not (English, tr() at display).
static func block_reason(id: String) -> String:
	if not is_found():
		return "Find Glim first"
	if track(id).is_empty():
		return "Unknown"
	if tier(id) >= max_tier(id):
		return "Maxed"
	var req: Dictionary = track(id).get("requires", {})
	for k: String in req:
		if tier(k) < int(req[k]):
			return "Needs %s %d" % [str(track(k).get("name", k)), int(req[k])]
	return ""


static func can_buy(id: String) -> bool:
	return block_reason(id) == "" and GameState.can_afford_all(next_cost(id))


static func buy(id: String) -> bool:
	if block_reason(id) != "":
		return false
	if not GameState.spend_all(next_cost(id)):
		return false
	(st()["tiers"] as Dictionary)[id] = tier(id) + 1
	GameState.inc_stat("upgrades_bought")
	EventBus.upgrade_bought.emit("glim_" + id, tier(id))
	return true


## The Music upgrade: Glim carries the found CDs (the "tunes" helper's library gates its
## play-anywhere quick-select on this).
static func has_music() -> bool:
	return is_found() and tier("music") >= 1


## [tunes] What's playing from the found-CD library ("" = nothing), and its tempo. Looked up by
## class name (Tunes.now_playing() / Tunes.bpm()) so this works with or without that branch;
## falls back to the radio / music track override.
static func song_playing() -> String:
	var t: Script = _tunes()
	if t:
		return str(t.call("now_playing"))
	return Audio.get_music_track() if Audio.has_method("get_music_track") else ""


static func song_bpm() -> float:
	var t: Script = _tunes()
	if t and _has_static(t, "bpm"):
		return maxf(40.0, float(t.call("bpm")))
	return 100.0


static var _tunes_script: Variant = false


static func _tunes() -> Script:
	if _tunes_script is bool:
		_tunes_script = null
		for c: Dictionary in ProjectSettings.get_global_class_list():
			if str(c.get("class", "")) == "Tunes":
				_tunes_script = load(str(c["path"]))
				break
	var s: Script = _tunes_script as Script
	return s if s and _has_static(s, "now_playing") else null


static func _has_static(s: Script, fn: String) -> bool:
	for m: Dictionary in s.get_script_method_list():
		if str(m.get("name", "")) == fn:
			return true
	return false


# --- Looks ----------------------------------------------------------------------------------

static func looks(slot: String) -> Array:
	return data().get(slot, [])


static func look(slot: String, id: String) -> Dictionary:
	for l: Variant in looks(slot):
		if str((l as Dictionary).get("id", "")) == id:
			return l
	return {}


## A look is worn only once its piece is found (CrewLooks; the planet's `finds` table hides it).
## Glim's own first looks are starting pieces.
static func look_unlocked(slot: String, id: String) -> bool:
	if look(slot, id).is_empty():
		return false
	return dev_all or CrewLooks.has(CrewLooks.GLIM, slot, id)


## The piece that stands for a look ("" when none does).
static func piece_of(slot: String, id: String) -> String:
	return CrewLooks.piece(CrewLooks.GLIM, slot, id)


static func wear(slot: String, id: String) -> bool:
	if not look_unlocked(slot, id):
		return false
	st()[slot] = id
	return true


static func worn(slot: String) -> String:
	var id: String = str(st()[slot])
	return id if not look(slot, id).is_empty() else str(DEFAULT_LOOK[slot])


static func worn_color(slot: String) -> Color:
	return Color.html(str(look(slot, worn(slot)).get("color", "#ffffff")))
