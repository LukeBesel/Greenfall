extends GutTest
## [orbC] Phase C: robots on the round planet (robots/sphere/), far crews, per-hub offline maths
## (core/sphere_offline.gd, shared with core/offline.gd) and Command-view picking.

var _g5: SphereGrid
var _t5: SphereTerrain


func before_all() -> void:
	_g5 = SphereGrid.new()
	_g5.generate(5)
	_g5.radius_m = SphereGrid.radius_for(5, 10.0)
	_t5 = SphereTerrain.new(_g5, 7)


func _world(junk: bool = true) -> Dictionary:
	var cells := SphereCells.new(_g5.cell_count())
	if not junk:
		cells.junk.fill(0.0)
		cells.state.fill(1)
		cells.refresh_all()
	var surface := SphereSurface.new(_g5.radius_m)
	surface.height_fn = _t5.height
	surface.cell_fn = func(p: Vector3, _h: int) -> int: return _g5.cell_at(p)
	surface.center_fn = func(c: int) -> Vector3: return _g5.centers[c]
	var crew := SphereCrew.new()
	crew.visuals = false
	add_child_autofree(crew)
	crew.setup(_g5, cells, null, surface, SphereSwarm.new(surface))
	crew.hub_cell = 100
	crew.depot_cell = 100
	var lumi := Node3D.new()
	add_child_autofree(lumi)
	lumi.global_position = surface.ground(_g5.centers[100])
	crew.focus = lumi
	return {"cells": cells, "surface": surface, "crew": crew, "lumi": lumi}


func _run(crew: SphereCrew, seconds: float, dt: float = 0.1) -> void:
	var n: int = int(seconds / dt)
	for i: int in n:
		for u: Dictionary in crew.robots():
			if u["bot"] != null:
				(u["bot"] as SphereBot).step(dt)
		crew.tick(dt)


# --- Movement profiles ----------------------------------------------------------------------

func test_every_type_moves_like_its_profile() -> void:
	var w: Dictionary = _world()
	var crew: SphereCrew = w["crew"]
	for t: String in ["scoopie", "haulbug", "seedling", "drip", "skimmer", "multibot"]:
		var u: Dictionary = crew.spawn(t, 0, _g5.cells_around(100, 1)[1])
		var b: SphereBot = u["bot"]
		assert_not_null(b, "%s spawns near Lumi as a real SphereBot" % t)
		assert_almost_eq(b.speed, Economy.robot_stat(t, "speed", 0), 0.001, "%s keeps the flat game's speed" % t)
		assert_eq(b.turn_rate, float(SphereRobotKinds.profile(t)["turn"]))
	var hb: float = float(SphereRobotKinds.profile("haulbug")["turn"])
	assert_lt(hb, float(SphereRobotKinds.profile("scoopie")["turn"]), "the wheeled hauler turns wider")


func test_bot_reaches_a_cell_on_the_graph() -> void:
	var w: Dictionary = _world()
	var crew: SphereCrew = w["crew"]
	var u: Dictionary = crew.spawn("haulbug", 0, 100)
	var to: int = _g5.cells_around(100, 3)[30]
	var p: PackedInt32Array = crew.route(100, to)
	assert_gt(p.size(), 2)
	assert_eq(p[0], 100)
	assert_eq(p[p.size() - 1], to)
	crew._go(u, p)
	u["mode"] = "go"
	_run(crew, 40.0)
	assert_lt(crew.unit_dir(u).angle_to(_g5.centers[to]) * _g5.radius_m, SphereCrew.ARRIVE_M, "arrived at the cell")


func test_astar_grid_avoids_water() -> void:
	var w: Dictionary = _world()
	var cells: SphereCells = w["cells"]
	var crew: SphereCrew = w["crew"]
	var ring: PackedInt32Array = _g5.cells_around(200, 1)
	for i: int in range(1, ring.size()):
		cells.set_state(ring[i], 5)  # a lake round cell 200 (except the goal)
	var to: int = ring[1]
	cells.set_state(to, 0)
	var p: PackedInt32Array = crew.route(_g5.cells_around(200, 3)[25], to)
	assert_gt(p.size(), 0)
	for i: int in range(0, p.size() - 1):
		assert_ne(cells.state[p[i]], 5, "no wading through the lake")


# --- Jobs by cell id ----------------------------------------------------------------------

