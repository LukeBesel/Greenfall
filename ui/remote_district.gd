class_name RemoteDistrict
extends Node3D
## [scope] A cheap, read-only model of another world's base district for the telescope view
## (ui/telescope_view.gd). Built from a RemoteProgress snapshot (its saved clean bits and hex
## levels), never from the full world: one ground texture with natural (noise-warped) borders
## between junk, clean and green ground, a MultiMesh of junk piles, the base, and the crew's
## robot models doing simple loops (cleaners at the junk front, haulers rolling bales home, Drips
## spraying light over green hexes, Seedlings planting). Progress is the remote-progress estimate:
## piles shrink and hexes turn clean at the rate RemoteProgress pays, so what you watch is what
## you'll be paid when you visit.

const HEX_SIZE: float = 10.0
const PIECES_PER_HEX: int = 24
const MAX_BOTS: int = 14
const BOT_SPEED: float = 2.6
const EXTENT: float = 96.0

var snap: Dictionary = {}
var world_rec: Dictionary = {}
var axial: Array[Vector2i] = []
var state: PackedInt32Array
var prog: PackedFloat32Array  ## junk hexes: share of the hex already cleaned (live)
var bots: Array[Dictionary] = []
var bales: Array[Dictionary] = []
var sprouts: int = 0
var boost: float = 1.0
var palette: Dictionary = {}
var spot_nodes: Dictionary = {}  # kind -> Node3D (Ledger wreck, deer)
var _ground_mat: StandardMaterial3D
var _junk_mm: MultiMesh
var _sprout_mm: MultiMesh
var _piece_hex: PackedInt32Array
var _piece_xf: Array[Transform3D] = []
var _base_units: float = 0.0  # pending units at open
var _t0_unix: float = 0.0
var _live_units: float = 0.0
var _rate: float = 0.0  # remote units per second (estimate)
var _noise: FastNoiseLite
var _rng := RandomNumberGenerator.new()
var _bale_mesh: Mesh
var _bale_mat: StandardMaterial3D
var _spray_mat: StandardMaterial3D


func setup(p_snap: Dictionary, p_world: Dictionary) -> void:
	snap = p_snap
	world_rec = p_world
	_rng.seed = int(snap.get("index", 0)) * 7919 + 13
	axial = Hex.spiral(int(snap.get("radius", 3)))
	var clean: PackedByteArray = snap.get("clean", PackedByteArray())
	var levels: PackedByteArray = snap.get("levels", PackedByteArray())
	state.resize(axial.size())
	prog.resize(axial.size())
	for i: int in axial.size():
		state[i] = RemoteProgress.hex_state(clean[i] if i < clean.size() else 0, levels[i] if i < levels.size() else 0)
		prog[i] = 0.0
	palette = terrain_palette(str(snap.get("type", "")), str(snap.get("planet_id", "")))
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.seed = 4177
	_noise.frequency = 0.07
	_noise.fractal_octaves = 3
	# What the crew has done since Lumi left: whole hexes first (nearest the base), then a share.
	var pend: Dictionary = RemoteProgress.pending(snap, world_rec)
	_base_units = float(pend["units"])
	_t0_unix = Time.get_unix_time_from_system()
	var later: Dictionary = RemoteProgress.pending(snap, world_rec, _t0_unix + 60.0)
	_rate = maxf(0.0, (float(later["units"]) - _base_units) / 60.0)
	_apply_units(_base_units)
	_build_ground()
	_build_base()
	_build_junk()
	_build_sprouts()
	_build_bots()
	_build_spots()


