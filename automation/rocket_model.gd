class_name RocketModel
extends Node3D
## The base rocket, in Lumi's design language (player/patch_model.gd, the Mk III/IV robots): a long,
## tapered pearl-white hull with a subtle waist, a recessed dark visor with Lumi's glowing C eyes
## (art/shaders/bot_face.gdshader), swept blade wings growing out of the body, landing legs that
## fold flush into the hull in flight, tangerine accents and thin, subtle cyan lines. Higher tiers
## (Mk I-IV, automation/rocket_tiers.gd) add panels, hover rings, winglets, wingtip nacelles,
## canards, gold trim and energy wing extensions.
## Local frame: +Z is the front (visor), the boarding hatch faces -Z, base of the feet at y=0.

const GLOW := Color(0.3, 0.88, 1.0)
const ACCENT := Color(1.0, 0.55, 0.18)
## Hull profile (radius, height): engine skirt, shoulder, waist, cockpit bulge, long tapered nose.
const PROFILE: Array[Vector2] = [Vector2(0.58, 1.05), Vector2(0.74, 1.25), Vector2(0.86, 1.6), Vector2(0.93, 2.1),
	Vector2(0.95, 2.6), Vector2(0.92, 3.2), Vector2(0.85, 3.9), Vector2(0.81, 4.4), Vector2(0.83, 4.9),
	Vector2(0.87, 5.6), Vector2(0.88, 6.2), Vector2(0.86, 6.9), Vector2(0.8, 7.6), Vector2(0.7, 8.3),
	Vector2(0.56, 9.0), Vector2(0.4, 9.6), Vector2(0.24, 10.15), Vector2(0.1, 10.55), Vector2(0.0, 10.75)]
const HULL_TOP: float = 10.75
const HATCH_Y: float = 5.6
const VISOR_Y: float = 7.0
## Nozzle exit (local): where the plume starts.
const NOZZLE_Y: float = 0.5
const WING_ANGLES: Array[float] = [30.0, 150.0, 270.0]
const LEG_ANGLES: Array[float] = [70.0, 190.0, 310.0]
## Where the pad's clamps hold the rocket (between the wings, clear of the legs), and at what height.
const CLAMP_ANGLES: Array[float] = [110.0, 230.0, 350.0]
const CLAMP_Y: float = 2.0
const CLAMP_BASE_R: float = 1.75
const LEG_FOLD: float = 2.75  # radians the legs swing up to lie along the hull

var tier: int = 1
var plume: RocketPlume
var hatch: Node3D
var _glow_mats: Array[StandardMaterial3D] = []
var _rings: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _face: ShaderMaterial
var _beacon_mat: StandardMaterial3D
var _engine_mat: StandardMaterial3D
var _boosters: Array[RocketPlume] = []
var _t: float = 0.0
var _blink: float = 2.0
var _blink_v: float = 0.0
var _charge: float = 0.0
var _legs_k: float = 1.0


