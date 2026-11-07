class_name CradleMode
extends RefCounted
## [late] Cradle Mode: the post-game prestige layer (booted by the CradleBoot autoload,
## systems/cradle_boot.gd, before any save is read).
## After the Cradle finale the ark can carry Lumi to a NEW world (systems/world_gen.gd): a fresh
## planet seed with its own biome mix, towns, name and two modifiers. Every world keeps its own
## save slot, so Verdance (world 0, slot 0) stays playable from the Ark Bridge (ui/ark_bridge.gd).
##
## The profile (user://saves/profile.save, next to the world slots) is the only state shared by
## worlds: the world list (seed, name, type, modifiers, slot, banked Starseeds, archived stats),
## the current world, Starseeds (prestige currency) and Heirloom levels (data/cradle.json).
## Heirlooms and the current world's modifiers reach the game through `stat_mod` (called from
## Economy.stat), so every system that reads a stat picks them up without knowing about worlds.
##
## Pure math is static (tests use it): prestige_earned, heirloom_cost, heirloom_mult, mod_mult.
## With --fresh (and no --save-dir) the profile is kept in memory only, so tests and dev runs
## never touch a player's worlds.

const PROFILE_FILE: String = "profile.save"
const PROFILE_VERSION: int = 1

## The profile in memory (see the class doc). Static so pure helpers and tests can reach it.
static var profile: Dictionary = {}
## Write the profile to disk (false under --fresh without --save-dir, and in tests).
static var persist: bool = false
## Tests / the save round trip point this somewhere harmless.
static var path_override: String = ""


static func boot() -> void:
	persist = not (DevHooks.has("fresh") or DevHooks.has("nosave")) or SaveManager.dev_dir != ""
	if persist and not DevHooks.has("fresh"):
		load_profile()
	elif persist and DevHooks.has("fresh"):
		profile = default_profile()  # [late] a fresh staged run starts a fresh profile too
		save_profile()
	else:
		profile = default_profile()
	apply_current()
	if DevHooks.has("world"):  # dev: --world=N plays the profile's world N (made on the fly if new)
		var wi: int = int(DevHooks.get_f("world", 0.0))
		while worlds().size() <= wi:
			_add_world()
		profile["current"] = wi
		apply_current()


# --- Profile ---------------------------------------------------------------------------

static func default_profile() -> Dictionary:
	var w: Dictionary = WorldGen.make(0)
	w["slot"] = 0
	w["claimed"] = 0
	w["stats"] = {}
	return {"version": PROFILE_VERSION, "current": 0, "starseeds": 0.0, "starseeds_total": 0.0,
		"heirlooms": {}, "unlocked": false, "worlds": [w]}


static func profile_path() -> String:
	if path_override != "":
		return path_override
	return SaveManager.save_dir().path_join(PROFILE_FILE)


static func load_profile() -> void:
	var d: Dictionary = SaveManager.read_dict(profile_path()) if FileAccess.file_exists(profile_path()) else {}
	profile = from_dict(d)


static func save_profile() -> bool:
	if not persist:
		return false
	DirAccess.make_dir_recursive_absolute(profile_path().get_base_dir())
	return SaveManager.write_dict(profile_path(), to_dict())


static func to_dict() -> Dictionary:
	return _p().duplicate(true)


## Loads a profile dict, filling in anything missing (older or empty files).
static func from_dict(d: Dictionary) -> Dictionary:
	var p: Dictionary = default_profile()
	if d.is_empty():
		return p
	for k: String in ["starseeds", "starseeds_total"]:
		p[k] = float(d.get(k, 0.0))
	p["unlocked"] = bool(d.get("unlocked", false))
	p["current"] = int(d.get("current", 0))
	var hl: Dictionary = {}
	for k: Variant in (d.get("heirlooms", {}) as Dictionary):
		hl[str(k)] = int(d["heirlooms"][k])
	p["heirlooms"] = hl
	var ws: Array = []
	for w: Variant in d.get("worlds", []):
		if not (w is Dictionary):
			continue
		var wd: Dictionary = (w as Dictionary).duplicate(true)
		for k: String in ["index", "seed", "slot", "claimed"]:
			wd[k] = int(wd.get(k, 0))
		ws.append(wd)
	if ws.is_empty():
		ws = p["worlds"]
	p["worlds"] = ws
	p["current"] = clampi(int(p["current"]), 0, ws.size() - 1)
	return p


static func _p() -> Dictionary:
	if profile.is_empty():
		profile = default_profile()
	return profile


static func worlds() -> Array:
	return _p()["worlds"]


