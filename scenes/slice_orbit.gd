class_name SliceOrbit
extends Node
## [orbB] The slice on the walkable globe (--orbit). scenes/slice.gd hands its build to this node
## and routes a few calls here (tagged `# [orbB]` hooks); the slice keeps being `world` for
## Patch, the HUD, the Depot and every system, so systems port one at a time by moving out of
## the "not ported yet" list below.
##
## Built here: the globe (OrbitPlanet: survey, terrain, cells, streamer, SphereField as the
## slice's `field`, SphereJunkView as its `view`, sites, gravity), sky and day/night (OrbitDay),
## stand-in crews (OrbitCrews), the real Patch on a SphereMotor with SphereCam, the HUD, the
## Depot on the start pad, Lumi Level, the pause menu, hex levels (sparse), the Hub (logic; the
## site prefab shows its stage), the workbench + Upgrades, Research/Achievements/Codex, music,
## WREN + subtitles, Goals, Tutorial, Requests, Interactables, WorldEvents, the Signal Tower,
## Extras (CD player, nursery, album, welcome back, Seed of the Week), the Telescope, Camp (broken
## bench, trash bin, yard builds), Glim, the crashed pod, CoreCharge, Objectives (+ the cell
## outline), the garden (sparse, per cell). Yard systems stand on orbD's hub-0 anchors (yard_slot).
## GameState.world is the start site's own dict (GameState.use_orbit_world).
## Not here: CityLayout/CityView/StreetDressing/litter/far junk/water (orbD sites), Fleet/robot
## builder/Command view (orbC), SkyDirector/GlobeView/FutureLayer, the intro cinematic and photo
## mode (orbE); frontier districts (retired on the globe). Fauna, eggs, outposts, the Ledger arc
## and Garden Mode's decor run per hub (HubFrame).
##
## Dev flags (phase A's, now on the slice): --orbit-walk[=boost] --orbit-lap-quit,
## --orbit-scoop, --orbit-cash --orbit-cash-quit, --orbit-view=follow|ground|command,
## --orbit-day=MIN, --orbit-time=0..1, --orbit-presim=MIN, --orbit-hubs=N, --orbit-cam=D,P,
## --orbit-bots=N (stand-in SphereBots, default 4). The phase A scenes stay reachable as
## --orbit=globe (planet/orbit/verdance_globe.tscn) and --orbit=v1.

const SCHEMA: int = OrbitSave.SCHEMA  # GameState.orbit layout: core/save_orbit.gd
const HEX_MILESTONES: Array[int] = [1, 5, 10, 25, 50, 100, 150, 200, 264]  # slice.gd's, by cell id here

var w: Node3D  # the slice (scenes/slice.gd)
var globe: OrbitPlanet
var day: OrbitDay
var crews: OrbitCrews
var cam: SphereCam
var dev: OrbitDev
var from_memory: bool = false  # [orbC] reloaded by rocket travel: no offline payout
var layers: OrbitLayers  # [orbE]
var view_mode: String = "follow"
var sites: OrbitSites  # [orbD]
var hub_states: Dictionary = {}  # site index (str) -> {level} (core/save_orbit.gd); the Hub port fills it


## True when --orbit asks for the slice on the globe (not one of the phase A prototypes).
static func wanted() -> bool:
	if DevHooks.has("orbit"):
		return not DevHooks.get_s("orbit", "") in ["v1", "globe"]
	return SaveManager.round_planets()  # the title screen's "Round planets (preview)"


