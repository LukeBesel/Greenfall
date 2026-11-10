extends GutTest
## [money] Three currencies (core/currencies.gd, data/currencies.json): the alias layer for the
## retired ids, cost folding, the v1 -> v2 save migration, and that every data file only prices
## things in cubes / parts / seeds.

var _cur: Dictionary
var _flags: Dictionary
var _stats: Dictionary


func before_each() -> void:
	_cur = GameState.currencies.duplicate()
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	GameState.currencies = {}
	Currencies.warn_legacy = false


func after_each() -> void:
	GameState.currencies = _cur
	GameState.flags = _flags
	GameState.stats = _stats
	Currencies.warn_legacy = true


func _f(id: String) -> float:
	return GameState.get_currency(id).to_float()


func test_exactly_three_currencies() -> void:
	assert_eq(Currencies.ids(), ["cubes", "parts", "seeds"] as Array[String])
	var ids: Array = []
	for c: Dictionary in Currencies.cfg()["currencies"]:
		ids.append(str(c["id"]))
		assert_ne(str(c.get("icon", "")), "", "%s has an icon" % c["id"])
	assert_eq(ids, ["cubes", "parts", "seeds"])
	for k: String in (Currencies.cfg()["legacy"] as Dictionary):
		assert_true(Currencies.canonical(k) in Currencies.IDS, "%s maps onto one of the three" % k)
	GameState.new_game()
	assert_eq(GameState.currencies.keys().size(), 3, "a new game starts with the three")


func test_legacy_alias_adds_and_reads_at_rate() -> void:
	GameState.add_currency("bolts", BigNum.from_float(4))
	assert_almost_eq(_f("parts"), 4.0 * Currencies.rate("bolts"), 0.001, "bolts become parts")
	assert_almost_eq(_f("bolts"), 4.0, 0.001, "reading the old id gives old units back")
	GameState.add_currency("sheet_metal", BigNum.from_float(10))
	assert_almost_eq(_f("parts"), 20.0 + 10.0, 0.001)
	GameState.add_currency("data", BigNum.from_float(3))
	assert_almost_eq(_f("cubes"), 30.0, 0.001, "Data pays cubes")
	GameState.add_currency("compost", BigNum.from_float(8))
	assert_almost_eq(_f("seeds"), 2.0, 0.001, "compost becomes seeds")
	assert_false(GameState.currencies.has("bolts"), "no legacy key is ever stored")
	assert_false(GameState.currencies.has("data"))


func test_legacy_alias_spends_and_affords() -> void:
	GameState.add_currency("parts", BigNum.from_float(50))
	assert_true(GameState.can_afford("bolts", BigNum.from_float(10)))
	assert_false(GameState.can_afford("bolts", BigNum.from_float(11)))
	assert_true(GameState.spend("bolts", BigNum.from_float(6)))
	assert_almost_eq(_f("parts"), 20.0, 0.001)
	assert_false(GameState.spend("glass_cullet", BigNum.from_float(21)))
	assert_almost_eq(_f("parts"), 20.0, 0.001, "a failed spend takes nothing")


func test_legacy_alias_warns_once_in_debug() -> void:
	Currencies.warn_legacy = true
	Currencies._warned.erase("tokens")
	GameState.add_currency("tokens", BigNum.from_float(1))
	assert_true(Currencies._warned.has("tokens") or not OS.is_debug_build(), "warned")
	assert_almost_eq(_f("parts"), Currencies.rate("tokens"), 0.001)


func test_fold_and_cost_dicts() -> void:
	var f: Dictionary = Currencies.fold({"cubes": 100, "sheet_metal": 20, "plastic_stock": 5, "bolts": 2, "research_tier": 3})
	assert_almost_eq(float(f["cubes"]), 100.0, 0.001)
	assert_almost_eq(float(f["parts"]), 35.0, 0.001)
	assert_eq(int(f["research_tier"]), 3, "non-currency keys are kept")
	assert_false(f.has("sheet_metal"))
	assert_false(GameState.can_afford_all({"cubes": 10, "parts": 5}))
	GameState.add_currency("cubes", BigNum.from_float(10))
	GameState.add_currency("parts", BigNum.from_float(5))
	assert_true(GameState.can_afford_all({"cubes": 10, "sheet_metal": 5}))
	assert_true(GameState.spend_all({"cubes": 10, "sheet_metal": 5}))
	assert_almost_eq(_f("cubes") + _f("parts"), 0.0, 0.001)
	assert_eq(Currencies.cost_text({"parts": 40, "cubes": 1500}), "1,500 cubes  ·  40 parts".replace("1,500", Settings.fmt(BigNum.from_float(1500))))


