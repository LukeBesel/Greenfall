class_name CradleShip
extends Node3D
## [intro2] The ark *Cradle*, redesigned (owner playtest #1: "too long for how skinny it was").
## A broad, layered seed ship in the same language as Lumi and the rocket: pearl-white clear-coat
## hull, tangerine accent bands, thin cyan seams and running lights.
##   - main hull: a wide, flattened teardrop (about 35 m long, 19 m wide, 10 m tall)
##   - an upper deck layered on top, carrying the big glass seed-vault dome with its garden glow
##   - a ventral keel with the cargo-pod rack (six pods; the intro's pod drops from rack slot 2)
##   - the greenhouse ring: a slowly spinning glass ring around the aft hull on four spokes
##   - solar wings: two long truss arms with paired blue cell panels, swept slightly back
##   - the engine cluster: one big bell and four smaller ones, cyan-white glow
## Built procedurally (lathed bodies with analytic normals; meshes cached per run). Flies toward
## -Z. API kept for the intro, the core-charge memories and the Bloom finale: alarm, thrust,
## ring_speed, dome_world(), pod_world(k), CYAN, ALARM; new: release_pod(k).

const CYAN := Color(0.3, 0.9, 1.0)
const ALARM := Color(1.0, 0.16, 0.1)
const PEARL := Color(0.92, 0.92, 0.9)
const TANGERINE := Color(1.0, 0.5, 0.14)
const SX: float = 1.45
const SY: float = 0.78
const POD_Y: float = -6.35
const POD_Z0: float = -8.5
const POD_DZ: float = 2.7
const DOME_AT := Vector3(0, 6.3, -4.5)
const DOME_R: float = 4.4
const DOME_SY: float = 0.82
const RING_Z: float = 7.0
const RING_R: float = 13.2

## Hull profile (z, radius) nose to tail; the cross-section is an ellipse SX wide, SY tall.
const HULL: Array[Vector2] = [
	Vector2(-20.0, 0.0), Vector2(-19.75, 1.2), Vector2(-19.2, 2.3), Vector2(-18.2, 3.4), Vector2(-16.6, 4.4),
	Vector2(-14.4, 5.25), Vector2(-11.5, 5.95), Vector2(-8.0, 6.4), Vector2(-4.0, 6.65), Vector2(0.0, 6.7),
	Vector2(4.0, 6.55), Vector2(8.0, 6.1), Vector2(11.0, 5.45), Vector2(13.2, 4.7), Vector2(14.6, 4.0),
	Vector2(15.3, 3.4), Vector2(15.55, 2.4), Vector2(15.6, 0.0),
]
## The upper deck: a lower, wider lathe layered on the hull's back.
const DECK: Array[Vector2] = [
	Vector2(-14.0, 0.0), Vector2(-13.6, 1.0), Vector2(-12.4, 1.9), Vector2(-10.0, 2.6), Vector2(-6.0, 3.0),
	Vector2(-1.0, 3.1), Vector2(3.5, 2.9), Vector2(7.0, 2.4), Vector2(9.0, 1.6), Vector2(10.0, 0.7), Vector2(10.3, 0.0),
]
## The ventral keel under the belly (the pod rack hangs from it).
const KEEL: Array[Vector2] = [
	Vector2(-13.0, 0.0), Vector2(-12.4, 1.0), Vector2(-10.5, 1.7), Vector2(-6.0, 2.0), Vector2(2.0, 2.0),
	Vector2(6.0, 1.7), Vector2(8.0, 1.0), Vector2(8.6, 0.0),
]

static var _built: Dictionary = {}

## 0..1: seams pulse red (meteor storm).
var alarm: float = 0.0
## Engine glow multiplier.
var thrust: float = 1.0
var ring_speed: float = 0.12

var _ring: Node3D
var _glow: StandardMaterial3D
var _engine: StandardMaterial3D
var _vault: StandardMaterial3D
var _nav: StandardMaterial3D
var _plume: StandardMaterial3D
var _pods: Array[Node3D] = []
var _lights: MultiMeshInstance3D
var _light_z: Array[float] = []
var _t: float = 0.0
var _vault_light: OmniLight3D


# --- Mesh building --------------------------------------------------------------------

