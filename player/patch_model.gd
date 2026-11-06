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
	"aurora": {"name": "Aurora", "paint": Color(0.9, 0.88, 0.83), "trim": Color(0.36, 0.38, 0.42), "glow": Color(0.3, 0.88, 1.0), "accent": Color(1.0, 0.5, 0.12), "icon": "recycle"},
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
var _beam_core: MeshInstance3D
## World position the tractor beam locks onto (null = no beam).
var _beam_target: Variant = null
var _beam_amt: float = 0.0
var _spark_t: float = 0.0
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


const MODEL_PATH := "res://art/models/aurora/aurora.glb"
const HERO_PAINT := preload("res://art/shaders/hero_paint.gdshader")
## Visual layer bit the hero's meshes also sit on, so his own key light only lights him.
const HERO_LAYER := 2
## Meshes and pivots baked from art/models/aurora (built by build_aurora.py in Blender).
static var _parts: Dictionary = {}
var _mats: Dictionary = {}
var _paint_mats: Array[ShaderMaterial] = []


static func _load_parts() -> void:
	if not _parts.is_empty():
		return
	var scene: PackedScene = load(MODEL_PATH)
	var inst: Node = scene.instantiate()
	for n: Node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		_parts[str(mi.name)] = {"mesh": mi.mesh, "pos": mi.position}
	inst.free()


static func _pivot(part: String) -> Vector3:
	_load_parts()
	return _parts[part]["pos"]


func _paint(c: Color, seed: float, coverage: float = 0.88, metal: float = 0.0, rough: float = 0.42) -> ShaderMaterial:
	var m: ShaderMaterial = Mats.worn_paint(c, coverage, 0.25, seed, 0.5)
	m.shader = HERO_PAINT
	m.set_shader_parameter("paint_roughness", rough)
	m.set_shader_parameter("paint_metallic", metal)
	m.set_shader_parameter("dust", 0.45)
	m.set_shader_parameter("grime", 0.6)
	m.set_shader_parameter("fade", 0.15 if c.s < 0.5 else 0.0)
	_paint_mats.append(m)
	return m


