class_name CellVerdure
extends Node3D
## [v6life] Cleaned ground comes back to life on the globe (owner item 58: the part the player
## cleans has to feel wonderful). Every clean land cell has a "green" amount (SphereCells.green,
## the cells texture's R channel) that grows by itself over the next minutes and rises with the
## cell's hex level:
##   Clean -> patches of young grass creep in;  Planted -> most of the cell is grass;
##   Growing -> a closed sward;  Sustained / Thriving -> lush, with more flowers.
## The ground shader (planet/sphere/sphere_ground.gdshader) draws the grass where a soft noise
## mask is under the cell's green, so it spreads out from seed patches; mask() here is the same
## noise on the CPU, so the grass tufts and small flowers of this node stand exactly in the green
## patches and come up as the edge passes them. The far shell and the map read the same value
## (planet/sphere/sphere_shell.gd), so a cleaned district reads green from far away.
## Nothing is saved: green derives from the cell's state and level. On load a clean cell is fully
## grown; only cells cleaned or levelled in this session grow in.
## Tufts: two MultiMeshes round Lumi, a fixed block of instances per cell, built a few cells a
## frame under a time budget and touched again only when that cell's green changes.

## Green a cell grows to, per hex level 0..5 (a clean cell that HexLevels doesn't track counts as 1).
const TARGET: Array[float] = [0.0, 0.34, 0.52, 0.72, 0.86, 1.0]
## Green gained per second: a fresh clean cell takes about two minutes to reach its patches.
const GROW_PER_S: float = 1.0 / 340.0
const TICK_S: float = 0.5
## Grass tufts per cell and the rings of cells round Lumi that carry them, per quality preset.
const TUFTS: Array[int] = [44, 60, 80, 100]
const RINGS: Array[int] = [3, 4, 5, 5]
const FLOWER_SHARE: float = 0.14
const BUDGET_US: int = 1200
const MASK_F1: float = 0.11
const MASK_F2: float = 0.47

const SHADER: String = """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform float sway = 1.0;
varying vec3 petal;
varying float rnd;
varying float kind;
varying float hgt;
void vertex() {
	petal = COLOR.rgb;
	rnd = INSTANCE_CUSTOM.a;
	kind = UV.x;
	hgt = UV.y;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ph = dot(wp, vec3(0.37, 0.41, 0.33)) + rnd * 6.283;
	float s = sin(TIME * 1.3 + ph) * 0.05 + sin(TIME * 2.9 + ph * 1.7) * 0.015;
	VERTEX.x += s * hgt * hgt * sway;
	VERTEX.z += s * 0.6 * hgt * hgt * sway;
	NORMAL = mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.8);
}
void fragment() {
	vec3 g = mix(vec3(0.05, 0.16, 0.03), vec3(0.2, 0.4, 0.09), hgt);
	g *= mix(vec3(0.8, 0.9, 0.8), vec3(1.15, 1.1, 0.85), rnd);
	ALBEDO = mix(g, petal * 0.8, kind);
	ROUGHNESS = 1.0;
}
"""
const PETALS: Array[Color] = [Color(0.98, 0.96, 0.9), Color(1.0, 0.86, 0.3), Color(0.96, 0.62, 0.78), Color(0.66, 0.6, 0.95), Color(1.0, 0.6, 0.3)]

var cells: SphereCells
var grid: SphereGrid
var terrain: SphereTerrain
var world: Node  # the slice (garden, patch, orbit)
var instant: bool = false  # dev / tests: green jumps to its target
var hex_r: float = 5.8
var stats: Dictionary = {"growing": 0, "blocks": 0, "build_us_max": 0, "tufts": 0}

var _grow: Dictionary = {}  # cell -> current green 0..1 (still growing)
var _tick: float = 0.0
var _grass: MultiMesh
var _flowers: MultiMesh
var _per: int = 44  # grass instances per block
var _fper: int = 6  # flower instances per block
var _rings: int = 3
var _block: Dictionary = {}  # cell -> block index
var _free: Array[int] = []
var _cache: Dictionary = {}  # cell -> {xf: Array[Transform3D], m: PackedFloat32Array, rnd: PackedFloat32Array, slots: int}
var _todo: Dictionary = {}  # cell -> true: its block needs (re)writing
var _lumi_cell: int = -1
var _in_range: Dictionary = {}
var _site_of: Dictionary = {}


