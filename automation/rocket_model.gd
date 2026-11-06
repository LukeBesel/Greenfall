class_name RocketModel
extends Node3D
## The hub rocket's look, in the same design family as Aurora and the Mk III/IV robots: a smooth
## pearl-white lathed hull, a dark wraparound visor with two glowing eyes, cyan seam rings, a
## tangerine band, swept fins on landing feet and a cyan energy engine. Higher tiers (Mk I-IV,
## automation/rocket_tiers.gd) add orbiting hover rings, side boosters, gold trim and energy fins.
## Local frame: +Z is the front (visor), the boarding hatch faces -Z, base of the feet at y=0.

const GLOW := Color(0.3, 0.88, 1.0)
const ACCENT := Color(1.0, 0.55, 0.18)
const HULL_TOP: float = 9.55
const HATCH_Y: float = 4.55
## Nozzle exit (local): where the plume starts.
const NOZZLE_Y: float = 0.5
const FIN_ANGLES: Array[float] = [30.0, 150.0, 270.0]
## Where the pad's clamps hold the rocket (between the fins; the Mk III boosters sit here too).
const CLAMP_ANGLES: Array[float] = [90.0, 210.0, 330.0]

var tier: int = 1
var plume: RocketPlume
var hatch: Node3D
var _glow_mats: Array[StandardMaterial3D] = []
var _eyes: Array[Node3D] = []
var _rings: Array[Node3D] = []
var _beacon_mat: StandardMaterial3D
var _engine_mat: StandardMaterial3D
var _boosters: Array[RocketPlume] = []
var _t: float = 0.0
var _blink: float = 2.0
var _charge: float = 0.0


