class_name TidewellEnv
extends Node3D
## [planet-tidewell] Tidewell, the Ocean World: drowned dredging rigs in an open sea.
## Shared planet-env contract (planet/planets/planet_envs.gd, data/planets.json "tidewell"):
##   dev_hub(planet)            the --planet-env dev hook loads a wild (non-city) hub
##   prepare_field(field)       before generate: the nets-and-buoys junk palette (biome set
##                              "tidewell") and the sea: every hex but the raft base, a ring-1
##                              sand crescent and a few small islands (field_water)
##   dress_view(view)           after generate, before FieldView.setup: floating junk gathers into
##                              trash rafts (post_generate); sandy ground layers, no hills horizon
##   apply(world, field, kind)  once the district scene is built: everything below
## The look (data: data/planets.json "tidewell" + planet/planets/tidewell/tidewell.json):
##   ocean.gdshader  one opaque sea from the base to the horizon (swell, foam, depth colour,
##                   seabed with caustics, kelp and coral when restored, fish/whale shadows, oil
##                   slicks that clear to turquoise hex by hex), replacing WaterView's lake plane
##   islands         heightfield isles, sandbars and reefs (baked into the bed maps the sea reads)
##   landmarks       the Ledger's rusted jack-up dredging rigs and a half-sunk mining barge, the
##                   tops of drowned towers, channel buoys, moorings round the raft base
##   restored        mangroves and palms on the isles, floating gardens, lighthouses with thin
##                   turning beams, clear lagoons; futuristic: white sea platforms, floating
##                   solar rafts, light buoys with hair-thin light
##   TideHover       Lumi floats: bob, wake ring, spray, reflection; skimmers leave wakes
##   TideSuns        the binary star (two lights, two glints on the sea)
## Stages: ruin (base 1, little cleaned) -> restored (base 2-3 or 35% cleaned) -> future (4-5).

const DIR := "res://planet/planets/tidewell/"
const NEAR_SIZE: float = 320.0
const NEAR_RES: int = 320
const FAR_SIZE: float = 2600.0
const FAR_RES: int = 256
const SEA_Y: float = HexField.WATER_Y

const RUST := Color(0.45, 0.24, 0.13)
const LEDGER := Color(0.86, 0.62, 0.16)
const WHITE := Color(0.93, 0.95, 0.96)
const LIGHT := Color(0.68, 0.92, 1.0)

static var _data: Dictionary = {}
static var _pending: HexField = null  # the field between prepare_field and dress_view

var world: Node
var field: HexField
var kind: Dictionary = {}
var level: int = 1
var restore: float = 0.0
var stage: int = 0

var ocean: MeshInstance3D
var ocean_mat: ShaderMaterial
var hover: TideHover
var suns: TideSuns
var islands: Array[Dictionary] = []

var _groups: Dictionary = {}
var _mats: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _bed_noise := FastNoiseLite.new()
var _near_img: Image
var _isle_mat: ShaderMaterial
var _rafts: MultiMesh
var _raft_hex := PackedInt32Array()
var _beams: Array[Node3D] = []
var _lamps: Array[StandardMaterial3D] = []
var _fish: Array[Dictionary] = []
var _tick: float = 0.0
var _t: float = 0.0
var _grade_ruin: Dictionary = {}
var _grade_clean: Dictionary = {}
var _field_edge: float = 48.0


# --- Static hooks ----------------------------------------------------------------------------

static func data() -> Dictionary:
	if _data.is_empty():
		_data = Economy.read_json(DIR + "tidewell.json")
	return _data


## Before the field is generated: register the junk palette under the district's biome id.
static func prepare(kind_: Dictionary) -> void:
	var bid: String = str(kind_.get("district", {}).get("biome", "tidewell"))
	Economy.biome_sets[bid] = data().get("biome_set", {})


static func entry() -> Dictionary:
	var e: Variant = (Economy.read_json("res://data/planets.json") as Dictionary).get("tidewell", {})
	return e if e is Dictionary else {}


## Dev hook: a wild hub (no streets; frontier hubs skipped), on the coast if there is one.
static func dev_hub(planet: PlanetData) -> int:
	var skip: Array = planet.frontier_hubs.values()
	var best: int = -1
	for i: int in planet.hubs.size():
		var c: int = planet.hubs[i]
		if i in skip or planet.city[c] >= 0:
			continue
		var b: String = str(PlanetData.BIOMES[planet.biome[c]])
		if b == "neon_coast":
			return i
		if best < 0 and not (b in ["frostcap", "dust_dunes"]):
			best = i
	return maxi(best, 0)


## Shared contract, before HexField.generate: junk palette, floating-junk density, the sea.
static func prepare_field(f: HexField) -> void:
	var e: Dictionary = entry()
	prepare(e)
	var d: Dictionary = e.get("district", {})
	f.biome = str(d.get("biome", "tidewell"))
	f.biome_set = Economy.biome_set(f.biome)
	f.float_mult = float(d.get("float_mult", 2.0))
	var w: Dictionary = field_water(f, e)
	for k: Variant in w:
		f.water_ids[k] = true
	_pending = f


## Shared contract, before FieldView.setup (the field is generated): trash rafts, ground look.
static func dress_view(view: FieldView) -> void:
	var e: Dictionary = entry()
	var d: Dictionary = e.get("district", {})
	if _pending:
		post_generate(_pending, e)
		_pending = null
	view.layer_swap = d.get("ground_layers", {})
	var fx: Array = d.get("fx", [0, 0, 0, 0])
	view.ground_fx = Vector4(float(fx[0]), float(fx[1]), float(fx[2]), float(fx[3]))
	view.skip_horizon = true


## Sea hexes (spiral index -> true). Dry: the base (ring 0), a crescent of ring 1 and the
## islands in data "land". Deterministic per field seed.
static func field_water(f: HexField, _kind: Dictionary) -> Dictionary:
	var land: Dictionary = land_hexes(f.radius, f.seed_value)
	var out: Dictionary = {}
	var sp: Array[Vector2i] = Hex.spiral(f.radius)
	for i: int in sp.size():
		if Hex.distance(sp[i], Vector2i.ZERO) >= 1 and not land.has(sp[i]):
			out[i] = true
	return out


## Axial coords of the dry hexes (besides the base).
static func land_hexes(radius: int, seed_v: int) -> Dictionary:
	var cfg: Dictionary = data().get("land", {})
	var r := RandomNumberGenerator.new()
	r.seed = seed_v * 31 + 1717
	var out: Dictionary = {}
	var ring1: Array[Vector2i] = _ring(1)
	var start: int = r.randi() % 6
	for k: int in int(cfg.get("ring1", 3)):
		out[ring1[(start + k) % 6]] = true
	for spec: Variant in cfg.get("islands", []):
		var ring_n: int = mini(int(spec[0]), radius)
		var n: int = int(spec[1])
		var cand: Array[Vector2i] = _ring(ring_n)
		for tries: int in 24:
			var a: Vector2i = cand[r.randi() % cand.size()]
			var near_land: bool = false
			for nb: Vector2i in Hex.neighbors(a):
				if out.has(nb):
					near_land = true
			if out.has(a) or near_land:
				continue
			out[a] = true
			if n > 1:
				var nbs: Array[Vector2i] = Hex.neighbors(a)
				for j: int in nbs.size():
					var b: Vector2i = nbs[(j + r.randi()) % nbs.size()]
					if Hex.distance(b, Vector2i.ZERO) <= radius and Hex.distance(b, Vector2i.ZERO) >= 2 and not out.has(b):
						out[b] = true
						break
			break
	return out


