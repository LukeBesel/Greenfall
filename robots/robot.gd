class_name Robot
extends CharacterBody3D
## A helper robot. Roles:
##   clean (Scoopie): picks junk in its work hex, bales it when full, moves on to the next hex.
##   haul (Haul Bug): carries loose bales to the scale.
##   plant (Seedling): plants seeds on clean ground.
##   water (Drip): sprays the thirstiest plants in its zone, refills at the nearest refill point.
##   skim (Skimmer): floats over lake hexes netting floating junk, drops bales on the shore.
## Robots with nothing to do park near their zone (or the base) and idle.
## Mk IV units hover and lift junk with a tractor beam; lower tiers scoop with an arm.

var type_id: String = "scoopie"
var tier: int = 0
var rarity_bonus: float = 0.0
var robot_name: String = ""
var world: Node
var work_hex: int = -1

var visual: RobotVisual
var hopper := Compartment.new()
var carried: Array[JunkCube] = []

var _target_piece: int = -1
var _target_bale: JunkCube
var _busy: float = 0.0
var _detour_t: float = 0.0
var _detour := Vector3.ZERO
var _progress_pos := Vector3.ZERO
var _progress_t: float = 0.0
var _beam_target: Variant = null
## Multibot job ("clean", "plant", "water"); specialists ignore it.
var job: String = "clean"
## [drones] Robot Builder: fitted parts {slot: part_id}, personality trait, cached stat multipliers.
var build: Dictionary = {}
var trait_id: String = ""
var build_mods: Dictionary = {}
var water: float = 0.0
var _target_slot: int = -1
## What this robot got done (for the Command panel / --bot-report).
var log_stats: Dictionary = {"junk": 0.0, "bales": 0.0, "hauled": 0.0, "planted": 0.0, "watered": 0.0, "refills": 0.0, "idle_s": 0.0, "stall_s": 0.0, "unstuck": 0.0}
var _idling: bool = false
var _parked: bool = false
var _l10n: bool = false  # [l10n] status_label() in progress
var _idle_reason: String = ""
var _refill: Dictionary = {}
var _refilling: bool = false
var _refill_fx_t: float = 0.0
var _shore := Vector3.INF
var _shore_t: float = 0.0  # [beat] time spent heading for this shore point
var _bad_shore: Array = []  # [beat] shore points this skimmer couldn't reach
var _bad_refill: Array = []  # [beat] refill points this robot got stuck on the way to
var _stall_goal := Vector3.INF
var _stall_best: float = INF
var _stall_t: float = 0.0
var _goal := Vector3.ZERO
var _goal_d: float = 0.0
var _trace_t: float = 0.0
var _skip: Dictionary = {}  # piece / slot ids this robot gave up on after getting stuck
## Idle back-off: after a district-wide search comes back empty, wait this long before the
## next one (staggered per robot) instead of rescanning every physics tick.
var _rescan_t: float = 0.0

const RESCAN_MIN: float = 0.4
const RESCAN_JITTER: float = 0.3


func _ready() -> void:
	add_to_group("robot")
	collision_layer = 8
	collision_mask = 1 | PhysLayers.PROP  # [world2] props are solid
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.35 if type_id in ["scoopie", "drip", "seedling"] else 0.45
	sh.height = 0.8
	cs.shape = sh
	cs.position = Vector3(0, 0.45, 0)
	add_child(cs)
	visual = RobotVisual.new()
	add_child(visual)
	rebuild_visual()


func role() -> String:
	var r: String = str(Economy.robots.get(type_id, {}).get("role", "clean"))
	return job if r == "any" else r


## Multibot tool swap: visible attachment change in a burst of sparks.
func set_job(j: String) -> void:
	if j == job:
		return
	job = j
	_target_piece = -1
	_target_slot = -1
	_rescan_t = 0.0
	if has_meta("dump_to"):
		remove_meta("dump_to")
	_busy = 0.8
	Vfx.burst("sparkle", global_position + Vector3(0, 0.6, 0), Color(1.0, 0.8, 0.4), 0.5)
	Audio.play("servo", 1.3, -10.0)


func rebuild_visual() -> void:
	var look: String = str(Economy.robot_tiers[tier].get("look", "salvage")) if tier < Economy.robot_tiers.size() else "salvage"
	visual.build(type_id, look)
	RobotBuilder.on_visual_rebuilt(self)  # [drones] part meshes, name tag, personality


const _WATER_TIER_STATS: Array[String] = ["tank", "refill_rate"]  # [health] no per-call array


func stat(s: String) -> float:
	var v: float = Economy.robot_stat(type_id, s, tier, rarity_bonus)
	# Water gear also improves with the Mk tier (Economy scales the work stats).
	if s in _WATER_TIER_STATS:
		v *= _tier_mult()
	elif s == "spray_radius":
		v *= sqrt(_tier_mult())
		v += maxf(0.0, Economy.stat("drip.range"))
	return v * float(build_mods.get(s, 1.0))  # [drones] builder parts + trait


