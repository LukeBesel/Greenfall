extends GutTest
## [orbD] Hub sites on the globe: PlanetEnvs.build_site / SitePrefab, SiteBuilders dispatch,
## SiteManager planet % over hub regions and growth.


class FakeGlobe:
	extends Node3D
	var grid: SphereGrid
	var terrain: SphereTerrain
	var cells: SphereCells
	var field: Variant = null
	var lumi: Node3D = null


func _globe(level: int = 4) -> FakeGlobe:
	var g := FakeGlobe.new()
	g.grid = SphereGrid.for_hex_size(level, 10.0)
	g.terrain = SphereTerrain.new(g.grid, 7)
	g.cells = SphereCells.new(g.grid.cell_count())
	add_child_autofree(g)
	return g


func test_globe_sizes_scale_from_verdance() -> void:
	var v: Dictionary = PlanetEnvs.globe("verdance")
	var a: Dictionary = PlanetEnvs.globe("anvil")
	var o: Dictionary = PlanetEnvs.globe("ochre")
	assert_gt(float(a["radius_m"]), float(v["radius_m"]))
	assert_lt(float(o["radius_m"]), float(v["radius_m"]))
	assert_gt(int(a["hub_count"]), int(v["hub_count"]))


func test_site_for_hub() -> void:
	assert_eq(SiteBuilders.site_for_hub("verdance", 0), "start_yard")
	assert_eq(SiteBuilders.site_for_hub("verdance", 4), "ruin_block")
	assert_eq(SiteBuilders.site_for_hub("anvil", 0), "foundry_yard")
	assert_eq(SiteBuilders.site_for_hub("tidewell", 0), "hub_raft")
	assert_eq(SiteBuilders.site_for_hub("rime", 0), "hub_camp")
	assert_eq(SiteBuilders.site_for_hub("ochre", 0), "hub_base")
	assert_eq(SiteBuilders.site_for_hub("ochre", 5), "hub_base", "only hub bases are hubs")
	assert_eq(SiteBuilders.tide_stage(1), 0)
	assert_eq(SiteBuilders.tide_stage(3), 1)
	assert_eq(SiteBuilders.tide_stage(5), 2)


func test_build_site_has_anchors_collision_and_restyles() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var xf := Transform3D(SphereGrid.frame(Vector3(0.3, 0.8, 0.2).normalized()), Vector3(5, 1800, 3))
	var p: SitePrefab = PlanetEnvs.build_site(root, {"planet": "rime", "prefab": "hub_camp", "transform": xf}, 1, 0.0)
	if not p.is_built:
		await p.rebuilt
	assert_true(p.is_built)
	assert_eq(root.global_transform.origin, xf.origin)
	for a: String in SitePrefab.ANCHORS:
		assert_not_null(p.anchor(a), a)
	assert_gt(p.find_children("*", "CollisionShape3D", true, false).size(), 0)
	# Anchors stay inside the clear core.
	assert_lt(p.anchor_local("rocket_pad").origin.length(), p.clear_core_m + 0.1)
	var content: Node = p.content
	p.set_stage(4)
	p.set_restoration(0.9)
	assert_eq(p.content, content, "Rime re-dresses in place (RimeHubSite.set_state)")


func test_verdance_ruin_block_footprints() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var p: SitePrefab = PlanetEnvs.build_site(root, {"planet": "verdance", "prefab": "ruin_block", "hub_index": 2}, 1, 0.0)
	if not p.is_built:
		await p.rebuilt
	var vs: VerdanceSite = p.content.get_child(0) as VerdanceSite
	assert_not_null(vs)
	assert_gt(vs.footprints().size(), 0)
	# The hub yard (centre block) stays clear.
	for r: Rect2 in vs.footprints():
		assert_false(r.has_point(Vector2.ZERO))
	var ruined: int = 0
	for bd: Dictionary in vs.layout.all_buildings():
		if bool(bd.get("ruined", false)):
			ruined += 1
	assert_gt(ruined, 0)
	# Every building is a kit building; the base level drives broken -> restored in place.
	assert_gt(vs.kits.size(), 0)
	assert_eq(vs.kits[0].state, "broken")
	var content: Node = p.content
	p.set_stage(4)
	assert_eq(p.content, content)
	assert_eq(vs.kits[0].state, "restored")


