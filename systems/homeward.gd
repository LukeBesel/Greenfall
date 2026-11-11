class_name Homeward
extends RefCounted
## [home] Homeward: the campaign across the Verdance system (data/homeward.json, docs/DECISIONS.md).
## Five fixed planets in a set order: Verdance (world 0) and four the Ledger strip-mined and left
## under its trash. Each is a world in the Cradle Mode profile (its own save slot) that restores
## like Verdance. The rocket's interplanetary drive (Mk V Orbital, Mk VI Interplanetary) opens them;
## once every planet is restored, the Mk VII Homeward rocket is built at Verdance's Cradle Returns,
## Lumi plants the last seed and launches up to the Cradle: the true ending (story/homecoming.gd).
##
## State lives in the profile (CradleMode.profile["homeward"], read and written only through
## CradleMode's profile API, so worlds2's save slots carry it):
##   pct      {planet id: best restoration 0..1}     drive   interplanetary drive tier (0, 5, 6, 7)
##   relics   [relic ids]                            picks   unspent Heirloom picks (one per restored planet)
##   answered the Cradle answered at Verdance        launched / done  the home launch / the ending played
##   beats    [story beat keys already played]
## Pure helpers (tests): planet_pct, system_pct, can_reach, drive_blocker.

const PATH: String = "res://data/homeward.json"
## Rocket targets below this are planets (-100 - planet index); HOME is the launch to the Cradle.
const PLANET_BASE: int = -100
const HOME: int = -200

static var _cfg: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(PATH)
	return _cfg


static func planets() -> Array:
	return cfg().get("planets", [])


static func planet_def(k: int) -> Dictionary:
	var ps: Array = planets()
	return ps[k] if k >= 0 and k < ps.size() else {}


static func planet_index(id: String) -> int:
	var ps: Array = planets()
	for i: int in ps.size():
		if str(ps[i]["id"]) == id:
			return i
	return -1


static func planet_name(k: int) -> String:
	return TranslationServer.translate(str(planet_def(k).get("name", "?")))


static func relic_def(id: String) -> Dictionary:
	return (cfg().get("relics", {}) as Dictionary).get(id, {})


static func drive_defs() -> Array:
	return cfg().get("drive", [])


static func drive_def(t: int) -> Dictionary:
	for d: Dictionary in drive_defs():
		if int(d["tier"]) == t:
			return d
	return {}


# --- Profile state ----------------------------------------------------------------------------

static func state() -> Dictionary:
	var p: Dictionary = CradleMode._p()
	var v: Variant = p.get("homeward")
	if not (v is Dictionary):
		v = {}
		p["homeward"] = v
	var s: Dictionary = v
	if not s.has("drive"):  # same shape as a loaded profile (sanitize), so saves round-trip exactly
		var full: Dictionary = sanitize(s)
		for k: String in full:
			if not s.has(k):
				s[k] = full[k]
	return s


## A loaded profile's homeward dict, cleaned (numbers back to ints after JSON).
static func sanitize(d: Variant) -> Dictionary:
	var out: Dictionary = {"pct": {}, "beats": [], "relics": [], "techs": []}
	if not (d is Dictionary):
		return out
	var src: Dictionary = d
	for k: Variant in src.get("pct", {}):
		(out["pct"] as Dictionary)[str(k)] = clampf(float(src["pct"][k]), 0.0, 1.0)
	out["seen"] = []  # [sysmap2] planet ids spotted early by the telescope
	for x: Variant in src.get("seen", []):
		(out["seen"] as Array).append(str(x))
	for k: String in ["beats", "relics", "techs"]:  # [pace2] techs: tools found on later planets
		for x: Variant in src.get(k, []):
			(out[k] as Array).append(str(x))
	out["drive"] = int(src.get("drive", 0))
	out["rocket_tier"] = int(src.get("rocket_tier", 1))
	out["picks"] = int(src.get("picks", 0))
	for k: String in ["answered", "launched", "done"]:
		out[k] = bool(src.get(k, false))
	return out


