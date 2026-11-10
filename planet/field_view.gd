class_name FieldView
extends Node3D
## Presentation of a HexField: PBR restoration ground, real-model junk in chunked MultiMeshes,
## big wreck landmarks, and a hazy dirt-hill horizon. Reads the sim; never owns game state.

const CHUNK: int = 5  # hexes per chunk side (axial), for MultiMesh culling + LOD
const GROUND_LAYERS: Array[String] = [
	"worn_asphalt", "road_damaged", "concrete_pavement", "dirty_concrete",
	"dry_ground_rocks", "withered_grass", "dry_decay_leaves", "rubble",
	"sparse_grass", "leafy_grass",
]

var layout: CityLayout
var ground_material: ShaderMaterial
## [biomes] Frontier ground: texture layer swaps (layer index -> texture id) and shader extras
## (x sand ripples, y frost, z wet silt). Set before setup().
var layer_swap: Dictionary = {}
var ground_fx := Vector4.ZERO
## [biomes2] Frontiers build their own terrain and silhouettes (planet/frontier_view.gd): no
## hemisphere hills or horizon wrecks here.
var skip_horizon: bool = false

var field: HexField
var clock: float = 0.0

var _ground_mat: ShaderMaterial
var _state_img: Image
var _state_tex: ImageTexture
var _piece_mm := PackedInt32Array()  # pid -> index into _mms
var _piece_slot := PackedInt32Array()  # pid -> instance index
var _mms: Array[MultiMesh] = []
## [deck] Junk MultiMeshes whose pieces are all gone are hidden (no empty draw calls late game).
var _mmis: Array[MultiMeshInstance3D] = []
## [vqa2] Junk near/far LOD; owns the junk MultiMesh buffers (_mms / _mmis are its NEAR ones).
var lod: JunkLod
var _piece_shown := PackedByteArray()
var _dirty_tex: bool = false
var _life_img: Image
var _life_tex: ImageTexture
var _life_dirty: bool = false  # [green] one texture upload per frame, however many hexes changed
var _mounds: Array = []  # hex id -> Array[MeshInstance3D]
## [leftovers] A layout bake already running on worker threads (CityLayout.bake_start), set before
## setup(); the ground picks it up at the end of setup instead of baking inline.
var layout_job: Dictionary = {}


## [leftovers] A coroutine when a BuildBudget is open (the loading screen): it yields between
## chunks. Without one it runs straight through, as before.
func setup(p_field: HexField) -> void:
	field = p_field
	layout = field.layout
	_build_ground()
	BuildBudget.sub(0.05)
	await BuildBudget.check("fv:ground")
	await _build_mounds()
	await _build_junk()
	await _build_landmarks()
	_apply_biome()
	for id: int in field.hex_count():
		_write_hex(id, -100.0)
	_flush()
	if not layout_job.is_empty():
		_ground_mat.set_shader_parameter("layout_tex", ImageTexture.create_from_image(await layout.bake_collect(layout_job)))
		layout_job = {}
	BuildBudget.sub(1.0)


func _process(delta: float) -> void:
	clock += delta
	if _ground_mat:
		_ground_mat.set_shader_parameter("time_now", clock)
	if _dirty_tex:
		_flush()
	var cam: Camera3D = get_viewport().get_camera_3d() if lod else null  # [vqa2] junk LOD
	if cam:
		lod.update(delta, cam.global_position)
	if _life_dirty:  # [green]
		_life_dirty = false
		_life_tex.update(_life_img)


# --- Ground -----------------------------------------------------------------------

