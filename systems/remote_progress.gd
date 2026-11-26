class_name RemoteProgress
extends RefCounted
## [scope] Remote progress: robots on the other worlds of the profile keep working while Lumi is
## somewhere else AND THE GAME IS RUNNING, at `remote_factor` (data/telescope.json) of their full
## rate. Owner item 110: "They work when I am in different locations and on different planets but
## not when I log off." So nothing here reads the system clock:
##   - every second of play (EventBus.sim_tick: not paused, not behind the loading screen) adds to
##     the `away_s` of every OTHER visited world's record in the Cradle profile (tick());
##   - landing on a world pays its crews for its `away_s` and sets it back to 0 (arrive()): on the
##     round planet the crews' hub regions are really cleaned (OrbitCrews.catch_up), so the same
##     junk can't pay twice;
##   - the telescope shows the same number live while you watch (pending()).
## Closing the game stops the count; the clock moving (either way) changes nothing.
## Hard caps: CAP_S of away play time per stay, and the junk the crews' regions have left.
## Snapshots of other worlds are read-only: their saves are read, never written.
## Pure helpers are static and tested in tests/test_remote_progress.gd.

const CFG_PATH: String = "res://data/telescope.json"
const DEFAULT_FACTOR: float = 0.25
const DEFAULT_MIN_AWAY_S: float = 120.0
## The most away play time one stay elsewhere can pay for.
const CAP_S: float = 8.0 * 3600.0
## Mean junk units per district hex (37 hexes of 10 m, measured on Verdance's Old Town).
const AVG_HEX_UNITS: float = 337.0

## Play seconds counted since the last tick() pass over the world records.
static var _acc: float = 0.0
## True when a world record changed and the profile wants saving (flush()).
static var _dirty: bool = false
static var _cfg: Dictionary = {}
## Dev / screenshots: a synthetic visited world (no save on disk), see sample_snapshot().
static var sample: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(CFG_PATH) if FileAccess.file_exists(CFG_PATH) else {}
	return _cfg


static func factor() -> float:
	return float(cfg().get("remote_factor", DEFAULT_FACTOR))


static func care_cfg() -> Dictionary:
	return cfg().get("care", {"cost_cubes": 400, "boost_s": 300.0, "boost_mult": 2.0})


# --- Pure maths --------------------------------------------------------------------------

## Effective work seconds: elapsed plus the extra speed of a boost, never past the cap.
static func effective_seconds(elapsed_s: float, boost_s: float = 0.0, boost_mult: float = 1.0) -> float:
	var e: float = maxf(elapsed_s, 0.0)
	var b: float = clampf(boost_s, 0.0, e)
	return minf(e + b * maxf(boost_mult - 1.0, 0.0), CAP_S)


## Remote gains for a fleet that worked `elapsed_s` seconds of play unwatched, at `f` of the full
## rate (CrewRate.fleet_work), capped by the junk left. Keys: seconds, units, cubes,
## waiting_value (bales with no hauler, paid all the same), elapsed.
static func compute(robots: Array, elapsed_s: float, junk_left: float = INF, boost_s: float = 0.0, boost_mult: float = 1.0, f: float = -1.0) -> Dictionary:
	if f < 0.0:
		f = factor()
	var r: Dictionary = CrewRate.fleet_work(robots, effective_seconds(elapsed_s, boost_s, boost_mult), junk_left, f)
	r["elapsed"] = minf(maxf(elapsed_s, 0.0), CAP_S)
	return r


## compute() with a care-package boost whose extra cubes are capped at `care.extra_cap` x its cost,
## so a package can help a crew but never turns cubes here into more cubes there.
static func compute_boosted(robots: Array, elapsed_s: float, left: float, boost_s: float, f: float = -1.0) -> Dictionary:
	var c: Dictionary = care_cfg()
	var base: Dictionary = compute(robots, elapsed_s, left, 0.0, 1.0, f)
	if boost_s <= 0.0:
		return base
	var r: Dictionary = compute(robots, elapsed_s, left, boost_s, float(c.get("boost_mult", 2.0)), f)
	var cap: float = float(c.get("cost_cubes", 400)) * float(c.get("extra_cap", 0.75))
	var extra: float = float(r["cubes"]) + float(r["waiting_value"]) - float(base["cubes"]) - float(base["waiting_value"])
	if extra > cap:
		var k: float = cap / extra
		for key: String in ["cubes", "waiting_value"]:
			r[key] = float(base[key]) + (float(r[key]) - float(base[key])) * k
		r["units"] = float(base["units"]) + (float(r["units"]) - float(base["units"])) * k
	r["boost_extra"] = minf(extra, cap)
	return r


