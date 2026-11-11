class_name CityKit
extends RefCounted
## Small builders the Verdance cities share: vertex-coloured prop meshes and MultiMeshes, steel
## lattice and banded stacks for the source landmarks, smoke, ground and water films, lamp glows
## and painted lettering. All static; everything is in site-local metres.

const FILM_SHADER: String = "res://planets/verdance/sites/city_film.gdshader"
const PUFF_PX: int = 64

static var _puff: GradientTexture2D


static func v3(p: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


## A vertex-coloured mesh from a Geo (the kind byte in alpha is dropped): for MultiMesh props,
## whose instance colour tints the light parts and leaves the dark ones dark.
static func vc_mesh(g: BuildingDetail.Geo) -> ArrayMesh:
	var cols := PackedColorArray()
	cols.resize(g.c.size())
	for i: int in g.c.size():
		cols[i] = Color(g.c[i].r, g.c[i].g, g.c[i].b, 1.0)
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = g.v
	arr[Mesh.ARRAY_NORMAL] = g.n
	arr[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func vc_material(rough: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	return m


## One MultiMesh under `parent`: per-instance colours when `cols` has them, hidden past `range_m`.
static func mmi_on(parent: Node3D, nm: String, mesh: Mesh, xfs: Array[Transform3D], cols: Array[Color], mat: Material, shadows: bool,
		range_m: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i: int in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		if mm.use_colors:
			mm.set_instance_color(i, cols[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	if mat:
		mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = range_m
	mi.visibility_range_end_margin = 30.0
	mi.set_meta("no_collide", true)
	parent.add_child(mi)
	return mi


## A Geo as one mesh node in `mat`.
static func mesh_node(nm: String, g: BuildingDetail.Geo, mat: Material, range_m: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = g.mesh()
	mi.material_override = mat
	if range_m > 0.0:
		mi.visibility_range_end = range_m
	mi.set_meta("no_collide", true)
	return mi


## Moves everything added to `g` since vertex `from` by `xf` (a landmark built in its own frame).
static func xform(g: BuildingDetail.Geo, from: int, xf: Transform3D) -> void:
	var b: Basis = xf.basis.orthonormalized()
	for i: int in range(from, g.v.size()):
		g.v[i] = xf * g.v[i]
		g.n[i] = b * g.n[i]


## A square steel lattice tower from `base` up `h`: four legs (tapering from half_bot to half_top),
## a ring and cross braces per level. The legs take colour `a` and `b` on alternate levels.
static func lattice(g: BuildingDetail.Geo, base: Vector3, half_bot: float, half_top: float, h: float, levels: int, r: float,
		a: Color, b: Color) -> void:
	var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for l: int in levels:
		var y0: float = h * float(l) / float(levels)
		var y1: float = h * float(l + 1) / float(levels)
		var h0: float = lerpf(half_bot, half_top, float(l) / float(levels))
		var h1: float = lerpf(half_bot, half_top, float(l + 1) / float(levels))
		g.mat(BuildingDetail.K_METAL, a if l % 2 == 0 else b)
		for i: int in 4:
			var c0: Vector2 = corners[i]
			var c1: Vector2 = corners[(i + 1) % 4]
			var p0: Vector3 = base + Vector3(c0.x * h0, y0, c0.y * h0)
			var p1: Vector3 = base + Vector3(c0.x * h1, y1, c0.y * h1)
			var q0: Vector3 = base + Vector3(c1.x * h0, y0, c1.y * h0)
			var q1: Vector3 = base + Vector3(c1.x * h1, y1, c1.y * h1)
			g.rod(p0, p1, r)
			g.rod(p1, q1, r * 0.6)
			g.rod(p0, q1, r * 0.5)
			if l % 2 == 0:
				g.rod(q0, p1, r * 0.5)


## A round stack from `base` up `h` in `bands` alternating colour bands (a at the top).
static func banded(g: BuildingDetail.Geo, base: Vector3, r_bot: float, r_top: float, h: float, bands: int, a: Color, b: Color,
		segs: int = 16) -> void:
	for i: int in bands:
		var t0: float = float(i) / float(bands)
		var t1: float = float(i + 1) / float(bands)
		g.mat(BuildingDetail.K_METAL, a if (bands - i) % 2 == 1 else b, 0, BuildingDetail.F_RUST if i < 2 else 0)
		g.cyl(Transform3D(Basis.IDENTITY, base + Vector3(0, h * (t0 + t1) * 0.5, 0)), lerpf(r_bot, r_top, t1), lerpf(r_bot, r_top, t0),
			h * (t1 - t0), segs, i == bands - 1)
	g.mat(BuildingDetail.K_DARK, Color(0.03, 0.03, 0.035))
	g.cyl(Transform3D(Basis.IDENTITY, base + Vector3(0, h + 0.02, 0)), r_top * 0.82, r_top * 0.82, 0.06, segs)


static func puff_texture() -> GradientTexture2D:
	if _puff == null:
		var gr := Gradient.new()
		gr.set_color(0, Color(1, 1, 1, 1))
		gr.add_point(0.55, Color(1, 1, 1, 0.5))
		gr.set_color(gr.get_point_count() - 1, Color(1, 1, 1, 0))
		_puff = GradientTexture2D.new()
		_puff.gradient = gr
		_puff.fill = GradientTexture2D.FILL_RADIAL
		_puff.fill_from = Vector2(0.5, 0.5)
		_puff.fill_to = Vector2(0.5, 0.0)
		_puff.width = PUFF_PX
		_puff.height = PUFF_PX
	return _puff


## A plume of soft puffs rising from `at`: `col` at the mouth fading to `col_end`, climbing about
## `rise` m over `life` s while it swells from s0 to s1 m and leans with `drift` (m/s2).
static func smoke(nm: String, at: Vector3, col: Color, col_end: Color, amount: int, life: float, rise: float, s0: float, s1: float,
		drift: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = nm
	var q := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = puff_texture()
	m.disable_receive_shadows = true
	q.material = m
	p.mesh = q
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.local_coords = true  # "up" is the site's, not the world's
	p.direction = Vector3.UP
	p.spread = 7.0
	p.initial_velocity_min = rise / life * 0.85
	p.initial_velocity_max = rise / life * 1.15
	p.gravity = drift
	p.scale_amount_min = s1 * 0.8
	p.scale_amount_max = s1 * 1.2
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, s0 / maxf(s1, 0.01)))
	grow.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.set_color(0, Color(col.r, col.g, col.b, 0.0))
	ramp.add_point(0.08, col)
	ramp.add_point(0.6, col.lerp(col_end, 0.6))
	ramp.set_color(ramp.get_point_count() - 1, Color(col_end.r, col_end.g, col_end.b, 0.0))
	p.color_ramp = ramp
	p.position = at
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var reach: float = rise * 1.6 + s1 * 2.0
	p.visibility_aabb = AABB(Vector3(-reach, -4.0, -reach), Vector3(reach * 2.0, reach + 8.0, reach * 2.0))
	return p


## A flat soft-edged film (an oil slick on water, a chemical stain on the ground, a smog layer
## seen from below): colours a and b in drifting patches, `rainbow` 0..1 of oil sheen over them.
static func film(nm: String, half: Vector2, a: Color, b: Color, rainbow: float, under_only: bool = false, scale: float = 0.12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var pm := PlaneMesh.new()
	pm.size = half * 2.0
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = load(FILM_SHADER)
	m.set_shader_parameter("colour_a", a)
	m.set_shader_parameter("colour_b", b)
	m.set_shader_parameter("rainbow", rainbow)
	m.set_shader_parameter("under_only", under_only)
	m.set_shader_parameter("patch_scale", scale)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("no_collide", true)
	return mi


## Unshaded lamp heads at `pts` (floodlights, deck lamps, stack lights).
static func glow(parent: Node3D, nm: String, pts: Array[Vector3], r: float, col: Color, range_m: float = 420.0) -> MultiMeshInstance3D:
	var xfs: Array[Transform3D] = []
	for p: Vector3 in pts:
		xfs.append(Transform3D(Basis.from_scale(Vector3.ONE * r), p))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	return mmi_on(parent, nm, ProcMesh.sphere(1.0, 10, 6), xfs, [], m, false, range_m)


## Painted lettering on a wall or hull: faces along the basis' +Z.
static func label(text: String, xf: Transform3D, letter_m: float, col: Color, range_m: float = 300.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 160
	l.pixel_size = letter_m / 160.0
	l.outline_size = 0
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.modulate = col
	l.transform = xf
	l.visibility_range_end = range_m
	return l
