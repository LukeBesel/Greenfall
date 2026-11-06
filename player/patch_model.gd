class_name PatchModel
extends Node3D
## The player's robot: a futuristic hover bot sent down to clean and repair the world.
## Big rounded head with a black glass screen face (glowing expressive eyes), round side lenses,
## a bulb antenna, a compact torso with a chest panel, small articulated claw arms, and a glowing
## hover ring instead of legs. Worn, dusty paint. Colorways are unlockable designs ("aurora" is
## the default look). Faces -Z. Base (hover ring) near y=0.

const VARIANTS: Dictionary = {
	"aurora": {"name": "Aurora", "paint": Color(0.9, 0.9, 0.87), "trim": Color(0.36, 0.38, 0.42), "glow": Color(0.3, 0.88, 1.0), "accent": Color(1.0, 0.62, 0.2), "icon": "recycle"},
	"bolt": {"name": "Bolt", "paint": Color(0.95, 0.72, 0.12), "trim": Color(0.3, 0.27, 0.22), "glow": Color(1.0, 0.72, 0.2), "accent": Color(0.25, 0.22, 0.18), "icon": "recycle"},
	"sprout": {"name": "Sprout", "paint": Color(0.5, 0.56, 0.24), "trim": Color(0.3, 0.32, 0.2), "glow": Color(0.55, 1.0, 0.35), "accent": Color(0.85, 0.7, 0.3), "icon": "leaf", "leaf": true},
	"pixel": {"name": "Pixel", "paint": Color(0.85, 0.2, 0.18), "trim": Color(0.92, 0.9, 0.86), "glow": Color(1.0, 0.35, 0.5), "accent": Color(0.92, 0.9, 0.86), "icon": "recycle", "ears": "round"},
	"nova": {"name": "Nova", "paint": Color(0.26, 0.24, 0.3), "trim": Color(0.15, 0.14, 0.18), "glow": Color(0.72, 0.4, 1.0), "accent": Color(0.72, 0.4, 1.0), "icon": "recycle", "ears": "cat"},
	"patch": {"name": "Patch", "paint": Color(0.92, 0.9, 0.86), "trim": Color(0.35, 0.36, 0.38), "glow": Color(1.0, 0.7, 0.25), "accent": Color(1.0, 0.5, 0.15), "icon": "plus"},
}

var variant: String = "aurora"

# Interface used by Patch, the camera, the detector and baling.
var chest_point := Vector3(0, 0.38, -0.22)
var back_hatch_point := Vector3(0, 0.36, 0.2)
var vent_points: Array[Vector3] = [Vector3(-0.33, 0.78, 0.0), Vector3(0.33, 0.78, 0.0)]
var stack_point := Vector3(0, 1.22, 0.3)
var lens_point := Vector3(0, 0.78, -0.3)
var sleeping: bool = false
var _iris_now: float = 0.5

var _root: Node3D
var _float: Node3D
var _head: Node3D
var _face_mat: ShaderMaterial
var _ring_mat: StandardMaterial3D
var _arm_l: Node3D
var _arm_r: Node3D
var _claws: Array[Node3D] = []
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _fill_bar: MeshInstance3D
var _hatch: Node3D

var _t: float = 0.0
var _scoop_t: float = 0.0
var _scoop_amt: float = 0.0
var _shudder: float = 0.0
var _press: float = 0.0
var _happy: float = 0.5
var _happy_target: float = 0.5
var _look := Vector2.ZERO
var _look_target := Vector2.ZERO
var _head_yaw: float = 0.0
var _head_yaw_target: float = 0.0
var _blink_timer: float = 2.5
var _blink: float = 0.0
var _flash: float = 0.0
var _lean := Vector2.ZERO
var _dip: float = 0.0


func _ready() -> void:
	variant = str(GameState.flags.get("patch_skin", "aurora"))
	if not VARIANTS.has(variant):
		variant = "aurora"
	_build()


## Switch colorway (cosmetic unlocks).
func set_variant(v: String) -> void:
	if not VARIANTS.has(v):
		return
	variant = v
	for c: Node in get_children():
		c.free()
	_claws.clear()
	_build()


