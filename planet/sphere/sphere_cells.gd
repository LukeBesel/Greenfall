class_name SphereCells
extends RefCounted
## [sgrid] Per-hex state for a whole planet in packed arrays (a few bytes per hex, so 160k hexes
## cost ~1.5 MB), plus an RGBA8 state texture the ground and far-shell shaders read by cell id:
## R = junk left (0..1), G = state * 36 / 255, B = biome * 17 / 255, A = level << 4 | flags.
## Writes mark the texel dirty; flush() uploads once per frame at most.
##
## State values follow PlanetData.State (JUNK, CLEAN, PLANTED, GROWING, RESTORED, WATER).

const TEX_W: int = 512
const F_SITE: int = 1      # reserved by a hub site
const F_VISITED: int = 2   # Lumi has set foot here
const F_NEAR: int = 4      # inside the 3D junk ring (set by the streamer)
const F_HUB: int = 8       # [orbB] hub ground (the cleared yard of a site): not a junk hex, not counted

var n: int = 0
var junk := PackedFloat32Array()   # remaining junk 1 = untouched .. 0 = clean
var state := PackedByteArray()
var level := PackedByteArray()     # per-hex upgrade / restoration level (0..15)
var biome := PackedByteArray()
var flags := PackedByteArray()
## [v6life] How green a clean land cell is, 0..255 (plants/cell_verdure.gd grows it from the cell's
## state and level; never saved). It rides in the texture's R channel, which junk only uses on
## junk and water cells.
var green := PackedByteArray()
var image: Image
var texture: ImageTexture
var _dirty: bool = false
var _dirty_count: int = 0

signal cell_changed(cell: int)
signal green_changed(cell: int)  # [v6life] only the far shell and the verdure layer listen


func _init(p_count: int) -> void:
	n = p_count
	junk.resize(n)
	junk.fill(1.0)
	state.resize(n)
	level.resize(n)
	biome.resize(n)
	flags.resize(n)
	green.resize(n)  # [v6life]
	@warning_ignore("integer_division")
	var h: int = (n + TEX_W - 1) / TEX_W
	image = Image.create(TEX_W, h, false, Image.FORMAT_RGBA8)
	_write_all()  # [orbE] one buffer pass (per-pixel set_pixel over 655k cells was ~1 s each time)
	texture = ImageTexture.create_from_image(image)


## Copy a PlanetData's arrays (same grid level: ids match).
static func from_planet(p: PlanetData) -> SphereCells:
	var c := SphereCells.new(p.cell_count())
	c.junk = p.junk.duplicate()
	c.state = p.state.duplicate()
	c.biome = p.biome.duplicate()
	c.refresh_all()
	return c


func refresh_all() -> void:
	_write_all()  # [orbE]
	texture.update(image)
	_dirty = false


## [orbE] Every cell's pixel in one pass over a byte buffer (same encoding as _write).
func _write_all() -> void:
	var data := PackedByteArray()
	data.resize(image.get_width() * image.get_height() * 4)
	for i: int in n:
		var st: int = state[i]
		var o: int = i * 4
		data[o] = int(junk[i] * 255.0 + 0.5) if st == 0 or st == 5 else green[i]  # [v4world] lakes too: the far water's murk (sphere_ground.gdshader); [v6life] else how green
		data[o + 1] = st * 36
		data[o + 2] = biome[i] * 17
		data[o + 3] = (level[i] << 4) | (flags[i] & 15)
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data)


func _write(i: int) -> void:
	var r8: int = int(junk[i] * 255.0 + 0.5) if state[i] == 0 or state[i] == 5 else green[i]  # [v4world] lakes too; [v6life] else how green
	@warning_ignore("integer_division")
	image.set_pixel(i % TEX_W, i / TEX_W, Color8(r8, state[i] * 36, biome[i] * 17, (level[i] << 4) | (flags[i] & 15)))


func set_junk(i: int, left: float) -> void:
	junk[i] = clampf(left, 0.0, 1.0)
	if junk[i] <= 0.0 and state[i] == 0:
		state[i] = 1  # JUNK -> CLEAN
	_touch(i)


func set_state(i: int, st: int) -> void:
	state[i] = st
	_touch(i)


func set_level(i: int, lv: int) -> void:
	level[i] = clampi(lv, 0, 15)
	_touch(i)


## [v6life] Sets how green a clean cell is. Quiet: no cell_changed (junk views, litter and the
## level layers have nothing to do with it), only green_changed.
func set_green(i: int, g: int) -> void:
	g = clampi(g, 0, 255)
	if green[i] == g:
		return
	green[i] = g
	_write(i)
	_dirty = true
	green_changed.emit(i)


func set_flag(i: int, f: int, on: bool = true) -> void:
	flags[i] = (flags[i] | f) if on else (flags[i] & ~f)
	_touch(i)


func has_flag(i: int, f: int) -> bool:
	return (flags[i] & f) != 0


## [v2feel] THE "this cell is clean" rule (owner item 36): 95% cleared counts as clean and the
## rest sweeps away. Lumi, robots, offline, saves and loads all test junk left against this.
const CLEAN_LEFT: float = 0.05


static func clean_left(left: float) -> bool:
	return left <= CLEAN_LEFT


func is_dirty(i: int) -> bool:
	return state[i] == 0 and junk[i] > CLEAN_LEFT


func _touch(i: int) -> void:
	_write(i)
	_dirty = true
	_dirty_count += 1
	cell_changed.emit(i)


## Upload pending changes to the GPU. Returns the number of cell writes since the last flush.
func flush() -> int:
	var k: int = _dirty_count
	if _dirty:
		texture.update(image)
		_dirty = false
		_dirty_count = 0
	return k


func clean_fraction() -> float:
	var land: int = 0
	var done: int = 0
	for i: int in n:
		if state[i] == 5:
			continue
		land += 1
		if state[i] != 0:
			done += 1
	return float(done) / maxf(land, 1)


func to_dict() -> Dictionary:
	return {"n": n, "junk": Marshalls.raw_to_base64(junk.to_byte_array()), "state": Marshalls.raw_to_base64(state),
		"level": Marshalls.raw_to_base64(level), "flags": Marshalls.raw_to_base64(flags)}


func apply_dict(d: Dictionary) -> bool:
	if int(d.get("n", -1)) != n:
		return false
	var j: PackedFloat32Array = Marshalls.base64_to_raw(str(d.get("junk", ""))).to_float32_array()
	var s: PackedByteArray = Marshalls.base64_to_raw(str(d.get("state", "")))
	var l: PackedByteArray = Marshalls.base64_to_raw(str(d.get("level", "")))
	var f: PackedByteArray = Marshalls.base64_to_raw(str(d.get("flags", "")))
	if j.size() != n or s.size() != n or l.size() != n or f.size() != n:
		return false
	junk = j
	state = s
	level = l
	flags = f
	refresh_all()
	return true
