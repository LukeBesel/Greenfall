class_name PhotoPoser
extends Node
## [photo] Procedural poses and eye expressions for Lumi (PatchModel) in photo mode.
## The hero model is node-based (float > shoulder > elbow > wrist > three fingers, head, hover
## ring, face shader), so a pose is a set of joint angles that this node writes after the model's
## own _process every frame (process_priority 100). Poses blend smoothly and keep animating while
## the world is paused. restore() puts every touched node back exactly as it was.
##
## Joint conventions (Euler YXZ, model faces -Z, right arm is +X):
##   shoulder.x > 0 swings the arm forward/up (at rest the upper arm hangs, the forearm points
##   forward); shoulder.z > 0 lifts the right arm out sideways (mirrored on the left);
##   elbow.x = -PI/2 straightens the arm; elbow.y sways a raised forearm side to side.
##   Finger curl > 0 pinches the claw shut, < 0 spreads it.

const POSES: Array = [
	["idle", "Hover"], ["wave", "Wave"], ["thumbs", "Thumbs up"], ["peace", "Peace sign"],
	["scan", "Laser scan"], ["sprout", "Holding a sprout"], ["sit", "Sitting on a cube"],
	["holo", "Hologram map"], ["cheer", "Happy ^ ^"], ["sleepy", "Low battery"],
	["hero", "Heroic hover"], ["selfie", "Selfie"], ["curious", "Curious tilt"],
]
const EYES: Array = [
	["auto", "Pose default"], ["bright", "Bright"], ["happy", "Happy ^ ^"], ["wink", "Wink"],
	["sleepy", "Sleepy"], ["wide", "Wide awake"], ["closed", "Closed"],
	["left", "Look left"], ["right", "Look right"], ["up", "Look up"],
]
const STRAIGHT: float = -PI * 0.5

var model: PatchModel
var pose: String = "idle"
var eyes: String = "auto"
## World position of the photo camera (selfie aims at it; null = straight ahead).
var camera_pos: Variant = null

var _t: float = 0.0
var _cur: Dictionary = {}
var _snap: Dictionary = {}
var _props: Node3D
var _prop_pose: String = ""
var _beams: Array[MeshInstance3D] = []
var _holo: Node3D
var _sprout: Node3D
var _battery: Sprite3D
var _active: bool = false


func _init() -> void:
	process_priority = 100
	process_mode = Node.PROCESS_MODE_ALWAYS


static func pose_ids() -> Array[String]:
	var out: Array[String] = []
	for p: Array in POSES:
		out.append(str(p[0]))
	return out


static func pose_names() -> Array[String]:
	var out: Array[String] = []
	for p: Array in POSES:
		out.append(str(p[1]))
	return out


static func eye_names() -> Array[String]:
	var out: Array[String] = []
	for e: Array in EYES:
		out.append(str(e[1]))
	return out


## Start driving `m`: snapshot every node the poses touch, so restore() is exact.
func attach(m: PatchModel) -> void:
	model = m
	_snap.clear()
	_snap["proc"] = m.process_mode
	_snap["model_xf"] = m.transform
	for n: Node3D in _nodes():
		_snap[n] = n.transform
	_snap["sleeping"] = m.sleeping
	_snap["holding"] = m.holding
	m.process_mode = Node.PROCESS_MODE_ALWAYS
	m.holding = false
	_cur = _read_current()
	_props = Node3D.new()
	_props.name = "PhotoProps"
	m.add_child(_props)
	_active = true


## Undo everything: joints, model transform/process mode, face, props.
func restore() -> void:
	if model == null or not is_instance_valid(model):
		_active = false
		return
	for n: Variant in _snap:
		if n is Node3D and is_instance_valid(n):
			(n as Node3D).transform = _snap[n]
	model.transform = _snap.get("model_xf", model.transform)
	model.process_mode = _snap.get("proc", Node.PROCESS_MODE_INHERIT)
	model.sleeping = _snap.get("sleeping", false)
	model.holding = _snap.get("holding", false)
	if model._face_mat:
		model._face_mat.set_shader_parameter("wink", 0.0)
		model._face_mat.set_shader_parameter("eye_color", PatchModel.VARIANTS[model.variant]["glow"])
	if _props and is_instance_valid(_props):
		_props.queue_free()
	_props = null
	_beams.clear()
	_holo = null
	_sprout = null
	_battery = null
	_prop_pose = ""
	_active = false