## Builds the whole orbit slice into `p_world`. [orbE] Behind the loading screen (a BuildBudget is
## open, scenes/slice.gd `building`) it yields between steps and runs the survey on a thread, so
## the first frame no longer freezes for the whole build; synchronous otherwise (tests, tools).
func build(p_world: Node3D) -> void:
	w = p_world
	var t0: int = Time.get_ticks_msec()
	get_tree().paused = false
	var loaded: bool = false
	if GameState.reload_in_memory:
		GameState.reload_in_memory = false
		loaded = true
		from_memory = true  # [orbC]
	elif not DevHooks.has("fresh"):
		loaded = SaveManager.load_game()
	var od: Dictionary = OrbitSave.migrate(GameState.orbit) if loaded else {}
	AssetLib.tracing = DevHooks.has("load-report") or DevHooks.has("record-preload")  # [v5load] blocking model loads, to the end of the build
	AssetLib.traced.clear()
	var ck_task: int = BuildBudget.add_task(FaunaSounds.crickets_loop, "crickets") if BuildBudget.active() else -1  # [v5load] the cricket bed's synthesis (pure maths)
	var preload_n: int = OrbitPreload.start()  # [orbE] junk models load on threads while the planet builds
	# The planet: --orbit-planet=<id>, else the saved one, else Verdance. Its size is data (GlobeSpec).
	var home_pid: String = str(Homeward.planet_def(maxi(Homeward.current_planet(), 0)).get("id", "verdance"))  # [orbD] a new world after an interplanet flight
	var pid: String = GlobeSpec.current_id() if DevHooks.has("orbit-planet") else str(od.get("planet_id", home_pid))
	var spec: Dictionary = GlobeSpec.of(pid)
	if int(od.get("freq", spec["frequency"])) != int(spec["frequency"]) or str(od.get("planet_id", pid)) != pid:
		push_warning("[orbit] saved globe is %s f=%d, building %s f=%d fresh" % [od.get("planet_id", "?"), int(od.get("freq", 0)), pid, int(spec["frequency"])])
		od = {}
		loaded = false
		GameState.orbit = {}
	var seed_v: int = int(DevHooks.get_f("seed", float(od.get("seed", spec.get("seed", 4471)))))
	globe = OrbitPlanet.new()
	globe.name = "Globe"
	w.add_child(globe)
	# An old flat save without a globe yet: its survey and bases move onto this globe (OrbitMigrate).
	var migrate: bool = loaded and od.is_empty() and OrbitMigrate.can_migrate(int(spec["frequency"]))
	var report: Dictionary = {}
	var hook := Callable()
	if migrate:
		hook = func(g: OrbitPlanet) -> void: report.merge(OrbitMigrate.apply(g))
	if DevHooks.has("load-report"):  # [orbE] the stretch before the first yield
		print("[orbit-load] before globe: %d ms" % (Time.get_ticks_msec() - t0))
	BuildBudget.span(0.0, 0.5)  # [orbE] loading bar: the globe is the first half
	await globe.build(seed_v, spec, int(DevHooks.get_f("orbit-hubs", -1.0)), od.get("planet", {}), od.get("cells", {}), OrbitSave.site_cells(od), hook)
	BuildBudget.span(0.5, 0.65)
	hub_states = (od.get("hubs", {}) as Dictionary).duplicate(true)
	# GameState.world is the start site's own dict on the globe (the flat one is kept for saves).
	GameState.use_orbit_world(OrbitMigrate.hub_world() if migrate else ((od.get("hub_worlds", {}) as Dictionary).get("0", {}) as Dictionary).duplicate(true))
	if migrate:
		hub_states = report.get("hubs", {})
		GameState.orbit = {"migrated": "flat_v%d" % GameState.SAVE_VERSION, "hubs": hub_states}
		print("[orbit] migrated a flat save: %s" % JSON.stringify(report))
	if od.has("field"):
		globe.field.apply_dict(od["field"])
	w.set("planet", globe.planet)
	w.set("field", globe.field)
	w.set("view", globe.junk_view)
	w.set("anchor_cell", globe.start_cell())
	w.set("hub_index", 0)
	w.set("district_name", pid.capitalize())
	day = OrbitDay.new()
	day.name = "Day"
	w.add_child(day)
	day.build(w, globe.grid.centers[globe.start_cell()])
	crews = OrbitCrews.new()
	crews.name = "Crews"
	w.add_child(crews)
	crews.setup(globe)
	BuildBudget.lap("orbit crews setup")
	for i: int in range(1, globe.sites.size() if DevHooks.has("orbit-bots") else 0):  # [orbC] stand-ins only on request: far work is the crew's
		crews.add_far_crew(int(globe.sites[i]["cell"]), 0.25 + 0.05 * (i % 4))
	if DevHooks.has("orbit-presim"):
		var all_crews: Array[Dictionary] = []
		for i: int in globe.sites.size():
			all_crews.append({"hub": int(globe.sites[i]["cell"]), "rate": 0.5 + 0.1 * (i % 4), "acc": 0.0})
		crews.tick(all_crews, DevHooks.get_f("orbit-presim", 120.0) * 60.0)
	var cubes_root := Node3D.new()
	cubes_root.name = "Cubes"
	w.add_child(cubes_root)
	w.set("_cubes_root", cubes_root)
	await BuildBudget.check("orbit crews")  # [orbE]
	var tq: int = Time.get_ticks_msec()  # [orbE] load breakdown
	await OrbitPreload.warm()  # [v5load] the build's own models: files from the loader threads, meshes within budget
	var site: Node3D = await globe.build_start_site()
	BuildBudget.lap("orbit start site")
	if DevHooks.has("load-report"):  # [orbE] what the start site loads on the main thread
		print("[orbit-load] start site %d ms" % (Time.get_ticks_msec() - tq))
	await BuildBudget.check("orbit start site")  # [orbE]
	# The site's deferred footprint probe and anchor fix (physics queries and flood fills, yielding
	# themselves): wait for it here, so it never stacks with a build slice or outlives the loader.
	await BuildBudget.pause("site probe")
	var wait_t: int = Time.get_ticks_msec()
	while BuildBudget.active() and globe.site_manager and not globe.site_manager.probed.has(0) and Time.get_ticks_msec() - wait_t < 30000:
		await BuildBudget.pause("site probe")
	_build_patch()
	BuildBudget.lap("orbit patch")
	await BuildBudget.check("orbit patch")  # [v5load]
	_build_depot(site)
	BuildBudget.lap("orbit depot")
	await BuildBudget.check("orbit lumi")  # [orbE]
	sites = OrbitSites.attach(self)  # [orbD] sled, rocket hops, planet %, site state
	BuildBudget.lap("orbit sites attach")
	await BuildBudget.check("orbit sites")  # [v5load]
	_build_hub()
	BuildBudget.lap("orbit hub")
	await BuildBudget.check("orbit hub")  # [v5load]
	_build_bench()
	BuildBudget.lap("orbit bench")
	await BuildBudget.check("orbit bench")  # [v5load]
	crews.build_crew(self)  # [orbC] the robot crew (planet/orbit/orbit_crews.gd)
	BuildBudget.lap("orbit build_crew")
	if DevHooks.has("orbit-bots"):  # [orbC] stand-in bots only on request (the crew replaces them)
		crews.spawn_demo_bots(globe.start_cell(), int(DevHooks.get_f("orbit-bots", 4.0)), w)
	await BuildBudget.check("orbit crew")  # [orbE]
	BuildBudget.span(0.65, 0.8)
	var garden := Garden.new()  # sparse: a cell's slots come when Lumi plants or waters near it
	garden.name = "Garden"
	garden.world = w
	garden.sparse = true
	w.add_child(garden)
	w.set("garden", garden)
	garden.setup()
	BuildBudget.lap("orbit garden")
	GardenMarks.attach(w)  # [v4grow] #51: soil mounds, sprouts, thirsty drops, cell rings, the can's ring
	var hl := HexLevels.new()  # sparse: only cleaned cells are tracked; levels also go to SphereCells
	hl.name = "HexLevels"
	hl.world = w
	hl.sparse = true
	w.set("hex_levels", hl)  # before add_child: its tree-entered hooks may read world.hex_levels
	w.add_child(hl)
	hl.setup()
	BuildBudget.lap("orbit hexlevels")
	EventBus.hex_level_changed.connect(_on_hex_level)
	if not DevHooks.has("life-off"):  # [v6life] clean ground greens over (plants/cell_verdure.gd)
		var cv := CellVerdure.new()
		w.add_child(cv)
		cv.setup(w, globe)
		var fl := Flutter.new()  # butterflies and fireflies over planted cells (plants/flutter.gd)
		w.add_child(fl)
		fl.setup(w, globe)
		var la := LifeAmbience.new()  # wind over junk, leaves over green (audio/life_ambience.gd)
		w.add_child(la)
		la.setup(w, globe)
		BuildBudget.lap("orbit verdure")
	var lumi_level := LumiLevel.new()
	lumi_level.name = "LumiLevel"
	lumi_level.world = w
	w.add_child(lumi_level)
	w.set("lumi_level", lumi_level)
	BuildBudget.lap("orbit lumilevel")
	if not (DevHooks.has("orbit-nohud") or DevHooks.has("no-hud")):
		var hud := HUD.new()
		hud.patch = w.get("patch")
		hud.world = w
		w.add_child(hud)
		w.set("hud", hud)
	var pm := PauseMenu.new()
	w.add_child(pm)
	pm.closed.connect(on_modal_closed)
	w.set("pause_menu", pm)
	BuildBudget.lap("orbit hud+pause")
	await BuildBudget.check("orbit hud")  # [orbE]
	_build_upgrades()
	BuildBudget.lap("orbit upgrades")
	w.call("_setup_research_codex")  # slice.gd's own: Research, Achievements, the Codex (UI + data)
	BuildBudget.lap("orbit codex")
	await BuildBudget.check("orbit codex")  # [orbE]
	await BuildBudget.join(ck_task)  # [v5load]
	if BuildBudget.active():
		await FaunaModels.prewarm()  # [v5load] the animals' procedural meshes, before the hub frame makes the wildlife
	_build_story()
	BuildBudget.lap("orbit story")
	await _build_yard_systems()
	BuildBudget.lap("orbit yard systems")
	await BuildBudget.check("orbit story")  # [orbE]
	if loaded and not migrate:
		restore_world()
	elif migrate:
		(w.get("patch") as Patch).restore_cargo(OrbitMigrate.lumi_cargo())
	globe.stats["site_patch_hud_ms"] = Time.get_ticks_msec() - tq
	tq = Time.get_ticks_msec()
	layers = OrbitLayers.attach(self)  # [orbE] sky + day/night, Glim, future layer, survey, system map, photo mode
	globe.stats["layers_ms"] = Time.get_ticks_msec() - tq
	BuildBudget.lap("orbit layers")
	await BuildBudget.check("orbit layers")  # [orbE]
	BuildBudget.span(0.8, 1.0)
	var tw: int = Time.get_ticks_msec()
	await OrbitPreload.finish()  # [orbE] models were loading on threads all along; the settle seats them
	globe.stats["preload_wait_ms"] = Time.get_ticks_msec() - tw
	globe.stats["preload_models"] = preload_n
	BuildBudget.lap("orbit preload finish")
	globe.update_centres()
	var t2: int = Time.get_ticks_msec()
	globe.defer_fill = BuildBudget.active()  # [v5load] the first ring's junk fills in slices (refresh_junk_async)
	await globe.streamer.settle_async(20000, not DevHooks.has("orbit-settle-all"))  # [orbE] near chunks only; the rest streams in
	globe.stats["settle_ms"] = Time.get_ticks_msec() - t2
	var t3: int = Time.get_ticks_msec()
	await globe.refresh_junk_async()
	OrbitPreload.done()  # [v5load] the surface copies the worker mesh tasks read
	globe.stats["junk_fill_ms"] = Time.get_ticks_msec() - t3
	BuildBudget.lap("orbit junk fill")
	await BuildBudget.check("orbit junk")  # [orbE]
	Settings.apply_quality_to_tree(w)
	day.after_quality(view_mode == "command")
	BuildBudget.lap("orbit quality")
	if DevHooks.has("give"):
		GameState.add_currency("cubes", BigNum.from_float(DevHooks.get_f("give", 100.0)))
	Pace.sync_flags()
	dev = OrbitDev.new()
	dev.name = "OrbitDev"
	dev.so = self
	w.add_child(dev)
	if not w.get("bot") and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	w.add_to_group("persist")
	var g: OrbitPlanet = globe
	print("[orbit] %s f=%d near ring: pieces=%d parts=%d landmarks=%d mounds=%d" % [pid, g.grid.freq, g.field.piece_pos.size(), g.field.part_pos.size(), g.field.landmarks.size(), g.junk_view.mound_count()])
	print("[orbit] slice on the globe: R=%.0fm hexes=%d around=%.1fkm hubs=%d (nearest hub mean %.0fm, min %.0fm) loaded=%s built=%dms planet=%dms grid=%dms settle=%dms junk_fill=%dms" % [
		g.grid.radius_m, g.grid.cell_count(), TAU * g.grid.radius_m / 1000.0, g.sites.size(), g.hub_spacing(false), g.hub_spacing(true),
		str(loaded), Time.get_ticks_msec() - t0, g.stats["planet_ms"], g.stats["grid_ms"], g.stats["settle_ms"], g.stats["junk_fill_ms"]])
	if AssetLib.tracing:  # [v5load]
		print("[orbit-load] %d models loaded on the main thread: %s" % [AssetLib.traced.size(), ",".join(AssetLib.traced)])
		if DevHooks.has("record-preload"):
			OrbitPreload.record(AssetLib.traced)
		AssetLib.tracing = false
	if DevHooks.has("load-report"):  # [orbE] where the build time goes
		print("[orbit-load] %s streamer=%s chunks=%d cells/chunk=%d" % [JSON.stringify(g.stats), JSON.stringify(g.streamer.stats), g.grid.chunk_count(), g.grid.cell_count() / maxi(g.grid.chunk_count(), 1)])
	if not bool(w.get("building")):  # [orbE] behind the loader, slice.gd emits once it has re-enabled the world
		w.emit_signal("built")
	if DevHooks.has("yard-probe"):  # [v1yard] junk distance from the pad and pod, what stands at the start
		YardProbe.attach(self)
	if DevHooks.has("ground-probe"):  # [v3qa] floating / sunken props and junk around Lumi
		GroundProbe.attach(self)
	LifeDev.attach(self)  # [v6life] --life-clean / --life-report


