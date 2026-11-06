class_name LitterView
extends Node3D
## Dense ground-cover trash: crumpled paper, wrappers, plastic film, cardboard scraps, flattened
## cans and caps, covering every walkable surface of junk hexes. Purely visual but tied to hex
## state: Patch's scoop sweeps a clean swath through it, partial cleaning thins it, and a clean
## hex has none. Batched as MultiMeshes per (chunk, mesh) with per-instance colors.

const CHUNK: int = 4
const DENSITY: float = 30.0
const CELL: float = 1.0  # pieces per square meter on an ordinary junk hex

var field: HexField
var layout: CityLayout

var _mms: Array[MultiMesh] = []
## Per hex: Array of [mm_index, slot, x, z, threshold]
var _by_hex: Array = []
var _meshes: Array[Mesh] = []
var _rng := RandomNumberGenerator.new()
var _carpet_mat: StandardMaterial3D


func setup(p_field: HexField) -> void:
	field = p_field
	layout = field.layout
	_rng.seed = field.seed_value + 4242
	_build_meshes()
	_build()


static func _crumple(size: Vector2, segs: int, height: float, rng: RandomNumberGenerator, color: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array = []
	for j: int in segs + 1:
		var row: Array = []
		for i: int in segs + 1:
			var u: float = float(i) / segs - 0.5
			var v: float = float(j) / segs - 0.5
			var edge: float = 1.0 - maxf(absf(u), absf(v)) * 2.0
			row.append(Vector3(u * size.x * rng.randf_range(0.85, 1.1), rng.randf_range(0.0, height) * (0.3 + edge), v * size.y * rng.randf_range(0.85, 1.1)))
		pts.append(row)
	for j: int in segs:
		for i: int in segs:
			var a: Vector3 = pts[j][i]
			var b: Vector3 = pts[j][i + 1]
			var c: Vector3 = pts[j + 1][i + 1]
			var d: Vector3 = pts[j + 1][i]
			for p: Vector3 in [a, b, c, a, c, d]:
				st.set_color(color)
				st.add_vertex(p + Vector3(0, 0.01, 0))
	st.generate_normals()
	return st.commit()


func _build_meshes() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 77
	# Sheets / wrappers / film / cardboard scraps (vertex color white: tinted per instance).
	# [deck] Low preset: one fewer crumple segment and much lighter tiny items (this layer is
	# ~150k instances, the biggest triangle load in the game).
	var low: bool = Settings.quality == Settings.Quality.LOW
	var dseg: int = 1 if low else 0
	_meshes.append(_crumple(Vector2(0.3, 0.22), 3 - dseg, 0.05, r, Color.WHITE))
	_meshes.append(_crumple(Vector2(0.16, 0.12), 2 - dseg, 0.03, r, Color.WHITE))
	_meshes.append(_crumple(Vector2(0.45, 0.35), 4 - dseg, 0.07, r, Color.WHITE))
	_meshes.append(_crumple(Vector2(0.24, 0.24), 3 - dseg, 0.12, r, Color.WHITE))
	# Tiny real items at very low detail.
	for id: String in ["can_rusted", "bleach_bottle", "lubricant_spray", "garden_gloves_01", "drain_cleaner",
			"multi_cleaner_bottle", "russian_food_cans_01", "oil_tin", "circuit_board"]:
		_meshes.append(AssetLib.model_mesh_lite(id, [70, 140, 220, 220][clampi(Settings.quality, 0, 3)]))


## Real-world trash colours: mostly sun-faded paper, cardboard, grey film and black bags, with
## the occasional bright wrapper. Everything gets dusty toward the ground colour.
func _litter_color() -> Color:
	var palette: Array[Color] = [
		Color(0.84, 0.82, 0.74), Color(0.78, 0.74, 0.62), Color(0.6, 0.46, 0.31), Color(0.5, 0.39, 0.27),
		Color(0.7, 0.71, 0.7), Color(0.12, 0.12, 0.13), Color(0.32, 0.45, 0.62), Color(0.72, 0.24, 0.18),
		Color(0.86, 0.7, 0.22), Color(0.28, 0.5, 0.32), Color(0.92, 0.92, 0.9), Color(0.3, 0.6, 0.72),
	]
	var weights: Array[float] = [4, 3, 4, 3, 2.5, 2.5, 0.8, 0.8, 0.8, 0.5, 1.5, 0.5]
	var t: float = 0.0
	for w: float in weights:
		t += w
	var x: float = _rng.randf() * t
	var c: Color = palette[0]
	for i: int in palette.size():
		x -= weights[i]
		if x <= 0.0:
			c = palette[i]
			break
	# Fade, grime and dust.
	c = c.lerp(Color(c.get_luminance(), c.get_luminance(), c.get_luminance()), _rng.randf_range(0.1, 0.4))
	c = c.darkened(_rng.randf_range(0.05, 0.4))
	return c.lerp(Color(0.48, 0.43, 0.37), _rng.randf_range(0.0, 0.35))


func _build() -> void:
	_by_hex.resize(field.hex_count())
	for i: int in field.hex_count():
		_by_hex[i] = {}  # cell Vector2i -> Array of [mm, slot, x, z, threshold]
	var groups: Dictionary = {}  # "cx,cz|mesh" -> Array of [xf, color, hex, x, z, threshold]
	var area: float = 2.598 * field.hex_size * field.hex_size
	for id: int in field.hex_count():
		if field.hex_hub[id] != 0 or field.is_water(id):
			continue
		var c: Vector3 = field.hex_center(id)
		var btype: int = layout.block_type_at(c.x, c.z) if layout else 0
		var mult: float = 1.0
		if btype == CityLayout.Block.LANDFILL:
			mult = 2.2
		elif btype == CityLayout.Block.VACANT:
			mult = 0.8
		var n: int = int(area * DENSITY * mult)
		var a: Vector2i = field.hex_axial[id]
		for k: int in n:
			var p := Vector3(c.x + _rng.randf_range(-1, 1) * field.hex_size, 0, c.z + _rng.randf_range(-1, 1) * field.hex_size)
			if field.hex_at(p) != id:
				continue
			var surf: int = layout.surface_at(p.x, p.z) if layout else 0
			if surf == CityLayout.Surface.BUILDING or surf == CityLayout.Surface.YARD:
				continue
			if surf == CityLayout.Surface.ROAD and layout.curb_distance(p.x, p.z) > 1.5 and _rng.randf() < 0.45:
				continue
			# Layered carpet: later pieces sit on top of earlier ones so the ground disappears.
			var layer: float = float(k) / float(n)
			p.y = (layout.height_at(p.x, p.z) if layout else 0.0) + field.ground_height(id, p) * 0.9 + layer * 0.06 * mult
			var n_items: int = _meshes.size() - 4
			var mi: int = _rng.randi() % 4 if _rng.randf() < 0.72 else 4 + _rng.randi() % n_items
			var b := Basis(Vector3.UP, _rng.randf() * TAU)
			if mi >= 4:
				b = b * Basis(Vector3.RIGHT, PI * 0.5)  # small items lie on their side
			b = b * Basis(Vector3.FORWARD, _rng.randf_range(-0.2, 0.2))
			var scl: float = _rng.randf_range(0.7, 1.3) if mi < 4 else _rng.randf_range(0.8, 1.0)
			var xf := Transform3D(b.scaled(Vector3.ONE * scl), p + (Vector3(0, 0.05, 0) if mi >= 4 else Vector3.ZERO))
			var key: String = "%d,%d|%d" % [floori(float(a.x) / CHUNK), floori(float(a.y) / CHUNK), mi]
			if not groups.has(key):
				groups[key] = []
			var arr: Array = groups[key]
			arr.append([xf, _litter_color() if mi < 4 else Color.WHITE, id, p.x, p.z, _rng.randf()])
			groups[key] = arr
	for key: String in groups:
		var items: Array = groups[key]
		var mesh_i: int = int(key.split("|")[1])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = mesh_i < 4
		mm.mesh = _meshes[mesh_i]
		mm.instance_count = items.size()
		var mm_idx: int = _mms.size()
		for i: int in items.size():
			var it: Array = items[i]
			var hid: int = it[2]
			var visible: bool = field.hex_clean[hid] == 0 and float(it[5]) >= field.removed_fraction(hid) * 0.9
			mm.set_instance_transform(i, it[0] if visible else _hidden())
			if mm.use_colors:
				mm.set_instance_color(i, it[1])
			var cell := Vector2i(floori(float(it[3]) / CELL), floori(float(it[4]) / CELL))
			var bins: Dictionary = _by_hex[hid]
			var lst: Array = bins.get(cell, [])
			lst.append([mm_idx, i, it[3], it[4], it[5]])
			bins[cell] = lst
		_mms.append(mm)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# [deck] Tiny items (5-15 cm, ~1 px past this) stop drawing earlier than the paper carpet.
		mmi.visibility_range_end = (80.0 if Settings.quality == Settings.Quality.LOW else 120.0) if mm.use_colors \
			else (45.0 if Settings.quality == Settings.Quality.LOW else 75.0)
		mmi.visibility_range_end_margin = 8.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if mm.use_colors and _carpet_mat:
			mmi.material_override = _carpet_mat  # [deck] one shared material for every chunk
		elif mm.use_colors:
			var mat := StandardMaterial3D.new()
			_carpet_mat = mat
			mat.vertex_color_use_as_albedo = true
			mat.roughness = 0.85
			# Grime: a worn-concrete texture multiplied over the per-piece colour breaks up flat tints.
			mat.albedo_texture = AssetLib.tex("dirty_concrete", "diff")
			mat.albedo_color = Color(1.7, 1.7, 1.7)
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.normal_enabled = true
			mat.normal_texture = AssetLib.tex("rubble", "nor_gl")
			mat.normal_scale = 0.4
			mat.uv1_triplanar = true
			mat.uv1_scale = Vector3.ONE * 3.0
			mmi.material_override = mat
		add_child(mmi)


func _hidden() -> Transform3D:
	return Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0))


