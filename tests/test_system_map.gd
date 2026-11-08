extends GutTest
## [sysmap] The solar-system map's layout (ui/system_map.gd): orbit lanes in AU order with room
## for each planet's rings, and a zoom framing that makes the selected globe large on screen.


func _map() -> SystemMap:
	var m := SystemMap.new()
	autofree(m)
	m._layout_orbits()
	return m


func test_orbits_follow_au_and_leave_ring_room() -> void:
	var m := _map()
	var n: int = Homeward.planets().size()
	assert_eq(m._orbit_rs.size(), n)
	var order: Array[int] = []
	for k: int in n:
		order.append(k)
	order.sort_custom(func(a: int, b: int) -> bool: return SolarSystem.orbit_au(m._pid_of(a)) < SolarSystem.orbit_au(m._pid_of(b)))
	assert_gt(m._orbit_rs[order[0]] - m._reach(order[0]), SystemMap.SUN_ZONE - 0.001, "first lane clears the suns")
	for i: int in range(1, order.size()):
		var a: int = order[i - 1]
		var b: int = order[i]
		assert_gt(m._orbit_rs[b] - m._orbit_rs[a], maxf(m._reach(a) + m._globe_r(b), m._reach(b) + m._globe_r(a)), "%s and %s: no ring reaches the other globe" % [m._pid_of(a), m._pid_of(b)])


func test_ringed_planets_reach_past_twice_their_radius() -> void:
	var m := _map()
	for k: int in Homeward.planets().size():
		if SystemMap.RING_REACH.has(m._pid_of(k)):
			assert_gt(m._ring_out(k), m._globe_r(k) * 2.1)


func test_zoom_fills_the_screen() -> void:
	var m := _map()
	var t: float = tan(deg_to_rad(42.0) * 0.5)
	for k: int in Homeward.planets().size():
		var eye: float = m._zoom_dist(k) * 1.52
		var globe_share: float = m._globe_r(k) / (eye * t)  # of the screen height
		var ring_share: float = m._ring_out(k) / (eye * t)
		assert_gt(globe_share, 0.3, "%s globe is big when zoomed" % m._pid_of(k))
		assert_lt(ring_share, 0.81, "%s rings stay on screen" % m._pid_of(k))
