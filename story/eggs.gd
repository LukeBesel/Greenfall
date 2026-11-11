class_name EasterEggs
extends Node3D
## Small original secrets spread through the districts (data/eggs.json). Each district gets a
## deterministic set of eggs at deterministic spots (seeded by the district's field seed).
## Found eggs give a toast, a small reward, a WREN line, flags["egg_<id>"] and stats.eggs_found;
## they stay in the world afterwards as little landmarks you can still poke.

var world: Node
var defs: Dictionary = {}
var order: Array[String] = []
var placed: Array[Dictionary] = []  # {id, part, node, def, hex, final}
var _tick: float = 0.0
var _t: float = 0.0
var _stars: Node3D
var _star_mat: StandardMaterial3D
var _jukebox_player: AudioStreamPlayer3D
var _jukebox_node: Node3D
var _note_t: float = 0.0
var _watch: Dictionary = {}  # id -> seconds watched
var _ring_cd: float = 0.0
var _scoop_cd: Dictionary = {}
## [eggs2] Where Lumi starts (scenes/slice.gd SPAWN): far-out eggs measure from here.
const SPAWN_Z: float = 3.0
## [eggs2] Where WREN's constellation hangs in the sky (the telescope aims here).
const STAR_POS := Vector3(80, 260, -140)  # high (~58 deg) so streets and towers rarely hide it
var _peek: Node  # [eggs2] StarPeek while looking through the telescope
var _tv: Node  # [eggs2] TvBroadcast while it plays
var _dev_use: Dictionary = {}  # [eggs2] dev --egg-use target
const JUKEBOX_LEAVE_M: float = 12.0  # [eggs2]
var _jukebox_on: bool = false  # [eggs2] the waltz is playing (the score is hushed)


static var _data_cache: Dictionary = {}
static var _defs_cache: Dictionary = {}
static var _order_cache: Array[String] = []  # [v6qa] data/eggs.json, parsed once (each hub switch parsed it again)


func setup() -> void:
	if _data_cache.is_empty():
		_data_cache = Economy.read_json("res://data/eggs.json")
		for e: Dictionary in _data_cache.get("eggs", []):
			_defs_cache[str(e["id"])] = e
			_order_cache.append(str(e["id"]))
	var data: Dictionary = _data_cache  # read only
	defs = _defs_cache.duplicate()  # (the entries are shared and read only)
	order = _order_cache.duplicate()
	StorySfx.ensure()
	if world.field is SphereField:  # [orbB] the globe: this hub's eggs, planned in the hub frame
		_setup_globe(data)
		return
	var wild: bool = world.field.layout != null and world.field.layout.wild
	var ids: Array[String] = district_eggs(order, defs, GameState.current_hub, world.field.seed_value, int(data.get("per_district", 9)),
		wild, world.field.biome, int(data.get("wild_per_district", 4)))
	var avoid: Array[Vector3] = [Vector3.ZERO, FirstSeed.GREENHOUSE_POS, Intro.POD_POS]
	avoid.append((LedgerArc.relay_spot(world.field)["pos"] as Vector3))
	for s: Dictionary in Outposts.plan(world.field):  # [outposts] keep eggs off the outpost slabs
		avoid.append(s["pos"] as Vector3)
	if DevHooks.has("museum-sample"):  # [eggs2] dev: a partly filled collection
		Museum.dev_sample()
	if DevHooks.has("egg-parts"):  # [eggs2] dev: --egg-parts=ID marks every part of a collectible egg as collected
		var pid: String = DevHooks.get_s("egg-parts", "gnomes")
		if defs.has(pid):
			for i: int in int(defs[pid].get("parts", 1)):
				EggCollect.add(pid, i)
	var plan: Array[Dictionary] = plan_spots(world.field, ids, defs, avoid)
	for p: Dictionary in plan:
		_spawn(p)
	print("[eggs] district %d: %d eggs, %d props placed" % [GameState.current_hub, ids.size(), placed.size()])
	if _jukebox_node:
		StorySfx.prewarm_music_box()
	_build_stars()
	_migrate_collected()  # [eggs2]
	Museum.attach.call_deferred(world)  # [eggs2] the late Museum build (Cradle Returns, after the Cradle answers)
	EventBus.junk_scooped.connect(_on_scooped)
	EventBus.hex_cleaned.connect(func(_h: int, _p: Vector3, _b: BigNum) -> void: _refresh_visibility())
	_refresh_visibility()
	if DevHooks.has("spawn-egg"):
		_dev_spawn.call_deferred(DevHooks.get_s("spawn-egg", "duck"))


# --- [orbB] The globe: eggs per hub, in the hub frame (planet/orbit/hub_frame.gd) -----------

var hub_index: int = 0  # the hub whose eggs these are (set by the frame host)
var frame_cells := PackedInt32Array()  # that hub's region


func _setup_globe(data: Dictionary) -> void:
	# [v5load] Behind the loading screen this plans and spawns across frames (the caller waits with
	# BuildBudget.idle()); without a budget it runs in one go, as before.
	BuildBudget.busy += 1
	var f: SphereField = world.field
	var ids: Array[String] = district_eggs(order, defs, hub_index, f.seed_value + hub_index * 977, int(data.get("per_district", 9)),
		hub_index != 0, "", int(data.get("wild_per_district", 4)))
	await BuildBudget.check("eggs:pick")
	var avoid: Array[Vector3] = [Vector3.ZERO]
	var so: Node = world.get("orbit")
	if so:  # the yard's anchors (bench, bin, pod, tower, ...) stay clear
		for nm: String in ["bench", "depot", "bin", "pod", "signal_tower", "telescope", "radio", "locker", "nursery", "rocket_pad", "stations"]:
			avoid.append(to_local(so.call("yard_point", nm)))
	for s: Dictionary in Outposts.plan_cells(self, f, frame_cells, {}, hub_index):  # keep off the outpost slabs
		avoid.append(s["pos"] as Vector3)
	await BuildBudget.check("eggs:outposts")
	avoid.append(LedgerArc.relay_spot_cells(self, f, frame_cells, hub_index)["pos"] as Vector3)  # and the Ledger's relay
	await BuildBudget.check("eggs:relay")
	var plan: Array[Dictionary] = plan_spots_cells(self, f, frame_cells, ids, defs, avoid, f.seed_value + 9091 + hub_index * 31)
	for p: Dictionary in plan:
		await BuildBudget.check("eggs:spawn")
		_spawn(p)
	BuildBudget.busy -= 1
	print("[eggs] hub %d: %d eggs, %d props placed" % [hub_index, ids.size(), placed.size()])
	if _jukebox_node:
		StorySfx.prewarm_music_box()
	_migrate_collected()
	EventBus.junk_scooped.connect(_on_scooped)
	EventBus.hex_cleaned.connect(func(_h: int, _p: Vector3, _b: BigNum) -> void: _refresh_visibility())
	_refresh_visibility()


