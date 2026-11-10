class_name OrbitLayers
extends Node
## [orbE] Phase E on the real slice (--orbit, scenes/slice_orbit.gd): the sky and day/night
## (SkyDirector's sphere mode takes over OrbitDay's environment, suns and sky shader), Glim's
## lantern in place of the stand-in Lumi lamp, the Future Layer on chunks, the survey hologram
## (M), the system map (from the hologram) and photo mode. Everything sits on the slice's
## usual names (sky_director, globe, photo) so the game's systems find it. One call from
## SliceOrbit.build: OrbitLayers.attach(self).

var so: SliceOrbit
var sky: SkyDirector
var glim: GlimBot
var future: FutureLayerSphere
var survey: GlobeView
var system_map: SystemMap
var lumi_lod: LumiLod


static func attach(p_so: SliceOrbit) -> OrbitLayers:
	var l := OrbitLayers.new()
	l.name = "OrbitLayers"
	l.so = p_so
	p_so.w.add_child(l)
	l._build()
	return l


func _build() -> void:
	var w: Node3D = so.w
	var g: OrbitPlanet = so.globe
	var day: OrbitDay = so.day
	var patch: Patch = w.get("patch")
	# Sky: SkyDirector drives OrbitDay's environment, primary sun and sky shader from now on.
	day.set_process(false)
	if day.sun2:
		day.sun2.visible = false  # the director's companion fill replaces it
	if day.lamp and Glim.is_found():  # [v1yard] Glim carries the local light once he is found; Lumi's lamp until then
		day.lamp.queue_free()
		day.lamp = null
	sky = SkyDirector.new()
	sky.name = "SkyDirector"
	sky.world = w
	sky.day_period_s = day.day_min * 60.0
	sky.player_fn = func() -> Vector3: return patch.global_position
	sky.eye_fn = func() -> Vector3: return so.cam.camera.global_position if so.cam and so.cam.camera else patch.global_position
	sky.space_fn = func() -> bool: return day.space_view
	sky.clean_fn = func() -> float: return g.cells.clean_fraction()
	sky.fog_scale = 0.27 if so.view_mode == "command" else 1.0
	w.add_child(sky)
	var forced: bool = DevHooks.has("orbit-time") or not GameState.flags.has("orbit_spin")
	sky.setup_sphere(day.env, day.sun, day.sky_mat, g.grid.radius_m, DevHooks.get_f("orbit-time", 0.42) if forced else -1.0)
	if DevHooks.has("orbit-clouds"):
		sky.clouds = DevHooks.get_f("orbit-clouds", 0.4)
		sky.weather_frozen = true
	if DevHooks.has("orbit-freeze-time") or DevHooks.has("time"):
		if DevHooks.has("time"):
			sky.time_of_day = DevHooks.get_f("time", 0.5)
			sky.spin = SkyDirector.spin_for_local_time(sky.time_of_day, patch.global_position)
		sky.frozen = true
	w.set("sky_director", sky)
	# [v1yard] Glim, the light buddy, comes as on the flat game: GlimDirector finds him in the junk
	# (5 min and 25 pieces in, or the first dusk) and keeps his body. Not at the start.
	_sync_glim()
	# The Future Layer per cell on the near chunks.
	future = FutureLayerSphere.new()
	future.name = "FutureLayer"
	w.add_child(future)
	future.setup(g.grid, g.terrain, g.cells, g.streamer)
	future.eye_fn = sky.eye_fn
	future.sky = sky
	if DevHooks.has("orbit-future"):
		print("[future] dev levels on %d cells" % FutureLayerSphere.dev_seed(g.cells, g.grid, g.grid.cell_at(patch.global_position), int(DevHooks.get_f("orbit-future", 10.0))))
	# Survey hologram, system map, photo mode.
	survey = GlobeView.new()
	survey.planet = g.planet
	survey.cells = g.cells
	survey.shell = g.streamer.shell
	survey.sphere_grid = g.grid
	survey.patch_cell_provider = func() -> int: return g.grid.cell_at(patch.global_position)
	survey.holder = patch
	survey.world_root = w
	survey.hub_dirs = func() -> Array:  # [v2map] sprout glyphs on the map
		var out: Array = []
		if g.site_manager:
			for st: Dictionary in g.site_manager.sites:
				out.append((st["transform"] as Transform3D).origin.normalized())
		return out
	survey.pod_dir = func() -> Vector3:  # [v2map] the crashed pod's smoke plume
		var site: Node3D = g.start_site
		var pod: Node3D = site.find_child("pod", true, false) as Node3D if site else null
		return (pod.global_position - g.global_position).normalized() if pod else Vector3.ZERO
	survey.travel_in_map = false  # [v2map] travel is at the rocket (planet/sites/orbit_sites.gd)
	survey.planet_fraction_fn = func() -> float: return so.sites.planet_fraction() if so.sites else 0.0  # [v5text] the HUD's planet %
	survey.hub_count = func() -> int: return g.site_manager.sites.size() if g.site_manager else g.planet.hubs.size()  # [v2map] the legend counted the flat hubs
	w.add_child(survey)
	survey.closed.connect(so.on_modal_closed)
	w.set("globe", survey)
	system_map = SystemMap.shared(w)  # [v5text] one map: the Homeward campaign uses this same node
	survey.open_system = func() -> void: system_map.open_map(true)
	var lens := LensOverlay.new()  # [orbE] the lens view's dressing (SphereCam.lens_view)
	lens.name = "LensOverlay"
	lens.cam = so.cam
	lens.patch = patch
	w.add_child(lens)
	if DevHooks.has("lens"):  # as on the flat slice: start in the lens view
		so.cam.lens_view = true
	var photo := PhotoMode.new()
	photo.world = w
	w.add_child(photo)
	w.set("photo", photo)
	OrbitQuality.apply_world(sky, future, Settings.quality)
	if DevHooks.has("orbit-survey"):
		get_tree().create_timer(DevHooks.get_f("orbit-survey", 3.0)).timeout.connect(open_survey)
	if DevHooks.has("orbit-sysmap"):
		get_tree().create_timer(DevHooks.get_f("orbit-sysmap", 3.0)).timeout.connect(func() -> void: system_map.open_map(true))
	# Lumi far away (Command view): one merged proxy without shadows instead of the 27-mesh rig.
	var model: Node3D = patch.get("model") as Node3D
	if model:
		lumi_lod = LumiLod.new()
		lumi_lod.name = "LumiLod"
		add_child(lumi_lod)
		lumi_lod.setup(model, sky.eye_fn)
		if DevHooks.has("load-report"):
			print("[orbit-load] lumi lod: %d rig surfaces -> %d far, no shadow" % [lumi_lod.stats["surfaces_in"], lumi_lod.stats["surfaces_out"]])
	place_intro.call_deferred()  # [orbE] if the slice made an Intro (orbB ports the pod onto the "pod" anchor)
	if DevHooks.has("orbit-tour"):
		var tour := OrbitSkyTour.new()
		tour.sky = sky
		add_child(tour)