static func _ring(n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for a: Vector2i in Hex.spiral(n):
		if Hex.distance(a, Vector2i.ZERO) == n:
			out.append(a)
	# Angular order so "contiguous" picks make a crescent.
	out.sort_custom(func(p: Vector2i, q: Vector2i) -> bool:
		var wp: Vector2 = Hex.axial_to_world(p, 1.0)
		var wq: Vector2 = Hex.axial_to_world(q, 1.0)
		return atan2(wp.y, wp.x) < atan2(wq.y, wq.x))
	return out


## Trash rafts and the nets-and-buoys palette on floating junk. Positions, models and poses
## only (types and volumes are kept): cubes and saves (alive bits by piece slot) are unchanged.
static func post_generate(f: HexField, _kind: Dictionary) -> void:
	var cfg: Dictionary = data().get("floaters", {})
	var pools: Dictionary = cfg.get("pools", {})
	var lying: Array = cfg.get("lying", [])
	for id: int in f.hex_count():
		if not f.is_water(id):
			continue
		var cs: Array[Vector3] = raft_centres(f, id)
		var r := RandomNumberGenerator.new()
		r.seed = hash([f.seed_value, id, 991])
		for pid: int in f.hex_pieces[id]:
			var tid: String = Economy.junk_ids[f.piece_type[pid]] if f.piece_type[pid] < Economy.junk_ids.size() else ""
			# plastic_crate_01's lite mesh does not decimate (10k tris): never float thousands of them.
			var force: bool = f.piece_model[pid] in (cfg.get("never", []) as Array)
			if (force or r.randf() < float(cfg.get("swap", 0.5))) and pools.has(tid):
				var pool: Array = pools[tid]
				var m: String = str(pool[r.randi() % pool.size()])
				if AssetLib.has_model(m):
					f.piece_model[pid] = m
					f.piece_pose[pid] = 1 if m in lying else 0
			if not cs.is_empty() and r.randf() < float(cfg.get("raft_frac", 0.5)):
				var c: Vector3 = cs[r.randi() % cs.size()]
				var rr: Array = cfg.get("raft_r", [2.2, 3.6])
				var ang: float = r.randf() * TAU
				var d: float = sqrt(r.randf()) * float(rr[1]) * 0.85
				var np := Vector3(c.x + cos(ang) * d, f.piece_pos[pid].y, c.z + sin(ang) * d)
				if f.hex_at(np) == id:
					f.piece_pos[pid] = np


## Where a water hex's trash rafts float (deterministic; shared by post_generate and the view).
static func raft_centres(f: HexField, id: int) -> Array[Vector3]:
	var cfg: Dictionary = data().get("floaters", {})
	var n_rng: Array = cfg.get("rafts_per_hex", [1, 3])
	var r := RandomNumberGenerator.new()
	r.seed = hash([f.seed_value, id, 4242])
	var out: Array[Vector3] = []
	var c: Vector3 = f.hex_center(id)
	for k: int in r.randi_range(int(n_rng[0]), int(n_rng[1])):
		var p := c + Vector3(r.randf_range(-0.55, 0.55), 0.0, r.randf_range(-0.55, 0.55)) * f.hex_size
		if f.hex_at(p) == id:
			out.append(p)
	return out


## Entry point (brief): builds the planet's look on a district that was made with the hooks above.
static func apply(p_world: Node, p_field: HexField, p_kind: Dictionary) -> TidewellEnv:
	var old: Node = p_world.get_node_or_null("TidewellEnv")
	if old:
		old.free()
	var env := TidewellEnv.new()
	env.name = "TidewellEnv"
	p_world.add_child(env)
	env.build(p_world, p_field, p_kind)
	return env


# --- Build -----------------------------------------------------------------------------------

func build(p_world: Node, p_field: HexField, p_kind: Dictionary) -> void:
	var t0: int = Time.get_ticks_msec()
	world = p_world
	field = p_field
	kind = p_kind
	_rng.seed = field.seed_value + 9090
	level = int(world.hub.level) if world.get("hub") != null else 1
	_field_edge = (field.radius + 0.6) * field.hex_size * 1.5
	_bed_noise.seed = field.seed_value + 33
	_bed_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_bed_noise.frequency = 0.006
	_bed_noise.fractal_octaves = 3
	for g: String in ["always", "ruin", "green", "mid", "future"]:
		var n := Node3D.new()
		n.name = g.capitalize()
		add_child(n)
		_groups[g] = n
	_dev_clean_water()
	_plan_islands()
	_build_ocean()
	_build_islands()
	_build_rigs()
	_build_barge()
	_build_towers()
	_build_buoys()
	_build_base_moorings()
	_build_lighthouses()
	_build_gardens()
	_build_future()
	_build_flotsam()
	_build_rafts()
	_setup_sky()
	_weather_junk()
	hover = TideHover.new()
	hover.name = "TideHover"
	hover.ocean_mat = ocean_mat
	hover.reflections = Settings.quality >= Settings.Quality.LOW
	hover.mirror_base = {"near_tex": ocean_mat.get_shader_parameter("near_tex"), "near_size": NEAR_SIZE, "state_tex": ocean_mat.get_shader_parameter("state_tex"), "grid_radius": field.radius, "hex_size": field.hex_size, "sea_y": SEA_Y, "water_col": Color(0.1, 0.42, 0.46)}
	add_child(hover)
	hover.setup(world)
	_spawn_fish()
	_open_camera()
	if DevHooks.has("tide-cam"):  # now, and again after the landing / intro placement settles
		_dev_cam.call_deferred()
		for d: float in [1.0, 3.0, 6.0]:
			get_tree().create_timer(d, false).timeout.connect(_dev_cam)
	world.set_meta("hover_water", true)  # Lumi floats over water here (player/patch.gd: no wading slowdown)
	if world.get("hub") != null:
		world.hub.level_changed.connect(func(l: int) -> void:
			level = l
			_refresh(true))
	EventBus.hex_cleaned.connect(_on_hex_cleaned)
	_measure()
	restore = _target_restore()
	_refresh(false)
	var counts: Array[String] = []
	for g: String in _groups:
		counts.append("%s=%d" % [g, (_groups[g] as Node).find_children("*", "GeometryInstance3D", true, false).size()])
	print("[planet-tidewell] env built in %d ms: level %d restore %.2f stage %d islands=%d %s" % [Time.get_ticks_msec() - t0, level, restore, stage, islands.size(), " ".join(counts)])


func _process(delta: float) -> void:
	_t += delta
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		var want: float = _target_restore()
		restore = move_toward(restore, want, 0.05)
		_apply_restore()
	if ocean_mat:
		var v: Node = world.get("view")
		if v:
			ocean_mat.set_shader_parameter("time_now", float(v.get("clock")))
		ocean_mat.set_shader_parameter("clarity_bonus", Economy.stat("lake_clarity") if Economy.has_method("stat") else 0.0)
	for b: Node3D in _beams:
		if b.is_visible_in_tree():
			b.rotation.y += delta * 0.6
	_update_fish(delta)


func _measure() -> void:
	pass


## Dev: --tide-clean (or a --future preview) skims every water hex clean (restored-look shots).
func _dev_clean_water() -> void:
	if not (DevHooks.has("tide-clean") or DevHooks.has("future")):
		return
	var view: Node = world.get("view")
	for pid: int in field.piece_count():
		var h: int = field.piece_hex[pid]
		if field.piece_alive[pid] == 1 and field.is_water(h):
			field.remove_piece(pid)
			if view:
				view.call("hide_piece", pid)
	for h: int in field.hex_count():
		if not field.is_water(h):
			continue
		if field.hex_clean[h] == 0:  # (remove_piece may already have flipped it)
			field.hex_clean[h] = 1
			field.cleaned_count += 1
		if view:
			view.call("refresh_hex", h, false)


## Open sea to the horizon: a long far plane, and the far blur only far out.
func _open_camera() -> void:
	var rig: Node = world.get("cam")
	var cam: Camera3D = rig.get("camera") if rig else null
	if cam == null:
		return
	cam.far = 2600.0
	var attrs: CameraAttributesPractical = cam.attributes as CameraAttributesPractical
	if attrs:
		attrs.dof_blur_far_distance = 300.0
		attrs.dof_blur_far_transition = 500.0
		attrs.dof_blur_amount = 0.03


## Dev: --tide-cam=dist,pitch,yaw[,fov] for landscape screenshots (like --frontier-cam).
func _dev_cam() -> void:
	if not DevHooks.has("tide-cam"):
		return
	var c: PackedStringArray = DevHooks.get_s("tide-cam", "30,-0.3,0").split(",")
	var pt: Node3D = world.get("patch")
	if DevHooks.has("tide-water") and pt and not has_meta("placed"):  # Lumi hovering on open water
		set_meta("placed", true)
		for h: int in field.hex_count():
			if field.is_water(h) and Hex.distance(field.hex_axial[h], Vector2i.ZERO) == 2:
				pt.global_position = field.hex_center(h) + Vector3(0, 0.3, 0)
				break
	var cam: Node = world.get("cam")
	if cam == null:
		return
	cam.set("max_distance", maxf(float(cam.get("max_distance")), float(c[0])))
	cam.set("distance", float(c[0]))
	cam.set("pitch", float(c[1]) if c.size() > 1 else -0.3)
	if c.size() > 2:
		cam.set("yaw", float(c[2]))
	var arm: Variant = cam.get("_arm")
	if arm is SpringArm3D:
		(arm as SpringArm3D).collision_mask = 0
	if c.size() > 3:
		Settings.fov = float(c[3])
		(cam.get("camera") as Camera3D).fov = Settings.fov
	cam.call("snap")
	var hud: Variant = world.get("hud")
	if hud is Object and "visible" in hud:
		(hud as Object).set("visible", false)


## 0 ruined .. 1 restored: cleaned share of the district and the base level.
func _target_restore() -> float:
	var total: int = maxi(field.junk_hex_count, 1)
	var cf: float = clampf(float(field.cleaned_count) / total, 0.0, 1.0)
	return clampf(cf * 0.65 + float(level - 1) / 4.0 * 0.5, 0.0, 1.0)


func _stage() -> int:
	if level >= int(data().get("stages", {}).get("future_level", 4)):
		return 2
	if level >= 2 or restore >= float(data().get("stages", {}).get("restored_at", 0.35)):
		return 1
	return 0


func _refresh(animate: bool) -> void:
	var s: int = _stage()
	var vis: Dictionary = {"always": true, "ruin": s == 0, "green": s >= 1, "mid": s == 1, "future": s == 2}
	for g: String in _groups:
		var node: Node3D = _groups[g]
		var want: bool = vis[g]
		if want and not node.visible and animate:
			node.scale = Vector3(1, 0.02, 1)
			node.create_tween().tween_property(node, "scale", Vector3.ONE, 1.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		node.visible = want
	stage = s
	_apply_restore()


func _apply_restore() -> void:
	if _stage() != stage:
		_refresh(true)
		return
	if ocean_mat:
		ocean_mat.set_shader_parameter("restore", restore)
		ocean_mat.set_shader_parameter("future", 1.0 if stage == 2 else 0.0)
	if _isle_mat:
		_isle_mat.set_shader_parameter("restore", clampf(restore * 1.3, 0.0, 1.0))
	var sd: Node = world.get("sky_director")
	if sd and not _grade_ruin.is_empty():
		sd.set("grade", _blend_grade(_grade_ruin, _grade_clean, smoothstep(0.1, 0.8, restore)))
		sd.set("grade_amt", 1.0)
	for m: StandardMaterial3D in _lamps:
		m.emission_energy_multiplier = 1.2 if stage == 2 else 0.8


func _on_hex_cleaned(hid: int, _pos: Vector3, _bonus: Variant) -> void:
	if _rafts == null:
		return
	for i: int in _raft_hex.size():
		if _raft_hex[i] == hid:
			var xf: Transform3D = _rafts.get_instance_transform(i)
			create_tween().tween_method(func(k: float) -> void:
				_rafts.set_instance_transform(i, Transform3D(xf.basis.scaled(Vector3.ONE * maxf(k, 0.001)), xf.origin)), 1.0, 0.0, 1.6)


# --- Bed map and islands ----------------------------------------------------------------------

func _plan_islands() -> void:
	var cfg: Dictionary = data().get("islands", {})
	var near: Array = cfg.get("near", [75, 260])
	var far: Array = cfg.get("far", [420, 900])
	var tries: int = 0
	var want: int = int(cfg.get("count", 9))
	while islands.size() < want and tries < 300:
		tries += 1
		var ang: float = _rng.randf() * TAU
		var dist: float = _rng.randf_range(float(near[0]), float(near[1]))
		var k: String = ["isle", "isle", "bar", "reef", "isle", "bar"][islands.size() % 6]
		var rad: float = {"isle": _rng.randf_range(14.0, 32.0), "bar": _rng.randf_range(16.0, 34.0), "reef": _rng.randf_range(18.0, 30.0)}[k]
		var c := Vector2(cos(ang), sin(ang)) * dist
		if _clashes(c, rad):
			continue
		var peak: float = {"isle": _rng.randf_range(3.0, 9.0), "bar": _rng.randf_range(0.25, 0.5), "reef": -0.9}[k]
		islands.append({"c": c, "r": rad, "h": peak, "kind": k, "yaw": _rng.randf() * TAU, "stretch": 1.0 if k == "isle" else 2.4})
	for i: int in int(cfg.get("far_count", 5)):
		var ang2: float = TAU * (float(i) + _rng.randf_range(0.1, 0.8)) / float(cfg.get("far_count", 5))
		var c2 := Vector2(cos(ang2), sin(ang2)) * _rng.randf_range(float(far[0]), float(far[1]))
		var r2: float = _rng.randf_range(50.0, 120.0)
		islands.append({"c": c2, "r": r2, "h": _rng.randf_range(16.0, 42.0), "kind": "isle", "yaw": _rng.randf() * TAU, "stretch": _rng.randf_range(1.0, 1.8), "far": true})


func _clashes(c: Vector2, rad: float) -> bool:
	if c.length() - rad * 1.6 < _field_edge + 12.0:
		return true
	for o: Dictionary in islands:
		if c.distance_to(o["c"]) < (float(o["r"]) + rad) * 1.5:
			return true
	return false


## Seabed / land height in metres at (x, z) and the reef mask (coral zones).
func bed_at(x: float, z: float) -> Vector2:
	var p := Vector2(x, z)
	var r: float = p.length()
	var h: float = -9.5 + _bed_noise.get_noise_2d(x, z) * 3.0
	# The raft base sits on a shallow bank that drops off past the field.
	var bank: float = 1.0 - smoothstep(_field_edge + 6.0, _field_edge + 55.0, r)
	h = lerpf(h, -2.6 + _bed_noise.get_noise_2d(x * 3.0, z * 3.0) * 0.8, bank)
	var reef: float = 0.0
	for isl: Dictionary in islands:
		var c: Vector2 = isl["c"]
		var rad: float = isl["r"]
		var dv: Vector2 = p - c
		if absf(dv.x) > rad * 3.0 or absf(dv.y) > rad * 3.0:
			continue
		var cy: float = cos(float(isl["yaw"]))
		var sy: float = sin(float(isl["yaw"]))
		var lv := Vector2(cy * dv.x + sy * dv.y, -sy * dv.x + cy * dv.y)
		lv.x /= float(isl["stretch"])
		var d: float = lv.length() / rad
		# Eroded outline: two octaves of wander, plus coves cut by a ridged term.
		d += _bed_noise.get_noise_2d(x * 4.0, z * 4.0) * 0.24 + _bed_noise.get_noise_2d(x * 13.0, z * 13.0) * 0.07
		d += maxf(0.0, 0.5 - absf(_bed_noise.get_noise_2d(x * 2.2 + 300.0, z * 2.2))) * 0.25
		var s: float = clampf(1.0 - d, 0.0, 1.0)
		var peak: float = isl["h"]
		var hi: float
		match str(isl["kind"]):
			"bar":
				hi = lerpf(-3.5, peak, pow(s, 0.6))
			"reef":
				hi = lerpf(-4.0, peak, pow(s, 0.5))
				reef = maxf(reef, smoothstep(0.0, 0.3, s))
			_:
				# Rocky relief: ridged outcrops and gullies on the slopes, a terrace above the beach.
				var ridge: float = 1.0 - absf(_bed_noise.get_noise_2d(x * 7.0 + 50.0, z * 7.0))
				hi = lerpf(-4.0, peak, pow(s, 1.3)) + (smoothstep(0.55, 0.75, s) * 0.6 if peak > 2.0 else 0.0)
				hi += (ridge - 0.55) * peak * 0.35 * smoothstep(0.15, 0.6, s)
				reef = maxf(reef, exp(-pow((d - 1.15) / 0.3, 2.0)) * (0.0 if isl.get("far", false) else 1.0))
		h = maxf(h, hi)
	return Vector2(h, reef)


## Near map: the field (warped land hexes are dry ground, water hexes a shallow lagoon) and the
## sea round it; far map: the archipelago to the horizon. R = height, G = reef.
func _bake(size: float, res: int, with_field: bool) -> ImageTexture:
	var img := Image.create(res, res, false, Image.FORMAT_RGH)  # half float: linear filtering everywhere (RG32F is not filterable on some GPUs)
	for y: int in res:
		for x: int in res:
			var wx: float = (float(x) + 0.5) / res * size - size * 0.5
			var wz: float = (float(y) + 0.5) / res * size - size * 0.5
			var v: Vector2 = bed_at(wx, wz)
			if with_field and Vector2(wx, wz).length() < _field_edge + 12.0:
				var pw: Vector3 = Vector3(wx, 0, wz)
				if field.natural_borders:
					pw += field.border_warp(pw)
				var hid: int = field.hex_at(pw)
				if hid >= 0:
					if field.is_water(hid):
						v.x = minf(v.x, -2.4 - _bed_noise.get_noise_2d(wx * 5.0, wz * 5.0) * 0.6)
					else:
						v.x = 0.5
			img.set_pixel(x, y, Color(v.x, v.y, 0.0))
	if with_field:
		# A soft shore slope around dry hexes (shallows and foam hug the land).
		var small: Image = img.duplicate()
		small.resize(res / 3, res / 3, Image.INTERPOLATE_BILINEAR)
		small.resize(res, res, Image.INTERPOLATE_CUBIC)
		for y: int in res:
			for x: int in res:
				var a: Color = img.get_pixel(x, y)
				var b: Color = small.get_pixel(x, y)
				# Keep dry land dry; water near land takes the softened (shallower) height.
				var hgt: float = a.r if a.r > 0.3 else maxf(a.r, minf(b.r, 0.05))
				img.set_pixel(x, y, Color(hgt, a.g, 0.0))
		_near_img = img
	return ImageTexture.create_from_image(img)


func _build_ocean() -> void:
	var wv: Node = world.get("water")
	var view: Node = world.get("view")
	ocean_mat = ShaderMaterial.new()
	ocean_mat.shader = preload(DIR + "ocean.gdshader")
	ocean_mat.set_shader_parameter("state_tex", view.call("state_texture"))
	ocean_mat.set_shader_parameter("wave_nrm", AssetLib.tex("rubble", "nor_gl"))
	ocean_mat.set_shader_parameter("grid_radius", field.radius)
	ocean_mat.set_shader_parameter("hex_size", field.hex_size)
	ocean_mat.set_shader_parameter("sea_y", SEA_Y)
	ocean_mat.set_shader_parameter("field_r", _field_edge)
	ocean_mat.set_shader_parameter("detail", 1.0 if Settings.quality >= Settings.Quality.MEDIUM else 0.6)
	var pal: Dictionary = kind.get("palette", {})
	for pair: Array in [["deep_col", "deep"], ["shallow_col", "shallow"], ["lagoon_col", "lagoon"], ["murky_col", "murky"], ["oil_col", "oil"], ["sand_col", "sand"]]:
		var c: Array = pal.get(pair[1], [])
		if c.size() >= 3:
			ocean_mat.set_shader_parameter(pair[0], Color(float(c[0]), float(c[1]), float(c[2])))
	var gm: ShaderMaterial = view.get("ground_material") if view else null
	if gm and field.natural_borders:
		for k: String in ["warp_tex", "warp_size", "warp_amp"]:
			ocean_mat.set_shader_parameter(k, gm.get_shader_parameter(k))
		gm.set_shader_parameter("lake_warp", 1.0)
	ocean_mat.set_shader_parameter("near_tex", _bake(NEAR_SIZE, NEAR_RES, true))
	ocean_mat.set_shader_parameter("near_size", NEAR_SIZE)
	ocean_mat.set_shader_parameter("far_tex", _bake(FAR_SIZE, FAR_RES, false))
	ocean_mat.set_shader_parameter("far_size", FAR_SIZE)
	ocean_mat.set_shader_parameter("debug_view", int(DevHooks.get_f("tide-debug-view", 0.0)))
	ocean = MeshInstance3D.new()
	ocean.name = "Ocean"
	ocean.mesh = _polar_mesh(2400.0)
	ocean.material_override = ocean_mat
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ocean.position.y = SEA_Y
	ocean.extra_cull_margin = 2.0
	_groups["always"].add_child(ocean)
	# WaterView keeps its fish and its clean-lake moment; its lake plane is replaced by the sea.
	if wv:
		for c: Node in wv.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).mesh is PlaneMesh:
				(c as MeshInstance3D).visible = false


## Dense near the base, coarse to the horizon: rings of growing radius.
static func _polar_mesh(r_out: float) -> ArrayMesh:
	var rs := PackedFloat32Array([0.0])
	var r: float = 0.0
	while r < r_out:
		r += clampf(0.9 + r * 0.06, 0.9, 140.0)
		rs.append(minf(r, r_out))
	var segs: int = 144
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	st.add_vertex(Vector3.ZERO)
	for i: int in range(1, rs.size()):
		for j: int in segs:
			var a: float = TAU * float(j) / segs
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(cos(a) * rs[i], 0.0, sin(a) * rs[i]))
	for j: int in segs:
		st.add_index(0)
		st.add_index(1 + j)
		st.add_index(1 + (j + 1) % segs)
	for i: int in range(1, rs.size() - 1):
		var b0: int = 1 + (i - 1) * segs
		var b1: int = 1 + i * segs
		for j: int in segs:
			var j1: int = (j + 1) % segs
			for idx: int in [b0 + j, b1 + j, b0 + j1, b0 + j1, b1 + j, b1 + j1]:
				st.add_index(idx)
	var m: ArrayMesh = st.commit()
	m.custom_aabb = AABB(Vector3(-r_out, -2.0, -r_out), Vector3(r_out * 2.0, 4.0, r_out * 2.0))
	return m