func _tier_mult() -> float:
	if Economy.robot_tiers.is_empty():
		return 1.0
	return float(Economy.robot_tiers[clampi(tier, 0, Economy.robot_tiers.size() - 1)].get("mult", 1.0))


func _physics_process(delta: float) -> void:
	if world == null:
		return
	_detour_t -= delta
	_progress_t += delta
	_busy = maxf(0.0, _busy - delta)
	_rescan_t = maxf(0.0, _rescan_t - delta)
	var move := Vector3.ZERO
	if _busy <= 0.0:
		_idling = false
		move = _think(delta)
	_watch_stall(move, delta)
	if DevHooks.get_s("trace-bot", "") == robot_name:
		_trace_t += delta
		if _trace_t > 2.0:
			_trace_t = 0.0
			var col: KinematicCollision3D = get_last_slide_collision()
			if col and col.get_collider() is Node:
				var cn: Node = col.get_collider()
				print("[trace] hit %s (%s) parent=%s at %s" % [cn.name, cn.get_class(), str(cn.get_parent().name) if cn.get_parent() else "-", str(col.get_position())])
			print("[trace] %s pos=%s hex=%d work=%d piece=%d ppos=%s busy=%.1f hop=%.1f/%.1f pend=%.1f stall=%.1f move=%s | %s" % [robot_name, str(global_position.snapped(Vector3.ONE * 0.1)), world.field.hex_at(global_position), work_hex, _target_piece, str(world.field.piece_pos[_target_piece].snapped(Vector3.ONE * 0.1)) if _target_piece >= 0 else "-", _busy, hopper.fill, stat("capacity"), hopper.pending, _stall_t, str(move.snapped(Vector3.ONE * 0.1)), status_text()])
	if _idling:
		log_stats["idle_s"] = float(log_stats["idle_s"]) + delta
	var spd: float = stat("speed") * Outposts.charge_mult(self, world, delta)  # [outposts] recharge pad
	var target_v: Vector3 = move * spd
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(target_v, 10.0 * delta)
	velocity = Vector3(hv.x, 0.0 if is_on_floor() else velocity.y - 20.0 * delta, hv.z)
	if visual.hover or visual.floats:
		# Hold a fixed height over whatever is below (and just ahead), so curbs and slabs
		# poking out of the lake don't wall a hovering/floating robot in.
		velocity.y = 0.0
		var lay: CityLayout = world.field.layout
		var ground: float = 0.0
		if lay:
			var ahead: Vector3 = global_position + Vector3(hv.x, 0, hv.z).limit_length(1.0) * 0.6
			ground = clampf(maxf(lay.height_at(global_position.x, global_position.z), lay.height_at(ahead.x, ahead.z)), 0.0, 0.4)
		global_position.y = lerpf(global_position.y, ground + 0.06, clampf(delta * 6.0, 0.0, 1.0))
	if hv.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-hv.x, -hv.z), clampf(delta * 6.0, 0.0, 1.0))
	move_and_slide()
	visual.idle = _idling and _parked and _busy <= 0.0
	if role() == "water":
		visual.set_fill(water / maxf(stat("tank"), 1.0))
	visual.animate(hv.length(), _busy > 0.0 or _refilling, delta)
	visual.beam_to(_beam_target if _busy > 0.0 else null)
	for i: int in carried.size():
		carried[i].position = visual.position + visual.fork_point + Vector3(0, carried[i].size * (0.5 + i), 0)  # [drones] + part lift


func _steer(target: Vector3, stop: float) -> Vector3:
	var d: Vector3 = target - global_position
	d.y = 0.0
	var dist: float = d.length()
	_goal = target
	_goal_d = dist
	if dist <= stop:
		return Vector3.ZERO
	var m: Vector3 = d.normalized()
	if _detour_t > 0.0:
		return (_detour + m * 0.3).normalized()
	if global_position.distance_to(_progress_pos) > 0.4:
		_progress_pos = global_position
		_progress_t = 0.0
	elif _progress_t > 1.0:
		_detour = Vector3(m.z, 0, -m.x) * (1.0 if randf() < 0.5 else -1.0)
		_detour_t = 1.2
		_progress_t = 0.0
	return m * clampf(dist / 1.2, 0.3, 1.0)


func reset_targets(keep_skip: bool = false) -> void:
	if not keep_skip:
		_skip.clear()
	work_hex = -1
	_target_piece = -1
	_target_slot = -1
	_refill = {}
	_refilling = false
	_shore = Vector3.INF
	_rescan_t = 0.0
	# A stale auto-baler claim (role/job changed mid-dump) would otherwise be acted on later.
	if has_meta("dump_to"):
		remove_meta("dump_to")
	_release_bale()


## Drop the hauler's current target and clear the reservation it put on that bale.
func _release_bale() -> void:
	if _target_bale and is_instance_valid(_target_bale):
		_target_bale.set_meta("reserved", false)
	_target_bale = null


func _backoff() -> void:
	_rescan_t = RESCAN_MIN + randf() * RESCAN_JITTER


func _fleet() -> Fleet:
	return get_parent() as Fleet


## Hexes from the current order ([] = whole district) and whether to stay inside them.
func _zone() -> Array:
	var f: Fleet = _fleet()
	return f.zone_hexes(self) if f else []


