class_name PatchModel
extends Node3D
## The player's robot: a futuristic hover bot sent down to clean and repair the world.
## Matches the owner's concept sheet: a big wide rounded head with a glossy black visor and thick
## glowing "C" eyes, round ear lenses with glow rings, a curved antenna ending in an orange fin,
## orange accents, a compact torso with an orange-framed chest screen and glowing waist slots,
## segmented arms with three-finger claws (the right one projects a tractor beam), and a hover
## bowl with a bright thruster ring instead of legs. Worn, dusty paint. Colorways are unlockable designs ("aurora" is
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
var _beam_mat: ShaderMaterial
var _beam_big: bool = false
## World position the tractor beam locks onto (null = no beam).
var _beam_target: Variant = null
var _beam_amt: float = 0.0
var _spark_t: float = 0.0
var _fill_bar: MeshInstance3D
var _icon: Label3D
var _icon_color := Color.WHITE
## Pickup feedback: hopper pop (fill bar + chest icon) and a quick eye flash.
var _hopper_pulse: float = 0.0
var _eye_flash: float = 0.0
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
## Holding up the survey hologram (right claw raised, palm up).
var holding: bool = false
var _hold: float = 0.0


func _ready() -> void:
	variant = str(GameState.flags.get("patch_skin", "aurora"))
	if not VARIANTS.has(variant):
		variant = "aurora"
	_build()
	if DevHooks.has("beam-demo"):
		beam_at(Vector3(0.45, 0.25, -0.9))


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
	var accent: ShaderMaterial = _paint(v["accent"], 11.0, 0.8)
	var dark: StandardMaterial3D = Mats.metal("dark_steel")
	var glow: Color = v["glow"]
	var glow_mat: StandardMaterial3D = Mats.lamp(glow, 3.5)
	_root = Node3D.new()
	add_child(_root)
	_float = Node3D.new()
	_root.add_child(_float)

	# --- Hover base: dark bowl, thin accent rim, bright thruster ring and light pool.
	_mi(_float, ProcMesh.hemisphere(0.2, 28, 7), trim, Vector3(0, 0.22, 0), Vector3(180, 0, 0), Vector3(1.0, 0.62, 1.0))
	_mi(_float, ProcMesh.torus(0.19, 0.215, 36, 5), accent, Vector3(0, 0.215, 0), Vector3.ZERO, Vector3(1, 0.5, 1))
	_ring_mat = Mats.lamp(glow, 4.5)
	_mi(_float, ProcMesh.torus(0.1, 0.14, 36, 6), _ring_mat, Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(1, 0.45, 1))
	_mi(_float, ProcMesh.cyl(0.1, 0.1, 0.01, 28), Mats.lamp(glow.lightened(0.35), 5.0), Vector3(0, 0.092, 0))
	var hover_light := OmniLight3D.new()
	hover_light.light_color = glow
	hover_light.light_energy = 1.4
	hover_light.omni_range = 1.4
	hover_light.position = Vector3(0, 0.02, 0)
	_float.add_child(hover_light)

	# --- Torso: compact cream body, dark side plates, orange-framed chest screen, glowing waist slots.
	_mi(_float, ProcMesh.rounded_box(Vector3(0.44, 0.3, 0.36), 0.12, 4), paint, Vector3(0, 0.38, 0))
	for x: float in [-0.215, 0.215]:
		_mi(_float, ProcMesh.rounded_box(Vector3(0.05, 0.2, 0.26), 0.025, 2), trim, Vector3(x, 0.38, 0.0))
		_mi(_float, ProcMesh.rounded_box(Vector3(0.04, 0.09, 0.1), 0.018, 2), accent, Vector3(x * 1.08, 0.36, -0.07))
	# Chest screen: orange frame, dark glass, glowing icon.
	_mi(_float, ProcMesh.rounded_box(Vector3(0.24, 0.17, 0.04), 0.03, 2), accent, Vector3(0, 0.395, -0.168))
	_mi(_float, ProcMesh.rounded_box(Vector3(0.18, 0.13, 0.03), 0.02, 2), Mats.glass(Color(0.03, 0.05, 0.07, 1.0)), Vector3(0, 0.395, -0.182))
	var icon: String = str(v.get("icon", "recycle"))
	var icon_l := Label3D.new()
	icon_l.text = "+" if icon == "plus" else ("❦" if icon == "leaf" else "♻")
	icon_l.font_size = 64
	icon_l.pixel_size = 0.0015
	icon_l.modulate = glow.lightened(0.25)
	icon_l.outline_size = 0
	icon_l.shaded = false
	icon_l.position = Vector3(0, 0.4, -0.2)
	_float.add_child(icon_l)
	_icon = icon_l
	_icon_color = icon_l.modulate
	_fill_bar = _mi(_float, ProcMesh.box(Vector3(0.14, 0.01, 0.01)), Mats.lamp(glow, 2.5), Vector3(0, 0.343, -0.2))
	_fill_bar.scale.x = 0.01
	# Waist: dark band with a row of glowing slots across the front.
	_mi(_float, ProcMesh.cyl(0.2, 0.19, 0.05, 32), dark, Vector3(0, 0.255, 0), Vector3.ZERO, Vector3(1.05, 1, 0.9))
	for k: int in 5:
		var ax: float = deg_to_rad(-40.0 + k * 20.0)
		_mi(_float, ProcMesh.rounded_box(Vector3(0.05, 0.022, 0.02), 0.008, 1), glow_mat, Vector3(sin(ax) * 0.205, 0.255, -cos(ax) * 0.18), Vector3(0, -rad_to_deg(ax), 0))
	# Back hatch where bales come out.
	_hatch = Node3D.new()
	_hatch.position = Vector3(0, 0.48, 0.17)
	_float.add_child(_hatch)
	_mi(_hatch, ProcMesh.rounded_box(Vector3(0.24, 0.19, 0.03), 0.025, 2), trim, Vector3(0, -0.095, 0.0))
	_mi(_hatch, ProcMesh.box(Vector3(0.12, 0.012, 0.01)), Mats.lamp(glow, 1.5), Vector3(0, -0.05, 0.018))
	_mi(_hatch, ProcMesh.rounded_box(Vector3(0.05, 0.05, 0.02), 0.01, 1), accent, Vector3(0.08, -0.14, 0.018))

	# --- Arms with three-finger claws.
	_arm_l = _build_arm(-1.0, paint, trim, accent, dark, glow)
	_arm_r = _build_arm(1.0, paint, trim, accent, dark, glow)

	# --- Head: big, wide, rounded; most of the front is a glossy black visor.
	_mi(_float, ProcMesh.cyl(0.07, 0.08, 0.06, 14), dark, Vector3(0, 0.55, 0))
	_head = Node3D.new()
	_head.position = Vector3(0, 0.56, 0)
	_float.add_child(_head)
	_mi(_head, ProcMesh.rounded_box(Vector3(0.74, 0.5, 0.56), 0.22, 7), paint, Vector3(0, 0.24, 0))
	# Dark bezel around the visor, then the screen.
	_mi(_head, ProcMesh.rounded_box(Vector3(0.64, 0.42, 0.53), 0.13, 6), trim, Vector3(0, 0.235, -0.03))
	_face_mat = ShaderMaterial.new()
	_face_mat.shader = preload("res://art/shaders/bot_face.gdshader")
	_face_mat.set_shader_parameter("eye_color", glow)
	_face_mat.set_shader_parameter("half_width", 0.29)
	_face_mat.set_shader_parameter("half_height", 0.18)
	_mi(_head, ProcMesh.rounded_box(Vector3(0.6, 0.38, 0.53), 0.1, 6), _face_mat, Vector3(0, 0.235, -0.04))
	# Orange accents: a stripe along the crown and small tabs beside the visor.
	_mi(_head, ProcMesh.rounded_box(Vector3(0.09, 0.03, 0.2), 0.012, 2), accent, Vector3(-0.16, 0.48, 0.08), Vector3(0, 0, 8))
	for x: float in [-0.335, 0.335]:
		_mi(_head, ProcMesh.rounded_box(Vector3(0.025, 0.07, 0.09), 0.012, 2), Mats.lamp((v["accent"] as Color), 1.6), Vector3(x * 1.08, 0.05, -0.12))
	# Ears: compact mechanical caps (not lenses, so they never read as extra eyes): a white
	# housing, a dark trim ring, a thin glowing accent arc, and a vented end cap.
	for x: float in [-0.372, 0.372]:
		var sx: float = signf(x)
		var ear := Node3D.new()
		ear.position = Vector3(x, 0.2, 0.05)
		ear.rotation_degrees = Vector3(0, 0, 90)
		_head.add_child(ear)
		_mi(ear, ProcMesh.cyl(0.12, 0.13, 0.05, 36), paint, Vector3(0, -sx * 0.012, 0))
		_mi(ear, ProcMesh.cyl(0.105, 0.105, 0.014, 36), trim, Vector3(0, -sx * 0.036, 0))
		_mi(ear, ProcMesh.torus(0.088, 0.096, 36, 4), Mats.lamp(glow, 2.2), Vector3(0, -sx * 0.042, 0))
		_mi(ear, ProcMesh.cyl(0.075, 0.08, 0.02, 32), paint, Vector3(0, -sx * 0.046, 0))
		for k: int in 3:
			_mi(ear, ProcMesh.box(Vector3(0.09, 0.012, 0.01)), trim, Vector3(0, -sx * 0.057, -0.03 + k * 0.03), Vector3(90, 0, 0))
	# Antenna: a dark curved stalk from the back of the crown ending in an orange swept fin.
	var fin := Node3D.new()
	fin.position = Vector3(0.06, 0.48, 0.12)
	_head.add_child(fin)
	_mi(fin, ProcMesh.cyl(0.04, 0.05, 0.035, 14), trim, Vector3.ZERO)
	var seg1 := Node3D.new()
	seg1.rotation_degrees = Vector3(28, 0, -10)
	fin.add_child(seg1)
	_mi(seg1, ProcMesh.cyl(0.016, 0.02, 0.12, 8), dark, Vector3(0, 0.06, 0))
	var seg2 := Node3D.new()
	seg2.position = Vector3(0, 0.12, 0)
	seg2.rotation_degrees = Vector3(-80, 0, 0)
	seg1.add_child(seg2)
	_mi(seg2, ProcMesh.sphere(0.022, 10, 5), dark, Vector3.ZERO)
	_mi(seg2, ProcMesh.cyl(0.013, 0.016, 0.07, 8), dark, Vector3(0, 0.035, 0))
	_mi(seg2, ProcMesh.rounded_box(Vector3(0.07, 0.18, 0.025), 0.012, 3), accent, Vector3(0, 0.14, 0.0), Vector3(-15, 0, 0))
	_mi(seg2, ProcMesh.sphere(0.014, 8, 4), Mats.lamp((v["accent"] as Color).lightened(0.3), 3.0), Vector3(0, 0.23, -0.02))
	# Variant extras.
	if v.get("leaf", false):
		var sprout := Node3D.new()
		sprout.position = Vector3(-0.12, 0.48, -0.02)
		_head.add_child(sprout)
		var leaf_mat := StandardMaterial3D.new()
		leaf_mat.albedo_color = Color(0.35, 0.75, 0.25)
		leaf_mat.roughness = 0.5
		_mi(sprout, ProcMesh.cyl(0.008, 0.01, 0.12, 6), leaf_mat, Vector3(0, 0.06, 0))
		_mi(sprout, ProcMesh.sphere(0.05, 10, 5), leaf_mat, Vector3(0.04, 0.13, 0), Vector3(0, 0, -30), Vector3(1.4, 0.25, 0.8))
		_mi(sprout, ProcMesh.sphere(0.04, 10, 5), leaf_mat, Vector3(-0.035, 0.11, 0), Vector3(0, 0, 30), Vector3(1.4, 0.25, 0.8))
	match str(v.get("ears", "")):
		"cat":
			for x: float in [-0.22, 0.22]:
				_mi(_head, ProcMesh.cyl(0.0, 0.09, 0.16, 4), trim, Vector3(x, 0.5, 0.02), Vector3(0, 45, signf(x) * -12))
				_mi(_head, ProcMesh.cyl(0.0, 0.055, 0.11, 4), Mats.lamp(glow, 2.0), Vector3(x, 0.49, 0.0), Vector3(0, 45, signf(x) * -12))
		"round":
			for x: float in [-0.24, 0.24]:
				_mi(_head, ProcMesh.hemisphere(0.09, 14, 5), trim, Vector3(x, 0.46, 0.02), Vector3(0, 0, signf(x) * -25))
	# Tractor beam from the right claw: a cone of scrolling energy rings (tractor_beam shader)
	# that stretches to whatever is being picked up. The twin lasers and arcs are PickupFx.
	_beam = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.03
	cone.bottom_radius = 0.12
	cone.height = 1.0
	cone.radial_segments = 24
	cone.rings = 6
	cone.cap_top = false
	cone.cap_bottom = false
	_beam.mesh = cone
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = preload("res://art/shaders/tractor_beam.gdshader")
	_beam_mat.set_shader_parameter("beam_color", glow)
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.top_level = true
	_beam.visible = false
	add_child(_beam)


