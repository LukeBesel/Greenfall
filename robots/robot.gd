class_name Robot
extends CharacterBody3D
## A helper robot. Roles:
##   clean (Scoopie): picks junk in its work hex, bales it when full, moves on to the next hex.
##   haul (Haul Bug): carries loose bales to the scale.
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
var _work_t: float = 0.0
var _busy: float = 0.0
var _repath_t: float = 0.0
var _detour_t: float = 0.0
var _detour := Vector3.ZERO
var _progress_pos := Vector3.ZERO
var _progress_t: float = 0.0
var _beam_target: Variant = null


func _ready() -> void:
	add_to_group("robot")
	collision_layer = 8
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.35 if type_id == "scoopie" else 0.45
	sh.height = 0.8
	cs.shape = sh
	cs.position = Vector3(0, 0.45, 0)
	add_child(cs)
	visual = RobotVisual.new()
	add_child(visual)
	rebuild_visual()


func role() -> String:
	return str(Economy.robots.get(type_id, {}).get("role", "clean"))


func rebuild_visual() -> void:
	var look: String = str(Economy.robot_tiers[tier].get("look", "salvage")) if tier < Economy.robot_tiers.size() else "salvage"
	visual.build(type_id, look)


func stat(s: String) -> float:
	return Economy.robot_stat(type_id, s, tier, rarity_bonus)


func _physics_process(delta: float) -> void:
	if world == null:
		return
	_detour_t -= delta
	_progress_t += delta
	_busy = maxf(0.0, _busy - delta)
	var move := Vector3.ZERO
	if _busy <= 0.0:
		move = _think(delta)
	var spd: float = stat("speed")
	var target_v: Vector3 = move * spd
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(target_v, 10.0 * delta)
	velocity = Vector3(hv.x, 0.0 if is_on_floor() else velocity.y - 20.0 * delta, hv.z)
	if visual.hover:
		velocity.y = 0.0
		global_position.y = lerpf(global_position.y, 0.05, delta * 4.0)
	if hv.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-hv.x, -hv.z), clampf(delta * 6.0, 0.0, 1.0))
	move_and_slide()
	visual.animate(hv.length(), _busy > 0.0, delta)
	visual.beam_to(_beam_target if _busy > 0.0 else null)
	for i: int in carried.size():
		carried[i].position = visual.fork_point + Vector3(0, carried[i].size * (0.5 + i), 0)


func _steer(target: Vector3, stop: float) -> Vector3:
	var d: Vector3 = target - global_position
	d.y = 0.0
	var dist: float = d.length()
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


func _think(delta: float) -> Vector3:
	match role():
		"haul":
			return _think_haul()
		_:
			return _think_clean(delta)


# --- Cleaner -------------------------------------------------------------------------

func _think_clean(_delta: float) -> Vector3:
	var field: HexField = world.field
	if not hopper.can_accept(stat("capacity")):
		_make_bale()
		return Vector3.ZERO
	if work_hex < 0 or field.is_clean(work_hex):
		work_hex = _pick_work_hex()
		_target_piece = -1
		if work_hex < 0:
			if not hopper.is_empty():
				_make_bale()
			return Vector3.ZERO
	if _target_piece < 0 or field.piece_alive[_target_piece] == 0:
		_target_piece = _nearest_piece_in(work_hex)
		if _target_piece < 0:
			return Vector3.ZERO
	var p: Vector3 = field.piece_pos[_target_piece]
	var reach: float = 1.6 if visual.hover else 0.75
	var m: Vector3 = _steer(p, reach)
	if m == Vector3.ZERO:
		_pick(_target_piece)
		_target_piece = -1
	return m


func _pick_work_hex() -> int:
	var field: HexField = world.field
	var best: int = -1
	var best_d: float = INF
	for id: int in field.hex_count():
		if field.hex_hub[id] != 0 or field.is_clean(id):
			continue
		var d: float = field.hex_center(id).distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = id
	return best


func _nearest_piece_in(hid: int) -> int:
	var field: HexField = world.field
	var best: int = -1
	var best_d: float = INF
	for pid: int in field.hex_pieces[hid]:
		if field.piece_alive[pid] == 0:
			continue
		var d: float = field.piece_pos[pid].distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = pid
	return best


func _pick(pid: int) -> void:
	var field: HexField = world.field
	if field.piece_alive[pid] == 0:
		return
	var type_id_j: String = Economy.junk_ids[field.piece_type[pid]]
	var vol: float = field.piece_vol[pid]
	var start_xf: Transform3D = world.view.piece_transform(pid)
	var mesh: Mesh = world.view.piece_mesh(pid)
	hopper.reserve(vol)
	world.collect_piece(pid)
	if world.get("litter") != null:
		world.litter.sweep(start_xf.origin, 0.6)
	var dur: float = 0.7 if visual.hover else 0.45
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
		flyer.global_position = pos
		flyer.scale = start_scale * lerpf(1.0, 0.4, t * t)
		, 0.0, 1.0, dur)
	tw.tween_callback(func() -> void:
		flyer.queue_free()
		if is_instance_valid(self):
			hopper.add(type_id_j, vol)
			GameState.add_junk_removed(type_id_j, vol)
			world.salvage_materials(type_id_j, vol * 0.5)
			Audio.play("clink", randf_range(0.8, 1.1), -14.0))
	if hov:
		Vfx.burst("sparkle", start, Color(0.4, 1.0, 0.85), 0.4)
		Audio.play("servo", 1.6, -16.0)
	else:
		Audio.play("servo", randf_range(0.9, 1.1), -18.0)


func _make_bale() -> void:
	if hopper.is_empty() or hopper.pending > 0.0:
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


# --- Hauler ----------------------------------------------------------------------------

func _think_haul() -> Vector3:
	var depot: Depot = world.depot
	var cap: int = int(round(stat("carry")))
	if carried.size() >= cap or (not carried.is_empty() and _find_bale() == null):
		var m: Vector3 = _steer(depot.global_position, 0.6)
		if depot.pad_contains(global_position) or m == Vector3.ZERO:
			for c: JunkCube in carried:
				c.reparent(world.get_node("Cubes"), true)
				c.global_position = depot.global_position + Vector3(randf_range(-0.4, 0.4), 0.6, randf_range(-0.4, 0.4))
				c.set_carried(false)
				c.set_meta("reserved", false)
			carried.clear()
			_busy = 0.5
			Audio.play("clunk", 0.9, -10.0)
		return m
	if _target_bale == null or not is_instance_valid(_target_bale) or _target_bale.carried or _target_bale.claimed:
		_target_bale = _find_bale()
		if _target_bale:
			_target_bale.set_meta("reserved", true)
	if _target_bale == null:
		return Vector3.ZERO
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


func _find_bale() -> JunkCube:
	var best: JunkCube = null
	var best_d: float = INF
	for n: Node in get_tree().get_nodes_in_group("junk_cube"):
		var c: JunkCube = n
		if c.carried or c.claimed or bool(c.get_meta("reserved", false)) and c != _target_bale:
			continue
		if world.depot.pad_contains(c.global_position):
			continue
		var d: float = c.global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = c
	return best


func to_dict() -> Dictionary:
	return {"type": type_id, "tier": tier, "rarity_bonus": rarity_bonus, "name": robot_name,
		"pos": [global_position.x, global_position.y, global_position.z], "hex": work_hex,
		"hopper": hopper.to_dict()}