func build(p_tier: int) -> void:
	tier = clampi(p_tier, 1, 4)
	for c: Node in get_children():
		c.queue_free()
	_glow_mats.clear()
	_rings.clear()
	_legs.clear()
	_boosters.clear()
	var pearl := _gloss(Color(0.96, 0.96, 0.95), 0.14, 0.08, 1.0)
	var pearl2 := _gloss(Color(0.88, 0.89, 0.9), 0.2, 0.15, 1.0)   # slightly darker panels
	var tang := _gloss(ACCENT, 0.22, 0.1, 1.0)
	var dark := _gloss(Color(0.04, 0.05, 0.07), 0.08, 0.4, 1.0)
	var seam := _gloss(Color(0.3, 0.32, 0.36), 0.35, 0.5, 0.0)
	var trim := _gloss(Color(1.0, 0.78, 0.38), 0.2, 1.0, 0.0) if tier >= 4 else _gloss(Color(0.62, 0.65, 0.7), 0.22, 0.9, 0.0)
	var glow := _glow(GLOW, 1.6)  # thin, subtle accent lines (never thick)
	# Hull: one smooth lathe; 20 sides give a faint faceted silhouette under smooth shading.
	_mi(self, lathe(PackedVector2Array(PROFILE), 20), pearl, Vector3.ZERO)
	_mi(self, ProcMesh.cyl(0.58, 0.58, 0.02, 20), dark, Vector3(0, 1.05, 0))
	# Panel seams (dark hairlines) and two thin cyan lines.
	for y: float in [2.6, 6.2, 9.0]:
		_ring_line(y, 0.006, seam)
	for y2: float in [4.4, 8.3]:
		_ring_line(y2, 0.008, glow)
	for a_deg: float in [0.0, 180.0]:
		var a0: float = deg_to_rad(a_deg)
		var rr: float = hull_r(5.25) + 0.004
		var vs := _mi(self, ProcMesh.box(Vector3(0.012, 1.7, 0.012)), seam, Vector3(cos(a0) * rr, 5.3, sin(a0) * rr))
		vs.rotation.y = -a0 + PI * 0.5
	# Tangerine shoulder band and nose tip.
	_band(2.18, 2.42, 0.006, tang)
	_band(HULL_TOP - 0.55, HULL_TOP, 0.006, tang)
	# Recessed visor: a curved dark glass band (Lumi's face shader) between two pearl lips.
	_build_visor(pearl)
	# Porthole on the left flank and the markings.
	var pa: float = deg_to_rad(40.0)
	var pr: float = hull_r(5.4)
	var port := Node3D.new()
	port.position = Vector3(cos(pa) * pr, 5.4, sin(pa) * pr)
	port.rotation.y = -pa + PI * 0.5
	add_child(port)
	_mi(port, ProcMesh.cyl(0.17, 0.17, 0.04, 20), dark, Vector3.ZERO, Vector3(90, 0, 0))
	_mi(port, ProcMesh.torus(0.17, 0.19, 20, 3), glow, Vector3(0, 0, 0.01), Vector3(90, 0, 0))
	var name_l := Mats.stencil("GREENFALL", 64, Color(0.22, 0.26, 0.32, 0.9))
	name_l.pixel_size = 0.0034
	name_l.position = Vector3(0, 3.45, hull_r(3.45) + 0.01)
	add_child(name_l)
	var tag := Label3D.new()
	tag.text = ["", tr("MK I"), tr("MK II"), tr("MK III"), tr("MK IV")][tier]
	tag.font_size = 64
	tag.pixel_size = 0.0028
	tag.modulate = Color(0.45, 1.3, 1.7)
	tag.outline_size = 0
	tag.shaded = false
	tag.position = Vector3(0, 3.15, hull_r(3.15) + 0.012)
	add_child(tag)
	# Boarding hatch at the back (-Z): a rounded door in a hairline glow frame.
	var hr: float = hull_r(HATCH_Y)
	_mi(self, RobotVisual._rbox(Vector3(0.74, 1.06, 0.05), 0.11, 3), glow, Vector3(0, HATCH_Y, -hr + 0.012))
	hatch = Node3D.new()
	hatch.position = Vector3(0, HATCH_Y, -hr - 0.02)
	add_child(hatch)
	_mi(hatch, RobotVisual._rbox(Vector3(0.7, 1.02, 0.07), 0.1, 3), pearl, Vector3.ZERO)
	_mi(hatch, ProcMesh.box(Vector3(0.3, 0.035, 0.02)), tang, Vector3(0, 0.3, -0.04))
	# Engine: dark bell with a cyan heart.
	var bell := PackedVector2Array([Vector2(0.36, 1.1), Vector2(0.42, 0.92), Vector2(0.54, 0.68), Vector2(0.64, NOZZLE_Y)])
	_mi(self, lathe(bell, 28), _gloss(Color(0.12, 0.13, 0.15), 0.3, 0.9, 0.0), Vector3.ZERO)
	_engine_mat = _glow(GLOW, 1.0)
	_engine_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mi(self, ProcMesh.cyl(0.38, 0.38, 0.02, 24), _engine_mat, Vector3(0, 0.98, 0))
	_mi(self, ProcMesh.torus(0.62, 0.645, 28, 3), glow, Vector3(0, NOZZLE_Y + 0.02, 0))
	# Swept blade wings, integrated into the body.
	var wing := PackedVector2Array([Vector2(0.62, 5.6), Vector2(0.62, 1.35), Vector2(2.25, 0.62), Vector2(2.55, 0.62),
		Vector2(2.48, 1.05), Vector2(1.05, 3.8)])
	for a_deg2: float in WING_ANGLES:
		var w := _radial_node(a_deg2)
		_mi(w, extrude(wing, 0.085), pearl, Vector3.ZERO)
		_mi(w, extrude(PackedVector2Array([Vector2(2.1, 0.62), Vector2(2.55, 0.62), Vector2(2.48, 1.05), Vector2(2.15, 1.6)]), 0.095), tang, Vector3.ZERO)
		_rod(w, Vector3(1.05, 3.8, 0.0), Vector3(2.15, 1.6, 0.0), 0.008, glow)
		if tier >= 2:  # winglet at the tip
			_mi(w, extrude(PackedVector2Array([Vector2(2.36, 0.95), Vector2(2.52, 0.8), Vector2(2.68, 2.05), Vector2(2.56, 2.1)]), 0.06), pearl2, Vector3.ZERO)
		if tier >= 3:  # wingtip nacelle with its own small engine
			_mi(w, ProcMesh.capsule(0.15, 1.5), pearl, Vector3(2.55, 1.2, 0))
			_mi(w, ProcMesh.torus(0.14, 0.155, 16, 3), glow, Vector3(2.55, 0.52, 0), Vector3.ZERO)
			var bp := RocketPlume.new()
			bp.scale_len = 0.45
			bp.radius = 0.13
			bp.position = Vector3(2.55, 0.45, 0)
			w.add_child(bp)
			_boosters.append(bp)
		if tier >= 4:  # energy extension beyond the trailing edge
			var ef := _mi(w, extrude(PackedVector2Array([Vector2(1.05, 3.8), Vector2(2.15, 1.6), Vector2(3.0, 1.1), Vector2(1.75, 3.95)]), 0.02), _additive(Color(0.25, 0.75, 1.0, 0.35)), Vector3.ZERO)
			ef.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Landing legs: hinged at the shoulder, deployed for the pad, folded flush in flight.
	for a_deg3: float in LEG_ANGLES:
		var base := _radial_node(a_deg3)
		_mi(base, ProcMesh.box(Vector3(0.05, 2.2, 0.2)), dark, Vector3(hull_r(3.0) - 0.02, 3.0, 0))  # recess
		var leg := Node3D.new()
		leg.position = Vector3(0.9, 1.95, 0)
		base.add_child(leg)
		var foot := Vector3(0.85, -1.95, 0)
		_rod(leg, Vector3.ZERO, foot, 0.06, trim)
		_rod(leg, Vector3(0.0, -0.6, 0), foot * 0.7, 0.035, pearl)
		_mi(leg, ProcMesh.cyl(0.16, 0.2, 0.06, 18), dark, foot + Vector3(0, 0.0, 0))
		_mi(leg, ProcMesh.torus(0.18, 0.195, 18, 3), glow, foot + Vector3(0, 0.035, 0))
		_legs.append(leg)
	set_legs(_legs_k)
	# Nose beacon.
	_beacon_mat = Mats.lamp(Color(1.0, 0.4, 0.15), 4.0)
	_mi(self, ProcMesh.sphere(0.05, 10, 5), _beacon_mat, Vector3(0, HULL_TOP + 0.02, 0))
	# Tier extras.
	if tier >= 2:  # tangerine side panels and a hover ring at the waist
		for side: float in [0.0, PI]:
			var pprof := PackedVector2Array()
			for i: int in 7:
				var yy: float = lerpf(4.9, 6.1, float(i) / 6.0)
				pprof.append(Vector2(hull_r(yy) + 0.006, yy))
			_mi(self, lathe(pprof, 8, side - 0.35, side + 0.35), pearl2, Vector3.ZERO)
		_add_ring(4.4, 1.35, Vector3.ZERO, 0.6, trim)
	if tier >= 3:
		_add_ring(7.6, 1.15, Vector3(0.14, 0, 0.08), -0.9, trim)
		var canard := PackedVector2Array([Vector2(0.5, 8.6), Vector2(0.62, 7.7), Vector2(1.05, 7.55), Vector2(0.95, 7.85)])
		for a_deg4: float in [90.0, 210.0, 330.0]:
			_mi(_radial_node(a_deg4), extrude(canard, 0.05), pearl, Vector3.ZERO)
	if tier >= 4:
		_add_ring(9.3, 0.8, Vector3(-0.1, 0, 0.06), 1.3, trim)
		var halo := _mi(self, ProcMesh.torus(0.15, 0.165, 24, 3), _glow(Color(1.0, 0.8, 0.45), 2.5), Vector3(0, HULL_TOP + 0.3, 0))
		halo.set_meta("spin", 1.0)
		_band(2.05, 2.12, 0.01, trim)
	plume = RocketPlume.new()
	plume.position = Vector3(0, NOZZLE_Y, 0)
	plume.scale_len = [1.0, 1.0, 1.15, 1.3, 1.5][tier]
	plume.radius = 0.58
	add_child(plume)