# --- The mask: the same value noise as the ground shader --------------------------------------

static func _vh(x: int, y: int, z: int) -> float:
	var h: int = (((x + 4096) * 73856093) & 0xFFFFFFFF) ^ (((y + 4096) * 19349663) & 0xFFFFFFFF) ^ (((z + 4096) * 83492791) & 0xFFFFFFFF)
	h ^= h >> 13
	h = (h * 1274126177) & 0xFFFFFFFF
	h ^= h >> 16
	return float(h & 0xFFFF) / 65535.0


static func vnoise(p: Vector3) -> float:
	var i: Vector3 = p.floor()
	var f: Vector3 = p - i
	f = f * f * (Vector3(3.0, 3.0, 3.0) - 2.0 * f)
	var x: int = int(i.x)
	var y: int = int(i.y)
	var z: int = int(i.z)
	var a: float = lerpf(lerpf(_vh(x, y, z), _vh(x + 1, y, z), f.x), lerpf(_vh(x, y + 1, z), _vh(x + 1, y + 1, z), f.x), f.y)
	var b: float = lerpf(lerpf(_vh(x, y, z + 1), _vh(x + 1, y, z + 1), f.x), lerpf(_vh(x, y + 1, z + 1), _vh(x + 1, y + 1, z + 1), f.x), f.y)
	return lerpf(a, b, f.z)


## 0..1 at a world point: grass stands where cover(green, mask) > 0.
static func mask(p: Vector3) -> float:
	return vnoise(p * MASK_F1) * 0.7 + vnoise(p * MASK_F2) * 0.3


## How far inside the grass a point is (<= 0: bare; about 0.1: the edge has passed).
static func cover(green: float, m: float) -> float:
	return green * 1.5 - 0.05 - m


## The green a cell grows to (0 for junk, water and hub ground).
static func target_of(state: int, level: int, flags: int) -> float:
	if state != 1 or (flags & SphereCells.F_HUB) != 0:
		return 0.0
	return TARGET[clampi(maxi(level, 1), 1, 5)]


# --- Growth ------------------------------------------------------------------------------------

func setup(p_world: Node, globe: OrbitPlanet) -> void:
	name = "CellVerdure"
	world = p_world
	cells = globe.cells
	grid = globe.grid
	terrain = globe.terrain
	hex_r = float(grid.hex_metrics().get("corner_m", 5.8)) * 0.92
	instant = DevHooks.has("life-grown")
	for s: Dictionary in globe.sites:
		for c: int in s["cells"]:
			_site_of[c] = int(s["index"])
	seed_all()
	cells.cell_changed.connect(_on_cell)
	cells.green_changed.connect(_on_green)
	EventBus.hex_cleaned.connect(_on_cleaned)
	_build_meshes()


## The hex-complete moment gets a second beat: after the gold sweep, a slow soft green ring breathes
## out over the cell (the ground is about to turn). Only near Lumi; far crews' cells stay quiet.
func _on_cleaned(hid: int, center: Vector3, _bonus: BigNum) -> void:
	var patch: Variant = world.get("patch") if world else null
	if instant or not (patch is Node3D) or (patch as Node3D).global_position.distance_to(center) > 40.0:
		return
	if hid < 0 or hid >= cells.n or cells.state[hid] == 5:
		return
	var r: float = hex_r
	get_tree().create_timer(0.55).timeout.connect(func() -> void:
		Vfx.ring(center, r * 1.05, Color(0.55, 0.95, 0.45, 0.6), 1.7))


## Every clean cell at its full green (a load, a fresh start): one pass over the clean cells.
func seed_all() -> int:
	var st: PackedByteArray = cells.state
	var n: int = 0
	var i: int = st.find(1)
	while i >= 0:
		var g: int = int(target_of(1, cells.level[i], cells.flags[i]) * 255.0 + 0.5)
		if g != cells.green[i]:
			cells.set_green(i, g)
			n += 1
		i = st.find(1, i + 1)
	return n


