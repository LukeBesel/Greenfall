extends Node3D
## [smove] Demo / test bed: Lumi on a true-scale stand-in planet (a smooth sphere, collision =
## SphereShape3D), with roaming robots, a traveller that drives over the horizon and back, rocks,
## and junk scattered on the surface (normal-aligned, random yaw) that the tractor scoop takes.
##
##   --sphere-walk            auto: walk straight ahead all the way round and report the lap
##   --sphere-walk=boost      the same lap on hover-boost (~11 min game time at R 1840)
##   --sphere-walk=play       you drive (WASD/stick, Shift/LT boost, F jump, B command view)
##   --sphere-r=M             planet radius (default 1840 m: level-7 globe at 10 m hexes)
##   --sphere-start=pole      start on the north pole (default: on the equator heading north)
##   --sphere-view=follow|command  --sphere-cmd-h=M   --sphere-cam=dist,pitch[,yaw_deg]   --sphere-quit (quit after the lap)
##   --sphere-scene=horizon   Lumi parked, the traveller ~150 m out driving over the horizon
## Lap report: user://sphere_lap.json and a "[sphere] lap" line (PASS = back within 1 m).

const JUNK_MODELS: Array[String] = ["can_rusted", "oil_tin", "metal_jerrycan", "rusted_wheel_rim_01",
	"plastic_bottle_gallon", "old_tyre", "plastic_crate_01", "trashbag"]
const FAR_OUT_M: float = 320.0
const FAR_IN_M: float = 260.0

var R: float = 1840.0
var surface: SphereSurface
var walker: SphereWalker
var cam: SphereCam
var swarm: SphereSwarm
var bots: Array[SphereBot] = []
## Far bots as records (SphereCrewSim) with their type and home.
var far_bots: Array[Dictionary] = []
var env: Environment
var sun: DirectionalLight3D
var mode: String = "1"
var _start := Vector3.ZERO
var _start_dir := Vector3.UP
var _heading := Vector3.FORWARD
var _lap_on: bool = false
var _lap_best: float = INF
var _lap_t: float = 0.0
var _lap_done: bool = false
var _next_pct: int = 10
var _hud: Label
var _rng := RandomNumberGenerator.new()
# Junk: one MultiMesh per model; a collected piece's instance is scaled to zero.
var _junk_pos: Array = []  # world positions (Vector3.INF = gone)
var _junk_slot := PackedInt32Array()
var _junk_mm: Array[MultiMesh] = []
var _junk_model := PackedInt32Array()
var _junk_xf: Array[Transform3D] = []
var _scoop_cd: float = 0.0
var _flying: Array[Dictionary] = []
var scooped: int = 0
var _max_ortho: float = 0.0
var _max_roll: float = 0.0
var _far_t: float = 0.0
var _prev_pos := Vector3.ZERO


