extends GutTest
## [planet-ochre] Ochre's environment: registry entry, pit shape, junk registration, and a
## headless build + stage switch with no errors.


func test_registry_entry() -> void:
	var k: Dictionary = PlanetEnvs.kind("ochre")
	assert_false(k.is_empty(), "data/planets.json has ochre")
	for key: String in ["id", "name", "world_type", "env_script", "sky", "fog", "sun", "ambient", "palette", "junk_tint", "music_mood"]:
		assert_true(k.has(key), "ochre has %s" % key)
	assert_true(ResourceLoader.exists(str(k["env_script"])), "env script exists")
	assert_not_null(PlanetEnvs.script_for(k), "env script loads")


func test_pit_shape() -> void:
	var pit := OchrePit.new(7)
	# The play field (radius ~55 m round the origin) sits flat on the haul bench.
	for a: float in [0.0, 1.0, 2.0, 3.0, 4.0, 5.0]:
		for r: float in [0.0, 30.0, 58.0]:
			assert_almost_eq(pit.height_at(cos(a) * r, sin(a) * r), 0.0, 0.5, "field bench flat at %.1f, %.0f" % [a, r])
	# Terraces climb to the rim and drop to the floor.
	var floor_p: Vector2 = pit.world_at(1.0, OchrePit.FLOOR_R - 3.0)
	assert_almost_eq(pit.height_at(floor_p.x, floor_p.y), OchrePit.FLOOR_Y, 1.0, "pit floor")
	var rim_p: Vector2 = pit.world_at(-1.0, OchrePit.RIM_RHO + 5.0)
	assert_gt(pit.height_at(rim_p.x, rim_p.y), OchrePit.RIM_Y - 1.0, "rim plateau")
	var last: float = -999.0
	for k: int in OchrePit.N_UP:
		var p: Vector2 = pit.world_at(-2.0, OchrePit.FIELD_OUT + OchrePit.STEP_P * k + OchrePit.WALL_W + 3.0)
		var h: float = float(pit.sample(-2.0, OchrePit.FIELD_OUT + OchrePit.STEP_P * k + OchrePit.WALL_W + 3.0)[0])
		assert_gt(h, last, "bench %d higher than the one below" % k)
		last = h
		assert_true(p.length() > 60.0, "benches lie beyond the field")
	# Each haul ramp climbs one step.
	for r: Dictionary in pit.ramps:
		var y0: float = float(pit.ramp_at(r, float(r["th0"]) + 0.0001)[0])
		var y1: float = float(pit.ramp_at(r, float(r["th1"]) - 0.0001)[0])
		assert_almost_eq(absf(y1 - y0), absf(float(r["y1"]) - float(r["y0"])), 0.5, "ramp spans its step")


func test_prepare_registers_junk() -> void:
	var k: Dictionary = PlanetEnvs.kind("ochre")
	PlanetEnvs.prepare(k)
	var set: Dictionary = Economy.biome_set(str(k["junk_biome"]))
	assert_false(set.is_empty(), "junk biome set registered")
	for type_id: String in (set["models"] as Dictionary):
		for m: Dictionary in set["models"][type_id]:
			var id: String = str(m["id"])
			assert_true(AssetLib.has_model(id) or AssetLib._meshes.has(id), "model %s exists" % id)
	for id: String in OchreProps.junk_meshes():
		var mesh: Mesh = AssetLib.model_mesh_lite(id, 320)
		assert_gt(mesh.get_surface_count(), 0, "%s has a surface" % id)
		assert_not_null(mesh.surface_get_material(0), "%s has a material" % id)


func test_apply_headless_and_stages() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	var field := HexField.new(4, 3.2, 11)
	OchreEnv.apply(world, field, PlanetEnvs.kind("ochre"))
	var env: OchreEnv = world.get_node_or_null("OchreEnv")
	assert_not_null(env, "env node added")
	assert_gt(env.find_children("Pit*", "MeshInstance3D", true, false).size(), 8, "pit terrain sectors")
	assert_not_null(env.find_child("Mesas", true, false), "mesas")
	env.set_level(1, false)
	assert_true((env._groups["ruin"] as Node3D).visible, "ruin layer at base 1")
	assert_false((env._groups["future"] as Node3D).visible, "no future layer at base 1")
	env.set_level(5, false)
	assert_false((env._groups["ruin"] as Node3D).visible, "ruin layer gone at base 5")
	assert_true((env._groups["future"] as Node3D).visible, "future layer at base 5")
	# Plants climb the terraces with restoration.
	env.restore_shown = 0.0
	env._update_plants()
	var shown0: int = 0
	for p: Array in env._plants:
		shown0 += (p[0] as MultiMesh).visible_instance_count
	env.restore_shown = 1.0
	env._update_plants()
	var shown1: int = 0
	var total: int = 0
	for p: Array in env._plants:
		shown1 += (p[0] as MultiMesh).visible_instance_count
		total += (p[0] as MultiMesh).instance_count
	assert_eq(shown0, 0, "no plants while ruined")
	assert_eq(shown1, total, "every plant once restored")
	assert_gt(total, 500, "plenty of plants")
