class_name OrbitRoundtrip
extends RefCounted
## [orbB] Save/load round trip for the slice on the globe (tools/save_roundtrip.tscn with
## --orbit): builds state in one orbit slice, saves it to the round trip's slot, loads it into a
## second slice and compares. Grows with each ported system.

## The Ledger drop check draws its pieces from this seed: the same pick every run.
const LEDGER_DROP_SEED: int = 4471


static func _snap(s: Node) -> Dictionary:
	var g: OrbitPlanet = (s.orbit as SliceOrbit).globe
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
	var crew: SphereCrew = (s.orbit as SliceOrbit).crews.crew
	if crew:
		for u: Dictionary in crew.robots():
			bots.append("%s %s t%d hopper %.0f carry %d junk %.0f sack %.1f" % [u["name"], u["type"], int(u["tier"]), float(u["hopper"]), (u["carry"] as Array).size(),
				float(u["log"]["junk"]), SphereScrounge.carried(u)])
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
		"sites_built": str(OrbitSave.sites_to_array((s.orbit as SliceOrbit).globe.sites)),
		"hexes_paid": (GameState.orbit.get("hexes_paid", {}) as Dictionary).size(),
		"districts": JSON.stringify((s.orbit as SliceOrbit).districts.save_state()),  # stages, unlocked, visited
		"pollution": JSON.stringify((s.orbit as SliceOrbit).pollution.save_state()),  # part-cleared kinds, cost owed
		"chain": JSON.stringify((s.orbit as SliceOrbit).chain.save_state()),  # buried parts, the Assembler, its mix
		"mastery": JSON.stringify((s.orbit as SliceOrbit).mastery.save_state()),  # Lumi's hand work per kind
		"rigs": JSON.stringify((s.orbit as SliceOrbit).rigs.save_state()),  # plans, built modules, what is fitted
		"surge": JSON.stringify((s.orbit as SliceOrbit).surge.save_state()),  # the Bloom Core's charge: no gain while away
		"goals": _goals_sig(s),  # finished goals, and how often each repeating goal came round
		"mastery_shut_hexes": (s.orbit as SliceOrbit).globe.cells.shut.count(1),  # hexes robots must leave alone
		"assembler_model": (s.orbit as SliceOrbit).chain.model != null,
		"restoration": JSON.stringify((s.orbit as SliceOrbit).restoration.save_state()),
		# Looks: found pieces are global progress; what the planet has given is in its own section.
		"pieces": JSON.stringify(GameState.global.get(Looks.KEY, [])),
		"finds": JSON.stringify((s.orbit as SliceOrbit).look_finds.save_state()),
		# Source jobs: the step each city's job is at, which are shut, and the hold each puts on its city.
		"sources": JSON.stringify((s.orbit as SliceOrbit).sources.save_state()),
		"source_holds": _source_holds(s.orbit as SliceOrbit),
		"fouled_hex_dirty": g.cells.is_dirty(int(s.get_meta("rt_target", 0))),
		"fouled_hex_soiled": (s.orbit as SliceOrbit).pollution.is_soiled(int(s.get_meta("rt_target", 0))),
		"worn_set": Designs.worn_set(),
		"worn_head": str(LumiStyle.current()["head"]),
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
		"sky_spin": (s.get("sky_director") as SkyDirector).spin if s.get("sky_director") is SkyDirector else -1.0,  # [orbE] compared within 0.05 rad
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


static func _outpost_levels(s: Node) -> Array:
	var out: Array = []
	var op: Outposts = s.get("outposts") as Outposts
	if op:
		for o: Outpost in op.items:
			out.append(o.level)
	return out