static func _tex_array(ids: Array[String], map: String) -> Texture2DArray:
	var imgs: Array[Image] = []
	for id: String in ids:
		var t: Texture2D = AssetLib.tex(id, map)
		var img: Image = t.get_image() if t else null
		if img == null:
			img = Image.create(64, 64, true, Image.FORMAT_RGBA8)
			img.fill(Color(0.5, 0.5, 1.0) if map == "nor_gl" else Color(0.5, 0.45, 0.4))
		imgs.append(img)
	# All layers must share size/format/mipmaps; convert mismatches to the first layer's format.
	var ref: Image = imgs[0]
	for i: int in imgs.size():
		var im: Image = imgs[i]
		if im.get_format() != ref.get_format() or im.get_size() != ref.get_size() or im.has_mipmaps() != ref.has_mipmaps():
			if im.is_compressed():
				im.decompress()
			if ref.is_compressed():
				push_warning("Texture array layer %s mismatched; using uncompressed layers" % ids[i])
			im.convert(ref.get_format() if not ref.is_compressed() else Image.FORMAT_RGBA8)
			im.resize(ref.get_width(), ref.get_height())
			if ref.has_mipmaps():
				im.generate_mipmaps()
			imgs[i] = im
	if imgs.any(func(im: Image) -> bool: return im.get_format() != imgs[0].get_format()):
		for im: Image in imgs:
			if im.is_compressed():
				im.decompress()
			im.convert(Image.FORMAT_RGBA8)
			if not im.has_mipmaps():
				im.generate_mipmaps()
	var arr := Texture2DArray.new()
	arr.create_from_images(imgs)
	return arr


func _build_ground() -> void:
	var size: int = field.radius * 2 + 1
	_state_img = Image.create(size, size, false, Image.FORMAT_RGBAF)
	_state_tex = ImageTexture.create_from_image(_state_img)
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = preload("res://art/shaders/ground_pbr.gdshader")
	var layers: Array[String] = GROUND_LAYERS.duplicate()
	for k: Variant in layer_swap:  # [biomes]
		layers[int(str(k))] = str(layer_swap[k])
	_ground_mat.set_shader_parameter("albedo_arr", _tex_array(layers, "diff"))
	_ground_mat.set_shader_parameter("normal_arr", _tex_array(layers, "nor_gl"))
	_ground_mat.set_shader_parameter("arm_arr", _tex_array(layers, "arm"))
	_ground_mat.set_shader_parameter("frontier_fx", ground_fx)
	_ground_mat.set_shader_parameter("state_tex", _state_tex)
	_life_img = Image.create(size, size, false, Image.FORMAT_RGBA8)  # [green] R life, G level / 5, B row angle (8-bit: always filterable)
	_life_tex = ImageTexture.create_from_image(_life_img)
	_ground_mat.set_shader_parameter("life_tex", _life_tex)
	_ground_mat.set_shader_parameter("grid_radius", field.radius)
	_ground_mat.set_shader_parameter("hex_size", field.hex_size)
	var extent: float = (layout.extent * 2.0) if layout else (field.radius + 8) * field.hex_size * 2.4
	if layout:
		if layout_job.is_empty():
			_ground_mat.set_shader_parameter("layout_tex", ImageTexture.create_from_image(layout.bake_image(extent, 0.25)))
		_ground_mat.set_shader_parameter("layout_size", extent)
	_ground_mat.set_shader_parameter("warp_tex", ImageTexture.create_from_image(field.border_warp_image(extent)))
	_ground_mat.set_shader_parameter("warp_size", extent)
	_ground_mat.set_shader_parameter("warp_amp", field.hex_size * 0.75 if field.natural_borders else 0.0)
	ground_material = _ground_mat
	var plane := PlaneMesh.new()
	plane.size = Vector2(extent, extent)
	plane.subdivide_width = 32
	plane.subdivide_depth = 32
	plane.material = _ground_mat
	var g := MeshInstance3D.new()
	g.name = "Ground"
	g.mesh = plane
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(g)
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(extent, 1.0, extent)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	body.add_child(shape)
	add_child(body)


# --- Junk -------------------------------------------------------------------------

## Basis + vertical offset so the model rests on the ground in the given pose.
func _pose_basis(model: String, pose: int, yaw: float, tilt: float, scl: float) -> Transform3D:
	var b := Basis(Vector3.UP, yaw)
	match pose:
		1: b = b * Basis(Vector3.RIGHT, PI * 0.5)
		2: b = b * Basis(Vector3.FORWARD, PI * 0.5)
	b = b * Basis(Vector3.RIGHT, tilt) * Basis(Vector3.FORWARD, tilt * 0.7)
	b = b.scaled(Vector3.ONE * scl)
	var aabb: AABB = AssetLib.model_aabb(model)
	var min_y: float = INF
	for i: int in 8:
		min_y = minf(min_y, (b * aabb.get_endpoint(i)).y)
	return Transform3D(b, Vector3(0, -min_y - 0.01, 0))


