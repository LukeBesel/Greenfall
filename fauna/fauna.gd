class_name Fauna
extends Node3D
## [wild] Ambient animals: a visible reward for restoring the world. Who lives where comes from
## FaunaRules.plan() (data/fauna.json): stray cats, pigeons and sparrows on clean city ground,
## rats on junky hexes (they thin out and leave as the hex is cleaned), rabbits on Growing hexes,
## deer at the edges of Sustained ground, foxes and bees, songbirds and fireflies on Thriving
## hexes, fish, ducks and frogs in and around clean lakes, and each frontier's own animals.
##
## Cheap by design: one MultiMesh per model (art/shaders/fauna.gdshader rigs legs, heads, tails
## and wings in the vertex shader), plain state machines in GDScript, far animals update every
## third frame, nothing has a collider (robots and Lumi walk straight through), and every place
## an animal stands is checked against junk (FaunaRules.spot_ok).
##
## Cats: sit, groom, wander, curl up asleep on warm spots by the base, follow Lumi a little when
## he stops nearby, and can be petted (E): a purr and a heart. Pet the same cat three times and
## it adopts you: it gets a name, lives at that base and follows you there (GameState.flags.fauna_cat).
## Sightings (in view and near Lumi) unlock Codex "Animals" entries (flags.fauna_seen); photos
## in photo mode go into the Collection (flags.fauna_photos, trinkets pic_<species>).
##
## Dev: --fauna-look=SPECIES[,dist,pitch,yaw] frames Lumi next to one (after --fauna-look-at=S,
## default 5), --fauna-pose=sit|groom|sleep|pet|graze|fly holds a pose, --fauna-dense spawns on
## every qualifying hex, --fauna-report[=S] prints the census.

enum St { IDLE, WALK, GRAZE, SIT, GROOM, SLEEP, FOLLOW, FLEE, FLY, PECK, PET, BASK, SWIM, SOAR, LEAVE }

const CAT_NAMES: Array[String] = ["Biscuit", "Pixel", "Mochi", "Rivet", "Clover", "Sprocket", "Juniper", "Nimbus", "Pepper", "Tofu"]
const UPDATE_FAR: float = 32.0

class Animal:
	extends RefCounted
	var sp: String = ""
	var kind: String = ""
	var key: String = ""
	var hex: int = -1
	var pos: Vector3 = Vector3.ZERO
	var home: Vector3 = Vector3.ZERO
	var target: Vector3 = Vector3.ZERO
	var vel: Vector3 = Vector3.ZERO
	var yaw: float = 0.0
	var roll: float = 0.0
	var state: int = 0
	var t: float = 0.0
	var phase: float = 0.0
	var gait: float = 0.0
	var head_pitch: float = 0.0
	var head_yaw: float = 0.0
	var tail: float = 0.2
	var coat: int = 0
	var size: float = 1.0
	var fade: float = 0.0
	var bob: float = 0.0
	var alt: float = 0.0
	var members: Array = []  # schools / swarms: [offset Vector3, phase]
	var anchor: Node3D
	var pets: int = 0
	var cat_name: String = ""
	var named: bool = false
	var follow_t: float = 0.0
	var follow_cool: float = 0.0
	var sound_t: float = 0.0
	var acc: float = 0.0
	var check_t: float = 0.0
	var seen: bool = false
	var hold: bool = false

var world: Node
var animals: Array[Animal] = []
var regs: Array[String] = []
var district_seed: int = 0
var dense: bool = false
var _cfg: Dictionary
var _batches: Dictionary = {}  # model id -> MultiMeshInstance3D
var _counts: Dictionary = {}
var _glow: MultiMeshInstance3D
var _glow_n: int = 0
var _rng := RandomNumberGenerator.new()
var _plan_t: float = 0.5
var _desired: Dictionary = {}  # key -> {sp, hex, n}
var _cooldown: Dictionary = {}  # key -> seconds before it may respawn
var _anchors: Dictionary = {}  # "sp|hex" -> flock anchor
var _frame: int = 0
var _sight_t: float = 0.0
var _toast_q: Array[String] = []
var _toast_t: float = 0.0
var _crickets: AudioStreamPlayer
var _cricket_vol: float = 0.0
var _green_share: float = 0.0
var _still_t: float = 0.0
var _lumi_speed: float = 0.0
var _lumi_pos: Vector3 = Vector3.ZERO
var _cam: Camera3D
var _night: float = 0.0
var _warm: Array[Vector3] = []
var _look_done: bool = false
var _heart_mesh: Mesh
var _heart_mat: StandardMaterial3D


func setup(p_world: Node) -> void:
	world = p_world
	name = "Fauna"
	_cfg = FaunaRules.cfg()
	_rng.seed = hash([int(world.get("hub_index") if world.get("hub_index") != null else 0), 1717])
	var f: HexField = world.field
	district_seed = f.seed_value
	regs = FaunaRules.regions(f.biome)
	dense = DevHooks.has("fauna-dense")
	FaunaSounds.ensure()
	_crickets = AudioStreamPlayer.new()
	_crickets.bus = "SFX"
	_crickets.stream = FaunaSounds.crickets_loop()
	_crickets.volume_db = -80.0
	add_child(_crickets)
	_build_warm_spots()
	EventBus.hex_level_changed.connect(func(_h: int, _l: int) -> void: _plan_t = minf(_plan_t, 0.4))
	EventBus.hex_cleaned.connect(func(_h: int, _p: Vector3, _b: BigNum) -> void: _plan_t = minf(_plan_t, 0.4))
	var ph: Node = world.get("photo")
	if ph and ph.has_signal("captured"):
		ph.connect("captured", _on_photo)
	add_to_group("fauna")


# --- Planning ----------------------------------------------------------------------------------

func _level_of(h: int) -> int:
	var hl: Node = world.get("hex_levels")
	return int(hl.call("level_of", h)) if hl else (1 if world.field.is_clean(h) else 0)


func night_amount() -> float:
	var sky: Node = world.get("sky_director")
	if sky == null:
		return 0.0
	var tod: float = float(sky.get("time_of_day"))
	return maxf(1.0 - smoothstep(0.19, 0.27, tod), smoothstep(0.75, 0.83, tod))


func clarity() -> float:
	return clampf(Economy.stat("lake_clarity"), 0.0, 1.0) if Economy.has_method("stat") else 0.0


## Re-make the plan and start/stop animals to match it.
func replan() -> void:
	var f: HexField = world.field
	var ctxs: Array = FaunaRules.contexts(f, _level_of)
	var fd: Dictionary = {}
	var green: int = 0
	var land: int = 0
	for c: Dictionary in ctxs:
		var h: int = int(c["hex"])
		fd[h] = f.hex_center(h).distance_to(_lumi_pos)
		if dense:
			c["dense"] = true
		if int(c["level"]) >= 0:
			land += 1
			if int(c["level"]) >= 3:
				green += 1
	_green_share = float(green) / maxf(1.0, float(land))
	var plan: Array = FaunaRules.plan(ctxs, regs, _night > 0.5, district_seed + (0 if not dense else 1), fd, clarity()) if not dense else _dense_plan(ctxs, fd)
	_desired.clear()
	var spawn_r: float = float(_cfg.get("spawn_radius", 55.0))
	for e: Dictionary in plan:
		var sid: String = str(e["sp"])
		var kind: String = str(FaunaRules.def(sid).get("kind", ""))
		var h: int = int(e["hex"])
		if h >= 0 and float(fd.get(h, 0.0)) > spawn_r:
			continue
		if kind in ["swarm", "school"]:
			_desired["%s|%d" % [sid, h]] = e
		else:
			for k: int in int(e["n"]):
				_desired["%s|%d|%d" % [sid, h, k]] = e
	var named: Dictionary = adopted_cat()
	if not named.is_empty() and int(named.get("hub", -1)) == int(world.get("hub_index") if world.get("hub_index") != null else 0):
		_desired["named_cat"] = {"sp": "cat", "hex": -2, "n": 1}
	var have: Dictionary = {}
	for a: Animal in animals:
		have[a.key] = true
		if not _desired.has(a.key) and a.state != St.LEAVE:
			_leave(a)
	var spawned: int = 0
	for key: String in _desired:
		if have.has(key) or float(_cooldown.get(key, 0.0)) > 0.0:
			continue
		if _spawn(key, _desired[key]):
			spawned += 1
		if spawned >= 12:
			break


## --fauna-dense: every qualifying hex gets the species (screenshots).
func _dense_plan(ctxs: Array, fd: Dictionary) -> Array:
	var out: Array = []
	for d: Dictionary in FaunaRules.defs():
		var used: int = 0
		var cap: int = int(d.get("cap", 99))
		if str(d.get("where", "")) == "district":
			if FaunaRules.in_region(d, regs) and FaunaRules.time_ok(d, _night > 0.5):
				out.append({"sp": d["id"], "hex": -1, "n": int((d.get("per_hex", [1, 1]) as Array)[1])})
			continue
		var order: Array = ctxs.duplicate()
		order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(fd[int(a["hex"])]) < float(fd[int(b["hex"])]))
		for c: Dictionary in order:
			if used >= cap:
				break
			if FaunaRules.suits(d, c, regs, _night > 0.5):
				var n: int = mini(int((d.get("per_hex", [1, 1]) as Array)[1]), cap - used)
				out.append({"sp": d["id"], "hex": int(c["hex"]), "n": n})
				used += n
	return out


