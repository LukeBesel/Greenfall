extends GutTest
## [v13goals] Owner, 26 Nov: "maybe we forget about the whole planting thing and only clean up planet
## and as that happens the planets slowly auto grow plants". The player only cleans: no seed
## currency, no planting or watering tool, robot, goal, card, Request or line that asks for it, and
## clean ground greens by itself (plants/auto_grow.gd). An old save with seeds, planting robots and
## the seed step loads clean. Fails if planting text or a planting step comes back.

## Player text that asks the player to plant, water or deal in seeds.
const ASKS: String = "(?i)\\bplant (a|the|it|some|seeds?|more)\\b|\\bplanting\\b|\\bwatering\\b|\\bwater (it|them|the plants?|the garden|the seeds?)\\b|seed tin|\\b(find|found|out of|more|no|\\+\\d+) seeds\\b|\\bseed stock\\b.*\\bplant|\\bdrips?\\b|\\bseedlings? (bot|robot|planter)\\b|compost press|\\bthirsty\\b"
## The data a player meets on Verdance (their shown fields; ids, keys and _doc notes are not text).
const FILES: Array[String] = ["objectives", "goals", "achievements", "story_reasons", "research", "robots", "events",
	"currencies", "codex", "workbench", "lumi_level", "planets", "glim", "upgrades", "builds"]
## The one planting beat left: the Homecoming's last seed (one press of E at the very end, after all
## five worlds; the story's heart, not a system).
const ALLOWED: Array[String] = ["Plant the last seed"]
const SKIP_KEYS: Array[String] = ["id", "key", "icon", "model", "type", "stat", "requires", "requires_research", "branch", "flag", "unlock_plant", "unlock_robot", "kind", "tpl"]


var _before: Dictionary


func before_each() -> void:
	_before = GameState.to_dict()


func after_each() -> void:
	GameState.from_dict(_before)
	AutoGrow.force = -1


func _texts(v: Variant, key: String, out: Array[String]) -> void:
	if key.begins_with("_") or key in SKIP_KEYS:
		return
	if v is Dictionary:
		for k: Variant in v:
			_texts(v[k], str(k), out)
	elif v is Array:
		for e: Variant in v:
			_texts(e, key, out)
	elif v is String:
		out.append(str(v))


func test_no_player_text_asks_to_plant_or_water() -> void:
	var rx := RegEx.create_from_string(ASKS)
	var hits: Array[String] = []
	for f: String in FILES:
		var d: Variant = Economy.read_json("res://data/%s.json" % f)
		var texts: Array[String] = []
		if f == "hex_levels":
			continue
		if f == "builds":
			continue  # ids only
		_texts(d, "", texts)
		for t: String in texts:
			if rx.search(t) != null and not (t in ALLOWED):
				hits.append("%s: %s" % [f, t])
	var hl: Dictionary = Economy.read_json("res://data/hex_levels.json")
	var lv_texts: Array[String] = []
	_texts(hl.get("auto_levels", []), "", lv_texts)
	for t: String in lv_texts:
		if rx.search(t) != null:
			hits.append("hex_levels auto: " + t)
	assert_eq(hits, [] as Array[String], "player text that asks for planting, watering or seeds")


func test_no_seed_currency() -> void:
	assert_eq(Currencies.ids(), ["cubes", "parts"] as Array[String])
	assert_false(Currencies.is_currency("seeds"))
	assert_true(Currencies.is_legacy("seeds"), "old ids still resolve (to nothing)")
	GameState.add_currency("seeds", BigNum.from_float(5.0))
	assert_eq(GameState.get_currency("seeds").to_float(), 0.0, "seeds are worth nothing outside a save")
	for g: Dictionary in Economy.read_json("res://data/goals.json").get("goals", []):
		assert_false((g.get("reward", {}) as Dictionary).has("seeds"), "goal %s pays no seeds" % str(g["id"]))
	for f: String in ["glim", "decor", "museum", "style_parts", "eggs", "events", "bloom", "homeward", "weekly", "camp", "planets"]:
		var text: String = JSON.stringify(Economy.read_json("res://data/%s.json" % f))
		assert_false(text.contains("\"seeds\":"), "%s has no seed cost or reward" % f)


func test_no_planting_goal_robot_or_step() -> void:
	for g: Dictionary in Economy.read_json("res://data/goals.json").get("goals", []):
		var key: String = str(g.get("key", ""))
		assert_false(key in ["plants_planted", "seeds_unlocked", "garden_stipend", "seedling", "drip"], "goal %s asks for planting" % str(g["id"]))
		assert_ne(str(g.get("type", "")), "hex_level", "goal %s waits for a hex level (it greens by itself)" % str(g["id"]))
	for a: Dictionary in Economy.read_json("res://data/achievements.json").get("achievements", []):
		var c: Dictionary = a.get("cond", {})
		assert_false(str(c.get("key", "")) in ["plants_planted", "seeds_unlocked"], "achievement %s asks for planting" % str(a["id"]))
	for t: Dictionary in Economy.read_json("res://data/robots.json").get("types", []):
		assert_false(str(t.get("role", "")) in ["plant", "water"], "robot %s plants or waters" % str(t["id"]))
	var ids: Array = (Economy.read_json("res://data/objectives.json").get("objectives", []) as Array).map(func(d: Dictionary) -> String: return str(d["id"]))
	for gone: String in ["seed", "scoop_size", "hex2", "map"]:
		assert_false(gone in ids, "the step %s is gone" % gone)
	for t: Dictionary in (Economy.read_json("res://data/events.json").get("contracts", {}) as Dictionary).get("templates", []):
		assert_false(str(t.get("id", "")) in ["plant", "bloom", "sustain"], "no Request to plant")


