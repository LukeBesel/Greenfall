class_name KitProps
extends RefCounted
## [kit] Prop and greeble helpers (docs/ART_KIT.md). Every function ADDS geometry into a
## KitMesh.Builder so a whole building or site merges into a few draw calls.
## Conventions: t places the prop (origin on the ground, +Y up, front faces +Z); sizes in metres;
## state is "broken" | "repaired" | "restored"; material keys follow KitMat.for_key
## ("paint:main", "paint:accent", "paint:pipe", "steel", "dark_steel", "rusty", "hazard",
## "trim:warm", ...). "paint:<role>" keys are resolved through the palette given to KitMat.apply.

static func _x(pos: Vector3, rot: Vector3 = Vector3.ZERO) -> Transform3D:
	return KitMesh.xf(pos, rot)


## Pipe run through pts (local to t) with rounded elbows, flanges at every joint and both ends,
## and little support feet where the pipe runs low.
static func pipe_run(b: KitMesh.Builder, t: Transform3D, pts: PackedVector3Array, radius: float = 0.12, key: String = "paint:pipe", flanges: bool = true) -> void:
	var wp := PackedVector3Array()
	for p: Vector3 in pts:
		wp.append(t * p)
	b.tube(key, wp, radius, 12, radius * 3.0)
	if not flanges:
		return
	for i: int in pts.size():
		var d: Vector3
		if i < pts.size() - 1:
			d = pts[i + 1] - pts[i]
		else:
			d = pts[i] - pts[i - 1]
		var at: Vector3 = pts[i]
		if i > 0 and i < pts.size() - 1:
			# flange just after the elbow
			at = pts[i] + d.normalized() * minf(radius * 4.5, d.length() * 0.4)
		elif i == pts.size() - 1:
			at = pts[i] - d.normalized() * 0.04
		var ft: Transform3D = t * KitMesh.look_y(at - d.normalized() * 0.04, d)
		b.add("dark_steel", KitMesh.bevel_cylinder(radius * 1.45, 0.08, 0.015, 12), ft)
		if pts[i].y < 1.2 and pts[i].y > radius * 1.5:
			b.box("dark_steel", Vector3(0.08, pts[i].y - radius, 0.3), t * _x(Vector3(pts[i].x, (pts[i].y - radius) * 0.5, pts[i].z)), 0.015)


## Hanging cable between a and c (local to t) sagging by `sag` metres.
static func cable(b: KitMesh.Builder, t: Transform3D, a: Vector3, c: Vector3, sag: float = 0.5, radius: float = 0.025) -> void:
	var pts := PackedVector3Array()
	for k: int in 13:
		var f: float = float(k) / 12.0
		var p: Vector3 = a.lerp(c, f)
		p.y -= sag * 4.0 * f * (1.0 - f)
		pts.append(t * p)
	b.tube("rubber", pts, radius, 6)


## Louvred vent box (wall or roof). size: width x height (depth is 0.25).
static func vent(b: KitMesh.Builder, t: Transform3D, size: Vector2 = Vector2(0.9, 0.6), key: String = "paint:accent") -> void:
	b.box(key, Vector3(size.x, size.y, 0.22), t * _x(Vector3(0, size.y * 0.5, 0)), 0.035)
	b.box("dark_steel", Vector3(size.x - 0.14, size.y - 0.14, 0.05), t * _x(Vector3(0, size.y * 0.5, 0.1)), 0.01)
	var n: int = maxi(2, int(size.y / 0.11))
	for k: int in n:
		var y: float = 0.1 + (size.y - 0.2) * (k + 0.5) / n
		b.box("steel", Vector3(size.x - 0.18, 0.025, 0.09), t * _x(Vector3(0, y, 0.13), Vector3(-35, 0, 0)), 0.006)


