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
	assert_eq(SiteBuilders.tide_stage(1), 0)
	assert_eq(SiteBuilders.tide_stage(3), 1)
	assert_eq(SiteBuilders.tide_stage(5), 2)


func test_build_site_has_anchors_collision_and_restyles() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var xf := Transform3D(SphereGrid.frame(Vector3(0.3, 0.8, 0.2).normalized()), Vector3(5, 1800, 3))
	var p: SitePrefab = PlanetEnvs.build_site(root, {"planet": "rime", "prefab": "crater_camp", "transform": xf}, 1, 0.0)
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
	assert_eq(p.content, content, "Rime re-dresses in place")
	var rs: RimeSite = content.get_child(0) as RimeSite
	assert_eq(rs.level, 4)


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