# --- Spawning ----------------------------------------------------------------------------------

func _ground_y(p: Vector3) -> float:
	var lay: CityLayout = world.field.layout
	return clampf(lay.height_at(p.x, p.z), 0.0, 0.3) if lay else 0.0


func _in_view(p: Vector3) -> bool:
	return _cam != null and _cam.is_position_in_frustum(p) and _cam.global_position.distance_to(p) < 30.0


## A free spot on hex h for the species (land, shore edge or water), or Vector3.INF.
func find_spot(sid: String, h: int, near: Vector3 = Vector3.INF, spread: float = -1.0) -> Vector3:
	var f: HexField = world.field
	var d: Dictionary = FaunaRules.def(sid)
	var where: String = str(d.get("where", "land"))
	var junk_ok: bool = bool(d.get("junk", false))
	var c: Vector3 = f.hex_center(h) if near == Vector3.INF else near
	var rad: float = f.hex_size * 0.85 if spread < 0.0 else spread
	var best := Vector3.INF
	for i: int in 14:
		var p: Vector3 = c + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)) * rad
		var ph: int = f.hex_at(p)
		if ph < 0:
			continue
		if where == "water":
			if f.is_water(ph) and f.is_clean(ph) and f.hex_at(p + Vector3(0.6, 0, 0)) == ph and f.hex_at(p - Vector3(0.6, 0, 0)) == ph:
				return Vector3(p.x, HexField.WATER_Y, p.z)
			continue
		if f.is_water(ph):
			continue
		if near == Vector3.INF and ph != h:
			continue
		if not FaunaRules.spot_ok(f, p, 0.45 if not junk_ok else 0.3, junk_ok):
			continue
		if where == "shore":
			# Frogs, herons and seals stand at the water's edge.
			var wet: bool = false
			for k: int in 6:
				var a: float = TAU * k / 6.0
				if f.is_water(f.hex_at(p + Vector3(cos(a), 0, sin(a)) * 1.6)):
					wet = true
					break
			if not wet:
				continue
		p.y = _ground_y(p)
		if not _in_view(p):
			return p
		best = p
	return best


func _spawn(key: String, e: Dictionary) -> bool:
	var sid: String = str(e["sp"])
	var d: Dictionary = FaunaRules.def(sid)
	var a := Animal.new()
	a.sp = sid
	a.kind = str(d.get("kind", "quad"))
	a.key = key
	a.hex = int(e["hex"])
	a.coat = _rng.randi() % maxi(1, (d.get("coats", ["#ffffff"]) as Array).size())
	a.size = float(d.get("scale", 1.0)) * _rng.randf_range(0.9, 1.08)
	a.phase = _rng.randf() * TAU
	var f: HexField = world.field
	var p := Vector3.INF
	if key == "named_cat":
		a.named = true
		a.cat_name = str(adopted_cat().get("name", "Biscuit"))
		a.coat = int(adopted_cat().get("coat", 0))
		a.size = 1.0
		var w: Vector3 = _warm[0] if not _warm.is_empty() else Vector3(2, 0, 2)
		p = w + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
		p.y = _ground_y(p)
	elif a.hex == -1:
		p = Vector3.ZERO
	elif a.kind == "bird":
		var ak: String = "%s|%d" % [sid, a.hex]
		var anc: Vector3 = _anchors.get(ak, Vector3.INF)
		if anc == Vector3.INF or not FaunaRules.spot_ok(f, anc, 0.4):
			anc = find_spot(sid, a.hex)
			_anchors[ak] = anc
		if anc != Vector3.INF:
			p = find_spot(sid, a.hex, anc, 1.6)
			if p == Vector3.INF:
				p = anc
	else:
		p = find_spot(sid, a.hex)
	if p == Vector3.INF:
		_cooldown[key] = 6.0
		return false
	a.pos = p
	a.home = p
	a.target = p
	a.yaw = _rng.randf() * TAU
	a.fade = 0.0 if _in_view(p) else 1.0
	match a.kind:
		"school":
			for k: int in int(e["n"]):
				a.members.append([Vector3(_rng.randf_range(-0.7, 0.7), _rng.randf_range(-0.01, 0.01), _rng.randf_range(-0.9, 0.9)), _rng.randf() * TAU])
			a.pos.y = 0.055
			a.state = St.SWIM
		"swarm":
			for k: int in int(e["n"]):
				a.members.append([Vector3(_rng.randf_range(-1.2, 1.2), _rng.randf_range(0.0, 0.5), _rng.randf_range(-1.2, 1.2)), _rng.randf() * TAU])
			a.pos = _swarm_center(a)
			a.home = a.pos
			a.fade = 1.0
		"soarer":
			a.state = St.SOAR
			a.home = Vector3.ZERO
			a.alt = _rng.randf_range(16.0, 30.0)
			a.target = Vector3(_rng.randf_range(18.0, 34.0), 0, _rng.randf_range(0.08, 0.14) * (1 if _rng.randf() < 0.7 else -1))
			a.fade = 1.0
		"swim":
			a.state = St.SWIM
		"bird":
			a.state = St.PECK
			var soar: int = int(d.get("soar", 0))
			if soar > 0 and int(key.get_slice("|", 2)) < 1 and _count_state(sid, St.SOAR) < soar:
				a.state = St.SOAR
				a.home = f.hex_center(a.hex)
				a.alt = _rng.randf_range(7.0, 12.0)
				a.target = Vector3(_rng.randf_range(8.0, 16.0), 0, _rng.randf_range(0.25, 0.4))
			elif a.fade < 1.0:
				# In view: fly in and land instead of popping up.
				a.fade = 1.0
				a.state = St.FLY
				a.target = p
				a.pos = p + Vector3(_rng.randf_range(-8, 8), _rng.randf_range(5, 8), _rng.randf_range(-8, 8))
				a.alt = 1.0
		"cat":
			a.state = St.SIT
			a.t = _rng.randf_range(2.0, 6.0)
			a.anchor = Node3D.new()
			a.anchor.name = "CatAnchor"
			add_child(a.anchor)
			a.anchor.global_position = a.pos
			var ints: Node = world.get("interactables")
			if ints:
				var aa: Animal = a
				ints.call("register", a.anchor, 1.9, func() -> String: return _pet_prompt(aa), func() -> void: pet(aa), func() -> bool: return _pet_enabled(aa))
		_:
			a.state = St.IDLE
			a.t = _rng.randf_range(1.0, 4.0)
	animals.append(a)
	return true


func _count_state(sid: String, st: int) -> int:
	var n: int = 0
	for a: Animal in animals:
		if a.sp == sid and a.state == st:
			n += 1
	return n


func _leave(a: Animal) -> void:
	a.state = St.LEAVE
	a.t = 0.0
	if a.anchor:
		var ints: Node = world.get("interactables")
		if ints:
			ints.call("unregister", a.anchor)
	match a.kind:
		"bird", "soarer", "heron":
			a.vel = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * 5.0 + Vector3(0, 3.0, 0)
		"rat":
			a.target = _toward_junk(a.pos)
		_:
			var away: Vector3 = (a.pos - _lumi_pos)
			away.y = 0.0
			a.target = a.pos + (away.normalized() if away.length() > 0.1 else Vector3.FORWARD) * 8.0


func _remove(a: Animal) -> void:
	if a.anchor:
		var ints: Node = world.get("interactables")
		if ints:
			ints.call("unregister", a.anchor)
		a.anchor.queue_free()
		a.anchor = null
	animals.erase(a)


func _toward_junk(p: Vector3) -> Vector3:
	var f: HexField = world.field
	var best: Vector3 = p + Vector3(6, 0, 0)
	var bd: float = INF
	for h: int in f.hex_count():
		if not f.is_clean(h) and not f.is_water(h) and f.hex_hub[h] == 0:
			var d: float = f.hex_center(h).distance_to(p)
			if d < bd:
				bd = d
				best = f.hex_center(h)
	return best


func _build_warm_spots() -> void:
	_warm.clear()
	var f: HexField = world.field
	var comp: Node3D = world.get("composter") as Node3D
	if comp:
		_warm.append(comp.global_position + Vector3(1.2, 0, 0.8))
	var dep: Node3D = world.get("depot") as Node3D
	if dep:
		_warm.append(dep.global_position + Vector3(-1.4, 0, 1.0))
	for h: int in f.hex_count():
		if f.hex_hub[h] != 0:
			_warm.append(f.hex_center(h) + Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3)))
	for i: int in range(_warm.size() - 1, -1, -1):
		var w: Vector3 = _warm[i]
		w.y = _ground_y(w)
		_warm[i] = w
		if not FaunaRules.spot_ok(f, w, 0.4):
			_warm.remove_at(i)


