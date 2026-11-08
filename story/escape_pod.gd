class_name EscapePod
extends RefCounted
## [intro2] The cargo pod Lumi rides down in (intro, the vault set, the landmark beside the shack).
## An upright pearl-white egg built as one lathed shell with a real door opening cut out of it, so
## the door is the exact missing patch of the hull: no overlapping faces, no z-fighting. Behind the
## opening: a jamb (the hull's thickness), a dark padded interior and a warm light that spills out
## when the door drops. The door is hinged on its bottom edge and opens outward into a ramp.
## Nodes: "Hatch" (rotation.x: 0 closed, OPEN = open), "Scorch" (crater ring), "PodLight",
## "Spill" (light pool on the ground), "Body".

const OPEN: float = -1.62
const SEGS: int = 10  # ten flat facets, sharp chines (the Seedglider family's faceted look)
const DOOR_HALF: int = 1  # door width in facets either side of the front chine
const FRONT: int = 5  # SEGS / 2: the chine facing -Z
const DOOR_Y0: float = 0.34
const DOOR_Y1: float = 1.6
const WALL: float = 0.07
const DOOR_GAP: float = 0.012
# The Seedglider palette (automation/ship_model.gd on wt/ship): the pod is a piece of that family.
const PEARL := Color(0.93, 0.93, 0.91)
const PANEL := Color(0.82, 0.83, 0.84)
const TANGERINE := Color(1.0, 0.5, 0.16)
const TRIM := Color(0.09, 0.1, 0.115)
const CYAN := Color(0.3, 0.88, 1.0)
const LAMP := Color(1.0, 0.36, 0.12)
const SOOT := Color(0.36, 0.32, 0.28)  # re-entry scorch on a worn hull
const SHIP_PAINT := "res://art/shaders/ship_paint.gdshader"

## (radius, y) of the shell, bottom to top.
const PROFILE: Array[Vector2] = [
	Vector2(0.0, 0.0), Vector2(0.3, 0.015), Vector2(0.5, 0.05), Vector2(0.63, 0.12), Vector2(0.71, 0.22),
	Vector2(0.76, DOOR_Y0), Vector2(0.795, 0.55), Vector2(0.81, 0.8), Vector2(0.805, 1.05),
	Vector2(0.785, 1.3), Vector2(0.74, DOOR_Y1), Vector2(0.68, 1.8), Vector2(0.585, 1.98),
	Vector2(0.536, 2.04), Vector2(0.528, 2.05), Vector2(0.47, 2.12), Vector2(0.32, 2.24), Vector2(0.16, 2.31), Vector2(0.0, 2.335),
]


static func _ang(j: int) -> float:
	return (float(j) / SEGS) * TAU - PI


## A point on the shell: angle 0 faces -Z (the door side).
static func _pt(a: float, y: float, r: float) -> Vector3:
	return Vector3(sin(a) * r, y, -cos(a) * r)


static func _in_door(j: int, i: int) -> bool:
	var row_y: float = PROFILE[i].y
	var next_y: float = PROFILE[i + 1].y
	return j >= FRONT - DOOR_HALF and j < FRONT + DOOR_HALF and row_y >= DOOR_Y0 - 0.001 and next_y <= DOOR_Y1 + 0.001


## Which material a shell quad uses (by its row): 0 pearl, 1 tangerine band, 2 dark base, 3 cyan line.
static func _band(y0: float, y1: float) -> int:
	var m: float = (y0 + y1) * 0.5
	if m < 0.12:
		return 2
	if m > 1.6 and m < 1.8:
		return 1
	if m > 2.04 and m < 2.05:
		return 3
	return 0


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, nb := Vector3.ZERO, nt := Vector3.ZERO) -> void:
	# a-b bottom edge, d-c top edge. Godot's front faces wind clockwise. nb / nt: normals of the
	# bottom and top edge (facet normals: sharp chines around, smooth up the profile).
	# COLOR (1, 0, 0) = no baked AO / edge / cavity for ship_paint.
	var verts: Array[Vector3] = [a, b, c, a, c, d]
	var uvs: Array[Vector2] = [ua, ub, uc, ua, uc, ud]
	var ns: Array[Vector3] = [nb, nb, nt, nb, nt, nt]
	for k: int in 6:
		st.set_color(Color(1, 0, 0))
		if nb != Vector3.ZERO:
			st.set_normal(ns[k])
		st.set_uv(uvs[k])
		st.add_vertex(verts[k])


