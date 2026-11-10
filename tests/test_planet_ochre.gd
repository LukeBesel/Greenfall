extends GutTest
## [planet-ochre] Ochre's environment: registry entry, pit shape, junk registration, and a
## headless build + stage switch with no errors.


func test_registry_entry() -> void:
	var def: PlanetDefinition = Planets.by_id(&"ochre")
	assert_not_null(def, "ochre is registered")
	var k: Dictionary = def.look()
	for key: String in ["id", "name", "world_type", "sky", "fog", "sun", "ambient", "palette", "junk_tint", "globe", "orbit"]:
		assert_true(k.has(key), "ochre has %s" % key)
	assert_eq(def.env_script, OchreEnv as Script, "the definition names the env script")
	assert_ne(def.music_set, "")
	assert_true(Planets.has(&"rime"), "rime shares the registry")


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
	var k: Dictionary = Planets.by_id(&"ochre").look()
	var f := HexField.new(3, 3.2, 5)
	Planets.by_id(&"ochre").call_env("prepare_field", [f])
	assert_null(Planets.by_id(&"ochre").call_env("no_such_hook"), "a missing hook is skipped")
	assert_eq(f.biome, str(k["junk_biome"]), "prepare_field sets the junk biome")
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
	OchreEnv.apply(world, field, Planets.by_id(&"ochre").look())
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
	# Junk covers the pit while ruined and clears as it is restored.
	env.restore_shown = 0.0
	env._update_junk()
	var junk0: int = 0
	for p: Array in env._junk:
		junk0 += (p[0] as MultiMesh).visible_instance_count
	env.restore_shown = 1.0
	env._update_junk()
	var junk1: int = 0
	for p: Array in env._junk:
		junk1 += (p[0] as MultiMesh).visible_instance_count
	assert_gt(junk0, 3000, "the pit is trashed")
	assert_eq(junk1, 0, "restored pit is clean")


func test_site_prefabs_build_local() -> void:
	assert_eq(SiteBuilders.sites_of("ochre").size(), OchreSites.SITES.size(), "the sites table lists every site")
	for id: String in OchreSites.SITES:
		assert_false(SiteBuilders.find("ochre", id).is_empty(), "%s in the sites table" % id)
		for stage: int in [1, 5]:
			var root := Node3D.new()
			add_child_autofree(root)
			root.position = Vector3(500, 40, -300)  # anywhere: sites are local
			var site: Node3D = OchreSites.build(id, root, stage, 0.0 if stage == 1 else 1.0)
			var geo: Array = site.find_children("*", "GeometryInstance3D", true, false)
			assert_gt(geo.size(), 3, "%s stage %d has geometry" % [id, stage])
			var r: float = 0.0
			for g: Node in geo:
				var gi: GeometryInstance3D = g
				var aabb: AABB = gi.get_aabb()
				var c: Vector3 = root.to_local(gi.global_transform * aabb.get_center())
				r = maxf(r, Vector2(c.x, c.z).length())
			assert_lt(r, 60.0, "%s stays within its patch" % id)