# --- Frame update ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if world == null or world.get("patch") == null:
		return
	_frame += 1
	var patch: Node3D = world.patch
	var pv: Vector3 = patch.get("velocity") if patch.get("velocity") != null else Vector3.ZERO
	_lumi_speed = Vector2(pv.x, pv.z).length()
	_lumi_pos = patch.global_position
	_still_t = _still_t + delta if _lumi_speed < 0.4 else 0.0
	_cam = get_viewport().get_camera_3d()
	_night = night_amount()
	for k: String in _cooldown.keys():
		_cooldown[k] = float(_cooldown[k]) - delta
		if float(_cooldown[k]) <= 0.0:
			_cooldown.erase(k)
	_plan_t -= delta
	if _plan_t <= 0.0:
		_plan_t = 2.5
		replan()
	var despawn_r: float = float(_cfg.get("despawn_radius", 70.0))
	var cam_p: Vector3 = _cam.global_position if _cam else _lumi_pos
	for i: int in range(animals.size() - 1, -1, -1):
		var a: Animal = animals[i]
		if a.hex >= 0 and a.pos.distance_to(_lumi_pos) > despawn_r:
			_remove(a)
			continue
		var far: bool = a.pos.distance_to(cam_p) > UPDATE_FAR
		a.acc += delta
		if far and (_frame + i) % 3 != 0:
			continue
		var dt: float = minf(a.acc, 0.25)
		a.acc = 0.0
		a.fade = minf(a.fade + dt * 1.6, 1.0)
		_update(a, dt)
		if a.anchor:
			a.anchor.global_position = a.pos
	_draw_all()
	_sight_t -= delta
	if _sight_t <= 0.0:
		_sight_t = 0.5
		_sightings()
	_toast_t -= delta
	if _toast_t <= 0.0 and not _toast_q.is_empty():
		_toast_t = 4.0
		EventBus.toast.emit(_toast_q.pop_front(), "hint")
	_ambience(delta)
	if not _look_done and DevHooks.has("fauna-look"):
		_dev_look()
	if DevHooks.has("fauna-report") and not has_meta("reported"):
		if Time.get_ticks_msec() * 0.001 > DevHooks.get_f("fauna-report", 8.0):
			set_meta("reported", true)
			print("[fauna] ", census())


## Species -> live count (for tests and --fauna-report).
func census() -> Dictionary:
	var out: Dictionary = {}
	for a: Animal in animals:
		if a.state == St.LEAVE:
			continue
		out[a.sp] = int(out.get(a.sp, 0)) + (a.members.size() if not a.members.is_empty() else 1)
	return out


func _face(a: Animal, dir: Vector3, dt: float, rate: float = 6.0) -> void:
	if Vector2(dir.x, dir.z).length() < 0.001:
		return
	a.yaw = lerp_angle(a.yaw, atan2(-dir.x, -dir.z), minf(dt * rate, 1.0))


## Moves toward a.target at speed; returns true on arrival.
func _step(a: Animal, speed: float, dt: float, stop: float = 0.15) -> bool:
	var to: Vector3 = a.target - a.pos
	to.y = 0.0
	var d: float = to.length()
	if d <= stop:
		return true
	var mv: float = minf(speed * dt, d)
	a.pos += to / d * mv
	if a.kind != "swim" and a.kind != "school":
		a.pos.y = _ground_y(a.pos)
	_face(a, to, dt)
	return false


func _look_at_lumi(a: Animal, dt: float, amount: float = 1.0) -> void:
	var to: Vector3 = _lumi_pos - a.pos
	var want: float = wrapf(atan2(-to.x, -to.z) - a.yaw, -PI, PI)
	a.head_yaw = lerpf(a.head_yaw, clampf(want, -1.1, 1.1) * amount, minf(dt * 4.0, 1.0))


func _relax_head(a: Animal, dt: float) -> void:
	a.head_yaw = lerpf(a.head_yaw, 0.0, minf(dt * 3.0, 1.0))


## Lumi is close (or rushing at it): a reason to bolt.
func _scared(a: Animal, r: float) -> bool:
	var d: float = Vector2(a.pos.x - _lumi_pos.x, a.pos.z - _lumi_pos.z).length()
	return d < r or (_lumi_speed > 3.0 and d < r * 1.9)


func _flee_target(a: Animal, dist: float) -> Vector3:
	var away: Vector3 = a.pos - _lumi_pos
	away.y = 0.0
	away = away.normalized() if away.length() > 0.05 else Vector3.FORWARD
	var junk_ok: bool = a.kind == "rat"
	for k: int in 7:
		var ang: float = (k + 1) / 2 * 0.5 * (1.0 if k % 2 == 0 else -1.0)
		var p: Vector3 = a.pos + away.rotated(Vector3.UP, ang) * dist
		if FaunaRules.spot_ok(world.field, p, 0.35, junk_ok) and (a.kind != "rat" or world.field.hex_at(p) >= 0):
			p.y = _ground_y(p)
			return p
	return a.pos + away * 1.5


func _wander_target(a: Animal, r: float) -> Vector3:
	var junk_ok: bool = a.kind == "rat"
	for k: int in 6:
		var p: Vector3 = a.home + Vector3(_rng.randf_range(-r, r), 0, _rng.randf_range(-r, r))
		var mid: Vector3 = (p + a.pos) * 0.5
		if FaunaRules.spot_ok(world.field, p, 0.35, junk_ok) and FaunaRules.spot_ok(world.field, mid, 0.25, junk_ok):
			p.y = _ground_y(p)
			return p
	return a.pos


func _update(a: Animal, dt: float) -> void:
	a.t -= dt
	a.sound_t -= dt
	# Dev: hold a posed animal still for screenshots.
	if a.hold:
		_hold_pose(a, dt)
		return
	if a.state == St.LEAVE:
		_update_leave(a, dt)
		return
	# Never stand in junk: a Ledger drop or a stray piece moves the animal on.
	a.check_t -= dt
	if a.check_t <= 0.0:
		a.check_t = 1.0 + _rng.randf()
		if a.kind in ["quad", "deer", "hopper", "cat", "lizard", "frog", "seal", "heron"] or (a.kind == "bird" and a.state != St.FLY and a.state != St.SOAR):
			if not FaunaRules.spot_ok(world.field, a.pos, 0.2, false):
				a.target = _wander_target(a, 4.0)
				a.state = St.WALK
	match a.kind:
		"cat": _update_cat(a, dt)
		"bird", "heron": _update_bird(a, dt)
		"soarer": _update_soar(a, dt)
		"school": _update_school(a, dt)
		"swarm": _update_swarm(a, dt)
		"swim": _update_swim(a, dt)
		"hopper", "frog": _update_hopper(a, dt)
		_: _update_walker(a, dt)


func _update_leave(a: Animal, dt: float) -> void:
	a.t += dt
	match a.kind:
		"bird", "soarer", "heron":
			a.pos += a.vel * dt
			a.vel.y = minf(a.vel.y + dt * 0.5, 3.5)
			a.phase += dt * 22.0
			a.gait = 0.9
			_face(a, a.vel, dt)
		"school", "swarm", "swim":
			a.fade -= dt * 0.6
		_:
			var arrived: bool = _step(a, 3.2 if a.kind != "seal" else 0.6, dt)
			a.phase += dt * 14.0
			a.gait = 0.6
			if arrived:
				a.fade -= dt * 2.0
	if a.t > 9.0 or a.fade <= 0.0 or (a.t > 1.5 and not _in_view(a.pos)):
		_remove(a)


# --- Behaviours --------------------------------------------------------------------------------

