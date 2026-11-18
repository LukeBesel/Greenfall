class_name LifeDev
extends RefCounted
## [v6life] Dev hooks for the "life returns" layers (renders and tests of cleaned ground):
##   --life-clean=RINGS[,LEVEL|ramp[,X,Z]]  cleans every land cell within RINGS cells of Lumi (or of the
##       point X,Z metres from the start cell) the quiet way a robot would, and gives each the hex
##       level LEVEL (1 Clean .. 5 Thriving; default 1). Hub ground stays as it is.
##   --life-clean-at=S                 does it S seconds into play instead of at once (the grow-in).
##   --life-grown                      green jumps to its target instead of growing in.
##   --life-off                        none of the v6life layers (the "before" render).
##   --life-report                     prints a [life] line every few seconds.
##   --life-tour=PREFIX --life-tour-stops="x,z,yaw_deg,time,wait_s[,cam_dist[,cam_pitch]];..."
##       several screenshots from one run (a render costs minutes of loading here): once the world is
##       up, Lumi is put at each stop (metres from the start cell), the local time is set, and after
##       wait_s seconds PREFIX_<k>.png is saved. Quits after the last stop.
##   --life-land                       prints where open land lies round the start town.


static func attach(so: Node) -> void:
	if DevHooks.has("life-clean"):
		var at: float = DevHooks.get_f("life-clean-at", 0.0)
		if at > 0.0:
			so.get_tree().create_timer(at).timeout.connect(func() -> void: apply_clean(so))
		else:
			apply_clean(so)
	if DevHooks.has("life-land"):  # where open land lies round the start town (for --orbit-spawn)
		var globe: OrbitPlanet = so.get("globe")
		for d: float in [170.0, 230.0]:
			for a: int in 8:
				var x: float = sin(a * PI / 4.0) * d
				var z: float = -cos(a * PI / 4.0) * d
				var land: int = 0
				var site: int = 0
				var around: PackedInt32Array = globe.grid.cells_around(globe.grid.cell_at(globe.terrain.local_to_dir(globe.start_cell(), x, z)), 4)
				for c: int in around:
					land += 1 if globe.cells.state[c] != 5 else 0
					site += 1 if globe.cells.has_flag(c, SphereCells.F_SITE) else 0
				print("[life] land at %d,%d: %d of %d cells (%d site)" % [int(x), int(z), land, around.size(), site])
	if DevHooks.has("life-tour"):
		tour(so)
	if DevHooks.has("life-report"):
		var t := Timer.new()
		t.wait_time = 5.0
		t.autostart = true
		so.add_child(t)
		t.timeout.connect(func() -> void: print("[life] ", report(so)))


static func apply_clean(so: Node) -> int:
	var n: int = 0
	for one: String in DevHooks.get_s("life-clean", "3").split(";", false):  # several areas: "8,2;5,ramp,162,-162"
		n += _clean_one(so, one)
	return n


static func _clean_one(so: Node, one: String) -> int:
	var spec: PackedStringArray = one.split(",")
	var rings: int = int(spec[0])
	var ramp: bool = spec.size() > 1 and spec[1] == "ramp"  # Thriving in the middle down to Clean at the rim
	var level: int = clampi(int(spec[1]), 1, 5) if spec.size() > 1 and not ramp else 1
	var globe: OrbitPlanet = so.get("globe")
	var w: Node = so.get("w")
	var patch: Variant = w.get("patch")
	var centre: int = globe.cell_at((patch as Node3D).global_position) if patch is Node3D else globe.start_cell()
	if spec.size() > 3:
		centre = globe.grid.cell_at(globe.terrain.local_to_dir(globe.start_cell(), float(spec[2]), float(spec[3])))
	var n: int = 0
	if ramp:
		var seen: Dictionary = {}
		for k: int in range(0, rings + 1):
			var ring := PackedInt32Array()
			for c: int in globe.grid.cells_around(centre, k):
				if not seen.has(c):
					seen[c] = true
					ring.append(c)
			@warning_ignore("integer_division")
			n += clean_cells(so, ring, clampi(5 - k * 5 / (rings + 1), 1, 5))
	else:
		n = clean_cells(so, globe.grid.cells_around(centre, rings), level)
	print("[life] cleaned %d cells to level %s" % [n, "ramp" if ramp else str(level)])
	return n


