class_name GoalAudit
extends RefCounted
## [v9d] Owner, 2026-11-13: "I need to make sure all goals and all that work". The goal chain
## (data/goals.json) runs ONE goal at a time on the objective card once the story is done, so a goal
## that can never complete is a dead end: every goal after it never shows. This proves, for every
## goal and achievement left on Verdance in this release (other planets closed: data/homeward.json),
## that the thing its condition reads exists and is written by the round game, and that its target
## can be reached with what Verdance offers.
##   GoalAudit.audit(world)  -> Array[String] of failures (world = null: the data-only checks)
## Runs from tests/test_goal_audit.gd (data) and tools/walk_goals.gd (--walk-goals, on the globe).
## A new goal whose stat or flag is not listed in SOURCES below fails until its source is named.

## Goal condition types the round game reads (story/goals.gd value_of). "zone" (Command zones,
## removed), "bases_l5", "frontier_base" and "frontier_growing" (flat frontier districts) are gone.
const TYPES: Array[String] = ["stat", "earned", "upgrade", "robot", "tier", "hub_level", "hex_level", "flag", "districts", "research"]

## Stat / flag key -> where the round game writes it. "core": a system every Verdance game has
## (the story chain or a hook proves it moves); "node:<Class>": a node of that class must be in the
## world; "build:<id>": a build the workbench offers (data/builds.json, not hidden); "fauna:<kind>": the fauna data has that animal; "eggs" / "shards": capped by how many the
## globe places; "closed:<why>": never written on Verdance in this release (a goal must not use it).
const SOURCES: Dictionary = {
	"junk_scooped": "core", "junk_dumps": "core", "upgrades_bought": "core", "cubes_made": "core",
	"cubes_cashed": "core", "hexes_cleaned": "core", "robots_built": "core", "research_done": "core",
	"robot_bales": "core", "hubs_seen": "core", "hubs_woken": "core", "rocket_tier": "core",
	"plants_planted": "core", "plants_bloomed": "core", "perfect_cubes": "core", "pure_cubes": "core",
	"lumpy_cubes": "core", "parts_found": "core", "garden_stipend": "core", "hexes_restored": "core",
	"time_played": "core", "distance_m": "core", "data_earned": "core", "drive_tier": "core",
	"seeds_unlocked": "core", "glim_repaired": "core",
	"shards_found": "shards", "eggs_found": "eggs",
	"cats_petted": "fauna:cat", "fauna_cat_named": "fauna:cat", "album_shots": "node:PhotoAlbum", "seen_deer": "fauna:deer", "seen_fish": "fauna:fish",
	"bales_recycled": "build:recycler", "air_filtered": "build:air_scrubber",
	"radio_plays": "build:radio", "radio_songs": "build:radio", "robots_retired": "build:nursery", "nursery_visits": "build:nursery",
	"builder_parts_fitted": "core", "builder_full_custom": "core", "builder_maker_set": "core", "builder_toppers": "core",
	"decor_placed": "core", "decor_kinds": "core", "decor_charm_best": "core",
	"outposts_repaired": "core", "outpost_pads": "core",
	"water_tanks": "closed:no Water Tanks on the round world (the flat WaterNet; SphereFleet has none)",
	"weekly_chips": "closed:Seed of the Week is hidden",
}

## Goals and achievements whose key is fed only by content hidden in this release: any key a
## hidden achievement reads (data/homeward.json closed.hide_achievements), at that target or more.
static func closed_keys() -> Dictionary:
	var out: Dictionary = {}
	if not Homeward.next_closed():
		return out
	var hide: Array = Homeward.closed_cfg().get("hide_achievements", [])
	for a: Variant in Achievements.defs():
		var d: Dictionary = a
		if str(d.get("id", "")) in hide:
			var c: Dictionary = d.get("cond", {})
			var k: String = str(c.get("key", ""))
			if k != "":
				out[k] = minf(float(out.get(k, INF)), float(c.get("target", 1)))
	return out


## The goals as the game loads them on Verdance (story/goals.gd load_chain).
static func verdance_goals() -> Array:
	var cfg: Dictionary = Economy.read_json("res://data/goals.json")
	var chain: Array = PlanetSteps.goals(cfg.get("goals", []), "verdance")
	return chain.filter(func(g: Variant) -> bool: return not Homeward.goal_hidden(str((g as Dictionary).get("id", ""))))