## Railing from a to c (local to t): posts every ~1.2 m, top and mid rails, toe board.
static func railing(b: KitMesh.Builder, t: Transform3D, a: Vector3, c: Vector3, height: float = 1.0, key: String = "paint:rail", state: String = "repaired") -> void:
	var l: float = a.distance_to(c)
	var n: int = maxi(1, ceili(l / 1.2))
	var broken: bool = state == "broken"
	var up := Vector3(0, height, 0)
	for k: int in n + 1:
		var p: Vector3 = a.lerp(c, float(k) / n)
		var top: Vector3 = p + up
		if broken and b.rng.randf() < 0.25:
			top = p + Vector3(b.rng.randf_range(-0.3, 0.3), height * 0.8, b.rng.randf_range(-0.3, 0.3))
		b.rod(key, t * p, t * top, 0.03, 8)
	if not (broken and b.rng.randf() < 0.4):
		b.rod(key, t * (a + up), t * (c + up), 0.032, 8)
	b.rod(key, t * (a + up * 0.5), t * (c + up * 0.5), 0.022, 6)
	var mid: Vector3 = (a + c) * 0.5
	var dir: Vector3 = c - a
	b.box(key, Vector3(l, 0.1, 0.02), t * Transform3D(Basis(Vector3.UP, atan2(-dir.z, dir.x)), mid + Vector3(0, 0.06, 0)), 0.008)


## Ladder up the +Z face of something: two rails and rungs, safety cage above 2.5 m.
static func ladder(b: KitMesh.Builder, t: Transform3D, height: float, key: String = "paint:rail") -> void:
	for sx: float in [-0.22, 0.22]:
		b.rod(key, t * Vector3(sx, 0, 0.15), t * Vector3(sx, height + 0.8, 0.15), 0.025, 6)
		b.box("dark_steel", Vector3(0.05, 0.05, 0.16), t * _x(Vector3(sx, height * 0.5, 0.07)), 0.01)
	var n: int = int(height / 0.3)
	for k: int in n:
		b.rod("steel", t * Vector3(-0.22, 0.3 * (k + 1), 0.15), t * Vector3(0.22, 0.3 * (k + 1), 0.15), 0.017, 6)
	if height > 2.5:
		var hoops: int = int((height - 2.2) / 0.7)
		for k: int in hoops + 1:
			var y: float = 2.2 + k * 0.7
			var arc := PackedVector3Array()
			for s: int in 9:
				var a: float = PI * float(s) / 8.0
				arc.append(t * Vector3(cos(a) * 0.36, y, 0.15 + sin(a) * 0.4))
			b.tube(key, arc, 0.016, 5)
		for s: int in 3:
			var a2: float = PI * (0.2 + 0.3 * s)
			b.rod(key, t * Vector3(cos(a2) * 0.36, 2.2, 0.15 + sin(a2) * 0.4), t * Vector3(cos(a2) * 0.36, 2.2 + hoops * 0.7, 0.15 + sin(a2) * 0.4), 0.014, 5)


## Stairs climbing +Z by `run` to `height`, width w, with stringers and railings.
static func stairs(b: KitMesh.Builder, t: Transform3D, height: float, run: float, w: float = 1.0, key: String = "paint:rail", state: String = "repaired") -> void:
	var n: int = maxi(2, int(height / 0.2))
	var dz: float = run / n
	var dy: float = height / n
	for k: int in n:
		b.box("dark_steel", Vector3(w, 0.05, dz + 0.04), t * _x(Vector3(0, dy * (k + 1) - 0.03, dz * (k + 0.5))), 0.012)
		b.box("hazard", Vector3(w, 0.052, 0.06), t * _x(Vector3(0, dy * (k + 1) - 0.03, dz * (k + 1) - 0.02)), 0.01)
	var ang: float = atan2(height, run)
	var sl: float = sqrt(height * height + run * run)
	for sx: float in [-w * 0.5 - 0.04, w * 0.5 + 0.04]:
		b.box(key, Vector3(0.07, 0.24, sl), t * Transform3D(Basis(Vector3.RIGHT, -ang), Vector3(sx, height * 0.5, run * 0.5)), 0.02)
		railing(b, t, Vector3(sx, 0.1, 0.1), Vector3(sx, height, run), 0.95, key, state)