func _build_patch() -> void:
	var g: OrbitPlanet = globe
	var hub_cell: int = g.start_cell()
	# Facing north from the pad's middle: the crashed pod (anchor "pod", 9.8 m south) stays behind
	# the follow camera (~6 m back) instead of filling the view or swallowing the camera.
	var spawn_dir: Vector3 = g.terrain.local_to_dir(hub_cell, 0.0, 0.5)
	if DevHooks.has("orbit-spawn"):  # [v1world] dev: --orbit-spawn=x,z[,yaw_deg] metres from the start cell (renders of the junk field)
		var sp: PackedStringArray = DevHooks.get_s("orbit-spawn", "0,0").split(",")
		spawn_dir = g.terrain.local_to_dir(hub_cell, float(sp[0]), float(sp[1]) if sp.size() > 1 else 0.0)
	var north: Vector3 = -SphereGrid.frame(spawn_dir).z
	if DevHooks.has("orbit-spawn") and DevHooks.get_s("orbit-spawn", "").split(",").size() > 2:  # [v1world]
		var up_s: Vector3 = spawn_dir.normalized()
		north = north.rotated(up_s, deg_to_rad(float(DevHooks.get_s("orbit-spawn", "").split(",")[2])))
	cam = SphereCam.new()
	cam.name = "SphereCam"
	cam.surface = g.surface
	var patch := Patch.new()
	patch.name = "Patch"
	patch.world = w
	match DevHooks.get_s("orbit-walk", "") if DevHooks.has("orbit-walk") else "-":
		"-":
			patch.input = SphereInput.new()
			if DevHooks.has("autoplay"):  # the pacing bot (tools/autoplay.gd), moving along the ground
				var ab := AutoplayBot.new(w)
				ab.world_space = true
				patch.input = ab
				w.set("bot", ab)
		"boost":
			patch.input = SphereAutoInput.new(Vector3(0, 0, -1), true)
		_:
			patch.input = SphereAutoInput.new(Vector3(0, 0, -1), false)
	if patch.input is SphereAutoInput:  # [orbD] lap tests detour round mounds and props
		(patch.input as SphereAutoInput).body = patch
	if DevHooks.has("orbit-scoop") and patch.input is SphereAutoInput:
		(patch.input as SphereAutoInput).scoop = true
	patch.enable_sphere(g.surface, cam)
	w.add_child(patch)
	patch.place_on_sphere(g.terrain.ground(spawn_dir), north)
	patch.detector.field = g.field
	w.set("patch", patch)
	cam.target = patch
	w.add_child(cam)
	cam.reset_frame(north)
	view_mode = DevHooks.get_s("orbit-view", "follow")
	match view_mode:
		"ground":
			cam.distance = 7.5
			cam.pitch = -0.1
		"command":
			cam.view = "command"
			cam.command_height = DevHooks.get_f("orbit-height", 400.0)
	if DevHooks.has("orbit-cam"):
		var a: PackedStringArray = DevHooks.get_s("orbit-cam", "6,-0.3").split(",")
		cam.distance = float(a[0])
		if a.size() > 1:
			cam.pitch = float(a[1])
	cam.snap()
	g.track("lumi", patch)
	g.view_camera = func() -> Vector3: return cam.camera.global_position
	day.body = patch
	day.camera_pos = g.view_camera
	day.add_lamp(patch)


## The cash-in depot on the start site's pad (site-local metres, like any site prefab).
func _build_depot(site: Node3D) -> void:
	var depot := Depot.new()
	depot.name = "Depot"
	depot.world = w
	depot.patch = w.get("patch")
	site.add_child(depot)
	depot.position = Vector3(5.5, 0.0, 3.5)
	depot.rotation.y = -PI * 0.5
	var sp: SitePrefab = globe.site_manager.prefab(0) if globe.site_manager else null  # [orbD] on the site's depot anchor
	if sp:
		depot.transform = sp.anchor_local("depot")
		depot.seat_bin(sp)  # [v3clear] the bin body on the "bin" anchor, inside its bay
	w.set("depot", depot)


# --- The slice API on the globe (slice.gd hooks call these) ------------------------------

func collect_piece(pid: int) -> void:
	var field: SphereField = globe.field
	var hid: int = field.piece_hex[pid]
	var became_clean: bool = field.remove_piece(pid)
	globe.write_cell(hid)
	globe.junk_view.hide_piece(pid)
	globe.junk_view.refresh_hex(hid, became_clean)
	if became_clean:
		on_hex_clean(hid)


## A bite off a heavy piece (Patch._take_piece): the cell's numbers and its heap follow.
func piece_bitten(pid: int) -> void:
	var hid: int = globe.field.piece_hex[pid]
	globe.write_cell(hid)
	globe.junk_view.refresh_hex(hid)


