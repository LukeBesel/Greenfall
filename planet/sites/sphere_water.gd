class_name SphereWater
extends Node3D
## [orbD] Lake surfaces on the walkable globe: a hex of water over every water cell in the
## streamer's near ring (the ground there sits SphereTerrain.water_drop low, its bed), built from
## the grid's shared corners so neighbouring water cells meet without seams, a little below the
## land. murky -> clear as the cell is cleaned (sphere_water.gdshader, the flat lakes' look).
## Freed when a cell leaves the ring; the far shell shows lakes from afar.
## As on the flat (water/water_view.gd): fish jump in clear lake cells (a few per cell, each
## jumping now and then with a splash), and cleaning a lake cell Lumi can see plays the lake-clear
## moment (chime, whoosh, a little shake, Wren's line) and stocks it.

const BELOW_LAND: float = 0.25  # [v1world] was 0.12: the chunk bank (sphere_chunk_job._wetness) crosses this inside the cell
const FISH_PER_CELL: int = 3
const FISH_SPREAD: float = 5.0  # jump starts within this far of the cell centre (10 m cells)

var grid: SphereGrid
var terrain: SphereTerrain
var cells: SphereCells
var _mat: ShaderMaterial
var _cell: Dictionary = {}  # cell -> MeshInstance3D
var world: Node  # the slice (its wren speaks the lake line)
var _fish: Array[Dictionary] = []  # {node, cell, lake, speed, phase, a, b, splashed}; a/b in the lake's frame
var _fish_mesh: Mesh
var _fish_mat: StandardMaterial3D


func setup_globe(g: Node) -> void:
	grid = g.get("grid")
	terrain = g.get("terrain")
	cells = g.get("cells")
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://planet/sites/sphere_water.gdshader")
	globe_ref = g  # [v4world] its streamer's ground materials get the sky too (far water)
	var st: SphereStreamer = g.get("streamer")
	if st:
		st.near_changed.connect(_on_near)
		var near: Array[int] = []
		for c: int in cells.n:
			if cells.has_flag(c, SphereCells.F_NEAR):
				near.append(c)
		_on_near(PackedInt32Array(near), PackedInt32Array())
	cells.cell_changed.connect(func(c: int) -> void:
		if _cell.has(c):
			_tint(c))
	EventBus.hex_cleaned.connect(_on_clean)


func _on_near(added: PackedInt32Array, removed: PackedInt32Array) -> void:
	for c: int in removed:
		if _cell.has(c):
			(_cell[c] as Node).queue_free()
			_cell.erase(c)
			_fish = _fish.filter(func(f: Dictionary) -> bool: return int(f["cell"]) != c)
	var h: int = Hitch.t()
	for c: int in added:
		if cells.state[c] == 5 and not _cell.has(c):
			_build(c)
	Hitch.mark("water cells", h)


func _build(c: int) -> void:
	var dir: Vector3 = grid.centers[c]
	var f: Basis = SphereGrid.frame(dir)
	var origin: Vector3 = dir * (terrain.R + terrain.height(dir) - BELOW_LAND)
	var xf := Transform3D(f, origin)
	var inv: Transform3D = xf.affine_inverse()
	var corners: PackedVector3Array = grid.corners(c)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# [v4world] A fan over the corners and the edge midpoints, each vertex carrying how close the
	# shore is (COLOR.r, 1 at the waterline) and how deep the lake is there (COLOR.g); both come
	# from the point alone, so neighbouring cells agree on their shared vertices.
	var rim: Array[Vector3] = []
	for k: int in corners.size():
		var a0: Vector3 = corners[k].normalized()
		var b0: Vector3 = corners[(k + 1) % corners.size()].normalized()
		rim.append(a0)
		rim.append((a0 + b0).normalized())
	var ctr: Vector3 = inv * origin
	var pts: Array[Vector3] = []
	var cols: Array[Color] = []
	for d: Vector3 in rim:
		pts.append(inv * (d * (terrain.R + terrain.height(d) - BELOW_LAND)))
		cols.append(_shore_col(d))
	var c_col: Color = _shore_col(dir)
	for k: int in pts.size():
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[(k + 1) % pts.size()]
		var ca: Color = cols[k]
		var cb: Color = cols[(k + 1) % pts.size()]
		# Clockwise seen from above (Godot's front face): the surface was wound the other way and
		# culled from above, so only the lake bed showed (the "flat slab" of owner playtest 3 #53).
		var tri: Array = [[ctr, c_col], [a, ca], [b, cb]] if (b - ctr).cross(a - ctr).dot(Vector3.UP) > 0.0 else [[ctr, c_col], [b, cb], [a, ca]]
		for e: Array in tri:
			st.set_normal(Vector3.UP)
			st.set_color(e[1])
			st.add_vertex(e[0])
	var mi := MeshInstance3D.new()
	mi.name = "Lake%d" % c
	mi.mesh = st.commit()
	mi.material_override = _mat
	if DevHooks.has("lake-debug"):  # [v4world] dev: lake surfaces in flat red (which surface is which)
		var dm := StandardMaterial3D.new()
		dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dm.albedo_color = Color.RED
		mi.material_override = dm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = xf
	add_child(mi)
	_cell[c] = mi
	_tint(c)
	if _clear(c):
		_stock_fish(c)