## Lattice antenna mast with crossbars, a small dish and a beacon (trim:red) on top.
static func antenna(b: KitMesh.Builder, t: Transform3D, height: float = 6.0, state: String = "repaired") -> void:
	var lean := Transform3D.IDENTITY
	if state == "broken":
		lean = Transform3D(Basis(Vector3(1, 0, 0.4).normalized(), deg_to_rad(9.0)), Vector3.ZERO)
	var tt: Transform3D = t * lean
	var r: float = 0.28
	var legs: Array[Vector3] = []
	for k: int in 3:
		var a: float = TAU * k / 3.0
		legs.append(Vector3(cos(a) * r, 0, sin(a) * r))
	b.box("concrete", Vector3(1.0, 0.3, 1.0), t * _x(Vector3(0, 0.15, 0)), 0.06)
	for k: int in 3:
		var top: Vector3 = legs[k] * 0.35 + Vector3(0, height, 0)
		b.rod("paint:rail", tt * (legs[k] + Vector3(0, 0.3, 0)), tt * top, 0.035, 6)
	var seg: int = int(height / 0.9)
	for s: int in seg:
		var f0: float = float(s) / seg
		var f1: float = float(s + 1) / seg
		for k: int in 3:
			var a0: Vector3 = legs[k].lerp(legs[k] * 0.35, f0) + Vector3(0, 0.3 + (height - 0.3) * f0, 0)
			var b1: Vector3 = legs[(k + 1) % 3].lerp(legs[(k + 1) % 3] * 0.35, f1) + Vector3(0, 0.3 + (height - 0.3) * f1, 0)
			b.rod("steel", tt * a0, tt * b1, 0.014, 4)
	b.rod("steel", tt * Vector3(0, height, 0), tt * Vector3(0, height + 1.2, 0), 0.025, 6)
	for k: int in 2:
		var y: float = height * (0.55 + 0.25 * k)
		b.rod("steel", tt * Vector3(-0.6, y, 0), tt * Vector3(0.6, y, 0), 0.02, 5)
	b.add("trim:red", KitMesh.bevel_cylinder(0.07, 0.12, 0.02, 10), tt * _x(Vector3(0, height + 1.2, 0)), 0.5, 0.0)
	dish(b, tt * _x(Vector3(0, height * 0.7, 0.25), Vector3(0, 0, 0)), 0.45, state, false)


## Satellite dish. radius = dish radius. pedestal: true for a ground-standing dish with a yoke.
static func dish(b: KitMesh.Builder, t: Transform3D, radius: float = 1.2, state: String = "repaired", pedestal: bool = true) -> void:
	var aim := Vector3(-35, 0, 0) if state != "broken" else Vector3(-80, 0, 25)
	var h: float = 0.0
	if pedestal:
		h = radius * 1.3
		b.cyl("paint:accent", radius * 0.35, h * 0.6, t, 0.04, 14)
		b.cyl("dark_steel", radius * 0.25, h * 0.4, t * _x(Vector3(0, h * 0.6, 0)), 0.03, 12)
		b.box("paint:accent", Vector3(radius * 0.9, 0.18, 0.3), t * _x(Vector3(0, h, 0)), 0.04)
	var dt: Transform3D = t * _x(Vector3(0, h + radius * 0.15, 0), aim) * _x(Vector3(0, 0, 0), Vector3(90, 0, 0)) * _x(Vector3(0, 0, 0), Vector3(180, 0, 0))
	# paraboloid shell, open side +Y in dish space (lathe profile: inside then outside)
	var p := PackedVector3Array()
	var steps: int = 6
	for k: int in steps + 1:
		var r: float = radius * float(k) / steps
		p.append(Vector3(r, r * r / (radius * 2.2), 0.0 if k < steps else 1.0))
	for k: int in range(steps, -1, -1):
		var r: float = radius * float(k) / steps
		p.append(Vector3(r, r * r / (radius * 2.2) - 0.05, 1.0 if k == steps else 0.0))
	# reverse order so the inner surface faces up (lathe normals follow profile direction)
	var rp := PackedVector3Array()
	for k: int in range(p.size() - 1, -1, -1):
		rp.append(p[k])
	b.add("paint:main", KitMesh.lathe(rp, 20), dt)
	# rim and feed
	var fy: float = radius * 0.75
	for k: int in 3:
		var a: float = TAU * k / 3.0
		b.rod("steel", dt * Vector3(cos(a) * radius * 0.85, radius * 0.33, sin(a) * radius * 0.85), dt * Vector3(0, fy, 0), 0.012, 4)
	b.add("dark_steel", KitMesh.bevel_cylinder(0.07, 0.16, 0.02, 10), dt * _x(Vector3(0, fy - 0.08, 0)))