## [orbC] Stops a slice's robot crew (the brain and every real robot) so state compares as saved.
static func _freeze_crew(s: Node) -> void:
	var so: SliceOrbit = s.orbit
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
	var cells: Dictionary = gdn.persist().get("cells", {})
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
		# A fixed seed and a pick that reaches the volume: an unseeded pick among small pieces hits
		# the 14-piece cap first, leaves the hex clean and failed the next check now and then.
		var drop_rng := RandomNumberGenerator.new()
		drop_rng.seed = LEDGER_DROP_SEED
		cands.sort()
		var drop: Dictionary = LedgerArc.pick_dirtying_drop(g.field, cands, drop_rng)
		var hid: int = int(drop.get("hex", -1))
		var pids: PackedInt32Array = drop.get("pieces", PackedInt32Array())
		check.call("orbit_ledger_drop_pick", true, hid >= 0)
		if hid >= 0:
			var drops0: int = int(GameState.stats.get("ledger_drops", 0))
			lg._release(hid, pids, lg._marker(lg.to_local(g.field.hex_center(hid)), Color.RED))
			check.call("orbit_ledger_drop_dirties_cell", "0 0 true", "%d %d %s" % [g.field.hex_clean[hid], g.cells.state[hid], str(g.cells.junk[hid] > 0.0)])
			await tree.create_timer(2.2).timeout  # [v1world] denser cells drop up to 14 pieces (~1.9 s)
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
	var h1: Vector3 = g.terrain.ground(g.grid.centers[int(g.sites[1]["cell"])])
	var sp1: SitePrefab = g.site_manager.build_hub(1, true)  # [v4world] the frame wakes a hub once its town is built (as a walk or a hop gets it)
	if not sp1.is_built:
		await sp1.rebuilt
	p.place_on_sphere(h1, p.forward())
	hf.check_now()
	check.call("orbit_fauna_frame_hops", 1, hf.hub)
	check.call("orbit_fauna_rebuilt_at_hub", true, hf.node("Fauna") != null and hf.node("Fauna") != fa)
	var eg1: EasterEggs = hf.node("EasterEggs") as EasterEggs
	var op1: Outposts = hf.node("Outposts") as Outposts
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
	for i: int in 3:
		await tree.process_frame