## Foxes, deer, lizards, rats, seals: idle / walk / graze / flee.
func _update_walker(a: Animal, dt: float) -> void:
	var walk_s: float = 0.7
	var run_s: float = 4.5
	var scare: float = 4.0
	var cyc: float = 7.0
	match a.kind:
		"deer":
			walk_s = 0.55
			run_s = 6.0
			scare = 5.5
			cyc = 5.0
		"rat":
			walk_s = 1.6
			run_s = 3.8
			scare = 2.6
			cyc = 26.0
		"lizard":
			walk_s = 1.2
			run_s = 3.5
			scare = 1.8
			cyc = 30.0
		"seal":
			walk_s = 0.25
			run_s = 0.6
			scare = 2.5
			cyc = 3.0
		_:
			if a.sp == "fennec":
				scare = 3.2
	if a.state != St.FLEE and _scared(a, scare):
		a.state = St.FLEE
		a.target = _flee_target(a, 10.0 if a.kind == "deer" else 5.0)
		a.t = 4.0
		if a.kind == "seal" and a.sound_t <= 0.0:
			a.sound_t = 6.0
			_sound_at("seal", a.pos, -6.0)
	match a.state:
		St.FLEE:
			var arrived: bool = _step(a, run_s, dt, 0.3)
			a.phase += dt * run_s * cyc * 0.55
			a.gait = lerpf(a.gait, 0.85 if a.kind == "deer" else 0.6, minf(dt * 6.0, 1.0))
			a.head_pitch = lerpf(a.head_pitch, -0.15, dt * 4.0)
			if a.kind == "deer":
				a.bob = absf(sin(a.phase * 0.5)) * 0.22  # graceful bounds
				a.tail = 0.7
			if arrived or a.t <= 0.0:
				a.state = St.IDLE
				a.t = _rng.randf_range(2.5, 5.0)
				a.home = a.pos
		St.WALK:
			var arrived2: bool = _step(a, walk_s, dt)
			a.phase += dt * walk_s * cyc
			a.gait = lerpf(a.gait, 0.45, minf(dt * 5.0, 1.0))
			a.head_pitch = lerpf(a.head_pitch, 0.3 if a.kind == "deer" else 0.0, dt * 2.0)
			if arrived2:
				a.state = St.GRAZE if a.kind in ["deer", "rat"] or _rng.randf() < 0.4 else St.IDLE
				a.t = _rng.randf_range(3.0, 8.0) if a.kind != "lizard" else _rng.randf_range(6.0, 14.0)
		St.GRAZE:
			a.gait = lerpf(a.gait, 0.0, minf(dt * 5.0, 1.0))
			var down: float = 1.15 if a.kind == "deer" else 0.6
			a.head_pitch = lerpf(a.head_pitch, down + sin(Time.get_ticks_msec() * 0.003 + a.phase) * 0.06, dt * 2.5)
			_relax_head(a, dt)
			if a.kind == "deer" and _lumi_dist(a) < 10.0:
				a.state = St.IDLE  # alert: head up, watch
				a.t = 3.0
			if a.t <= 0.0:
				_next_idle(a)
		_:
			a.gait = lerpf(a.gait, 0.0, minf(dt * 5.0, 1.0))
			a.head_pitch = lerpf(a.head_pitch, -0.1 if a.kind == "deer" else 0.0, dt * 3.0)
			if _lumi_dist(a) < 11.0:
				_look_at_lumi(a, dt, 0.8)
			else:
				a.head_yaw = lerpf(a.head_yaw, sin(Time.get_ticks_msec() * 0.0007 + a.phase) * 0.6, dt)
			a.tail = 0.25 if a.kind in ["quad"] else 0.1
			if a.t <= 0.0:
				_next_idle(a)
	if a.state != St.FLEE:
		a.bob = lerpf(a.bob, 0.0, minf(dt * 6.0, 1.0))


func _next_idle(a: Animal) -> void:
	if _rng.randf() < 0.55:
		a.target = _wander_target(a, 5.0 if a.kind != "rat" else 3.0)
		a.state = St.WALK
	else:
		a.state = St.GRAZE if a.kind in ["deer", "rat"] and _rng.randf() < 0.7 else St.IDLE
		a.t = _rng.randf_range(2.0, 6.0)


func _lumi_dist(a: Animal) -> float:
	return Vector2(a.pos.x - _lumi_pos.x, a.pos.z - _lumi_pos.z).length()


## Rabbits and frogs move in hops.
func _update_hopper(a: Animal, dt: float) -> void:
	var frog: bool = a.kind == "frog"
	var scare: float = 2.2 if frog else 3.5
	if a.state != St.FLEE and _scared(a, scare):
		a.state = St.FLEE
		a.t = 3.0
		if frog:
			# Into the water with a plop; it comes back later.
			var f: HexField = world.field
			for k: int in 12:
				var ang: float = TAU * k / 12.0
				var p: Vector3 = a.pos + Vector3(cos(ang), 0, sin(ang)) * 1.4
				if f.is_water(f.hex_at(p)):
					a.target = p
					break
			if a.target == a.pos or not f.is_water(f.hex_at(a.target)):
				a.target = _flee_target(a, 2.0)
		else:
			a.target = _flee_target(a, 7.0)
	var moving: bool = a.state in [St.FLEE, St.WALK]
	if moving:
		var spd: float = (3.8 if a.state == St.FLEE else 1.2) * (0.7 if frog else 1.0)
		a.phase += dt * (11.0 if a.state == St.FLEE else 7.0)
		var air: float = maxf(sin(a.phase), 0.0)
		a.bob = air * (0.16 if frog else 0.12)
		a.gait = 0.7 * air
		var arrived: bool = _step(a, spd * (0.4 + air), dt, 0.2)
		if frog and a.state == St.FLEE and world.field.is_water(world.field.hex_at(a.pos)):
			Vfx.burst("soil", a.pos + Vector3(0, 0.12, 0), Color(0.7, 0.85, 1.0, 0.8), 0.25)
			_cooldown[a.key] = 40.0
			_remove(a)
			return
		if arrived or (a.state == St.FLEE and a.t <= 0.0):
			if a.state == St.FLEE:
				a.home = a.pos
			a.state = St.IDLE
			a.t = _rng.randf_range(2.0, 6.0)
	else:
		a.bob = lerpf(a.bob, 0.0, minf(dt * 10.0, 1.0))
		a.gait = 0.0
		a.head_pitch = lerpf(a.head_pitch, (0.45 if a.state == St.GRAZE else 0.0), dt * 3.0)
		if a.t <= 0.0:
			if _rng.randf() < 0.5:
				a.state = St.WALK
				a.target = _wander_target(a, 2.5 if frog else 4.0)
			else:
				a.state = St.GRAZE if not frog and _rng.randf() < 0.6 else St.IDLE
				a.t = _rng.randf_range(2.0, 7.0)
		if frog and a.sound_t <= 0.0:
			a.sound_t = _rng.randf_range(4.0, 11.0) * (0.6 if _night > 0.5 else 1.0)
			if _lumi_dist(a) < 18.0:
				_sound_at("frog", a.pos, -8.0)


## Ground birds: peck, toddle, take off as a flock when Lumi comes through, land somewhere else.
func _update_bird(a: Animal, dt: float) -> void:
	var heron: bool = a.kind == "heron"
	if a.state == St.SOAR:
		_update_soar(a, dt)
		return
	if a.state == St.FLY:
		a.phase += dt * (9.0 if heron else (16.0 if a.sp == "pigeon" or a.sp == "gull" else 24.0))
		var to: Vector3 = a.target - a.pos
		var hd: float = Vector2(to.x, to.z).length()
		if a.alt > 0.5:
			# Climbing / cruising: circle out then head for the landing spot.
			var want := Vector3(to.x, 0, to.z).normalized() * (5.0 if not heron else 3.0)
			var cruise: float = maxf(a.alt * 4.0, 2.5)
			want.y = clampf((a.target.y + cruise) - a.pos.y, -2.5, 3.0)
			if hd < 6.0:
				want.y = clampf((a.target.y + hd * 0.35) - a.pos.y, -3.0, 1.0)
			a.vel = a.vel.lerp(want, minf(dt * 2.0, 1.0))
			a.pos += a.vel * dt
			a.gait = 0.95 if a.vel.y > -0.4 else 0.25
			_face(a, a.vel, dt, 4.0)
			a.roll = lerpf(a.roll, clampf(wrapf(atan2(-a.vel.x, -a.vel.z) - a.yaw, -PI, PI) * 2.0, -0.6, 0.6), dt * 3.0)
			if hd < 0.4 and absf(a.pos.y - a.target.y) < 0.4:
				a.pos = a.target
				a.state = St.PECK
				a.alt = 0.0
				a.roll = 0.0
				a.home = a.pos
				a.t = _rng.randf_range(1.0, 3.0)
		return
	# On the ground.
	var scare: float = 3.2 if a.sp == "pigeon" else (4.2 if heron else 3.6)
	if _scared(a, scare):
		_take_off(a, true)
		return
	a.phase += dt * 6.0
	match a.state:
		St.WALK:
			var arrived: bool = _step(a, 0.45 if not heron else 0.3, dt, 0.08)
			a.gait = 0.55
			a.phase += dt * 6.0
			# Pigeons bob their heads as they walk.
			a.head_pitch = sin(a.phase * 2.0) * (0.25 if a.sp == "pigeon" else 0.1)
			if arrived:
				a.state = St.PECK
				a.t = _rng.randf_range(1.0, 4.0)
		St.PECK:
			a.gait = 0.0
			var k: float = fmod(Time.get_ticks_msec() * 0.001 * (2.2 if not heron else 0.4) + a.phase, 3.0)
			a.head_pitch = (1.1 if k < 0.35 else 0.0) if not heron else (1.0 if k < 0.2 else -0.1)
			if a.t <= 0.0:
				if _rng.randf() < 0.6:
					a.state = St.WALK
					a.target = _wander_target(a, 1.5 if not heron else 2.0)
				else:
					a.state = St.IDLE
					a.t = _rng.randf_range(1.0, 3.0)
		_:
			a.gait = 0.0
			a.head_pitch = lerpf(a.head_pitch, -0.1, dt * 5.0)
			a.head_yaw = sin(Time.get_ticks_msec() * 0.002 + a.phase * 3.0) * 0.7
			if a.t <= 0.0:
				a.state = St.PECK
				a.t = _rng.randf_range(1.5, 4.0)
				# Now and then a songbird flits to another spot.
				if a.sp == "songbird" and _rng.randf() < 0.25:
					_take_off(a, false)
	if a.sound_t <= 0.0:
		a.sound_t = _rng.randf_range(3.0, 9.0)
		var dl: float = _lumi_dist(a)
		if a.sp == "songbird" and dl < 28.0:
			a.sound_t = _rng.randf_range(4.0, 12.0)
			_sound_at("song", a.pos, -10.0)
		elif a.sp == "pigeon" and dl < 12.0 and _rng.randf() < 0.5:
			_sound_at("coo", a.pos, -10.0)
		elif a.sp == "sparrow" and dl < 14.0 and _rng.randf() < 0.5:
			_sound_at("chirp", a.pos, -12.0)
		elif a.sp == "gull" and dl < 25.0 and _rng.randf() < 0.3:
			_sound_at("gull", a.pos, -10.0)


