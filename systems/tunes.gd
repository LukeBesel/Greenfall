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
const RESTORED_AT: float = 0.55  # fallback for cfg "restored_at"
## [v6sound] Drop-in songs: any of these in audio/songs/ or one folder below it (a planet id, or
## any other name for "everywhere"). A file with no entry in data/songs.json gets default_entry().
const EXTS: Array[String] = ["mp3", "ogg", "wav"]
## When a song may play (entry "moments"). docs/ADJUSTING.md, "Music and sound".
const MOMENTS: Array[String] = ["title", "intro", "explore", "night", "restored", "base_restored", "launch", "ending"]

static var _cfg: Dictionary = {}
static var _files: Dictionary = {}  # [v6sound] id -> res:// path of its audio file (scan_files)
static var _index: Dictionary = {}  # id -> entry
static var _broken: Dictionary = {}  # id -> true: the file is there but will not load (logged once)
static var _scanned: bool = false
static var _streams: Dictionary = {}  # id -> AudioStream
static var _glim: GDScript
static var _glim_checked: bool = false
## Tests: pretend these ids have (true) or lack (false) a file, whatever is on disk.
static var file_override: Dictionary = {}
static var _title_opened: bool = false  # [v1menu] the title has played its first song this launch


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(PATH)
		_scan()
	return _cfg


## Every song: the entries of data/songs.json, then the files that were dropped in with no entry.
static func songs() -> Array:
	return cfg().get("songs", [])


static func song(id: String) -> Dictionary:
	cfg()
	return _index.get(id, {})


## The main theme's id (cfg "main_theme"): first at launch, the most common, never twice in a row.
static func main_id() -> String:
	return str(cfg().get("main_theme", "greenfall_main"))


# --- Drop-in files [v6sound] ---------------------------------------------------------------

## "My New Song.mp3" -> "my_new_song".
static func slug(file_name: String) -> String:
	var out: String = ""
	for ch: String in file_name.get_basename().to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	return out.trim_prefix("_").trim_suffix("_")


## The audio files under `dir`: {id: {path, folder, name}}. One folder deep. In an exported game
## only the ".import" stubs are listed, so those count too.
static func scan_files(dir: String = DIR) -> Dictionary:
	var out: Dictionary = {}
	var folders: Array[String] = [""]
	for sub: String in DirAccess.get_directories_at(dir):
		folders.append(sub)
	for folder: String in folders:
		var base: String = dir.path_join(folder) if folder != "" else dir
		var names: Array = Array(DirAccess.get_files_at(base))
		names.sort()
		for f: String in names:
			var n: String = f.trim_suffix(".import").trim_suffix(".remap")
			if not EXTS.has(n.get_extension().to_lower()):
				continue
			var id: String = slug(n)
			if id == "" or out.has(id):
				continue
			out[id] = {"path": base.path_join(n), "folder": folder, "name": n.get_basename()}
	return out


## The entry a file gets when data/songs.json does not list it: title from the file name, owned
## from the start, in the background shuffle on its folder's planet (any other folder: everywhere).
static func default_entry(id: String, file_name: String, folder: String, planet_ids: Array) -> Dictionary:
	var t: String = file_name.replace("_", " ").strip_edges()
	if t == t.to_lower():
		t = t.capitalize()
	var d: Dictionary = cfg_defaults().duplicate(true)
	d.merge({"id": id, "title": t, "auto": true, "planets": [folder] if planet_ids.has(folder) else ["all"]}, true)
	return d


## cfg "defaults": what a dropped-in file with no entry gets.
static func cfg_defaults() -> Dictionary:
	var d: Dictionary = {"artist": "", "group": "story", "kind": "playlist", "unlock": "start", "bpm": 100,
		"weight": 1.0, "volume_db": 0.0, "moments": ["title", "explore", "night"], "desc": ""}
	var v: Variant = _cfg.get("defaults")
	if v is Dictionary:
		d.merge(v as Dictionary, true)
	return d


static func planet_ids() -> Array:
	var ids: Array = []
	var v: Variant = _cfg.get("planets")
	if v is Dictionary:
		ids = (v as Dictionary).keys().filter(func(k: Variant) -> bool: return not str(k).begins_with("_"))
	if ids.is_empty():
		ids = ["verdance", "ochre", "tidewell", "rime", "anvil"]
	return ids