func _nodes() -> Array[Node3D]:
	var out: Array[Node3D] = [model._root, model._float, model._head]
	for arm: Node3D in [model._arm_l, model._arm_r]:
		out.append(arm)
		out.append(arm.get_meta("elbow"))
		out.append(arm.get_meta("wrist"))
	for f: Node3D in model._claws:
		out.append(f)
	return out


func _read_current() -> Dictionary:
	var el_r: Node3D = model._arm_r.get_meta("elbow")
	var el_l: Node3D = model._arm_l.get_meta("elbow")
	return {
		"float_y": model._float.position.y, "lean": Vector2(model._float.rotation.x, model._float.rotation.z),
		"head": model._head.rotation, "sh_r": model._arm_r.rotation, "sh_l": model._arm_l.rotation,
		"el_r": el_r.rotation, "el_l": el_l.rotation, "wr_r": Vector3.ZERO, "wr_l": Vector3.ZERO,
		"claw_r": Vector3(0.2, 0.2, 0.2), "claw_l": Vector3(0.2, 0.2, 0.2), "ring": 3.5,
		"happy": 0.0, "blink": 0.0, "energy": 4.0, "look": Vector2.ZERO, "wink": 0.0, "dim": 0.0,
	}


## Target joint values for a pose at time t (seconds). Pure: used by tests too.
func target(p: String, t: float) -> Dictionary:
	var bob: float = sin(t * 2.4) * 0.02
	var d: Dictionary = {
		"float_y": 0.04 + bob, "lean": Vector2.ZERO, "head": Vector3(0, 0, sin(t * 0.7) * 0.03),
		"sh_r": Vector3(0.15 * sin(t * 1.3), 0, 0), "sh_l": Vector3(0.15 * sin(t * 1.3 + 1.0), 0, 0),
		"el_r": Vector3.ZERO, "el_l": Vector3.ZERO, "wr_r": Vector3.ZERO, "wr_l": Vector3.ZERO,
		"claw_r": Vector3(0.2, 0.2, 0.2), "claw_l": Vector3(0.2, 0.2, 0.2), "ring": 3.5 + sin(t * 9.0) * 0.4,
		"happy": 0.0, "blink": 0.0, "energy": 4.0, "look": Vector2.ZERO, "wink": 0.0, "dim": 0.0,
	}
	match p:
		"wave":
			d["sh_r"] = Vector3(1.45, 0.35, 1.3)
			d["el_r"] = Vector3(0.42 * sin(t * 7.5), 0, 0)
			d["claw_r"] = Vector3(-0.5, -0.5, -0.5)
			d["sh_l"] = Vector3(0.1, 0, -0.08)
			d["head"] = Vector3(0.06, -0.12, 0.14)
			d["happy"] = 1.0
			d["lean"] = Vector2(0.03, -0.04)
		"thumbs":
			d["sh_r"] = Vector3(0.6, 0.45, 0.3)
			d["el_r"] = Vector3(-0.4, 0, 0)
			d["claw_r"] = Vector3(-2.6, 1.7, 1.7)  # top finger up, the other two make a fist
			d["sh_l"] = Vector3(0.05, 0, -0.1)
			d["head"] = Vector3(0.04, 0.08, -0.12)
			d["wink"] = 1.0
			d["look"] = Vector2(0.2, 0.1)
		"peace":
			d["sh_r"] = Vector3(1.5, 0.55, 1.15)
			d["el_r"] = Vector3(0.15, 0, 0)
			d["wr_r"] = Vector3(0, 0, PI * 0.5)
			d["claw_r"] = Vector3(1.7, -1.1, -1.1)  # two fingers spread into a V
			d["sh_l"] = Vector3(0.1, 0, -0.08)
			d["head"] = Vector3(0.05, -0.1, 0.2)
			d["happy"] = 1.0
			d["lean"] = Vector2(0.0, -0.05)
		"scan":
			var sweep: float = sin(t * 1.4)
			d["sh_r"] = Vector3(0.3, sweep * 0.25 + 0.12, 0.05)
			d["sh_l"] = Vector3(0.3, sweep * 0.25 - 0.12, -0.05)
			d["el_r"] = Vector3(-0.38, 0, 0)
			d["el_l"] = Vector3(-0.38, 0, 0)
			d["claw_r"] = Vector3(-0.6, -0.6, -0.6)
			d["claw_l"] = Vector3(-0.6, -0.6, -0.6)
			d["head"] = Vector3(-0.16, sweep * 0.3, 0)
			d["look"] = Vector2(-sweep * 0.5, -0.35)
			d["energy"] = 5.5
			d["blink"] = 0.18
			d["lean"] = Vector2(-0.06, 0)
		"sprout":
			d["sh_r"] = Vector3(0.7, 0.3, -0.25)
			d["sh_l"] = Vector3(0.7, -0.3, 0.25)
			d["el_r"] = Vector3(-0.2, 0, 0)
			d["el_l"] = Vector3(-0.2, 0, 0)
			d["claw_r"] = Vector3(-0.35, -0.35, -0.35)
			d["claw_l"] = Vector3(-0.35, -0.35, -0.35)
			d["head"] = Vector3(-0.2, 0, 0.1 + sin(t * 0.9) * 0.03)
			d["happy"] = 1.0
			d["lean"] = Vector2(-0.04, 0)
		"sit":
			d["float_y"] = 0.53 + sin(t * 1.2) * 0.004
			d["lean"] = Vector2(0.07, 0)
			d["sh_r"] = Vector3(-0.2, 0, 0.5)
			d["sh_l"] = Vector3(-0.2, 0, -0.5)
			d["el_r"] = Vector3(-1.3, 0, 0)
			d["el_l"] = Vector3(-1.3, 0, 0)
			d["claw_r"] = Vector3(-0.2, -0.2, -0.2)
			d["claw_l"] = Vector3(-0.2, -0.2, -0.2)
			d["head"] = Vector3(0.1, 0.1, 0.13 + sin(t * 0.6) * 0.03)
			d["blink"] = 0.25
			d["ring"] = 1.0
		"holo":
			d["sh_r"] = Vector3(0.9, 0.5, 0.9)
			d["el_r"] = Vector3(0.2, 0, 0)
			d["wr_r"] = Vector3(0, 0, 0)
			d["claw_r"] = Vector3(-0.9, -0.9, -0.9)
			d["sh_l"] = Vector3(0.1, 0, -0.08)
			d["head"] = Vector3(0.12, -0.32, 0.05)
			d["look"] = Vector2(0.5, 0.45)
			d["energy"] = 5.0
		"cheer":
			var hop: float = absf(sin(t * 4.5))
			d["float_y"] = 0.08 + hop * 0.06
			d["sh_r"] = Vector3(1.5, 0.2, 1.25 + hop * 0.12)
			d["sh_l"] = Vector3(1.5, -0.2, -1.25 - hop * 0.12)
			d["el_r"] = Vector3(0.2 + 0.15 * sin(t * 9.0), 0, 0)
			d["el_l"] = Vector3(0.2 - 0.15 * sin(t * 9.0), 0, 0)
			d["claw_r"] = Vector3(-0.8, -0.8, -0.8)
			d["claw_l"] = Vector3(-0.8, -0.8, -0.8)
			d["head"] = Vector3(0.16, 0, sin(t * 4.5) * 0.06)
			d["happy"] = 1.0
			d["energy"] = 5.0
			d["ring"] = 5.0 + hop * 2.0
		"sleepy":
			d["float_y"] = 0.0 + sin(t * 0.8) * 0.006
			d["lean"] = Vector2(-0.07, 0.04)
			d["sh_r"] = Vector3(0.0, 0, 0.1)
			d["sh_l"] = Vector3(0.0, 0, -0.1)
			d["el_r"] = Vector3(-1.35, 0, 0)
			d["el_l"] = Vector3(-1.35, 0, 0)
			d["claw_r"] = Vector3(0.5, 0.5, 0.5)
			d["claw_l"] = Vector3(0.5, 0.5, 0.5)
			d["head"] = Vector3(-0.3, 0.05, 0.14 + sin(t * 0.8) * 0.02)
			d["blink"] = 0.74
			d["energy"] = 1.1
			d["look"] = Vector2(0, -0.4)
			d["ring"] = 0.8 + absf(sin(t * 1.5)) * 0.4
			d["dim"] = 1.0
		"hero":
			d["float_y"] = 0.32 + sin(t * 1.6) * 0.015
			d["lean"] = Vector2(0.1, -0.03)
			d["sh_r"] = Vector3(0.0, 0.35, 2.5)
			d["el_r"] = Vector3(STRAIGHT, 0, 0)
			d["claw_r"] = Vector3(1.5, 1.5, 1.5)
			d["sh_l"] = Vector3(-0.55, 0, -0.32)
			d["el_l"] = Vector3(-0.85, 0, 0)
			d["claw_l"] = Vector3(0.8, 0.8, 0.8)
			d["head"] = Vector3(0.16, -0.05, 0)
			d["energy"] = 6.0
			d["blink"] = 0.15
			d["ring"] = 7.5 + sin(t * 11.0) * 0.6
		"selfie":
			var aim: Vector3 = _selfie_angles()
			d["sh_r"] = aim
			d["el_r"] = Vector3(STRAIGHT + 0.25, 0, 0)
			d["claw_r"] = Vector3(-0.4, -0.4, -0.4)
			d["sh_l"] = Vector3(1.5, -0.55, -1.15)
			d["el_l"] = Vector3(0.15, 0, 0)
			d["wr_l"] = Vector3(0, 0, -PI * 0.5)
			d["claw_l"] = Vector3(1.7, -1.1, -1.1)
			d["head"] = Vector3(0.1, clampf(aim.y * 0.35, -0.3, 0.3), 0.18)
			d["happy"] = 1.0
			d["lean"] = Vector2(0.04, 0.05)
		"curious":
			d["sh_l"] = Vector3(0.9, -0.45, 0.25)
			d["el_l"] = Vector3(0.45, 0, 0)
			d["claw_l"] = Vector3(0.9, 0.9, 0.9)
			d["sh_r"] = Vector3(0.05, 0, 0.12)
			d["head"] = Vector3(0.08, 0.15, -0.3 + sin(t * 0.8) * 0.03)
			d["look"] = Vector2(-0.35, 0.5)
	return d


