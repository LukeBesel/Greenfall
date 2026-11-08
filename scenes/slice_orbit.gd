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
## site prefab shows its stage), the workbench (bench anchor) + Upgrades, Research/Achievements/
## Codex, music, WREN + subtitles, Goals, the restart checklist (Tutorial), Requests (Contracts).
## GameState.world is the start site's own dict (GameState.use_orbit_world).
## Not ported yet (left null on the slice, skipped): CityLayout/CityView/StreetDressing/litter/
## far junk/water (orbD sites), Fleet/robot builder/Command view (orbC), SkyDirector/GlobeView/
## FutureLayer (orbE), Camp (bench repair, trash bin, yard builds), garden, events, intro/
## objectives/signal tower, core charge, outposts, eggs, ledger, telescope, extras, Glim, photo.
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
var view_mode: String = "follow"
var sites: OrbitSites  # [orbD]
var hub_states: Dictionary = {}  # site index (str) -> {level} (core/save_orbit.gd); the Hub port fills it


## True when --orbit asks for the slice on the globe (not one of the phase A prototypes).
static func wanted() -> bool:
	return DevHooks.has("orbit") and not DevHooks.get_s("orbit", "") in ["v1", "globe"]


## Builds the whole orbit slice into `p_world`. Synchronous (no BuildBudget yields yet).
func build(p_world: Node3D) -> void:
	w = p_world
	var t0: int = Time.get_ticks_msec()
	get_tree().paused = false
	var loaded: bool = false
	if GameState.reload_in_memory:
		GameState.reload_in_memory = false
		loaded = true
	elif not DevHooks.has("fresh"):
		loaded = SaveManager.load_game()
	var od: Dictionary = OrbitSave.migrate(GameState.orbit) if loaded else {}
	# The planet: --orbit-planet=<id>, else the saved one, else Verdance. Its size is data (GlobeSpec).
	var pid: String = GlobeSpec.current_id() if DevHooks.has("orbit-planet") else str(od.get("planet_id", "verdance"))
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
	globe.build(seed_v, spec, int(DevHooks.get_f("orbit-hubs", -1.0)), od.get("planet", {}), od.get("cells", {}), OrbitSave.site_cells(od), hook)
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
	for i: int in range(1, globe.sites.size()):
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
	var site: Node3D = globe.build_start_site()
	_build_patch()
	_build_depot(site)
	sites = OrbitSites.attach(self)  # [orbD] sled, rocket hops, planet %, site state
	_build_hub()
	if DevHooks.has("orbit-bots") or not DevHooks.has("orbit-walk"):
		crews.spawn_demo_bots(globe.start_cell(), int(DevHooks.get_f("orbit-bots", 4.0)), w)
	var hl := HexLevels.new()  # sparse: only cleaned cells are tracked; levels also go to SphereCells
	hl.name = "HexLevels"
	hl.world = w
	hl.sparse = true
	w.set("hex_levels", hl)  # before add_child: its tree-entered hooks may read world.hex_levels
	w.add_child(hl)
	hl.setup()
	EventBus.hex_level_changed.connect(_on_hex_level)
	var lumi_level := LumiLevel.new()
	lumi_level.name = "LumiLevel"
	lumi_level.world = w
	w.add_child(lumi_level)
	w.set("lumi_level", lumi_level)
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
	_build_upgrades()
	w.call("_setup_research_codex")  # slice.gd's own: Research, Achievements, the Codex (UI + data)
	_build_story()
	if loaded and not migrate:
		restore_world()
	elif migrate:
		(w.get("patch") as Patch).restore_cargo(OrbitMigrate.lumi_cargo())
	globe.update_centres()
	var t2: int = Time.get_ticks_msec()
	globe.streamer.settle()
	globe.stats["settle_ms"] = Time.get_ticks_msec() - t2
	var t3: int = Time.get_ticks_msec()
	globe.refresh_junk_now()
	globe.stats["junk_fill_ms"] = Time.get_ticks_msec() - t3
	Settings.apply_quality_to_tree(w)
	day.after_quality(view_mode == "command")
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
	w.emit_signal("built")