func _build_islands() -> void:
	_isle_mat = ShaderMaterial.new()
	_isle_mat.shader = preload("res://art/shaders/terrain.gdshader")
	_isle_mat.set_shader_parameter("tex_a", AssetLib.tex("sand_01", "diff"))
	_isle_mat.set_shader_parameter("nrm_a", AssetLib.tex("sand_01", "nor_gl"))
	_isle_mat.set_shader_parameter("tex_b", AssetLib.tex("dry_ground_rocks", "diff"))
	_isle_mat.set_shader_parameter("nrm_b", AssetLib.tex("dry_ground_rocks", "nor_gl"))
	_isle_mat.set_shader_parameter("tex_g", AssetLib.tex("leafy_grass", "diff"))
	_isle_mat.set_shader_parameter("tint_a", Vector3(1.05, 1.0, 0.92))
	_isle_mat.set_shader_parameter("tint_b", Vector3(0.82, 0.8, 0.76))
	_isle_mat.set_shader_parameter("tint_g", Vector3(0.55, 0.78, 0.42))
	_isle_mat.set_shader_parameter("slope_lo", 0.28)
	_isle_mat.set_shader_parameter("slope_hi", 0.5)
	_isle_mat.set_shader_parameter("green_amt", 0.9)
	_isle_mat.set_shader_parameter("ripple", 0.3)
	_isle_mat.set_shader_parameter("macro", 0.14)
	for isl: Dictionary in islands:
		if str(isl["kind"]) == "reef":
			continue
		var far: bool = isl.get("far", false)
		var rad: float = float(isl["r"]) * float(isl["stretch"]) * 1.25
		var rings: int = 22 if far else 18
		var spokes: int = 56 if far else 48
		var c: Vector2 = isl["c"]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i: int in rings + 1:
			var rr: float = rad * pow(float(i) / rings, 0.85)
			for j: int in spokes:
				var a: float = TAU * float(j) / spokes
				var x: float = c.x + cos(a) * rr
				var z: float = c.y + sin(a) * rr
				st.add_vertex(Vector3(x, maxf(bed_at(x, z).x, -3.0), z))
		for i: int in rings:
			for j: int in spokes:
				var j1: int = (j + 1) % spokes
				var a0: int = i * spokes + j
				var a1: int = i * spokes + j1
				var b0: int = (i + 1) * spokes + j
				var b1: int = (i + 1) * spokes + j1
				for idx: int in [a0, b0, a1, a1, b0, b1]:
					st.add_index(idx)
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.name = "Isle"
		mi.mesh = st.commit()
		mi.material_override = _isle_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if far else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_groups["always"].add_child(mi)
	_dress_islands()


