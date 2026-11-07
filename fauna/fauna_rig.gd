class_name FaunaRig
extends Node3D
## [fauna2] A skinned, animated animal (art/models/fauna/<id>.glb, built in Blender by
## art/models/fauna/build_<id>.py) for the animals that are seen up close: soft fur shading with
## fur shells near the camera (art/shaders/fauna_fur.gdshader), glossy eyes with catchlights
## that close when asleep (fauna_eye.gdshader), per-animal coats, blended actions and a head
## that turns to look (bone override after the animation). Fauna keeps the state machine; this
## only shows it. Far or numerous animals stay on the MultiMesh path.

const DIR: String = "res://art/models/fauna/%s.glb"
const SHELLS: int = 6
const SHELL_RANGE: float = 9.0
## Target overall height (metres, rest pose incl. ears/antlers) for vendor models; 0 = as built.
const HEIGHT: Dictionary = {"cat": 0.0, "deer": 1.22, "stag": 1.55, "fox": 0.5, "fennec": 0.36, "arctic_fox": 0.42}

## Cat coats (index = Animal.coat): ginger tabby, black tuxedo, grey tabby, brown tabby,
## cream, calico.
const CAT_COATS: Array[Dictionary] = [
	{"base": Color(0.9, 0.55, 0.25), "stripe": Color(0.6, 0.29, 0.1), "stripe_amt": 1.0, "white_amt": 0.45, "iris": Color(0.78, 0.62, 0.15)},
	{"base": Color(0.07, 0.065, 0.07), "stripe": Color(0.05, 0.05, 0.05), "stripe_amt": 0.0, "white_amt": 0.75, "iris": Color(0.6, 0.72, 0.18)},
	{"base": Color(0.55, 0.56, 0.58), "stripe": Color(0.24, 0.24, 0.26), "stripe_amt": 1.0, "white_amt": 0.35, "iris": Color(0.45, 0.68, 0.3)},
	{"base": Color(0.55, 0.43, 0.3), "stripe": Color(0.18, 0.13, 0.09), "stripe_amt": 1.0, "white_amt": 0.2, "iris": Color(0.72, 0.58, 0.2)},
	{"base": Color(0.95, 0.88, 0.76), "stripe": Color(0.86, 0.68, 0.5), "stripe_amt": 0.6, "white_amt": 0.6, "iris": Color(0.35, 0.6, 0.85)},
	{"base": Color(0.92, 0.6, 0.3), "stripe": Color(0.75, 0.42, 0.18), "stripe_amt": 0.2, "white_amt": 0.8, "iris": Color(0.75, 0.6, 0.2), "patch": Color(0.1, 0.08, 0.07), "patch_amt": 1.0},
]

static var _scenes: Dictionary = {}
static var _mats: Dictionary = {}

var id: String = ""
var anim: AnimationPlayer
var skel: Skeleton3D
var meshes: Array[MeshInstance3D] = []
var shells: Array[MeshInstance3D] = []
var _cur: String = ""
var _head: int = -1
var _own: Array[ShaderMaterial] = []  # this animal's own fur / eye / shell materials (coat, eyes)
var _look := Vector2.ZERO  # yaw, pitch (radians; pitch > 0 looks down)


static func available(p_id: String) -> bool:
	return ResourceLoader.exists(DIR % p_id)


static func make(p_id: String) -> FaunaRig:
	if not available(p_id):
		return null
	if not _scenes.has(p_id):
		_scenes[p_id] = load(DIR % p_id)
	var r := FaunaRig.new()
	r.id = p_id
	r.name = "Rig_" + p_id
	var inst: Node3D = (_scenes[p_id] as PackedScene).instantiate() as Node3D
	r.add_child(inst)
	r._wire(inst)
	r._fit(inst, float(HEIGHT.get(p_id, 0.0)))
	return r