func build(p_tier: int) -> void:
	tier = clampi(p_tier, 1, 4)
	for c: Node in get_children():
		c.queue_free()
	_glow_mats.clear()
	_eyes.clear()
	_rings.clear()
	_boosters.clear()
	var pearl := _gloss(Color(0.96, 0.96, 0.95), 0.16, 0.08, 1.0)
	var tang := _gloss(ACCENT, 0.22, 0.1, 1.0)
	var dark := _gloss(Color(0.04, 0.05, 0.07), 0.08, 0.4, 1.0)
	var trim := _gloss(Color(1.0, 0.78, 0.38), 0.2, 1.0, 0.0) if tier >= 4 else _gloss(Color(0.55, 0.58, 0.63), 0.25, 0.9, 0.0)
	var glow := _glow(GLOW, 1.6)  # thin, subtle accent lines (not Tron-thick)
	# Hull: one smooth lathe from the engine skirt to the nose.
	var prof := PackedVector2Array([Vector2(0.55, 1.1), Vector2(0.78, 1.32), Vector2(0.95, 1.7), Vector2(1.03, 2.3), Vector2(1.05, 3.0)])
	for i: int in range(0, 15):
		var u: float = float(i) / 14.0
		var y: float = lerpf(3.4, HULL_TOP, u)
		var k: float = clampf((y - 5.2) / (HULL_TOP - 5.2), 0.0, 1.0)
		prof.append(Vector2(1.05 * pow(1.0 - pow(k, 2.2), 0.6), y))
	_mi(self, lathe(prof, 40), pearl, Vector3.ZERO)
	_mi(self, ProcMesh.cyl(0.55, 0.55, 0.02, 24), dark, Vector3(0, 1.1, 0))
	# Tangerine band and the cyan seam rings.
	_mi(self, ProcMesh.cyl(1.065, 1.06, 0.34, 40), tang, Vector3(0, 2.45, 0))
	for y: float in [3.0, 5.25, 7.75]:
		var r: float = hull_r(y)
		_mi(self, ProcMesh.torus(r + 0.002, r + 0.016, 48, 3), glow, Vector3(0, y, 0))
	# Tangerine nose cap (like Aurora's antenna fin) and vertical light strips on the flanks.
	var cap := PackedVector2Array()
	for i: int in 7:
		var y3: float = lerpf(HULL_TOP - 0.75, HULL_TOP, float(i) / 6.0)
		cap.append(Vector2(hull_r(y3) + 0.01, y3))
	_mi(self, lathe(cap, 32), tang, Vector3.ZERO)
	for a_deg: float in [0.0, 180.0]:
		var a5: float = deg_to_rad(a_deg)
		var rr: float = hull_r(4.1) + 0.012
		var strip := _mi(self, ProcMesh.box(Vector3(0.022, 2.1, 0.02)), glow, Vector3(cos(a5) * rr, 4.12, sin(a5) * rr))
		strip.rotation.y = -a5 + PI * 0.5
	# Dark wraparound visor (front), with Aurora's glowing eyes.
	var vprof := PackedVector2Array()
	for i: int in 9:
		var y2: float = lerpf(6.2, 7.35, float(i) / 8.0)
		vprof.append(Vector2(hull_r(y2) + 0.015, y2))
	_mi(self, lathe(vprof, 24, deg_to_rad(28.0), deg_to_rad(152.0)), dark, Vector3.ZERO)
	for side: float in [-1.0, 1.0]:
		var th: float = deg_to_rad(90.0 + side * 13.0)
		var r2: float = hull_r(6.8) + 0.04
		var eye := Node3D.new()
		eye.position = Vector3(cos(th) * r2, 6.8, sin(th) * r2)
		eye.rotation.y = -th + PI * 0.5
		add_child(eye)
		_mi(eye, ProcMesh.capsule(0.07, 0.36), _glow(GLOW, 4.0), Vector3.ZERO, Vector3(0, 0, 0), Vector3(1, 1, 0.35))
		_eyes.append(eye)
	# Porthole below the visor: dark glass and a glow ring.
	var pr: float = hull_r(4.2)
	_mi(self, ProcMesh.cyl(0.26, 0.26, 0.06, 24), dark, Vector3(0, 4.2, pr - 0.01), Vector3(90, 0, 0))
	_mi(self, ProcMesh.torus(0.26, 0.285, 24, 3), glow, Vector3(0, 4.2, pr + 0.01), Vector3(90, 0, 0))
	# Markings: name and a holographic tier tag.
	var name_l := Mats.stencil("GREENFALL", 64, Color(0.2, 0.24, 0.3, 0.9))
	name_l.pixel_size = 0.0045
	name_l.position = Vector3(0, 3.55, hull_r(3.55) + 0.012)
	add_child(name_l)
	var tag := Label3D.new()
	tag.text = ["", "MK I", "MK II", "MK III", "MK IV"][tier]
	tag.font_size = 72
	tag.pixel_size = 0.004
	tag.modulate = Color(0.5, 1.6, 2.0)
	tag.outline_size = 0
	tag.shaded = false
	tag.position = Vector3(0, 2.0, hull_r(2.0) + 0.04)
	add_child(tag)
	# Boarding hatch at the back (-Z): a rounded door in a glowing frame.
	var hr: float = hull_r(HATCH_Y)
	_mi(self, RobotVisual._rbox(Vector3(0.82, 1.16, 0.06), 0.11, 3), glow, Vector3(0, HATCH_Y, -hr + 0.015))
	hatch = Node3D.new()
	hatch.position = Vector3(0, HATCH_Y, -hr - 0.02)
	add_child(hatch)
	_mi(hatch, RobotVisual._rbox(Vector3(0.78, 1.12, 0.08), 0.1, 3), pearl, Vector3.ZERO)
	_mi(hatch, ProcMesh.box(Vector3(0.4, 0.05, 0.02)), tang, Vector3(0, 0.3, -0.045))
	# Engine: dark bell with a cyan heart.
	var bell := PackedVector2Array([Vector2(0.36, 1.15), Vector2(0.42, 0.95), Vector2(0.55, 0.68), Vector2(0.68, NOZZLE_Y)])
	_mi(self, lathe(bell, 28), _gloss(Color(0.12, 0.13, 0.15), 0.3, 0.9, 0.0), Vector3.ZERO).set_meta("double", true)
	_engine_mat = _glow(GLOW, 1.0)
	_engine_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mi(self, ProcMesh.cyl(0.4, 0.4, 0.02, 24), _engine_mat, Vector3(0, 1.0, 0))
	_mi(self, ProcMesh.torus(0.66, 0.69, 28, 3), _glow(GLOW, 1.6), Vector3(0, NOZZLE_Y + 0.02, 0))
	# Three swept fins on landing feet (at 30, 150 and 270 degrees: clear of the hatch side).
	var fin_poly := PackedVector2Array([Vector2(0.7, 4.0), Vector2(0.75, 1.5), Vector2(1.75, 0.42), Vector2(2.0, 0.42), Vector2(2.0, 0.95), Vector2(1.1, 2.75)])
	for a_deg: float in FIN_ANGLES:
		var fin := Node3D.new()
		fin.rotation.y = -deg_to_rad(a_deg)
		add_child(fin)
		_mi(fin, extrude(fin_poly, 0.12), pearl, Vector3.ZERO)
		_mi(fin, ProcMesh.box(Vector3(0.26, 0.55, 0.14)), tang, Vector3(1.87, 0.7, 0))
		_rod(fin, Vector3(1.1, 2.75, 0.0), Vector3(2.0, 0.95, 0.0), 0.012, glow)
		_mi(fin, ProcMesh.cyl(0.07, 0.09, 0.42, 12), trim, Vector3(1.88, 0.24, 0))
		_mi(fin, ProcMesh.cyl(0.24, 0.3, 0.08, 20), dark, Vector3(1.88, 0.04, 0))
		_mi(fin, ProcMesh.torus(0.28, 0.3, 20, 3), glow, Vector3(1.88, 0.08, 0))
		if tier >= 4:  # energy fin: a translucent cyan blade beyond the hard fin
			var ef := _mi(fin, extrude(PackedVector2Array([Vector2(1.1, 2.75), Vector2(2.0, 0.95), Vector2(2.55, 1.35), Vector2(1.6, 3.4)]), 0.02), _additive(Color(0.25, 0.75, 1.0, 0.5)), Vector3.ZERO)
			ef.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Nose beacon.
	_beacon_mat = Mats.lamp(Color(1.0, 0.4, 0.15), 4.0)
	_mi(self, ProcMesh.sphere(0.09, 12, 6), _beacon_mat, Vector3(0, HULL_TOP - 0.02, 0))
	_mi(self, ProcMesh.cyl(0.02, 0.04, 0.5, 8), trim, Vector3(0, HULL_TOP - 0.25, 0))
	# Tier extras.
	if tier >= 2:
		_add_ring(4.3, 1.75, Vector3.ZERO, 0.6, trim)
	if tier >= 3:
		_add_ring(6.3, 1.45, Vector3(0.18, 0, 0.1), -0.9, trim)
		for a_deg: float in [210.0, 330.0]:
			var a: float = deg_to_rad(a_deg)
			var p := Vector3(cos(a) * 1.32, 0, sin(a) * 1.32)
			_mi(self, ProcMesh.capsule(0.27, 2.9), pearl, p + Vector3(0, 2.75, 0))
			_mi(self, ProcMesh.cyl(0.29, 0.29, 0.18, 20), tang, p + Vector3(0, 3.6, 0))
			_mi(self, ProcMesh.torus(0.27, 0.29, 20, 3), glow, p + Vector3(0, 1.45, 0))
			_rod(self, p * 0.82 + Vector3(0, 3.0, 0), p * 0.5 + Vector3(0, 3.0, 0), 0.05, trim)
			var bp := RocketPlume.new()
			bp.scale_len = 0.55
			bp.radius = 0.24
			bp.position = p + Vector3(0, 1.3, 0)
			add_child(bp)
			_boosters.append(bp)
	if tier >= 4:
		_add_ring(8.2, 0.95, Vector3(-0.12, 0, 0.08), 1.3, trim)
		var halo := _mi(self, ProcMesh.torus(0.19, 0.21, 24, 3), _glow(Color(1.0, 0.8, 0.45), 2.5), Vector3(0, HULL_TOP + 0.35, 0))
		halo.set_meta("spin", 1.0)
	plume = RocketPlume.new()
	plume.position = Vector3(0, NOZZLE_Y, 0)
	plume.scale_len = [1.0, 1.0, 1.15, 1.3, 1.5][tier]
	plume.radius = 0.62
	add_child(plume)