static func _scan() -> void:
	_index.clear()
	_files.clear()
	var list: Array = _cfg.get("songs", [])
	if not _cfg.has("songs"):
		_cfg["songs"] = list
	var found_files: Dictionary = scan_files()
	var by_file: Dictionary = {}  # an entry may name its file: "file": "ochre/My Song.mp3"
	for s: Dictionary in list:
		_index[str(s["id"])] = s
		if s.has("file"):
			by_file[slug(str(s["file"]).get_file())] = str(s["id"])
	var ids: Array = planet_ids()
	var added: Array[String] = []
	for fid: String in found_files:
		var f: Dictionary = found_files[fid]
		var id: String = str(by_file.get(fid, fid))
		if not _index.has(id):
			var e: Dictionary = default_entry(id, str(f["name"]), str(f["folder"]), ids)
			list.append(e)
			_index[id] = e
			added.append(id)
		_files[id] = str(f["path"])
	if _scanned:
		return
	_scanned = true
	var missing: int = 0
	for id: String in _index:
		if not _files.has(id):
			missing += 1
	print("[tunes] %d songs listed, %d with a file, %d waiting for one (skipped)%s" % [_index.size() - added.size(),
		_files.size() - added.size(), missing, ("; picked up with defaults: " + ", ".join(added)) if not added.is_empty() else ""])


## Reads data/songs.json and the folder again (tests, or after files changed).
static func reload() -> void:
	_cfg = {}
	_streams.clear()
	_broken.clear()
	cfg()


## Where a song may play: [] = by its group (the old rule), else planet ids or "all".
static func planets_of(id: String) -> Array:
	var v: Variant = song(id).get("planets")
	if v is String:
		return [str(v)]
	return v if v is Array else []


## When a song may play (MOMENTS). Entries without "moments" get them from their kind.
static func moments(id: String) -> Array:
	var s: Dictionary = song(id)
	var v: Variant = s.get("moments")
	if v is String:
		return [str(v)]
	if v is Array:
		return v
	if s.is_empty():
		return []
	if not bool(s.get("shuffle", true)):
		return ["title"]
	match str(s.get("kind", "playlist")):
		"night":
			return ["title", "night"]
		"restored":
			return ["title", "restored"]
	return ["title", "explore", "night"]


static func has_moment(id: String, moment: String) -> bool:
	return moments(id).has(moment)


## True when the song may play on `planet` at all.
static func on_planet(id: String, planet: String) -> bool:
	var ps: Array = planets_of(id)
	if not ps.is_empty():
		return ps.has("all") or ps.has(planet)
	if planet_list(planet).has(id):
		return true
	var s: Dictionary = song(id)
	return str(s.get("kind", "playlist")) not in ["night", "restored"] or str(s.get("group", "")) == planet


## cfg "planets".<planet>: that planet's own playlist and rule overrides ({} if none).
static func planet_cfg(planet: String) -> Dictionary:
	var v: Variant = cfg().get("planets")
	if v is Dictionary and (v as Dictionary).get(planet) is Dictionary:
		return (v as Dictionary)[planet]
	return {}


## Songs a planet lists by hand (cfg planets.<planet>.songs): they play there at full weight.
static func planet_list(planet: String) -> Array:
	var v: Variant = planet_cfg(planet).get("songs")
	return v if v is Array else []


## A music rule (gap_s, main_share, ...): the planet's override if it has one, else the global one.
static func rule(key: String, planet: String, fallback: Variant) -> Variant:
	var pc: Dictionary = planet_cfg(planet)
	if pc.has(key):
		return pc[key]
	return cfg().get(key, fallback)


## Volume trim of a song in dB (entry "volume_db").
static func trim_db(id: String) -> float:
	return clampf(float(song(id).get("volume_db", 0.0)), -40.0, 12.0)