static func save() -> void:
	CradleMode.save_profile()


static func drive() -> int:
	return int(state().get("drive", 0))


## The rocket's interplanetary drive tier for the ship model's look: 0 (district hops only, Mk I-IV
## look from RocketTiers), 5 Orbital, 6 Interplanetary, 7 Homeward. Stable API for the "ship" helper.
static func drive_tier() -> int:
	return drive()


static func answered() -> bool:
	return bool(state().get("answered", false))


## [pace2] The system (map, drives, other planets) opens with partial progress: the Cradle's
## answer, a built Mk V, or Verdance far enough along for the Mk V gate (data: drive requires_*).
static func system_open() -> bool:
	if answered() or drive() >= 5:
		return true
	var d5: Dictionary = drive_def(5)
	return not d5.is_empty() and progress_blocker(d5) == ""


## [pace2] "" when a drive tier's partial-progress gates hold (pure on the stored percentages):
## requires_planet_pct [k, pct]: planet k restored to pct; requires_other_pct: any planet other
## than Verdance restored to pct (its chart). 100% and relics stay optional except where a tier
## still lists requires_relics / requires_system ([v7arc] none today: Mk VII takes requires_home).
static func progress_blocker(nd: Dictionary) -> String:
	var pp: Variant = nd.get("requires_planet_pct")
	if pp is Array and (pp as Array).size() >= 2:
		var k: int = int(pp[0])
		var need: float = float(pp[1])
		# [pace2] or a base that far along there. [v6pace] Owner note 58: leaving a planet is not tied
		# to cleaning it. Each planet names its own leave gate (planets[k].leave.base_level); the
		# drive's or_base_level is the fallback.
		var ob: int = leave_base_level(k, int(nd.get("or_base_level", 0)))
		var base_ok: bool = ob > 0 and current_planet() == k and (int(GameState.world.get("hub_level", 1)) >= ob or Frontiers.bases_at_level(ob) > 0)
		var lh: Vector2i = leave_hubs(k)  # [v6pace] or that many hubs restored there (owner note 61)
		if lh.x > 0:
			base_ok = current_planet() == k and hubs_at_level(lh.y) >= lh.x
		if stored_pct(k) < need - 0.0001 and not base_ok:
			if lh.x > 0:
				return TranslationServer.translate("Wake %d old stations on %s to level %d (%d so far)") % [lh.x, planet_name(k), lh.y, hubs_at_level(lh.y) if current_planet() == k else 0]
			if ob > 0:
				return TranslationServer.translate("Restore %s to %d%% (%d%%) or get a base to level %d") % [planet_name(k), int(round(need * 100.0)), int(floor(stored_pct(k) * 100.0)), ob]
			return TranslationServer.translate("Restore %s to %d%% (%d%%)") % [planet_name(k), int(round(need * 100.0)), int(floor(stored_pct(k) * 100.0))]
	if nd.has("requires_other_pct"):
		var need2: float = float(nd["requires_other_pct"])
		var best: float = 0.0
		for k2: int in range(1, planets().size()):
			best = maxf(best, stored_pct(k2))
		if best < need2 - 0.0001:
			return TranslationServer.translate("Restore another planet to %d%% (best %d%%)") % [int(round(need2 * 100.0)), int(floor(best * 100.0))]
	return ""


## [v6pace] The base level on planet k that opens the way onward (data/homeward.json
## planets[k].leave.base_level), or `fallback` when the planet names none.
static func leave_base_level(k: int, fallback: int = 0) -> int:
	var lv: Variant = planet_def(k).get("leave", {})
	return int((lv as Dictionary).get("base_level", fallback)) if lv is Dictionary else fallback


## [v6pace] (hubs, level): planet k's leave gate by hubs restored (planets[k].leave.hubs hubs at
## leave.hub_level or better), (0, 0) when it names none.
static func leave_hubs(k: int) -> Vector2i:
	var lv: Variant = planet_def(k).get("leave", {})
	if not (lv is Dictionary) or int((lv as Dictionary).get("hubs", 0)) <= 0:
		return Vector2i.ZERO
	return Vector2i(int((lv as Dictionary)["hubs"]), int((lv as Dictionary).get("hub_level", 2)))