func test_scoopies_clean_cells_and_haulbug_cashes() -> void:
	var w: Dictionary = _world()
	var crew: SphereCrew = w["crew"]
	var cells: SphereCells = w["cells"]
	var c0: float = GameState.get_currency("cubes").to_float()
	for i: int in 3:
		crew.spawn("scoopie", 0, _g5.cells_around(100, 1)[i + 1])
	crew.spawn("haulbug", 0, 100)
	var dirty0: int = 0
	for c: int in _g5.cells_around(100, crew.rings):
		dirty0 += 1 if cells.is_dirty(c) else 0
	_run(crew, 600.0, 0.2)
	assert_gt(crew.cells_cleaned(), 3, "three Scoopies clean a few hexes in 10 min")
	assert_gt(crew.cashed, 0.0, "the Haul Bug brought bales to the depot")
	assert_gt(GameState.get_currency("cubes").to_float(), c0)
	assert_eq(crew.stuck_count(), 0, "no stuck robots")
	for u: Dictionary in crew.robots():
		assert_true(u["bot"] != null, "all near Lumi stay real")


func test_claims_are_exclusive_and_respect_zones() -> void:
	var w: Dictionary = _world()
	var crew: SphereCrew = w["crew"]
	var a: int = crew.claim_dirty(100, 100, -1, "clean", "a")
	var b: int = crew.claim_dirty(100, 100, -1, "clean", "b")
	assert_ne(a, b)
	crew.release(a)
	var zc: int = _g5.cells_around(100, 2)[15]
	crew.set_zone_cell("clean", zc, true)
	assert_eq(crew.claim_dirty(100, 100, -1, "clean", "c"), zc, "a painted zone is worked first and only")
	assert_eq(crew.claim_dirty(100, 100, -1, "clean", "d"), -1)


func test_order_sends_a_robot_to_a_cell() -> void:
	var w: Dictionary = _world()
	var crew: SphereCrew = w["crew"]
	var u: Dictionary = crew.spawn("scoopie", 0, 100)
	var target: int = _g5.cells_around(100, 2)[12]
	crew.order(u, target)
	assert_eq(int(u["job"]), target)
	_run(crew, 25.0)
	assert_eq(str(u["mode"]), "work")


func test_seedling_plants_and_drip_waters() -> void:
	var w: Dictionary = _world(false)
	var crew: SphereCrew = w["crew"]
	var cells: SphereCells = w["cells"]
	crew.spend_seeds = false
	crew.spawn("seedling", 0, 100)
	crew.spawn("drip", 0, _g5.cells_around(100, 1)[2])
	_run(crew, 60.0, 0.2)
	var planted: int = 0
	var growing: int = 0
	for c: int in _g5.cells_around(100, 3):
		planted += 1 if cells.state[c] >= 2 else 0
		growing += 1 if cells.state[c] == 3 else 0
	assert_gt(planted, 0)
	assert_gt(growing, 0)


# --- Far crews ------------------------------------------------------------------------------

func test_demote_far_and_promote_near_with_hysteresis() -> void:
	var w: Dictionary = _world()
	var crew: SphereCrew = w["crew"]
	var lumi: Node3D = w["lumi"]
	var surface: SphereSurface = w["surface"]
	var u: Dictionary = crew.spawn("scoopie", 0, 100)
	assert_true(crew.is_near(u))
	var d0: Vector3 = _g5.centers[100]
	var side: Vector3 = SphereMath.any_perpendicular(d0)
	lumi.global_position = surface.ground(SphereMath.advance(d0, side, 290.0 / _g5.radius_m)[0])
	crew.tick(0.3)
	assert_true(crew.is_near(u), "290 m: still inside the demote radius")
	lumi.global_position = surface.ground(SphereMath.advance(d0, side, 340.0 / _g5.radius_m)[0])
	crew.tick(0.3)
	assert_false(crew.is_near(u), "340 m: demoted to a record")
	assert_eq(crew.near_count(), 0)
	lumi.global_position = surface.ground(SphereMath.advance(d0, side, 290.0 / _g5.radius_m)[0])
	crew.tick(0.3)
	assert_false(crew.is_near(u), "290 m on the way back: hysteresis keeps it a record")
	lumi.global_position = surface.ground(d0)
	crew.tick(0.3)
	assert_true(crew.is_near(u), "promoted back")
	assert_lt(crew.unit_dir(u).angle_to(d0) * _g5.radius_m, 20.0, "streams back in where it was")