func _ready() -> void:
	_rng.seed = 4242
	R = DevHooks.get_f("sphere-r", 1840.0)
	mode = DevHooks.get_s("sphere-walk", "play" if not DevHooks.has("sphere-walk") else "1")
	surface = SphereSurface.new(R)
	swarm = SphereSwarm.new(surface)
	_build_env()
	_build_planet()
	# Spawn: on the equator heading north (the lap runs over both poles), or on the pole itself.
	_start_dir = Vector3.UP if DevHooks.get_s("sphere-start", "") == "pole" else Vector3(0, 0, 1)
	_heading = Vector3.FORWARD if _start_dir == Vector3.UP else Vector3.UP
	walker = SphereWalker.new(surface)
	walker.name = "Lumi"
	match mode:
		"1", "walk":
			walker.input = SphereAutoInput.new(Vector3(0, 0, -1), false)
		"boost":
			walker.input = SphereAutoInput.new(Vector3(0, 0, -1), true)
		_:
			walker.input = SphereInput.new()
	if walker.input is SphereAutoInput:
		(walker.input as SphereAutoInput).scoop = true
		_lap_on = true
	add_child(walker)
	walker.place(_start_dir * R, _heading)
	walker.scoop_fn = _scoop
	_start = walker.global_position
	cam = SphereCam.new()
	cam.name = "SphereCam"
	cam.surface = surface
	cam.target = walker
	cam.view = DevHooks.get_s("sphere-view", "follow")
	cam.command_height = DevHooks.get_f("sphere-cmd-h", cam.command_height)
	add_child(cam)
	walker.cam = cam
	if DevHooks.has("sphere-cam"):
		var c: PackedStringArray = DevHooks.get_s("sphere-cam", "").split(",")
		cam.distance = float(c[0])
		if c.size() > 1:
			cam.pitch = float(c[1])
	cam.reset_frame(_heading)
	if DevHooks.has("sphere-cam") and DevHooks.get_s("sphere-cam", "").split(",").size() > 2:
		cam.add_yaw(deg_to_rad(float(DevHooks.get_s("sphere-cam", "").split(",")[2])))
		cam.snap()
	_scatter_rocks()
	_scatter_junk()
	_spawn_bots()
	if DevHooks.get_s("sphere-scene", "") == "horizon":
		_setup_horizon()
	_build_hud()
	print("[sphere] R=%.0f m, circumference %.0f m, mode=%s, start=%s, bots=%d, junk=%d" % [R, TAU * R, mode, str(_start_dir), bots.size(), _junk_pos.size()])


# --- World ------------------------------------------------------------------------------

func _build_env() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.47, 0.68)
	sm.sky_horizon_color = Color(0.78, 0.74, 0.66)
	sm.ground_bottom_color = Color(0.3, 0.27, 0.24)
	sm.ground_horizon_color = Color(0.7, 0.66, 0.6)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	# A thin aerial haze: the horizon softens, the curve still reads.
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.72, 0.68)
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.0
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)


func _build_planet() -> void:
	var body := StaticBody3D.new()
	body.name = "Planet"
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = R
	cs.shape = sh
	body.add_child(cs)
	add_child(body)
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = R
	m.height = R * 2.0
	m.radial_segments = 768
	m.rings = 384
	mi.mesh = m
	var mat: StandardMaterial3D = AssetLib.pbr_material("dry_ground_rocks", 0.22, Color(0.92, 0.86, 0.78), true)
	mat.uv1_world_triplanar = true
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)


## Rocks around the start, off Lumi's lap line, as collision + avoidance obstacles.
func _scatter_rocks() -> void:
	var lap_n: Vector3 = _start_dir.cross(_heading).normalized()
	var mat: StandardMaterial3D = AssetLib.pbr_material("rubble", 0.6, Color(0.8, 0.76, 0.7), true)
	for i: int in 26:
		var d: Vector3 = SpherePlace.random_in_cap(_start_dir, 70.0, R, _rng)
		if absf(d.dot(lap_n)) * R < 5.0 or d.angle_to(_start_dir) * R < 6.0:
			continue
		var rad: float = _rng.randf_range(0.5, 1.6)
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = rad
		cs.shape = sh
		sb.add_child(cs)
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = rad
		sm.height = rad * 1.5
		sm.radial_segments = 9
		sm.rings = 5
		mi.mesh = sm
		mi.material_override = mat
		mi.scale = Vector3(_rng.randf_range(0.9, 1.3), 1.0, _rng.randf_range(0.8, 1.2))
		sb.add_child(mi)
		add_child(sb)
		sb.global_transform = SpherePlace.random_on_surface(surface, d, _rng, 0.0, rad * 0.35)
		swarm.obstacles.append([d, rad])