func _on_cell(i: int) -> void:
	var want: float = target_of(cells.state[i], cells.level[i], cells.flags[i])
	var have: float = float(cells.green[i]) / 255.0
	if want <= 0.0:
		if cells.green[i] != 0:
			cells.set_green(i, 0)
		_grow.erase(i)
		return
	if have + 0.002 >= want:
		return
	if instant:
		cells.set_green(i, int(want * 255.0 + 0.5))
	elif not _grow.has(i):
		_grow[i] = have


## Advances growing cells by dt seconds. Returns how many cells are still growing.
func step(dt: float) -> int:
	if _grow.is_empty():
		return 0
	var done: Array[int] = []
	for i: int in _grow:
		var want: float = target_of(cells.state[i], cells.level[i], cells.flags[i])
		var cur: float = minf(float(_grow[i]) + GROW_PER_S * dt, want)
		_grow[i] = cur
		var b: int = int(cur * 255.0 + 0.5)
		if cur >= want:
			cells.set_green(i, b)
			done.append(i)
		elif b - cells.green[i] >= 3:
			cells.set_green(i, b)
	for i: int in done:
		_grow.erase(i)
	stats["growing"] = _grow.size()
	return _grow.size()


func growing(i: int) -> bool:
	return _grow.has(i)


# --- Tufts and flowers --------------------------------------------------------------------------

static func tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for b: int in 12:
		var a: float = TAU * b / 12.0 + rng.randf_range(-0.4, 0.4)
		var out := Vector3(cos(a), 0.0, sin(a))
		_blade(st, out * rng.randf_range(0.0, 0.16), out, rng.randf_range(0.5, 1.0), rng.randf_range(0.022, 0.04), rng.randf_range(0.04, 0.3), 0.0)
	st.generate_normals()
	return st.commit()


static func flower_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	for f: int in 3:
		var a: float = TAU * f / 3.0 + rng.randf_range(-0.4, 0.4)
		var out := Vector3(cos(a), 0.0, sin(a))
		var base: Vector3 = out * rng.randf_range(0.04, 0.16)
		var h: float = rng.randf_range(0.7, 1.0)
		var lean: float = rng.randf_range(0.05, 0.18)
		_blade(st, base, out, h, 0.02, lean, 0.0)
		var top: Vector3 = base + out * lean + Vector3(0.0, h, 0.0)
		var r: float = rng.randf_range(0.24, 0.3)
		var tilt := Basis(out.cross(Vector3.UP).normalized(), -0.5)
		for k: int in 5:
			var pa: float = TAU * k / 5.0
			var c1: Vector3 = top + tilt * (Vector3(cos(pa - 0.5), 0.0, sin(pa - 0.5)) * r * 0.6)
			var c2: Vector3 = top + tilt * (Vector3(cos(pa), 0.06, sin(pa)) * r)
			var c3: Vector3 = top + tilt * (Vector3(cos(pa + 0.5), 0.0, sin(pa + 0.5)) * r * 0.6)
			for v: Vector3 in [top, c1, c2, top, c2, c3]:
				st.set_uv(Vector2(1.0, 1.0))
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## One blade: a quad and a tip. UV: x = petal (kind), y = height along the blade.
static func _blade(st: SurfaceTool, base: Vector3, out: Vector3, h: float, w: float, lean: float, kind: float) -> void:
	var side: Vector3 = out.cross(Vector3.UP).normalized()
	var ws: Array[float] = [1.0, 0.7, 0.0]
	var ts: Array[float] = [0.0, 0.5, 1.0]
	var pts: Array[Vector3] = []
	for t: float in ts:
		pts.append(base + out * lean * t * t + Vector3(0.0, h * t, 0.0))
	for i: int in 2:
		var a0: Vector3 = pts[i] - side * w * ws[i]
		var a1: Vector3 = pts[i] + side * w * ws[i]
		var b0: Vector3 = pts[i + 1] - side * w * ws[i + 1]
		var b1: Vector3 = pts[i + 1] + side * w * ws[i + 1]
		var quad: Array = [[a0, ts[i]], [b0, ts[i + 1]], [a1, ts[i]]] if i == 1 else [[a0, ts[i]], [b0, ts[i + 1]], [a1, ts[i]], [a1, ts[i]], [b0, ts[i + 1]], [b1, ts[i + 1]]]
		for e: Array in quad:
			st.set_uv(Vector2(kind, float(e[1])))
			st.add_vertex(e[0])