## B43: the start site's prefab is freed when Lumi flies away and built anew when she comes back.
## The yard's models stood on it and were never built again: Camp drove freed nodes (a script
## error at every base level-up or yard build after a trip) and the bench was gone. Now Camp has
## no bits while the site is away, and the bench and the yard models stand on the new prefab.
static func _yard_trip_check(tree: SceneTree, s: Node, so: SliceOrbit, check: Callable) -> void:
	var sm: SiteManager = so.globe.site_manager
	var camp: Camp = s.get("camp")
	if sm == null or sm.prefab(0) == null or camp == null:
		check.call("orbit_yard_survives_a_trip", "the start site and its camp", "none")
		return
	var shown_before: Array[String] = camp.standing()
	sm.free_hub(0)
	await tree.process_frame
	await tree.process_frame
	var bits_ok: bool = true
	for k: Variant in (s.get("_ruin_bits") as Dictionary):
		bits_ok = bits_ok and is_instance_valid((s.get("_ruin_bits") as Dictionary)[k])
	check.call("orbit_yard_bits_valid_while_away", true, bits_ok)
	camp.rebind_yard()  # what a base level-up does while the start site is away
	var p: SitePrefab = sm.build_hub(0, true)
	for i: int in 600:
		if p.is_built:
			break
		await tree.process_frame
	await tree.process_frame  # the rebuild of the yard on site_built
	var bits: Dictionary = s.get("_ruin_bits")
	var bench: Node3D = bits.get("bench") as Node3D
	var on_new: bool = bench != null and is_instance_valid(bench) and p.is_ancestor_of(bench)
	for k: Variant in bits:
		on_new = on_new and is_instance_valid(bits[k]) and p.is_ancestor_of(bits[k] as Node)
	check.call("orbit_yard_rebuilt_on_the_new_site", true, on_new)
	camp.rebind_yard()
	check.call("orbit_yard_shows_what_was_built", str(shown_before), str(camp.standing()))
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
	# [v4grow] #48/#55: the tin is reachable and seen (nothing in the footprint, open sky), and the
	# seed step's beacon stands on it once its signal is in.
	var bl: Array[String] = fs.blockers()
	check.call("orbit_greenhouse_clear", "[]", str(bl))
	var ob: Objectives = s.get("objectives") as Objectives
	if ob:
		var sig0: Variant = GameState.flags.get("seed_signal", false)
		var unl0: Variant = GameState.flags.get("seeds_unlocked", false)
		GameState.flags["seed_signal"] = true
		GameState.flags.erase("seeds_unlocked")
		var bt: Variant = ob.step_target({"id": "seed"}).get("pos", null)
		check.call("orbit_seed_beacon_on_tin", true, bt is Vector3 and (bt as Vector3).distance_to(fs._tin.global_position) < 0.6)
		GameState.flags["seed_signal"] = sig0
		GameState.flags["seeds_unlocked"] = unl0
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
	var region0: PackedInt32Array = g.grid.cells_around(g.start_cell(), HubFrame.AREA_RINGS)
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
	var so: SliceOrbit = s1.orbit
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
			if gi.is_in_group("see_through"):  # [v2feel] the pod's smoke plume fades out near the camera
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
	OrbitBeaconCheck.run(s1, so, check)  # [v2guide] every beacon on its object (playtest 2 #33)
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
	# [v4grow] Planting stays off streets, kerbs and the pad: if this cell is all paving, clean a
	# nearby cell with open ground and plant there.
	if gdn.free_slot_near(ctr - fwd * 1.0, fwd, 6.0) < 0:
		for c2: int in g.field.hexes_near(ctr, 3):
			if g.field.hex_hub[c2] != 0 or g.field.is_water(c2):
				continue
			so.crews.work_cell(c2, 0.0)
			gdn.ensure_hex(c2)
			var c2p: Vector3 = g.field.hex_center(c2)
			if gdn.free_slot_near(c2p - fwd * 1.0, fwd, 6.0) >= 0:
				var open_n: int = 0
				for sl2: int in gdn.hex_slots.get(c2, PackedInt32Array()):
					open_n += 1 if gdn.plantable(sl2) and gdn.slot_pos[sl2].distance_to(c2p) < 6.0 else 0
				if open_n >= 3:
					ctr = c2p
					break
	var planted_n: int = 0
	for k: int in 3:
		var sl: int = gdn.free_slot_near(ctr - fwd * 1.0, fwd, 6.0)
		if sl >= 0 and gdn.plant(sl):
			gdn.water(sl, 120.0)
			planted_n += 1
	check.call("orbit_garden_planted", 3, planted_n)
	check.call("orbit_garden_slots_on_ground", true, gdn.slot_pos.size() > 0 and absf(gdn.slot_pos[0].length() - (g.grid.radius_m + g.terrain.height(gdn.slot_pos[0].normalized()))) < 0.05)
	# [v4grow] #51: the planted cell reads from Lumi's camera (mounds, a ring on the cell, real-size
	# plants once grown).
	var gm: GardenMarks = s1.get_node_or_null("GardenMarks") as GardenMarks
	if gm:
		gm._refresh()
	check.call("orbit_garden_marks", "planted 3 rings 1", "planted %d rings %d" % [int(gm.shown["planted"]), int(gm.shown["rings"])] if gm else "none")
	var big: bool = true
	for sl: int in gdn.planted_slots():
		var st0: int = gdn.slot_stage[sl]
		gdn.slot_stage[sl] = 4
		var vs: Array = PlantParts.variants(str(gdn.species[gdn.slot_species[sl]]["model"]), Garden.VARIANT_TRIS)
		var sz: Vector3 = (vs[gdn._variant_of(sl)] as Mesh).get_aabb().size * gdn.globe_scale(sl)
		big = big and (sz.y >= 0.4 or maxf(sz.x, sz.z) >= 1.0)
		gdn.slot_stage[sl] = st0
	check.call("orbit_garden_blooms_read", true, big)
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
		ob.set_process(false)  # [v1guide] every step now outlines its own dirty hex: hold it still for the check
		for i: int in 600:  # [v1guide] the outline fades out its old hex before it moves: wait for the move (+ a few frames)
			ob.outline.set_hex(oc)  # [main] a goal finishing by signal (not _process) can clear it mid-wait on slow runners: keep it pinned
			await tree.process_frame
			if i >= 40 and ob.outline.hex == oc:
				break
		var aabb: AABB = (ob.outline.get_child(0) as MeshInstance3D).get_aabb() if ob.outline.get_child_count() > 0 else AABB()
		check.call("orbit_outline_on_cell", true, ob.outline.global_position.distance_to(g.field.hex_center(oc)) < 0.5)
		check.call("orbit_outline_cell_sized", true, aabb.size.x > 12.0 and aabb.size.x < 24.0 and absf(aabb.size.y) < 3.0)
		ob.set_process(true)
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
	check.call("orbit_bench_prompt", TranslationServer.translate("E   Fix the workbench"), s1.interact_prompt(p))
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
	# Looks: a find taken from the planet, a second piece found, and a mixed look worn.
	var first_find: Dictionary = so1.look_finds.entries()[0]
	check.call("orbit_find_taken", true, so1.look_finds.take(str(first_find["id"])))
	# The finds standing in the world: a wreck salvaged by hand, another with one piece of junk
	# pulled off, and a buried find lying in cleared soil. All three must come back as they were.
	var wreck_ids: Array[String] = so1.find_sites.wreck_ids()
	var wreck_pieces: int = (so1.look_finds.entry(wreck_ids[0])["pieces"] as Array).size()
	so1.look_finds.set_cleared(wreck_ids[0], int(so1.find_sites.cfg("junk")))
	check.call("orbit_wreck_salvaged", true, so1.look_finds.take(wreck_ids[0]))
	so1.look_finds.set_cleared(wreck_ids[1], 1)
	var lying: String = _second_buried(so1)
	check.call("orbit_buried_find_surfaced", true, so1.look_finds.surface(lying, so1.cell_at(p.global_position)))
	# Source jobs: one city's source is shut down (one that gives no piece, so the piece counts
	# below stay what they were); its city is no longer held, the others are.
	var shut_city: String = _city_without_source_find(so1)
	check.call("orbit_source_shut", true, shut_city != "" and so1.sources.force_shut(shut_city))
	check.call("orbit_source_hold_lifted", Districts.MAX_STAGE, so1.districts.stage_cap_of(shut_city))
	Looks.grant("head_halo", "secret")
	var look: Dictionary = LumiStyle.current()
	LumiStyle.wear_piece(look, "head_halo")
	LumiStyle.set_current(look)
	check.call("orbit_pieces_in_global", true, Looks.has(str((first_find["pieces"] as Array)[0])) and Looks.has("head_halo"))
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
	GameState.flags["bench_tier"] = maxi(int(GameState.flags.get("bench_tier", 1)), 2)  # base level 2 waits for the Bot Bay
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
	# The robot chain: the Assembler stands with a mix of the player's and a robot half built, a
	# hex holds buried parts, a Scrounger has brought a fraction of a Part home.
	var rc: RobotChain = so.chain
	rc.chain.offered = true
	check.call("orbit_assembler_built", true, rc.build())
	rc.set_weight("scoopie", 7)
	rc.chain.current = "scoopie"
	rc.chain.progress_s = rc.chain.assembly_s() * 0.5
	rc.set_paused(true)
	rc.chain.seed_cell(far_hub, "")
	rc.chain.take(far_hub, 0.25)
	rc.chain.deliver(0.25)
	nb["parts"] = 3.0
	# Mastery: Lumi has learnt the base kind to the level where robots work at their own rate (the
	# offline check below compares against that rate), and has made a start on every other kind.
	var mastery: Mastery = so.mastery
	var base_kind: String = so.pollution.base_id()
	mastery.grant(base_kind, int(mastery.config()["dev_level"]))
	for id: String in mastery.kinds():
		if id != base_kind:
			mastery.add_work(id, 12.5)
	check.call("orbit_mastery_base_level", int(mastery.config()["dev_level"]), mastery.level(base_kind))
	# Rigs: one module of every slot is built and fitted, so the snapshot compares a real rig
	# (plans, built modules, what is fitted) and not an empty one.
	var rig_fitted: int = 0
	for slot: String in so.rigs.slots():
		var slot_modules: Array[String] = so.rigs.modules_of(slot)
		if not slot_modules.is_empty():
			so.rigs.grant(slot_modules[0])
			rig_fitted += 1 if so.rigs.is_fitted(slot_modules[0]) else 0
	check.call("orbit_rig_fitted_every_slot", so.rigs.slots().size(), rig_fitted)
	# Surge: a part-charged Bloom Core, so the snapshot compares a real charge. The time away that
	# this round trip plays through must add nothing to it.
	GameState.stats["robots_built"] = maxi(int(GameState.stats.get("robots_built", 0)), 1)  # the Surge opens with the first robot
	so.surge.add_share(0.05)
	check.call("orbit_surge_part_charged", true, so.surge.charge() > 0.0 and so.surge.charge() < 1.0)
	# Goals: pay every goal that already holds and bring one repeating goal round, so the snapshot
	# compares finished goals and a repeat count, and the reloaded game has nothing left to pay.
	var goals: Goals = s1.get("goals")
	var settle: int = goals.chain.size()
	while goals.check() >= 0 and settle > 0:
		settle -= 1
	var repeating: int = -1
	for gi: int in goals.chain.size():
		if goals.is_repeat(gi) and goals.is_offered(gi) and repeating < 0:
			repeating = gi
	if repeating >= 0:
		goals.complete(repeating)
	check.call("orbit_goals_one_per_tier", goals.tier_ids().size(), goals.current().size())
	check.call("orbit_goal_repeat_counted", 1, goals.times_done(repeating) if repeating >= 0 else 0)
	var bot_dirs: Array[Vector3] = [crew.unit_dir(nb), crew.unit_dir(fb)]
	var rad: float = g.grid.radius_m
	check.call("orbit_robot_near_far", "near far", ("near " if crew.is_near(nb) else "far ") + ("near" if crew.is_near(fb) else "far"))
	# A running source fouls the hex Lumi cleaned again: it lies dirty with its own pieces, keeps
	# its level, and the save keeps what it showed before (the "pollution" snapshot).
	var fouled_hex: int = int(s1.get_meta("rt_target", -1))
	if fouled_hex >= 0 and g.cells.is_dirty(fouled_hex):  # a Ledger drone may have dumped on it since: clean it first
		so.crews.work_cell(fouled_hex, 0.0)
	check.call("orbit_source_fouled_hex", true, fouled_hex >= 0 and so.pollution.soil(fouled_hex, so.pollution.base_id(), 0.3) > 0.0)
	check.call("orbit_fouled_hex_is_dirty", true, fouled_hex >= 0 and g.cells.is_dirty(fouled_hex) and so.pollution.is_soiled(fouled_hex))
	for i: int in 3:
		await tree.physics_frame
	# B42: where the rocket stands and that Lumi owns it are kept by every save (a save dropped
	# both, so the rocket went back to the start pad while Lumi worked in another city).
	GameState.orbit["rocket_site"] = 0
	GameState.orbit["rocket_owned"] = true
	# M3-22: a city's field bench, once set up, stays set up.
	var bench_city: String = ""
	if so.field_benches != null:
		for id: String in so.districts.ids():
			if so.field_benches.rules.has_site(id):
				bench_city = id
				break
		so.field_benches.rules.load_state({"set_up": [bench_city]}, true)
	var ok: bool = SaveManager.save_game()
	check.call("orbit_saved", true, ok)
	check.call("orbit_save_keeps_the_rocket", "site 0 owned true", "site %s owned %s" % [str(GameState.orbit.get("rocket_site", "none")),
		str(GameState.orbit.get("rocket_owned", "none"))])
	var a: Dictionary = _snap(s1)
	var disk: Dictionary = SaveManager.read_dict(SaveManager.slot_path())
	check.call("orbit_flat_world_untouched", false, (disk.get("world", {}) as Dictionary).has("hub_level"))
	check.call("orbit_pieces_saved_in_global_section", 2 + wreck_pieces, (((disk.get("global", {}) as Dictionary).get(Looks.KEY, []) as Array)).size())
	check.call("orbit_pieces_not_in_planet_section", false, JSON.stringify(disk.get("orbit", {})).contains("head_halo"))
	check.call("orbit_hub_world_saved", 2, int((((disk.get("orbit", {}) as Dictionary).get("hub_worlds", {}) as Dictionary).get("0", {}) as Dictionary).get("hub_level", 0)))
	var s1_target: int = int(s1.get_meta("rt_target", -1))
	check.call("orbit_save_has_no_flat_xz", false, JSON.stringify(GameState.orbit.get("lumi", {})).contains("\"pos\""))
	await _yard_trip_check(tree, s1, so, check)
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
		if k == "sky_spin":  # [orbB] the reloaded sky runs a few frames before the snapshot: within 0.05
			check.call("orbit_sky_spin_within_0.05", true, absf(angle_difference(float(a[k]), float(b[k]))) <= 0.05)
			continue
		check.call("orbit_" + k, a[k], b[k])
	var fb2: FieldBenchSites = (s2.orbit as SliceOrbit).field_benches
	check.call("orbit_field_bench_kept", true, bench_city != "" and fb2 != null and fb2.rules.is_set_up(bench_city))
	var finds2: Finds = (s2.orbit as SliceOrbit).look_finds
	var sites2: FindSites = (s2.orbit as SliceOrbit).find_sites
	check.call("orbit_wreck_stays_salvaged", true, finds2.is_taken(wreck_ids[0]) and sites2.junk_left(wreck_ids[0]) == 0)
	check.call("orbit_wreck_not_salvaged_twice", false, finds2.take(wreck_ids[0]))
	check.call("orbit_wreck_junk_pulled_kept", int(sites2.cfg("junk")) - 1, sites2.junk_left(wreck_ids[1]))
	check.call("orbit_buried_find_still_lies", true, finds2.surfaced_finds().has(lying) and not finds2.is_taken(lying))
	var crew2: SphereCrew = (s2.orbit as SliceOrbit).crews.crew  # [orbC] robots back where they were
	var worst: float = INF if crew2 == null or crew2.robots().size() != 2 else 0.0
	if worst == 0.0:
		for i: int in 2:
			worst = maxf(worst, crew2.unit_dir(crew2.robots()[i]).angle_to(bot_dirs[i]) * rad)
	check.call("orbit_robot_positions_within_1m", true, worst < 1.0)
	# [orbC] Reopened from disk 2 h later: the offline jump cleans what the flat game would (10%).
	if crew2 != null:
		GameState.saved_unix = Time.get_unix_time_from_system() - 7200.0
		var so2: SliceOrbit = s2.orbit
		var res: Dictionary = so2.crews.restore_crew(so2, GameState.orbit, true)
		var flat: Dictionary = Offline.compute([{"type": "scoopie", "tier": 1}, {"type": "haulbug", "tier": 0}], 0, 1.0, 7200.0, INF)
		# Robots earn no cubes: the time away is compared in units cleaned, and pays nothing.
		var fc: float = float(flat["units"])
		var oc: float = float(res.get("units", 0.0))
		check.call("orbit_offline_2h_within_10pct", true, fc > 0.0 and absf(oc - fc) / fc <= 0.10)
		check.call("orbit_offline_pays_no_cubes", 0.0, float(res.get("cubes", 0.0)) + float(res.get("waiting_value", 0.0)))
	s2.queue_free()
	await tree.process_frame
	await _old_save(tree, packed, check)
	_old_crew_looks(check)


