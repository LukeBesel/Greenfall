class_name SphereDemo
extends Node3D
## [sgrid] Demo of the hex globe foundation (dev flag --sphere-demo, or run
## res://planet/sphere/sphere_demo.tscn): a whole true-scale planet of hexes streamed around a
## free camera, hub sites flattened on it, the near-cell junk ring, optional hex outlines.
##
## Flags: --sphere-level=7 --sphere-hex=10 (hex circumradius m) --sphere-cam=orbit|skim|ground|high
## --sphere-alt=M (skim/high altitude) --sphere-speed=M/S (skim flight) --sphere-dist=R multiples
## (orbit) --sphere-outlines --sphere-lod-tint --sphere-nohud --sphere-yaw=DEG --sphere-pitch=DEG.
## Keys: Tab cycles the camera, WASD fly over the surface, Q/E lower/raise, right-drag look,
## O outlines, L LOD tint.

const MODES: Array[String] = ["orbit", "high", "skim", "ground"]

var grid: SphereGrid
var terrain: SphereTerrain
var cells: SphereCells
var streamer: SphereStreamer
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var sites: Array[Dictionary] = []
var mode: String = "orbit"
var lumi: Node3D
var _hud: Label
var _junk_mm: MultiMeshInstance3D
var _dir := Vector3.UP        # camera ground direction (skim, high, ground)
var _heading := Vector3.ZERO  # tangent heading
var _alt: float = 60.0
var _orbit_ang: float = 0.0
var _yaw: float = 0.0
var _pitch: float = -12.0
var _perf_t: float = 0.0
var _frames: int = 0
var _speed: float = 0.0
var _start_cell: int = 0


func _ready() -> void:
	var t0: int = Time.get_ticks_msec()
	var lv: int = int(DevHooks.get_f("sphere-level", 7.0))
	var hex: float = DevHooks.get_f("sphere-hex", 10.0)
	grid = SphereGrid.for_hex_size(lv, hex)
	var t_grid: int = Time.get_ticks_msec() - t0
	terrain = SphereTerrain.new(grid, int(DevHooks.get_f("seed", 4471.0)))
	cells = SphereCells.new(grid.cell_count())
	_fill_demo_cells()
	_place_sites()
	_build_env()
	streamer = SphereStreamer.new()
	streamer.name = "Streamer"
	add_child(streamer)
	streamer.setup(grid, terrain, cells)
	streamer.outlines = DevHooks.has("sphere-outlines")
	streamer.lod_debug = DevHooks.has("sphere-lod-tint")
	streamer.near_changed.connect(_on_near_changed)
	_build_lumi()
	cam = Camera3D.new()
	cam.near = 0.25
	cam.far = grid.radius_m * 12.0
	cam.fov = 70.0
	add_child(cam)
	mode = DevHooks.get_s("sphere-cam", "orbit")
	_alt = DevHooks.get_f("sphere-alt", 400.0 if mode == "high" else 60.0)
	_speed = DevHooks.get_f("sphere-speed", 0.0)
	_yaw = DevHooks.get_f("sphere-yaw", 0.0)
	_pitch = DevHooks.get_f("sphere-pitch", -10.0 if mode == "high" else -6.0)
	_dir = terrain.local_to_dir(_start_cell, 0.0, 30.0)
	_heading = -SphereGrid.frame(_dir).z  # north
	_place_camera(0.0)
	streamer.set_centre("view", cam.global_position, SphereStreamer.VIEW)
	streamer.set_centre("lumi", lumi.global_position, SphereStreamer.BODY)
	var t1: int = Time.get_ticks_msec()
	streamer.settle()
	Settings.apply_quality_to_tree(self)
	if not DevHooks.has("sphere-nohud"):
		_hud = Label.new()
		_hud.position = Vector2(12, 10)
		_hud.add_theme_font_size_override("font_size", 15)
		_hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		var cl := CanvasLayer.new()
		cl.add_child(_hud)
		add_child(cl)
	var m: Dictionary = grid.hex_metrics()
	print("[sphere] level=%d cells=%d chunks=%d R=%.0fm circumference=%.1fkm hex corner=%.2fm spacing=%.2fm grid=%dms ready=%dms settle=%dms sites=%d" % [
		lv, grid.cell_count(), grid.chunk_count(), grid.radius_m, TAU * grid.radius_m / 1000.0, m["corner_m"], m["spacing_m"],
		t_grid, Time.get_ticks_msec() - t0, Time.get_ticks_msec() - t1, sites.size()])


