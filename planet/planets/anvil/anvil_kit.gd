class_name AnvilKit
extends RefCounted
## [planet-anvil] Anvil's foundry pieces built from the shared art kit (art/kit, docs/ART_KIT.md):
## bevelled kit primitives on KitMesh.Builder, kit materials per state (broken / repaired /
## restored), decals as images, emissive trims only where powered. Every function adds parts to
## a builder `b` at transform `t` (local +Y up, base at y 0); AnvilSites assembles them.

## Foundry iron (sooty warm grey) with foundry-red accents; habitats in the kit's Anvil cream.
const FOUNDRY: Dictionary = {"main": "#5b4c44", "accent": "#c4461c", "pipe": "#d68a1c", "rail": "yellow",
	"pole": "#3a3330", "crate": "#c4461c", "barrel": "#a8321c", "broken_main": "#4a3c34", "broken_accent": "#6e3420",
	"trim_cool": "warm"}
const HABITAT: Dictionary = {"main": "#d9c7a8", "accent": "orange", "trim_cool": "warm"}
const LEDGER: Dictionary = {"main": "#c9902a", "accent": "#3a3330", "broken_main": "#8a6a34", "trim_cool": "warm"}


static func kit_state(stage: int) -> String:
	return "broken" if stage <= 1 else ("repaired" if stage <= 3 else "restored")