func piece_transform(pid: int) -> Transform3D:
	var t: Transform3D = _pose_basis(field.piece_model[pid], field.piece_pose[pid], field.piece_yaw[pid], field.piece_tilt[pid], field.piece_scale[pid])
	var p: Vector3 = field.piece_pos[pid]
	t.origin += Vector3(p.x, field.piece_rest_y(pid), p.z)
	return t


func piece_mesh(pid: int) -> Mesh:
	return AssetLib.model_mesh(field.piece_model[pid])


func _build_junk() -> void:
	var groups: Dictionary = {}  # "cx,cy|model" -> PackedInt32Array
	for pid: int in field.piece_count():
		var a: Vector2i = field.hex_axial[field.piece_hex[pid]]
		var key: String = "%d,%d|%s" % [floori(float(a.x) / CHUNK), floori(float(a.y) / CHUNK), field.piece_model[pid]]
		var arr: PackedInt32Array = groups.get(key, PackedInt32Array())
		arr.append(pid)
		groups[key] = arr
	_piece_mm.resize(field.piece_count())
	_piece_slot.resize(field.piece_count())
	_piece_shown.resize(field.piece_count())
	lod = JunkLod.new(field, Settings.quality)  # [vqa2] near/far junk LOD (planet/junk_lod.gd)
	var gi: int = 0
	for key: String in groups:
		gi += 1
		BuildBudget.sub(0.1 + 0.75 * float(gi) / groups.size())
		await BuildBudget.check("fv:junk")
		var pids: PackedInt32Array = groups[key]
		var model: String = key.split("|")[1]
		# Small litter doesn't cast sun shadows (SSAO grounds it); bigger items do.
		var vol: float = field.piece_vol[pids[0]]
		await AssetLib.fetch_model(model)  # [leftovers] its file loads on a loader thread
		await BuildBudget.check("fv:junk model")
		var near_mesh: Mesh = AssetLib.model_mesh_lite(model, [320, 500, 700, 700][clampi(Settings.quality, 0, 3)])  # [deck] lighter junk on Low/Medium
		await BuildBudget.check("fv:junk lite")
		var idx: int = lod.add_group(self, "Junk_" + key.replace("|", "_").replace(",", "_"), model, near_mesh, pids, vol >= 1.2, Settings.quality)
		_mms.append(lod.near_mm[idx])
		_mmis.append(lod.near_mmi[idx])
		for i: int in pids.size():
			var pid: int = pids[i]
			_piece_mm[pid] = idx
			_piece_slot[pid] = i
			_piece_shown[pid] = 1 if field.piece_alive[pid] == 1 else 0
			if field.piece_alive[pid] == 1:
				lod.show_piece(pid, piece_transform(pid))
			if i & 63 == 63:
				await BuildBudget.check("fv:junk pieces")


## [biomes2] Frontiers: a weathering overlay (art/shaders/junk_coat.gdshader) on every junk piece.
func set_junk_overlay(m: Material) -> void:
	lod.set_overlay(m)  # [vqa2] near + far junk
	for list: Variant in _mounds:  # [vqa2] the debris mounds too (dark rubble crescents in the dunes)
		for mi: MeshInstance3D in list:
			mi.material_overlay = m


