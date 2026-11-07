class_name AnvilProps
extends RefCounted
## [planet-anvil] Anvil's structures, merged per material (FrontierView.Batch) into each stage
## group of AnvilEnv: foundry stacks and halls, conveyor gantries, the core shaft's headframe,
## half-buried mining haulers, ore carts on a rail spur, slag heaps; restored: vertical-garden
## shells and thin warm-white light rings on the stacks, wind turbines, domed greenhouses.

const Batch = FrontierView.Batch
const LINE := Color(1.0, 0.88, 0.7)

static var _box_mesh: BoxMesh


static func box() -> BoxMesh:
	if _box_mesh == null:
		_box_mesh = ProcMesh.box(Vector3.ONE)
	return _box_mesh


static func add_box(b: Batch, pos: Vector3, size: Vector3, m: Material, rot_deg: Vector3 = Vector3.ZERO) -> void:
	b.add(box(), Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)) * Basis.from_scale(size), pos), m)


static func add_beam(b: Batch, a: Vector3, c: Vector3, thick: float, m: Material) -> void:
	b.add(box(), FrontierView._beam_xf(a, c, thick), m)


static func add_cyl(b: Batch, pos: Vector3, r_top: float, r_bot: float, h: float, m: Material, segs: int = 24, basis: Basis = Basis()) -> void:
	b.add(ProcMesh.cyl(r_top, r_bot, h, segs), Transform3D(basis, pos), m)


static func make_mat(env: AnvilEnv, key: String) -> Material:
	match key:
		"stack":
			var s: ShaderMaterial = Mats.worn_paint(Color(0.36, 0.31, 0.28), 0.35, 0.95, 3.0, 0.8)
			s.set_shader_parameter("tex_scale", 0.22)
			return s
		"hauler":
			var h: ShaderMaterial = Mats.worn_paint(Color(0.82, 0.55, 0.14), 0.45, 0.85, 7.0, 0.7)
			h.set_shader_parameter("tex_scale", 0.5)
			return h
		"cart":
			var c: ShaderMaterial = Mats.worn_paint(Color(0.3, 0.34, 0.3), 0.4, 0.9, 11.0, 0.7)
			c.set_shader_parameter("tex_scale", 0.9)
			return c
		"rust":
			return AssetLib.pbr_material("rusty_metal_03", 0.12, Color(0.92, 0.62, 0.5), true)
		"corr":
			return AssetLib.pbr_material("corrugated_iron", 0.18, Color(0.75, 0.42, 0.3), true)
		"concrete":
			return AssetLib.pbr_material("concrete_wall_008", 0.06, Color(0.82, 0.62, 0.54), true)
		"soot":
			var so := StandardMaterial3D.new()
			so.albedo_color = Color(0.06, 0.05, 0.045)
			so.roughness = 0.95
			return so
		"tyre":
			return Mats.rubber(Color(0.09, 0.06, 0.05))
		"ore":
			var o := StandardMaterial3D.new()
			o.albedo_color = Color(0.2, 0.12, 0.09)
			o.roughness = 0.8
			o.metallic = 0.3
			return o
		"white":
			var w := StandardMaterial3D.new()
			w.albedo_color = Color(0.9, 0.9, 0.88)
			w.roughness = 0.3
			w.clearcoat_enabled = true
			w.clearcoat = 0.4
			return w
		"glass":
			var g := StandardMaterial3D.new()
			g.albedo_color = Color(0.86, 0.93, 0.95, 0.16)
			g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			g.roughness = 0.05
			g.metallic = 0.2
			g.cull_mode = BaseMaterial3D.CULL_DISABLED
			return g
		"line":
			# Thin warm-white light line: visible, never neon.
			var l := StandardMaterial3D.new()
			l.albedo_color = LINE
			l.emission_enabled = true
			l.emission = LINE
			l.emission_energy_multiplier = 0.9
			l.roughness = 0.3
			return l
		"green":
			var gr := AssetLib.pbr_material("leafy_grass", 0.35, Color(0.5, 0.78, 0.4), true)
			gr.metallic = 0.0
			return gr
		"redleaf":
			var rl := AssetLib.pbr_material("leafy_grass", 0.35, Color(1.05, 0.3, 0.24), true)
			rl.metallic = 0.0
			return rl
		"terrain":
			return env.terrain_mat
		"slag":
			return env.slag_mat
	return StandardMaterial3D.new()