func test_far_crew_works_at_the_online_rate() -> void:
	var w: Dictionary = _world()
	var crew: SphereCrew = w["crew"]
	crew.focus = null  # everything far
	var u: Dictionary = crew.spawn("scoopie", 0, 100)
	assert_false(crew.is_near(u))
	var secs: float = 1800.0
	crew.run_far(secs, 1.0)
	var expect: float = Offline.unit_rate("scoopie", 0) * secs
	var got: float = float(u["log"]["junk"])
	assert_gt(got, expect * 0.85, "far work = Offline.unit_rate minus a little travel")
	assert_lt(got, expect * 1.001)


func test_far_cleaning_changes_the_far_shell() -> void:
	var w: Dictionary = _world()
	var crew: SphereCrew = w["crew"]
	var cells: SphereCells = w["cells"]
	var shell := SphereShell.new(_g5, cells, _t5, 3)
	var far_hub: int = 3000
	crew.focus = w["lumi"]
	assert_gt(_g5.distance_m(100, far_hub), 600.0)
	var big: int = shell.owner_of(far_hub)
	var before: float = shell._img_a.get_pixel(big % SphereShell.TEX_W, big / SphereShell.TEX_W).r
	for i: int in 3:
		crew.spawn("scoopie", 0, far_hub, far_hub)
	assert_eq(crew.near_count(), 0)
	crew.run_far(900.0, 1.0)
	shell.update(1.0)
	var after: float = shell._img_a.get_pixel(big % SphereShell.TEX_W, big / SphereShell.TEX_W).r
	assert_lt(after, before - 0.05, "the big hex over the far crew lost junk (%.2f -> %.2f)" % [before, after])


func test_save_round_trip_by_direction() -> void:
	var w: Dictionary = _world()
	var crew: SphereCrew = w["crew"]
	crew.spawn("scoopie", 0, 100)
	var u2: Dictionary = crew.spawn("haulbug", 0, 3000)
	u2["carry"] = [4.0]
	_run(crew, 5.0)
	var d: Dictionary = crew.to_dict()
	var dirs: Array[Vector3] = []
	for u: Dictionary in crew.robots():
		dirs.append(crew.unit_dir(u))
	var back: Dictionary = JSON.parse_string(JSON.stringify(d))
	crew.from_dict(back)
	assert_eq(crew.robots().size(), 2)
	for i: int in 2:
		assert_lt(crew.unit_dir(crew.robots()[i]).angle_to(dirs[i]) * _g5.radius_m, 0.01)
	assert_eq((crew.robots()[1]["carry"] as Array).size(), 1)


# --- Offline (shared maths) -------------------------------------------------------------

func test_offline_compute_unchanged_by_the_refactor() -> void:
	var r: Dictionary = Offline.compute([{"type": "scoopie", "tier": 0}, {"type": "haulbug", "tier": 0}], 0, 1.0, 3600.0)
	var units: float = Economy.robot_stat("scoopie", "scoop_rate", 0) * 0.35 * 0.9 * 3600.0 * Offline.OFFLINE_RATE
	assert_almost_eq(float(r["units"]), units, 0.001)
	assert_almost_eq(float(r["cubes"]), units * Offline.AVG_VALUE_PER_UNIT * Economy.robot_stat("scoopie", "efficiency", 0), 0.001)


func test_two_hour_offline_matches_flat_within_10_percent() -> void:
	var g7: SphereGrid = SphereGrid.for_hex_size(7, 10.0)
	var cells := SphereCells.new(g7.cell_count())
	var fleet: Array = [{"type": "scoopie", "tier": 0}, {"type": "scoopie", "tier": 0}, {"type": "scoopie", "tier": 0},
		{"type": "haulbug", "tier": 0}, {"type": "haulbug", "tier": 0}]
	var flat: Dictionary = Offline.compute(fleet, 0, 1.0, 7200.0, 1e9)
	var orbit: Dictionary = SphereOffline.simulate(g7, cells, null, [{"cell": 500, "robots": fleet}], 7200.0)
	var fc: float = float(flat["cubes"])
	assert_gt(fc, 0.0)
	assert_lt(absf(float(orbit["cubes"]) - fc) / fc, 0.10, "orbit %.0f vs flat %.0f cubes" % [float(orbit["cubes"]), fc])
	var cleaned: int = 0
	for c: int in SphereOffline.region(g7, cells, 500):
		cleaned += 0 if cells.is_dirty(c) else 1
	assert_almost_eq(float(cleaned), float(flat["units"]) / SphereOffline.UNITS_PER_CELL, 1.5, "the units became cleaned cells")
	# Nearest the hub first: the hub cell itself is clean.
	assert_false(cells.is_dirty(500))


