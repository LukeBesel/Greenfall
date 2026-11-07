class_name Meadow
extends Node3D
## [green] The living ground cover of restored hexes, so a district visibly turns green:
## - grass tufts, flower clumps and planting-row sprouts, placed once over every plantable patch
##   of the field (lots, verges, sidewalk edges; never roads, buildings or the yard) and grown in
##   the vertex shader (art/shaders/meadow.gdshader) from the field's life texture: R life, G hex
##   level, B row angle. Coverage, height and the organic border follow life with no CPU work.
## - Thriving hexes get shrubs, ferns and small trees (real plant models, a few per hex).
## Planted -> sprouts in rows on dark tilled soil; Growing -> young grass patches; Sustained ->
## a closed sward with flowers; Thriving -> a dense meadow, flowers, shrubs and small trees.
## Pure presentation: nothing is saved; it is rebuilt from the garden and hex levels.

const CHUNK: float = 24.0
## Grid spacing (m) per quality preset: Low, Medium, High, Ultra.
const GRASS_STEP: Array[float] = [0.95, 0.8, 0.62, 0.52]
const FLOWER_STEP: Array[float] = [1.4, 1.15, 0.95, 0.85]
const ROW_GAP: float = 0.8
const SPROUT_STEP: Array[float] = [0.9, 0.75, 0.6, 0.55]
const THRIVE_MODELS: Array = [
	# [model, count per hex, scale min, scale max, needs open lot]
	["shrub_02", 3, 0.75, 1.05, true],
	["pine_sapling_small", 2, 1.5, 2.1, true],
	["fern_02", 4, 1.1, 1.5, false],
]

var world: Node
var field: HexField
var layout: CityLayout
var _mats: Dictionary = {}
var _thrive_done: Dictionary = {}  # hid -> true
var _thrive_mm: Dictionary = {}  # "model|variant" -> MultiMeshInstance3D
var _thrive_xf: Dictionary = {}  # "model|variant" -> Array[Transform3D]
var _built: bool = false


func setup(p_world: Node) -> void:
	world = p_world
	field = world.field
	layout = field.layout
	name = "Meadow"


func _process(_delta: float) -> void:
	if _built:
		return
	# Built on the first frame, once hex levels (and any --future / --restore preview) are in.
	_built = true
	_build()


func _build() -> void:
	var view: FieldView = world.get("view") as FieldView
	if view == null or view.ground_material == null:
		return
	var t0: int = Time.get_ticks_msec()
	var q: int = clampi(Settings.quality, 0, 3)
	var gm: ShaderMaterial = view.ground_material
	var rng := RandomNumberGenerator.new()
	rng.seed = field.seed_value * 7 + 11
	for hid: int in field.hex_count():
		view.set_rows(hid, _hh(hid, 3))
	var hl: HexLevels = world.get("hex_levels") as HexLevels
	if hl:
		for hid: int in hl.levels:
			view.set_level(hid, int(hl.levels[hid]))
			if int(hl.levels[hid]) >= 5:
				_add_thriving(hid)
		EventBus.hex_level_changed.connect(_on_level)
	_place_kind(0, _tuft_mesh(), GRASS_STEP[q], 0.55, gm, rng)
	_place_kind(1, _flower_mesh(), FLOWER_STEP[q], 0.55, gm, rng)
	_place_sprouts(_sprout_mesh(), SPROUT_STEP[q], gm, rng)
	print("[meadow] %s in %d ms" % [census(), Time.get_ticks_msec() - t0])


## "grass=N flowers=N sprouts=N thriving=N" (instances placed).
func census() -> String:
	var n: Array[int] = [0, 0, 0]
	for c: Node in get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("Meadow"):
			n[int(String(c.name).substr(6, 1))] += (c as MultiMeshInstance3D).multimesh.instance_count
	return "grass=%d flowers=%d sprouts=%d thriving=%d" % [n[0], n[1], n[2], thriving_count()]


func _on_level(hid: int, level: int) -> void:
	var view: FieldView = world.get("view") as FieldView
	if view:
		view.set_level(hid, level)
	if level >= 5:
		_add_thriving(hid)


static func _hh(a: int, b: int = 0) -> float:
	var x: int = (a * 73856093) ^ (b * 19349663) ^ 0x5bd1e995
	x = (x ^ (x >> 13)) * 1274126177
	return float((x ^ (x >> 16)) & 0xffff) / 65535.0


