class_name CradleShip
extends Node3D
## The ark *Cradle*: the ship the Settlers sleep on, with the last plants under glass.
## [v11film] Redesigned for the opening film (owner: "the rocket design is bad": it was a toy
## space plane of a few big flat polygons, with a handle-like hoop, no windows and no sense of
## size). Now it is built to read as a huge, old, quiet ship in one look, in the Seedglider's
## colours (pearl, tangerine, graphite, thin cyan lines, a teal bridge visor):
##   - a long whale-backed hull of pearl plates (art/shaders/ark_hull.gdshader draws the plates and
##     four decks of small lit windows along each flank: the sleepers' decks)
##   - the garden dome on its back (ribbed glass, small trees inside, a green glow): the seed
##     vault, where Lumi lives. `breach` breaks a hole in it
##   - a slowly turning ring round the aft hull on four spokes, its rim lit with windows
##   - an engine block: one main bell and four nacelles (they go dark with `thrust` 0)
##   - a keel with six drop pods docked under it (story/escape_pod.gd)
##   - a bridge visor on the nose, a dish on the back, running lights nose to tail
## All built in code (no model file), about 46 m long; flies toward -Z.
## API (the intro, the core-charge memories, the Bloom finale, the Homecoming): alarm, thrust,
## ring_speed, power, breach, dome_world(), breach_world(), engine_world(), dock_world(), pod_world(k),
## pod_xform(k), release_pod(k), wake_points(), CYAN, ALARM, PEARL, TANGERINE.

const CYAN := Color(0.3, 0.9, 1.0)
const ALARM := Color(1.0, 0.16, 0.1)
const PEARL := Color(0.93, 0.93, 0.91)
const TANGERINE := Color(1.0, 0.5, 0.16)
const GRAPHITE := Color(0.19, 0.21, 0.24)
const PLATE := Color(0.72, 0.74, 0.77)
const POD_Y: float = -7.05
const POD_Z0: float = -8.5
const POD_DZ: float = 2.7
const DOME_AT := Vector3(0, 4.9, -4.5)
const DOME_R: float = 4.2
const DOME_SY: float = 0.85
const RING_Z: float = 8.5
const RING_R: float = 12.0
## The docking port under the belly, ahead of the pod row.
const DOCK_Z: float = -13.0
## The hull is wider than it is tall.
const HULL_SX: float = 1.3
const HULL_SHADER := preload("res://art/shaders/ark_hull.gdshader")
const DOME_SHADER := preload("res://art/shaders/ark_dome.gdshader")
## The hull's profile, nose to tail: (z, radius).
const PROFILE: Array[Vector2] = [
	Vector2(-23.0, 0.0), Vector2(-22.7, 0.9), Vector2(-21.9, 1.9), Vector2(-20.6, 2.8), Vector2(-18.8, 3.55),
	Vector2(-16.5, 4.1), Vector2(-14.3, 4.42), Vector2(-13.7, 4.47), Vector2(-10.0, 4.72), Vector2(-5.0, 4.8),
	Vector2(5.0, 4.8), Vector2(9.5, 4.6), Vector2(12.0, 4.32), Vector2(13.0, 4.18), Vector2(15.5, 3.7),
	Vector2(17.6, 3.2), Vector2(18.0, 3.65), Vector2(21.0, 3.55), Vector2(21.4, 2.7), Vector2(21.4, 0.0),
]

## 0..1: windows, seams and running lights pulse red (the meteor storm).
var alarm: float = 0.0
## Engine glow multiplier (0 = engines dead).
var thrust: float = 1.0
## How fast the ring turns and the line lights breathe.
var ring_speed: float = 0.12
## 0..1: how many windows are lit (the storm puts half the ship in the dark).
var power: float = 1.0
## 0..1: a hole broken in the garden dome (toward `breach_dir`, in the dome's own space).
var breach: float = 0.0
var breach_dir := Vector3(0.75, 0.55, -0.35)

var _ring: Node3D
var _hull_mat: ShaderMaterial
var _ring_mat: ShaderMaterial
var _dome_mat: ShaderMaterial
var _glow: StandardMaterial3D
var _engine: StandardMaterial3D
var _vault: StandardMaterial3D
var _nav: StandardMaterial3D
var _plume: StandardMaterial3D
var _pods: Array[Node3D] = []
var _lights: MultiMeshInstance3D
var _light_z: Array[float] = []
var _flank: Array[Vector3] = []
var _t: float = 0.0
var _vault_light: OmniLight3D
var _engine_light: OmniLight3D


