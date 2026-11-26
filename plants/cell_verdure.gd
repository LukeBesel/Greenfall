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
## [art7] What stands on the green (the look only; green, its timing and the mask are as they were):
## the plants of the flora kit (plants/flora_kit.gd, art/models/flora), one MultiMesh per kit mesh
## and one shared material. A cell's spots are fixed by its id; what stands on a spot follows how
## far inside the green it is (cover): moss and pioneer weeds ahead of the grass edge, then grass
## clumps of mixed height, flowers in drifts (one or two kinds and colours per area), ferns in the
## damp hollows, bushes, saplings, young trees and grown ones. Small plants stand within `_rings`
## cells of Lumi (full blades within GRASS_NEAR, cards beyond); bushes and trees out to `_far`
## rings, low-detail past the near rings. Built a few cells a frame under a time budget and touched
## again only when that cell's green or its distance band changes.

## Green a cell grows to, per hex level 0..5 (a clean cell that HexLevels doesn't track counts as 1).
## These come from data/life.json "ground" (core/life_cfg.gd); the values here are the fallbacks.
static var TARGET: Array[float] = LifeCfg.floats("ground", "green_per_level", [0.0, 0.34, 0.52, 0.72, 0.86, 1.0], 6)
## Green gained per second: a fresh clean cell takes about two minutes to reach its patches.
static var GROW_PER_S: float = 1.0 / maxf(1.0, LifeCfg.num("ground", "grow_s", 340.0))
const TICK_S: float = 0.5
## Grass tufts per cell and the rings of cells round Lumi that carry them, per quality preset.
static var TUFTS: Array[int] = LifeCfg.ints("ground", "tufts_per_cell", [44, 60, 80, 100], 4)
static var RINGS: Array[int] = LifeCfg.ints("ground", "tuft_rings", [3, 4, 5, 5], 4)
static var FLOWER_SHARE: float = LifeCfg.num("ground", "flower_share", 0.14)
const BUDGET_US: int = 1200
const MASK_F1: float = 0.11
const MASK_F2: float = 0.47

static var PETALS: Array[Color] = LifeCfg.colors("ground", "petals", [Color(0.98, 0.96, 0.9), Color(1.0, 0.86, 0.3), Color(0.96, 0.62, 0.78), Color(0.66, 0.6, 0.95), Color(1.0, 0.6, 0.3)])


## Re-reads the values for the current planet (LifeCfg.use_planet).
static func configure() -> void:
	TARGET = LifeCfg.floats("ground", "green_per_level", TARGET, 6)
	GROW_PER_S = 1.0 / maxf(1.0, LifeCfg.num("ground", "grow_s", 1.0 / GROW_PER_S))
	TUFTS = LifeCfg.ints("ground", "tufts_per_cell", TUFTS, 4)
	RINGS = LifeCfg.ints("ground", "tuft_rings", RINGS, 4)
	FLOWER_SHARE = LifeCfg.num("ground", "flower_share", FLOWER_SHARE)
	PETALS = LifeCfg.colors("ground", "petals", PETALS)

var cells: SphereCells
var grid: SphereGrid
var terrain: SphereTerrain
var world: Node  # the slice (garden, patch, orbit)
var instant: bool = false  # dev / tests: green jumps to its target
var hex_r: float = 5.8
var stats: Dictionary = {"growing": 0, "blocks": 0, "build_us_max": 0, "tufts": 0}

