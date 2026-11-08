extends GutTest
## [p_seas] Tidewell + Rime hub-site art pass: SeasKit meshes face outward, structures carry
## colliders (skimmers and Lumi stop at hulls, legs and cabins), Rime site prefabs build and
## restage with the same API shape as TideSite.


func _outward(m: Mesh) -> Vector2i:
	var a: Array = m.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var good: int = 0
	var bad: int = 0
	for t: int in range(0, v.size(), 3):
		var g: Vector3 = (v[t + 2] - v[t]).cross(v[t + 1] - v[t])
		if g.length() < 1e-9:
			continue
		if g.dot(n[t]) > 0.0:
			good += 1
		else:
			bad += 1
	return Vector2i(good, bad)


func test_kit_meshes_face_outward() -> void:
	for m: Mesh in [SeasKit.bevel_box(Vector3(2, 1, 3)), SeasKit.bevel_cyl(0.5, 2.0), SeasKit.hull_mesh(40.0, 10.0, 5.0)]:
		var s: Vector2i = _outward(m)
		assert_gt(s.x, 0)
		assert_eq(s.y, 0, "no inside-out triangles")


func _bodies(n: Node, layer: int) -> int:
	var c: int = 0
	for b: Node in n.find_children("*", "StaticBody3D", true, false):
		if (b as StaticBody3D).collision_layer & layer:
			c += 1
	return c


func test_tidewell_structures_are_solid() -> void:
	for id: String in ["wreck", "dredge_rig", "hub_raft"]:
		var root := Node3D.new()
		add_child_autofree(root)
		var s: TideSite = TideSite.place(id, root, 0, 0.0)
		assert_gt(_bodies(s, PhysLayers.PROP), 2, id + " has PROP colliders")
	var r2 := Node3D.new()
	add_child_autofree(r2)
	var raft: TideSite = TideSite.place("hub_raft", r2, 0, 0.0)
	assert_gt(_bodies(raft, PhysLayers.WORLD), 2, "raft decks and slipway are walkable")


func test_skimmer_ray_hits_the_wreck_hull() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	TideSite.place("wreck", root, 0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(-40, 0.5, 0), Vector3(40, 0.5, 0), PhysLayers.PROP)
	var hit: Dictionary = space.intersect_ray(q)
	assert_false(hit.is_empty(), "a skimmer at sea level runs into the hull")


func test_rime_sites_build_and_restage() -> void:
	for id: String in RimeSite.SITES:
		var root := Node3D.new()
		add_child_autofree(root)
		root.position = Vector3(300, 12, -80)
		var s: RimeSite = RimeSite.place(id, root, 0, 0.0)
		assert_true((s._groups["ruin"] as Node3D).visible, id + " ruined")
		assert_false((s._groups["green"] as Node3D).visible)
		assert_gt(_bodies(s, PhysLayers.WORLD), 0, id + " ice is walkable")
		assert_gt(_bodies(s, PhysLayers.PROP), 0, id + " structures are solid")
		s.set_state(1, 1.0)
		assert_true((s._groups["green"] as Node3D).visible, id + " restored")
		assert_false((s._groups["ruin"] as Node3D).visible)
		s.set_state(2, 1.0)
		assert_true((s._groups["future"] as Node3D).visible)


func test_rust_follows_restoration() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var s: TideSite = TideSite.place("wreck", root, 0, 0.0)
	var hull: ShaderMaterial = s._mats["k:hull"]
	var ruined: float = float(hull.get_shader_parameter("rust"))
	s.set_state(1, 1.0)
	assert_lt(float(hull.get_shader_parameter("rust")), ruined, "restoring cleans the rust")