## A version 5 save from before Glim's and the crew's looks were found pieces keeps what it had
## (tests/fixtures/saves/crew_looks_v5.json), and keeps it through a save and a load.
static func _old_crew_looks(check: Callable) -> void:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/saves/crew_looks_v5.json"))
	check.call("old_crew_looks_fixture", true, d is Dictionary)
	if not (d is Dictionary):
		return
	(d as Dictionary).erase("_doc")
	SaveManager.write_dict(SaveManager.slot_path(), d)
	GameState.new_game()
	check.call("old_crew_looks_loads", true, SaveManager.load_game())
	var kept: Array[String] = ["glim_shell_sunset", "glim_top_beanie", "glim_glow_ember", "glim_top_sprout", "crew_treads", "crew_top_hat",
		"crew_livery_neon", "crew_glow_mint"]
	var have := func() -> bool:
		for id: String in kept:
			if not Looks.has(id):
				return false
		return true
	check.call("old_crew_looks_kept", true, have.call())
	check.call("old_crew_looks_not_given", false, Looks.has("glim_shell_moss") or Looks.has("crew_big_eye"))
	check.call("old_crew_looks_glim_worn", "sunset/ember/sprout", "%s/%s/%s" % [Glim.worn("shells"), Glim.worn("glows"), Glim.worn("tops")])
	check.call("old_crew_looks_design_worn", "treads", str(RobotDesign.parts("scoopie").get("mobility", "")))
	check.call("old_crew_looks_saved", true, SaveManager.save_game())
	GameState.new_game()
	SaveManager.load_game()
	check.call("old_crew_looks_reload_kept", true, have.call())
	check.call("old_crew_looks_reload_glim_worn", "sunset", Glim.worn("shells"))


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
	var so: SliceOrbit = s.orbit
	var g: OrbitPlanet = so.globe
	check.call("orbit_old_migrated", "flat_v%d" % GameState.SAVE_VERSION, str(GameState.orbit.get("migrated", "")))
	# A save from before found pieces keeps what it had: the colours that were free are pieces now.
	check.call("orbit_old_keeps_its_free_colours", true, Looks.has("tin_graphite") and Looks.has("tin_slate") and Looks.has("chip_orange"))
	check.call("orbit_old_look_still_wearable", true, LumiStyle.allowed(LumiStyle.current()))
	check.call("orbit_old_has_no_unearned_design", false, Designs.is_collected("sprout") or Designs.is_collected("bolt"))
	var old_pieces: String = JSON.stringify(GameState.global.get(Looks.KEY, []))
	check.call("orbit_old_base_level", 2, OrbitSave.hub_level({"hubs": so.hub_states}, 0))
	var clean_cells: int = 0
	for c: int in g.cells.n:
		if g.cells.state[c] == 1 and not g.cells.has_flag(c, SphereCells.F_HUB):
			clean_cells += 1
	check.call("orbit_old_cells_cleaned", true, clean_cells >= 9)
	# A save from before the robot chain: its clean ground is spent, nothing is built or on offer.
	check.call("orbit_old_chain_ground_spent", true, so.chain.chain.seeded.size() >= clean_cells and so.chain.chain.stock_total() == 0.0)
	check.call("orbit_old_chain_no_assembler", false, so.chain.is_built() or so.chain.listed())
	# A save from before mastery: its clean hexes count as Lumi's work on the base kind, so a crew
	# built on it is not shut out.
	var old_base: String = so.pollution.base_id()
	check.call("orbit_old_mastery_from_clean_hexes", true, so.mastery.level(old_base) >= 1 and so.mastery.robots_can_work(old_base))
	var old_level: int = so.mastery.level(old_base)
	# A save from before source jobs: no city of it was at the gated stage, so every source still
	# runs, every city is held one stage short, and nothing was paid.
	var old_gate: int = so.sources.gates_stage()
	check.call("orbit_old_sources_all_running", 0, so.sources.shut_count())
	for id: String in so.sources.ids():
		check.call("orbit_old_source_holds_%s" % id, old_gate - 1, so.districts.stage_cap_of(id))
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
	var g2: OrbitPlanet = (s2.orbit as SliceOrbit).globe
	check.call("orbit_old_reload_cells", hash(cd["state"]), hash(g2.cells.to_dict()["state"]))
	check.call("orbit_old_reload_base_level", 2, OrbitSave.hub_level({"hubs": (s2.orbit as SliceOrbit).hub_states}, 0))
	check.call("orbit_old_reload_cubes", cubes0, GameState.get_currency("cubes").to_float())
	check.call("orbit_old_reload_pieces", old_pieces, JSON.stringify(GameState.global.get(Looks.KEY, [])))
	check.call("orbit_old_reload_mastery", old_level, (s2.orbit as SliceOrbit).mastery.level(old_base))
	s2.queue_free()
	await tree.process_frame