## plan_spots for a globe hub region, in `frame`'s local metres (+Y up): open, clean-able land away
## from the yard, wrecks, heaps, water and each other. Deterministic per hub.
static func plan_spots_cells(frame: Node3D, f: SphereField, cells: PackedInt32Array, ids: Array[String], all_defs: Dictionary, avoid: Array[Vector3], seed_v: int) -> Array[Dictionary]:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var used: Array[Vector3] = avoid.duplicate()
	var out: Array[Dictionary] = []
	var hexes: Array[int] = []
	for c: int in cells:
		if f.hex_hub[c] == 0 and not f.is_water(c):
			hexes.append(c)
	if hexes.is_empty():
		return out
	var lms: Array[Vector3] = []
	for lm: Dictionary in f.landmarks:
		lms.append(frame.to_local(lm["pos"]))
	for egg_id: String in ids:
		var d: Dictionary = all_defs[egg_id]
		var n_parts: int = int(d.get("parts", 1))
		var has_final: bool = d.has("final")
		var min_r: float = maxf(15.0, float(d.get("min_spawn_dist", 0.0)))
		for part: int in n_parts + (1 if has_final else 0):
			var best := Vector3.INF
			var best_hex: int = -1
			for attempt: int in 120:
				var hid: int = hexes[r.randi() % hexes.size()]
				var c: Vector3 = frame.to_local(f.hex_center(hid))
				var p: Vector3 = c + Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)) * f.hex_size * 0.6
				var wp: Vector3 = f.terrain.ground(frame.to_global(p).normalized())
				if f.hex_at(wp) != hid or Vector2(p.x, p.z).length() < min_r or f.ground_height(hid, wp) > 0.05:
					continue
				if f.keep_out.is_valid() and bool(f.keep_out.call(wp.normalized())):
					continue  # [v3city] not inside a town building or a parked wreck
				var min_d: float = 9.0 if attempt < 70 else 5.0
				var clash: bool = false
				for u: Vector3 in used + lms:
					if Vector2(u.x - p.x, u.z - p.z).length() < min_d:
						clash = true
						break
				if clash:
					continue
				var tr_: TargetReach = TargetReach.for_field(f)  # [v4world] #55: reachable (not walled in, steep or wet)
				if tr_ and tr_.reach(wp) != "":
					continue
				best = frame.to_local(wp)
				best_hex = hid
				break
			if best == Vector3.INF:
				continue
			used.append(best)
			var yaw: float = atan2(-best.x, -best.z) + r.randf_range(-0.35, 0.35)  # facing back toward the hub
			out.append({"id": egg_id, "part": part, "final": has_final and part == n_parts, "pos": best, "yaw": yaw, "hex": best_hex})
	return out


# --- Placement (pure, deterministic) -------------------------------------------------

## Which eggs live in a district: Old Town (hub 0) gets the starter set; others a seeded pick.
## Eggs with where = "wild" only appear in wilderness districts, which take up to `wild_n` of them
## first (eggs whose "biome" matches the district's go to the front), then fill from the rest.
static func district_eggs(all_ids: Array[String], all_defs: Dictionary, hub: int, seed_v: int, per_district: int,
		wild: bool = false, biome: String = "", wild_n: int = 4) -> Array[String]:
	var out: Array[String] = []
	if hub == 0:
		for id: String in all_ids:
			if bool(all_defs[id].get("starter", false)):
				out.append(id)
		out.append_array(EggPropsLate.new_world_eggs(all_ids, all_defs))  # [late] Cradle Mode worlds' own finds
		return out
	var r := RandomNumberGenerator.new()
	r.seed = seed_v + 313
	var general: Array[String] = []
	var wild_ids: Array[String] = []
	out.append_array(EggPropsLate.frontier_eggs(all_ids, all_defs, biome))  # [late] frontier-only eggs go first
	for id: String in all_ids:
		if str(all_defs[id].get("where", "")) in ["frontier", "new_world"]:  # [late]
			continue
		if str(all_defs[id].get("where", "")) == "wild":
			wild_ids.append(id)
		else:
			general.append(id)
	_shuffle(general, r)
	if wild and not wild_ids.is_empty():
		_shuffle(wild_ids, r)
		var match_first: Array[String] = []
		for id: String in wild_ids:
			if biome != "" and str(all_defs[id].get("biome", "")) == biome:
				match_first.append(id)
		for id: String in wild_ids:
			if not (id in match_first):
				match_first.append(id)
		for i: int in mini(mini(wild_n, per_district), match_first.size()):
			out.append(match_first[i])
	for id: String in general:
		if out.size() >= per_district:
			break
		out.append(id)
	return out


static func _shuffle(pool: Array[String], r: RandomNumberGenerator) -> void:
	for i: int in range(pool.size() - 1, 0, -1):
		var j: int = r.randi_range(0, i)
		var tmp: String = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp


## Deterministic spots for every part of every egg. Open ground (lots, sidewalks; roads only as
## a fallback), away from the hub yard, buildings, junk mounds, water, landmarks and each other.
static func plan_spots(field: HexField, ids: Array[String], all_defs: Dictionary, avoid: Array[Vector3]) -> Array[Dictionary]:
	var r := RandomNumberGenerator.new()
	r.seed = field.seed_value + 9091
	var used: Array[Vector3] = avoid.duplicate()
	var out: Array[Dictionary] = []
	var hexes: Array[int] = []
	for id: int in field.hex_count():
		if field.hex_hub[id] == 0 and not field.is_water(id):
			hexes.append(id)
	if hexes.is_empty():
		return out
	for egg_id: String in ids:
		var d: Dictionary = all_defs[egg_id]
		var n_parts: int = int(d.get("parts", 1))
		var has_final: bool = d.has("final")
		var wide: float = 2.8 if str(d.get("kind", "")) in ["mural", "bench_bots"] else 0.8
		for part: int in n_parts + (1 if has_final else 0):
			var best := Vector3.INF
			var best_hex: int = -1
			for attempt: int in 90:
				var hid: int = hexes[r.randi() % hexes.size()]
				var p: Vector3 = field.hex_center(hid) + Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)) * field.hex_size * 0.7
				if field.hex_at(p) != hid or Vector2(p.x, p.z).length() < 15.0:
					continue
				if not _open_ground(field, p, wide, attempt > 60):
					continue
				var min_d: float = 9.0 if attempt < 50 else 5.0
				var clash: bool = false
				for u: Vector3 in used:
					if Vector2(u.x - p.x, u.z - p.z).length() < min_d:
						clash = true
						break
				if not clash:
					for lm: Dictionary in field.landmarks:
						if (lm["pos"] as Vector3).distance_to(Vector3(p.x, (lm["pos"] as Vector3).y, p.z)) < 3.5:
							clash = true
							break
				if not clash:
					for pile: Vector4 in field.hex_piles[hid]:
						if Vector2(p.x - pile.x, p.z - pile.y).length() < pile.z + 1.0:
							clash = true
							break
				if clash:
					continue
				best = p
				best_hex = hid
				break
			if best == Vector3.INF:
				continue
			best.y = clampf(field.layout.height_at(best.x, best.z), 0.0, 0.3) if field.layout else 0.0
			used.append(best)
			# Face back toward the hub (where Patch usually comes from), with a little wobble.
			var yaw: float = atan2(-best.x, -best.z) + r.randf_range(-0.35, 0.35)
			out.append({"id": egg_id, "part": part, "final": has_final and part == n_parts, "pos": best, "yaw": yaw, "hex": best_hex})
	# [eggs2] Eggs that must stand away from the spawn move out in a second pass: their first spot
	# stays reserved, so every other egg lands exactly where it always did.
	for o: Dictionary in out:
		var od: Dictionary = all_defs[o["id"]]
		if float(od.get("min_spawn_dist", 0.0)) > 0.0:
			var far: Vector3 = _far_spot(field, od, used, hexes)
			if far != Vector3.INF:
				used.append(far)
				o["pos"] = far
				o["hex"] = field.hex_at(far)
				o["yaw"] = atan2(-far.x, -far.z)
	return out