## Instance a baked part (mesh vertices are relative to its pivot) with per-surface materials.
func _part(parent: Node3D, part: String, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	_load_parts()
	var mi := MeshInstance3D.new()
	mi.mesh = _parts[part]["mesh"]
	mi.position = pos
	mi.layers = 1 | HERO_LAYER
	for i: int in mi.mesh.get_surface_count():
		var src: Material = mi.mesh.surface_get_material(i)
		var key: String = src.resource_name if src else ""
		if _mats.has(key):
			mi.set_surface_override_material(i, _mats[key])
	parent.add_child(mi)
	return mi


func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot
	m.scale = scl
	m.layers = 1 | HERO_LAYER
	parent.add_child(m)
	return m


## Point the paint rim light away from the scene's sun (once the scene is up).
func _find_sun() -> void:
	if not is_inside_tree():
		return
	for n: Node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		var sun: DirectionalLight3D = n
		if sun.visible:
			var to_sun: Vector3 = sun.global_transform.basis.z.normalized()
			for m: ShaderMaterial in _paint_mats:
				m.set_shader_parameter("sun_dir", to_sun)
			return


func _build() -> void:
	var v: Dictionary = VARIANTS[variant]
	var glow: Color = v["glow"]
	var accent_c: Color = v["accent"]
	_paint_mats.clear()
	_ring_mat = Mats.lamp(glow, 4.5)
	var screen := Mats.glass(Color(0.02, 0.03, 0.04, 1.0), 0.08)
	_mats = {
		"paint": _paint((v["paint"] as Color).darkened(0.04), 3.0, 0.9),
		"trim": _paint((v["trim"] as Color).darkened(0.45), 7.0, 0.9, 0.35, 0.4),
		"accent": _paint(accent_c, 11.0, 0.86),
		"dark": _paint(Color(0.17, 0.175, 0.19), 5.0, 0.75, 0.6, 0.38),
		"steel": Mats.metal("steel"),
		"glow": Mats.lamp(glow, 3.2),
		"lamp_accent": Mats.lamp(accent_c, 2.4),
		"screen": screen,
		"thruster": _ring_mat,
		"thruster_core": Mats.lamp(glow.lightened(0.4), 5.0),
	}
	_face_mat = ShaderMaterial.new()
	_face_mat.shader = preload("res://art/shaders/bot_face.gdshader")
	_face_mat.set_shader_parameter("eye_color", glow)
	_face_mat.set_shader_parameter("half_width", 0.29)
	_face_mat.set_shader_parameter("half_height", 0.17)
	_mats["face"] = _face_mat
	_root = Node3D.new()
	add_child(_root)
	_float = Node3D.new()
	_root.add_child(_float)

	# --- Body: rounded torso (white upper shell, dark lower section, orange side panels, chest
	# screen with orange lights, cyan collar strip) on a dark hover bowl with a thruster ring.
	_part(_float, "body")
	_part(_float, "thruster")
	var hover_light := OmniLight3D.new()
	hover_light.light_color = glow
	hover_light.light_energy = 1.6
	hover_light.omni_range = 1.5
	hover_light.position = Vector3(0, 0.02, 0)
	hover_light.shadow_enabled = false
	_float.add_child(hover_light)
	# His own soft key light (only lights his meshes) so he reads against the busy world.
	var key := OmniLight3D.new()
	key.light_color = Color(1.0, 0.93, 0.84)
	key.light_energy = 0.8
	key.omni_range = 2.2
	key.omni_attenuation = 1.2
	key.light_cull_mask = HERO_LAYER
	key.shadow_enabled = false
	key.light_specular = 0.4
	key.position = Vector3(0.4, 1.5, 0.9)  # above/behind: the side the game camera usually sees
	_float.add_child(key)
	var fill := key.duplicate() as OmniLight3D
	fill.light_energy = 0.45
	fill.position = Vector3(-0.5, 1.1, -1.0)  # soft front fill for the face and chest
	_float.add_child(fill)
	var icon: String = str(v.get("icon", "recycle"))
	var icon_l := Label3D.new()
	icon_l.text = "+" if icon == "plus" else ("❦" if icon == "leaf" else "♻")
	icon_l.font_size = 64
	icon_l.pixel_size = 0.0013
	icon_l.modulate = glow.lightened(0.3)
	icon_l.outline_size = 0
	icon_l.shaded = false
	icon_l.position = Vector3(0, 0.44, -0.182)
	_float.add_child(icon_l)
	_fill_bar = _mi(_float, ProcMesh.box(Vector3(0.14, 0.01, 0.006)), Mats.lamp(glow, 2.5), Vector3(0, 0.388, -0.182))
	_fill_bar.scale.x = 0.01
	# Back hatch where bales come out (hinged at its top edge).
	_hatch = Node3D.new()
	_hatch.position = _pivot("hatch")
	_float.add_child(_hatch)
	_part(_hatch, "hatch")

	# --- Arms with three-finger claws.
	_arm_l = _build_arm(-1.0)
	_arm_r = _build_arm(1.0)

	# --- Head: big rounded shell, glossy convex visor, ear discs with glow rings, crown vent,
	# curved antenna with an orange fin.
	_head = Node3D.new()
	_head.position = _pivot("head")
	_float.add_child(_head)
	_part(_head, "head")
	_part(_head, "visor", _pivot("visor") - _pivot("head"))
	call_deferred("_find_sun")
	# Variant extras.
	var trim: Material = _mats["trim"]
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
	# Tractor beam from the right claw: a cone that stretches to whatever is being picked up.
	_beam = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.025
	cone.bottom_radius = 0.085
	cone.height = 1.0
	cone.radial_segments = 20
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
	_beam.top_level = true
	add_child(_beam)
	_beam_core = MeshInstance3D.new()
	var core := CylinderMesh.new()
	core.top_radius = 0.008
	core.bottom_radius = 0.03
	core.height = 1.0
	core.radial_segments = 10
	core.cap_top = false
	core.cap_bottom = false
	_beam_core.mesh = core
	_beam_core.material_override = Mats.lamp(glow.lightened(0.4), 4.0)
	_beam_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam_core.top_level = true
	add_child(_beam_core)


func _build_arm(side: float) -> Node3D:
	var sfx: String = "_r" if side > 0.0 else "_l"
	var sp: Vector3 = _pivot("arm_shoulder" + sfx)
	var ep: Vector3 = _pivot("arm_elbow" + sfx)
	var wp: Vector3 = _pivot("arm_wrist" + sfx)
	var shoulder := Node3D.new()
	shoulder.position = sp
	_float.add_child(shoulder)
	_part(shoulder, "arm_shoulder" + sfx)
	var elbow := Node3D.new()
	elbow.position = ep - sp
	shoulder.add_child(elbow)
	_part(elbow, "arm_elbow" + sfx)
	var wrist := Node3D.new()
	wrist.position = wp - ep
	elbow.add_child(wrist)
	_part(wrist, "arm_wrist" + sfx)
	for k: int in 3:
		var a: float = TAU * k / 3.0 + PI * 0.5
		var f := Node3D.new()
		f.position = Vector3(cos(a) * 0.026, sin(a) * 0.026, -0.045)
		wrist.add_child(f)
		# The finger meshes point down -Z with their outer face on +Y; turn them to face outward.
		var orient := Node3D.new()
		orient.rotation.z = a - PI * 0.5
		f.add_child(orient)
		_part(orient, "finger")
		var tip := Node3D.new()
		tip.position = Vector3(0, 0.002, -0.058)
		tip.rotation.x = -0.45
		orient.add_child(tip)
		_part(tip, "finger_tip")
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


## Lock the claw's tractor beam onto a world position (null releases it).
func beam_at(world_pos: Variant) -> void:
	_beam_target = world_pos
	if world_pos != null:
		_scoop_t = maxf(_scoop_t, 0.2)


func claw_point() -> Vector3:
	var wrist: Node3D = _arm_r.get_meta("wrist")
	return wrist.to_global(Vector3(0, 0, -0.1))


func _update_beam(delta: float) -> void:
	_beam_amt = move_toward(_beam_amt, 1.0 if _beam_target != null else 0.0, delta * 8.0)
	var on: bool = _beam_amt > 0.02 and _beam_target != null
	_beam.visible = on
	_beam_core.visible = on
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
	var basis := Basis(x, -y * len, z)
	_beam.global_transform = Transform3D(basis, a + d * 0.5)
	_beam_core.global_transform = Transform3D(Basis(x * 0.8, -y * len, z * 0.8), a + d * 0.5)
	_beam_mat.albedo_color.a = _beam_amt * (0.2 + 0.06 * sin(_t * 40.0))
	_spark_t -= delta
	if _spark_t <= 0.0:
		_spark_t = 0.12
		Vfx.burst("sparkle", b, VARIANTS[variant]["glow"], 0.12)
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