func _build_arm(side: float, paint: Material, trim: Material, accent: Material, dark: Material, glow: Color) -> Node3D:
	var shoulder := Node3D.new()
	shoulder.position = Vector3(0.26 * side, 0.44, -0.02)
	_float.add_child(shoulder)
	_mi(shoulder, ProcMesh.sphere(0.06, 14, 7), dark, Vector3.ZERO)
	# Armoured upper arm with an accent band.
	_mi(shoulder, ProcMesh.rounded_box(Vector3(0.085, 0.16, 0.09), 0.035, 3), paint, Vector3(0.045 * side, -0.07, -0.03), Vector3(-25, 0, side * 22))
	_mi(shoulder, ProcMesh.rounded_box(Vector3(0.09, 0.025, 0.095), 0.01, 1), accent, Vector3(0.06 * side, -0.11, -0.05), Vector3(-25, 0, side * 22))
	var elbow := Node3D.new()
	elbow.position = Vector3(0.08 * side, -0.13, -0.08)
	shoulder.add_child(elbow)
	_mi(elbow, ProcMesh.sphere(0.04, 12, 6), dark, Vector3.ZERO)
	# Forearm: dark mechanical with a piston and a glowing wrist ring.
	_mi(elbow, ProcMesh.rounded_box(Vector3(0.06, 0.06, 0.15), 0.02, 2), trim, Vector3(0, -0.005, -0.08))
	_mi(elbow, ProcMesh.cyl(0.01, 0.01, 0.12, 6), Mats.metal("steel"), Vector3(0.035 * side, 0.02, -0.07), Vector3(90, 0, 0))
	var wrist := Node3D.new()
	wrist.position = Vector3(0, -0.01, -0.17)
	elbow.add_child(wrist)
	_mi(wrist, ProcMesh.torus(0.026, 0.04, 16, 4), Mats.lamp(glow, 2.5), Vector3.ZERO, Vector3(90, 0, 0))
	_mi(wrist, ProcMesh.cyl(0.04, 0.035, 0.04, 14), dark, Vector3(0, 0, -0.03), Vector3(90, 0, 0))
	for k: int in 3:
		var a: float = TAU * k / 3.0 + PI * 0.5
		var f := Node3D.new()
		f.position = Vector3(cos(a) * 0.028, sin(a) * 0.028, -0.05)
		wrist.add_child(f)
		_mi(f, ProcMesh.capsule(0.014, 0.06), dark, Vector3(cos(a) * 0.006, sin(a) * 0.006, -0.025), Vector3(90, 0, 0))
		var tip := Node3D.new()
		tip.position = Vector3(cos(a) * 0.01, sin(a) * 0.01, -0.055)
		tip.rotation = Vector3(-sin(a), cos(a), 0) * -0.5
		f.add_child(tip)
		_mi(tip, ProcMesh.capsule(0.012, 0.05), trim, Vector3(0, 0, -0.02), Vector3(90, 0, 0))
		f.set_meta("dir", Vector2(cos(a), sin(a)))
		_claws.append(f)
	shoulder.set_meta("elbow", elbow)
	shoulder.set_meta("wrist", wrist)
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
	_hold = move_toward(_hold, 1.0 if holding else 0.0, delta * 3.0)
	if _hold > 0.0:
		var e: float = _hold * _hold * (3.0 - 2.0 * _hold)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -1.25 + sin(_t * 1.6) * 0.03, e)
		_arm_r.rotation.z = lerpf(_arm_r.rotation.z, 0.35, e)
		var elbow_h: Node3D = _arm_r.get_meta("elbow")
		elbow_h.rotation.x = lerpf(0.0, 0.9, e)
	for f: Node3D in _claws:
		var dir: Vector2 = f.get_meta("dir")
		var open: float = (0.5 + 0.5 * sin(s * 1.5)) if _scoop_amt > 0.1 else lerpf(0.2, 0.9, _hold)
		f.rotation = Vector3(-dir.y, dir.x, 0) * open * 0.6
	_update_beam(delta)
	_update_hopper(delta)
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
	_eye_flash = maxf(0.0, _eye_flash - delta * 6.0)
	_face_mat.set_shader_parameter("energy", 1.2 if sleeping else 4.0 + _flash * 2.0 + _eye_flash * 3.0)