## Shoulder angles that point a straight right arm up toward the camera.
func _selfie_angles() -> Vector3:
	var fallback := Vector3(2.0, 0.25, 0.1)
	if camera_pos == null or model == null or not model.is_inside_tree():
		return fallback
	var sh: Node3D = model._arm_r
	var local: Vector3 = model._float.global_transform.affine_inverse() * (camera_pos as Vector3)
	var dir: Vector3 = local - sh.position
	dir.y += dir.length() * 0.45  # held up high, the classic selfie angle
	dir = dir.normalized()
	# A straight arm points along R * (0,-1,0); with z = 0: dir = (-sinX sinY, -cosX, -sinX cosY).
	var ax: float = acos(clampf(-dir.y, -1.0, 1.0))
	var ay: float = atan2(-dir.x, -dir.z)
	return Vector3(clampf(ax, 1.2, 2.6), clampf(ay, -1.1, 0.45), 0.1)


## Eye overrides; empty = keep the pose's face.
static func eye_values(id: String) -> Dictionary:
	match id:
		"bright":
			return {"happy": 0.0, "blink": 0.0, "wink": 0.0, "energy": 4.5, "look": Vector2.ZERO}
		"happy":
			return {"happy": 1.0, "blink": 0.0, "wink": 0.0, "energy": 4.5}
		"wink":
			return {"happy": 0.0, "blink": 0.0, "wink": 1.0, "energy": 4.5}
		"sleepy":
			return {"happy": 0.0, "blink": 0.74, "wink": 0.0, "energy": 1.4}
		"wide":
			return {"happy": 0.0, "blink": 0.0, "wink": 0.0, "energy": 6.5}
		"closed":
			return {"happy": 0.0, "blink": 1.0, "wink": 0.0, "energy": 2.0}
		"left":
			return {"happy": 0.0, "blink": 0.0, "wink": 0.0, "look": Vector2(-0.9, 0.0)}
		"right":
			return {"happy": 0.0, "blink": 0.0, "wink": 0.0, "look": Vector2(0.9, 0.0)}
		"up":
			return {"happy": 0.0, "blink": 0.0, "wink": 0.0, "look": Vector2(0.0, 0.9)}
	return {}


