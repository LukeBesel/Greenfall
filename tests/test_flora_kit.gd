extends GutTest
## [art7] The regrowth plant kit (plants/flora_kit.gd, art/models/flora) and how CellVerdure picks
## from it: every mesh the code names exists and carries what the shader reads.


func test_the_kit_has_every_mesh_the_code_names() -> void:
	var names: Array[String] = ["grass_a", "grass_b", "grass_lod", "moss", "weed", "fern"]
	names.append_array(FloraKit.FLOWERS)
	names.append_array(FloraKit.BUSHES)
	for sp: int in FloraKit.TREES.size():
		for age: int in 3:
			names.append(FloraKit.tree(sp, age, false))
			names.append(FloraKit.tree(sp, age, true))
	for nm: String in names:
		var m: Mesh = FloraKit.mesh(nm)
		assert_not_null(m, nm)
		if m == null:
			continue
		var arr: Array = m.surface_get_arrays(0)
		assert_not_null(arr[Mesh.ARRAY_COLOR], nm + ": vertex colours (sway, occlusion, phase, kind)")
		assert_not_null(arr[Mesh.ARRAY_TEX_UV], nm + ": atlas UVs")
		assert_eq(m.get_surface_count(), 1, nm + ": one surface, one draw")


func test_far_twins_are_much_lighter_and_saplings_have_none() -> void:
	for sp: int in FloraKit.TREES.size():
		assert_eq(FloraKit.tree(sp, 0, true), FloraKit.tree(sp, 0, false), "a sapling is its own far mesh")
		for age: int in [1, 2]:
			var near: int = (FloraKit.mesh(FloraKit.tree(sp, age, false)).surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
			var far: int = (FloraKit.mesh(FloraKit.tree(sp, age, true)).surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
			assert_lt(far * 3, near, "%s age %d" % [FloraKit.TREES[sp], age])
			assert_lt(near / 3, 800, "a grown tree stays under 800 triangles")


func test_trees_stay_upright_and_sway_most_at_the_top() -> void:
	var m: Mesh = FloraKit.mesh("tree_oak_2")
	var arr: Array = m.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var top: float = 0.0
	var low_sway: float = 0.0
	var high_sway: float = 0.0
	for i: int in vs.size():
		top = maxf(top, vs[i].y)
	assert_between(top, 4.0, 9.0, "metres, y up")
	for i: int in vs.size():
		if vs[i].y < top * 0.1:
			low_sway = maxf(low_sway, cs[i].r)
		elif vs[i].y > top * 0.8:
			high_sway = maxf(high_sway, cs[i].r)
	assert_lt(low_sway, 0.02, "the foot of the trunk stands still")
	assert_gt(high_sway, 0.2, "the crown moves")


func test_the_material_is_shared_and_has_its_atlas() -> void:
	assert_same(FloraKit.material(), FloraKit.material())
	assert_true(FloraKit.material().get_shader_parameter("atlas") is Texture2D)


func test_area_pick_gives_one_kind_per_area_with_a_few_strays() -> void:
	var same: int = 0
	var p := Vector3(1200.0, 300.0, 1350.0)
	var first: int = CellVerdure._area_pick(p, 0.012, 1.7, 4, 0.5)
	for k: int in 200:
		var i: int = CellVerdure._area_pick(p + Vector3(k % 5, 0.0, k % 7) * 0.8, 0.012, 1.7, 4, fmod(k * 0.618, 1.0))
		assert_between(i, 0, 3)
		same += 1 if i == first else 0
	assert_gt(same, 150, "a grove is mostly one species")
	assert_lt(same, 200, "with a stray now and then")


func test_stages_follow_the_green() -> void:
	# A Clean cell (level 1) carries grass, weeds and moss but no trees; a Thriving one grows them up.
	assert_lt(CellVerdure.cover(CellVerdure.TARGET[1], 0.0), CellVerdure.TREE_AT[0], "no trees on a merely clean cell")
	assert_gt(CellVerdure.cover(CellVerdure.TARGET[5], 0.35), CellVerdure.TREE_AT[2], "grown trees on thriving land")
	assert_lt(CellVerdure.TREE_AT[0], CellVerdure.TREE_AT[1])
	assert_lt(CellVerdure.TREE_AT[1], CellVerdure.TREE_AT[2])
