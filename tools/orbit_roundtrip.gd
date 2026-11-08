class_name OrbitRoundtrip
extends RefCounted
## [orbB] Save/load round trip for the slice on the globe (tools/save_roundtrip.tscn with
## --orbit): builds state in one orbit slice, saves it to the round trip's slot, loads it into a
## second slice and compares. Grows with each ported system.


static func _snap(s: Node) -> Dictionary:
	var g: OrbitPlanet = (s.get("orbit") as SliceOrbit).globe
	var p: Patch = s.get("patch")
	var cd: Dictionary = g.cells.to_dict()
	var at: Array = g.to_dirh(p.global_position)
	var cubes: Array = []
	for n: Node in (s.get("_cubes_root") as Node).get_children():
		if n is JunkCube:
			var c: JunkCube = n
			var a: Array = g.to_dirh(c.global_position)
			cubes.append("%s %.4f,%.4f,%.4f" % [c.dominant_type() if c.has_method("dominant_type") else "", a[0], a[1], a[2]])
	cubes.sort()
	return {
		"schema": int(GameState.orbit.get("schema", 0)),
		"cells_n": g.grid.cell_count(),
		"freq": "%d saved=%d %s" % [g.grid.freq, int(GameState.orbit.get("freq", 0)), str(GameState.orbit.get("planet_id", ""))],
		"cubes": snappedf(GameState.get_currency("cubes").to_float(), 0.01),
		"cells_junk": hash(cd["junk"]),
		"cells_state": hash(cd["state"]),
		"cells_level": hash(cd["level"]),
		"cleaned": s.field.cleaned_count,
		"planet_clean": snappedf(g.planet.restored_fraction(), 0.000001),
		"lumi_dir": "%.4f,%.4f,%.4f" % [at[0], at[1], at[2]],
		"lumi_fill": snappedf(p.compartment.fill, 0.01),
		"parts_found": s.field.part_found.count(1),
		"sites": str(OrbitSave.site_cells(GameState.orbit)),
		"sites_built": str(OrbitSave.sites_to_array((s.get("orbit") as SliceOrbit).globe.sites)),
		"hexes_paid": (GameState.orbit.get("hexes_paid", {}) as Dictionary).size(),
		"hex_level_target": (s.get("hex_levels") as HexLevels).level_of(int(s.get_meta("rt_target", -1))),
		"cells_level_target": g.cells.level[int(s.get_meta("rt_target", 0))],
		"milestone_1": GameState.flags.get("hexm_1", false),
		"hub_level": (s.get("hub") as Hub).level,
		"bench_ok": Camp.bench_ok(),
		"site_stage": g.site_manager.levels[0] if g.site_manager else -1,
		"parts_near": s.field.part_pos.size() > 0,
		"loose_cubes": cubes,
	}


