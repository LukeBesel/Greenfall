class_name Conveyor
extends Node3D
## Conveyor feeder at the base: a yellow hopper pad with a roller turntable, and powered troughed
## belts. Bales dropped on the pad (by haulers or Patch) are turned toward their route and ride
## the belt into the depot scale, or up the incline into the recycler when auto-route says so.

const PAD_HALF: float = 0.9
const BELT_W: float = 0.78
const FEED_INTERVAL: float = 0.35

## One belt route: a polyline of belt-surface points and the bales riding it.
class Line:
	var pts: Array[Vector3] = []
	var lens: Array[float] = []
	var total: float = 0.0
	var items: Array = []  # [{"cube": JunkCube, "s": float}], farthest first
	var to: String = "depot"

	func _init(p: Array[Vector3], dest: String) -> void:
		pts = p
		to = dest
		for i: int in range(1, pts.size()):
			lens.append(pts[i].distance_to(pts[i - 1]))
			total += lens[-1]

	func point_at(s: float) -> Vector3:
		var acc: float = 0.0
		for i: int in lens.size():
			if s <= acc + lens[i] or i == lens.size() - 1:
				return pts[i].lerp(pts[i + 1], clampf((s - acc) / maxf(lens[i], 0.001), 0.0, 1.0))
			acc += lens[i]
		return pts[-1]

	func dir_at(s: float) -> Vector3:
		var acc: float = 0.0
		for i: int in lens.size():
			if s <= acc + lens[i] or i == lens.size() - 1:
				return (pts[i + 1] - pts[i]).normalized()
			acc += lens[i]
		return Vector3.FORWARD

	func entry_free(gap: float) -> bool:
		if items.is_empty():
			return true
		var last: Dictionary = items[-1]
		return float(last["s"]) > gap + (last["cube"] as JunkCube).size


var stations: Stations
var lines: Dictionary = {}  # dest -> Line
var distance: float = 0.0
var _belt_mats: Array[ShaderMaterial] = []
var _rollers: Array[Node3D] = []
var _turntable: Node3D
var _turn_rollers: Array[Node3D] = []
var _pending: JunkCube  # bale on the turntable
var _feed_t: float = 0.0
var _lamp: StandardMaterial3D
var _frame_mat: ShaderMaterial
var _steel: StandardMaterial3D
var _t: float = 0.0


func _ready() -> void:
	_frame_mat = Mats.worn_paint(Color(0.93, 0.68, 0.14), 0.75, 0.5, 51.0, 0.6)
	_steel = Mats.metal("dark_steel")
	_build_pad()
	var hp: Vector3 = hopper_pos()
	var main: Array[Vector3] = [hp + Vector3(-PAD_HALF - 0.05, 0.16, 0), hp + Vector3(-2.0, 0.52, 0), Vector3(1.25, 0.52, hp.z)]
	_add_line(main, "depot")
	var sign_label := Mats.stencil(tr("TO  SCALE  ◀"), 60, Color(0.12, 0.1, 0.08, 0.9))
	sign_label.position = Vector3(3.4, 0.5, hp.z + BELT_W * 0.5 + 0.075)
	add_child(sign_label)
	YardArt.kitify(self)  # [yard] bevelled kit parts and shaders


func hopper_pos() -> Vector3:
	return Stations.HOPPER_POS


func pad_contains(p: Vector3) -> bool:
	var d: Vector3 = p - hopper_pos()
	return absf(d.x) <= PAD_HALF and absf(d.z) <= PAD_HALF and p.y < 1.6


func speed() -> float:
	return float(stations.def("conveyor").get("belt_speed", 1.1)) * Stations.belt_mult() if stations else 1.1


func add_recycler_line() -> void:
	if lines.has("recycler"):
		return
	var hp: Vector3 = hopper_pos()
	if stations == null or stations.recycler == null:
		return
	_add_line(stations.recycler.belt_path(hp + Vector3(0, 0.16, -PAD_HALF - 0.05)), "recycler")
	YardArt.kitify(self)  # [yard]