func _process(delta: float) -> void:
	if not _active or model == null or not is_instance_valid(model):
		return
	_t += delta
	var tgt: Dictionary = target(pose, _t)
	var ev: Dictionary = eye_values(eyes)
	for k: String in ev:
		tgt[k] = ev[k]
	var k: float = 1.0 - exp(-delta * 7.0)
	for key: String in tgt:
		var a: Variant = _cur.get(key, tgt[key])
		var b: Variant = tgt[key]
		if b is float:
			_cur[key] = lerpf(float(a), float(b), k)
		else:
			_cur[key] = a.lerp(b, k)
	_apply_pose()
	_update_props(delta)


func _apply_pose() -> void:
	var m: PatchModel = model
	m._root.position = Vector3.ZERO
	m._root.scale = Vector3.ONE
	m._float.position.y = _cur["float_y"]
	var lean: Vector2 = _cur["lean"]
	m._float.rotation = Vector3(lean.x, 0, lean.y)
	m._head.rotation = _cur["head"]
	m._arm_r.rotation = _cur["sh_r"]
	m._arm_l.rotation = _cur["sh_l"]
	(m._arm_r.get_meta("elbow") as Node3D).rotation = _cur["el_r"]
	(m._arm_l.get_meta("elbow") as Node3D).rotation = _cur["el_l"]
	(m._arm_r.get_meta("wrist") as Node3D).rotation = _cur["wr_r"]
	(m._arm_l.get_meta("wrist") as Node3D).rotation = _cur["wr_l"]
	# Claws: the model builds the left arm's three fingers first, then the right arm's.
	for i: int in m._claws.size():
		var f: Node3D = m._claws[i]
		var curl: Vector3 = _cur["claw_l"] if i < 3 else _cur["claw_r"]
		var dir: Vector2 = f.get_meta("dir")
		f.rotation = Vector3(-dir.y, dir.x, 0) * curl[i % 3] * 0.6
	m._ring_mat.emission_energy_multiplier = _cur["ring"]
	var face: ShaderMaterial = m._face_mat
	face.set_shader_parameter("happy", _cur["happy"])
	face.set_shader_parameter("blink", _cur["blink"])
	face.set_shader_parameter("wink", _cur["wink"])
	face.set_shader_parameter("look", _cur["look"])
	face.set_shader_parameter("energy", _cur["energy"])
	var glow: Color = PatchModel.VARIANTS[m.variant]["glow"]
	face.set_shader_parameter("eye_color", glow.lerp(Color(1.0, 0.45, 0.3), float(_cur["dim"]) * 0.55))


