class_name Tunes
extends RefCounted
## [tunes] The song library: the owner's songs (audio/songs/<id>.mp3, listed in data/songs.json)
## and the CDs that unlock them. Pure rules are static (tests, the save round trip); playback is
## audio/tunes_director.gd, a child of the Audio autoload, reached through the helpers below.
##
## - A song whose file is missing is skipped everywhere, so new MP3s can be dropped in by id.
## - You start with the songs in "start"; every other song is a CD found in the rubble of its
##   planet (planet/cd_finds.gd). Owned CDs: GameState.flags.songs.found (in the order found).
## - The background shuffle (pick_next) plays owned songs that fit the planet and the moment;
##   the CD player (systems/extras/radio.gd) plays a pick on repeat or the whole collection on
##   shuffle. With Glim's Music upgrade (Glim.has_music(), wt/buddy) any CD plays anywhere.

const PATH: String = "res://data/songs.json"
const DIR: String = "res://audio/songs/"
const SHUFFLE: String = "shuffle"
const NIGHT_MOODS: Array[String] = ["night"]
const RESTORED_AT: float = 0.55

static var _cfg: Dictionary = {}
static var _exists: Dictionary = {}  # id -> bool (file check cache)
static var _streams: Dictionary = {}  # id -> AudioStream
static var _glim: GDScript
static var _glim_checked: bool = false
## Tests: pretend these ids have (true) or lack (false) a file, whatever is on disk.
static var file_override: Dictionary = {}
static var _title_opened: bool = false  # [v1menu] the title has played its first song this launch


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(PATH)
	return _cfg


static func songs() -> Array:
	return cfg().get("songs", [])


static func song(id: String) -> Dictionary:
	for s: Dictionary in songs():
		if str(s["id"]) == id:
			return s
	return {}


static func artists() -> Array:
	return cfg().get("artists", [])


static func artist(id: String) -> Dictionary:
	for a: Dictionary in artists():
		if str(a["id"]) == id:
			return a
	return {}


## Display title / artist name of a song (English; tr() where shown).
static func title(id: String) -> String:
	return str(song(id).get("title", id))


static func artist_name(id: String) -> String:
	return str(artist(str(song(id).get("artist", ""))).get("name", ""))


static func bpm_of(id: String) -> float:
	return float(song(id).get("bpm", 100.0))


static func path(id: String) -> String:
	return DIR + id + ".mp3"


## True when the song's MP3 is in the build (imported) or on disk.
static func has_file(id: String) -> bool:
	if file_override.has(id):
		return bool(file_override[id])
	if not _exists.has(id):
		var p: String = path(id)
		_exists[id] = not song(id).is_empty() and (ResourceLoader.exists(p) or FileAccess.file_exists(p))
	return bool(_exists[id])


## Loads the song (imported resource, else the raw MP3). null when missing.
static func stream(id: String) -> AudioStream:
	if _streams.has(id):
		return _streams[id]
	var s: AudioStream = null
	var p: String = path(id)
	if ResourceLoader.exists(p):
		s = load(p) as AudioStream
	elif FileAccess.file_exists(p):
		s = AudioStreamMP3.load_from_file(p)
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = false  # the director loops and crossfades by hand
	_streams[id] = s
	return s


static func clear_cache() -> void:
	_streams.clear()
	_glim = null
	_glim_checked = false


## Song ids whose files exist (data order).
static func available() -> Array[String]:
	var out: Array[String] = []
	for s: Dictionary in songs():
		if has_file(str(s["id"])):
			out.append(str(s["id"]))
	return out


# --- Owned CDs ---------------------------------------------------------------------------

static func st() -> Dictionary:
	var v: Variant = GameState.flags.get("songs")
	if not (v is Dictionary):
		v = {}
		GameState.flags["songs"] = v
	var d: Dictionary = v
	if not (d.get("found") is Array):
		d["found"] = []
	return d


static func is_start(id: String) -> bool:
	return str(song(id).get("unlock", "cd")) == "start"