## slice.gd's _on_hex_clean by cell id: first-clean bonus (a re-dirtied cell pays only the flat
## part again and doesn't count twice), milestones, the first hex's fanfare, the event.
## quiet: [orbC] a robot cleaned it out of Lumi's sight: same bonus, stats and milestones, no
## chime or sparkles.
func on_hex_clean(hid: int, quiet: bool = false) -> void:
	var field: SphereField = globe.field
	if field.hex_water[hid] == 0:
		globe.cells.set_state(hid, 1)
	var paid: Dictionary = GameState.orbit.get("hexes_paid", {})
	var first: bool = not paid.has(str(hid))
	paid[str(hid)] = true
	GameState.orbit["hexes_paid"] = paid
	var bonus: BigNum = Economy.hex_bonus(field.hex_total[hid] if first else 0.0)
	GameState.add_currency("cubes", bonus)
	if first:
		GameState.inc_stat("hexes_cleaned")
	var center: Vector3 = field.hex_center(hid)
	var u: Vector3 = center.normalized()
	var patch: Patch = w.get("patch")
	if not quiet:  # [orbC]
		Audio.play("chime", 1.0, -3.0)
		Vfx.burst("big_sparkle", center + u * 0.3, Color(1.0, 0.92, 0.55))
		Vfx.ring(center, field.hex_size * 1.1, Color(1.0, 0.9, 0.5, 0.9), 0.8)
		Vfx.float_text(center + u * 1.4, tr("HEX CLEAN!  +%s") % Settings.fmt(bonus), Color(1.0, 0.92, 0.45), 1.5, 2.0)
	EventBus.hex_cleaned.emit(hid, center, bonus)
	EventBus.field_progress_changed.emit(field.cleaned_count, field.junk_hex_count)
	if patch and not quiet:  # [orbC]
		patch.model.set_happy(1.0)
	var n: int = cleaned_by_lumi()
	if n == 1 and first and not quiet:  # [orbC]
		EventBus.hitstop_requested.emit(0.45, 0.25)
		Audio.play("fanfare", 1.0, -4.0)
	if n in HEX_MILESTONES and not GameState.flags.get("hexm_%d" % n, false):
		GameState.flags["hexm_%d" % n] = true
		EventBus.milestone_reached.emit("hexes_%d" % n)
		if n > 1:
			Audio.play("fanfare", 1.0, -5.0)
			if patch:
				Vfx.burst("confetti", patch.global_position + patch.up() * 1.5, Color.WHITE)
			EventBus.toast.emit(tr("Milestone: %d hexes clean!") % n, "reward")  # [v4calm] cut (the fanfare says it)


## Hexes counted for milestones: the cells this save paid a first-clean bonus for (far crews'
## numbers flip cells clean too, but they are not Lumi's milestones).
func cleaned_by_lumi() -> int:
	return (GameState.orbit.get("hexes_paid", {}) as Dictionary).size()


func _on_hex_level(hid: int, lvl: int) -> void:
	if globe and hid >= 0 and hid < globe.cells.n:
		globe.cells.set_level(hid, lvl)


func cell_at(pos: Vector3) -> int:
	return globe.cell_at(pos)


func try_interact(p: Patch) -> void:
	var ia: Interactables = w.get("interactables")
	if ia and ia.try_use(p.global_position):
		return
	var fs: FirstSeed = w.get("first_seed")
	if fs and fs.near_tin(p.global_position):  # the Maker seed tin in the greenhouse
		fs.take_tin()
		return
	var cmp: Composter = w.get("composter")
	if cmp and cmp.near(p.global_position):
		cmp.interact()
		return
	var sh: ShardSystem = w.get("shards")
	if sh and sh.nearby(p.global_position) >= 0:  # a memory shard: read it
		var doc: Dictionary = sh.take(p.global_position)
		var dv: DocumentView = w.get("doc_view")
		if not doc.is_empty() and dv:
			set_input(false)
			dv.show_doc(doc)
		return
	if near_bench():
		var camp: Camp = w.get("camp")
		if not Camp.bench_ok():
			if camp:
				camp.repair_bench()
			else:
				repair_bench()
		else:
			open_upgrades()


func interact_prompt(p: Patch) -> String:
	var ia: Interactables = w.get("interactables")
	var ip: String = ia.prompt(p.global_position) if ia else ""
	if ip != "":
		return ip
	var fs: FirstSeed = w.get("first_seed")
	if fs and fs.near_tin(p.global_position):
		return "seed"
	var cmp: Composter = w.get("composter")
	if cmp and cmp.near(p.global_position):
		return cmp.prompt()
	var sh: ShardSystem = w.get("shards")
	if sh and sh.nearby(p.global_position) >= 0:
		return "shard"
	if near_bench():
		var camp: Camp = w.get("camp")
		if camp:
			return camp.bench_prompt()
		if _repairing:
			return ""
		return tr("E   Fix the workbench") if not Camp.bench_ok() else tr("E   Open the workbench")  # [v3clear]
	return sites.interact_prompt() if sites else ""  # [orbD] the hover-sled


func any_modal_open() -> bool:
	for k: String in ["pause_menu", "upgrades", "codex", "doc_view"]:
		var m: Node = w.get(k)
		if m != null and bool(m.get("is_open")):
			return true
	return false


# --- Story, music, goals (no flat geometry) ---------------------------------------------

## The systems the flat slice builds after the board that only read world state: music, WREN and
## the subtitles, goals, the restart checklist (tutorial), the Requests board.
func _build_story() -> void:
	var music := MusicHooks.new()
	music.world = w
	w.add_child(music)
	w.set("music", music)
	var wren := Wren.new()
	wren.world = w
	w.add_child(wren)
	w.set("wren", wren)
	var subs := Subtitles.new()
	w.add_child(subs)
	wren.line_out.connect(subs.show_line)
	var goals := Goals.new()
	goals.name = "Goals"
	goals.world = w
	w.add_child(goals)
	w.set("goals", goals)
	var tut := Tutorial.new()
	tut.world = w
	w.add_child(tut)
	w.set("tutorial", tut)
	if DevHooks.has("clarity-log"):  # [v3clear] what the player is told, over time (tools/clarity_log.gd)
		w.add_child(ClarityLog.new(w))
	var ct := Contracts.new()
	ct.name = "Contracts"
	ct.world = w
	w.add_child(ct)
	w.set("contracts", ct)


# --- Yard systems on the start site's anchors ---------------------------------------------

## Where a yard system stands: the hub-0 prefab's named anchor (orbD), else its flat yard spot
## on the pad. Returns [parent, local transform].
func yard_slot(anchor: String, flat_pos: Vector3) -> Array:
	var sm: SiteManager = globe.site_manager
	var sp: SitePrefab = sm.prefab(0) if sm else null
	if sp and sp.anchor_names().has(anchor):
		return [sp, sp.anchor_local(anchor)]
	return [sp if sp else globe.start_site, Transform3D(Basis(), flat_pos)]