func _scatter_junk() -> void:
	var meshes: Array[Mesh] = []
	for id: String in JUNK_MODELS:
		meshes.append(AssetLib.model_mesh_lite(id, 600) if AssetLib.has_model(id) else BoxMesh.new())
	var dirs: Array[Vector3] = []
	# A field of junk around the start...
	for i: int in 260:
		dirs.append(SpherePlace.random_in_cap(_start_dir, 60.0, R, _rng))
	# ...and a trail along the lap line (every ~25 m, a little to either side) for the scoop.
	var lap_n: Vector3 = _start_dir.cross(_heading).normalized()
	var n_trail: int = int(TAU * R / 25.0)
	for i: int in n_trail:
		var a: float = TAU * float(i) / float(n_trail) + 0.004
		var d: Vector3 = _start_dir.rotated(lap_n, a)
		d = d.rotated(_heading.rotated(lap_n, a), _rng.randf_range(-0.5, 0.5) / R).normalized()
		dirs.append(d)
	var per_model: Array = []
	for k: int in meshes.size():
		per_model.append([])
	for d: Vector3 in dirs:
		var k: int = _rng.randi() % meshes.size()
		var xf: Transform3D = SpherePlace.random_on_surface(surface, d, _rng, 1.0, 0.02, _rng.randf_range(0.8, 1.2))
		(per_model[k] as Array).append(_junk_pos.size())
		_junk_pos.append(xf.origin)
		_junk_model.append(k)
		_junk_xf.append(xf)
	_junk_slot.resize(_junk_pos.size())
	for k: int in meshes.size():
		var ids: Array = per_model[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[k]
		mm.instance_count = ids.size()
		for s: int in ids.size():
			mm.set_instance_transform(s, _junk_xf[ids[s]])
			_junk_slot[ids[s]] = s
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)
		_junk_mm.append(mm)


func _spawn_bots() -> void:
	var types: Array[String] = ["scoopie", "haulbug", "scoopie", "drip", "scoopie", "haulbug"]
	for i: int in types.size():
		var d: Vector3 = SpherePlace.random_in_cap(_start_dir, 25.0, R, _rng)
		var b := _make_bot(types[i], d)
		b.set_meta("home", _start_dir)
		b.arrived.connect(_roam.bind(b))
		_roam(b)
	# The traveller: out 400 m along a great circle (over the horizon) and back, forever.
	var tr_b: SphereBot = _make_bot("haulbug", _start_dir.rotated(_heading, 0.004).normalized())
	tr_b.name = "Traveller"
	tr_b.speed = 6.0
	tr_b.set_meta("traveller", true)
	tr_b.set_meta("out", true)
	tr_b.arrived.connect(_travel.bind(tr_b))
	_travel(tr_b)


func _make_bot(type_id: String, d: Vector3) -> SphereBot:
	var b := SphereBot.new()
	add_child(b)
	b.setup(surface, d, SphereMath.any_perpendicular(d).rotated(d, _rng.randf() * TAU))
	b.add_visual(type_id, "salvage")
	b.set_meta("type", type_id)
	swarm.add(b)
	bots.append(b)
	return b


func _roam(b: SphereBot) -> void:
	var home: Vector3 = b.get_meta("home", _start_dir)
	b.go_to_point(SpherePlace.random_in_cap(home, 35.0, R, _rng) * R)


func _travel(b: SphereBot) -> void:
	var out: bool = b.get_meta("out", true)
	var side: Vector3 = _start_dir.cross(_heading).normalized()
	var away: Vector3 = _start_dir.rotated(side.rotated(_start_dir, 2.2), 400.0 / R).normalized()
	b.go_to_point((away if out else _start_dir.rotated(side, 6.0 / R)) * R)
	b.set_meta("out", not out)


func _setup_horizon() -> void:
	walker.input = SphereAutoInput.new(Vector3.ZERO)
	_lap_on = false
	for b: SphereBot in bots:
		if b.has_meta("traveller"):
			var side: Vector3 = _start_dir.cross(_heading).normalized()
			# Straight ahead of the camera, ~140 m out, heading away.
			b.dir = _start_dir.rotated(side, -140.0 / R).normalized()
			b.heading = SphereMath.tangent_dir(-_start_dir, b.dir)
			b.speed = 5.0
			b.go_to_point(_start_dir.rotated(side, -600.0 / R) * R)
			b.set_meta("out", false)


func _build_hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 15)
	_hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	cl.add_child(_hud)
	_hud.visible = not DevHooks.has("no-hud")


# --- Scoop on a curved surface ----------------------------------------------------------