static func _r_at(profile: Array[Vector2], z: float) -> float:
	if z <= profile[0].x:
		return profile[0].y
	for i: int in profile.size() - 1:
		if z <= profile[i + 1].x:
			var k: float = (z - profile[i].x) / maxf(profile[i + 1].x - profile[i].x, 0.0001)
			return lerpf(profile[i].y, profile[i + 1].y, k * k * (3.0 - 2.0 * k) * 0.35 + k * 0.65)
	return profile[-1].y


## Emits a triangle facing along its normals (Godot's front faces wind clockwise).
static func _tri(st: SurfaceTool, p: Array[Vector3], n: Array[Vector3], uv: Array[Vector2]) -> void:
	var g: Vector3 = (p[1] - p[0]).cross(p[2] - p[0])
	var flip: bool = g.dot(n[0] + n[1] + n[2]) >= 0.0
	for k: int in ([0, 2, 1] if flip else [0, 1, 2]):
		st.set_normal(n[k])
		st.set_uv(uv[k])
		st.add_vertex(p[k])


static func _st_for(sts: Dictionary, key: String) -> SurfaceTool:
	if not sts.has(key):
		var s := SurfaceTool.new()
		s.begin(Mesh.PRIMITIVE_TRIANGLES)
		sts[key] = s
	return sts[key]


## A lathed body around the Z axis with an elliptical cross-section. mat_of(z, angle) picks the
## surface per quad (angle 0 = +X side, PI/2 = top). Analytic normals: no seams between bands.
static func _lathe(sts: Dictionary, profile: Array[Vector2], center: Vector3, sx: float, sy: float, segs: int, rows: int, mat_of: Callable, breaks: Array[float] = []) -> void:
	var z0: float = profile[0].x
	var z1: float = profile[-1].x
	var pos := func(z: float, a: float) -> Vector3:
		var r: float = _r_at(profile, z)
		return center + Vector3(cos(a) * r * sx, sin(a) * r * sy, z)
	var nrm := func(z: float, a: float) -> Vector3:
		var out := Vector3(cos(a) / sx, sin(a) / sy, 0.0).normalized()
		var e: float = 0.03
		var ra: float = _r_at(profile, maxf(z - e, z0))
		var rb: float = _r_at(profile, minf(z + e, z1))
		var slope: float = (ra - rb) / (minf(z + e, z1) - maxf(z - e, z0))
		if z <= z0 + 0.001:
			return Vector3(0, 0, -1)
		if z >= z1 - 0.001:
			return Vector3(0, 0, 1)
		return (out + Vector3(0, 0, slope)).normalized()
	var zs: Array[float] = []
	for i: int in rows + 1:
		var u: float = float(i) / rows
		u = 0.5 - 0.5 * cos(u * PI)  # denser near the rounded ends
		zs.append(lerpf(z0, z1, u))
	# Band edges get their own rows so thin seams stay thin.
	for b: float in breaks:
		if b > z0 and b < z1:
			zs.append(b)
	zs.sort()
	var k: int = zs.size() - 1
	while k > 0:
		if zs[k] - zs[k - 1] < 0.02:
			zs.remove_at(k)
		k -= 1
	rows = zs.size() - 1
	for i: int in rows:
		for j: int in segs:
			var a0: float = TAU * j / segs
			var a1: float = TAU * (j + 1) / segs
			var za: float = zs[i]
			var zb: float = zs[i + 1]
			var st: SurfaceTool = _st_for(sts, mat_of.call((za + zb) * 0.5, (a0 + a1) * 0.5))
			var p00: Vector3 = pos.call(za, a0)
			var p10: Vector3 = pos.call(za, a1)
			var p11: Vector3 = pos.call(zb, a1)
			var p01: Vector3 = pos.call(zb, a0)
			var n00: Vector3 = nrm.call(za, a0)
			var n10: Vector3 = nrm.call(za, a1)
			var n11: Vector3 = nrm.call(zb, a1)
			var n01: Vector3 = nrm.call(zb, a0)
			var u00 := Vector2(a0 / TAU * 6.0, za * 0.08)
			var u10 := Vector2(a1 / TAU * 6.0, za * 0.08)
			var u11 := Vector2(a1 / TAU * 6.0, zb * 0.08)
			var u01 := Vector2(a0 / TAU * 6.0, zb * 0.08)
			if p00.distance_to(p10) > 0.0001:
				_tri(st, [p00, p10, p11] as Array[Vector3], [n00, n10, n11] as Array[Vector3], [u00, u10, u11] as Array[Vector2])
			if p11.distance_to(p01) > 0.0001:
				_tri(st, [p00, p11, p01] as Array[Vector3], [n00, n11, n01] as Array[Vector3], [u00, u11, u01] as Array[Vector2])