## Fast-build flourish when bought.
func build_in() -> void:
	for c: Node in get_children():
		if c is Node3D and not (c is JunkCube):
			var n: Node3D = c
			var final: Vector3 = n.position
			n.position = final + Vector3(0, 6.0, 0)
			var tw := n.create_tween()
			tw.tween_interval(randf_range(0.0, 0.8))
			tw.tween_property(n, "position", final, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var tw2 := create_tween()
	tw2.tween_interval(1.25)
	tw2.tween_callback(func() -> void:
		Audio.play("clunk", 0.9, -4.0)
		Audio.play("servo", 0.7, -8.0)
		Vfx.burst("dust", hopper_pos() + Vector3(0, 0.2, 0), Color(0.7, 0.65, 0.6, 0.6), 1.5))


# --- Construction -------------------------------------------------------------------

func _build_pad() -> void:
	var hp: Vector3 = hopper_pos()
	var plate := MeshInstance3D.new()
	plate.mesh = ProcMesh.box(Vector3(PAD_HALF * 2.0, 0.1, PAD_HALF * 2.0))
	plate.material_override = Mats.worn_paint(Color(0.3, 0.31, 0.31), 0.5, 0.6, 52.0, 0.7)
	plate.position = hp + Vector3(0, 0.05, 0)
	add_child(plate)
	# Chevron hazard border.
	var stripe_y := Mats.worn_paint(Color(0.95, 0.72, 0.12), 0.75, 0.4, 53.0, 0.5)
	var stripe_k := Mats.worn_paint(Color(0.07, 0.07, 0.07), 0.9, 0.3, 54.0, 0.5)
	for side: int in 4:
		var b := Basis(Vector3.UP, side * PI * 0.5)
		for k: int in 9:
			var st := MeshInstance3D.new()
			st.mesh = ProcMesh.box(Vector3(0.2, 0.012, 0.13))
			st.material_override = stripe_y if k % 2 == 0 else stripe_k
			st.position = hp + Vector3(0, 0.106, 0) + b * Vector3(-PAD_HALF + 0.1 + k * 0.2, 0, PAD_HALF - 0.065)
			st.basis = b
			add_child(st)
	# Roller turntable: a steel disc with a bed of live rollers that turns to face the route.
	_turntable = Node3D.new()
	_turntable.position = hp + Vector3(0, 0.1, 0)
	add_child(_turntable)
	var disc := MeshInstance3D.new()
	disc.mesh = ProcMesh.cyl(0.72, 0.74, 0.06, 32)
	disc.material_override = _steel
	disc.position.y = 0.03
	_turntable.add_child(disc)
	var ring := MeshInstance3D.new()
	ring.mesh = ProcMesh.torus(0.7, 0.76, 32, 6)
	ring.material_override = _frame_mat
	ring.position.y = 0.05
	_turntable.add_child(ring)
	for k: int in 7:
		var zz: float = -0.48 + k * 0.16
		var half: float = sqrt(maxf(0.68 * 0.68 - zz * zz, 0.01))
		var piv := Node3D.new()
		piv.position = Vector3(0, 0.1, zz)
		_turntable.add_child(piv)
		var r := MeshInstance3D.new()
		r.mesh = ProcMesh.cyl(0.045, 0.045, half * 1.8, 12)
		r.material_override = Mats.metal("steel")
		r.rotation_degrees = Vector3(0, 0, 90)
		piv.add_child(r)
		_turn_rollers.append(piv)
	# Low side guides on the north and east edges.
	for spec: Array in [[Vector3(0, 0.22, PAD_HALF - 0.04), Vector3(PAD_HALF * 2.0, 0.22, 0.06)], [Vector3(PAD_HALF - 0.04, 0.22, 0), Vector3(0.06, 0.22, PAD_HALF * 2.0)]]:
		var g := MeshInstance3D.new()
		g.mesh = ProcMesh.box(spec[1])
		g.material_override = _frame_mat
		g.position = hp + (spec[0] as Vector3)
		add_child(g)
	# Gantry over the north edge with a sign and a beacon.
	var parts: Array = []
	for x: float in [-PAD_HALF - 0.05, PAD_HALF + 0.05]:
		parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.1, 2.3, 0.1)), ProcMesh.xf(Vector3(x, 1.15, PAD_HALF + 0.1))))
		parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.3, 0.04, 0.3)), ProcMesh.xf(Vector3(x, 0.02, PAD_HALF + 0.1))))
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(PAD_HALF * 2.0 + 0.3, 0.12, 0.12)), ProcMesh.xf(Vector3(0, 2.3, PAD_HALF + 0.1))))
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(1.5, 0.42, 0.04)), ProcMesh.xf(Vector3(0, 1.98, PAD_HALF + 0.12))))
	var gantry := MeshInstance3D.new()
	gantry.mesh = ProcMesh.merge(parts)
	gantry.material_override = _frame_mat
	gantry.position = hp
	add_child(gantry)
	var sign_label := Mats.stencil(tr("BALE  FEED"), 110, Color(0.1, 0.09, 0.08, 0.95))
	sign_label.position = hp + Vector3(0, 1.98, PAD_HALF + 0.145)
	add_child(sign_label)
	var lamp := MeshInstance3D.new()
	lamp.mesh = ProcMesh.sphere(0.08, 12, 6)
	_lamp = Mats.lamp(Color(1.0, 0.6, 0.15), 0.6)
	lamp.material_override = _lamp
	lamp.position = hp + Vector3(PAD_HALF + 0.05, 2.42, PAD_HALF + 0.1)
	add_child(lamp)
	# Drive motor + gearbox beside the pad.
	var motor := MeshInstance3D.new()
	motor.mesh = ProcMesh.cyl(0.13, 0.13, 0.42, 16)
	motor.material_override = Mats.worn_paint(Color(0.25, 0.42, 0.55), 0.8, 0.4, 55.0, 0.5)
	motor.rotation_degrees = Vector3(0, 0, 90)
	motor.position = hp + Vector3(PAD_HALF + 0.3, 0.2, -0.45)
	add_child(motor)
	var gb := MeshInstance3D.new()
	gb.mesh = ProcMesh.rounded_box(Vector3(0.22, 0.3, 0.3), 0.03, 2)
	gb.material_override = _steel
	gb.position = hp + Vector3(PAD_HALF + 0.08, 0.17, -0.45)
	add_child(gb)
	var sb := StaticBody3D.new()
	sb.position = hp
	add_child(sb)
	for spec2: Array in [[Vector3(-PAD_HALF - 0.05, 1.15, PAD_HALF + 0.1), Vector3(0.12, 2.3, 0.12)], [Vector3(PAD_HALF + 0.05, 1.15, PAD_HALF + 0.1), Vector3(0.12, 2.3, 0.12)]]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = spec2[1]
		cs.shape = bs
		cs.position = spec2[0]
		sb.add_child(cs)