## [v4world] Shore and depth at a ground direction: r = 1 at the waterline fading out ~4 m onto
## the water, g = 0 at the bank to 1 about SHORE_DEEP_M out (the deep middle of a lake).
const SHORE_DEEP_M: float = 22.0
var _shore_cache: Dictionary = {}


func _shore_col(d: Vector3) -> Color:
	var key := Vector3i(roundi(d.x * 1.0e5), roundi(d.y * 1.0e5), roundi(d.z * 1.0e5))
	var hit: Variant = _shore_cache.get(key)
	if hit != null:
		return hit
	var land_m: float = SHORE_DEEP_M + 10.0
	for o: int in grid.cells_within(d, SHORE_DEEP_M + 10.0):
		if cells.state[o] == 5:
			continue
		# Distance to that land cell's edge, about its centre distance less its inradius.
		land_m = minf(land_m, grid.centers[o].angle_to(d) * terrain.R - _inradius())
	land_m = maxf(land_m, 0.0)
	var col := Color(1.0 - smoothstep(0.0, 4.5, land_m), smoothstep(1.5, SHORE_DEEP_M, land_m), 0.0, 1.0)
	if _shore_cache.size() > 20000:
		_shore_cache.clear()
	_shore_cache[key] = col
	return col


var _inr: float = -1.0


func _inradius() -> float:
	if _inr < 0.0:
		var c0: int = mini(1000, grid.cell_count() - 1)  # not one of the 12 pentagons
		var cs: PackedVector3Array = grid.corners(c0)
		var m0: Vector3 = ((cs[0].normalized() + cs[1].normalized()) * 0.5)
		_inr = m0.normalized().angle_to(grid.centers[c0]) * terrain.R
	return _inr


## [v4world] The sky the water mirrors, from the sky material (zenith, horizon, day, the sun),
## for this lake surface and the ground shader's far water, a few times a second.
var _sky_t: float = 0.0


func _sky_tick(delta: float) -> void:
	_sky_t -= delta
	if _sky_t > 0.0:
		return
	_sky_t = 0.2
	sync_sky()


func sync_sky() -> void:
	if not is_inside_tree():
		return
	var env: Environment = get_viewport().world_3d.environment if get_viewport() and get_viewport().world_3d else null
	var sm: ShaderMaterial = env.sky.sky_material as ShaderMaterial if env and env.sky else null
	var mats: Array[ShaderMaterial] = [_mat]
	if streamer_mats.is_empty() and globe_ref:
		var st: Object = globe_ref.get("streamer")
		if st:
			for k: String in ["material", "shell_material"]:
				var m: Variant = st.get(k)
				if m is ShaderMaterial:
					streamer_mats.append(m)
	mats.append_array(streamer_mats)
	var p: Dictionary = sky_params(sm, get_viewport().get_camera_3d())
	for m: ShaderMaterial in mats:
		if m == null:
			continue
		for k2: String in p:
			m.set_shader_parameter(k2, p[k2])


var streamer_mats: Array[ShaderMaterial] = []
var globe_ref: Node