func _add_ring(y: float, r: float, tilt: Vector3, spd: float, trim: Material) -> void:
	var ring := Node3D.new()
	ring.position = Vector3(0, y, 0)
	ring.rotation = tilt
	ring.set_meta("spd", spd)
	ring.set_meta("y", y)
	add_child(ring)
	_mi(ring, ProcMesh.torus(r - 0.07, r + 0.07, 56, 8), _gloss(Color(0.96, 0.96, 0.95), 0.15, 0.1, 1.0), Vector3.ZERO)
	_mi(ring, ProcMesh.torus(r - 0.085, r - 0.068, 56, 3), _glow(GLOW, 1.8), Vector3.ZERO)
	for k: int in 3:
		var a: float = TAU * k / 3.0
		_mi(ring, ProcMesh.sphere(0.09, 10, 5), trim, Vector3(cos(a) * r, 0, sin(a) * r))
	_rings.append(ring)


## Hull radius at height y (matches the lathe profile above).
static func hull_r(y: float) -> float:
	if y < 3.0:
		return lerpf(0.95, 1.05, clampf((y - 1.7) / 1.3, 0.0, 1.0))
	var k: float = clampf((y - 5.2) / (HULL_TOP - 5.2), 0.0, 1.0)
	return 1.05 * pow(1.0 - pow(k, 2.2), 0.6)


## 0..1 extra brightness on the glow parts (charging before ignition).
func set_charge(c: float) -> void:
	_charge = c