func _add_line(p: Array[Vector3], dest: String) -> void:
	var line := Line.new(p, dest)
	lines[dest] = line
	for i: int in range(1, p.size()):
		_belt_segment(p[i - 1], p[i], i == 1, i == p.size() - 1)


func _belt_segment(a: Vector3, b: Vector3, first: bool, last: bool) -> void:
	var d: Vector3 = b - a
	var length: float = d.length()
	var x: Vector3 = d / length
	var z: Vector3 = x.cross(Vector3.UP).normalized()
	var y: Vector3 = z.cross(x)
	var seg := Node3D.new()
	seg.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	add_child(seg)
	var belt := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(length, BELT_W)
	belt.mesh = pm
	var bm := ShaderMaterial.new()
	bm.shader = preload("res://art/shaders/belt.gdshader")
	bm.set_shader_parameter("length_m", length)
	bm.set_shader_parameter("width_m", BELT_W)
	bm.set_shader_parameter("grit", AssetLib.tex("rubble", "nor_gl"))
	belt.material_override = bm
	seg.add_child(belt)
	_belt_mats.append(bm)
	# Side skirts and a box-section frame under the belt.
	var parts: Array = []
	for s: float in [-1.0, 1.0]:
		parts.append(ProcMesh.part(ProcMesh.box(Vector3(length + 0.02, 0.2, 0.05)), ProcMesh.xf(Vector3(0, 0.0, s * (BELT_W * 0.5 + 0.03)))))
		parts.append(ProcMesh.part(ProcMesh.box(Vector3(length + 0.02, 0.03, 0.09)), ProcMesh.xf(Vector3(0, 0.1, s * (BELT_W * 0.5 + 0.05)))))
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(length, 0.05, BELT_W + 0.06)), ProcMesh.xf(Vector3(0, -0.2, 0))))
	var frame := MeshInstance3D.new()
	frame.mesh = ProcMesh.merge(parts)
	frame.material_override = _frame_mat
	seg.add_child(frame)
	var under := MeshInstance3D.new()
	under.mesh = ProcMesh.box(Vector3(length, 0.02, BELT_W - 0.02))
	under.material_override = Mats.rubber(Color(0.05, 0.05, 0.055))
	under.position = Vector3(0, -0.15, 0)
	seg.add_child(under)
	# Rollers: head/tail drums at the ends, return idlers underneath, bolt heads on the skirts.
	var ends: Array[float] = []
	if first:
		ends.append(-length * 0.5)
	if last:
		ends.append(length * 0.5)
	for ex: float in ends:
		_roller(seg, Vector3(ex, -0.075, 0), 0.075, BELT_W + 0.04)
	var n_idle: int = maxi(1, int(length / 0.7))
	for k: int in n_idle:
		_roller(seg, Vector3(-length * 0.5 + (k + 0.5) * length / n_idle, -0.17, 0), 0.03, BELT_W - 0.04)
	var bolts: Array = []
	for k: int in int(length / 0.35):
		for s: float in [-1.0, 1.0]:
			bolts.append(ProcMesh.part(ProcMesh.cyl(0.014, 0.014, 0.012, 6), ProcMesh.xf(Vector3(-length * 0.5 + 0.17 + k * 0.35, -0.02, s * (BELT_W * 0.5 + 0.058)), Vector3(90, 0, 0))))
	if not bolts.is_empty():
		var bm2 := MeshInstance3D.new()
		bm2.mesh = ProcMesh.merge(bolts)
		bm2.material_override = Mats.metal("steel")
		seg.add_child(bm2)
	# Legs down to the ground (in world space) every ~1.3 m.
	var n_legs: int = maxi(1, int(length / 1.3) + 1)
	for k: int in n_legs:
		var t: float = (k + 0.5) / n_legs
		var p: Vector3 = a.lerp(b, t) - y * 0.22
		if p.y < 0.12:
			continue
		var lp: Array = []
		for s: float in [-1.0, 1.0]:
			var q: Vector3 = p + z * s * (BELT_W * 0.5 + 0.04)
			lp.append(ProcMesh.part(ProcMesh.box(Vector3(0.06, q.y, 0.06)), ProcMesh.xf(Vector3(q.x, q.y * 0.5, q.z))))
			lp.append(ProcMesh.part(ProcMesh.box(Vector3(0.16, 0.025, 0.16)), ProcMesh.xf(Vector3(q.x, 0.012, q.z))))
		if p.y > 0.45:
			lp.append(ProcMesh.part(ProcMesh.box(Vector3(0.04, 0.04, BELT_W + 0.1)), ProcMesh.xf(Vector3(p.x, p.y * 0.45, p.z), Vector3(0, rad_to_deg(atan2(z.x, z.z)), 0))))
		var legs := MeshInstance3D.new()
		legs.mesh = ProcMesh.merge(lp)
		legs.material_override = _steel
		add_child(legs)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(length, 0.3, BELT_W + 0.12)
	cs.shape = bs
	cs.position = Vector3(0, -0.17, 0)
	sb.add_child(cs)
	seg.add_child(sb)