## Ground colours: data/planets.json env hints when that file exists, else the world type.
static func terrain_palette(type_id: String, planet_id: String = "") -> Dictionary:
	var p: Dictionary = {"junk": Color(0.42, 0.36, 0.3), "clean": Color(0.62, 0.58, 0.5), "green": Color(0.3, 0.5, 0.26),
		"far": Color(0.46, 0.42, 0.36), "base": Color(0.78, 0.79, 0.8), "sky": Color(0.55, 0.68, 0.82), "fog": Color(0.7, 0.72, 0.74)}
	match type_id:
		"ice_moon":
			p.merge({"junk": Color(0.55, 0.58, 0.62), "clean": Color(0.84, 0.88, 0.93), "green": Color(0.42, 0.6, 0.5), "far": Color(0.86, 0.9, 0.95), "sky": Color(0.62, 0.74, 0.88)}, true)
		"desert_world":
			p.merge({"junk": Color(0.55, 0.42, 0.3), "clean": Color(0.82, 0.68, 0.48), "green": Color(0.48, 0.56, 0.3), "far": Color(0.8, 0.64, 0.44), "sky": Color(0.75, 0.68, 0.6)}, true)
		"ocean_world":
			p.merge({"junk": Color(0.4, 0.38, 0.34), "clean": Color(0.72, 0.68, 0.58), "green": Color(0.28, 0.52, 0.34), "far": Color(0.2, 0.4, 0.55), "sky": Color(0.5, 0.66, 0.84)}, true)
		"fungal_world":
			p.merge({"junk": Color(0.32, 0.3, 0.28), "clean": Color(0.48, 0.44, 0.4), "green": Color(0.36, 0.46, 0.34), "far": Color(0.34, 0.36, 0.32), "sky": Color(0.56, 0.58, 0.62)}, true)
		"rust_world":
			p.merge({"junk": Color(0.46, 0.3, 0.22), "clean": Color(0.62, 0.5, 0.42), "far": Color(0.5, 0.36, 0.28), "sky": Color(0.68, 0.6, 0.56)}, true)
	var path: String = "res://data/planets.json"
	if planet_id != "" and FileAccess.file_exists(path):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var pl: Variant = null
		if d is Dictionary:
			var dd: Dictionary = d
			pl = dd.get(planet_id, (dd.get("planets", {}) as Dictionary).get(planet_id) if dd.get("planets") is Dictionary else null)
			if pl == null and dd.get("planets") is Array:
				for e: Variant in dd["planets"]:
					if e is Dictionary and str((e as Dictionary).get("id", "")) == planet_id:
						pl = e
		if pl is Dictionary:
			var env: Dictionary = (pl as Dictionary).get("env", pl)
			for k: String in ["ground_color", "ground", "soil"]:
				if env.get(k) is Array and (env[k] as Array).size() >= 3:
					var c: Array = env[k]
					p["clean"] = Color(float(c[0]), float(c[1]), float(c[2]))
					p["far"] = p["clean"].darkened(0.1)
					p["junk"] = p["clean"].darkened(0.38)
					break
			for k: String in ["sky_color", "sky"]:
				if env.get(k) is Array and (env[k] as Array).size() >= 3:
					var c2: Array = env[k]
					p["sky"] = Color(float(c2[0]), float(c2[1]), float(c2[2]))
					break
	return p


func center_of(i: int) -> Vector3:
	var p: Vector2 = Hex.axial_to_world(axial[i], HEX_SIZE)
	return Vector3(p.x, 0.0, p.y)


func hex_of(p: Vector3) -> int:
	var a: Vector2i = Hex.world_to_axial(Vector2(p.x, p.z), HEX_SIZE)
	return axial.find(a)


## Share of land hexes done, counting the live partial progress.
func district_share() -> float:
	var land: float = 0.0
	var done: float = 0.0
	for i: int in state.size():
		if state[i] == -1:
			continue
		land += 1.0
		if state[i] >= 1:
			done += 1.0
		else:
			done += prog[i]
	return done / land if land > 0.0 else 1.0


func active_bots() -> int:
	var n: int = 0
	for b: Dictionary in bots:
		if str(b["state"]) != "idle":
			n += 1
	return n


func live_units() -> float:
	return _base_units + _live_units


## Junk hexes in work order: nearest the base first (the crew cleans outward).
func _junk_order() -> Array[int]:
	var ids: Array[int] = []
	for i: int in state.size():
		if state[i] == 0:
			ids.append(i)
	ids.sort_custom(func(a: int, b: int) -> bool: return center_of(a).length() < center_of(b).length())
	return ids


