class_name EscapePod
extends RefCounted
## [pod2] The escape pod Lumi rides down in: the ark's cargo-rack pods, the intro's falling pod and
## the crash-site landmark beside the start. A piece of the Seedglider family (wt/ship): pearl and
## tangerine satin paint, graphite trim, thin cyan seams, small orange running lamps, faceted
## twelve-sided shell with sharp chines.
## Shape: a sleek teardrop standing on a flared thruster skirt, a raked glass canopy over the door,
## three swept fins that double as landing legs, panel seams, vents, RCS nubs and a mast beacon.
## The door is the exact missing patch of the shell (no overlapping faces), hinged on its bottom
## edge; a big porthole in it carries Lumi's C-eye glyph.
## Condition (set_condition): 0 crash-damaged (heat-tinted and sooty, cracked glass, a torn panel
## with a dangling live wire, stuttering seams and glyph), 1 patched (bolted plates, strobing fin
## lamps), 2 restored (clean paint, lit fins, a soft hover glow underneath), 3 planter-beacon (late
## upgrade: a ring of seedlings round the skirt and a soft beacon beam). animate() drives the
## flicker, strobe and sway each frame.
## Nodes: "Body", "Hatch" (rotation.x: 0 shut, OPEN open), "Scorch", "PodLight", "Spill", "Beacon",
## "Fin0..2/Lamp", "Canopy", "Skirt", "HoverGlow", "HoverLight".

const OPEN: float = -1.62
const SEGS: int = 12
const FRONT: int = 6  # the facet facing -Z (facet j spans _ang(j).._ang(j + 1))
const DOOR_J0: int = 5  # door facets 5, 6, 7
const DOOR_J1: int = 8
const DOOR_Y0: float = 0.42
const DOOR_Y1: float = 1.6
const CANOPY_Y0: float = 1.66
const CANOPY_Y1: float = 2.08
const WALL: float = 0.07
const DOOR_GAP: float = 0.012
const HEIGHT: float = 2.62
# The Seedglider palette (automation/ship_model.gd on wt/ship).
const PEARL := Color(0.93, 0.93, 0.91)
const PANEL := Color(0.82, 0.83, 0.84)
const TANGERINE := Color(1.0, 0.5, 0.16)
const TRIM := Color(0.09, 0.1, 0.115)
const STEEL := Color(0.62, 0.64, 0.68)
const CYAN := Color(0.3, 0.88, 1.0)
const LAMP := Color(1.0, 0.36, 0.12)
const SOOT := Color(0.36, 0.32, 0.28)
## [v7pod] How bright the cabin's light out of the open door is per repair stage (x 1.4 energy).
const CABIN_LIGHT: Array[float] = [0.3, 0.75, 1.0, 1.0]
const PAINT_SHADER := preload("res://art/shaders/pod_paint.gdshader")

## (radius, y) of the shell, bottom to top: a teardrop, widest low, a long taper to the tip.
const PROFILE: Array[Vector2] = [
	Vector2(0.0, 0.1), Vector2(0.4, 0.12), Vector2(0.6, 0.2), Vector2(0.71, 0.3), Vector2(0.76, DOOR_Y0),
	Vector2(0.79, 0.6), Vector2(0.8, 0.8), Vector2(0.785, 1.0), Vector2(0.75, 1.2), Vector2(0.7, 1.4),
	Vector2(0.63, DOOR_Y1), Vector2(0.56, 1.78), Vector2(0.47, 1.96), Vector2(0.37, 2.12), Vector2(0.26, 2.28),
	Vector2(0.16, 2.42), Vector2(0.08, 2.54), Vector2(0.0, HEIGHT),
]
## Thin band edges (rows of their own so the bands stay thin): cyan seams, dark panel seams, the
## tangerine chevron band.
const BREAKS: Array[float] = [0.32, 0.335, 0.9, 0.908, 1.35, 1.358, 2.14, 2.2, 2.3, 2.312]

static var _rows_cache: Array[Vector2] = []
static var _soft: GradientTexture2D
static var _glyph: ImageTexture
static var _cracks: ImageTexture


# --- Geometry helpers --------------------------------------------------------------------

## Angle of chine j (facet j spans _ang(j).._ang(j + 1)); facet FRONT is centred on -Z.
static func _ang(j: int) -> float:
	return (float(j) - 0.5) / SEGS * TAU - PI


## The centre angle of facet j.
static func facet_angle(j: int) -> float:
	return (_ang(j) + _ang(j + 1)) * 0.5


## A point on the shell: angle 0 faces -Z (the door side).
static func _pt(a: float, y: float, r: float) -> Vector3:
	return Vector3(sin(a) * r, y, -cos(a) * r)


static func _door_r(y: float) -> float:
	if y <= PROFILE[0].y:
		return PROFILE[0].x
	for i: int in PROFILE.size() - 1:
		if y >= PROFILE[i].y and y <= PROFILE[i + 1].y:
			return lerpf(PROFILE[i].x, PROFILE[i + 1].x, (y - PROFILE[i].y) / maxf(PROFILE[i + 1].y - PROFILE[i].y, 0.0001))
	return 0.0


## A point on the middle of facet j at height y, `out` metres proud of the flat facet.
static func facet_point(j: int, y: float, out: float = 0.0) -> Vector3:
	return _pt(facet_angle(j), y, _door_r(y) * cos(PI / SEGS) + out)


## Outward normal of facet j at height y.
static func facet_normal(j: int, y: float) -> Vector3:
	return _facet_n(facet_angle(j), y, false)


static func _rows() -> Array[Vector2]:
	if _rows_cache.is_empty():
		var ys: Array[float] = []
		for p: Vector2 in PROFILE:
			ys.append(p.y)
		for b: float in BREAKS:
			ys.append(b)
		ys.sort()
		for y: float in ys:
			if _rows_cache.is_empty() or y - _rows_cache[-1].y > 0.001:
				_rows_cache.append(Vector2(_door_r(y), y))
	return _rows_cache


static func _in_door(j: int, y0: float, y1: float) -> bool:
	return j >= DOOR_J0 and j < DOOR_J1 and y0 >= DOOR_Y0 - 0.001 and y1 <= DOOR_Y1 + 0.001


## Shell surface per row: 0 pearl, 1 tangerine chevron band, 2 graphite (base, panel seams), 3 cyan.
static func _band(y0: float, y1: float) -> int:
	var m: float = (y0 + y1) * 0.5
	if m < 0.2:
		return 2
	if (m > 0.32 and m < 0.335) or (m > 2.3 and m < 2.312):
		return 3
	if (m > 0.9 and m < 0.908) or (m > 1.35 and m < 1.358):
		return 2
	if m > 2.14 and m < 2.2:
		return 1
	return 0


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, nb := Vector3.ZERO, nt := Vector3.ZERO) -> void:
	# a-b bottom edge, d-c top edge. Godot's front faces wind clockwise. nb / nt: normals of the
	# bottom and top edge (facet normals: sharp chines around, smooth up the profile).
	var verts: Array[Vector3] = [a, b, c, a, c, d]
	var uvs: Array[Vector2] = [ua, ub, uc, ua, uc, ud]
	var ns: Array[Vector3] = [nb, nb, nt, nb, nt, nt]
	for k: int in 6:
		st.set_color(Color(1, 0, 0))
		if nb != Vector3.ZERO:
			st.set_normal(ns[k])
		st.set_uv(uvs[k])
		st.add_vertex(verts[k])


static func _facet_n(am: float, y: float, flip: bool) -> Vector3:
	var e: float = 0.02
	var ya: float = clampf(y - e, PROFILE[0].y + 0.0005, HEIGHT - 0.0005)
	var yb: float = clampf(y + e, PROFILE[0].y + 0.0005, HEIGHT - 0.0005)
	var slope: float = (_door_r(yb) - _door_r(ya)) / maxf(yb - ya, 0.0001)
	var n := (Vector3(sin(am), 0.0, -cos(am)) - Vector3(0, slope, 0)).normalized()
	if y <= PROFILE[0].y + 0.001:
		n = Vector3.DOWN
	elif y >= HEIGHT - 0.001:
		n = Vector3.UP
	return -n if flip else n