func _take_off(a: Animal, scared: bool) -> void:
	var away: Vector3 = a.pos - _lumi_pos
	away.y = 0.0
	away = away.normalized() if away.length() > 0.05 else Vector3.FORWARD.rotated(Vector3.UP, _rng.randf() * TAU)
	var dist: float = _rng.randf_range(10.0, 20.0) if scared else _rng.randf_range(3.0, 6.0)
	var land: Vector3 = Vector3.INF
	var f: HexField = world.field
	for k: int in 8:
		var p: Vector3 = a.pos + away.rotated(Vector3.UP, _rng.randf_range(-0.9, 0.9)) * dist
		var h: int = f.hex_at(p)
		if h >= 0 and (f.is_clean(h) or f.hex_hub[h] != 0) and FaunaRules.spot_ok(f, p, 0.4):
			p.y = _ground_y(p)
			land = p
			break
	if land == Vector3.INF:
		land = a.home
	a.state = St.FLY
	a.target = land
	a.alt = 1.0 if scared else 0.6
	a.vel = away * 2.0 + Vector3(0, 3.5, 0)
	if scared:
		_sound_at("flutter", a.pos, -6.0)
		# The flock goes together.
		for o: Animal in animals:
			if o != a and o.sp == a.sp and o.state != St.FLY and o.state != St.LEAVE and o.state != St.SOAR and o.pos.distance_to(a.pos) < 6.0:
				o.state = St.FLY
				o.target = land + Vector3(_rng.randf_range(-1.2, 1.2), 0, _rng.randf_range(-1.2, 1.2))
				if not FaunaRules.spot_ok(f, o.target, 0.3):
					o.target = land
				o.target.y = _ground_y(o.target)
				o.alt = 1.0
				o.vel = away * _rng.randf_range(1.5, 2.5) + Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf_range(3.0, 4.2), _rng.randf_range(-0.5, 0.5))


## Circling high: cradle cranes, soaring gulls. target = (radius, -, angular speed).
func _update_soar(a: Animal, dt: float) -> void:
	a.t += dt
	var r: float = a.target.x
	var w: float = a.target.z
	var ang: float = a.phase * 0.0 + a.t * w + float(hash(a.key) % 628) * 0.01
	var c: Vector3 = a.home
	a.pos = c + Vector3(cos(ang) * r, a.alt + sin(a.t * 0.3 + a.phase) * 1.5, sin(ang) * r)
	var tangent := Vector3(-sin(ang), 0, cos(ang)) * signf(w)
	a.yaw = atan2(-tangent.x, -tangent.z)
	a.roll = -0.35 * signf(w)
	# Slow flaps, long glides.
	var cyc: float = fmod(a.t + a.phase, 8.0)
	a.gait = 0.55 if cyc < 2.2 else 0.04
	a.phase += dt * (5.0 if cyc < 2.2 else 0.5)
	if a.sp == "gull" and a.sound_t <= 0.0:
		a.sound_t = _rng.randf_range(8.0, 18.0)
		if _lumi_dist(a) < 30.0:
			_sound_at("gull", a.pos, -12.0)


## Fish: a school drifts around the lake hex, darts away when Lumi comes close.
func _update_school(a: Animal, dt: float) -> void:
	var f: HexField = world.field
	var dart: bool = _scared(a, 3.5)
	if dart and a.state != St.FLEE:
		a.state = St.FLEE
		a.t = 1.3
		var away: Vector3 = a.pos - _lumi_pos
		away.y = 0.0
		a.target = a.pos + away.normalized() * 4.0
	var spd: float = 3.2 if a.state == St.FLEE else 0.4
	var to: Vector3 = a.target - a.pos
	to.y = 0.0
	if to.length() < 0.4 or a.t <= -6.0 or (a.state == St.FLEE and a.t <= 0.0):
		a.state = St.SWIM
		a.t = 0.0
		var nt: Vector3 = find_spot(a.sp, a.hex) if a.hex >= 0 else a.pos
		a.target = nt if nt != Vector3.INF else f.hex_center(a.hex)
	var h: int = f.hex_at(a.pos + to.normalized() * 0.8)
	if not f.is_water(h):
		a.target = f.hex_center(a.hex)
		to = a.target - a.pos
		to.y = 0.0
	if to.length() > 0.01:
		a.vel = a.vel.lerp(to.normalized() * spd, minf(dt * (5.0 if a.state == St.FLEE else 1.2), 1.0))
	a.pos += a.vel * dt
	a.pos.y = 0.055
	a.phase += dt * (25.0 if a.state == St.FLEE else 7.0)
	a.gait = 0.9 if a.state == St.FLEE else 0.35
	_face(a, a.vel, dt, 3.0)


## Bees around flowers, fireflies drifting over Thriving ground at night.
func _update_swarm(a: Animal, dt: float) -> void:
	if a.sp == "bee":
		a.state = St.IDLE
		var to: Vector3 = a.target - a.pos
		if to.length() < 0.2 or a.t < -5.0:
			a.t = 0.0
			a.target = _swarm_center(a)
		a.pos += to.limit_length(dt * 0.8)
	a.phase += dt


func _swarm_center(a: Animal) -> Vector3:
	var f: HexField = world.field
	if a.sp == "bee":
		var g: Node = world.get("garden")
		if g:
			var slots: PackedInt32Array = (g.get("hex_slots") as Dictionary).get(a.hex, PackedInt32Array())
			var sp_arr: PackedInt32Array = g.get("slot_species")
			var pos_arr: PackedVector3Array = g.get("slot_pos")
			var opts: Array[Vector3] = []
			for s: int in slots:
				if s < sp_arr.size() and sp_arr[s] >= 0:
					opts.append(pos_arr[s])
			if not opts.is_empty():
				return opts[_rng.randi() % opts.size()] + Vector3(0, 0.45, 0)
	var p: Vector3 = find_spot(a.sp, a.hex) if a.hex >= 0 else Vector3.INF
	return (p if p != Vector3.INF else f.hex_center(a.hex)) + Vector3(0, 0.4 if a.sp == "bee" else 0.6, 0)


## Ducks paddle and dabble; turtles cruise slowly with their heads up.
func _update_swim(a: Animal, dt: float) -> void:
	var f: HexField = world.field
	var duck: bool = a.sp == "duck"
	if _scared(a, 3.0) and a.state != St.FLEE:
		if duck and _lumi_speed > 3.0 and _rng.randf() < 0.5:
			_sound_at("quack", a.pos, -6.0)
			_sound_at("flutter", a.pos, -8.0)
			a.vel = Vector3(0, 3.0, 0)
		a.state = St.FLEE
		a.t = 3.0
		var away: Vector3 = a.pos - _lumi_pos
		away.y = 0.0
		a.target = a.pos + away.normalized() * 3.5
	var to: Vector3 = a.target - a.pos
	to.y = 0.0
	if not f.is_water(f.hex_at(a.target)) or to.length() < 0.3 or a.t < -10.0:
		var nt: Vector3 = find_spot(a.sp, a.hex) if a.hex >= 0 else a.pos
		a.target = nt if nt != Vector3.INF else a.pos
		a.t = 0.0
		if a.state == St.FLEE:
			a.state = St.SWIM
		elif duck and _rng.randf() < 0.3:
			a.state = St.GRAZE  # dabbling: tail up
			a.t = 2.5
	var spd: float = (1.4 if a.state == St.FLEE else 0.3) * (0.5 if not duck else 1.0)
	if a.state != St.GRAZE:
		a.pos += to.limit_length(spd * dt)
		_face(a, to, dt, 2.0)
	elif a.t <= 0.0:
		a.state = St.SWIM
	a.pos.y = HexField.WATER_Y + (-0.005 if duck else -0.04)
	a.phase += dt * 3.0
	a.bob = sin(a.phase) * 0.008
	a.head_pitch = lerpf(a.head_pitch, 1.3 if a.state == St.GRAZE else 0.0, dt * 5.0)
	a.tail = 0.3
	if duck and a.sound_t <= 0.0:
		a.sound_t = _rng.randf_range(6.0, 16.0)
		if _lumi_dist(a) < 16.0:
			_sound_at("quack", a.pos, -10.0)