## A thin tube along a half circle (a dome rib) in the XY plane, from +X over the top to -X.
static func _arc_mesh(radius: float, sy: float, thick: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_a: int = 48
	var n_t: int = 6
	var pt := func(i: int) -> Vector3: return Vector3(cos(PI * i / n_a) * radius, sin(PI * i / n_a) * radius * sy, 0)
	for i: int in n_a:
		var c0: Vector3 = pt.call(i)
		var c1: Vector3 = pt.call(i + 1)
		var d0: Vector3 = Vector3(c0.x, c0.y / (sy * sy), 0).normalized()
		var d1: Vector3 = Vector3(c1.x, c1.y / (sy * sy), 0).normalized()
		for k: int in n_t:
			var b0: float = TAU * k / n_t
			var b1: float = TAU * (k + 1) / n_t
			var o00: Vector3 = d0 * cos(b0) + Vector3(0, 0, 1) * sin(b0)
			var o01: Vector3 = d0 * cos(b1) + Vector3(0, 0, 1) * sin(b1)
			var o10: Vector3 = d1 * cos(b0) + Vector3(0, 0, 1) * sin(b0)
			var o11: Vector3 = d1 * cos(b1) + Vector3(0, 0, 1) * sin(b1)
			var uv: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
			_tri(st, [c0 + o00 * thick, c1 + o10 * thick, c1 + o11 * thick] as Array[Vector3], [o00, o10, o11] as Array[Vector3], uv)
			_tri(st, [c0 + o00 * thick, c1 + o11 * thick, c0 + o01 * thick] as Array[Vector3], [o00, o11, o01] as Array[Vector3], uv)
	return st.commit()


static func _in(z: float, a: float, b: float) -> bool:
	return z >= a and z <= b


## Hull bands: tangerine accent belts, thin cyan seams, a dark cabin-window strip down each side
## with a hairline of light above it, a grey belly.
static func _hull_mat(z: float, a: float) -> String:
	var up: float = sin(a)
	var side: float = absf(cos(a))
	if _in(z, -9.55, -8.95) or _in(z, 10.9, 11.5):
		return "accent"
	if _in(z, -13.3, -13.2) or _in(z, 2.9, 2.98) or _in(z, 13.5, 13.58):
		return "glow"
	if up < -0.82:
		return "trim"
	if side > 0.9 and up > 0.16 and up < 0.34 and _in(z, -16.0, 9.5):
		return "glass"
	return "hull"


static func _deck_mat(z: float, a: float) -> String:
	if sin(a) < 0.0:
		return "trim"
	if _in(z, -11.7, -11.45) or _in(z, 6.55, 6.8):
		return "glow"
	if absf(cos(a)) > 0.8 and sin(a) > 0.15 and _in(z, -10.5, 6.0):
		return "glass"
	return "hull"


static func _keel_mat(z: float, a: float) -> String:
	if _in(z, -11.3, -11.05):
		return "glow"
	return "trim" if sin(a) > -0.5 else "hull"


static func _commit(sts: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: String in sts:
		var st: SurfaceTool = sts[k]
		st.generate_tangents()
		out[k] = st.commit()
	return out


static func _build_meshes() -> void:
	if not _built.is_empty():
		return
	var hull_sts: Dictionary = {}
	_lathe(hull_sts, HULL, Vector3.ZERO, SX, SY, 72, 64, _hull_mat, [-9.55, -8.95, 10.9, 11.5, -13.3, -13.2, 2.9, 2.98, 13.5, 13.58, -16.0, 9.5] as Array[float])
	_lathe(hull_sts, DECK, Vector3(0, 4.55, 0), 1.65, 0.62, 56, 40, _deck_mat, [-11.7, -11.45, 6.55, 6.8, -10.5, 6.0] as Array[float])
	_lathe(hull_sts, KEEL, Vector3(0, -4.7, 0), 1.0, 0.55, 40, 30, _keel_mat, [-11.3, -11.05] as Array[float])
	_built["hull"] = _commit(hull_sts)
	_built["solar"] = _solar_texture()
	_built["rib"] = _arc_mesh(DOME_R + 0.02, DOME_SY, 0.07)


static func _solar_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y: int in 64:
		for x: int in 64:
			var c := Color(0.05, 0.1, 0.24)
			if x % 16 == 0 or y % 16 == 0:
				c = Color(0.62, 0.68, 0.75)
			elif x % 16 == 8 or y % 16 == 8:
				c = Color(0.1, 0.16, 0.3)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# --- Node -----------------------------------------------------------------------------

func _ready() -> void:
	_build_meshes()
	var hull := StandardMaterial3D.new()
	hull.albedo_color = PEARL
	hull.roughness = 0.26
	hull.metallic = 0.05
	hull.clearcoat_enabled = true
	hull.clearcoat = 0.8
	hull.clearcoat_roughness = 0.12
	hull.rim_enabled = true
	hull.rim = 0.2
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.02, 0.03, 0.045)
	glass.metallic = 0.7
	glass.roughness = 0.06
	glass.emission_enabled = true
	glass.emission = Color(0.65, 0.85, 0.85)
	glass.emission_energy_multiplier = 0.3
	_glow = Mats.lamp(CYAN, 2.6)
	var accent := StandardMaterial3D.new()
	accent.albedo_color = TANGERINE
	accent.roughness = 0.3
	accent.clearcoat_enabled = true
	accent.emission_enabled = true
	accent.emission = Color(1.0, 0.45, 0.1)
	accent.emission_energy_multiplier = 0.2
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.17, 0.18, 0.2)
	trim.metallic = 0.6
	trim.roughness = 0.35
	var mats: Dictionary = {"hull": hull, "glass": glass, "glow": _glow, "accent": accent, "trim": trim}
	var meshes: Dictionary = _built["hull"]
	for k: String in meshes:
		var mi := MeshInstance3D.new()
		mi.name = "Hull_" + k
		mi.mesh = meshes[k]
		mi.material_override = mats.get(k, hull)
		add_child(mi)
	_build_dome(hull)
	_build_ring(hull, accent, trim)
	_build_wings(hull, trim)
	_build_engines(hull, trim, accent)
	_build_pods(accent)
	_build_running_lights()


