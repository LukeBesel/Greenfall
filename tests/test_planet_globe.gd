extends GutTest
## [globes] PlanetGlobe (ui/planet_globe.gd): every planet builds, restoration and LOD reach the
## shaders, ring systems exist where they should, and the suns follow the binary-star canon.


func _make(id: String, r: float = 0.3) -> PlanetGlobe:
	var g := PlanetGlobe.new()
	add_child_autofree(g)
	g.setup(id, r)
	return g


func _multis(g: PlanetGlobe) -> Array:
	return g.find_children("*", "MultiMeshInstance3D", true, false)


func test_every_planet_builds() -> void:
	for id: String in PlanetGlobe.IDS:
		var g := _make(id)
		assert_eq(g.planet_id, id)
		var surf: MeshInstance3D = g.find_child("Body", true, false).get_child(0) as MeshInstance3D
		assert_not_null(surf, "%s has a surface" % id)
		var sm: ShaderMaterial = surf.material_override as ShaderMaterial
		assert_true(sm.shader.resource_path.ends_with("planet_%s.gdshader" % id), "%s uses its own shader" % id)
		assert_eq(g.find_children("*", "MeshInstance3D", true, false).size() >= 2, true, "%s has an atmosphere shell" % id)


func test_rings_and_clouds_where_fitting() -> void:
	assert_gt(_multis(_make("rime")).size(), 0, "Rime has its ring of ice spikes")
	assert_gt(_multis(_make("anvil")).size(), 0, "Anvil has its fire ring")
	assert_gt(_multis(_make("ochre")).size(), 0, "Ochre has its dust ring")
	assert_eq(_multis(_make("verdance")).size(), 0)
	assert_not_null(_make("tidewell").find_child("Clouds", true, false), "Tidewell has storm clouds")
	assert_not_null(_make("verdance").find_child("Clouds", true, false), "Verdance has clouds")
	var shards: MultiMeshInstance3D = null
	for m: Node in _multis(_make("rime")):
		if (m as MultiMeshInstance3D).multimesh.mesh is ArrayMesh:
			shards = m
	assert_not_null(shards, "the ice ring is instanced shards")
	assert_gt(shards.multimesh.instance_count, 100)


func test_restoration_reaches_every_material() -> void:
	var g := _make("verdance", 0.0)
	g.set_restoration(0.75)
	for mi: Node in g.find_children("*", "GeometryInstance3D", true, false):
		var m: ShaderMaterial = (mi as GeometryInstance3D).material_override as ShaderMaterial
		assert_almost_eq(float(m.get_shader_parameter("restoration")), 0.75, 0.001)
	g.set_restoration(4.0)
	assert_eq(g.restoration, 1.0, "clamped")


func test_lod_changes_octaves_and_instances() -> void:
	var g := _make("rime")
	var surf: MeshInstance3D = g.find_child("Body", true, false).get_child(0) as MeshInstance3D
	g.set_lod(0)
	var lo: int = int((surf.material_override as ShaderMaterial).get_shader_parameter("octaves"))
	var mm: MultiMesh = (_multis(g)[0] as MultiMeshInstance3D).multimesh
	var lo_n: int = mm.visible_instance_count
	g.set_lod(2)
	var hi: int = int((surf.material_override as ShaderMaterial).get_shader_parameter("octaves"))
	assert_lt(lo, hi)
	assert_lt(lo_n, mm.visible_instance_count)
	g.max_lod = 1
	g.set_lod(2)
	assert_eq(g.lod, 1, "max_lod caps it")


func test_two_suns_companion_is_warmer_and_dimmer() -> void:
	for id: String in PlanetGlobe.IDS:
		var s: Dictionary = PlanetGlobe.sun_light(id)
		var a: Color = s["a"]
		var b: Color = s["b"]
		assert_lt(b.get_luminance(), a.get_luminance(), "%s companion dimmer" % id)
		assert_gt(b.r / maxf(b.b, 0.001), a.r / maxf(a.b, 0.001), "%s companion warmer" % id)
	assert_gt(PlanetGlobe.sun_light("ochre")["a"].get_luminance(), PlanetGlobe.sun_light("rime")["a"].get_luminance(), "Ochre sits closer to the suns than Rime")


func test_sun_dirs_and_tracking() -> void:
	var g := _make("tidewell")
	g.set_sun_dirs(Vector3(1, 0, 0), Vector3(0, 0, 2))
	var surf: MeshInstance3D = g.find_child("Body", true, false).get_child(0) as MeshInstance3D
	var m: ShaderMaterial = surf.material_override as ShaderMaterial
	assert_almost_eq((m.get_shader_parameter("sun_b_dir") as Vector3).z, 1.0, 0.001)
	var a := Node3D.new()
	var b := Node3D.new()
	add_child_autofree(a)
	add_child_autofree(b)
	a.position = Vector3(0, 10, 0)
	b.position = Vector3(-10, 0, 0)
	g.track_suns(a, b)
	assert_almost_eq((m.get_shader_parameter("sun_a_dir") as Vector3).y, 1.0, 0.001)
	assert_almost_eq((m.get_shader_parameter("sun_b_dir") as Vector3).x, -1.0, 0.001)


func test_unknown_world_is_generic_rock() -> void:
	var g := PlanetGlobe.new()
	add_child_autofree(g)
	g.setup("Brightwater", 0.2, Color(0.3, 0.5, 0.7))
	assert_eq(g.planet_id, "brightwater")
	assert_eq(_multis(g).size(), 0)
	g.setup("rime", 0.1)
	assert_gt(_multis(g).size(), 0, "setup again rebuilds for the new id")
	assert_eq(g.find_children("Tilt", "", false, false).size(), 1, "no stale nodes")