static func x(pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> Transform3D:
	return KitMesh.xf(pos, rot_deg)


## Commits a builder into a node under root, with its requested lamps lit when powered.
static func node(b: KitMesh.Builder, root: Node3D, nm: String, powered: bool) -> MeshInstance3D:
	var mi: MeshInstance3D = KitMesh.instance(b, b.state, powered)
	mi.name = nm
	root.add_child(mi)
	if powered and b.state != "broken":
		for l: Dictionary in b.lights:
			var o := OmniLight3D.new()
			o.position = l.get("pos", Vector3.ZERO)
			o.light_color = l.get("color", Color(1.0, 0.8, 0.55))
			o.omni_range = float(l.get("range", 6.0))
			o.light_energy = float(l.get("energy", 1.0))
			o.shadow_enabled = false
			root.add_child(o)
	return mi


## A ready-made kit building placed on the site (it brings its own ground patch and clutter).
static func building(root: Node3D, kind: String, stage: int, seed_v: int, palette: Dictionary, pos: Vector3, yaw_deg: float, scl: float = 1.0) -> KitBuilding:
	var k: KitBuilding = KitBuilding.create(kind, kit_state(stage), seed_v, palette, stage >= 2)
	k.position = pos
	k.rotation_degrees.y = yaw_deg
	k.scale = Vector3.ONE * scl
	root.add_child(k)
	return k


## A foundry smokestack: octagonal plinth, a flanged and bolted shell tapering to a lip, sooted
## crown, accent bands, two galleries with railings and braces, a caged ladder on standoffs, a
## flanged riser pipe, decals. Restored: planted shells and planters, warm trims.
static func stack(b: KitMesh.Builder, t: Transform3D, h: float, r: float, seed_v: int) -> void:
	var st: String = b.state
	var broken: bool = st == "broken"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var top_r: float = r * 0.8
	var rad := func(y: float) -> float: return lerpf(r, top_r, clampf(y / h, 0.0, 1.0))
	b.add("concrete", KitMesh.bevel_cylinder(r * 1.5, 3.0, 0.3, 8), t * x(Vector3.ZERO, Vector3(0, 22.5, 0)))
	b.add("concrete", KitMesh.bevel_cylinder(r * 1.25, 0.6, 0.15, 8), t * x(Vector3(0, 3.0, 0), Vector3(0, 22.5, 0)))
	var tt: Transform3D = t * x(Vector3(0, 3.6, 0))
	# Shell: a lathed profile with a bolted flange at every course.
	var courses: int = maxi(3, int(h / 6.0))
	var p := PackedVector3Array([Vector3(0, 0, 0), Vector3(r, 0, 1)])
	for k: int in range(1, courses):
		var y: float = h * float(k) / courses
		var rr: float = rad.call(y)
		p.append(Vector3(rr, y - 0.28, 0))
		p.append(Vector3(rr + 0.16, y - 0.2, 1))
		p.append(Vector3(rr + 0.16, y + 0.2, 1))
		p.append(Vector3(rr, y + 0.28, 0))
	p.append(Vector3(top_r, h - 0.1, 0))
	p.append(Vector3(top_r + 0.45, h, 1))
	p.append(Vector3(top_r + 0.45, h + 0.7, 1))
	p.append(Vector3(top_r - 0.25, h + 0.7, 1))
	p.append(Vector3(top_r - 0.25, h - 3.0, 0))
	b.add("paint:main", KitMesh.lathe(p, 36), tt)
	# Soot-blackened crown and accent bands.
	var crown := PackedVector3Array([Vector3(rad.call(h * 0.86) + 0.03, h * 0.86, 1), Vector3(rad.call(h * 0.86) + 0.05, h * 0.87, 0), Vector3(top_r + 0.05, h - 0.15, 0), Vector3(top_r + 0.03, h - 0.1, 1)])
	b.add("dark_steel", KitMesh.lathe(crown, 36), tt)
	var bands: int = maxi(1, int(h / 20.0))
	for k: int in bands:
		var y2: float = h * (float(k) + 0.5) / (bands + 0.5)
		b.add("paint:accent", KitMesh.bevel_cylinder(rad.call(y2) + 0.12, 1.2, 0.12, 36), tt * x(Vector3(0, y2 - 0.6, 0)))
	# Bolts round every flange.
	var bolt: Array = KitMesh.bolt(0.06, 0.06)
	for k: int in range(1, courses):
		var y3: float = h * float(k) / courses
		var rr3: float = rad.call(y3) + 0.16
		var n: int = int(TAU * rr3 / 0.75)
		for q: int in n:
			var a: float = TAU * q / n
			b.add("steel", bolt, tt * Transform3D(Basis(Vector3.UP, -a + PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(cos(a) * rr3, y3, sin(a) * rr3)))
	# Rusted patch plates when broken.
	if broken:
		for k: int in 8:
			var a2: float = rng.randf() * TAU
			var y4: float = rng.randf_range(h * 0.1, h * 0.85)
			var rr4: float = rad.call(y4) + 0.06
			b.box("rusty", Vector3(rng.randf_range(1.2, 2.6), rng.randf_range(1.0, 2.4), 0.1), tt * Transform3D(Basis(Vector3.UP, -a2 + PI * 0.5) * Basis(Vector3.FORWARD, rng.randf_range(-0.1, 0.1)), Vector3(cos(a2) * rr4, y4, sin(a2) * rr4)), 0.03)
	# Galleries: grating ring with a hazard edge, braces, railings (gaps when broken), trims.
	for gy: float in [h * 0.38, h * 0.72]:
		var gr: float = rad.call(gy)
		var ring_r: float = gr + 2.2
		b.add("dark_steel", KitMesh.bevel_cylinder(ring_r, 0.28, 0.08, 32), tt * x(Vector3(0, gy, 0)))
		b.add("hazard", KitMesh.bevel_cylinder(ring_r + 0.02, 0.1, 0.03, 32), tt * x(Vector3(0, gy + 0.09, 0)))
		for k: int in 8:
			var a3: float = TAU * k / 8.0
			b.rod("paint:accent", tt * Vector3(cos(a3) * gr, gy - 1.6, sin(a3) * gr), tt * Vector3(cos(a3) * (ring_r - 0.2), gy, sin(a3) * (ring_r - 0.2)), 0.09, 6)
		var segs: int = 20
		for k: int in segs:
			if broken and rng.randf() < 0.2:
				continue
			var a4: float = TAU * k / segs
			var a5: float = TAU * (k + 1) / segs
			KitProps.railing(b, tt, Vector3(cos(a4) * (ring_r - 0.1), gy + 0.28, sin(a4) * (ring_r - 0.1)), Vector3(cos(a5) * (ring_r - 0.1), gy + 0.28, sin(a5) * (ring_r - 0.1)), 1.0, "paint:rail", st)
		b.add("trim:warm", KitMesh.bevel_cylinder(gr + 0.06, 0.06, 0.02, 32), tt * x(Vector3(0, gy + 1.4, 0)))
		if st == "restored":
			for k: int in 4:
				var a6: float = TAU * (k + 0.5) / 4.0
				KitProps.planter(b, tt * Transform3D(Basis(Vector3.UP, -a6), Vector3(cos(a6) * (ring_r - 0.9), gy + 0.28, sin(a6) * (ring_r - 0.9))), 1.6, st)
	# Restored: vertical garden shells between the bands.
	if st == "restored":
		for k: int in 3:
			var y5: float = h * (0.12 + 0.28 * k)
			var gp := PackedVector3Array([Vector3(rad.call(y5) + 0.05, y5, 1), Vector3(rad.call(y5) + 0.35, y5 + 0.4, 0), Vector3(rad.call(y5 + 6.0) + 0.35, y5 + 5.6, 0), Vector3(rad.call(y5 + 6.0) + 0.05, y5 + 6.0, 1)])
			b.add("leaves", KitMesh.lathe(gp, 36), tt)
	# Caged ladder on standoffs, from the plinth to the top gallery.
	var ly: float = h * 0.72
	KitProps.ladder(b, tt * x(Vector3(0, 0, r + 0.25)), ly)
	for k: int in int(ly / 5.0):
		var y6: float = 2.0 + k * 5.0
		for sx: float in [-0.22, 0.22]:
			b.rod("dark_steel", tt * Vector3(sx, y6, rad.call(y6)), tt * Vector3(sx, y6, r + 0.4), 0.03, 5)
	# Riser pipe with flanges, and decals on the plinth.
	var ps: float = -(r + 0.7)
	KitProps.pipe_run(b, tt, PackedVector3Array([Vector3(ps, -2.0, 0), Vector3(ps, h * 0.6, 0), Vector3(-(rad.call(h * 0.62) + 0.2), h * 0.66, 0)]), maxf(0.18, r * 0.09))
	b.decal("warn", Vector2(1.6, 1.6), t * x(Vector3(0, 1.6, r * 1.5 * 0.924 + 0.02)))
	b.decal("num_0%d" % (1 + seed_v % 6), Vector2(1.4, 1.4), t * x(Vector3(r * 0.6, 1.6, r * 1.5 * 0.924 + 0.02)))
	b.decal("logo", Vector2(2.6, 2.6), tt * x(Vector3(0, 6.0, -(r + 0.02)), Vector3(0, 180, 0)))


## A boxed lattice conveyor from a to c (ground points) at `deck` m, on A-frame bents with
## concrete footings; a rubber belt, hazard-striped ends, a trim line underneath.
static func truss(b: KitMesh.Builder, a: Vector3, c: Vector3, deck: float) -> void:
	var flat := Vector3(c.x - a.x, 0, c.z - a.z)
	var len_: float = flat.length()
	var fw: Vector3 = flat / maxf(len_, 0.001)
	var side: Vector3 = fw.cross(Vector3.UP).normalized()
	var top := func(t: float, dy: float, sx: float) -> Vector3:
		return a.lerp(c, t) + Vector3(0, deck + dy, 0) + side * sx
	for sx: float in [-1.1, 1.1]:
		for dy: float in [0.0, 1.8]:
			b.rod("paint:accent", top.call(0.0, dy, sx), top.call(1.0, dy, sx), 0.11, 6)
	var segs: int = maxi(2, int(len_ / 2.2))
	for k: int in segs:
		var t0: float = float(k) / segs
		var t1: float = float(k + 1) / segs
		for sx: float in [-1.1, 1.1]:
			b.rod("paint:accent", top.call(t0, 0.0, sx), top.call(t1, 1.8, sx), 0.06, 5)
		b.rod("dark_steel", top.call(t0, 0.0, -1.1), top.call(t0, 0.0, 1.1), 0.05, 5)
		b.rod("dark_steel", top.call(t0, 1.8, -1.1), top.call(t0, 1.8, 1.1), 0.05, 5)
	var mid: Vector3 = top.call(0.5, 0.25, 0.0)
	b.box("rubber", Vector3(1.5, 0.12, len_), Transform3D(Basis(Vector3.UP, atan2(fw.x, fw.z)) * Basis(Vector3.RIGHT, -atan2(c.y - a.y, len_)), mid), 0.04)
	b.add("trim:warm", KitMesh.bevel_box(Vector3(0.06, 0.06, len_ * 0.96), 0.02), Transform3D(Basis(Vector3.UP, atan2(fw.x, fw.z)), top.call(0.5, -0.12, -1.1)))
	var bents: int = maxi(1, int(len_ / 12.0))
	for k: int in bents + 1:
		var t2: float = float(k) / bents
		var g: Vector3 = a.lerp(c, t2)
		g.y = 0.0
		for sx: float in [-1.0, 1.0]:
			var foot: Vector3 = g + side * sx * 2.8
			b.rod("paint:main", foot + Vector3(0, 0.5, 0), top.call(t2, 0.0, sx * 1.1), 0.2, 8)
			b.box("concrete", Vector3(1.0, 0.6, 1.0), x(foot + Vector3(0, 0.3, 0)), 0.1)
		b.rod("paint:main", g + side * -2.0 + Vector3(0, deck * 0.45, 0), g + side * 2.0 + Vector3(0, deck * 0.45, 0), 0.1, 6)
	for end: float in [0.0, 1.0]:
		b.box("hazard", Vector3(2.5, 0.35, 0.2), Transform3D(Basis(Vector3.UP, atan2(fw.x, fw.z)), top.call(end, 0.9, 0.0)), 0.05)


## A Ledger ore hauler (about 11 m): bevelled chassis, tipping bed with ribs, cab with glass,
## six chunky tyres, ladder and rails, decals. Broken: tilted bed, a flat tyre, rust panels.
static func hauler(b: KitMesh.Builder, t: Transform3D) -> void:
	var broken: bool = b.state == "broken"
	b.box("dark_steel", Vector3(10.0, 1.0, 3.4), t * x(Vector3(0, 1.9, 0)), 0.15)
	var bed: Transform3D = t * x(Vector3(-1.0, 3.6, 0), Vector3(0, 0, 9.0 if broken else 0.0))
	b.box("paint:main", Vector3(7.6, 0.4, 4.4), bed, 0.15)
	for sz: float in [-1.0, 1.0]:
		b.box("paint:main", Vector3(7.6, 2.2, 0.3), bed * x(Vector3(0, 1.3, sz * 2.1)), 0.12)
		for k: int in 5:
			b.box("paint:accent", Vector3(0.22, 2.0, 0.16), bed * x(Vector3(-3.2 + k * 1.6, 1.3, sz * 2.3)), 0.05)
	b.box("paint:main", Vector3(0.3, 2.2, 4.4), bed * x(Vector3(-3.8, 1.3, 0)), 0.12)
	b.box("paint:main", Vector3(3.0, 0.3, 4.8), bed * x(Vector3(4.2, 2.5, 0)), 0.1)
	b.box("rusty", Vector3(6.8, 1.2, 3.8), bed * x(Vector3(0, 0.9, 0)), 0.3)
	b.box("paint:main", Vector3(2.2, 2.0, 2.0), t * x(Vector3(3.8, 3.4, -1.0)), 0.18)
	b.box("glass", Vector3(0.1, 1.0, 1.6), t * x(Vector3(4.92, 3.7, -1.0)), 0.03)
	b.box("dark_steel", Vector3(2.4, 0.2, 2.2), t * x(Vector3(3.8, 4.5, -1.0)), 0.05)
	KitProps.ladder(b, t * x(Vector3(3.2, 0.3, 0.6), Vector3(0, 90, 0)), 2.6)
	KitProps.railing(b, t, Vector3(2.8, 4.4, 0.2), Vector3(4.9, 4.4, 0.2), 0.9, "paint:rail", b.state)
	var flat: int = 2 if broken else -1
	var k2: int = 0
	for wx: float in [-3.8, -1.4, 3.6]:
		for sz: float in [-1.0, 1.0]:
			var squash: Basis = Basis.from_scale(Vector3(1.0, 1.0, 0.82 if k2 == flat else 1.0))
			b.add("rubber", KitMesh.bevel_cylinder(1.55, 1.1, 0.35, 20), t * Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * squash, Vector3(wx, 1.55, sz * 1.75 - 0.55 * sz)))
			b.add("dark_steel", KitMesh.bevel_cylinder(0.7, 1.16, 0.1, 10), t * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(wx, 1.55, sz * 1.75 - 0.58 * sz)))
			k2 += 1
	b.decal("chevrons", Vector2(1.6, 0.6), t * x(Vector3(5.05, 2.0, 0), Vector3(0, 90, 0)))
	b.decal("num_0%d" % (1 + b.rng.randi() % 6), Vector2(1.2, 1.2), bed * x(Vector3(0, 1.4, 2.27)))
	if broken:
		for k: int in 3:
			b.box("rusty", Vector3(1.4, 1.1, 0.08), bed * x(Vector3(-2.5 + k * 2.2, 1.2, -2.27), Vector3(0, 0, b.rng.randf_range(-12, 12))), 0.02)