## Plantable here? Lots and sidewalks (sidewalks only for a sparser fringe), on land, off the yard.
func _surface_ok(x: float, z: float) -> int:
	if layout == null:
		return 2
	match layout.surface_at(x, z):
		CityLayout.Surface.LOT:
			return 2
		CityLayout.Surface.SIDEWALK:
			return 1
		CityLayout.Surface.ROAD:
			# Grass verges along the kerbs of restored streets (ground_pbr draws the same verge).
			var off: int = 0
			for i: int in 8:
				var a: float = TAU * i / 8.0
				if layout.surface_at(x + cos(a) * 2.2, z + sin(a) * 2.2) != CityLayout.Surface.ROAD:
					off += 1
			return 3 if off >= 2 else 0
	return 0


func _hex_of(p: Vector3) -> int:
	return field.hex_at(p + field.border_warp(p)) if field.natural_borders else field.hex_at(p)


func _land(hid: int) -> bool:
	return hid >= 0 and field.hex_hub[hid] == 0 and not field.is_water(hid)


func _material(kind: int, height: float, gm: ShaderMaterial) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://art/shaders/meadow.gdshader")
	for k: String in ["warp_tex", "warp_size", "warp_amp", "life_tex", "grid_radius", "hex_size", "grass_tint"]:
		var v: Variant = gm.get_shader_parameter(k)
		if v != null:
			m.set_shader_parameter(k, v)
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("height_m", height)
	var far: float = [42.0, 55.0, 70.0, 85.0][clampi(Settings.quality, 0, 3)]
	m.set_shader_parameter("fade_start", far * 0.6)
	m.set_shader_parameter("fade_end", far)
	return m


func _place_kind(kind: int, mesh: Mesh, step: float, height: float, gm: ShaderMaterial, rng: RandomNumberGenerator) -> void:
	var r_m: float = (field.radius + 0.75) * field.hex_size * 1.75
	var n: int = int(ceil(r_m / step))
	var buckets: Dictionary = {}
	for gx: int in range(-n, n + 1):
		for gz: int in range(-n, n + 1):
			var p := Vector3((gx + rng.randf_range(-0.45, 0.45)) * step, 0.0, (gz + rng.randf_range(-0.45, 0.45)) * step)
			var rank: float = rng.randf()
			var hue: float = rng.randf()
			var pick: float = rng.randf()
			var sz: float = rng.randf()
			var yaw: float = rng.randf() * TAU
			if p.length() > r_m:
				continue
			var ok: int = _surface_ok(p.x, p.z)
			if ok == 0 or not _land(_hex_of(p)):
				continue
			if ok == 1:
				rank = 0.55 + rank * 0.45  # sidewalks: only a fringe, late
			elif ok == 3:
				rank = 0.4 + rank * 0.6  # kerb verges: once the hex is well established
			p.y = layout.height_at(p.x, p.z) if layout else 0.0
			_bucket(buckets, p, Transform3D(Basis(Vector3.UP, yaw), p), Color(rank, hue, pick, sz))
	_emit(buckets, mesh, _material(kind, height, gm), kind)


func _place_sprouts(mesh: Mesh, step: float, gm: ShaderMaterial, rng: RandomNumberGenerator) -> void:
	# Rows across each hex at its planting angle, sprouts sitting on the furrow crests.
	var buckets: Dictionary = {}
	for hid: int in field.hex_count():
		if not _land(hid):
			continue
		var a: float = _hh(hid, 3) * PI
		var d := Vector3(cos(a), 0.0, sin(a))
		var perp := Vector3(-d.z, 0.0, d.x)
		var c: Vector3 = field.hex_center(hid)
		var ext: float = field.hex_size * 1.6
		var rows: int = int(ext / ROW_GAP)
		var cols: int = int(ext / step)
		for i: int in range(-rows, rows + 1):
			for j: int in range(-cols, cols + 1):
				# Crest of the ground shader's furrows: dot(p, perp) = (k + 0.25) * ROW_GAP.
				var k0: float = floorf(perp.dot(c) / ROW_GAP)
				var along: float = d.dot(c) + j * step + rng.randf_range(-0.08, 0.08)
				var across: float = (k0 + i + 0.25) * ROW_GAP
				var p: Vector3 = d * along + perp * across
				if _hex_of(p) != hid or _surface_ok(p.x, p.z) != 2:
					continue
				p.y = layout.height_at(p.x, p.z) if layout else 0.0
				_bucket(buckets, p, Transform3D(Basis(Vector3.UP, a + rng.randf_range(-0.6, 0.6)), p),
					Color(rng.randf() * 0.9, rng.randf(), 0.0, rng.randf()))
	_emit(buckets, mesh, _material(2, 0.24, gm), 2)