static func audit(w: Node = null) -> Array[String]:
	var fails: Array[String] = []
	var closed: Dictionary = closed_keys()
	var seen: Dictionary = {}
	for g: Variant in verdance_goals():
		var d: Dictionary = g
		var id: String = str(d.get("id", ""))
		if seen.has(id):
			fails.append("goal %s: duplicate id" % id)
		seen[id] = true
		var why: String = goal_problem(d, w, closed)
		if why != "":
			fails.append("goal %s (%s): %s" % [id, str(d.get("text", "")), why])
	for a: Variant in Achievements.shown_defs():  # the Codex's list (closed planets and Seed of the Week left out)
		var ad: Dictionary = a
		var why2: String = achievement_problem(ad.get("cond", {}), w, closed)
		if why2 != "":
			fails.append("achievement %s (%s): %s" % [str(ad.get("id", "")), str(ad.get("name", "")), why2])
	return fails


## "" when the goal can complete on Verdance; else why not.
static func goal_problem(d: Dictionary, w: Node, closed: Dictionary) -> String:
	var typ: String = str(d.get("type", "stat"))
	var key: String = str(d.get("key", ""))
	var tgt: float = float(d.get("target", 1))
	for k: String in (d.get("reward", {}) as Dictionary):
		if not (k in ["cubes", "seeds", "parts"]):
			return "reward in a currency that is gone: %s" % k
	if not (typ in TYPES):
		return "condition type '%s' is not read by the round game" % typ
	match typ:
		"stat", "flag":
			return key_problem(key, tgt, w, closed)
		"upgrade":
			if not Economy.upgrade_defs.has(key):
				return "no upgrade '%s'" % key
			if tgt > float(Economy.upgrade_max(key)):
				return "target %d over the upgrade's max %d" % [int(tgt), Economy.upgrade_max(key)]
		"robot":
			if key != "any" and not Economy.robots.has(key):
				return "no robot type '%s'" % key
			if key in Homeward.hidden_builds():
				return "robot '%s' is hidden in this release" % key
			var rr: String = str((Economy.robots.get(key, {}) as Dictionary).get("requires_research", ""))
			if rr != "" and not Research.exists(rr):
				return "robot '%s' needs research '%s', which does not exist" % [key, rr]
			var cc: Dictionary = Economy.robot_cfg.get("crew_cap", {})
			var cap: float = float(cc.get("base", 1)) + float(cc.get("per_level", 2)) * 5.0
			if key != "any" and tgt > cap:
				return "target %d over the crew cap %d at base level 5" % [int(tgt), int(cap)]
		"tier":
			var tiers: Array = Economy.robot_tiers
			if tgt >= float(tiers.size()):
				return "target Mk %d: only %d tiers" % [int(tgt) + 1, tiers.size()]
		"hub_level":
			if tgt > 5.0:
				return "base levels stop at 5"
			if str(d.get("hub", "")) == "second" and w != null and _hub_count(w) < 2:
				return "one hub only"
		"hex_level":
			if int(d.get("key", 1)) > HexLevels.MAX_LEVEL:
				return "hex level %s over the max %d" % [key, HexLevels.MAX_LEVEL]
		"districts":
			if w != null and tgt > float(_hub_count(w)):
				return "target %d hubs: the globe has %d" % [int(tgt), _hub_count(w)]
		"research":
			if not researchable().has(key):
				return "research '%s' can't be started on Verdance (missing, story-only or needs a closed planet's tech)" % key
	return ""


static func achievement_problem(c: Dictionary, w: Node, closed: Dictionary) -> String:
	var typ: String = str(c.get("type", ""))
	var key: String = str(c.get("key", ""))
	var tgt: float = float(c.get("target", 1))
	match typ:
		"stat", "flag":
			if key.begins_with("bloom_") or key.begins_with("egg_") or key.begins_with("museum"):
				return ""  # written by id (Bloom milestones flags.bloom_<id>, eggs flags.egg_<id>, the Museum)
			return key_problem(key, tgt, w, closed)
		"research":
			if tgt > float(researchable().size()):
				return "target %d: only %d research projects can be started on Verdance" % [int(tgt), researchable().size()]
		"research_id":
			if not researchable().has(key):
				return "research '%s' can't be started on Verdance" % key
		"hub_level":
			if tgt > 5.0:
				return "base levels stop at 5"
	return ""