## Where the stacks stand (before the terrain is built: it flattens their pads).
static func stack_plan(_env: AnvilEnv) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var defs: Array = [
		[-PI * 0.5 - 0.2, 330.0, 150.0, 10.0], [-PI * 0.5 - 0.06, 385.0, 175.0, 12.0],
		[-PI * 0.5 + 0.62, 345.0, 125.0, 9.0], [-PI * 0.5 + 0.76, 290.0, 100.0, 7.5],
		[-PI * 0.5 - 0.42, 250.0, 88.0, 6.5], [PI * 0.82, 430.0, 120.0, 8.5], [PI * 0.08, 410.0, 110.0, 8.0],
	]
	for d: Array in defs:
		out.append({"pos": AnvilEnv.polar(float(d[0]), float(d[1])), "h": float(d[2]), "r": float(d[3])})
	return out


static func build_all(env: AnvilEnv) -> void:
	var g: Dictionary = env.groups
	var always := Batch.new()
	var fut := Batch.new()
	var high := Batch.new()
	var up := Batch.new()
	var ruin := Batch.new()
	for i: int in env.stacks.size():
		var s: Dictionary = env.stacks[i]
		var p: Vector3 = s["pos"]
		p.y = env.height(p.x, p.z)
		s["pos"] = p
		_stack(env, always, fut, p, float(s["h"]), float(s["r"]), i)
	_halls(env, always, fut)
	_gantries(env, always, fut)
	_headframe(env, always, fut)
	_haulers(env, always, high)
	_ore_spur(env, always)
	_slag_heaps(env, always)
	_ruin_debris(env, ruin)
	_domes(env, high, fut)
	always.flush(g["always"])
	fut.flush(g["future"])
	high.flush(g["high"])
	ruin.flush(g["ruin"])
	_turbines(env, up, fut)
	up.flush(g["up"])


# --- Foundry --------------------------------------------------------------------------------

static func _stack(env: AnvilEnv, b: Batch, fut: Batch, base: Vector3, h: float, r: float, idx: int) -> void:
	var stack_m: Material = env.mat("stack")
	var rust: Material = env.mat("rust")
	var top_r: float = r * 0.8
	add_box(b, base + Vector3(0, 3.0, 0), Vector3(r * 2.8, 8.0, r * 2.8), env.mat("concrete"))
	add_cyl(b, base + Vector3(0, 6.0 + h * 0.5, 0), top_r, r, h, stack_m, 28)
	var bands: int = int(h / 14.0)
	for k: int in bands:
		var y: float = 12.0 + k * 14.0
		var rr: float = lerpf(r, top_r, y / h) + 0.35
		add_cyl(b, base + Vector3(0, 6.0 + y, 0), rr, rr, 1.1, rust, 28)
		if k % 2 == 1 and y < h - 10.0:
			# Vertical gardens: planted shells between the bands, thin light rings on them.
			var gm: Material = env.mat("green") if (k + idx) % 4 != 0 else env.mat("redleaf")
			add_cyl(fut, base + Vector3(0, 6.0 + y + 7.0, 0), rr + 0.25, rr + 0.35, 11.5, gm, 28)
		add_cyl(fut, base + Vector3(0, 6.0 + y + 0.75, 0), rr + 0.5, rr + 0.5, 0.14, env.mat("line"), 32)
	# Sooted crown, lip and two galleries with railings.
	add_cyl(b, base + Vector3(0, 6.0 + h - 4.0, 0), top_r + 0.05, top_r + 0.1, 8.0, env.mat("soot"), 28)
	add_cyl(b, base + Vector3(0, 6.0 + h, 0), top_r + 0.6, top_r + 0.6, 1.2, rust, 28)
	add_cyl(fut, base + Vector3(0, 6.0 + h + 0.7, 0), top_r + 0.7, top_r + 0.7, 0.16, env.mat("line"), 32)
	for gy_: float in [h * 0.38, h * 0.72]:
		var rr2: float = lerpf(r, top_r, gy_ / h)
		add_cyl(b, base + Vector3(0, 6.0 + gy_, 0), rr2 + 2.4, rr2 + 2.4, 0.5, rust, 28)
		add_cyl(fut, base + Vector3(0, 6.0 + gy_ + 0.5, 0), rr2 + 2.2, rr2 + 2.2, 0.5, env.mat("green"), 28)
		for k: int in 16:
			var a: float = TAU * k / 16.0
			var q: Vector3 = base + Vector3(cos(a) * (rr2 + 2.3), 6.0 + gy_, sin(a) * (rr2 + 2.3))
			add_beam(b, q, q + Vector3(0, 1.3, 0), 0.12, rust)
	# Cage ladder up one side and a riser pipe on another.
	var side := Vector3(1, 0, 0).rotated(Vector3.UP, idx * 1.3)
	for k: int in 2:
		var off: Vector3 = side.rotated(Vector3.UP, 0.12 * (k * 2 - 1)) * (r + 0.6)
		add_beam(b, base + off + Vector3(0, 8.0, 0), base + off * (top_r / r) + Vector3(0, 6.0 + h, 0), 0.18, rust)
	var pside: Vector3 = side.rotated(Vector3.UP, 2.0)
	var pr: float = r * 0.2
	add_cyl(b, base + pside * (r + pr + 0.8) + Vector3(0, 6.0 + h * 0.35, 0), pr, pr, h * 0.7, stack_m, 12)
	for k: int in 6:
		var y2: float = 10.0 + k * h * 0.11
		add_beam(b, base + pside * (lerpf(r, top_r, y2 / h) - 0.2) + Vector3(0, 6.0 + y2, 0), base + pside * (r + pr + 0.8) + Vector3(0, 6.0 + y2, 0), 0.4, rust)