## Rocks on every isle; driftwood and junk while ruined; mangroves and palms once restored.
func _dress_islands() -> void:
	var rock_mat: StandardMaterial3D = AssetLib.pbr_material("dry_ground_rocks", 0.45, Color(0.7, 0.68, 0.62), true)
	rock_mat.metallic = 0.0
	var b_always := FrontierView.Batch.new()
	var b_ruin := FrontierView.Batch.new()
	var b_green := FrontierView.Batch.new()
	var trunk_m: Material = _mat("trunk")
	var leaf_m: Material = _mat("leaf")
	var mangrove_m: Material = _mat("mangrove")
	var dead_m: Material = _mat("driftwood")
	for isl: Dictionary in islands:
		if str(isl["kind"]) != "isle" or isl.get("far", false):
			continue
		var c: Vector2 = isl["c"]
		var rad: float = float(isl["r"])
		for k: int in 14:
			var a: float = _rng.randf() * TAU
			var d: float = rad * _rng.randf_range(0.6, 1.05)
			var p := Vector3(c.x + cos(a) * d, 0, c.y + sin(a) * d)
			p.y = bed_at(p.x, p.z).x - 0.2
			var s: float = _rng.randf_range(0.6, 2.2)
			b_always.add(_lumpy(k % 5, 0.42), FrontierView._xf(p, Vector3(_rng.randf() * 30, _rng.randf() * 360, 0), Vector3(s, s * 0.65, s * 1.25)), rock_mat)
		# Mangroves ring the shore, palms stand inland.
		for k: int in int(rad * 0.9):
			var a: float = TAU * float(k) / int(rad * 0.9) + _rng.randf() * 0.2
			var d: float = rad * _rng.randf_range(0.72, 0.9)
			var p := Vector3(c.x + cos(a) * d, 0, c.y + sin(a) * d)
			var gy: float = bed_at(p.x, p.z).x
			if gy < -0.6 or gy > 2.5:
				continue
			p.y = maxf(gy, SEA_Y - 0.4)
			_mangrove(b_green, p, _rng.randf_range(0.8, 1.4), trunk_m, mangrove_m)
		for k: int in int(rad * 0.35):
			var a: float = _rng.randf() * TAU
			var d: float = rad * _rng.randf_range(0.0, 0.55)
			var p := Vector3(c.x + cos(a) * d, 0, c.y + sin(a) * d)
			p.y = bed_at(p.x, p.z).x
			if p.y < 0.8:
				continue
			_palm(b_green, p, _rng.randf_range(5.0, 8.5), trunk_m, leaf_m)
			# Ruin: a dead snag and a heap of washed-up junk instead.
			_snag(b_ruin, p, dead_m)
	b_always.flush(_groups["always"])
	b_ruin.flush(_groups["ruin"])
	b_green.flush(_groups["green"])
	# Washed-up junk on the isles' beaches while ruined (real junk models, one MultiMesh each).
	var pts: Array[Transform3D] = []
	for isl: Dictionary in islands:
		if str(isl["kind"]) == "reef" or isl.get("far", false):
			continue
		var c: Vector2 = isl["c"]
		for k: int in 18:
			var a: float = _rng.randf() * TAU
			var d: float = float(isl["r"]) * float(isl["stretch"]) * _rng.randf_range(0.3, 0.95)
			var p := Vector3(c.x + cos(a) * d, 0, c.y + sin(a) * d)
			p.y = bed_at(p.x, p.z).x
			if p.y > SEA_Y:
				pts.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).rotated(Vector3.RIGHT, _rng.randf_range(-0.4, 0.4)), p))
	_scatter_models(["Barrel_01", "old_tyre", "wooden_crate_02", "lifebuoy", "plastic_jerrycan"], pts, _groups["ruin"], 260.0)


func _scatter_models(ids: Array, xfs: Array[Transform3D], parent: Node3D, vis_end: float) -> void:
	var by: Dictionary = {}
	for i: int in xfs.size():
		var id: String = str(ids[i % ids.size()])
		if not AssetLib.has_model(id):
			continue
		if not by.has(id):
			by[id] = []
		(by[id] as Array).append(xfs[i])
	for id: String in by:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = AssetLib.model_mesh_lite(id, 500)
		var arr: Array = by[id]
		mm.instance_count = arr.size()
		var aabb: AABB = AssetLib.model_aabb(id)
		for i: int in arr.size():
			var xf: Transform3D = arr[i]
			xf.origin.y -= aabb.position.y * 0.8
			mm.set_instance_transform(i, xf)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = vis_end
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)


func _palm(b: FrontierView.Batch, p: Vector3, h: float, trunk_m: Material, leaf_m: Material) -> void:
	var lean := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * h * 0.18
	var segs: int = 5
	var prev: Vector3 = p
	for i: int in segs:
		var t: float = float(i + 1) / segs
		var q: Vector3 = p + Vector3(0, h * t, 0) + lean * t * t
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.16
		cyl.bottom_radius = 0.22
		cyl.radial_segments = 6
		cyl.height = 1.0
		b.add(cyl, FrontierView._beam_xf(prev, q, 1.0), trunk_m)
		prev = q
	for k: int in 7:
		var a: float = TAU * k / 7.0 + _rng.randf() * 0.3
		var frond := BoxMesh.new()
		frond.size = Vector3(0.5, 0.04, 3.2)
		var dirv := Vector3(cos(a), 0, sin(a))
		var xf := Transform3D(Basis.looking_at(dirv, Vector3.UP).rotated(dirv.cross(Vector3.UP).normalized(), -0.35), prev + dirv * 1.4 + Vector3(0, -0.35, 0))
		b.add(frond, xf, leaf_m)


func _mangrove(b: FrontierView.Batch, p: Vector3, s: float, trunk_m: Material, leaf_m: Material) -> void:
	var top: Vector3 = p + Vector3(0, 1.6 * s, 0)
	for k: int in 5:
		var a: float = TAU * k / 5.0 + _rng.randf() * 0.5
		var foot: Vector3 = p + Vector3(cos(a), -0.3, sin(a)) * 1.1 * s
		var knee: Vector3 = p.lerp(foot, 0.5) + Vector3(0, 0.9 * s, 0)
		b.add(_twig(), FrontierView._beam_xf(foot, knee, 0.07 * s), trunk_m)
		b.add(_twig(), FrontierView._beam_xf(knee, top, 0.08 * s), trunk_m)
	for k: int in 4:
		var o := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.2, 0.9), _rng.randf_range(-1, 1)) * s
		var r: float = _rng.randf_range(0.9, 1.5) * s
		b.add(_lumpy(5 + k % 3, 0.5, 2.6), FrontierView._xf(top + o, Vector3(0, _rng.randf() * 360.0, 0), Vector3(r * 1.2, r * 0.7, r * 1.2)), leaf_m)


func _snag(b: FrontierView.Batch, p: Vector3, m: Material) -> void:
	var h: float = _rng.randf_range(2.0, 4.0)
	var lean := Vector3(_rng.randf_range(-0.5, 0.5), 1.0, _rng.randf_range(-0.5, 0.5)).normalized()
	b.add(_twig(), FrontierView._beam_xf(p, p + lean * h, 0.14), m)
	b.add(_twig(), FrontierView._beam_xf(p + lean * h * 0.6, p + lean * h * 0.6 + Vector3(_rng.randf_range(-1, 1), 0.6, _rng.randf_range(-1, 1)), 0.07), m)


func _twig() -> CylinderMesh:
	if not _mats.has("_twig"):
		var c := CylinderMesh.new()
		c.top_radius = 0.7
		c.bottom_radius = 1.0
		c.radial_segments = 5
		c.rings = 1
		c.height = 1.0
		_mats["_twig"] = c
	return _mats["_twig"]


# --- Materials --------------------------------------------------------------------------------