func _build_yard_systems() -> void:
	var ia := Interactables.new()  # generic E-interactables (eggs, relay, bin, tower, ...)
	ia.name = "Interactables"
	w.add_child(ia)
	BuildBudget.lap("yard:ia")
	await BuildBudget.check("yard:ia")  # [v5load]
	w.set("interactables", ia)
	var ev := WorldEvents.new()  # world events + the cleaning streak (systems/events.gd)
	ev.name = "WorldEvents"
	ev.world = w
	w.add_child(ev)
	BuildBudget.lap("yard:ev")
	await BuildBudget.check("yard:ev")  # [v5load]
	w.set("events", ev)
	SignalTower.migrate(w)  # WREN only talks through the Signal Tower (story/signal_tower.gd)
	if GameState.current_hub == 0:
		var tower := SignalTower.new()
		tower.name = "SignalTower"
		tower.world = w
		var slot: Array = yard_slot("signal_tower", SignalTower.pos())
		w.add_child(tower)  # a child of the slice, as on the flat game (HubBuilds and the bot look it up)
		tower.global_transform = (slot[0] as Node3D).global_transform * (slot[1] as Transform3D)  # after its _ready
	await _attach_extras()
	BuildBudget.lap("yard:_attach_extras")
	await BuildBudget.check("yard:_attach_extras")  # [v5load]
	var scope := Telescope.new()  # the Telescope + remote progress (automation/telescope.gd)
	scope.name = "Telescope"
	scope.world = w
	w.add_child(scope)
	BuildBudget.lap("yard:scope")
	await BuildBudget.check("yard:scope")  # [v5load]
	# Its model sits at _pos() in its own frame: put that point on the "telescope" anchor.
	var tslot: Array = yard_slot("telescope", scope.call("_pos"))
	scope.global_transform = (tslot[0] as Node3D).global_transform * (tslot[1] as Transform3D) * Transform3D(Basis(), -(scope.call("_pos") as Vector3))
	await _attach_camp()
	BuildBudget.lap("yard:_attach_camp")
	await BuildBudget.check("yard:_attach_camp")  # [v5load]
	GlimDirector.attach(w)  # Glim the lantern bot: light, hex scanner, upgrades, looks (systems/glim/)
	BuildBudget.lap("yard:GlimDirector")
	await BuildBudget.check("yard:GlimDirector")  # [v5load]
	_start_intro_or_place_pod()  # [orbE] the intro cinematic on the globe (new games); else the pod as before
	BuildBudget.lap("yard:_start_intro_or_place_pod")
	await BuildBudget.check("yard:_start_intro_or_place_pod")  # [v5load]
	var cc := CoreCharge.new()  # Lumi's Bloom Core charge and its story beats (story/core_charge.gd)
	cc.name = "CoreCharge"
	cc.world = w
	w.add_child(cc)
	BuildBudget.lap("yard:cc")
	await BuildBudget.check("yard:cc")  # [v5load]
	w.set("core_charge", cc)
	var obj := Objectives.new()  # WREN's last message after the intro + the objective card and outline
	obj.world = w
	w.add_child(obj)
	BuildBudget.lap("yard:obj")
	await BuildBudget.check("yard:obj")  # [v5load]
	w.set("objectives", obj)
	await _build_hub_frame()
	BuildBudget.lap("yard:_build_hub_frame")
	await BuildBudget.check("yard:_build_hub_frame")  # [v5load]
	_attach_seed_economy()
	BuildBudget.lap("yard:_attach_seed_economy")
	await BuildBudget.check("yard:seed economy")  # [v5load]
	_attach_shards()
	BuildBudget.lap("yard:_attach_shards")
	await BuildBudget.check("yard:shards")  # [v5load]
	var bloom := Bloom.new()  # post-game milestones + Seed Ark (systems/bloom.gd)
	bloom.name = "Bloom"
	bloom.world = w
	w.add_child(bloom)
	BuildBudget.lap("yard:bloom")
	LateDirector.attach(w)  # Homeward, the Ark Bridge, world look/story, Garden Mode (its decor per hub in the frame)
	BuildBudget.lap("yard:LateDirector")
	# [v5load] The greenhouse builds deferred (after everything above, as before): behind the loader
	# it gets a frame of its own instead of landing on top of the next build slice (a 190 ms frame).
	if BuildBudget.active():
		await BuildBudget.pause("yard:late")
	_attach_first_seed.call_deferred()
	if BuildBudget.active():
		await BuildBudget.pause("yard:first seed")


## A yard spot in world space (the anchor's origin, or the flat yard spot on the pad).
func yard_point(anchor: String) -> Vector3:
	var flat: Vector3 = YardBuilds.pos(anchor, Vector3.ZERO) if YardBuilds.def(anchor).size() > 0 else Vector3.ZERO
	var slot: Array = yard_slot(anchor, flat)
	return (slot[0] as Node3D).global_transform * (slot[1] as Transform3D).origin


## Extras as on the flat game (radio / CD player, robot nursery, album, welcome back, Seed of the
## Week); the radio and the nursery stand on the start site's anchors (the nursery's caretakers
## wander in its own frame, so they come along).
func _attach_extras() -> void:
	var ex: ExtrasDirector = ExtrasDirector.attach(w)
	await BuildBudget.idle()  # [v5load] its setup hands frames back behind the loader
	if ex == null:
		return
	if ex.radio:
		var slot: Array = yard_slot("radio", Radio.POS)
		ex.radio.global_transform = (slot[0] as Node3D).global_transform * (slot[1] as Transform3D)
		var reach: Node3D = ex.radio.get("_anchor") as Node3D
		if reach:
			reach.global_position = ex.radio.global_position + ex.radio.global_basis.x * 1.0
	if ex.nursery:
		var slot2: Array = yard_slot("nursery", ex.nursery.position)
		ex.nursery.global_transform = (slot2[0] as Node3D).global_transform * (slot2[1] as Transform3D)
		ex.nursery.set("center", ex.nursery.global_position)


## The Act 3 opener (story/first_seed.gd): the ruined greenhouse with the Maker seed tin, on a free
## spot east of the start yard (FirstSeed.find_spot; the site's colliders must be in the physics
## space first, so it waits two physics frames).
func _attach_first_seed() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_instance_valid(w) or not w.is_inside_tree():
		return
	var fs := FirstSeed.new()
	fs.name = "FirstSeed"
	fs.world = w
	w.add_child(fs)
	fs.place_on_globe(self)
	fs.setup()
	w.set("first_seed", fs)


## The seed economy at the base: the compost press on the start yard's "composter" anchor (its own
## model and label; YardSite's stand-in steps aside), and the early seed finds in scooped junk.
## Memory shards in the start hub's region (they surface as their cells are cleaned) and the
## paper view that reads them (also the Ledger's contract and the eggs' notes).
func _attach_shards() -> void:
	var dv := DocumentView.new()
	dv.name = "DocumentView"
	w.add_child(dv)
	dv.closed.connect(on_modal_closed)
	w.set("doc_view", dv)
	var sh := ShardSystem.new()
	sh.name = "Shards"
	sh.world = w
	w.add_child(sh)
	sh.setup()
	w.set("shards", sh)


func _attach_seed_economy() -> void:
	var finds := SeedFinds.new()
	finds.name = "SeedFinds"
	finds.world = w
	w.add_child(finds)
	var cmp := Composter.new()
	cmp.name = "Composter"
	cmp.world = w
	w.add_child(cmp)
	var slot: Array = yard_slot("composter", Composter.POS)
	cmp.global_transform = (slot[0] as Node3D).global_transform * (slot[1] as Transform3D)
	cmp.visible = YardBuilds.built("composter")
	w.set("composter", cmp)


## Flat-yard systems that live at whichever hub Lumi is near (planet/orbit/hub_frame.gd): they keep
## their flat-game coordinates in that hub's frame and sleep between hubs.
var hub_frame: HubFrame


func _build_hub_frame() -> void:
	hub_frame = HubFrame.new()
	w.add_child(hub_frame)
	hub_frame.setup(self)
	hub_frame.hub_changed.connect(func(_h: int) -> void:
		var fa: Node = hub_frame.node("Fauna")
		w.set("fauna", fa as Fauna if fa else null)
		var eg: Node = hub_frame.node("EasterEggs")
		w.set("eggs", eg as EasterEggs if eg else null)
		var op: Node = hub_frame.node("Outposts")
		w.set("outposts", op as Outposts if op else null)
		var lg: Node = hub_frame.node("Ledger")
		w.set("ledger", lg as LedgerArc if lg else null))
	hub_frame.host("Fauna", func(f: HubFrame, _hub: int) -> Node:  # ambient animals return as hexes are restored
		var fa := Fauna.new()
		f.add_child(fa)
		fa.frame_cells = f.region()
		fa.setup(w)
		return fa)
	await BuildBudget.check("hub frame:fauna")  # [v5load]
	hub_frame.host("Outposts", func(f: HubFrame, hub: int) -> Node:  # each hub's ruined frontier outposts
		var op := Outposts.new()
		op.name = "Outposts"
		op.world = w
		op.hub_index = hub
		op.frame_cells = f.region()
		f.add_child(op)
		op.setup()
		return op)
	await BuildBudget.check("hub frame:outposts")  # [v5load]
	hub_frame.host("EasterEggs", func(f: HubFrame, hub: int) -> Node:  # each hub's easter eggs and collectibles
		var eg := EasterEggs.new()
		eg.name = "EasterEggs"
		eg.world = w
		eg.hub_index = hub
		f.add_child(eg)
		eg.frame_cells = f.region()
		eg.setup()
		return eg)
	await BuildBudget.idle()  # [v5load] the eggs plan and spawn across frames
	await BuildBudget.check("hub frame:eggs")  # [v5load]
	w.set("fauna", hub_frame.node("Fauna") as Fauna)
	hub_frame.host("Ledger", func(f: HubFrame, hub: int) -> Node:  # the Ledger arc: drones, jammers and the relay at this hub
		var lg := LedgerArc.new()
		lg.name = "Ledger"
		lg.world = w
		lg.hub_index = hub
		lg.frame_cells = f.region()
		f.add_child(lg)
		lg.setup()
		return lg)
	await BuildBudget.check("hub frame:ledger")  # [v5load]
	hub_frame.host("Decor", func(f: HubFrame, hub: int) -> Node:  # Garden Mode's decorations at this hub
		var dc := Decor.new()
		dc.hub_index = hub
		f.add_child(dc)
		dc.setup(w)
		return dc)
	w.set("eggs", hub_frame.node("EasterEggs") as EasterEggs)
	w.set("outposts", hub_frame.node("Outposts") as Outposts)
	w.set("ledger", hub_frame.node("Ledger") as LedgerArc)