func _build_patch() -> void:
	var g: OrbitPlanet = globe
	var hub_cell: int = g.start_cell()
	var spawn_dir: Vector3 = g.terrain.local_to_dir(hub_cell, 0.0, 6.0)
	var north: Vector3 = -SphereGrid.frame(spawn_dir).z
	cam = SphereCam.new()
	cam.name = "SphereCam"
	cam.surface = g.surface
	var patch := Patch.new()
	patch.name = "Patch"
	patch.world = w
	match DevHooks.get_s("orbit-walk", "") if DevHooks.has("orbit-walk") else "-":
		"-":
			patch.input = SphereInput.new()
		"boost":
			patch.input = SphereAutoInput.new(Vector3(0, 0, -1), true)
		_:
			patch.input = SphereAutoInput.new(Vector3(0, 0, -1), false)
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


## slice.gd's _on_hex_clean by cell id: first-clean bonus (a re-dirtied cell pays only the flat
## part again and doesn't count twice), milestones, the first hex's fanfare, the event.
func on_hex_clean(hid: int) -> void:
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
	Audio.play("chime", 1.0, -3.0)
	Vfx.burst("big_sparkle", center + u * 0.3, Color(1.0, 0.92, 0.55))
	Vfx.ring(center, field.hex_size * 1.1, Color(1.0, 0.9, 0.5, 0.9), 0.8)
	Vfx.float_text(center + u * 1.4, tr("HEX CLEAN!  +%s") % Settings.fmt(bonus), Color(1.0, 0.92, 0.45), 1.5, 2.0)
	EventBus.hex_cleaned.emit(hid, center, bonus)
	EventBus.field_progress_changed.emit(field.cleaned_count, field.junk_hex_count)
	if patch:
		patch.model.set_happy(1.0)
	var n: int = cleaned_by_lumi()
	if n == 1 and first:
		EventBus.hitstop_requested.emit(0.45, 0.25)
		Audio.play("fanfare", 1.0, -4.0)
	if n in HEX_MILESTONES and not GameState.flags.get("hexm_%d" % n, false):
		GameState.flags["hexm_%d" % n] = true
		EventBus.milestone_reached.emit("hexes_%d" % n)
		if n > 1:
			Audio.play("fanfare", 1.0, -5.0)
			if patch:
				Vfx.burst("confetti", patch.global_position + patch.up() * 1.5, Color.WHITE)
			EventBus.toast.emit(tr("Milestone: %d hexes clean!") % n, "story")


## Hexes counted for milestones: the cells this save paid a first-clean bonus for (far crews'
## numbers flip cells clean too, but they are not Lumi's milestones).
func cleaned_by_lumi() -> int:
	return (GameState.orbit.get("hexes_paid", {}) as Dictionary).size()


func _on_hex_level(hid: int, lvl: int) -> void:
	if globe and hid >= 0 and hid < globe.cells.n:
		globe.cells.set_level(hid, lvl)


func cell_at(pos: Vector3) -> int:
	return globe.cell_at(pos)


func try_interact(_p: Patch) -> void:
	if near_bench():
		open_upgrades()


func interact_prompt(_p: Patch) -> String:
	if near_bench():
		return "upgrades"
	return sites.interact_prompt() if sites else ""  # [orbD] the hover-sled


func any_modal_open() -> bool:
	for k: String in ["pause_menu", "upgrades", "codex"]:
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
	var ct := Contracts.new()
	ct.name = "Contracts"
	ct.world = w
	w.add_child(ct)
	w.set("contracts", ct)


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
	(w.get("upgrades") as UpgradesScreen).open_screen()
	set_input(false)


func open_codex(tab: String = "") -> void:
	var cx: CodexScreen = w.get("codex")
	if cx == null or cx.is_open:
		return
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
	var pd: Dictionary = patch.to_dict()
	pd.erase("pos")
	pd.erase("yaw")
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
		"site_state": sites.save_state() if sites else {},  # [orbD] built hubs, levels, growth (main: renamed from "sites", which orbB uses for site geometry)
	}


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
	patch.restore_cargo(ld.get("cargo", {}))
	if sites:  # [orbD]
		sites.load_state(od.get("site_state", {}))


static func _v_arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]


static func _basis_arr(b: Basis) -> Array:
	var o: Basis = b.orthonormalized()
	return _v_arr(o.x) + _v_arr(o.y) + _v_arr(o.z)


static func _arr_basis(a: Array) -> Basis:
	if a.size() < 9:
		return Basis()
	return Basis(Vector3(float(a[0]), float(a[1]), float(a[2])), Vector3(float(a[3]), float(a[4]), float(a[5])), Vector3(float(a[6]), float(a[7]), float(a[8]))).orthonormalized()