static func _halls(env: AnvilEnv, b: Batch, fut: Batch) -> void:
	# Long casting halls between stack pairs, sawtooth roofs, a few roof panels gone.
	var pairs: Array = [[0, 1], [2, 3], [0, 4]]
	for pr: Array in pairs:
		var s0: Vector3 = env.stacks[int(pr[0])]["pos"]
		var s1: Vector3 = env.stacks[int(pr[1])]["pos"]
		var mid: Vector3 = (s0 + s1) * 0.5
		var d: Vector3 = s1 - s0
		var yaw: float = atan2(-d.z, d.x)
		var len_: float = maxf(d.length() - 30.0, 30.0)
		var w: float = 30.0
		var hh: float = 22.0
		var basis := Basis(Vector3.UP, yaw)
		var y0: float = minf(env.height(mid.x, mid.z), minf(s0.y, s1.y))
		var c: Vector3 = Vector3(mid.x, y0, mid.z)
		b.add(box(), Transform3D(basis * Basis.from_scale(Vector3(len_, hh, w)), c + Vector3(0, hh * 0.5 - 1.0, 0)), env.mat("corr"))
		var teeth: int = int(len_ / 9.0)
		for k: int in teeth:
			if (k * 7 + int(pr[0])) % 5 == 2:
				continue
			var lx: float = -len_ * 0.5 + (k + 0.5) * len_ / teeth
			var tp: Vector3 = c + basis * Vector3(lx, hh + 2.2, 0)
			b.add(box(), Transform3D(basis * Basis(Vector3.FORWARD, 0.45) * Basis.from_scale(Vector3(len_ / teeth * 1.05, 0.5, w)), tp), env.mat("rust"))
			b.add(box(), Transform3D(basis * Basis.from_scale(Vector3(0.4, 4.2, w)), c + basis * Vector3(lx + len_ / teeth * 0.45, hh + 1.9, 0)), env.mat("stack"))
		# Restored: a thin light line along each eave.
		for sgn: float in [-1.0, 1.0]:
			fut.add(box(), Transform3D(basis * Basis.from_scale(Vector3(len_, 0.14, 0.14)), c + basis * Vector3(0, hh - 0.9, sgn * (w * 0.5 + 0.1))), env.mat("line"))


static func _truss(env: AnvilEnv, b: Batch, fut: Batch, a: Vector3, c: Vector3, deck: float) -> void:
	# A boxed conveyor truss from a to c at `deck` m over the ground, on A-frame bents.
	var rust: Material = env.mat("rust")
	var d: Vector3 = c - a
	var flat := Vector3(d.x, 0, d.z)
	var len_: float = flat.length()
	var fw: Vector3 = flat / maxf(len_, 0.001)
	var side: Vector3 = fw.cross(Vector3.UP).normalized()
	var ya: float = a.y + deck
	var yc: float = c.y + deck
	var segs: int = maxi(2, int(len_ / 5.0))
	for sx: float in [-1.6, 1.6]:
		for sy: float in [0.0, 2.8]:
			add_beam(b, Vector3(a.x, ya + sy, a.z) + side * sx, Vector3(c.x, yc + sy, c.z) + side * sx, 0.32, rust)
	for k: int in segs:
		var t0: float = float(k) / segs
		var t1: float = float(k + 1) / segs
		var p0: Vector3 = a + flat * t0 + Vector3(0, lerpf(ya, yc, t0) - a.y, 0)
		var p1: Vector3 = a + flat * t1 + Vector3(0, lerpf(ya, yc, t1) - a.y, 0)
		for sx: float in [-1.6, 1.6]:
			add_beam(b, p0 + side * sx, p1 + side * sx + Vector3(0, 2.8, 0), 0.16, rust)
		add_beam(b, p0 + Vector3(0, 2.8, 0) - side * 1.6, p0 + Vector3(0, 2.8, 0) + side * 1.6, 0.16, rust)
	add_beam(fut, Vector3(a.x, ya - 0.18, a.z) - side * 1.65, Vector3(c.x, yc - 0.18, c.z) - side * 1.65, 0.1, env.mat("line"))
	# Bents every ~26 m.
	var bents: int = maxi(1, int(len_ / 26.0))
	for k: int in bents + 1:
		var t: float = float(k) / bents
		var top: Vector3 = a + flat * t
		top.y = lerpf(ya, yc, t)
		var gnd: float = env.gy(top)
		if top.y - gnd < 2.0:
			continue
		for sx: float in [-1.0, 1.0]:
			add_beam(b, Vector3(top.x, gnd, top.z) + side * sx * 4.5, top + side * sx * 1.6, 0.55, rust)
		add_box(b, Vector3(top.x, gnd + 0.4, top.z), Vector3(3, 0.8, 3), env.mat("concrete"))


