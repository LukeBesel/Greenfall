extends GutTest
## [v6qa] Known-glitch list fixes on round Verdance (docs/QA_VERDANCE.md, "Known-glitch list").


func _hinterland() -> Hinterland:
	var grid: SphereGrid = SphereGrid.for_hex_size(7, 10.0)
	var h := Hinterland.new()
	h.grid = grid
	h.terrain = SphereTerrain.new(grid, 4471)
	h.cells = SphereCells.new(grid.cell_count())
	h.seed_value = 4471
	h._zone.seed = 4471 + 811
	h._zone.frequency = 1.0 / 380.0
	h._zone.noise_type = FastNoiseLite.TYPE_SIMPLEX
	h._angle.seed = 4471 + 812
	h._angle.frequency = 1.0 / 600.0
	h._track.seed = 4471 + 813
	h._track.frequency = 1.0 / 300.0
	h._track.noise_type = FastNoiseLite.TYPE_SIMPLEX
	return h


## Q3: a hinterland road that ends (a hub's clearance, a lake, steep ground) ends at a road block,
## and only a dead end gets one.
func test_dead_end_roads_get_a_road_block() -> void:
	var h: Hinterland = _hinterland()
	var ends: int = 0
	var blocks: int = 0
	var wrong: int = 0
	for c: int in h.grid.cells_within(Vector3(0.3, 0.8, 0.2).normalized(), 400.0):
		var mine: Array = h._candidate(c)
		var strips: int = mine.filter(func(e: Array) -> bool: return int(e[0]) == Hinterland.K_TRACK).size()
		var blk: int = mine.filter(func(e: Array) -> bool: return int(e[0]) == Hinterland.K_BARRIER).size()
		if strips == 2:  # one link: two half strips
			ends += 1
			blocks += blk
			if blk != 1:
				wrong += 1
		elif blk > 0:
			wrong += 1
	h.free()
	assert_gt(ends, 0, "the sample region has dead-end roads")
	assert_eq(blocks, ends, "every dead end has one road block")
	assert_eq(wrong, 0, "road blocks only at dead ends")


## Q9b: a ground patch built in slices (a hub town's lots in play) is the same patch.
func test_ground_patch_in_slices_matches() -> void:
	var size := Vector2(18, 18)
	var key: String = "patch:%.1f,%.1f:%s:%d:%s" % [size.x, size.y, "broken", 9137, str({})]
	KitMesh._meshes.erase(key)
	var a: Node3D = KitMesh.ground_patch(size, "broken", 9137)
	var da: Array = _patch_sig(a)
	KitMesh._meshes.erase(key)
	var bb: BuildBudget = BuildBudget.begin_play(get_tree(), 1)  # 1 us a frame: it yields at every check
	var f0: int = bb.frames
	var b: Node3D = await KitMesh.ground_patch_async(size, "broken", 9137)
	var yielded: int = bb.frames - f0
	if BuildBudget.current == bb:
		BuildBudget.end()
	assert_gt(yielded, 3, "it ran over several frames")
	assert_eq(_patch_sig(b), da, "same plates, grit and tufts")
	a.free()
	b.free()


func _patch_sig(n: Node3D) -> Array:
	var out: Array = []
	var m: ArrayMesh = (n.get_node("Plates") as MeshInstance3D).mesh
	for s: int in m.get_surface_count():
		out.append(m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
	for nm: String in ["Grit", "Tufts"]:
		var mm: MultiMesh = (n.get_node(nm) as MultiMeshInstance3D).multimesh
		var xs: Array = []
		for i: int in mm.instance_count:
			xs.append(mm.get_instance_transform(i))
		out.append(xs)
	return out


## Q9b: fauna's replan apply in 3 ms slices gives the same wanted animals as in one go.
func test_fauna_apply_in_slices_matches() -> void:
	var plan: Array = []
	var fd: Dictionary = {}
	var ids: Array = FaunaRules.ids()
	for i: int in 400:
		plan.append({"sp": ids[i % ids.size()], "hex": i, "n": 1 + i % 3})
		fd[i] = float(i % 90)
	var w := Node.new()
	add_child_autofree(w)
	var one := Fauna.new()
	var two := Fauna.new()
	for fa: Fauna in [one, two]:
		fa.world = w
		fa._cfg = {"spawn_radius": 55.0}
		fa._rp_plan = plan.duplicate()
		fa._rp_fd = fd.duplicate()
	one._rp_apply()
	var guard: int = 0
	while not two._rp_apply_split() and guard < 10000:
		guard += 1
	assert_eq(two._desired.keys(), one._desired.keys())
	assert_eq(two._rp_keys, one._rp_keys)
	one.free()
	two.free()