## Storage tank: capsule body with bands, stubby legs, top hatch. key: body paint key.
static func tank(b: KitMesh.Builder, t: Transform3D, radius: float = 1.4, height: float = 3.5, key: String = "paint:main", state: String = "repaired") -> void:
	var p := PackedVector3Array()
	var base: float = 0.5
	p.append(Vector3(0, base, 0))
	p.append_array(KitMesh.arc(Vector2(radius - 0.35, base + 0.35), 0.35, -90, 0, 3))
	p.append(Vector3(radius, base + 0.45, 0))
	p.append(Vector3(radius, base + height - 0.6, 0))
	p.append_array(KitMesh.arc(Vector2(0, base + height - radius * 0.55), radius, 0, 90, 6))
	# squash the top dome: replace by elliptical points
	var dome := PackedVector3Array()
	for q: Vector3 in p:
		if q.y > base + height - radius * 0.55:
			var f: float = (q.y - (base + height - radius * 0.55)) / radius
			q.y = base + height - radius * 0.55 + f * radius * 0.55
			q.z = 1.0 if q.x > radius * 0.995 else 0.0
		dome.append(q)
	b.add(key, KitMesh.lathe(dome, 24), t)
	for k: int in 3:
		var y: float = base + 0.6 + (height - 1.4) * (k / 2.0)
		b.add("paint:accent", KitMesh.bevel_cylinder(radius + 0.05, 0.14, 0.03, 24), t * _x(Vector3(0, y, 0)))
	for k: int in 4:
		var a: float = TAU * (k + 0.5) / 4.0
		var lp: Vector3 = Vector3(cos(a), 0, sin(a)) * radius * 0.72
		b.box("dark_steel", Vector3(0.22, base + 0.4, 0.22), t * _x(lp + Vector3(0, (base + 0.4) * 0.5, 0)), 0.03)
		b.box("concrete", Vector3(0.5, 0.12, 0.5), t * _x(lp + Vector3(0, 0.06, 0)), 0.03)
	b.cyl("dark_steel", 0.32, 0.18, t * _x(Vector3(0, base + height - 0.02, 0)), 0.04, 14)
	b.decal("num_0%d" % (1 + b.rng.randi() % 4), Vector2(0.8, 0.8), t * _x(Vector3(0, base + height * 0.45, radius + 0.04)))
	if state == "broken":
		b.box("rusty", Vector3(0.7, 0.5, 0.06), t * _x(Vector3(radius * 0.7, base + 1.2, radius * 0.72), Vector3(0, 45, 15)), 0.02)


## Solar panel on a post, tilted towards +Z sky. size: panel width x depth.
static func solar_panel(b: KitMesh.Builder, t: Transform3D, size: Vector2 = Vector2(2.0, 1.2), state: String = "repaired", post: float = 1.0) -> void:
	var tilt: float = -28.0 if state != "broken" else -55.0
	if post > 0.0:
		b.cyl("dark_steel", 0.07, post, t, 0.015, 8)
	var pt: Transform3D = t * _x(Vector3(0, post + 0.05, 0), Vector3(tilt, 0, 0 if state != "broken" else 14))
	b.box("paint:accent", Vector3(size.x + 0.08, 0.08, size.y + 0.08), pt, 0.025)
	var cells: Transform3D = pt * _x(Vector3(0, 0.045, 0), Vector3(-90, 0, 0))
	if state == "broken":
		b.decal("solar_cells", Vector2(size.x * 0.48, size.y), cells * _x(Vector3(-size.x * 0.25, 0, 0)))
	else:
		b.decal("solar_cells", Vector2(size.x, size.y), cells)