# --- Mesh helpers ------------------------------------------------------------------------

## The hull's radius at z (before the sideways stretch).
static func radius_at(z: float) -> float:
	if z <= PROFILE[0].x or z >= PROFILE[-1].x:
		return 0.0
	for i: int in PROFILE.size() - 1:
		if z >= PROFILE[i].x and z <= PROFILE[i + 1].x and PROFILE[i + 1].x > PROFILE[i].x:
			return lerpf(PROFILE[i].y, PROFILE[i + 1].y, (z - PROFILE[i].x) / (PROFILE[i + 1].x - PROFILE[i].x))
	return 0.0


## A point on the hull's skin: `a` radians from the top (positive toward +X), `out` metres proud.
static func skin(z: float, a: float, out: float = 0.0) -> Vector3:
	var r: float = radius_at(z)
	return Vector3(sin(a) * (r * HULL_SX + out), cos(a) * (r + out), z)


static func skin_normal(_z: float, a: float) -> Vector3:
	return Vector3(sin(a) / HULL_SX, cos(a), 0.0).normalized()


## One quad ([point, normal, uv] x 4) as two triangles, wound so its front is the side the
## normals point to (Godot's front faces are clockwise).
static func _emit(st: SurfaceTool, quad: Array, col: Color) -> void:
	var p0: Vector3 = quad[0][0]
	var order: Array[int] = [0, 1, 2, 0, 2, 3]
	var n: Vector3 = (quad[0][1] as Vector3) + (quad[2][1] as Vector3)
	var geo: Vector3 = ((quad[2][0] as Vector3) - p0).cross((quad[1][0] as Vector3) - p0)
	if geo.length() < 0.000001:
		geo = ((quad[3][0] as Vector3) - p0).cross((quad[2][0] as Vector3) - p0)
	if geo.dot(n) < 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for k: int in order:
		st.set_color(col)
		st.set_normal(quad[k][1])
		st.set_uv(quad[k][2])
		st.add_vertex(quad[k][0])


## A shape turned round the Z axis from rows of [z, radius, colour] (colour.a = windows allowed),
## stretched sideways by sx. Smooth round the axis; each row band keeps its own colour.
## UV: x = metres round the shape, y = metres along it.
static func lathe(rows: Array, sides: int, sx: float = 1.0, girth: float = 30.0, a_from: float = 0.0, a_to: float = TAU) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in rows.size() - 1:
		var z0: float = float(rows[i][0])
		var r0: float = float(rows[i][1])
		var z1: float = float(rows[i + 1][0])
		var r1: float = float(rows[i + 1][1])
		var col: Color = rows[i][2]
		var slope := Vector2(z1 - z0, r1 - r0)
		if slope.length() < 0.0001:
			continue
		# Outward normal of this band in the (z, r) plane.
		var nz: float = -slope.y / slope.length()
		var nr: float = slope.x / slope.length()
		for j: int in sides:
			var a0: float = lerpf(a_from, a_to, float(j) / sides)
			var a1: float = lerpf(a_from, a_to, float(j + 1) / sides)
			var quad: Array = []
			for c: Array in [[a0, z0, r0], [a1, z0, r0], [a1, z1, r1], [a0, z1, r1]]:
				var a: float = float(c[0])
				var p := Vector3(sin(a) * float(c[2]) * sx, cos(a) * float(c[2]), float(c[1]))
				var n := Vector3(sin(a) * nr / sx, cos(a) * nr, nz).normalized()
				quad.append([p, n, Vector2(a / TAU * girth, float(c[1]))])
			_emit(st, quad, col)
	return st.commit()