## Junk units still on a saved district: junk hexes x the mean.
static func junk_left(snap: Dictionary) -> float:
	return maxf(0.0, float(snap.get("junk_hexes", 0)) * AVG_HEX_UNITS)


## Share of a district's land hexes that are no longer junk (0..1), from saved clean bits and levels.
static func district_share(clean: PackedByteArray, levels: PackedByteArray) -> float:
	var land: int = 0
	var done: int = 0
	for i: int in clean.size():
		var lv: int = levels[i] if i < levels.size() else 0
		if clean[i] == 0:
			land += 1
		elif lv >= 1:
			land += 1
			done += 1
	return float(done) / float(land) if land > 0 else 1.0


## Hex state for the remote view: 0 junk, 1 clean, 2 green (planted and up), -1 base / not land.
static func hex_state(clean: int, level: int) -> int:
	if clean == 0:
		return 0
	if level >= 2:
		return 2
	return 1 if level == 1 else -1


# --- World records and snapshots ------------------------------------------------------------

## Profile worlds other than the current one that have a save (or the dev sample).
static func visited_worlds() -> Array:
	var out: Array = []
	for w: Dictionary in CradleMode.worlds():
		if int(w.get("index", 0)) == CradleMode.current_index():
			continue
		if SaveManager.has_save(int(w.get("slot", 0))):
			out.append(w)
	if not sample.is_empty():
		out.append(sample["world"])
	return out


static func world_record(index: int) -> Dictionary:
	for w: Dictionary in CradleMode.worlds():
		if int(w.get("index", -1)) == index:
			return w
	if not sample.is_empty() and int((sample["world"] as Dictionary).get("index", -2)) == index:
		return sample["world"]
	return {}


## Read-only snapshot of a world's base district from its save (empty when there is none).
static func snapshot(w: Dictionary) -> Dictionary:
	if not sample.is_empty() and w == sample["world"]:
		return sample["snap"]
	var slot: int = int(w.get("slot", 0))
	var p: String = SaveManager.slot_path(slot)
	if not FileAccess.file_exists(p):
		return {}
	return snapshot_from_save(SaveManager.read_dict(p), w)


## Pure: a snapshot from a save dictionary (SaveManager format) and its profile record.
static func snapshot_from_save(d: Dictionary, w: Dictionary = {}) -> Dictionary:
	if d.is_empty():
		return {}
	var hub: int = int(d.get("current_hub", 0))
	var dist: Dictionary = d.get("world", {})
	var ds: Dictionary = d.get("districts", {})
	if ds.has(str(hub)) and ds[str(hub)] is Dictionary:
		dist = ds[str(hub)]
	var fd: Dictionary = dist.get("field", {})
	var clean: PackedByteArray = Marshalls.base64_to_raw(str(fd.get("clean", ""))) if fd.has("clean") else PackedByteArray()
	var hl: Dictionary = dist.get("hex_levels", {})
	var levels: PackedByteArray = Marshalls.base64_to_raw(str(hl.get("levels", ""))) if hl.has("levels") else PackedByteArray()
	var radius: int = int(fd.get("radius", 3))
	var n: int = Hex.spiral(radius).size()
	if clean.size() != n:
		clean = PackedByteArray()
		clean.resize(n)
		clean.fill(0)
		clean[0] = 1
	if levels.size() != n:
		levels.resize(n)
	var robots: Array = []
	for r: Variant in dist.get("robots", []):
		if r is Dictionary:
			robots.append({"type": str(r.get("type", "scoopie")), "tier": int(r.get("tier", 0))})
	var junk: int = 0
	for i: int in n:
		if clean[i] == 0:
			junk += 1
	return {
		"name": str(w.get("name", "Verdance")), "type": str(w.get("type", "")), "index": int(w.get("index", 0)),
		"planet_id": str(w.get("planet_id", w.get("planet", ""))),
		"saved_unix": float(d.get("saved_unix", 0.0)), "hub": hub, "hub_level": int(dist.get("hub_level", 1)),
		"radius": radius, "clean": clean, "levels": levels, "robots": robots, "junk_hexes": junk,
		"share": district_share(clean, levels),
	}