## A node at the hull's axis turned so its local +X points out along `a_deg` (lathe angle).
func _radial_node(a_deg: float) -> Node3D:
	var n := Node3D.new()
	n.rotation.y = -deg_to_rad(a_deg)
	add_child(n)
	return n


func _ring_line(y: float, w: float, mat: Material) -> void:
	var r: float = hull_r(y)
	_mi(self, ProcMesh.torus(r, r + w * 1.6, 48, 3), mat, Vector3(0, y, 0))


func _band(y0: float, y1: float, lift: float, mat: Material) -> void:
	var prof := PackedVector2Array()
	for i: int in 6:
		var y: float = lerpf(y0, y1, float(i) / 5.0)
		prof.append(Vector2(hull_r(y) + lift, y))
	_mi(self, lathe(prof, 40), mat, Vector3.ZERO)


func _build_visor(lip_mat: Material) -> void:
	var hh: float = 0.28
	var prof := PackedVector2Array()
	for i: int in 7:
		var y: float = lerpf(-hh, hh, float(i) / 6.0)
		prof.append(Vector2(hull_r(VISOR_Y + y) + 0.012, y))
	# Built around -Z then turned to face +Z, so the face shader's "front" (-Z) is the visor centre.
	var v := Node3D.new()
	v.position = Vector3(0, VISOR_Y, 0)
	v.rotation.y = PI
	add_child(v)
	_face = ShaderMaterial.new()
	_face.shader = preload("res://art/shaders/bot_face.gdshader")
	_face.set_shader_parameter("eye_color", GLOW)
	_face.set_shader_parameter("half_width", 0.62)
	_face.set_shader_parameter("half_height", hh)
	_face.set_shader_parameter("eye_spacing", 0.78)
	_face.set_shader_parameter("energy", 3.2)
	_mi(v, lathe(prof, 20, deg_to_rad(270.0 - 52.0), deg_to_rad(270.0 + 52.0)), _face, Vector3.ZERO)
	# Pearl lips above and below make the glass sit recessed in the hull.
	for y2: float in [-hh - 0.02, hh + 0.02]:
		var lip := PackedVector2Array([Vector2(hull_r(VISOR_Y + y2) + 0.0, y2 - 0.035), Vector2(hull_r(VISOR_Y + y2) + 0.035, y2), Vector2(hull_r(VISOR_Y + y2) + 0.0, y2 + 0.035)])
		_mi(v, lathe(lip, 20, deg_to_rad(270.0 - 56.0), deg_to_rad(270.0 + 56.0)), lip_mat, Vector3.ZERO)