## A ring round the Z axis: major radius `big`, tube half sizes (radial, axial). Windows are
## allowed on its outer shoulders. UV in metres.
static func ring_mesh(big: float, ra: float, rz: float, major: int = 64, minor: int = 12) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var around: float = TAU * big
	var tube: float = PI * (ra + rz)
	for i: int in major:
		for j: int in minor:
			var mid: float = TAU * (j + 0.5) / minor  # 0 = the outer rim, PI/2 = facing aft (+Z)
			var win: bool = absf(sin(mid)) > 0.45 and cos(mid) > -0.2
			var band: bool = cos(mid) > 0.92
			var col: Color = (GRAPHITE if band else PEARL)
			col.a = 1.0 if win else 0.0
			var quad: Array = []
			for c: Array in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
				var u: float = TAU * float(c[0]) / major
				var v: float = TAU * float(c[1]) / minor
				var rad: float = big + cos(v) * ra
				var p := Vector3(sin(u) * rad, cos(u) * rad, sin(v) * rz)
				var n := Vector3(sin(u) * cos(v) / ra, cos(u) * cos(v) / ra, sin(v) / rz).normalized()
				quad.append([p, n, Vector2(float(c[0]) / major * around, float(c[1]) / minor * tube)])
			_emit(st, quad, col)
	return st.commit()


## The dome's glass: a cap of a sphere standing on +Y. UV.x = round it (0..1), UV.y = rim to top.
static func dome_mesh(radius: float, squash: float, sides: int = 48, rings: int = 14) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in rings:
		for j: int in sides:
			var quad: Array = []
			for c: Array in [[i, j], [i, j + 1], [i + 1, j + 1], [i + 1, j]]:
				var el: float = PI * 0.5 * float(c[0]) / rings
				var az: float = TAU * float(c[1]) / sides
				var d := Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az))
				quad.append([Vector3(d.x * radius, d.y * radius * squash, d.z * radius), Vector3(d.x, d.y / squash, d.z).normalized(), Vector2(float(c[1]) / sides, float(c[0]) / rings)])
			_emit(st, quad, Color.WHITE)
	return st.commit()


static func hull_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = HULL_SHADER
	return m


static func dome_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = DOME_SHADER
	return m