## Door/hatch in a wall facing +Z, bottom centre at t. Frame, panel with window, hazard sill,
## handle, and a small lamp above (trim:warm + a light when powered).
static func hatch(b: KitMesh.Builder, t: Transform3D, size: Vector2 = Vector2(1.2, 2.2), state: String = "repaired", key: String = "paint:accent") -> void:
	var w: float = size.x
	var h: float = size.y
	b.box("dark_steel", Vector3(w + 0.36, 0.2, 0.3), t * _x(Vector3(0, h + 0.1, 0.0)), 0.05)
	for sx: float in [-1.0, 1.0]:
		b.box("dark_steel", Vector3(0.18, h + 0.1, 0.3), t * _x(Vector3(sx * (w * 0.5 + 0.09), h * 0.5, 0.0)), 0.05)
	b.box("hazard", Vector3(w + 0.36, 0.12, 0.4), t * _x(Vector3(0, 0.06, 0.05)), 0.03)
	var open: float = 0.0 if state != "broken" else 0.0
	var tilt := Vector3(0, 0, 0) if state != "broken" else Vector3(4, 0, -3)
	b.box(key, Vector3(w - 0.04, h - 0.06, 0.12), t * _x(Vector3(open, h * 0.5 + 0.02, -0.02), tilt), 0.04, 2)
	b.box(key, Vector3(w - 0.3, 0.08, 0.05), t * _x(Vector3(0, h * 0.32, 0.06), tilt), 0.015)
	b.box("dark_steel", Vector3(w * 0.55, h * 0.26, 0.05), t * _x(Vector3(0, h * 0.72, 0.045), tilt), 0.03)
	b.box("glass", Vector3(w * 0.48, h * 0.2, 0.05), t * _x(Vector3(0, h * 0.72, 0.06), tilt), 0.02)
	b.box("steel", Vector3(0.06, 0.28, 0.06), t * _x(Vector3(w * 0.36, h * 0.48, 0.08), tilt), 0.015)
	b.box("dark_steel", Vector3(0.4, 0.12, 0.22), t * _x(Vector3(0, h + 0.3, 0.12)), 0.03)
	b.box("trim:warm", Vector3(0.3, 0.04, 0.12), t * _x(Vector3(0, h + 0.23, 0.16)), 0.01)
	b.lights.append({"pos": t * Vector3(0, h + 0.1, 0.5), "color": KitMat.GLOW["warm"], "range": 4.5, "energy": 1.2})


## Lamp post. Broken: bent pole, drooping head, dead lens. Working: warm lens + light.
static func lamp_post(b: KitMesh.Builder, t: Transform3D, height: float = 4.5, state: String = "repaired", glow: String = "warm") -> void:
	b.box("concrete", Vector3(0.6, 0.35, 0.6), t * _x(Vector3(0, 0.175, 0)), 0.06, 2)
	var bend := Transform3D.IDENTITY
	if state == "broken":
		bend = Transform3D(Basis(Vector3(0.3, 0, 1).normalized(), deg_to_rad(14.0)), Vector3(0, 0.35, 0))
	var pt: Transform3D = t * _x(Vector3(0, 0.35, 0)) * bend
	var p := PackedVector3Array([Vector3(0, 0, 0), Vector3(0.14, 0, 1), Vector3(0.14, 0.5, 0), Vector3(0.1, 0.62, 1), Vector3(0.075, 0.7, 0), Vector3(0.06, height, 0), Vector3(0, height + 0.02, 0)])
	b.add("paint:pole", KitMesh.lathe(p, 12), pt)
	b.box("paint:pole", Vector3(0.12, 0.12, 0.9), pt * _x(Vector3(0, height - 0.05, 0.4)), 0.03)
	var head_rot := Vector3(0, 0, 0) if state != "broken" else Vector3(38, 0, 0)
	var ht: Transform3D = pt * _x(Vector3(0, height - 0.08, 0.85), head_rot)
	b.box("dark_steel", Vector3(0.42, 0.14, 0.62), ht, 0.05, 2)
	b.box("trim:" + glow, Vector3(0.32, 0.03, 0.48), ht * _x(Vector3(0, -0.075, 0)), 0.012)
	b.box("dark_steel", Vector3(0.18, 0.28, 0.1), pt * _x(Vector3(0, 1.1, 0.1)), 0.03)
	if state != "broken":
		b.lights.append({"pos": ht * Vector3(0, -0.4, 0), "color": KitMat.GLOW.get(glow, KitMat.GLOW["warm"]), "range": 9.0, "energy": 2.0})