static func _mound_mesh() -> ArrayMesh:
	# Lumpy compacted-debris mound: a hemisphere pushed around by noise, unit radius and height.
	var noise := FastNoiseLite.new()
	noise.frequency = 1.6
	noise.seed = 9
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: int = 10
	var segs: int = 28
	var pts: Array = []
	for r: int in rings + 1:
		var row: Array = []
		var phi: float = float(r) / rings * PI * 0.5
		for k: int in segs + 1:
			var th: float = float(k) / segs * TAU
			var dir := Vector3(cos(th) * cos(phi), sin(phi), sin(th) * cos(phi))
			var d: float = 1.0 + noise.get_noise_3dv(dir * 2.0) * 0.35
			var v: Vector3 = dir * d
			if r == 0:
				v.y = -0.05
			row.append(v)
		pts.append(row)
	for r: int in rings:
		for k: int in segs:
			var a: Vector3 = pts[r][k]
			var b: Vector3 = pts[r][k + 1]
			var c: Vector3 = pts[r + 1][k + 1]
			var d: Vector3 = pts[r + 1][k]
			for v: Vector3 in [a, b, c, a, c, d]:  # [world2] clockwise from outside (was inside-out)
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


func _build_mounds() -> void:
	var mesh: ArrayMesh = _mound_mesh()
	var mat: StandardMaterial3D = AssetLib.pbr_material("rubble", 0.9, Color(0.42, 0.38, 0.36), true)
	mesh.surface_set_material(0, mat)
	_mounds.resize(field.hex_count())
	for id: int in field.hex_count():
		await BuildBudget.check("fv:mounds")
		var list: Array = []
		for pile: Vector4 in field.hex_piles[id]:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.position = Vector3(pile.x, -0.02, pile.y)
			mi.set_meta("pile", pile)
			add_child(mi)
			mi.set_meta("body", MoundColliders.make(self, pile))  # [world2] bales rest on the heap
			list.append(mi)
		_mounds[id] = list
		_update_mounds(id)


func _update_mounds(id: int) -> void:
	var left: float = 0.0 if field.hex_clean[id] == 1 else (0.3 + 0.7 * (1.0 - field.removed_fraction(id)))
	for mi: MeshInstance3D in _mounds[id]:
		var pile: Vector4 = mi.get_meta("pile")
		mi.visible = left > 0.0
		mi.scale = Vector3(pile.z * 1.1, maxf(pile.w * left * 0.9, 0.001), pile.z * 1.1)
		MoundColliders.update(mi.get_meta("body", null), mi.scale, mi.visible, 1.0 - field.removed_fraction(id))  # [world2]


## Re-seat remaining pieces of a hex on its (shrinking) mound.
func _resettle(id: int) -> void:
	for pid: int in field.hex_pieces[id]:
		if field.piece_alive[pid] == 1:
			lod.show_piece(pid, piece_transform(pid))  # [vqa2]


func _hidden() -> Transform3D:
	return Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0))


func hide_piece(pid: int) -> void:
	lod.hide_piece(pid)  # [vqa2]
	_set_shown(pid, false)


func move_piece(pid: int, pos: Vector3) -> void:
	field.piece_pos[pid] = pos
	lod.show_piece(pid, piece_transform(pid))  # [vqa2]
	_set_shown(pid, true)


func _set_shown(pid: int, on: bool) -> void:
	if pid >= _piece_shown.size() or (_piece_shown[pid] == 1) == on:
		return
	_piece_shown[pid] = 1 if on else 0  # [vqa2] JunkLod hides empty near/far buffers itself


# --- Hex state --------------------------------------------------------------------

func refresh_hex(id: int, flipped_now: bool = false) -> void:
	_write_hex(id, clock if flipped_now else -1.0)
	if field.junk_gen >= 2:  # [world2] hub/blocked ground follows the junk hexes that own it
		for o: Vector2i in Hex.DIRECTIONS:
			var nb: int = int(field.axial_to_id.get(field.hex_axial[id] + o, -1))
			if nb >= 0 and field.hex_hub[nb] != 0:
				_write_hex(nb, clock if flipped_now else -1.0)
	_update_mounds(id)
	_resettle(id)
	_dirty_tex = true