## Hubs of the world Lumi is on at base level `l` or better: the round planet's sites
## (SiteManager.levels, the start hub's from its Hub), else the flat districts.
static func hubs_at_level(l: int) -> int:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var os_: OrbitSites = OrbitSites.of(tree.current_scene) if tree and tree.current_scene else null
	if os_ == null or os_.sm == null:
		return Frontiers.bases_at_level(l)
	var n: int = 0
	for i: int in os_.sm.levels.size():
		var lv: int = int(GameState.world.get("hub_level", 1)) if i == 0 else os_.sm.levels[i]
		if lv >= l and (i == 0 or os_.sm.built[i] != 0):
			n += 1
	return n


static func done() -> bool:
	return bool(state().get("done", false))


static func picks() -> int:
	return int(state().get("picks", 0))


static func relics() -> Array:
	return state()["relics"]


# --- [pace2] Tech from later planets (return trips) -------------------------------------------

static func techs() -> Array:
	var s: Dictionary = state()
	if not (s.get("techs") is Array):
		s["techs"] = []
	return s["techs"]


static func has_tech(id: String) -> bool:
	return id in techs() or DevHooks.has("all-tech")


static func tech_defs() -> Array:
	return cfg().get("tech", [])


static func tech_def(id: String) -> Dictionary:
	for t: Dictionary in tech_defs():
		if str(t.get("id", "")) == id:
			return t
	return {}


static func tech_name(id: String) -> String:
	return TranslationServer.translate(str(tech_def(id).get("name", id)))


## "Deep Drill: found on Ochre" (the hint shown wherever a tech gates something).
static func tech_hint(id: String) -> String:
	var pid: String = str(tech_def(id).get("planet", ""))
	var pname: String = pid
	for k: int in planets().size():
		if str(planet_def(k).get("id", "")) == pid:
			pname = planet_name(k)
	return TranslationServer.translate("Needs %s: found on %s") % [tech_name(id), pname]


## Highest restoration planet k can reach with the tech found so far (1.0 = no cap).
static func cap_for(k: int) -> float:
	var cap: float = 1.0
	for pair: Variant in planet_def(k).get("needs_tech", []):
		if pair is Array and (pair as Array).size() >= 2 and not has_tech(str(pair[0])):
			cap = minf(cap, float(pair[1]))
	return cap


## The tech still missing for planet k's next step (its lowest cap), or "".
static func blocking_tech(k: int) -> String:
	var best: String = ""
	var cap: float = 2.0
	for pair: Variant in planet_def(k).get("needs_tech", []):
		if pair is Array and (pair as Array).size() >= 2 and not has_tech(str(pair[0])) and float(pair[1]) < cap:
			cap = float(pair[1])
			best = str(pair[0])
	return best


## Grants the tech found on planet k once its restoration reaches each tech's `at`. Returns new ids.
static func grant_techs(k: int) -> Array[String]:
	var out: Array[String] = []
	var pid: String = str(planet_def(k).get("id", ""))
	for t: Dictionary in tech_defs():
		var id: String = str(t.get("id", ""))
		if str(t.get("planet", "")) == pid and not (id in techs()) and stored_pct(k) >= float(t.get("at", 0.25)) - 0.0001:
			techs().append(id)
			out.append(id)
	return out


static func beat_done(key: String) -> bool:
	return key in (state()["beats"] as Array)


static func mark_beat(key: String) -> void:
	if not beat_done(key):
		(state()["beats"] as Array).append(key)
		save()


static func stored_pct(k: int) -> float:
	return float((state()["pct"] as Dictionary).get(str(planet_def(k).get("id", "")), 0.0))