## [eggs2] A spot at least min_spawn_dist from the spawn (and not much further), on open ground
## clear of the other eggs; spot "corner" prefers a sidewalk corner with roads on two sides.
## Its own RNG, so moving one egg never reshuffles the others.
static func _far_spot(field: HexField, d: Dictionary, used: Array[Vector3], hexes: Array[int]) -> Vector3:
	var r := RandomNumberGenerator.new()
	r.seed = field.seed_value + 7177
	var min_r: float = float(d.get("min_spawn_dist", 0.0))
	var corner: bool = str(d.get("spot", "")) == "corner" and field.layout != null
	for attempt: int in 600:
		var hid: int = hexes[r.randi() % hexes.size()]
		var p: Vector3 = field.hex_center(hid) + Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)) * field.hex_size * 0.7
		var rad: float = Vector2(p.x, p.z - SPAWN_Z).length()
		if field.hex_at(p) != hid or rad < min_r or rad > min_r + 22.0:
			continue
		if not _open_ground(field, p, 0.8, attempt > 450):
			continue
		if corner and attempt < 400 and not is_corner(field, p):
			continue
		var clash: bool = false
		for u: Vector3 in used:
			if Vector2(u.x - p.x, u.z - p.z).length() < 7.0:
				clash = true
				break
		for lm: Dictionary in field.landmarks:
			if not clash and (lm["pos"] as Vector3).distance_to(Vector3(p.x, (lm["pos"] as Vector3).y, p.z)) < 3.5:
				clash = true
		for pile: Vector4 in field.hex_piles[hid]:
			if not clash and Vector2(p.x - pile.x, p.z - pile.y).length() < pile.z + 1.5:
				clash = true
		if clash:
			continue
		p.y = clampf(field.layout.height_at(p.x, p.z), 0.0, 0.3) if field.layout else 0.0
		return p
	return Vector3.INF


## [eggs2] Sidewalk with road a few metres off along both a street and a cross street.
static func is_corner(field: HexField, p: Vector3) -> bool:
	if field.layout == null or field.layout.surface_at(p.x, p.z) != CityLayout.Surface.SIDEWALK:
		return false
	var road_x: bool = false
	var road_z: bool = false
	for dd: float in [1.5, 3.0, 4.5]:
		for sg: float in [-1.0, 1.0]:
			road_x = road_x or field.layout.surface_at(p.x + sg * dd, p.z) == CityLayout.Surface.ROAD
			road_z = road_z or field.layout.surface_at(p.x, p.z + sg * dd) == CityLayout.Surface.ROAD
	return road_x and road_z


static func _open_ground(field: HexField, p: Vector3, wide: float, allow_road: bool) -> bool:
	if field.layout == null:
		return true
	var probes: Array[Vector3] = [Vector3.ZERO, Vector3(wide, 0, 0), Vector3(-wide, 0, 0), Vector3(0, 0, wide), Vector3(0, 0, -wide)]
	# Keep clear of facades too (gaps between buildings read as doorways): a ring at 2.4 m.
	for k: int in 8:
		probes.append(Vector3(cos(TAU * k / 8.0), 0, sin(TAU * k / 8.0)) * maxf(2.4, wide + 0.8))
	for o: Vector3 in probes:
		var s: int = field.layout.surface_at(p.x + o.x, p.z + o.z)
		if s == CityLayout.Surface.BUILDING or s == CityLayout.Surface.YARD:
			return false
		if s == CityLayout.Surface.ROAD and not allow_road and o == Vector3.ZERO:
			return false
	return true


# --- Spawning ------------------------------------------------------------------------

static func is_found(id: String) -> bool:
	return bool(GameState.flags.get("egg_" + id, false))


static func found_count() -> int:
	return (GameState.flags.get("eggs_found", []) as Array).size()


func _parts_seen(id: String) -> Array:
	return EggCollect.parts(id)  # [eggs2] ints, also after a load


func _spawn(p: Dictionary) -> void:
	var d: Dictionary = defs[str(p["id"])]
	var kind: String = str(d.get("final", "")) if bool(p["final"]) else str(d.get("kind", ""))
	var node: Node3D = EggProps.build(kind, int(p["part"]))
	node.name = "Egg_%s_%d" % [p["id"], p["part"]]
	add_child(node)
	node.position = p["pos"]  # [orbB] (this node sits at the origin on the flat game; in the hub frame on the globe)
	node.rotation.y = float(p["yaw"])
	if world.field is SphereField:  # [orbB] solid on the globe: a box from its own bounds
		OrbitUp.fit_box(node)
	else:
		PropColliders.fit(PropColliders.body(node, "Props"), node)  # [world2] egg props are solid (off while hidden)
	var e: Dictionary = p.duplicate()
	e["node"] = node
	e["def"] = d
	e["kind"] = kind
	placed.append(e)
	if kind == "jukebox":
		_jukebox_node = node
	if is_found(str(p["id"])):
		_show_found_state(node, kind)
	elif EggPower.applies(kind):  # [qafix] world3: machines are dead until Lumi pokes them
		EggPower.kill(node)
	if bool(d.get("collect", false)) and EggCollect.has_part(str(p["id"]), int(p["part"])):  # [eggs2] already brought home
		node.visible = false
	if kind == "telescope":  # [eggs2] the tube points at the Wren
		var to: Vector3 = STAR_POS - node.global_position
		node.rotation.y = atan2(-to.z, to.x)
		var head: Node3D = node.get_node_or_null("Anim")
		if head:
			head.rotation.z = atan2(to.y, Vector2(to.x, to.z).length()) * 0.6
	var prompt: String = tr(str(d.get("final_prompt", ""))) if bool(p["final"]) else tr(str(d.get("prompt", "")))
	if prompt != "" and world.get("interactables") != null:
		world.interactables.register(node, float(d.get("use_range", 2.6)), prompt, _use.bind(e))


## Found eggs keep the change Patch made: the sock is gone, the fire is lit, the stone is on top.
static func _show_found_state(node: Node3D, kind: String) -> void:
	EggPropsLate.show_found_state(node, kind)  # [late]
	match kind:
		"clothesline", "fishing_net":
			var prize: Node3D = node.get_node_or_null("Anim/Prize")
			if prize:
				prize.visible = false
		"cairn":
			var top: Node3D = node.get_node_or_null("Anim/Top")
			if top:
				top.visible = true
		"campfire":
			var fl: Node3D = node.get_node_or_null("Flame")
			var l: OmniLight3D = node.get_node_or_null("Light")
			if fl:
				fl.visible = true
			if l:
				l.light_energy = 1.6
		"drill_press":
			var b: Node3D = node.get_node_or_null("Bolt")
			if b:
				b.visible = true