static func is_found(id: String) -> bool:
	if song(id).is_empty():
		return false
	return is_start(id) or id in (st()["found"] as Array)


## Owned songs that can play (start songs plus found CDs, files present), data order.
static func found() -> Array[String]:
	var out: Array[String] = []
	for id: String in available():
		if is_found(id):
			out.append(id)
	return out


static func found_count() -> int:
	return found().size()


## Adds a CD to the collection (true if new). Announces it unless quiet.
static func grant(id: String, quiet: bool = false) -> bool:
	if song(id).is_empty() or is_found(id):
		return false
	(st()["found"] as Array).append(id)
	GameState.inc_stat("cds_found")
	print("[tunes] CD found: %s" % id)
	if not quiet:
		EventBus.toast.emit(toast_text(id), "info")
		Audio.play("sparkle", 1.1, -6.0)
	return true


static func toast_text(id: String) -> String:
	return TranslationServer.translate("New CD: %s by %s, from %s") % [TranslationServer.translate(title(id)),
		TranslationServer.translate(artist_name(id)), planet_name(home(id))]


## The planet the song's artist lived on: its intact CD is found there.
static func home(id: String) -> String:
	var a: Dictionary = artist(str(song(id).get("artist", "")))
	return str(a.get("home", song(id).get("found_on", "")))


static func artist_home(artist_id: String) -> String:
	return str(artist(artist_id).get("home", ""))


# --- Scratched CDs: one play, then they break -------------------------------------------

static func scratch_cfg() -> Dictionary:
	return cfg().get("scratched", {})


## Scratched CDs in the CD case (song ids, may repeat).
static func held() -> Array:
	var st_: Dictionary = st()
	if not (st_.get("scratched") is Array):
		st_["scratched"] = []
	return st_["scratched"]


static func case_size() -> int:
	return int(scratch_cfg().get("case_size", 4))


static func case_full() -> bool:
	return held().size() >= case_size()


## Keeps a scratched CD for later (false when the case is full or the song is owned already).
static func hold(id: String) -> bool:
	if case_full() or is_found(id) or song(id).is_empty():
		return false
	held().append(id)
	return true


## Songs a scratched CD may carry on `planet`: ones you don't own yet (files present), not
## already in your case. Other planets' songs first; never an owned song.
static func scratch_candidates(planet: String) -> Array[String]:
	var other: Array[String] = []
	var here: Array[String] = []
	for id: String in available():
		if is_found(id) or id in held():
			continue
		if home(id) == planet:
			here.append(id)
		else:
			other.append(id)
	return other if not other.is_empty() else here


static func plays() -> Dictionary:
	var st_: Dictionary = st()
	if not (st_.get("plays") is Dictionary):
		st_["plays"] = {}
	return st_["plays"]


static func note_play(id: String) -> void:
	plays()[id] = int(plays().get(id, 0)) + 1


static func play_count(id: String) -> int:
	return int(plays().get(id, 0))


## Plays a held scratched CD once (it breaks at the end). False if not in the case.
static func play_scratched(id: String) -> bool:
	if not (id in held()) or not has_file(id):
		return false
	var d: Node = director()
	if d == null:
		return false
	return bool(d.call("play_once", id))


## The scratched CD finished: it breaks and leaves the case.
static func break_scratched(id: String) -> void:
	var h: Array = held()
	var i: int = h.find(id)
	if i >= 0:
		h.remove_at(i)
	note_play(id)
	GameState.inc_stat("scratched_cds_played")


## CDs still to find on a planet (files present, not owned), data order.
static func cds_left(planet: String) -> Array[String]:
	var out: Array[String] = []
	for s: Dictionary in songs():
		var id: String = str(s["id"])
		if str(s.get("unlock", "cd")) == "cd" and str(s.get("found_on", "")) == planet and has_file(id) and not is_found(id):
			out.append(id)
	return out


## The planet a CD is found on ("" for start songs).
static func found_on(id: String) -> String:
	return str(song(id).get("found_on", home(id)))