# --- Props ----------------------------------------------------------------------------------

func _update_props(_delta: float) -> void:
	if _prop_pose != pose:
		_prop_pose = pose
		for c: Node in _props.get_children():
			c.queue_free()
		_beams.clear()
		_holo = null
		_sprout = null
		_battery = null
		match pose:
			"scan":
				for i: int in 2:
					_beams.append(_beam_mesh())
			"sprout":
				_sprout = _make_sprout()
			"sit":
				_props.add_child(_make_cube())
			"holo":
				_holo = _make_holo()
			"sleepy":
				_battery = _make_battery()
	var glow: Color = PatchModel.VARIANTS[model.variant]["glow"]
	if not _beams.is_empty():
		var sweep: float = sin(_t * 1.4)
		var fwd: Vector3 = -model.global_transform.basis.z
		var side: Vector3 = model.global_transform.basis.x
		var hit: Vector3 = model.global_position + fwd * 1.7 + side * (sweep * 0.55)
		hit.y = model.global_position.y + 0.01
		var spread: Vector3 = side * 0.12
		_place_beam(_beams[0], model.claw_point(), hit + spread)
		_place_beam(_beams[1], model.claw_point_l(), hit - spread)
	if _sprout:
		var mid: Vector3 = (model.claw_point() + model.claw_point_l()) * 0.5
		_sprout.global_position = mid + Vector3(0, 0.035, 0)
		_sprout.rotation.y = sin(_t * 0.7) * 0.15
	if _holo:
		_holo.global_position = model.hand_point() + Vector3(0, 0.2, 0)
		_holo.rotate_y(0.004)
		(_holo.get_child(0) as Node3D).rotation.y = _t * 0.35
	if _battery:
		_battery.global_position = model._head.to_global(Vector3(0.0, 0.62, -0.05))
		_battery.modulate.a = 0.55 + 0.45 * absf(sin(_t * 2.2))
	if _beams.size() > 0:
		for b: MeshInstance3D in _beams:
			(b.material_override as StandardMaterial3D).emission = glow


