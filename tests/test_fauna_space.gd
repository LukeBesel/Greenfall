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


func test_songbird_perches() -> void:
	assert_true(FaunaSpace.perch_sized(AABB(Vector3(-0.8, 0.1, -0.2), Vector3(1.6, 5.4, 0.4))), "a lamp post")
	assert_true(FaunaSpace.perch_sized(AABB(Vector3(0, 9.0, 0), Vector3(3.0, 0.6, 0.5))), "a roof crown")
	assert_false(FaunaSpace.perch_sized(AABB(Vector3(-0.2, 0, -0.2), Vector3(0.4, 0.9, 0.4))), "a hydrant is too low")
	assert_false(FaunaSpace.perch_sized(AABB(Vector3(-6, 0, -6), Vector3(12, 15, 12))), "a whole building")
	var cyl := CylinderMesh.new()
	cyl.height = 4.0
	cyl.top_radius = 0.1
	var top: Vector3 = FaunaSpace.top_point(cyl)
	assert_almost_eq(top.y, 2.0, 0.01, "on top of the post")
	assert_almost_eq(Vector2(top.x, top.z).length(), 0.0, 0.05, "in the middle")
	var s := FaunaSpace.new()
	s.perches = PackedVector3Array([Vector3(0, 5, 0), Vector3(3, 5, 0), Vector3(30, 5, 0)])
	var got: Array[Vector3] = s.free_perches(Vector3(1, 0, 0), 10.0, [])
	assert_eq(got.size(), 2, "only the near ones")
	assert_eq(got[0], Vector3(0, 5, 0), "nearest first")
	assert_eq(s.free_perches(Vector3(1, 0, 0), 10.0, [Vector3(0, 5, 0)]).size(), 1, "one bird per perch")


func test_frontier_ambience() -> void:
	assert_eq(FaunaAmbience.kind_for(["dust_flats"]), "desert")
	assert_eq(FaunaAmbience.kind_for(["wild", "wild_frost"]), "port")
	assert_eq(FaunaAmbience.kind_for(["sunken_city"]), "sunken")
	assert_eq(FaunaAmbience.kind_for(["city"]), "", "the city has its own sounds")
	assert_gt(float(FaunaAmbience.levels("desert", 0.0)["insects"]), 0.2, "insects by day")
	assert_almost_eq(float(FaunaAmbience.levels("desert", 1.0)["insects"]), 0.0, 0.001, "quiet at night")
	assert_true(FaunaAmbience.levels("sunken", 0.0).has("lapping"))
	var lp: PackedFloat32Array = FaunaSounds.loopify(PackedFloat32Array([1, 1, 1, 1, 0, 0]), 2.0 / FaunaSounds.RATE)
	assert_eq(lp.size(), 4, "the tail is folded into the start")
	assert_almost_eq(lp[0], 0.0, 0.001, "starts where it ended")
	for id: String in ["wind", "insects", "lapping"]:
		var w: AudioStreamWAV = FaunaSounds.loop_stream(id)
		assert_eq(w.loop_mode, AudioStreamWAV.LOOP_FORWARD, id)
		var peak: int = 0
		for i: int in range(0, w.data.size() - 1, 202):
			peak = maxi(peak, absi(w.data.decode_s16(i)))
		assert_between(peak, 400, 32000, id + " is audible and not clipped")
	var rng := RandomNumberGenerator.new()
	for buf: PackedFloat32Array in [FaunaSounds.ice_creak(rng, 0.0), FaunaSounds.heron(rng, 0.0)]:
		var mx: float = 0.0
		for v: float in buf:
			mx = maxf(mx, absf(v))
		assert_between(mx, 0.02, 1.0)


func test_lumi_pets_with_a_reach_and_tilt() -> void:
	var pm := PatchModel.new()
	assert_eq(pm._pet_env(0.1), 0.0, "not petting")
	pm.pet_reach(2.0)
	assert_true(pm.is_petting())
	var e0: float = pm._pet_env(0.05)
	var mid: float = pm._pet_env(0.6)
	assert_lt(e0, mid, "eases in")
	assert_almost_eq(mid, 1.0, 0.001)
	pm._pet_env(1.3)
	assert_lt(pm._pet_env(0.03), 0.5, "eases out at the end")
	pm._pet_env(1.0)
	assert_false(pm.is_petting())
	pm.free()


func test_bird_sounds_are_occasional() -> void:
	var day: float = Fauna.sound_gap("call", 0.0, 0.0)
	assert_gte(day, 20.0, "one bird call every 20 s at most")
	assert_lte(Fauna.sound_gap("call", 0.0, 1.0), 60.0)
	assert_almost_eq(Fauna.sound_gap("call", 1.0, 0.0), day * 2.0, 0.01, "rarer at night")
	assert_gte(Fauna.sound_gap("flutter", 0.0, 0.0), 1.5, "wings never stack up")
	assert_eq(Fauna.sound_gap("meow", 0.0, 0.5), 0.0, "other sounds aren't gated")
	Fauna._call_next_s = -1.0
	assert_true(Fauna.bird_call_ok(), "a call when it's been quiet")
	for k: int in 50:
		assert_false(Fauna.bird_call_ok(), "then silence, however many birds ask")


func test_feeding_brings_the_flock() -> void:
	var w := FakeWorld.new()
	w.field = HexField.new(1, 10.0, 3)
	add_child_autofree(w)
	var fa := Fauna.new()
	fa.world = w
	w.add_child(fa)
	fa.set_process(false)
	var birds: Array = []
	for k: int in 4:
		var b := Fauna.Animal.new()
		b.sp = "pigeon"
		b.kind = "bird"
		b.hex = 0
		b.state = Fauna.St.PECK
		b.pos = Vector3(2.0 + k * 0.5, 0, 1.0)
		b.target = b.pos
		fa.animals.append(b)
		birds.append(b)
	birds[3].state = Fauna.St.PERCH
	birds[3].perch = true
	birds[3].pos.y = 5.0
	var cat := Fauna.Animal.new()
	cat.sp = "cat"
	cat.kind = "cat"
	cat.pos = Vector3(1, 0, 1)
	fa.animals.append(cat)
	assert_eq(fa.feed_candidate(Vector3(1.0, 0, 1.0)), birds[0], "the nearest bird on the ground")
	assert_null(fa.feed_candidate(Vector3(30, 0, 30)), "no birds near")
	var n: int = fa.feed_flock("pigeon", Vector3(1.5, 0, 1.0))
	assert_eq(n, 4)
	for b: Fauna.Animal in birds:
		assert_gt(b.fed_t, 0.0)
		assert_lt(Vector2(b.target.x - 1.5, b.target.z - 1.0).length(), 1.0, "pecking round the crumbs")
	assert_eq(birds[3].state, Fauna.St.FLY, "the one on the lamp post flies down")
	assert_false(birds[3].perch)
	assert_false(fa._scared(birds[0], 5.0), "not shy while eating")