static func current_index() -> int:
	return int(_p().get("current", 0))


static func current_world() -> Dictionary:
	return worlds()[clampi(current_index(), 0, worlds().size() - 1)]


## The world record with its generated mix (towns etc. are recomputed, not stored).
static func current_full() -> Dictionary:
	var w: Dictionary = current_world()
	return WorldGen.make(int(w.get("index", 0)), int(w.get("seed", WorldGen.VERDANCE_SEED)))


static func world_seed() -> int:
	return int(current_world().get("seed", WorldGen.VERDANCE_SEED))


static func world_name() -> String:
	return str(current_world().get("name", "Verdance"))


static func planet_mix() -> Dictionary:
	return current_full().get("mix", {})


static func modifiers() -> Array:
	return current_world().get("modifiers", [])


static func has_modifier(id: String) -> bool:
	return id in modifiers()


## Points SaveManager at the current world's slot and names the planet (HUD, hologram).
static func apply_current() -> void:
	SaveManager.slot = int(current_world().get("slot", 0))
	Economy.planet["name"] = world_name()


## Cradle Mode is open once any world's finale has played.
static func unlocked() -> bool:
	return bool(_p().get("unlocked", false)) or bool(GameState.flags.get("bloom_finale_seen", false))


static func starseeds() -> float:
	return float(_p().get("starseeds", 0.0))


# --- Prestige (pure) -------------------------------------------------------------------

## Starseeds a world has earned in all, from its summary (see data/cradle.json).
static func prestige_earned(s: Dictionary) -> int:
	var c: Dictionary = WorldGen.cfg().get("prestige", {})
	var v: float = float(c.get("per_ark_wave", 4)) * float(s.get("ark_waves", 0)) \
		+ float(c.get("per_bloom_milestone", 6)) * float(s.get("bloom_milestones", 0)) \
		+ float(c.get("per_sqrt_thriving", 1.5)) * sqrt(maxf(float(s.get("thriving", 0)), 0.0)) \
		+ float(c.get("cradle_bonus", 20)) * (1.0 if bool(s.get("cradle", false)) else 0.0) \
		+ float(c.get("per_base_l5", 3)) * float(s.get("bases_l5", 0))
	return int(floor(v + 0.000001))


## What banking now would add: earned minus what this world already paid out.
static func claimable(s: Dictionary, claimed: int) -> int:
	return maxi(0, prestige_earned(s) - claimed)


## This world's summary from GameState (all its districts).
static func world_summary() -> Dictionary:
	var thriving: int = 0
	var l5: int = 0
	for k: Variant in GameState.districts:
		var d: Variant = GameState.world if int(k) == GameState.current_hub else GameState.districts[k]
		if d is Dictionary:
			thriving += Bloom.district_summary(d).x
			if int((d as Dictionary).get("hub_level", 1)) >= 5:
				l5 += 1
	return {"ark_waves": int(GameState.stats.get("ark_waves", 0)), "bloom_milestones": Bloom.done_list().size(),
		"thriving": thriving, "cradle": bool(GameState.flags.get("cradle_returned", false)), "bases_l5": l5,
		"time_played": float(GameState.stats.get("time_played", 0.0)), "hexes_cleaned": int(GameState.stats.get("hexes_cleaned", 0)),
		"blooms": int(GameState.stats.get("plants_bloomed", 0)), "eggs": (GameState.flags.get("eggs_found", []) as Array).size(),
		"districts": GameState.districts.size(), "decor": int(GameState.stats.get("decor_placed", 0))}


## Banks the current world's new Starseeds into the profile and archives its stats. Returns the gain.
static func bank() -> int:
	var w: Dictionary = current_world()
	var s: Dictionary = world_summary()
	var gain: int = claimable(s, int(w.get("claimed", 0)))
	w["claimed"] = int(w.get("claimed", 0)) + gain
	w["stats"] = s
	w["last_unix"] = Time.get_unix_time_from_system()
	if bool(GameState.flags.get("bloom_finale_seen", false)):
		w["finale"] = true
		_p()["unlocked"] = true
	_p()["starseeds"] = starseeds() + gain
	_p()["starseeds_total"] = float(_p().get("starseeds_total", 0.0)) + gain
	mirror_stats()
	save_profile()
	return gain


## Profile numbers copied into this world's stats so goals and achievements can count them.
static func mirror_stats() -> void:
	GameState.stats["worlds_seeded"] = float(worlds().size() - 1)
	GameState.stats["heirloom_levels"] = float(heirloom_total())
	GameState.stats["starseeds_earned"] = float(_p().get("starseeds_total", 0.0))
	if current_index() > 0:
		GameState.stats["world_index"] = float(current_index())


