class_name TownLife
extends Node
## [v6life] A town's streets wake up block by block as Lumi cleans and plants them (owner item 58:
## the part the player cleans has to feel wonderful). One TownLife lives in each Verdance town
## (VerdanceSite) on the globe. For every city block it watches the globe cells in and round it
## (the block and half of each street beside it) and derives, from the cells alone:
##   clean   share of the block's land cells that are clean: facades and awnings lose their grime
##           and get their colour back, continuously;
##   stage 1 SWEPT  most of the block is clean (CLEAN_1): the first few windows glow at dusk;
##   stage 2 AWAKE  the block is clean (CLEAN_2): its street lamps flicker on, more windows;
##   stage 3 ALIVE  the block is clean and somebody planted there (PLANTED cells at Planted or
##           better): neon and shop signs and string lights flicker on, shop windows are lit, and
##           most windows glow at dusk.
## Blocks with no cleanable ground of their own (all yard or buildings) follow their neighbours.
## The look is in art/shaders/building_city.gdshader, which reads one texel per block from
## `life_tex` (R lit-window share, G clean, B stage / 3); windows come on one by one because each
## has its own threshold. Lights go through StreetPower (planet/sites/site_power.gd asks
## lights_on()). Nothing is saved: it all derives from the cells' state and hex levels, so a
## loaded game shows what was earned, without the flicker.

signal stage_changed(key: Vector2i, stage: int)
## The first evaluation is in (a load, a town that streamed in): lights take their state at once.
signal settled

const CLEAN_1: float = 0.55
const CLEAN_2: float = 0.9
const PLANTED: int = 1
## Share of windows lit at dusk per stage.
const LIT: Array[float] = [0.0, 0.07, 0.22, 0.5]
const TEX_N: int = 16
const HALF: int = 8
## Seconds for a block's windows / colour to follow a change.
const EASE_S: float = 7.0
const LAMP_STAGE: int = 2
const SIGN_STAGE: int = 3
const BLOCKS_PER_FRAME: int = 3

var site: VerdanceSite
var grid: SphereGrid
var cells: SphereCells
var hub_index: int = 0
var manager: SiteManager
var active: bool = true  # this town drives the shared building material (the nearest one does)
var stats: Dictionary = {"blocks": 0, "stage1": 0, "stage2": 0, "stage3": 0, "clean": 0.0}

var _keys: Array[Vector2i] = []
var _cells_of: Dictionary = {}  # key -> PackedInt32Array (every cell under the block's square)
var _watch: Dictionary = {}  # cell -> true
var _stage: Dictionary = {}  # key -> int
var _want: Dictionary = {}  # key -> Vector3(lit, clean, stage / 3)
var _have: Dictionary = {}  # key -> Vector3 shown now
var _scan: int = 0  # blocks whose cells are mapped so far
var _dirty: bool = true
var _poll: float = 0.0
var _live: bool = false  # after the first evaluation: changes ease in and flicker
var _img: Image
var _tex: ImageTexture
var _night: float = 0.0
var _moving: bool = false
var _mean := Vector3.ZERO  # the town as a whole (its skyline past the pad follows this)


static func attach(vs: VerdanceSite, p_grid: SphereGrid, p_cells: SphereCells, hub_i: int, sm: SiteManager = null) -> TownLife:
	var old: Node = vs.get_node_or_null("TownLife")
	if old:
		old.free()
	if vs.layout == null or vs.layout.wild or DevHooks.has("life-off"):
		return null
	var tl := TownLife.new()
	tl.name = "TownLife"
	tl.site = vs
	tl.grid = p_grid
	tl.cells = p_cells
	tl.hub_index = hub_i
	tl.manager = sm
	vs.add_child(tl)
	return tl


func _ready() -> void:
	for key: Vector2i in site.layout.blocks:
		if absi(key.x) < HALF and absi(key.y) < HALF:
			_keys.append(key)
			_stage[key] = 0
			_want[key] = Vector3.ZERO
			_have[key] = Vector3.ZERO
	_img = Image.create(TEX_N, TEX_N, false, Image.FORMAT_RGBA8)
	_img.fill(Color(0, 0, 0, 1))
	_tex = ImageTexture.create_from_image(_img)
	cells.cell_changed.connect(_on_cell)
	stats["blocks"] = _keys.size()
	_push_material()


func _exit_tree() -> void:
	if cells and cells.cell_changed.is_connected(_on_cell):
		cells.cell_changed.disconnect(_on_cell)
	var m: ShaderMaterial = BuildingDetail.material()
	if m.get_shader_parameter("life_tex") == _tex:
		m.set_shader_parameter("life_on", 0.0)
		m.set_shader_parameter("life_tex", null)


func _on_cell(c: int) -> void:
	if _watch.has(c):
		_dirty = true


## The stage (0..3) of the block a site-local point lies in or beside.
func stage_at(local: Vector3) -> int:
	return int(_stage.get(site.layout.block_key_at(local.x, local.z), 0))


## StreetPower's question for a light group: is the block round this light awake enough?
## Street lamps come on with the block clean; signs and string lights when it is planted too.
func lights_on(g: Dictionary) -> bool:
	var at: Vector3 = g["at"]
	return stage_at(at) >= (SIGN_STAGE if g.has("node") else LAMP_STAGE)


## (lit-window share, clean share, stage) a block with these counts gets.
static func rate(land: int, clean: int, planted: int) -> Vector3i:
	# x: stage, y: clean share in 1/1000
	if land <= 0:
		return Vector3i(-1, 0, 0)
	var share: float = float(clean) / float(land)
	var st: int = 0
	if share >= CLEAN_2:
		st = 3 if planted >= PLANTED else 2
	elif share >= CLEAN_1:
		st = 1
	return Vector3i(st, int(share * 1000.0), planted)