func _add_ring(y: float, r: float, tilt: Vector3, spd: float, trim: Material) -> void:
	var ring := Node3D.new()
	ring.position = Vector3(0, y, 0)
	ring.rotation = tilt
	ring.set_meta("spd", spd)
	ring.set_meta("y", y)
	add_child(ring)
	_mi(ring, ProcMesh.torus(r - 0.045, r + 0.045, 56, 8), _gloss(Color(0.96, 0.96, 0.95), 0.15, 0.1, 1.0), Vector3.ZERO)
	_mi(ring, ProcMesh.torus(r - 0.058, r - 0.048, 56, 3), _glow(GLOW, 1.8), Vector3.ZERO)
	for k: int in 3:
		var a: float = TAU * k / 3.0
		_mi(ring, ProcMesh.sphere(0.06, 10, 5), trim, Vector3(cos(a) * r, 0, sin(a) * r))
	_rings.append(ring)


## Hull radius at height y (interpolates PROFILE).
static func hull_r(y: float) -> float:
	if y <= PROFILE[0].y:
		return PROFILE[0].x
	for i: int in range(1, PROFILE.size()):
		if y <= PROFILE[i].y:
			var a: Vector2 = PROFILE[i - 1]
			var b: Vector2 = PROFILE[i]
			return lerpf(a.x, b.x, (y - a.y) / (b.y - a.y))
	return 0.0


## 0..1 extra brightness on the glow parts (charging before ignition).
func set_charge(c: float) -> void:
	_charge = c


## 1 = legs down (standing), 0 = folded flush against the hull.
func set_legs(k: float) -> void:
	_legs_k = k
	for leg: Node3D in _legs:
		leg.rotation.z = (1.0 - k) * LEG_FOLD


func _process(delta: float) -> void:
	_t += delta
	for ring: Node3D in _rings:
		ring.rotate_y(delta * float(ring.get_meta("spd")))
		ring.position.y = float(ring.get_meta("y")) + sin(_t * 1.3 + float(ring.get_meta("spd"))) * 0.05
	_blink -= delta
	var want: float = 0.0
	if _blink < 0.12:
		want = 1.0
		if _blink < 0.0:
			_blink = randf_range(2.0, 4.5)
	_blink_v = lerpf(_blink_v, want, clampf(delta * 30.0, 0.0, 1.0))
	if _face:
		_face.set_shader_parameter("blink", _blink_v)
		_face.set_shader_parameter("energy", 3.2 + _charge * 3.0)
	if _beacon_mat:
		_beacon_mat.emission_energy_multiplier = 6.0 if fmod(_t, 1.2) < 0.15 else 0.4
	var pulse: float = 1.0 + _charge * (1.0 + 0.6 * sin(_t * (8.0 + 20.0 * _charge)))
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