## A crate: bevelled box with darker corner frames and a label decal.
static func crate(b: KitMesh.Builder, t: Transform3D, size: Vector3 = Vector3(0.9, 0.7, 0.9), key: String = "paint:crate") -> void:
	b.box(key, size, t * _x(Vector3(0, size.y * 0.5, 0)), 0.04, 2)
	for sy: float in [0.06, size.y - 0.06]:
		b.box("dark_steel", Vector3(size.x + 0.03, 0.08, size.z + 0.03), t * _x(Vector3(0, sy, 0)), 0.02)
	if b.rng.randf() < 0.6:
		b.decal(["arrow", "warn", "logo", "power"][b.rng.randi() % 4], Vector2(minf(size.x, size.y) * 0.5, minf(size.x, size.y) * 0.5), t * _x(Vector3(0, size.y * 0.5, size.z * 0.5 + 0.002)))


## Stack of n crates around t (seeded by the builder rng), toppled when broken.
static func crate_stack(b: KitMesh.Builder, t: Transform3D, n: int = 4, state: String = "repaired") -> void:
	var placed: Array[Vector3] = []
	var keys: PackedStringArray = ["paint:crate", "paint:accent", "paint:crate", "dark_steel"]
	for k: int in n:
		var s := Vector3(b.rng.randf_range(0.6, 1.0), b.rng.randf_range(0.5, 0.8), b.rng.randf_range(0.6, 1.0))
		var col: int = k % 3
		var pos := Vector3((col - 1) * 0.95, 0, b.rng.randf_range(-0.1, 0.1))
		if k >= 3:
			pos = Vector3(((k - 3) % 2 - 0.5) * 0.95, 0.75, 0)
		var rot := Vector3(0, b.rng.randf_range(-12, 12), 0)
		if state == "broken" and b.rng.randf() < 0.4:
			rot = Vector3(b.rng.randf_range(-20, 20), b.rng.randf() * 90, 70 if pos.y > 0 else 0)
			pos.y = 0.0
			pos.x += 1.0
		crate(b, t * _x(pos, rot), s, keys[k % keys.size()])
		placed.append(pos)


## Oil drum with ribs. tipped: lying on its side (broken sites).
static func barrel(b: KitMesh.Builder, t: Transform3D, key: String = "paint:barrel", tipped: bool = false) -> void:
	var tt: Transform3D = t
	if tipped:
		tt = t * _x(Vector3(0, 0.3, 0), Vector3(0, 0, 90)) * _x(Vector3(0, -0.45, 0))
	b.cyl(key, 0.3, 0.9, tt, 0.03, 14)
	for y: float in [0.3, 0.6]:
		b.add(key, KitMesh.bevel_cylinder(0.315, 0.04, 0.012, 14), tt * _x(Vector3(0, y, 0)))
	b.cyl("dark_steel", 0.05, 0.03, tt * _x(Vector3(0.15, 0.9, 0)), 0.01, 8)


