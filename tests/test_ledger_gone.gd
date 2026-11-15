extends GutTest
## Owner item 105: "remove this whole ledger thing". The Ledger is gone from the player's game:
## no text of it in the data or the six languages, no class, event or build of it, and an old
## save that carries its state (also one taken in the middle of a Ledger step) loads clean.

var _before: Dictionary


func before_each() -> void:
	_before = GameState.to_dict()


func after_each() -> void:
	GameState.from_dict(_before)


## A v4 save with everything the Ledger ever wrote, taken mid-arc: act 3 (relay placed, not yet
## used), two jammers standing, coupons seen, an audit in the events' memory, both Codex pages.
func _old_save() -> Dictionary:
	return {"version": 4,
		"currencies": {"cubes": BigNum.from_float(100).serialize(), "parts": BigNum.from_float(10).serialize(), "seeds": BigNum.from_float(3).serialize()},
		"stats": {"hexes_cleaned": 41, "ledger_drops": 6, "ledger_jammed": 2, "ledger_seed_drops": 1},
		"flags": {"ledger_act": 3, "ledger_resolved": false, "ledger_relay_hub": 0, "ledger_coupons": [0, 3, 5],
			"seeds_unlocked": true, "first_sprout": true, "tutorial_step": 12,
			"once": {"toast_ledger_note": true, "wren_ledger_drop": true, "first_bale": true},
			"codex": ["shards:ledger_memo", "sightings:ledger_wreck", "homeward:ledger_system", "sightings:first_light"],
			"shards_found": ["maint_log", "ledger_memo"],
			"trinkets": ["streak_medal", "audit_stamp", "drone_propeller"],
			"events": {"next_in": 12.0, "recent": ["ledger_audit", "rain_shower"], "done": {"ledger_audit": 2, "rain_shower": 1}}},
		"world": {"hub_level": 3, "ledger_jammers": 2},
		"districts": {"1": {"hub_level": 1, "ledger_jammers": 1}}}


func test_old_save_drops_the_ledger() -> void:
	var m: Dictionary = SaveManager.migrate(_old_save())
	assert_eq(int(m["version"]), GameState.SAVE_VERSION)
	assert_false(JSON.stringify(m).to_lower().contains("ledger"), "no Ledger key or id is left: %s" % JSON.stringify(m))
	var fl: Dictionary = m["flags"]
	assert_eq(fl["codex"], ["shards:pause_memo", "homeward:buried_worlds", "sightings:first_light"], "the memo and the system page keep their place")
	assert_eq(fl["shards_found"], ["maint_log", "pause_memo"])
	assert_eq(fl["trinkets"], ["streak_medal"])
	assert_eq(fl["events"]["recent"], ["rain_shower"])
	assert_eq((fl["events"]["done"] as Dictionary).keys(), ["rain_shower"])
	assert_true(bool(fl["once"]["first_bale"]), "other once-marks stay")
	assert_eq(int(fl["tutorial_step"]), 12, "the story step is untouched")
	assert_eq(int(m["stats"]["hexes_cleaned"]), 41)
	# Three jammers stood (two at the base, one in another district): paid back at what they cost.
	var mult: float = (1.0 + 2.2) + 1.0
	assert_almost_eq(BigNum.from_serialized(m["currencies"]["cubes"]).to_float(), 100.0 + 900.0 * mult, 0.01)
	assert_almost_eq(BigNum.from_serialized(m["currencies"]["parts"]).to_float(), 10.0 + 42.0 * mult, 0.01)
	# Again: nothing more happens (no second refund).
	var again: Dictionary = SaveManager.drop_ledger(m.duplicate(true))
	assert_eq(JSON.stringify(again), JSON.stringify(m))


func test_old_save_loads_and_saves_round() -> void:
	GameState.from_dict(SaveManager.migrate(_old_save()))
	assert_false(GameState.flags.has("ledger_act"))
	assert_false(GameState.world.has("ledger_jammers"))
	assert_true(Codex.is_unlocked("shards:pause_memo"), "the memo read before is still read")
	assert_true(Codex.is_unlocked("homeward:buried_worlds"))
	assert_eq(Codex.count("shards"), 1)
	for key: String in Codex.unlocked_list():
		assert_false(Codex.entry(str(key)).is_empty(), "%s is a page that exists" % key)
	for id: Variant in Collection.found_list():
		assert_false(Collection.def(str(id)).is_empty(), "%s is a trinket that exists" % id)
	var back: Dictionary = SaveManager.migrate(GameState.to_dict())
	assert_false(JSON.stringify(back).to_lower().contains("ledger"))
	# The events' memory holds only events that exist: the next pick can't land on the audit.
	var elig: Dictionary = WorldEvents.eligible_ids({"junk_hexes": 9, "planted": 9, "robots": 2, "max_hex_level": 5, "parts_left": 2})
	assert_false(elig.has("ledger_audit"))
	for id: Variant in WorldEvents.persist_state()["recent"]:
		assert_false(WorldEvents.def(str(id)).is_empty(), "%s is an event that exists" % id)


func test_nothing_of_the_ledger_is_built() -> void:
	for cls: String in ["LedgerArc", "LedgerDrone", "LedgerUplink"]:
		assert_false(ClassDB.class_exists(cls) or _script_class(cls), "%s is gone" % cls)
	assert_false(FileAccess.file_exists("res://data/ledger.json"))
	for b: Dictionary in Economy.read_json("res://data/builds.json").get("builds", []):
		assert_ne(str(b.get("id", "")), "signal_jammer")
	assert_true(WorldEvents.def("ledger_audit").is_empty())
	assert_false(Subtitles.SPEAKERS.has("ledger"))


func _script_class(cls: String) -> bool:
	for c: Dictionary in ProjectSettings.get_global_class_list():
		if str(c["class"]) == cls:
			return true
	return false


## No player text says "Ledger": every data file, and every language (source and translation).
func test_no_ledger_text_in_data_or_languages() -> void:
	var bad: Array[String] = []
	for f: String in DirAccess.get_files_at("res://data"):
		if f.ends_with(".json") and FileAccess.get_file_as_string("res://data/" + f).to_lower().contains("ledger"):
			bad.append("data/" + f)
	for f: String in DirAccess.get_files_at("res://locale"):
		if not (f.ends_with(".po") or f.ends_with(".pot")):
			continue
		var n: int = 0
		for line: String in FileAccess.get_file_as_string("res://locale/" + f).split("\n"):
			if line.begins_with("#~"):
				continue  # an obsolete entry: never loaded
			var low: String = line.to_lower()
			if low.contains("ledger") or line.contains("レジャー"):
				n += 1
		if n > 0:
			bad.append("locale/%s (%d lines)" % [f, n])
	assert_eq(bad, [] as Array[String], "Ledger text left in: %s" % ", ".join(bad))


## What the Ledger pages became is still there to find.
func test_renamed_pages_exist() -> void:
	assert_false(Codex.entry("shards:pause_memo").is_empty())
	assert_false(Codex.entry("homeward:buried_worlds").is_empty())
	assert_true(Codex.entry("sightings:ledger_wreck").is_empty())
	var ids: Array = []
	for s: Dictionary in Economy.read_json("res://data/shards.json").get("shards", []):
		ids.append(str(s["id"]))
	assert_has(ids, "pause_memo")
	assert_eq(ids.size(), 8, "still eight memory shards (achievement shard_all)")