func set_motion(speed: float, speed_ratio: float, local_accel: Vector2, delta: float) -> void:
	var target := Vector2(clampf(-local_accel.y * 0.015, -0.18, 0.18) - speed_ratio * 0.08, clampf(local_accel.x * 0.012, -0.15, 0.15))
	_lean = _lean.lerp(target, clampf(delta * 6.0, 0.0, 1.0))
	_ring_mat.emission_energy_multiplier += speed * 0.3


## Lock the claw's tractor beam onto a world position (null releases it). `big` widens it.
func beam_at(world_pos: Variant, big: bool = false) -> void:
	_beam_target = world_pos
	_beam_big = big
	if world_pos != null:
		_scoop_t = maxf(_scoop_t, 0.2)


func claw_point() -> Vector3:
	var wrist: Node3D = _arm_r.get_meta("wrist")
	return wrist.to_global(Vector3(0, 0, -0.1))


## Left claw tip (the second laser emitter).
func claw_point_l() -> Vector3:
	var wrist: Node3D = _arm_l.get_meta("wrist")
	return wrist.to_global(Vector3(0, 0, -0.1))


## World position of the chest hopper screen (where pickups stream in).
func chest_world() -> Vector3:
	return _float.to_global(Vector3(0, 0.395, -0.2))


