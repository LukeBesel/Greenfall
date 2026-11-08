class_name OrbitGlobe
extends RefCounted
## [orbit] Prototype: the planet as one walkable sphere. Wraps the survey PlanetData (the 40k-hex
## Goldberg grid every planet already has) with metres, terrain height, surface frames, chunks and
## a per-cell state texture the ground shaders read. Pure data; OrbitWorld builds the views.
##
## Sizes (hex circumradius 10 m, as the flat districts): level 6 = 40,962 cells, R ~ 920 m,
## circumference ~ 5.8 km (about 21 min on foot at 4.6 m/s).

const STATE_W: int = 256
const CHUNK_LEVEL: int = 2  # 162 chunks of ~250 cells (~250 m across at level 6)

var planet: PlanetData
var grid: GeoSphere
var R: float = 920.0
var hex_size: float = 10.0
var noise := FastNoiseLite.new()
var height_amp: float = 1.1
var chunk_grid: GeoSphere
var cell_chunk := PackedInt32Array()
var chunk_cells: Array[PackedInt32Array] = []
var state_img: Image
var state_tex: ImageTexture
## Optional stand-in junk per cell (1 = untouched) when no PlanetData: mirrors planet.junk.
var _dirty_tex: bool = false


func _init(p_planet: PlanetData, p_hex_size: float = 10.0) -> void:
	planet = p_planet
	grid = planet.grid
	hex_size = p_hex_size
	R = planet.radius_m
	noise.seed = planet.seed_value + 77
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	noise.frequency = 1.0 / 55.0
	_build_chunks()
	_build_state()


# --- Geometry -------------------------------------------------------------------------

## Flattened site patches: {dir, flat_m, blend_m, h}. A hub prefab sits on a level pad that
## blends back into the sphere terrain (what planet env site prefabs would get).
var sites: Array[Dictionary] = []


func add_site(dir: Vector3, flat_m: float, blend_m: float, h: float = 0.0) -> void:
	sites.append({"dir": dir.normalized(), "flat": flat_m, "blend": blend_m, "h": h})


## Terrain height (m) above the base radius for a unit direction.
func height(dir: Vector3) -> float:
	var t: float = noise.get_noise_3dv(dir * R) * height_amp
	for s: Dictionary in sites:
		var d: float = (s["dir"] as Vector3).angle_to(dir) * R
		var fl: float = float(s["flat"])
		if d < fl + float(s["blend"]):
			var k: float = smoothstep(fl, fl + float(s["blend"]), d)
			t = lerpf(float(s["h"]), t, k)
	return t


## Ground point for a unit direction.
func ground(dir: Vector3) -> Vector3:
	return dir * (R + height(dir))


## Smooth surface normal (finite differences of the height field).
func ground_normal(dir: Vector3) -> Vector3:
	var f: Basis = frame(dir)
	var e: float = 1.5 / R
	var px: Vector3 = ground((dir + f.x * e).normalized())
	var pz: Vector3 = ground((dir + f.z * e).normalized())
	var p0: Vector3 = ground(dir)
	return (pz - p0).cross(px - p0).normalized()


## A right-handed surface frame: y = up (radial), x = east, z = south (like PlanetData.local_to_dir).
static func frame(dir: Vector3) -> Basis:
	var up: Vector3 = dir.normalized()
	var east: Vector3 = Vector3.UP.cross(up)
	if east.length() < 0.01:
		east = Vector3.RIGHT
	east = east.normalized()
	var south: Vector3 = east.cross(up).normalized()
	return Basis(east, up, south)


## Local tangent metres (x east, z south) around a cell -> world ground point.
func local_point(cell: int, x: float, z: float) -> Vector3:
	return ground(planet.local_to_dir(cell, x, z))


func cell_at(p: Vector3, hint: int = 0) -> int:
	return grid.nearest_from(p.normalized(), hint)


## Angular radius of one cell (centre to corner).
func cell_angle() -> float:
	return hex_size / R


# --- Chunks ---------------------------------------------------------------------------

func _build_chunks() -> void:
	chunk_grid = GeoSphere.cached(CHUNK_LEVEL)
	var n: int = grid.cell_count()
	cell_chunk.resize(n)
	chunk_cells.clear()
	for _c: int in chunk_grid.cell_count():
		chunk_cells.append(PackedInt32Array())
	var hint: int = 0
	for i: int in n:
		hint = chunk_grid.nearest_from(grid.centers[i], hint)
		cell_chunk[i] = hint
		chunk_cells[hint].append(i)


## Chunks whose centre is within `meters` (great-circle) of p.
func chunks_near(p: Vector3, meters: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var d: Vector3 = p.normalized()
	var lim: float = cos(meters / R)
	for c: int in chunk_grid.cell_count():
		if chunk_grid.centers[c].dot(d) > lim:
			out.append(c)
	return out


## Cells within `rings` neighbour steps of a cell (BFS on the hex graph).
func cells_around(cell: int, rings: int) -> PackedInt32Array:
	var out := PackedInt32Array([cell])
	var seen: Dictionary = {cell: true}
	var front := PackedInt32Array([cell])
	for _r: int in rings:
		var nxt := PackedInt32Array()
		for c: int in front:
			for j: int in grid.neighbors(c):
				if not seen.has(j):
					seen[j] = true
					nxt.append(j)
					out.append(j)
		front = nxt
	return out


# --- Per-cell state texture -------------------------------------------------------------
## R = junk left (0..1), G = state / 5, B = biome / 12, A = 1.

func _build_state() -> void:
	var n: int = grid.cell_count()
	@warning_ignore("integer_division")
	var h: int = (n + STATE_W - 1) / STATE_W
	state_img = Image.create(STATE_W, h, false, Image.FORMAT_RGBA8)
	for i: int in n:
		_write(i)
	state_tex = ImageTexture.create_from_image(state_img)


func _write(i: int) -> void:
	var junk: float = planet.junk[i] if planet.state[i] == PlanetData.State.JUNK else 0.0
	state_img.set_pixel(i % STATE_W, i / STATE_W, Color(junk, float(planet.state[i]) / 5.0, float(planet.biome[i]) / 12.0, 1.0))


func set_cell(i: int, junk_left: float, st: int = -1) -> void:
	planet.junk[i] = clampf(junk_left, 0.0, 1.0)
	if st >= 0:
		planet.state[i] = st
	elif planet.junk[i] <= 0.0 and planet.state[i] == PlanetData.State.JUNK:
		planet.state[i] = PlanetData.State.CLEAN
	_write(i)
	_dirty_tex = true


## Push pending state changes to the GPU (call once per frame at most).
func flush() -> void:
	if _dirty_tex:
		_dirty_tex = false
		state_tex.update(state_img)


func is_dirty(i: int) -> bool:
	return planet.state[i] == PlanetData.State.JUNK and planet.junk[i] > 0.02