func _apply_units(units: float) -> void:
	var left: float = units
	for i: int in _junk_order():
		if left <= 0.0:
			break
		var need: float = (1.0 - prog[i]) * RemoteProgress.AVG_HEX_UNITS
		if left >= need:
			left -= need
			prog[i] = 1.0
			state[i] = 1
		else:
			prog[i] += left / RemoteProgress.AVG_HEX_UNITS
			left = 0.0


# --- Build ---------------------------------------------------------------------------------

func _state_color(s: int) -> Color:
	match s:
		0: return palette["junk"]
		1: return palette["clean"]
		2: return palette["green"]
	return palette["base"]


func _bake_ground() -> ImageTexture:
	var res: int = 192
	var img := Image.create(res, res, false, Image.FORMAT_RGB8)
	var r_out: float = HEX_SIZE * (float(snap.get("radius", 3)) + 0.9) * 1.6
	for y: int in res:
		for x: int in res:
			var wp := Vector3((float(x) + 0.5) / res * EXTENT - EXTENT * 0.5, 0.0, (float(y) + 0.5) / res * EXTENT - EXTENT * 0.5)
			var warp := Vector3(_noise.get_noise_2d(wp.x, wp.z), 0.0, _noise.get_noise_2d(wp.x + 913.0, wp.z - 377.0)) * HEX_SIZE * 0.75
			var i: int = hex_of(wp + warp)
			var c: Color
			if i < 0:
				c = palette["far"]
			else:
				c = _state_color(state[i])
				if state[i] == 0:
					c = c.lerp(palette["clean"], prog[i] * 0.45)
			var fine: float = _noise.get_noise_2d(wp.x * 6.0, wp.z * 6.0)
			c = c.lightened(fine * 0.06) if fine > 0.0 else c.darkened(-fine * 0.08)
			var d: float = Vector2(wp.x, wp.z).length()
			c = c.lerp(palette["far"], clampf((d - r_out * 0.62) / (r_out * 0.5), 0.0, 1.0))
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(EXTENT, EXTENT)
	_ground_mat = StandardMaterial3D.new()
	_ground_mat.albedo_texture = _bake_ground()
	_ground_mat.roughness = 0.95
	_ground_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var g := MeshInstance3D.new()
	g.mesh = plane
	g.material_override = _ground_mat
	add_child(g)
	var far := MeshInstance3D.new()
	var fp := PlaneMesh.new()
	fp.size = Vector2(900, 900)
	far.mesh = fp
	var fm := StandardMaterial3D.new()
	fm.albedo_color = palette["far"]
	fm.roughness = 1.0
	far.material_override = fm
	far.position.y = -0.02
	add_child(far)


func _build_base() -> void:
	var white := Telescope._mat(Color(0.9, 0.91, 0.92), 0.32, 0.0, 0.5)
	var satin := Telescope._mat(Color(0.16, 0.17, 0.19), 0.4, 0.6)
	var glow := Telescope._glow_mat(Color(0.55, 0.88, 1.0), 1.4)
	var lv: int = int(snap.get("hub_level", 1))
	var pad := MeshInstance3D.new()
	pad.mesh = ProcMesh.cyl(3.2, 3.3, 0.12, 6)
	pad.material_override = satin
	pad.position = Vector3(0, 0.06, -1.8)
	add_child(pad)
	var seam := MeshInstance3D.new()
	seam.mesh = ProcMesh.torus(3.1, 3.16, 6, 4)
	seam.material_override = glow
	seam.position = Vector3(0, 0.125, -1.8)
	seam.rotation.y = PI / 6.0
	add_child(seam)
	# Workshop and hall blocks grow with the base level.
	var blocks: Array = [[Vector3(-4.9, 0, 2.2), Vector3(4.0, 2.6, 3.2)], [Vector3(5.5, 0, 4.5), Vector3(4.0, 2.8, 3.0)],
		[Vector3(0, 0, 7.0), Vector3(6.0, 0.9, 2.0)], [Vector3(6.4, 0, -5.4), Vector3(3.0, 3.6, 2.4)], [Vector3(-6.2, 0, -4.8), Vector3(2.2, 5.0, 2.2)]]
	for k: int in mini(blocks.size(), lv + 1):
		var b: Array = blocks[k]
		var size: Vector3 = b[1]
		var m := MeshInstance3D.new()
		m.mesh = ProcMesh.box(size)
		m.material_override = white
		m.position = (b[0] as Vector3) + Vector3(0, size.y * 0.5, 0)
		add_child(m)
		var strip := MeshInstance3D.new()
		strip.mesh = ProcMesh.box(Vector3(size.x + 0.03, 0.035, size.z + 0.03))
		strip.material_override = glow
		strip.position = (b[0] as Vector3) + Vector3(0, size.y * 0.82, 0)
		add_child(strip)
	if lv >= 3:
		var mast := MeshInstance3D.new()
		mast.mesh = ProcMesh.cyl(0.05, 0.08, 8.0, 6)
		mast.material_override = satin
		mast.position = Vector3(2.5, 4.0, -6.0)
		add_child(mast)
		var lamp := MeshInstance3D.new()
		lamp.mesh = ProcMesh.sphere(0.14, 8, 4)
		lamp.material_override = Mats.lamp(Color(0.6, 0.9, 1.0), 2.5)
		lamp.position = Vector3(2.5, 8.1, -6.0)
		add_child(lamp)