## UV.x runs round the pod, UV.y is the height in metres (pod_paint.gdshader reads it).
static func _uv(j: int, y: float) -> Vector2:
	return Vector2(float(j) / SEGS * 4.6, y)


## The shell as surfaces per band. skip_door / door_only cut or keep the door patch (the door is a
## hair smaller than its opening: gap). patch (x = facets, y = heights) clips to a sub-patch.
static func _shell_mesh(inset: float, flip: bool, skip_door: bool, door_only: bool, gap: float = 0.0, patch := Rect2()) -> Array[SurfaceTool]:
	var sts: Array[SurfaceTool] = []
	for k: int in 4:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		sts.append(st)
	var rows: Array[Vector2] = _rows()
	var use_patch: bool = patch.size != Vector2.ZERO
	for i: int in rows.size() - 1:
		var y0: float = rows[i].y
		var y1: float = rows[i + 1].y
		if use_patch and (y1 <= patch.position.y + 0.001 or y0 >= patch.end.y - 0.001):
			continue
		var band: int = _band(y0, y1)
		for j: int in SEGS:
			if use_patch and (j < int(patch.position.x) or j >= int(patch.end.x)):
				continue
			var door: bool = _in_door(j, y0, y1)
			if (skip_door and door) or (door_only and not door):
				continue
			var a0: float = _ang(j)
			var a1: float = _ang(j + 1)
			var qy0: float = y0
			var qy1: float = y1
			if use_patch:
				qy0 = maxf(y0, patch.position.y)
				qy1 = minf(y1, patch.end.y)
			if door_only and gap > 0.0:
				var ag: float = gap / 0.78
				a0 = maxf(a0, _ang(DOOR_J0) + ag)
				a1 = minf(a1, _ang(DOOR_J1) - ag)
				qy0 = maxf(y0, DOOR_Y0 + gap)
				qy1 = minf(y1, DOOR_Y1 - gap)
			var qr0: float = maxf(_door_r(qy0) - inset, 0.0) if _door_r(qy0) > 0.0 else 0.0
			var qr1: float = maxf(_door_r(qy1) - inset, 0.0) if _door_r(qy1) > 0.0 else 0.0
			var p00: Vector3 = _pt(a0, qy0, qr0)
			var p10: Vector3 = _pt(a1, qy0, qr0)
			var p11: Vector3 = _pt(a1, qy1, qr1)
			var p01: Vector3 = _pt(a0, qy1, qr1)
			var st: SurfaceTool = sts[0 if (door_only or use_patch) else band]
			var am: float = facet_angle(j)
			var nb: Vector3 = _facet_n(am, qy0, flip)
			var nt: Vector3 = _facet_n(am, qy1, flip)
			var u00: Vector2 = _uv(j, qy0)
			var u10: Vector2 = _uv(j + 1, qy0)
			var u11: Vector2 = _uv(j + 1, qy1)
			var u01: Vector2 = _uv(j, qy1)
			if use_patch:
				# 0..1 over the whole patch (the crack overlay maps onto it).
				var pw: float = patch.size.x
				u00 = Vector2((j - patch.position.x) / pw, 1.0 - (qy0 - patch.position.y) / patch.size.y)
				u10 = Vector2((j + 1 - patch.position.x) / pw, u00.y)
				u11 = Vector2(u10.x, 1.0 - (qy1 - patch.position.y) / patch.size.y)
				u01 = Vector2(u00.x, u11.y)
			if flip:
				_quad(st, p10, p00, p01, p11, u10, u00, u01, u11, nb, nt)
			else:
				_quad(st, p00, p10, p11, p01, u00, u10, u11, u01, nb, nt)
	return sts


static func _commit(sts: Array[SurfaceTool], mats: Array[Material]) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for k: int in sts.size():
		var arr: Array = sts[k].commit_to_arrays()
		if arr.is_empty() or not (arr[Mesh.ARRAY_VERTEX] is PackedVector3Array) or (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats[mini(k, mats.size() - 1)])
	return mesh


## The jamb: the hull's thickness around the opening (or the door's own edge, with shift/gap).
static func _jamb_mesh(out_off: float = 0.0, in_off: float = WALL, shift: Vector3 = Vector3.ZERO, gap: float = 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: Array[float] = []
	for r: Vector2 in _rows():
		if r.y >= DOOR_Y0 - 0.001 and r.y <= DOOR_Y1 + 0.001:
			rows.append(r.y)
	var ag: float = gap / 0.78
	var ey := func(y: float) -> float: return clampf(y, DOOR_Y0 + gap, DOOR_Y1 - gap)
	var ea := func(j: int) -> float: return clampf(_ang(j), _ang(DOOR_J0) + ag, _ang(DOOR_J1) - ag)
	var o := func(j: int, y: float) -> Vector3: return _pt(ea.call(j), ey.call(y), _door_r(ey.call(y)) - out_off) - shift
	var n := func(j: int, y: float) -> Vector3: return _pt(ea.call(j), ey.call(y), _door_r(ey.call(y)) - in_off) - shift
	for j: int in range(DOOR_J0, DOOR_J1):
		for edge: float in [rows[0], rows[-1]]:
			var a: Vector3 = o.call(j, edge)
			var b: Vector3 = o.call(j + 1, edge)
			var c: Vector3 = n.call(j + 1, edge)
			var d: Vector3 = n.call(j, edge)
			if edge == rows[0]:
				_quad(st, d, c, b, a, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN)
			else:
				_quad(st, a, b, c, d, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN)
	for k: int in rows.size() - 1:
		for side: int in [DOOR_J0, DOOR_J1]:
			var a: Vector3 = o.call(side, rows[k])
			var b: Vector3 = n.call(side, rows[k])
			var c: Vector3 = n.call(side, rows[k + 1])
			var d: Vector3 = o.call(side, rows[k + 1])
			if side == DOOR_J0:
				_quad(st, a, b, c, d, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN)
			else:
				_quad(st, b, a, d, c, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN)
	st.generate_normals()
	return st.commit()


## The door: the cut-out patch of the shell with its own thickness, relative to its hinge.
static func _door_mesh(hinge: Vector3, mats: Array[Material]) -> ArrayMesh:
	var outer: Array[SurfaceTool] = _shell_mesh(-0.004, false, false, true, DOOR_GAP)
	var inner: Array[SurfaceTool] = _shell_mesh(WALL * 0.6, true, false, true, DOOR_GAP)
	var mesh := ArrayMesh.new()
	for pair: Array in [[outer[0], mats[0]], [inner[0], mats[1]]]:
		var arr: Array = (pair[0] as SurfaceTool).commit_to_arrays()
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for v: int in vs.size():
			vs[v] -= hinge
		arr[Mesh.ARRAY_VERTEX] = vs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, pair[1])
	return mesh


