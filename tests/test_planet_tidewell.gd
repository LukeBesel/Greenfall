extends GutTest
## [planet-tidewell] Tidewell environment: sea / land hexes, trash rafts keep the junk economy,
## the env builds headless on a small fake district, and its stages follow restoration.

class FakeWorld:
	extends Node3D
	var field: HexField
	var view: FieldView
	var water: Node3D
	var hub: Node = null
	var sky_director: Node = null
	var patch: Node3D = null
	var fleet: Node = null


func _kind() -> Dictionary:
	return (Economy.read_json("res://data/planets.json") as Dictionary).get("tidewell", {})


func _types() -> Array:
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	return types


func _field(seed_v: int = 4471) -> HexField:
	var k: Dictionary = _kind()
	TidewellEnv.prepare(k)
	var f := HexField.new(4, 10.0, seed_v, CityLayout.new(seed_v, 150.0, true))
	f.biome = "tidewell"
	f.biome_set = Economy.biome_set("tidewell")
	f.float_mult = 1.0
	f.water_ids = TidewellEnv.field_water(f, k)
	f.generate(_types(), Vector2i(20, 30))
	return f


func test_registered_in_planets_json() -> void:
	var k: Dictionary = _kind()
	assert_eq(str(k.get("world_type", "")), "ocean_world")
	assert_true(ResourceLoader.exists(str(k.get("env", ""))))
	for key: String in ["sky", "fog", "sun", "ambient", "palette", "junk_tint", "music_mood", "district"]:
		assert_true(k.has(key), "planets.json tidewell has " + key)


func test_mostly_ocean_with_islands() -> void:
	var f: HexField = _field()
	var water: int = 0
	var land: int = 0
	for id: int in f.hex_count():
		if f.hex_hub[id] != 0:
			continue
		if f.is_water(id):
			water += 1
		else:
			land += 1
	assert_gt(water, land * 3, "mostly water (%d water, %d land)" % [water, land])
	assert_gt(land, 4, "some dry hexes for planting")
	# Deterministic per seed.
	assert_eq(TidewellEnv.land_hexes(4, 4471), TidewellEnv.land_hexes(4, 4471))


func test_rafts_keep_volumes_and_slots() -> void:
	var f: HexField = _field()
	var vol_before: float = 0.0
	for pid: int in f.piece_count():
		vol_before += f.piece_vol[pid]
	var n: int = f.piece_count()
	TidewellEnv.post_generate(f, _kind())
	var vol_after: float = 0.0
	var moved_out: int = 0
	for pid: int in f.piece_count():
		vol_after += f.piece_vol[pid]
		if f.is_water(f.piece_hex[pid]) and f.hex_at(f.piece_pos[pid]) != f.piece_hex[pid]:
			moved_out += 1
	assert_eq(f.piece_count(), n)
	assert_almost_eq(vol_after, vol_before, 0.001)
	assert_eq(moved_out, 0, "raft pieces stay in their own hex")


func test_env_applies_headless_and_stages() -> void:
	var w := FakeWorld.new()
	add_child_autofree(w)
	w.field = _field()
	TidewellEnv.post_generate(w.field, _kind())
	w.view = FieldView.new()
	w.view.skip_horizon = true  # as the slice does for frontier-style districts
	w.add_child(w.view)
	w.view.setup(w.field)
	w.water = Node3D.new()
	w.add_child(w.water)
	var env: TidewellEnv = TidewellEnv.apply(w, w.field, _kind())
	assert_not_null(env.ocean, "ocean built")
	assert_eq(env.stage, 0, "starts ruined")
	assert_true((env._groups["ruin"] as Node3D).visible)
	assert_false((env._groups["future"] as Node3D).visible)
	# A deep sea offshore, dry land on the islands.
	var deep: float = env.bed_at(900.0, 0.0).x if env.islands.is_empty() else 0.0
	assert_lt(env.bed_at(0.0, env._field_edge + 120.0).x, 1.0)
	assert_lt(deep, 0.5)
	var isle: Dictionary = {}
	for i: Dictionary in env.islands:
		if str(i["kind"]) == "isle":
			isle = i
			break
	assert_false(isle.is_empty())
	assert_gt(env.bed_at((isle["c"] as Vector2).x, (isle["c"] as Vector2).y).x, HexField.WATER_Y)
	# Base level drives the stages.
	env.level = 3
	env._refresh(false)
	assert_eq(env.stage, 1)
	assert_true((env._groups["green"] as Node3D).visible)
	env.level = 5
	env._refresh(false)
	assert_eq(env.stage, 2)
	assert_true((env._groups["future"] as Node3D).visible)
	assert_false((env._groups["ruin"] as Node3D).visible)


func test_grade_blend() -> void:
	var g: Dictionary = TidewellEnv._blend_grade({"fog": [0.0, 0.0, 0.0], "fog_amt": 0.0}, {"fog": [1.0, 1.0, 1.0], "fog_amt": 1.0}, 0.5)
	assert_almost_eq(float(g["fog_amt"]), 0.5, 0.001)
	assert_almost_eq(float((g["fog"] as Array)[1]), 0.5, 0.001)


func test_suns_fallback() -> void:
	var s: Dictionary = BinarySun.suns_for("tidewell")
	assert_true(s.has("a") and s.has("b"))
	assert_gt(float(s["a"]["energy"]), float(s["b"]["energy"]), "the companion is the dimmer star")
	assert_gt(float(s["a"]["size"]), float(s["b"]["size"]))


func test_site_prefabs_build_and_restage() -> void:
	var reg: Dictionary = _kind().get("sites", {})
	for id: String in TideSite.SITES:
		assert_true(reg.has(id), "registry lists " + id)
		var root := Node3D.new()
		add_child_autofree(root)
		root.position = Vector3(500, 30, -200)  # anywhere: sites are local
		var s: TideSite = TideSite.place(id, root, 0, 0.0)
		assert_not_null(s.ocean, id + " has its sea patch")
		assert_true((s._groups["ruin"] as Node3D).visible)
		var live: int = 0
		for mmi: MultiMeshInstance3D in s._junk:
			live += mmi.multimesh.visible_instance_count
		assert_gt(live, 50, id + " is trashed when ruined")
		s.set_state(2, 1.0)
		assert_true((s._groups["future"] as Node3D).visible)
		var left: int = 0
		for mmi: MultiMeshInstance3D in s._junk:
			left += mmi.multimesh.visible_instance_count
		assert_eq(left, 0, id + " junk gone when restored")