func test_planet_fraction_counts_built_hub_regions_only() -> void:
	var g := _globe()
	var sites: Array[Dictionary] = []
	for c: int in [0, g.grid.cell_count() / 2]:
		var s: Dictionary = g.terrain.reserve_site(c, 30.0, 10.0)
		assert_false(s.is_empty())
		sites.append(s)
	var sm := SiteManager.new()
	g.add_child(sm)
	sm.setup(g, "verdance", sites)
	sm.set_process(false)
	g.cells.state.fill(0)
	g.cells.junk.fill(1.0)
	assert_almost_eq(sm.planet_fraction(), 0.0, 0.001)
	for c: int in sm.regions[0]:
		g.cells.set_state(c, 1)
		g.cells.set_junk(c, 0.0)
	assert_almost_eq(sm.planet_fraction(), 1.0, 0.001, "only hub 0 is built")
	sm.set_built(1)
	var union: Dictionary = {}
	for k: int in 2:
		for c: int in sm.regions[k]:
			union[c] = true
	assert_almost_eq(sm.planet_fraction(), float(sm.regions[0].size()) / float(union.size()), 0.001)
	# A thriving hub greens cells past its region.
	var n: int = sm.grow(600.0)
	assert_gt(n, 0)
	assert_gt(sm.growth_m[0], 0.0)
	assert_eq(sm.growth_m[1], 0.0)
	var st: Dictionary = sm.save_state()
	sm.growth_m[0] = 0.0
	sm.load_state(st)
	assert_gt(sm.growth_m[0], 0.0)


func test_hop_is_short_and_low() -> void:
	assert_lt(HubHop.duration(1700.0), 10.0, "well under 10 s on screen")
	assert_eq(HubHop.duration(5000.0), HubHop.duration(1700.0), "Anvil's long hops cost the same")
	assert_almost_eq(HubHop.leg_alt(0.0, true), 0.0, 0.01)
	assert_almost_eq(HubHop.leg_alt(1.0, true), HubHop.CRUISE_ALT, 0.01)
	assert_almost_eq(HubHop.leg_alt(1.0, false), 0.0, 0.01)
	assert_lt(HubHop.CRUISE_ALT, 80.0, "the ground stays detailed terrain")


func test_sled_upgrade_registers_once_and_tiers_speed_up() -> void:
	var had: bool = Economy.upgrade_defs.has(HoverSled.UPGRADE_ID)
	var n: int = Economy.upgrade_order.size()
	HoverSled.register_upgrade()
	HoverSled.register_upgrade()
	assert_eq(Economy.upgrade_order.size(), n + (0 if had else 1))
	var saved: Variant = GameState.upgrades.get(HoverSled.UPGRADE_ID)
	GameState.upgrades[HoverSled.UPGRADE_ID] = 2
	assert_eq(HoverSled.owned_tier(), 2)
	if saved == null:
		GameState.upgrades.erase(HoverSled.UPGRADE_ID)
	else:
		GameState.upgrades[HoverSled.UPGRADE_ID] = saved
	assert_gt(float(HoverSled.tune(3)["speed_mult"]), float(HoverSled.tune(1)["speed_mult"]))
	# Cleanup: the flat game's list stays as shipped.
	if not had:
		Economy.upgrade_defs.erase(HoverSled.UPGRADE_ID)
		Economy.upgrade_order.erase(HoverSled.UPGRADE_ID)
		Economy._index_upgrades()


func test_sled_mount_retunes_motor_and_restores() -> void:
	var m := SphereMotor.new()
	var p := Patch.new()
	p.sphere_motor = m
	add_child_autofree(p)
	var s := HoverSled.new()
	s.lumi = p
	add_child_autofree(s)
	s.mount()
	assert_true(s.mounted)
	assert_gt(m.speed_mult, 2.0)
	assert_lt(m.accel, 16.0, "heavier inertia")
	assert_eq(s.get_parent(), p)
	s.dismount()
	assert_false(s.mounted)
	assert_eq(m.speed_mult, 1.0)
	assert_eq(m.accel, 16.0)
	assert_ne(s.get_parent(), p)


