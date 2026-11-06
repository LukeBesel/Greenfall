class_name PlanetData
extends RefCounted
## Whole-planet simulation state on the geodesic hex sphere (pure data, deterministic from seed).
## Per cell: elevation, water, biome, city id, junk amount (0..1 of the cell's original junk),
## state (junk / clean / planted / growing / restored). Compact packed arrays: saves as bytes.

enum State { JUNK, CLEAN, PLANTED, GROWING, RESTORED, WATER }

const BIOMES: Array[String] = ["rustlands", "sprawl", "neon_coast", "fungal_marsh", "dust_dunes", "frostcap", "old_capital", "lake"]

var grid: GeoSphere
var seed_value: int
var radius_m: float
var elevation := PackedFloat32Array()
var biome := PackedByteArray()
var city := PackedInt32Array()      # -1 = none, else city index
var junk := PackedFloat32Array()    # remaining junk fraction (1 = untouched)
var state := PackedByteArray()
var cities: Array[Dictionary] = []  # {name, cell, rings, capital}
var hubs: Array[int] = []           # hub site cells (first = Junkyard Hub / start)
var _land: int = 0
var _done: int = 0


func _init(p_seed: int = 4471, level: int = 6, hex_radius_m: float = 10.0) -> void:
	seed_value = p_seed
	grid = GeoSphere.cached(level)
	var cell_area: float = 2.598 * hex_radius_m * hex_radius_m
	radius_m = sqrt(cell_area * grid.cell_count() / (4.0 * PI))


func cell_count() -> int:
	return grid.cell_count()


func generate(water_fraction: float = 0.25, city_count: int = 24) -> void:
	var n: int = cell_count()
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	noise.frequency = 1.1
	var moist := FastNoiseLite.new()
	moist.seed = seed_value + 9
	moist.frequency = 1.6
	elevation.resize(n)
	biome.resize(n)
	city.resize(n)
	junk.resize(n)
	state.resize(n)
	for i: int in n:
		elevation[i] = noise.get_noise_3dv(grid.centers[i] * 1.5)
		city[i] = -1
		junk[i] = 1.0
	# Sea level at the requested water percentile (lakes and inland seas, no huge oceans:
	# the noise keeps water broken into many bodies).
	var sorted: Array = Array(elevation)
	sorted.sort()
	var sea: float = float(sorted[int(n * water_fraction)])
	for i: int in n:
		var c: Vector3 = grid.centers[i]
		var lat: float = absf(asin(clampf(c.y, -1.0, 1.0))) / (PI * 0.5)
		var m: float = moist.get_noise_3dv(c * 2.0)
		if elevation[i] < sea:
			biome[i] = BIOMES.find("lake")
			state[i] = State.WATER
			continue
		state[i] = State.JUNK
		var b: String = "rustlands"
		if lat > 0.78:
			b = "frostcap"
		elif m < -0.25 and lat < 0.55:
			b = "dust_dunes"
		elif m > 0.3:
			b = "fungal_marsh"
		biome[i] = BIOMES.find(b)
	# Coasts become boardwalk/beach biome.
	for i: int in n:
		if state[i] == State.WATER:
			continue
		for j: int in grid.neighbors(i):
			if state[j] == State.WATER and biome[i] == BIOMES.find("rustlands"):
				biome[i] = BIOMES.find("neon_coast")
				break
	_place_cities(city_count)
	_place_hubs()
	recount()