## The thruster skirt: a flared ring (outer and inner faces).
static func _skirt_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prof: Array[Vector2] = [Vector2(0.69, 0.36), Vector2(0.74, 0.24), Vector2(0.82, 0.08), Vector2(0.86, 0.02)]
	var n: int = SEGS * 2
	for side: float in [0.0, -0.035]:
		for i: int in prof.size() - 1:
			for j: int in n:
				var a0: float = TAU * j / n
				var a1: float = TAU * (j + 1) / n
				var r0: float = prof[i].x + side
				var r1: float = prof[i + 1].x + side
				var p00: Vector3 = _pt(a0, prof[i].y, r0)
				var p10: Vector3 = _pt(a1, prof[i].y, r0)
				var p11: Vector3 = _pt(a1, prof[i + 1].y, r1)
				var p01: Vector3 = _pt(a0, prof[i + 1].y, r1)
				if side == 0.0:
					_quad(st, p01, p11, p10, p00, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
				else:
					_quad(st, p00, p10, p11, p01, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	st.generate_normals()
	return st.commit()


## A swept fin (YZ plane, +Z outward): root along the hull, tip swept down to the ground as a leg.
static func _fin_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var t: float = 0.03
	var o: Array[Vector2] = [Vector2(0.12, 0.62), Vector2(1.08, 0.7), Vector2(0.44, 1.26), Vector2(-0.02, 1.2)]
	var l: Array[Vector3] = []
	var r: Array[Vector3] = []
	for q: Vector2 in o:
		l.append(Vector3(-t, q.x, q.y))
		r.append(Vector3(t, q.x, q.y))
	_quad(st, l[0], l[1], l[2], l[3], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	_quad(st, r[3], r[2], r[1], r[0], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	for k: int in 4:
		var k2: int = (k + 1) % 4
		_quad(st, r[k], r[k2], l[k2], l[k], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	st.generate_normals()
	return st.commit()


## A thin bar (cylinder) from a to b.
static func _bar(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material, name_: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if name_ != "":
		mi.name = name_
	mi.mesh = ProcMesh.cyl(radius, radius, a.distance_to(b), 6)
	mi.material_override = mat
	var dir: Vector3 = (b - a).normalized()
	var up: Vector3 = Vector3.FORWARD if absf(dir.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x: Vector3 = up.cross(dir).normalized()
	mi.transform = Transform3D(Basis(x, dir, x.cross(dir)), (a + b) * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A node on facet j at height y, oriented so +Z points out of the facet.
static func _on_facet(parent: Node3D, j: int, y: float, out: float = 0.0) -> Node3D:
	var n := Node3D.new()
	var nrm: Vector3 = facet_normal(j, y)
	n.transform = Transform3D(Basis.looking_at(-nrm, Vector3.UP), facet_point(j, y, out))
	parent.add_child(n)
	return n


static func _box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, name_: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if name_ != "":
		mi.name = name_
	mi.mesh = ProcMesh.box(size)
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


# --- Materials -------------------------------------------------------------------------

## Hull paint (art/shaders/pod_paint.gdshader): Seedglider satin with re-entry heat. wear 0..1.
static func paint(color: Color, rough: float = 0.3, wear: float = 0.0, height: float = -1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PAINT_SHADER
	m.set_shader_parameter("paint_color", color)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("heat", wear)
	m.set_shader_parameter("height_override", height)
	return m


## Re-entry heat on every paint material of the pod (0 clean .. 1 just landed).
static func set_wear(pod: Node3D, _color: Color, wear: float) -> void:
	for m: ShaderMaterial in pod.get_meta("paints", []):
		m.set_shader_parameter("heat", wear)


static func _trim() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = TRIM
	m.roughness = 0.4
	m.metallic = 0.5
	return m


static func _glass() -> StandardMaterial3D:
	var g := StandardMaterial3D.new()
	g.albedo_color = Color(0.05, 0.28, 0.38)
	g.roughness = 0.04
	g.metallic = 0.4
	g.clearcoat_enabled = true
	g.clearcoat = 1.0
	g.emission_enabled = true
	g.emission = Color(0.1, 0.55, 0.7)
	g.emission_energy_multiplier = 0.25
	g.rim_enabled = true
	g.rim = 0.4
	return g


static func _soft_tex() -> GradientTexture2D:
	if _soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.55))
		_soft = GradientTexture2D.new()
		_soft.gradient = g
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(1.0, 0.5)
		_soft.width = 128
		_soft.height = 128
	return _soft


## Lumi's two C eyes (opening to the right) as an emission mask for the porthole glass.
static func glyph_texture() -> ImageTexture:
	if _glyph == null:
		var s: int = 128
		var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
		for y: int in s:
			for x: int in s:
				var v: float = 0.0
				for cx: float in [42.0, 86.0]:
					var d := Vector2(x - cx, y - 64.0)
					if absf(atan2(d.y, d.x)) > 0.85:  # the C opens to the right
						v = maxf(v, clampf(1.0 - absf(d.length() - 15.0) / 4.5, 0.0, 1.0))
				var halo: float = clampf(1.0 - Vector2(x - 64.0, y - 64.0).length() / 64.0, 0.0, 1.0) * 0.12
				var a: float = clampf(v + halo, 0.0, 1.0)
				img.set_pixel(x, y, Color(a, a, a, 1.0))
		img.generate_mipmaps()
		_glyph = ImageTexture.create_from_image(img)
	return _glyph


## Fracture lines spreading from an impact point, for cracked glass.
static func crack_texture() -> ImageTexture:
	if _cracks == null:
		var s: int = 256
		var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 0))
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		var origin := Vector2(s * 0.38, s * 0.42)
		for k: int in 16:
			var p: Vector2 = origin
			var a: float = TAU * k / 16.0 + rng.randf_range(-0.2, 0.2)
			var length: int = rng.randi_range(40, 150)
			for step: int in length:
				a += rng.randf_range(-0.25, 0.25)
				p += Vector2(cos(a), sin(a))
				if p.x < 1 or p.y < 1 or p.x >= s - 2 or p.y >= s - 1:
					break
				var alpha: float = 0.9 * (1.0 - float(step) / length) + 0.1
				img.set_pixel(int(p.x), int(p.y), Color(1, 1, 1, alpha))
				img.set_pixel(int(p.x) + 1, int(p.y), Color(1, 1, 1, alpha * 0.5))
		for ring: float in [9.0, 17.0]:
			for i: int in 90:
				var a: float = TAU * i / 90.0
				var q: Vector2 = origin + Vector2(cos(a), sin(a)) * (ring + rng.randf_range(-1.5, 1.5))
				img.set_pixel(int(q.x), int(q.y), Color(1, 1, 1, 0.7))
		img.generate_mipmaps()
		_cracks = ImageTexture.create_from_image(img)
	return _cracks


# --- Build -----------------------------------------------------------------------------

static func build() -> Node3D:
	var pod := Node3D.new()
	pod.name = "LandingPod"
	var shell: ShaderMaterial = paint(PEARL, 0.3)
	var accent: ShaderMaterial = paint(TANGERINE, 0.3)
	var panel_m: ShaderMaterial = paint(PANEL, 0.36)
	var paints: Array[ShaderMaterial] = [shell, accent, panel_m]
	pod.set_meta("paints", paints)
	var dark: StandardMaterial3D = _trim()
	var seam: StandardMaterial3D = Mats.lamp(CYAN, 1.5)
	pod.set_meta("seam", seam)
	# [v7pod] The cabin's inner wall: a clean matte cream (the old lining was a dim brown with a
	# warm self-glow, which read as a flat smear through the hatch). Both sides drawn, so no gaps.
	var lining := StandardMaterial3D.new()
	lining.albedo_color = MachineArt.col("pod", "cabin_wall", Color(0.84, 0.8, 0.71))
	lining.roughness = 0.92
	lining.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ramp := StandardMaterial3D.new()
	ramp.albedo_color = Color(0.58, 0.59, 0.6)
	ramp.roughness = 0.55
	ramp.metallic = 0.4
	var gasket := StandardMaterial3D.new()
	gasket.albedo_color = Color(0.05, 0.05, 0.055)
	gasket.roughness = 0.6
	gasket.cull_mode = BaseMaterial3D.CULL_DISABLED
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _commit(_shell_mesh(0.0, false, true, false), [shell, accent, dark, seam] as Array[Material])
	pod.add_child(body)
	var lin := MeshInstance3D.new()
	lin.name = "Lining"
	# [v7pod] skip_door: the lining used to run straight across the doorway, so the open hatch showed
	# a flat inner skin (brown, self-lit, facet-banded) where the cabin should be.
	lin.mesh = _commit(_shell_mesh(WALL, true, true, false), [lining] as Array[Material])
	lin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pod.add_child(lin)
	var jamb := MeshInstance3D.new()
	jamb.name = "Jamb"
	jamb.mesh = _jamb_mesh()
	jamb.material_override = gasket
	pod.add_child(jamb)
	_build_cabin(pod)  # [v7pod] floor, padded seat, console, wall pads, lamps
	_build_canopy(pod, dark)
	_build_skirt(pod, dark, accent)
	_build_fins(pod, accent)
	_build_greebles(pod, dark, seam, panel_m)
	_build_door(pod, shell, ramp, gasket, accent, seam)
	_build_lights(pod)
	_build_damage_kit(pod, panel_m, accent, seam)
	# Factory fresh (the ark's rack, the intro's fall): restored look, engines cold.
	set_condition(pod, 2)
	(pod.get_node("HoverGlow") as Node3D).visible = false
	(pod.get_node("HoverLight") as OmniLight3D).visible = false
	return pod


## [v7pod] Where a point on the inner wall of facet j sits at height y, `off` metres in from it,
## with a basis whose +Z looks into the cabin (for Kit parts laid on the wall).
static func _wall_xf(j: int, y: float, off: float) -> Transform3D:
	var n: Vector3 = facet_normal(j, y)
	var p: Vector3 = facet_point(j, y, -WALL * cos(PI / SEGS) - off)
	return Transform3D(Basis.looking_at(n, Vector3.UP), p)


## [v7pod] The cabin seen through the open hatch, on the yard machines' art kit (YardArt.Kit):
## a rubber-matted floor with a hazard sill, a padded tangerine cradle sized for Lumi with a
## cream harness, quilted cream wall pads, a teal console with a screen and two buttons (node
## "Cabin": its glow comes on with power), a strip of warm lamps round the back wall and a ceiling
## lamp ("CabinLamps"), and a little red alarm lamp ("CabinAlarm") that blinks while the pod is
## dead. Colours: data/machine_art.json "pod" (cabin_*). set_condition() powers them per stage.
static func _build_cabin(pod: Node3D) -> void:
	var wall_pad: Color = MachineArt.col("pod", "cabin_pad", YardArt.CREAM)
	var seat_c: Color = MachineArt.col("pod", "cabin_seat", YardArt.ORANGE)
	var frame: Color = MachineArt.col("pod", "cabin_frame", Color(0.17, 0.2, 0.25))
	var console_c: Color = MachineArt.col("pod", "cabin_console", YardArt.TEAL)
	var floor_c: Color = MachineArt.col("pod", "cabin_floor", YardArt.DARK)
	var screen: Color = MachineArt.col("pod", "cabin_screen", YardArt.CYAN)
	var lamp: Color = MachineArt.col("pod", "cabin_lamp", YardArt.WARM)
	var k := YardArt.Kit.new()
	# Floor: a deck plate just over the sill, a rubber mat on it, a hazard strip at the door.
	var fr: float = (_door_r(DOOR_Y0) - WALL) * cos(PI / SEGS) - 0.004
	k.cyl(fr, 0.05, Vector3(0, DOOR_Y0 - 0.02, 0), floor_c, Vector3.ZERO, 0.01, SEGS * 2)
	k.cyl(fr - 0.1, 0.012, Vector3(0, DOOR_Y0 + 0.008, 0.04), floor_c.lightened(0.12), Vector3.ZERO, 0.004, SEGS * 2)
	for i: int in 4:  # grip ribs on the mat
		k.box(Vector3(0.7, 0.008, 0.025), Vector3(0, DOOR_Y0 + 0.016, -0.2 + i * 0.13), floor_c.darkened(0.2), Vector3.ZERO, 0.003)
	k.hazard(Vector3(0.62, 0.014, 0.07), Vector3(0, DOOR_Y0 + 0.009, -fr + 0.06))
	# The cradle: pedestal, cushion, backrest, headrest, side bolsters, harness. [v7look] cushions and
	# pads use the kit "pad" key: no paint wear (it read as grime smudges on the backrest).
	k.box(Vector3(0.3, 0.3, 0.26), Vector3(0, 0.57, 0.33), frame, Vector3.ZERO, 0.03)
	k.box(Vector3(0.4, 0.04, 0.34), Vector3(0, 0.71, 0.32), frame, Vector3.ZERO, 0.012)
	k.box(Vector3(0.48, 0.11, 0.38), Vector3(0, 0.78, 0.31), seat_c, Vector3.ZERO, 0.05, "pad")
	k.box(Vector3(0.46, 0.62, 0.1), Vector3(0, 1.13, 0.52), seat_c, Vector3(-4, 0, 0), 0.05, "pad")
	k.box(Vector3(0.3, 0.15, 0.1), Vector3(0, 1.53, 0.5), seat_c, Vector3(-8, 0, 0), 0.05, "pad")
	k.box(Vector3(0.5, 0.05, 0.09), Vector3(0, 0.83, 0.56), frame, Vector3.ZERO, 0.015)
	for sx: float in [-1.0, 1.0]:
		k.box(Vector3(0.08, 0.15, 0.36), Vector3(sx * 0.27, 0.9, 0.36), seat_c, Vector3.ZERO, 0.035, "pad")  # [v7look] one pad colour per surface: the cabin's draw-call budget
		k.box(Vector3(0.05, 0.12, 0.05), Vector3(sx * 0.27, 0.78, 0.22), frame, Vector3.ZERO, 0.012)
		k.box(Vector3(0.012, 0.5, 0.012), Vector3(sx * 0.08, 1.14, 0.466), seat_c.darkened(0.22), Vector3(-4, 0, 0), 0.004)
		k.box(Vector3(0.05, 0.56, 0.014), Vector3(sx * 0.13, 1.1, 0.462), wall_pad, Vector3(-4, 0, sx * -6.0), 0.005, "pad")
	k.box(Vector3(0.09, 0.07, 0.02), Vector3(0, 0.92, 0.46), YardArt.STEEL, Vector3.ZERO, 0.01)
	# Quilted wall pads on the flanks and a padded strip under the door's top edge inside.
	for j: int in [1, 2, 10, 11]:
		for y: float in [0.86, 1.28]:
			k.push(_wall_xf(j, y, 0.025))
			k.box(Vector3(0.24, 0.34, 0.05), Vector3.ZERO, wall_pad, Vector3.ZERO, 0.035, "pad")
			k.box(Vector3(0.012, 0.3, 0.012), Vector3(0, 0, 0.026), wall_pad.darkened(0.12), Vector3.ZERO, 0.004)
			k.pop()
	for j: int in [3, 9]:
		k.push(_wall_xf(j, 1.38, 0.02))
		k.box(Vector3(0.24, 0.3, 0.04), Vector3.ZERO, wall_pad, Vector3.ZERO, 0.03, "pad")
		k.pop()
	# The console on the +X wall, facing the cradle and the door: a teal desk with a raked face, a
	# screen (Lumi's C-eye mark on it) and two round buttons.
	var cpos := Vector3(0.47, 0.0, -0.02)
	var cxf: Transform3D = ProcMesh.xf(cpos, Vector3(0, -110, 0))
	k.push(cxf)
	k.box(Vector3(0.34, 0.5, 0.2), Vector3(0, 0.69, 0.0), console_c, Vector3.ZERO, 0.03)
	k.box(Vector3(0.38, 0.05, 0.24), Vector3(0, 0.95, 0.0), wall_pad, Vector3.ZERO, 0.02)
	k.push(ProcMesh.xf(Vector3(0, 1.06, 0.02), Vector3(-35, 0, 0)))
	k.box(Vector3(0.32, 0.2, 0.05), Vector3.ZERO, frame, Vector3.ZERO, 0.02)
	k.glow_box(Vector3(0.22, 0.12, 0.012), Vector3(0, 0.01, 0.026), screen)
	k.pop()
	k.glow_cyl(0.028, 0.02, Vector3(-0.09, 0.985, 0.07), lamp)
	k.glow_cyl(0.028, 0.02, Vector3(0.0, 0.985, 0.08), YardArt.MINT)
	k.box(Vector3(0.06, 0.02, 0.03), Vector3(0.1, 0.985, 0.07), YardArt.STEEL, Vector3.ZERO, 0.006)
	k.vent(0.2, 0.12, Vector3(0, 0.6, 0.105), frame, Vector3.ZERO, 3)
	k.pop()
	var cabin: MeshInstance3D = k.mi(0.1, "Cabin")
	cabin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pod.add_child(cabin)
	# Lamps: a warm strip on every wall facet but the door's, above head height, and a ceiling lamp.
	var lk := YardArt.Kit.new()
	for j: int in SEGS:
		if j >= DOOR_J0 - 1 and j <= DOOR_J1:
			continue
		lk.push(_wall_xf(j, 1.7, 0.012))
		lk.box(Vector3(0.2, 0.05, 0.024), Vector3.ZERO, frame, Vector3.ZERO, 0.01)
		lk.glow_box(Vector3(0.16, 0.022, 0.012), Vector3(0, 0, 0.014), lamp)
		lk.pop()
	lk.pipe(Vector3(0, 2.4, 0), Vector3(0, 2.0, 0), 0.014, frame, false)
	lk.cyl(0.12, 0.04, Vector3(0, 1.98, 0.0), frame, Vector3.ZERO, 0.012, 16)
	lk.glow_cyl(0.085, 0.02, Vector3(0, 1.955, 0.0), lamp, Vector3.ZERO, 16)
	var lamps: MeshInstance3D = lk.mi(0.1, "CabinLamps")
	lamps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pod.add_child(lamps)
	# The alarm lamp on the console's top corner (its own material: it blinks while the pod is dead).
	var alarm := MeshInstance3D.new()
	alarm.name = "CabinAlarm"
	alarm.mesh = ProcMesh.sphere(0.026, 10, 5)
	alarm.material_override = Mats.lamp(Color(1.0, 0.18, 0.12), 0.0)
	alarm.position = cxf * Vector3(0.13, 0.99, -0.05)
	alarm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pod.add_child(alarm)
	pod.set_meta("cabin", {"cabin": cabin, "lamps": lamps, "alarm": alarm})


## The raked canopy over the door: a faceted glass visor proud of the shell, with frame bars.
static func _build_canopy(pod: Node3D, dark: StandardMaterial3D) -> void:
	var patch := Rect2(DOOR_J0, CANOPY_Y0, DOOR_J1 - DOOR_J0, CANOPY_Y1 - CANOPY_Y0)
	var canopy := MeshInstance3D.new()
	canopy.name = "Canopy"
	canopy.mesh = _commit(_shell_mesh(-0.03, false, false, false, 0.0, patch), [_glass()] as Array[Material])
	pod.add_child(canopy)
	pod.set_meta("canopy", canopy)
	for j: int in range(DOOR_J0, DOOR_J1 + 1):
		var a: float = _ang(j)
		_bar(pod, _pt(a, CANOPY_Y0, _door_r(CANOPY_Y0) + 0.034), _pt(a, CANOPY_Y1, _door_r(CANOPY_Y1) + 0.034), 0.016, dark)
	for y: float in [CANOPY_Y0, CANOPY_Y1]:
		for j: int in range(DOOR_J0, DOOR_J1):
			_bar(pod, _pt(_ang(j), y, _door_r(y) + 0.034), _pt(_ang(j + 1), y, _door_r(y) + 0.034), 0.018, dark)


## The thruster skirt: a flared graphite ring with a tangerine lip, four bells underneath and the
## hover glow pool (restored pods only).
static func _build_skirt(pod: Node3D, dark: StandardMaterial3D, accent: ShaderMaterial) -> void:
	var skirt := MeshInstance3D.new()
	skirt.name = "Skirt"
	skirt.mesh = _skirt_mesh()
	var sm: StandardMaterial3D = dark.duplicate()
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	skirt.material_override = sm
	pod.add_child(skirt)
	var lip := MeshInstance3D.new()
	lip.mesh = ProcMesh.torus(0.84, 0.88, SEGS * 2, 4)
	lip.material_override = accent
	lip.position.y = 0.03
	lip.scale = Vector3(1, 0.5, 1)
	pod.add_child(lip)
	var glow: StandardMaterial3D = Mats.lamp(Color(0.55, 0.9, 1.0), 0.0)
	pod.set_meta("thrust", glow)
	for k: int in 4:
		var p: Vector3 = _pt(PI * 0.25 + PI * 0.5 * k, 0.1, 0.42)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.06
		cm.bottom_radius = 0.1
		cm.height = 0.12
		cm.cap_top = false
		cm.cap_bottom = false
		cm.radial_segments = 12
		var bell := MeshInstance3D.new()
		bell.mesh = cm
		bell.material_override = sm
		bell.position = p
		pod.add_child(bell)
		var disc := MeshInstance3D.new()
		disc.mesh = ProcMesh.cyl(0.06, 0.06, 0.01, 12)
		disc.material_override = glow
		disc.position = p + Vector3(0, 0.04, 0)
		pod.add_child(disc)
	var hover := MeshInstance3D.new()
	hover.name = "HoverGlow"
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.4, 2.4)
	hover.mesh = pm
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hm.albedo_texture = _soft_tex()
	hm.albedo_color = Color(0.35, 0.85, 1.0, 0.0)
	hm.disable_fog = true
	hover.material_override = hm
	hover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hover.position.y = 0.03
	pod.add_child(hover)
	var hl := OmniLight3D.new()
	hl.name = "HoverLight"
	hl.light_color = Color(0.45, 0.88, 1.0)
	hl.light_energy = 0.0
	hl.omni_range = 2.2
	hl.position = Vector3(0, 0.15, 0)
	pod.add_child(hl)


## Three swept graphite fins (back and both rear flanks): tangerine tips, a cyan leading-edge line
## and an orange running lamp.
static func _build_fins(pod: Node3D, accent: ShaderMaterial) -> void:
	var fin_mesh: ArrayMesh = _fin_mesh()
	var fin_mat: StandardMaterial3D = _trim()
	fin_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var edge_m: StandardMaterial3D = Mats.lamp(CYAN, 0.0)
	pod.set_meta("fin_edge", edge_m)
	var lamps: Array[StandardMaterial3D] = []
	for k: int in 3:
		var a: float = [PI, PI - 1.95, PI + 1.95][k]
		var fin := Node3D.new()
		fin.name = "Fin%d" % k
		fin.rotation = Vector3(0, PI - a, 0)
		pod.add_child(fin)
		var mi := MeshInstance3D.new()
		mi.mesh = fin_mesh
		mi.material_override = fin_mat
		fin.add_child(mi)
		var tip := MeshInstance3D.new()
		tip.mesh = ProcMesh.box(Vector3(0.07, 0.42, 0.1))
		tip.material_override = accent
		tip.position = Vector3(0, 0.2, 1.23)
		fin.add_child(tip)
		_bar(fin, Vector3(0, 1.08, 0.7), Vector3(0, 0.46, 1.25), 0.008, edge_m)
		var lm: StandardMaterial3D = Mats.lamp(LAMP, 2.5)
		lamps.append(lm)
		var bulb := MeshInstance3D.new()
		bulb.name = "Lamp"
		bulb.mesh = ProcMesh.sphere(0.03, 10, 5)
		bulb.material_override = lm
		bulb.position = Vector3(0, 0.46, 1.27)
		fin.add_child(bulb)
		var foot := MeshInstance3D.new()
		foot.mesh = ProcMesh.cyl(0.07, 0.09, 0.05, 10)
		foot.material_override = fin_mat
		foot.position = Vector3(0, 0.0, 1.2)
		fin.add_child(foot)
	pod.set_meta("fin_lamps", lamps)


## [v7pod] Thin raised strips along chines `js` from y0 to y1, following the profile (one mesh).
static func _seam_strips(pod: Node3D, js: Array, y0: float, y1: float, w: float, h: float, mat: Material) -> void:
	var ys: Array[float] = [y0]
	for r: Vector2 in _rows():
		if r.y > y0 + 0.01 and r.y < y1 - 0.01:
			ys.append(r.y)
	ys.append(y1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j: int in js:
		var a: float = _ang(j)
		var d := Vector3(sin(a), 0.0, -cos(a))
		var t := Vector3(cos(a), 0.0, sin(a))
		for i: int in ys.size() - 1:
			var cb: Vector3 = _pt(a, ys[i], _door_r(ys[i]))
			var ct: Vector3 = _pt(a, ys[i + 1], _door_r(ys[i + 1]))
			var lbi: Vector3 = cb - t * w - d * 0.002
			var rbi: Vector3 = cb + t * w - d * 0.002
			var lti: Vector3 = ct - t * w - d * 0.002
			var rti: Vector3 = ct + t * w - d * 0.002
			var lbo: Vector3 = cb - t * w * 0.6 + d * h
			var rbo: Vector3 = cb + t * w * 0.6 + d * h
			var lto: Vector3 = ct - t * w * 0.6 + d * h
			var rto: Vector3 = ct + t * w * 0.6 + d * h
			var z := Vector2.ZERO
			_quad(st, lbo, rbo, rto, lto, z, z, z, z)
			_quad(st, rbo, rbi, rti, rto, z, z, z, z)
			_quad(st, lbi, lbo, lto, lti, z, z, z, z)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pod.add_child(mi)


## Panel seams, raised plates, vent grilles, RCS nubs, grab rails and the mast with the beacon.
static func _build_greebles(pod: Node3D, dark: StandardMaterial3D, seam: StandardMaterial3D, panel_m: ShaderMaterial) -> void:
	# [v7pod] The chine seams follow the curved shell (they were straight bars from end to end, which
	# cut right through the cabin and showed as dark lines down its inner wall).
	_seam_strips(pod, [0, 2, 10], 0.36, 2.1, 0.006, 0.006, dark)
	_seam_strips(pod, [4, 9], 0.5, 1.55, 0.005, 0.008, seam)
	var steel: StandardMaterial3D = Mats.metal("steel")
	for j: int in [2, 10]:
		var f: Node3D = _on_facet(pod, j, 1.12)
		_box(f, Vector3(0.3, 0.42, 0.016), panel_m, Vector3(0, 0, 0.008))
		_box(f, Vector3(0.05, 0.05, 0.004), paint(TANGERINE, 0.3, 0.0, 1.5), Vector3(0.11, 0.17, 0.018))
	for j: int in [1, 11]:
		var f: Node3D = _on_facet(pod, j, 0.62)
		_box(f, Vector3(0.26, 0.16, 0.02), dark, Vector3(0, 0, 0.01))
		for s: int in 4:
			_box(f, Vector3(0.22, 0.012, 0.006), steel, Vector3(0, -0.055 + s * 0.037, 0.022))
	for j: int in [0, 3, 9]:
		var f: Node3D = _on_facet(pod, j, 1.95)
		var nub := MeshInstance3D.new()
		nub.mesh = ProcMesh.cyl(0.035, 0.045, 0.08, 8)
		nub.material_override = dark
		nub.rotation.x = PI * 0.5
		nub.position = Vector3(0, 0, 0.04)
		f.add_child(nub)
	for j: int in [4, 8]:
		var f: Node3D = _on_facet(pod, j, 1.0)
		_bar(f, Vector3(0, -0.2, 0.05), Vector3(0, 0.2, 0.05), 0.012, steel)
		_box(f, Vector3(0.03, 0.03, 0.05), dark, Vector3(0, -0.2, 0.025))
		_box(f, Vector3(0.03, 0.03, 0.05), dark, Vector3(0, 0.2, 0.025))
	_bar(pod, Vector3(0, HEIGHT - 0.04, 0), Vector3(0, HEIGHT + 0.22, 0), 0.012, dark)
	var beacon := MeshInstance3D.new()
	beacon.name = "Beacon"
	beacon.mesh = ProcMesh.sphere(0.04, 12, 6)
	beacon.material_override = Mats.lamp(LAMP, 3.0)
	beacon.position = Vector3(0, HEIGHT + 0.24, 0)
	pod.add_child(beacon)


## The door with its porthole (Lumi's C-eye glyph), grab bar and status line.
static func _build_door(pod: Node3D, shell: ShaderMaterial, ramp: StandardMaterial3D, gasket: StandardMaterial3D, accent: ShaderMaterial, seam: StandardMaterial3D) -> void:
	var hinge := Vector3(0, DOOR_Y0, -_door_r(DOOR_Y0) * cos(PI / SEGS) + 0.02)
	var hatch := Node3D.new()
	hatch.name = "Hatch"
	hatch.position = hinge
	pod.add_child(hatch)
	pod.set_meta("hinge_z", hinge.z)
	var door := MeshInstance3D.new()
	door.name = "Door"
	door.mesh = _door_mesh(hinge, [shell, ramp] as Array[Material])
	hatch.add_child(door)
	var edge := MeshInstance3D.new()
	edge.name = "DoorEdge"
	edge.mesh = _jamb_mesh(-0.004, WALL * 0.6, hinge, DOOR_GAP)
	edge.material_override = gasket
	hatch.add_child(edge)
	var f: Node3D = _on_facet(hatch, FRONT, 1.12)
	f.position -= hinge
	var bezel := MeshInstance3D.new()
	bezel.mesh = ProcMesh.torus(0.17, 0.215, 32, 8)
	bezel.material_override = paint(STEEL, 0.3, 0.0, 1.5)
	bezel.rotation.x = PI * 0.5
	bezel.position = Vector3(0, 0, 0.012)
	f.add_child(bezel)
	var port := MeshInstance3D.new()
	port.name = "Porthole"
	port.mesh = ProcMesh.cyl(0.175, 0.175, 0.012, 32)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.03, 0.12, 0.17)
	pm.roughness = 0.03
	pm.metallic = 0.4
	pm.clearcoat_enabled = true
	pm.emission_enabled = true
	pm.emission = CYAN
	pm.emission_texture = glyph_texture()
	pm.emission_energy_multiplier = 2.2
	port.material_override = pm
	port.rotation.x = PI * 0.5
	port.position = Vector3(0, 0, 0.008)
	f.add_child(port)
	pod.set_meta("glyph", pm)
	pod.set_meta("porthole", port)
	_box(f, Vector3(0.3, 0.045, 0.04), accent, Vector3(0, 0.3, 0.02))
	_box(f, Vector3(0.2, 0.012, 0.006), seam, Vector3(0, -0.26, 0.006))


static func _build_lights(pod: Node3D) -> void:
	var light := OmniLight3D.new()
	light.name = "PodLight"
	light.light_color = Color(1.0, 0.78, 0.5)
	light.light_energy = 0.0
	light.omni_range = 3.2
	light.position = Vector3(0, 1.45, -0.2)  # [v7pod] up by the lamps, clear of the seat's padding
	pod.add_child(light)
	var spill := MeshInstance3D.new()
	spill.name = "Spill"
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.6, 2.4)
	spill.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.albedo_texture = _soft_tex()
	sm.albedo_color = Color(1.0, 0.72, 0.42, 0.0)
	sm.disable_fog = true
	spill.material_override = sm
	spill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spill.position = Vector3(0, 0.035, -_door_r(DOOR_Y0) - 1.0)
	pod.add_child(spill)
	var scorch := MeshInstance3D.new()
	scorch.name = "Scorch"
	var scm := StandardMaterial3D.new()
	scm.albedo_color = Color(0.08, 0.07, 0.06, 0.75)
	scm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	scm.albedo_texture = _soft_tex()
	scm.roughness = 1.0
	var sp := PlaneMesh.new()
	sp.size = Vector2(3.8, 3.8)
	scorch.mesh = sp
	scorch.material_override = scm
	scorch.position = Vector3(0, 0.02, 0)
	scorch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pod.add_child(scorch)


## Damage and repair pieces: a torn flank panel over live wiring with a dangling cable, crack
## overlays on the glass, bolted patch plates, and the planter ring with its beacon beam.
static func _build_damage_kit(pod: Node3D, panel_m: ShaderMaterial, accent: ShaderMaterial, seam: StandardMaterial3D) -> void:
	var face: Node3D = _on_facet(pod, 4, 1.26, 0.004)
	face.name = "LoosePanel"
	var swing := Node3D.new()
	swing.name = "Swing"
	face.add_child(swing)
	_box(swing, Vector3(0.34, 0.3, 0.016), panel_m, Vector3(0, -0.15, 0.008))
	var bolts := Node3D.new()
	bolts.name = "Bolts"
	swing.add_child(bolts)
	for bx: float in [-0.14, 0.14]:
		for by: float in [-0.03, -0.27]:
			var bolt := MeshInstance3D.new()
			bolt.mesh = ProcMesh.cyl(0.016, 0.016, 0.012, 6)
			bolt.material_override = accent
			bolt.rotation.x = PI * 0.5
			bolt.position = Vector3(bx, by, 0.02)
			bolts.add_child(bolt)
	var pline: MeshInstance3D = _box(swing, Vector3(0.24, 0.008, 0.004), seam, Vector3(0, -0.15, 0.018), "Line")
	var wires_m: StandardMaterial3D = Mats.lamp(Color(1.0, 0.5, 0.2), 2.0)
	var wires: MeshInstance3D = _box(face, Vector3(0.24, 0.18, 0.008), wires_m, Vector3(0, -0.15, -0.002), "Wires")
	# A dangling cable: five short links hanging from the hole, swaying (animate()).
	var cable := Node3D.new()
	cable.name = "Cable"
	cable.position = Vector3(0.06, -0.24, 0.02)
	face.add_child(cable)
	var cable_m := StandardMaterial3D.new()
	cable_m.albedo_color = Color(0.12, 0.12, 0.13)
	cable_m.roughness = 0.6
	var links: Array[Node3D] = []
	var parent: Node3D = cable
	for i: int in 5:
		var link := Node3D.new()
		link.position = Vector3(0, -0.07 if i > 0 else 0.0, 0)
		parent.add_child(link)
		var seg := MeshInstance3D.new()
		seg.mesh = ProcMesh.cyl(0.008, 0.008, 0.07, 5)
		seg.material_override = cable_m
		seg.position = Vector3(0, -0.035, 0)
		link.add_child(seg)
		links.append(link)
		parent = link
	var tip := MeshInstance3D.new()
	tip.mesh = ProcMesh.sphere(0.016, 8, 4)
	tip.material_override = wires_m
	tip.position = Vector3(0, -0.075, 0)
	parent.add_child(tip)
	var wire_light := OmniLight3D.new()
	wire_light.name = "WireLight"
	wire_light.light_color = Color(1.0, 0.55, 0.25)
	wire_light.light_energy = 0.0
	wire_light.omni_range = 1.4
	wire_light.position = Vector3(0, -0.15, 0.2)
	face.add_child(wire_light)
	# Bolted repair plates over scorched spots (patched stage).
	var patches := Node3D.new()
	patches.name = "Patches"
	pod.add_child(patches)
	var steel_paint: ShaderMaterial = paint(STEEL, 0.35, 0.0, 1.5)
	for spec: Array in [[1, 0.98, Vector2(0.24, 0.2)], [11, 1.5, Vector2(0.2, 0.26)], [3, 0.55, Vector2(0.26, 0.16)]]:
		var f: Node3D = _on_facet(patches, int(spec[0]), float(spec[1]))
		var sz: Vector2 = spec[2]
		_box(f, Vector3(sz.x, sz.y, 0.012), steel_paint, Vector3(0, 0, 0.006))
		for cx: float in [-1.0, 1.0]:
			for cy: float in [-1.0, 1.0]:
				var b := MeshInstance3D.new()
				b.mesh = ProcMesh.cyl(0.012, 0.012, 0.01, 6)
				b.material_override = accent
				b.rotation.x = PI * 0.5
				b.position = Vector3(cx * (sz.x * 0.5 - 0.025), cy * (sz.y * 0.5 - 0.025), 0.014)
				f.add_child(b)
	# Cracks on the canopy and the porthole (crash-damaged only).
	var crack := StandardMaterial3D.new()
	crack.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	crack.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	crack.albedo_texture = crack_texture()
	crack.albedo_color = Color(0.9, 0.97, 1.0, 0.85)
	pod.set_meta("crack", crack)
	(pod.get_meta("canopy") as MeshInstance3D).material_overlay = crack
	# The planter ring (late upgrade): seedlings round the skirt, a soft green beacon beam.
	var planter := Node3D.new()
	planter.name = "Planter"
	pod.add_child(planter)
	var tray := MeshInstance3D.new()
	tray.mesh = ProcMesh.torus(0.9, 1.12, 36, 6)
	tray.material_override = accent
	tray.scale = Vector3(1, 0.35, 1)
	tray.position.y = 0.06
	planter.add_child(tray)
	var soil := MeshInstance3D.new()
	soil.mesh = ProcMesh.torus(0.93, 1.09, 36, 6)
	var soil_m := StandardMaterial3D.new()
	soil_m.albedo_color = Color(0.17, 0.11, 0.07)
	soil_m.roughness = 1.0
	soil.material_override = soil_m
	soil.scale = Vector3(1, 0.3, 1)
	soil.position.y = 0.09
	planter.add_child(soil)
	var leaf := Mats.lamp(Color(0.45, 1.0, 0.45), 0.7)
	leaf.albedo_color = Color(0.3, 0.72, 0.28)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for i: int in 22:
		var a: float = TAU * i / 22.0 + rng.randf_range(-0.08, 0.08)
		if absf(wrapf(a, -PI, PI)) < 0.6:
			continue  # keep the ramp clear
		var sprout := MeshInstance3D.new()
		sprout.mesh = ProcMesh.sphere(rng.randf_range(0.05, 0.09), 8, 5)
		sprout.material_override = leaf
		sprout.scale = Vector3(1.0, rng.randf_range(1.2, 2.0), 1.0)
		sprout.position = _pt(a, 0.18, 1.01)
		planter.add_child(sprout)
	var beam := MeshInstance3D.new()
	beam.name = "BeaconBeam"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.22
	cm.bottom_radius = 0.03
	cm.height = 6.0
	cm.cap_top = false
	cm.cap_bottom = false
	beam.mesh = cm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.albedo_color = Color(0.45, 1.0, 0.7, 0.12)
	bm.disable_fog = true
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = HEIGHT + 0.28 + 3.0
	planter.add_child(beam)
	pod.set_meta("kit", {"swing": swing, "bolts": bolts, "line": pline, "wires": wires, "wires_m": wires_m,
		"cable": cable, "links": links, "wire_light": wire_light, "patches": patches, "planter": planter})


# --- Condition ---------------------------------------------------------------------------

## 0 crash-damaged, 1 patched, 2 restored, 3 planter-beacon. Cosmetic only (no save state here).
static func set_condition(pod: Node3D, stage: int) -> void:
	var kit: Dictionary = pod.get_meta("kit", {})
	if kit.is_empty():
		return
	stage = clampi(stage, 0, 3)
	pod.set_meta("condition", stage)
	set_wear(pod, PEARL, [0.9, 0.45, 0.06, 0.06][stage])
	(kit["swing"] as Node3D).rotation = Vector3(-0.85, 0.0, 0.2) if stage == 0 else Vector3.ZERO
	(kit["bolts"] as Node3D).visible = stage == 1
	(kit["line"] as Node3D).visible = stage >= 2
	(kit["wires"] as Node3D).visible = stage == 0
	(kit["cable"] as Node3D).visible = stage == 0
	(kit["wire_light"] as OmniLight3D).visible = stage == 0
	(kit["patches"] as Node3D).visible = stage == 1
	(kit["planter"] as Node3D).visible = stage == 3
	var crack: StandardMaterial3D = pod.get_meta("crack")
	crack.albedo_color.a = 0.85 if stage == 0 else 0.0
	(pod.get_meta("porthole") as MeshInstance3D).material_overlay = crack if stage == 0 else null
	(pod.get_meta("fin_edge") as StandardMaterial3D).emission_energy_multiplier = 0.0 if stage < 2 else 1.6
	var seam: StandardMaterial3D = pod.get_meta("seam")
	seam.emission = CYAN
	seam.emission_energy_multiplier = 1.5 if stage >= 1 else 0.8
	(pod.get_meta("glyph") as StandardMaterial3D).emission_energy_multiplier = 2.2
	(pod.get_node("HoverGlow") as Node3D).visible = stage >= 2
	(pod.get_node("HoverLight") as OmniLight3D).visible = stage >= 2
	var hover: StandardMaterial3D = (pod.get_node("HoverGlow") as MeshInstance3D).material_override
	hover.albedo_color.a = 0.0 if stage < 2 else 0.45
	(pod.get_node("HoverLight") as OmniLight3D).light_energy = 0.0 if stage < 2 else 0.9
	(pod.get_meta("thrust") as StandardMaterial3D).emission_energy_multiplier = 0.0 if stage < 2 else 2.5
	for lm: StandardMaterial3D in pod.get_meta("fin_lamps", []):
		lm.emission_energy_multiplier = 0.0 if stage == 0 else 2.5
	_cabin_stage(pod, stage)


## [v7pod] The cabin per stage: 0 dead (console and lamps dark, the red alarm blinks, a dim amber
## glow), 1 patched (the console wakes, the alarm turns steady amber), 2+ restored (warm lamps on,
## a green all-good lamp, full warm light out of the door).
static func _cabin_stage(pod: Node3D, stage: int) -> void:
	var c: Dictionary = pod.get_meta("cabin", {})
	if c.is_empty():
		return
	YardArt.set_wear(c["cabin"], 0.3 if stage == 0 else 0.1)
	YardArt.set_powered(c["cabin"], stage >= 1)
	YardArt.set_powered(c["lamps"], stage >= 2)
	var alarm: StandardMaterial3D = (c["alarm"] as MeshInstance3D).material_override
	alarm.emission = [Color(1.0, 0.16, 0.1), Color(1.0, 0.6, 0.15), Color(0.4, 1.0, 0.5), Color(0.4, 1.0, 0.5)][stage]
	alarm.albedo_color = alarm.emission.darkened(0.3)
	alarm.emission_energy_multiplier = 0.0 if stage == 0 else 2.0
	pod.set_meta("cabin_k", CABIN_LIGHT[stage])
	var light: OmniLight3D = pod.get_node("PodLight")
	light.light_color = Color(1.0, 0.6, 0.4) if stage == 0 else Color(1.0, 0.78, 0.5)
	var hatch: Node3D = pod.get_node("Hatch")
	if hatch.rotation.x < -0.5:  # open: match the light to the stage
		set_open(pod, true, -(hatch.rotation.x - OPEN))


## Per-frame life: stuttering seams and glyph, flickering wires and a swaying cable while damaged;
## strobing fin lamps when patched; a slow hover pulse and lamp chase once restored.
static func animate(pod: Node3D, t: float, delta: float) -> void:
	var kit: Dictionary = pod.get_meta("kit", {})
	if kit.is_empty():
		return
	var stage: int = int(pod.get_meta("condition", 2))
	var lamps: Array = pod.get_meta("fin_lamps", [])
	match stage:
		0:
			var seam: StandardMaterial3D = pod.get_meta("seam")
			var glyph: StandardMaterial3D = pod.get_meta("glyph")
			var g: float = float(pod.get_meta("glitch_t", 0.0)) - delta
			if g <= 0.0:
				g = randf_range(0.04, 0.12) if randf() < 0.55 else randf_range(0.5, 1.8)
				var bad: bool = randf() < 0.5
				seam.emission_energy_multiplier = randf_range(0.0, 0.3) if bad else 1.2
				seam.emission = CYAN.lerp(Color(1.0, 0.3, 0.3), 0.6) if bad and randf() < 0.3 else CYAN
				glyph.emission_energy_multiplier = randf_range(0.0, 0.6) if bad else 1.6
			pod.set_meta("glitch_t", g)
			var w: float = maxf(0.0, 0.6 + 0.4 * sin(t * 37.0) * sin(t * 13.0))
			(kit["wires_m"] as StandardMaterial3D).emission_energy_multiplier = 1.0 + 2.5 * w
			var wl: OmniLight3D = kit["wire_light"]
			wl.light_energy = maxf(wl.light_energy - delta * 6.0, 0.3 + 0.5 * w)
			var links: Array = kit["links"]
			for k: int in links.size():
				(links[k] as Node3D).rotation = Vector3(sin(t * 1.7 - k * 0.5) * 0.12, 0, sin(t * 2.3 - k * 0.6) * 0.18)
			var cab: Dictionary = pod.get_meta("cabin", {})  # [v7pod] the cabin's alarm blinks
			if not cab.is_empty():
				var al: StandardMaterial3D = (cab["alarm"] as MeshInstance3D).material_override
				al.emission_energy_multiplier = 3.0 if fmod(t, 1.3) < 0.3 else 0.0
		1:
			for i: int in lamps.size():
				var ph: float = fmod(t * 1.3 + i * 0.33, 1.0)
				(lamps[i] as StandardMaterial3D).emission_energy_multiplier = 4.0 if ph < 0.05 or (ph > 0.1 and ph < 0.15) else 0.25
		_:
			var hover: StandardMaterial3D = (pod.get_node("HoverGlow") as MeshInstance3D).material_override
			hover.albedo_color.a = 0.4 + 0.08 * sin(t * 2.1)
			(pod.get_node("HoverLight") as OmniLight3D).light_energy = 0.8 + 0.2 * sin(t * 2.1)
			for i: int in lamps.size():
				(lamps[i] as StandardMaterial3D).emission_energy_multiplier = 3.2 if fmod(t * 0.7 + i * 0.33, 1.0) < 0.14 else 1.2


## A spark from the torn panel: kicks the wire light, returns where to burst.
static func spark(pod: Node3D) -> Vector3:
	var kit: Dictionary = pod.get_meta("kit", {})
	if kit.is_empty():
		return pod.global_position + Vector3(0, 1.2, 0)
	(kit["wire_light"] as OmniLight3D).light_energy = 2.4
	return (kit["wire_light"] as Node3D).global_position


# --- Door --------------------------------------------------------------------------------

## Snap the door open or shut (no animation), cabin light to match.
static func set_open(pod: Node3D, open: bool, lean: float = 0.0) -> void:
	var hatch: Node3D = pod.get_node("Hatch")
	hatch.rotation.x = OPEN - lean if open else 0.0
	hatch.position.z = float(pod.get_meta("hinge_z", -0.74))
	var k: float = float(pod.get_meta("cabin_k", 1.0))  # [v7pod] dim while the cabin is dead
	(pod.get_node("PodLight") as OmniLight3D).light_energy = 1.4 * k if open else 0.0
	((pod.get_node("Spill") as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a = 0.35 * k if open else 0.0


## Where steam vents from the door seams (pod-local).
static func seam_points() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for y: float in [0.6, 1.1, 1.5]:
		pts.append(_pt(_ang(DOOR_J0), y, _door_r(y) + 0.04))
		pts.append(_pt(_ang(DOOR_J1), y, _door_r(y) + 0.04))
	pts.append(_pt(0.0, DOOR_Y1 + 0.02, _door_r(DOOR_Y1) + 0.04))
	return pts


## The opening: the seal pops (a few cm kick and a hiss of steam), a beat, then the door drops into
## a ramp and settles; the warm cabin light spills onto the ground. puff(local_pos, dir) per jet.
## Returns the total time in seconds.
static func open_door(pod: Node3D, puff: Callable, speed: float = 1.0, lean: float = 0.0) -> float:
	var open_a: float = OPEN - lean
	var hatch: Node3D = pod.get_node("Hatch")
	var light: OmniLight3D = pod.get_node("PodLight")
	var spill: StandardMaterial3D = (pod.get_node("Spill") as MeshInstance3D).material_override
	var z0: float = float(pod.get_meta("hinge_z", -0.74))
	hatch.rotation.x = 0.0
	hatch.position.z = z0
	var k: float = 1.0 / maxf(speed, 0.05)
	var lk: float = float(pod.get_meta("cabin_k", 1.0))  # [v7pod] dim while the cabin is dead
	var tw := pod.create_tween()
	tw.tween_property(hatch, "position:z", z0 - 0.035, 0.12 * k).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(hatch, "rotation:x", -0.04, 0.12 * k)
	tw.parallel().tween_property(light, "light_energy", 0.35 * lk, 0.12 * k)
	tw.tween_callback(func() -> void:
		for p: Vector3 in seam_points():
			var out: Vector3 = Vector3(p.x, 0.0, p.z).normalized()
			puff.call(p, out + Vector3(0, 0.35, 0)))
	tw.tween_interval(0.45 * k)
	tw.tween_property(hatch, "rotation:x", open_a, 0.95 * k).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(light, "light_energy", 1.6 * lk, 0.95 * k)
	tw.parallel().tween_property(spill, "albedo_color:a", 0.38 * lk, 1.1 * k)
	tw.tween_property(hatch, "rotation:x", open_a + 0.07, 0.12 * k).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(hatch, "rotation:x", open_a, 0.16 * k).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(light, "light_energy", 1.4 * lk, 0.3 * k)
	return (0.12 + 0.45 + 0.95 + 0.28) * k


## Closing (the vault set: Lumi seals himself in). Returns the time in seconds.
static func close_door(pod: Node3D, speed: float = 1.0) -> float:
	var hatch: Node3D = pod.get_node("Hatch")
	var light: OmniLight3D = pod.get_node("PodLight")
	var spill: StandardMaterial3D = (pod.get_node("Spill") as MeshInstance3D).material_override
	var k: float = 1.0 / maxf(speed, 0.05)
	var tw := pod.create_tween()
	tw.tween_property(hatch, "rotation:x", -0.05, 0.75 * k).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(spill, "albedo_color:a", 0.0, 0.6 * k)
	tw.tween_property(hatch, "rotation:x", 0.0, 0.1 * k)
	tw.parallel().tween_property(light, "light_energy", 0.0, 0.2 * k)
	return 0.85 * k