## Sweep litter within radius of a point (Patch's scoop). Returns how many pieces were swept.
func sweep(pos: Vector3, radius: float) -> int:
	var n: int = 0
	var r2: float = radius * radius
	var c0 := Vector2i(floori((pos.x - radius) / CELL), floori((pos.z - radius) / CELL))
	var c1 := Vector2i(floori((pos.x + radius) / CELL), floori((pos.z + radius) / CELL))
	var hexes: Dictionary = {}
	for o: Vector3 in [Vector3.ZERO, Vector3(radius, 0, 0), Vector3(-radius, 0, 0), Vector3(0, 0, radius), Vector3(0, 0, -radius)]:
		var h: int = field.hex_at(pos + o)
		if h >= 0:
			hexes[h] = true
	for hid: int in hexes:
		var bins: Dictionary = _by_hex[hid]
		for cx: int in range(c0.x, c1.x + 1):
			for cz: int in range(c0.y, c1.y + 1):
				var cell := Vector2i(cx, cz)
				if not bins.has(cell):
					continue
				var list: Array = bins[cell]
				for i: int in range(list.size() - 1, -1, -1):
					var it: Array = list[i]
					var dx: float = float(it[2]) - pos.x
					var dz: float = float(it[3]) - pos.z
					if dx * dx + dz * dz <= r2:
						_mms[it[0]].set_instance_transform(it[1], _hidden())
						list.remove_at(i)
						n += 1
	return n


## Thin litter as the hex gets cleaner; clear it completely when the hex flips.
func refresh_hex(hid: int) -> void:
	var bins: Dictionary = _by_hex[hid]
	var clean: bool = field.hex_clean[hid] == 1
	var rem: float = field.removed_fraction(hid)
	for cell: Vector2i in bins:
		var list: Array = bins[cell]
		for i: int in range(list.size() - 1, -1, -1):
			var it: Array = list[i]
			if clean or float(it[4]) < rem * 0.9:
				_mms[it[0]].set_instance_transform(it[1], _hidden())
				list.remove_at(i)