## Raised planter with leafy bushes and flowers (restored sites). Empty dry soil when broken.
static func planter(b: KitMesh.Builder, t: Transform3D, length: float = 2.0, state: String = "restored") -> void:
	b.box("concrete", Vector3(length, 0.5, 0.7), t * _x(Vector3(0, 0.25, 0)), 0.06, 2)
	b.box("dirt", Vector3(length - 0.14, 0.04, 0.56), t * _x(Vector3(0, 0.49, 0)), 0.01)
	if state == "broken":
		return
	var n: int = int(length / 0.45)
	for k: int in n:
		var x: float = -length * 0.5 + (k + 0.5) * length / n
		var r: float = b.rng.randf_range(0.2, 0.32) * (1.0 if state == "restored" else 0.7)
		bush(b, t * _x(Vector3(x, 0.48, b.rng.randf_range(-0.08, 0.08))), r)
		if state == "restored" and b.rng.randf() < 0.6:
			var fk: String = ["paint:flower_a", "paint:flower_b", "paint:yellow"][b.rng.randi() % 3]
			b.add(fk, KitMesh.pebble(k % 4), t * _x(Vector3(x + 0.12, 0.48 + r * 1.4, 0.15)) * Transform3D(Basis().scaled(Vector3.ONE * 0.07), Vector3.ZERO), -1.0, 0.0)


## Leafy blob (lumpy sphere) of radius r sitting on t.
static func bush(b: KitMesh.Builder, t: Transform3D, r: float = 0.3) -> void:
	var p := PackedVector3Array()
	for k: int in 7:
		var a: float = lerpf(-80.0, 90.0, k / 6.0)
		var rr: float = r * (1.0 + 0.12 * sin(k * 2.3))
		p.append(Vector3(cos(deg_to_rad(a)) * rr, r * 0.8 + sin(deg_to_rad(a)) * rr * 0.9, 0))
	p[0] = Vector3(0, p[0].y, 0)
	p[6] = Vector3(0, p[6].y, 0)
	b.add("leaves", KitMesh.lathe(p, 9), t * _x(Vector3.ZERO, Vector3(0, b.rng.randf() * 90, 0)), -1.0, 0.6)


## Scattered junk for broken sites: plates, pipes, tyres around t within radius.
static func debris(b: KitMesh.Builder, t: Transform3D, radius: float = 4.0, n: int = 12) -> void:
	for k: int in n:
		var a: float = b.rng.randf() * TAU
		var d: float = sqrt(b.rng.randf()) * radius
		var p := Vector3(cos(a) * d, 0.02, sin(a) * d)
		var rot := Vector3(b.rng.randf_range(-25, 25), b.rng.randf() * 180, b.rng.randf_range(-25, 25))
		match k % 4:
			0:
				b.box("rusty", Vector3(b.rng.randf_range(0.4, 1.2), 0.04, b.rng.randf_range(0.3, 0.8)), t * _x(p, rot), 0.012)
			1:
				b.add("rusty", KitMesh.bevel_cylinder(0.08, b.rng.randf_range(0.6, 1.4), 0.02, 8), t * _x(p + Vector3(0, 0.08, 0), Vector3(90, rot.y, 0)))
			2:
				b.add("rubber", KitMesh.lathe(PackedVector3Array([Vector3(0.18, -0.1, 0), Vector3(0.3, -0.1, 1), Vector3(0.34, 0, 1), Vector3(0.3, 0.1, 1), Vector3(0.18, 0.1, 0), Vector3(0.18, -0.1, 0)]), 14), t * _x(p + Vector3(0, 0.1, 0), Vector3(b.rng.randf_range(-10, 10), 0, b.rng.randf_range(-10, 10))))
			_:
				b.box("paint:main", Vector3(b.rng.randf_range(0.3, 0.7), 0.05, b.rng.randf_range(0.3, 0.6)), t * _x(p, rot), 0.015)