## A believable mid-game world for screenshots and the dev hook (--scope-sample).
static func make_sample() -> void:
	var radius: int = 3
	var axial: Array[Vector2i] = Hex.spiral(radius)
	var clean := PackedByteArray()
	var levels := PackedByteArray()
	clean.resize(axial.size())
	levels.resize(axial.size())
	for i: int in axial.size():
		var a: Vector2i = axial[i]
		var ring: int = maxi(absi(a.x), maxi(absi(a.y), absi(-a.x - a.y)))
		if ring == 0:
			clean[i] = 1
		elif ring == 1:
			clean[i] = 1
			levels[i] = 4 if i % 2 == 0 else 3
		elif ring == 2:
			clean[i] = 1 if i % 3 != 0 else 0
			levels[i] = 2 if clean[i] == 1 and i % 2 == 0 else (1 if clean[i] == 1 else 0)
	var robots: Array = [{"type": "scoopie", "tier": 2}, {"type": "scoopie", "tier": 1}, {"type": "scoopie", "tier": 2},
		{"type": "haulbug", "tier": 1}, {"type": "haulbug", "tier": 2}, {"type": "drip", "tier": 1}, {"type": "seedling", "tier": 1}]
	var w: Dictionary = {"index": 90, "name": "Tidewell", "type": "ocean_world", "slot": -1, "planet_id": "tidewell", "away_s": 0.4 * 3600.0}
	var snap: Dictionary = snapshot_from_save({"saved_unix": Time.get_unix_time_from_system() - 0.4 * 3600.0, "current_hub": 0,
		"world": {"hub_level": 4, "robots": robots, "field": {"radius": radius, "clean": Marshalls.raw_to_base64(clean)},
		"hex_levels": {"levels": Marshalls.raw_to_base64(levels)}}}, w)
	sample = {"world": w, "snap": snap}


# --- The away count (play time only), live estimate and arrival ------------------------------------

## Play seconds Lumi has spent elsewhere since she left world `w` (never past CAP_S).
static func away_s(w: Dictionary) -> float:
	return clampf(float(w.get("away_s", 0.0)), 0.0, CAP_S)


## Seconds of a care package still to run on world `w`, and the seconds of it already worked.
static func boost_left(w: Dictionary) -> float:
	return maxf(0.0, float(w.get("boost_left_s", 0.0)))


static func boost_used(w: Dictionary) -> float:
	return maxf(0.0, float(w.get("boost_used_s", 0.0)))


## Adds `dt` seconds of play to one world record that Lumi is not on (pure: no profile, no clock).
static func add_away(w: Dictionary, dt: float) -> void:
	if dt <= 0.0:
		return
	w["away_s"] = minf(float(w.get("away_s", 0.0)) + dt, CAP_S)
	var bl: float = boost_left(w)
	if bl > 0.0:
		var d: float = minf(bl, dt)
		w["boost_left_s"] = bl - d
		w["boost_used_s"] = boost_used(w) + d


## Called with every simulation step of play (automation/telescope.gd on EventBus.sim_tick, which
## stands still while the game is paused or loading). Once a second the other visited worlds'
## records get the time. Seed of the Week runs are a side game: they count for nothing.
static func tick(dt: float) -> void:
	if WeeklyChallenge.active:
		return
	_acc += dt
	if _acc < 1.0:
		return
	var step: float = _acc
	_acc = 0.0
	for w: Dictionary in visited_worlds():
		if not sample.is_empty() and w == sample["world"]:
			continue
		add_away(w, step)
		_dirty = true