func _refresh_visibility() -> void:
	for e: Dictionary in placed:
		var n: Node3D = e["node"]
		var id: String = e["id"]
		var trig: String = str(e["def"].get("trigger", ""))
		if trig == "clean":
			var was: bool = n.visible
			n.visible = is_found(id) or world.field.is_clean(int(e["hex"]))
			PropColliders.set_active(n, n.visible)  # [world2]
			if n.visible and not was and not is_found(id):
				Vfx.burst("sparkle", n.global_position + OrbitUp.up(n.global_position) * 0.5, Color(0.6, 0.95, 1.0))
				EventBus.toast.emit(tr("Something metal surfaced in the cleared ground."), "info")
		elif bool(e["final"]):
			n.visible = is_found(id) or _parts_seen(id).size() >= int(e["def"].get("parts", 1))
			PropColliders.set_active(n, n.visible)  # [world2]


func _dev_spawn(id: String) -> void:
	for e: Dictionary in placed:
		if e["id"] == id and (not bool(e["final"]) or id != "lost_cat"):
			var n: Node3D = e["node"]
			n.visible = true
			var fwd: Vector3 = n.global_transform.basis.z
			var p: Vector3 = n.global_position + fwd * float(DevHooks.get_f("egg-dist", 2.4)) + n.global_transform.basis.x * 1.5
			world.patch.global_position = Vector3(p.x, n.global_position.y + 0.2, p.z)
			world.patch.rotation.y = atan2(p.x - n.global_position.x, p.z - n.global_position.z)  # -Z (forward) toward the egg
			var rig: Variant = world.get("cam")  # [v6flat] the flat rig's framing (none on the globe)
			if rig:
				rig.yaw = world.patch.rotation.y + DevHooks.get_f("egg-yaw", 0.4)
				rig.snap()
			if DevHooks.has("egg-use"):  # [eggs2] dev: --egg-use[=S] presses E on it S wall-clock s after start
				_dev_use = e
			if DevHooks.has("egg-cam") and rig:  # [eggs2] dev: camera distance for egg shots
				rig.distance = DevHooks.get_f("egg-cam", 4.0)
				rig.snap()
			if DevHooks.has("egg-poke"):
				get_tree().create_timer(DevHooks.get_f("egg-poke", 0.5), false).timeout.connect(func() -> void: _effect(e))
			print("[eggs] spawned next to %s at %s (patch %s, yaw %.2f)" % [id, str(n.global_position), str(world.patch.global_position), world.patch.rotation.y])
			return
	print("[eggs] egg '%s' is not placed in this district (placed: %s)" % [id, str(placed.map(func(e: Dictionary) -> String: return e["id"]))])


# --- Stars (the WREN constellation) -----------------------------------------------------

const STAR_PATTERN: Array = [
	# The bird: five stars.
	[0.0, 3.2], [1.2, 3.8], [2.2, 3.4], [3.0, 3.9], [1.6, 2.6],
]
const LETTERS: Dictionary = {
	"W": [[0, 4], [0.25, 2], [0.5, 0], [1, 2], [1.5, 0], [1.75, 2], [2, 4]],
	"R": [[0, 0], [0, 1.3], [0, 2.6], [0, 4], [1, 4], [1.6, 3.2], [1, 2.2], [0.8, 2.2], [1.6, 0]],
	"E": [[1.5, 4], [0.7, 4], [0, 4], [0, 2.7], [0, 1.3], [0, 0], [0.7, 0], [1.5, 0], [0.8, 2]],
	"N": [[0, 0], [0, 1.3], [0, 2.6], [0, 4], [0.7, 2.6], [1.3, 1.3], [2, 0], [2, 1.3], [2, 2.6], [2, 4]],
}


func _build_stars() -> void:
	_stars = Node3D.new()
	_stars.name = "WrenConstellation"
	add_child(_stars)
	_star_mat = StandardMaterial3D.new()
	_star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_star_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_star_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_star_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_star_mat.billboard_keep_scale = true  # [eggs2] without it every star drew at full size and W R E N blurred into one blob
	_star_mat.disable_fog = true
	_star_mat.albedo_texture = _star_tex()  # [eggs2] was the drone's BLACK shadow blob: additive black = no stars at all
	_star_mat.albedo_color = Color(0.85, 0.92, 1.0, 0.0)
	var q := QuadMesh.new()
	q.size = Vector2(3.2, 3.2)
	var pts: Array[Vector2] = []
	for s: Array in STAR_PATTERN:
		pts.append(Vector2(float(s[0]) * 6.0, float(s[1]) * 6.0))
	var x0: float = -6.0
	for ch: String in "WREN":
		for s: Array in LETTERS[ch]:
			pts.append(Vector2(x0 + float(s[0]) * 2.4, float(s[1]) * 2.4 - 4.0))
		x0 += 7.0
	# Big bird stars a bit brighter.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = pts.size()
	for i: int in pts.size():
		var sc: float = 1.1 if i < STAR_PATTERN.size() else 0.34  # [eggs2] small enough that the letters read through the eyepiece
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * sc), Vector3(pts[i].x, pts[i].y, 0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _star_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 400.0
	_stars.add_child(mmi)
	# High in the north-east sky over Old Town.
	_stars.position = STAR_POS
	_stars.look_at_from_position(_stars.position, Vector3.ZERO, Vector3.UP)
	_stars.rotate_object_local(Vector3.UP, PI)


## [eggs2] A soft white star: bright core, faint halo.
static func _star_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.12, Color(1, 1, 1, 0.85))
	g.add_point(0.3, Color(0.8, 0.9, 1.0, 0.12))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _night_amount() -> float:
	if world.get("sky_director") == null:
		return 0.0
	var tod: float = world.sky_director.time_of_day
	# 0 = midnight. Fully visible 21:00-03:00, fading around dusk and dawn.
	var d: float = minf(tod, 1.0 - tod)  # distance from midnight in days
	return clampf((0.17 - d) / 0.06, 0.0, 1.0)


# --- Triggers ------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	_ring_cd = maxf(0.0, _ring_cd - delta)
	if _star_mat:
		var boost: float = 1.0 if is_found("stars") else 0.55
		_star_mat.albedo_color.a = _night_amount() * boost * (0.85 + 0.15 * sin(_t * 1.7))
		# [eggs2] Through the eyepiece the Wren burns bright (HDR white over the darkened lens sky).
		var k: float = 2.5 if is_instance_valid(_peek) else 1.0
		_star_mat.albedo_color = Color(0.85 * k, 0.92 * k, 1.0 * k, 1.0 if is_instance_valid(_peek) else _star_mat.albedo_color.a)
	_animate(delta)
	_glint(delta)
	if not _dev_use.is_empty() and DevHooks._elapsed >= DevHooks.get_f("egg-use", 0.5):  # [eggs2] wall clock (slow renders)
		var du: Dictionary = _dev_use
		_dev_use = {}
		print("[eggs] dev use %s at %.1fs" % [du["id"], DevHooks._elapsed])
		_use(du)
	_tick += delta
	if _tick < 0.15 or world == null or world.patch == null:
		return
	var dt: float = _tick
	_tick = 0.0
	var pp: Vector3 = world.patch.global_position
	update_jukebox(pp)  # [eggs2]
	for e: Dictionary in placed:
		var n: Node3D = e["node"]
		if not n.visible:
			continue
		var d: Dictionary = e["def"]
		var id: String = e["id"]
		var dist: float = OrbitUp.ground_dist(pp, n.global_position)  # [orbB] along the ground
		match str(d.get("trigger", "")):
			"near":
				if dist < float(d.get("range", 4.0)) and not is_found(id):
					_effect(e)
					found(id)
			"chain":
				if not bool(e["final"]) and str(e["kind"]) == "gnome" and not bool(d.get("collect", false)) and dist < float(d.get("range", 2.6)):
					_mark_part(e)
			"watched":
				if dist < float(d.get("range", 9.0)):
					_watch[id] = float(_watch.get(id, 0.0)) + dt
					if float(_watch[id]) >= float(d.get("hold", 5.0)) and not is_found(id):
						_effect(e)
						found(id)
				else:
					_watch[id] = 0.0
		if str(e["kind"]) == "payphone" and dist < 9.0 and dist > 2.5 and _ring_cd <= 0.0 and not is_found(id):
			_ring_cd = 7.0
			Audio.play("phone_ring", 1.0, -8.0)
			_wobble(n.get_node_or_null("Anim"), 0.06)


