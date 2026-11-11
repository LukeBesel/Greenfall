class_name OldTownGround
extends Node3D
## Old Town's restored ground (CityOldTown builds one): what lies between the sidewalks and the
## buildings once the district is cleaned, in place of bare swept earth.
##   stage 3  clay paving round the buildings and over the open lots, thin new grass in the courts
##   stage 4  the paving washed, lawns thick with tufts, shrubs along the lawn edges
##   stage 5  flower borders in each block's own two colours round every lawn
## Each block inside its sidewalk ring is cut into CELLS x CELLS squares. A square under a building
## or in the lake is left out; one next to a building or on the block's rim is paved; the rest is
## lawn. Car parks stay paved with planted strips, the pump house's forecourt is all paving.
## Along the streets every tree stands in a grass verge cut into the sidewalk beside the kerb.
## Batched: one paving mesh and one lawn mesh for the town, and per block one MultiMesh each for
## tufts, shrubs and flowers (OldTownFlowers), hidden past PLANT_RANGE_M.

const CELLS: int = 16
const PAVE_Y: float = 0.05
const LAWN_Y: float = 0.065
const VERGE_Y: float = CityLayout.CURB_H + 0.02
const VERGE_HALF: Vector2 = Vector2(0.55, 2.3)  # across the sidewalk, along the street
const VERGE_IN: float = 0.2                     # the tree stands this far to the kerb side of its verge's middle
const PLANT_RANGE_M: float = 75.0
const TUFT_SHARE: float = 0.55
const SHRUB_EVERY: int = 4       # one shrub per this many lawn-edge squares
const FLOWERS_PER_EDGE: int = 3
const SHRUB_IDS: Array[String] = ["shrub_01", "shrub_02"]
const TUFT_ID: String = "grass_medium_01"
const PAVING_SHADER: String = "res://planets/verdance/sites/old_town_paving.gdshader"
const NONE: int = 0
const PAVE: int = 1
const LAWN: int = 2
## Lawn colour per stage (0-5): thin and yellow-green when new, deep and bright when kept.
const LAWN_TINT: Array[Color] = [Color.WHITE, Color.WHITE, Color.WHITE, Color(0.8, 0.82, 0.5), Color(0.6, 0.8, 0.42), Color(0.5, 0.8, 0.36)]

var stats: Dictionary = {}
var _paving: ShaderMaterial
var _lawn: StandardMaterial3D
var _stage3: Array[Node3D] = []
var _stage4: Array[Node3D] = []
var _stage5: Array[Node3D] = []


