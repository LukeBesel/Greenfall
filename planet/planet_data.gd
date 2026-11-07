class_name PlanetData
extends RefCounted
## Whole-planet simulation state on the geodesic hex sphere (pure data, deterministic from seed).
## Per cell: elevation, water, biome, city id, junk amount (0..1 of the cell's original junk),
## state (junk / clean / planted / growing / restored). Compact packed arrays: saves as bytes.

enum State { JUNK, CLEAN, PLANTED, GROWING, RESTORED, WATER }

const BIOMES: Array[String] = ["rustlands", "sprawl", "neon_coast", "fungal_marsh", "dust_dunes", "frostcap", "old_capital", "lake",
	"dust_flats", "frozen_port", "sunken_city", "cradle_landing"]  # [biomes] late-game frontier biomes (planet/frontiers.gd)
## [biomes] Frontier districts (data/frontiers.json): one extra hub each, appended after the
## ordinary hubs so existing hub indices never move. kind id -> hub index.
const FRONTIER_KINDS: Array[String] = ["dust_flats", "frozen_port", "sunken_city", "cradle_returns"]
const FRONTIER_BIOMES: Array[String] = ["dust_flats", "frozen_port", "sunken_city", "cradle_landing"]

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
var frontier_hubs: Dictionary = {}  # [biomes] frontier kind id -> hub index
var base_hub_count: int = 0         # [biomes] hubs before the frontier ones
## [late] Cradle Mode worlds (systems/world_gen.gd): biome thresholds, water share, city count and
## city names. Empty = Verdance exactly as before.
var mix: Dictionary = {}
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
	water_fraction = float(mix.get("water_fraction", water_fraction))  # [late]
	city_count = int(mix.get("city_count", city_count))
	var frost_lat: float = float(mix.get("frost_lat", 0.78))
	var dust_m: float = float(mix.get("dust_m", -0.25))
	var dust_lat: float = float(mix.get("dust_lat", 0.55))
	var marsh_m: float = float(mix.get("marsh_m", 0.3))
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
		if lat > frost_lat:  # [late] thresholds from the world mix
			b = "frostcap"
		elif m < dust_m and lat < dust_lat:
			b = "dust_dunes"
		elif m > marsh_m:
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
	_place_frontiers()
	recount()


func _place_cities(count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 3
	cities.clear()
	var names: Array[String] = ["Old Town", "Harbor Row", "Millbrook", "Ironside", "Kettle Bay", "Ashgrove", "Northgate", "Lumen Pier",
		"Copperfield", "Stillwater", "Brakton", "Mossbank", "Redcliff", "Dunmere", "Glasswick", "Pellham",
		"Saltmarsh", "Ferrous", "Quarry End", "Lowmeadow", "Highreach", "Tinsley", "Graybridge", "Wrenfield"]
	if mix.get("city_names") is Array and not (mix["city_names"] as Array).is_empty():  # [late] another world's towns
		names.clear()
		for nm: Variant in mix["city_names"]:
			names.append(str(nm))
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
	if not mix.is_empty():  # [late] other worlds: the landing town is the driest one (a full district to work)
		_driest_city_first()
	for ci: int in cities.size():
		var cd: Dictionary = cities[ci]
		var b: int = BIOMES.find("old_capital") if cd["capital"] else BIOMES.find("sprawl")
		for cell: int in cells_within(int(cd["cell"]), int(cd["rings"])):
			if state[cell] == State.WATER:
				continue
			city[cell] = ci
			if b == BIOMES.find("old_capital") or biome[cell] != BIOMES.find("neon_coast"):
				biome[cell] = b


## [late] Moves the town with the least water within a district's reach to the front (hub 0);
## names stay in order, so the landing town keeps the first name.
func _driest_city_first() -> void:
	var best: int = 0
	var best_wet: int = 1 << 30
	for ci: int in cities.size():
		if bool(cities[ci]["capital"]):
			continue
		var wet: int = 0
		for c: int in cells_within(int(cities[ci]["cell"]), 6):
			if state[c] == State.WATER:
				wet += 1
		if wet < best_wet:
			best_wet = wet
			best = ci
	if best != 0:
		var a: Dictionary = cities[0]
		var b: Dictionary = cities[best]
		for k: String in ["cell", "rings"]:
			var tmp: Variant = a[k]
			a[k] = b[k]
			b[k] = tmp


func _place_hubs() -> void:
	# One hub per city plus a few wilderness sites; the first city's center is the Junkyard Hub.
	hubs.clear()
	for cd: Dictionary in cities:
		hubs.append(int(cd["cell"]))
	# Wilderness hub sites in each biome, away from cities.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 5
	var tries: int = 0
	while hubs.size() < cities.size() + 10 and tries < 5000:
		tries += 1
		var c: int = rng.randi_range(0, cell_count() - 1)
		if state[c] == State.WATER or city[c] >= 0:
			continue
		var ok: bool = true
		for h: int in hubs:
			if grid.centers[c].angle_to(grid.centers[h]) < 0.25:
				ok = false
				break
		if ok:
			hubs.append(c)


## [biomes] One remote hub per frontier kind, chosen to suit it: the Dust Flats in dry country,
## the Frozen Port near a pole, the Sunken City among lakes, the Cradle's launch city near the
## equator. Deterministic from the seed; the cells around each are painted with its biome.
func _place_frontiers() -> void:
	base_hub_count = hubs.size()
	frontier_hubs.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 11
	for k: int in FRONTIER_KINDS.size():
		var best: int = -1
		var best_score: float = -INF
		for t: int in 500:
			var c: int = rng.randi_range(0, cell_count() - 1)
			if state[c] == State.WATER or city[c] >= 0:
				continue
			var near: float = INF
			for h: int in hubs:
				near = minf(near, grid.centers[c].angle_to(grid.centers[h]))
			if near < 0.2:
				continue
			var lat: float = absf(asin(clampf(grid.centers[c].y, -1.0, 1.0))) / (PI * 0.5)
			var score: float = minf(near, 0.5) + rng.randf() * 0.1
			match FRONTIER_KINDS[k]:
				"dust_flats":
					score += 1.0 if biome[c] == BIOMES.find("dust_dunes") else 0.0
				"frozen_port":
					score += lat * 1.5
				"sunken_city":
					var wet: int = 0
					for n: int in cells_within(c, 2):
						if state[n] == State.WATER:
							wet += 1
					score += minf(wet, 8) * 0.15
				_:
					score += (1.0 - lat)
			if score > best_score:
				best_score = score
				best = c
		if best < 0:
			continue
		hubs.append(best)
		frontier_hubs[FRONTIER_KINDS[k]] = hubs.size() - 1
		for n: int in cells_within(best, 2):
			if state[n] != State.WATER:
				biome[n] = BIOMES.find(FRONTIER_BIOMES[k])


## [biomes] Frontier kind id of a hub ("" for ordinary bases).
func frontier_kind(hub_index: int) -> String:
	for k: String in frontier_hubs:
		if int(frontier_hubs[k]) == hub_index:
			return k
	return ""


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