static func planet_name(planet: String) -> String:
	var k: int = Homeward.planet_index(planet)
	return Homeward.planet_name(k) if k >= 0 else TranslationServer.translate(planet.capitalize())


## Artists with at least one owned song (data order). The Codex lists only these.
static func known_artists() -> Array[String]:
	var out: Array[String] = []
	var have: Array[String] = found()
	for a: Dictionary in artists():
		for id: String in have:
			if str(song(id).get("artist", "")) == str(a["id"]):
				out.append(str(a["id"]))
				break
	return out


static func songs_by(artist_id: String) -> Array[String]:
	var out: Array[String] = []
	for s: Dictionary in songs():
		if str(s.get("artist", "")) == artist_id and has_file(str(s["id"])):
			out.append(str(s["id"]))
	return out


# --- Shuffle -----------------------------------------------------------------------------

## Whether an owned song fits the background shuffle right now.
static func fits(id: String, planet: String, mood: String, restoration: float) -> bool:
	var s: Dictionary = song(id)
	if s.is_empty() or not bool(s.get("shuffle", true)):
		return false
	var group: String = str(s.get("group", ""))
	match str(s.get("kind", "playlist")):
		"night":
			return group == planet and mood in NIGHT_MOODS
		"restored":
			return group == planet and restoration >= RESTORED_AT
	return true


## Background weight: songs from this planet first, story-neutral ones now and then, other
## planets' songs rarely.
static func weight(id: String, planet: String) -> float:
	var group: String = str(song(id).get("group", ""))
	if group == planet:
		return 1.0
	if group == "story":
		return float(cfg().get("story_weight", 0.5))
	return float(cfg().get("other_planet_weight", 0.12))


## The next background song ("" when nothing fits). Never the last one twice in a row while
## another fits; avoids the last few when it can.
static func pick_next(planet: String, mood: String, restoration: float, recent: Array, rng: RandomNumberGenerator) -> String:
	var pool: Array[String] = []
	for id: String in found():
		if fits(id, planet, mood, restoration):
			pool.append(id)
	return pick_main_rule(pool, recent, rng, func(id: String) -> float: return weight(id, planet))  # [v1menu]


## [v1menu] The owner's rules for the title and the background shuffle (2026-11-08): the main theme
## is the most common song (picked with probability cfg main_share whenever it may play), the
## other songs are mixed in by `w`, and the main theme never plays twice in a row (the intro's
## cinematic song in between does not count). "" when only the main theme fits and it just played.
static func pick_main_rule(pool: Array[String], recent: Array, rng: RandomNumberGenerator, w: Callable) -> String:
	const MAIN_ID: String = "greenfall_main"
	var last: String = last_heard(recent)
	var others: Array[String] = []
	for id: String in pool:
		if id != MAIN_ID:
			others.append(id)
	var main_ok: bool = MAIN_ID in pool and last != MAIN_ID
	if main_ok and (others.is_empty() or rng.randf() < float(cfg().get("main_share", 0.6))):
		return MAIN_ID
	return _weighted(others, recent, rng, w)


## The last song heard before now, skipping cinematic songs (the intro's score).
static func last_heard(recent: Array) -> String:
	for i: int in range(recent.size() - 1, -1, -1):
		if str(song(str(recent[i])).get("kind", "")) != "cinematic":
			return str(recent[i])
	return ""


## The CD player's shuffle: every owned song, evenly.
static func pick_any(recent: Array, rng: RandomNumberGenerator) -> String:
	return _weighted(found(), recent, rng, func(_id: String) -> float: return 1.0)