func test_offline_capped_by_region_junk() -> void:
	var cells := SphereCells.new(_g5.cell_count())
	var fleet: Array = [{"type": "scoopie", "tier": 3}, {"type": "haulbug", "tier": 0}]
	var reg: PackedInt32Array = SphereOffline.region(_g5, cells, 100, 2)
	var r: Dictionary = SphereOffline.simulate(_g5, cells, null, [{"cell": 100, "robots": fleet, "rings": 2}], 8.0 * 3600.0)
	assert_almost_eq(float(r["units"]), reg.size() * SphereOffline.UNITS_PER_CELL, 0.01)
	var again: Dictionary = SphereOffline.simulate(_g5, cells, null, [{"cell": 100, "robots": fleet, "rings": 2}], 8.0 * 3600.0)
	assert_eq(float(again["cubes"]), 0.0, "a clean region pays nothing")


func test_region_scales_with_planet_size() -> void:
	assert_eq(SphereOffline.region_rings(163842, 10), 16, "Verdance")
	# Every planet's hub region keeps the same share of its hub's ground (planets.json globe).
	var ref: float = (1.0 + 3.0 * 16.0 * 17.0) / (163842.0 / 10.0)
	for id: String in ["verdance", "ochre", "tidewell", "rime", "anvil"]:
		var sp: Dictionary = GlobeSpec.of(id)
		var n: int = GlobeSpec.cells_for(int(sp["frequency"]))
		var hubs: int = SphereOffline.hub_count(id)
		assert_eq(hubs, int(sp["hub_count"]))
		var r: int = SphereOffline.region_rings(n, hubs)
		var share: float = (1.0 + 3.0 * r * (r + 1)) / (float(n) / hubs)
		assert_almost_eq(share / ref, 1.0, 0.15, "%s: %d rings" % [id, r])


# --- Command view -----------------------------------------------------------------------

func test_command_pick_returns_the_cell_under_the_cursor() -> void:
	var w: Dictionary = _world()
	var surface: SphereSurface = w["surface"]
	var cell: int = 2500
	var d: Vector3 = _g5.centers[cell]
	var o: Vector3 = surface.ground(d) + d * 120.0
	assert_eq(_g5.cell_at(SphereCommand.ray_dir(o, -d, surface)), cell, "straight down")
	var off: Vector3 = SphereMath.any_perpendicular(d)
	var slant: Vector3 = (surface.ground(d) - (o + off * 60.0)).normalized()
	assert_eq(_g5.cell_at(SphereCommand.ray_dir(o + off * 60.0, slant, surface)), cell, "slanted ray hits the same hex")
	assert_eq(SphereCommand.ray_dir(o, d, surface), Vector3.ZERO, "looking at the sky picks nothing")


func test_materialized_cell_takes_a_full_cell_of_work() -> void:
	# Pieces are removed whole; the crew's work target keeps the account, so a cell's worth of
	# junk goes into the hopper before the cell is clean (big pieces must not lose junk).
	var w: Dictionary = _world()
	var crew: SphereCrew = w["crew"]
	var cells: SphereCells = w["cells"]
	var field := SphereField.new(_g5, _t5, cells, 7)
	crew.field = field
	var c: int = _g5.cells_around(100, 1)[3]
	field.materialize(c)
	assert_eq(field.pieces_in(c).size(), SphereField.FULL_PIECES)
	var u: Dictionary = crew.spawn("scoopie", 0, c)
	crew.order(u, c)
	var at_clean: Array = [-1.0]
	crew.cell_cleaned.connect(func(cc: int) -> void:
		if cc == c:
			at_clean[0] = float(u["log"]["junk"]))
	_run(crew, 200.0, 0.1)
	assert_false(cells.is_dirty(c), "cleaned")
	var got: float = at_clean[0]
	assert_gt(got, SphereOffline.UNITS_PER_CELL * 0.93, "about a full cell baled (%.1f)" % got)
	assert_lt(got, SphereOffline.UNITS_PER_CELL * 1.01)
	var alive: int = 0
	for pid: int in field.pieces_in(c):
		alive += field.piece_alive[pid]
	assert_lte(alive, 1, "the pieces are gone too")


# --- [orbC] polish: buildings, piece-by-piece work, 3D bales ---------------------------------