## Facet normal at height y: the facet's outward direction tilted by the profile's slope.
static func _facet_n(am: float, y: float, flip: bool) -> Vector3:
	var e: float = 0.02
	var ya: float = clampf(y - e, 0.0005, PROFILE[-1].y - 0.0005)
	var yb: float = clampf(y + e, 0.0005, PROFILE[-1].y - 0.0005)
	var slope: float = (_door_r(yb) - _door_r(ya)) / maxf(yb - ya, 0.0001)
	var n := (Vector3(sin(am), 0.0, -cos(am)) - Vector3(0, slope, 0)).normalized()
	if y <= 0.001:
		n = Vector3.DOWN
	elif y >= PROFILE[-1].y - 0.001:
		n = Vector3.UP
	return -n if flip else n


static func _uv(j: int, y: float) -> Vector2:
	return Vector2(float(j) / SEGS * 4.6, y)


## The shell (minus the door opening) as one mesh with a surface per band material.
static func _shell_mesh(inset: float, flip: bool, skip_door: bool, door_only: bool, gap: float = 0.0) -> Array[SurfaceTool]:
	var sts: Array[SurfaceTool] = []
	for k: int in 4:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(0)
		sts.append(st)
	for i: int in PROFILE.size() - 1:
		var y0: float = PROFILE[i].y
		var y1: float = PROFILE[i + 1].y
		var r0: float = maxf(PROFILE[i].x - inset, 0.0) if PROFILE[i].x > 0.0 else 0.0
		var r1: float = maxf(PROFILE[i + 1].x - inset, 0.0) if PROFILE[i + 1].x > 0.0 else 0.0
		var band: int = _band(y0, y1)
		for j: int in SEGS:
			var door: bool = _in_door(j, i)
			if (skip_door and door) or (door_only and not door):
				continue
			var a0: float = _ang(j)
			var a1: float = _ang(j + 1)
			var qy0: float = y0
			var qy1: float = y1
			var qr0: float = r0
			var qr1: float = r1
			if door_only and gap > 0.0:
				# The door is a hair smaller than its opening: a thin dark seam all round.
				var ag: float = gap / 0.78
				a0 = maxf(a0, _ang(FRONT - DOOR_HALF) + ag)
				a1 = minf(a1, _ang(FRONT + DOOR_HALF) - ag)
				qy0 = maxf(y0, DOOR_Y0 + gap)
				qy1 = minf(y1, DOOR_Y1 - gap)
				qr0 = _door_r(qy0) - inset
				qr1 = _door_r(qy1) - inset
			var p00: Vector3 = _pt(a0, qy0, qr0)
			var p10: Vector3 = _pt(a1, qy0, qr0)
			var p11: Vector3 = _pt(a1, qy1, qr1)
			var p01: Vector3 = _pt(a0, qy1, qr1)
			var st: SurfaceTool = sts[0 if door_only else band]
			var am: float = (_ang(j) + _ang(j + 1)) * 0.5
			var nb: Vector3 = _facet_n(am, qy0, flip)
			var nt: Vector3 = _facet_n(am, qy1, flip)
			if flip:
				_quad(st, p10, p00, p01, p11, _uv(j + 1, y0), _uv(j, y0), _uv(j, y1), _uv(j + 1, y1), nb, nt)
			else:
				_quad(st, p00, p10, p11, p01, _uv(j, y0), _uv(j + 1, y0), _uv(j + 1, y1), _uv(j, y1), nb, nt)
	return sts