func _build_junk() -> void:
	var junk_cols: Array[Color] = [Color(0.45, 0.3, 0.2), Color(0.36, 0.34, 0.32), Color(0.55, 0.45, 0.34), Color(0.3, 0.36, 0.4), Color(0.62, 0.3, 0.2)]
	var box := ProcMesh.box(Vector3(1.0, 0.7, 0.8))
	_junk_mm = MultiMesh.new()
	_junk_mm.transform_format = MultiMesh.TRANSFORM_3D
	_junk_mm.use_colors = true
	_junk_mm.mesh = box
	var n_junk: int = 0
	for i: int in state.size():
		if state[i] == 0:
			n_junk += 1
	_junk_mm.instance_count = n_junk * PIECES_PER_HEX
	_piece_hex.resize(_junk_mm.instance_count)
	var k: int = 0
	for i: int in state.size():
		if state[i] != 0:
			continue
		var c: Vector3 = center_of(i)
		for j: int in PIECES_PER_HEX:
			var a: float = _rng.randf() * TAU
			var r: float = sqrt(_rng.randf()) * HEX_SIZE * 0.78
			var s: float = _rng.randf_range(0.35, 1.25)
			var p: Vector3 = c + Vector3(cos(a) * r, s * 0.25, sin(a) * r)
			var xf := Transform3D(Basis.from_euler(Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf() * TAU, _rng.randf_range(-0.4, 0.4))).scaled(Vector3(s, s * _rng.randf_range(0.6, 1.3), s)), p)
			_piece_xf.append(xf)
			_piece_hex[k] = i
			_junk_mm.set_instance_transform(k, xf)
			_junk_mm.set_instance_color(k, junk_cols[_rng.randi() % junk_cols.size()].darkened(_rng.randf() * 0.2))
			k += 1
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	mat.metallic = 0.2
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _junk_mm
	mi.material_override = mat
	add_child(mi)
	_refresh_piles()


## Hides the share of each junk hex's pieces that has been cleaned.
func _refresh_piles() -> void:
	var seen: Dictionary = {}
	for k: int in _piece_hex.size():
		var i: int = _piece_hex[k]
		var idx: int = int(seen.get(i, 0))
		seen[i] = idx + 1
		var keep: bool = state[i] == 0 and float(idx) >= prog[i] * PIECES_PER_HEX
		_junk_mm.set_instance_transform(k, _piece_xf[k] if keep else Transform3D(Basis().scaled(Vector3.ONE * 0.001), Vector3(0, -5, 0)))