var _grow: Dictionary = {}  # cell -> current green 0..1 (still growing)
var _tick: float = 0.0
var _per: int = 44  # grass spots per cell
var _fper: int = 6  # flower spots per cell
var _rings: int = 3  # small plants: rings of cells round Lumi
var _far: int = 10  # bushes and trees: rings of cells round Lumi
var _kinds: Array[Dictionary] = []  # per kit mesh: {name, mm, free: Array[int], top: int}
var _kind_of: Dictionary = {}  # kit mesh name -> index in _kinds
var _inst: Dictionary = {}  # cell -> {kind index: PackedInt32Array of instance slots}
var _cache: Dictionary = {}  # cell -> its spots (see _make_cache)
var _todo: Dictionary = {}  # cell -> true: its plants need (re)writing
var _lumi_cell: int = -1
var _zone: Dictionary = {}  # cell in range -> 0 (round Lumi), 1 (near), 2 (far: bushes and trees only)
var _site_of: Dictionary = {}
var _shown: Dictionary = {}  # cell -> small plants standing on it
var _dev_k: float = 1.0  # dev (--life-green=F): every target times F, to look at an early stage


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
	configure()
	world = p_world
	cells = globe.cells
	grid = globe.grid
	terrain = globe.terrain
	hex_r = float(grid.hex_metrics().get("corner_m", 5.8)) * 0.92
	instant = DevHooks.has("life-grown")
	_dev_k = clampf(DevHooks.get_f("life-green", 1.0), 0.0, 1.0)
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
		var g: int = int(target_of(1, cells.level[i], cells.flags[i]) * _dev_k * 255.0 + 0.5)
		if g != cells.green[i]:
			cells.set_green(i, g)
			n += 1
		i = st.find(1, i + 1)
	return n


func _on_cell(i: int) -> void:
	var want: float = target_of(cells.state[i], cells.level[i], cells.flags[i]) * _dev_k
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
		var want: float = target_of(cells.state[i], cells.level[i], cells.flags[i]) * _dev_k
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


# --- The plants ----------------------------------------------------------------------------------

## Spot classes (what a spot can carry).
enum { C_TREE, C_BUSH, C_FLOWER, C_MOSS, C_WEED, C_FERN, C_TALL, C_GRASS }
## Full blades within this many rings of Lumi; the far grass card beyond.
const GRASS_NEAR: int = 2
## Rings of cells that carry bushes and trees, per quality preset.
const FAR_RINGS: Array[int] = [9, 11, 13, 14]
const PIONEERS: int = 8  # moss, weeds and ferns per cell
## How far inside the green (cover) a spot must be for a sapling, a young tree and a grown one.
const TREE_AT: Array[float] = [0.55, 0.8, 1.05]
const YELLOW := Color(1.0, 0.82, 0.22)
const ZERO := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)


func _build_meshes() -> void:
	var q: int = clampi(Settings.quality, 0, 3)
	_per = TUFTS[q]
	_fper = maxi(2, int(round(_per * FLOWER_SHARE)))
	_rings = RINGS[q]
	_far = maxi(FAR_RINGS[q], _rings)
	var near: int = 1 + 3 * _rings * (_rings + 1) + 6
	var close: int = 1 + 3 * GRASS_NEAR * (GRASS_NEAR + 1) + 8
	var far: int = 1 + 3 * _far * (_far + 1) + 6
	var mat: ShaderMaterial = FloraKit.material()
	_kind("grass_a", close * _per, mat, false)
	_kind("grass_lod", near * _per, mat, false)
	@warning_ignore("integer_division")
	_kind("grass_b", near * (_per / 4 + 2), mat, false)
	for nm: String in ["moss", "weed", "fern"]:
		_kind(nm, near * PIONEERS, mat, false)
	for nm: String in FloraKit.FLOWERS:
		_kind(nm, near * _fper, mat, false)
	for nm: String in FloraKit.BUSHES:
		_kind(nm, far * 2, mat, true)
	for sp: int in FloraKit.TREES.size():
		for age: int in 3:
			_kind(FloraKit.tree(sp, age, false), (near + 12) * 2 if age > 0 else far * 2, mat, age > 0)
			if age > 0:
				_kind(FloraKit.tree(sp, age, true), far * 2, mat, true)