## The water's sky uniforms from the sky shader's own (orbit_sky.gdshader: day mixes its night
## colours to its hazy day colours) and the camera's local up.
static func sky_params(sm: ShaderMaterial, cam: Camera3D) -> Dictionary:
	var out: Dictionary = {}
	if sm == null:
		return out
	var gv := func(k: String, fb: Variant) -> Variant:
		var v: Variant = sm.get_shader_parameter(k)
		return fb if v == null else v
	var day: float = float(gv.call("day", 1.0))
	var haze: float = float(gv.call("haze", 1.0))
	var zd: Color = _c(gv.call("zenith_day", Color(0.2, 0.42, 0.82)))
	var zc: Color = _c(gv.call("zenith_clear", Color(0.12, 0.38, 0.9)))
	var hd: Color = _c(gv.call("horizon_day", Color(0.74, 0.7, 0.6)))
	var hc: Color = _c(gv.call("horizon_clear", Color(0.46, 0.66, 0.95)))
	var zn: Color = _c(gv.call("zenith_night", Color(0.03, 0.05, 0.11)))
	var hn: Color = _c(gv.call("horizon_night", Color(0.09, 0.12, 0.21)))
	var zen: Color = zn.lerp(zc.lerp(zd, haze * 0.4), day)
	var hor: Color = hn.lerp(hc.lerp(hd, haze * 0.4), day)
	out["sky_zen"] = Vector3(zen.r, zen.g, zen.b)
	out["sky_hor"] = Vector3(hor.r, hor.g, hor.b)
	out["sky_day"] = day
	var s1: Vector3 = gv.call("sun1_dir", Vector3.UP)
	var up: Vector3 = cam.global_position.normalized() if cam else Vector3.UP
	out["sun_dir"] = s1.normalized()
	out["sun_vis"] = smoothstep(-0.03, 0.12, s1.normalized().dot(up))
	var warm: float = 1.0 - smoothstep(0.05, 0.4, s1.normalized().dot(up))  # low sun: a warmer glint
	out["sun_col"] = Vector3(1.0, 0.95, 0.85).lerp(Vector3(1.0, 0.62, 0.32), warm)
	return out


static func _c(v: Variant) -> Color:
	if v is Color:
		return v
	if v is Vector3:
		return Color((v as Vector3).x, (v as Vector3).y, (v as Vector3).z)
	return Color.WHITE


## Clarity from the cell's junk: a cleaned lake goes clear.
func _tint(c: int) -> void:
	var mi: MeshInstance3D = _cell[c]
	var clear: float = 1.0 - cells.junk[c]
	mi.set_instance_shader_parameter("clarity", clear)


func _clear(c: int) -> bool:
	return SphereCells.clean_left(cells.junk[c])  # [v2feel]


func count() -> int:
	return _cell.size()


## Fish jumping (for checks).
func fish_count() -> int:
	return _fish.size()


## The lake-clear moment (flat WaterView._on_clean), for a lake cell Lumi is near.
func _on_clean(hid: int, _pos: Vector3, _bonus: BigNum) -> void:
	if hid < 0 or hid >= cells.n or cells.state[hid] != 5 or not _cell.has(hid):
		return
	if BeepGate.take("lake_clear", 20.0):  # [v4calm] item 50: water bots clear many lake hexes in a row
		Audio.play("chime", 0.6, -6.0)
		Audio.play("whoosh", 0.4, -10.0)
	var wren: Variant = world.get("wren") if world else null
	if wren is Wren and Once.take("wren_lake_clear"):  # [v4calm] item 45: once per save, not per lake hex
		(wren as Wren).line_started.emit(tr("The water... I can see the bottom. Lumi, there's something moving down there."), 1)
	if not _fish.any(func(f: Dictionary) -> bool: return int(f["cell"]) == hid):
		_stock_fish(hid)


func _stock_fish(c: int) -> void:
	if _fish_mesh == null:
		_fish_mesh = ProcMesh.capsule(0.05, 0.28)
		_fish_mat = StandardMaterial3D.new()
		_fish_mat.albedo_color = Color(0.75, 0.78, 0.8)
		_fish_mat.metallic = 0.6
		_fish_mat.roughness = 0.3
	var lake: MeshInstance3D = _cell[c]
	for i: int in FISH_PER_CELL:
		var n := MeshInstance3D.new()
		n.mesh = _fish_mesh
		n.material_override = _fish_mat
		n.visible = false
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lake.add_child(n)
		var fish: Dictionary = {"node": n, "cell": c, "speed": randf_range(0.6, 1.1), "phase": randf() * 6.0}
		_new_jump(fish)
		_fish.append(fish)


func _new_jump(fish: Dictionary) -> void:
	var a := Vector3(randf_range(-FISH_SPREAD, FISH_SPREAD), 0.0, randf_range(-FISH_SPREAD, FISH_SPREAD))
	var d := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(1.0, 2.0)
	fish["a"] = a
	fish["b"] = a + d
	fish["splashed"] = false