func _paint(c: Color, seed: float, coverage: float = 0.86) -> ShaderMaterial:
	var m: ShaderMaterial = Mats.worn_paint(c, coverage, 0.25, seed, 0.45)
	m.set_shader_parameter("paint_roughness", 0.42)
	m.set_shader_parameter("dust", 0.55)
	return m


func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot
	m.scale = scl
	parent.add_child(m)
	return m


func _build() -> void:
	var v: Dictionary = VARIANTS[variant]
	var paint: ShaderMaterial = _paint(v["paint"], 3.0)
	var trim: ShaderMaterial = _paint(v["trim"], 7.0, 0.9)
	var accent: ShaderMaterial = _paint(v["accent"], 11.0, 0.88)
	var dark: StandardMaterial3D = Mats.metal("dark_steel")
	var glow: Color = v["glow"]
	_root = Node3D.new()
	add_child(_root)
	_float = Node3D.new()
	_root.add_child(_float)

	# Hover base: a dark bowl with a glowing ring and a soft light on the ground.
	_mi(_float, ProcMesh.hemisphere(0.17, 24, 6), trim, Vector3(0, 0.2, 0), Vector3(180, 0, 0), Vector3(1.0, 0.7, 1.0))
	_ring_mat = Mats.lamp(glow, 4.0)
	_mi(_float, ProcMesh.torus(0.1, 0.15, 32, 6), _ring_mat, Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(1, 0.5, 1))
	_mi(_float, ProcMesh.cyl(0.1, 0.1, 0.01, 24), Mats.lamp(glow.lightened(0.3), 5.0), Vector3(0, 0.085, 0))
	var hover_light := OmniLight3D.new()
	hover_light.light_color = glow
	hover_light.light_energy = 1.2
	hover_light.omni_range = 1.3
	hover_light.position = Vector3(0, 0.02, 0)
	_float.add_child(hover_light)

	# Torso.
	_mi(_float, ProcMesh.rounded_box(Vector3(0.42, 0.28, 0.34), 0.11, 4), paint, Vector3(0, 0.37, 0))
	_mi(_float, ProcMesh.torus(0.17, 0.2, 32, 6), Mats.lamp(glow, 3.0), Vector3(0, 0.255, 0), Vector3.ZERO, Vector3(1.05, 0.5, 0.85))
	# Chest panel with icon and fill bar.
	_mi(_float, ProcMesh.rounded_box(Vector3(0.2, 0.15, 0.03), 0.03, 2), Mats.metal("dark_steel"), Vector3(0, 0.38, -0.172))
	var icon: String = str(v.get("icon", "recycle"))
	var icon_l := Label3D.new()
	icon_l.text = "+" if icon == "plus" else ("❦" if icon == "leaf" else "♻")
	icon_l.font_size = 64
	icon_l.pixel_size = 0.0016
	icon_l.modulate = glow.lightened(0.2)
	icon_l.outline_size = 0
	icon_l.shaded = false
	icon_l.position = Vector3(0, 0.385, -0.19)
	_float.add_child(icon_l)
	_fill_bar = _mi(_float, ProcMesh.box(Vector3(0.14, 0.012, 0.01)), Mats.lamp(glow, 2.5), Vector3(0, 0.315, -0.19))
	_fill_bar.scale.x = 0.01
	# Side vents and a back hatch where bales come out.
	for x: float in [-0.185, 0.185]:
		for k: int in 3:
			_mi(_float, ProcMesh.box(Vector3(0.012, 0.012, 0.12)), dark, Vector3(x, 0.33 + k * 0.03, 0.02))
	_hatch = Node3D.new()
	_hatch.position = Vector3(0, 0.46, 0.15)
	_float.add_child(_hatch)
	_mi(_hatch, ProcMesh.rounded_box(Vector3(0.22, 0.18, 0.025), 0.02, 2), trim, Vector3(0, -0.09, 0.0))
	_mi(_hatch, ProcMesh.box(Vector3(0.12, 0.012, 0.01)), Mats.lamp(glow, 1.5), Vector3(0, -0.04, 0.015))

	# Arms with claw hands.
	_arm_l = _build_arm(-1.0, paint, trim, dark, glow)
	_arm_r = _build_arm(1.0, paint, trim, dark, glow)

	# Neck + head.
	_mi(_float, ProcMesh.cyl(0.06, 0.07, 0.08, 12), dark, Vector3(0, 0.52, 0))
	_head = Node3D.new()
	_head.position = Vector3(0, 0.56, 0)
	_float.add_child(_head)
	_mi(_head, ProcMesh.rounded_box(Vector3(0.66, 0.47, 0.5), 0.21, 6), paint, Vector3(0, 0.22, 0))
	# Screen face: a glossy black rounded panel inset in the front, eyes drawn by a shader.

	_face_mat = ShaderMaterial.new()
	_face_mat.shader = preload("res://art/shaders/bot_face.gdshader")
	_face_mat.set_shader_parameter("eye_color", glow)
	_face_mat.set_shader_parameter("half_width", 0.26)
	_face_mat.set_shader_parameter("half_height", 0.165)
	# The visor is a slightly smaller rounded shell pushed forward through the white helmet.
	_mi(_head, ProcMesh.rounded_box(Vector3(0.56, 0.37, 0.48), 0.17, 6), _face_mat, Vector3(0, 0.22, -0.035))
	# Side lenses ("ears") with glowing rings.
	for x: float in [-0.335, 0.335]:
		_mi(_head, ProcMesh.cyl(0.11, 0.115, 0.06, 28), trim, Vector3(x, 0.21, 0), Vector3(0, 0, 90))
		_mi(_head, ProcMesh.torus(0.06, 0.085, 28, 5), Mats.lamp(glow, 3.5), Vector3(x * 1.1, 0.21, 0), Vector3(0, 0, 90))
		_mi(_head, ProcMesh.cyl(0.055, 0.055, 0.02, 24), Mats.glass(Color(0.04, 0.06, 0.08, 1.0)), Vector3(x * 1.1, 0.21, 0), Vector3(0, 0, 90))
	# Antenna: a short springy stalk with a glowing bulb on top.
	var fin := Node3D.new()
	fin.position = Vector3(0.0, 0.425, 0.02)
	fin.rotation_degrees = Vector3(-10, 0, -6)
	_head.add_child(fin)
	_mi(fin, ProcMesh.cyl(0.05, 0.06, 0.03, 16), trim, Vector3(0, 0.0, 0))
	_mi(fin, ProcMesh.cyl(0.014, 0.018, 0.13, 8), trim, Vector3(0, 0.075, 0))
	_mi(fin, ProcMesh.sphere(0.045, 16, 8), Mats.lamp((v["accent"] as Color).lightened(0.2), 3.0), Vector3(0, 0.16, 0))
	# Variant extras.
	if v.get("leaf", false):
		var sprout := Node3D.new()
		sprout.position = Vector3(-0.12, 0.45, -0.02)
		_head.add_child(sprout)
		var leaf_mat := StandardMaterial3D.new()
		leaf_mat.albedo_color = Color(0.35, 0.75, 0.25)
		leaf_mat.roughness = 0.5
		_mi(sprout, ProcMesh.cyl(0.008, 0.01, 0.12, 6), leaf_mat, Vector3(0, 0.06, 0))
		_mi(sprout, ProcMesh.sphere(0.05, 10, 5), leaf_mat, Vector3(0.04, 0.13, 0), Vector3(0, 0, -30), Vector3(1.4, 0.25, 0.8))
		_mi(sprout, ProcMesh.sphere(0.04, 10, 5), leaf_mat, Vector3(-0.035, 0.11, 0), Vector3(0, 0, 30), Vector3(1.4, 0.25, 0.8))
	match str(v.get("ears", "")):
		"cat":
			for x: float in [-0.2, 0.2]:
				_mi(_head, ProcMesh.cyl(0.0, 0.08, 0.14, 4), trim, Vector3(x, 0.47, 0.02), Vector3(0, 45, signf(x) * -12))
				_mi(_head, ProcMesh.cyl(0.0, 0.05, 0.1, 4), Mats.lamp(glow, 2.0), Vector3(x, 0.46, 0.0), Vector3(0, 45, signf(x) * -12))
		"round":
			for x: float in [-0.22, 0.22]:
				_mi(_head, ProcMesh.hemisphere(0.08, 14, 5), trim, Vector3(x, 0.43, 0.02), Vector3(0, 0, signf(x) * -25))
	# Tractor beam from the right claw (scooping).
	_beam = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.16
	cone.height = 0.7
	cone.radial_segments = 16
	cone.cap_top = false
	cone.cap_bottom = false
	_beam.mesh = cone
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.albedo_color = Color(glow, 0.0)
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var elbow: Node3D = _arm_r.get_meta("elbow")
	elbow.add_child(_beam)
	_beam.position = Vector3(0, -0.02, -0.5)
	_beam.rotation_degrees = Vector3(-90, 0, 0)