## Quick brightening of the visor eyes (target lock).
func eye_flash(amount: float = 0.4) -> void:
	_eye_flash = maxf(_eye_flash, amount)


## Soft pop on the chest panel: the fill bar and icon flare as a pickup lands in the hopper.
func hopper_pulse(amount: float = 0.6) -> void:
	_hopper_pulse = clampf(maxf(_hopper_pulse, amount), 0.0, 1.0)


func _update_hopper(delta: float) -> void:
	if _fill_bar == null:
		return
	_hopper_pulse = maxf(0.0, _hopper_pulse - delta * 5.0)
	var p: float = _hopper_pulse
	_fill_bar.scale.y = 1.0 + p * 2.5
	_fill_bar.scale.z = 1.0 + p * 1.5
	(_fill_bar.material_override as StandardMaterial3D).emission_energy_multiplier = 2.5 + p * 7.0
	if _icon:
		_icon.modulate = _icon_color.lerp(Color(1.6, 1.8, 1.9), p * 0.8)
		_icon.scale = Vector3.ONE * (1.0 + p * 0.18)


func _update_beam(delta: float) -> void:
	_beam_amt = move_toward(_beam_amt, 1.0 if _beam_target != null else 0.0, delta * 8.0)
	var on: bool = _beam_amt > 0.02 and _beam_target != null
	_beam.visible = false  # no cone: the pickup is a few thin lasers (player/pickup_fx.gd)
	if not on:
		return
	var a: Vector3 = claw_point()
	var b: Vector3 = _beam_target
	var d: Vector3 = b - a
	var len: float = maxf(d.length(), 0.05)
	var y: Vector3 = d / len
	var x: Vector3 = y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z: Vector3 = x.cross(y)
	# Cylinder top (narrow) at the claw, wide end at the target.
	var w: float = 1.35 if _beam_big else 1.0
	var basis := Basis(x * w, -y * len, z * w)
	_beam.global_transform = Transform3D(basis, a + d * 0.5)
	_beam_mat.set_shader_parameter("beam_length", len)
	_beam_mat.set_shader_parameter("intensity", _beam_amt * (1.25 if _beam_big else 1.0))
	_spark_t -= delta
	if _spark_t <= 0.0:
		_spark_t = 0.16
		Vfx.burst("sparkle", b, VARIANTS[variant]["glow"], 0.1)
	# Aim the right arm toward the target.
	var local: Vector3 = _float.global_transform.affine_inverse() * b
	var reach: float = clampf(-atan2(local.y - 0.4, -local.z) , -1.4, 0.3)
	_arm_r.rotation.x = lerpf(_arm_r.rotation.x, reach - 0.3, _beam_amt)


## World position just above the raised right claw (where the hologram sits).
func hand_point() -> Vector3:
	return claw_point() + Vector3(0, 0.05, 0)


func set_scooping(active: bool) -> void:
	if active:
		_scoop_t = 0.15


func set_fill(ratio: float, band: Array) -> void:
	if _fill_bar == null:
		return
	_fill_bar.scale.x = clampf(ratio, 0.01, 1.1)
	var m: StandardMaterial3D = _fill_bar.material_override
	hopper_pulse(0.3)
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
	_head_yaw_target = clampf(yaw * 0.5, -0.45, 0.45)
	# Eyes stay facing forward; only the head turns (a hint of eye shift for life).
	_look_target = Vector2(clampf(-yaw * 0.3, -0.2, 0.2), 0.0)


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