## [orbE] A new game plays the intro cinematic (story/intro.gd) in the pod anchor's frame; its
## end places the pod the globe's way (_place_pod). Saves, tools and headless runs: the pod at once.
func _start_intro_or_place_pod() -> void:
	var intro := Intro.new()
	intro.name = "Intro"
	intro.world = w
	w.add_child(intro)
	w.set("intro", intro)
	if not intro.should_play():
		_place_pod()
		return
	intro.site_fn = func() -> Transform3D:
		var at: Vector3 = yard_point("pod")
		return Intro.site_for_anchor(Transform3D(SphereGrid.frame(at.normalized()), at))
	intro.place_pod_fn = _place_pod
	intro.cam_reset_fn = func() -> void:
		var patch: Patch = w.get("patch")
		cam.reset_frame(patch.forward())
		cam.snap()
		if DevHooks.has("intro"):
			var pod_site: Node3D = w.get_meta("orbit_pod", null)
			print("[intro] globe: Lumi %.2f m above the ground, %.1f m from the pod, pod placed=%s" % [
				globe.surface.altitude(patch.global_position), patch.global_position.distance_to(pod_site.global_position) if pod_site else -1.0, str(pod_site != null)])
	var hud: Node = w.get("hud")
	if hud:
		hud.visible = false  # no one-frame HUD flash before the deferred intro starts (as the flat slice)
	intro.cover_now()
	intro.play.call_deferred()


## The landing pod in its crash site on the start site's "pod" anchor. The intro cinematic itself
## is camera work for orbE; on the globe it doesn't play yet, so the landing counts as done.
func _place_pod() -> void:
	GameState.flags["intro_done"] = true
	var pod: Node3D = Intro.build_pod()
	var fire: Node = pod.get_node_or_null("ReentryFire")
	if fire:
		fire.queue_free()
	var at: Vector3 = yard_point("pod")
	var site: Node3D = CrashSite.attach(w, pod, at, 0.5)
	site.global_basis = SphereGrid.frame(at.normalized()) * Basis(Vector3.UP, 0.5)
	EscapePod.set_open(pod, true, CrashSite.LEAN.x)
	pod_body(pod)  # [v1yard] colliders that fit the model (it was one box round the fins and the open ramp)
	w.set_meta("orbit_pod", site)


## [v1yard] The crashed pod's colliders, fitted to EscapePod's model in its own (leaning) frame: the
## shell as a cylinder (r 0.8 m, the widest facet), one thin slab per landing fin, and nothing for
## the open ramp on the ground or the tapering top above Lumi's head. A child of the pod, so it
## follows the pod when reseat_yard moves it. Lumi can walk right round it and up to the door.
static func pod_body(pod: Node3D) -> StaticBody3D:
	var old: Node = pod.get_node_or_null("PodBody")
	if old:
		old.free()
	var b := StaticBody3D.new()
	b.name = "PodBody"
	b.collision_layer = PhysLayers.PROP
	b.collision_mask = 0
	b.add_to_group("prop_body")
	pod.add_child(b)
	var shell := CollisionShape3D.new()
	shell.name = "Shell"
	shell.shape = PropColliders.cyl_shape(0.8, 2.0)
	shell.position = Vector3(0, 1.0, 0)
	b.add_child(shell)
	for k: int in 3:
		var fin: Node3D = pod.get_node_or_null("Fin%d" % k)
		if fin == null:
			continue
		var cs := CollisionShape3D.new()
		cs.name = "Fin%d" % k
		cs.shape = PropColliders.box_shape(Vector3(0.14, 1.0, 0.62))
		cs.transform = fin.transform * Transform3D(Basis(), Vector3(0, 0.5, 0.95))
		b.add_child(cs)
	return b


## Camp (systems/camp/camp.gd) as on the flat game: the broken bench is its "bench" bit, the
## yard builds (lean-to, generator, lamps, press, radio, locker, nursery, Blink) keep their
## built state in the hub's dict, and the bin's reach is the start site's "bin" anchor. The
## yard models on the anchors are orbD's / yard's; Camp shows and hides what exists.
func _attach_camp() -> void:
	var sp0: SitePrefab = globe.site_manager.prefab(0) if globe.site_manager else null  # [orbD] the yard's models on the anchors
	if sp0:
		var ys: YardSite = YardSite.build(w, sp0, bench)
		w.set("_ruin_bits", ys.bits)
	else:
		w.set("_ruin_bits", {"bench": bench})
	await BuildBudget.idle()  # [v5load] the yard models build across frames
	await BuildBudget.check("camp:yard site")  # [v5load]
	var camp: Camp = Camp.attach(w)
	await BuildBudget.idle()  # [v5load] its setup hands frames back behind the loader
	w.set("camp", camp)
	if camp == null:
		_apply_bench(Camp.bench_ok(), false)
	var locker: Node3D = w.get_node_or_null("LockerCabinet") as Node3D
	if locker:
		var slot: Array = yard_slot("locker", LockerCabinet.POS)
		locker.global_transform = (slot[0] as Node3D).global_transform * (slot[1] as Transform3D)
		var reach: Node3D = locker.get("_anchor") as Node3D
		if reach:
			reach.global_position = locker.global_position + locker.global_basis.z * 0.9
	if camp.camera_bot:
		var home: Vector3 = yard_point("camera_bot")
		camp.camera_bot.set("_home", home)
		camp.camera_bot.global_position = home + home.normalized() * 1.5
	if sp0:  # [orbD] anchors that settle later (moved out of another planet's geometry) carry their interactables
		sp0.anchors_moved.connect(func(_names: PackedStringArray) -> void: reseat_yard())