## Scales a vendor model to its real size and turns it to face -Z (head forward).
func _fit(inst: Node3D, height: float) -> void:
	if height <= 0.0 or meshes.is_empty():
		return
	var bb := AABB()
	var first: bool = true
	for mi: MeshInstance3D in meshes:
		var b: AABB = _rel(mi, inst) * mi.mesh.get_aabb()
		bb = b if first else bb.merge(b)
		first = false
	var k: float = height / maxf(bb.size.y, 0.001)
	inst.scale = Vector3.ONE * k
	if skel and _head >= 0:
		var hp: Vector3 = _rel(skel, inst) * skel.get_bone_global_rest(_head).origin
		if hp.z > 0.0:
			inst.rotation.y = PI


func _wire(root: Node) -> void:
	for n: Node in root.find_children("*", "AnimationPlayer", true, false):
		anim = n as AnimationPlayer
	for n: Node in root.find_children("*", "Skeleton3D", true, false):
		skel = n as Skeleton3D
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		meshes.append(n as MeshInstance3D)
	if skel:
		_head = skel.find_bone("head")
		if _head < 0:
			_head = skel.find_bone("Head")
	if anim:
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for an: StringName in anim.get_animation_list():
			var a: Animation = anim.get_animation(an)
			a.loop_mode = Animation.LOOP_NONE if str(an) in ["Stretch"] else Animation.LOOP_LINEAR
	for mi: MeshInstance3D in meshes.duplicate():
		for s: int in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(s)
			var nm: String = m.resource_name if m else ""
			var mat: Material = _material(nm)
			if mat is ShaderMaterial:
				mat = (mat as ShaderMaterial).duplicate()
				_own.append(mat)
			mi.set_surface_override_material(s, mat)
		# Fur shells: a second instance of the skinned mesh with only the fur surfaces, seen near.
		var fur_s: int = -1
		var baked: bool = false
		for s2: int in mi.mesh.get_surface_count():
			var m2: Material = mi.mesh.surface_get_material(s2)
			if m2 and m2.resource_name in ["Fur", "FurBaked"]:
				fur_s = s2
				baked = m2.resource_name == "FurBaked"
		if fur_s >= 0:
			var sh := MeshInstance3D.new()
			sh.mesh = mi.mesh
			sh.skin = mi.skin
			sh.name = "FurShells"
			mi.get_parent().add_child(sh)
			sh.skeleton = sh.get_path_to(skel) if skel else NodePath()
			sh.transform = mi.transform
			sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			sh.visibility_range_end = SHELL_RANGE
			for s3: int in mi.mesh.get_surface_count():
				if s3 == fur_s:
					var chain: ShaderMaterial = _shell_chain(baked).duplicate(true)
					var c2: Material = chain
					while c2 is ShaderMaterial:
						_own.append(c2)
						c2 = c2.next_pass
					sh.set_surface_override_material(s3, chain)
				else:
					sh.set_surface_override_material(s3, _invisible())
			shells.append(sh)


## n's transform relative to its ancestor root (works outside the tree).
static func _rel(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != root:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t


static func _material(nm: String) -> Material:
	if _mats.has(nm):
		return _mats[nm]
	var m: Material
	match nm:
		"Fur", "FurBaked":
			var f := ShaderMaterial.new()
			f.shader = preload("res://art/shaders/fauna_fur.gdshader")
			f.set_shader_parameter("baked", nm == "FurBaked")
			m = f
		"Gloss":
			var g := StandardMaterial3D.new()
			g.vertex_color_use_as_albedo = true
			g.roughness = 0.06
			g.clearcoat_enabled = true
			m = g
		"Eye":
			var e := ShaderMaterial.new()
			e.shader = preload("res://art/shaders/fauna_eye.gdshader")
			m = e
		"Whisker":
			var w := StandardMaterial3D.new()
			w.albedo_color = Color(0.97, 0.96, 0.93)
			w.roughness = 0.4
			m = w
		"Skin":
			var k := StandardMaterial3D.new()
			k.albedo_color = Color(0.93, 0.68, 0.66)
			k.roughness = 0.6
			k.backlight_enabled = true
			k.backlight = Color(0.6, 0.3, 0.3)
			m = k
		_:
			var n := StandardMaterial3D.new()
			n.albedo_color = Color(0.83, 0.5, 0.5) if nm == "Nose" else Color(0.5, 0.5, 0.5)
			n.roughness = 0.35
			m = n
	_mats[nm] = m
	return m


static func _shell_chain(baked: bool = false) -> Material:
	var key: String = "_shells_b" if baked else "_shells"
	if _mats.has(key):
		return _mats[key]
	var first: ShaderMaterial = null
	var prev: ShaderMaterial = null
	for k: int in SHELLS:
		var s := ShaderMaterial.new()
		s.shader = preload("res://art/shaders/fauna_fur.gdshader")
		s.set_shader_parameter("shell", float(k + 1) / SHELLS)
		s.set_shader_parameter("baked", baked)
		if baked:
			s.set_shader_parameter("fur_len", 0.012)  # big animals: the shells are scaled down with the model
		s.render_priority = k
		if prev:
			prev.next_pass = s
		else:
			first = s
		prev = s
	_mats[key] = first
	return first


static func _invisible() -> Material:
	if not _mats.has("_none"):
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0, 0, 0, 0)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mats["_none"] = m
	return _mats["_none"]