## Lays the ground of every block of `site` but its yard and the two kit lots beside it.
## `station_key` is the pump house's block; `solid` are footprints the lawn keeps off; `tree_spots`
## are the street trees (each gets a verge).
func build(site: VerdanceSite, station_key: Vector2i, solid: Array[Rect2], tree_spots: Array[Vector2] = []) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = site.seed_value + 5503
	var pave := SurfaceTool.new()
	pave.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lawn := SurfaceTool.new()
	lawn.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_pave: int = 0
	var n_lawn: int = 0
	var tuft: Array[Mesh] = PlantParts.variants(TUFT_ID, 160)
	var shrubs: Array[Mesh] = []
	for id: String in SHRUB_IDS:
		shrubs.append_array(PlantParts.variants(id, 420).slice(0, 1))
	var block_i: int = 0
	for key: Vector2i in site.layout.blocks:
		if key == Vector2i.ZERO or (key.x == 0 and absi(key.y) == 1):
			continue
		var b: Dictionary = site.layout.blocks[key]
		var kinds: PackedInt32Array = _plan_block(site, b, key == station_key, solid)
		var r: Rect2 = b["rect"]
		var step: Vector2 = r.size / float(CELLS)
		var tufts: Array[Transform3D] = []
		var bushes: Array[Transform3D] = []
		var blooms: Array[Transform3D] = []
		var bloom_cols: Array[Color] = []
		var edge_n: int = 0
		for j: int in CELLS:
			for i: int in CELLS:
				var k: int = kinds[j * CELLS + i]
				if k == NONE:
					continue
				var cell := Rect2(r.position + Vector2(i, j) * step, step)
				if k == PAVE:
					_quad(pave, cell, PAVE_Y, 1.0)
					n_pave += 1
					continue
				_quad(lawn, cell, LAWN_Y, 0.3)
				n_lawn += 1
				if rng.randf() < TUFT_SHARE:
					tufts.append(_plant_xf(rng, cell, 0.9, 1.5))
				if not _edge(kinds, i, j):
					continue
				edge_n += 1
				if edge_n % SHRUB_EVERY == 0:
					bushes.append(_plant_xf(rng, cell.grow(-0.3), 0.8, 1.25))
				for f: int in FLOWERS_PER_EDGE:
					blooms.append(_plant_xf(rng, cell, 0.8, 1.35))
					bloom_cols.append(OldTownFlowers.colour(block_i * 2 + (i + j + f) % 2 * 3, rng))
		var c: Vector2 = r.get_center()
		if not tuft.is_empty() and not tufts.is_empty():
			_stage4.append(_plants("Tufts%d" % block_i, tuft[0], tufts, c))
		if not shrubs.is_empty() and not bushes.is_empty():
			_stage4.append(_plants("Shrubs%d" % block_i, shrubs[block_i % shrubs.size()], bushes, c))
		if not blooms.is_empty():
			_stage5.append(_plants("Flowers%d" % block_i, OldTownFlowers.mesh(), blooms, c, bloom_cols, OldTownFlowers.material()))
		block_i += 1
	var n_verge: int = 0
	for p: Vector2 in tree_spots:
		var verge: Rect2 = verge_rect(p)
		if site._wet_share(verge, 0.5) > 0.0:
			continue
		_quad(lawn, verge, VERGE_Y, 0.3)
		n_verge += 1
	n_lawn += n_verge
	_paving = ShaderMaterial.new()
	_paving.shader = load(PAVING_SHADER)
	_lawn = AssetLib.pbr_material("leafy_grass", 1.0, Color.WHITE)
	if n_pave > 0:
		_stage3.append(_surface("Paving", pave, _paving))
	if n_lawn > 0:
		_stage3.append(_surface("Lawns", lawn, _lawn))
	stats = {"paved_cells": n_pave, "lawn_cells": n_lawn, "verges": n_verge, "plant_batches": _stage4.size() + _stage5.size()}


func set_stage(stage: int) -> void:
	var s: int = clampi(stage, 0, LAWN_TINT.size() - 1)
	for n: Node3D in _stage3:
		n.visible = s >= 3
	for n: Node3D in _stage4:
		n.visible = s >= 4
	for n: Node3D in _stage5:
		n.visible = s >= 5
	if _paving:
		_paving.set_shader_parameter("fresh", 0.0 if s <= 3 else 1.0)
	if _lawn:
		_lawn.albedo_color = LAWN_TINT[s]


## The grass verge of the street tree at `p`: a strip along the street it stands on, on the
## sidewalk beside the kerb. The street's direction comes from which side of its block the tree is.
static func verge_rect(p: Vector2) -> Rect2:
	var off: Vector2 = p - (p / CityLayout.PITCH).round() * CityLayout.PITCH
	var across: Vector2 = Vector2(signf(off.x), 0.0) if absf(off.x) > absf(off.y) else Vector2(0.0, signf(off.y))
	var half: Vector2 = Vector2(VERGE_HALF.x, VERGE_HALF.y) if across.x != 0.0 else Vector2(VERGE_HALF.y, VERGE_HALF.x)
	return Rect2(p - across * VERGE_IN - half, half * 2.0)