func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	match key:
		"rust":
			m = Mats.worn_paint(LEDGER, 0.32, 0.9, 3.0, 0.8)
		"rust_dark":
			m = Mats.worn_paint(Color(0.3, 0.31, 0.32), 0.35, 0.85, 7.0, 0.8)
		"rust_red":
			m = Mats.worn_paint(Color(0.55, 0.16, 0.1), 0.5, 0.8, 11.0, 0.7)
		"hull":
			m = Mats.worn_paint(Color(0.2, 0.24, 0.26), 0.45, 0.85, 5.0, 0.9)
		"concrete":
			var c := AssetLib.pbr_material("dirty_concrete", 0.25, Color(0.78, 0.8, 0.78), true)
			m = c
		"window":
			m = Mats.glass(Color(0.04, 0.07, 0.08, 1.0), 0.15)
		"white":
			var s := StandardMaterial3D.new()
			s.albedo_color = WHITE
			s.roughness = 0.32
			s.metallic = 0.05
			m = s
		"lamp":
			var l := Mats.lamp(LIGHT, 1.0)
			_lamps.append(l)
			m = l
		"lamp_warm":
			var lw := Mats.lamp(Color(1.0, 0.86, 0.6), 1.6)
			m = lw
		"solar":
			var sp := StandardMaterial3D.new()
			sp.albedo_color = Color(0.05, 0.09, 0.18)
			sp.metallic = 0.4
			sp.roughness = 0.12
			m = sp
		"wood":
			var w := StandardMaterial3D.new()
			w.albedo_texture = AssetLib.tex("dry_decay_leaves", "diff")
			w.albedo_color = Color(0.56, 0.44, 0.32)
			w.uv1_triplanar = true
			w.uv1_scale = Vector3.ONE * 0.6
			w.roughness = 0.85
			m = w
		"trunk":
			var tr := StandardMaterial3D.new()
			tr.albedo_color = Color(0.36, 0.29, 0.22)
			tr.roughness = 0.9
			m = tr
		"driftwood":
			var dw := StandardMaterial3D.new()
			dw.albedo_color = Color(0.62, 0.6, 0.56)
			dw.roughness = 0.95
			m = dw
		"leaf":
			var lf := StandardMaterial3D.new()
			lf.albedo_color = Color(0.28, 0.5, 0.2)
			lf.roughness = 0.75
			lf.cull_mode = BaseMaterial3D.CULL_DISABLED
			m = lf
		"mangrove":
			var mg := StandardMaterial3D.new()
			mg.albedo_texture = AssetLib.tex("leafy_grass", "diff")
			mg.albedo_color = Color(0.55, 0.8, 0.5)
			mg.uv1_triplanar = true
			mg.uv1_scale = Vector3.ONE * 0.7
			mg.roughness = 0.8
			m = mg
		"pontoon":
			m = Mats.worn_paint(Color(0.85, 0.42, 0.14), 0.7, 0.6, 9.0, 0.7)
		"buoy_red":
			m = Mats.worn_paint(Color(0.75, 0.15, 0.1), 0.75, 0.5, 13.0, 0.5)
		"garden":
			var gd := StandardMaterial3D.new()
			gd.albedo_texture = AssetLib.tex("leafy_grass", "diff")
			gd.albedo_color = Color(0.7, 0.95, 0.6)
			gd.uv1_triplanar = true
			gd.roughness = 0.8
			m = gd
		_:
			m = StandardMaterial3D.new()
	_mats[key] = m
	return m


## An eroded lump: a sphere pushed in and out by 3D noise (rocks, canopies, coral heads), with
## smooth normals. A few variants are cached and reused with random scale/rotation.
func _lumpy(variant: int, amp: float = 0.35, freq: float = 1.6) -> ArrayMesh:
	var key: String = "_lumpy_%d_%.2f_%.2f" % [variant, amp, freq]
	if _mats.has(key):
		return _mats[key]
	var nz := FastNoiseLite.new()
	nz.seed = 7000 + variant * 31
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.frequency = freq * 0.5
	nz.fractal_octaves = 4
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: int = 9
	var segs: int = 14
	for i: int in rings + 1:
		var v: float = PI * float(i) / rings
		for j: int in segs + 1:
			var u: float = TAU * float(j % segs) / segs
			var d := Vector3(sin(v) * cos(u), cos(v), sin(v) * sin(u))
			var n: float = nz.get_noise_3d(d.x * 2.0, d.y * 2.0, d.z * 2.0)
			var ridged: float = 1.0 - absf(nz.get_noise_3d(d.x * 5.0 + 9.0, d.y * 5.0, d.z * 5.0))
			var r: float = 1.0 + n * amp + (ridged - 0.6) * amp * 0.35
			st.set_uv(Vector2(float(j) / segs, float(i) / rings))
			st.add_vertex(d * r)
	for i: int in rings:
		for j: int in segs:
			var a: int = i * (segs + 1) + j
			var b: int = a + segs + 1
			for idx: int in [a, b, a + 1, a + 1, b, b + 1]:
				st.add_index(idx)
	st.generate_normals()
	st.generate_tangents()
	var m: ArrayMesh = st.commit()
	_mats[key] = m
	return m


## A flat slab with a wandering, irregular outline (raft decks, garden mats, sea platforms):
## top at y = +h/2, a slight bevel, no perfect circles.
func _blob_slab(variant: int, wobble: float = 0.18, h: float = 1.0, lobes: int = 0) -> ArrayMesh:
	var key: String = "_slab_%d_%.2f_%.2f_%d" % [variant, wobble, h, lobes]
	if _mats.has(key):
		return _mats[key]
	var nz := FastNoiseLite.new()
	nz.seed = 9100 + variant * 17
	nz.frequency = 0.9
	var segs: int = 40
	var rim: Array[float] = []
	for j: int in segs:
		var a: float = TAU * j / segs
		var r: float = 1.0 + nz.get_noise_2d(cos(a) * 1.5, sin(a) * 1.5) * wobble
		if lobes > 0:
			r += 0.08 * cos(a * lobes)
		rim.append(r)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top: float = h * 0.5
	var c := Vector3(0, top, 0)
	for j: int in segs:
		var j1: int = (j + 1) % segs
		var a0: float = TAU * j / segs
		var a1: float = TAU * j1 / segs
		var p0 := Vector3(cos(a0) * rim[j], top, sin(a0) * rim[j])
		var p1 := Vector3(cos(a1) * rim[j1], top, sin(a1) * rim[j1])
		var i0 := Vector3(p0.x * 0.94, top, p0.z * 0.94)
		var i1 := Vector3(p1.x * 0.94, top, p1.z * 0.94)
		var b0 := Vector3(p0.x, -top, p0.z) * Vector3(0.96, 1, 0.96)
		var b1 := Vector3(p1.x, -top, p1.z) * Vector3(0.96, 1, 0.96)
		var e0 := Vector3(p0.x, top - h * 0.12, p0.z)
		var e1 := Vector3(p1.x, top - h * 0.12, p1.z)
		for v: Vector3 in [c, i1, i0, i0, i1, e1, i0, e1, e0, e0, e1, b1, e0, b1, b0]:
			st.set_uv(Vector2(v.x, v.z) * 0.5)
			st.add_vertex(v)
	st.generate_normals()
	var m: ArrayMesh = st.commit()
	_mats[key] = m
	return m


## Basis with a local (pre-rotation) scale.
static func _ls(b: Basis, s: Vector3) -> Basis:
	return b * Basis.from_scale(s)