func _kind(nm: String, count: int, mat: Material, shadow: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true  # white, never changed: on the Compatibility renderer custom data alone reads as 1
	mm.use_custom_data = true
	mm.mesh = FloraKit.mesh(nm)
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var r: float = terrain.R + 200.0
	mi.custom_aabb = AABB(Vector3(-r, -r, -r), Vector3(r, r, r) * 2.0)
	mi.top_level = true
	add_child(mi)
	var free: Array[int] = []
	_kind_of[nm] = _kinds.size()
	_kinds.append({"name": nm, "mm": mm, "free": free, "top": 0, "cap": count})


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
	var around: PackedInt32Array = grid.cells_around(c, _far)  # ring by ring, the nearest first
	var n_close: int = 1 + 3 * GRASS_NEAR * (GRASS_NEAR + 1)
	var n_near: int = 1 + 3 * _rings * (_rings + 1)
	var now: Dictionary = {}
	for idx: int in around.size():
		var j: int = around[idx]
		var z: int = 0 if idx < n_close else (1 if idx < n_near else 2)
		now[j] = z
		if int(_zone.get(j, -1)) != z and cells.green[j] > 0:
			_todo[j] = true
	for j: int in _zone:
		if not now.has(j):
			_release(j)
	_zone = now
	for j: int in _cache.keys():
		if not now.has(j):
			_cache.erase(j)


func _on_green(i: int) -> void:
	if _zone.has(i):
		_todo[i] = true


## Takes a cell's plants down and frees their instance slots.
func _release(c: int) -> void:
	_todo.erase(c)
	_shown.erase(c)
	if not _inst.has(c):
		return
	var held: Dictionary = _inst[c]
	_inst.erase(c)
	for ki: int in held:
		_give_back(ki, held[ki], 0)
	stats["blocks"] = _inst.size()


## Slots [from..] of `slots` go back to the kind's free list, hidden.
func _give_back(ki: int, slots: PackedInt32Array, from: int) -> void:
	var k: Dictionary = _kinds[ki]
	var mm: MultiMesh = k["mm"]
	var free: Array[int] = k["free"]
	for i: int in range(from, slots.size()):
		mm.set_instance_transform(slots[i], ZERO)
		free.append(slots[i])


func _drain() -> void:
	var ht: int = Hitch.t()
	var t0: int = Time.get_ticks_usec()
	for c: int in _todo.keys():
		if not _write_block(c, t0 + BUDGET_US):
			break  # stays in _todo; its search goes on next frame
		_todo.erase(c)
		if Time.get_ticks_usec() - t0 > BUDGET_US:
			break
	stats["build_us_max"] = maxi(int(stats["build_us_max"]), Time.get_ticks_usec() - t0)
	stats["blocks"] = _inst.size()
	var total: int = 0
	for c: int in _shown:
		total += int(_shown[c])
	stats["tufts"] = total
	Hitch.mark("verdure tufts", ht)


## Where plants may stand in a cell: off a town's paving and lot plates, off the garden's mounds.
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


## The cell's spots: per spot its class, a full-size transform on the ground (local up from the
## spot's own direction: the world is a sphere), the mask there and a random. Classes come in a
## fixed order from one seeded generator (trees, bushes, then the small plants), so a far cell
## that only needed its trees grows the rest later and gets the same plants. The search is
## resumable: it stops at `deadline_us` (Time.get_ticks_usec) and goes on next frame, so a town
## cell (paving and lot checks per spot) never costs one frame more than the budget.
func _make_cache(c: int, small: bool, deadline_us: int = 0x7FFFFFFFFFFFFFFF) -> Dictionary:
	var garden: Garden = world.get("garden") as Garden if world else null
	var slots: PackedInt32Array = garden.hex_slots[c] if garden and garden.hex_slots.has(c) else PackedInt32Array()
	var e: Dictionary = _cache.get(c, {})
	if e.is_empty() or int(e["slots"]) != slots.size():
		var r0 := RandomNumberGenerator.new()
		r0.seed = c * 7919 + 13
		var x0: Array[Transform3D] = []
		var n_tree: int = (1 if r0.randf() < 0.62 else 0) + (1 if r0.randf() < 0.2 else 0)
		var n_bush: int = int(r0.randf() * 2.7)
		# three drift centres for the flowers of this cell (tangent metres from its middle)
		var d0 := PackedVector2Array()
		for k: int in 3:
			var da: float = r0.randf() * TAU
			d0.append(Vector2(cos(da), sin(da)) * sqrt(r0.randf()) * hex_r * 0.75)
		@warning_ignore("integer_division")
		var moss_n: int = PIONEERS * 3 / 8
		@warning_ignore("integer_division")
		var fern_n: int = PIONEERS / 4
		@warning_ignore("integer_division")
		var tall_n: int = _per / 5
		e = {"xf": x0, "m": PackedFloat32Array(), "rnd": PackedFloat32Array(), "cls": PackedByteArray(), "slots": slots.size(), "rng": r0,
			"plan": [[C_TREE, n_tree], [C_BUSH, n_bush], [C_FLOWER, _fper], [C_MOSS, moss_n], [C_WEED, PIONEERS - moss_n - fern_n], [C_FERN, fern_n], [C_TALL, tall_n], [C_GRASS, _per - tall_n]],
			"phase": 0, "made": 0, "attempt": 0, "drifts": d0, "done": false, "small": false}
	var in_town: bool = cells.has_flag(c, SphereCells.F_SITE)
	var towns: Array = garden._towns() if garden and in_town else []
	var rng: RandomNumberGenerator = e["rng"]
	var up: Vector3 = grid.centers[c]
	var f: Basis = SphereGrid.frame(up)
	var xf: Array[Transform3D] = e["xf"]
	var ms: PackedFloat32Array = e["m"]
	var rnd: PackedFloat32Array = e["rnd"]
	var cls: PackedByteArray = e["cls"]
	var plan: Array = e["plan"]
	var drifts: PackedVector2Array = e["drifts"]
	var last: int = plan.size() if small else 2
	var phase: int = e["phase"]
	var timed_out: bool = false
	while phase < last:
		var cl: int = plan[phase][0]
		var want: int = plan[phase][1]
		if int(e["made"]) >= want or int(e["attempt"]) >= want * 2 + 2:
			phase += 1
			e["made"] = 0
			e["attempt"] = 0
			continue
		if Time.get_ticks_usec() > deadline_us:
			timed_out = true
			break
		e["attempt"] = int(e["attempt"]) + 1
		var a: float = rng.randf() * TAU
		var r: float = sqrt(rng.randf()) * hex_r
		var yaw: float = rng.randf() * TAU
		var size: float = rng.randf_range(0.75, 1.25)
		var rr: float = rng.randf()
		var off := Vector2(cos(a), sin(a)) * r
		if cl == C_FLOWER:  # a drift: close round one of the cell's centres
			off = drifts[int(e["attempt"]) % drifts.size()] + Vector2(cos(a), sin(a)) * r * 0.26
		elif cl == C_TREE or cl == C_BUSH:
			off *= 0.8  # woody plants keep off the cell's rim (a restored cell's light seams run there)
		var d: Vector3 = (up + (f.x * off.x + f.z * off.y) / terrain.R).normalized()
		if grid.walk(d, c) != c:
			continue
		var p: Vector3 = terrain.ground(d)
		if not _spot_ok(c, p, towns, slots, garden):
			continue
		if cl == C_TREE and in_town:  # a trunk needs room: no paving or lot within 1.6 m either
			var fd: Basis = SphereGrid.frame(d)
			var clear: bool = true
			for k: int in 4:
				if not _spot_ok(c, p + (fd.x * cos(k * PI * 0.5) + fd.z * sin(k * PI * 0.5)) * 1.6, towns, slots, garden):
					clear = false
					break
			if not clear:
				continue
		var b: Basis = SphereGrid.frame(d).rotated(d, yaw).scaled(Vector3(size, size, size))
		xf.append(Transform3D(b, p - d * 0.03))
		ms.append(mask(p))
		rnd.append(rr)
		cls.append(cl)
		e["made"] = int(e["made"]) + 1
	e["phase"] = phase
	e["m"] = ms
	e["rnd"] = rnd
	e["cls"] = cls
	e["small"] = small and not timed_out
	e["done"] = not timed_out
	return e


## One or two kinds per area: a slow noise picks them, a spot now and then takes another.
static func _area_pick(p: Vector3, freq: float, salt: float, n: int, rr: float) -> int:
	var v: float = vnoise(p * freq + Vector3(salt, salt * 0.7, -salt))
	var i: int = int(clampf(v * 1.6 - 0.3, 0.0, 0.999) * n)
	return (i + 1 + int(rr * 97.0) % maxi(n - 1, 1)) % n if fmod(rr * 13.0, 1.0) < 0.14 else i


## Writes a cell's plants. Returns false when its spot search ran out of time (it goes on next frame).
func _write_block(c: int, deadline_us: int = 0x7FFFFFFFFFFFFFFF) -> bool:
	var g: float = float(cells.green[c]) / 255.0
	if g <= 0.0 or not _zone.has(c):
		_release(c)
		return true
	var zone: int = _zone[c]
	var small: bool = zone < 2
	var garden: Garden = world.get("garden") as Garden if world else null
	var n_slots: int = (garden.hex_slots[c] as PackedInt32Array).size() if garden and garden.hex_slots.has(c) else 0
	var e: Dictionary = _cache.get(c, {})
	if e.is_empty() or int(e["slots"]) != n_slots or not bool(e["done"]) or (small and not bool(e["small"])):
		e = _make_cache(c, small, deadline_us)
		_cache[c] = e
		if not bool(e["done"]):
			return false
	var xf: Array[Transform3D] = e["xf"]
	var ms: PackedFloat32Array = e["m"]
	var rnd: PackedFloat32Array = e["rnd"]
	var cls: PackedByteArray = e["cls"]
	var old: Dictionary = _inst.get(c, {})
	var used: Dictionary = {}  # kind -> slots taken this time
	var cursor: Dictionary = {}  # kind -> how many of the old slots are taken again
	var shown: int = 0
	var gg: float = 0.75 + 0.5 * g
	for j: int in xf.size():
		var cl: int = cls[j]
		if not small and cl > C_BUSH:
			break  # the small plants come after the woody ones
		var k: float = cover(g, ms[j])
		var rr: float = rnd[j]
		var t: Transform3D = xf[j]
		var o: Vector3 = t.origin
		var nm: String = ""
		var sc := Vector3.ONE
		var tint := Color.WHITE
		match cl:
			C_GRASS:
				var s: float = smoothstep(0.0, 0.25, k)
				if s <= 0.0:
					continue
				nm = "grass_a" if zone == 0 else "grass_lod"
				var w: float = (0.75 + 0.45 * s) * (0.8 + 0.5 * rr)
				sc = Vector3(w, (0.2 + 0.3 * s) * gg * (0.65 + 0.9 * rr * rr), w)
			C_TALL:
				var s: float = smoothstep(0.02, 0.3, k)
				if s <= 0.0:
					continue
				nm = "grass_b" if zone == 0 or rr < 0.6 else "grass_lod"
				var h: float = (0.35 + 0.45 * s) * gg * (0.8 + 0.4 * rr)
				sc = Vector3(0.7, h, 0.7) if nm == "grass_b" else Vector3(0.7, h * 0.75, 0.7)
			C_FLOWER:
				var s: float = smoothstep(0.22, 0.5, k)
				if s <= 0.0:
					continue
				var kind: int = _area_pick(o, 0.045, 3.1, FloraKit.FLOWERS.size(), rr)
				nm = FloraKit.FLOWERS[kind]
				tint = PETALS[(_area_pick(o, 0.06, 9.7, PETALS.size(), rr) + kind) % PETALS.size()]
				var fs: float = (0.3 + 0.7 * s) * (0.55 if kind != 3 else 0.8)
				sc = Vector3(fs, fs, fs)
			C_MOSS:
				var s: float = smoothstep(-0.45, -0.2, k) * smoothstep(0.0, 0.08, g)
				if s <= 0.0:
					continue
				nm = "moss"
				sc = Vector3.ONE * (0.5 + 0.8 * s)
			C_WEED:
				var s: float = smoothstep(-0.3, -0.05, k) * smoothstep(0.03, 0.12, g)
				if s <= 0.0:
					continue
				nm = "weed"
				tint = YELLOW
				var ws: float = (0.25 + 0.3 * s) * (1.0 - 0.3 * smoothstep(0.5, 0.9, k))
				sc = Vector3(ws, ws, ws)
			C_FERN:
				var s: float = smoothstep(0.05, 0.4, k)
				if s <= 0.0:
					continue
				nm = "fern"
				var fs: float = 0.35 + 0.45 * s
				sc = Vector3(fs, fs, fs)
			C_BUSH:
				var s: float = smoothstep(0.4, 0.75, k)
				if s <= 0.0:
					continue
				nm = FloraKit.BUSHES[_area_pick(o, 0.03, 5.3, FloraKit.BUSHES.size(), rr)]
				tint = PETALS[0].lerp(PETALS[2 % PETALS.size()], fmod(rr * 5.0, 1.0))
				var bs: float = 0.35 + 0.65 * s
				sc = Vector3(bs, bs, bs)
			C_TREE:
				if k < TREE_AT[0]:
					continue
				var age: int = 2 if k >= TREE_AT[2] else (1 if k >= TREE_AT[1] else 0)
				var into: float = clampf((k - TREE_AT[age]) / 0.25, 0.0, 1.0)
				nm = FloraKit.tree(_area_pick(o, 0.012, 1.7, FloraKit.TREES.size(), rr), age, zone > 0)
				tint = Color(1.0, 0.82, 0.9).lerp(Color(1.0, 0.97, 0.94), fmod(rr * 3.0, 1.0))
				var ts: float = [0.5, 0.62, 0.72][age] + [0.5, 0.38, 0.28][age] * into
				sc = Vector3(ts, ts, ts)
		var ki: int = _kind_of[nm]
		var kd: Dictionary = _kinds[ki]
		var slot: int = -1
		var had: PackedInt32Array = old.get(ki, PackedInt32Array())
		var cur: int = cursor.get(ki, 0)
		if cur < had.size():
			slot = had[cur]
			cursor[ki] = cur + 1
		else:
			var free: Array[int] = kd["free"]
			if not free.is_empty():
				slot = free.pop_back()
			elif int(kd["top"]) < int(kd["cap"]):
				slot = kd["top"]
				kd["top"] = slot + 1
				(kd["mm"] as MultiMesh).set_instance_color(slot, Color.WHITE)
				(kd["mm"] as MultiMesh).visible_instance_count = slot + 1
			else:
				continue
		var mine: PackedInt32Array = used.get(ki, PackedInt32Array())
		mine.append(slot)
		used[ki] = mine
		var mm: MultiMesh = kd["mm"]
		mm.set_instance_transform(slot, Transform3D(t.basis * Basis.from_scale(sc), o))
		mm.set_instance_custom_data(slot, Color(tint.r, tint.g, tint.b, rr))
		if cl > C_BUSH:
			shown += 1
	for ki: int in old:  # what the cell no longer needs
		_give_back(ki, old[ki], int(cursor.get(ki, 0)))
	if used.is_empty():
		_inst.erase(c)
	else:
		_inst[c] = used
	_shown[c] = shown
	return true