## What each square of a block is: NONE, PAVE or LAWN (row by row, CELLS x CELLS).
static func _plan_block(site: VerdanceSite, b: Dictionary, station: bool, solid: Array[Rect2]) -> PackedInt32Array:
	var r: Rect2 = b["rect"]
	var step: Vector2 = r.size / float(CELLS)
	var built := PackedByteArray()
	built.resize(CELLS * CELLS)
	var out := PackedInt32Array()
	out.resize(CELLS * CELLS)
	var foot: Array[Rect2] = []
	for bd: Dictionary in b["buildings"]:
		foot.append((bd["rect"] as Rect2).grow(0.15))
	for s: Rect2 in solid:
		if s.intersects(r):
			foot.append(s.grow(0.3))
	for j: int in CELLS:
		for i: int in CELLS:
			var c: Vector2 = r.position + (Vector2(i, j) + Vector2(0.5, 0.5)) * step
			for f: Rect2 in foot:
				if f.has_point(c):
					built[j * CELLS + i] = 1
					break
			if built[j * CELLS + i] == 0 and site._wet_share(Rect2(c - step * 0.5, step), step.x * 0.5) > 0.0:
				built[j * CELLS + i] = 2
	var parking: bool = int(b["type"]) == CityLayout.Block.PARKING
	for j: int in CELLS:
		for i: int in CELLS:
			var o: int = j * CELLS + i
			if built[o] != 0:
				out[o] = NONE
				continue
			var rim: bool = i == 0 or j == 0 or i == CELLS - 1 or j == CELLS - 1
			if station:
				out[o] = PAVE
			elif parking:  # a paved car park in a green frame, a planted strip between the rows
				var strip: bool = (j == CELLS / 2 - 1 or j == CELLS / 2) and absi(i * 2 - CELLS + 1) > 3
				out[o] = LAWN if rim or strip else PAVE
			else:
				var by_wall: bool = false
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = Vector2i(i, j) + d
					if q.x >= 0 and q.y >= 0 and q.x < CELLS and q.y < CELLS and built[q.y * CELLS + q.x] == 1:
						by_wall = true
				out[o] = PAVE if rim or by_wall else LAWN
	return out


## A lawn square with paving (or nothing) on one of its four sides: where the borders grow.
static func _edge(kinds: PackedInt32Array, i: int, j: int) -> bool:
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var q: Vector2i = Vector2i(i, j) + d
		if q.x < 0 or q.y < 0 or q.x >= CELLS or q.y >= CELLS or kinds[q.y * CELLS + q.x] != LAWN:
			return true
	return false


static func _quad(st: SurfaceTool, cell: Rect2, y: float, uv_scale: float) -> void:
	var pts: Array[Vector2] = [cell.position, Vector2(cell.end.x, cell.position.y), cell.end, Vector2(cell.position.x, cell.end.y)]
	for idx: int in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.UP)
		st.set_uv(pts[idx] * uv_scale)
		st.add_vertex(Vector3(pts[idx].x, y, pts[idx].y))


static func _plant_xf(rng: RandomNumberGenerator, cell: Rect2, s0: float, s1: float) -> Transform3D:
	var p: Vector2 = cell.position + Vector2(rng.randf(), rng.randf()) * cell.size
	return Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(s0, s1)), Vector3(p.x, LAWN_Y, p.y))


func _surface(nm: String, st: SurfaceTool, mat: Material) -> MeshInstance3D:
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("no_collide", true)
	add_child(mi)
	return mi


## One block's plants of one kind, placed about the block's middle so the range is measured there.
func _plants(nm: String, mesh: Mesh, xfs: Array[Transform3D], centre: Vector2, cols: Array[Color] = [], mat: Material = null) -> MultiMeshInstance3D:
	var at := Vector3(centre.x, 0.0, centre.y)
	var local: Array[Transform3D] = []
	for xf: Transform3D in xfs:
		local.append(Transform3D(xf.basis, xf.origin - at))
	var mi: MultiMeshInstance3D = CityKit.mmi_on(self, nm, mesh, local, cols, mat, false, PLANT_RANGE_M)
	mi.position = at
	mi.visibility_range_end_margin = 10.0
	return mi