## Songs (files present) for a story moment on `planet`: "intro", "launch", "ending",
## "base_restored". These play whether or not the CD is owned.
static func moment_songs(moment: String, planet: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in available():
		if has_moment(id, moment) and (on_planet(id, planet) or planets_of(id).is_empty()):
			out.append(id)
	return out


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


## The song's audio file ("" until one is dropped in).
static func path(id: String) -> String:
	cfg()
	return str(_files.get(id, ""))


## True when the song's file is in the build (imported) or on disk, and loads.
static func has_file(id: String) -> bool:
	if _broken.has(id):
		return false
	if file_override.has(id):
		return bool(file_override[id])
	cfg()
	return _files.has(id)


## Loads the song (imported resource, else the raw file). null when missing or unreadable: the
## song is then skipped everywhere from now on and the reason is logged once.
static func stream(id: String) -> AudioStream:
	if _streams.has(id):
		return _streams[id]
	var s: AudioStream = null
	var p: String = path(id)
	if p != "":
		if ResourceLoader.exists(p):
			s = load(p) as AudioStream
		elif FileAccess.file_exists(p) and _file_size(p) > 256:  # an empty file is not a song
			match p.get_extension().to_lower():
				"mp3": s = AudioStreamMP3.load_from_file(p)
				"ogg": s = AudioStreamOggVorbis.load_from_file(p)
				"wav": s = AudioStreamWAV.load_from_file(p)
	if s != null and s.get_length() <= 0.05:
		s = null  # empty or damaged
	if s == null:
		mark_broken(id, "no file" if p == "" else "will not load: " + p)
	elif s.get("loop") != null:
		s.set("loop", false)  # the director loops and crossfades by hand
	_streams[id] = s
	return s


static func _file_size(p: String) -> int:
	var f := FileAccess.open(p, FileAccess.READ)
	return int(f.get_length()) if f else 0


## Skips a song everywhere from now on (logged once).
static func mark_broken(id: String, why: String) -> void:
	if not _broken.has(id):
		_broken[id] = true
		print("[tunes] skipping %s (%s)" % [id, why])


static func clear_cache() -> void:
	_streams.clear()
	_broken.clear()
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
		EventBus.toast.emit(toast_text(id), "info" if Once.take("toast_first_cd") else "reward")  # [v4calm] the first CD only
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

## Whether an owned song fits the background shuffle right now. [v6sound] By its "planets" and
## "moments" (data/songs.json); entries without them follow their group and kind as before.
static func fits(id: String, planet: String, mood: String, restoration: float) -> bool:
	var s: Dictionary = song(id)
	if s.is_empty() or not on_planet(id, planet):
		return false
	var ms: Array = moments(id)
	if ms.has("night" if mood in NIGHT_MOODS else "explore"):
		return true
	return ms.has("restored") and restoration >= float(rule("restored_at", planet, RESTORED_AT))


## Background weight: songs from this planet first, story-neutral ones now and then, other
## planets' songs rarely. Times the song's own "weight".
static func weight(id: String, planet: String) -> float:
	var s: Dictionary = song(id)
	var own: float = maxf(0.0, float(s.get("weight", 1.0)))
	var group: String = str(s.get("group", ""))
	if group == planet or not planets_of(id).is_empty() or planet_list(planet).has(id):
		return own
	if group == "story":
		return own * float(rule("story_weight", planet, 0.5))
	return own * float(rule("other_planet_weight", planet, 0.12))


## The next background song ("" when nothing fits). Never the last one twice in a row while
## another fits; avoids the last few when it can.
static func pick_next(planet: String, mood: String, restoration: float, recent: Array, rng: RandomNumberGenerator) -> String:
	var pool: Array[String] = []
	for id: String in found():
		if fits(id, planet, mood, restoration):
			pool.append(id)
	return pick_main_rule(pool, recent, rng, func(id: String) -> float: return weight(id, planet),
		float(rule("main_share", planet, 0.6)))  # [v1menu]


## [v1menu] The owner's rules for the title and the background shuffle (2026-11-08): the main theme
## is the most common song (picked with probability `share`, cfg main_share, whenever it may play),
## the other songs are mixed in by `w`, and the main theme never plays twice in a row (the intro's
## cinematic song in between does not count). "" when only the main theme fits and it just played.
static func pick_main_rule(pool: Array[String], recent: Array, rng: RandomNumberGenerator, w: Callable, share: float = -1.0) -> String:
	var main: String = main_id()
	if share < 0.0:
		share = float(cfg().get("main_share", 0.6))
	var last: String = last_heard(recent)
	var others: Array[String] = []
	for id: String in pool:
		if id != main:
			others.append(id)
	var main_ok: bool = main in pool and last != main
	if main_ok and (others.is_empty() or rng.randf() < share):
		return main
	return _weighted(others, recent, rng, w)


## The last song heard before now, skipping cinematic songs (the intro's score).
static func last_heard(recent: Array) -> String:
	for i: int in range(recent.size() - 1, -1, -1):
		if str(song(str(recent[i])).get("kind", "")) != "cinematic" and not has_moment(str(recent[i]), "intro"):
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
		first = main_id()
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


## [v6sound] A story moment ("launch", "ending", "base_restored"): plays one of the songs marked
## for it on this planet, once, over the shuffle. False (and nothing changes) when no song is
## marked for it, so the synth score keeps its part.
static func play_moment(moment: String) -> bool:
	var d: Node = director()
	return d != null and bool(d.call("play_moment", moment))


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