static func _weighted(pool: Array[String], recent: Array, rng: RandomNumberGenerator, w: Callable) -> String:
	if pool.is_empty():
		return ""
	var cand: Array[String] = pool.duplicate()
	# Drop the most recent songs, newest last to go, while at least one is left.
	for i: int in range(recent.size() - 1, -1, -1):
		if cand.size() <= 1:
			break
		var depth: int = recent.size() - 1 - i
		if depth >= maxi(1, int(pool.size() / 2.0)):
			break
		cand.erase(str(recent[i]))
	var total: float = 0.0
	for id: String in cand:
		total += maxf(0.0, float(w.call(id)))
	if total <= 0.0:
		return cand[rng.randi_range(0, cand.size() - 1)]
	var r: float = rng.randf() * total
	for id: String in cand:
		r -= maxf(0.0, float(w.call(id)))
		if r <= 0.0:
			return id
	return cand[cand.size() - 1]


# --- Glim's Music upgrade (wt/buddy; looked up at runtime so either branch runs alone) --

static func glim_music() -> bool:
	if DevHooks.has("glim-music"):
		return true
	if not _glim_checked:
		_glim_checked = true
		for c: Dictionary in ProjectSettings.get_global_class_list():
			if str(c.get("class", "")) == "Glim":
				_glim = load(str(c["path"])) as GDScript
	if _glim == null:
		return false
	return bool(_glim.call("has_music"))


# --- Playback (audio/tunes_director.gd) --------------------------------------------------

static func director() -> Node:
	return Audio.get_node_or_null("TunesDirector")


## The owned song audible now ("" in a gap, under the synth score, or when nothing plays).
static func now_playing() -> String:
	var d: Node = director()
	return str(d.call("current")) if d else ""


## Tempo of the song playing now (Glim bobs to it). 100 when none.
static func bpm() -> float:
	var id: String = now_playing()
	return bpm_of(id) if id != "" else 100.0


## [tunes] The title screen's songs: the owned songs of the save shown on the title (start songs
## plus its found CDs), or on a brand-new save any song. [v1menu] The main theme first every time
## the game opens, then pick_main_rule.
static func setup_title(save: Dictionary) -> void:
	var d: Node = director()
	if d == null:
		return
	var pool: Array[String] = []
	var first: String = ""
	var main_w: float = 1.0
	if not save.is_empty():
		var fl: Variant = save.get("flags", {})
		var sv: Variant = (fl as Dictionary).get("songs", {}) if fl is Dictionary else {}
		var got: Variant = (sv as Dictionary).get("found", []) if sv is Dictionary else []
		for id: String in available():
			if is_start(id) or (got is Array and id in (got as Array)):
				pool.append(id)
	else:
		pool = available()
		main_w = 3.0

	if not _title_opened:  # [v1menu] the main theme first whenever the game opens
		_title_opened = true
		first = "greenfall_main"
	d.call("set_menu_pool", pool, first, main_w)
	print("[tunes] title pool %s (first %s)" % [",".join(pool), first if first != "" else "-"])
	set_context("menu")


## "menu" (title), "intro" (the opening cinematic), "play" (the background shuffle) or "none".
static func set_context(c: String) -> void:
	var d: Node = director()
	if d:
		d.call("set_context", c)


static func context() -> String:
	var d: Node = director()
	return str(d.get("context")) if d else ""


## The CD player / Glim: play one owned song on repeat. False if not owned or missing.
static func play(id: String) -> bool:
	if not is_found(id) or not has_file(id):
		return false
	var d: Node = director()
	if d:
		d.call("set_radio", id)
	return true


## Every owned song back to back, at random.
static func shuffle() -> void:
	var d: Node = director()
	if d:
		d.call("set_radio", SHUFFLE)


## Back to the background music.
static func stop() -> void:
	var d: Node = director()
	if d:
		d.call("set_radio", "")


## "" (background), "shuffle" or a song id.
static func radio_mode() -> String:
	var d: Node = director()
	return str(d.get("radio")) if d else ""


## Quick-select (needs Glim's Music upgrade): Shuffle / Pick / Off.
static func open_picker(world: Node) -> void:
	if world == null or not glim_music():
		return
	var p: Node = world.get_node_or_null("TunesPicker")
	if p and p.has_method("open"):
		p.call("open")
