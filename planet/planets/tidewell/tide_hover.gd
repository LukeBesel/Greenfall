class_name TideHover
extends Node3D
## [planet-tidewell] Floating over water: Lumi rises onto the swell and bobs gently over water
## hexes, a foam wake ring and spreading ripples follow his hover skirt (ocean shader wakes), fine
## spray kicks up when he moves fast, and his reflection (a mirrored copy of his model, see
## mirror.gdshader) sits under him in open water. Skimmer robots get wakes too.

const MAX_WAKES: int = 8

var world: Node
var sea_y: float = HexField.WATER_Y
var ocean_mat: ShaderMaterial
var mirror_base: Dictionary = {}  # shared mirror.gdshader parameters (maps)
var reflections: bool = true

var _patch: Node3D
var _model: Node3D
var _mirror: Node3D
var _pairs: Array = []  # [src Node3D, dst Node3D]
var _mirror_mats: Dictionary = {}  # source material id -> ShaderMaterial
var _spray: CPUParticles3D
var _over: float = 0.0
var _t: float = 0.0
var _prev := Vector3.ZERO
var _speed: float = 0.0
var _robots_t: float = 0.0
var _robot_wakes: Array = []  # Node3D skimmers / hovering robots on water


func setup(p_world: Node) -> void:
	world = p_world
	_patch = world.get("patch")
	if _patch:
		_model = _patch.get("model")
		_prev = _patch.global_position
	_spray = CPUParticles3D.new()
	_spray.name = "HoverSpray"
	_spray.amount = 28
	_spray.lifetime = 0.7
	_spray.local_coords = false
	_spray.emitting = false
	_spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_spray.emission_ring_axis = Vector3.UP
	_spray.emission_ring_radius = 0.55
	_spray.emission_ring_inner_radius = 0.4
	_spray.emission_ring_height = 0.02
	_spray.direction = Vector3.UP
	_spray.spread = 35.0
	_spray.initial_velocity_min = 0.8
	_spray.initial_velocity_max = 1.8
	_spray.gravity = Vector3(0, -6.0, 0)
	_spray.scale_amount_min = 0.5
	_spray.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0.0))
	_spray.scale_amount_curve = curve
	var qm := QuadMesh.new()
	qm.size = Vector2(0.06, 0.06)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.albedo_color = Color(0.92, 0.97, 1.0, 0.7)
	sm.albedo_texture = _dot_tex()
	qm.material = sm
	_spray.mesh = qm
	_spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_spray)
	if reflections and _model and DisplayServer.get_name() != "headless":
		_build_mirror.call_deferred()


static func _dot_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32
	t.height = 32
	return t


func _process(delta: float) -> void:
	_t += delta
	if _patch == null or not is_instance_valid(_patch):
		return
	var f: HexField = world.field
	var pp: Vector3 = _patch.global_position
	var hv := Vector3(pp.x - _prev.x, 0.0, pp.z - _prev.z)
	_prev = pp
	_speed = lerpf(_speed, hv.length() / maxf(delta, 0.0001), clampf(delta * 8.0, 0.0, 1.0))
	var hid: int = f.hex_at(pp)
	var water_here: bool = hid >= 0 and f.is_water(hid)
	if hid < 0:
		water_here = true  # past the field edge it is open sea
	_over = move_toward(_over, 1.0 if water_here else 0.0, delta * 2.5)
	# Bob: ride up onto the water and roll gently with the swell.
	if _model and is_instance_valid(_model):
		var e: float = _over * _over * (3.0 - 2.0 * _over)
		_model.position.y = e * (0.2 + sin(_t * 1.7) * 0.045 + sin(_t * 0.63 + 1.1) * 0.02)
		_model.rotation.x = e * sin(_t * 1.1) * 0.035
		_model.rotation.z = e * sin(_t * 0.9 + 0.7) * 0.045
	# Wake ring + spray.
	var wakes: Array = []
	wakes.resize(MAX_WAKES)
	wakes.fill(Vector4.ZERO)
	var mv: float = clampf(_speed / 6.0, 0.0, 1.0)
	if _over > 0.01:
		wakes[0] = Vector4(pp.x, pp.z, _over * (0.55 + 0.45 * mv), 0.85 + mv * 0.5)
	_spray.global_position = Vector3(pp.x, sea_y + 0.03, pp.z)
	_spray.emitting = _over > 0.6 and _speed > 2.2
	_spray.speed_scale = lerpf(0.8, 1.3, mv)
	_robots_t -= delta
	if _robots_t <= 0.0:
		_robots_t = 1.0
		_collect_robots()
	var k: int = 1
	for rb: Node3D in _robot_wakes:
		if k >= MAX_WAKES:
			break
		if not is_instance_valid(rb):
			continue
		var rp: Vector3 = rb.global_position
		var rh: int = f.hex_at(rp)
		if rh >= 0 and f.is_water(rh) and rp.distance_squared_to(pp) < 3600.0:
			wakes[k] = Vector4(rp.x, rp.z, 0.6, 0.7)
			k += 1
	if ocean_mat:
		ocean_mat.set_shader_parameter("wakes", wakes)
	_sync_mirror()