# --- Demo planet --------------------------------------------------------------------------

func _fill_demo_cells() -> void:
	var n: int = grid.cell_count()
	var hs := PackedFloat32Array()
	hs.resize(n)
	for i: int in n:
		hs[i] = terrain.raw_height(grid.centers[i])
	var sorted: PackedFloat32Array = hs.duplicate()
	sorted.sort()
	var sea: float = sorted[int(n * 0.16)]
	var moist := FastNoiseLite.new()
	moist.seed = terrain.seed_value + 9
	moist.frequency = 1.6
	var cleaned := FastNoiseLite.new()
	cleaned.seed = terrain.seed_value + 21
	cleaned.frequency = 3.0
	for i: int in n:
		var c: Vector3 = grid.centers[i]
		if hs[i] < sea:
			cells.state[i] = 5
			cells.biome[i] = 7
			continue
		var lat: float = absf(asin(clampf(c.y, -1.0, 1.0))) / (PI * 0.5)
		var m: float = moist.get_noise_3dv(c * 2.0)
		cells.biome[i] = 5 if lat > 0.8 else (4 if m < -0.25 else (3 if m > 0.3 else 0))
		# Some ground already reclaimed, so the far view shows state from orbit.
		var k: float = cleaned.get_noise_3dv(c)
		if k > 0.38:
			cells.state[i] = 2 if k > 0.5 else 1
			cells.junk[i] = 0.0
		else:
			cells.junk[i] = clampf(0.6 + k, 0.2, 1.0)
	cells.refresh_all()


## Hub sites: spaced far apart (the rocket links them); the first is the demo's start.
func _place_sites() -> void:
	var want: Vector3 = Vector3(0.25, 1.0, 0.15).normalized()
	var start: int = grid.cell_at(want)
	var blocked := func(c: int) -> bool: return cells.state[c] == 5
	var tries: Array[int] = [start]
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain.seed_value
	for _i: int in 400:
		tries.append(rng.randi_range(0, grid.cell_count() - 1))
	var min_sep: float = grid.radius_m * 0.9
	for c: int in tries:
		if sites.size() >= 10:
			break
		var ok: bool = true
		for s: Dictionary in sites:
			if grid.distance_m(c, s["cell"]) < min_sep:
				ok = false
		if not ok:
			continue
		var s2: Dictionary = terrain.reserve_site(c, 45.0, 30.0, blocked)
		if s2.is_empty():
			continue
		sites.append(s2)
		for cc: int in s2["cells"]:
			cells.set_flag(cc, SphereCells.F_SITE)
			if grid.distance_m(cc, c) < 60.0:
				cells.state[cc] = 1
				cells.junk[cc] = 0.0
		_build_prefab(s2)
	if not sites.is_empty():
		_start_cell = sites[0]["cell"]
	cells.refresh_all()


## Placeholder hub prefab in site-local metres (the planet helpers' build(site_root, ...) goes here).
func _build_prefab(s: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Site%d" % int(s["id"])
	root.transform = s["transform"]
	add_child(root)
	var pad := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 34.0
	cyl.bottom_radius = 34.5
	cyl.height = 0.3
	cyl.radial_segments = 48
	pad.mesh = cyl
	pad.position = Vector3(0, 0.1, 0)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.55, 0.56, 0.58)
	pm.roughness = 0.8
	pad.material_override = pm
	root.add_child(pad)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.85, 0.83, 0.78)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.4, 0.9, 1.0)
	gm.emission_enabled = true
	gm.emission = Color(0.4, 0.9, 1.0)
	gm.emission_energy_multiplier = 1.5
	for b: Array in [[Vector3(-14, 0, -10), Vector3(12, 8, 10)], [Vector3(14, 0, -6), Vector3(10, 5, 14)],
			[Vector3(0, 0, 16), Vector3(18, 4, 8)], [Vector3(10, 0, 14), Vector3(4, 22, 4)]]:
		var mi := MeshInstance3D.new()
		var bx := BoxMesh.new()
		bx.size = b[1]
		mi.mesh = bx
		mi.position = (b[0] as Vector3) + Vector3(0, (b[1] as Vector3).y * 0.5, 0)
		mi.material_override = bm
		root.add_child(mi)
	var beacon := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 0.6
	bc.bottom_radius = 0.6
	bc.height = 60.0
	beacon.mesh = bc
	beacon.position = Vector3(-14, 30, 14)
	beacon.material_override = gm
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(beacon)