func _bucket(buckets: Dictionary, p: Vector3, xf: Transform3D, cd: Color) -> void:
	var ck := Vector2i(floori(p.x / CHUNK), floori(p.z / CHUNK))
	if not buckets.has(ck):
		buckets[ck] = [[], []]
	(buckets[ck][0] as Array).append(xf)
	(buckets[ck][1] as Array).append(cd)


func _emit(buckets: Dictionary, mesh: Mesh, mat: ShaderMaterial, kind: int) -> void:
	for ck: Vector2i in buckets:
		var xfs: Array = buckets[ck][0]
		var cds: Array = buckets[ck][1]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = xfs.size()
		for i: int in xfs.size():
			mm.set_instance_transform(i, xfs[i])
			mm.set_instance_custom_data(i, cds[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Meadow%d_%d_%d" % [kind, ck.x, ck.y]
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = float(mat.get_shader_parameter("fade_end")) + CHUNK
		add_child(mmi)


# --- Thriving: shrubs, ferns and small trees ----------------------------------------------

func _add_thriving(hid: int) -> void:
	if _thrive_done.has(hid) or not _land(hid):
		return
	_thrive_done[hid] = true
	var c: Vector3 = field.hex_center(hid)
	var placed: Array[Vector3] = []
	var touched: Dictionary = {}
	for mi: int in THRIVE_MODELS.size():
		var spec: Array = THRIVE_MODELS[mi]
		var parts: Array[Mesh] = PlantParts.variants(str(spec[0]))
		if parts.is_empty():
			continue
		var want: int = int(spec[1])
		var tries: int = 0
		var k: int = 0
		while k < want and tries < want * 10:
			tries += 1
			var a: float = _hh(hid, 100 + mi * 31 + tries) * TAU
			var r: float = sqrt(_hh(hid, 200 + mi * 31 + tries)) * field.hex_size * 0.85
			var p: Vector3 = c + Vector3(cos(a), 0.0, sin(a)) * r
			if _hex_of(p) != hid:
				continue
			var ok: int = _surface_ok(p.x, p.z)
			if ok == 0 or ok == 3 or (bool(spec[4]) and (ok != 2 or not _open_lot(p, 1.4))):
				continue
			var near: bool = false
			for q: Vector3 in placed:
				if q.distance_to(p) < 1.6:
					near = true
					break
			if near:
				continue
			placed.append(p)
			p.y = layout.height_at(p.x, p.z) if layout else 0.0
			var vi: int = int(_hh(hid, 300 + mi * 31 + tries) * parts.size()) % parts.size()
			var sc: float = lerpf(float(spec[2]), float(spec[3]), _hh(hid, 400 + tries))
			var key: String = "%s|%d" % [spec[0], vi]
			if not _thrive_xf.has(key):
				_thrive_xf[key] = []
			(_thrive_xf[key] as Array).append(Transform3D(Basis(Vector3.UP, a * 3.0).scaled(Vector3.ONE * sc), p))
			touched[key] = parts[vi]
			k += 1
	for key: String in touched:
		_flush_thrive(key, touched[key])


func _open_lot(p: Vector3, r: float) -> bool:
	for i: int in 6:
		var a: float = TAU * i / 6.0
		if _surface_ok(p.x + cos(a) * r, p.z + sin(a) * r) != 2:
			return false
	return true


func _flush_thrive(key: String, mesh: Mesh) -> void:
	var xfs: Array = _thrive_xf[key]
	if not _thrive_mm.has(key):
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Thrive_" + key.replace("|", "_")
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mmi.multimesh = mm
		mmi.visibility_range_end = 140.0
		add_child(mmi)
		_thrive_mm[key] = mmi
	var mm2: MultiMesh = (_thrive_mm[key] as MultiMeshInstance3D).multimesh
	mm2.instance_count = xfs.size()
	for i: int in xfs.size():
		mm2.set_instance_transform(i, xfs[i])


## Thriving extras placed so far (tests, reports).
func thriving_count() -> int:
	var n: int = 0
	for key: String in _thrive_xf:
		n += (_thrive_xf[key] as Array).size()
	return n


# --- Meshes (unit height; the shader scales them) ------------------------------------------

## A tuft of curved, tapering blades.
static func _tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for b: int in 16:
		var a: float = TAU * b / 16.0 + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0.0, sin(a))
		var base: Vector3 = out * rng.randf_range(0.0, 0.32)
		_blade(st, base, out, rng.randf_range(0.5, 1.0), rng.randf_range(0.05, 0.085), rng.randf_range(0.2, 0.6), Color.BLACK)
	st.generate_normals()
	return st.commit()


static func _blade(st: SurfaceTool, base: Vector3, out: Vector3, h: float, w: float, lean: float, col: Color) -> void:
	var side: Vector3 = out.cross(Vector3.UP).normalized()
	var pts: Array[Vector3] = []
	var ws: Array[float] = [1.0, 0.85, 0.55, 0.0]
	var ts: Array[float] = [0.0, 0.35, 0.7, 1.0]
	for t: float in ts:
		pts.append(base + out * lean * t * t + Vector3(0.0, h * t, 0.0))
	for i: int in 3:
		var a0: Vector3 = pts[i] - side * w * ws[i]
		var a1: Vector3 = pts[i] + side * w * ws[i]
		var b0: Vector3 = pts[i + 1] - side * w * ws[i + 1]
		var b1: Vector3 = pts[i + 1] + side * w * ws[i + 1]
		for v: Vector3 in [a0, b0, a1, a1, b0, b1]:
			st.set_color(col)
			st.add_vertex(v)


## Two or three stems with flat, five-petal heads (painted red: the shader picks the colour) and a
## few leaves at the base.
static func _flower_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	for f: int in 3:
		var a: float = TAU * f / 3.0 + rng.randf_range(-0.4, 0.4)
		var out := Vector3(cos(a), 0.0, sin(a))
		var base: Vector3 = out * rng.randf_range(0.03, 0.12)
		var h: float = rng.randf_range(0.65, 1.0)
		var lean: float = rng.randf_range(0.05, 0.18)
		_blade(st, base, out, h, 0.018, lean, Color.BLACK)
		var top: Vector3 = base + out * lean + Vector3(0.0, h, 0.0)
		var r: float = rng.randf_range(0.2, 0.27)
		var tilt: Basis = Basis(out.cross(Vector3.UP).normalized(), -0.35)
		for k: int in 5:
			var pa: float = TAU * k / 5.0
			var c0: Vector3 = top
			var c1: Vector3 = top + tilt * (Vector3(cos(pa - 0.42), 0.0, sin(pa - 0.42)) * r * 0.55)
			var c2: Vector3 = top + tilt * (Vector3(cos(pa), 0.05, sin(pa)) * r)
			var c3: Vector3 = top + tilt * (Vector3(cos(pa + 0.42), 0.0, sin(pa + 0.42)) * r * 0.55)
			for v: Vector3 in [c0, c1, c2, c0, c2, c3]:
				st.set_color(Color.RED)
				st.add_vertex(v + Vector3(0.0, 0.01, 0.0))
	for l: int in 4:
		var a2: float = TAU * l / 4.0 + 0.4
		_blade(st, Vector3.ZERO, Vector3(cos(a2), 0.0, sin(a2)), 0.35, 0.05, 0.25, Color.BLACK)
	st.generate_normals()
	return st.commit()


## A seedling: a short stem with two round seed leaves (unit height ~1).
static func _sprout_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_blade(st, Vector3.ZERO, Vector3.RIGHT, 0.7, 0.05, 0.05, Color.BLACK)
	var top := Vector3(0.0, 0.68, 0.0)
	for s: float in [-1.0, 1.0]:
		var dir := Vector3(s, 0.35, 0.0).normalized()
		var tip: Vector3 = top + dir * 0.55
		var mid: Vector3 = top + dir * 0.28
		var side := Vector3(0.0, 0.0, 0.2)
		for v: Vector3 in [top, mid - side, tip, top, tip, mid + side]:
			st.set_color(Color.BLACK)
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()