func _beam_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.0045
	c.bottom_radius = 0.0045
	c.height = 1.0
	c.radial_segments = 6
	c.rings = 1
	mi.mesh = c
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.7, 0.95, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.88, 1.0)
	mat.emission_energy_multiplier = 3.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	_props.add_child(mi)
	# A small scan dot where the laser lands.
	var dot := MeshInstance3D.new()
	dot.mesh = ProcMesh.sphere(0.018, 8, 4)
	dot.material_override = mat
	dot.position = Vector3(0, -0.5, 0)
	dot.scale = Vector3(1.0, 1.0, 1.0)
	mi.add_child(dot)
	return mi


func _place_beam(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d: Vector3 = b - a
	var len: float = maxf(d.length(), 0.05)
	var y: Vector3 = d / len
	var x: Vector3 = y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z: Vector3 = x.cross(y)
	mi.global_transform = Transform3D(Basis(x, -y * len, z), a + d * 0.5)
	# Keep the end dot round despite the stretched beam.
	(mi.get_child(0) as Node3D).scale = Vector3(1.0, 1.0 / len, 1.0)


func _make_sprout() -> Node3D:
	var root := Node3D.new()
	_props.add_child(root)
	var pot := StandardMaterial3D.new()
	pot.albedo_color = Color(0.62, 0.36, 0.24)
	pot.roughness = 0.8
	var soil := StandardMaterial3D.new()
	soil.albedo_color = Color(0.16, 0.11, 0.08)
	soil.roughness = 1.0
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color(0.36, 0.72, 0.26)
	leaf.roughness = 0.5
	leaf.emission_enabled = true
	leaf.emission = Color(0.3, 0.8, 0.25)
	leaf.emission_energy_multiplier = 0.25
	_prop_mi(root, ProcMesh.cyl(0.05, 0.038, 0.07, 14), pot, Vector3(0, 0.035, 0))
	_prop_mi(root, ProcMesh.cyl(0.046, 0.046, 0.008, 14), soil, Vector3(0, 0.066, 0))
	_prop_mi(root, ProcMesh.cyl(0.004, 0.005, 0.09, 6), leaf, Vector3(0, 0.11, 0))
	_prop_mi(root, ProcMesh.sphere(0.035, 10, 5), leaf, Vector3(0.03, 0.15, 0), Vector3(0, 0, -32), Vector3(1.4, 0.22, 0.8))
	_prop_mi(root, ProcMesh.sphere(0.03, 10, 5), leaf, Vector3(-0.027, 0.135, 0.005), Vector3(0, 20, 30), Vector3(1.4, 0.22, 0.8))
	_prop_mi(root, ProcMesh.sphere(0.018, 8, 4), leaf, Vector3(0.0, 0.16, -0.01), Vector3(-20, 0, 0), Vector3(0.8, 0.3, 1.3))
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.6, 1.0, 0.55)
	glow.light_energy = 0.35
	glow.omni_range = 0.6
	glow.position = Vector3(0, 0.15, 0)
	root.add_child(glow)
	return root