func _place_cities(count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 3
	cities.clear()
	var names: Array[String] = ["Old Town", "Harbor Row", "Millbrook", "Ironside", "Kettle Bay", "Ashgrove", "Northgate", "Lumen Pier",
		"Copperfield", "Stillwater", "Brakton", "Mossbank", "Redcliff", "Dunmere", "Glasswick", "Pellham",
		"Saltmarsh", "Ferrous", "Quarry End", "Lowmeadow", "Highreach", "Tinsley", "Graybridge", "Wrenfield"]
	var tries: int = 0
	while cities.size() < count and tries < 20000:
		tries += 1
		var c: int = rng.randi_range(0, cell_count() - 1)
		if state[c] == State.WATER:
			continue
		var ok: bool = true
		for other: Dictionary in cities:
			if grid.centers[c].angle_to(grid.centers[int(other["cell"])]) < 0.32:
				ok = false
				break
		if not ok:
			continue
		var capital: bool = cities.size() == count - 1
		var rings: int = 14 if capital else rng.randi_range(5, 9)
		cities.append({"name": "Old Capital" if capital else names[cities.size() % names.size()], "cell": c, "rings": rings, "capital": capital})
	for ci: int in cities.size():
		var cd: Dictionary = cities[ci]
		var b: int = BIOMES.find("old_capital") if cd["capital"] else BIOMES.find("sprawl")
		for cell: int in cells_within(int(cd["cell"]), int(cd["rings"])):
			if state[cell] == State.WATER:
				continue
			city[cell] = ci
			if b == BIOMES.find("old_capital") or biome[cell] != BIOMES.find("neon_coast"):
				biome[cell] = b


func _place_hubs() -> void:
	# One hub per city plus a few wilderness sites; the first city's center is the Junkyard Hub.
	hubs.clear()
	for cd: Dictionary in cities:
		hubs.append(int(cd["cell"]))


## Cells within `rings` steps of a cell (breadth-first).
func cells_within(center: int, rings: int) -> Array[int]:
	var seen: Dictionary = {center: 0}
	var frontier: Array[int] = [center]
	for r: int in rings:
		var next: Array[int] = []
		for c: int in frontier:
			for j: int in grid.neighbors(c):
				if not seen.has(j):
					seen[j] = r + 1
					next.append(j)
		frontier = next
	var out: Array[int] = []
	for k: int in seen:
		out.append(k)
	return out


func land_count() -> int:
	var n: int = 0
	for i: int in cell_count():
		if state[i] != State.WATER:
			n += 1
	return n


func recount() -> void:
	_land = 0
	_done = 0
	for i: int in cell_count():
		if state[i] == State.WATER:
			continue
		_land += 1
		if state[i] >= State.CLEAN:
			_done += 1


func restored_fraction() -> float:
	return float(_done) / maxf(_land, 1)


func restored_count() -> int:
	return _done


func set_junk(i: int, remaining: float) -> void:
	junk[i] = clampf(remaining, 0.0, 1.0)


func mark_clean(i: int) -> void:
	if state[i] == State.JUNK:
		state[i] = State.CLEAN
		junk[i] = 0.0
		_done += 1


## Local tangent-plane meters (x east, z south) around an anchor cell -> unit direction.
## Azimuthal-equidistant (exponential) map: distances from the anchor are preserved.
func local_to_dir(anchor: int, x: float, z: float) -> Vector3:
	var up: Vector3 = grid.centers[anchor]
	var east: Vector3 = Vector3.UP.cross(up).normalized()
	if east.length() < 0.01:
		east = Vector3.RIGHT
	var south: Vector3 = up.cross(east).normalized() * -1.0
	var d: float = sqrt(x * x + z * z)
	if d < 0.0001:
		return up
	var a: float = d / radius_m
	var t: Vector3 = (east * x + south * z) / d
	return (up * cos(a) + t * sin(a)).normalized()


## World position (meters, planet centered at origin) of a cell center.
func cell_world(i: int) -> Vector3:
	return grid.centers[i] * radius_m


func to_dict() -> Dictionary:
	return {"seed": seed_value, "level": grid.level,
		"junk": Marshalls.raw_to_base64(junk.to_byte_array()),
		"state": Marshalls.raw_to_base64(state)}


func apply_dict(d: Dictionary) -> bool:
	if int(d.get("seed", -1)) != seed_value or int(d.get("level", -1)) != grid.level:
		return false
	var j: PackedFloat32Array = Marshalls.base64_to_raw(str(d.get("junk", ""))).to_float32_array()
	var s: PackedByteArray = Marshalls.base64_to_raw(str(d.get("state", "")))
	if j.size() != cell_count() or s.size() != cell_count():
		return false
	junk = j
	state = s
	recount()
	return true