func _roller(parent: Node3D, pos: Vector3, r: float, w: float) -> void:
	var piv := Node3D.new()
	piv.position = pos
	parent.add_child(piv)
	var m := MeshInstance3D.new()
	m.mesh = ProcMesh.cyl(r, r, w, 14)
	m.material_override = Mats.metal("steel")
	m.rotation_degrees = Vector3(90, 0, 0)
	piv.add_child(m)
	piv.set_meta("r", r)
	_rollers.append(piv)


# --- Running ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_t += delta
	var v: float = speed()
	distance += v * delta
	for m: ShaderMaterial in _belt_mats:
		m.set_shader_parameter("scroll", distance)
	for r: Node3D in _rollers:
		r.rotation.z = -distance / float(r.get_meta("r", 0.05))
	var busy: bool = _pending != null
	for dest: String in lines:
		var line: Line = lines[dest]
		busy = busy or not line.items.is_empty()
		_advance(line, v, delta)
	if _lamp:
		_lamp.emission_energy_multiplier = (2.5 + sin(_t * 9.0) * 1.5) if busy else 0.6
	_feed_t -= delta
	if _pending == null and _feed_t <= 0.0:
		_try_feed()


func _advance(line: Line, v: float, delta: float) -> void:
	var gap: float = float(stations.def("conveyor").get("gap", 0.75)) if stations else 0.75
	var i: int = 0
	while i < line.items.size():
		var it: Dictionary = line.items[i]
		var c: JunkCube = it["cube"]
		if not is_instance_valid(c):
			line.items.remove_at(i)
			continue
		var limit: float = line.total
		if i > 0:
			limit = float(line.items[i - 1]["s"]) - gap - c.size * 0.5
		var s: float = minf(float(it["s"]) + v * delta, maxf(limit, float(it["s"])))
		it["s"] = s
		var dir: Vector3 = line.dir_at(s)
		var up: Vector3 = dir.cross(Vector3.UP).normalized().cross(dir)
		c.global_position = line.point_at(s) + up * (c.size * 0.5 + 0.01)
		c.global_basis = Basis.looking_at(Vector3(dir.x, 0, dir.z).normalized() if absf(dir.y) < 0.99 else Vector3.FORWARD, Vector3.UP)
		if i == 0 and s >= line.total - 0.001 and _deliver(line, c):
			line.items.remove_at(0)
			continue
		i += 1


