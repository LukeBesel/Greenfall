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
	var bots: Array = []  # [orbC] the crew: type, tier, cargo (positions are checked with a tolerance)
	var crew: SphereCrew = (s.get("orbit") as SliceOrbit).crews.crew
	if crew:
		for u: Dictionary in crew.robots():
			bots.append("%s %s t%d hopper %.0f carry %d junk %.0f" % [u["name"], u["type"], int(u["tier"]), float(u["hopper"]), (u["carry"] as Array).size(), float(u["log"]["junk"])])
	return {
		"robots": bots,  # [orbC]
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
		"garden": _garden_sig(s),
		"outposts": "%s live %s" % [_outpost_state(), str(_outpost_levels(s))],  # [orbB]
		"decor": _decor_state(),  # [orbB]
		"yard_built": JSON.stringify(YardBuilds.state().get("built", {})),
		"site_stage": g.site_manager.levels[0] if g.site_manager else -1,
		"parts_near": s.field.part_pos.size() > 0,
		"loose_cubes": cubes,
		"sky_spin": snappedf((s.get("sky_director") as SkyDirector).spin, 0.01) if s.get("sky_director") is SkyDirector else -1.0,  # [orbE]
		"sky_clouds": snappedf((s.get("sky_director") as SkyDirector).clouds, 0.01) if s.get("sky_director") is SkyDirector else -1.0,  # [orbE]
	}


static func _outpost_state() -> String:
	var out: Array = []
	var by_hub: Dictionary = GameState.world.get("orbit_outposts", {})
	for k: String in by_hub:
		out.append("%s:%s" % [k, str(((by_hub[k] as Dictionary).get("levels", []) as Array).map(func(v: Variant) -> int: return int(v)))])
	out.sort()
	return " ".join(out)


static func _decor_state() -> String:
	var lists: Dictionary = {"0": GameState.world.get("decor", {})}
	for k: String in (GameState.world.get("orbit_decor", {}) as Dictionary):
		lists[k] = GameState.world["orbit_decor"][k]
	var out: Array = []
	for k: String in lists:
		for it: Variant in (lists[k] as Dictionary).get("items", []):
			out.append("%s:%s %d,%d r%d" % [k, str(it["t"]), int(it["x"]), int(it["z"]), int(it.get("r", 0))])
	out.sort()
	return " ".join(out)


## A free decor cell near Lumi (frame-local), or Vector2i(9999, 9999).
static func _free_decor_cell(dc: Decor, t: String, near: Vector3) -> Vector2i:
	var c0: Vector2i = Decor.cell_at(dc.to_local(near))
	for r: int in range(2, 14):
		for k: int in 16:
			var c: Vector2i = c0 + Vector2i(roundi(cos(TAU * k / 16.0) * r), roundi(sin(TAU * k / 16.0) * r))
			if dc.place_block_reason(t, c, 0) == "":
				return c
	return Vector2i(9999, 9999)


static func _outpost_levels(s: Node) -> Array:
	var out: Array = []
	var op: Outposts = s.get("outposts") as Outposts
	if op:
		for o: Outpost in op.items:
			out.append(o.level)
	return out


## [orbC] Stops a slice's robot crew (the brain and every real robot) so state compares as saved.
static func _freeze_crew(s: Node) -> void:
	var so: SliceOrbit = s.get("orbit")
	var crew: SphereCrew = so.crews.crew if so and so.crews else null
	if crew == null:
		return
	crew.set_process(false)
	for u: Dictionary in crew.robots():
		if u["bot"] != null:
			(u["bot"] as Node).set_process(false)


static func _garden_sig(s: Node) -> String:
	var gdn: Garden = s.get("garden")
	if gdn == null:
		return "-"
	var cells: Dictionary = gdn.persist_sparse().get("cells", {})
	var keys: Array = cells.keys()
	keys.sort()
	var parts: Array = []
	for k: Variant in keys:
		parts.append("%s:%s" % [str(k), str((cells[k] as Array)[0])])
	return ",".join(parts)