func _build_sprouts() -> void:
	var cone := ProcMesh.sphere(0.5, 7, 4)
	_sprout_mm = MultiMesh.new()
	_sprout_mm.transform_format = MultiMesh.TRANSFORM_3D
	_sprout_mm.use_colors = true
	_sprout_mm.mesh = cone
	var spots: Array[Transform3D] = []
	for i: int in state.size():
		if state[i] != 2:
			continue
		var c: Vector3 = center_of(i)
		for j: int in 26:
			var a: float = _rng.randf() * TAU
			var r: float = sqrt(_rng.randf()) * HEX_SIZE * 0.8
			var s: float = _rng.randf_range(0.45, 1.1)
			spots.append(Transform3D(Basis().scaled(Vector3(s, s * _rng.randf_range(0.45, 0.8), s)), c + Vector3(cos(a) * r, s * 0.18, sin(a) * r)))
	_sprout_mm.instance_count = spots.size() + 60
	for k: int in _sprout_mm.instance_count:
		if k < spots.size():
			_sprout_mm.set_instance_transform(k, spots[k])
			_sprout_mm.set_instance_color(k, (palette["green"] as Color).lerp(Color(0.16, 0.34, 0.14), _rng.randf()).darkened(_rng.randf() * 0.15))
		else:
			_sprout_mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ONE * 0.001), Vector3(0, -5, 0)))
	sprouts = spots.size()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _sprout_mm
	mi.material_override = mat
	add_child(mi)


func _add_sprout(p: Vector3) -> void:
	if sprouts >= _sprout_mm.instance_count:
		return
	_sprout_mm.set_instance_transform(sprouts, Transform3D(Basis().scaled(Vector3(0.45, 0.3, 0.45)), p + Vector3(0, 0.08, 0)))
	_sprout_mm.set_instance_color(sprouts, Color(0.42, 0.68, 0.32))
	sprouts += 1


func _build_bots() -> void:
	_bale_mesh = ProcMesh.box(Vector3(0.7, 0.6, 0.7))
	_bale_mat = Telescope._mat(Color(0.62, 0.52, 0.38), 0.8, 0.1)
	_spray_mat = Telescope._glow_mat(Color(0.65, 0.92, 1.0), 2.2)
	var list: Array = snap.get("robots", [])
	for r: Dictionary in list.slice(0, MAX_BOTS):
		var t: String = str(r.get("type", "scoopie"))
		var tier: int = clampi(int(r.get("tier", 0)), 0, 3)
		var vis := RobotVisual.new()
		add_child(vis)
		vis.build(t, ["salvage", "restored", "modern", "hover"][tier])
		var role: String = str(Economy.robots.get(t, {}).get("role", "clean"))
		if role == "any" or role == "skim":
			role = "clean"
		var start := Vector3(_rng.randf_range(-6, 6), 0, _rng.randf_range(-6, 6))
		vis.position = start
		var b: Dictionary = {"node": vis, "role": role, "state": "think", "t": _rng.randf() * 2.0, "target": start, "carry": null, "hex": -1}
		if role == "water":
			var sp := CPUParticles3D.new()
			sp.amount = 40
			sp.lifetime = 0.9
			sp.emitting = false
			sp.direction = Vector3(0, 1, 0)
			sp.spread = 55.0
			sp.initial_velocity_min = 2.2
			sp.initial_velocity_max = 3.4
			sp.gravity = Vector3(0, -6.5, 0)
			sp.scale_amount_min = 0.05
			sp.scale_amount_max = 0.09
			var q := SphereMesh.new()
			q.radius = 0.5
			q.height = 1.0
			q.radial_segments = 4
			q.rings = 2
			sp.mesh = q
			sp.material_override = _spray_mat
			sp.position = Vector3(0, 0.9, 0)
			vis.add_child(sp)
			b["spray"] = sp
		bots.append(b)


## Things to spot through the reticle: a Ledger dump-drone wreck (Ledger act 2+) and deer on
## Growing ground (level 3+). Each unlocks a Codex entry the first time it is held in view.
func _build_spots() -> void:
	var junk: Array[int] = _junk_order()
	if int(snap.get("ledger_act", 0)) >= 2 and not junk.is_empty():
		var h: int = junk[mini(junk.size() - 1, 2)]
		var wreck := _ledger_wreck()
		wreck.position = center_of(h) + Vector3(2.5, 0, -1.5)
		wreck.rotation = Vector3(0.25, 0.8, -0.35)
		add_child(wreck)
		spot_nodes["ledger_wreck"] = wreck
	var levels: PackedByteArray = snap.get("levels", PackedByteArray())
	for i: int in state.size():
		if state[i] == 2 and i < levels.size() and levels[i] >= 3:
			var deer := MeshInstance3D.new()
			deer.mesh = FaunaModels.mesh("deer")
			var dm := StandardMaterial3D.new()
			dm.vertex_color_use_as_albedo = true
			dm.albedo_color = Color(0.62, 0.44, 0.3)
			dm.roughness = 0.85
			deer.material_override = dm
			deer.position = center_of(i) + Vector3(3.0, 0, 2.0)
			deer.rotation.y = 2.2
			add_child(deer)
			spot_nodes["deer"] = deer
			break