static func _commit(sts: Array[SurfaceTool], mats: Array[Material]) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for k: int in sts.size():
		var st: SurfaceTool = sts[k]
		var arr: Array = st.commit_to_arrays()
		if arr.is_empty() or not (arr[Mesh.ARRAY_VERTEX] is PackedVector3Array) or (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats[mini(k, mats.size() - 1)])
	return mesh


## The jamb: the hull's thickness around the opening (outer shell to the inner lining).
static func _jamb_mesh(out_off: float = 0.0, in_off: float = WALL, shift: Vector3 = Vector3.ZERO, gap: float = 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var j0: int = FRONT - DOOR_HALF
	var j1: int = FRONT + DOOR_HALF
	var rows: Array[int] = []
	for i: int in PROFILE.size():
		if PROFILE[i].y >= DOOR_Y0 - 0.001 and PROFILE[i].y <= DOOR_Y1 + 0.001:
			rows.append(i)
	var ag: float = gap / 0.78
	var ey := func(i: int) -> float: return clampf(PROFILE[i].y, DOOR_Y0 + gap, DOOR_Y1 - gap)
	var ea := func(j: int) -> float: return clampf(_ang(j), _ang(j0) + ag, _ang(j1) - ag)
	var o := func(j: int, i: int) -> Vector3: return _pt(ea.call(j), ey.call(i), _door_r(ey.call(i)) - out_off) - shift
	var n := func(j: int, i: int) -> Vector3: return _pt(ea.call(j), ey.call(i), _door_r(ey.call(i)) - in_off) - shift
	# Bottom sill and top lintel.
	for j: int in range(j0, j1):
		for edge: int in [rows[0], rows[-1]]:
			var a: Vector3 = o.call(j, edge)
			var b: Vector3 = o.call(j + 1, edge)
			var c: Vector3 = n.call(j + 1, edge)
			var d: Vector3 = n.call(j, edge)
			if edge == rows[0]:
				_quad(st, d, c, b, a, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN)
			else:
				_quad(st, a, b, c, d, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN)
	# Left and right posts.
	for k: int in rows.size() - 1:
		for side: int in [j0, j1]:
			var a: Vector3 = o.call(side, rows[k])
			var b: Vector3 = n.call(side, rows[k])
			var c: Vector3 = n.call(side, rows[k + 1])
			var d: Vector3 = o.call(side, rows[k + 1])
			if side == j0:
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
		var st: SurfaceTool = pair[0]
		var arr: Array = st.commit_to_arrays()
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for v: int in vs.size():
			vs[v] -= hinge
		arr[Mesh.ARRAY_VERTEX] = vs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, pair[1])
	return mesh


static func _door_r(y: float) -> float:
	for i: int in PROFILE.size() - 1:
		if y >= PROFILE[i].y and y <= PROFILE[i + 1].y:
			return lerpf(PROFILE[i].x, PROFILE[i + 1].x, (y - PROFILE[i].y) / maxf(PROFILE[i + 1].y - PROFILE[i].y, 0.0001))
	return 0.78