## An ore cart on a short track piece: lathed tub with a rim, axle boxes, four wheels, ore heap.
static func ore_cart(b: KitMesh.Builder, t: Transform3D, tipped: bool) -> void:
	var tt: Transform3D = t * x(Vector3.ZERO, Vector3(0, 0, 70 if tipped else 0))
	b.box("dark_steel", Vector3(2.0, 0.3, 1.2), tt * x(Vector3(0, 0.55, 0)), 0.06)
	var tub := PackedVector3Array([Vector3(0, 0, 0), Vector3(0.85, 0, 1), Vector3(1.1, 1.0, 0), Vector3(1.18, 1.05, 1), Vector3(1.18, 1.2, 1), Vector3(1.0, 1.2, 1), Vector3(0.9, 0.3, 0)])
	b.add("paint:accent", KitMesh.lathe(tub, 14), tt * Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.7)), Vector3(0, 0.7, 0)))
	for sx: float in [-0.7, 0.7]:
		for sz: float in [-0.62, 0.62]:
			b.add("dark_steel", KitMesh.bevel_cylinder(0.28, 0.12, 0.04, 12), tt * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(sx, 0.3, sz)))
	if not tipped:
		b.add("rusty", KitMesh.pebble(2), tt * Transform3D(Basis.from_scale(Vector3(1.6, 0.6, 1.1)), Vector3(0, 1.7, 0)))