## Skimmers (and any hovering/floating robot) leave wakes on the water.
func _collect_robots() -> void:
	_robot_wakes.clear()
	var fl: Node = world.get("fleet")
	if fl == null or not fl.has_method("robots"):
		return
	for rb: Node in fl.robots():
		var vis: Object = rb.get("visual")
		var floaty: bool = vis != null and (bool(vis.get("hover")) or bool(vis.get("floats")))
		if floaty or (rb.has_method("role") and str(rb.role()) == "skim"):
			_robot_wakes.append(rb)


# --- Reflection ----------------------------------------------------------------------------

func _build_mirror() -> void:
	if not is_instance_valid(_model):
		return
	var m: Node3D = PatchModel.new()
	if _model.get("variant") != null:
		m.set("variant", _model.get("variant"))
	m.name = "LumiReflection"
	add_child(m)
	m.set_process(false)
	_mirror = m
	_pairs.clear()
	_pair(_model, m)
	for pr: Array in _pairs:
		var dst: Node = pr[1]
		dst.set_process(false)
		if dst is MeshInstance3D:
			_dress(pr[0] as MeshInstance3D, dst as MeshInstance3D)
		elif dst is GeometryInstance3D or dst is Light3D:
			(dst as Node3D).visible = false


func _pair(a: Node, b: Node) -> void:
	if a is Node3D and b is Node3D and a != _model:
		_pairs.append([a, b])
	var n: int = mini(a.get_child_count(), b.get_child_count())
	for i: int in n:
		_pair(a.get_child(i), b.get_child(i))


func _dress(src: MeshInstance3D, dst: MeshInstance3D) -> void:
	dst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat: Material = src.material_override
	if mat == null and src.mesh and src.mesh.get_surface_count() > 0:
		mat = src.get_active_material(0)
	var key: int = mat.get_instance_id() if mat else 0
	if not _mirror_mats.has(key):
		var tint := Color(0.85, 0.85, 0.85)
		var glow: float = 0.0
		if mat is StandardMaterial3D:
			var sm: StandardMaterial3D = mat
			tint = sm.albedo_color
			if sm.emission_enabled:
				tint = sm.emission
				glow = 0.8
		elif mat is ShaderMaterial:
			var shm: ShaderMaterial = mat
			for p: String in ["paint_color", "albedo", "color"]:
				var v: Variant = shm.get_shader_parameter(p)
				if v is Color:
					tint = v
					break
			var ec: Variant = shm.get_shader_parameter("eye_color")
			if ec is Color:
				tint = (ec as Color).darkened(0.6)
				glow = 0.3
		var mm := ShaderMaterial.new()
		mm.shader = preload("res://planet/planets/tidewell/mirror.gdshader")
		mm.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b))
		mm.set_shader_parameter("glow", glow)
		mm.render_priority = 1
		for k: String in mirror_base:
			mm.set_shader_parameter(k, mirror_base[k])
		_mirror_mats[key] = mm
	dst.material_override = _mirror_mats[key]


func _sync_mirror() -> void:
	if _mirror == null:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	var on: bool = _over > 0.05 and _model.is_visible_in_tree() and cam != null and cam.global_position.distance_to(_model.global_position) < 70.0
	_mirror.visible = on
	if not on:
		return
	var refl := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, 1)), Vector3(0, 2.0 * sea_y, 0))
	_mirror.global_transform = refl * _model.global_transform
	for pr: Array in _pairs:
		var s: Node3D = pr[0]
		var d: Node3D = pr[1]
		if not is_instance_valid(s):
			continue
		d.transform = s.transform
		if d is MeshInstance3D:
			d.visible = s.visible
	var sun: DirectionalLight3D = world.get("_sun")
	var lit: float = clampf(sun.light_energy / 2.5, 0.25, 1.0) if sun else 1.0
	var a: float = 0.42 * _over
	for k: int in _mirror_mats:
		var mm: ShaderMaterial = _mirror_mats[k]
		mm.set_shader_parameter("lit", lit)
		mm.set_shader_parameter("strength", a)