## The system planet the player is on (-1 on a "beyond the system" Cradle Mode world).
static func current_planet() -> int:
	var w: Dictionary = CradleMode.current_world()
	if w.has("planet"):  # worlds2's key: the planet id ("ochre"); an int index is read too
		var v: Variant = w["planet"]
		return planet_index(str(v)) if v is String else int(v)
	return 0 if int(w.get("index", 0)) == 0 else -1


static func _planet_of(w: Dictionary) -> int:
	if not w.has("planet"):
		return -1
	var v: Variant = w["planet"]
	return planet_index(str(v)) if v is String else int(v)


## Profile world index of planet k, or -1 if not visited yet.
static func world_of(k: int) -> int:
	var ws: Array = CradleMode.worlds()
	for i: int in ws.size():
		var w: Dictionary = ws[i]
		if (k == 0 and int(w.get("index", -1)) == 0) or _planet_of(w) == k:
			return i
	return -1


# --- Restoration (pure) -----------------------------------------------------------------------

## Restoration 0..1 of a non-Verdance planet from its numbers.
static func planet_pct(def: Dictionary, thriving: int, bases_l5: int, start_share: float) -> float:
	var w: Dictionary = cfg().get("weights", {})
	var p: float = float(w.get("thriving", 0.5)) * minf(1.0, float(thriving) / maxf(1.0, float(def.get("thriving", 100))))
	p += float(w.get("bases", 0.3)) * minf(1.0, float(bases_l5) / maxf(1.0, float(def.get("bases", 1))))
	p += float(w.get("start", 0.2)) * minf(1.0, start_share / maxf(0.01, float(cfg().get("start_ratio", 0.6))))
	return clampf(p, 0.0, 1.0)


## Mean restoration of the whole system from per-planet values.
static func system_pct_of(values: Array) -> float:
	var n: int = maxi(1, planets().size())
	var t: float = 0.0
	for v: Variant in values:
		t += clampf(float(v), 0.0, 1.0)
	return t / n


static func system_pct() -> float:
	var vals: Array = []
	for k: int in planets().size():
		vals.append(stored_pct(k))
	return system_pct_of(vals)


static func restored(k: int) -> bool:
	return stored_pct(k) >= 0.9999


## Live restoration of the current world (GameState), if it is a system planet.
static func measure_current() -> float:
	var k: int = current_planet()
	if k < 0:
		return 0.0
	if k == 0:
		if GameState.flags.get("cradle_returned", false):
			return 1.0
		return clampf(float(GameState.flags.get("core_charge", 0.0)), 0.0, 1.0)
	var thriving: int = 0
	var start_share: float = 0.0
	for key: Variant in GameState.districts:
		var d: Variant = GameState.world if int(key) == GameState.current_hub else GameState.districts[key]
		if d is Dictionary:
			var s: Vector2i = Bloom.district_summary(d)
			thriving += s.x
			if int(key) == 0:
				start_share = float(s.x) / maxf(1.0, float(s.y))
	if not GameState.districts.has(GameState.current_hub):
		var s2: Vector2i = Bloom.district_summary(GameState.world)
		thriving += s2.x
		if GameState.current_hub == 0:
			start_share = float(s2.x) / maxf(1.0, float(s2.y))
	return planet_pct(planet_def(k), thriving, Frontiers.bases_at_level(5), start_share)


## Raises the stored value of the current planet (never lowers). Returns planets newly restored.
static func store_current(v: float) -> Array[int]:
	var out: Array[int] = []
	var k: int = current_planet()
	if k < 0:
		return out
	var id: String = str(planet_def(k).get("id", ""))
	var old: float = stored_pct(k)
	var now: float = maxf(old, minf(clampf(v, 0.0, 1.0), cap_for(k)))  # [pace2] capped until later-planet tech
	if now <= old:
		return out
	(state()["pct"] as Dictionary)[id] = now
	for tid: String in grant_techs(k):  # [pace2]
		EventBus.toast.emit(TranslationServer.translate("New tech: %s. %s") % [tech_name(tid), TranslationServer.translate(str(tech_def(tid).get("desc", "")))], "story")
	if old < 0.9999 and now >= 0.9999:
		out.append(k)
		var relic: String = str(planet_def(k).get("relic", ""))
		if relic != "" and not (relic in relics()):
			relics().append(relic)
		if k > 0:
			state()["picks"] = picks() + 1
	mirror_stats()
	save()
	return out


