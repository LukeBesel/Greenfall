class_name SphereShell
extends RefCounted
## [orbit] The far shell as a map of big hexes: every cell of a coarse grid (level `level`,
## ~16 fine hexes at level 5 over level 7) is one flat-coloured hex polygon with a thin outline.
## Its colour is the aggregate of the fine hexes it covers (junk left, cleaned, greened, water,
## biome, city, hub site), kept in two small RGBA8 textures and refreshed as cells change, so
## the planet visibly changes from orbit as crews clean and plant.
##
## Texture A: R = junk left, G = cleaned, B = green (planted .45 / growing .75 / restored 1),
##            A = water. Shares of the hex (they sum to 1).
## Texture B: R = dominant land biome * 17, G = city share, B = hub-site share, A = visited share.

const TEX_W: int = 512
const GREEN_W: Array[float] = [0.0, 0.0, 0.45, 0.75, 1.0, 0.0]

var level: int = 5
var coarse: SphereGrid
var fine: SphereGrid
var cells: SphereCells
var terrain: SphereTerrain
## Optional: PlanetData.city (-1 = none) for the fine grid; without it, sprawl/old_capital
## biomes count as city.
var city := PackedInt32Array()
var drop: float = 3.0
## Normal exaggeration for relief shading (heights are a few metres on a ~2 km planet).
var relief: float = 3.5

var tex_a: ImageTexture
var tex_b: ImageTexture
var stats: Dictionary = {}

var _img_a: Image
var _img_b: Image
var _owner := PackedInt32Array()   # fine cell -> coarse cell
var _start := PackedInt32Array()   # CSR: fine cells of coarse c = _members[_start[c] .. _start[c + 1])
var _members := PackedInt32Array()
var _water := PackedFloat32Array() # coarse water share (for the mesh heights)
var _dirty: Dictionary = {}
var _dirty_t: float = 0.0


func _init(p_fine: SphereGrid, p_cells: SphereCells, p_terrain: SphereTerrain, p_level: int = 5,
		p_city := PackedInt32Array()) -> void:
	fine = p_fine
	city = p_city
	cells = p_cells
	terrain = p_terrain
	level = mini(p_level, fine.level)
	coarse = SphereGrid.cached(level)
	var t0: int = Time.get_ticks_msec()
	_map_cells()
	stats["map_ms"] = Time.get_ticks_msec() - t0
	var n: int = coarse.cell_count()
	@warning_ignore("integer_division")
	var h: int = (n + TEX_W - 1) / TEX_W
	_img_a = Image.create(TEX_W, h, false, Image.FORMAT_RGBA8)
	_img_b = Image.create(TEX_W, h, false, Image.FORMAT_RGBA8)
	_water.resize(n)
	for c: int in n:
		_aggregate(c)
	tex_a = ImageTexture.create_from_image(_img_a)
	tex_b = ImageTexture.create_from_image(_img_b)
	cells.cell_changed.connect(_on_cell_changed)


## Fine cell -> nearest coarse centre. Icosphere subdivision keeps vertex ids, so fine cell i
## for i < coarse count IS coarse cell i; the rest walk from a neighbour's owner.
func _map_cells() -> void:
	var nf: int = fine.cell_count()
	var nc: int = coarse.cell_count()
	_owner.resize(nf)
	var counts := PackedInt32Array()
	counts.resize(nc + 1)
	var hint: int = 0
	for i: int in nf:
		var o: int
		if i < nc:
			o = i
		else:
			o = coarse.walk(fine.centers[i], hint)
		_owner[i] = o
		hint = o
		counts[o + 1] += 1
	for c: int in nc:
		counts[c + 1] += counts[c]
	_start = counts.duplicate()
	_members.resize(nf)
	var fill: PackedInt32Array = counts.duplicate()
	for i: int in nf:
		var o: int = _owner[i]
		_members[fill[o]] = i
		fill[o] += 1


func owner_of(fine_cell: int) -> int:
	return _owner[fine_cell]


func _aggregate(c: int) -> void:
	var a: int = _start[c]
	var b: int = _start[c + 1]
	var cnt: float = maxf(b - a, 1)
	var junk_s: float = 0.0
	var clean_s: float = 0.0
	var green_s: float = 0.0
	var water_s: float = 0.0
	var city_s: float = 0.0
	var site_s: float = 0.0
	var seen_s: float = 0.0
	var votes: Dictionary = {}
	for k: int in range(a, b):
		var i: int = _members[k]
		var st: int = cells.state[i]
		if st == 5:
			water_s += 1.0
			continue
		var bi: int = cells.biome[i]
		votes[bi] = int(votes.get(bi, 0)) + 1
		if st == 0:
			var j: float = cells.junk[i]
			junk_s += j
			clean_s += 1.0 - j
		else:
			var g: float = GREEN_W[st]
			green_s += g
			clean_s += 1.0 - g
		var is_city: bool = (city[i] >= 0) if not city.is_empty() else (bi == 1 or bi == 6)
		if is_city:
			city_s += 1.0
		if cells.flags[i] & SphereCells.F_SITE:
			site_s += 1.0
		if cells.flags[i] & SphereCells.F_VISITED:
			seen_s += 1.0
	var best_b: int = 7  # lake when all water
	var best_n: int = -1
	for bi: int in votes:
		if int(votes[bi]) > best_n:
			best_n = int(votes[bi])
			best_b = bi
	_water[c] = water_s / cnt
	var x: int = c % TEX_W
	@warning_ignore("integer_division")
	var y: int = c / TEX_W
	_img_a.set_pixel(x, y, Color(junk_s / cnt, clean_s / cnt, green_s / cnt, water_s / cnt))
	_img_b.set_pixel(x, y, Color8(best_b * 17, int(city_s / cnt * 255.0 + 0.5), int(site_s / cnt * 255.0 + 0.5),
		int(seen_s / cnt * 255.0 + 0.5)))