func _ledger_wreck() -> Node3D:
	var n := Node3D.new()
	var shell := Telescope._mat(Color(0.18, 0.16, 0.16), 0.5, 0.5)
	var red := Telescope._glow_mat(Color(1.0, 0.22, 0.16), 1.6)
	var body := MeshInstance3D.new()
	body.mesh = ProcMesh.box(Vector3(1.6, 0.6, 1.1))
	body.material_override = shell
	body.position.y = 0.3
	n.add_child(body)
	for k: int in 3:
		var arm := MeshInstance3D.new()
		arm.mesh = ProcMesh.box(Vector3(1.4 - k * 0.3, 0.06, 0.12))
		arm.material_override = shell
		arm.position = Vector3(0.4 - k * 0.5, 0.62, 0.3 * k - 0.3)
		arm.rotation = Vector3(0, k * 1.1, 0.3 * (k - 1))
		n.add_child(arm)
	var eye := MeshInstance3D.new()
	eye.mesh = ProcMesh.sphere(0.09, 8, 4)
	eye.material_override = red
	eye.position = Vector3(0.82, 0.38, 0)
	n.add_child(eye)
	return n


# --- Simulation ------------------------------------------------------------------------------

func _random_in(i: int, r: float = 0.7) -> Vector3:
	var a: float = _rng.randf() * TAU
	var d: float = sqrt(_rng.randf()) * HEX_SIZE * r
	return center_of(i) + Vector3(cos(a) * d, 0, sin(a) * d)


func _pick_job(b: Dictionary) -> void:
	var role: String = b["role"]
	var depot := Vector3(0, 0, -1.8)
	b["work_t"] = 0.0
	match role:
		"clean":
			var junk: Array[int] = _junk_order()
			if junk.is_empty():
				b["state"] = "idle"
				b["target"] = Vector3(_rng.randf_range(-5, 5), 0, _rng.randf_range(-5, 5))
				return
			var h: int = junk[_rng.randi() % mini(junk.size(), 3)]
			b["hex"] = h
			b["target"] = _random_in(h, 0.6)
			b["state"] = "go"
		"haul":
			if b["carry"] != null:
				b["target"] = depot + Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-1.5, 1.5))
				b["state"] = "go"
				return
			for bale: Dictionary in bales:
				if not bool(bale["claimed"]):
					bale["claimed"] = true
					b["bale"] = bale
					b["target"] = (bale["node"] as Node3D).position
					b["state"] = "go"
					return
			b["state"] = "idle"
			b["target"] = depot + Vector3(_rng.randf_range(-4, 4), 0, _rng.randf_range(2, 4))
		"water", "plant":
			var want: int = 2 if role == "water" else 1
			var ids: Array[int] = []
			for i: int in state.size():
				if state[i] == want:
					ids.append(i)
			if ids.is_empty() and role == "plant":
				for i: int in state.size():
					if state[i] == 2:
						ids.append(i)
			if ids.is_empty():
				b["state"] = "idle"
				b["target"] = Vector3(_rng.randf_range(-5, 5), 0, _rng.randf_range(-5, 5))
				return
			b["hex"] = ids[_rng.randi() % ids.size()]
			b["target"] = _random_in(int(b["hex"]))
			b["state"] = "go"