static func build() -> Node3D:
	var pod := Node3D.new()
	pod.name = "LandingPod"
	var shell: Material = paint(PEARL, 0.3)
	var accent: Material = paint(TANGERINE, 0.3)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = TRIM
	dark.roughness = 0.4
	dark.metallic = 0.5
	var line: StandardMaterial3D = Mats.lamp(CYAN, 1.5)
	var lining := StandardMaterial3D.new()
	lining.albedo_color = Color(0.36, 0.33, 0.3)
	lining.roughness = 0.8
	lining.emission_enabled = true
	lining.emission = Color(1.0, 0.72, 0.45)
	lining.emission_energy_multiplier = 0.12
	var ramp := StandardMaterial3D.new()
	ramp.albedo_color = Color(0.6, 0.6, 0.58)
	ramp.roughness = 0.6
	ramp.metallic = 0.3
	var gasket := StandardMaterial3D.new()
	gasket.albedo_color = Color(0.06, 0.06, 0.065)
	gasket.roughness = 0.6
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _commit(_shell_mesh(0.0, false, true, false), [shell, accent, dark, line] as Array[Material])
	pod.add_child(body)
	# Inner lining (seen through the opening) and the jamb.
	var lin := MeshInstance3D.new()
	lin.name = "Lining"
	lin.mesh = _commit(_shell_mesh(WALL, true, false, false), [lining] as Array[Material])
	lin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pod.add_child(lin)
	var jamb := MeshInstance3D.new()
	jamb.name = "Jamb"
	jamb.mesh = _jamb_mesh()
	jamb.material_override = gasket
	pod.add_child(jamb)
	gasket.cull_mode = BaseMaterial3D.CULL_DISABLED
	lining.cull_mode = BaseMaterial3D.CULL_DISABLED
	# A thin tangerine floor strip and a seat pad inside (reads as a cabin when the door is open).
	var pad := MeshInstance3D.new()
	pad.mesh = ProcMesh.rounded_box(Vector3(0.7, 0.08, 0.5), 0.03, 2)
	pad.material_override = accent
	pad.position = Vector3(0, DOOR_Y0 - 0.02, 0.05)
	pod.add_child(pad)
	# Three swept graphite fins on the chines away from the door, tangerine tips with a small
	# orange running lamp (the glider's wing language).
	var fin_mesh: ArrayMesh = _fin_mesh()
	var fin_mat: StandardMaterial3D = dark.duplicate()
	fin_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lamp: StandardMaterial3D = Mats.lamp(LAMP, 2.5)
	for k: int in 3:
		var a: float = _ang([2, 0, 8][k])
		var fin := MeshInstance3D.new()
		fin.name = "Fin%d" % k
		fin.mesh = fin_mesh
		fin.material_override = fin_mat
		fin.position = _pt(a, 0.0, 0.0)
		fin.rotation = Vector3(0, PI - a, 0)
		pod.add_child(fin)
		var tip := MeshInstance3D.new()
		tip.mesh = ProcMesh.box(Vector3(0.05, 0.16, 0.2))
		tip.material_override = accent
		tip.position = Vector3(0, 0.12, 1.12)
		fin.add_child(tip)
		var bulb := MeshInstance3D.new()
		bulb.name = "Lamp"
		bulb.mesh = ProcMesh.sphere(0.025, 8, 4)
		bulb.material_override = lamp
		bulb.position = Vector3(0, 0.22, 1.16)
		fin.add_child(bulb)
	# A porthole on the back and a beacon on top.
	var port := MeshInstance3D.new()
	port.mesh = ProcMesh.sphere(0.17, 20, 10)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.08, 0.42, 0.55)
	glass.roughness = 0.05
	glass.metallic = 0.3
	glass.clearcoat_enabled = true
	glass.emission_enabled = true
	glass.emission = Color(0.1, 0.55, 0.7)
	glass.emission_energy_multiplier = 0.25
	port.material_override = glass
	port.scale = Vector3(1, 1, 0.35)
	port.position = _pt(PI, 1.25, _door_r(1.25) - 0.03)
	pod.add_child(port)
	var beacon := MeshInstance3D.new()
	beacon.name = "Beacon"
	beacon.mesh = ProcMesh.sphere(0.06, 12, 6)
	beacon.material_override = Mats.lamp(LAMP, 3.0)
	beacon.position = Vector3(0, 2.33, 0)
	pod.add_child(beacon)
	# The door, hinged along its bottom edge.
	var hinge := Vector3(0, DOOR_Y0, -_door_r(DOOR_Y0) + 0.02)
	var hatch := Node3D.new()
	hatch.name = "Hatch"
	hatch.position = hinge
	pod.add_child(hatch)
	var door := MeshInstance3D.new()
	door.name = "Door"
	door.mesh = _door_mesh(hinge, [shell, ramp] as Array[Material])
	hatch.add_child(door)
	var edge := MeshInstance3D.new()
	edge.name = "DoorEdge"
	edge.mesh = _jamb_mesh(-0.004, WALL * 0.6, hinge, DOOR_GAP)
	edge.material_override = gasket
	hatch.add_child(edge)
	# Door details sit proud of its surface: a tangerine grab bar and a thin cyan status line.
	var mid_y: float = (DOOR_Y0 + DOOR_Y1) * 0.5
	var bar := MeshInstance3D.new()
	bar.mesh = ProcMesh.rounded_box(Vector3(0.36, 0.06, 0.05), 0.025, 2)
	bar.material_override = accent
	bar.position = Vector3(0, mid_y + 0.28, -_door_r(mid_y + 0.28) - 0.02) - hinge
	hatch.add_child(bar)
	var status := MeshInstance3D.new()
	status.mesh = ProcMesh.rounded_box(Vector3(0.22, 0.018, 0.02), 0.008, 1)
	status.material_override = line
	status.position = Vector3(0, mid_y - 0.2, -_door_r(mid_y - 0.2) - 0.012) - hinge
	hatch.add_child(status)
	# Warm cabin light (off until the door opens) and its pool on the ground.
	var light := OmniLight3D.new()
	light.name = "PodLight"
	light.light_color = Color(1.0, 0.78, 0.5)
	light.light_energy = 0.0
	light.omni_range = 3.2
	light.shadow_enabled = false
	light.position = Vector3(0, 1.1, 0.05)
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
	# Scorched crater ring.
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
	return pod