func _box(b: FrontierView.Batch, pos: Vector3, size: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> void:
	if not _mats.has("_box"):
		_mats["_box"] = ProcMesh.rounded_box(Vector3.ONE, 0.07, 2)
	b.add(_mats["_box"], FrontierView._xf(pos, rot, size), mat)


func _cyl(b: FrontierView.Batch, a: Vector3, c: Vector3, r: float, mat: Material) -> void:
	if not _mats.has("_cyl"):
		var cm := CylinderMesh.new()
		cm.top_radius = 1.0
		cm.bottom_radius = 1.0
		cm.radial_segments = 10
		cm.rings = 1
		cm.height = 1.0
		_mats["_cyl"] = cm
	b.add(_mats["_cyl"], FrontierView._beam_xf(a, c, r), mat)


## A free spot on open water at distance [d0, d1] (clear of islands and the field).
func _sea_spot(d0: float, d1: float, clear: float) -> Vector3:
	for k: int in 80:
		var a: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(d0, d1)
		var p := Vector2(cos(a), sin(a)) * d
		var ok: bool = d - clear > _field_edge + 4.0
		for isl: Dictionary in islands:
			if p.distance_to(isl["c"]) < float(isl["r"]) * float(isl["stretch"]) * 1.3 + clear:
				ok = false
		if ok:
			return Vector3(p.x, SEA_Y, p.y)
	return Vector3(d1, SEA_Y, 0)


# --- Ledger landmarks -------------------------------------------------------------------------

## Jack-up dredging rigs: four lattice legs, a deck hull, a derrick, a crane and a bucket ladder
## dipping into the sea. Ruin: rust, a list, oil round the legs. Future: a white sea platform.
func _build_rigs() -> void:
	var always := FrontierView.Batch.new()
	var fut := FrontierView.Batch.new()
	var mid := FrontierView.Batch.new()
	if not _mats.has("_box"):
		_mats["_box"] = ProcMesh.rounded_box(Vector3.ONE, 0.07, 2)
	for i: int in 2:
		var p: Vector3 = _sea_spot(95.0 + i * 70.0, 150.0 + i * 90.0, 28.0)
		print("[planet-tidewell] dredging rig %d at (%.0f, %.0f)" % [i, p.x, p.z])
		var yaw: float = atan2(p.x, p.z) + _rng.randf_range(-0.5, 0.5)
		var basis := Basis(Vector3.UP, yaw)
		var list: float = deg_to_rad(_rng.randf_range(2.0, 5.0))
		basis = basis * Basis(Vector3.FORWARD, list)
		var o := Vector3(p.x, 0, p.z)
		var deck_y: float = 10.0 + i * 2.0
		var hw := Vector2(13.0, 10.0)
		var xf := func(v: Vector3) -> Vector3: return o + basis * v
		# Legs (triangular lattice towers) poking up above the deck.
		for lx: float in [-1.0, 1.0]:
			for lz: float in [-1.0, 1.0]:
				var base: Vector3 = Vector3(lx * hw.x, -8.0, lz * hw.y)
				var top: Vector3 = Vector3(lx * hw.x, deck_y + 14.0, lz * hw.y)
				for c: int in 3:
					var a: float = TAU * c / 3.0
					var off := Vector3(cos(a), 0, sin(a)) * 1.1
					_cyl(always, xf.call(base + off), xf.call(top + off), 0.18, _mat("rust"))
				var yv: float = -2.0
				while yv < deck_y + 13.0:
					for c: int in 3:
						var a0: float = TAU * c / 3.0
						var a1: float = TAU * (c + 1) / 3.0
						var p0 := Vector3(lx * hw.x, yv, lz * hw.y) + Vector3(cos(a0), 0, sin(a0)) * 1.1
						var p1 := Vector3(lx * hw.x, yv + 2.0, lz * hw.y) + Vector3(cos(a1), 0, sin(a1)) * 1.1
						_cyl(always, xf.call(p0), xf.call(p1), 0.06, _mat("rust"))
					yv += 2.0
		# Deck hull and its deckhouse.
		var hull_c := Vector3(0, deck_y, 0)
		always.add(_mats["_box"], Transform3D(_ls(basis, Vector3(hw.x * 2.0 + 4.0, 3.2, hw.y * 2.0 + 3.0)), xf.call(hull_c)), _mat("hull"))
		var house_c := Vector3(-hw.x * 0.45, deck_y + 4.0, -hw.y * 0.4)
		always.add(_mats["_box"], Transform3D(_ls(basis, Vector3(9.0, 5.0, 7.0)), xf.call(house_c)), _mat("rust_dark"))
		for wy: int in 2:
			always.add(_mats["_box"], Transform3D(_ls(basis, Vector3(9.1, 0.7, 5.0)), xf.call(house_c + Vector3(0, -0.8 + wy * 2.0, 0))), _mat("window"))
		# Derrick: a tapered lattice tower.
		var dc := Vector3(hw.x * 0.35, deck_y + 1.6, hw.y * 0.2)
		for c: int in 4:
			var a: float = TAU * c / 4.0 + PI * 0.25
			_cyl(always, xf.call(dc + Vector3(cos(a), 0, sin(a)) * 2.6), xf.call(dc + Vector3(0, 18.0, 0) + Vector3(cos(a), 0, sin(a)) * 0.5), 0.12, _mat("rust"))
		for k: int in 6:
			var y0: float = 2.0 + k * 2.8
			var r0: float = lerpf(2.6, 0.5, y0 / 18.0)
			var r1: float = lerpf(2.6, 0.5, (y0 + 2.8) / 18.0)
			for c: int in 4:
				var a0: float = TAU * c / 4.0 + PI * 0.25
				var a1: float = TAU * (c + 1) / 4.0 + PI * 0.25
				_cyl(always, xf.call(dc + Vector3(cos(a0) * r0, y0, sin(a0) * r0)), xf.call(dc + Vector3(cos(a1) * r1, y0 + 2.8, sin(a1) * r1)), 0.05, _mat("rust"))
		# Bucket ladder: an inclined boom into the sea with a chain of buckets.
		var lad_a := Vector3(hw.x + 1.0, deck_y + 2.0, 0)
		var lad_b := Vector3(hw.x + 16.0, -3.0, 2.0)
		_cyl(always, xf.call(lad_a), xf.call(lad_b), 0.55, _mat("rust_dark"))
		for k: int in 12:
			var t: float = float(k) / 11.0
			var bp: Vector3 = lad_a.lerp(lad_b, t) + Vector3(0, 0.9, 0)
			if bp.y < -0.5:
				continue
			always.add(_mats["_box"], Transform3D(_ls(basis, Vector3(1.3, 0.9, 1.6)), xf.call(bp)), _mat("rust"))
		# Crane: a pedestal and a jib.
		var cr := Vector3(-hw.x * 0.6, deck_y + 1.6, hw.y * 0.6)
		_cyl(always, xf.call(cr), xf.call(cr + Vector3(0, 5.0, 0)), 0.9, _mat("rust"))
		_cyl(always, xf.call(cr + Vector3(0, 5.0, 0)), xf.call(cr + Vector3(-14.0, 11.0, 6.0)), 0.35, _mat("rust"))
		# Ledger stencil on the deckhouse.
		var lbl: Label3D = Mats.stencil(tr("LEDGER  DREDGE %02d") % (7 + i * 4), 64, Color(0.92, 0.88, 0.78, 0.8))
		lbl.pixel_size = 0.03
		lbl.global_transform = Transform3D(basis, xf.call(house_c + Vector3(0, 1.3, 3.56)))
		_groups["always"].add_child(lbl)
		# Mid: patched and painted bands, work lights; future: white cladding with thin light seams.
		_box(mid, xf.call(hull_c + Vector3(0, 1.75, 0)), Vector3(hw.x * 2.0 + 4.2, 0.3, hw.y * 2.0 + 3.2), _mat("pontoon"))
		_box(fut, xf.call(hull_c), Vector3(hw.x * 2.0 + 4.3, 3.4, hw.y * 2.0 + 3.3), _mat("white"))
		_box(fut, xf.call(hull_c + Vector3(0, 1.75, 0)), Vector3(hw.x * 2.0 + 4.4, 0.06, hw.y * 2.0 + 3.4), _mat("lamp"))
		_box(fut, xf.call(house_c), Vector3(9.2, 5.1, 7.2), _mat("white"))
		_box(fut, xf.call(house_c + Vector3(0, 0.6, 0)), Vector3(9.3, 1.0, 5.4), _mat("window"))
		for k: int in 3:
			_box(fut, xf.call(dc + Vector3(1.2 + k * 1.6, 0.4, -6.0)), Vector3(1.2, 0.8, 4.0), _mat("solar"))
		# Ruin: an oil sheen spot beside the legs is drawn by the sea itself (slicks).
	always.flush(_groups["always"])
	mid.flush(_groups["mid"])
	fut.flush(_groups["future"])


## The half-sunk mining barge: a long hull rolled over and settling by the stern, ore hoppers,
## a conveyor boom pointing at the sky, a wheelhouse. Always there (the Ledger's landmark).
func _build_barge() -> void:
	var b := FrontierView.Batch.new()
	var p: Vector3 = _sea_spot(70.0, 115.0, 30.0)
	print("[planet-tidewell] ore barge at (%.0f, %.0f)" % [p.x, p.z])
	var yaw: float = _rng.randf() * TAU
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(-7.0)) * Basis(Vector3.FORWARD, deg_to_rad(11.0))
	var o := Vector3(p.x, -1.6, p.z)
	var xf := func(v: Vector3) -> Vector3: return o + basis * v
	if not _mats.has("_box"):
		_mats["_box"] = ProcMesh.rounded_box(Vector3.ONE, 0.07, 2)
	var bx: Mesh = _mats["_box"]
	b.add(bx, Transform3D(_ls(basis, Vector3(12.0, 5.0, 52.0)), xf.call(Vector3.ZERO)), _mat("hull"))
	b.add(bx, Transform3D(_ls(basis, Vector3(12.2, 0.5, 52.2)), xf.call(Vector3(0, 1.0, 0))), _mat("rust_red"))
	# Bow rake.
	b.add(bx, Transform3D(_ls(basis * Basis(Vector3.RIGHT, deg_to_rad(30.0)), Vector3(11.8, 4.0, 6.0)), xf.call(Vector3(0, 1.0, 27.0))), _mat("hull"))
	for k: int in 4:
		var hz: float = -14.0 + k * 9.0
		b.add(bx, Transform3D(_ls(basis, Vector3(9.0, 3.2, 7.0)), xf.call(Vector3(0, 4.0, hz))), _mat("rust"))
		b.add(bx, Transform3D(_ls(basis, Vector3(7.6, 0.6, 5.6)), xf.call(Vector3(0, 5.4, hz))), _mat("rust_dark"))
	_cyl(b, xf.call(Vector3(0, 6.0, 18.0)), xf.call(Vector3(2.0, 20.0, 34.0)), 0.6, _mat("rust"))
	_cyl(b, xf.call(Vector3(0, 6.0, 18.0)), xf.call(Vector3(0, 2.5, 18.0)), 0.9, _mat("rust_dark"))
	b.add(bx, Transform3D(_ls(basis, Vector3(8.0, 6.0, 6.0)), xf.call(Vector3(0, 5.5, -22.0))), _mat("rust_dark"))
	b.add(bx, Transform3D(_ls(basis, Vector3(8.1, 1.0, 4.0)), xf.call(Vector3(0, 7.0, -22.0))), _mat("window"))
	_cyl(b, xf.call(Vector3(2.0, 8.5, -23.0)), xf.call(Vector3(2.0, 13.0, -23.0)), 0.5, _mat("rust_red"))
	b.flush(_groups["always"])
	var lbl: Label3D = Mats.stencil(tr("LEDGER MINING  ORE BARGE 3"), 72, Color(0.9, 0.86, 0.76, 0.75))
	lbl.pixel_size = 0.035
	lbl.global_transform = Transform3D(basis * Basis(Vector3.UP, PI * 0.5), xf.call(Vector3(6.06, 0.6, 2.0)))
	_groups["always"].add_child(lbl)
	# Junk spilled from the hoppers, floating around the wreck while ruined.
	var pts: Array[Transform3D] = []
	for k: int in 40:
		var a: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(8.0, 34.0)
		pts.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(p.x + cos(a) * d, SEA_Y - 0.12, p.z + sin(a) * d)))
	_scatter_models(["Barrel_01", "bleach_bottle", "wooden_crate_02", "plastic_jerrycan", "lifebuoy"], pts, _groups["ruin"], 220.0)


