class_name OchreExcavator
extends RefCounted
## [planet-ochre] A towering bucket-wheel excavator (~48 m tall, ~90 m long), built from boxes and
## merged per material. Local frame: origin on the ground under the turntable, +X along the boom,
## crawlers along Z.
##   "working": crawlers, house, mast and counterweight always; the boom slumps with its wheel
##               dug into the ground while ruined, and is raised once the base is fixed up.
##   "fallen":  the boom snapped and lies down the slope, the mast collapsed beside it.
## Futuristic: the buckets become planters, sail vanes turn the wheel into a slow wind wheel, a
## terracotta wind-catcher tower rises from the house roof, vines hang from the boom.

const WHEEL_R: float = 9.0
const BOOM_L: float = 42.0
const PIVOT := Vector3(5.0, 11.5, 0.0)


static func _truss(b: OchreProps.Batch, a: Vector3, c: Vector3, half: float, chord: Material, brace: Material, half_end: float = -1.0) -> void:
	if half_end < 0.0:
		half_end = half
	var d: Vector3 = (c - a).normalized()
	var s: Vector3 = d.cross(Vector3.UP).normalized() if absf(d.y) < 0.95 else Vector3.FORWARD
	var u: Vector3 = s.cross(d).normalized()
	var cs: Array[Vector2] = [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	var l: float = a.distance_to(c)
	var n: int = maxi(2, int(l / 3.6))
	for k: int in 4:
		var o0: Vector3 = (s * cs[k].x + u * cs[k].y) * half
		var o1: Vector3 = (s * cs[k].x + u * cs[k].y) * half_end
		b.beam(a + o0, c + o1, 0.42, chord)
	for i: int in n:
		var t0: float = float(i) / n
		var t1: float = float(i + 1) / n
		var p0: Vector3 = a.lerp(c, t0)
		var p1: Vector3 = a.lerp(c, t1)
		var h0: float = lerpf(half, half_end, t0)
		var h1: float = lerpf(half, half_end, t1)
		for k: int in 4:
			var ka: Vector2 = cs[k]
			var kb: Vector2 = cs[(k + 1) % 4]
			var q0: Vector3 = p0 + (s * ka.x + u * ka.y) * h0
			var q1: Vector3 = p1 + (s * kb.x + u * kb.y) * h1
			if i % 2 == 1:
				q0 = p0 + (s * kb.x + u * kb.y) * h0
				q1 = p1 + (s * ka.x + u * ka.y) * h1
			b.beam(q0, q1, 0.2, brace)


static func boom_tip(tilt_deg: float) -> Vector3:
	var a: float = deg_to_rad(tilt_deg)
	return PIVOT + Vector3(cos(a), sin(a), 0.0) * BOOM_L


## Builds into the groups ("always", "ruin", "up", "future": Node3D); returns
## {"paint": [MeshInstance3D], "wheels": [Node3D] (spin at the futuristic stage)}.
static func build(groups: Dictionary, xf: Transform3D, mats: Dictionary, kind: String, seed_v: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var out: Dictionary = {"paint": [], "wheels": []}
	var nodes: Dictionary = {}
	for g: String in groups:
		var n := Node3D.new()
		n.name = "Excavator%d" % seed_v
		n.transform = xf
		(groups[g] as Node3D).add_child(n)
		nodes[g] = n
	var paint: Material = mats["paint"]
	var steel: Material = mats["steel"]
	var dark: Material = mats["dark"]
	var base := OchreProps.Batch.new()
	# Crawlers, frame and turntable.
	for x: float in [-4.6, 4.6]:
		# Track frame, idlers, rollers and a belt of grousered pads.
		base.box(Vector3(x, 1.7, 0), Vector3(2.4, 2.2, 18.0), steel)
		for z: float in [-9.0, 9.0]:
			base.add(ProcMesh.cyl(1.7, 1.7, 3.7, 14), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(x, 1.7, z)), dark)
		for z: int in 6:
			base.add(ProcMesh.cyl(0.55, 0.55, 3.0, 10), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(x, 0.75, -6.5 + z * 2.6)), steel)
		for i: int in 26:
			var zz: float = -8.4 + i * 0.68
			base.box(Vector3(x, 0.18, zz), Vector3(3.8, 0.36, 0.6), dark)
			base.box(Vector3(x, 3.22, zz), Vector3(3.8, 0.36, 0.6), dark)
		for i: int in 8:
			var a: float = PI * 0.5 + PI * i / 7.0
			for zs: float in [-9.0, 9.0]:
				var o := Vector3(0, sin(a), cos(a) * signf(zs)) * 1.75
				base.box(Vector3(x, 1.7, zs) + o, Vector3(3.8, 0.5, 0.5), dark, Basis(Vector3.RIGHT, -a * signf(zs)))
	base.box(Vector3(0, 3.9, 0), Vector3(12.0, 1.4, 12.0), steel)
	base.add(ProcMesh.cyl(6.4, 6.8, 1.6, 20), ProcMesh.xf(Vector3(0, 5.4, 0)), steel)
	# House, roof machinery, cab, walkways.
	base.box(Vector3(-1.5, 10.6, 0), Vector3(15.0, 9.0, 10.5), paint)
	base.box(Vector3(-3.0, 16.6, 0), Vector3(8.5, 3.0, 7.5), paint)
	base.box(Vector3(6.6, 12.2, 5.8), Vector3(3.4, 3.2, 3.2), paint)
	base.box(Vector3(8.35, 12.6, 5.8), Vector3(0.1, 1.6, 2.6), mats["glass"])
	base.box(Vector3(6.6, 12.6, 7.42), Vector3(2.8, 1.5, 0.08), mats["glass"])
	base.box(Vector3(7.0, 13.95, 5.8), Vector3(4.2, 0.18, 3.8), dark)
	base.box(Vector3(-1.5, 6.3, 5.6), Vector3(16.0, 0.25, 1.4), steel)
	# Walkways with handrails round the house, a stair down to the crawlers, ducts, stacks, vents.
	for side: float in [-1.0, 1.0]:
		base.box(Vector3(-1.5, 15.2, side * 5.95), Vector3(15.6, 0.2, 1.2), steel)
		for i: int in 9:
			base.box(Vector3(-9.0 + i * 1.9, 15.8, side * 6.5), Vector3(0.08, 1.1, 0.08), steel)
		base.box(Vector3(-1.5, 16.35, side * 6.5), Vector3(15.6, 0.08, 0.08), steel)
		base.box(Vector3(-1.5, 15.85, side * 6.5), Vector3(15.6, 0.06, 0.06), steel)
	for i: int in 14:
		base.box(Vector3(-8.5 + i * 0.55, 6.1 - i * 0.42, 6.9), Vector3(0.5, 0.08, 1.0), steel)
	base.beam(Vector3(-8.7, 6.3, 7.45), Vector3(-1.2, 0.4, 7.45), 0.12, steel)
	base.beam(Vector3(-8.7, 7.3, 7.45), Vector3(-1.2, 1.4, 7.45), 0.06, steel)
	for i: int in 3:
		base.add(ProcMesh.cyl(0.45, 0.5, 4.5, 10), ProcMesh.xf(Vector3(-6.5 + i * 1.5, 20.2, -2.5)), dark)
	base.add(ProcMesh.cyl(0.4, 0.4, 13.0, 10), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-1.5, 9.0, -5.55)), steel)
	base.add(ProcMesh.cyl(0.4, 0.4, 13.0, 10), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-1.5, 11.0, -5.55)), steel)
	for i: int in 5:
		base.box(Vector3(-7.5 + i * 3.0, 12.5, 5.3), Vector3(1.6, 2.4, 0.1), dark)
		for k: int in 5:
			base.box(Vector3(-7.5 + i * 3.0, 11.6 + k * 0.45, 5.37), Vector3(1.4, 0.06, 0.06), steel)
	# Hazard chevrons on the counterweight and the crawler ends.
	for i: int in 9:
		base.box(Vector3(-35.56, 14.0, -2.8 + i * 0.7), Vector3(0.06, 2.4, 0.32), dark if i % 2 == 0 else paint, Basis(Vector3.RIGHT, 0.55))
		base.box(Vector3(-35.56, 17.6, -2.8 + i * 0.7), Vector3(0.06, 2.4, 0.32), paint if i % 2 == 0 else dark, Basis(Vector3.RIGHT, -0.55))
	for i: int in 9:
		base.box(Vector3(-9.0 + i * 1.9, 13.7, -5.3), Vector3(0.12, 4.0, 0.12) if i % 2 == 0 else Vector3(1.0, 0.5, 0.06), dark)
	# Counterweight boom and its block (behind the house).
	var cw0 := Vector3(-8.0, 12.5, 0)
	var cw1 := Vector3(-30.0, 17.0, 0)
	_truss(base, cw0, cw1, 1.4, paint, steel, 1.0)
	base.box(cw1 + Vector3(-2.0, -1.5, 0), Vector3(7.0, 6.0, 6.5), mats["concrete"])
	# Discharge conveyor boom, slung off the back to one side.
	var dc0 := Vector3(-6.0, 7.5, 5.5)
	var dc1 := Vector3(-34.0, 4.0, 19.0)
	if kind == "fallen":
		dc1 = Vector3(-30.0, 0.8, 20.0)
	_truss(base, dc0, dc1, 0.9, paint, steel)
	base.beam(dc0 + Vector3(0, 1.0, 0), dc1 + Vector3(0, 1.0, 0), 0.08, dark)
	base.box(dc1 + Vector3(0, -1.5, 0), Vector3(2.0, 3.0, 2.0), steel)
	# Mast (A-frame) over the house.
	var apex := Vector3(-4.0, 47.0, 0)
	if kind == "fallen":
		apex = Vector3(-26.0, 4.0, -16.0)
	for z: float in [-3.4, 3.4]:
		base.beam(Vector3(-1.0, 18.0, z), apex + Vector3(0, 0, z * 0.15), 1.0, paint)
		base.beam(Vector3(-6.5, 18.0, z), apex + Vector3(0, 0, z * 0.15), 0.7, paint)
	base.box(apex, Vector3(2.4, 2.4, 2.4), steel)
	if kind != "fallen":
		for z: float in [-0.6, 0.6]:
			base.beam(apex + Vector3(0, 0, z), cw1 + Vector3(0, 2.5, z), 0.16, dark)
	var lists: Array[MeshInstance3D] = base.flush(nodes["always"], true, 1600.0)
	for mi: MeshInstance3D in lists:
		if mi.material_override == paint:
			(out["paint"] as Array).append(mi)
	# Booms: slumped (ruined), raised (fixed up) or snapped (fallen).
	var poses: Array = [["ruin", -8.5], ["up", 9.0]] if kind != "fallen" else [["always", -33.0]]
	for pz: Array in poses:
		var g: String = pz[0]
		var tilt: float = pz[1]
		var bb := OchreProps.Batch.new()
		var tip: Vector3 = boom_tip(tilt)
		var root: Vector3 = PIVOT
		if kind == "fallen":
			# Snapped at a third of its length: the stub droops, the rest lies on the ground.
			var brk: Vector3 = PIVOT + Vector3(cos(deg_to_rad(-12.0)), sin(deg_to_rad(-12.0)), 0) * 14.0
			_truss(bb, PIVOT, brk, 1.7, paint, steel, 1.55)
			root = brk + Vector3(1.0, -1.5, 1.5)
			tip = Vector3(root.x + 27.0, 1.6, root.z + 8.0)
		_truss(bb, root, tip, 1.7, paint, steel, 1.2)
		bb.box(tip + Vector3(-1.0, 0, 1.4), Vector3(4.0, 3.0, 1.2), steel)
		if kind != "fallen":
			for z: float in [-0.6, 0.6]:
				bb.beam(apex + Vector3(0, 0, z), PIVOT.lerp(tip, 0.82) + Vector3(0, 1.6, z), 0.16, dark)
			# Conveyor belt along the boom.
			bb.beam(root + Vector3(0, -0.6, 0), tip + Vector3(-3.0, -0.6, 0), 0.06, dark)
		for mi: MeshInstance3D in bb.flush(nodes[g], true, 1600.0):
			if mi.material_override == paint:
				(out["paint"] as Array).append(mi)
		var wheel := Node3D.new()
		wheel.name = "Wheel"
		wheel.position = tip + Vector3(0, 0, 3.6)
		if kind == "fallen":
			wheel.position = tip + Vector3(3.0, 1.2, 4.0)
			wheel.rotation = Vector3(deg_to_rad(84.0), deg_to_rad(10.0), 0.0)
		(nodes[g] as Node3D).add_child(wheel)
		_wheel(wheel, mats, kind == "fallen" or g == "ruin", rng)
		if g == "up":
			(out["wheels"] as Array).append(wheel)
			_wheel_future(wheel, mats, true)
		if kind == "fallen":
			_wheel_future(wheel, mats, false)
	# Futuristic: wind-catcher tower, roof planters, vines along the raised boom.
	var fb := OchreProps.Batch.new()
	var terra: Material = mats["terra"]
	if kind != "fallen":
		fb.box(Vector3(-3.0, 24.0, 0), Vector3(5.0, 12.0, 5.0), terra)
		for i: int in 5:
			for s: int in 4:
				var a: float = s * PI * 0.5
				fb.box(Vector3(-3.0, 0, 0) + Vector3(cos(a) * 2.55, 27.0 + i * 0.6, sin(a) * 2.55), Vector3(0.12, 0.25, 3.8) if s % 2 == 0 else Vector3(3.8, 0.25, 0.12), mats["cream"])
		fb.box(Vector3(-3.0, 30.4, 0), Vector3(5.8, 0.5, 5.8), mats["cream"])
		fb.box(Vector3(-3.0, 30.7, 0), Vector3(5.9, 0.06, 5.9), mats["line"])
		var tip_up: Vector3 = boom_tip(9.0)
		for i: int in 9:
			var p: Vector3 = PIVOT.lerp(tip_up, 0.1 + i * 0.09) + Vector3(0, -1.7, rng.randf_range(-1.6, 1.6))
			var ln: float = rng.randf_range(2.0, 6.0)
			fb.beam(p, p + Vector3(rng.randf_range(-0.4, 0.4), -ln, 0), 0.22, mats["leaf"])
			fb.add(ProcMesh.sphere(0.8, 8, 4), ProcMesh.xf(p + Vector3(0, -ln, 0)), mats["leaf"])
		fb.beam(PIVOT + Vector3(0, 1.75, 1.7), tip_up + Vector3(0, 1.25, 1.25), 0.07, mats["line"])
		fb.beam(PIVOT + Vector3(0, 1.75, -1.7), tip_up + Vector3(0, 1.25, -1.25), 0.07, mats["line"])
	for x: float in [-7.5, -1.5, 4.5]:
		var y: float = 15.15
		fb.box(Vector3(x, y + 0.4, 4.4), Vector3(4.6, 0.8, 1.2), terra)
		for k: int in 3:
			fb.add(ProcMesh.sphere(0.9, 8, 4), ProcMesh.xf(Vector3(x - 1.4 + k * 1.4, y + 1.1, 4.4), Vector3.ZERO, Vector3(1.0, 0.8, 0.8)), mats["leaf"])
	fb.flush(nodes["future"], true, 1200.0)
	return out