func _box_site(w: Dictionary, at_cell: int) -> Node3D:
	var surface: SphereSurface = w["surface"]
	var d: Vector3 = _g5.centers[at_cell]
	var root := Node3D.new()
	root.set("size_m", 90.0)
	add_child_autofree(root)
	root.global_transform = Transform3D(SphereMath.basis_from_up_fwd(d, SphereMath.any_perpendicular(d)), surface.ground(d))
	var sb := StaticBody3D.new()
	root.add_child(sb)
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(8.0, 4.0, 4.0)
	cs.shape = bx
	cs.position = Vector3(0, 2.0, 0)
	sb.add_child(cs)
	return root


func test_site_colliders_become_obstacles_and_blocked_cells() -> void:
	var w: Dictionary = _world()
	var crew: SphereCrew = w["crew"]
	var c: int = _g5.cells_around(100, 2)[10]
	var site: Node3D = _box_site(w, c)
	var circ: Array = SphereObstacles.circles(site, crew.surface)
	assert_gt(circ.size(), 2, "an 8 x 4 m box is tiled")
	for ob: Array in circ:
		assert_lt((ob[0] as Vector3).angle_to(_g5.centers[c]) * _g5.radius_m, 4.5, "on the box")
		assert_lt(float(ob[1]), 2.5, "a tight fit")
	crew.set_obstacles("s", circ)
	assert_true(crew.blocked.has(c), "routes avoid the cell under the building")
	var p: PackedInt32Array = crew.route(_g5.cells_around(100, 4)[50], _g5.cells_around(c, 2)[12])
	assert_false(p.slice(1, p.size() - 1).has(c), "no route through it")
	crew.tick(3.0)  # the swarm gets the circles
	var stand: Vector3 = crew._approach(crew.surface.ground(_g5.centers[c]), crew.surface.ground(_g5.centers[100]))
	assert_false(crew._inside_building(crew.surface.up_at(stand)), "scoops a piece under a wall from outside")


func test_near_robot_drives_to_each_piece() -> void:
	var w: Dictionary = _world()
	var crew: SphereCrew = w["crew"]
	var cells: SphereCells = w["cells"]
	var field := SphereField.new(_g5, _t5, cells, 7)
	crew.field = field
	var c: int = _g5.cells_around(100, 1)[2]
	field.materialize(c)
	var u: Dictionary = crew.spawn("scoopie", 0, c)
	crew.order(u, c)
	var took_near: int = 0
	var took: int = 0
	var alive: Dictionary = {}
	for pid: int in field.pieces_in(c):
		alive[pid] = true
	for i: int in 600:
		(u["bot"] as SphereBot).step(0.1)
		crew.tick(0.1)
		for pid: int in alive.keys():
			if field.piece_alive[pid] == 0:
				alive.erase(pid)
				took += 1
				if (u["bot"] as SphereBot).global_position.distance_to(field.piece_pos[pid]) < 2.0:
					took_near += 1
	assert_gt(took, 10)
	assert_gt(float(took_near) / took, 0.8, "pieces go where the robot is (%d of %d)" % [took_near, took])


func test_command_overlay_clusters_hundreds() -> void:
	var pts: Array = []
	for i: int in 300:
		pts.append({"pos": Vector2(400 + (i % 20) * 3.0, 300 + (i / 20) * 3.0), "role": "clean" if i % 4 else "haul", "state": 0})
	pts.append({"pos": Vector2(900, 100), "role": "plant", "state": 2})
	var cl: Array = CommandOverlay.cluster(pts, CommandOverlay.CLUSTER_PX)
	assert_lt(cl.size(), 12, "300 crowded robots read as a few clusters (%d)" % cl.size())
	var total: int = 0
	var lone: Dictionary = {}
	for c: Dictionary in cl:
		total += int(c["n"])
		if int(c["n"]) == 1:
			lone = c
	assert_eq(total, 301, "every robot is in one mark")
	assert_eq(int(lone.get("worst", -1)), 2, "a lone stuck robot keeps its warning")