# --- Cats --------------------------------------------------------------------------------------

func _update_cat(a: Animal, dt: float) -> void:
	a.follow_cool -= dt
	var dl: float = _lumi_dist(a)
	var follow_r: float = 20.0 if a.named else 7.0
	# Startled by Lumi rushing right past (not if he's just standing there).
	if a.state != St.PET and a.state != St.FOLLOW and _lumi_speed > 3.5 and dl < 1.6:
		a.state = St.WALK
		a.target = _flee_target(a, 3.0)
	if a.state == St.PET:
		a.gait = 0.0
		a.head_pitch = lerpf(a.head_pitch, -0.35, dt * 4.0)
		_look_at_lumi(a, dt)
		a.tail = 0.9
		if a.t <= 0.0:
			a.state = St.SIT
			a.t = _rng.randf_range(3.0, 6.0)
		return
	# Follow Lumi a little when he stops nearby.
	if a.state not in [St.FOLLOW, St.SLEEP] and _still_t > 1.2 and dl < follow_r and dl > 1.4 and a.follow_cool <= 0.0:
		a.state = St.FOLLOW
		a.follow_t = 0.0
		if a.sound_t <= 0.0:
			a.sound_t = 12.0
			_sound_at("meow", a.pos, -8.0)
	match a.state:
		St.FOLLOW:
			a.follow_t += dt
			var to: Vector3 = _lumi_pos - a.pos
			to.y = 0.0
			if to.length() > 1.05:
				a.target = _lumi_pos - to.normalized() * 1.0
				var running: bool = to.length() > 4.0
				_step(a, 1.6 if running else 0.75, dt, 0.05)
				a.phase += dt * (16.0 if running else 9.0)
				a.gait = 0.5
				a.tail = 0.15
			else:
				a.gait = lerpf(a.gait, 0.0, dt * 6.0)
				_face(a, to, dt, 3.0)
				_look_at_lumi(a, dt)
				if _still_t > 0.0 and a.follow_t > 2.0:
					a.state = St.SIT  # sits and looks up at him
					a.t = _rng.randf_range(4.0, 9.0)
			var budget: float = 9999.0 if a.named else 25.0
			if a.follow_t > budget or (not a.named and a.pos.distance_to(a.home) > 14.0) or dl > follow_r + 6.0:
				a.state = St.GROOM
				a.t = _rng.randf_range(3.0, 6.0)
				a.follow_cool = 30.0 if not a.named else 3.0
		St.WALK:
			var arrived: bool = _step(a, 0.6, dt, 0.08)
			a.phase += dt * 8.0
			a.gait = 0.42
			a.tail = 0.12
			a.head_pitch = lerpf(a.head_pitch, 0.1, dt * 3.0)
			_relax_head(a, dt)
			if arrived:
				if a.has_meta("to_warm"):
					a.remove_meta("to_warm")
					a.state = St.SLEEP
					a.t = _rng.randf_range(20.0, 45.0)
				else:
					a.state = St.SIT if _rng.randf() < 0.6 else St.IDLE
					a.t = _rng.randf_range(3.0, 8.0)
		St.SLEEP:
			a.gait = 0.0
			a.head_pitch = 0.0
			a.head_yaw = 0.0
			a.tail = 0.0
			if a.t <= 0.0 or (dl < 1.2 and _lumi_speed > 2.0):
				a.state = St.SIT
				a.t = _rng.randf_range(3.0, 6.0)
		_:
			a.gait = lerpf(a.gait, 0.0, dt * 6.0)
			if a.state == St.GROOM:
				# Lick a raised paw.
				a.phase = -PI * 0.5
				a.gait = 0.0
				a.head_pitch = 0.55 + sin(Time.get_ticks_msec() * 0.012) * 0.12
				a.head_yaw = lerpf(a.head_yaw, -0.25, dt * 4.0)
			else:
				a.head_pitch = lerpf(a.head_pitch, -0.05, dt * 3.0)
				if dl < 6.0:
					_look_at_lumi(a, dt, 0.9)
				else:
					a.head_yaw = lerpf(a.head_yaw, sin(Time.get_ticks_msec() * 0.0005 + a.phase) * 0.5, dt)
			a.tail = 0.25
			if a.t <= 0.0:
				var r: float = _rng.randf()
				if r < 0.25 and not _warm.is_empty() and (_night > 0.5 or _rng.randf() < 0.6):
					var w: Vector3 = _nearest_warm(a.pos)
					if w.distance_to(a.pos) < 22.0:
						a.target = w
						a.set_meta("to_warm", true)
						a.state = St.WALK
					else:
						a.state = St.SLEEP
						a.t = _rng.randf_range(20.0, 40.0)
				elif r < 0.45:
					a.state = St.GROOM
					a.t = _rng.randf_range(3.0, 6.0)
				elif r < 0.8:
					a.state = St.WALK
					a.target = _wander_target(a, 4.0)
				else:
					a.state = St.SIT
					a.t = _rng.randf_range(4.0, 10.0)


func _nearest_warm(p: Vector3) -> Vector3:
	var best: Vector3 = p
	var bd: float = INF
	for w: Vector3 in _warm:
		var d: float = w.distance_to(p)
		var taken: bool = false
		for o: Animal in animals:
			if o.kind == "cat" and o.state == St.SLEEP and o.pos.distance_to(w) < 0.8:
				taken = true
		if not taken and d < bd:
			bd = d
			best = w + Vector3(_rng.randf_range(-0.3, 0.3), 0, _rng.randf_range(-0.3, 0.3))
	return best


func _pet_prompt(a: Animal) -> String:
	if a.named:
		return tr("E   pet %s") % a.cat_name
	return tr("E   pet the cat")


func _pet_enabled(a: Animal) -> bool:
	if a.state == St.LEAVE or a.state == St.PET:
		return false
	if world.has_method("near_bench") and bool(world.call("near_bench")):
		return false
	var fs: Node = world.get("first_seed")
	if fs and fs.has_method("near_tin") and bool(fs.call("near_tin", _lumi_pos)):
		return false
	return true


## E on a cat: it sits up, leans in and purrs; a heart rises. Third time: it adopts you.
func pet(a: Animal) -> void:
	a.state = St.PET
	a.t = 2.6
	a.pets += 1
	var to: Vector3 = _lumi_pos - a.pos
	_face(a, to, 1.0, 1.0)
	Audio.play("purr", 1.0, -3.0, 0.05)
	_heart(a.pos + Vector3(0, 0.55, 0))
	var pm: Node = world.patch.get("model") if world.get("patch") else null
	if pm:
		if pm.has_method("look_toward"):
			pm.call("look_toward", a.pos + Vector3(0, 0.2, 0))
		if pm.has_method("set_happy"):
			pm.call("set_happy", 1.0)
	GameState.inc_stat("cats_petted")
	mark_seen("cat")
	if a.pets >= 3 and not a.named and adopted_cat().is_empty():
		adopt(a)


func adopted_cat() -> Dictionary:
	var v: Variant = GameState.flags.get("fauna_cat")
	return v if v is Dictionary else {}


func adopt(a: Animal) -> void:
	var nm: String = CAT_NAMES[absi(hash([district_seed, a.coat, a.key])) % CAT_NAMES.size()]
	var hub: int = int(world.get("hub_index") if world.get("hub_index") != null else 0)
	GameState.flags["fauna_cat"] = {"name": nm, "coat": a.coat, "hub": hub}
	GameState.flags["fauna_cat_named"] = true
	a.named = true
	a.cat_name = nm
	a.key = "named_cat"
	EventBus.toast.emit(tr("The cat has decided you're hers. Meet %s. She lives at this base now.") % nm, "story")
	Audio.play("sparkle", 1.2, -6.0)


func _heart(p: Vector3) -> void:
	if _heart_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var pts := PackedVector2Array()
		for i: int in 40:
			var t: float = TAU * i / 40.0
			pts.append(Vector2(16.0 * pow(sin(t), 3.0), 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)) * 0.006)
		var tris: PackedInt32Array = Geometry2D.triangulate_polygon(pts)
		for k: int in tris:
			st.set_normal(Vector3.BACK)
			st.add_vertex(Vector3(pts[k].x, pts[k].y, 0))
		_heart_mesh = st.commit()
		_heart_mat = StandardMaterial3D.new()
		_heart_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_heart_mat.albedo_color = Color(1.0, 0.42, 0.55)
		_heart_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_heart_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_heart_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mi := MeshInstance3D.new()
	mi.mesh = _heart_mesh
	mi.material_override = _heart_mat.duplicate()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = p
	mi.scale = Vector3.ONE * 0.2
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mi, "global_position", p + Vector3(0, 0.7, 0), 1.6).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mi.material_override, "albedo_color:a", 0.0, 0.6).set_delay(1.0)
	tw.tween_callback(mi.queue_free)


