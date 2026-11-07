class_name RemoteProgress
extends RefCounted
## [scope] Remote progress: robots on the other worlds of the profile keep working while Lumi is
## somewhere else, at `remote_factor` (data/telescope.json) of the offline rate. The maths is the
## one offline function, Offline.compute (core/offline.gd), so its rates, the 8 h cap and the
## "junk left" cap are shared, never duplicated:
##   remote cubes = Offline.compute(robots, elapsed (+ care-package boost), junk_left / f) x f
## When it pays: on arrival at a world by world travel (CradleMode.switch_world loads it in memory,
## so the slice skips its own offline payout). The window starts at that world's last save, which
## is the moment Lumi left it. A cold start onto a world gets the normal offline payout instead,
## never both. The units paid count into the district's `offline_units`, like the offline payout,
## so the same junk can't pay twice. The telescope shows the same number live while you watch.
## Snapshots of other worlds are read-only: their saves are read, never written.
## Pure helpers are static and tested in tests/test_remote_progress.gd.

const CFG_PATH: String = "res://data/telescope.json"
const DEFAULT_FACTOR: float = 0.5
const DEFAULT_MIN_AWAY_S: float = 120.0
## Mean junk units per district hex (37 hexes of 10 m, measured on Verdance's Old Town).
const AVG_HEX_UNITS: float = 337.0

## The world index the last district ran on (this session only; -1 before the first one).
static var last_world: int = -1
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

## Seconds of a boost window [b_from, b_until] that fall inside [t0, t1].
static func boost_overlap(t0: float, t1: float, b_from: float, b_until: float) -> float:
	return maxf(0.0, minf(t1, b_until) - maxf(t0, b_from))


## Effective work seconds: elapsed plus the extra speed of a boost, never past the offline cap.
static func effective_seconds(elapsed_s: float, boost_s: float = 0.0, boost_mult: float = 1.0) -> float:
	var e: float = maxf(elapsed_s, 0.0)
	var b: float = clampf(boost_s, 0.0, e)
	return minf(e + b * maxf(boost_mult - 1.0, 0.0), Offline.CAP_S)


## Remote gains for a fleet away `elapsed_s` seconds. Same keys as Offline.compute; cubes and
## units are scaled by `f`, the junk cap applies after scaling, waiting bales are paid like offline.
static func compute(robots: Array, elapsed_s: float, junk_left: float = INF, boost_s: float = 0.0, boost_mult: float = 1.0, f: float = -1.0) -> Dictionary:
	if f < 0.0:
		f = factor()
	var t: float = effective_seconds(elapsed_s, boost_s, boost_mult)
	var cap: float = INF if is_inf(junk_left) else maxf(junk_left, 0.0) / maxf(f, 0.0001)
	var r: Dictionary = Offline.compute(robots, 0, 0.0, t, cap)
	r["units"] = float(r["units"]) * f
	r["cubes"] = float(r["cubes"]) * f
	r["waiting_value"] = float(r["waiting_value"]) * f
	r["air"] = 0.0
	r["elapsed"] = minf(maxf(elapsed_s, 0.0), Offline.CAP_S)
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