var _glint_t: float = 0.0


## Unfound curiosities near Patch catch the light now and then, so they can be noticed.
func _glint(delta: float) -> void:
	_glint_t -= delta
	if _glint_t > 0.0 or world == null or world.patch == null:
		return
	_glint_t = 3.5
	var pp: Vector3 = world.patch.global_position
	for e: Dictionary in placed:
		var n: Node3D = e["node"]
		if not n.visible or is_found(str(e["id"])) or n.global_position.distance_to(pp) > 28.0:
			continue
		if str(e["kind"]) == "gnome" and int(e["part"]) in _parts_seen(str(e["id"])):
			continue
		Vfx.burst("sparkle", n.global_position + OrbitUp.up(n.global_position) * 1.1, Color(1.0, 0.95, 0.75), 0.35)


func _on_scooped(_type_id: String, pos: Vector3) -> void:
	for e: Dictionary in placed:
		if str(e["def"].get("trigger", "")) != "scoop_near":
			continue
		var n: Node3D = e["node"]
		if n.global_position.distance_to(pos) > float(e["def"].get("range", 6.0)):
			continue
		var id: String = e["id"]
		if float(_scoop_cd.get(id, 0.0)) > _t:
			continue
		_scoop_cd[id] = _t + (20.0 if str(e["kind"]) == "jukebox" else 8.0)
		_effect(e)
		if str(e["kind"]) != "microwave":
			found(id)


func _mark_part(e: Dictionary) -> void:
	var id: String = e["id"]
	var seen: Array = _parts_seen(id)
	var part: int = int(e["part"])
	if part in seen:
		return
	seen.append(part)
	GameState.flags["egg_%s_parts" % id] = seen
	var total: int = int(e["def"].get("parts", 1))
	var n: Node3D = e["node"]
	_hop(n.get_node_or_null("Anim"))
	Audio.play_scale("blip", seen.size() * 2, -6.0)
	var label: String = tr("Gnome %d / %d") % [seen.size(), total] if str(e["kind"]) == "gnome" else "%d / %d" % [seen.size(), total]
	Vfx.float_text(n.global_position + OrbitUp.up(n.global_position) * 1.3, label, Color(1.0, 0.9, 0.6), 1.1, 1.0)
	if seen.size() >= total:
		if e["def"].has("final"):
			_refresh_visibility()
			for f: Dictionary in placed:
				if f["id"] == id and bool(f["final"]):
					Vfx.burst("sparkle", (f["node"] as Node3D).global_position + OrbitUp.up((f["node"] as Node3D).global_position) * 0.5, Color(1.0, 0.8, 0.5))
			EventBus.toast.emit(tr("The last poster points somewhere close. Something orange is curled up nearby."), "info")
		else:
			_chain_complete(e)
			found(id)


func _chain_complete(e: Dictionary) -> void:
	var id: String = e["id"]
	for f: Dictionary in placed:
		if f["id"] != id:
			continue
		var g: Node3D = f["node"]
		var to: Vector3 = g.get_parent().to_local(world.patch.global_position) - g.position  # [orbB] in its own frame
		var tw := g.create_tween()
		tw.tween_property(g, "rotation:y", atan2(to.x, to.z), 1.2).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(_hop.bind(g.get_node_or_null("Anim")))


# --- Collectibles [eggs2] (story/egg_collect.gd, story/egg_display.gd) -----------------

## Eggs found before parts were tracked: every part counts as collected.
func _migrate_collected() -> void:
	for id: String in order:
		var d: Dictionary = defs[id]
		var total: int = int(d.get("parts", 1))
		if bool(d.get("collect", false)) and is_found(id) and EggCollect.count(id) < total:
			for i: int in total:
				EggCollect.add(id, i)


## E on a collectible part: the tractor beam lifts it into Lumi's compartment and it joins her
## collection (Codex > Collection; shown in the Museum at the end). The last one completes the egg.
func _collect(e: Dictionary) -> void:
	var id: String = e["id"]
	var part: int = int(e["part"])
	var n: Node3D = e["node"]
	if EggCollect.has_part(id, part) or not n.visible:
		return
	var patch: Node3D = world.patch if world else null
	if patch and patch.get("model") != null and patch.model.has_method("eye_flash"):
		patch.model.eye_flash(0.6)
	Audio.play("servo", 1.5, -8.0)
	var dur: float = EggCollect.lift(patch, n, Color(1.0, 0.85, 0.6))
	get_tree().create_timer(dur, false).timeout.connect(_collected.bind(e))


func _collected(e: Dictionary) -> void:
	var id: String = e["id"]
	var d: Dictionary = e["def"]
	var total: int = int(d.get("parts", 1))
	var count: int = EggCollect.add(id, int(e["part"]))
	print("[eggs] collected %s part %d (%d / %d)" % [id, int(e["part"]), count, int(d.get("parts", 1))])
	Audio.play("pop", 1.1, -2.0)
	Audio.play_scale("blip", count * 2, -6.0)
	var label: String = tr("Gnome %d / %d") % [count, total] if str(e["kind"]) == "gnome" else "%d / %d" % [count, total]
	EventBus.toast.emit(tr("%s   ·   added to Lumi's collection") % label, "info")
	if world and world.patch:
		Vfx.float_text(world.patch.global_position + OrbitUp.up(world.patch.global_position) * 2.0, label, Color(1.0, 0.9, 0.6), 1.1, 1.0)
		Vfx.burst("sparkle", world.patch.global_position + OrbitUp.up(world.patch.global_position) * 1.1, Color(1.0, 0.9, 0.6), 0.5)
	if count >= total and not is_found(id):
		found(id)