func _hold_pose(a: Animal, dt: float) -> void:
	a.fade = 1.0
	match a.state:
		St.GROOM:
			a.phase = -PI * 0.5
			a.head_pitch = 0.55
		St.GRAZE:
			a.head_pitch = 1.15 if a.kind == "deer" else 0.6
		St.PET, St.SIT, St.FOLLOW:
			_look_at_lumi(a, dt)
			a.head_pitch = -0.3
		St.FLY:
			a.phase += dt * 14.0
			a.gait = 0.9
		St.SOAR:
			_update_soar(a, dt)
		St.SWIM:
			if a.kind == "school":
				_update_school(a, dt)
		_:
			pass
	if a.kind == "swarm":
		_update_swarm(a, dt)


# --- Drawing -----------------------------------------------------------------------------------

func _model_for(a: Animal) -> String:
	match a.kind:
		"cat":
			match a.state:
				St.SIT, St.GROOM, St.PET:
					return "cat_sit"
				St.SLEEP:
					return "cat_curl"
			return "cat"
		"bird", "heron":
			return a.sp + "_fly" if a.state in [St.FLY, St.SOAR, St.LEAVE] else a.sp
		"soarer":
			return a.sp + "_fly"
		"swim":
			return a.sp + ("_fly" if a.sp == "duck" and a.state == St.LEAVE else "")
		"deer":
			return "deer_stag" if hash(a.key) % 3 == 0 else "deer"
		"quad":
			return a.sp
	return a.sp


func _batch(model: String) -> MultiMeshInstance3D:
	if _batches.has(model):
		return _batches[model]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = FaunaModels.mesh(model)
	mm.instance_count = 8
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = "Fauna_" + model
	mi.multimesh = mm
	mi.custom_aabb = AABB(Vector3(-500, -20, -500), Vector3(1000, 120, 1000))
	if is_rigged(mm.mesh):
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://art/shaders/fauna.gdshader")
		var sid: String = model.trim_suffix("_fly").trim_suffix("_sit").trim_suffix("_curl").trim_suffix("_stag")
		var coats: Array = FaunaRules.def(sid).get("coats", ["#ffffff"])
		var pal := PackedVector3Array()
		for k: int in 8:
			var c: Color = Color.html(str(coats[k % coats.size()]))
			pal.append(Vector3(c.r, c.g, c.b))
		mat.set_shader_parameter("coats", pal)
		if sid in ["fish", "frog", "turtle", "seal", "duck"]:
			mat.set_shader_parameter("fur_rim", 0.12)
			mat.set_shader_parameter("roughness_base", 0.5)
		mi.material_override = mat
	if model in ["bee", "fish", "frog", "lizard", "sparrow", "songbird"]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_batches[model] = mi
	return mi


func _put(model: String, xf: Transform3D, custom: Color) -> void:
	var mi: MultiMeshInstance3D = _batch(model)
	var mm: MultiMesh = mi.multimesh
	var n: int = int(_counts.get(model, 0))
	if n >= mm.instance_count:
		var keep: Array = []
		for k: int in n:
			keep.append([mm.get_instance_transform(k), mm.get_instance_custom_data(k)])
		mm.instance_count = mm.instance_count * 2
		for k: int in n:
			mm.set_instance_transform(k, keep[k][0])
			mm.set_instance_custom_data(k, keep[k][1])
	mm.set_instance_transform(n, xf)
	mm.set_instance_custom_data(n, custom)
	_counts[model] = n + 1


## Procedural meshes carry the rig (CUSTOM0); the vendor rat keeps its own materials.
static func is_rigged(m: Mesh) -> bool:
	return m is ArrayMesh and m.get_surface_count() > 0 and ((m as ArrayMesh).surface_get_format(0) & Mesh.ARRAY_FORMAT_CUSTOM0) != 0


static func pack_custom(phase: float, gait: float, head_yaw: float, head_pitch: float, coat: int, tail: float) -> Color:
	var hz: float = floor((clampf(head_yaw, -1.95, 1.95) + 2.0) * 50.0) + clampf((head_pitch + 1.0) / 2.5, 0.0, 1.0) * 0.99
	return Color(fmod(phase, TAU * 64.0), gait, hz, float(coat) * 2.0 + clampf(tail, 0.0, 1.95))


func _draw_all() -> void:
	_counts.clear()
	_glow_n = 0
	var now: float = Time.get_ticks_msec() * 0.001
	for a: Animal in animals:
		var s: float = a.size * clampf(a.fade, 0.0, 1.0)
		if s <= 0.001:
			continue
		match a.kind:
			"school":
				var b := Basis(Vector3.UP, a.yaw)
				for m: Array in a.members:
					var off: Vector3 = m[0]
					var ph: float = float(m[1])
					var wob := Vector3(sin(now * 0.9 + ph) * 0.25, 0, cos(now * 0.7 + ph * 1.3) * 0.2)
					var fy: float = a.yaw + sin(now * 1.3 + ph) * 0.25
					var p: Vector3 = a.pos + b * (off + wob)
					if not world.field.is_water(world.field.hex_at(p)):
						continue
					_put("fish", Transform3D(Basis(Vector3.UP, fy).scaled(Vector3.ONE * s * (0.8 + 0.25 * fmod(ph, 1.0))), p), pack_custom(a.phase + ph, a.gait, 0.0, 0.0, a.coat, 0.0))
			"swarm":
				for m: Array in a.members:
					var off2: Vector3 = m[0]
					var ph2: float = float(m[1])
					var p2: Vector3 = a.pos + Vector3(sin(now * (0.7 + fmod(ph2, 0.5)) + ph2) * off2.x, off2.y + sin(now * 1.7 + ph2) * 0.15, cos(now * (0.6 + fmod(ph2, 0.4)) + ph2 * 1.7) * off2.z)
					if a.sp == "bee":
						var dir: float = now * 2.0 + ph2
						_put("bee", Transform3D(Basis(Vector3.UP, dir).scaled(Vector3.ONE * 1.6 * s), p2), pack_custom(now * 140.0 + ph2, 0.9, 0.0, 0.0, 0, 0.0))
					else:
						var blink: float = clampf(sin(now * (1.3 + fmod(ph2, 0.7)) + ph2 * 5.0) * 2.0 - 0.6, 0.0, 1.0) * clampf(_night * 1.5 - 0.3, 0.0, 1.0) * a.fade
						_put_glow(p2 + Vector3(0, 0.3, 0), blink)
			_:
				var b2 := Basis(Vector3.UP, a.yaw)
				if a.roll != 0.0:
					b2 = b2 * Basis(Vector3.BACK, a.roll)
				if a.kind == "swim" and a.state == St.GRAZE and a.sp == "duck":
					b2 = b2 * Basis(Vector3.RIGHT, -0.9 * clampf(a.head_pitch / 1.3, 0.0, 1.0))
				var breathe: float = 1.0
				if a.kind == "cat" and a.state == St.SLEEP:
					breathe = 1.0 + sin(now * 1.6 + a.phase) * 0.025
				var xf := Transform3D(b2.scaled(Vector3(s, s * breathe, s)), a.pos + Vector3(0, a.bob, 0))
				var model: String = _model_for(a)
				if model == "rat" and not is_rigged(FaunaModels.mesh("rat")):
					xf = Transform3D(xf.basis * _rat_fix(), xf.origin)
				_put(model, xf, pack_custom(a.phase, a.gait, a.head_yaw, a.head_pitch, a.coat, a.tail))
	for model: String in _batches:
		var mm: MultiMesh = (_batches[model] as MultiMeshInstance3D).multimesh
		mm.visible_instance_count = int(_counts.get(model, 0))
	if _glow:
		_glow.multimesh.visible_instance_count = _glow_n


var _rat_basis: Basis = Basis.IDENTITY
var _rat_basis_ok: bool = false


## The Poly Haven rat's own scale and facing, normalised to ~0.32 m nose to tail-base, facing -Z.
func _rat_fix() -> Basis:
	if _rat_basis_ok:
		return _rat_basis
	_rat_basis_ok = true
	var m: Mesh = FaunaModels.mesh("rat")
	var bb: AABB = m.get_aabb()
	var longest: float = maxf(bb.size.x, bb.size.z)
	var k: float = 0.42 / maxf(longest, 0.001)
	var b := Basis.from_scale(Vector3.ONE * k)
	if bb.size.x > bb.size.z:
		b = Basis(Vector3.UP, PI * 0.5) * b
	_rat_basis = b
	return b