## Profile numbers copied into this world's stats (goals, achievements and designs read them).
static func mirror_stats() -> void:
	GameState.stats["system_pct"] = float(int(floor(system_pct() * 100.0 + 0.0001)))
	var n: int = 0
	for k: int in planets().size():
		if restored(k):
			n += 1
	GameState.stats["planets_restored"] = float(n)
	GameState.stats["relics_found"] = float(relics().size())
	GameState.stats["drive_tier"] = float(drive())
	var visited: int = 0
	for k: int in planets().size():
		if world_of(k) >= 0:
			visited += 1
	GameState.stats["planets_visited"] = float(visited)
	if done():
		GameState.stats["homecoming"] = 1.0


# --- Reach ------------------------------------------------------------------------------------

## Whether planet k has its chart: the previous planet is restored to chart_at (pure).
static func charted(k: int, pcts: Array) -> bool:
	if k <= 0:
		return true
	return float(pcts[k - 1]) >= float(cfg().get("chart_at", 0.5)) - 0.0001


## "" if the drive and charts reach planet k (pure given values).
static func reach_blocker(k: int, drive_t: int, pcts: Array) -> String:
	var d: Dictionary = planet_def(k)
	if d.is_empty():
		return "unknown"
	if drive_t < int(d.get("nav", 0)):
		return TranslationServer.translate("Needs the %s drive") % TranslationServer.translate(str(drive_def(int(d.get("nav", 5))).get("name", "")))
	if not charted(k, pcts):
		return TranslationServer.translate("No chart yet: restore %s to %d%%") % [planet_name(k - 1), int(round(float(cfg().get("chart_at", 0.5)) * 100.0))]
	return ""


static func pct_list() -> Array:
	var out: Array = []
	for k: int in planets().size():
		out.append(stored_pct(k))
	return out


static func can_reach(k: int) -> bool:
	return reach_blocker(k, drive(), pct_list()) == ""


# --- [sysmap2] Discovery ------------------------------------------------------------------------
# Planets are found strictly in campaign order (data/homeward.json). Planet k shows on the system
# map once planet k-1 is discovered and either reaches discover_at, was spotted by the telescope
# (state "seen", see spot()) or Lumi has been to k. Unlocked (travel allowed) = discovered and
# reach_blocker() clear (the chart at chart_at and the drive tier).

## Pure: is planet k discovered, given per-planet restoration, the spotted ids and visited flags.
static func discovered_of(k: int, pcts: Array, seen: Array, visited: Array) -> bool:
	if k <= 0:
		return true
	if k >= planets().size() or not discovered_of(k - 1, pcts, seen, visited):
		return false
	if k < visited.size() and bool(visited[k]):
		return true
	if str(planet_def(k).get("id", "")) in seen:
		return true
	return float(pcts[k - 1]) >= float(cfg().get("discover_at", 0.25)) - 0.0001


static func _visited_list() -> Array:
	var out: Array = []
	for k: int in planets().size():
		out.append(k == current_planet() or world_of(k) >= 0)
	return out


static func discovered(k: int) -> bool:
	return discovered_of(k, pct_list(), state().get("seen", []), _visited_list())


## Travel allowed: discovered, charted and the drive reaches it (or Lumi is already there).
static func unlocked(k: int) -> bool:
	return k == current_planet() or (discovered(k) and can_reach(k))


## How many planets are discovered (they always form a prefix of the campaign order).
static func discovered_count() -> int:
	var n: int = 0
	while n < planets().size() and discovered(n):
		n += 1
	return n