func _build_meshes() -> void:
	var q: int = clampi(Settings.quality, 0, 3)
	_per = TUFTS[q]
	_fper = maxi(2, int(round(_per * FLOWER_SHARE)))
	_rings = RINGS[q]
	var blocks: int = 1 + 3 * _rings * (_rings + 1) + 6
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	mat.shader = sh
	_grass = _mm("Tufts", tuft_mesh(), blocks * _per, mat)
	_flowers = _mm("Flowers", flower_mesh(), blocks * _fper, mat)
	for b: int in blocks:
		_free.append(blocks - 1 - b)


func _mm(nm: String, mesh: Mesh, count: int, mat: Material) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	var zero := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
	for i: int in count:
		mm.set_instance_transform(i, zero)
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var r: float = terrain.R + 200.0
	mi.custom_aabb = AABB(Vector3(-r, -r, -r), Vector3(r, r, r) * 2.0)
	mi.top_level = true
	add_child(mi)
	return mm


func _process(delta: float) -> void:
	_tick += delta
	if _tick >= TICK_S:
		step(_tick)
		_tick = 0.0
		_track()
	if not _todo.is_empty():
		_drain()


func _track() -> void:
	var patch: Variant = world.get("patch") if world else null
	if not (patch is Node3D) or not (patch as Node3D).is_inside_tree():
		return
	var c: int = grid.cell_at_from((patch as Node3D).global_position, _lumi_cell)
	if c == _lumi_cell:
		return
	_lumi_cell = c
	var now: Dictionary = {}
	for j: int in grid.cells_around(c, _rings):
		now[j] = true
		if not _in_range.has(j) and cells.green[j] > 0:
			_todo[j] = true
	for j: int in _in_range:
		if not now.has(j):
			_release(j)
	_in_range = now
	for j: int in _cache.keys():
		if not now.has(j):
			_cache.erase(j)


func _on_green(i: int) -> void:
	if _in_range.has(i):
		_todo[i] = true


func _release(c: int) -> void:
	_todo.erase(c)
	if not _block.has(c):
		return
	var b: int = _block[c]
	_block.erase(c)
	_free.append(b)
	var zero := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
	for k: int in _per:
		_grass.set_instance_transform(b * _per + k, zero)
	for k: int in _fper:
		_flowers.set_instance_transform(b * _fper + k, zero)
	stats["blocks"] = _block.size()


func _drain() -> void:
	var ht: int = Hitch.t()
	var t0: int = Time.get_ticks_usec()
	for c: int in _todo.keys():
		_todo.erase(c)
		_write_block(c)
		if Time.get_ticks_usec() - t0 > BUDGET_US:
			break
	stats["build_us_max"] = maxi(int(stats["build_us_max"]), Time.get_ticks_usec() - t0)
	stats["blocks"] = _block.size()
	Hitch.mark("verdure tufts", ht)


## Where tufts may stand in a cell: off a town's paving and lot plates, off the garden's mounds.
func _spot_ok(c: int, p: Vector3, towns: Array, slots: PackedInt32Array, garden: Garden) -> bool:
	for s: int in slots:
		if garden.slot_pos[s].distance_squared_to(p) < 0.8 * 0.8:
			return false
	if not cells.has_flag(c, SphereCells.F_SITE):
		return true
	for t: Array in towns:
		var vs: VerdanceSite = t[0]
		var loc: Vector3 = (t[1] as Transform3D) * p
		if Vector2(loc.x, loc.z).length() > vs.town_r + 2.0:
			continue
		if Garden.paved(vs.layout, loc.x, loc.z):
			return false
		var lots: Variant = vs.get("_lots")
		for lot: Dictionary in lots if lots is Array else []:
			var d: Vector2 = (Vector2(loc.x, loc.z) - (lot["c"] as Vector2)).abs()
			if maxf(d.x, d.y) < Garden.LOT_HALF + 0.3:
				return false
	return true


