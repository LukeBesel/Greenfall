extends GutTest
## [sysmap] The solar-system map's layout (ui/system_map.gd): orbit lanes in AU order with room
## for each planet's rings, and a zoom framing that makes the selected globe large on screen.
## [sysmap2] Discovery and unlock order (systems/homeward.gd) and the clean view: no 3D text, only
## discovered planets shown, the orrery framed clear of the info panel.

var _profile: Dictionary
var _flags: Dictionary


func before_each() -> void:
	_profile = CradleMode.profile.duplicate(true)
	_flags = GameState.flags.duplicate(true)
	CradleMode.persist = false
	CradleMode.profile = CradleMode.default_profile()


func after_each() -> void:
	CradleMode.profile = _profile
	GameState.flags = _flags


func _set_pct(vals: Dictionary) -> void:
	for id: String in vals:
		(Homeward.state()["pct"] as Dictionary)[id] = float(vals[id])


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


# --- [sysmap2] Discovery and unlock order -------------------------------------------------------

func test_start_of_game_only_verdance_is_known() -> void:
	assert_true(Homeward.discovered(0))
	for k: int in range(1, Homeward.planets().size()):
		assert_false(Homeward.discovered(k), "%s hidden at the start" % Homeward.planet_def(k)["id"])
	assert_eq(Homeward.discovered_count(), 1)


func test_planets_are_discovered_strictly_in_campaign_order() -> void:
	var at: float = float(Homeward.cfg().get("discover_at", 0.25))
	_set_pct({"verdance": at})
	assert_true(Homeward.discovered(1), "Ochre shows once Verdance reaches discover_at")
	assert_false(Homeward.discovered(2))
	# A later planet's predecessor alone is not enough: the chain must be unbroken.
	assert_false(Homeward.discovered_of(3, [0.0, 0.0, 1.0, 0.0, 0.0], [], []), "Rime needs Ochre and Tidewell first")
	assert_true(Homeward.discovered_of(3, [1.0, 1.0, 1.0, 0.0, 0.0], [], []))
	assert_false(Homeward.discovered_of(4, [1.0, 1.0, 1.0, at - 0.01, 0.0], [], []))
	assert_true(Homeward.discovered_of(4, [1.0, 1.0, 1.0, at, 0.0], [], []))


func test_discovered_is_not_unlocked_until_chart_and_drive() -> void:
	_set_pct({"verdance": 0.3})
	assert_true(Homeward.discovered(1))
	assert_false(Homeward.unlocked(1), "no chart and no drive yet")
	_set_pct({"verdance": 0.6})
	assert_false(Homeward.unlocked(1), "charted, but the Mk V drive is missing")
	Homeward.state()["drive"] = 5
	assert_true(Homeward.unlocked(1))
	assert_false(Homeward.unlocked(2), "Tidewell is not even discovered")
	assert_ne(SystemMap.launch_blocker(null, 2), "")


func test_telescope_spots_only_the_next_planet() -> void:
	assert_false(Homeward.spot(2), "can't skip ahead")
	assert_true(Homeward.spot(1))
	assert_true(Homeward.discovered(1))
	assert_false(Homeward.spot(1), "already known")
	assert_true(Homeward.spot(2))
	assert_eq(Homeward.discovered_count(), 3)
	assert_eq(Homeward.sanitize(Homeward.state())["seen"], ["ochre", "tidewell"], "seen survives a load")


# --- [sysmap2] Clean view ------------------------------------------------------------------------

func _labels_under(n: Node) -> int:
	var c: int = 1 if n is Label3D else 0
	for ch: Node in n.get_children():
		c += _labels_under(ch)
	return c


func test_map_has_no_3d_text_and_shows_only_discovered_planets() -> void:
	_set_pct({"verdance": 1.0, "ochre": 0.3})
	var m := SystemMap.new()
	add_child_autofree(m)
	m.open_map()
	assert_eq(_labels_under(m._vp), 0, "no Label3D in the orrery")
	var shown: int = 0
	for k: int in m._planets.size():
		if m._planets[k].visible:
			shown += 1
			assert_true(Homeward.discovered(k))
		assert_eq(m._orbits[k].visible, m._planets[k].visible, "orbit lines only for known planets")
	assert_eq(shown, 3, "Verdance, Ochre and Tidewell")
	m._cycle(1)
	assert_true(Homeward.discovered(m.selected), "cycling skips hidden planets")
	m._select(4, true)
	assert_ne(m.selected, 4, "hidden planets can't be selected")
	m.close_map()
	assert_false(get_tree().paused)


func test_overview_fits_left_of_the_panel() -> void:
	_set_pct({"verdance": 1.0, "ochre": 1.0, "tidewell": 1.0, "rime": 1.0})
	var m := SystemMap.new()
	add_child_autofree(m)
	m.open_map()
	var known: Array[int] = [0, 1, 2, 3, 4]
	var fr: Rect2 = m.free_rect()
	var bx: Rect2 = m._overview_box(m._ov_xf, known)
	var t: float = tan(deg_to_rad(SystemMap.FOV) * 0.5)
	var shift: Vector2 = m._ov_off / (SystemMap.NEAR * t)
	var on_screen := Rect2(bx.position - shift, bx.size)
	assert_true(fr.grow(0.01).encloses(on_screen), "every orbit stays in the free area: %s in %s" % [on_screen, fr])
	m.close_map()