## The telescope spotted planet k. Only the next undiscovered planet in order can be spotted.
## Returns true if this revealed it.
static func spot(k: int) -> bool:
	if k <= 0 or k >= planets().size() or discovered(k) or k != discovered_count():
		return false
	(state()["seen"] as Array).append(str(planet_def(k).get("id", "")))
	save()
	return true


# --- Drive upgrades ---------------------------------------------------------------------------

static func next_drive() -> Dictionary:
	var t: int = drive()
	for d: Dictionary in drive_defs():
		if int(d["tier"]) > t:
			return d
	return {}


## Cost keys are currency ids (cubes, parts).
static func _cur(k: String) -> String:
	return k


static func cost_ok(cost: Dictionary) -> bool:
	for k: String in cost:
		if not GameState.can_afford(_cur(k), BigNum.from_float(float(cost[k]))):
			return false
	return true


## "" if the next drive tier can be built here and now, else why not (translated).
static func drive_blocker(at_home_site: bool = false) -> String:
	var nd: Dictionary = next_drive()
	if nd.is_empty():
		return TranslationServer.translate("The Homeward rocket is built")
	var flag: String = str(nd.get("requires_flag", ""))
	if flag == "cradle_answered" and not answered():
		return TranslationServer.translate("The Cradle has to answer first (Cradle Returns)")
	var pb: String = progress_blocker(nd)  # [pace2]
	if pb != "":
		return pb
	if bool(nd.get("requires_home", false)) and not StoryArc.full():  # [v7arc] fuel and power for home
		return TranslationServer.translate("Needs full fuel and power. %s") % StoryArc.meter_text()
	if relics().size() < int(nd.get("requires_relics", 0)):
		return TranslationServer.translate("Needs %d planet relics (%d)") % [int(nd["requires_relics"]), relics().size()]
	if system_pct() < float(nd.get("requires_system", 0.0)) - 0.0001:
		return TranslationServer.translate("Restore every planet first (%d%%)") % int(floor(system_pct() * 100.0))
	if bool(nd.get("home_only", false)) and not at_home_site:
		return TranslationServer.translate("Build it at Verdance's Cradle Returns")
	if not cost_ok(nd.get("cost", {})):
		return TranslationServer.translate("Not enough cubes or parts")
	return ""


static func buy_drive(at_home_site: bool = false) -> bool:
	if drive_blocker(at_home_site) != "":
		return false
	var nd: Dictionary = next_drive()
	for k: String in nd.get("cost", {}):
		GameState.spend(_cur(k), BigNum.from_float(float(nd["cost"][k])))
	state()["drive"] = int(nd["tier"])
	GameState.inc_stat("drive_upgrades")
	mirror_stats()
	save()
	EventBus.toast.emit(TranslationServer.translate("Rocket drive built: %s.") % TranslationServer.translate(str(nd["name"])), "story")
	return true


static func cost_text(cost: Dictionary) -> String:
	var bits: Array[String] = []
	for k: String in cost:
		bits.append(L10nFmt.amount(k, float(cost[k]), false))
	return "  ".join(bits)


# --- Travel -----------------------------------------------------------------------------------

## [orbC] What a crew brings to planet k (data/homeward.json planets[k].arrival): the tools and
## bots of the planets before it, so each bigger planet starts further along and never plays
## slower than Verdance. Keys (all optional): research_tier (grants every research below that
## tier), robots (kit robots, added to the Heirloom crew), robot_tier {type: Mk index}, cubes, parts,
## seeds (also unlocks seeds).
static func arrival_kit(k: int) -> Dictionary:
	return (planet_def(k).get("arrival", {}) as Dictionary).duplicate(true) if k > 0 else {}


static func apply_arrival(k: int) -> Dictionary:
	return apply_kit(arrival_kit(k))