static func _gantries(env: AnvilEnv, b: Batch, fut: Batch) -> void:
	var hf: Vector3 = env.pit_c + Vector3(0, AnvilEnv.RIM_Y, 0)
	var to_pit: Vector3 = (Vector3(env.pit_c.x, 0, env.pit_c.z)).normalized()
	var rim: Vector3 = env.pit_c - to_pit * (AnvilEnv.PIT_R + 8.0)
	rim.y = AnvilEnv.RIM_Y
	# Stacks to the pit rim, and one long run from beside the base out to the rim.
	for i: int in [0, 2, 4]:
		var s: Vector3 = env.stacks[i]["pos"]
		var dir: Vector3 = (hf - s)
		dir.y = 0.0
		var start: Vector3 = s + dir.normalized() * (float(env.stacks[i]["r"]) * 2.0 + 6.0)
		start.y = env.gy(start)
		var end_: Vector3 = env.pit_c - dir.normalized() * (AnvilEnv.PIT_R + 10.0)
		end_.y = AnvilEnv.RIM_Y
		_truss(env, b, fut, start, end_, 16.0 + i * 2.0)
	var near := AnvilEnv.polar(-PI * 0.5 + 0.08, env.r_in + 14.0)
	near.y = env.gy(near)
	_truss(env, b, fut, near, rim, 14.0)


static func _headframe(env: AnvilEnv, b: Batch, fut: Batch) -> void:
	# Two lattice towers astride the shaft, a crown girder, the sheave wheel and cables.
	var c: Vector3 = env.pit_c
	var side := Vector3(1, 0, 0.35).normalized()
	var r0: float = AnvilEnv.PIT_R * AnvilEnv.SHAFT_K
	var hgt: float = 105.0
	var rust: Material = env.mat("rust")
	var tops: Array[Vector3] = []
	for sgn: float in [-1.0, 1.0]:
		var foot: Vector3 = c + side * sgn * (r0 + 14.0)
		foot.y = AnvilEnv.RIM_Y - AnvilEnv.PIT_DEPTH / 6.0 * 1.0
		var top: Vector3 = c + side * sgn * (r0 * 0.55) + Vector3(0, hgt, 0)
		tops.append(top)
		var fw: Vector3 = side.cross(Vector3.UP)
		var legs: Array[Vector3] = [foot + fw * 9.0 + side * sgn * 6.0, foot - fw * 9.0 + side * sgn * 6.0, foot + fw * 9.0 - side * sgn * 6.0, foot - fw * 9.0 - side * sgn * 6.0]
		for lg: Vector3 in legs:
			add_beam(b, lg, top + (lg - foot) * 0.25, 1.1, rust)
			add_box(b, lg, Vector3(4, 2, 4), env.mat("concrete"))
		for k: int in 7:
			var t: float = float(k + 1) / 8.0
			var ring: Array[Vector3] = []
			for lg: Vector3 in legs:
				ring.append(lg.lerp(top + (lg - foot) * 0.25, t))
			for q: int in 4:
				add_beam(b, ring[q], ring[[1, 3, 0, 2][q]], 0.45, rust)
	add_beam(b, tops[0] + Vector3(0, 2, 0), tops[1] + Vector3(0, 2, 0), 3.2, env.mat("stack"))
	add_beam(fut, tops[0] + Vector3(0, 0.2, 0), tops[1] + Vector3(0, 0.2, 0), 0.16, env.mat("line"))
	var mid: Vector3 = (tops[0] + tops[1]) * 0.5 + Vector3(0, 9.0, 0)
	b.add(ProcMesh.torus(10.5, 12.0, 36, 8), Transform3D(Basis(Vector3.FORWARD, PI * 0.5) * Basis(Vector3.UP, atan2(-side.z, side.x)), mid), rust)
	add_beam(b, mid, mid - Vector3(0, 7.0, 0), 1.6, rust)
	for k: int in 4:
		var off: Vector3 = side * (k - 1.5) * 3.0
		add_beam(b, mid + off - Vector3(0, 9, 0), c + off * 2.0 + Vector3(0, -150.0, 0), 0.2, env.mat("soot"))
	# Restored: a thin light ring round the shaft mouth and the rim.
	var ring_y: float = AnvilEnv.RIM_Y - AnvilEnv.PIT_DEPTH + 0.3
	fut.add(ProcMesh.torus(r0 + 0.6, r0 + 1.0, 96, 4), Transform3D(Basis(), Vector3(c.x, ring_y, c.z)), env.mat("line"))
	fut.add(ProcMesh.torus(AnvilEnv.PIT_R + 4.6, AnvilEnv.PIT_R + 5.0, 128, 4), Transform3D(Basis(), Vector3(c.x, AnvilEnv.RIM_Y + 1.65, c.z)), env.mat("line"))