## Tops of drowned towers: concrete shafts out of the water with dark window bands, broken
## crowns, rebar. Future: clean white crowns with roof gardens and a hair-thin light band.
func _build_towers() -> void:
	var b := FrontierView.Batch.new()
	var ruin := FrontierView.Batch.new()
	var fut := FrontierView.Batch.new()
	var grn := FrontierView.Batch.new()
	for i: int in 7:
		var p: Vector3 = _sea_spot(70.0, 380.0, 16.0)
		var w: float = _rng.randf_range(9.0, 16.0)
		var dpt: float = _rng.randf_range(9.0, 15.0)
		var h: float = _rng.randf_range(3.0, 16.0)
		var yaw: float = _rng.randf_range(-0.4, 0.4) + float(i)
		var tilt: float = _rng.randf_range(-3.0, 3.0)
		var c := Vector3(p.x, (h - 8.0) * 0.5, p.z)
		_box(b, c, Vector3(w, h + 8.0, dpt), _mat("concrete"), Vector3(tilt, rad_to_deg(yaw), 0))
		var fl: float = 0.8
		while fl < h - 0.6:
			_box(b, Vector3(p.x, fl, p.z), Vector3(w + 0.05, 1.3, dpt + 0.05), _mat("window"), Vector3(tilt, rad_to_deg(yaw), 0))
			fl += 3.3
		# Broken crown (ruin): jagged blocks and bent rebar.
		for k: int in 5:
			var o := Vector3(_rng.randf_range(-0.4, 0.4) * w, h + _rng.randf_range(0.0, 1.6), _rng.randf_range(-0.4, 0.4) * dpt)
			var cs: float = _rng.randf_range(0.7, 1.6)
			ruin.add(_lumpy(k % 5, 0.45, 2.2), FrontierView._xf(Vector3(p.x, 0, p.z) + Basis(Vector3.UP, yaw) * o, Vector3(_rng.randf() * 40, _rng.randf() * 360, 0), Vector3(cs * 1.3, cs, cs)), _mat("concrete"))
			_cyl(ruin, Vector3(p.x, h, p.z) + Basis(Vector3.UP, yaw) * Vector3(o.x, 0, o.z), Vector3(p.x, h + 2.4, p.z) + Basis(Vector3.UP, yaw) * Vector3(o.x + 0.6, 0, o.z), 0.04, _mat("rust_dark"))
		# Fallen slabs and rubble heaped against the shaft at the waterline.
		for k: int in 6:
			var ang: float = _rng.randf() * TAU
			var rp := Vector3(p.x, -0.3, p.z) + Basis(Vector3.UP, yaw) * Vector3(cos(ang) * (w * 0.5 + 0.6), 0, sin(ang) * (dpt * 0.5 + 0.6))
			var rs: float = _rng.randf_range(0.8, 2.0)
			b.add(_lumpy((k + i) % 5, 0.4, 1.8), FrontierView._xf(rp, Vector3(_rng.randf() * 30, _rng.randf() * 360, 0), Vector3(rs * 1.4, rs * 0.6, rs)), _mat("concrete"))
		# Future crown.
		_box(fut, Vector3(p.x, h + 0.9, p.z), Vector3(w + 0.4, 1.8, dpt + 0.4), _mat("white"), Vector3(tilt, rad_to_deg(yaw), 0))
		_box(fut, Vector3(p.x, h + 0.25, p.z), Vector3(w + 0.46, 0.05, dpt + 0.46), _mat("lamp"), Vector3(tilt, rad_to_deg(yaw), 0))
		_box(grn, Vector3(p.x, h + 0.35, p.z), Vector3(w * 0.9, 0.7, dpt * 0.9), _mat("garden"), Vector3(tilt, rad_to_deg(yaw), 0))
	b.flush(_groups["always"])
	ruin.flush(_groups["ruin"])
	fut.flush(_groups["future"])
	grn.flush(_groups["green"])


# --- Sea furniture ------------------------------------------------------------------------------

## Channel buoys round the field and out to the rigs; light buoys (thin cyan cap) when futuristic.
func _build_buoys() -> void:
	var pts: Array[Transform3D] = []
	var caps := FrontierView.Batch.new()
	for k: int in 14:
		var a: float = TAU * k / 14.0 + _rng.randf() * 0.2
		var d: float = _field_edge + _rng.randf_range(8.0, 30.0)
		var p := Vector3(cos(a) * d, SEA_Y - 0.25, sin(a) * d)
		pts.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).rotated(Vector3.FORWARD, _rng.randf_range(-0.12, 0.12)), p))
		_cyl(caps, p + Vector3(0, 2.6, 0), p + Vector3(0, 2.75, 0), 0.12, _mat("lamp"))
	_scatter_models(["ocean_buoy"], pts, _groups["always"], 420.0)
	caps.flush(_groups["future"], false)


## The base is an anchored raft: pontoon floats and bollards along the yard's water edges, a
## couple of moored work rafts and a fuel float just outside the field (no robot traffic there).
func _build_base_moorings() -> void:
	var b := FrontierView.Batch.new()
	var fut := FrontierView.Batch.new()
	var hub_r: float = field.hex_size * 0.92
	for k: int in 12:
		var a: float = TAU * k / 12.0
		var p := Vector3(cos(a), 0, sin(a)) * hub_r
		var hid: int = field.hex_at(p * 1.25)
		if hid < 0 or not field.is_water(hid):
			continue
		var t := Vector3(-sin(a), 0, cos(a))
		_cyl(b, p - t * 2.0 + Vector3(0, 0.12, 0), p + t * 2.0 + Vector3(0, 0.12, 0), 0.32, _mat("pontoon"))
		_cyl(b, p + Vector3(0, -0.2, 0), p + Vector3(0, 0.75, 0), 0.12, _mat("rust_dark"))
		_cyl(fut, p - t * 2.05 + Vector3(0, 0.12, 0), p + t * 2.05 + Vector3(0, 0.12, 0), 0.34, _mat("white"))
	for k: int in 3:
		var p: Vector3 = _sea_spot(_field_edge + 8.0, _field_edge + 26.0, 6.0)
		var yaw: float = _rng.randf() * 180.0
		_box(b, p + Vector3(0, 0.15, 0), Vector3(6.0, 0.35, 4.0), _mat("wood"), Vector3(0, yaw, 0))
		for sx: float in [-2.6, 2.6]:
			_box(b, p + Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(sx, -0.1, 0), Vector3(0.8, 0.6, 4.2), _mat("pontoon"), Vector3(0, yaw, 0))
		_box(b, p + Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(-1.0, 1.4, 0.6), Vector3(2.6, 2.2, 2.2), _mat("rust_dark"), Vector3(0, yaw, 0))
		_box(fut, p + Vector3(0, 0.36, 0), Vector3(6.1, 0.06, 4.1), _mat("white"), Vector3(0, yaw, 0))
	b.flush(_groups["always"])
	fut.flush(_groups["future"])


## Lighthouses on the bigger isles: a broken dark stump while ruined; restored, a white tower
## with a red band and a lantern whose thin beam sweeps slowly over the sea.
func _build_lighthouses() -> void:
	var b := FrontierView.Batch.new()
	var ruin := FrontierView.Batch.new()
	var n: int = 0
	var beam_mat := ShaderMaterial.new()
	beam_mat.shader = preload(DIR + "beam.gdshader")
	for isl: Dictionary in islands:
		if n >= 2 or str(isl["kind"]) != "isle" or isl.get("far", false) or float(isl["h"]) < 3.5:
			continue
		n += 1
		var c: Vector2 = isl["c"]
		var g: float = bed_at(c.x, c.y).x
		var base := Vector3(c.x, g - 0.3, c.y)
		var h: float = 14.0
		for k: int in 4:
			var y0: float = h * k / 4.0
			var cm := CylinderMesh.new()
			cm.bottom_radius = lerpf(1.8, 1.1, float(k) / 4.0)
			cm.top_radius = lerpf(1.8, 1.1, float(k + 1) / 4.0)
			cm.height = h / 4.0
			cm.radial_segments = 16
			b.add(cm, FrontierView._xf(base + Vector3(0, y0 + h / 8.0, 0)), _mat("buoy_red") if k == 2 else _mat("white"))
		var gal := CylinderMesh.new()
		gal.top_radius = 1.6
		gal.bottom_radius = 1.6
		gal.height = 0.25
		gal.radial_segments = 16
		b.add(gal, FrontierView._xf(base + Vector3(0, h + 0.1, 0)), _mat("rust_dark"))
		var lan := CylinderMesh.new()
		lan.top_radius = 0.85
		lan.bottom_radius = 0.95
		lan.height = 1.4
		lan.radial_segments = 12
		b.add(lan, FrontierView._xf(base + Vector3(0, h + 0.95, 0)), _mat("lamp_warm"))
		var cap := SphereMesh.new()
		cap.radius = 1.0
		cap.height = 1.0
		cap.is_hemisphere = true
		b.add(cap, FrontierView._xf(base + Vector3(0, h + 1.65, 0)), _mat("buoy_red"))
		var stump := CylinderMesh.new()
		stump.top_radius = 1.4
		stump.bottom_radius = 1.8
		stump.height = 6.0
		stump.radial_segments = 12
		ruin.add(stump, FrontierView._xf(base + Vector3(0, 3.0, 0), Vector3(4, 0, 2)), _mat("rust_dark"))
		# Beam: two thin cones back to back on a turning pivot (green group, so restored only).
		var pivot := Node3D.new()
		pivot.position = base + Vector3(0, h + 0.95, 0)
		for side: float in [1.0, -1.0]:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.25
			cone.bottom_radius = 7.0
			cone.height = 160.0
			cone.radial_segments = 12
			cone.cap_top = false
			cone.cap_bottom = false
			var mi := MeshInstance3D.new()
			mi.mesh = cone
			mi.material_override = beam_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# Narrow end (cylinder top) at the lamp: +Y turns to -Z (side 1) or +Z (side -1).
			mi.rotation.x = -PI * 0.5 if side > 0 else PI * 0.5
			mi.position = Vector3(0, 0, 80.0 * side)
			pivot.add_child(mi)
		_groups["green"].add_child(pivot)
		_beams.append(pivot)
	b.flush(_groups["green"])
	ruin.flush(_groups["ruin"])