## The goals as saved: ids of the finished ones and the count of each repeating one.
static func _goals_sig(s: Node) -> String:
	var done: Array = (GameState.flags.get(Goals.FLAG_DONE, []) as Array).duplicate()
	done.sort()
	var goals: Goals = s.get("goals")
	var counts: Dictionary = {}  # a JSON reload reads whole numbers back as floats
	var saved: Dictionary = (GameState.flags.get(Goals.FLAG_REPEAT, {}) as Dictionary).get("n", {})
	for id: Variant in saved:
		counts[str(id)] = int(saved[id])
	return "%s %s tiers %d" % [JSON.stringify(done), JSON.stringify(counts), goals.current().size() if goals else -1]


## The stage each city is held at by its source job, in play order ("5" = not held).
static func _source_holds(so: SliceOrbit) -> String:
	var out: PackedStringArray = []
	for id: String in so.districts.ids():
		out.append("%s:%d" % [id, so.districts.stage_cap_of(id)])
	return ",".join(out)


## The second buried find of the planet's table (the first is taken by the round trip).
static func _second_buried(so: SliceOrbit) -> String:
	var seen: int = 0
	for e: Dictionary in so.look_finds.entries():
		if e["where"] == Finds.BURIED:
			seen += 1
			if seen == 2:
				return str(e["id"])
	return ""


## The first city with a source job whose shutdown hands out no piece of a look ("" when none).
static func _city_without_source_find(so: SliceOrbit) -> String:
	for id: String in so.sources.ids():
		var gives: bool = false
		for e: Dictionary in so.look_finds.entries():
			gives = gives or (e["where"] == Finds.SOURCE and e["district"] == id)
		if not gives:
			return id
	return ""