# --- Haulers, carts, slag ----------------------------------------------------------------------

static func _haulers(env: AnvilEnv, b: Batch, high: Batch) -> void:
	var spots: Array = [[-PI * 0.5 + 1.15, 30.0, 0.6, 9.0], [PI * 0.22, 60.0, 2.1, -7.0], [PI * 0.6, 34.0, -0.8, 6.0], [-PI * 0.5 - 0.95, 80.0, 1.2, -11.0], [PI * 1.06, 52.0, 2.8, 8.0]]
	for i: int in spots.size():
		var sp: Array = spots[i]
		var p: Vector3 = AnvilEnv.polar(float(sp[0]), env.r_in + float(sp[1]))
		p.y = env.gy(p) - 2.4
		var basis := Basis(Vector3.UP, float(sp[2])) * Basis(Vector3.FORWARD, deg_to_rad(float(sp[3]))) * Basis(Vector3.RIGHT, deg_to_rad(float(sp[3]) * 0.4))
		_hauler(env, b, high, Transform3D(basis, p), i)


static func _hauler(env: AnvilEnv, b: Batch, high: Batch, xf: Transform3D, idx: int) -> void:
	# A Ledger-class ore hauler: 18 m chassis, tilted bed, cab and canopy, six 3.4 m wheels.
	var paint: Material = env.mat("hauler")
	var rust: Material = env.mat("rust")
	b.add(box(), xf * Transform3D(Basis.from_scale(Vector3(16.0, 1.6, 6.0)), Vector3(0, 3.6, 0)), rust)
	var bed := Transform3D(Basis(Vector3.FORWARD, -0.08), Vector3(-1.5, 6.4, 0))
	b.add(box(), xf * bed * Transform3D(Basis.from_scale(Vector3(13.0, 0.5, 8.0)), Vector3.ZERO), paint)
	for sz: float in [-1.0, 1.0]:
		b.add(box(), xf * bed * Transform3D(Basis.from_scale(Vector3(13.0, 4.0, 0.4)), Vector3(0, 2.0, sz * 3.8)), paint)
	b.add(box(), xf * bed * Transform3D(Basis.from_scale(Vector3(0.4, 4.0, 8.0)), Vector3(-6.3, 2.0, 0)), paint)
	b.add(box(), xf * bed * Transform3D(Basis.from_scale(Vector3(5.0, 0.4, 8.6)), Vector3(7.5, 4.1, 0)), paint)
	b.add(box(), xf * Transform3D(Basis.from_scale(Vector3(3.2, 3.2, 3.0)), Vector3(6.8, 6.0, -2.2)), paint)
	b.add(box(), xf * Transform3D(Basis.from_scale(Vector3(0.1, 1.4, 2.6)), Vector3(8.45, 6.6, -2.2)), env.mat("soot"))
	b.add(box(), xf * bed * Transform3D(Basis.from_scale(Vector3(11.0, 2.0, 7.0)), Vector3(-0.5, 1.1, 0)), env.mat("ore") if idx % 2 == 0 else env.mat("terrain"))
	var wheel := ProcMesh.cyl(3.4, 3.4, 1.8, 20)
	for wx: float in [-5.0, -1.4, 6.0]:
		for sz: float in [-1.0, 1.0]:
			b.add(wheel, xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(wx, 3.4, sz * 3.6)), env.mat("tyre"))
	# Restored: the bed is a planter of red-leaf and green.
	high.add(box(), xf * bed * Transform3D(Basis.from_scale(Vector3(11.5, 1.2, 7.2)), Vector3(-0.5, 2.6, 0)), env.mat("redleaf") if idx % 2 == 0 else env.mat("green"))
	# A drift of dust banked against the windward side.
	var drift := ProcMesh.hemisphere(1.0, 20, 6)
	b.add(drift, xf * Transform3D(Basis.from_scale(Vector3(10.0, 3.4, 4.5)), Vector3(0, 1.6, 4.4)), env.mat("terrain"))