func _add(mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	(parent if parent else self).add_child(mi)
	return mi


## A bar from a to b (a rounded box: spokes, pylons, masts).
func _beam(a: Vector3, b: Vector3, w: float, h: float, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var dir: Vector3 = (b - a).normalized()
	var up: Vector3 = Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var x: Vector3 = up.cross(dir).normalized()
	var mi := MeshInstance3D.new()
	mi.mesh = ProcMesh.rounded_box(Vector3(w, h, a.distance_to(b)), minf(w, h) * 0.25, 2)
	mi.material_override = mat
	mi.transform = Transform3D(Basis(x, dir.cross(x), dir), (a + b) * 0.5)
	(parent if parent else self).add_child(mi)
	return mi


static func _paint(col: Color, rough: float = 0.45, metal: float = 0.3) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


# --- Build -------------------------------------------------------------------------------

func _ready() -> void:
	_glow = Mats.lamp(CYAN, 2.4)
	_engine = Mats.lamp(Color(0.6, 0.95, 1.0), 6.0)
	_nav = Mats.lamp(Color(1.0, 0.36, 0.12), 4.0)
	_build_hull()
	_build_dome()
	_build_ring()
	_build_engines()
	_build_keel()
	_build_fittings()
	_build_pods()
	_build_running_lights()


## The hull: pearl plates, a tangerine nose cap and waist stripe, graphite belts behind the decks
## and at the engine block; windows on the flank decks between the stripe and the belt.
func _build_hull() -> void:
	var zs: Array[float] = [-15.3]
	for p: Vector2 in PROFILE:
		zs.append(p.x)
	zs.sort()
	var rows: Array = []
	for i: int in zs.size():
		var z: float = zs[i]
		var col: Color = PEARL
		if z < -22.7:
			col = GRAPHITE
		elif z >= -15.3 and z < -14.3:
			col = TANGERINE
		elif (z >= 12.0 and z < 13.0) or z >= 17.6:
			col = GRAPHITE
		col.a = 1.0 if (z >= -13.7 and z < 12.0) else 0.0
		var r: float = radius_at(z)
		if i == zs.size() - 1:
			r = 0.0  # the back plate
		elif i == zs.size() - 2 and is_equal_approx(z, zs[i + 1]):
			r = PROFILE[-2].y
		rows.append([z, r, col])
	_hull_mat = hull_material()
	_hull_mat.set_shader_parameter("plate", Vector2(1.3, 2.3))
	_hull_mat.set_shader_parameter("window_cell", Vector2(0.44, 0.7))
	_hull_mat.set_shader_parameter("decks", Vector4(1.45, 0.44, -1.2, 0.44))
	var hull := MeshInstance3D.new()
	hull.name = "Hull"
	hull.mesh = lathe(rows, 40, HULL_SX, 34.0)
	hull.material_override = _hull_mat
	add_child(hull)
	# Two thin light seams round the hull (they turn red in the storm).
	for z: float in [-14.0, 12.5]:
		var r: float = radius_at(z)
		var seam := _add(ProcMesh.torus(r + 0.01, r + 0.09, 64, 6), _glow, Vector3(0, 0, z), Vector3(PI * 0.5, 0, 0), Vector3(HULL_SX, 1, 1))
		seam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The garden dome on the hull's back: a graphite collar, ribbed glass, and inside a floor of soil
## and moss, small trees, and the green light of the last plants.
func _build_dome() -> void:
	var holder := Node3D.new()
	holder.name = "Dome"
	holder.position = DOME_AT
	add_child(holder)
	var dark := _paint(GRAPHITE, 0.4, 0.5)
	# Collar: a low drum the glass stands on, with a tangerine lip.
	_add(ProcMesh.cyl(DOME_R + 0.25, DOME_R + 0.6, 0.9, 48), dark, Vector3(0, -0.35, 0), Vector3.ZERO, Vector3.ONE, holder)
	_add(ProcMesh.torus(DOME_R + 0.12, DOME_R + 0.3, 64, 6), _paint(TANGERINE, 0.35, 0.1), Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(1, 0.8, 1), holder)
	_dome_mat = dome_material()
	var glass := _add(dome_mesh(DOME_R, DOME_SY), _dome_mat, Vector3(0, 0.1, 0), Vector3.ZERO, Vector3.ONE, holder)
	glass.name = "Glass"
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The garden.
	_vault = Mats.lamp(Color(0.45, 0.95, 0.5), 0.5)
	_vault.albedo_color = Color(0.16, 0.3, 0.14)
	_add(ProcMesh.cyl(DOME_R - 0.1, DOME_R - 0.1, 0.1, 40), _vault, Vector3(0, 0.12, 0), Vector3.ZERO, Vector3.ONE, holder)
	var bark := _paint(Color(0.3, 0.22, 0.15), 0.9, 0.0)
	var leaf := Mats.lamp(Color(0.35, 0.9, 0.4), 0.35)
	leaf.albedo_color = Color(0.2, 0.55, 0.22)
	leaf.roughness = 0.8
	var crowns: Array[Transform3D] = []
	var trunks: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i: int in 30:
		var a: float = rng.randf() * TAU
		var r: float = sqrt(rng.randf()) * (DOME_R - 0.7)
		if r < 0.9:
			continue  # the clearing in the middle: the pedestal with the seedling tray
		var h: float = rng.randf_range(0.5, 1.5) * (1.0 - 0.45 * r / DOME_R)
		var p := Vector3(cos(a) * r, 0.15, sin(a) * r)
		var cr: float = rng.randf_range(0.28, 0.55)
		trunks.append(Transform3D(Basis().scaled(Vector3(1, h, 1)), p + Vector3(0, h * 0.5, 0)))
		crowns.append(Transform3D(Basis().scaled(Vector3(cr, cr * rng.randf_range(0.8, 1.25), cr)), p + Vector3(0, h + cr * 0.6, 0)))
	for spec: Array in [[ProcMesh.cyl(0.035, 0.05, 1.0, 5), bark, trunks], [ProcMesh.sphere(1.0, 8, 5), leaf, crowns]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = spec[0]
		var xs: Array[Transform3D] = spec[2]
		mm.instance_count = xs.size()
		for i: int in xs.size():
			mm.set_instance_transform(i, xs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = spec[1]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mmi)
	# The pedestal in the clearing and its little green lamp (where Lumi stands).
	_add(ProcMesh.cyl(0.3, 0.38, 0.7, 12), _paint(PEARL, 0.4, 0.1), Vector3(0, 0.5, 0), Vector3.ZERO, Vector3.ONE, holder)
	_add(ProcMesh.sphere(0.16, 8, 4), Mats.lamp(Color(0.5, 1.0, 0.55), 3.0), Vector3(0, 0.95, 0), Vector3.ZERO, Vector3(1.6, 0.5, 1.1), holder)
	_vault_light = OmniLight3D.new()
	_vault_light.light_color = Color(0.55, 1.0, 0.7)
	_vault_light.light_energy = 1.6
	_vault_light.omni_range = 9.0
	_vault_light.position = DOME_AT + Vector3(0, 1.8, 0)
	add_child(_vault_light)


## The ring round the aft hull: a squashed tube on four spokes with a hub collar. It turns.
func _build_ring() -> void:
	_ring = Node3D.new()
	_ring.name = "Ring"
	_ring.position = Vector3(0, 0, RING_Z)
	add_child(_ring)
	_ring_mat = hull_material()
	_ring_mat.set_shader_parameter("plate", Vector2(2.4, 1.1))
	_ring_mat.set_shader_parameter("window_cell", Vector2(0.7, 0.44))
	var tube := MeshInstance3D.new()
	tube.mesh = ring_mesh(RING_R, 1.25, 1.6)
	tube.material_override = _ring_mat
	_ring.add_child(tube)
	var dark := _paint(GRAPHITE, 0.4, 0.5)
	var plate := _paint(PLATE, 0.45, 0.35)
	var hub_r: float = radius_at(RING_Z)
	for k: int in 4:
		var a: float = PI * 0.25 + PI * 0.5 * k
		var dir := Vector3(sin(a), cos(a), 0)
		_beam(dir * (hub_r + 0.2), dir * (RING_R - 1.1), 0.9, 1.5, plate, _ring)
		_beam(dir * (hub_r + 1.6), dir * (RING_R - 2.4), 1.0, 0.5, dark, _ring)
		var lamp := _add(ProcMesh.sphere(0.16, 8, 4), _nav, dir * (RING_R + 1.3), Vector3.ZERO, Vector3.ONE, _ring)
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The hub collar the spokes stand on (round the hull, so it carries the sideways stretch).
	_add(ProcMesh.torus(hub_r - 0.1, hub_r + 0.5, 48, 8), dark, Vector3(0, 0, RING_Z), Vector3(PI * 0.5, 0, 0), Vector3(HULL_SX, 1.8, 1))
	for s: float in [-1.0, 1.0]:
		var line := _add(ProcMesh.torus(RING_R + 1.2, RING_R + 1.3, 96, 4), _glow, Vector3(0, 0, s * 0.55), Vector3(PI * 0.5, 0, 0), Vector3.ONE, _ring)
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The engine block: the main bell and four nacelles on pylons; a soft glow behind each nozzle.
func _build_engines() -> void:
	var dark := _paint(GRAPHITE, 0.35, 0.6)
	_plume = StandardMaterial3D.new()
	_plume.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_plume.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_plume.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_plume.cull_mode = BaseMaterial3D.CULL_DISABLED
	_plume.albedo_texture = EscapePod._soft_tex()
	_plume.albedo_color = Color(0.45, 0.85, 1.0, 0.1)
	_plume.disable_fog = true
	var nozzles: Array = [[Vector3(0, 0, 21.4), 1.9]]
	var pearl := Color(PEARL, 0.0)
	var tang := Color(TANGERINE, 0.0)
	var graph := Color(GRAPHITE, 0.0)
	var nac_rows: Array = [[-3.4, 0.0, tang], [-3.1, 0.75, tang], [-2.5, 1.02, pearl], [-2.0, 1.1, pearl], [1.2, 1.1, graph], [2.4, 0.95, graph], [2.4, 0.0, graph]]
	var nac_mesh: ArrayMesh = lathe(nac_rows, 16, 1.0, 7.0)
	var nac_mat: ShaderMaterial = hull_material()
	nac_mat.set_shader_parameter("plate", Vector2(1.75, 1.6))
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var at := Vector3(sx * 6.6, sy * 2.5, 18.6)
			_add(nac_mesh, nac_mat, at)
			_beam(Vector3(sx * 3.6, sy * 1.6, 17.8), at + Vector3(-sx * 0.7, -sy * 0.3, -0.4), 0.5, 1.6, dark)
			nozzles.append([at + Vector3(0, 0, 2.4), 0.85])
	for nz: Array in nozzles:
		var p: Vector3 = nz[0]
		var r: float = float(nz[1])
		var bell := CylinderMesh.new()
		bell.top_radius = r * 0.62
		bell.bottom_radius = r
		bell.height = r * 1.1
		bell.radial_segments = 20
		bell.cap_top = false
		bell.cap_bottom = false
		var bm: StandardMaterial3D = dark.duplicate()
		bm.cull_mode = BaseMaterial3D.CULL_DISABLED
		_add(bell, bm, p + Vector3(0, 0, r * 0.5), Vector3(-PI * 0.5, 0, 0))
		var disc := _add(ProcMesh.cyl(r * 0.6, r * 0.6, 0.05, 20), _engine, p + Vector3(0, 0, 0.1), Vector3(PI * 0.5, 0, 0))
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var q := QuadMesh.new()
		q.size = Vector2(r * 4.4, r * 4.4)
		var m := _add(q, _plume, p + Vector3(0, 0, r * 1.15), Vector3(0, PI, 0))
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_engine_light = OmniLight3D.new()
	_engine_light.light_color = Color(0.55, 0.9, 1.0)
	_engine_light.light_energy = 2.0
	_engine_light.omni_range = 14.0
	_engine_light.position = Vector3(0, 0, 24.5)
	add_child(_engine_light)


## The keel: a graphite beam under the belly with a thin light line down each side.
func _build_keel() -> void:
	var dark := _paint(GRAPHITE, 0.4, 0.5)
	var z0: float = POD_Z0 - 2.0
	var z1: float = POD_Z0 + 5 * POD_DZ + 2.0
	_beam(Vector3(0, -5.0, z0), Vector3(0, -5.0, z1), 1.6, 1.3, dark)
	_beam(Vector3(0, -4.4, z0 - 1.2), Vector3(0, -5.0, z0 + 0.4), 1.4, 0.8, dark)
	_beam(Vector3(0, -5.0, z1 - 0.4), Vector3(0, -4.4, z1 + 1.2), 1.4, 0.8, dark)
	for s: float in [-1.0, 1.0]:
		var line := _beam(Vector3(s * 0.83, -5.35, z0 + 0.5), Vector3(s * 0.83, -5.35, z1 - 0.5), 0.05, 0.08, _glow)
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Small things that give the size away: the bridge visor on the nose, a dish and a mast on the
## back, hatches and service blocks on the flanks.
func _build_fittings() -> void:
	var dark := _paint(GRAPHITE, 0.4, 0.5)
	var plate := _paint(PLATE, 0.45, 0.35)
	var pane := Mats.lamp(Color(0.25, 0.75, 0.85), 1.4)  # the Seedglider canopy's teal
	# Bridge: a dark visor band over the nose with a row of lit teal panes in it.
	var vis_rows: Array = []
	for z: float in [-20.9, -20.3, -19.6, -19.0]:
		vis_rows.append([z, radius_at(z) + 0.06, Color(0.03, 0.05, 0.07)])
	var visor_m := _paint(Color(0.03, 0.05, 0.07), 0.12, 0.6)
	var visor := MeshInstance3D.new()
	visor.name = "Visor"
	visor.mesh = lathe(vis_rows, 18, HULL_SX, 10.0, deg_to_rad(-62.0), deg_to_rad(62.0))
	visor.material_override = visor_m
	add_child(visor)
	for i: int in 11:
		var a: float = deg_to_rad(-55.0 + 11.0 * i)
		var z: float = -19.95
		var n: Vector3 = (skin_normal(z, a) + Vector3(0, 0, -0.42)).normalized()
		var glass := _add(ProcMesh.box(Vector3(0.52, 0.34, 0.04)), pane, skin(z, a, 0.09))
		glass.basis = Basis.looking_at(-n, Vector3.UP)
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A dorsal spine from the dome back to the ring's hub, and a fairing in front of the dome.
	_beam(skin(DOME_AT.z + DOME_R + 0.6, 0.0, -0.3), skin(RING_Z - 1.2, 0.0, -0.2), 1.5, 0.9, plate)
	_beam(skin(DOME_AT.z + DOME_R + 1.0, 0.0, 0.25), skin(RING_Z - 2.0, 0.0, 0.3), 0.5, 0.3, dark)
	_beam(skin(DOME_AT.z - DOME_R - 3.4, 0.0, -0.5), skin(DOME_AT.z - DOME_R - 0.3, 0.0, 0.1), 2.6, 0.8, plate)
	# Dish and mast on the back, behind the dome.
	var base: Vector3 = skin(3.2, 0.0)
	_beam(base + Vector3(0, -0.2, 0), base + Vector3(0, 2.2, 0), 0.22, 0.22, dark)
	var dish := CylinderMesh.new()
	dish.top_radius = 1.5
	dish.bottom_radius = 0.25
	dish.height = 0.5
	dish.radial_segments = 20
	var dm := _add(dish, plate, base + Vector3(0, 2.5, 0.2), Vector3(deg_to_rad(-38.0), 0, 0))
	dm.name = "Dish"
	_beam(base + Vector3(0, 2.6, 0.1), base + Vector3(0, 3.3, -0.5), 0.05, 0.05, dark)
	_beam(skin(11.0, 0.0), skin(11.0, 0.0) + Vector3(0, 3.6, 0), 0.1, 0.1, dark)
	var tip := _add(ProcMesh.sphere(0.11, 8, 4), _nav, skin(11.0, 0.0) + Vector3(0, 3.7, 0))
	tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The docking port under the forward belly: a collar with a lit ring.
	var port: Vector3 = Vector3(0, -radius_at(DOCK_Z), DOCK_Z)
	_add(ProcMesh.cyl(1.5, 1.8, 0.7, 20), dark, port + Vector3(0, -0.2, 0))
	var port_ring := _add(ProcMesh.torus(1.25, 1.4, 32, 6), _glow, port + Vector3(0, -0.58, 0), Vector3.ZERO, Vector3(1, 0.5, 1))
	port_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Hatches and service blocks along the back and the belly.
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for i: int in 16:
		var z: float = rng.randf_range(-15.0, 15.0)
		var a: float = [rng.randf_range(0.18, 0.7), rng.randf_range(2.1, 2.7)][i % 2] * (1.0 if rng.randf() < 0.5 else -1.0)
		if absf(z - DOME_AT.z) < DOME_R + 1.5 and absf(a) < 1.0:
			continue
		var n: Vector3 = skin_normal(z, a)
		var blk := _add(ProcMesh.rounded_box(Vector3(rng.randf_range(0.6, 1.5), rng.randf_range(0.5, 1.0), 0.3), 0.06, 2), dark if i % 3 == 0 else plate, skin(z, a, 0.08))
		blk.basis = Basis.looking_at(-n, Vector3(0, 0, 1))


## Six drop pods docked under the keel, hanging from clamps (the intro's pod is slot 2).
func _build_pods() -> void:
	var dark := _paint(GRAPHITE, 0.4, 0.5)
	for k: int in 6:
		var holder := Node3D.new()
		holder.position = Vector3(0, POD_Y, POD_Z0 + k * POD_DZ)
		add_child(holder)
		var pod: Node3D = EscapePod.build()
		pod.position = Vector3(0, -EscapePod.HEIGHT * 0.5, 0)
		pod.rotation.y = PI * 0.5  # doors face the ship's side
		for n: String in ["Scorch", "Spill", "PodLight"]:
			var c: Node = pod.get_node_or_null(n)
			if c:
				c.queue_free()
		holder.add_child(pod)
		_add(ProcMesh.cyl(0.3, 0.42, 0.5, 10), dark, Vector3(0, EscapePod.HEIGHT * 0.5 + 0.2, 0), Vector3.ZERO, Vector3.ONE, holder)
		_pods.append(holder)


## Thin running lights down the spine and along the flanks, a slow chase toward the tail.
func _build_running_lights() -> void:
	var xs: Array[Vector3] = []
	var z: float = -19.0
	while z <= 16.0:
		if absf(z - DOME_AT.z) > DOME_R + 1.0:
			xs.append(skin(z, 0.0, 0.06))
		for s: float in [-1.0, 1.0]:
			var p: Vector3 = skin(z, s * PI * 0.5, 0.06)
			xs.append(p)
			_flank.append(p)
		z += 2.0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = ProcMesh.sphere(0.1, 6, 3)
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


# --- API ---------------------------------------------------------------------------------

## Spots along the flanks (local) where the Homecoming's waking lights can sit.
func wake_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p: Vector3 in _flank:
		out.append(p + Vector3(0, 0.25, 0))
	return out


## The seed-vault dome's centre in world space.
func dome_world() -> Vector3:
	return global_transform * (DOME_AT + Vector3(0, 1.2, 0))


## Where the storm breaks the dome, in world space (on the glass).
func breach_world() -> Vector3:
	var d: Vector3 = breach_dir.normalized()
	return global_transform * (DOME_AT + Vector3(d.x * DOME_R, 0.1 + d.y * DOME_R * DOME_SY, d.z * DOME_R))


## Where a small ship docks: the port under the forward belly (the Homecoming's rocket), in
## world space.
func dock_world() -> Vector3:
	return global_transform * Vector3(0, -radius_at(DOCK_Z) - 1.2, DOCK_Z)


## The main engine's nozzle in world space.
func engine_world() -> Vector3:
	return global_transform * Vector3(0, 0, 22.6)


## Where the drop pods hang (k = 0..5) in world space.
func pod_world(k: int = 2) -> Vector3:
	return global_transform * Vector3(0, POD_Y, POD_Z0 + clampi(k, 0, 5) * POD_DZ)


## A docked pod's own transform (the intro swaps in its loose pod exactly there).
func pod_xform(k: int = 2) -> Transform3D:
	var h: Node3D = _pods[clampi(k, 0, _pods.size() - 1)]
	return (h.get_child(0) as Node3D).global_transform


## Hide a docked pod (it has been let go); release_pod(k, false) puts it back.
func release_pod(k: int, gone: bool = true) -> void:
	if k >= 0 and k < _pods.size():
		(_pods[k].get_child(0) as Node3D).visible = not gone


func _process(delta: float) -> void:
	_t += delta
	var pulse: float = 0.5 + 0.5 * sin(_t * 9.0)
	var a: float = clampf(alarm, 0.0, 1.0)
	var th: float = clampf(thrust, 0.0, 2.0)
	var pw: float = clampf(power, 0.0, 1.0)
	_ring.rotation.z += delta * ring_speed * 0.35
	_glow.emission = CYAN.lerp(ALARM, a * (0.55 + 0.45 * pulse))
	_glow.emission_energy_multiplier = (2.4 + a * pulse * 3.0 + 0.4 * sin(_t * ring_speed * 20.0)) * lerpf(0.35, 1.0, pw)
	_engine.emission_energy_multiplier = maxf(0.0, 6.0 * th + (sin(_t * 23.0) * 0.3 if th > 0.02 else 0.0))
	_plume.albedo_color.a = maxf(0.0, 0.35 * minf(th, 1.5) + (sin(_t * 31.0) * 0.02 if th > 0.02 else 0.0))
	_engine_light.light_energy = 2.0 * th
	var br: float = clampf(breach, 0.0, 1.0)
	_vault.emission_energy_multiplier = (0.5 + sin(_t * 1.3) * 0.12) * (1.0 - 0.6 * br)
	_vault_light.light_color = Color(0.55, 1.0, 0.7).lerp(ALARM, a * pulse)
	_vault_light.light_energy = 1.6 * (1.0 - 0.55 * br * (0.6 + 0.4 * pulse))
	_nav.emission_energy_multiplier = 6.0 if fmod(_t, 1.6) < 0.12 else 1.0
	for m: ShaderMaterial in [_hull_mat, _ring_mat]:
		m.set_shader_parameter("alarm", a)
		m.set_shader_parameter("power", pw)
	_dome_mat.set_shader_parameter("breach", br)
	_dome_mat.set_shader_parameter("hole_dir", breach_dir)
	# Running lights: a slow chase toward the tail (red in the storm), updated ten times a second.
	if _lights and fmod(_t, 0.1) < delta:
		var mm: MultiMesh = _lights.multimesh
		var head: float = fmod(_t * 9.0, 40.0) - 20.0
		for i: int in _light_z.size():
			var b: float = 0.35 + 0.65 * clampf(1.0 - absf(_light_z[i] - head) / 3.0, 0.0, 1.0)
			mm.set_instance_color(i, Color(b, b, b).lerp(Color(ALARM.r * b, ALARM.g * b, ALARM.b * b), a))