func _process(_delta: float) -> void:
	_sky_tick(_delta)  # [v4world]
	if _fish.is_empty():
		return
	var t: float = Time.get_ticks_msec() * 0.001
	for fish: Dictionary in _fish:
		var n: MeshInstance3D = fish["node"]
		if not is_instance_valid(n):
			continue
		var ph: float = fmod(t * float(fish["speed"]) + float(fish["phase"]), 6.0)
		if ph < 1.0:
			var a: Vector3 = fish["a"]
			var b: Vector3 = fish["b"]
			n.visible = true
			n.position = a.lerp(b, ph) + Vector3(0, sin(ph * PI) * 0.9, 0)
			n.rotation = Vector3(0, atan2(b.x - a.x, b.z - a.z), cos(ph * PI) * 1.2)
			if ph >= 0.97 and not bool(fish.get("splashed", false)):
				fish["splashed"] = true
				var lake: Node3D = n.get_parent()
				Vfx.burst("soil", lake.global_transform * (b + Vector3(0, 0.1, 0)), Color(0.7, 0.85, 1.0, 0.8), 0.4)
		else:
			n.visible = false
			if ph > 5.9:
				_new_jump(fish)


## [v4world] Dev: --lake-view[=back_m] puts Lumi on the shore of the lake nearest the start, back_m
## (default 4) from the water's edge, facing out over it (water look renders: owner playtest 3 #53;
## add --lake-view-high[=40] for a camera that many metres up, --lake-clean for cleaned lakes).
static func dev_view(so: SliceOrbit) -> void:
	var tree: SceneTree = so.w.get_tree()
	var patch: Patch = null
	for k: int in 600:  # until Lumi is placed (the scene builds over many frames)
		await tree.process_frame
		patch = so.w.get("patch") as Patch
		if patch and patch.is_inside_tree() and patch.global_position.length() > 1.0:
			break
	await tree.create_timer(2.0).timeout
	var g: OrbitPlanet = so.globe
	if patch == null:
		print("[lake-view] no Lumi")
		return
	var from: Vector3 = g.grid.centers[g.start_cell()].normalized()
	if DevHooks.has("lake-clean"):  # every lake round the start cleaned (the clear look)
		for c0: int in g.grid.cells_within(from, 900.0):
			if g.cells.state[c0] == 5:
				g.cells.set_junk(c0, 0.0)
		g.cells.flush()
	var best: int = -1
	var best_land: int = -1
	var bd: float = INF
	for c: int in g.grid.cells_within(from, 900.0):
		if g.cells.state[c] != 5 or g.cells.has_flag(c, SphereCells.F_SITE) or g.grid.centers[c].angle_to(from) * g.terrain.R < 60.0:
			continue  # not the wet cells under the pad
		var wet_n: int = 0
		for o: int in g.grid.neighbors(c):
			wet_n += 1 if g.cells.state[o] == 5 else 0
		if wet_n < 4:
			continue  # the edge of open water, not a puddle cell
		for o2: int in g.grid.neighbors(c):
			if g.cells.state[o2] == 5 or g.cells.has_flag(o2, SphereCells.F_SITE):
				continue
			var d: float = g.grid.centers[o2].angle_to(from)
			if d < bd:
				bd = d
				best = c
				best_land = o2
	if best < 0:
		print("[lake-view] no lake near the start")
		return
	var wc: Vector3 = g.grid.centers[best]
	var lc: Vector3 = g.grid.centers[best_land]
	var up: Vector3 = lc.normalized()
	var to_w: Vector3 = (wc - lc)
	to_w = (to_w - up * to_w.dot(up)).normalized()
	var back: float = DevHooks.get_f("lake-view", 4.0)
	var at: Vector3 = g.terrain.ground((lc * g.terrain.R - to_w * back).normalized())
	patch.place_on_sphere(at, to_w)
	so.cam.reset_frame(to_w)
	so.cam.snap()
	if DevHooks.has("lake-view-high"):  # a free camera H m up over the shore, looking out over the lake
		var hh: float = DevHooks.get_f("lake-view-high", 40.0)
		var hc := Camera3D.new()
		hc.name = "LakeViewCam"
		hc.far = 4000.0
		so.w.add_child(hc)
		var eye: Vector3 = at + up * hh - to_w * hh * 0.5
		hc.look_at_from_position(eye, at + to_w * hh * 1.4, up)
		hc.current = true
	print("[lake-view] Lumi on the shore of lake cell %d, %.0f m from the start, facing the water" % [best, bd * g.terrain.R])
