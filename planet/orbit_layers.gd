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
	if day.lamp:
		day.lamp.queue_free()  # Glim carries the local light
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
	# Glim, the light buddy.
	glim = GlimBot.new()
	glim.name = "Glim"
	w.add_child(glim)
	glim.target = patch
	glim.sky = sky
	glim.set_light(Glim.value("light", "range", 6.0), Glim.value("light", "energy", 1.1))
	glim.snap_to_target()
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
	w.add_child(survey)
	survey.closed.connect(so.on_modal_closed)
	w.set("globe", survey)
	system_map = SystemMap.new()
	system_map.name = "SystemMap"
	system_map.world = w
	w.add_child(system_map)
	survey.open_system = func() -> void: system_map.open_map(true)
	var photo := PhotoMode.new()
	photo.world = w
	w.add_child(photo)
	w.set("photo", photo)
	OrbitQuality.apply_world(sky, future, Settings.quality)
	if DevHooks.has("orbit-survey"):
		get_tree().create_timer(DevHooks.get_f("orbit-survey", 3.0)).timeout.connect(open_survey)
	if DevHooks.has("orbit-sysmap"):
		get_tree().create_timer(DevHooks.get_f("orbit-sysmap", 3.0)).timeout.connect(func() -> void: system_map.open_map(true))
	if DevHooks.has("orbit-tour"):
		var tour := OrbitSkyTour.new()
		tour.sky = sky
		add_child(tour)


func open_survey() -> void:
	if survey.is_open or system_map.is_open or so.any_modal_open():
		return
	so.set_input(false)
	survey.open_view()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_globe") and not survey.is_open:
		open_survey()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	sky.fog_scale = 0.27 if so.cam and so.cam.view == "command" else 1.0
	so.day.stats["local_time"] = sky.time_of_day
	so.day.stats["daylight"] = sky.daylight
