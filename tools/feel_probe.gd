class_name FeelProbe
extends Node
## [v6feel] Scripted feel checks on the round game: a timeline drives Lumi (FeelInput) and the probe
## prints what a player would notice, as `[feel]` lines. Headless, add `-- --fresh --orbit --no-intro`:
##   --feel=carry --orbit-carry=N   gap between the carried bales and Lumi's body, per phase
##                                  (idle, walk, turn, boost, stop, put down, pick up). Exit 1 if a
##                                  bale ever touches a solid part of him.
##   --feel=move                    start / stop times, top speeds, hover height jitter.
##   --feel=cam                     camera arm and jumps along a walk (--feel-walk=x,z;x,z;... in
##                                  metres from the start cell).
##   --feel=snag                    pushes Lumi at the known snag corners; reports ground covered.
## --feel-quit quits when the timeline ends.

class FeelInput:
	extends InputSource
	var stick := Vector3.ZERO  # camera-local (x right, z back), or world space with world_space
	var world_space: bool = false
	var boost: bool = false
	var scoop: bool = false
	var jump: bool = false
	var cube: bool = false
	var interact: bool = false
	var drop: bool = false

	func get_world_move(_cam_yaw: float) -> Vector3:
		return stick

	func scoop_held() -> bool:
		return scoop

	func boost_held() -> bool:
		return boost

	func jump_pressed() -> bool:
		var j: bool = jump
		jump = false
		return j

	func cube_pressed() -> bool:
		var c: bool = cube
		cube = false
		return c

	func interact_pressed() -> bool:
		var i: bool = interact
		interact = false
		return i

	func drop_pressed() -> bool:
		var d: bool = drop
		drop = false
		return d


var so: Node  # SliceOrbit
var lumi: Patch
var inp := FeelInput.new()
var mode: String = ""
var _t: float = 0.0
var _phase: String = ""
var _steps: Array = []  # [until_s, name, Callable(inp, t_in_phase)]
var _acc: Dictionary = {}
var _fail: bool = false
var _done: bool = false
var _verts: Dictionary = {}  # Mesh -> PackedVector3Array (thinned)


static func attach(p_so: Node) -> void:
	var p := FeelProbe.new()
	p.name = "FeelProbe"
	p.so = p_so
	p.mode = DevHooks.get_s("feel", "carry")
	p_so.w.add_child(p)


func _ready() -> void:
	lumi = so.w.get("patch")
	process_physics_priority = 100  # after Lumi's own step
	await get_tree().create_timer(DevHooks.get_f("feel-delay", 3.0)).timeout
	lumi.input = inp
	match mode:
		"carry":
			_steps = _carry_steps()
		"move":
			_steps = _move_steps()
	_t = 0.0
	set_physics_process(true)
	print("[feel] %s: start, design %s, %d bales" % [mode, lumi.model.variant, lumi.carried.size()])


func _fwd(i: FeelInput, _t_in: float) -> void:
	i.stick = Vector3(0, 0, -1)


func _carry_steps() -> Array:
	return [
		[1.5, "idle", func(i: FeelInput, _s: float) -> void: i.stick = Vector3.ZERO],
		[4.5, "walk", _fwd],
		[5.5, "stop", func(i: FeelInput, _s: float) -> void: i.stick = Vector3.ZERO],
		[9.5, "turn", func(i: FeelInput, s: float) -> void: i.stick = Vector3(sin(s * 3.0), 0, -cos(s * 3.0))],
		[11.0, "zigzag", func(i: FeelInput, s: float) -> void: i.stick = Vector3(1.0 if fmod(s, 0.5) < 0.25 else -1.0, 0, 0)],
		[15.0, "boost", func(i: FeelInput, _s: float) -> void:
			i.stick = Vector3(0, 0, -1)
			i.boost = true],
		[16.5, "boost_stop", func(i: FeelInput, _s: float) -> void:
			i.stick = Vector3.ZERO
			i.boost = false],
		[18.5, "scoop_walk", func(i: FeelInput, _s: float) -> void:
			i.stick = Vector3(0, 0, -1)
			i.scoop = true],
		[19.5, "jump", func(i: FeelInput, s: float) -> void:
			i.scoop = false
			i.stick = Vector3(0, 0, -1)
			i.jump = s < 0.05],
		[20.5, "put_down", func(i: FeelInput, s: float) -> void:
			i.stick = Vector3.ZERO
			i.drop = s < 0.02],
		[22.0, "pick_up", func(i: FeelInput, s: float) -> void: i.interact = s < 0.02],
	]


func _move_steps() -> Array:
	return [
		[1.0, "idle", func(i: FeelInput, _s: float) -> void: i.stick = Vector3.ZERO],
		[3.0, "start", _fwd],
		[4.5, "stop", func(i: FeelInput, _s: float) -> void: i.stick = Vector3.ZERO],
		[6.5, "reverse", func(i: FeelInput, _s: float) -> void: i.stick = Vector3(0, 0, 1)],
		[8.0, "stop2", func(i: FeelInput, _s: float) -> void: i.stick = Vector3.ZERO],
		[12.0, "boost", func(i: FeelInput, _s: float) -> void:
			i.stick = Vector3(0, 0, -1)
			i.boost = true],
		[14.0, "boost_stop", func(i: FeelInput, _s: float) -> void:
			i.stick = Vector3.ZERO
			i.boost = false],
		[20.0, "walk_long", _fwd],
	]