func test_it_greens_by_itself() -> void:
	assert_true(AutoGrow.on(), "data/plants.json player_planting is false")
	var g := Garden.new()
	assert_false(g.unlocked(), "no seed tool, no watering can")
	g.free()
	var hl: Dictionary = Economy.read_json("res://data/hex_levels.json")
	var names: Array = (hl.get("auto_levels", []) as Array).map(func(l: Dictionary) -> String: return str(l["name"]))
	assert_eq(names, ["Junk", "Clean", "Grassy", "Blooming", "Lush", "Thriving"])
	for l: Dictionary in hl.get("auto_levels", []):
		if int(l["level"]) >= 2:
			assert_true((l.get("reward", {}) as Dictionary).is_empty(), "level %d pays nothing: it comes by itself" % int(l["level"]))


func test_old_planting_save_migrates() -> void:
	var d: Dictionary = {"version": 5,
		"currencies": {"cubes": BigNum.from_float(100).serialize(), "parts": BigNum.from_float(10).serialize(), "seeds": BigNum.from_float(4).serialize()},
		"stats": {"plants_planted": 9},
		"flags": {"seeds_unlocked": true, "press_hopper": 7.5, "objective_step": 12,
			"contracts": {"slots": [{"state": "active", "tpl": "plant", "n": 12}, {"state": "offer", "tpl": "scoop", "n": 120}]}},
		"orbit": {"robots": {"robots": [{"type": "drip", "tier": 2, "name": "D-1", "dir": [0, 1, 0]}, {"type": "seedling", "tier": 0, "name": "S-2"},
			{"type": "multibot", "tier": 0, "name": "M-3", "role": "water"}, {"type": "scoopie", "tier": 1, "name": "C-4"}]},
			"hubs": {"3": {"robots": [{"type": "seedling", "tier": 1, "name": "S-5"}]}}}}
	var m: Dictionary = SaveManager.migrate(d)
	assert_eq(int(m["version"]), GameState.SAVE_VERSION)
	assert_false((m["currencies"] as Dictionary).has("seeds"))
	assert_almost_eq(BigNum.from_serialized(m["currencies"]["cubes"]).to_float(), 100.0 + 4.0 * 25.0, 0.01, "seeds became cubes")
	assert_false((m["flags"] as Dictionary).has("press_hopper"))
	var types: Array = (m["orbit"]["robots"]["robots"] as Array).map(func(r: Dictionary) -> String: return str(r["type"]))
	assert_eq(types, ["scoopie", "scoopie", "multibot", "scoopie"])
	assert_eq(str(m["orbit"]["robots"]["robots"][2]["role"]), "clean")
	assert_eq(int(m["orbit"]["robots"]["robots"][0]["tier"]), 2, "the same tier")
	assert_eq(str(m["orbit"]["hubs"]["3"]["robots"][0]["type"]), "scoopie", "far hubs' robots too")
	assert_eq(str(m["flags"]["contracts"]["slots"][0]["state"]), "wait", "the planting Request waits for a new offer")
	assert_eq(str(m["flags"]["contracts"]["slots"][1]["tpl"]), "scoop", "other Requests stay")
	var again: Dictionary = SaveManager.drop_planting(m.duplicate(true))
	assert_eq(JSON.stringify(again), JSON.stringify(m), "running it again changes nothing")


func test_card_on_the_seed_step_moves_on() -> void:
	var now: Array[String] = []
	for d: Dictionary in Economy.read_json("res://data/objectives.json").get("objectives", []):
		now.append(str(d["id"]))
	var seed_at: int = Objectives.ORDER_V4.find("seed")
	assert_eq(Objectives.remap_step(seed_at, Objectives.ORDER_V4, now), now.find("robot2"), "on the seed step: the second robot is next")
	assert_eq(Objectives.remap_step(Objectives.ORDER_V4.find("hex2"), Objectives.ORDER_V4, now), now.find("hex3"))
	assert_eq(Objectives.remap_step(Objectives.ORDER_V4.find("map"), Objectives.ORDER_V4, now), now.find("base2"))
	assert_eq(Objectives.remap_step(Objectives.ORDER_V4.find("scoop_size"), Objectives.ORDER_V4, now), now.find("baler"))
	assert_eq(Objectives.remap_step(Objectives.ORDER_V4.find("shuttle"), Objectives.ORDER_V4, now), now.find("shuttle"))