func _stay() -> bool:
	var f: Fleet = _fleet()
	return f != null and f.mode_of(self) in ["stay", "follow"]


## Short line for the Command View.
## Status line in English (logic and logs read it: Command view pip colours, tests, [bots] report).
## status_label() is the same line translated for display.
func status_text() -> String:
	var f: Fleet = _fleet()
	if f and f.mode_of(self) == "recall":
		return _t("parked at hub") if global_position.distance_to(_park_pos()) < 2.5 else _t("returning to hub")
	if _idling:
		return _t("idle · %s") % _t(_idle_reason) if _idle_reason != "" else _t("idle")
	match role():
		"haul":
			if carried.size() > 0:
				if _l10n:
					return tr_n("hauling %d bale", "hauling %d bales", carried.size()) % carried.size()
				return "hauling %d bale%s" % [carried.size(), "" if carried.size() == 1 else "s"]
			return _t("fetching a bale") if _target_bale else _t("waiting for bales")
		"plant":
			if not GameState.can_afford("seeds", BigNum.from_float(1.0)):
				return _t("out of seeds")
			return _t("planting") if _target_slot >= 0 else _t("looking for soil")
		"water":
			if _refilling or water < 1.0:
				return _t("refilling at %s (%d%%)") % [str({"barrel": _t("base barrel"), "tank": _t("tank"), "lake": _t("lake")}.get(str(_refill.get("kind", "barrel")), str(_refill.get("kind", "")))), int(100.0 * water / maxf(stat("tank"), 1.0))]
			return _t("watering · tank %d%%") % int(100.0 * water / maxf(stat("tank"), 1.0)) if _target_slot >= 0 else _t("looking for thirsty plants")
		"skim":
			if _shore != Vector3.INF:
				return _t("taking a bale to shore")
			if work_hex >= 0:
				return _t("skimming lake hex %d (%d%%)") % [work_hex, int(world.field.removed_fraction(work_hex) * 100.0)]
			return _t("lake is clean")
		_:
			if work_hex >= 0:
				return _t("cleaning hex %d (%d%%)") % [work_hex, int(world.field.removed_fraction(work_hex) * 100.0)]
			return _t("zone clean, waiting") if _stay() else _t("nothing left to clean")


## [l10n] status_text() translated, for the screen.
func status_label() -> String:
	_l10n = true
	var s: String = status_text()
	_l10n = false
	return s


## [l10n] Translates only while status_label() runs (the extractor reads _t("...") like tr()).
func _t(s: String) -> String:
	return tr(s) if _l10n else s


func _park_pos() -> Vector3:
	var i: int = get_index()
	@warning_ignore("integer_division")
	return world.depot.global_position + Vector3(-3.0 + float(i % 6) * 1.2, 0, 4.0 + float(i / 6) * 1.2)


## Nothing to do: drive to a parking spot near the zone (or the base) and idle there.
func _go_idle(reason: String) -> Vector3:
	_idling = true
	_idle_reason = reason
	var m: Vector3 = _steer(_idle_spot(), 0.7)
	# Close enough if a crew-mate already sits on the spot.
	if m != Vector3.ZERO and _stall_t > 1.5 and _goal_d < 2.5:
		m = Vector3.ZERO
	_parked = m == Vector3.ZERO
	return m


## [outposts] With no zone, park at the nearest working outpost when it is closer than the base.
func _rest_pos() -> Vector3:
	var p: Vector3 = Outposts.idle_spot(world, global_position, get_index())
	return p if p != Vector3.INF else _park_pos()


func _idle_spot() -> Vector3:
	var z: Array = _zone()
	if z.is_empty():
		return _rest_pos()
	var field: HexField = world.field
	var best: int = -1
	var best_d: float = INF
	for h: Variant in z:
		var id: int = int(h)
		if id < 0 or id >= field.hex_count():
			continue
		var d: float = field.hex_center(id).distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = id
	if best < 0:
		return _park_pos()
	# Spread the crew around the hex center, avoiding building footprints.
	var c: Vector3 = field.hex_center(best)
	var i: int = get_index()
	for k: int in 6:
		var a: float = TAU * float((i + k) % 6) / 6.0 + 0.4
		var p: Vector3 = c + Vector3(cos(a), 0, sin(a)) * (0.9 + 0.3 * float(i % 3))
		if field.layout == null or field.layout.surface_at(p.x, p.z) != CityLayout.Surface.BUILDING:
			return p
	return c


## Stall watch: wanting to move but not getting closer to the goal (blocked, or sliding
## sideways along a wall). After a while, give up the target and back off.
func _watch_stall(move: Vector3, delta: float) -> void:
	if move.length() < 0.05 or _busy > 0.0:
		_stall_goal = Vector3.INF
		_stall_t = 0.0
		return
	if _goal.distance_to(_stall_goal) > 0.5 or _goal_d < _stall_best - 0.4:
		_stall_goal = _goal
		_stall_best = _goal_d
		_stall_t = 0.0
		return
	_stall_t += delta
	if _stall_t > 2.0:
		log_stats["stall_s"] = float(log_stats["stall_s"]) + delta
	if _stall_t > 6.0:
		_unstick()