func _physics_process(delta: float) -> void:
	if _steps.is_empty() or _done:
		return
	_t += delta
	var start: float = 0.0
	var cur: Array = []
	for s: Array in _steps:
		if _t < float(s[0]):
			cur = s
			break
		start = float(s[0])
	if cur.is_empty():
		_flush()
		_done = true
		print("[feel] %s: %s" % [mode, "FAIL" if _fail else "PASS"])
		if DevHooks.has("feel-quit"):
			get_tree().quit(1 if _fail else 0)
		return
	if str(cur[1]) != _phase:
		_flush()
		_phase = str(cur[1])
		_acc = {}
	(cur[2] as Callable).call(inp, _t - start)
	match mode:
		"carry":
			_carry_sample()
		"move":
			_move_sample(delta, _t - start)


func _flush() -> void:
	if _phase == "" or _acc.is_empty():
		return
	match mode:
		"carry":
			var solid: float = float(_acc.get("solid", 9.0))
			var thin: float = float(_acc.get("thin", 9.0))
			var bad: bool = solid < 0.0
			_fail = _fail or bad
			var ys: Array = []
			for c: JunkCube in lumi.carried:
				ys.append(snappedf(lumi.to_local(c.global_position).y, 0.01))
			print("[feel] carry   bale heights %s, hold point %.2f, sizes %s" % [str(ys), lumi.get_node("Stack").position.y, str(lumi.carried.map(func(c: JunkCube) -> float: return snappedf(c.size, 0.01)))])
			print("[feel] carry %-10s gap to body %+.3f m (%s)  to thin parts %+.3f m (%s)  bales %d%s" % [_phase, solid, str(_acc.get("solid_part", "-")), thin, str(_acc.get("thin_part", "-")), lumi.carried.size(), "  CLIP" if bad else ""])
		"move":
			print("[feel] move %-10s %s" % [_phase, JSON.stringify(_acc)])


# --- carry: how close the bales come to Lumi's own meshes -----------------------------------

func _mesh_verts(m: Mesh) -> PackedVector3Array:
	if _verts.has(m):
		return _verts[m]
	var out := PackedVector3Array()
	var seen: Dictionary = {}
	for v: Vector3 in m.get_faces():
		var k: Vector3i = Vector3i((v * 200.0).round())
		if not seen.has(k):
			seen[k] = true
			out.append(v)
	_verts[m] = out
	return out


## Signed gap (m) between every carried bale's drawn block and Lumi's meshes: below 0 = inside.
func _carry_sample() -> void:
	if lumi.carried.is_empty():
		return
	var holder_inv: Transform3D = lumi.global_transform.affine_inverse()
	for n: Node in lumi.model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or mi.top_level:
			continue
		var ab: AABB = (holder_inv * mi.global_transform) * mi.mesh.get_aabb()
		if ab.position.y > 2.5 or ab.end.y < 0.5:
			continue
		var thin: bool = ab.size.x < 0.12 and ab.size.z < 0.12
		var vs: PackedVector3Array = _mesh_verts(mi.mesh)
		for c: JunkCube in lumi.carried:
			var vis: MeshInstance3D = c.get("_visual")
			var xf: Transform3D = vis.global_transform.affine_inverse() * mi.global_transform
			var sc: Vector3 = vis.global_basis.get_scale()
			var best: float = 9.0
			for v: Vector3 in vs:
				var p: Vector3 = xf * v
				# Unit block: distance outside the nearest face, in metres.
				var d: float = maxf(maxf((absf(p.x) - 0.52) * sc.x, (absf(p.y) - 0.52) * sc.y), (absf(p.z) - 0.52) * sc.z)
				if d < best:
					best = d
			var key: String = "thin" if thin else "solid"
			if best < float(_acc.get(key, 9.0)):
				_acc[key] = best
				_acc[key + "_part"] = str(mi.mesh.resource_name if mi.mesh.resource_name != "" else mi.get_parent().name)


# --- move: timings ----------------------------------------------------------------------------

func _move_sample(delta: float, s: float) -> void:
	var m: SphereMotor = lumi.sphere_motor
	var spd: float = m.hv.length()
	_acc["top"] = snappedf(maxf(float(_acc.get("top", 0.0)), spd), 0.01)
	_acc["end"] = snappedf(spd, 0.01)
	var walk: float = lumi.stat("move_speed")
	if not _acc.has("t90") and spd >= walk * 0.9:
		_acc["t90"] = snappedf(s, 0.01)
	if not _acc.has("t_stop") and spd <= 0.05 and s > delta * 2.0:
		_acc["t_stop"] = snappedf(s, 0.01)
	var alt: float = lumi.sphere.altitude(lumi.global_position)
	_acc["alt_min"] = snappedf(minf(float(_acc.get("alt_min", 9.0)), alt), 0.001)
	_acc["alt_max"] = snappedf(maxf(float(_acc.get("alt_max", -9.0)), alt), 0.001)
	_acc["vv_max"] = snappedf(maxf(float(_acc.get("vv_max", 0.0)), absf(m.vv)), 0.01)