## Hull paint: the Seedglider's ship_paint shader when it is in the project (wt/ship), else a
## clear-coat StandardMaterial3D in the same colours. wear 0..1 (a crash-worn pod is ~0.4).
static func paint(color: Color, rough: float = 0.3, wear: float = 0.0) -> Material:
	if ResourceLoader.exists(SHIP_PAINT):
		var sh: Shader = load(SHIP_PAINT) as Shader
		if sh:
			var m := ShaderMaterial.new()
			m.shader = sh
			m.set_shader_parameter("paint_color", color)
			m.set_shader_parameter("roughness", rough)
			m.set_shader_parameter("clearcoat_amt", 0.6)
			m.set_shader_parameter("edge_wear", wear)
			# Procedural meshes carry no baked AO / edge / cavity colours.
			m.set_shader_parameter("seam_dark", 0.0)
			m.set_shader_parameter("edge_light", 0.0)
			m.set_shader_parameter("ao_strength", 0.0)
			return m
	var sm := StandardMaterial3D.new()
	sm.albedo_color = color.lerp(SOOT, wear * 1.1)
	sm.roughness = rough + wear * 0.3
	sm.metallic = 0.05
	sm.clearcoat_enabled = true
	sm.clearcoat = 0.6 * (1.0 - wear * 0.6)
	sm.clearcoat_roughness = 0.15
	return sm


## Set the hull wear (crash site repair): works for both paint kinds.
static func set_wear(pod: Node3D, color: Color, wear: float) -> void:
	var body: MeshInstance3D = pod.get_node_or_null("Body")
	if body == null:
		return
	var m: Material = body.mesh.surface_get_material(0)
	if m is ShaderMaterial:
		(m as ShaderMaterial).set_shader_parameter("edge_wear", wear)
	elif m is StandardMaterial3D:
		var sm: StandardMaterial3D = m
		sm.albedo_color = color.lerp(SOOT, wear * 1.1)
		sm.roughness = 0.3 + wear * 0.3
		sm.clearcoat = 0.6 * (1.0 - wear * 0.6)