## Patch pressed E next to an egg.
func _use(e: Dictionary) -> void:
	var d: Dictionary = e["def"]
	var id: String = e["id"]
	var kind: String = e["kind"]
	match str(d.get("trigger", "")):
		"night":
			if _night_amount() < 0.5:
				EventBus.toast.emit(tr("The radio hisses quietly. Nothing up there is awake yet. Come back after dark.") if kind == "radio" \
					else tr("Through the telescope: just a bright, dusty sky. Come back after dark."), "info")
				Audio.play("click", 0.8, -8.0)
				return
		"chain":
			if bool(d.get("collect", false)) and not bool(e["final"]):  # [eggs2] a real pickup
				_collect(e)
				return
			if kind == "poster":
				var posters: Array = d.get("posters", [])
				var doc: Dictionary = (posters[int(e["part"]) % posters.size()] as Dictionary).duplicate() if not posters.is_empty() else {}
				doc["header"] = "A   P O S T E R   ·   %d  O F  %d" % [int(e["part"]) + 1, int(d.get("parts", 3))]
				_mark_part(e)
				if world.get("doc_view") != null and not doc.is_empty():
					world.doc_view.show_doc(doc)
				return
	if d.has("doc") and world.get("doc_view") != null:
		var doc2: Dictionary = (d["doc"] as Dictionary).duplicate()
		doc2["header"] = "T I M E   C A P S U L E   ·   L E T T E R" if kind == "time_capsule" else "A   C L I P B O A R D   ·   N O T E S"
		_effect(e)
		found(id)
		world.doc_view.show_doc(doc2)
		return
	if kind == "telescope":  # [eggs2] counts once Lumi has looked (StarPeek.finished)
		_effect(e)
		return
	if kind == "tv":  # [eggs2] rewatchable; the egg counts once the broadcast has played
		_effect(e)
		return
	if kind == "vending" and is_found(id):
		Vfx.float_text((e["node"] as Node3D).global_position + OrbitUp.up((e["node"] as Node3D).global_position) * 2.2, tr("SOLD OUT"), Color(1.0, 0.4, 0.3), 1.2, 1.0)
		Audio.play("buzz", 1.3, -8.0)
		_wobble(e["node"], 0.04)
		return
	_effect(e)
	found(id)


## The fun part: each egg's little reaction (also replayed after it has been found).
func _effect(e: Dictionary) -> void:
	var n: Node3D = e["node"]
	EggPower.wake(n)  # [qafix] the poke brings the machine back to life
	var anim: Node3D = n.get_node_or_null("Anim")
	var top: Vector3 = n.global_position + OrbitUp.up(n.global_position) * 1.6
	match str(e["kind"]):
		"duck":
			Audio.play("quack", 1.0, -2.0)
			_squash(anim)
			Vfx.float_text(top, tr("QUACK!"), Color(1.0, 0.9, 0.3), 1.3, 1.2)
			EventBus.toast.emit(_duck_hint(), "hint")
		"jukebox":
			_play_jukebox()
		"mural":
			Vfx.burst("sparkle", n.global_position + Vector3(0, 1.6, 0.4), Color(1.0, 0.8, 0.5), 1.5)
		"gnome":
			_hop(anim)
		"time_capsule":
			if anim:
				var tw := anim.create_tween()
				tw.tween_property(anim, "position:y", 0.45, 0.4).set_trans(Tween.TRANS_BACK)
				tw.tween_property(anim, "rotation_degrees:z", 90.0, 0.4)
			Audio.play("dig", 1.0, -4.0)
			Vfx.burst("soil", n.global_position + OrbitUp.up(n.global_position) * 0.2, Color(0.5, 0.4, 0.3))
		"arcade":
			Audio.play("arcade", 1.0, -4.0)
			_flash(n.get_node_or_null("Screen"), Color(0.4, 1.0, 0.7), 3.0)
			Vfx.float_text(top + OrbitUp.up(top) * 0.6, tr("NEW CHALLENGER!"), Color(0.5, 1.0, 0.7), 1.2, 1.0)
			get_tree().create_timer(2.2, false).timeout.connect(func() -> void:
				Audio.play("arcade", 0.6, -6.0)
				Vfx.float_text(top + OrbitUp.up(top) * 0.6, tr("GAME OVER  ·  SCORE 12"), Color(1.0, 0.6, 0.4), 1.1, 1.0))
		"cat_shell":
			Audio.play("purr", 1.0, -3.0)
			var eye: OmniLight3D = n.get_node_or_null("Light")
			if eye:
				var tw2 := eye.create_tween()
				tw2.tween_property(eye, "light_energy", 1.2, 0.6)
			if anim:
				var tw3 := anim.create_tween().set_loops(3)
				tw3.tween_property(anim, "scale", Vector3(1.0, 1.06, 1.0), 0.5).set_trans(Tween.TRANS_SINE)
				tw3.tween_property(anim, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_SINE)
			Vfx.float_text(n.global_position + OrbitUp.up(n.global_position) * 0.9, "purrrr", Color(1.0, 0.8, 0.55), 1.0, 0.8)
		"vending":
			_wobble(n, 0.05)
			Audio.play("clunk", 0.8, -2.0)
			_dispense_can(n)
		"telescope":
			_peek_stars(e)  # [eggs2] steady eyepiece view (story/star_peek.gd)
			Audio.play("sparkle", 0.7, -6.0)
		"payphone":
			Audio.play("click", 0.9, -4.0)
			_wobble(anim, 0.08)
		"tv":
			Audio.play("tv_static", 1.0, -6.0)
			_wobble(anim, 0.03)
			_tune_tv(e)  # [eggs2] the last broadcast (story/tv_broadcast.gd)
		"snail":
			_hop(anim)
			Vfx.float_text(n.global_position + OrbitUp.up(n.global_position) * 1.3, tr("hi, Gus"), Color(0.9, 1.0, 0.8), 1.0, 0.8)
		"bench_bots":
			var fl: Node3D = n.get_node_or_null("Flower")
			if fl:
				fl.visible = true
				fl.scale = Vector3.ONE * 0.05
				var tw5 := fl.create_tween()
				tw5.tween_property(fl, "scale", Vector3.ONE * 0.5, 0.6).set_trans(Tween.TRANS_BACK)
			Vfx.burst("sparkle", n.global_position + OrbitUp.up(n.global_position) * 0.9, Color(1.0, 0.9, 0.6), 0.6)
			Audio.play("chime", 1.3, -10.0)
		"microwave":
			for k: int in 3:
				get_tree().create_timer(0.35 * k, false).timeout.connect(func() -> void: Audio.play("ding", 1.6, -6.0, 0.0))
			_flash(n.get_node_or_null("Screen"), Color(0.3, 1.0, 0.4), 4.0)
		"wet_floor":
			_wobble(anim, 0.1)
			if world.patch.get("model") != null and world.patch.model.has_method("shudder"):
				world.patch.model.shudder(0.4)
			Audio.play("squeak", 1.0, -6.0)
		"camera":
			var led: Node3D = anim.get_node_or_null("Led") if anim else null
			if led:
				var tw6 := led.create_tween().set_loops(2)
				tw6.tween_property(led, "visible", false, 0.15)
				tw6.tween_property(led, "visible", true, 0.15)
			Audio.play("servo", 1.4, -8.0)
		"clothesline", "fishing_net":
			_wobble(anim, 0.12)
			Audio.play("squeak", 1.3, -8.0)
			var prize: Node3D = n.get_node_or_null("Anim/Prize") if anim else null
			if prize:
				prize.visible = false
			if str(e["kind"]) == "fishing_net":
				Vfx.burst("sparkle", n.global_position + OrbitUp.up(n.global_position) * 0.6, Color(0.7, 0.85, 1.0), 0.6)
		"pedestal":
			if anim:
				var twp := anim.create_tween()
				twp.tween_property(anim, "rotation:y", anim.rotation.y + TAU, 1.6).set_trans(Tween.TRANS_SINE)
			Vfx.burst("sparkle", n.global_position + OrbitUp.up(n.global_position) * 1.3, Color(1.0, 0.85, 0.3), 1.2)
			Audio.play("chime", 1.5, -6.0)
		"weather_bot":
			if anim:
				var twv := anim.create_tween().set_loops(3)
				twv.tween_property(anim, "rotation:y", anim.rotation.y + PI * 0.66, 0.25)
			Audio.play("servo", 1.2, -6.0)
			var fc: Array[String] = [tr("CONFETTI"), tr("LIGHT JAZZ"), tr("99% DUCKS"), tr("SUNNY (INDOORS)"), tr("FOG OF NOODLES")]
			Vfx.float_text(top + OrbitUp.up(top) * 1.4, "FORECAST: " + fc[randi() % fc.size()], Color(0.7, 0.9, 1.0), 1.1, 1.4)
		"potato":
			_squash(anim)
			Audio.play("dig", 1.4, -6.0)
			Vfx.float_text(top, tr("1ST PLACE"), Color(0.4, 0.7, 1.0), 1.2, 1.0)
		"radio":
			Audio.play("tv_static", 0.7, -8.0)
			_flash(n.get_node_or_null("Screen"), Color(1.0, 0.7, 0.3), 3.0)
			_look_up()
		"dev_desk":
			Audio.play("pop", 0.8, -6.0)
			_hop(anim)
		"scarecrow":
			if anim:
				var tws := anim.create_tween()
				tws.tween_property(anim, "rotation_degrees:z", -12.0, 0.4).set_trans(Tween.TRANS_SINE)
				tws.tween_property(anim, "rotation_degrees:z", 10.0, 0.6).set_trans(Tween.TRANS_SINE)
				tws.tween_property(anim, "rotation_degrees:z", 0.0, 0.4).set_trans(Tween.TRANS_SINE)
			Audio.play("servo", 0.7, -6.0)
		"sand_car":
			_wobble(anim, 0.05)
			Vfx.burst("dust", n.global_position + OrbitUp.up(n.global_position) * 0.6, Color(0.9, 0.8, 0.6, 0.8), 1.2)
			Audio.play("clunk", 0.7, -6.0)
		"cairn":
			var stone: Node3D = n.get_node_or_null("Anim/Top")
			if stone:
				stone.visible = true
				stone.scale = Vector3.ONE * 0.1
				var twc := stone.create_tween()
				twc.tween_property(stone, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK)
			Audio.play("clink", 0.6, -6.0)
		"campfire":
			var fire: OmniLight3D = n.get_node_or_null("Light")
			var flame: Node3D = n.get_node_or_null("Flame")
			if fire:
				var twf := fire.create_tween()
				twf.tween_property(fire, "light_energy", 1.6, 1.2)
			if flame:
				flame.visible = true
			Vfx.burst("sparkle", n.global_position + OrbitUp.up(n.global_position) * 0.4, Color(1.0, 0.6, 0.25), 0.8)
			Audio.play("whoosh", 0.6, -8.0)
		"drill_press":
			_wobble(n.get_node_or_null("Sign"), 0.08)
			var bolt: Node3D = n.get_node_or_null("Bolt")
			if bolt:
				bolt.visible = true
			Audio.play("clink", 1.2, -6.0)
		"tyre_tower":
			if anim:
				var tw7 := anim.create_tween()
				for k: int in 4:
					tw7.tween_property(anim, "rotation:z", 0.06 * (1.0 if k % 2 == 0 else -1.0) * (1.0 - k * 0.2), 0.25).set_trans(Tween.TRANS_SINE)
				tw7.tween_property(anim, "rotation:z", 0.0, 0.3)
			Audio.play("squeak", 0.7, -6.0)
		_:
			EggPropsLate.effect(self, e)  # [late] the newer curiosities