func test_boost_is_rebindable_without_conflicts() -> void:
	var names: Array = Settings.REBINDABLE.map(func(e: Array) -> String: return e[0])
	assert_true(names.has("boost"))
	assert_eq(Settings.conflicts(), {})
	assert_eq(Settings.event_label(Settings.binding("boost", false)), "Shift")


func test_pad_view_short_press_opens_map_long_press_toggles_goals() -> void:
	var h := PadHold.new()
	add_child_autofree(h)
	var got: Array[String] = []
	h.sent.connect(func(a: String) -> void: got.append(a))
	var down := InputEventJoypadButton.new()
	down.button_index = JOY_BUTTON_BACK
	down.pressed = true
	var up := InputEventJoypadButton.new()
	up.button_index = JOY_BUTTON_BACK
	up.pressed = false
	assert_true(PadHold.is_hold_button(down), "View is bound to the map")
	h._input(down)
	h._process(0.2)
	h._input(up)
	assert_eq(got, ["open_globe"] as Array[String])
	got.clear()
	h._input(down)
	h._process(0.3)
	h._process(0.3)
	h._input(up)
	assert_eq(got, ["toggle_goals"] as Array[String], "a long press only toggles the goals")


func test_start_yard_anchors_spaced_and_lane_open() -> void:
	var a: Dictionary = VerdanceSite.START_YARD_ANCHORS
	for k: String in ["pod", "bin", "shack", "generator", "composter", "radio", "locker", "nursery", "camera_bot", "signal_tower", "telescope", "stations", "lamps_0"]:
		assert_true(a.has(k), k)
	var inter: Array[String] = ["depot", "bench", "bin", "stations", "radio", "signal_tower", "telescope", "generator", "composter", "locker", "camera_bot", "nursery", "pod"]
	var all: Dictionary = {"depot": [Vector3(8.0, 0, 7.5)], "bench": [Vector3(-8.0, 0, 7.5)]}
	all.merge(a)
	for i: int in inter.size():
		var p: Vector3 = all[inter[i]][0]
		if inter[i] != "pod":
			assert_gt(absf(p.x), 2.5, inter[i] + " keeps the north lane open")
		for j: int in range(i + 1, inter.size()):
			assert_gt(p.distance_to(all[inter[j]][0]), 2.99, "%s / %s at least 3 m apart" % [inter[i], inter[j]])


func test_autowalk_detours_with_longer_sidesteps() -> void:
	var b := CharacterBody3D.new()
	add_child_autofree(b)
	b.global_position = Vector3(0, 1840, 0)
	var inp := SphereAutoInput.new(Vector3(0, 0, -1))
	inp.body = b
	b.velocity = Vector3(1.2, 0, 0)  # pressing into a mound: jitters but gets nowhere
	for k: int in 25:
		inp.update(0.1)
	assert_gt(absf(inp.get_world_move(0.0).x), 0.5, "stalled: sidestepping")
	var first: float = inp._side_dur
	for k: int in 25:
		inp.update(0.1)  # still blocked sideways: the other way, longer
	assert_gt(inp._side_dur, first)
	for k: int in 200:  # moving freely again
		b.global_position += Vector3(0.3, 0, 0)
		inp.update(0.1)
	assert_eq(inp._phase, 0, "back on its heading")
	assert_almost_eq(inp.get_world_move(0.0), Vector3(0, 0, -1), Vector3.ONE * 0.001)


func test_probe_clears_junk_inside_any_planets_buildings() -> void:
	var g := _globe(6)
	g.cells.state.fill(0)
	g.cells.junk.fill(1.0)
	var c0: int = 123
	var s: Dictionary = g.terrain.reserve_site(c0, 55.0, 20.0)
	assert_false(s.is_empty())
	var sites: Array[Dictionary] = [s]
	var sm := SiteManager.new()
	g.add_child(sm)
	sm.setup(g, "ochre", sites)
	sm.set_process(false)
	var p: SitePrefab = sm.build_hub(0)
	if not p.is_built:
		await p.rebuilt
	for k: int in 3:
		await get_tree().physics_frame
	sm.probe_cells(0, p)
	var clean: int = 0
	for c: int in s["cells"]:
		if not g.cells.is_dirty(c):
			clean += 1
	assert_gt(clean, 0, "cells under Ochre's hub buildings go clean")
	assert_lt(clean, s["cells"].size(), "open ground keeps its junk")