## A swept fin: a thin trapezoid prism in the YZ plane, root along the hull, tip swept back (+Z) and
## up, sharp edges.
static func _fin_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var t: float = 0.03
	# Outline (y, z): root bottom, root top, tip top, tip bottom.
	var o: Array[Vector2] = [Vector2(0.0, 0.3), Vector2(0.72, 0.7), Vector2(0.3, 1.14), Vector2(-0.02, 1.12)]
	var side := func(x: float) -> Array[Vector3]:
		var out: Array[Vector3] = []
		for q: Vector2 in o:
			out.append(Vector3(x, q.x, q.y))
		return out
	var l: Array[Vector3] = side.call(-t)
	var r: Array[Vector3] = side.call(t)
	_quad(st, l[0], l[1], l[2], l[3], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	_quad(st, r[3], r[2], r[1], r[0], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	for k: int in 4:
		var k2: int = (k + 1) % 4
		_quad(st, r[k], r[k2], l[k2], l[k], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	st.generate_normals()
	return st.commit()


static var _soft: GradientTexture2D


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


## Snap the door open or shut (no animation), cabin light to match.
static func set_open(pod: Node3D, open: bool, lean: float = 0.0) -> void:
	(pod.get_node("Hatch") as Node3D).rotation.x = OPEN - lean if open else 0.0
	(pod.get_node("Hatch") as Node3D).position.z = -_door_r(DOOR_Y0) + 0.02
	(pod.get_node("PodLight") as OmniLight3D).light_energy = 1.4 if open else 0.0
	((pod.get_node("Spill") as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a = 0.35 if open else 0.0


## Where steam vents from the door seams (pod-local).
static func seam_points() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var a: float = _ang(FRONT + DOOR_HALF)
	for y: float in [0.6, 1.1, 1.5]:
		pts.append(_pt(a, y, _door_r(y) + 0.04))
		pts.append(_pt(-a, y, _door_r(y) + 0.04))
	pts.append(_pt(0.0, DOOR_Y1 + 0.02, _door_r(DOOR_Y1) + 0.04))
	return pts


## The opening: the seal pops (the door kicks out a few cm with a hiss of steam), a beat, then it
## drops outward into a ramp and settles; the warm cabin light spills onto the ground.
## puff(local_pos, dir) is called for each steam jet (the caller knows which world the pod is in).
## Returns the total time in seconds.
static func open_door(pod: Node3D, puff: Callable, speed: float = 1.0, lean: float = 0.0) -> float:
	var open_a: float = OPEN - lean  # a pod leaning back opens further so the ramp still meets the ground
	var hatch: Node3D = pod.get_node("Hatch")
	var light: OmniLight3D = pod.get_node("PodLight")
	var spill: StandardMaterial3D = (pod.get_node("Spill") as MeshInstance3D).material_override
	var z0: float = -_door_r(DOOR_Y0) + 0.02
	hatch.rotation.x = 0.0
	hatch.position.z = z0
	var k: float = 1.0 / maxf(speed, 0.05)
	var tw := pod.create_tween()
	# Unlatch: a small outward kick and a crack of light.
	tw.tween_property(hatch, "position:z", z0 - 0.035, 0.12 * k).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(hatch, "rotation:x", -0.04, 0.12 * k)
	tw.parallel().tween_property(light, "light_energy", 0.35, 0.12 * k)
	tw.tween_callback(func() -> void:
		for p: Vector3 in seam_points():
			var out: Vector3 = Vector3(p.x, 0.0, p.z).normalized()
			puff.call(p, out + Vector3(0, 0.35, 0)))
	tw.tween_interval(0.45 * k)
	# The drop: gravity pulls it open (ease-in), the light swells as the gap widens.
	tw.tween_property(hatch, "rotation:x", open_a, 0.95 * k).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(light, "light_energy", 1.6, 0.95 * k)
	tw.parallel().tween_property(spill, "albedo_color:a", 0.38, 1.1 * k)
	# A small settle on the ground.
	tw.tween_property(hatch, "rotation:x", open_a + 0.07, 0.12 * k).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(hatch, "rotation:x", open_a, 0.16 * k).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(light, "light_energy", 1.4, 0.3 * k)
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