## Junk units still on a saved district: junk hexes x the mean, minus what offline already paid.
static func junk_left(snap: Dictionary) -> float:
	return maxf(0.0, float(snap.get("junk_hexes", 0)) * AVG_HEX_UNITS - float(snap.get("offline_units", 0.0)))


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
	var flags: Dictionary = d.get("flags", {})
	return {
		"name": str(w.get("name", "Verdance")), "type": str(w.get("type", "")), "index": int(w.get("index", 0)),
		"planet_id": str(w.get("planet_id", w.get("planet", ""))),
		"saved_unix": float(d.get("saved_unix", 0.0)), "hub": hub, "hub_level": int(dist.get("hub_level", 1)),
		"radius": radius, "clean": clean, "levels": levels, "robots": robots, "junk_hexes": junk,
		"offline_units": float(dist.get("offline_units", 0.0)), "share": district_share(clean, levels),
		"ledger_act": int(flags.get("ledger_act", 0)), "ledger_resolved": bool(flags.get("ledger_resolved", false)),
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
	var w: Dictionary = {"index": 90, "name": "Tidewell", "type": "ocean_world", "slot": -1, "planet_id": "tidewell"}
	var snap: Dictionary = snapshot_from_save({"saved_unix": Time.get_unix_time_from_system() - 0.4 * 3600.0, "current_hub": 0,
		"world": {"hub_level": 4, "robots": robots, "field": {"radius": radius, "clean": Marshalls.raw_to_base64(clean)},
		"hex_levels": {"levels": Marshalls.raw_to_base64(levels)}}, "flags": {"ledger_act": 2}}, w)
	sample = {"world": w, "snap": snap}


# --- Live estimate and arrival -----------------------------------------------------------------

## Boost window of a world's care package: [from, until] (unix), or [0, 0].
static func boost_window(w: Dictionary) -> Array:
	var b: Variant = w.get("scope_boost", [])
	if b is Array and (b as Array).size() == 2:
		return [float(b[0]), float(b[1])]
	return [0.0, 0.0]


## What the crew on a saved world has earned since Lumi left it (live, for the telescope).
static func pending(snap: Dictionary, w: Dictionary, now: float = -1.0) -> Dictionary:
	if now < 0.0:
		now = Time.get_unix_time_from_system()
	var t0: float = float(snap.get("saved_unix", now))
	var bw: Array = boost_window(w)
	var bo: float = boost_overlap(t0, now, float(bw[0]), float(bw[1]))
	return compute_boosted(snap.get("robots", []), now - t0, junk_left(snap), bo)


## Called once per district start (automation/telescope.gd). Pays remote gains when this district
## was reached by world travel from another world (from_memory); otherwise the offline payout ran.
static func on_district_ready(from_memory: bool, now: float = -1.0) -> Dictionary:
	var here: int = CradleMode.current_index()
	var came_from: int = last_world
	last_world = here
	if not from_memory or came_from < 0 or came_from == here or GameState.saved_unix <= 0.0:
		return {}
	if now < 0.0:
		now = Time.get_unix_time_from_system()
	var away: float = now - GameState.saved_unix
	if away < float(cfg().get("min_away_s", DEFAULT_MIN_AWAY_S)):
		return {}
	var w: Dictionary = CradleMode.current_world()
	var bw: Array = boost_window(w)
	var bo: float = boost_overlap(GameState.saved_unix, now, float(bw[0]), float(bw[1]))
	var left: float = live_junk_left()
	var res: Dictionary = compute_boosted(GameState.world.get("robots", []), away, left, bo)
	GameState.world["offline_units"] = float(GameState.world.get("offline_units", 0.0)) + float(res["units"])
	var pay: float = float(res["cubes"]) + float(res["waiting_value"])
	if pay > 0.0:
		GameState.add_currency("cubes", BigNum.from_float(pay))
		GameState.inc_stat("remote_cubes", pay)
	w.erase("scope_boost")
	return res


## Junk left in the live district (same accounting as the offline payout in scenes/slice.gd).
static func live_junk_left() -> float:
	var sc: Node = (Engine.get_main_loop() as SceneTree).current_scene if Engine.get_main_loop() is SceneTree else null
	var f: Variant = sc.get("field") if sc else null
	var left: float = 0.0
	if f is HexField:
		var hf: HexField = f
		for h: int in hf.hex_count():
			if not hf.is_clean(h):
				left += hf.hex_left[h]
	else:
		return INF
	return maxf(0.0, left - float(GameState.world.get("offline_units", 0.0)))


static func arrival_text(res: Dictionary) -> String:
	var pay: float = float(res.get("cubes", 0.0)) + float(res.get("waiting_value", 0.0))
	var t: float = float(res.get("elapsed", 0.0))
	var when: String = (TranslationServer.translate("%d min") % int(t / 60.0)) if t < 3600.0 else ("%.1f h" % (t / 3600.0))
	return TranslationServer.translate("While you were away (%s), the crew here kept at it at a steady remote pace: %s cubes.") % [when, Settings.fmt(BigNum.from_float(pay))]


# --- Care package ------------------------------------------------------------------------------

static func care_cost() -> float:
	return float(care_cfg().get("cost_cubes", 400))


## "" when a care package can go to world w now, else why not.
static func care_block_reason(w: Dictionary, now: float = -1.0) -> String:
	if now < 0.0:
		now = Time.get_unix_time_from_system()
	if w.is_empty():
		return TranslationServer.translate("No world in view.")
	if now < float(boost_window(w)[1]):
		return TranslationServer.translate("A care package is already on its way.")
	if not GameState.can_afford("cubes", BigNum.from_float(care_cost())):
		return TranslationServer.translate("Needs %s cubes.") % Settings.fmt(BigNum.from_float(care_cost()))
	return ""


static func send_care(w: Dictionary, now: float = -1.0) -> bool:
	if now < 0.0:
		now = Time.get_unix_time_from_system()
	if care_block_reason(w, now) != "":
		return false
	GameState.spend("cubes", BigNum.from_float(care_cost()))
	w["scope_boost"] = [now, now + float(care_cfg().get("boost_s", 300.0))]
	GameState.inc_stat("care_packages")
	CradleMode.save_profile()
	return true


static func boost_left(w: Dictionary, now: float = -1.0) -> float:
	if now < 0.0:
		now = Time.get_unix_time_from_system()
	return maxf(0.0, float(boost_window(w)[1]) - now)
