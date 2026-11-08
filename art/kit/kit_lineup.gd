extends Node3D
## [kit] Art kit lineup: every kit piece in broken / repaired / restored state, day and night.
##   xvfb-run -a -s "-screen 0 960x540x24" godot --path . --rendering-driver vulkan --resolution 960x540 \
##     res://art/kit/kit_lineup.tscn -- --fresh --out=screenshots/kit/lineup [--only=tower,hangar] [--night-only]
## (or any normal run with --kit-lineup). Writes <out>_<item>_<day|night>.png per item plus an
## overview <out>_all_<day|night>.png; tools/kit_sheet.py stitches them into a contact sheet.
## Without --out it just shows the lineup (orbit with the mouse wheel / arrows is not provided:
## it is a render rig).

const STATES: PackedStringArray = ["broken", "repaired", "restored"]
const SPACING: float = 40.0  # between items (z)

var _items: Array[Dictionary] = []
var _shots: Array[Dictionary] = []
var _cam: Camera3D
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _out: String = ""
var _i: int = -1
var _frames: int = 0
var _night: bool = false
var _lights: Array[Node] = []


func _ready() -> void:
	_out = DevHooks.get_s("out", "")
	_items = KitLineupItems.items()
	var only: String = DevHooks.get_s("only", "")
	if only != "":
		var keep: PackedStringArray = only.split(",")
		_items = _items.filter(func(d: Dictionary) -> bool: return str(d["name"]) in keep)
	_build_world()
	var t0: int = Time.get_ticks_msec()
	for k: int in _items.size():
		var it: Dictionary = _items[k]
		var z: float = -k * SPACING
		var span: float = float(it.get("span", 12.0))
		for s: int in STATES.size():
			var x: float = (s - 1) * span
			var node: Node3D = (it["build"] as Callable).call(STATES[s])
			node.position = Vector3(x, 0, z)
			add_child(node)
	print("[kit] lineup built %d items in %d ms" % [_items.size(), Time.get_ticks_msec() - t0])
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_cam.far = 600.0
	add_child(_cam)
	_cam.current = true
	var passes: Array = [false, true]
	if DevHooks.has("night-only"):
		passes = [true]
	elif DevHooks.has("day-only"):
		passes = [false]
	for night: bool in passes:
		for k: int in _items.size():
			_shots.append({"item": k, "night": night})
	_set_view(0)


func _build_world() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sky.sky_material = sm
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.ssao_enabled = true
	_env.ssao_radius = 1.2
	_env.ssao_intensity = 2.2
	_env.glow_enabled = true
	_env.glow_intensity = 0.35
	_env.glow_bloom = 0.02
	_env.glow_hdr_threshold = 1.1
	_env.fog_enabled = true
	_env.fog_density = 0.0025
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 80.0
	add_child(_sun)
	_fill = DirectionalLight3D.new()
	_fill.light_specular = 0.6
	add_child(_fill)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	pm.material = AssetLib.pbr_material("dry_ground_rocks", 80.0)
	ground.mesh = pm
	ground.position = Vector3(0, -0.01, -SPACING * 3)
	add_child(ground)
	_apply_light(false)


func _apply_light(night: bool) -> void:
	_night = night
	var sm: ProceduralSkyMaterial = _env.sky.sky_material
	if night:
		sm.sky_top_color = Color(0.03, 0.05, 0.12)
		sm.sky_horizon_color = Color(0.1, 0.13, 0.22)
		sm.ground_horizon_color = Color(0.06, 0.07, 0.1)
		sm.ground_bottom_color = Color(0.02, 0.02, 0.03)
		sm.sky_energy_multiplier = 1.0
		_env.ambient_light_energy = 0.6
		_env.fog_light_color = Color(0.08, 0.1, 0.18)
		_sun.light_color = Color(0.55, 0.65, 1.0)
		_sun.light_energy = 0.28
		_sun.rotation_degrees = Vector3(-40, 130, 0)
		_fill.light_energy = 0.0
	else:
		sm.sky_top_color = Color(0.25, 0.48, 0.82)
		sm.sky_horizon_color = Color(0.72, 0.78, 0.86)
		sm.ground_horizon_color = Color(0.6, 0.56, 0.5)
		sm.ground_bottom_color = Color(0.3, 0.26, 0.22)
		sm.sky_energy_multiplier = 1.0
		_env.ambient_light_energy = 1.0
		_env.fog_light_color = Color(0.72, 0.76, 0.82)
		_sun.light_color = Color(1.0, 0.9, 0.76)
		_sun.light_energy = 1.9
		_sun.rotation_degrees = Vector3(-38, -35, 0)
		_fill.light_color = Color(0.6, 0.75, 1.0)
		_fill.light_energy = 0.35
		_fill.rotation_degrees = Vector3(-15, 150, 0)
	for n: Node in get_tree().get_nodes_in_group("kit_night_light"):
		if n is Light3D:
			(n as Light3D).visible = night


func _set_view(i: int) -> void:
	if _shots.is_empty():
		return
	var sh: Dictionary = _shots[mini(i, _shots.size() - 1)]
	var it: Dictionary = _items[int(sh["item"])]
	if bool(sh["night"]) != _night:
		_apply_light(bool(sh["night"]))
	var span: float = float(it.get("span", 12.0))
	var h: float = float(it.get("height", 6.0))
	var z: float = -int(sh["item"]) * SPACING
	var dist: float = float(it.get("dist", span * 2.1))
	var target := Vector3(0, h * 0.42, z)
	_cam.position = target + Vector3(dist * 0.32, dist * 0.42, dist)
	_cam.look_at(target)


func _process(_delta: float) -> void:
	if _out == "" or _shots.is_empty():
		return
	_frames += 1
	if _i < 0:
		if _frames < 12:  # shader compile / first frames
			return
		_i = 0
		_frames = 0
		_set_view(0)
		return
	if _i >= _shots.size():
		get_tree().quit()
		return
	if _frames < 5:
		return
	var sh: Dictionary = _shots[_i]
	var path: String = "%s_%s_%s.png" % [_out, _items[int(sh["item"])]["name"], "night" if sh["night"] else "day"]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	get_viewport().get_texture().get_image().save_png(path)
	print("[kit] shot ", path)
	_i += 1
	_frames = 0
	if _i < _shots.size():
		_set_view(_i)