func test_migrate_v1_save_to_three_currencies() -> void:
	var old: Dictionary = {"version": 1, "currencies": {
		"cubes": BigNum.from_float(1000).serialize(), "seeds": BigNum.from_float(7).serialize(),
		"bolts": BigNum.from_float(10).serialize(), "sheet_metal": BigNum.from_float(30).serialize(),
		"plastic_stock": BigNum.from_float(20).serialize(), "glass_cullet": BigNum.from_float(5).serialize(),
		"data": BigNum.from_float(45).serialize(), "compost": BigNum.from_float(12).serialize(),
		"tokens": BigNum.from_float(6).serialize(), "trinkets": BigNum.from_float(2).serialize()},
		"flags": {"builder": {"fragments": 3, "inv": {}}, "contracts": {"slots": [{"state": "active", "tpl": "events", "tokens": 5}], "done_total": 3}}}
	var m: Dictionary = SaveManager.migrate(old)
	assert_eq(int(m["version"]), GameState.SAVE_VERSION)
	var cur: Dictionary = m["currencies"]
	assert_eq(cur.keys().size(), 3, "only cubes, parts and seeds are left")
	var cubes: float = BigNum.from_serialized(cur["cubes"]).to_float()
	var parts: float = BigNum.from_serialized(cur["parts"]).to_float()
	var seeds: float = BigNum.from_serialized(cur["seeds"]).to_float()
	assert_almost_eq(cubes, 1000.0 + 45.0 * 10.0 + 2.0 * 150.0, 0.01, "Data x10, trinkets x150")
	assert_almost_eq(parts, 10.0 * 5.0 + 30.0 + 20.0 + 5.0 + 6.0 * 5.0 + 3.0 * 25.0, 0.01, "bolts x5, stock x1, tokens x5, fragments x25")
	assert_almost_eq(seeds, 7.0, 0.01, "compost is not turned into seeds")
	assert_almost_eq(float(m["flags"]["press_hopper"]), 12.0, 0.01, "compost goes into the press hopper")
	assert_eq(int(m["flags"]["builder"]["fragments"]), 0)
	assert_eq(str(m["flags"]["contracts"]["slots"][0]["state"]), "wait", "the retired events contract is cleared")
	assert_eq(int(m["flags"]["contracts"]["done_total"]), 3, "finished contracts count toward the Requests track")
	GameState.from_dict(m)
	assert_almost_eq(_f("parts"), parts, 0.01)
	assert_almost_eq(Composter.hopper(), 12.0, 0.01)


func test_migrate_is_idempotent_for_v2() -> void:
	var d: Dictionary = {"version": 2, "currencies": {"cubes": BigNum.from_float(5).serialize(), "parts": BigNum.from_float(9).serialize()}}
	var m: Dictionary = SaveManager.migrate(d.duplicate(true))
	assert_almost_eq(BigNum.from_serialized(m["currencies"]["parts"]).to_float(), 9.0, 0.001)


## Every cost and reward in the data files is priced in the three currencies only.
func test_data_files_use_only_the_three() -> void:
	var legacy: Dictionary = Currencies.cfg()["legacy"]
	var bad: Array[String] = []
	for f: String in ["rockets", "decor", "designs", "robot_parts", "parts"]:
		_scan(Economy.read_json("res://data/%s.json" % f), f, legacy, bad)
	for t: String in ["hub", "stations", "outposts", "ledger", "goals", "eggs", "postgame", "regrowth", "events", "upgrades", "research", "robot_level"]:
		assert_true(Planets.current().has_table(t), "the planet has a '%s' table" % t)
		_scan(Economy.planet_table(t), t, legacy, bad)
	assert_eq(bad, [] as Array[String], "legacy currency keys in data: %s" % ", ".join(bad))


func _scan(v: Variant, where: String, legacy: Dictionary, bad: Array[String]) -> void:
	if v is Dictionary:
		for k: Variant in v:
			var key: String = str(k)
			if key in ["cost", "repair_cost", "relocate_cost", "reward", "resolve_reward", "source"] and v[k] is Dictionary:
				for ck: Variant in v[k]:
					if legacy.has(str(ck)):
						bad.append("%s %s.%s" % [where, key, str(ck)])
			_scan(v[k], where, legacy, bad)
	elif v is Array:
		for x: Variant in v:
			_scan(x, where, legacy, bad)