func _unstick() -> void:
	log_stats["unstuck"] = float(log_stats["unstuck"]) + 1.0
	if _target_piece >= 0:
		# Whatever blocked this piece probably blocks its neighbours too.
		for pid: int in world.field.pieces_within(world.field.piece_pos[_target_piece], 1.5):
			_skip[pid] = true
		_skip[_target_piece] = true
	if _target_slot >= 0:
		_skip[-2 - _target_slot] = true
	# [beat] Pinned on the way to a refill point: try another one next time (a Drip circled a
	# blocked barrel for good at the Cradle).
	if not _refill.is_empty() and not _refilling:
		_bad_refill.append(_refill["pos"])
		if _bad_refill.size() > 6:
			_bad_refill.pop_front()
	reset_targets(true)
	_stall_t = 0.0
	_stall_goal = Vector3.INF
	# Back off in a random direction, then a little hop free of whatever is pinning it.
	var a: float = randf() * TAU
	_detour = Vector3(cos(a), 0, sin(a))
	_detour_t = 1.5
	global_position += _detour * 0.35 + Vector3(0, 0.25, 0)
	Vfx.burst("dust", global_position, Color(0.7, 0.65, 0.6, 0.6), 0.5)


func _think(delta: float) -> Vector3:
	var f: Fleet = _fleet()
	if f and f.mode_of(self) == "recall":
		if role() == "haul":
			_release_bale()
			if not carried.is_empty():
				return _think_haul(true)  # deliver what it carries, collect nothing new
		return _steer(_park_pos(), 0.8)
	match role():
		"haul":
			return _think_haul()
		"plant":
			return _think_plant()
		"water":
			return _think_water(delta)
		"skim":
			return _think_skim()
		_:
			return _think_clean(delta)


# --- Cleaner -------------------------------------------------------------------------

func _think_clean(_delta: float) -> Vector3:
	if has_meta("dump_to"):  # [stations] driving to an auto-baler (automation/stations.gd)
		return Stations.dump_step(self)
	var field: HexField = world.field
	if not hopper.can_accept(stat("capacity")):
		_make_bale()
		return Vector3.ZERO
	if work_hex < 0 or field.is_clean(work_hex):
		if _rescan_t > 0.0 and hopper.is_empty():
			return _go_idle(_idle_reason)
		work_hex = _pick_work_hex()
		_target_piece = -1
		if work_hex < 0:
			_backoff()
			if not hopper.is_empty():
				_make_bale()
				return Vector3.ZERO
			return _go_idle(_t("zone clean") if _stay() else _t("nothing left to clean"))
	if _target_piece < 0 or field.piece_alive[_target_piece] == 0:
		_target_piece = _nearest_piece_in(work_hex)
		if _target_piece < 0:
			work_hex = -1  # only pieces we gave up on are left here
			return Vector3.ZERO
	var p: Vector3 = field.piece_pos[_target_piece]
	var reach: float = 1.6 if visual.hover else 0.75
	var m: Vector3 = _steer(p, reach)
	if m == Vector3.ZERO:
		_pick(_target_piece)
		_target_piece = -1
	return m


## Nearest dirty hex in the zone, else in the district. Cleaners work land, skimmers the lake.
func _pick_work_hex() -> int:
	var field: HexField = world.field
	var lake: bool = role() == "skim"
	var best: int = -1
	var best_d: float = INF
	var z: Array = _zone()
	for h: Variant in z:
		var id: int = int(h)
		if id < 0 or id >= field.hex_count() or field.hex_hub[id] != 0 or field.is_clean(id) or field.is_water(id) != lake or _skip.has(1000000 + id) or field.locked.has(id):  # [biomes] ice
			continue
		var d: float = field.hex_center(id).distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = id
	if best >= 0 or (_stay() and not z.is_empty()):
		return best
	# [beat] Sunken City: skim the ring the pumps need next before the outer rings.
	var fr: Variant = world.get("frontier")
	var sunken: FrontierDistrict = fr if lake and fr is FrontierDistrict and (fr as FrontierDistrict).kid == "sunken_city" else null
	for id: int in field.hex_count():
		if field.hex_hub[id] != 0 or field.is_clean(id) or field.is_water(id) != lake or _skip.has(1000000 + id) or field.locked.has(id):  # [biomes] ice
			continue
		var d: float = field.hex_center(id).distance_squared_to(global_position)
		if sunken:
			d += 1.0e6 * maxf(0.0, Frontiers.flood_stage_of(field, id, sunken.kind.get("flood", {})) - (sunken.drained + 1))
		if d < best_d:
			best_d = d
			best = id
	return best


func _nearest_piece_in(hid: int) -> int:
	var field: HexField = world.field
	var best: int = -1
	var best_d: float = INF
	for pid: int in field.hex_pieces[hid]:
		if field.piece_alive[pid] == 0 or _skip.has(pid):
			continue
		var d: float = field.piece_pos[pid].distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = pid
	if best < 0:
		_skip[1000000 + hid] = true  # everything left here is unreachable for this robot
	return best