func _write_hex(id: int, flip_time: float) -> void:
	var a: Vector2i = field.hex_axial[id]
	var x: int = a.x + field.radius
	var y: int = a.y + field.radius
	var prev: Color = _state_img.get_pixel(x, y)
	var ft: float = prev.g if flip_time == -1.0 else flip_time
	var flag: float = 1.0 if field.hex_hub[id] == 1 else (0.5 if field.is_water(id) else 0.0)
	if field.junk_gen >= 2 and field.hex_hub[id] != 0:  # [world2] only the yard slab is clean ground
		var nb: Vector2 = _owner_state(field, id)
		_state_img.set_pixel(x, y, Color(nb.x, ft, nb.y, 0.0))
		return
	_state_img.set_pixel(x, y, Color(field.removed_fraction(id), ft, float(field.hex_clean[id]), flag))


## [world2] A yard/street hex's junk state is its land neighbours': x = their mean removed
## fraction, y = 1 when they are all clean.
static func _owner_state(f: HexField, id: int) -> Vector2:
	var rem: float = 0.0
	var n: int = 0
	var all_clean: bool = true
	for o: Vector2i in Hex.DIRECTIONS:
		var nb: int = int(f.axial_to_id.get(f.hex_axial[id] + o, -1))
		if nb < 0 or f.hex_hub[nb] != 0 or f.is_water(nb):
			continue
		rem += f.removed_fraction(nb)
		n += 1
		all_clean = all_clean and f.is_clean(nb)
	if n == 0:
		return Vector2(1.0, 1.0)
	return Vector2(rem / n, 1.0 if all_clean else 0.0)


func _flush() -> void:
	_state_tex.update(_state_img)
	_dirty_tex = false


func state_texture() -> ImageTexture:
	return _state_tex


func set_life(id: int, life: float) -> void:
	_set_life_ch(id, 0, life)  # [green] keeps the level / row channels


## [green] Hex level (0..5) and planting-row angle (0..1 = 0..PI) for the meadow and the tilled
## soil (plants/meadow.gd, ground_pbr.gdshader).
func set_level(id: int, level: int) -> void:
	_set_life_ch(id, 1, float(level) / 5.0)


func set_rows(id: int, angle01: float) -> void:
	_set_life_ch(id, 2, angle01)


func life_texture() -> ImageTexture:
	return _life_tex


func _set_life_ch(id: int, ch: int, v: float) -> void:
	var a: Vector2i = field.hex_axial[id]
	var c: Color = _life_img.get_pixel(a.x + field.radius, a.y + field.radius)
	c[ch] = clampf(v, 0.0, 1.0)
	c.a = 1.0
	_life_img.set_pixel(a.x + field.radius, a.y + field.radius, c)
	_life_dirty = true


func set_focus_hex(_id: int) -> void:
	# [onboard] The straight amber focus line is replaced by the laser outline (story/objective_hex.gd).
	_ground_mat.set_shader_parameter("focus_axial", Vector2(9999, 9999))


func set_grid_visible(v: float) -> void:
	_ground_mat.set_shader_parameter("show_grid", v)


# --- Landmarks + horizon ------------------------------------------------------------