func _scoop(w: SphereWalker, delta: float) -> void:
	var reach: float = 2.4
	var width: float = 1.4
	var fwd: Vector3 = -w.global_basis.z
	var origin: Vector3 = w.global_position + w.up() * 0.2 + fwd * 0.25
	# Candidates near Lumi only (cheap distance prefilter, then the curved cone test).
	var near: Array = []
	var near_ids: Array[int] = []
	for i: int in _junk_pos.size():
		var p: Vector3 = _junk_pos[i]
		if p != Vector3.INF and origin.distance_squared_to(p) < 20.0:
			near.append(p)
			near_ids.append(i)
	# Magnet pull along the ground toward the scoop.
	for j: int in near.size():
		var p: Vector3 = near[j]
		if origin.distance_to(p) < reach + 1.2 and SpherePlace.in_scoop(surface, origin, fwd, p, reach + 1.2, width + 1.0):
			var np: Vector3 = SpherePlace.pull_along(surface, p, origin, 1.5 * delta)
			_move_junk(near_ids[j], np)
	_scoop_cd -= delta
	if _scoop_cd > 0.0:
		return
	var k: int = SpherePlace.find_scoop_target(surface, origin, fwd, near, reach, width)
	if k < 0:
		return
	_scoop_cd = 1.0 / 8.0
	var id: int = near_ids[k]
	var xf: Transform3D = _junk_xf[id]
	var mm: MultiMesh = _junk_mm[_junk_model[id]]
	mm.set_instance_transform(_junk_slot[id], Transform3D(Basis().scaled(Vector3.ZERO), xf.origin))
	_junk_pos[id] = Vector3.INF
	var mi := MeshInstance3D.new()
	mi.mesh = mm.mesh
	add_child(mi)
	mi.global_transform = xf
	_flying.append({"node": mi, "from": xf, "t": 0.0})
	scooped += 1
	if w.model:
		w.model.beam_at(xf.origin)


func _move_junk(id: int, p: Vector3) -> void:
	var xf: Transform3D = _junk_xf[id]
	var u: Vector3 = surface.up_at(p)
	xf.basis = SphereMath.transport(xf.basis, surface.up_at(xf.origin), u)
	xf.origin = p
	_junk_xf[id] = xf
	_junk_pos[id] = p
	_junk_mm[_junk_model[id]].set_instance_transform(_junk_slot[id], xf)


func _update_flying(delta: float) -> void:
	for i: int in range(_flying.size() - 1, -1, -1):
		var f: Dictionary = _flying[i]
		f["t"] = float(f["t"]) + delta / 0.4
		var t: float = minf(float(f["t"]), 1.0)
		var mi: MeshInstance3D = f["node"]
		var from: Transform3D = f["from"]
		var to: Vector3 = walker.model.chest_world() if walker.model else walker.global_position + walker.up()
		var e: float = t * t * (3.0 - 2.0 * t)
		mi.global_transform = Transform3D(from.basis.scaled(Vector3.ONE * (1.0 - 0.85 * e)), SpherePlace.beam_arc(surface, from.origin, to, e, 0.6))
		if t >= 1.0:
			mi.queue_free()
			_flying.remove_at(i)
			if walker.model:
				walker.model.hopper_pulse(0.5)
				walker.model.beam_at(null)