func _build_lumi() -> void:
	lumi = Node3D.new()
	lumi.name = "LumiMarker"
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.3
	mi.mesh = cap
	mi.position = Vector3(0, 0.65, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.7, 0.2)
	mi.material_override = m
	lumi.add_child(mi)
	add_child(lumi)
	var d: Vector3 = terrain.local_to_dir(_start_cell, 0.0, 30.0)
	lumi.transform = Transform3D(SphereGrid.frame(d), terrain.ground(d))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bx := BoxMesh.new()
	bx.size = Vector3(0.5, 0.35, 0.4)
	mm.mesh = bx
	_junk_mm = MultiMeshInstance3D.new()
	_junk_mm.name = "NearJunk"
	_junk_mm.multimesh = mm
	var jm := StandardMaterial3D.new()
	jm.vertex_color_use_as_albedo = true
	jm.roughness = 0.7
	_junk_mm.material_override = jm
	add_child(_junk_mm)


## 3D junk only for the near ring (stand-in boxes; the game's junk models go here).
func _on_near_changed(_added: PackedInt32Array, _removed: PackedInt32Array) -> void:
	var near: PackedInt32Array = streamer.near_cells()
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	for c: int in near:
		if not cells.is_dirty(c):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = c * 7919 + 13
		var cnt: int = int(10.0 * cells.junk[c])
		for _k: int in cnt:
			var d: Vector3 = grid.centers[c]
			var f: Basis = SphereGrid.frame(d)
			var off: Vector3 = (f.x * rng.randf_range(-7, 7) + f.z * rng.randf_range(-7, 7)) / grid.radius_m
			var dd: Vector3 = (d + off).normalized()
			var b: Basis = SphereGrid.frame(dd).rotated(dd, rng.randf() * TAU)
			xf.append(Transform3D(b.scaled(Vector3.ONE * rng.randf_range(0.6, 1.6)), terrain.ground(dd) + dd * 0.15))
			cols.append(Color.from_hsv(rng.randf_range(0.02, 0.12), rng.randf_range(0.2, 0.6), rng.randf_range(0.25, 0.6)))
	var mm: MultiMesh = _junk_mm.multimesh
	mm.instance_count = xf.size()
	for i: int in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, cols[i])


func _build_env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := PhysicalSkyMaterial.new()
	sm.rayleigh_coefficient = 2.4
	sm.rayleigh_color = Color(0.3, 0.45, 0.85)
	sm.mie_coefficient = 0.006
	sm.mie_color = Color(0.95, 0.85, 0.75)
	sm.turbidity = 6.0
	sm.ground_color = Color(0.32, 0.4, 0.55)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.2
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.66, 0.74)
	env.fog_density = 0.0008
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.94, 0.85)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	add_child(sun)


# --- Camera -------------------------------------------------------------------------------

func _place_camera(delta: float) -> void:
	var R: float = grid.radius_m
	match mode:
		"orbit":
			_orbit_ang += delta * 0.05
			var dist: float = DevHooks.get_f("sphere-dist", 2.4) * R
			var start: Vector3 = grid.centers[_start_cell]
			var side: Vector3 = SphereGrid.frame(start).x
			var p: Vector3 = (start.rotated(Vector3.UP, _orbit_ang) + side * 0.35).normalized() * dist
			cam.global_transform = Transform3D(Basis.looking_at(-p, Vector3.UP), p)
		"ground":
			# Lumi's follow camera: ~9 m behind, ~5 m above, looking a little past him.
			var d: Vector3 = lumi.global_position.normalized()
			var f: Basis = SphereGrid.frame(d)
			var fwd: Vector3 = (-f.z).rotated(d, deg_to_rad(_yaw))
			var eye: Vector3 = lumi.global_position - fwd * 9.0 + d * 5.0
			var look: Vector3 = lumi.global_position + fwd * 6.0 + d * 1.0
			cam.global_transform = Transform3D(Basis.looking_at(look - eye, d), eye)
		_:
			# skim / high: fly over the surface at an altitude above the terrain.
			if _speed > 0.0:
				var ax: Vector3 = _dir.cross(_heading).normalized()
				var a: float = _speed * delta / R
				_dir = _dir.rotated(ax, a).normalized()
				_heading = _heading.rotated(ax, a)
			_heading = (_heading - _dir * _heading.dot(_dir)).normalized()
			var ground_h: float = terrain.height(_dir)
			var eye: Vector3 = _dir * (R + ground_h + _alt)
			var fwd: Vector3 = _heading.rotated(_dir, deg_to_rad(_yaw))
			var right: Vector3 = fwd.cross(_dir).normalized()
			var look: Vector3 = fwd.rotated(right, deg_to_rad(_pitch))
			cam.global_transform = Transform3D(Basis.looking_at(look, _dir), eye)
	_orient_sky()


