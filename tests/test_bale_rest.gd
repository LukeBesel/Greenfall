extends GutTest
## [world2] Bales rest ON whatever is under them: flat ground, a curb, a junk heap; never inside it,
## never through it (spawned overlapping the ground, dropped fast, put down after being carried).

var root: Node3D


func before_each() -> void:
	root = Node3D.new()
	add_child_autofree(root)
	# Flat ground like FieldView's GroundBody (top at y = 0).
	var g := StaticBody3D.new()
	var gs := CollisionShape3D.new()
	var gb := BoxShape3D.new()
	gb.size = Vector3(60, 1, 60)
	gs.shape = gb
	gs.position = Vector3(0, -0.5, 0)
	g.add_child(gs)
	root.add_child(g)
	# A sidewalk slab with a bevelled curb like CityView's (top at CURB_H), x in [4, 8].
	var w := StaticBody3D.new()
	var ws := CollisionShape3D.new()
	var cv := ConvexPolygonShape3D.new()
	var h: float = CityLayout.CURB_H
	cv.points = PackedVector3Array([Vector3(3.65, 0, -2.35), Vector3(8.35, 0, -2.35), Vector3(8.35, 0, 2.35), Vector3(3.65, 0, 2.35),
		Vector3(4, h, -2), Vector3(8, h, -2), Vector3(8, h, 2), Vector3(4, h, 2)])
	ws.shape = cv
	w.add_child(ws)
	root.add_child(w)


func _bale(pos: Vector3, fill: float = 1.0, lumpy: bool = false) -> JunkCube:
	var c := JunkCube.create(BigNum.from_float(10.0), {"fill": fill, "lumpy": lumpy, "colors": [Color(0.5, 0.45, 0.4)]})
	root.add_child(c)
	c.global_position = pos
	return c


func _half_h(c: JunkCube) -> float:
	return ((c.get("_shape") as CollisionShape3D).shape as BoxShape3D).size.y * 0.5


func test_dropped_bale_rests_on_flat_ground() -> void:
	var c := _bale(Vector3(0, 1.5, 0))
	await wait_physics_frames(240)
	assert_almost_eq(c.global_position.y, _half_h(c), 0.03, "bottom on the ground, not in it")


func test_bale_spawned_inside_the_ground_pops_out() -> void:
	var c := _bale(Vector3(-2, 0.05, 0))  # its lower half is inside the slab
	await wait_physics_frames(240)
	assert_gt(c.global_position.y, _half_h(c) - 0.03)
	assert_lt(c.global_position.y, _half_h(c) + 0.08)


func test_fast_drop_never_tunnels() -> void:
	var c := _bale(Vector3(2, 6.0, -4), 0.3)  # the smallest bale
	c.linear_velocity = Vector3(0, -40, 0)
	await wait_physics_frames(240)
	assert_gt(c.global_position.y, 0.0, "no tunnelling through the ground")
	assert_almost_eq(c.global_position.y, _half_h(c), 0.04)


func test_bale_on_the_curb_sits_on_the_sidewalk() -> void:
	var c := _bale(Vector3(6, 1.0, 0))
	await wait_physics_frames(240)
	assert_almost_eq(c.global_position.y, CityLayout.CURB_H + _half_h(c), 0.04)


func test_overstuffed_bale_box_matches_its_look() -> void:
	var c := _bale(Vector3(-4, 1.2, 3), 1.1, true)
	await wait_physics_frames(240)
	var vis: Node3D = c.get("_visual")
	# The drawn bale is (1.08, 0.9, 1.02) x size: its bottom must not be below the ground.
	assert_almost_eq(_half_h(c), vis.scale.y * 0.5 * 1.045, 0.005)
	assert_almost_eq(c.global_position.y, _half_h(c), 0.04)


func test_bale_rests_on_a_junk_mound_and_settles_as_it_shrinks() -> void:
	var pile := Vector4(-8, 6, 2.0, 1.2)
	var body: StaticBody3D = MoundColliders.make(root, pile)
	var sc := Vector3(pile.z * 1.1, pile.w * 0.9, pile.z * 1.1)
	MoundColliders.update(body, sc, true)
	await wait_physics_frames(2)
	var c := _bale(Vector3(pile.x, 2.5, pile.y))
	await wait_physics_frames(240)
	assert_gt(c.global_position.y, sc.y * MoundColliders.INSET_H * 0.8, "on top of the heap, not sunk into it")
	# The hex gets cleaned: the heap shrinks away and the bale comes down to the ground.
	MoundColliders.update(body, Vector3(sc.x, 0.0, sc.z), false)
	await wait_physics_frames(300)
	assert_almost_eq(c.global_position.y, _half_h(c), 0.05)


func test_heaps_are_solid_for_lumi_and_bots_and_shrink_as_cleared() -> void:
	# [world2] Playtest #2: Lumi stood inside heaps and vacuumed the whole pile.
	var pile := Vector4(12, -6, 2.0, 1.2)
	var body: StaticBody3D = MoundColliders.make(root, pile)
	assert_true(body.collision_layer & PhysLayers.PROP != 0, "heaps block Lumi and robots")
	var sc := Vector3(pile.z * 1.1, pile.w * 0.9, pile.z * 1.1)
	MoundColliders.update(body, sc, true, 1.0)
	await wait_physics_frames(2)
	var space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state
	var q := PhysicsPointQueryParameters3D.new()
	q.collision_mask = PhysLayers.SOLID
	q.position = Vector3(pile.x + 1.6, 0.15, pile.y)
	assert_false(space.intersect_point(q).is_empty(), "the full heap's edge is solid")
	MoundColliders.update(body, Vector3(sc.x, sc.y * 0.4, sc.z), true, 0.3)
	await wait_physics_frames(2)
	assert_true(space.intersect_point(q).is_empty(), "a mostly cleared heap has drawn in")
	q.position = Vector3(pile.x, 0.1, pile.y)
	assert_false(space.intersect_point(q).is_empty(), "what is left is still solid")


func _front_ratio(m: Mesh) -> float:
	# Godot's front faces wind clockwise seen from outside: (b - a) x (c - a) points inward.
	var good: int = 0
	var all: int = 0
	for s: int in m.get_surface_count():
		var arr: Array = m.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var n: int = idx.size() if not idx.is_empty() else v.size()
		for t: int in range(0, n, 3):
			var a: Vector3 = v[idx[t] if not idx.is_empty() else t]
			var b: Vector3 = v[idx[t + 1] if not idx.is_empty() else t + 1]
			var c: Vector3 = v[idx[t + 2] if not idx.is_empty() else t + 2]
			var cr: Vector3 = (b - a).cross(c - a)
			if cr.length() < 1e-9:
				continue
			all += 1
			if cr.dot((a + b + c) / 3.0) < 0.0:
				good += 1
	return float(good) / maxf(all, 1)


func test_bale_faces_point_outward() -> void:
	# [world2] An inside-out bale renders see-through (the "transparent" bale): its back faces show.
	assert_gt(_front_ratio(JunkCube.bale_mesh()), 0.99, "bale block winds outward")
	assert_gt(_front_ratio(ProcMesh.box(Vector3.ONE)), 0.99, "reference: ProcMesh.box")
	assert_gt(_front_ratio(FieldView._mound_mesh()), 0.9, "junk heaps wind outward")
	# The bale used ProcMesh.rounded_box, which was inside-out: the owner's "transparent" bale.
	assert_gt(_front_ratio(ProcMesh.rounded_box(Vector3.ONE, 0.05, 3)), 0.99, "rounded_box winds outward")