func _pick(pid: int) -> void:
	var field: HexField = world.field
	if field.piece_alive[pid] == 0:
		return
	var type_id_j: String = Economy.junk_ids[field.piece_type[pid]]
	var vol: float = field.piece_vol[pid]
	var start_xf: Transform3D = world.view.piece_transform(pid)
	var mesh: Mesh = world.view.piece_mesh(pid)
	var extras: Array = []  # [world2] gen-2 junk is finer: the scoop takes the little cluster along
	for e: int in field.cluster_extra(pid):
		extras.append([Economy.junk_ids[field.piece_type[e]], field.piece_vol[e]])
		hopper.reserve(field.piece_vol[e])
		world.collect_piece(e)
	hopper.reserve(vol)
	world.collect_piece(pid)
	log_stats["junk"] = float(log_stats["junk"]) + 1.0
	if world.get("litter") != null:
		world.litter.sweep(start_xf.origin, 0.6)
	var dur: float = 0.7 if visual.hover else (0.6 if visual.floats else 0.45)
	_busy = maxf(1.0 / maxf(stat("scoop_rate"), 0.1), dur)
	_beam_target = start_xf.origin
	var flyer := MeshInstance3D.new()
	flyer.mesh = mesh
	get_tree().current_scene.add_child(flyer)
	flyer.global_transform = start_xf
	var start: Vector3 = start_xf.origin
	var start_scale: Vector3 = start_xf.basis.get_scale()
	var hov: bool = visual.hover
	var tw := flyer.create_tween()
	tw.tween_method(func(t: float) -> void:
		if not is_instance_valid(self):
			return
		var end: Vector3 = to_global(visual.hopper_point)
		var pos: Vector3
		if hov:
			# Tractor beam: rise slowly, spin, then get pulled in.
			var lift: Vector3 = start + Vector3(0, 0.9 * smoothstep(0.0, 0.5, t), 0)
			pos = lift.lerp(end, smoothstep(0.45, 1.0, t))
			flyer.rotation += Vector3(0.05, 0.08, 0.03)
			_beam_target = pos
		else:
			var top: Vector3 = (start + end) * 0.5 + Vector3(0, 0.6, 0)
			pos = start.lerp(top, t).lerp(top.lerp(end, t), t)
			_beam_target = pos  # Mk III shows a slim beam on the arc (hidden on lower tiers)
		flyer.global_position = pos
		flyer.scale = start_scale * lerpf(1.0, 0.4, t * t)
		, 0.0, 1.0, dur)
	tw.tween_callback(flyer.queue_free)
	get_tree().create_timer(dur, false).timeout.connect(func() -> void:
		if is_instance_valid(self):
			hopper.add(type_id_j, vol)
			GameState.add_junk_removed(type_id_j, vol)
			world.salvage_materials(type_id_j, vol * 0.5)
			for ex: Array in extras:  # [world2]
				hopper.add(str(ex[0]), float(ex[1]))
				GameState.add_junk_removed(str(ex[0]), float(ex[1]))
				world.salvage_materials(str(ex[0]), float(ex[1]) * 0.5)
			Audio.play("clink", randf_range(0.8, 1.1), -14.0))
	if hov:
		Vfx.burst("sparkle", start, Color(0.4, 1.0, 0.85), 0.4)
		Audio.play("servo", 1.6, -16.0)
	else:
		Audio.play("servo", randf_range(0.9, 1.1), -18.0)


func _make_bale() -> void:
	if hopper.is_empty() or hopper.pending > 0.0:
		return
	if Stations.claim_dump(self):  # [stations] tip the hopper into a nearby auto-baler instead
		return
	var cap: float = stat("capacity")
	var contents: Dictionary = hopper.take_all()
	var info: Dictionary = Economy.evaluate_cube(contents, cap, stat("efficiency"))
	info["perfect"] = false
	var cube: JunkCube = JunkCube.create(info["value"], info)
	world.add_cube(cube)
	cube.global_position = global_position + global_transform.basis.z * 0.7 + Vector3(0, 0.5, 0)
	cube.linear_velocity = global_transform.basis.z * 0.8
	_busy = 0.9
	Audio.play("crunch", 1.3, -12.0)
	Audio.play("clunk", 1.2, -10.0)
	GameState.inc_stat("robot_bales")
	log_stats["bales"] = float(log_stats["bales"]) + 1.0


# --- Planter -----------------------------------------------------------------------------

func _think_plant() -> Vector3:
	var g: Garden = world.get("garden")
	if g == null or not g.unlocked():
		return _go_idle(_t("seeds locked"))
	if not GameState.can_afford("seeds", BigNum.from_float(1.0)):
		return _go_idle(_t("out of seeds"))
	if _target_slot < 0 or g.slot_species[_target_slot] >= 0:
		if _rescan_t > 0.0:
			_target_slot = -1
			return _go_idle(_t("no empty soil"))
		_target_slot = _find_slot(g, true)
		if _target_slot < 0:
			_backoff()
			return _go_idle(_t("no empty soil"))
	var m: Vector3 = _steer(g.slot_pos[_target_slot], 0.8)
	if m == Vector3.ZERO:
		if g.plant(_target_slot):
			_busy = 1.0 / maxf(stat("work_rate"), 0.1)
			_beam_target = g.slot_pos[_target_slot]
			log_stats["planted"] = float(log_stats["planted"]) + 1.0
		_target_slot = -1
	return m