# --- Heirlooms ------------------------------------------------------------------------

static func heirloom_defs() -> Array:
	return WorldGen.cfg().get("heirlooms", [])


static func heirloom_def(id: String) -> Dictionary:
	for h: Dictionary in heirloom_defs():
		if str(h["id"]) == id:
			return h
	return {}


static func heirloom_level(id: String) -> int:
	return int((_p().get("heirlooms", {}) as Dictionary).get(id, 0))


static func heirloom_total() -> int:
	var n: int = 0
	for k: Variant in (_p().get("heirlooms", {}) as Dictionary):
		n += int(_p()["heirlooms"][k])
	return n


## Cost of buying level `level` + 1 (pure).
static func heirloom_cost(def: Dictionary, level: int) -> int:
	return int(round(float(def.get("cost", 10)) * pow(float(def.get("cost_growth", 1.5)), level)))


static func buy_block_reason(id: String) -> String:
	var d: Dictionary = heirloom_def(id)
	if d.is_empty():
		return "unknown"
	var lv: int = heirloom_level(id)
	if lv >= int(d.get("max", 5)):
		return TranslationServer.translate("Fully grown")
	if starseeds() + 0.0001 < heirloom_cost(d, lv):
		return TranslationServer.translate("Needs %d Starseeds") % heirloom_cost(d, lv)
	return ""


static func buy(id: String) -> bool:
	if buy_block_reason(id) != "":
		return false
	var d: Dictionary = heirloom_def(id)
	var lv: int = heirloom_level(id)
	_p()["starseeds"] = starseeds() - heirloom_cost(d, lv)
	(_p()["heirlooms"] as Dictionary)[id] = lv + 1
	GameState.inc_stat("heirlooms_bought")
	mirror_stats()
	save_profile()
	EventBus.toast.emit(TranslationServer.translate("Heirloom: %s, level %d. It travels with Lumi to every world.") % [TranslationServer.translate(str(d.get("name", id))), lv + 1], "story")
	return true


## Stat multiplier from Heirlooms (pure given levels).
static func heirloom_mult(stat_id: String, levels: Dictionary) -> float:
	var m: float = 1.0
	for h: Dictionary in heirloom_defs():
		if str(h.get("stat", "")) == stat_id:
			m *= 1.0 + float(h.get("per_level", 0.0)) * int(levels.get(str(h["id"]), 0))
	return m


## Stat multiplier from a world's modifiers (pure).
static func mod_mult(stat_id: String, mods: Array) -> float:
	var m: float = 1.0
	for id: Variant in mods:
		m *= float((WorldGen.modifier(str(id)).get("stats", {}) as Dictionary).get(stat_id, 1.0))
	return m


## Economy.stat hook: Heirlooms x this world's modifiers x this district's decor charm.
static func stat_mod(stat_id: String, value: float) -> float:
	if profile.is_empty():
		return value * Decor.stat_mult(stat_id)
	return value * heirloom_mult(stat_id, _p().get("heirlooms", {})) * mod_mult(stat_id, modifiers()) * Decor.stat_mult(stat_id)


## World event weight multiplier (systems/events.gd).
static func event_weight(id: String) -> float:
	var m: float = 1.0
	for mid: Variant in modifiers():
		m *= float((WorldGen.modifier(str(mid)).get("event_weight", {}) as Dictionary).get(id, 1.0))
	return m


## How fast the clock runs at this time of day (planet/sky_director.gd): Long Nights halves nights.
static func day_speed(time_of_day: float) -> float:
	var night: bool = time_of_day < 0.22 or time_of_day > 0.78
	if not night:
		return 1.0
	var m: float = 1.0
	for mid: Variant in modifiers():
		m *= float(WorldGen.modifier(str(mid)).get("night_speed", 1.0))
	return m


## The starting kit for a new world, from Heirloom levels (pure): {cubes, data, seeds, seeds_unlocked, robots, research_tier}.
static func start_kit(levels: Dictionary) -> Dictionary:
	var kit: Dictionary = {"cubes": 0.0, "data": 0.0, "seeds": 0.0, "seeds_unlocked": false, "robots": [], "research_tier": 0}
	for h: Dictionary in heirloom_defs():
		var lv: int = int(levels.get(str(h["id"]), 0))
		if lv <= 0 or not h.has("start"):
			continue
		var st: Dictionary = h["start"]
		for k: String in ["cubes", "data", "seeds"]:
			kit[k] = float(kit[k]) + float(st.get(k, 0.0)) * lv
		if st.has("seeds_unlocked"):
			kit["seeds_unlocked"] = true
		if st.has("robots"):
			kit["robots"] = (st["robots"] as Array).slice(0, lv)
		if st.has("research_tier"):
			kit["research_tier"] = maxi(int(kit["research_tier"]), lv)
	return kit