## The intro's in-world shots (crash, landing, pod) in the start site's "pod" anchor frame
## (story/intro.gd site_xf). Called once the slice has an Intro; safe to call again.
func place_intro() -> bool:
	var it: Variant = so.w.get("intro")
	var site: Node3D = so.globe.start_site
	if not (it is Intro) or site == null:
		return false
	var anchor: Node3D = site.find_child("pod", true, false) as Node3D
	var xf: Transform3D = anchor.global_transform if anchor else site.global_transform
	(it as Intro).site_xf = Intro.site_for_anchor(Transform3D(xf.basis.orthonormalized(), xf.origin))
	return true


func open_survey() -> void:
	if survey.is_open or system_map.is_open or so.any_modal_open():
		return
	if so.sites and so.sites.picker and so.sites.picker.is_open:  # [v2map] the rocket's list is up
		return
	so.set_input(false)
	survey.open_view()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_globe") and not survey.is_open:
		open_survey()
		get_viewport().set_input_as_handled()


## [v1yard] GlimDirector's Glim (once found) lights by this sky; Lumi's own lamp goes then.
func _sync_glim() -> void:
	var gd: GlimDirector = GlimDirector.of(so.w)
	glim = gd.bot if gd else null
	if glim and glim.sky == null:
		glim.sky = sky
	if glim and so.day.lamp:
		so.day.lamp.queue_free()
		so.day.lamp = null


func _process(_delta: float) -> void:
	if glim == null and Glim.is_found():
		_sync_glim()
	sky.fog_scale = 0.27 if so.cam and so.cam.view == "command" else 1.0
	so.day.stats["local_time"] = sky.time_of_day
	so.day.stats["daylight"] = sky.daylight