func _duck_hint() -> String:
	var have: Array = GameState.flags.get("skins_unlocked", ["aurora"])
	for sid: String in Designs.ids():  # [skins]
		if not (sid in have) and PatchModel.VARIANTS.has(sid):
			return tr("The duck squeaks a secret: \"%s\" unlocks the %s design.") % [Designs.unlock_text(sid), tr(str(PatchModel.VARIANTS[sid]["name"]))]
	return tr("The duck has taught you everything it knows. Quack.")


func _play_jukebox() -> void:
	if _jukebox_node == null:
		return
	if _jukebox_on:
		return
	if _jukebox_player == null:
		_jukebox_player = AudioStreamPlayer3D.new()
		_jukebox_player.finished.connect(_stop_jukebox.bind(false))  # [eggs2]
		_jukebox_player.bus = "SFX"
		_jukebox_player.unit_size = 6.0
		_jukebox_player.max_distance = 45.0
		_jukebox_player.volume_db = 2.0
		_jukebox_player.position = Vector3(0, 1.0, 0.3)
		_jukebox_node.add_child(_jukebox_player)
	_jukebox_player.stream = StorySfx.music_box()
	_jukebox_player.volume_db = 2.0
	_jukebox_player.play()
	_jukebox_on = true
	Audio.hush_music("jukebox")  # [eggs2] the score fades out; only the waltz plays
	var l: OmniLight3D = _jukebox_node.get_node_or_null("Light")
	if l:
		var tw := l.create_tween()
		tw.tween_property(l, "light_energy", 2.2, 0.8)
	Audio.play("clunk", 1.4, -10.0)


## [eggs2] The waltz ends (or Lumi walks off): fade the jukebox out and the normal music back in.
func _stop_jukebox(fade: bool = true) -> void:
	if not _jukebox_on:
		return
	_jukebox_on = false
	Audio.unhush_music("jukebox")
	if _jukebox_player and _jukebox_player.playing:
		if fade:
			var p: AudioStreamPlayer3D = _jukebox_player
			var tw := p.create_tween()
			tw.tween_property(p, "volume_db", -40.0, 1.2)
			tw.tween_callback(func() -> void:
				if not _jukebox_on:
					p.stop())
		else:
			_jukebox_player.stop()


## [eggs2] Called each tick with Lumi's position: walking JUKEBOX_LEAVE_M away ends the waltz.
func update_jukebox(patch_pos: Vector3) -> void:
	if _jukebox_on and _jukebox_node:
		var d: float = Vector2(_jukebox_node.global_position.x - patch_pos.x, _jukebox_node.global_position.z - patch_pos.z).length()
		if d > JUKEBOX_LEAVE_M:
			_stop_jukebox(true)


func _exit_tree() -> void:
	Audio.unhush_music("jukebox")  # [eggs2] never leave the score hushed after a district change