# --- Waterer -------------------------------------------------------------------------------
# A Drip carries `tank` units of water; each plant it sprays costs one unit. It goes for the
# thirstiest plants in its zone first, sprays every planted slot within `spray_radius` of its
# target in one go, and refills at the nearest refill point (base barrel, Water Tank, clean lake).

const THIRSTY: float = 0.45  # water fraction under which a plant wants watering
const SPRAY_AMOUNT_S: float = 60.0


static func water_fraction(g: Garden, s: int) -> float:
	if g.slot_species[s] < 0:
		return 1.0
	return g.slot_water[s] / maxf(float(g.species[g.slot_species[s]].get("water_s", 120)), 1.0)


func _think_water(delta: float) -> Vector3:
	var g: Garden = world.get("garden")
	if g == null:
		return _go_idle(_t("no garden"))
	var tank: float = stat("tank")
	if _refilling or water < 1.0:
		return _do_refill(delta, tank)
	if _target_slot >= 0 and (g.slot_species[_target_slot] < 0 or water_fraction(g, _target_slot) > 0.7):
		_target_slot = -1  # someone else got it
	if _target_slot < 0:
		_target_slot = _find_thirsty(g) if _rescan_t <= 0.0 else -1
		if _target_slot < 0:
			if _rescan_t <= 0.0:
				_backoff()
			# Nothing thirsty: top the tank up while it's quiet, then park.
			if water < tank * 0.5:
				return _do_refill(delta, tank)
			return _go_idle(_t("everything watered"))
	var radius: float = maxf(stat("spray_radius"), 0.8)
	var reach: float = clampf(radius * 0.7, 0.9, 2.4)
	var m: Vector3 = _steer(g.slot_pos[_target_slot], reach)
	if m == Vector3.ZERO:
		_spray_at(g, g.slot_pos[_target_slot], radius)
		_target_slot = -1
	return m


## Water every planted, not-full slot within radius of `at` (thirstiest first) with spray arcs.
func _spray_at(g: Garden, at: Vector3, radius: float) -> void:
	var cand: Array = []
	for hid: int in world.field.hexes_near(at, 1):
		if not g.hex_slots.has(hid):
			continue
		for s: int in g.hex_slots[hid]:
			if g.slot_species[s] < 0 or g.slot_pos[s].distance_to(at) > radius:
				continue
			var wf: float = water_fraction(g, s)
			if wf < 0.9:
				cand.append([wf, s])
	cand.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var amount: float = SPRAY_AMOUNT_S * maxf(stat("work_rate"), 0.3)
	var nozzle: Vector3 = to_global(visual.nozzle_point)
	var net: WaterNet = _fleet().water_net if _fleet() else null
	var n: int = 0
	for c: Array in cand:
		if water < 1.0:
			break
		var s: int = int(c[1])
		g.water(s, amount)
		water -= 1.0
		n += 1
		if net:
			net.spray(nozzle, g.slot_pos[s] + Vector3(0, 0.1, 0), 0.45 + 0.05 * n)
	if n == 0:
		return
	log_stats["watered"] = float(log_stats["watered"]) + n
	GameState.inc_stat("plants_watered_by_bots")
	# Face the spray and hold still while it lands.
	var d: Vector3 = at - global_position
	if Vector2(d.x, d.z).length() > 0.05:
		rotation.y = atan2(-d.x, -d.z)
	_busy = (0.6 + 0.08 * n) / maxf(stat("work_rate"), 0.3)
	Audio.play("steam", 1.5, -16.0)


## The thirstiest planted slot (zone first), skipping slots another waterer is heading for.
func _find_thirsty(g: Garden) -> int:
	var taken: Dictionary = {}
	var f: Fleet = _fleet()
	if f:
		for r: Robot in f.robots():
			if r != self and r.role() == "water" and r._target_slot >= 0:
				taken[r._target_slot] = true
	var z: Array = _zone()
	var hexes: Array = []
	if not z.is_empty():
		hexes = z
	var best: int = _thirstiest_in(g, hexes, taken) if not hexes.is_empty() else -1
	if best >= 0 or (_stay() and not z.is_empty()):
		return best
	return _thirstiest_in(g, g.hex_slots.keys(), taken)


func _thirstiest_in(g: Garden, hexes: Array, taken: Dictionary) -> int:
	var best: int = -1
	var best_score: float = INF
	for h: Variant in hexes:
		var hid: int = int(h)
		if not g.hex_slots.has(hid) or not world.field.is_clean(hid):
			continue
		for s: int in g.hex_slots[hid]:
			if g.slot_species[s] < 0 or taken.has(s) or _skip.has(-2 - s):
				continue
			var wf: float = water_fraction(g, s)
			if wf >= THIRSTY:
				continue
			# Thirst dominates; distance breaks ties (and keeps trips short).
			var score: float = wf * 40.0 + g.slot_pos[s].distance_to(global_position) * 0.25
			if score < best_score:
				best_score = score
				best = s
	return best


