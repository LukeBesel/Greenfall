extends GutTest
## [planet-anvil] Anvil's env applies headless on a bare stub world (no view, sky or hub), the
## registry entry is complete, the junk set keeps types and counts, and the pure helpers hold.

var field: HexField


func before_each() -> void:
	var layout := CityLayout.new(4471, 150.0, true)
	field = HexField.new(9, 3.2, 4471, layout)


func _types() -> Array:
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	return types


func test_registry_entry_is_complete() -> void:
	var e: Dictionary = AnvilEnv.planet_entry()
	for k: String in ["id", "name", "world_type", "env", "sky", "fog", "sun", "ambient", "palette", "junk_tint", "music_mood"]:
		assert_true(e.has(k), "data/planets.json anvil lacks " + k)
	assert_true(ResourceLoader.exists(str(e.get("env", ""))))


func test_junk_swap_keeps_types_and_counts() -> void:
	var plain := HexField.new(9, 3.2, 4471, CityLayout.new(4471, 150.0, true))
	plain.generate(_types(), Vector2i(6, 12))
	AnvilEnv.prepare_field(field)
	field.generate(_types(), Vector2i(6, 12))
	assert_eq(field.biome, AnvilEnv.BIOME)
	assert_eq(field.piece_count(), plain.piece_count())
	var swapped: int = 0
	for pid: int in field.piece_count():
		assert_eq(field.piece_type[pid], plain.piece_type[pid])
		if field.piece_model[pid] != plain.piece_model[pid]:
			swapped += 1
	assert_gt(swapped, 0, "some junk should take Anvil's rusty models")


func test_restore_and_stages() -> void:
	assert_eq(AnvilEnv.restore_of({}), 0.0)
	assert_almost_eq(AnvilEnv.restore_of({1: 5, 2: 0}), 0.5, 0.001)
	assert_almost_eq(AnvilEnv.restore_of({1: 5, 2: 5}), 1.0, 0.001)
	assert_true(AnvilEnv.stage_visible("ruin", 1))
	assert_false(AnvilEnv.stage_visible("ruin", 2))
	assert_false(AnvilEnv.stage_visible("future", 3))
	assert_true(AnvilEnv.stage_visible("future", 5))
	assert_true(AnvilEnv.stage_visible("always", 4))


func test_applies_on_stub_world() -> void:
	field.generate(_types(), Vector2i(6, 12))
	var w := Node3D.new()
	add_child_autofree(w)
	AnvilEnv.apply(w, field, {})
	var env: AnvilEnv = w.get_node_or_null("AnvilEnv")
	assert_not_null(env)
	assert_gt(env.find_children("Terrain*", "MeshInstance3D", true, false).size(), 0)
	assert_not_null(env.find_child("CoreShaft", true, false))
	assert_eq(env.stacks.size(), 7)
	# The pit is a hole in the terrain; the field stays flat.
	assert_lt(env.height(env.pit_c.x, env.pit_c.z), -100.0)
	assert_eq(env.gy(Vector3(5, 0, 5)), 0.0)
	env.set_level(5, false)
	assert_true((env.groups["future"] as Node3D).visible)
	assert_false((env.groups["ruin"] as Node3D).visible)
	var s: Dictionary = env.suns()
	assert_true(s.has("a") and s.has("b"), "two suns")
	assert_lt(float(s["b"]["size"]), float(s["a"]["size"]))