func _map_block(key: Vector2i) -> void:
	var c := Vector2(key) * CityLayout.PITCH
	var half: float = CityLayout.PITCH * 0.5
	var xf: Transform3D = site.global_transform
	var seen: Dictionary = {}
	var hint: int = -1
	var x: float = -half + 1.5
	while x < half:
		var z: float = -half + 1.5
		while z < half:
			if Vector2(c.x + x, c.y + z).length() <= site.town_r + 6.0:
				hint = grid.cell_at_from(xf * Vector3(c.x + x, 0.0, c.y + z), hint)
				seen[hint] = true
			z += 3.0
		x += 3.0
	var list := PackedInt32Array()
	for i: int in seen:
		list.append(i)
		_watch[i] = true
	_cells_of[key] = list


## Re-derives every mapped block from its cells. Returns how many blocks changed stage.
func evaluate() -> int:
	var changed: int = 0
	var open: Array[Vector2i] = []
	var sum: Array[int] = [0, 0, 0, 0]
	var clean_sum: float = 0.0
	var rated: int = 0
	for key: Vector2i in _cells_of:
		var land: int = 0
		var clean: int = 0
		var planted: int = 0
		for i: int in _cells_of[key]:
			if cells.state[i] == 5 or (cells.flags[i] & SphereCells.F_HUB) != 0:
				continue
			land += 1
			if not cells.is_dirty(i) and cells.state[i] != 0:
				clean += 1
				if cells.level[i] >= 2:
					planted += 1
		var r: Vector3i = rate(land, clean, planted)
		if r.x < 0:
			open.append(key)
			continue
		rated += 1
		clean_sum += float(r.y) / 1000.0
		changed += _set_block(key, r.x, float(r.y) / 1000.0)
	for key: Vector2i in open:  # no ground of its own: as awake as the blocks beside it
		var best: int = 0
		var cl: float = 0.0
		var n: int = 0
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if _cells_of.has(key + d) and not (key + d) in open:
				best = maxi(best, int(_stage.get(key + d, 0)))
				cl += (_want[key + d] as Vector3).y
				n += 1
		changed += _set_block(key, best, cl / maxf(n, 1.0))
	for key: Vector2i in _stage:
		sum[int(_stage[key])] += 1
	stats["stage1"] = sum[1]
	stats["stage2"] = sum[2]
	stats["stage3"] = sum[3]
	stats["clean"] = snappedf(clean_sum / maxf(rated, 1.0), 0.01)
	if not _live:
		for key: Vector2i in _want:
			_have[key] = _want[key]
		_write_tex()
	return changed


func _set_block(key: Vector2i, st: int, clean: float) -> int:
	_want[key] = Vector3(LIT[st], clean, float(st) / 3.0)
	if int(_stage[key]) == st:
		return 0
	_stage[key] = st
	if _live:
		stage_changed.emit(key, st)
	return 1


func _write_tex() -> void:
	for key: Vector2i in _have:
		var v: Vector3 = _have[key]
		_img.set_pixel(key.x + HALF, key.y + HALF, Color(v.x, v.y, v.z, 1.0))
	_tex.update(_img)
	var sum := Vector3.ZERO
	for key: Vector2i in _have:
		sum += _have[key]
	_mean = sum / maxf(_have.size(), 1.0)


func _push_material() -> void:
	if not active:
		return
	var m: ShaderMaterial = BuildingDetail.material()
	m.set_shader_parameter("life_tex", _tex)
	m.set_shader_parameter("life_on", 1.0)
	m.set_shader_parameter("life_night", _night)
	# The skyline past the pad (TownOutskirts, its own copy of the material, no block map) wakes
	# with the town as a whole: a dark ring of towers until the streets below are clean.
	var om: ShaderMaterial = TownOutskirts.material()
	om.set_shader_parameter("life_on", 0.0)
	om.set_shader_parameter("life_flat", Vector3(_mean.x * 0.8, _mean.y, 0.0))
	om.set_shader_parameter("life_night", _night)


## How dark it is for the windows: they start to glow at dusk, before the street is black.
static func dusk(tod: float) -> float:
	return maxf(1.0 - smoothstep(0.2, 0.27, tod), smoothstep(0.71, 0.79, tod))


func _process(delta: float) -> void:
	if _scan < _keys.size():
		if not site.is_inside_tree():
			return
		for k: int in BLOCKS_PER_FRAME:
			if _scan < _keys.size():
				_map_block(_keys[_scan])
				_scan += 1
		if _scan < _keys.size():
			return
		_dirty = true
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.5
		if _dirty:
			_dirty = false
			if evaluate() > 0:
				_moving = true
			if not _live:
				_live = true
				settled.emit()
		if manager:
			active = manager.nearest == hub_index or manager.nearest < 0
		var w: Node = manager.globe.get_parent() if manager and manager.globe else get_tree().current_scene
		var sky: Variant = w.get("sky_director") if w else null
		_night = dusk(float((sky as Object).get("time_of_day"))) if sky is Object else 0.0
		_push_material()
		_moving = _moving or _lagging()
	if _moving:
		var k: float = clampf(delta / EASE_S, 0.0, 1.0)
		var still: bool = true
		for key: Vector2i in _have:
			var h: Vector3 = _have[key]
			var t: Vector3 = _want[key]
			if h.is_equal_approx(t):
				continue
			_have[key] = Vector3(move_toward(h.x, t.x, k * 0.5), move_toward(h.y, t.y, k), move_toward(h.z, t.z, k * 2.0))
			still = false
		_write_tex()
		_moving = not still


func _lagging() -> bool:
	for key: Vector2i in _have:
		if not (_have[key] as Vector3).is_equal_approx(_want[key]):
			return true
	return false