static func _ore_spur(env: AnvilEnv, b: Batch) -> void:
	# A rail spur arcing round the field edge to the north-east, a train of ore carts, two derailed.
	var r: float = env.r_in + 9.0
	var a0: float = -PI * 0.5 + 0.55
	var a1: float = -PI * 0.5 + 1.35
	var steps: int = 36
	var rust: Material = env.mat("rust")
	for k: int in steps:
		var ta: float = lerpf(a0, a1, float(k) / steps)
		var tb: float = lerpf(a0, a1, float(k + 1) / steps)
		for off: float in [-0.75, 0.75]:
			var pa: Vector3 = AnvilEnv.polar(ta, r + off)
			var pb: Vector3 = AnvilEnv.polar(tb, r + off)
			pa.y = env.gy(pa) + 0.25
			pb.y = env.gy(pb) + 0.25
			add_beam(b, pa, pb, 0.14, rust)
		var ps: Vector3 = AnvilEnv.polar(ta, r)
		ps.y = env.gy(ps) + 0.08
		add_box(b, ps, Vector3(0.35, 0.16, 2.4), env.mat("soot"), Vector3(0, -rad_to_deg(ta), 0))
	for k: int in 7:
		var ta: float = lerpf(a0 + 0.08, a1 - 0.1, float(k) / 7.0)
		var p: Vector3 = AnvilEnv.polar(ta, r)
		var yaw: float = -ta + PI * 0.5
		var tilt := Vector3.ZERO
		if k == 2 or k == 5:
			p = AnvilEnv.polar(ta, r + 2.4)
			tilt = Vector3(0, 0, 38.0 if k == 2 else -70.0)
		p.y = env.gy(p)
		var xf := Transform3D(Basis.from_euler(Vector3(deg_to_rad(tilt.x), yaw, deg_to_rad(tilt.z))), p)
		b.add(box(), xf * Transform3D(Basis.from_scale(Vector3(2.4, 0.35, 1.5)), Vector3(0, 0.55, 0)), rust)
		b.add(ProcMesh.cyl(1.25, 0.95, 1.5, 10), xf * Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.75)), Vector3(0, 1.5, 0)), env.mat("cart"))
		if k != 5:
			b.add(ProcMesh.hemisphere(1.1, 10, 4), xf * Transform3D(Basis.from_scale(Vector3(1.0, 0.45, 0.7)), Vector3(0, 2.2, 0)), env.mat("ore"))
		for wx: float in [-0.8, 0.8]:
			for wz: float in [-0.7, 0.7]:
				b.add(ProcMesh.cyl(0.32, 0.32, 0.14, 10), xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(wx, 0.35, wz)), env.mat("tyre"))


## A noisy cone of slag (local, base at y 0).
static func slag_mesh(seed_v: int) -> ArrayMesh:
	var nz := FastNoiseLite.new()
	nz.seed = seed_v
	nz.frequency = 1.4
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var na: int = 40
	var nr: int = 12
	for j: int in na + 1:
		var a: float = TAU * j / na
		for i: int in nr:
			var u: float = float(i) / (nr - 1)
			var rr: float = u * (1.0 + nz.get_noise_2d(cos(a), sin(a)) * 0.35)
			# Lumpy tipped-load profile: a ragged crest, dumped lobes and gullies down the flanks.
			var gully: float = absf(nz.get_noise_2d(cos(a) * 4.0 + 9.0, sin(a) * 4.0)) * 0.12 * u
			var hgt: float = pow(1.0 - u, 1.15) * (1.0 + nz.get_noise_2d(cos(a) * 2.0 + 3.0, sin(a) * 2.0) * 0.25) - gully + nz.get_noise_2d(cos(a) * u * 6.0, sin(a) * u * 6.0) * 0.05 * (1.0 - u)
			st.add_vertex(Vector3(cos(a) * rr, maxf(hgt, 0.0) - (0.05 if i == nr - 1 else 0.0), sin(a) * rr))
	for j: int in na:
		for i: int in nr - 1:
			var p0: int = j * nr + i
			var p1: int = (j + 1) * nr + i
			for idx: int in [p0, p0 + 1, p1, p1, p0 + 1, p1 + 1]:
				st.add_index(idx)
	st.generate_normals()
	return st.commit()