func _dispense_can(n: Node3D) -> void:
	var can := EggProps.model("can_rusted", Vector3.ZERO, 0.0, 1.2)
	add_child(can)
	var start: Vector3 = n.global_position + n.global_transform.basis * Vector3(-0.1, 0.32, 0.45)
	var end: Vector3 = n.global_position + n.global_transform.basis * Vector3(0.3, 0.06, 1.2)
	can.global_position = start
	var tw := can.create_tween()
	tw.tween_interval(0.3)
	tw.tween_property(can, "global_position", end, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(can, "rotation:z", PI * 0.5, 0.3)
	tw.tween_callback(func() -> void: Audio.play("clink", 0.9, -4.0))
	var sign_: MeshInstance3D = n.get_node_or_null("Screen")
	if sign_:
		_flash(sign_, Color(1.0, 0.3, 0.2), 2.0)


func _look_up() -> void:
	var so: SliceOrbit = world.get("orbit") as SliceOrbit  # [v6flat] the globe's camera (this read the flat rig: null on the globe)
	var cam: SphereCam = so.cam if so else null
	if cam == null:
		return
	var p0: float = cam.pitch
	var was: bool = cam.lens_view
	# Lens view allows looking up; peek at the constellation for a few seconds.
	cam.lens_view = true
	var tw := create_tween()
	tw.tween_property(cam, "pitch", 0.5, 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(3.5)
	tw.tween_property(cam, "pitch", p0, 1.0).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void: cam.lens_view = was)


## [eggs2] Tunes the TV in: the last Old Town news broadcast, on its screen and in a close-up.
func _tune_tv(e: Dictionary) -> void:
	if is_instance_valid(_tv):
		return
	var b := TvBroadcast.new()
	b.world = world
	b.screen = (e["node"] as Node3D).get_node_or_null("Screen") as MeshInstance3D
	_tv = b
	var id: String = e["id"]
	b.finished.connect(func() -> void: found(id))
	add_child(b)
	b.start()


## [eggs2] The middle of the constellation (bird and letters), in world space.
func star_center() -> Vector3:
	return _stars.to_global(Vector3(6.0, 9.7, 0.0)) if _stars else STAR_POS


## [eggs2] Tilts the tube onto the Wren, then looks through the eyepiece.
func _peek_stars(e: Dictionary) -> void:
	if is_instance_valid(_peek):
		return
	var n: Node3D = e["node"]
	var head: Node3D = n.get_node_or_null("Anim")
	var aim: Vector3 = star_center()
	var to: Vector3 = aim - n.global_position
	var elev: float = atan2(to.y, Vector2(to.x, to.z).length())
	var peek := StarPeek.new()
	peek.world = world
	peek.scope = n
	peek.target = aim
	_peek = peek
	var id: String = e["id"]
	peek.finished.connect(func() -> void:
		if _night_amount() >= 0.5 or DevHooks.has("egg-poke"):
			found(id))
	Audio.play("servo", 0.8, -8.0)
	if head:
		head.rotation.z = elev  # on the Wren (the tube is hidden while we look through it)
	add_child(peek)
	peek.start()


func _hop(n: Node3D) -> void:
	if n == null:
		return
	var y0: float = n.position.y
	var tw := n.create_tween()
	tw.tween_property(n, "position:y", y0 + 0.18, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(n, "position:y", y0, 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _squash(n: Node3D) -> void:
	if n == null:
		return
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector3(1.25, 0.7, 1.25), 0.08)
	tw.tween_property(n, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _wobble(n: Node3D, amt: float) -> void:
	if n == null:
		return
	var tw := n.create_tween()
	for k: int in 4:
		tw.tween_property(n, "rotation:z", amt * (1.0 if k % 2 == 0 else -1.0), 0.06)
	tw.tween_property(n, "rotation:z", 0.0, 0.08)


func _flash(n: Node3D, col: Color, energy: float) -> void:
	var mi: MeshInstance3D = n as MeshInstance3D
	if mi == null or not (mi.material_override is StandardMaterial3D):
		return
	var m: StandardMaterial3D = (mi.material_override as StandardMaterial3D).duplicate()
	mi.material_override = m
	var e0: float = m.emission_energy_multiplier
	var c0: Color = m.emission
	m.emission = col
	var tw := mi.create_tween()
	tw.tween_property(m, "emission_energy_multiplier", energy, 0.1)
	tw.tween_interval(1.4)
	tw.tween_property(m, "emission_energy_multiplier", e0, 0.6)
	tw.tween_callback(func() -> void: m.emission = c0)


func _animate(delta: float) -> void:
	# Jukebox: disc spins and notes float up while it plays.
	if _jukebox_on and _jukebox_node:
		var disc: Node3D = _jukebox_node.get_node_or_null("Disc")
		if disc:
			disc.rotate_object_local(Vector3.UP, delta * 4.0)
		_note_t -= delta
		if _note_t <= 0.0:
			_note_t = 0.6
			var p: Vector3 = _jukebox_node.global_position + Vector3(randf_range(-0.4, 0.4), 1.9, randf_range(-0.2, 0.3))
			Vfx.float_text(p, ["♪", "♫"][randi() % 2], Color(1.0, 0.85, 0.55), 1.0, 1.2)
	elif _jukebox_node:
		var l: OmniLight3D = _jukebox_node.get_node_or_null("Light")
		if l and l.light_energy > 0.0:
			l.light_energy = maxf(0.0, l.light_energy - delta * 0.6)
	# Security camera: swivels to follow Patch when near.
	for e: Dictionary in placed:
		if str(e["kind"]) != "camera" or world.patch == null or EggPower.is_dead(e["node"]):  # [qafix] a dead camera doesn't track
			continue
		var head: Node3D = (e["node"] as Node3D).get_node_or_null("Anim")
		if head == null:
			continue
		var to: Vector3 = world.patch.global_position - head.global_position
		var want: float = atan2(to.x, to.z) - (e["node"] as Node3D).global_rotation.y if Vector2(to.x, to.z).length() < float(e["def"].get("range", 9.0)) else sin(_t * 0.4) * 0.8
		head.rotation.y = lerp_angle(head.rotation.y, want, minf(delta * 2.5, 1.0))


# --- Found ---------------------------------------------------------------------------

func found(id: String) -> void:
	if is_found(id) or not defs.has(id):
		return
	var d: Dictionary = defs[id]
	GameState.flags["egg_" + id] = true
	var list: Array = GameState.flags.get("eggs_found", [])
	if not (id in list):
		list.append(id)
	GameState.flags["eggs_found"] = list
	GameState.inc_stat("eggs_found")
	if str(d.get("where", "")) == "wild":
		var wl: Array = GameState.flags.get("eggs_wild", [])
		if not (id in wl):
			wl.append(id)
		GameState.flags["eggs_wild"] = wl
	var rew: Dictionary = d.get("reward", {})
	var bits: Array[String] = []
	for k: String in rew:
		GameState.add_currency(k, BigNum.from_float(float(rew[k])))
		bits.append(L10nFmt.reward(k, int(rew[k])))  # [i18n2]
	var pos: Vector3 = world.patch.global_position + OrbitUp.up(world.patch.global_position) * 1.8 if world and world.patch else Vector3.ZERO
	Vfx.burst("confetti", pos, Color.WHITE, 0.5)
	Audio.play("sparkle", 1.0, -4.0)
	Audio.play("chime", 1.2, -8.0)
	EventBus.toast.emit(tr(str(d.get("toast", ""))), "story")
	EventBus.toast.emit(tr("Curiosity found: %s  (%d / %d)   %s") % [tr(str(d.get("name", id))), found_count(), defs.size(), "  ".join(bits)], "hint")
	EventBus.easter_egg_found.emit(id)
	if world and world.get("wren") != null:
		var w: Wren = world.wren
		get_tree().create_timer(2.5, false).timeout.connect(func() -> void:
			if w.lines.has("egg_" + id):
				w.say("egg_" + id, 1.0, true)
			else:
				w.say("egg_found", 1.0, true))
	if found_count() == defs.size():
		get_tree().create_timer(6.0, false).timeout.connect(func() -> void:
			EventBus.toast.emit(tr("Every curiosity on the list, found. Lumi's collection compartment is very full of memories."), "story"))