## Wind turbine TOWER (static, into the builder): tapered painted mast with bands, concrete
## foot, service door, ladder cage and a chunky nacelle. Pair it with turbine_rotor() on a
## separate MeshInstance3D at turbine_hub(height) so the rotor can spin (only when powered).
## Replaces the rejected "plain white CG turbine".
static func wind_turbine(b: KitMesh.Builder, t: Transform3D, height: float = 12.0, state: String = "repaired") -> void:
	b.add("concrete", KitMesh.bevel_cylinder(1.6, 0.6, 0.1, 8), t * _x(Vector3.ZERO, Vector3(0, 22.5, 0)))
	var lean := Vector3(0, 0, 3.0) if state == "broken" else Vector3.ZERO
	var tt: Transform3D = t * _x(Vector3(0, 0.6, 0), lean)
	var p := PackedVector3Array([Vector3(0, 0, 0), Vector3(0.95, 0, 1), Vector3(0.95, 0.3, 1), Vector3(0.8, 0.5, 0), Vector3(0.45, height - 0.6, 0), Vector3(0.5, height - 0.5, 1), Vector3(0.5, height, 1), Vector3(0, height, 0)])
	b.add("paint:main", KitMesh.lathe(p, 16), tt)
	for k: int in 3:
		var y: float = 1.2 + k * (height - 2.5) / 2.0
		var r: float = lerpf(0.82, 0.48, y / height) + 0.04
		b.add("paint:accent", KitMesh.bevel_cylinder(r, 0.28, 0.05, 16), tt * _x(Vector3(0, y, 0)))
	hatch(b, tt * _x(Vector3(0, 0.0, 0.78)), Vector2(0.8, 1.7), state)
	# nacelle
	var nt: Transform3D = tt * _x(Vector3(0, height, 0))
	b.box("paint:main", Vector3(1.1, 1.0, 2.6), nt * _x(Vector3(0, 0.5, -0.3)), 0.3, 2)
	b.box("paint:accent", Vector3(1.14, 0.22, 2.64), nt * _x(Vector3(0, 0.55, -0.3)), 0.08)
	vent(b, nt * _x(Vector3(0.58, 0.3, -0.9), Vector3(0, 90, 0)), Vector2(0.8, 0.4), "paint:main")
	b.add("trim:red", KitMesh.bevel_cylinder(0.08, 0.12, 0.02, 8), nt * _x(Vector3(0, 1.0, -1.2)))
	b.rod("steel", nt * Vector3(-0.3, 1.0, -1.4), nt * Vector3(-0.3, 1.7, -1.4), 0.03)


## Rotor hub position (local to the turbine's t) for turbine_rotor().
static func turbine_hub(height: float = 12.0) -> Vector3:
	return Vector3(0, 0.6 + height + 0.5, 1.15)


## Spinning rotor (cached ArrayMesh, faces +Z, spin around local Z). Three chunky blades with
## accent tips; broken: one blade snapped, one bent.
static func turbine_rotor(state: String = "repaired", blade: float = 5.0, palette: Dictionary = {}) -> ArrayMesh:
	return KitMesh.cached("rotor:%s:%.1f:%d" % [state, blade, palette.hash()], func() -> Resource:
		var b := KitMesh.Builder.new(5, palette, state)
		var cone := PackedVector3Array([Vector3(0, -0.1, 0), Vector3(0.48, -0.1, 1), Vector3(0.5, 0.2, 0), Vector3(0.3, 0.75, 0), Vector3(0, 0.9, 0)])
		b.add("paint:accent", KitMesh.lathe(cone, 16), _x(Vector3.ZERO, Vector3(90, 0, 0)))
		for k: int in 3:
			if state == "broken" and k == 2:
				b.box("rusty", Vector3(0.5, 0.9, 0.12), _x(Vector3(0, 0.7, 0), Vector3(0, 0, 120 * k)) * _x(Vector3(0, 0.0, 0)), 0.03)
				continue
			var bend := Vector3(0, 0, 0) if not (state == "broken" and k == 1) else Vector3(25, 0, 0)
			var bt: Transform3D = _x(Vector3.ZERO, Vector3(0, 0, 120 * k)) * _x(Vector3(0, 0.4, 0), bend)
			# blade = 3 tapered bevelled segments with a twist, accent tip
			var segs: int = 3
			for s: int in segs:
				var f0: float = float(s) / segs
				var w: float = lerpf(0.55, 0.22, f0)
				var l: float = blade / segs
				var key: String = "paint:main" if s < segs - 1 else "paint:accent"
				b.box(key, Vector3(w, l + 0.04, 0.12), bt * _x(Vector3(0.08 * (1.0 - f0), l * (s + 0.5), 0), Vector3(0, 12.0 - 6.0 * s, 0)), 0.05, 2)
		return b.commit()) as ArrayMesh