func _deliver(line: Line, c: JunkCube) -> bool:
	if line.to == "recycler":
		if stations == null or stations.recycler == null or not stations.recycler.can_feed():
			return false
		stations.recycler.feed(c)
		return true
	var dir: Vector3 = line.dir_at(line.total)
	if stations:
		stations.release_cube(c, c.global_position + dir * 0.15, dir * speed() + Vector3(0, -0.3, 0))
	Audio.play("thud", 1.1, -12.0)
	return true


func _try_feed() -> void:
	var cube: JunkCube = null
	var from_patch: bool = false
	# Patch standing on the pad: his carried bales hop onto the turntable one by one.
	var p: Node3D = stations.patch_node() if stations else null
	if p and pad_contains(p.global_position) and p.has_method("pop_carried_cube"):
		cube = p.pop_carried_cube()
		from_patch = cube != null
	if cube == null:
		for n: Node in get_tree().get_nodes_in_group("junk_cube"):
			var c: JunkCube = n
			if c.carried or c.claimed or not pad_contains(c.global_position):
				continue
			cube = c
			break
	if cube == null:
		return
	var dest: String = "depot"
	if lines.has("recycler") and stations:
		dest = stations.next_route()
	var line: Line = lines.get(dest, lines["depot"])
	if not line.entry_free(float(stations.def("conveyor").get("gap", 0.75)) if stations else 0.75):
		# Belt backed up: leave the bale on the pad for now.
		if from_patch and stations:
			stations.release_cube(cube, hopper_pos() + Vector3(randf_range(-0.3, 0.3), 0.7, randf_range(-0.3, 0.3)))
		if dest == "recycler":
			stations.route_count -= 1
		_feed_t = 0.3
		return
	_turn_and_push(cube, line)