## Per-animal coat (keys: base, stripe, stripe_amt, white_amt, patch, patch_amt, iris, pupil_w).
func set_coat(c: Dictionary) -> void:
	var vals: Dictionary = {"coat_base": c.get("base", Color(0.86, 0.52, 0.24)), "coat_stripe": c.get("stripe", Color(0.5, 0.25, 0.1)),
		"coat_patch": c.get("patch", Color(0.1, 0.1, 0.1)), "stripe_amt": float(c.get("stripe_amt", 1.0)), "white_amt": float(c.get("white_amt", 0.5)),
		"patch_amt": float(c.get("patch_amt", 0.0)), "iris": c.get("iris", Color(0.7, 0.65, 0.2)), "pupil_w": float(c.get("pupil_w", 0.62))}
	for m: ShaderMaterial in _own:
		for k: String in vals:
			m.set_shader_parameter(k, vals[k])


var _closed: float = -1.0


func set_eyes_closed(v: float) -> void:
	_want_closed = v


func _apply_closed(v: float) -> void:
	if v == _closed:
		return
	_closed = v
	for m: ShaderMaterial in _own:
		m.set_shader_parameter("eye_closed", v)


## Plays (blends to) an action; speed scales playback.
func play(action: String, speed: float = 1.0, blend: float = 0.3) -> void:
	if anim == null or not anim.has_animation(action):
		return
	if action != _cur:
		_cur = action
		anim.play(action, blend)
	anim.speed_scale = speed


func current() -> String:
	return _cur


func look(yaw: float, pitch: float) -> void:
	_look = Vector2(yaw, pitch)


## Advances the animation, then turns the head (in model space, about its own pivot).
var _blink_t: float = randf_range(1.0, 4.0)
var _want_closed: float = 0.0


func advance(dt: float) -> void:
	if anim:
		anim.advance(dt)
	# Blink now and then (the eye shader draws the closed lid for a few frames).
	_blink_t -= dt
	var blink: float = 1.0 if _blink_t < 0.0 else 0.0
	if _blink_t < -0.13:
		_blink_t = randf_range(2.5, 6.0)
	_apply_closed(maxf(_want_closed, blink))
	if skel and _head >= 0 and (absf(_look.x) > 0.01 or absf(_look.y) > 0.01):
		var par: int = skel.get_bone_parent(_head)
		var g: Transform3D = skel.get_bone_global_pose(_head)
		var pg: Transform3D = skel.get_bone_global_pose(par) if par >= 0 else Transform3D.IDENTITY
		var rot := Basis(Vector3.UP, clampf(_look.x, -1.1, 1.1)) * Basis(Vector3.RIGHT, -clampf(_look.y, -0.6, 0.8))
		var local: Basis = pg.basis.inverse() * (rot * g.basis)
		skel.set_bone_pose_rotation(_head, local.get_rotation_quaternion())