func _do_refill(delta: float, tank: float) -> Vector3:
	var f: Fleet = _fleet()
	var net: WaterNet = f.water_net if f else null
	if net == null:
		water = tank  # no world network (tests): instant refill
		return Vector3.ZERO
	if _refill.is_empty():
		_refill = net.nearest_refill(global_position, _bad_refill)
		if _refill.is_empty():
			return _go_idle(_t("no water source"))
	var spot: Vector3 = _refill["pos"]
	var stop: float = 1.35 if _refill["kind"] != "lake" else 0.6
	if not _refilling:
		var m: Vector3 = _steer(spot, stop)
		if m != Vector3.ZERO:
			return m
		_refilling = true
	var want: float = minf(maxf(stat("refill_rate"), 3.0) * delta, tank - water)
	var got: float = net.draw(_refill, want)
	water = minf(tank, water + got)
	_refill_fx_t -= delta
	if _refill_fx_t <= 0.0:
		_refill_fx_t = 0.5
		Vfx.burst("soil", to_global(visual.hopper_point) + Vector3(0, 0.15, 0), Color(0.55, 0.8, 1.0, 0.8), 0.25)
		Audio.play("steam", 0.7, -20.0)
	if water >= tank - 0.01 or (got <= 0.0 and want > 0.0):
		if water < tank * 0.3 and got <= 0.0:
			_refill = {}  # that tank ran dry; try another point
			_refilling = false
			return Vector3.ZERO
		_refilling = false
		_refill = {}
		_bad_refill.clear()
		log_stats["refills"] = float(log_stats["refills"]) + 1.0
		_busy = 0.4
	return Vector3.ZERO


# --- Skimmer -------------------------------------------------------------------------------

func _think_skim() -> Vector3:
	var field: HexField = world.field
	if _shore != Vector3.INF:
		return _to_shore()
	if not hopper.can_accept(stat("capacity")):
		return _to_shore()
	if work_hex < 0 or field.is_clean(work_hex):
		if _rescan_t > 0.0 and hopper.is_empty():
			return _go_idle(_idle_reason)
		work_hex = _pick_work_hex()
		_target_piece = -1
		if work_hex < 0:
			_backoff()
			if not hopper.is_empty():
				return _to_shore()
			return _go_idle(_t("lake is clean") if not _stay() else _t("zone clean"))
	if _target_piece < 0 or field.piece_alive[_target_piece] == 0:
		_target_piece = _nearest_piece_in(work_hex)
		if _target_piece < 0:
			work_hex = -1
			return Vector3.ZERO
	var m: Vector3 = _steer(field.piece_pos[_target_piece], 1.05 if not visual.hover else 1.6)
	if m == Vector3.ZERO:
		_pick(_target_piece)
		_target_piece = -1
	return m


## Carry the full net to the nearest bit of shore and leave a bale there for the haulers.
func _to_shore() -> Vector3:
	if hopper.is_empty() and hopper.pending <= 0.0:
		_shore = Vector3.INF
		return Vector3.ZERO
	if _shore == Vector3.INF:
		_shore = shore_point(world.field, global_position, _bad_shore)
		_shore_t = 0.0
	var m: Vector3 = _steer(_shore, 0.5)
	# [beat] Blocked on the way (Sunken City rooftops, piers): after a while try another bit of
	# shore; after several, drop the bale where it is rather than circle forever.
	_shore_t += get_physics_process_delta_time()
	if m != Vector3.ZERO and _shore_t > 40.0:
		_bad_shore.append(_shore)
		if _bad_shore.size() > 4:
			_bad_shore.clear()
			_make_bale()
			_shore = Vector3.INF
			return Vector3.ZERO
		_shore = shore_point(world.field, global_position, _bad_shore)
		_shore_t = 0.0
	if m == Vector3.ZERO and hopper.pending <= 0.0:
		_make_bale()
		_shore = Vector3.INF
		_bad_shore.clear()
	return m


## Nearest land point just off a lake hex (not a building), for dropping bales.
static func shore_point(field: HexField, from: Vector3, avoid: Array = []) -> Vector3:
	var best := Vector3.INF
	var best_d: float = INF
	for id: int in field.hex_count():
		if not field.is_water(id):
			continue
		var wc: Vector3 = field.hex_center(id)
		for nb: int in field.hexes_near(wc, 1):
			if nb == id or field.is_water(nb) or field.hex_hub[nb] == 2:
				continue
			var lc: Vector3 = field.hex_center(nb)
			for t: float in [0.3, 0.15, 0.45, 0.0]:
				var p: Vector3 = lc.lerp(wc, t)
				if field.layout and field.layout.surface_at(p.x, p.z) == CityLayout.Surface.BUILDING:
					continue
				var near_bad: bool = false
				for q: Variant in avoid:
					if (q as Vector3).distance_to(p) < 4.0:
						near_bad = true
				if near_bad:
					continue
				var d: float = p.distance_squared_to(from)
				if d < best_d:
					best_d = d
					best = p
				break
	if best == Vector3.INF:
		return from
	return best