## The wheel: two rims, spokes, a hub and the buckets (a few lost while ruined).
static func _wheel(wheel: Node3D, mats: Dictionary, ruined: bool, rng: RandomNumberGenerator) -> void:
	var b := OchreProps.Batch.new()
	var segs: int = 24
	for side: float in [-1.3, 1.3]:
		for i: int in segs:
			var a0: float = TAU * i / segs
			var a1: float = TAU * (i + 1) / segs
			b.beam(Vector3(cos(a0), sin(a0), 0) * WHEEL_R + Vector3(0, 0, side), Vector3(cos(a1), sin(a1), 0) * WHEEL_R + Vector3(0, 0, side), 0.55, mats["paint"])
		for k: int in 8:
			var a: float = TAU * k / 8.0
			b.beam(Vector3(0, 0, side * 0.6), Vector3(cos(a), sin(a), 0) * (WHEEL_R - 0.3) + Vector3(0, 0, side), 0.4, mats["steel"])
	b.add(ProcMesh.cyl(1.6, 1.6, 3.6, 14), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), mats["steel"])
	for k: int in 16:
		if ruined and rng.randf() < 0.25:
			continue
		var a: float = TAU * k / 16.0
		var rad := Vector3(cos(a), sin(a), 0)
		var tan := Vector3(-sin(a), cos(a), 0)
		var bs := Basis(tan, rad, Vector3(0, 0, 1))
		b.box(rad * (WHEEL_R + 0.6), Vector3(2.6, 1.8, 3.0), mats["dark"], bs)
		b.box(rad * (WHEEL_R + 0.2) - tan * 1.2, Vector3(0.3, 2.4, 3.1), mats["paint"], bs)
		b.box(rad * (WHEEL_R + 1.5) + tan * 1.1, Vector3(0.5, 0.35, 3.2), mats["steel"], bs)
		b.beam(rad * (WHEEL_R - 0.4), rad * (WHEEL_R + 1.3) - tan * 1.3, 0.12, mats["steel"])
		for t: int in 3:
			b.add(ProcMesh.cyl(0.05, 0.22, 0.8, 4), Transform3D(bs, rad * (WHEEL_R + 1.8) + tan * 1.0 + Vector3(0, 0, -0.9 + t * 0.9)), mats["steel"])
	b.flush(wheel, true, 1600.0)