## Writes the profile if the away counts moved (with every save of the game).
static func flush() -> void:
	if _dirty:
		_dirty = false
		CradleMode.save_profile()


## What the crew on a saved world has earned since Lumi left it (live, for the telescope).
static func pending(snap: Dictionary, w: Dictionary, extra_s: float = 0.0) -> Dictionary:
	return compute_boosted(snap.get("robots", []), away_s(w) + extra_s, junk_left(snap), boost_used(w))


## Called once when a world is up (scenes/slice_orbit.gd, after the crew is restored): this
## world's crews catch up on the play time Lumi spent on other worlds, and she is paid for it.
## The count is set back to 0 whatever happens, so it can never pay twice. Returns the catch-up
## result ({} when there was nothing to pay).
static func arrive(crews: OrbitCrews) -> Dictionary:
	var w: Dictionary = CradleMode.current_world()
	var t: float = away_s(w)
	var bo: float = boost_used(w)
	var had: bool = w.has("away_s") or w.has("boost_left_s") or w.has("boost_used_s")
	for k: String in ["away_s", "boost_left_s", "boost_used_s"]:
		w.erase(k)
	if had:
		CradleMode.save_profile()
	if WeeklyChallenge.active or crews == null or crews.crew == null or crews.crew.robots().is_empty():
		return {}
	if t < float(cfg().get("min_away_s", DEFAULT_MIN_AWAY_S)):
		return {}
	# A care package's extra is capped (compute_boosted): take the same share of extra seconds.
	var fleet: Array = []
	for u: Dictionary in crews.crew.robots():
		fleet.append({"type": u["type"], "tier": u["tier"]})
	var plain: Dictionary = compute(fleet, t)
	var boosted: Dictionary = compute_boosted(fleet, t, INF, bo)
	var k_boost: float = float(boosted["units"]) / float(plain["units"]) if float(plain["units"]) > 0.0 else 1.0
	var res: Dictionary = crews.catch_up(minf(t, CAP_S) * k_boost, factor())
	res["elapsed"] = minf(t, CAP_S)
	var pay: float = float(res["cubes"]) + float(res["waiting_value"])
	if pay > 0.0:
		GameState.add_currency("cubes", BigNum.from_float(pay))
		GameState.inc_stat("remote_cubes", pay)
	return res


static func arrival_text(res: Dictionary) -> String:
	var pay: float = float(res.get("cubes", 0.0)) + float(res.get("waiting_value", 0.0))
	var t: float = float(res.get("elapsed", 0.0))
	var when: String = (TranslationServer.translate("%d min") % int(t / 60.0)) if t < 3600.0 else ("%.1f h" % (t / 3600.0))
	return TranslationServer.translate("While you were on another planet (%s of play), your robots here earned %s cubes.") % [when, Settings.fmt(BigNum.from_float(pay))]


# --- Care package ------------------------------------------------------------------------------

static func care_cost() -> float:
	return float(care_cfg().get("cost_cubes", 400))


## "" when a care package can go to world w now, else why not.
static func care_block_reason(w: Dictionary) -> String:
	if w.is_empty():
		return TranslationServer.translate("No world in view.")
	if boost_left(w) > 0.0:
		return TranslationServer.translate("A care package is already on its way.")
	if not GameState.can_afford("cubes", BigNum.from_float(care_cost())):
		return TranslationServer.translate("Needs %s cubes.") % Settings.fmt(BigNum.from_float(care_cost()))
	return ""


## Sends a care package: the crew on world `w` works at boost_mult for the next boost_s seconds
## of play (counted by add_away, so it waits while the game is closed or paused).
static func send_care(w: Dictionary) -> bool:
	if care_block_reason(w) != "":
		return false
	GameState.spend("cubes", BigNum.from_float(care_cost()))
	w["boost_left_s"] = float(care_cfg().get("boost_s", 300.0))
	GameState.inc_stat("care_packages")
	CradleMode.save_profile()
	return true
