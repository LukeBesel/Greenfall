extends GutTest
## [art5] The shuttle's look (art/models/shuttle, automation/ship_model.gd, art/shuttle_fx.gd):
## what other code and the Locker rely on. Every part a tier asks for is in the GLB with its
## moving pieces, every surface gets a runtime material (so paint, trim and glow stay editable),
## the gear carries weight, the engines' metal stays hot after they stop, and the ground effects
## lie on the pad's local up and die away.


func _ship(t: int) -> ShipModel:
	var m := ShipModel.new()
	add_child_autofree(m)
	m.build(t)
	return m


func test_every_surface_has_a_runtime_material() -> void:
	for t: int in range(1, ShipTiers.MAX_LOOK + 1):
		var m: ShipModel = _ship(t)
		for n: Node in m.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = n
			if mi.material_override != null or mi.mesh == null:
				continue
			for i: int in mi.mesh.get_surface_count():
				assert_not_null(mi.get_surface_override_material(i), "Mk %d %s surface %d (%s) is mapped" % [t, mi.name, i,
					mi.mesh.surface_get_material(i).resource_name if mi.mesh.surface_get_material(i) else "?"])


func test_locker_colours_reach_the_hull() -> void:
	var m: ShipModel = _ship(1)
	var hull: MeshInstance3D = m.find_child("hull_rear", true, false)
	var seen: Dictionary = {}
	for i: int in hull.mesh.get_surface_count():
		seen[hull.mesh.surface_get_material(i).resource_name] = hull.get_surface_override_material(i)
	for slot: String in ["paint", "accent", "tile", "steel", "glass", "decal"]:
		assert_true(seen.has(slot), "the hull keeps its %s slot" % slot)
	assert_eq((seen["paint"] as ShaderMaterial).get_shader_parameter("paint_color"), ShipStyle.paint_color())
	assert_eq((seen["accent"] as ShaderMaterial).get_shader_parameter("paint_color"), ShipStyle.trim_color())


func test_moving_pieces() -> void:
	var m: ShipModel = _ship(1)
	for nm: String in ["skid_l_foot", "skid_r_foot", "eng_a_bell_0", "eng_a_bell_1", "rotor"]:
		assert_not_null(m.find_child(nm, true, false), "Mk I has %s" % nm)
	var m4: ShipModel = _ship(4)
	for nm: String in ["gear_n_foot", "gear_l_foot", "gear_r_foot", "eng_b_bell_0"]:
		assert_not_null(m4.find_child(nm, true, false), "Mk IV has %s" % nm)
	m.set_legs(0.0)
	var l: Node3D = m.find_child("skid_l", true, false).get_parent()
	var r: Node3D = m.find_child("skid_r", true, false).get_parent()
	assert_gt(absf(l.rotation.z), 1.0, "the Mk I legs fold")
	assert_almost_eq(l.rotation.z, -r.rotation.z, 0.001, "left and right fold as mirrors")


func test_gear_carries_weight() -> void:
	var m: ShipModel = _ship(1)
	var hull: Node3D = m.find_child("hull_rear", true, false)
	var foot: Node3D = m.find_child("skid_l_foot", true, false)
	var y0: float = hull.position.y
	assert_almost_eq(m.squat(), ShipModel.SQUAT_REST, 0.001, "standing, the legs are pressed in")
	var foot_y: float = foot.global_position.y
	m.set_airborne(true)
	for i: int in 60:
		m._process(1.0 / 60.0)
	assert_lt(m.squat(), 0.0, "in the air the legs hang")
	assert_gt(hull.position.y, y0, "the hull rides higher on the unloaded gear")
	m.set_airborne(false, 1.0)
	var deepest: float = 0.0
	for i: int in 240:
		m._process(1.0 / 60.0)
		deepest = maxf(deepest, m.squat())
	assert_gt(deepest, ShipModel.SQUAT_REST + 0.015, "touchdown presses the gear past its rest")
	assert_almost_eq(m.squat(), ShipModel.SQUAT_REST, 0.004, "and it settles")
	assert_almost_eq(foot.global_position.y, foot_y, 0.004, "the feet end where they stood (no sliding into the pad)")


func test_engines_heat_and_cool() -> void:
	var m: ShipModel = _ship(1)
	assert_almost_eq(m.heat, 0.0, 0.001)
	m.set_lift(1.0)
	for i: int in 20:
		m._process(1.0 / 60.0)
	assert_gt(m.heat, 0.9, "the metal is hot within a third of a second")
	m.set_lift(0.0)
	for i: int in 60:
		m._process(1.0 / 60.0)
	assert_gt(m.heat, 0.6, "a second after shutdown the bells still glow")
	for i: int in 600:
		m._process(1.0 / 60.0)
	assert_almost_eq(m.heat, 0.0, 0.001, "and they are cold ten seconds later")


func test_display_ship_has_no_ground_lamp() -> void:
	var d: ShipModel = ShipModel.for_display(1)
	add_child_autofree(d)
	assert_null(d.get_node_or_null("BellyLamp"), "the map's ship lights nothing")
	assert_not_null(_ship(1).get_node_or_null("BellyLamp"))


func test_ground_effects_follow_the_local_up() -> void:
	var fx := ShuttleFx.new()
	add_child_autofree(fx)
	# A pad on the side of the globe: up is +X there, not world Y.
	var up := Vector3(1, 0, 0)
	var pad := Vector3(900, 0, 0)
	fx.fly(pad + up * 2.0, pad, up, 2.0, 1.0)
	assert_gt(fx.strength(), 0.5, "low over the pad the skirt blows")
	var dust: CPUParticles3D = fx._dust
	assert_almost_eq(dust.global_basis.y.dot(up), 1.0, 0.001, "the skirt's plane is the pad's, not world XZ")
	assert_almost_eq(dust.gravity.normalized().dot(up), 1.0, 0.001, "dust drifts along the local up")
	assert_almost_eq(fx._grit.gravity.normalized().dot(up), -1.0, 0.001, "grit falls toward the planet")
	assert_gt((fx._light.global_position - pad).dot(up), 0.5, "the lamp is above the ground, not under it")
	fx.fly(pad + up * 40.0, pad, up, 40.0, 1.0)
	assert_eq(fx.strength(), 0.0, "high up nothing blows")
	assert_false(dust.emitting)


func test_scorch_stays_a_while_then_goes() -> void:
	var fx := ShuttleFx.new()
	add_child_autofree(fx)
	var up := Vector3(0, 0, 1)
	var xf := Transform3D(ShuttleFx._frame(up), up * 900.0)
	fx.mark(xf, 1.0)
	assert_almost_eq(fx.scorch_left(0), 1.0, 0.01)
	assert_almost_eq(fx._scorch[0].global_basis.y.dot(up), 1.0, 0.001, "the scorch lies on the pad")
	fx.mark(xf, 1.0)
	assert_eq(fx.scorch_left(1), 0.0, "the same pad keeps one mark")
	fx._process(ShuttleFx.SCORCH_S * 0.5)
	assert_gt(fx.scorch_left(0), 0.3, "half way through it still shows")
	fx._process(ShuttleFx.SCORCH_S * 0.6)
	assert_eq(fx.scorch_left(0), 0.0)
	assert_false(fx.is_processing(), "nothing left to animate: the node sleeps")