func _process(delta: float) -> void:
	_t += delta
	for ring: Node3D in _rings:
		ring.rotate_y(delta * float(ring.get_meta("spd")))
		ring.position.y = float(ring.get_meta("y")) + sin(_t * 1.3 + float(ring.get_meta("spd"))) * 0.06
	_blink -= delta
	var eye_s: float = 1.0
	if _blink < 0.12:
		eye_s = 0.15
		if _blink < 0.0:
			_blink = randf_range(2.0, 4.5)
	for e: Node3D in _eyes:
		e.scale.y = lerpf(e.scale.y, eye_s, clampf(delta * 30.0, 0.0, 1.0))
	if _beacon_mat:
		_beacon_mat.emission_energy_multiplier = 6.0 if fmod(_t, 1.2) < 0.15 else 0.4
	var pulse: float = 1.0 + _charge * (1.2 + 0.8 * sin(_t * (8.0 + 20.0 * _charge)))
	for m: StandardMaterial3D in _glow_mats:
		m.emission_energy_multiplier = float(m.get_meta("base")) * pulse
	if _engine_mat:
		_engine_mat.emission_energy_multiplier = 1.0 + _charge * 8.0 + plume.power * 10.0
	for bp: RocketPlume in _boosters:
		bp.power = plume.power * 0.85
	for c: Node in get_children():
		if c is MeshInstance3D and c.has_meta("spin"):
			(c as Node3D).rotate_y(delta * 2.0)


# --- Mesh and material helpers ----------------------------------------------------------

## Surface of revolution of a (radius, y) profile. a0..a1 limits the sweep (a partial band).
static func lathe(prof: PackedVector2Array, segs: int, a0: float = 0.0, a1: float = TAU) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = prof.size()
	# Per-profile-point 2D normals (outward), averaged over neighbouring segments.
	var nrm: Array[Vector2] = []
	for i: int in n:
		var d := Vector2.ZERO
		if i > 0:
			d += (prof[i] - prof[i - 1]).normalized()
		if i < n - 1:
			d += (prof[i + 1] - prof[i]).normalized()
		nrm.append(Vector2(d.y, -d.x).normalized())
	var cols: int = segs + 1
	var verts: Array[Vector3] = []
	var norms: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	for s: int in cols:
		var a: float = lerpf(a0, a1, float(s) / segs)
		var ca: float = cos(a)
		var sa: float = sin(a)
		for i: int in n:
			verts.append(Vector3(prof[i].x * ca, prof[i].y, prof[i].x * sa))
			norms.append(Vector3(nrm[i].x * ca, nrm[i].y, nrm[i].x * sa))
			uvs.append(Vector2(float(s) / segs, float(i) / (n - 1)))
	for s: int in segs:
		for i: int in n - 1:
			var a00: int = s * n + i
			var a10: int = (s + 1) * n + i
			for idx: int in [a00, a10, a00 + 1, a10, a10 + 1, a00 + 1]:
				st.set_normal(norms[idx])
				st.set_uv(uvs[idx])
				st.add_vertex(verts[idx])
	return st.commit()


## Prism from a polygon in the XY plane, `depth` thick along Z.
static func extrude(poly: PackedVector2Array, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri: PackedInt32Array = Geometry2D.triangulate_polygon(poly)
	var h: float = depth * 0.5
	var ccw: bool = _area(poly) > 0.0
	for side: float in [1.0, -1.0]:
		st.set_normal(Vector3(0, 0, side))
		for k: int in range(0, tri.size(), 3):
			var order: Array = [0, 2, 1] if (side > 0.0) == ccw else [0, 1, 2]
			for o: int in order:
				var p: Vector2 = poly[tri[k + o]]
				st.set_normal(Vector3(0, 0, side))
				st.add_vertex(Vector3(p.x, p.y, h * side))
	for i: int in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		var e: Vector2 = (b - a).normalized()
		var nn := Vector3(e.y, -e.x, 0) * (1.0 if ccw else -1.0)
		var quad: Array[Vector3] = [Vector3(a.x, a.y, h), Vector3(b.x, b.y, h), Vector3(b.x, b.y, -h), Vector3(a.x, a.y, -h)]
		var idx: Array = [0, 1, 2, 0, 2, 3] if ccw else [0, 2, 1, 0, 3, 2]
		for j: int in idx:
			st.set_normal(nn)
			st.add_vertex(quad[j])
	return st.commit()


static func _area(poly: PackedVector2Array) -> float:
	var s: float = 0.0
	for i: int in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


func _gloss(c: Color, rough: float, metal: float, coat: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if coat > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = coat
		m.clearcoat_roughness = 0.08
	return m


func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = Mats.lamp(c, energy)
	m.set_meta("base", energy)
	_glow_mats.append(m)
	return m


static func _additive(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
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


func _rod(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var m := _mi(parent, ProcMesh.cyl(r, r, a.distance_to(b), 8), mat, (a + b) * 0.5)
	var up: Vector3 = (b - a).normalized()
	var side: Vector3 = up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	m.basis = Basis(side, up, side.cross(up)).orthonormalized()
	return m