static func run(rt: Node, check: Callable) -> void:
	var tree: SceneTree = rt.get_tree()
	var packed: PackedScene = load("res://scenes/slice.tscn")
	var s1: Node = packed.instantiate()
	tree.root.add_child(s1)
	for i: int in 5:
		await tree.process_frame
	var so: SliceOrbit = s1.get("orbit")
	check.call("orbit_slice_built", true, so != null and so.globe != null)
	if so == null:
		return
	var g: OrbitPlanet = so.globe
	var p: Patch = s1.get("patch")
	GameState.add_currency("cubes", BigNum.from_float(1234))
	# Clean the dirty near cell closest to Lumi, by hand.
	var target: int = -1
	var best: float = INF
	for c: int in g.streamer.near_cells():
		if g.field.hex_hub[c] == 0 and not g.field.is_clean(c) and not g.field.pieces_in(c).is_empty():
			var d: float = g.field.hex_center(c).distance_to(p.global_position)
			if d < best:
				best = d
				target = c
	check.call("orbit_has_dirty_near_cell", true, target >= 0)
	var clean0: int = s1.field.cleaned_count
	if target >= 0:
		for pid: int in g.field.pieces_in(target):
			if g.field.piece_alive[pid] == 1:
				s1.collect_piece(pid)
	check.call("orbit_cell_cleaned", clean0 + 1, s1.field.cleaned_count)
	check.call("orbit_first_hex_milestone", true, GameState.flags.get("hexm_1", false))
	await tree.create_timer(1.4).timeout  # HexLevels samples once a second: the clean cell reaches level 1
	check.call("orbit_hex_level_1", 1, (s1.get("hex_levels") as HexLevels).level_of(target))
	s1.set_meta("rt_target", target)
	# Half-clean a second one and set a level on a third (the far shell / future layer read these).
	for c: int in g.grid.neighbors(target if target >= 0 else g.start_cell()):
		if g.field.hex_hub[c] == 0 and not g.field.is_clean(c):
			so.crews.work_cell(c, 0.4)
			break
	g.cells.set_level(g.start_cell(), 3)
	if g.field.part_pos.size() > 0:  # the detector dug one up
		g.field.part_found[0] = 1
	# The workbench: Lumi at the start site's bench anchor gets the prompt, E opens the Upgrades.
	var so1: SliceOrbit = so
	p.place_on_sphere(so1.bench_position() + so1.bench_position().normalized() * 0.3, p.forward())
	await tree.physics_frame
	check.call("orbit_bench_starts_broken", false, Camp.bench_ok())
	check.call("orbit_bench_prompt", TranslationServer.translate("E   Workbench (broken): repair it"), s1.interact_prompt(p))
	s1.try_interact(p)  # the first E repairs it
	await tree.create_timer(float(Camp.cfg().get("bench_repair_s", 2.6)) + 0.6).timeout
	check.call("orbit_bench_repaired", true, Camp.bench_ok())
	s1.try_interact(p)
	check.call("orbit_upgrades_open", true, (s1.get("upgrades") as UpgradesScreen).is_open)
	(s1.get("upgrades") as UpgradesScreen).close_screen()
	# The base: a hub upgrade raises the start site's stage and stays in the site's own dict.
	GameState.add_currency("cubes", BigNum.from_float(1e6))
	GameState.add_currency("parts", BigNum.from_float(1e5))
	check.call("orbit_hub_upgrade", true, (s1.get("hub") as Hub).upgrade())
	check.call("orbit_site_stage", 2, g.site_manager.levels[0] if g.site_manager else -1)
	# Lumi walks 40 m off the pad with something in the chest.
	var d: Vector3 = g.terrain.local_to_dir(g.start_cell(), 40.0, -25.0)
	p.place_on_sphere(g.terrain.ground(d), -SphereGrid.frame(d).z)
	p.compartment.fill = 3.5
	for i: int in 3:
		await tree.physics_frame
	var ok: bool = SaveManager.save_game()
	check.call("orbit_saved", true, ok)
	var a: Dictionary = _snap(s1)
	var disk: Dictionary = SaveManager.read_dict(SaveManager.slot_path())
	check.call("orbit_flat_world_untouched", false, (disk.get("world", {}) as Dictionary).has("hub_level"))
	check.call("orbit_hub_world_saved", 2, int((((disk.get("orbit", {}) as Dictionary).get("hub_worlds", {}) as Dictionary).get("0", {}) as Dictionary).get("hub_level", 0)))
	var s1_target: int = int(s1.get_meta("rt_target", -1))
	check.call("orbit_save_has_no_flat_xz", false, JSON.stringify(GameState.orbit.get("lumi", {})).contains("\"pos\""))
	s1.queue_free()
	await tree.process_frame
	await tree.process_frame
	GameState.new_game()
	check.call("orbit_loads", true, SaveManager.load_game())
	GameState.reload_in_memory = true
	var s2: Node = packed.instantiate()
	tree.root.add_child(s2)
	for i: int in 5:
		await tree.process_frame
	s2.set_meta("rt_target", s1_target)
	var b: Dictionary = _snap(s2)
	for k: String in a:
		check.call("orbit_" + k, a[k], b[k])
	s2.queue_free()
	await tree.process_frame
	await _old_save(tree, packed, check)


## An old flat save (tests/fixtures) loads into the globe: its cleaned cells, base level and
## chest come over, Lumi stands on the start site, and the migrated globe saves and reloads.
static func _old_save(tree: SceneTree, packed: PackedScene, check: Callable) -> void:
	var d: Dictionary = SaveManager.read_dict(ProjectSettings.globalize_path("res://tests/fixtures/flat_v4_oldtown.save"))
	check.call("orbit_old_fixture", true, not d.is_empty())
	if d.is_empty():
		return
	SaveManager.write_dict(SaveManager.slot_path(), d)
	GameState.new_game()
	check.call("orbit_old_loads", true, SaveManager.load_game())
	GameState.reload_in_memory = true
	var s: Node = packed.instantiate()
	tree.root.add_child(s)
	for i: int in 5:
		await tree.process_frame
	var so: SliceOrbit = s.get("orbit")
	var g: OrbitPlanet = so.globe
	check.call("orbit_old_migrated", "flat_v%d" % GameState.SAVE_VERSION, str(GameState.orbit.get("migrated", "")))
	check.call("orbit_old_base_level", 2, OrbitSave.hub_level({"hubs": so.hub_states}, 0))
	var clean_cells: int = 0
	for c: int in g.cells.n:
		if g.cells.state[c] == 1 and not g.cells.has_flag(c, SphereCells.F_HUB):
			clean_cells += 1
	check.call("orbit_old_cells_cleaned", true, clean_cells >= 9)
	var p: Patch = s.get("patch")
	check.call("orbit_old_lumi_on_start_site", 0, g.site_at(p.global_position))
	check.call("orbit_old_chest", 2.5, snappedf(p.compartment.fill, 0.01))
	var cubes0: float = GameState.get_currency("cubes").to_float()
	check.call("orbit_old_saved", true, SaveManager.save_game())
	var cd: Dictionary = g.cells.to_dict()
	s.queue_free()
	await tree.process_frame
	GameState.new_game()
	SaveManager.load_game()
	GameState.reload_in_memory = true
	var s2: Node = packed.instantiate()
	tree.root.add_child(s2)
	for i: int in 5:
		await tree.process_frame
	var g2: OrbitPlanet = (s2.get("orbit") as SliceOrbit).globe
	check.call("orbit_old_reload_cells", hash(cd["state"]), hash(g2.cells.to_dict()["state"]))
	check.call("orbit_old_reload_base_level", 2, OrbitSave.hub_level({"hubs": (s2.get("orbit") as SliceOrbit).hub_states}, 0))
	check.call("orbit_old_reload_cubes", cubes0, GameState.get_currency("cubes").to_float())
	s2.queue_free()
	await tree.process_frame