## Cleans the given cells (quietly) and sets their hex level. Returns how many it touched.
static func clean_cells(so: Node, list: PackedInt32Array, level: int) -> int:
	var globe: OrbitPlanet = so.get("globe")
	var w: Node = so.get("w")
	var crews: OrbitCrews = so.get("crews")
	var hl: HexLevels = w.get("hex_levels") as HexLevels
	var n: int = 0
	for c: int in list:
		if globe.cells.state[c] == 5 or globe.cells.has_flag(c, SphereCells.F_HUB) or globe.field.hex_hub[c] != 0:
			continue
		if globe.cells.is_dirty(c):
			crews.work_cell(c, 0.0)
			so.call("on_hex_clean", c, true)
		if hl:
			hl.track(c)
			if hl.levels.has(c) and int(hl.levels[c]) < level:
				hl.levels[c] = level
				EventBus.hex_level_changed.emit(c, level)
		n += 1
	if hl:
		hl._recalc_bonus()
	return n


static func report(so: Node) -> String:
	var w: Node = so.get("w")
	var out: Array[String] = []
	var cv: Variant = w.get_node_or_null("CellVerdure")
	if cv is CellVerdure:
		out.append("verdure %s" % str((cv as CellVerdure).stats))
	var fl: Variant = w.get_node_or_null("Flutter")
	if fl is Flutter:
		out.append("flutter %d" % (fl as Flutter).shown)
	var la: Variant = w.get_node_or_null("LifeAmbience")
	if la is LifeAmbience:
		out.append("sound dirty %.2f green %.2f shots %s" % [(la as LifeAmbience).dirty, (la as LifeAmbience).green, str((la as LifeAmbience).shots_played)])
	var sm: SiteManager = (so.get("globe") as OrbitPlanet).site_manager
	for i: int in sm.prefabs.size() if sm else 0:
		var pf: Variant = sm.prefabs[i]
		if not (pf is SitePrefab) or (pf as SitePrefab).content == null:
			continue
		for c: Node in (pf as SitePrefab).content.get_children():
			var tl: Variant = c.get_node_or_null("TownLife")
			if tl is TownLife:
				var sp: Variant = sm.power.get(i)
				out.append("town %d %s lights %s" % [i, str((tl as TownLife).stats), "%d/%d" % [(sp as StreetPower).lit_count(), (sp as StreetPower).group_count()] if sp is StreetPower else "-"])
	return "  ".join(out)


## [v7look] Waits `s` seconds of wall clock.
static func _wait_wall_for(tree: SceneTree, s: float) -> void:
	var until: int = Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await tree.process_frame


static func tour(so: Node) -> void:
	var globe: OrbitPlanet = so.get("globe")
	var w: Node = so.get("w")
	var tree: SceneTree = so.get_tree()
	var prefix: String = DevHooks.get_s("life-tour", "screenshots/life")
	await DevHooks.wait_wall(DevHooks.get_f("life-tour-start", 6.0))  # [v7look] wall clock: game time crawls on software renders
	var k: int = 0
	for stop: String in DevHooks.get_s("life-tour-stops", "0,0,0,0.5,4").split(";", false):
		var a: PackedStringArray = stop.split(",")
		var patch: Patch = w.get("patch")
		var cam: SphereCam = so.get("cam")
		var d: Vector3 = globe.terrain.local_to_dir(globe.start_cell(), float(a[0]), float(a[1]))
		var north: Vector3 = (-SphereGrid.frame(d).z).rotated(d.normalized(), deg_to_rad(float(a[2])))
		patch.place_on_sphere(globe.terrain.ground(d), north)
		if a.size() > 5:
			cam.distance = float(a[5])
		if a.size() > 6:
			cam.pitch = float(a[6])
		cam.reset_frame(north)
		cam.snap()
		var sky: Variant = w.get("sky_director")
		if sky is SkyDirector:
			(sky as SkyDirector).time_of_day = float(a[3])
			(sky as SkyDirector).spin = SkyDirector.spin_for_local_time(float(a[3]), patch.global_position)
			(sky as SkyDirector).frozen = true
		await _wait_wall_for(tree, float(a[4]))  # [v7look] wall clock (a 10 s game-time wait took minutes)
		DevHooks.save_viewport("%s_%d.png" % [prefix, k])
		print("[life] stop %d: %s  %s" % [k, stop, report(so)])
		k += 1
	tree.quit()
