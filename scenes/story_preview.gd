extends Node3D
## [intro2] Quick renders of the story props without loading a district (fast on software Vulkan):
##   godot --path . --rendering-driver vulkan res://scenes/story_preview.tscn -- --view=ark --out=screenshots/ark
##   --view=ark      the ark Cradle from two angles          (<out>_0, <out>_1)
##   --view=pod      the escape pod door opening: unlatch + steam, then open with light spill
##   --view=loading  the loading screen at three points along the bar

var _out: String
var _view: String
var _t: float = 0.0
var _shots: Array = []  # [time, callable-before, index]
var _i: int = 0
var _pod: Node3D
var _cam: Camera3D
var _saving: bool = false


func _ready() -> void:
	_out = DevHooks.get_s("out", "screenshots/story_preview")
	_view = DevHooks.get_s("view", "ark")
	match _view:
		"ark": _setup_ark()
		"pod": _setup_pod()
		"crash": _setup_pod(true)
		"loading": _setup_loading()


func _setup_ark() -> void:
	var stage := SpaceStage.new()
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(stage)
	await get_tree().process_frame
	stage.show_set("space")
	var ark: CradleShip = stage.ark
	ark.rotation = Vector3(0, -PI * 0.5, 0)
	ark.position = Vector3(0, 0, 0)
	_shots = [
		[3.0, func() -> void: stage.aim(Vector3(30, 14, 44), Vector3(0, -1, 0), 40.0)],
		[5.0, func() -> void: stage.aim(Vector3(-40, 7, 34), Vector3(2, -1, 0), 40.0)],
	]


func _setup_pod(crash: bool = false) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := PhysicalSkyMaterial.new()
	sm.turbidity = 10.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-22, 140, 0)
	sun.light_energy = 1.6
	sun.light_color = Color(1.0, 0.8, 0.62)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	pm.material = AssetLib.pbr_material("dry_ground_rocks", 10.0)
	ground.mesh = pm
	add_child(ground)
	_pod = EscapePod.build()
	var site: CrashSite = CrashSite.attach(self, _pod, Vector3.ZERO, 0.5)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	add_child(_cam)
	_cam.current = true
	var pod: Node3D = _pod
	if crash:
		# Before / after: damaged (smoke, sparks, torn panel, worn paint), then repaired.
		EscapePod.set_open(pod, true, CrashSite.LEAN.x)
		var eye: Vector3 = Vector3(-3.6, 2.3, -4.6)
		_cam.look_at_from_position(eye, Vector3(0.3, 0.8, 0.6), Vector3.UP)
		_shots = [[4.0, Callable()], [12.0, func() -> void: pass]]
		get_tree().create_timer(4.6).timeout.connect(func() -> void: site.set_stage(2))
		return
	var front: Vector3 = pod.global_transform * Vector3(1.0, 1.1, -4.6)
	_cam.look_at_from_position(front, pod.global_transform * Vector3(0, 0.85, 0), Vector3.UP)
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		EscapePod.open_door(pod, func(p: Vector3, _d: Vector3) -> void:
			Vfx.burst("steam", pod.global_transform * p, Color(0.92, 0.94, 0.97, 0.75), 0.35), 1.0, CrashSite.LEAN.x))
	_shots = [[2.4, Callable()], [4.6, Callable()]]


func _setup_loading() -> void:
	var ld: LoadingScreen = get_node("/root/Loader")
	await get_tree().process_frame
	ld.visible = true
	ld.active = false
	ld._alpha = 1.0
	ld._apply_alpha()
	ld._reset_pieces()
	ld._status.text = tr("Setting the scene")
	ld.shown = 0.0
	ld.target = 0.0
	var fill := func(p: float) -> void:
		ld.shown = p
		ld.target = p
	_shots = [[1.6, fill.bind(0.18)], [3.4, fill.bind(0.52)], [5.4, fill.bind(0.86)]]
	# Animate the bar between shots so pieces get scooped on the way.
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		ld.shown = v
		ld.target = v, 0.0, 0.18, 1.5)
	tw.tween_interval(0.1)
	tw.tween_method(func(v: float) -> void:
		ld.shown = v
		ld.target = v, 0.18, 0.52, 1.6)
	tw.tween_interval(0.2)
	tw.tween_method(func(v: float) -> void:
		ld.shown = v
		ld.target = v, 0.52, 0.86, 1.8)
	_shots = [[1.62, Callable()], [3.42, Callable()], [5.5, Callable()]]


func _process(delta: float) -> void:
	_t += minf(delta, 0.05)
	if _i >= _shots.size():
		if not _shots.is_empty() and _t > float(_shots[-1][0]) + 0.5:
			get_tree().quit()
		return
	var s: Array = _shots[_i]
	var pre: Callable = s[1]
	if _t >= float(s[0]) - 0.5 and pre.is_valid():
		pre.call()
		s[1] = Callable()
	if _t >= float(s[0]) and not _saving:
		_saving = true
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		var path: String = "%s_%d.png" % [_out, _i]
		img.save_png(path)
		print("[preview] saved %s" % path)
		_i += 1
		_saving = false
