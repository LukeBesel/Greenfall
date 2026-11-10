class_name SphereCrewDev
extends RefCounted
## [orbC] Puts the phase C crew into a globe scene (the --orbit slice, scenes/slice_orbit.gd, and the
## phase A prototype --orbit=globe): a SphereCrew on the start hub plus the Command-view picker, and the dev checks.
## Dev flags (with --orbit):
##   --robots=scoopie:3,haulbug:2@1   robots at the start hub (count, optional tier after @);
##                                    prints the [bots] table before --quit-after
##   --orbit-far-crew[=N]             3 Scoopies + 1 Haul Bug at hub site N (default 1, ~1.7 km
##                                    away); prints the far shell's colour there before --quit-after
##   --bot-motion                     with --quit-after: [motion] jitter / building-overlap report
##   --offline-jump[=S]               offline jump of S seconds (default 7200) for the --robots
##                                    fleet: flat Offline.compute vs SphereOffline.simulate, PASS
##                                    within 10%, and the cells it cleaned


## The globe's planet id (OrbitPlanet.spec, GlobeSpec.of), Verdance for the phase A scene.
static func planet_of(src: Object) -> String:
	var sp: Variant = src.get("spec")
	return str((sp as Dictionary).get("id", "verdance")) if sp is Dictionary else "verdance"


static func wanted() -> bool:
	return DevHooks.has("robots") or DevHooks.has("orbit-far-crew") or DevHooks.has("offline-jump")


## `src` = the globe (OrbitPlanet in the slice, VerdanceGlobe in the phase A scene): grid, cells,
## field, surface, swarm, streamer, junk_view, sites. `write_cell` (optional) is called for each
## cell the crew works (the survey / planet % bookkeeping). The crew's dev robots come from flags.
static func install(src: Object, parent: Node, lumi: Node3D, cam: SphereCam, write_cell: Callable = Callable()) -> SphereCrew:
	var crew := SphereCrew.new()
	crew.name = "SphereCrew"
	crew.setup(src.grid, src.cells, src.field, src.surface, src.swarm, src.streamer, planet_of(src))
	var start: int = int((src.sites[0] as Dictionary)["cell"])
	crew.hub_cell = start
	crew.depot_cell = start
	var dp: Node3D = parent.get("depot") as Node3D if "depot" in parent else null
	if dp != null:  # haulers drive up to the Depot itself, not the hub's centre (the pod stands there)
		var dd: Vector3 = crew.surface.up_at(dp.global_position)
		crew.depot_cell = crew.grid.cell_at(dd)
		crew.depot_points[start] = dd
	crew.junk_view = src.junk_view
	crew.world = parent
	if parent.has_method("add_cube"):
		crew.add_cube_fn = Callable(parent, "add_cube")
	crew.terrain_for_recount = src.get("terrain") as SphereTerrain
	crew.focus = lumi
	parent.add_child(crew)
	if write_cell.is_valid():
		crew.cell_worked.connect(func(c: int) -> void: write_cell.call(c))
	var cmd := SphereCommand.new()
	cmd.name = "SphereCommand"
	cmd.cam = cam
	cmd.surface = src.surface
	cmd.grid = src.grid
	cmd.crew = crew
	cmd.streamer = src.streamer
	if lumi != null and lumi.get("input") is PlayerInput:
		cmd.lumi_input = lumi.get("input")
	parent.add_child(cmd)
	var around: PackedInt32Array = (src.grid as SphereGrid).cells_around(start, 2)
	var n: int = 0
	var fleet: Array = []
	for spec: String in DevHooks.get_s("robots", "").split(",", false):
		var tier: int = int(spec.get_slice("@", 1)) if "@" in spec else 0
		var kv: String = spec.get_slice("@", 0)
		for k: int in int(kv.get_slice(":", 1)):
			crew.spawn(kv.get_slice(":", 0), tier, around[(n + 1) % around.size()], start, "Test-%d" % n)
			fleet.append({"type": kv.get_slice(":", 0), "tier": tier})
			n += 1
	if DevHooks.has("bot-motion"):
		var pr := CrewProbe.new()
		pr.name = "CrewProbe"
		pr.crew = crew
		parent.add_child(pr)
	if DevHooks.has("orbit-far-crew"):
		var si: int = clampi(int(DevHooks.get_f("orbit-far-crew", 0.0)), 0, src.sites.size() - 1)
		if si <= 1:  # a bare flag reads as "1"  # default: the hub nearest the start (~1.6-1.7 km on Verdance)
			var best: float = INF
			for i: int in range(1, src.sites.size()):
				var dm: float = (src.grid as SphereGrid).distance_m(start, int((src.sites[i] as Dictionary)["cell"]))
				if dm < best:
					best = dm
					si = i
		var far: int = int((src.sites[si] as Dictionary)["cell"])
		var far_around: PackedInt32Array = (src.grid as SphereGrid).cells_around(far, 1)
		for k: int in 4:
			crew.spawn("haulbug" if k == 3 else "scoopie", 0, far_around[k + 1], far, "Far-%d" % k)
		_far_check(src, lumi, crew, far)
	if DevHooks.has("offline-jump"):
		offline_jump(src, fleet if not fleet.is_empty() else [{"type": "scoopie", "tier": 0}, {"type": "haulbug", "tier": 0}],
			DevHooks.get_f("offline-jump", 7200.0))
	return crew


## Watches the far shell's big hex over a far hub and prints how its colour moved.
static func _far_check(src: Object, lumi: Node3D, crew: SphereCrew, far: int) -> void:
	var st: SphereStreamer = src.streamer
	var g: SphereGrid = src.grid
	var dist: float = (src.surface as SphereSurface).arc_dist(lumi.global_position, g.centers[far] * g.radius_m)
	var hubs_m: PackedStringArray = []
	for s: Dictionary in src.sites:
		hubs_m.append("%.0f" % g.distance_m(int((src.sites[0] as Dictionary)["cell"]), int(s["cell"])))
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
static func offline_jump(src: Object, fleet: Array, seconds: float) -> Dictionary:
	var start: int = int((src.sites[0] as Dictionary)["cell"])
	var flat: Dictionary = Offline.compute(fleet, 0, 1.0, seconds, INF)
	var res: Dictionary = SphereOffline.simulate(src.grid, src.cells, src.field, [{"cell": start, "robots": fleet}], seconds,
		planet_of(src))
	if src.get("junk_view") != null:
		for pid: int in res["pieces"]:
			src.junk_view.call("hide_piece", pid)
	var fc: float = float(flat["cubes"]) + float(flat["waiting_value"])
	var oc: float = float(res["cubes"]) + float(res["waiting_value"])
	var diff: float = absf(oc - fc) / maxf(fc, 0.001)
	print("[offline] %.0f s, %d robots: flat %.0f cubes (%.0f units), orbit %.0f cubes (%.0f units, %d hexes cleaned), diff %.1f%% %s" % [
		seconds, fleet.size(), fc, float(flat["units"]), oc, float(res["units"]), int(res["cells"]), diff * 100.0, "PASS" if diff <= 0.10 else "FAIL"])
	Offline.apply(res)
	return res