func _add_prop(model: String, pos: Vector3, yaw: float, collide: bool, scl: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = AssetLib.model_mesh_lite(model, 4000)
	var t: Transform3D = _pose_basis(model, 0, yaw, 0.0, scl)
	t.origin += pos
	mi.transform = t
	mi.visibility_range_end = 220.0
	add_child(mi)
	if collide:
		var aabb: AABB = mi.mesh.get_aabb()
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = aabb.size * scl * 0.92
		cs.shape = box
		cs.position = aabb.get_center() * scl
		body.add_child(cs)
		mi.add_child(body)
	return mi


func _build_landmarks() -> void:
	var coat: Material = _biome_coat()
	for lm: Dictionary in field.landmarks:
		await BuildBudget.check("fv:landmarks")
		await AssetLib.fetch_model(str(lm["model"]))
		await BuildBudget.check("fv:landmark model")
		var mi: MeshInstance3D = _add_prop(str(lm["model"]), lm["pos"], float(lm["yaw"]), true)
		if coat:
			mi.material_overlay = coat


## Wilderness districts: tint the ground and grass to the biome and ring the field with its own
## horizon (sand dunes, frost ridges, stumpy rust hills) so a rocket trip lands somewhere new.
func _apply_biome() -> void:
	var b: Dictionary = field.biome_set
	if b.is_empty():
		return
	var gt: Array = b.get("ground_tint", [1, 1, 1, 0])
	_ground_mat.set_shader_parameter("biome_tint", Vector4(float(gt[0]), float(gt[1]), float(gt[2]), float(gt[3])))
	var gr: Array = b.get("grass_tint", [1, 1, 1])
	_ground_mat.set_shader_parameter("grass_tint", Vector3(float(gr[0]), float(gr[1]), float(gr[2])))
	if (layout == null or layout.wild) and not skip_horizon:
		_build_horizon()


## A thin translucent film (sand, frost, moss) over big wrecks; null in cities.
func _biome_coat() -> Material:
	var c: Array = field.biome_set.get("coat", [])
	if c.size() < 4:
		return null
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(float(c[0]), float(c[1]), float(c[2]), float(c[3]))
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m


func _build_horizon() -> void:
	# Low dirt and rubble hills ringing the field, with wrecks on them, fading into haze.
	var rng := RandomNumberGenerator.new()
	rng.seed = field.seed_value + 99
	var r0: float = (field.radius + 1.6) * field.hex_size * 1.75
	var ht: Array = field.biome_set.get("hills", [1, 1, 1])
	var hc := Color(float(ht[0]), float(ht[1]), float(ht[2]))
	var mat: StandardMaterial3D = AssetLib.pbr_material("rubble", 0.12, Color(0.85, 0.8, 0.78) * hc, true)
	var mat2: StandardMaterial3D = AssetLib.pbr_material("brown_mud_dry", 0.1, Color(0.9, 0.85, 0.82) * hc, true)
	var coat: Material = _biome_coat()
	var hill := SphereMesh.new()
	hill.radius = 1.0
	hill.height = 1.0
	hill.is_hemisphere = true
	hill.radial_segments = 24
	hill.rings = 8
	var props: Array[String] = ["covered_car", "old_tyre", "Barrel_01", "electric_stove", "exterior_aircon_unit", "plastic_crate_01", "trashbag", "metal_jerrycan", "concrete_road_barrier"]
	if field.biome_set.has("horizon"):
		props.assign(field.biome_set["horizon"])
	for i: int in 54:
		var ang: float = TAU * i / 54.0 + rng.randf_range(-0.04, 0.04)
		var dist: float = r0 + rng.randf_range(2.0, 24.0)
		var h: float = rng.randf_range(2.0, 7.0) * (1.0 + (dist - r0) / r0)
		var w: float = rng.randf_range(8.0, 15.0)
		var mi := MeshInstance3D.new()
		mi.mesh = hill
		mi.material_override = mat if rng.randf() < 0.6 else mat2
		mi.position = Vector3(cos(ang) * dist, -0.3, sin(ang) * dist)
		mi.scale = Vector3(w, h, w * rng.randf_range(0.6, 1.0))
		mi.rotation.y = rng.randf() * TAU
		add_child(mi)
		for k: int in rng.randi_range(1, 4):
			var model: String = props[rng.randi() % props.size()]
			var a2: float = rng.randf() * TAU
			var rr: float = rng.randf_range(0.0, 0.6)
			var local := Vector3(cos(a2) * rr * w, 0.0, sin(a2) * rr * w)
			var y: float = h * sqrt(maxf(0.0, 1.0 - rr * rr)) - 0.3
			var hp: MeshInstance3D = _add_prop(model, mi.position + Vector3(local.x, y - 0.25, local.z), rng.randf() * TAU, false, rng.randf_range(0.9, 1.3))
			if coat:
				hp.material_overlay = coat
	# Scattered wrecks between field edge and hills.
	for i: int in 16:
		var ang: float = rng.randf() * TAU
		var dist: float = (field.radius + 0.8) * field.hex_size * 1.6 + rng.randf_range(0.0, 8.0)
		var wreck: MeshInstance3D = _add_prop(props[rng.randi() % props.size()], Vector3(cos(ang) * dist, 0, sin(ang) * dist), rng.randf() * TAU, true)
		if coat:
			wreck.material_overlay = coat