func _make_cube() -> Node3D:
	var c := JunkCube.create(BigNum.zero(), {"fill": 1.0, "colors": [Color(0.5, 0.47, 0.43), Color(0.42, 0.3, 0.22), Color(0.32, 0.45, 0.52)]})
	c.freeze = true
	c.position = Vector3(0, 0.3, 0.04)
	c.rotation_degrees = Vector3(0, 8, 0)
	c.ready.connect(func() -> void:
		c.remove_from_group("junk_cube")  # a prop: never sold, carried or saved
		c.collision_layer = 0
		c.collision_mask = 0
		c.process_mode = Node.PROCESS_MODE_DISABLED)
	return c


func _make_holo() -> Node3D:
	var root := Node3D.new()
	_props.add_child(root)
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec4 col : source_color = vec4(0.3, 0.88, 1.0, 1.0);
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	vec3 n = normalize(lp);
	float lat = asin(clamp(n.y, -1.0, 1.0));
	float lon = atan(n.z, n.x);
	float grid = (1.0 - smoothstep(0.0, 0.06, abs(fract(lat * 6.0 / 3.14159 + 0.5) - 0.5)))
		+ (1.0 - smoothstep(0.0, 0.05, abs(fract(lon * 8.0 / 6.28318 + 0.5) - 0.5)));
	float land = smoothstep(0.15, 0.4, sin(lon * 3.0 + 1.0) * cos(lat * 4.0) + sin(lon * 5.0 - lat * 2.0) * 0.5);
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	float scan = 0.6 + 0.4 * sin(lp.y * 160.0 - TIME * 3.0);
	float a = (grid * 0.35 + land * 0.4 + fres * 0.6) * scan;
	ALBEDO = col.rgb;
	EMISSION = col.rgb * a * 1.4;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("col", PatchModel.VARIANTS[model.variant]["glow"])
	var globe := MeshInstance3D.new()
	globe.mesh = ProcMesh.sphere(0.12, 32, 16)
	globe.material_override = mat
	globe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(globe)
	# A soft projection cone from the claw up to the globe.
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.1
	cm.bottom_radius = 0.01
	cm.height = 0.16
	cm.cap_top = false
	cm.cap_bottom = false
	cone.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	cmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cmat.albedo_color = Color(0.3, 0.85, 1.0, 0.18)
	cone.material_override = cmat
	cone.position = Vector3(0, -0.15, 0)
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(cone)
	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 0.85, 1.0)
	light.light_energy = 0.6
	light.omni_range = 1.0
	root.add_child(light)
	return root


func _make_battery() -> Sprite3D:
	var img := Image.create(96, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var white := Color(0.95, 0.95, 0.92, 1.0)
	for x: int in range(4, 84):
		for y: int in range(6, 42):
			var edge: bool = x < 9 or x >= 79 or y < 11 or y >= 37
			if edge:
				img.set_pixel(x, y, white)
	for x: int in range(84, 92):
		for y: int in range(17, 31):
			img.set_pixel(x, y, white)
	for x: int in range(14, 28):
		for y: int in range(16, 32):
			img.set_pixel(x, y, Color(1.0, 0.3, 0.22, 1.0))
	var s := Sprite3D.new()
	s.texture = ImageTexture.create_from_image(img)
	s.pixel_size = 0.0016
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.top_level = true
	_props.add_child(s)
	return s


func _prop_mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot
	m.scale = scl
	parent.add_child(m)
	return m
