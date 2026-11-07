extends GutTest
## Street dressing must never get in the way: its only collision sits on hub ground (no junk,
## no plant slots) or outside the junk field, and the build is deterministic from the seed.

var layout: CityLayout
var field: HexField


func before_each() -> void:
	layout = CityLayout.new(4471, 150.0, false)
	field = HexField.new(9, 3.2, 4471, layout)
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	field.generate(types, Vector2i(6, 12))


func _build() -> StreetDressing:
	var d := StreetDressing.new()
	add_child_autofree(d)
	d.build(layout, field)
	return d


func _shapes(n: Node, out: Array) -> void:
	if n is CollisionShape3D:
		out.append(n)
	for c: Node in n.get_children():
		_shapes(c, out)


func test_collision_never_covers_junk() -> void:
	# [world2] Solid props stand anywhere now (lamps, kit, sign posts), but junk inside one is
	# nudged out to its edge (PropColliders.push_out_pieces), so nothing is ever unreachable.
	var d := _build()
	var shapes: Array = []
	_shapes(d, shapes)
	assert_gt(shapes.size(), 0)
	PropColliders.push_out_pieces(d, field)
	for cs: CollisionShape3D in shapes:
		if not cs.has_meta("foot"):
			continue
		var f: Vector3 = cs.get_meta("foot")
		for pid: int in field.pieces_within(Vector3(f.x, 0, f.y), f.z + 0.2):
			fail_test("piece %d still inside the prop at %s" % [pid, str(Vector2(f.x, f.y))])


func test_no_yard_fence_and_props_are_solid() -> void:
	# [world2] The owner walked through the yard fence: it is gone, and props sit on PhysLayers.PROP.
	var d := _build()
	var bodies: Array = d.find_children("*", "StaticBody3D", true, false)
	assert_gt(bodies.size(), 0)
	for b: StaticBody3D in bodies:
		if (b.get_parent() as Node3D).visible:
			assert_eq(b.collision_layer, PhysLayers.PROP)
	assert_false(d.has_method("_build_fence"), "no yard fence builder")


func test_deterministic_and_batched() -> void:
	var a := _build()
	var b := _build()
	assert_eq(a.get_child_count(), b.get_child_count())
	var mm_a: Array = a.get_children().filter(func(n: Node) -> bool: return n is MultiMeshInstance3D)
	var mm_b: Array = b.get_children().filter(func(n: Node) -> bool: return n is MultiMeshInstance3D)
	assert_eq(mm_a.size(), mm_b.size())
	for i: int in mm_a.size():
		assert_eq((mm_a[i] as MultiMeshInstance3D).multimesh.instance_count, (mm_b[i] as MultiMeshInstance3D).multimesh.instance_count)
	# Cheap: a few dozen nodes, not hundreds.
	assert_lt(a.get_child_count(), 60)


func test_ruined_base_fixes_up_with_level() -> void:
	var d := StreetDressing.new()
	add_child_autofree(d)
	d.build(layout, field, 3, "Ironside", "", 1)
	var ruin: Node3D = d.get_node("Ruin")
	assert_true(ruin.visible, "a non-starter base starts ruined")
	assert_false((d.get_node("Salvage") as Node3D).visible)
	assert_false((d.get_node("Future") as Node3D).visible)
	d.set_level(3, false)
	assert_false(is_instance_valid(ruin) and ruin.visible, "the ruin is cleared")
	assert_true((d.get_node("Future") as Node3D).visible, "level 3 brings the futuristic kit")
	assert_false((d.get_node("Thrive") as Node3D).visible)
	d.set_level(5, true)  # live: the flourish must not error


func test_starter_yard_is_never_ruined() -> void:
	var d := StreetDressing.new()
	add_child_autofree(d)
	d.build(layout, field, 0, "Old Town", "", 1)
	assert_false(d.has_node("Ruin"))
	assert_true((d.get_node("Yard") as Node3D).visible)
	assert_true((d.get_node("Salvage") as Node3D).visible)