func _build_arm(side: float, paint: Material, trim: Material, dark: Material, glow: Color) -> Node3D:
	var shoulder := Node3D.new()
	shoulder.position = Vector3(0.24 * side, 0.43, -0.02)
	_float.add_child(shoulder)
	_mi(shoulder, ProcMesh.sphere(0.05, 12, 6), trim, Vector3.ZERO)
	_mi(shoulder, ProcMesh.capsule(0.042, 0.17), paint, Vector3(0.04 * side, -0.05, -0.04), Vector3(-30, 0, side * 25))
	var elbow := Node3D.new()
	elbow.position = Vector3(0.07 * side, -0.1, -0.08)
	shoulder.add_child(elbow)
	_mi(elbow, ProcMesh.sphere(0.03, 10, 5), dark, Vector3.ZERO)
	_mi(elbow, ProcMesh.capsule(0.03, 0.15), trim, Vector3(0, -0.01, -0.07), Vector3(-80, 0, 0))
	var wrist := Node3D.new()
	wrist.position = Vector3(0, -0.02, -0.15)
	elbow.add_child(wrist)
	_mi(wrist, ProcMesh.cyl(0.035, 0.03, 0.04, 12), Mats.lamp(glow, 2.0), Vector3.ZERO, Vector3(90, 0, 0))
	for k: int in 3:
		var a: float = TAU * k / 3.0
		var f := Node3D.new()
		f.position = Vector3(cos(a) * 0.025, sin(a) * 0.025, -0.02)
		wrist.add_child(f)
		_mi(f, ProcMesh.capsule(0.013, 0.09), dark, Vector3(cos(a) * 0.01, sin(a) * 0.01, -0.04), Vector3(90, 0, 0))
		f.set_meta("dir", Vector2(cos(a), sin(a)))
		_claws.append(f)
	shoulder.set_meta("elbow", elbow)
	return shoulder