## Rails and sleepers from a to c (ground points).
static func track(b: KitMesh.Builder, a: Vector3, c: Vector3) -> void:
	var d: Vector3 = c - a
	var side := Vector3(-d.z, 0, d.x).normalized()
	var yaw: float = rad_to_deg(atan2(d.x, d.z))
	var n: int = int(d.length() / 0.9)
	for k: int in n:
		b.box("concrete", Vector3(2.0, 0.16, 0.3), x(a + d * (float(k) / n) + Vector3(0, 0.08, 0), Vector3(0, yaw + 90.0, 0)), 0.04)
	for sx: float in [-0.62, 0.62]:
		b.rod("steel", a + side * sx + Vector3(0, 0.22, 0), c + side * sx + Vector3(0, 0.22, 0), 0.06, 6)


## A greenhouse dome: concrete ring with an accent band and warm trim, a lathed glass dome on
## painted ribs, planters and bushes inside.
static func dome(b: KitMesh.Builder, t: Transform3D, r: float) -> void:
	b.add("concrete", KitMesh.bevel_cylinder(r + 0.5, 0.9, 0.15, 32), t)
	b.add("paint:accent", KitMesh.bevel_cylinder(r + 0.3, 0.3, 0.06, 32), t * x(Vector3(0, 0.9, 0)))
	b.add("trim:warm", KitMesh.bevel_cylinder(r + 0.32, 0.05, 0.02, 32), t * x(Vector3(0, 1.05, 0)))
	var prof := PackedVector3Array()
	for k: int in 11:
		var e: float = PI * 0.5 * float(k) / 10.0
		prof.append(Vector3(cos(e) * r, sin(e) * r, 0))
	b.add("glass", KitMesh.lathe(prof, 32), t * x(Vector3(0, 1.2, 0)))
	for k: int in 10:
		var a: float = TAU * k / 10.0
		var arc := PackedVector3Array()
		for s: int in 9:
			var e2: float = PI * 0.5 * float(s) / 8.0
			arc.append(t * Vector3(cos(a) * cos(e2) * (r + 0.05), 1.2 + sin(e2) * (r + 0.05), sin(a) * cos(e2) * (r + 0.05)))
		b.tube("paint:main", arc, 0.1, 6)
	b.add("paint:main", KitMesh.bevel_cylinder(0.7, 0.4, 0.1, 12), t * x(Vector3(0, 1.2 + r, 0)))
	KitProps.hatch(b, t * x(Vector3(0, 0.9, r + 0.4)), Vector2(1.2, 2.1), b.state)
	for k: int in 4:
		var a2: float = TAU * k / 4.0 + 0.4
		KitProps.planter(b, t * Transform3D(Basis(Vector3.UP, -a2), Vector3(cos(a2) * r * 0.5, 1.0, sin(a2) * r * 0.5)), r * 0.45, "restored")
	for k: int in 5:
		KitProps.bush(b, t * x(Vector3(b.rng.randf_range(-r, r) * 0.4, 1.0, b.rng.randf_range(-r, r) * 0.4)), b.rng.randf_range(0.4, 0.9))


