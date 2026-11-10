extends Node3D
## [globes] Renders the planet globes (ui/planet_globe.gd) for visual QA, or checks them headless.
##   Rendered: xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver vulkan \
##     --resolution 1280x720 res://tools/globe_shots.tscn -- --globe-out=screenshots/globes [--globe-only=rime]
##   Headless check: godot --headless --path . res://tools/globe_shots.tscn -- --globe-check
## Shots: one close-up per planet, the five in a lineup (automatic LOD), Verdance at 0% and 100%.

var _cam: Camera3D
var _stage: Node3D
var _out: String = "screenshots/globes"
var _only: String = ""


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a: String in args:
		if a.begins_with("--globe-out="):
			_out = a.substr(12)
		elif a.begins_with("--globe-only="):
			_only = a.substr(13)
	_build_env()
	if args.has("--globe-check"):
		_check.call_deferred()
	else:
		_run.call_deferred()


func _build_env() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type sky;
float h(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
void sky() {
	vec3 d = EYEDIR * 260.0;
	vec3 c = floor(d);
	float s = h(c);
	vec3 o = fract(d) - 0.5 - (vec3(h(c + 1.3), h(c + 2.7), h(c + 4.1)) - 0.5) * 0.6;
	float star = step(0.985, s) * smoothstep(0.12, 0.0, length(o)) * (0.25 + 0.75 * h(c + 9.1));
	vec3 tint = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.85, 0.7), h(c + 5.5));
	float band = exp(-pow(EYEDIR.y * 3.0 - EYEDIR.x, 2.0) * 2.0) * 0.006;
	COLOR = vec3(0.0015, 0.002, 0.004) + tint * star * 0.8 + vec3(0.5, 0.55, 0.7) * band;
}"""
	sm.shader = sh
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.0, 0.0, 0.0)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.35
	e.glow_bloom = 0.015
	e.glow_hdr_threshold = 1.15
	for i: int in 7:
		e.set_glow_level(i, i >= 2 and i <= 4)
	we.environment = e
	add_child(we)
	_cam = Camera3D.new()
	_cam.fov = 30.0
	_cam.current = true
	add_child(_cam)
	get_viewport().msaa_3d = Viewport.MSAA_4X


func _fresh_stage() -> void:
	if _stage:
		_stage.queue_free()
	_stage = Node3D.new()
	add_child(_stage)


func _globe(id: String, r: float, pos: Vector3, rest: float, lod: int) -> PlanetGlobe:
	var g := PlanetGlobe.new()
	g.radius = r
	g.spin_scale = 0.0
	g.position = pos
	_stage.add_child(g)
	g.setup(id, rest)
	if lod >= 0:
		g.set_lod(lod)
	return g


func _aim(from: Vector3, at: Vector3) -> void:
	_cam.position = from
	_cam.look_at(at, Vector3.UP)


func _snap(name: String) -> void:
	for i: int in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + _out))
	var path: String = "res://%s/%s.png" % [_out, name]
	get_viewport().get_texture().get_image().save_png(path)
	print("[globes] shot %s" % path)


func _run() -> void:
	var shots: Array = [
		["verdance", 0.35, false], ["ochre", 0.15, true], ["tidewell", 0.4, false], ["rime", 0.2, true], ["anvil", 0.15, true],
	]
	for s: Array in shots:
		if _only != "" and _only != str(s[0]):
			continue
		_fresh_stage()
		_globe(str(s[0]), 1.0, Vector3.ZERO, float(s[1]), 2)
		if bool(s[2]):
			_aim(Vector3(1.2, 1.25, 7.6), Vector3(0.25, 0.0, 0.0))
		else:
			_aim(Vector3(0.5, 0.35, 4.3), Vector3(0.18, 0.0, 0.0))
		await _snap("globe_%s" % s[0])
	if _only == "" or _only == "lineup":
		_fresh_stage()
		var row: Array = [["ochre", 0.85, 2.2], ["verdance", 1.0, 1.0], ["tidewell", 1.1, 1.1], ["anvil", 0.8, 1.75], ["rime", 0.62, 1.5]]
		var x: float = 0.0
		var xs: Array[float] = []
		for r: Array in row:
			var half: float = float(r[1]) * float(r[2])
			x += half
			xs.append(x)
			x += half + 0.45
		var mid: float = (x - 0.45) * 0.5
		for i: int in row.size():
			_globe(str(row[i][0]), float(row[i][1]), Vector3(xs[i] - mid, 0.0, 0.0), 0.2, -1)
		_aim(Vector3(0.0, 2.4, 18.5), Vector3(0.0, -0.1, 0.0))
		await _snap("globe_lineup")
	if _only == "" or _only == "verdance_rest":
		for rest: float in [0.0, 1.0]:
			_fresh_stage()
			_globe("verdance", 1.0, Vector3.ZERO, rest, 2)
			_aim(Vector3(0.5, 0.35, 4.3), Vector3(0.18, 0.0, 0.0))
			await _snap("globe_verdance_%d" % int(rest * 100.0))
	get_tree().quit(0)


func _planet_ids() -> Array[String]:
	var out: Array[String] = []
	for def: PlanetDefinition in Planets.all():
		out.append(String(def.id))
	return out


func _check() -> void:
	_fresh_stage()
	var ok: bool = true
	for id: String in _planet_ids() + ["mystery"]:
		var g := _globe(id, 1.0, Vector3.ZERO, 0.5, -1)
		g.set_restoration(1.0)
		ok = ok and g.planet_id == id
	for i: int in 3:
		await get_tree().process_frame
	print("[globes] check %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