# --- Per frame -----------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _prev_pos == Vector3.ZERO:
		_prev_pos = walker.global_position
	_max_ortho = maxf(_max_ortho, SphereMath.ortho_error(walker.global_basis))
	if _lap_on and not _lap_done:
		_lap_t += delta
		var circ: float = TAU * R
		var pct: int = int(walker.distance / circ * 100.0)
		if pct >= _next_pct and _next_pct < 100:
			print("[sphere] lap %d%%  %.0f m  t=%.0fs  pos=%s" % [_next_pct, walker.distance, _lap_t, str(walker.global_position.snapped(Vector3.ONE * 0.1))])
			_next_pct += 10
		if walker.distance > circ * 0.9:
			# Closest approach to the start along this step's segment (not just at the samples).
			var a: Vector3 = _prev_pos
			var ab: Vector3 = walker.global_position - a
			var t: float = clampf((_start - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
			_lap_best = minf(_lap_best, (a + ab * t).distance_to(_start))
			if walker.distance > circ + 20.0:
				_finish_lap()
	_prev_pos = walker.global_position


func _finish_lap() -> void:
	_lap_done = true
	var ok: bool = _lap_best < 1.0
	var rep := {"radius": R, "circumference": TAU * R, "walked": walker.distance, "closest_to_start_m": _lap_best,
		"time_s": _lap_t, "mode": mode, "max_ortho_err": _max_ortho, "max_cam_roll": _max_roll,
		"scooped": scooped, "bots_near": bots.size(), "bots_far": far_bots.size(), "pass": ok}
	print("[sphere] lap %s: walked %.1f m of %.1f m in %.0f s, closest to start %.3f m, ortho %.7f, cam roll %.4f rad, scooped %d" % [
		"PASS" if ok else "FAIL", walker.distance, TAU * R, _lap_t, _lap_best, _max_ortho, _max_roll, scooped])
	var f := FileAccess.open("user://sphere_lap.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(rep, "  "))
	if DevHooks.has("sphere-quit"):
		get_tree().quit(0 if ok else 1)


func _process(delta: float) -> void:
	if walker == null:
		return
	_update_flying(delta)
	_max_roll = maxf(_max_roll, cam.horizon_roll())
	# Sky and sun follow the local frame: the sky's horizon is Lumi's horizon, the sun stays up.
	env.sky_rotation = cam.frame.get_euler()
	sun.global_basis = cam.frame * Basis.from_euler(Vector3(deg_to_rad(-38.0), deg_to_rad(28.0), 0.0))
	_stream_bots(delta)
	if walker.input is PlayerInput and (walker.input as PlayerInput).enabled:
		if Input.is_action_just_pressed("open_command"):
			cam.view = "follow" if cam.view == "command" else "command"
	if _hud.visible:
		var circ: float = TAU * R
		_hud.text = tr("Planet %d m around") % int(circ) + "\n" + tr("Walked %d m (%d%%)") % [int(walker.distance), int(walker.distance / circ * 100.0)] \
			+ "\n" + tr("Speed %.1f m/s") % walker.motor.hv.length() + "\n" + tr("Bots near %d, far %d") % [bots.size(), far_bots.size()]


func _unhandled_input(event: InputEvent) -> void:
	if not (walker and walker.input is SphereInput):
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Bots far from Lumi become records advanced by SphereCrewSim; close ones come back as nodes.
func _stream_bots(delta: float) -> void:
	_far_t += delta
	var lumi_dir: Vector3 = walker.up()
	for i: int in range(bots.size() - 1, -1, -1):
		var b: SphereBot = bots[i]
		if b.dir.angle_to(lumi_dir) * R > FAR_OUT_M:
			var rec: Dictionary = SphereCrewSim.demote(b)
			rec["type"] = b.get_meta("type", "scoopie")
			rec["traveller"] = b.has_meta("traveller")
			rec["home"] = b.get_meta("home", _start_dir)
			far_bots.append(rec)
			bots.remove_at(i)
	if _far_t < 1.0:
		return
	var dt: float = _far_t
	_far_t = 0.0
	for i: int in range(far_bots.size() - 1, -1, -1):
		var rec: Dictionary = far_bots[i]
		SphereCrewSim.advance(rec, dt, R)
		if rec["goal"] == Vector3.ZERO:  # arrived while far: pick the next leg abstractly
			rec["goal"] = SpherePlace.random_in_cap(rec["home"], 35.0, R, _rng)
		if (rec["dir"] as Vector3).angle_to(lumi_dir) * R < FAR_IN_M:
			var b: SphereBot = SphereCrewSim.promote(rec, surface, self, rec["type"])
			b.set_meta("type", rec["type"])
			b.set_meta("home", rec["home"])
			if rec["traveller"]:
				b.set_meta("traveller", true)
				b.arrived.connect(_travel.bind(b))
			else:
				b.arrived.connect(_roam.bind(b))
			swarm.add(b)
			bots.append(b)
			far_bots.remove_at(i)
