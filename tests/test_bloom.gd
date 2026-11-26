extends GutTest
## Post-game (systems/bloom.gd, data/bloom.json): Verdance Bloom milestones from Thriving
## districts / planet fraction, rewards paid once, and the endless Seed Ark waves.

var _flags: Dictionary
var _stats: Dictionary
var _cur: Dictionary


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_cur = GameState.currencies.duplicate()
	GameState.flags = {}
	GameState.stats = {}
	GameState.currencies = {}


func after_each() -> void:
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.currencies = _cur


func test_district_summary_from_live_summary_or_level_bytes() -> void:
	assert_eq(Bloom.district_summary({"bloom_summary": {"thriving": 150, "land": 200}}), Vector2i(150, 200))
	var raw := PackedByteArray()
	raw.resize(40)
	raw.fill(0)
	for i: int in 12:
		raw[i] = 5
	raw[20] = 4
	var s: Vector2i = Bloom.district_summary({"hex_levels": {"levels": Marshalls.raw_to_base64(raw)}})
	assert_eq(s.x, 12, "only level-5 (Thriving) hexes count")
	assert_eq(s.y, int(Bloom.cfg()["default_land_hexes"]))
	assert_eq(Bloom.district_summary({}), Vector2i(0, int(Bloom.cfg()["default_land_hexes"])))


func test_thriving_district_threshold() -> void:
	assert_true(Bloom.is_thriving_district(Vector2i(120, 200), 0.6))
	assert_false(Bloom.is_thriving_district(Vector2i(119, 200), 0.6))
	assert_false(Bloom.is_thriving_district(Vector2i(0, 0), 0.6))
	var m: Dictionary = Bloom.measure([Vector2i(150, 200), Vector2i(30, 200), Vector2i(200, 230)] as Array[Vector2i], 0.004)
	assert_eq(int(m["thriving_hexes"]), 380)
	assert_eq(int(m["thriving_districts"]), 2)
	assert_almost_eq(float(m["planet_pct"]), 0.4, 0.0001)


func test_milestones_unlock_in_order_and_pay_once() -> void:
	var none: Dictionary = {"thriving_hexes": 0, "thriving_districts": 0, "planet_pct": 0.0}
	assert_eq(Bloom.check(none), [] as Array[String])
	var some: Dictionary = {"thriving_hexes": 30, "thriving_districts": 1, "planet_pct": 0.1}
	var got: Array[String] = Bloom.check(some)
	assert_eq(got, ["first_meadow", "thriving_district"] as Array[String])
	assert_true(GameState.flags.get("bloom_first_meadow", false))
	var cubes: float = GameState.get_currency("cubes").to_float()
	assert_almost_eq(cubes, 1800.0 + 4600.0, 0.01, "[money] old trinket rewards are 150 cubes each")
	assert_eq(Bloom.check(some), [] as Array[String], "never twice")
	assert_almost_eq(GameState.get_currency("cubes").to_float(), cubes, 0.01)
	# [beat] Three districts in bloom no longer end the game: the Verdance Bloom (the finale) is
	# the Cradle path, or 2% of the planet.
	var three: Dictionary = {"thriving_hexes": 90, "thriving_districts": 3, "planet_pct": 1.05}
	var got3: Array[String] = Bloom.check(three)
	assert_true("green_shoots" in got3)
	assert_false("verdance_bloom" in got3, "no early finale from three thriving districts")
	var cradle: Dictionary = {"thriving_hexes": 90, "thriving_districts": 3, "planet_pct": 1.05, "cradle_returned": 1.0}
	assert_true("verdance_bloom" in Bloom.check(cradle))
	var pct: Dictionary = {"thriving_hexes": 30, "thriving_districts": 1, "planet_pct": 1.05}
	assert_false("wide_bloom" in Bloom.check(pct))
	var ms: Dictionary = Bloom.milestones().filter(func(m: Dictionary) -> bool: return m["id"] == "wide_bloom")[0]
	assert_almost_eq(Bloom.progress(ms, pct), 0.35, 0.001)


func test_seed_ark_locked_until_bloom_then_endless_waves() -> void:
	GameState.stats["plants_bloomed"] = 500.0
	assert_false(Bloom.ark_unlocked())
	assert_eq(Bloom.ark_step(), 0)
	assert_eq(Bloom.globe_line(), "")
	Bloom.done_list().append("verdance_bloom")
	assert_true(Bloom.ark_unlocked())
	# Counting starts when the Ark opens: old blooms don't count.
	assert_eq(Bloom.ark_progress(), 0)
	assert_string_contains(Bloom.globe_line(), "Seed Ark wave 1")
	var t0: int = Bloom.ark_target(0)
	var t1: int = Bloom.ark_target(1)
	assert_gt(t1, t0, "waves grow")
	GameState.stats["plants_bloomed"] = 500.0 + t0 - 1
	assert_eq(Bloom.ark_step(), 0)
	GameState.stats["plants_bloomed"] = 500.0 + t0 + t1 + 3
	assert_eq(Bloom.ark_step(), 2, "a big catch-up finishes several waves")
	assert_eq(int(Bloom.ark_state()["wave"]), 2)
	assert_eq(Bloom.ark_progress(), 3)
	assert_almost_eq(float(GameState.stats.get("ark_waves", 0.0)), 2.0, 0.001)
	assert_gt(GameState.get_currency("seeds").to_float(), 0.0)
	assert_string_contains(Bloom.globe_line(), "wave 3")


func test_globe_line_shows_next_bloom_before_the_ark() -> void:
	Bloom.done_list().append("first_meadow")
	assert_string_contains(Bloom.globe_line(), "Verdance Bloom 1 /")


func test_bloom_achievements_wired() -> void:
	for id: String in ["bloom_meadow", "bloom_verdance", "ark_1", "curio_5", "biome_1", "wild_curio"]:
		assert_false(Achievements.def(id).is_empty(), id)
	GameState.flags["bloom_verdance_bloom"] = true
	assert_true(Achievements.met(Achievements.def("bloom_verdance")))
	GameState.flags["biomes_visited"] = ["dust_dunes", "frostcap", "rustlands"]
	assert_true(Achievements.met(Achievements.def("biome_3")))