func _process(delta: float) -> void:
	_t += delta
	# Hover bob and ring pulse.
	_float.position.y = 0.04 + sin(_t * 2.4) * 0.02 - _dip
	_dip = maxf(0.0, _dip - delta * 0.4)
	_ring_mat.emission_energy_multiplier = 3.5 + sin(_t * 9.0) * 0.4 + _flash * 4.0
	_flash = maxf(0.0, _flash - delta * 2.0)
	# Arms: reach forward and pinch while scooping; the right claw projects a small tractor beam.
	_scoop_amt = move_toward(_scoop_amt, 1.0 if _scoop_t > 0.0 else 0.0, delta * 5.0)
	_scoop_t = maxf(0.0, _scoop_t - delta)
	var s: float = _t * 8.0
	_arm_r.rotation.x = lerpf(0.15 * sin(_t * 1.3), -0.9 + sin(s) * 0.15, _scoop_amt)
	_arm_l.rotation.x = lerpf(0.15 * sin(_t * 1.3 + 1.0), -0.5 + sin(s + 1.5) * 0.12, _scoop_amt * 0.7)
	_arm_r.rotation.z = lerpf(0.0, -0.25, _scoop_amt)
	for f: Node3D in _claws:
		var dir: Vector2 = f.get_meta("dir")
		var open: float = (0.5 + 0.5 * sin(s * 1.5)) if _scoop_amt > 0.1 else 0.2
		f.rotation = Vector3(-dir.y, dir.x, 0) * open * 0.6
	_beam_mat.albedo_color.a = _scoop_amt * (0.22 + 0.06 * sin(_t * 30.0))
	_beam.visible = _scoop_amt > 0.02
	# Press: the body compresses slightly while baling.
	_root.scale = Vector3(1.0 + _press * 0.04, 1.0 - _press * 0.06, 1.0 + _press * 0.04)
	if _shudder > 0.0:
		_shudder -= delta
		_root.position = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.01
	else:
		_root.position = Vector3.ZERO
	_float.rotation = Vector3(_lean.x, 0, _lean.y)
	# Head look and face.
	_head_yaw = lerp_angle(_head_yaw, _head_yaw_target, delta * 4.0)
	_head.rotation.y = _head_yaw
	_head.rotation.z = sin(_t * 0.7) * 0.03 + (0.08 if _happy > 0.8 else 0.0)
	_look = _look.lerp(_look_target, delta * 6.0)
	_happy = lerpf(_happy, _happy_target, delta * 4.0)
	_iris_now = _happy
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_timer = randf_range(2.0, 5.0)
		_blink = 1.0
	_blink = maxf(0.0, _blink - delta * 7.0)
	_face_mat.set_shader_parameter("look", _look)
	_face_mat.set_shader_parameter("happy", clampf((_happy - 0.6) * 2.5, 0.0, 1.0))
	_face_mat.set_shader_parameter("blink", 0.9 if sleeping else _blink)
	_face_mat.set_shader_parameter("energy", 1.2 if sleeping else 4.0 + _flash * 2.0)


