class_name SphereCrewDev
extends RefCounted
## [orbC] Puts the phase C crew into a globe scene (the phase A --orbit scene now, the --orbit slice
## once B1 lands): a SphereCrew on the start hub plus the Command-view picker, and the dev checks.
## Dev flags (with --orbit):
##   --robots=scoopie:3,haulbug:2@1   robots at the start hub (count, optional tier after @);
##                                    prints the [bots] table before --quit-after
##   --orbit-far-crew[=N]             3 Scoopies + 1 Haul Bug at hub site N (default 1, ~1.7 km
##                                    away); prints the far shell's colour there before --quit-after
##   --offline-jump[=S]               offline jump of S seconds (default 7200) for the --robots
##                                    fleet: flat Offline.compute vs SphereOffline.simulate, PASS
##                                    within 10%, and the cells it cleaned
## `world` needs: grid, cells, field, surface, swarm, streamer, junk_view, lumi, cam, sites.


static func wanted() -> bool:
	return DevHooks.has("robots") or DevHooks.has("orbit-far-crew") or DevHooks.has("offline-jump")


static func install(world: Node) -> SphereCrew:
	var crew := SphereCrew.new()
	crew.name = "SphereCrew"
	crew.setup(world.grid, world.cells, world.field, world.surface, world.swarm, world.streamer, str(world.get("planet_id") if world.get("planet_id") != null else "verdance"))
	var start: int = int((world.sites[0] as Dictionary)["cell"])
	crew.hub_cell = start
	crew.depot_cell = start
	crew.junk_view = world.junk_view
	crew.focus = world.lumi
	world.add_child(crew)
	if world.has_method("_write_cell"):
		crew.cell_worked.connect(func(c: int) -> void: world.call("_write_cell", c))
	var cmd := SphereCommand.new()
	cmd.name = "SphereCommand"
	cmd.cam = world.cam
	cmd.surface = world.surface
	cmd.grid = world.grid
	cmd.crew = crew
	cmd.streamer = world.streamer
	world.add_child(cmd)
	var around: PackedInt32Array = (world.grid as SphereGrid).cells_around(start, 2)
	var n: int = 0
	var fleet: Array = []
	for spec: String in DevHooks.get_s("robots", "").split(",", false):
		var tier: int = int(spec.get_slice("@", 1)) if "@" in spec else 0
		var kv: String = spec.get_slice("@", 0)
		for k: int in int(kv.get_slice(":", 1)):
			crew.spawn(kv.get_slice(":", 0), tier, around[(n + 1) % around.size()], start, "Test-%d" % n)
			fleet.append({"type": kv.get_slice(":", 0), "tier": tier})
			n += 1
	if DevHooks.has("orbit-far-crew"):
		var si: int = clampi(int(DevHooks.get_f("orbit-far-crew", 0.0)), 0, world.sites.size() - 1)
		if si <= 1:  # a bare flag reads as "1"  # default: the hub nearest the start (~1.6-1.7 km on Verdance)
			var best: float = INF
			for i: int in range(1, world.sites.size()):
				var dm: float = (world.grid as SphereGrid).distance_m(start, int((world.sites[i] as Dictionary)["cell"]))
				if dm < best:
					best = dm
					si = i
		var far: int = int((world.sites[si] as Dictionary)["cell"])
		var far_around: PackedInt32Array = (world.grid as SphereGrid).cells_around(far, 1)
		for k: int in 4:
			crew.spawn("haulbug" if k == 3 else "scoopie", 0, far_around[k + 1], far, "Far-%d" % k)
		_far_check(world, crew, far)
	if DevHooks.has("offline-jump"):
		offline_jump(world, fleet if not fleet.is_empty() else [{"type": "scoopie", "tier": 0}, {"type": "haulbug", "tier": 0}],
			DevHooks.get_f("offline-jump", 7200.0))
	return crew


## Watches the far shell's big hex over a far hub and prints how its colour moved.
static func _far_check(world: Node, crew: SphereCrew, far: int) -> void:
	var st: SphereStreamer = world.streamer
	var g: SphereGrid = world.grid
	var dist: float = (world.surface as SphereSurface).arc_dist(world.lumi.global_position, g.centers[far] * g.radius_m)
	var hubs_m: PackedStringArray = []
	for s: Dictionary in world.sites:
		hubs_m.append("%.0f" % g.distance_m(int((world.sites[0] as Dictionary)["cell"]), int(s["cell"])))
	print("[bots] hub distances from the start (m): %s; far crew at hub %d" % [", ".join(hubs_m), far])
	# Big hexes of the far shell the far crew works in, with their colour before the work.
	var before: Dictionary = {}
	var px: Callable = func(big: int) -> Color:
		@warning_ignore("integer_division")
		return st.shell._img_a.get_pixel(big % SphereShell.TEX_W, big / SphereShell.TEX_W)
	crew.cell_worked.connect(func(c: int) -> void:
		if st.shell == null or g.distance_m(c, far) > 600.0:
			return
		var big: int = st.shell.owner_of(c)
		if not before.has(big):
			before[big] = px.call(big))
	crew.reporting.connect(func() -> void:
		st.shell.update(1.0, 0.0)
		var drop: float = 0.0
		var greener: float = 0.0
		for big: int in before:
			var c1: Color = px.call(big)
			drop = maxf(drop, (before[big] as Color).r - c1.r)
			greener = maxf(greener, c1.g - (before[big] as Color).g)
		var far_n: int = crew.units.size() - crew.near_count()
		var ok: bool = drop > 0.001 and far_n >= 4
		print("[bots] far crew: hub %d at %.0f m from Lumi, %d far robots, %d far-shell big hexes worked, junk down by up to %.3f, clean up by up to %.3f %s" % [
			far, dist, far_n, before.size(), drop, greener, "PASS" if ok else "FAIL"]))


## The offline jump on the globe vs the flat game, for one fleet at the start hub.
static func offline_jump(world: Node, fleet: Array, seconds: float) -> Dictionary:
	var start: int = int((world.sites[0] as Dictionary)["cell"])
	var flat: Dictionary = Offline.compute(fleet, 0, 1.0, seconds, INF)
	var res: Dictionary = SphereOffline.simulate(world.grid, world.cells, world.field, [{"cell": start, "robots": fleet}], seconds,
		str(world.get("planet_id") if world.get("planet_id") != null else "verdance"))
	if world.get("junk_view") != null:
		for pid: int in res["pieces"]:
			world.junk_view.call("hide_piece", pid)
	var fc: float = float(flat["cubes"]) + float(flat["waiting_value"])
	var oc: float = float(res["cubes"]) + float(res["waiting_value"])
	var diff: float = absf(oc - fc) / maxf(fc, 0.001)
	print("[offline] %.0f s, %d robots: flat %.0f cubes (%.0f units), orbit %.0f cubes (%.0f units, %d hexes cleaned), diff %.1f%% %s" % [
		seconds, fleet.size(), fc, float(flat["units"]), oc, float(res["units"]), int(res["cells"]), diff * 100.0, "PASS" if diff <= 0.10 else "FAIL"])
	Offline.apply(res)
	return res