## [orbB] Fauna in its hub frame: animals on greened cells near the start hub, standing on the
## globe's ground; a hop to hub 1 moves the frame and rebuilds them there; between hubs they sleep.
static func _fauna_check(tree: SceneTree, s: Node, so: SliceOrbit, check: Callable) -> void:
	var hf: HubFrame = so.hub_frame
	check.call("orbit_fauna_frame_at_start", 0, hf.hub)
	var g: OrbitPlanet = so.globe
	var hl: HexLevels = s.get("hex_levels")
	var region: PackedInt32Array = hf.region()
	var n: int = 0
	for c: int in region:
		if g.field.hex_hub[c] == 0 and g.field.hex_water[c] == 0 and n < 60 and not hl.levels.has(c) and g.field.is_clean(c) == false:
			so.crews.work_cell(c, 0.0)
			hl.track(c)
			hl.levels[c] = 4
			n += 1
	var fa: Fauna = hf.node("Fauna") as Fauna
	fa.replan()
	for i: int in 30:
		await tree.process_frame
	var bad: Array = []
	for a: Variant in fa.animals:
		var wp: Vector3 = fa.to_global(a.pos)
		var alt: float = g.surface.altitude(wp)
		if alt < -1.5 or alt > 40.0 or g.grid.great_circle_m(wp, g.grid.centers[g.start_cell()]) > 450.0:
			bad.append("%s alt %.1f" % [str(a.sp), alt])
	check.call("orbit_fauna_animals", true, fa.animals.size() > 0)
	check.call("orbit_fauna_on_the_ground", "[]", str(bad))
	var far_p := Vector3(0, 0, 120.0)  # 120 m out the frame's up is degrees off; the animal's is the ground's
	var off_frame: float = rad_to_deg((fa.global_basis * Vector3.UP).angle_to(fa.to_global(far_p).normalized()))
	var off_animal: float = rad_to_deg((fa.global_basis * (fa._tilt(far_p) * Vector3.UP)).angle_to(fa.to_global(far_p).normalized()))
	check.call("orbit_fauna_upright_far_out", true, off_frame > 3.0 and off_animal < 0.05)
	# Easter eggs: this hub's set, standing on the ground clear of the yard; one can be poked.
	var eg: EasterEggs = hf.node("EasterEggs") as EasterEggs
	check.call("orbit_eggs_placed", true, eg != null and eg.placed.size() > 0)
	var off: Array = []
	for e: Dictionary in eg.placed:
		var en0: Node3D = e["node"]
		var alt: float = g.surface.altitude(en0.global_position)
		var dm: float = g.grid.great_circle_m(en0.global_position, g.grid.centers[g.start_cell()])
		if absf(alt) > 0.6 or dm < 13.0 or dm > 450.0:
			off.append("%s alt %.2f at %.0f m" % [str(e["id"]), alt, dm])
	check.call("orbit_eggs_on_the_ground", "[]", str(off))
	var e0: Dictionary = eg.placed[0]
	var en: Node3D = e0["node"]
	en.visible = true
	var p: Patch = s.get("patch")
	var back: Vector3 = p.global_position
	p.place_on_sphere(en.global_position + en.global_basis.z * 1.4, p.forward())
	await tree.physics_frame
	check.call("orbit_egg_prompt", true, s.interact_prompt(p) != "")
	var eggs0: Array = eg.placed.map(func(x: Dictionary) -> String: return str(x["id"]))
	# Outposts: 3-4 ruins round the hub just outside its site, upright on the ground; one repaired
	# (its level lives per hub in the start site's dict) becomes the nearest scale for a hauler.
	var op: Outposts = hf.node("Outposts") as Outposts
	check.call("orbit_outposts_placed", true, op != null and op.items.size() >= 3 and s.get("outposts") == op)
	var opbad: Array = []
	for o: Outpost in op.items:
		var alt2: float = g.surface.altitude(o.global_position)
		var tilt: float = rad_to_deg(o.global_basis.y.normalized().angle_to(o.global_position.normalized()))
		var cell: int = g.field.hex_at(o.global_position)
		if absf(alt2) > 0.6 or tilt > 1.0 or not region.has(cell) or g.cells.has_flag(cell, SphereCells.F_SITE):
			opbad.append("outpost %d alt %.2f tilt %.1f cell %d" % [o.index, alt2, tilt, cell])
	check.call("orbit_outposts_on_the_ground", "[]", str(opbad))
	p.place_on_sphere(op.items[0].anchor.global_position, p.forward())
	await tree.physics_frame
	check.call("orbit_outpost_prompt", true, s.interact_prompt(p).to_lower().contains("outpost"))
	op.repair(0, false, true)
	var lv0: Array = ((GameState.world.get("orbit_outposts", {}) as Dictionary).get("0", {}) as Dictionary).get("levels", [])
	check.call("orbit_outpost_repaired_state", 1, int(lv0[0]) if lv0.size() > 0 else -1)
	check.call("orbit_outpost_nearest_scale", true, Outposts.nearest_depot(s, op.items[0].pad_world()) == op.items[0].scale_depot)
	# The Ledger: a drone comes in from up high; its dump makes a clean cell dirty again in the
	# cell's numbers too; the relay (act 3) stands upright at this hub's frontier with its prompt.
	var lg: LedgerArc = hf.node("Ledger") as LedgerArc
	check.call("orbit_ledger_at_hub", true, lg != null and s.get("ledger") == lg)
	GameState.flags["ledger_act"] = 2
	p.place_on_sphere(back, p.forward())
	lg._dev_clean_nearest()
	var cands: Array[int] = LedgerArc.drop_candidates(g.field, lg.is_planted, region)
	check.call("orbit_ledger_drop_candidates", true, cands.size() > 0)
	if cands.size() > 0:
		check.call("orbit_ledger_drone_inbound", true, lg.start_drop(true) and lg.drone != null)
		var dalt: float = g.surface.altitude(lg.drone.global_position) if lg.drone else -1.0
		check.call("orbit_ledger_drone_up_high", true, dalt > 10.0 and dalt < 40.0)
		lg._drone_done(lg.drone)
		var hid: int = -1
		var pids := PackedInt32Array()
		for c: int in cands:
			pids = LedgerArc.pick_drop_pieces(g.field, c, RandomNumberGenerator.new())
			if not pids.is_empty():
				hid = c
				break
		if hid >= 0:
			var drops0: int = int(GameState.stats.get("ledger_drops", 0))
			lg._release(hid, pids, lg._marker(lg.to_local(g.field.hex_center(hid)), Color.RED))
			check.call("orbit_ledger_drop_dirties_cell", "0 0 true", "%d %d %s" % [g.field.hex_clean[hid], g.cells.state[hid], str(g.cells.junk[hid] > 0.0)])
			await tree.create_timer(1.3).timeout
			check.call("orbit_ledger_drop_landed", drops0 + 1, int(GameState.stats.get("ledger_drops", 0)))
	var jclash: Array = []  # the base's jammer spots stay clear of the yard's anchors
	for ji: int in 3:
		var js: Vector3 = lg.jammer_spot(ji)
		if absf(g.surface.altitude(lg.to_global(js))) > 0.6 or lg._solid_at(js):
			jclash.append("jammer %d off the ground or in something" % ji)
		for nm: String in LedgerArc.YARD_ANCHORS:
			var yp: Vector3 = lg.to_local(so.yard_point(nm))
			if Vector2(yp.x - js.x, yp.z - js.z).length() < 3.0:
				jclash.append("%s %.1f m" % [nm, Vector2(yp.x - js.x, yp.z - js.z).length()])
	check.call("orbit_ledger_jammer_spots_clear", "[]", str(jclash))
	GameState.flags["ledger_act"] = 3
	GameState.flags["ledger_relay_hub"] = 0
	lg._place_relay()
	var ra: float = g.surface.altitude(lg.relay.global_position) if lg.relay else 99.0
	var rtilt: float = rad_to_deg(lg.relay.global_basis.y.angle_to(lg.relay.global_position.normalized())) if lg.relay else 99.0
	check.call("orbit_ledger_relay_placed", true, lg.relay != null and absf(ra) < 0.6 and rtilt < 1.0 and not g.cells.has_flag(g.field.hex_at(lg.relay.global_position), SphereCells.F_SITE))
	if lg.relay:
		p.place_on_sphere(lg.relay.to_global(Vector3(0, 0, 2.0)), p.forward())
		await tree.physics_frame
		check.call("orbit_ledger_relay_prompt", true, s.interact_prompt(p).contains("jack in"))
	p.place_on_sphere(back, p.forward())
	await tree.physics_frame
	# Garden Mode: this hub's decor sits in the frame on the ground; the yard's machines and its
	# buildings block a spot; the placer opens on it with the SphereCam following its cursor.
	var dc: Decor = hf.node("Decor") as Decor
	var lt: LateDirector = LateDirector.of(s)
	check.call("orbit_decor_at_hub", true, dc != null and lt != null and lt.decor == dc and lt.placer.decor == dc)
	var t0: String = Decor.type_ids()[0]
	var c0: Vector2i = _free_decor_cell(dc, t0, back)
	check.call("orbit_decor_placed", true, c0.x != 9999 and dc.place(t0, c0, 1, false, false))
	if not dc.nodes.is_empty():
		var dn: Node3D = dc.nodes[0]
		var dtilt: float = rad_to_deg(dn.global_basis.y.angle_to(dn.global_position.normalized()))
		check.call("orbit_decor_on_the_ground", true, absf(g.surface.altitude(dn.global_position)) < 0.4 and dtilt < 1.0)
	check.call("orbit_decor_state", 1, ((GameState.world.get("decor", {}) as Dictionary).get("items", []) as Array).size())
	var pod: Node3D = s.get_meta("orbit_pod") as Node3D if s.has_meta("orbit_pod") else null
	check.call("orbit_decor_sees_solid", true, pod != null and dc._solid_at(dc.to_local(pod.global_position)))
	check.call("orbit_decor_blocked_at_bench", true, dc.place_block_reason(t0, Decor.cell_at(dc.to_local(so.yard_point("bench"))), 0) != "")
	var hl0: int = int(GameState.world.get("hub_level", 1))
	GameState.world["hub_level"] = 5
	var sc: SphereCam = so.cam
	check.call("orbit_garden_mode_opens", true, lt.placer.open() and lt.placer.is_open and sc.target != null and sc.target.get_parent() == dc)
	lt.placer.close()
	check.call("orbit_garden_mode_closes", true, not lt.placer.is_open and sc.target == p)
	GameState.world["hub_level"] = hl0
	var h1: Vector3 = g.terrain.ground(g.grid.centers[int(g.sites[1]["cell"])])
	p.place_on_sphere(h1, p.forward())
	hf.check_now()
	check.call("orbit_fauna_frame_hops", 1, hf.hub)
	check.call("orbit_fauna_rebuilt_at_hub", true, hf.node("Fauna") != null and hf.node("Fauna") != fa)
	var eg1: EasterEggs = hf.node("EasterEggs") as EasterEggs
	var op1: Outposts = hf.node("Outposts") as Outposts
	var dc1: Decor = hf.node("Decor") as Decor
	var t1: String = Decor.type_ids()[0]
	var c1: Vector2i = _free_decor_cell(dc1, t1, h1) if dc1 else Vector2i(9999, 9999)
	check.call("orbit_decor_hub1_own", true, dc1 != null and dc1 != dc and dc1.items.is_empty() and lt.decor == dc1 and dc1.place(t1, c1, 1, false, false))
	check.call("orbit_decor_hub1_state", 1, (((GameState.world.get("orbit_decor", {}) as Dictionary).get("1", {}) as Dictionary).get("items", []) as Array).size())
	var lg1: LedgerArc = hf.node("Ledger") as LedgerArc
	check.call("orbit_ledger_hub1_no_relay", true, lg1 != null and lg1 != lg and lg1.relay == null and s.get("ledger") == lg1)
	check.call("orbit_outposts_hub1_own", true, op1 != null and op1 != op and op1.hub_index == 1 and op1.repaired_count() == 0 and s.get("outposts") == op1)
	check.call("orbit_eggs_hub1_own_set", true, eg1 != null and eg1 != eg and eg1.hub_index == 1 and (eg1.placed.size() == 0 or eg1.placed.map(func(x: Dictionary) -> String: return str(x["id"])) != eggs0))
	var mid: Vector3 = (back.normalized() + h1.normalized()).normalized()
	p.place_on_sphere(g.terrain.ground(mid), p.forward())
	hf.check_now()
	check.call("orbit_fauna_sleeps_between_hubs", -1, hf.hub)
	p.place_on_sphere(back, p.forward())
	hf.check_now()
	check.call("orbit_fauna_back_at_start", 0, hf.hub)
	check.call("orbit_outpost_rebuilt_repaired", 1, (hf.node("Outposts") as Outposts).items[0].level)
	check.call("orbit_decor_rebuilt", 1, (hf.node("Decor") as Decor).items.size())
	for i: int in 3:
		await tree.process_frame