## The cell's tuft and flower spots (full-size transforms, mask and a random per spot).
func _make_cache(c: int) -> Dictionary:
	var garden: Garden = world.get("garden") as Garden if world else null
	var slots: PackedInt32Array = garden.hex_slots[c] if garden and garden.hex_slots.has(c) else PackedInt32Array()
	var towns: Array = garden._towns() if garden and cells.has_flag(c, SphereCells.F_SITE) else []
	var rng := RandomNumberGenerator.new()
	rng.seed = c * 7919 + 13
	var up: Vector3 = grid.centers[c]
	var f: Basis = SphereGrid.frame(up)
	var xf: Array[Transform3D] = []
	var ms := PackedFloat32Array()
	var rnd := PackedFloat32Array()
	var want: int = _per + _fper
	for attempt: int in want * 2:
		if xf.size() >= want:
			break
		var a: float = rng.randf() * TAU
		var r: float = sqrt(rng.randf()) * hex_r
		var d: Vector3 = (up + (f.x * cos(a) + f.z * sin(a)) * r / terrain.R).normalized()
		var yaw: float = rng.randf() * TAU
		var size: float = rng.randf_range(0.75, 1.25)
		var rr: float = rng.randf()
		if grid.walk(d, c) != c:
			continue
		var p: Vector3 = terrain.ground(d)
		if not _spot_ok(c, p, towns, slots, garden):
			continue
		var b: Basis = SphereGrid.frame(d).rotated(d, yaw).scaled(Vector3(size, size, size))
		xf.append(Transform3D(b, p - d * 0.03))
		ms.append(mask(p))
		rnd.append(rr)
	return {"xf": xf, "m": ms, "rnd": rnd, "slots": slots.size()}


func _write_block(c: int) -> void:
	var g: float = float(cells.green[c]) / 255.0
	if g <= 0.0 or not _in_range.has(c):
		_release(c)
		return
	var garden: Garden = world.get("garden") as Garden if world else null
	var n_slots: int = (garden.hex_slots[c] as PackedInt32Array).size() if garden and garden.hex_slots.has(c) else 0
	if not _cache.has(c) or int(_cache[c]["slots"]) != n_slots:
		_cache[c] = _make_cache(c)
	if not _block.has(c):
		if _free.is_empty():
			return
		_block[c] = _free.pop_back()
	var b: int = _block[c]
	var e: Dictionary = _cache[c]
	var xf: Array[Transform3D] = e["xf"]
	var ms: PackedFloat32Array = e["m"]
	var rnd: PackedFloat32Array = e["rnd"]
	var zero := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
	# The first _fper spots are flowers (they come up well behind the grass edge), the rest tufts.
	var shown: int = 0
	for k: int in _fper:
		var t: Transform3D = zero
		if k < xf.size():
			var s: float = smoothstep(0.22, 0.5, cover(g, ms[k]))
			if s > 0.0:
				var sc: float = (0.3 + 0.7 * s) * 0.38
				t = Transform3D(xf[k].basis * Basis.from_scale(Vector3(sc, sc, sc)), xf[k].origin)
				var pc: Color = PETALS[int(rnd[k] * 4.999)]
				_flowers.set_instance_color(b * _fper + k, pc)
				_flowers.set_instance_custom_data(b * _fper + k, Color(0.0, 0.0, 0.0, rnd[k]))
				shown += 1
		_flowers.set_instance_transform(b * _fper + k, t)
	for k: int in _per:
		var t: Transform3D = zero
		var j: int = _fper + k
		if j < xf.size():
			var s: float = smoothstep(0.0, 0.25, cover(g, ms[j]))
			if s > 0.0:
				var w: float = 0.7 + 0.5 * s
				var h: float = (0.14 + 0.2 * s) * (0.8 + 0.5 * g)
				t = Transform3D(xf[j].basis * Basis.from_scale(Vector3(w, h, w)), xf[j].origin)
				_grass.set_instance_custom_data(b * _per + k, Color(0.0, 0.0, 0.0, rnd[j]))
				shown += 1
		_grass.set_instance_transform(b * _per + k, t)
	stats["tufts"] = shown
