extends GutTest
## [fauna2] Animals never overlap each other or the street furniture (fauna/fauna_space.gd).


func test_animals_keep_their_distance() -> void:
	var deer_r: float = FaunaSpace.radius_of("deer", "deer")
	var duck_r: float = FaunaSpace.radius_of("duck", "swim")
	var others: Array = [Vector4(0, 0, deer_r, 0)]
	assert_false(FaunaSpace.spaced_ok(Vector3(0.2, 0.9, 0.1), duck_r, others), "no duck on a deer's back")
	assert_false(FaunaSpace.spaced_ok(Vector3(deer_r + duck_r - 0.05, 0, 0), duck_r, others), "bodies may not touch")
	assert_true(FaunaSpace.spaced_ok(Vector3(deer_r + duck_r + 0.05, 0, 0), duck_r, others))
	assert_true(FaunaSpace.spaced_ok(Vector3(5, 0, 5), duck_r, []), "alone is always fine")


func test_body_radii_follow_size() -> void:
	assert_gt(FaunaSpace.radius_of("deer", "deer"), FaunaSpace.radius_of("cat", "cat"))
	assert_gt(FaunaSpace.radius_of("cat", "cat"), FaunaSpace.radius_of("sparrow", "bird"))
	assert_gt(FaunaSpace.radius_of("seal", "seal"), FaunaSpace.radius_of("rabbit", "hopper"))
	assert_gt(FaunaSpace.radius_of("unknown", "bird"), 0.0, "every animal has a body")


func test_prop_grid_blocks_a_hydrant() -> void:
	var s := FaunaSpace.new()
	s.add_disc(Vector2(3.0, 4.0), 0.2)  # a hydrant
	assert_true(s.blocked(Vector3(3.0, 0, 4.0), 0.1), "standing on it")
	assert_true(s.blocked(Vector3(3.5, 0, 4.0), 0.4), "a deer's body would reach it")
	assert_false(s.blocked(Vector3(5.0, 0, 4.0), 0.4), "well clear")
	assert_false(FaunaSpace.new().blocked(Vector3.ZERO, 1.0), "an empty grid blocks nothing")


func test_prop_sizes() -> void:
	assert_true(FaunaSpace.prop_sized(AABB(Vector3(-0.2, 0.1, -0.2), Vector3(0.4, 0.8, 0.4))), "hydrant")
	assert_true(FaunaSpace.prop_sized(AABB(Vector3(-0.8, 0.12, -0.15), Vector3(1.6, 5.5, 0.3))), "lamp post with its arm")
	assert_false(FaunaSpace.prop_sized(AABB(Vector3(-20, 0, -20), Vector3(40, 0.1, 40))), "ground")
	assert_false(FaunaSpace.prop_sized(AABB(Vector3(-5, 0, -5), Vector3(11, 12, 11))), "a building")
	assert_false(FaunaSpace.prop_sized(AABB(Vector3(-1, 4.0, -0.1), Vector3(2, 0.4, 0.2))), "a festoon wire overhead")
	assert_false(FaunaSpace.prop_sized(AABB(Vector3(-0.1, 0, -0.1), Vector3(0.2, 0.05, 0.2))), "a flat manhole cover")


func test_scan_stamps_props_and_skips_ground_cover() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 0.9, 0.4)
	var bench := MeshInstance3D.new()
	bench.mesh = box
	root.add_child(bench)
	bench.global_position = Vector3(10, 0.45, 10)
	var weeds := MultiMeshInstance3D.new()
	weeds.name = "Weeds_tall"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(-10, 0.45, -10)))
	weeds.multimesh = mm
	root.add_child(weeds)
	var s := FaunaSpace.new()
	assert_eq(s.scan(root), 1)
	assert_true(s.blocked(Vector3(10, 0, 10), 0.2), "the bench blocks")
	assert_false(s.blocked(Vector3(-10, 0, -10), 0.2), "weeds don't")


