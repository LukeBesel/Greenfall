extends GutTest
## [ship] Lumi's ship (automation/ship_model.gd, automation/ship_tiers.gd, automation/launch_pad.gd):
## the look follows RocketTiers (Mk I-IV) and Homeward's drive (Mk V-VII); each look keeps the base
## and adds parts; the ship and its pad grow; the model builds every look with engines and a canopy.


func test_look_mapping() -> void:
	assert_eq(ShipTiers.look_for(1, 0), 1)
	assert_eq(ShipTiers.look_for(4, 0), 4)
	assert_eq(ShipTiers.look_for(2, 5), 5, "the drive tier wins once built")
	assert_eq(ShipTiers.look_for(4, 7), 7)
	assert_eq(ShipTiers.look_for(9, 0), 4, "in-planet tiers cap at Mk IV")


func test_parts_grow_on_one_base() -> void:
	var prev: int = 0
	for t: int in range(1, ShipTiers.MAX_LOOK + 1):
		var p: PackedStringArray = ShipTiers.parts_for(t)
		for base: String in ["hull_rear", "hull_front", "wing"]:
			assert_true(base in p, "Mk %d keeps %s" % [t, base])
		assert_true(p.size() >= prev, "Mk %d has at least as many parts" % t)
		prev = p.size()
	assert_true("wing_ext" in ShipTiers.parts_for(2))
	assert_true("eng_b" in ShipTiers.parts_for(3) and not ("eng_a" in ShipTiers.parts_for(3)), "better engines replace the first pair")
	assert_true("gear_n" in ShipTiers.parts_for(4) and "pods" in ShipTiers.parts_for(4))
	assert_true("hull_mid" in ShipTiers.parts_for(5) and "eng_c" in ShipTiers.parts_for(5))
	assert_true("ring" in ShipTiers.parts_for(6) and "wing_big" in ShipTiers.parts_for(6))
	assert_true("vault" in ShipTiers.parts_for(7))


func test_ship_and_pad_grow() -> void:
	for t: int in range(2, ShipTiers.MAX_LOOK + 1):
		assert_true(ShipTiers.scale_of(t) >= ShipTiers.scale_of(t - 1))
		assert_true(ShipTiers.pad_scale(t) >= ShipTiers.pad_scale(t - 1))
		var a: Vector2 = ShipModel.extent(t - 1)
		var b: Vector2 = ShipModel.extent(t)
		assert_true(b.x >= a.x and b.y >= a.y, "Mk %d is at least as big" % t)
	assert_gt(ShipModel.front_shift(5), 0.0, "Mk V lengthens the hull")
	assert_eq(ShipModel.front_shift(4), 0.0)


func test_model_builds_every_look() -> void:
	for t: int in range(1, ShipTiers.MAX_LOOK + 1):
		var m := ShipModel.new()
		add_child_autofree(m)
		m.build(t)
		assert_not_null(m.plume, "Mk %d has a main plume" % t)
		assert_not_null(m.hatch, "Mk %d has a canopy" % t)
		var parts: int = 0
		for name: String in ShipTiers.parts_for(t):
			if m.find_child(name, true, false) != null:
				parts += 1
		assert_eq(parts, ShipTiers.parts_for(t).size(), "Mk %d: every part is in the GLB" % t)
	var big := ShipModel.new()
	add_child_autofree(big)
	big.build(7)
	assert_gt(big.find_children("*", "RocketPlume", true, false).size(), 8, "Mk VII has many engines")


func test_canopy_and_gear_animate() -> void:
	var m := ShipModel.new()
	add_child_autofree(m)
	m.build(4)
	m.set_canopy(1.0)
	assert_lt(m.hatch.rotation.x, -0.5, "canopy opens up")
	m.set_canopy(0.0)
	assert_almost_eq(m.hatch.rotation.x, 0.0, 0.001)
	m.set_legs(0.0)
	var leg: Node3D = m.find_child("gear_n", true, false).get_parent()
	assert_gt(leg.rotation.x, 1.0, "gear folds")


func test_legacy_rocket_model_is_the_ship() -> void:
	var r := RocketModel.new()
	add_child_autofree(r)
	r.build(4)
	assert_true(r is ShipModel)
	assert_not_null(r.plume)


func test_pad_grows_with_the_ship() -> void:
	var a := LaunchPad.new()
	a.look = 1
	add_child_autofree(a)
	var b := LaunchPad.new()
	b.look = 7
	add_child_autofree(b)
	assert_gt(b.radius(), a.radius())
	var span7: float = ShipModel.extent(7).y * ShipTiers.scale_of(7)
	assert_gt(b.radius(), span7 * 0.75, "the Mk VII mostly fits its pad")
	a.set_clamps(1.0)
	a.set_gangway(0.0)
	assert_true(a.gangway.visible)


func test_ark_keeps_its_api() -> void:
	var ark := CradleShip.new()
	add_child_autofree(ark)
	assert_gt(ark.get_child_count(), 8, "the ark is built from ark.glb parts")
	assert_eq(ark.find_children("*", "", false, false).filter(func(n: Node) -> bool: return n.name.begins_with("ark_")).size(), 8)
	var p: Vector3 = ark.pod_world(2)
	assert_almost_eq(p.y, CradleShip.POD_Y, 0.01)
	assert_true(ark.pod_xform(2).origin.distance_to(p) < 2.0, "the rack pod hangs where pod_world says")
	ark.release_pod(2)
	ark.release_pod(2, false)
	assert_gt(ark.wake_points().size(), 10)
	assert_gt(ark.dome_world().y, 5.0)