func _turn_and_push(cube: JunkCube, line: Line) -> void:
	_pending = cube
	cube.claimed = true
	cube.set_carried(true)
	if cube.get_parent() != self:
		if cube.get_parent():
			cube.reparent(self, true)
		else:
			add_child(cube)
	var start: Vector3 = cube.global_position
	var center: Vector3 = hopper_pos() + Vector3(0, 0.2 + cube.size * 0.5, 0)
	var dir: Vector3 = line.dir_at(0.0)
	var yaw: float = atan2(-dir.x, -dir.z)
	var entry: Vector3 = line.pts[0] + Vector3(0, cube.size * 0.5 + 0.02, 0)
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		if is_instance_valid(cube):
			var top: Vector3 = (start + center) * 0.5 + Vector3(0, 0.25, 0)
			cube.global_position = start.lerp(top, t).lerp(top.lerp(center, t), t)
		, 0.0, 1.0, 0.25)
	tw.tween_callback(func() -> void:
		Audio.play("clunk", 1.1, -9.0)
		Audio.play("servo", 0.9, -12.0))
	var yaw0: float = _turntable.rotation.y
	var target: float = yaw0 + wrapf(yaw - yaw0, -PI, PI)
	tw.tween_method(func(a: float) -> void:
		_turntable.rotation.y = a
		if is_instance_valid(cube):
			cube.global_basis = Basis(Vector3.UP, a)
		, yaw0, target, 0.3).set_trans(Tween.TRANS_SINE)
	tw.tween_method(func(t: float) -> void:
		for r: Node3D in _turn_rollers:
			r.rotation.x = -t * 8.0
		if is_instance_valid(cube):
			cube.global_position = center.lerp(entry, t)
		, 0.0, 1.0, 0.75 / maxf(speed(), 0.2))
	tw.tween_callback(func() -> void:
		_pending = null
		_feed_t = FEED_INTERVAL
		if is_instance_valid(cube):
			line.items.append({"cube": cube, "s": 0.0}))


## Dev/screenshot helper: spreads bales along the belts (the last one waits on the pad).
func demo_load(cubes: Array[JunkCube]) -> void:
	var i: int = 0
	for dest: String in ["depot", "recycler"]:
		if not lines.has(dest):
			continue
		var line: Line = lines[dest]
		var n: int = 3 if dest == "depot" else 1
		for k: int in n:
			if i >= cubes.size() - 1:
				break
			var c: JunkCube = cubes[i]
			i += 1
			c.claimed = true
			c.set_carried(true)
			c.reparent(self, true)
			line.items.append({"cube": c, "s": line.total * (0.85 - 0.3 * k) if dest == "depot" else line.total * 0.55})
	for k2: int in range(i, cubes.size()):
		cubes[k2].global_position = hopper_pos() + Vector3(-0.2 + (k2 - i) * 0.1, 0.5 + (k2 - i) * 0.7, 0.1)


func held_dicts() -> Array:
	var out: Array = []
	for dest: String in lines:
		for it: Dictionary in (lines[dest] as Line).items:
			if is_instance_valid(it["cube"]):
				out.append((it["cube"] as JunkCube).to_dict())
	if _pending and is_instance_valid(_pending):
		out.append(_pending.to_dict())
	return out