static func _slag_heaps(env: AnvilEnv, b: Batch) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = env.field.seed_value + 4242
	var meshes: Array[ArrayMesh] = [slag_mesh(1), slag_mesh(2), slag_mesh(3)]
	var spots: Array[Vector3] = []
	for s: Dictionary in env.stacks.slice(0, 5):
		var sp: Vector3 = s["pos"]
		for k: int in 2:
			spots.append(sp + AnvilEnv.polar(rng.randf() * TAU, float(s["r"]) * 4.0 + rng.randf_range(10.0, 40.0)))
	for k: int in 5:
		spots.append(AnvilEnv.polar(rng.randf_range(-PI * 0.5 - 1.2, -PI * 0.5 + 1.4), env.r_in + rng.randf_range(22.0, 60.0)))
	for sp: Vector3 in spots:
		var near: bool = Vector2(sp.x, sp.z).length() < env.r_in + 80.0
		if Vector2(sp.x - env.pit_c.x, sp.z - env.pit_c.z).length() < AnvilEnv.PIT_R + 20.0:
			continue
		var w: float = rng.randf_range(7.0, 13.0) if near else rng.randf_range(18.0, 40.0)
		var hgt: float = w * rng.randf_range(0.45, 0.7)
		var p: Vector3 = sp
		p.y = env.gy(p) - 0.3
		b.add(meshes[rng.randi() % 3], Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(w, hgt, w * rng.randf_range(0.7, 1.0))), p), env.mat("slag"))


static func _ruin_debris(env: AnvilEnv, b: Batch) -> void:
	# A fallen stack section and a collapsed gantry span: cleared once the base is rebuilt.
	var p: Vector3 = AnvilEnv.polar(-PI * 0.5 - 0.62, 190.0)
	p.y = env.gy(p) + 3.0
	add_cyl(b, p, 5.2, 5.6, 46.0, env.mat("stack"), 24, Basis(Vector3.UP, 0.7) * Basis(Vector3.FORWARD, PI * 0.5 - 0.05))
	add_cyl(b, p + Vector3(16.0, -1.0, 12.0), 5.0, 5.0, 1.1, env.mat("rust"), 24, Basis(Vector3.UP, 0.7) * Basis(Vector3.FORWARD, PI * 0.5))
	var a: Vector3 = AnvilEnv.polar(PI * 0.35, env.r_in + 30.0)
	var c: Vector3 = AnvilEnv.polar(PI * 0.47, env.r_in + 44.0)
	a.y = env.gy(a) + 0.8
	c.y = env.gy(c) + 9.0
	for sx: float in [-1.6, 1.6]:
		add_beam(b, a + Vector3(sx, 0, 0), c + Vector3(sx, 0, 0), 0.32, env.mat("rust"))
		add_beam(b, a + Vector3(sx, 2.8, 0), c + Vector3(sx, 2.8, 0), 0.32, env.mat("rust"))


# --- Restored: turbines and domes ------------------------------------------------------------

static func _turbines(env: AnvilEnv, up: Batch, fut: Batch) -> void:
	var spots: Array = [[-PI * 0.5 - 1.05, 120.0], [-PI * 0.5 - 1.25, 150.0], [PI * 0.12, 105.0], [PI * 0.3, 135.0],
		[PI * 0.75, 170.0], [PI * 0.9, 120.0], [-PI * 0.5 + 1.6, 160.0], [PI * 1.2, 150.0], [-PI * 0.5 - 1.45, 190.0], [PI * 0.55, 210.0]]
	for i: int in spots.size():
		var base: Vector3 = AnvilEnv.polar(float(spots[i][0]), env.r_in + float(spots[i][1]))
		base.y = env.gy(base) - 0.5
		var target: Node3D = env.groups["up"] if i < 4 else env.groups["future"]
		var b: Batch = up if i < 4 else fut
		var h: float = 52.0
		add_cyl(b, base + Vector3(0, h * 0.5, 0), 1.0, 1.8, h, env.mat("white"), 16)
		add_box(b, base + Vector3(0, h + 0.6, 0.6), Vector3(1.8, 1.8, 4.6), env.mat("white"))
		add_cyl(b, base + Vector3(0, h * 0.6, 0), 1.45, 1.45, 0.1, env.mat("line"), 20)
		var hub := Node3D.new()
		hub.position = base + Vector3(0, h + 0.6, -1.9)
		hub.rotation.z = float(i) * 0.7
		hub.set_meta("k", i % 3)
		target.add_child(hub)
		var bl := Batch.new()
		bl.add(ProcMesh.sphere(0.8, 12, 6), Transform3D(), env.mat("white"))
		for k: int in 3:
			var a: float = TAU * k / 3.0
			bl.add(box(), FrontierView._beam_xf(Vector3.ZERO, Vector3(cos(a), sin(a), 0) * 22.0, 1.1) * Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.18)), Vector3.ZERO), env.mat("white"))
		bl.flush(hub)
		env.rotors.append(hub)