## First Seed: the greenhouse stands on open ground east of the start yard; with enough clean
## cells the tin gives the prompt, and the cinematic (sped up here) unlocks seeds and hands
## the controls back.
static func _first_seed_check(tree: SceneTree, s: Node, so: SliceOrbit, check: Callable) -> void:
	for i: int in 4:
		await tree.physics_frame
	var fs: FirstSeed = s.get("first_seed") as FirstSeed
	check.call("orbit_first_seed_built", true, fs != null and fs._tin != null)
	if fs == null:
		return
	var g: OrbitPlanet = so.globe
	var gh: Vector3 = fs.greenhouse_point()
	var site: Transform3D = g.sites[0]["transform"]
	var local: Vector3 = site.affine_inverse() * gh
	var tilt: float = rad_to_deg(fs.global_basis.y.angle_to(gh.normalized()))
	check.call("orbit_greenhouse_east_on_ground", true, absf(g.surface.altitude(gh)) < 0.7 and tilt < 1.0 and local.x > 0.0 and Vector2(local.x, local.z).length() > 14.0 and Vector2(local.x, local.z).length() < 75.0)
	var fcfg: Dictionary = s.garden.cfg.get("first_seed", {})
	var need0: Variant = fcfg.get("hexes_needed", 5)
	fcfg["hexes_needed"] = 0
	s.garden.cfg["first_seed"] = fcfg
	var p: Patch = s.get("patch")
	var back: Vector3 = p.global_position
	var tin: Vector3 = fs._tin.global_position
	p.place_on_sphere(tin + (fs.global_basis.x.normalized()) * 1.2, p.forward())
	GameState.flags.erase("seeds_unlocked")  # (the garden check above unlocked them by hand)
	await tree.physics_frame
	check.call("orbit_seed_tin_prompt", "seed", s.interact_prompt(p))
	var seeds0: float = GameState.get_currency("seeds").to_float()
	s.try_interact(p)
	check.call("orbit_seed_cinematic_runs", true, fs._active and not (s.get("hud") as CanvasLayer).visible and not so.cam.input_enabled)
	Engine.time_scale = 30.0
	var t0: int = Time.get_ticks_msec()
	while (fs._active or not (s.get("hud") as CanvasLayer).visible) and Time.get_ticks_msec() - t0 < 15000:  # (the lines' timers drift a frame each)
		await tree.process_frame
	Engine.time_scale = 1.0
	check.call("orbit_seed_unlocked", true, GameState.flags.get("seeds_unlocked", false) and GameState.get_currency("seeds").to_float() > seeds0)
	await tree.process_frame
	check.call("orbit_seed_controls_back", "hud true cam true", "hud %s cam %s" % [str((s.get("hud") as CanvasLayer).visible), str(so.cam.input_enabled)])
	fcfg["hexes_needed"] = need0
	# The compost press stands on the "composter" anchor, hidden until it's a Hub build; once
	# built, its own model replaces the yard's stand-in, paper feeds it and it presses seeds.
	var cmp: Composter = s.get("composter") as Composter
	check.call("orbit_composter_on_anchor", true, cmp != null and cmp.global_position.distance_to(so.yard_point("composter")) < 0.1 and not cmp.visible)
	if cmp:
		YardBuilds.mark_built("composter")
		(s.get("camp") as Camp)._apply_builds()  # (a Hub build does this through Camp's build handler)
		await tree.create_timer(1.3).timeout
		var stand_in: bool = false
		for n: Node in s.find_children("*", "Node3D", true, false):
			if n is YardSite and (n as YardSite).get("_composter") != null:
				stand_in = true
		check.call("orbit_composter_built_one_model", true, cmp.visible and not stand_in)
		p.place_on_sphere(cmp.global_position + cmp.global_basis.z * 1.6, p.forward())
		await tree.physics_frame
		check.call("orbit_composter_prompt", true, s.interact_prompt(p).contains("compost press"))
		GameState.flags["first_sprout"] = true
		var h0: float = Composter.hopper()
		s.salvage_materials("paper", 10.0)
		check.call("orbit_composter_takes_paper", true, Composter.hopper() > h0)
		var sd0: float = GameState.get_currency("seeds").to_float()
		Engine.time_scale = 20.0
		await tree.create_timer(cmp.cycle_seconds() + 1.0).timeout
		Engine.time_scale = 1.0
		check.call("orbit_composter_presses_seeds", true, GameState.get_currency("seeds").to_float() > sd0)
	var sf: SeedFinds = null
	for n2: Node in s.get_children():
		if n2 is SeedFinds:
			sf = n2
	check.call("orbit_seed_finds", true, sf != null and sf.chance_for("paper") > 0.0)
	# Memory shards: placed in the start hub's region; one surfaces when its cell is clean, on the
	# ground; E reads it in the document view and it counts as found.
	var sh: ShardSystem = s.get("shards") as ShardSystem
	var region0: PackedInt32Array = g.grid.cells_around(g.start_cell(), SiteManager.REGION_RINGS)
	var placed_ok: bool = sh != null and sh._placed.size() == sh.docs.size() and sh.docs.size() > 0
	if placed_ok:
		for hid: int in sh._placed:
			placed_ok = placed_ok and region0.has(hid)
	check.call("orbit_shards_placed", true, placed_ok)
	if sh and placed_ok:
		var first: int = -1
		for hid2: int in sh._placed:
			if int(sh._placed[hid2]) == 0:
				first = hid2
		so.crews.work_cell(first, 0.0)
		sh._reveal(first, true)
		var sn: Node3D = sh._visible.get(first) as Node3D
		check.call("orbit_shard_surfaces_on_ground", true, sn != null and absf(g.surface.altitude(sn.global_position)) < 0.4)
		if sn:
			p.place_on_sphere(sn.global_position + sn.global_basis.z * 1.0, p.forward())
			await tree.physics_frame
			check.call("orbit_shard_prompt", "shard", s.interact_prompt(p))
			s.try_interact(p)
			var dv: DocumentView = s.get("doc_view") as DocumentView
			check.call("orbit_shard_read", true, dv != null and dv.is_open and sh.found(0))
			if dv:
				dv.close_doc()
			check.call("orbit_shard_closed_input_back", true, not tree.paused and so.cam.input_enabled)
	p.place_on_sphere(back, p.forward())


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
	# The start view: the crashed pod stays behind the follow camera, and nothing big sits between
	# the camera and Lumi (orbE's render had the camera inside the pod).
	var cam3: Camera3D = so.cam.camera
	var site: Node3D = s1.get_meta("orbit_pod", null) as Node3D
	if site and cam3:
		var to_pod: Vector3 = site.global_position - cam3.global_position
		var fwd3: Vector3 = -cam3.global_basis.z
		check.call("orbit_pod_out_of_view", true, to_pod.normalized().dot(fwd3) < cos(deg_to_rad(cam3.fov * 0.8)))
		check.call("orbit_camera_clear_of_pod", true, to_pod.length() > 3.0)
	var blockers: Array = []
	if cam3:
		for n: Node in s1.find_children("*", "GeometryInstance3D", true, false):
			var gi := n as GeometryInstance3D
			if not gi.is_visible_in_tree() or gi is MultiMeshInstance3D or s1.get("patch").is_ancestor_of(gi) or (s1.get_node_or_null("Glim") and s1.get_node("Glim").is_ancestor_of(gi)):
				continue
			if n.get_parent() is OrbitPlanet or str(n.get_path()).contains("Streamer") or str(n.get_path()).contains("Content/"):
				continue
			var ab: AABB = gi.global_transform * gi.get_aabb()
			if ab.size.length() < 1.5:
				continue
			var mid: Vector3 = cam3.global_position.lerp(p.global_position, 0.5)
			if ab.grow(0.2).has_point(mid) or ab.grow(0.2).has_point(cam3.global_position):
				blockers.append(str(s1.get_path_to(gi)))
	check.call("orbit_start_view_clear", "[]", str(blockers))
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
	# The garden: plant and water in the cell Lumi just cleaned (its slots are made on demand).
	var gdn: Garden = s1.get("garden")
	GameState.flags["seeds_unlocked"] = true
	GameState.add_currency("seeds", BigNum.from_float(10))
	var ctr: Vector3 = g.field.hex_center(target)
	var fwd: Vector3 = SphereGrid.frame(ctr.normalized()).x
	var planted_n: int = 0
	for k: int in 3:
		var sl: int = gdn.free_slot_near(ctr - fwd * 1.0, fwd, 6.0)
		if sl >= 0 and gdn.plant(sl):
			gdn.water(sl, 120.0)
			planted_n += 1
	check.call("orbit_garden_planted", 3, planted_n)
	check.call("orbit_garden_slots_on_ground", true, gdn.slot_pos.size() > 0 and absf(gdn.slot_pos[0].length() - (g.grid.radius_m + g.terrain.height(gdn.slot_pos[0].normalized()))) < 0.05)
	await _fauna_check(tree, s1, so, check)
	await _first_seed_check(tree, s1, so, check)
	# Glim's scanner marks the junk of the cell Lumi stands in (pieces by how big they look).
	var gd: GlimDirector = GlimDirector.of(s1)
	if gd:
		Glim.set_found(true)
		if gd.bot == null:
			gd.call("_spawn", false)
		var dc: int = -1
		for c: int in g.streamer.near_cells():
			if g.field.hex_hub[c] == 0 and not g.field.is_clean(c) and g.field.hex_water[c] == 0 and g.field.pieces_in(c).size() > 20:
				dc = c
				break
		if dc >= 0:
			p.place_on_sphere(g.field.hex_center(dc), p.forward())
			await tree.physics_frame
			check.call("orbit_glim_scan_marks", true, gd.do_scan(false) > 0)
	# The objective outline draws around a globe cell, in that cell's frame.
	var ob: Objectives = s1.get("objectives")
	if ob and ob.outline:
		var oc: int = g.grid.neighbors(target)[2]
		ob.outline.set_hex(oc)
		for i: int in 40:
			await tree.process_frame
		var aabb: AABB = (ob.outline.get_child(0) as MeshInstance3D).get_aabb() if ob.outline.get_child_count() > 0 else AABB()
		check.call("orbit_outline_on_cell", true, ob.outline.global_position.distance_to(g.field.hex_center(oc)) < 0.5)
		check.call("orbit_outline_cell_sized", true, aabb.size.x > 12.0 and aabb.size.x < 24.0 and absf(aabb.size.y) < 3.0)
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
	# The trash bin answers at the start site's "bin" anchor; a yard build's state lives in the hub.
	p.place_on_sphere(so1.yard_point("bin") + so1.yard_point("bin").normalized() * 0.3, p.forward())
	await tree.physics_frame
	check.call("orbit_bin_prompt", true, s1.interact_prompt(p) != "")
	YardBuilds.mark_built("radio")
	var scope: Telescope = Telescope.of(s1)
	check.call("orbit_telescope_at_anchor", true, scope != null and scope.door_point().distance_to(so1.yard_point("telescope")) < 3.0)
	var ex: ExtrasDirector = ExtrasDirector.of(s1)
	check.call("orbit_radio_on_anchor", true, ex != null and ex.radio != null and ex.radio.global_position.distance_to(so1.yard_point("radio")) < 0.1)
	if ex and ex.radio:
		ex.radio.set_built(true, false)
		var reach: Node3D = ex.radio.get("_anchor") as Node3D
		p.place_on_sphere(reach.global_position, p.forward())
		await tree.physics_frame
		check.call("orbit_radio_prompt", true, s1.interact_prompt(p).contains(TranslationServer.translate("E   CD player: %s").split(":")[0]))
	# The base: a hub upgrade raises the start site's stage and stays in the site's own dict.
	GameState.add_currency("cubes", BigNum.from_float(1e6))
	GameState.add_currency("parts", BigNum.from_float(1e5))
	check.call("orbit_hub_upgrade", true, (s1.get("hub") as Hub).upgrade())
	check.call("orbit_site_stage", 2, g.site_manager.levels[0] if g.site_manager else -1)
	# Lumi walks 40 m off the pad with something in the chest.
	var d: Vector3 = g.terrain.local_to_dir(g.start_cell(), 40.0, -25.0)
	p.place_on_sphere(g.terrain.ground(d), -SphereGrid.frame(d).z)
	p.compartment.fill = 3.5
	# [orbC] Two robots: one beside Lumi (near), one at the farthest hub (a far record), with cargo.
	var crew: SphereCrew = so.crews.crew
	var far_hub: int = int(g.sites[g.sites.size() - 1]["cell"])
	var nb: Dictionary = crew.spawn("scoopie", 1, g.grid.cell_at(d), g.start_cell(), "RT-near")
	nb["hopper"] = 5.25
	var fb: Dictionary = crew.spawn("haulbug", 0, far_hub, far_hub, "RT-far")
	fb["carry"] = [3.0, 4.0]
	crew.set_process(false)
	var bot_dirs: Array[Vector3] = [crew.unit_dir(nb), crew.unit_dir(fb)]
	var rad: float = g.grid.radius_m
	check.call("orbit_robot_near_far", "near far", ("near " if crew.is_near(nb) else "far ") + ("near" if crew.is_near(fb) else "far"))
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
	_freeze_crew(s2)  # [orbC] the reloaded robots must not work before the comparison
	for i: int in 5:
		await tree.process_frame
		_freeze_crew(s2)
	s2.set_meta("rt_target", s1_target)
	var b: Dictionary = _snap(s2)
	for k: String in a:
		if k == "sky_spin":  # [orbB] the reloaded sky runs a few frames before the snapshot: within 0.02
			check.call("orbit_sky_spin_within_0.02", true, absf(angle_difference(float(a[k]), float(b[k]))) <= 0.02)
			continue
		check.call("orbit_" + k, a[k], b[k])
	var crew2: SphereCrew = (s2.get("orbit") as SliceOrbit).crews.crew  # [orbC] robots back where they were
	var worst: float = INF if crew2 == null or crew2.robots().size() != 2 else 0.0
	if worst == 0.0:
		for i: int in 2:
			worst = maxf(worst, crew2.unit_dir(crew2.robots()[i]).angle_to(bot_dirs[i]) * rad)
	check.call("orbit_robot_positions_within_1m", true, worst < 1.0)
	# [orbC] Reopened from disk 2 h later: the offline jump pays what the flat game would (10%).
	if crew2 != null:
		GameState.saved_unix = Time.get_unix_time_from_system() - 7200.0
		var so2: SliceOrbit = s2.get("orbit")
		var res: Dictionary = so2.crews.restore_crew(so2, GameState.orbit, true)
		var flat: Dictionary = Offline.compute([{"type": "scoopie", "tier": 1}, {"type": "haulbug", "tier": 0}], 0, 1.0, 7200.0, INF)
		var fc: float = float(flat["cubes"]) + float(flat["waiting_value"])
		var oc: float = float(res.get("cubes", 0.0)) + float(res.get("waiting_value", 0.0))
		check.call("orbit_offline_2h_within_10pct", true, fc > 0.0 and absf(oc - fc) / fc <= 0.10)
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