func _on_cell_changed(i: int) -> void:
	_dirty[_owner[i]] = true


## Re-aggregate changed big hexes and upload, at most every `every` seconds. Returns how many.
func update(delta: float, every: float = 0.5) -> int:
	_dirty_t += delta
	if _dirty.is_empty() or _dirty_t < every:
		return 0
	_dirty_t = 0.0
	var k: int = _dirty.size()
	for c: int in _dirty:
		_aggregate(c)
	_dirty.clear()
	tex_a.update(_img_a)
	tex_b.update(_img_b)
	return k


## One fan per big hex: centre + corners. UV.x = 1 at the centre, 0 on the rim (outline);
## UV2.x = coarse cell id (flat per hex). Corner heights are shared by the 3 hexes that meet
## there, so the shell is watertight.
func build_mesh() -> ArrayMesh:
	var t0: int = Time.get_ticks_msec()
	var nc: int = coarse.cell_count()
	var ntri: int = coarse.tri_center.size()
	var R: float = terrain.R
	# Heights: centres and corners (corner = centroid of an icosphere triangle).
	var hc := PackedFloat32Array()
	hc.resize(nc)
	for c: int in nc:
		hc[c] = terrain.height(coarse.centers[c]) - terrain.water_drop * _water[c]
	var ht := PackedFloat32Array()
	ht.resize(ntri)
	for t: int in ntri:
		var a: int = coarse.tris[t * 3]
		var b: int = coarse.tris[t * 3 + 1]
		var d: int = coarse.tris[t * 3 + 2]
		var w: float = (_water[a] + _water[b] + _water[d]) / 3.0
		ht[t] = terrain.height(coarse.tri_center[t]) - terrain.water_drop * w
	# Smooth relief normals from exaggerated heights (shared keys: centres, then corners).
	var nrm_c := PackedVector3Array()
	nrm_c.resize(nc)
	var nrm_t := PackedVector3Array()
	nrm_t.resize(ntri)
	var ex: float = relief
	for c: int in nc:
		var k: int = coarse.nbr_count[c]
		var pc: Vector3 = coarse.centers[c] * (R + hc[c] * ex)
		for j: int in k:
			var t1: int = coarse.cell_tri[c * SphereGrid.MAX_N + j]
			var t2: int = coarse.cell_tri[c * SphereGrid.MAX_N + (j + 1) % k]
			var p1: Vector3 = coarse.tri_center[t1] * (R + ht[t1] * ex)
			var p2: Vector3 = coarse.tri_center[t2] * (R + ht[t2] * ex)
			var fn: Vector3 = (p1 - pc).cross(p2 - pc)
			if fn.dot(pc) < 0.0:
				fn = -fn
			nrm_c[c] += fn
			nrm_t[t1] += fn
			nrm_t[t2] += fn
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for c: int in nc:
		var k: int = coarse.nbr_count[c]
		var base: int = v.size()
		var cid := Vector2(float(c), 0.0)
		v.append(coarse.centers[c] * (R + hc[c] - drop))
		nr.append(nrm_c[c].normalized())
		uv.append(Vector2(1.0, 0.0))
		uv2.append(cid)
		for j: int in k:
			var t: int = coarse.cell_tri[c * SphereGrid.MAX_N + j]
			v.append(coarse.tri_center[t] * (R + ht[t] - drop))
			nr.append(nrm_t[t].normalized())
			uv.append(Vector2(0.0, 0.0))
			uv2.append(cid)
		for j: int in k:
			# Corners run CCW from outside; Godot's front faces are clockwise.
			idx.append(base)
			idx.append(base + 1 + (j + 1) % k)
			idx.append(base + 1 + j)
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nr
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	stats["mesh_ms"] = Time.get_ticks_msec() - t0
	stats["tris"] = idx.size() / 3
	return am


func make_material(ground: ShaderMaterial) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://planet/sphere/sphere_shell.gdshader")
	m.set_shader_parameter("shell_a", tex_a)
	m.set_shader_parameter("shell_b", tex_b)
	m.set_shader_parameter("shell_w", TEX_W)
	if ground:
		m.set_shader_parameter("tex_noise", ground.get_shader_parameter("tex_rubble"))
	return m