static func _dome(env: AnvilEnv, b: Batch, c: Vector3, r: float, seed_v: int) -> void:
	var white: Material = env.mat("white")
	add_cyl(b, c + Vector3(0, 0.6, 0), r + 0.4, r + 0.6, 1.4, white, 40)
	add_cyl(b, c + Vector3(0, 1.36, 0), r + 0.45, r + 0.45, 0.12, env.mat("line"), 48)
	b.add(ProcMesh.hemisphere(r, 32, 12), Transform3D(Basis(), c + Vector3(0, 1.3, 0)), env.mat("glass"))
	# Ribs: meridians and two parallels.
	for k: int in 10:
		var a: float = TAU * k / 10.0
		var prev: Vector3 = c + Vector3(cos(a) * r, 1.3, sin(a) * r)
		for s: int in 6:
			var e: float = PI * 0.5 * float(s + 1) / 6.0
			var q: Vector3 = c + Vector3(cos(a) * cos(e) * r, 1.3 + sin(e) * r, sin(a) * cos(e) * r)
			add_beam(b, prev, q, 0.16, white)
			prev = q
	for e: float in [0.45, 0.95]:
		b.add(ProcMesh.torus(cos(e) * r - 0.08, cos(e) * r + 0.08, 40, 4), Transform3D(Basis(), c + Vector3(0, 1.3 + sin(e) * r, 0)), white)
	# Inside: a green mound and a few trees.
	b.add(ProcMesh.hemisphere(1.0, 20, 6), Transform3D(Basis.from_scale(Vector3(r * 0.85, r * 0.18, r * 0.85)), c + Vector3(0, 1.0, 0)), env.mat("green"))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for k: int in int(r * 0.6):
		var p: Vector3 = c + AnvilEnv.polar(rng.randf() * TAU, rng.randf() * r * 0.6, 1.0)
		var th: float = rng.randf_range(2.0, r * 0.45)
		add_beam(b, p, p + Vector3(0, th, 0), 0.25, env.mat("soot"))
		b.add(ProcMesh.sphere(rng.randf_range(1.2, 2.4), 10, 6), Transform3D(Basis.from_scale(Vector3(1, 0.85, 1)), p + Vector3(0, th + 0.6, 0)), env.mat("redleaf") if k % 3 == 0 else env.mat("green"))


static func _domes(env: AnvilEnv, high: Batch, fut: Batch) -> void:
	# Two clusters joined by white tubes; the first dome of each goes up at base level 3.
	var clusters: Array = [[-PI * 0.5 - 0.75, 72.0], [PI * 0.08, 70.0], [PI * 0.62, 95.0]]
	for ci: int in clusters.size():
		var cc: Vector3 = AnvilEnv.polar(float(clusters[ci][0]), env.r_in + float(clusters[ci][1]))
		var prev := Vector3.INF
		for k: int in 4:
			var p: Vector3 = cc + AnvilEnv.polar(float(k) * 1.9 + ci, 0.0 if k == 0 else 24.0 + k * 3.0)
			p.y = env.gy(p) - 0.3
			var r: float = [14.0, 9.0, 11.0, 7.5][k]
			var b: Batch = high if (k == 0 and ci < 2) else fut
			_dome(env, b, p, r, env.field.seed_value + ci * 10 + k)
			if prev != Vector3.INF:
				var d: Vector3 = p - prev
				var mid: Vector3 = (p + prev) * 0.5 + Vector3(0, 1.8, 0)
				var len_: float = Vector2(d.x, d.z).length()
				var basis := Basis(Vector3.UP, atan2(-d.z, d.x)) * Basis(Vector3.FORWARD, PI * 0.5)
				add_cyl(fut, mid, 1.5, 1.5, len_, env.mat("white"), 14, basis)
				add_cyl(fut, mid + Vector3(0, 1.52, 0), 0.05, 0.05, len_, env.mat("line"), 4, basis)
			prev = p