func _add(mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	(parent if parent else self).add_child(mi)
	return mi


## The seed vault: a big glass dome on the upper deck, a garden glowing inside, white ribs.
func _build_dome(hull: StandardMaterial3D) -> void:
	_add(ProcMesh.cyl(DOME_R + 0.3, DOME_R + 0.9, 0.8, 64), hull, DOME_AT + Vector3(0, -0.3, 0))
	_add(ProcMesh.torus(DOME_R + 0.02, DOME_R + 0.3, 64, 8), _glow, DOME_AT + Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(1, 0.22, 1))
	_vault = Mats.lamp(Color(0.45, 0.95, 0.5), 0.9)
	_vault.albedo_color = Color(0.2, 0.5, 0.22)
	var hm := SphereMesh.new()
	hm.radius = DOME_R * 0.92
	hm.height = DOME_R * 0.92
	hm.is_hemisphere = true
	hm.radial_segments = 48
	hm.rings = 12
	_add(hm, _vault, DOME_AT + Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(1, 0.4, 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var leaf := Mats.lamp(Color(0.4, 1.0, 0.45), 1.2)
	leaf.albedo_color = Color(0.25, 0.65, 0.25)
	for i: int in 16:
		var a: float = rng.randf() * TAU
		var r: float = rng.randf_range(0.5, DOME_R * 0.72)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		_add(ProcMesh.sphere(rng.randf_range(0.45, 0.85), 10, 6), leaf, DOME_AT + p + Vector3(0, 0.55 + 1.35 * (1.0 - r / DOME_R), 0))
	var dm := SphereMesh.new()
	dm.radius = DOME_R
	dm.height = DOME_R
	dm.is_hemisphere = true
	dm.radial_segments = 64
	dm.rings = 20
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.6, 0.9, 0.95, 0.16)
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.roughness = 0.03
	dmat.metallic = 0.4
	dmat.rim_enabled = true
	dmat.rim = 0.9
	dmat.rim_tint = 0.3
	var dome := _add(dm, dmat, DOME_AT, Vector3.ZERO, Vector3(1, DOME_SY, 1))
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rib_m := StandardMaterial3D.new()
	rib_m.albedo_color = PEARL
	rib_m.roughness = 0.3
	for k: int in 6:
		_add(_built["rib"], rib_m, DOME_AT, Vector3(0, PI * k / 6.0, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lat_y: float = 0.62
	_add(ProcMesh.torus(DOME_R * sqrt(1.0 - lat_y * lat_y) - 0.02, DOME_R * sqrt(1.0 - lat_y * lat_y) + 0.05, 64, 4), _glow,
		DOME_AT + Vector3(0, DOME_R * DOME_SY * lat_y, 0), Vector3.ZERO, Vector3(1, 0.5, 1))
	_vault_light = OmniLight3D.new()
	_vault_light.light_color = Color(0.55, 1.0, 0.7)
	_vault_light.light_energy = 2.0
	_vault_light.omni_range = 9.0
	_vault_light.position = DOME_AT + Vector3(0, 1.6, 0)
	add_child(_vault_light)


## The greenhouse ring: two pearl rims with a glowing glass band between, on four spokes.
func _build_ring(hull: StandardMaterial3D, accent: StandardMaterial3D, trim: StandardMaterial3D) -> void:
	_ring = Node3D.new()
	_ring.name = "ring"
	_ring.position = Vector3(0, 0, RING_Z)
	add_child(_ring)
	var flat := Vector3(PI * 0.5, 0, 0)
	for dz: float in [-0.95, 0.95]:
		_add(ProcMesh.torus(RING_R - 0.55, RING_R + 0.55, 96, 12), hull, Vector3(0, 0, dz), flat, Vector3.ONE, _ring)
	var gm := Mats.lamp(Color(0.5, 1.0, 0.6), 0.7)
	gm.albedo_color = Color(0.18, 0.4, 0.25)
	gm.metallic = 0.5
	gm.roughness = 0.08
	_add(ProcMesh.torus(RING_R - 0.5, RING_R + 0.5, 96, 12), gm, Vector3.ZERO, flat, Vector3(1, 1.25, 1), _ring)
	_add(ProcMesh.torus(RING_R + 0.42, RING_R + 0.6, 96, 4), accent, Vector3(0, 0, -1.55), flat, Vector3(1, 0.35, 1), _ring)
	for k: int in 4:
		var a: float = TAU * k / 4.0 + PI * 0.25
		_add(ProcMesh.cyl(0.32, 0.42, RING_R - 3.0, 12), trim, Vector3(cos(a), sin(a), 0) * (RING_R * 0.5 + 1.4), Vector3(0, 0, a - PI * 0.5), Vector3.ONE, _ring)
		_add(ProcMesh.sphere(0.62, 12, 6), hull, Vector3(cos(a), sin(a), 0) * (RING_R - 0.6), Vector3.ZERO, Vector3.ONE, _ring)


## Solar wings: a truss arm each side with two pairs of blue cell panels, swept slightly back.
func _build_wings(hull: StandardMaterial3D, trim: StandardMaterial3D) -> void:
	var cells := StandardMaterial3D.new()
	cells.albedo_texture = _built["solar"]
	cells.uv1_scale = Vector3(5.0, 3.0, 1.0)
	cells.metallic = 0.6
	cells.roughness = 0.22
	cells.emission_enabled = true
	cells.emission = Color(0.1, 0.25, 0.6)
	cells.emission_energy_multiplier = 0.2
	_nav = Mats.lamp(Color(0.85, 0.97, 1.0), 4.0)
	for side: float in [-1.0, 1.0]:
		var wing := Node3D.new()
		wing.position = Vector3(side * 8.2, 0.6, -3.5)
		wing.rotation = Vector3(0, side * -0.12, side * 0.04)
		add_child(wing)
		_add(ProcMesh.cyl(0.26, 0.34, 19.0, 10), trim, Vector3(side * 9.5, 0, 0), Vector3(0, 0, PI * 0.5), Vector3.ONE, wing)
		_add(ProcMesh.rounded_box(Vector3(2.4, 1.4, 2.8), 0.4, 3), hull, Vector3(side * 0.4, 0, 0), Vector3.ZERO, Vector3.ONE, wing)
		for k: int in 2:
			var x: float = side * (4.2 + k * 7.6)
			for f: float in [-1.0, 1.0]:
				_add(ProcMesh.box(Vector3(7.0, 0.1, 3.0)), cells, Vector3(x, 0, f * 1.85), Vector3.ZERO, Vector3.ONE, wing)
				_add(ProcMesh.box(Vector3(7.2, 0.15, 0.12)), hull, Vector3(x, 0, f * 3.38), Vector3.ZERO, Vector3.ONE, wing)
			_add(ProcMesh.rounded_box(Vector3(0.5, 0.5, 7.0), 0.12, 2), hull, Vector3(x + side * 3.6, 0, 0), Vector3.ZERO, Vector3.ONE, wing)
		var tip := _add(ProcMesh.sphere(0.2, 10, 6), _nav, Vector3(side * 19.2, 0, 0), Vector3.ZERO, Vector3.ONE, wing)
		tip.name = "NavTip"


## The engine cluster: one big bell and four smaller ones around it, glowing cyan-white.
func _build_engines(hull: StandardMaterial3D, trim: StandardMaterial3D, accent: StandardMaterial3D) -> void:
	_engine = Mats.lamp(Color(0.6, 0.95, 1.0), 6.0)
	_plume = StandardMaterial3D.new()
	_plume.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_plume.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_plume.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_plume.cull_mode = BaseMaterial3D.CULL_DISABLED
	_plume.albedo_texture = EscapePod._soft_tex()
	_plume.albedo_color = Color(0.45, 0.85, 1.0, 0.1)
	_plume.disable_fog = true
	var flat := Vector3(PI * 0.5, 0, 0)
	_add(ProcMesh.cyl(4.0, 3.3, 1.4, 48), trim, Vector3(0, 0, 15.6), flat)
	_add(ProcMesh.torus(3.75, 4.15, 48, 8), accent, Vector3(0, 0, 15.15), flat)
	var spots: Array[Vector3] = [Vector3.ZERO]
	for k: int in 4:
		var a: float = TAU * k / 4.0 + PI * 0.25
		spots.append(Vector3(cos(a) * 2.75, sin(a) * 2.2, 0))
	var bm := Mats.metal("dark_steel")
	bm = bm.duplicate()
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i: int in spots.size():
		var big: bool = i == 0
		var r0: float = 1.2 if big else 0.6
		var r1: float = 1.9 if big else 0.95
		var ln: float = 2.6 if big else 1.6
		var cm := CylinderMesh.new()
		cm.top_radius = r0
		cm.bottom_radius = r1
		cm.height = ln
		cm.radial_segments = 32
		cm.cap_top = false
		cm.cap_bottom = false
		_add(cm, bm, spots[i] + Vector3(0, 0, 16.3 + ln * 0.5), flat)
		_add(ProcMesh.torus(r1 - 0.06, r1 + 0.06, 32, 4), hull, spots[i] + Vector3(0, 0, 16.3 + ln), flat)
		_add(ProcMesh.cyl(r0 * 0.95, r0 * 0.95, 0.05, 24), _engine, spots[i] + Vector3(0, 0, 16.4), flat)
		# A faint heat shimmer instead of solid plumes: a soft additive disc just past each bell.
		var pm := QuadMesh.new()
		pm.size = Vector2(r1 * 2.6, r1 * 2.6)
		_add(pm, _plume, spots[i] + Vector3(0, 0, 16.3 + ln + 0.15), Vector3(0, PI, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The cargo-pod rack under the keel: six small pearl pods with tangerine collars.
func _build_pods(accent: StandardMaterial3D) -> void:
	var pm := StandardMaterial3D.new()
	pm.albedo_color = PEARL
	pm.roughness = 0.3
	pm.clearcoat_enabled = true
	var dark: StandardMaterial3D = Mats.metal("dark_steel")
	for k: int in 6:
		var pod := Node3D.new()
		pod.position = Vector3(0, POD_Y, POD_Z0 + k * POD_DZ)
		add_child(pod)
		_add(ProcMesh.sphere(0.95, 24, 12), pm, Vector3.ZERO, Vector3.ZERO, Vector3(0.95, 1.15, 0.95), pod)
		_add(ProcMesh.torus(0.78, 0.92, 24, 6), accent, Vector3(0, 0.45, 0), Vector3.ZERO, Vector3(1, 0.5, 1), pod)
		_add(ProcMesh.cyl(0.18, 0.22, 0.9, 8), dark, Vector3(0, 1.2, 0), Vector3.ZERO, Vector3.ONE, pod)
		_pods.append(pod)


## Thin running lights: tiny cyan-white points down the spine and along the flanks, a slow chase
## toward the tail.
func _build_running_lights() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = ProcMesh.sphere(0.08, 6, 3)
	var xs: Array[Vector3] = []
	var z: float = -17.0
	while z < 13.5:
		var r: float = _r_at(HULL, z)
		var dr: float = _r_at(DECK, z)
		if dr > 0.2 and absf(z - DOME_AT.z) > DOME_R + 1.0:
			xs.append(Vector3(0, 4.55 + dr * 0.62 + 0.04, z))
		for s: float in [-1.0, 1.0]:
			xs.append(Vector3(s * cos(0.06) * r * SX, sin(0.06) * r * SY, z))
		z += 1.2
	mm.instance_count = xs.size()
	for i: int in xs.size():
		mm.set_instance_transform(i, Transform3D(Basis(), xs[i]))
		mm.set_instance_color(i, Color(1, 1, 1))
		_light_z.append(xs[i].z)
	_lights = MultiMeshInstance3D.new()
	_lights.name = "RunningLights"
	_lights.multimesh = mm
	var m := Mats.lamp(Color(0.75, 0.95, 1.0), 3.0)
	m.vertex_color_use_as_albedo = true
	_lights.material_override = m
	_lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lights)


## The seed-vault dome's centre in world space.
func dome_world() -> Vector3:
	return global_transform * (DOME_AT + Vector3(0, 1.2, 0))


## Where the cargo pods hang (k = 0..5) in world space.
func pod_world(k: int = 2) -> Vector3:
	return global_transform * Vector3(0, POD_Y, POD_Z0 + clampi(k, 0, 5) * POD_DZ)


## Hide a rack pod (it has been blown loose); release_pod(k, false) puts it back.
func release_pod(k: int, gone: bool = true) -> void:
	if k >= 0 and k < _pods.size():
		_pods[k].visible = not gone


func _process(delta: float) -> void:
	_t += delta
	if _ring:
		_ring.rotate_object_local(Vector3(0, 0, 1), delta * ring_speed)
	var pulse: float = 0.5 + 0.5 * sin(_t * 9.0)
	var a: float = clampf(alarm, 0.0, 1.0)
	_glow.emission = CYAN.lerp(ALARM, a * (0.55 + 0.45 * pulse))
	_glow.emission_energy_multiplier = 2.6 + a * pulse * 3.0
	_engine.emission_energy_multiplier = 6.0 * thrust + sin(_t * 23.0) * 0.3
	_plume.albedo_color.a = 0.35 * clampf(thrust, 0.0, 1.5) + sin(_t * 31.0) * 0.02
	_vault.emission_energy_multiplier = 0.9 + sin(_t * 1.3) * 0.15
	_vault_light.light_color = Color(0.55, 1.0, 0.7).lerp(ALARM, a * pulse)
	_nav.emission_energy_multiplier = 4.0 if fmod(_t, 1.6) < 0.12 else 0.4
	# Running lights: a slow chase toward the tail (red in the storm), updated ten times a second.
	if _lights and fmod(_t, 0.1) < delta:
		var mm: MultiMesh = _lights.multimesh
		var head: float = fmod(_t * 9.0, 34.0) - 18.0
		for i: int in _light_z.size():
			var b: float = 0.35 + 0.65 * clampf(1.0 - absf(_light_z[i] - head) / 3.0, 0.0, 1.0)
			mm.set_instance_color(i, Color(b, b, b).lerp(Color(ALARM.r * b, ALARM.g * b, ALARM.b * b), a))