## Floating gardens: round planted rafts moored on some clean water hexes once restored, and a
## ring of them just outside the field. Small and low (skimmers glide past them).
func _build_gardens() -> void:
	var b := FrontierView.Batch.new()
	var spots: Array[Vector3] = []
	var k_g: int = 0
	for k: int in 10:
		spots.append(_sea_spot(_field_edge + 4.0, _field_edge + 60.0, 4.0))
	for p: Vector3 in spots:
		var r: float = _rng.randf_range(1.4, 2.6)
		var yaw: float = _rng.randf() * 360.0
		b.add(_blob_slab(k_g % 4, 0.22, 1.0), FrontierView._xf(p + Vector3(0, 0.02, 0), Vector3(0, yaw, 0), Vector3(r, 0.3, r)), _mat("wood"))
		b.add(_blob_slab((k_g + 2) % 4, 0.26, 1.0), FrontierView._xf(p + Vector3(0, 0.2, 0), Vector3(0, yaw + 40.0, 0), Vector3(r * 0.86, 0.14, r * 0.86)), _mat("garden"))
		for k: int in 6:
			var o := Vector3(_rng.randf_range(-0.6, 0.6), 0.36, _rng.randf_range(-0.6, 0.6)) * r
			var s: float = _rng.randf_range(0.25, 0.6)
			b.add(_lumpy(5 + k % 3, 0.55, 3.0), FrontierView._xf(p + Vector3(o.x, 0.36, o.z), Vector3(0, _rng.randf() * 360.0, 0), Vector3(s, s * 0.8, s)), _mat("mangrove"))
		k_g += 1
	b.flush(_groups["green"], false)


## Futuristic stage: white sea platforms on slim floats with hair-thin light edges, floating
## solar rafts, and a glass greenhouse dome on the biggest platform.
func _build_future() -> void:
	var b := FrontierView.Batch.new()
	var lit := FrontierView.Batch.new()
	for k: int in 3:
		var p: Vector3 = _sea_spot(_field_edge + 25.0, 160.0, 18.0)
		var r: float = _rng.randf_range(7.0, 11.0)
		var pyaw: float = _rng.randf() * 360.0
		b.add(_blob_slab(10 + k, 0.1, 1.0, 3), FrontierView._xf(p + Vector3(0, 0.55, 0), Vector3(0, pyaw, 0), Vector3(r, 1.0, r)), _mat("white"))
		lit.add(_blob_slab(10 + k, 0.1, 1.0, 3), FrontierView._xf(p + Vector3(0, 1.03, 0), Vector3(0, pyaw, 0), Vector3(r * 1.004, 0.03, r * 1.004)), _mat("lamp"))
		for f: int in 6:
			var a: float = TAU * f / 6.0
			_cyl(b, p + Vector3(cos(a) * r * 0.8, -1.2, sin(a) * r * 0.8), p + Vector3(cos(a) * r * 0.8, 0.2, sin(a) * r * 0.8), 0.5, _mat("white"))
		if k == 0:
			var dome := SphereMesh.new()
			dome.radius = r * 0.6
			dome.height = r * 0.6
			dome.is_hemisphere = true
			dome.radial_segments = 24
			b.add(dome, FrontierView._xf(p + Vector3(0, 1.05, 0)), Mats.glass(Color(0.6, 0.8, 0.85, 0.35), 0.05))
			var g := SphereMesh.new()
			g.radius = r * 0.45
			g.height = r * 0.35
			g.is_hemisphere = true
			b.add(g, FrontierView._xf(p + Vector3(0, 1.05, 0)), _mat("mangrove"))
	for k: int in 4:
		var p: Vector3 = _sea_spot(_field_edge + 10.0, 120.0, 12.0)
		var yaw: float = _rng.randf() * 180.0
		for i: int in 3:
			for j: int in 2:
				var o: Vector3 = Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3((i - 1) * 3.4, 0, (j - 0.5) * 2.4)
				_box(b, p + o + Vector3(0, 0.35, 0), Vector3(3.2, 0.08, 2.2), _mat("solar"), Vector3(8, yaw, 0))
				_box(b, p + o + Vector3(0, 0.12, 0), Vector3(3.3, 0.25, 2.3), _mat("white"), Vector3(0, yaw, 0))
	b.flush(_groups["future"])
	lit.flush(_groups["future"], false)


## Floating flotsam on the open sea while ruined (it is gone once the planet is restored).
func _build_flotsam() -> void:
	var pts: Array[Transform3D] = []
	for k: int in 140:
		var p: Vector3 = _sea_spot(_field_edge + 3.0, 230.0, 1.0)
		p.y = SEA_Y - 0.1
		pts.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).rotated(Vector3.RIGHT, _rng.randf_range(-0.3, 0.3)), p))
	_scatter_models(["plastic_bottle_gallon", "Barrel_01", "multi_cleaner_bottle", "lifebuoy", "wooden_crate_02", "trashbag", "old_tyre"], pts, _groups["ruin"], 170.0)


## Trash rafts: a tangle of ghost net and scum under each raft cluster on a dirty water hex
## (planet/planets/tidewell/net.gdshader); it shrinks away when the hex is cleaned.
func _build_rafts() -> void:
	var xfs: Array[Transform3D] = []
	var rr: Array = data().get("floaters", {}).get("raft_r", [2.2, 3.6])
	for id: int in field.hex_count():
		if not field.is_water(id):
			continue
		for c: Vector3 in raft_centres(field, id):
			var s: float = _rng.randf_range(float(rr[0]), float(rr[1]))
			var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, 1.0, s * _rng.randf_range(0.7, 1.0))), Vector3(c.x, SEA_Y + 0.015, c.z))
			if field.is_clean(id):
				xf = Transform3D(xf.basis.scaled(Vector3.ONE * 0.001), xf.origin)
			xfs.append(xf)
			_raft_hex.append(id)
	if xfs.is_empty():
		return
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0, 2.0)
	pm.subdivide_width = 4
	pm.subdivide_depth = 4
	var m := ShaderMaterial.new()
	m.shader = preload(DIR + "net.gdshader")
	_rafts = MultiMesh.new()
	_rafts.transform_format = MultiMesh.TRANSFORM_3D
	_rafts.mesh = pm
	_rafts.instance_count = xfs.size()
	for i: int in xfs.size():
		_rafts.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "TrashRafts"
	mmi.multimesh = _rafts
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 140.0
	_groups["always"].add_child(mmi)


# --- Sky, junk, life -------------------------------------------------------------------------------

func _setup_sky() -> void:
	var sky: Dictionary = kind.get("sky", {})
	_grade_ruin = sky.get("ruined", {})
	_grade_clean = sky.get("restored", {})
	var sun: DirectionalLight3D = world.get("_sun")
	if sun:
		suns = TideSuns.new()
		suns.name = "TideSuns"
		add_child(suns)
		suns.setup(world, sun)
	var env: Environment = null
	var sd: Node = world.get("sky_director")
	if sd:
		env = sd.get("env")
	if env:
		var amb: Dictionary = kind.get("ambient", {})
		env.ambient_light_sky_contribution = 0.85
		var ac: Array = amb.get("color", [])
		if ac.size() >= 3:
			env.ambient_light_color = Color(float(ac[0]), float(ac[1]), float(ac[2]))


static func _blend_grade(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out: Dictionary = {}
	for k: String in a:
		var va: Variant = a[k]
		var vb: Variant = b.get(k, va)
		if va is Array and vb is Array and (va as Array).size() == (vb as Array).size():
			var arr: Array = []
			for i: int in (va as Array).size():
				arr.append(lerpf(float(va[i]), float(vb[i]), t))
			out[k] = arr
		elif (va is float or va is int) and (vb is float or vb is int):
			out[k] = lerpf(float(va), float(vb), t)
		else:
			out[k] = vb if t > 0.5 else va
	return out


## Salt-crusted, sea-faded junk (the shared weathering overlay).
func _weather_junk() -> void:
	var view: Node = world.get("view")
	if view == null or not view.has_method("set_junk_overlay"):
		return
	var jt: Array = kind.get("junk_tint", [0.36, 0.4, 0.36, 0.55])
	var m := ShaderMaterial.new()
	m.shader = preload("res://art/shaders/junk_coat.gdshader")
	m.set_shader_parameter("coat", Color(float(jt[0]), float(jt[1]), float(jt[2])))
	m.set_shader_parameter("top_amt", float(jt[3]))
	m.set_shader_parameter("film", 0.4)
	m.set_shader_parameter("roughness", 0.6)
	view.call("set_junk_overlay", m)


## Big fish in the clean field water and two whales offshore: shadows on the seabed (ocean shader).
func _spawn_fish() -> void:
	for k: int in 6:
		var whale: bool = k < 2
		_fish.append({
			"whale": whale,
			"c": Vector2(_sea_spot(_field_edge + 40.0, 320.0, 20.0).x, 0) if whale else Vector2.ZERO,
			"r": _rng.randf_range(60.0, 140.0) if whale else _rng.randf_range(6.0, 22.0),
			"ph": _rng.randf() * TAU,
			"sp": (_rng.randf_range(0.02, 0.04) if whale else _rng.randf_range(0.08, 0.2)) * (1.0 if _rng.randf() < 0.5 else -1.0),
			"len": _rng.randf_range(12.0, 18.0) if whale else _rng.randf_range(1.2, 2.6),
		})
	for f: Dictionary in _fish:
		if f["whale"]:
			var p: Vector3 = _sea_spot(_field_edge + 90.0, 400.0, 30.0)
			f["c"] = Vector2(p.x, p.z)


func _update_fish(delta: float) -> void:
	if ocean_mat == null:
		return
	var arr: Array = []
	var life: float = clampf(restore * 1.6 - 0.4, 0.0, 1.0)
	for f: Dictionary in _fish:
		f["ph"] = float(f["ph"]) + float(f["sp"]) * delta * (1.0 if f["whale"] else 1.0)
		var ph: float = f["ph"]
		var c: Vector2 = f["c"]
		var r: float = f["r"]
		var p: Vector2 = c + Vector2(cos(ph), sin(ph)) * r
		var head: float = ph + (PI * 0.5 if float(f["sp"]) > 0.0 else -PI * 0.5)
		var on: bool = life > 0.05
		if not f["whale"]:
			# Fish only show over clean water hexes.
			var hid: int = field.hex_at(Vector3(p.x, 0, p.y))
			on = on and hid >= 0 and field.is_water(hid) and field.is_clean(hid)
		arr.append(Vector4(p.x, p.y, head, float(f["len"]) if on else 0.0))
	ocean_mat.set_shader_parameter("fish", arr)