## Nearest empty (planting) or thirsty (watering) slot on clean hexes.
func _find_slot(g: Garden, empty: bool) -> int:
	var z: Array = _zone()
	if not z.is_empty():
		var zs: int = _find_slot_in(g, empty, z)
		if zs >= 0 or _stay():
			return zs
	var best: int = -1
	var best_d: float = INF
	for s: int in g.slot_species.size():
		if not world.field.is_clean(g.slot_hex[s]) or _skip.has(-2 - s):
			continue
		if empty:
			if g.slot_species[s] >= 0 or not g.plantable(s):  # [biomes] cold / flooded slots
				continue
		elif g.slot_species[s] < 0 or g.slot_water[s] > 10.0:
			continue
		var d: float = g.slot_pos[s].distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = s
	return best


func _find_slot_in(g: Garden, empty: bool, z: Array) -> int:
	var best: int = -1
	var best_d: float = INF
	for h: Variant in z:
		var hid: int = int(h)
		if not g.hex_slots.has(hid) or not world.field.is_clean(hid):
			continue
		for s: int in g.hex_slots[hid]:
			if _skip.has(-2 - s):
				continue
			if empty:
				if g.slot_species[s] >= 0 or not g.plantable(s):  # [biomes] cold / flooded slots
					continue
			elif g.slot_species[s] < 0 or g.slot_water[s] > 10.0:
				continue
			var d: float = g.slot_pos[s].distance_squared_to(global_position)
			if d < best_d:
				best_d = d
				best = s
	return best


# --- Hauler ----------------------------------------------------------------------------

## deliver_only (recall): take what it carries to the drop-off and never fetch more.
func _think_haul(deliver_only: bool = false) -> Vector3:
	var cap: int = int(round(stat("carry")))
	if deliver_only or carried.size() >= cap:
		return _haul_deliver()
	if _target_bale == null or not is_instance_valid(_target_bale) or _target_bale.carried or _target_bale.claimed:
		_release_bale()  # Patch grabbed it / it got claimed: let other haulers have it later
		if _rescan_t <= 0.0:
			_target_bale = _find_bale()  # one scan per tick at most
			if _target_bale:
				_target_bale.set_meta("reserved", true)
			else:
				_backoff()
	if _target_bale == null:
		if not carried.is_empty():
			return _haul_deliver()
		return _go_idle(_t("waiting for bales"))
	var m2: Vector3 = _steer(_target_bale.global_position, 0.9)
	if m2 == Vector3.ZERO:
		_target_bale.set_carried(true)
		_target_bale.reparent(self, true)
		_target_bale.rotation = Vector3.ZERO
		carried.append(_target_bale)
		_target_bale = null
		_busy = 0.6
		Audio.play("servo", 0.8, -14.0)
	return m2


func _haul_deliver() -> Vector3:
	var depot: Depot = Outposts.nearest_depot(world, global_position)  # [outposts] nearest working scale
	var drop: Vector3 = Stations.haul_drop(self, depot.global_position)  # [stations] feeder pad if closer
	var m: Vector3 = _steer(drop, 0.6)
	if depot.pad_contains(global_position) or m == Vector3.ZERO:
		for c: JunkCube in carried:
			c.reparent(world.get_node("Cubes"), true)
			c.global_position = drop + Vector3(randf_range(-0.4, 0.4), 0.6, randf_range(-0.4, 0.4))
			c.set_carried(false)
			c.set_meta("reserved", false)
		log_stats["hauled"] = float(log_stats["hauled"]) + carried.size()
		carried.clear()
		_busy = 0.5
		Audio.play("clunk", 0.9, -10.0)
	return m


func _find_bale() -> JunkCube:
	var best: JunkCube = null
	var best_d: float = INF
	var z: Array = _zone()
	var stay: bool = _stay()
	for n: Node in get_tree().get_nodes_in_group("junk_cube"):
		var c: JunkCube = n
		if c.carried or c.claimed or bool(c.get_meta("reserved", false)) and c != _target_bale:
			continue
		if world.depot.pad_contains(c.global_position) or Stations.on_feeder(c) or Outposts.on_pad(world, c.global_position):  # [stations] [outposts]
			continue
		var in_zone: bool = z.is_empty() or z.has(world.field.hex_at(c.global_position))
		if stay and not in_zone:
			continue
		var d: float = c.global_position.distance_squared_to(global_position)
		if not in_zone:
			d += 1.0e6  # zone bales first
		if d < best_d:
			best_d = d
			best = c
	return best


func to_dict() -> Dictionary:
	return {"type": type_id, "tier": tier, "rarity_bonus": rarity_bonus, "name": robot_name,
		"pos": [global_position.x, global_position.y, global_position.z], "hex": work_hex,
		"hopper": hopper.to_dict(), "job": job, "build": build.duplicate(), "trait": trait_id}  # [drones] build + trait