## [orbD] Re-reads the start site's anchors for everything attached to them at setup: the signal
## tower, the locker and its reach point, Blink's home and the trash bin's reach point. (The
## depot, bench and the yard models follow the anchors on their own: OrbitSites / YardSite.)
func reseat_yard() -> void:
	var tower: Node3D = w.get_node_or_null("SignalTower") as Node3D
	if tower:
		var ts: Array = yard_slot("signal_tower", SignalTower.pos())
		tower.global_transform = (ts[0] as Node3D).global_transform * (ts[1] as Transform3D)
	var locker: Node3D = w.get_node_or_null("LockerCabinet") as Node3D
	if locker:
		var ls: Array = yard_slot("locker", LockerCabinet.POS)
		locker.global_transform = (ls[0] as Node3D).global_transform * (ls[1] as Transform3D)
		var reach: Node3D = locker.get("_anchor") as Node3D
		if reach:
			reach.global_position = locker.global_position + locker.global_basis.z * 0.9
	var camp: Camp = w.get("camp")
	if camp and camp.camera_bot:
		var home: Vector3 = yard_point("camera_bot")
		camp.camera_bot.set("_home", home)
		camp.camera_bot.global_position = home + home.normalized() * 1.5
	var bin_reach: Variant = camp.get("_bin_anchor") if camp else null
	if bin_reach is Node3D:
		(bin_reach as Node3D).global_position = yard_point("bin")
	var dep: Variant = w.get("depot")  # [v3clear] the bin body follows its anchor too
	if dep is Depot and globe.site_manager and globe.site_manager.prefab(0):
		(dep as Depot).seat_bin(globe.site_manager.prefab(0))
	var cmp: Node3D = w.get("composter") as Node3D  # the compost press
	if cmp:
		var cs: Array = yard_slot("composter", Composter.POS)
		cmp.global_transform = (cs[0] as Node3D).global_transform * (cs[1] as Transform3D)
	# [orbB] the CD player, the nursery, the Telescope and the crashed pod follow their anchors too
	var ex: ExtrasDirector = ExtrasDirector.of(w)
	if ex and ex.radio:
		var rs: Array = yard_slot("radio", Radio.POS)
		ex.radio.global_transform = (rs[0] as Node3D).global_transform * (rs[1] as Transform3D)
		var rr: Node3D = ex.radio.get("_anchor") as Node3D
		if rr:
			rr.global_position = ex.radio.global_position + ex.radio.global_basis.x * 1.0
	if ex and ex.nursery:
		var ns: Array = yard_slot("nursery", ex.nursery.position)
		ex.nursery.global_transform = (ns[0] as Node3D).global_transform * (ns[1] as Transform3D)
		ex.nursery.set("center", ex.nursery.global_position)
	var scope: Telescope = Telescope.of(w)
	if scope:
		var tp: Vector3 = scope.call("_pos")
		var tsl: Array = yard_slot("telescope", tp)
		scope.global_transform = (tsl[0] as Node3D).global_transform * (tsl[1] as Transform3D) * Transform3D(Basis(), -tp)
	var pod_site: Node3D = w.get_meta("orbit_pod", null) as Node3D
	if pod_site:
		var at: Vector3 = yard_point("pod")
		pod_site.global_transform = Transform3D(SphereGrid.frame(at.normalized()) * Basis(Vector3.UP, 0.5), at)
	if DevHooks.has("yard-report"):
		var dd := func(n: Variant, anchor: String) -> String:
			return "%.2f" % (n as Node3D).global_position.distance_to(yard_point(anchor)) if n is Node3D else "-"
		print("[yard] reseated: tower %s, locker %s, bin reach %s (m from their anchors)" % [dd.call(tower, "signal_tower"), dd.call(locker, "locker"), dd.call(bin_reach, "bin")])


# --- Hub and workbench (the start site) ---------------------------------------------------

const BENCH_RANGE: float = 3.2


## The base: hub.json levels, costs and scrubbers, logic only (the site prefab shows each level).
## Its level lives in GameState.world (the start site's dict) and drives the site's stage.
func _build_hub() -> void:
	var hub := Hub.new()
	hub.name = "Hub"
	hub.visuals = false
	w.add_child(hub)
	w.set("hub", hub)
	_sync_hub_level(hub.level)
	hub.level_changed.connect(_sync_hub_level)


func _sync_hub_level(l: int) -> void:
	hub_states["0"] = {"level": l}
	var sm: SiteManager = globe.site_manager
	if sm:
		sm.set_level(0, l)


## The workbench: the start site's "bench" anchor (falls back to the pad centre).
func bench_position() -> Vector3:
	var sm: SiteManager = globe.site_manager
	var sp: SitePrefab = sm.prefab(0) if sm else null
	if sp:
		return sp.global_transform * sp.anchor_local("bench").origin
	return globe.site_point(0, Vector3(-3.6, 0, 2.2))


func near_bench() -> bool:
	var patch: Patch = w.get("patch")
	return patch != null and patch.global_position.distance_to(bench_position()) < BENCH_RANGE


func _build_upgrades() -> void:
	var up := UpgradesScreen.new()
	up.fleet = w.get("fleet")
	up.hub = w.get("hub")
	up.build_at = func() -> Vector3: return bench_position() + bench_position().normalized() * 0.2
	w.add_child(up)
	up.closed.connect(on_modal_closed)
	w.set("upgrades", up)


## slice.gd's open_upgrades: only at the bench (Tab elsewhere peeks the key hints).
func open_upgrades() -> void:
	var pm: PauseMenu = w.get("pause_menu")
	if pm.is_open:
		return
	if not near_bench() and not DevHooks.has("open"):
		var hud: Node = w.get("hud")
		if hud and hud.has_method("peek_hints"):
			hud.call("peek_hints")
		if not GameState.flags.get("bench_hint_seen", false):
			GameState.flags["bench_hint_seen"] = true
			EventBus.toast.emit(tr("Upgrades need a workbench. Head back to the hub."), "info")
		return
	if not Camp.bench_ok() and not DevHooks.has("open"):  # the first E repairs the broken bench
		var camp: Camp = w.get("camp")
		if camp:
			camp.repair_bench()
		else:
			repair_bench()
		return
	(w.get("upgrades") as UpgradesScreen).open_screen()
	set_input(false)


# --- The broken workbench (Camp's rules on the start site's bench anchor) -----------------------

var bench: Node3D
var _bench_parts: Array = []  # [node, repaired transform, broken transform]
var _repairing: bool = false


func _build_bench() -> void:
	var sm: SiteManager = globe.site_manager
	var sp: SitePrefab = sm.prefab(0) if sm else null
	bench = Node3D.new()
	bench.name = "Workbench"
	if sp:
		sp.add_child(bench)
		bench.transform = sp.anchor_local("bench")
	else:
		globe.start_site.add_child(bench)
		bench.position = Vector3(-3.6, 0, 2.2)
	var top := MeshInstance3D.new()
	var bparts: Array = [ProcMesh.part(ProcMesh.box(Vector3(2.2, 0.06, 0.8)), ProcMesh.xf(Vector3(0, 0.92, 0)))]
	for x: float in [-1.0, 1.0]:
		for z: float in [-0.33, 0.33]:
			bparts.append(ProcMesh.part(ProcMesh.box(Vector3(0.06, 0.9, 0.06)), ProcMesh.xf(Vector3(x, 0.45, z))))
	bparts.append(ProcMesh.part(ProcMesh.box(Vector3(2.0, 0.03, 0.7)), ProcMesh.xf(Vector3(0, 0.25, 0))))
	top.mesh = ProcMesh.merge(bparts)
	top.material_override = Mats.worn_paint(Color(0.32, 0.38, 0.45), 0.5, 0.6, 12.0, 0.7)
	bench.add_child(top)
	_bench_parts.append([top, Transform3D(), Transform3D(Basis(Vector3.BACK, 0.32) * Basis(Vector3.UP, 0.25), Vector3(0.1, -0.12, 0.05))])
	var i: int = 0
	for spec: Array in [["metal_toolbox", Vector3(-0.6, 0.95, 0.0), 0.2], ["clipboard", Vector3(0.35, 0.955, 0.1), 0.0], ["oil_tin", Vector3(0.8, 0.95, -0.2), 0.0]]:
		var mi := MeshInstance3D.new()
		mi.mesh = AssetLib.model_mesh_lite(spec[0], 3000) if AssetLib.has_model(spec[0]) else ProcMesh.box(Vector3(0.3, 0.2, 0.2))
		var fixed := Transform3D(Basis(Vector3.UP, spec[2]), spec[1])
		var broken := Transform3D(Basis.from_euler(Vector3(1.1 - i * 0.6, i * 1.7, 1.3 - i * 0.9)), Vector3(-0.9 + i * 0.7, 0.08, 0.6 + (i % 2) * 0.2))
		mi.transform = fixed
		bench.add_child(mi)
		_bench_parts.append([mi, fixed, broken])
		i += 1
	var pb: StaticBody3D = PropColliders.body(bench, "BenchBody")  # top level, world space
	PropColliders.add_box(pb, bench.global_transform * Transform3D(Basis(), Vector3(0, 0.47, 0)), Vector3(2.2, 0.95, 0.8))
	# Its broken look is Camp's (it records this repaired pose first); see _attach_camp.