## Futuristic wheel: greenery spilling from every bucket and cream sail vanes between the spokes.
## The holder carries meta "future": the env shows it with the futuristic layer (set_level).
static func _wheel_future(wheel: Node3D, mats: Dictionary, vanes: bool) -> void:
	var holder := Node3D.new()
	holder.name = "WheelFuture"
	holder.set_meta("future", true)
	wheel.add_child(holder)
	var b := OchreProps.Batch.new()
	for k: int in 16:
		var a: float = TAU * k / 16.0 + 0.1
		var rad := Vector3(cos(a), sin(a), 0)
		b.add(ProcMesh.sphere(1.25, 8, 4), ProcMesh.xf(rad * (WHEEL_R + 1.1), Vector3.ZERO, Vector3(1.0, 0.85, 1.25)), mats["leaf"])
	b.flush(holder, true, 1200.0)
	if vanes:
		for k: int in 8:
			var a0: float = TAU * k / 8.0
			var a1: float = a0 + TAU / 16.0
			var corners: Array[Vector3] = [Vector3(0, 0, 0.2), Vector3(cos(a0), sin(a0), 0) * (WHEEL_R - 0.5) + Vector3(0, 0, 0.2), Vector3(cos(a1), sin(a1), 0) * (WHEEL_R - 0.6) + Vector3(0, 0, 0.9)]
			var mi := MeshInstance3D.new()
			mi.mesh = OchreProps.sail_mesh(corners, 0.0)
			mi.material_override = mats["vane"]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			holder.add_child(mi)