func _arrive(b: Dictionary) -> void:
	match str(b["role"]):
		"clean":
			b["state"] = "work"
			b["work_t"] = _rng.randf_range(9.0, 15.0)
		"haul":
			if b["carry"] != null:
				var c: Node3D = b["carry"]
				b["carry"] = null
				var tw := c.create_tween()
				tw.tween_property(c, "scale", Vector3.ONE * 0.01, 0.5)
				tw.tween_callback(c.queue_free)
				b["state"] = "think"
				b["t"] = 0.8
			elif b.has("bale"):
				var bale: Dictionary = b["bale"]
				b.erase("bale")
				bales.erase(bale)
				var n: Node3D = bale["node"]
				n.reparent(b["node"] as Node3D, false)
				n.position = Vector3(0, 0.55, -0.75)
				n.rotation = Vector3.ZERO
				b["carry"] = n
				b["state"] = "think"
				b["t"] = 0.4
			else:
				b["state"] = "think"
		"water":
			b["state"] = "work"
			b["work_t"] = 3.2
			(b["spray"] as CPUParticles3D).emitting = true
		"plant":
			b["state"] = "work"
			b["work_t"] = 2.6
		_:
			b["state"] = "think"


func _finish_work(b: Dictionary) -> void:
	var vis: RobotVisual = b["node"]
	match str(b["role"]):
		"clean":
			vis.beam_to(null)
			if bales.size() < 12:
				var n := MeshInstance3D.new()
				n.mesh = _bale_mesh
				n.material_override = _bale_mat
				n.position = vis.position + vis.basis.z * 0.9 + Vector3(0, 0.3, 0)
				add_child(n)
				bales.append({"node": n, "claimed": false})
		"water":
			(b["spray"] as CPUParticles3D).emitting = false
		"plant":
			_add_sprout(vis.position - vis.basis.z * 0.7)
	b["state"] = "think"
	b["t"] = _rng.randf_range(0.3, 1.2)


func _process(delta: float) -> void:
	if bots.is_empty() and _rate <= 0.0:
		return
	var dt: float = delta * boost
	# Live progress at the remote rate (the boost from a care package doubles it).
	if _rate > 0.0:
		var before: Array[int] = _junk_order()
		var du: float = _rate * delta * boost
		_live_units += du
		var flipped: bool = false
		for i: int in before:
			var need: float = (1.0 - prog[i]) * RemoteProgress.AVG_HEX_UNITS
			var take: float = minf(du, need)
			prog[i] += take / RemoteProgress.AVG_HEX_UNITS
			du -= take
			if prog[i] >= 0.999:
				state[i] = 1
				flipped = true
			if du <= 0.0:
				break
		_pile_t += delta
		if _pile_t > 0.5 or flipped:
			_pile_t = 0.0
			_refresh_piles()
		if flipped:
			_ground_mat.albedo_texture = _bake_ground()
	for b: Dictionary in bots:
		var vis: RobotVisual = b["node"]
		var speed: float = 0.0
		match str(b["state"]):
			"think":
				b["t"] = float(b["t"]) - dt
				if float(b["t"]) <= 0.0:
					_pick_job(b)
			"go", "idle":
				var to: Vector3 = (b["target"] as Vector3) - vis.position
				to.y = 0.0
				var d: float = to.length()
				if d < 0.35:
					if str(b["state"]) == "idle":
						b["state"] = "think"
						b["t"] = _rng.randf_range(2.0, 4.0)
					else:
						_arrive(b)
				else:
					var step: float = minf(d, BOT_SPEED * (0.5 if str(b["state"]) == "idle" else 1.0) * dt)
					vis.position += to / d * step
					var yaw: float = atan2(-to.x, -to.z)
					vis.rotation.y = lerp_angle(vis.rotation.y, yaw, clampf(dt * 6.0, 0.0, 1.0))
					speed = step / maxf(dt, 0.0001)
			"work":
				b["work_t"] = float(b["work_t"]) - dt
				if str(b["role"]) == "clean":
					var h: int = int(b["hex"])
					if h >= 0 and state[h] == 0:
						vis.beam_to(vis.position - vis.basis.z * 1.6 + Vector3(0, 0.2, 0))
					vis.rotation.y += sin(float(b["work_t"]) * 2.0) * dt * 0.4
				if float(b["work_t"]) <= 0.0:
					_finish_work(b)
		vis.animate(speed, str(b["state"]) == "work", dt)


var _pile_t: float = 0.0
