extends GutTest
## [planet-rime] Rime's environment: registry entry, pure helpers, and a headless build on a
## minimal stand-in world (no errors, the look groups follow the base level).


class FakeWorld:
	extends Node3D
	var field: HexField
	var view: FieldView
	var _env: Environment
	var _sun: DirectionalLight3D
	var sky_director: Node
	var patch: Node3D


func _field() -> HexField:
	var layout := CityLayout.new(4471, 150.0, true)
	var f := HexField.new(3, 10.0, 4471, layout)
	RimeEnv.prepare_field(f)
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	f.generate(types, Vector2i(20, 30))
	return f


func test_registry_entry() -> void:
	var def: PlanetDefinition = Planets.by_id(&"rime")
	assert_not_null(def, "rime is registered")
	var e: Dictionary = def.look()
	assert_eq(str(e.get("world_type")), "ice_moon")
	assert_eq(def.env_script, RimeEnv as Script)
	assert_ne(def.music_set, "")
	for k: String in ["name", "sky", "fog", "sun", "ambient", "palette", "junk_tint", "globe", "orbit"]:
		assert_true(e.has(k), "rime entry has %s" % k)


func test_biome_set_registers() -> void:
	var f: HexField = _field()
	assert_eq(f.biome, "rime")
	assert_false((f.biome_set.get("models", {}) as Dictionary).is_empty())
	for m: Variant in (f.biome_set["models"] as Dictionary).values():
		for d: Dictionary in m:
			assert_true(AssetLib.has_model(str(d["id"])), "model %s exists" % d["id"])


func test_stages_and_restore() -> void:
	assert_eq(RimeEnv.stages_for(1), ["always", "ruin"] as Array[String])
	assert_true("mid" in RimeEnv.stages_for(3))
	assert_true("future" in RimeEnv.stages_for(5))
	assert_false("ruin" in RimeEnv.stages_for(4))
	assert_eq(RimeEnv.restore_from_levels({}), 0.0)
	assert_almost_eq(RimeEnv.restore_from_levels({1: 5, 2: 0}), 0.5, 0.001)


func test_two_small_suns() -> void:
	var s: Dictionary = RimeEnv.suns_for_rime()
	assert_true(s.has("a") and s.has("b"))
	assert_lt(float(s["a"]["size"]), 1.0, "Rime's primary looks smaller than Verdance's")
	assert_lt(float(s["b"]["size"]), float(s["a"]["size"]))
	assert_lt(float(s["a"]["energy"]), 1.0, "weak daylight")


func test_env_applies_headless() -> void:
	var w := FakeWorld.new()
	add_child_autofree(w)
	w.field = _field()
	var env := Environment.new()
	env.sky = Sky.new()
	env.sky.sky_material = PhysicalSkyMaterial.new()
	w._env = env
	w._sun = DirectionalLight3D.new()
	w.add_child(w._sun)
	w.view = FieldView.new()
	RimeEnv.dress_view(w.view)
	w.add_child(w.view)
	w.view.setup(w.field)
	RimeEnv.apply(w, w.field, Planets.by_id(&"rime").look())
	var re: RimeEnv = w.get_node_or_null("RimeEnv")
	assert_not_null(re)
	assert_true(env.sky.sky_material is ShaderMaterial, "Rime's own sky")
	assert_gt(re.find_children("*", "MeshInstance3D", true, false).size(), 20)
	assert_gt(re.find_children("IceBody*", "StaticBody3D", true, false).size(), 0, "walkable ice near the field")
	re.set_level(1, false)
	assert_true((re.get_node("Ruin") as Node3D).visible)
	assert_false((re.get_node("Future") as Node3D).visible)
	re.set_level(5, false)
	re.set_restore(1.0)
	assert_false((re.get_node("Ruin") as Node3D).visible)
	assert_true((re.get_node("Future") as Node3D).visible)
	assert_almost_eq(re.warmth(), 1.0, 0.001)
	# Terrain: the field edge sits at ground level, the land rises toward the crater rim.
	assert_almost_eq(re.ground_y(0.0, 0.0), 0.0, 0.001)
	re._update_light()