func test_command_pan_moves_away_from_lumi_and_back() -> void:
	var w: Dictionary = _world()
	var cam := SphereCam.new()
	cam.surface = w["surface"]
	cam.target = w["lumi"]
	add_child_autofree(cam)
	cam.reset_frame(SphereMath.any_perpendicular(_g5.centers[100]))
	cam.view = "command"
	cam.command_height = 100.0
	for i: int in 30:
		cam.pan_command(Vector2(0, -1), 0.1)
	var moved: float = cam.command_focus.angle_to(_g5.centers[100]) * _g5.radius_m
	assert_almost_eq(moved, 100.0 * 1.2 * 3.0, 5.0, "panned forward at 1.2 x height per second")
	cam.update_camera(0.0)
	var below: Vector3 = (w["surface"] as SphereSurface).up_at(cam.camera.global_position)
	assert_lt(below.angle_to(cam.command_focus) * _g5.radius_m, 60.0, "the camera is over the panned spot")
	cam.view = "follow"
	cam.update_camera(0.0)
	assert_eq(cam.command_focus, Vector3.ZERO, "leaving Command recentres on Lumi")


func test_skimmers_clean_lakes_and_bale_on_the_shore() -> void:
	var w: Dictionary = _world()
	var crew: SphereCrew = w["crew"]
	var cells: SphereCells = w["cells"]
	var lake: PackedInt32Array = _g5.cells_around(_g5.cells_around(100, 2)[14], 1)
	for c: int in lake:
		cells.set_state(c, 5)
		cells.set_junk(c, 1.0)
	var u: Dictionary = crew.spawn("skimmer", 0, 100)
	_run(crew, 400.0, 0.2)
	var cleaned: int = 0
	for c: int in lake:
		cleaned += 1 if not crew.water_dirty(c) else 0
	assert_gt(cleaned, 1, "the skimmer cleared lake hexes")
	assert_gt(float(u["log"]["junk"]), SphereOffline.UNITS_PER_WATER_CELL, "it netted floaters")
	for b: Dictionary in crew.bales:
		assert_ne(cells.state[_g5.cell_at(b["dir"])], 5, "bales sit on the shore, not in the lake")
	assert_eq(crew.stuck_count(), 0)


func test_offline_skimmers_work_the_lakes() -> void:
	var cells := SphereCells.new(_g5.cell_count())
	var lake: PackedInt32Array = _g5.cells_around(_g5.cells_around(100, 2)[14], 1)
	for c: int in lake:
		cells.set_state(c, 5)
		cells.set_junk(c, 1.0)
	var land0: float = SphereOffline.units_left(cells, SphereOffline.region(_g5, cells, 100, 4))
	var fleet: Array = [{"type": "skimmer", "tier": 0}, {"type": "haulbug", "tier": 0}]
	var r: Dictionary = SphereOffline.simulate(_g5, cells, null, [{"cell": 100, "robots": fleet, "rings": 4}], 3600.0)
	assert_gt(float(r["cubes"]), 0.0)
	assert_almost_eq(SphereOffline.units_left(cells, SphereOffline.region(_g5, cells, 100, 4)), land0, 0.01, "land untouched")
	assert_lt(SphereOffline.units_left(cells, SphereOffline.region_water(_g5, cells, 100, 4)), lake.size() * SphereOffline.UNITS_PER_WATER_CELL, "lakes cleaner")


func test_robot_cleaned_count_matches_a_reload() -> void:
	# [orbC] The live ledger count must equal what a reload recounts from SphereCells (orbD soak:
	# 90 live vs 92 after reload). Near piece work and far numbers work, many cells.
	var w: Dictionary = _world()
	var crew: SphereCrew = w["crew"]
	var cells: SphereCells = w["cells"]
	var field := SphereField.new(_g5, _t5, cells, 7)
	crew.field = field
	var cleaned_signals: Array = [0]
	crew.cell_cleaned.connect(func(_c: int) -> void: cleaned_signals[0] = int(cleaned_signals[0]) + 1)
	var start: int = field.cleaned_count
	for c: int in _g5.cells_around(100, 2):
		field.materialize(c)  # Lumi's near ring: real pieces
	for c: int in _g5.cells_around(3000, 3):
		field.materialize(c)  # a far crew's own ring: real pieces, worked as numbers (the soak's case)
	for i: int in 3:
		crew.spawn("scoopie", 0, _g5.cells_around(100, 1)[i + 1])
	for i: int in 3:
		crew.spawn("scoopie", 0, _g5.cells_around(3000, 1)[i + 1], 3000)  # far: numbers only
	_run(crew, 900.0, 0.2)
	var reloaded := SphereField.new(_g5, _t5, cells, 7)
	assert_gt(field.cleaned_count - start, 4, "the crews cleaned hexes")
	assert_eq(field.cleaned_count, reloaded.cleaned_count, "live count = count after a reload")
	assert_eq(int(cleaned_signals[0]), field.cleaned_count - start, "every clean went through cell_cleaned (the player's on_hex_clean flow)")