func _apply_bench(ok: bool, animate: bool) -> void:
	for e: Array in _bench_parts:
		var n: Node3D = e[0]
		var to: Transform3D = e[1] if ok else e[2]
		if animate:
			create_tween().tween_property(n, "transform", to, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			n.transform = to


## Camp.repair_bench on the globe: the beam welds along the bench, it rights itself, then works.
func repair_bench() -> void:
	if _repairing or Camp.bench_ok():
		return
	_repairing = true
	var patch: Patch = w.get("patch")
	set_input(false)
	var up: Vector3 = bench.global_position.normalized()
	var target: Vector3 = bench.global_position + up * 0.9
	var dur: float = float(Camp.cfg().get("bench_repair_s", 2.6))
	var tw := create_tween()
	tw.tween_callback(func() -> void:
		patch.model.call("beam_at", target)
		patch.model.call("shudder", 0.25)
		Audio.play("servo", 1.1, -6.0))
	for k: int in 6:
		tw.tween_callback(func() -> void:
			var at: Vector3 = target + bench.global_basis.x * lerpf(-0.9, 0.9, k / 5.0)
			patch.model.call("beam_at", at)
			Vfx.burst("sparkle", at, Color(1.0, 0.75, 0.35), 0.35)
			Audio.play("tick" if k % 2 == 0 else "clink", randf_range(0.9, 1.3), -8.0))
		tw.tween_interval(dur * 0.5 / 6.0)
	tw.tween_callback(func() -> void:
		Audio.play("hydraulic", 1.0, -6.0)
		_apply_bench(true, true))
	tw.tween_interval(dur * 0.5)
	tw.tween_callback(func() -> void:
		patch.model.call("beam_at", null)
		patch.model.call("set_happy", 1.0)
		Camp.set_bench_ok(true)
		_repairing = false
		set_input(true)
		GameState.inc_stat("bench_repaired")
		Audio.play("chime", 1.0, -4.0)
		EventBus.toast.emit(tr("Workbench fixed. Press E at it to spend cubes on upgrades."), "info"))


func open_codex(tab: String = "") -> void:
	var cx: CodexScreen = w.get("codex")
	if cx == null or cx.is_open:
		return
	var pm: PauseMenu = w.get("pause_menu")
	if pm and pm.is_open:  # [ui7] never stack the Codex on the pause menu
		pm.close_menu()
	cx.open_screen(tab)
	set_input(false)


func set_input(on: bool) -> void:
	var patch: Patch = w.get("patch")
	if patch and patch.input is PlayerInput:
		(patch.input as PlayerInput).enabled = on
	cam.input_enabled = on


func on_modal_closed() -> void:
	set_input(true)
	if not w.get("bot") and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func unhandled_input(event: InputEvent) -> void:
	var pm: PauseMenu = w.get("pause_menu")
	if any_modal_open():
		return
	if event.is_action_pressed("open_codex") and w.get("codex"):
		open_codex()
		w.get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_upgrades"):
		open_upgrades()
		w.get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_command"):
		cam.view = "follow" if cam.view == "command" else "command"
		crews.on_view(self)  # [orbC]
		w.get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		pm.open_menu()
		set_input(false)
		w.get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not w.get("bot"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Persistence: GameState.orbit -------------------------------------------------------
## Separate from the flat district state (world / districts / planet_state), which an orbit run
## never rewrites, so the flat game keeps its save until phase F. Positions are direction +
## height above the ground (OrbitPlanet.to_dirh), never x/z.

func persist_save() -> void:
	var g: OrbitPlanet = globe
	var patch: Patch = w.get("patch")
	var cubes: Array = []
	var root: Node = w.get("_cubes_root")
	for n: Node in root.get_children():
		var c: JunkCube = n as JunkCube
		if c and not c.carried and not c.claimed:
			var cd: Dictionary = c.to_dict()
			cd.erase("pos")
			cd["at"] = g.to_dirh(c.global_position)
			cd["basis"] = _basis_arr(c.global_basis)
			cubes.append(cd)
	var gdn: Garden = w.get("garden")
	if gdn:
		GameState.world["garden"] = gdn.persist()  # the hub's dict (GameState.world on the globe)
	var pd: Dictionary = patch.to_dict()
	pd.erase("pos")
	pd.erase("yaw")
	var keep: Dictionary = {}  # [v5play] the rocket's keys live in the old dict (OrbitSites sets them on a hop)
	for k: String in ROCKET_KEYS:
		if GameState.orbit.has(k):
			keep[k] = GameState.orbit[k]
	GameState.orbit = {
		"schema": SCHEMA,
		"planet_id": str(g.spec.get("id", "verdance")),
		"freq": g.grid.freq,
		"seed": g.seed_value,
		"cells_n": g.grid.cell_count(),
		"planet": g.planet.to_dict(),
		"cells": g.cells.to_dict(),
		"field": g.field.to_dict(),  # found parts, unlocked cells
		"sites": OrbitSave.sites_to_array(g.sites),
		"hubs": hub_states,
		"hub_worlds": {"0": GameState.world},
		"migrated": str(GameState.orbit.get("migrated", "")),
		"hexes_paid": GameState.orbit.get("hexes_paid", {}),
		"hex_levels": (w.get("hex_levels") as HexLevels).persist(),
		"day_t": day.elapsed(),
		"lumi": {"at": g.to_dirh(patch.global_position), "fwd": _v_arr(patch.forward()), "cargo": pd},
		"cubes": cubes,
		"robots": crews.save_crew(),  # [orbC]
		"site_state": sites.save_state() if sites else {},  # [orbD] built hubs, levels, growth (main: renamed from "sites", which orbB uses for site geometry)
	}
	GameState.orbit.merge(keep)


## [v5play] Kept across saves: where the rocket stands, that Lumi owns it, the hubs he has flown to.
## (save_world rebuilt GameState.orbit without them: after a hop, a save and a reload, Lumi stood
## at the far hub and the rocket was back on the start pad, or gone below base level 5.)
const ROCKET_KEYS: Array[String] = ["rocket_site", "rocket_owned", "hubs_flown"]


func restore_world() -> void:
	var g: OrbitPlanet = globe
	var od: Dictionary = GameState.orbit
	if int(od.get("schema", 0)) < 1:
		return
	day.set_elapsed(float(od.get("day_t", 0.0)))
	var root: Node = w.get("_cubes_root")
	for cd: Dictionary in od.get("cubes", []):
		var c: JunkCube = JunkCube.from_dict(cd)
		root.add_child(c)
		c.global_position = g.from_dirh(cd.get("at", [0.0, 1.0, 0.0, 0.5])) + g.from_dirh(cd.get("at", [0.0, 1.0, 0.0, 0.5])).normalized() * 0.02
		if cd.has("basis"):
			c.global_basis = _arr_basis(cd["basis"])
	var patch: Patch = w.get("patch")
	var ld: Dictionary = od.get("lumi", {})
	if ld.has("at"):
		var p: Vector3 = g.from_dirh(ld["at"])
		var f: Array = ld.get("fwd", [0.0, 0.0, -1.0])
		patch.place_on_sphere(p, Vector3(float(f[0]), float(f[1]), float(f[2])))
		cam.reset_frame(patch.forward())
		cam.snap()
		if DevHooks.has("intro"):
			var pod_site: Node3D = w.get_meta("orbit_pod", null)
			print("[intro] globe: Lumi %.2f m above the ground, %.1f m from the pod, pod placed=%s" % [
				globe.surface.altitude(patch.global_position), patch.global_position.distance_to(pod_site.global_position) if pod_site else -1.0, str(pod_site != null)])
	patch.restore_cargo(ld.get("cargo", {}))
	if sites:  # [orbD]
		sites.load_state(od.get("site_state", {}))
	crews.restore_crew(self, od, not from_memory)  # [orbC] crew + offline jump


static func _v_arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]


static func _basis_arr(b: Basis) -> Array:
	var o: Basis = b.orthonormalized()
	return _v_arr(o.x) + _v_arr(o.y) + _v_arr(o.z)


static func _arr_basis(a: Array) -> Basis:
	if a.size() < 9:
		return Basis()
	return Basis(Vector3(float(a[0]), float(a[1]), float(a[2])), Vector3(float(a[3]), float(a[4]), float(a[5])), Vector3(float(a[6]), float(a[7]), float(a[8]))).orthonormalized()