# --- Worlds ---------------------------------------------------------------------------

static func _next_slot() -> int:
	var used: Array = []
	for w: Dictionary in worlds():
		used.append(int(w.get("slot", 0)))
	var s: int = 0
	while s in used or s == 7 or s == 8:  # 7/8: the save round trip's scratch slots
		s += 1
	return s


static func _add_world(slot: int = -1) -> Dictionary:
	var idx: int = worlds().size()
	var w: Dictionary = WorldGen.make(idx, WorldGen.seed_for(idx, int(_p().get("starseeds_total", 0.0))))
	w.erase("mix")
	w["slot"] = slot if slot >= 0 else _next_slot()
	w["claimed"] = 0
	w["stats"] = {}
	w["started_unix"] = Time.get_unix_time_from_system()
	worlds().append(w)
	return w


## Fresh GameState for a new world: the Heirloom starting kit, carried-over meta flags and a
## pod landing instead of the intro film (Lumi already knows how all this works).
static func prepare_new_world_state(carry: Dictionary) -> void:
	GameState.new_game()
	for k: String in carry:
		GameState.flags[k] = carry[k]
	GameState.flags["intro_done"] = true
	GameState.flags["world_index"] = current_index()
	GameState.flags["late_new_world"] = true  # the arrival card + kit robots (systems/late_hooks.gd)
	var kit: Dictionary = start_kit(_p().get("heirlooms", {}))
	if float(kit["cubes"]) > 0.0:
		GameState.add_currency("cubes", BigNum.from_float(float(kit["cubes"])))
	if float(kit["data"]) > 0.0:
		GameState.add_currency(Research.CURRENCY, BigNum.from_float(float(kit["data"])))
	if bool(kit["seeds_unlocked"]):
		GameState.flags["seeds_unlocked"] = true
		GameState.add_currency("seeds", BigNum.from_float(float(kit["seeds"])))
	if not (kit["robots"] as Array).is_empty():
		GameState.flags["late_start_robots"] = (kit["robots"] as Array).duplicate()
	var tier: int = int(kit["research_tier"])
	if tier > 0:
		for rid: String in Research.ids():
			if int(Research.def(rid).get("tier", 0)) < tier:
				Research.grant(rid)
	mirror_stats()


static func _carry_flags() -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in WorldGen.cfg().get("carry_flags", []):
		if GameState.flags.has(str(k)):
			out[str(k)] = (GameState.flags[str(k)] as Variant)
			if out[str(k)] is Array or out[str(k)] is Dictionary:
				out[str(k)] = out[str(k)].duplicate(true)
	return out


## Seeds a new world and starts it. Saves the world being left first. Returns the new record.
static func launch_new_world(tree: SceneTree = null) -> Dictionary:
	bank()
	if tree:
		SaveManager.save_game()
	var carry: Dictionary = _carry_flags()
	var w: Dictionary = _add_world()
	_p()["current"] = worlds().size() - 1
	_p()["unlocked"] = true
	apply_current()
	prepare_new_world_state(carry)
	save_profile()
	print("[cradle] new world %d: %s seed=%d type=%s mods=%s slot=%d" % [int(w["index"]), w["name"], int(w["seed"]), w["type"], str(w["modifiers"]), int(w["slot"])])
	if tree:
		tree.paused = false
		tree.change_scene_to_file("res://scenes/slice.tscn")
	return w


## Travels to an existing world (its save is loaded; a world with no save starts fresh).
static func switch_world(i: int, tree: SceneTree = null) -> bool:
	if i < 0 or i >= worlds().size():
		return false
	bank()
	if tree:
		SaveManager.save_game()
	var carry: Dictionary = _carry_flags()
	_p()["current"] = i
	apply_current()
	save_profile()
	if SaveManager.has_save():
		if not SaveManager.load_game():
			return false
		GameState.reload_in_memory = true  # the slice uses what we just loaded (even under --fresh)
	else:
		prepare_new_world_state(carry)
	mirror_stats()
	if tree:
		tree.paused = false
		tree.change_scene_to_file("res://scenes/slice.tscn")
	return true


## Title screen New Game: every world is erased and the profile starts over.
static func reset_all() -> void:
	for w: Dictionary in worlds():
		SaveManager.delete_save(int(w.get("slot", 0)))
	profile = default_profile()
	save_profile()
	apply_current()