## Sky and sun follow the camera's local up (a fixed world sun would put half the globe at night).
func _orient_sky() -> void:
	var up: Vector3 = cam.global_position.normalized()
	if mode == "orbit":
		up = grid.centers[_start_cell]
	var f: Basis = SphereGrid.frame(up)
	env.sky_rotation = f.get_euler()
	sun.global_transform = Transform3D(f * Basis.from_euler(Vector3(deg_to_rad(-35.0), deg_to_rad(40.0), 0.0)), Vector3.ZERO)
	var alt: float = terrain.altitude(cam.global_position)
	env.fog_density = 0.0008 * clampf(1.0 - alt / 1500.0, 0.0, 1.0)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match (e as InputEventKey).keycode:
			KEY_TAB:
				mode = MODES[(MODES.find(mode) + 1) % MODES.size()]
				_alt = 400.0 if mode == "high" else 60.0
			KEY_O:
				streamer.outlines = not streamer.outlines
			KEY_L:
				streamer.lod_debug = not streamer.lod_debug
	if e is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var mm: InputEventMouseMotion = e
		_yaw -= mm.relative.x * 0.2
		_pitch = clampf(_pitch - mm.relative.y * 0.2, -89.0, 30.0)


func _process(delta: float) -> void:
	var mv := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if Input.is_key_pressed(KEY_W): mv.y -= 1.0
	if Input.is_key_pressed(KEY_S): mv.y += 1.0
	if Input.is_key_pressed(KEY_A): mv.x -= 1.0
	if Input.is_key_pressed(KEY_D): mv.x += 1.0
	if Input.is_key_pressed(KEY_Q): _alt = maxf(2.0, _alt * (1.0 - delta))
	if Input.is_key_pressed(KEY_E): _alt *= 1.0 + delta
	if mv != Vector2.ZERO and mode != "orbit":
		var fwd: Vector3 = _heading.rotated(_dir, deg_to_rad(_yaw))
		var right: Vector3 = fwd.cross(_dir).normalized()
		var step: Vector3 = (fwd * -mv.y + right * mv.x) * maxf(10.0, _alt) * delta / grid.radius_m
		_dir = (_dir + step).normalized()
		if mode == "ground":
			lumi.transform = Transform3D(SphereGrid.frame(_dir), terrain.ground(_dir))
	_place_camera(delta)
	streamer.set_centre("view", cam.global_position, SphereStreamer.VIEW)
	streamer.set_centre("lumi", lumi.global_position, SphereStreamer.BODY)
	_perf(delta)


func _perf(delta: float) -> void:
	_perf_t += delta
	_frames += 1
	var st: Dictionary = streamer.stats
	var built: int = maxi(1, int(st.get("built", 0)))
	var line: String = "%s  alt %.0f m  horizon %.0f m | chunks L0 %d  L1 %d  coll %d  near %d hexes | jobs %d  queued %d | build %.1f ms (max %.1f)  apply %.2f ms (max %.2f)" % [
		mode, float(st.get("view_alt", 0.0)), float(st.get("horizon_m", 0.0)), int(st.get("lod0", 0)), int(st.get("lod1", 0)),
		int(st.get("collide", 0)), int(st.get("near", 0)), int(st.get("jobs", 0)), int(st.get("pending", 0)),
		float(st.get("build_us_sum", 0)) / built / 1000.0, float(st.get("build_us_max", 0)) / 1000.0,
		float(st.get("apply_us_sum", 0)) / built / 1000.0, float(st.get("apply_us_max", 0)) / 1000.0]
	if _hud:
		_hud.text = line + "\nFPS %d  draw calls %d  prims %d" % [Engine.get_frames_per_second(),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)]
	if _perf_t >= 3.0:
		print("[sphere] fps=%.1f frame=%.1fms draw_calls=%d prims=%d objects=%d mem_static=%.0fMB video=%.0fMB tex=%.0fMB buf=%.0fMB | %s" % [
			_frames / _perf_t, _perf_t / _frames * 1000.0,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED) / 1048576.0, line])
		_perf_t = 0.0
		_frames = 0
