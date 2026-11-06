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


func test_collision_only_on_hub_ground_or_outside_field() -> void:
	var d := _build()
	var shapes: Array = []
	_shapes(d, shapes)
	assert_gt(shapes.size(), 0)
	for cs: CollisionShape3D in shapes:
		var box := cs.shape as BoxShape3D
		var c: Vector3 = cs.global_position
		var h: Vector3 = box.size * 0.5
		for o: Vector3 in [Vector3.ZERO, Vector3(h.x, 0, h.z), Vector3(-h.x, 0, h.z), Vector3(h.x, 0, -h.z), Vector3(-h.x, 0, -h.z)]:
			var hid: int = field.hex_at(c + o)
			assert_true(hid < 0 or field.hex_hub[hid] != 0, "collision at %s sits on a junk hex" % str(c + o))
		assert_eq(field.pieces_within(c, maxf(h.x, h.z) + 0.3).size(), 0, "collision covers junk near %s" % str(c))


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