func set_motion(speed: float, speed_ratio: float, local_accel: Vector2, delta: float) -> void:
	var target := Vector2(clampf(-local_accel.y * 0.015, -0.18, 0.18) - speed_ratio * 0.08, clampf(local_accel.x * 0.012, -0.15, 0.15))
	_lean = _lean.lerp(target, clampf(delta * 6.0, 0.0, 1.0))
	_ring_mat.emission_energy_multiplier += speed * 0.3


func set_scooping(active: bool) -> void:
	if active:
		_scoop_t = 0.15


func set_fill(ratio: float, band: Array) -> void:
	if _fill_bar == null:
		return
	_fill_bar.scale.x = clampf(ratio, 0.01, 1.1)
	var m: StandardMaterial3D = _fill_bar.material_override
	if ratio > float(band[1]) + 0.0001:
		m.emission = Color(1.0, 0.3, 0.25)
	elif ratio >= float(band[0]):
		m.emission = Color(1.0, 0.8, 0.3)
	else:
		m.emission = VARIANTS[variant]["glow"]


func shudder(duration: float = 0.3) -> void:
	_shudder = duration


func squash(amount: float) -> void:
	_dip = clampf(_dip + absf(amount) * 0.04, 0.0, 0.05)


func look_toward(world_pos: Variant) -> void:
	if world_pos == null:
		_head_yaw_target = 0.0
		_look_target = Vector2.ZERO
		return
	var local: Vector3 = global_transform.affine_inverse() * (world_pos as Vector3)
	var yaw: float = atan2(-local.x, -local.z)
	_head_yaw_target = clampf(yaw * 0.6, -0.7, 0.7)
	_look_target = Vector2(clampf(-yaw * 1.5, -1.0, 1.0), clampf(local.y * 0.5 - 0.3, -1.0, 1.0))


func set_happy(amount: float) -> void:
	_happy_target = clampf(amount, 0.0, 1.0)


func flash() -> void:
	_flash = 1.0


func set_rust(_amount: float) -> void:
	pass  # Wear comes from the worn-paint shader; colorways are swapped with set_variant().


func press(t: float) -> void:
	_press = clampf(t, 0.0, 1.0)


func open_hatch(t: float) -> void:
	if _hatch:
		_hatch.rotation.x = -clampf(t, 0.0, 1.0) * 1.3
