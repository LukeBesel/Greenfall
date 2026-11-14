extends GutTest

const TEST_PATH: String = "user://test_save.save"


func test_roundtrip_gamestate() -> void:
	var before: Dictionary = GameState.to_dict()
	GameState.currencies["cubes"] = BigNum.new(3.25, 45)
	GameState.upgrades = {"scoop_width": 4}
	GameState.flags["beat_test"] = true
	GameState.world["field"] = {"seed": 1, "radius": 2, "alive": "AQE=", "clean": "AA=="}
	var d: Dictionary = GameState.to_dict()
	assert_true(SaveManager.write_dict(TEST_PATH, d))
	var back: Dictionary = SaveManager.migrate(SaveManager.read_dict(TEST_PATH))
	GameState.from_dict(back)
	assert_eq(GameState.get_currency("cubes").exponent, 45)
	assert_almost_eq(GameState.get_currency("cubes").mantissa, 3.25, 0.0001)
	assert_eq(GameState.level_of("scoop_width"), 4)
	assert_true(GameState.flags.get("beat_test", false))
	assert_eq(str(GameState.world["field"]["alive"]), "AQE=")
	GameState.from_dict(before)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func test_migrate_v0_float_currency() -> void:
	var old: Dictionary = {"currencies": {"cubes": 1234.0}}
	var m: Dictionary = SaveManager.migrate(old)
	assert_eq(int(m["version"]), GameState.SAVE_VERSION)
	assert_true(m["currencies"]["cubes"] is Array)
	assert_almost_eq(BigNum.from_serialized(m["currencies"]["cubes"]).to_float(), 1234.0, 0.01)


func test_field_roundtrip() -> void:
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	var f := HexField.new(4, 3.2, 77)
	f.generate(types)
	var removed: Array[int] = []
	for pid: int in range(0, f.piece_count(), 3):
		f.remove_piece(pid)
		removed.append(pid)
	var d: Dictionary = f.to_dict()
	var g := HexField.new(4, 3.2, 77)
	g.generate(types)
	assert_true(g.apply_dict(d))
	assert_eq(g.cleaned_count, f.cleaned_count)
	for pid: int in removed:
		assert_eq(g.piece_alive[pid], 0)
	for id: int in f.hex_count():
		assert_almost_eq(g.hex_left[id], f.hex_left[id], 0.001)


func test_field_rejects_mismatched_seed() -> void:
	var types: Array = [Economy.junk_types["metal"]]
	var f := HexField.new(3, 3.2, 1)
	f.generate(types)
	var g := HexField.new(3, 3.2, 2)
	g.generate(types)
	assert_false(g.apply_dict(f.to_dict()))
