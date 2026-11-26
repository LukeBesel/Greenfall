extends GutTest
## [art4] The start yard's quay (planet/sites/outpost_pad.gd) and the aged yard models
## (systems/camp/yard_art.gd): the names, sizes and switches other code relies on.


func test_pad_keeps_its_node_names_and_has_no_collider() -> void:
	var pad: Node3D = VerdanceSite.clean_pad(21.0)
	add_child_autofree(pad)
	assert_eq(str(pad.name), "YardPad")
	var mi: MeshInstance3D = pad.get_node_or_null("CleanPad") as MeshInstance3D
	assert_not_null(mi, "YardPad > CleanPad")
	assert_true(mi.has_meta("no_collide"), "the pad is drawn, not walked on: the site's own ground carries Lumi")
	assert_eq(pad.find_children("*", "CollisionShape3D", true, false).size(), 0)
	assert_not_null(mi.mesh, "the mesh from art/models/outpost/outpost_pad.glb")
	assert_eq(mi.mesh.get_surface_count(), 2, "two draw calls: the deck and the light lenses")
	assert_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "no shadow pass for a flat quay")


func test_pad_is_the_size_and_height_the_yard_was_built_round() -> void:
	var ab: AABB = OutpostPad.mesh().get_aabb()
	assert_almost_eq(ab.size.x, 21.0, 0.3, "21 m across (the junk starts 0.3 m off its edge)")
	assert_almost_eq(ab.size.z, 21.0, 0.3)
	assert_almost_eq(ab.get_center().x, 0.0, 0.1)
	assert_lt(ab.end.y, 0.2, "kerb and all under 20 cm: nothing to trip a bale or a robot")


func test_pad_lights_are_dark_until_powered() -> void:
	var pad: Node3D = OutpostPad.build()
	add_child_autofree(pad)
	var mi: MeshInstance3D = pad.get_node("CleanPad")
	var lens: int = -1
	for s: int in mi.mesh.get_surface_count():
		if mi.get_surface_override_material(s) is StandardMaterial3D:
			lens = s
	assert_gt(lens, -1, "a lens surface")
	assert_false((mi.get_surface_override_material(lens) as StandardMaterial3D).emission_enabled, "nothing is lit when you land")
	OutpostPad.set_powered(get_tree(), true)
	assert_true((mi.get_surface_override_material(lens) as StandardMaterial3D).emission_enabled, "lit once the yard has power")
	OutpostPad.set_powered(get_tree(), false)
	assert_false((mi.get_surface_override_material(lens) as StandardMaterial3D).emission_enabled)


func test_bench_keeps_the_parts_camp_moves() -> void:
	var bench := Node3D.new()
	add_child_autofree(bench)
	var body := MeshInstance3D.new()
	bench.add_child(body)
	YardArt.dress_bench(bench)
	for nm: String in ["Upper", "Drawer", "Scraps"]:
		assert_not_null(body.get_node_or_null(nm), "bench part " + nm)
	var ab: AABB = body.mesh.get_aabb()
	assert_almost_eq(ab.size.x, 2.4, 0.25, "the bench is as wide as its collider and E spot expect")
	assert_lt(ab.end.z, 0.75, "nothing sticks far out of the front (the E spot is there)")
	YardArt.bench_state(bench, false, false)
	assert_true((body.get_node("Scraps") as Node3D).visible, "broken: scraps on the floor")
	assert_eq(str(body.get_meta("kit_state")), "broken")
	YardArt.bench_state(bench, true, false)
	assert_false((body.get_node("Scraps") as Node3D).visible)
	assert_eq(str(body.get_meta("kit_state")), "repaired", "a fixed bench is a used bench, not a new one")
	assert_true(bool(body.get_meta("kit_powered")))


func test_bin_levels_keep_their_sizes_and_mouths() -> void:
	var want: Dictionary = {1: [Vector3(0.96, 1.25, 1.02), 1.43], 2: [Vector3(2.6, 1.45, 1.6), 1.65], 4: [Vector3(2.6, 2.8, 1.6), 1.65]}
	for l: int in want:
		var b: Dictionary = YardArt.bin_body(l)
		assert_almost_eq((b["size"] as Vector3).x, (want[l][0] as Vector3).x, 0.001, "bin L%d width" % l)
		assert_almost_eq((b["size"] as Vector3).y, (want[l][0] as Vector3).y, 0.001, "bin L%d height" % l)
		assert_almost_eq((b["size"] as Vector3).z, (want[l][0] as Vector3).z, 0.001, "bin L%d depth" % l)
		assert_almost_eq(float(b["mouth_y"]), float(want[l][1]), 0.001, "bin L%d mouth" % l)
		assert_eq(b["ram"] != null, l >= 4, "the ram comes with the compactor")
		(b["root"] as Node).free()


func test_lamp_head_and_wear_states() -> void:
	assert_almost_eq(YardArt.LAMP_HEAD_Y, 3.62, 0.001, "the yard lights hang under this height")
	var lamp: MeshInstance3D = YardArt.street_lamp().mi(0.15)
	add_child_autofree(lamp)
	assert_almost_eq(lamp.mesh.get_aabb().end.y, YardArt.LAMP_HEAD_Y + 0.37, 0.15)
	assert_eq(YardArt.state_for(0.72), "broken")
	assert_eq(YardArt.state_for(0.15), "repaired", "working yard machines are used, not showroom-new")
	assert_eq(YardArt.state_for(0.05), "restored")