func test_fences_and_the_yard() -> void:
	var lay := CityLayout.new(4471, 150.0, false)
	# The hub yard is for cats only.
	assert_false(FaunaSpace.layout_ok(lay, Vector3(2, 0, 2), 0.6), "no deer in the yard")
	assert_true(FaunaSpace.layout_ok(lay, Vector3(2, 0, 2), 0.6, true), "cats may sit by the base")
	assert_false(FaunaSpace.layout_ok(lay, Vector3(CityLayout.YARD_HALF + 0.3, 0, 0), 0.6), "nor on the yard fence")
	# Parking lots are fenced: keep off the fence line, the middle of the lot is fine.
	var key := Vector2i(0, -1)
	assert_eq(int(lay.blocks[key]["type"]), CityLayout.Block.PARKING)
	var r: Rect2 = lay.blocks[key]["rect"]
	var mid: Vector2 = r.get_center()
	assert_true(FaunaSpace.layout_ok(lay, Vector3(mid.x, 0, mid.y), 0.6))
	assert_false(FaunaSpace.layout_ok(lay, Vector3(r.position.x + 0.2, 0, mid.y), 0.6), "on the fence")
	assert_false(FaunaSpace.layout_ok(lay, Vector3(mid.x, 0, r.end.y - 0.3), 0.6), "on the other fence")
	# Buildings are never a spot.
	var bkey := Vector2i(1, 0)
	var bd: Dictionary = (lay.blocks[bkey]["buildings"] as Array)[0]
	var bc: Vector2 = (bd["rect"] as Rect2).get_center()
	assert_false(FaunaSpace.layout_ok(lay, Vector3(bc.x, 0, bc.y), 0.6, true), "inside a building")
	assert_true(FaunaSpace.layout_ok(null, Vector3.ZERO, 0.6), "no layout, no limits")


class FakeWorld:
	extends Node3D
	var field: HexField
	var hub_index: int = 0


func test_live_fauna_refuses_overlapping_spots() -> void:
	var w := FakeWorld.new()
	w.field = HexField.new(1, 10.0, 3)
	add_child_autofree(w)
	var fa := Fauna.new()
	fa.world = w
	w.add_child(fa)
	fa.set_process(false)
	var deer := Fauna.Animal.new()
	deer.sp = "deer"
	deer.kind = "deer"
	deer.hex = 0
	deer.pos = Vector3(1, 0, 1)
	deer.target = deer.pos
	fa.animals.append(deer)
	assert_false(fa.spot_free(Vector3(1.2, 0, 1.1), "duck", "swim"), "a duck can't land on the deer")
	assert_true(fa.spot_free(Vector3(3.0, 0, 1.0), "duck", "swim"))
	deer.target = Vector3(4, 0, 4)
	assert_false(fa.spot_free(Vector3(4.1, 0, 4.0), "fox", "quad"), "nor where the deer is heading")
	# A prop (a lamp post) on the field: the grid keeps animals out of it.
	var post := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.1
	cyl.bottom_radius = 0.12
	cyl.height = 4.0
	post.mesh = cyl
	w.add_child(post)
	post.global_position = Vector3(-3, 2.0, -2)
	fa._space_t = 0.0
	assert_false(fa.spot_free(Vector3(-3.1, 0, -2), "cat", "cat"), "never inside a lamp post")
	assert_true(fa.spot_free(Vector3(-1.5, 0, -2), "cat", "cat"))
	# Two animals walked into each other: separation pushes them apart.
	var fox := Fauna.Animal.new()
	fox.sp = "fox"
	fox.kind = "quad"
	fox.hex = 0
	fox.pos = Vector3(1.1, 0, 1.0)
	fox.target = fox.pos
	fa.animals.append(fox)
	for k: int in 12:
		fa._separate(fox)
		fa._separate(deer)
	var gap: float = Vector2(fox.pos.x - deer.pos.x, fox.pos.z - deer.pos.z).length()
	assert_gt(gap, FaunaSpace.radius_of("fox", "quad") + FaunaSpace.radius_of("deer", "deer") - 0.05, "pushed apart")