## The forge furnace: bulging bolted shell with bands, a bustle main ringing the hearth with
## tuyere pipes, a hood and a soot-black flanged chimney, a work deck with stairs.
static func furnace(b: KitMesh.Builder, t: Transform3D) -> void:
	var st: String = b.state
	b.add("concrete", KitMesh.bevel_cylinder(9.0, 1.0, 0.25, 12), t)
	var tt: Transform3D = t * x(Vector3(0, 1.0, 0))
	var prof := PackedVector3Array([Vector3(0, 0, 0), Vector3(6.6, 0, 1), Vector3(7.0, 0.4, 0), Vector3(7.3, 4.0, 0), Vector3(6.6, 9.0, 0), Vector3(5.0, 12.0, 0), Vector3(4.6, 12.2, 1), Vector3(0, 12.2, 0)])
	b.add("paint:main", KitMesh.lathe(prof, 40), tt)
	for k: int in 4:
		var y: float = 1.5 + k * 2.6
		var rr: float = 7.3 if y < 4.0 else lerpf(7.3, 6.6, (y - 4.0) / 5.0)
		b.add("paint:accent", KitMesh.bevel_cylinder(rr + 0.12, 0.7, 0.1, 40), tt * x(Vector3(0, y, 0)))
		var n: int = int(TAU * (rr + 0.12) / 0.6)
		for q: int in n:
			var a: float = TAU * q / n
			b.add("steel", KitMesh.bolt(0.05, 0.05), tt * Transform3D(Basis(Vector3.UP, -a + PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(cos(a) * (rr + 0.12), y + 0.35, sin(a) * (rr + 0.12))))
	# Bustle main and tuyeres.
	var ring := PackedVector3Array()
	for k: int in 33:
		var a2: float = TAU * k / 32.0
		ring.append(tt * Vector3(cos(a2) * 9.0, 5.2, sin(a2) * 9.0))
	b.tube("paint:pipe", ring, 0.55, 10)
	for k: int in 10:
		var a3: float = TAU * k / 10.0
		KitProps.pipe_run(b, tt, PackedVector3Array([Vector3(cos(a3) * 9.0, 5.2, sin(a3) * 9.0), Vector3(cos(a3) * 8.6, 2.6, sin(a3) * 8.6), Vector3(cos(a3) * 7.2, 2.0, sin(a3) * 7.2)]), 0.22, "paint:pipe")
	# Hood and chimney.
	var hood := PackedVector3Array([Vector3(4.8, 0, 1), Vector3(4.9, 0.4, 1), Vector3(2.0, 3.2, 0), Vector3(1.9, 3.4, 1), Vector3(0, 3.4, 0)])
	b.add("dark_steel", KitMesh.lathe(hood, 32), tt * x(Vector3(0, 12.2, 0)))
	var ch := PackedVector3Array([Vector3(1.7, 0, 1), Vector3(1.6, 0.3, 0), Vector3(1.45, 20.0, 0), Vector3(1.8, 20.2, 1), Vector3(1.8, 20.8, 1), Vector3(1.2, 20.8, 1), Vector3(1.2, 17.0, 0)])
	b.add("dark_steel", KitMesh.lathe(ch, 24), tt * x(Vector3(0, 15.4, 0)))
	for k: int in 3:
		b.add("paint:accent", KitMesh.bevel_cylinder(1.62, 0.4, 0.06, 24), tt * x(Vector3(0, 19.0 + k * 5.5, 0)))
	# Work deck and stairs on the tap side.
	b.box("dark_steel", Vector3(6.0, 0.25, 3.0), tt * x(Vector3(0, 4.0, 8.2)), 0.06)
	b.box("hazard", Vector3(6.0, 0.08, 0.12), tt * x(Vector3(0, 4.15, 9.66)), 0.02)
	KitProps.railing(b, tt, Vector3(-3.0, 4.13, 9.6), Vector3(3.0, 4.13, 9.6), 1.0, "paint:rail", st)
	for sx: float in [-2.6, 2.6]:
		b.rod("paint:main", tt * Vector3(sx, -1.0, 9.4), tt * Vector3(sx, 4.0, 9.4), 0.12, 6)
	KitProps.stairs(b, tt * x(Vector3(4.0, -1.0, 7.0), Vector3(0, 90, 0)), 5.0, 5.0, 1.1, "paint:rail", st)
	b.decal("warn", Vector2(1.4, 1.4), tt * x(Vector3(-4.6, 2.2, 5.4), Vector3(0, -38, 0)))
	b.decal("num_02", Vector2(1.6, 1.6), tt * x(Vector3(4.6, 2.2, 5.4), Vector3(0, 38, 0)))


## A ladle gantry crane over a channel: two A-frame legs, a hazard-striped girder, a trolley,
## cables down to a lathed ladle.
static func crane(b: KitMesh.Builder, c: Vector3, span: float, height: float, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	for sgn: float in [-1.0, 1.0]:
		var leg: Vector3 = c + basis * Vector3(sgn * span * 0.5, 0, 0)
		for dz: float in [-2.0, 2.0]:
			b.rod("paint:accent", leg + basis * Vector3(0, 0.4, dz), leg + Vector3(0, height, 0), 0.32, 8)
			b.box("concrete", Vector3(1.4, 0.8, 1.4), x(leg + basis * Vector3(0, 0.4, dz)), 0.12)
		b.rod("paint:main", leg + basis * Vector3(0, height * 0.4, -1.2), leg + basis * Vector3(0, height * 0.4, 1.2), 0.14, 6)
	b.box("hazard", Vector3(span + 1.6, 1.1, 0.9), Transform3D(basis, c + Vector3(0, height + 0.5, 0)), 0.12)
	b.box("dark_steel", Vector3(1.6, 0.9, 1.6), Transform3D(basis, c + Vector3(0, height - 0.4, 0)), 0.1)
	for dx: float in [-0.3, 0.3]:
		b.rod("rubber", c + basis * Vector3(dx, height - 0.8, 0), c + basis * Vector3(dx, 6.6, 0), 0.035, 5)
	var ladle := PackedVector3Array([Vector3(0, 0, 0), Vector3(1.1, 0, 1), Vector3(1.6, 2.2, 0), Vector3(1.75, 2.3, 1), Vector3(1.75, 2.5, 1), Vector3(1.5, 2.5, 1), Vector3(1.35, 0.5, 0)])
	b.add("paint:main", KitMesh.lathe(ladle, 20), Transform3D(basis * Basis(Vector3.RIGHT, 0.3), c + Vector3(0, 4.0, 0)))


## A smelting pot (lathed, flanged lip, trunnions) on transform t.
static func pot(b: KitMesh.Builder, t: Transform3D) -> void:
	var prof := PackedVector3Array([Vector3(0, 0, 0), Vector3(2.2, 0, 1), Vector3(2.4, 0.3, 0), Vector3(3.1, 5.6, 0), Vector3(3.5, 5.8, 1), Vector3(3.5, 6.2, 1), Vector3(2.9, 6.2, 1), Vector3(2.6, 1.0, 0)])
	b.add("paint:main", KitMesh.lathe(prof, 28), t)
	b.add("paint:accent", KitMesh.bevel_cylinder(3.0, 0.6, 0.1, 28), t * x(Vector3(0, 3.6, 0)))
	for sx: float in [-1.0, 1.0]:
		b.add("dark_steel", KitMesh.bevel_cylinder(0.55, 0.9, 0.1, 12), t * Transform3D(Basis(Vector3.FORWARD, PI * 0.5 * sx), Vector3(sx * 2.9, 4.4, 0)))


## An I-beam column or girder from a to c (web + two flanges), size = flange width.
static func i_beam(b: KitMesh.Builder, a: Vector3, c: Vector3, w: float, key: String) -> void:
	var d: Vector3 = c - a
	var l: float = d.length()
	var tb: Transform3D = KitMesh.look_y(a, d)
	b.box(key, Vector3(w * 0.18, l, w), tb * x(Vector3(0, l * 0.5, 0)), 0.03)
	for sx: float in [-1.0, 1.0]:
		b.box(key, Vector3(w, l, w * 0.14), tb * x(Vector3(0, l * 0.5, sx * w * 0.5)), 0.03)