static func apply_kit(a: Dictionary) -> Dictionary:
	if a.is_empty():
		return a
	if float(a.get("cubes", 0.0)) > 0.0:
		GameState.add_currency("cubes", BigNum.from_float(float(a["cubes"])))
	if float(a.get("parts", 0.0)) > 0.0:
		GameState.add_currency("parts", BigNum.from_float(float(a["parts"])))
	if float(a.get("seeds", 0.0)) > 0.0:
		GameState.add_currency("seeds", BigNum.from_float(float(a["seeds"])))
		GameState.flags["seeds_unlocked"] = true
	var tier: int = int(a.get("research_tier", 0))
	if tier > 0:
		for rid: String in Research.ids():
			if int(Research.def(rid).get("tier", 0)) < tier and not Research.has(rid):
				Research.grant(rid)
	var bots: Array = (GameState.flags.get("late_start_robots", []) as Array).duplicate()
	bots.append_array(a.get("robots", []))
	if not bots.is_empty():
		GameState.flags["late_start_robots"] = bots
	var rt: Dictionary = a.get("robot_tier", {})
	for t: String in rt:
		GameState.flags["tier_" + t] = maxi(int(GameState.flags.get("tier_" + t, 0)), int(rt[t]))
	return a


## Creates planet k's world record (fixed seed, name, type, modifiers) in the profile.
static func make_planet_world(k: int) -> Dictionary:
	var d: Dictionary = planet_def(k)
	var w: Dictionary = CradleMode._add_world()
	w["seed"] = int(d.get("seed", 1))
	w["name"] = str(d.get("name", "?"))
	w["type"] = str(d.get("type", "rust_world"))
	w["modifiers"] = (d.get("mods", []) as Array).duplicate()
	w["planet"] = str(d.get("id", ""))  # worlds2 reads this id for the planet's look and sky
	return w


## Flies to planet k (after the rocket's launch): saves this world, then loads or starts planet k.
## The rocket arrival plays there.
static func travel_to_planet(k: int, tree: SceneTree) -> bool:
	if k < 0 or k >= planets().size() or k == current_planet():
		return false
	var cargo: Variant = GameState.flags.get("patch_cargo")
	var wi: int = world_of(k)
	GameState.inc_stat("planet_flights")
	if wi >= 0:
		if not CradleMode.switch_world(wi, tree):
			return false
	else:
		CradleMode.bank()
		if tree:
			SaveManager.save_game()
		var carry: Dictionary = CradleMode._carry_flags()
		carry["rocket_tier"] = maxi(int(GameState.flags.get("rocket_tier", 1)), 1)
		make_planet_world(k)
		CradleMode.profile["current"] = CradleMode.worlds().size() - 1
		CradleMode.apply_current()
		CradleMode.prepare_new_world_state(carry)
		CradleMode.save_profile()
		print("[home] new planet %d %s seed=%d" % [k, planet_def(k).get("name", "?"), int(planet_def(k).get("seed", 0))])
		CradleMode._change_scene(tree)
	GameState.flags["arrived_from_rocket"] = true
	GameState.flags["home_arrived_planet"] = k
	if cargo != null:
		GameState.flags["patch_cargo"] = cargo
	return true


## The Homeward complex: Verdance's Cradle Returns frontier district.
static func at_home_site(world: Node) -> bool:
	if current_planet() != 0 or world == null:
		return false
	return Frontiers.world_kind(world) == str(cfg().get("homeward_frontier", "cradle_returns"))


## Bloom.play_finale hook: before the home launch the Cradle Returns finale becomes "The Cradle
## Answers" (story/cradle_answers.gd). True when the original finale must not play.
static func redirect_finale(world: Node, force: bool) -> bool:
	if done() or (force and DevHooks.has("bloom-finale")):
		return false
	if current_planet() < 0:
		return false  # beyond the system: every world keeps its own finale
	if not answered() and current_planet() == 0:
		var c := CradleAnswers.new()
		c.world = world
		world.add_child(c)
		c.play()
	return true


## Heirloom picks (one per restored planet) replace Starseeds as the way to grow Heirlooms.
static func use_pick() -> bool:
	if picks() <= 0:
		return false
	state()["picks"] = picks() - 1
	save()
	return true