## A stat or flag key: written on the round world, not closed, target reachable.
static func key_problem(key: String, tgt: float, w: Node, closed: Dictionary) -> String:
	if closed.has(key) and tgt >= float(closed[key]):
		return "'%s' >= %d only comes from content hidden in this release (a hidden achievement reads it)" % [key, int(closed[key])]
	if not SOURCES.has(key):
		return "nothing known writes '%s' on the round world (name its source in tools/goal_audit.gd SOURCES)" % key
	var src: String = str(SOURCES[key])
	if src.begins_with("closed:"):
		return "'%s': %s" % [key, src.substr(7)]
	if src.begins_with("fauna:"):
		var kind: String = src.substr(6)
		if not (kind in _fauna_kinds()):
			return "no '%s' in data/fauna.json" % kind
	if src.begins_with("build:"):
		var bid: String = src.substr(6)
		if not (Economy.read_json("res://data/builds.json").get("builds", []) as Array).any(func(b: Variant) -> bool: return b is Dictionary and str((b as Dictionary).get("id", "")) == bid):
			return "no build '%s' in data/builds.json (writes '%s')" % [bid, key]
		if bid in Homeward.hidden_builds():
			return "build '%s' is hidden in this release (writes '%s')" % [bid, key]
	var cap: float = cap_of(key, w)
	if tgt > cap:
		return "target %d over what Verdance has (%d)" % [int(tgt), int(cap)]
	if w != null and src.begins_with("node:"):
		var cls: String = src.substr(5)
		if not _has_class(w.get_tree().root, cls):
			return "no %s in the round world (writes '%s')" % [cls, key]
	return ""


## The most a key can reach on Verdance (INF when unbounded or unknown without the world).
static func cap_of(key: String, w: Node) -> float:
	match key:
		"research_done":
			return float(researchable().size())
		"shards_found":
			return float((Economy.read_json("res://data/shards.json").get("shards", []) as Array).size())
		"eggs_found":
			return float(reachable_eggs(w).size()) if w != null else INF
		"hubs_seen", "hubs_woken":
			return float(_hub_count(w) - 1) if w != null else INF
		"drive_tier":
			return 5.0 if Homeward.next_closed() else 7.0
		"rocket_tier":
			return float((Economy.read_json("res://data/rockets.json").get("tiers", []) as Array).size())
	return INF


## Research projects a player can start on Verdance: not story unlocks, no closed planet's tech
## anywhere up their prerequisites.
static func researchable() -> Dictionary:
	var ok: Dictionary = {}
	var memo: Dictionary = {}
	for id: String in Research.ids():
		if _can_research(id, memo):
			ok[id] = true
	return ok


static func _can_research(id: String, memo: Dictionary) -> bool:
	if memo.has(id):
		return memo[id]
	memo[id] = false
	if not Research.exists(id) or Research.is_story(id):
		return false
	var rt: String = str(Research.def(id).get("requires_tech", ""))
	if rt != "" and not Homeward.has_tech(rt):
		return false
	for r: Variant in Research.requires(id):
		if not Research.is_story(str(r)) and not _can_research(str(r), memo):
			return false
	memo[id] = true
	return true


## The eggs the globe's hubs place (story/eggs.gd: the starter set at hub 0, a seeded pick at the others).
static func reachable_eggs(w: Node) -> Dictionary:
	var data: Dictionary = Economy.read_json("res://data/eggs.json")
	var ids: Array[String] = []
	var defs: Dictionary = {}
	for e: Dictionary in data.get("eggs", []):
		ids.append(str(e["id"]))
		defs[str(e["id"])] = e
	var out: Dictionary = {}
	var f: Variant = w.get("field") if w else null
	if f == null:
		return out
	for hub: int in _hub_count(w):
		for id: String in EasterEggs.district_eggs(ids, defs, hub, int((f as HexField).seed_value) + hub * 977,
				int(data.get("per_district", 9)), hub != 0, "", int(data.get("wild_per_district", 4))):
			out[id] = true
	return out


static func _hub_count(w: Node) -> int:
	var so: Variant = w.get("orbit") if w else null
	if so == null or (so as Object).get("globe") == null:
		return 1
	return ((so as Object).get("globe") as OrbitPlanet).sites.size()


static func _fauna_kinds() -> Array:
	var out: Array = []
	for s: Variant in Economy.read_json("res://data/fauna.json").get("species", []):
		if s is Dictionary:
			out.append(str((s as Dictionary).get("id", "")))
	return out


static func _has_class(n: Node, cls: String) -> bool:
	var sc: Variant = n.get_script()
	if sc is Script and (sc as Script).get_global_name() == cls:
		return true
	for c: Node in n.get_children():
		if _has_class(c, cls):
			return true
	return false