func _put_glow(p: Vector3, a: float) -> void:
	if a <= 0.02:
		return
	if _glow == null:
		var q := QuadMesh.new()
		q.size = Vector2(0.14, 0.14)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.vertex_color_use_as_albedo = true
		mat.no_depth_test = false
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 0.8, 1))
		g.set_color(1, Color(0.6, 1.0, 0.3, 0))
		g.add_point(0.25, Color(0.85, 1.0, 0.45, 0.8))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 64
		gt.height = 64
		mat.albedo_texture = gt
		q.material = mat
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = q
		mm.instance_count = 256
		mm.visible_instance_count = 0
		_glow = MultiMeshInstance3D.new()
		_glow.name = "Fireflies"
		_glow.multimesh = mm
		_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_glow.custom_aabb = AABB(Vector3(-500, -20, -500), Vector3(1000, 120, 1000))
		add_child(_glow)
	if _glow_n >= _glow.multimesh.instance_count:
		return
	_glow.multimesh.set_instance_transform(_glow_n, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * (0.6 + 0.6 * a)), p))
	_glow.multimesh.set_instance_color(_glow_n, Color(1, 1, 1, a))
	_glow_n += 1


# --- Sightings, photos, sound ------------------------------------------------------------------

func seen_list() -> Array:
	var v: Variant = GameState.flags.get("fauna_seen")
	if not (v is Array):
		v = []
		GameState.flags["fauna_seen"] = v
	return v


func photo_list() -> Array:
	var v: Variant = GameState.flags.get("fauna_photos")
	if not (v is Array):
		v = []
		GameState.flags["fauna_photos"] = v
	return v


## First sighting of a species: Codex entry, a quiet toast, achievement flags.
func mark_seen(sid: String) -> bool:
	if sid == "deer":
		GameState.flags["seen_deer"] = true
	if sid == "fish":
		GameState.flags["seen_fish"] = true
	if sid in seen_list():
		return false
	seen_list().append(sid)
	GameState.inc_stat("animals_spotted")
	Codex.unlock("animals:" + sid)
	_toast_q.append(tr("New sighting: %s. It's in the Codex now.") % tr(str(FaunaRules.def(sid).get("name", sid))))
	return true


func _sightings() -> void:
	if _cam == null:
		return
	for a: Animal in animals:
		if a.seen or a.state == St.LEAVE or a.fade < 0.9:
			continue
		var reach: float = 14.0 if a.kind in ["swarm", "school", "frog", "lizard", "rat"] else 26.0
		if a.kind == "soarer":
			reach = 60.0
		if a.kind == "swarm" and a.sp == "firefly" and _night < 0.5:
			continue
		var p: Vector3 = a.pos + Vector3(0, 0.2, 0)
		if p.distance_to(_lumi_pos) < reach and _cam.is_position_in_frustum(p):
			a.seen = true
			mark_seen(a.sp)


## Photo mode capture: the animals in frame (close enough to make out) go into the Collection.
func _on_photo(_path: String) -> void:
	var ph: Node = world.get("photo")
	var cam: Camera3D = ph.call("camera") if ph and ph.has_method("camera") else _cam
	var got: Array[String] = photo_subjects(cam)
	for sid: String in got:
		record_photo(sid)


## Species clearly in a camera's frame (projected size >= ~4% of the view height).
func photo_subjects(cam: Camera3D) -> Array[String]:
	var out: Array[String] = []
	if cam == null:
		return out
	var vh: float = float(cam.get_viewport().get_visible_rect().size.y) if cam.get_viewport() else 720.0
	for a: Animal in animals:
		if a.state == St.LEAVE or a.sp in out:
			continue
		var p: Vector3 = a.pos + Vector3(0, 0.25 * a.size, 0)
		if not cam.is_position_in_frustum(p):
			continue
		var d: float = cam.global_position.distance_to(p)
		var body: float = _body_size(a)
		var proj: float = body / maxf(d * 2.0 * tan(deg_to_rad(cam.fov) * 0.5), 0.001)
		if proj >= 0.04 or (a.kind in ["swarm", "school"] and d < 6.0):
			out.append(a.sp)
	if vh <= 0.0:
		return out
	return out


func _body_size(a: Animal) -> float:
	match a.kind:
		"deer", "heron", "soarer": return 1.2
		"cat", "quad", "seal": return 0.55
		"bird", "swim", "hopper": return 0.3
	return 0.2


func record_photo(sid: String) -> bool:
	mark_seen(sid)
	if sid in photo_list():
		return false
	photo_list().append(sid)
	GameState.inc_stat("animal_photos")
	var first: bool = Collection.grant("pic_" + sid, true)
	var ph: Node = world.get("photo")
	var msg: String = tr("Snap! A %s for your Collection.") % tr(str(FaunaRules.def(sid).get("name", sid)))
	if ph and ph.has_method("toast") and bool(ph.get("is_open")):
		ph.call("toast", msg)
	else:
		EventBus.toast.emit(msg, "story")
	return first


## A one-shot animal sound, quieter with distance from the camera.
func _sound_at(sound: String, p: Vector3, db: float) -> void:
	var d: float = (_cam.global_position if _cam else _lumi_pos).distance_to(p)
	var att: float = -20.0 * log(maxf(d, 2.0) / 2.0) / log(10.0)
	if db + att < -40.0:
		return
	Audio.play(sound, 1.0, db + att, 0.08)


func _ambience(delta: float) -> void:
	# Crickets at night once the ground is growing again.
	var want: float = _night * clampf(_green_share * 2.5, 0.0, 1.0)
	_cricket_vol = move_toward(_cricket_vol, want, delta * 0.2)
	if _cricket_vol > 0.01:
		if not _crickets.playing:
			_crickets.play()
		_crickets.volume_db = linear_to_db(_cricket_vol) - 8.0
	elif _crickets.playing:
		_crickets.stop()


# --- Dev hooks ---------------------------------------------------------------------------------

## --fauna-look=SPECIES[,dist,pitch,yaw]: put Lumi beside the nearest one and frame both.
func _dev_look() -> void:
	if Time.get_ticks_msec() * 0.001 < DevHooks.get_f("fauna-look-at", 5.0):
		return
	var parts: PackedStringArray = DevHooks.get_s("fauna-look", "cat").split(",")
	var sid: String = parts[0]
	var best: Animal = null
	for a: Animal in animals:
		if a.sp == sid and a.state != St.LEAVE and (best == null or a.pos.distance_to(_lumi_pos) < best.pos.distance_to(_lumi_pos)):
			best = a
	if best == null:
		if Time.get_ticks_msec() * 0.001 > DevHooks.get_f("fauna-look-at", 5.0) + 20.0:
			_look_done = true
			print("[fauna] look: no %s here (%s)" % [sid, str(census())])
		return
	_look_done = true
	var a: Animal = best
	var patch: Node3D = world.patch
	var side: float = float(parts[4]) if parts.size() > 4 else 1.0
	var gap: float = 1.1 if a.kind == "cat" else (3.5 if a.kind in ["deer", "bird", "swim", "school"] else 2.0)
	if DevHooks.has("fauna-gap"):
		gap = DevHooks.get_f("fauna-gap", gap)
	var dir := Vector3(sin(a.yaw + 0.9 * side), 0, cos(a.yaw + 0.9 * side)) * -1.0
	var lp: Vector3 = a.pos + dir * gap
	if a.kind in ["school", "swim"]:
		lp = a.pos + dir * gap
		var f: HexField = world.field
		for k: int in 16:
			var cand: Vector3 = a.pos + Vector3(cos(TAU * k / 16.0), 0, sin(TAU * k / 16.0)) * gap
			if not f.is_water(f.hex_at(cand)):
				lp = cand
				break
	patch.global_position = Vector3(lp.x, _ground_y(lp) + 0.05, lp.z)
	var to: Vector3 = a.pos - lp
	patch.rotation.y = atan2(to.x, to.z)
	if a.kind == "cat":
		a.yaw = atan2(-(lp.x - a.pos.x), -(lp.z - a.pos.z))
	a.hold = true
	var pose: String = DevHooks.get_s("fauna-pose", "")
	match pose:
		"sit": a.state = St.SIT
		"groom": a.state = St.GROOM
		"sleep": a.state = St.SLEEP
		"pet":
			a.state = St.PET
			_heart(a.pos + Vector3(0, 0.55, 0))
		"graze": a.state = St.GRAZE
		"fly":
			a.state = St.FLY
			a.pos.y += 1.5
		"": a.hold = DevHooks.has("fauna-hold")
	if pose == "pet":
		var pm: Node = patch.get("model")
		if pm and pm.has_method("set_happy"):
			pm.call("set_happy", 1.0)
	var cam: Node = world.get("cam")
	if cam:
		var yaw_off: float = float(parts[3]) if parts.size() > 3 else 0.6
		cam.set("yaw", patch.rotation.y + PI + yaw_off)
		cam.set("distance", float(parts[1]) if parts.size() > 1 else 3.2)
		cam.set("pitch", float(parts[2]) if parts.size() > 2 else -0.22)
		if cam.has_method("snap"):
			cam.call("snap")
	print("[fauna] look: %s at %s, Lumi at %s" % [sid, str(a.pos), str(patch.global_position)])
