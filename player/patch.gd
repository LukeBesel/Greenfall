class_name Patch
extends CharacterBody3D
## P-47CH "Patch": the player robot. Movement on treads, scooping junk into the chest compartment,
## compacting cubes (Pure / Perfect / Lumpy), carrying a wobbly stack and dropping or stacking cubes.
## All intent comes from an InputSource so the player, touch and the autoplay bot share this code.

const ACCEL: float = 16.0
const DECEL: float = 22.0
const TURN_RATE: float = 9.0
const GRAVITY: float = 20.0
const PICKUP_RANGE: float = 1.9
const CUBE_TIME: float = 1.7

var input: InputSource
var world: Node  # the slice scene: field, view, collect_piece(), depot
var cam_yaw_provider: Callable = func() -> float: return 0.0

var compartment := Compartment.new()
var carried: Array[JunkCube] = []
var model: PatchModel
var detector: PartDetector

var _scoop_timer: float = 0.0
var _scoop_combo: int = 0
var _combo_timer: float = 0.0
var _cubing: float = 0.0
var _cube_spawned: bool = false
var _crunched: bool = false
var _sweep_timer: float = 0.0
var _buzz_cooldown: float = 0.0
var _was_in_band: bool = false
var _prev_vel := Vector3.ZERO
var _moving: bool = false
var _idle_time: float = 0.0
var _stack_root: Node3D
var _stack_sway := Vector2.ZERO
var _stack_sway_v := Vector2.ZERO
var _distance_accum: float = 0.0
var _dust_timer: float = 0.0
var _focus_hex: int = -1
var prompt: String = ""
enum Tool { SCOOP, PLANT, WATER }
var tool: int = Tool.SCOOP
var water: float = 0.0
var _plant_t: float = 0.0
var _water_t: float = 0.0


func _ready() -> void:
	add_to_group("patch")
	collision_layer = 2
	collision_mask = 1 | 4
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.1, 1.2, 1.0)
	shape.shape = box
	shape.position = Vector3(0, 0.6, 0)
	add_child(shape)
	model = PatchModel.new()
	model.name = "Model"
	add_child(model)
	detector = PartDetector.new()
	detector.name = "Detector"
	detector.patch = self
	add_child(detector)
	_stack_root = Node3D.new()
	_stack_root.name = "Stack"
	_stack_root.position = model.stack_point
	add_child(_stack_root)
	if input == null:
		input = PlayerInput.new()


func stat(id: String) -> float:
	return Economy.stat(id)


func capacity() -> float:
	return stat("capacity")


func carry_cap() -> int:
	return int(round(stat("carry_stack")))


func _physics_process(delta: float) -> void:
	input.update(delta)
	_buzz_cooldown = maxf(0.0, _buzz_cooldown - delta)
	_combo_timer -= delta
	if _combo_timer <= 0.0:
		_scoop_combo = 0
	_move(delta)
	# Safety net: if physics ever pushes Patch through the ground (seen once in a long autoplay run,
	# wedged against the base), put him back in the yard instead of falling forever.
	if global_position.y < -30.0:
		global_position = Vector3(0.0, 0.6, 3.0)
		velocity = Vector3.ZERO
		GameState.inc_stat("fell_through")
		EventBus.toast.emit("Patch rattles back up into the yard. That was odd.", "info")
	_handle_cubing(delta)
	_handle_tools(delta)
	if tool == Tool.SCOOP:
		_handle_scoop(delta)
	_handle_interact()
	_update_stack(delta)
	_update_hints(delta)


# --- Movement -----------------------------------------------------------------

func _move(delta: float) -> void:
	var wish: Vector3 = Vector3.ZERO if _cubing > 0.0 else input.get_world_move(cam_yaw_provider.call())
	var speed: float = stat("move_speed") * (0.55 if input.scoop_held() and wish.length() > 0.1 else 1.0)
	# Wading: Patch can't swim yet. Shallow lake water slows him and splashes.
	var here: int = world.field.hex_at(global_position) if world and world.field else -1
	if here >= 0 and world.field.is_water(here):
		speed *= 0.45
		if Vector2(velocity.x, velocity.z).length() > 0.5 and randf() < 0.15:
			Vfx.burst("soil", global_position + Vector3(0, 0.15, 0), Color(0.6, 0.7, 0.75, 0.7), 0.3)
	# A heavy stack slows him a touch, never much.
	speed *= 1.0 - 0.03 * carried.size()
	var target: Vector3 = wish * speed
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var rate: float = ACCEL if target.length() > hv.length() else DECEL
	hv = hv.move_toward(target, rate * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	if wish.length() > 0.1:
		var target_yaw: float = atan2(-wish.x, -wish.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(TURN_RATE * delta, 0.0, 1.0))
	move_and_slide()
	# Nudge cubes we bump into.
	for i: int in get_slide_collision_count():
		var col: KinematicCollision3D = get_slide_collision(i)
		var body: Object = col.get_collider()
		if body is JunkCube and not (body as JunkCube).carried:
			(body as JunkCube).apply_central_impulse(-col.get_normal() * 0.6)
	var hspeed: float = Vector2(velocity.x, velocity.z).length()
	var accel_w: Vector3 = (velocity - _prev_vel) / maxf(delta, 0.0001)
	_prev_vel = velocity
	var local_acc: Vector3 = global_transform.basis.inverse() * accel_w
	model.set_motion(hspeed, hspeed / maxf(stat("move_speed"), 0.1), Vector2(local_acc.x, -local_acc.z), delta)
	var now_moving: bool = hspeed > 0.6
	if now_moving != _moving:
		_moving = now_moving
		Vfx.burst("dust", global_position + Vector3(0, 0.1, 0), Color(0.8, 0.65, 0.5, 0.7), 0.8)
		Audio.play("squeak", 1.0 if now_moving else 0.85, -10.0, 0.1)
		model.squash(0.25 if now_moving else -0.3)
	if now_moving:
		_idle_time = 0.0
		_dust_timer -= delta
		if _dust_timer <= 0.0:
			_dust_timer = 0.35
			Vfx.burst("dust", global_position + global_transform.basis.z * 0.5, Color(0.8, 0.65, 0.5, 0.45), 0.35)
		_distance_accum += hspeed * delta
		if _distance_accum > 1.0:
			GameState.inc_stat("distance_m", _distance_accum)
			_distance_accum = 0.0
	else:
		_idle_time += delta


# --- Tools: plant and water ---------------------------------------------------------

func water_cap() -> float:
	return float(Economy.read_json("res://data/plants.json").get("water_tank", 30)) if _water_cap < 0.0 else _water_cap

var _water_cap: float = -1.0


func set_tool(t: int) -> void:
	if t != Tool.SCOOP and (world == null or world.get("garden") == null or not world.garden.unlocked()):
		EventBus.toast.emit("No seeds yet. Keep cleaning.", "info")
		return
	if t == tool:
		return
	tool = t
	Audio.play("servo", 1.2 + t * 0.1, -10.0)
	EventBus.tool_changed.emit(t)


func _handle_tools(delta: float) -> void:
	if input is PlayerInput and (input as PlayerInput).enabled:
		if Input.is_action_just_pressed("tool_scoop"):
			set_tool(Tool.SCOOP)
		elif Input.is_action_just_pressed("tool_plant"):
			set_tool(Tool.PLANT)
		elif Input.is_action_just_pressed("tool_water"):
			set_tool(Tool.WATER)
	if _water_cap < 0.0:
		_water_cap = float(Economy.read_json("res://data/plants.json").get("water_tank", 30))
	# Refill at the hub's water barrel (anywhere in the yard).
	if world and world.field and world.field.hex_at(global_position) >= 0 and world.field.hex_hub[world.field.hex_at(global_position)] == 1:
		if water < _water_cap:
			water = minf(_water_cap, water + delta * 8.0)
	if world == null or world.get("garden") == null or _cubing > 0.0:
		return
	var g: Garden = world.garden
	_plant_t -= delta
	_water_t -= delta
	if not input.scoop_held():
		return
	if tool == Tool.PLANT and _plant_t <= 0.0:
		_plant_t = 0.65
		var s: int = g.free_slot_near(global_position, forward())
		if s >= 0:
			if g.plant(s):
				model.set_scooping(true)
				model.shudder(0.15)
			else:
				Audio.play("buzz", 1.2, -10.0)
				EventBus.toast.emit("Out of seeds. Blooming plants drop more.", "info")
				_plant_t = 2.0
	elif tool == Tool.WATER and _water_t <= 0.0:
		_water_t = 0.25
		if water <= 0.0:
			Audio.play("buzz", 1.0, -12.0)
			_water_t = 1.5
			EventBus.toast.emit("Watering can is empty. Refill at the hub.", "info")
			return
		# The old can leaks: a bit is lost with every pour (an upgrade fixes it).
		water = maxf(0.0, water - (1.0 if GameState.level_of("fix_can") > 0 else 1.3))
		var spot: Vector3 = global_position + forward() * 1.3
		Vfx.burst("soil", spot + Vector3(0, 0.6, 0), Color(0.55, 0.75, 1.0, 0.8), 0.7)
		Vfx.burst("dust", spot + Vector3(0, 0.05, 0), Color(0.6, 0.75, 0.9, 0.4), 0.3)
		if randf() < 0.5:
			Audio.play("steam", 1.8, -16.0)
		for slot: int in g.planted_near(global_position, forward()):
			g.water(slot, 30.0)


# --- Scooping -----------------------------------------------------------------

func scoop_origin() -> Vector3:
	return global_position + Vector3(0, 0.2, 0) - global_transform.basis.z * 0.25


func forward() -> Vector3:
	return -global_transform.basis.z


func _handle_scoop(delta: float) -> void:
	if world == null or _cubing > 0.0:
		return
	var holding: bool = input.scoop_held()
	if not holding:
		_scoop_timer = 0.0
		return
	model.set_scooping(true)
	_sweep_timer -= delta
	if _sweep_timer <= 0.0 and world.get("litter") != null:
		_sweep_timer = 0.08
		var swept: int = world.litter.sweep(scoop_origin() + forward() * 0.9, stat("scoop_width") * 0.55)
		if swept > 0:
			Vfx.burst("dust", scoop_origin() + forward() * 0.9, Color(0.62, 0.58, 0.52, 0.35), 0.3)
			if randf() < 0.35:
				Audio.play("whoosh", randf_range(1.4, 1.8), -18.0)
	var cap: float = capacity()
	if not compartment.can_accept(cap):
		if _buzz_cooldown <= 0.0:
			_buzz_cooldown = 0.8
			Audio.play("buzz", 1.0, -8.0)
			model.shudder(0.12)
			EventBus.compartment_changed.emit(compartment.fill, cap)  # HUD shakes the meter
		return
	# Magnet arm: pull nearby junk toward the scoop.
	var mag: float = stat("magnet_radius")
	if mag > 0.0:
		var field: HexField = world.field
		for pid: int in field.pieces_within(scoop_origin(), stat("scoop_reach") + mag):
			var to_me: Vector3 = scoop_origin() - field.piece_pos[pid]
			to_me.y = 0.0
			if to_me.length() > 0.4:
				world.view.move_piece(pid, field.piece_pos[pid] + to_me.normalized() * minf(2.5 * delta, to_me.length()))
	_scoop_timer -= delta
	if _scoop_timer > 0.0:
		return
	var pid: int = world.field.find_scoop_target(scoop_origin(), forward(), stat("scoop_reach"), stat("scoop_width"))
	if pid < 0:
		return
	_scoop_timer = 1.0 / maxf(stat("scoop_rate"), 0.5)
	_take_piece(pid)


func _take_piece(pid: int) -> void:
	var field: HexField = world.field
	var type_id: String = Economy.junk_ids[field.piece_type[pid]]
	var vol: float = field.piece_vol[pid]
	var start_xf: Transform3D = world.view.piece_transform(pid)
	var mesh: Mesh = world.view.piece_mesh(pid)
	var color: Color = Color.html(str(Economy.junk_types[type_id].get("cube_color", "#888888")))
	compartment.reserve(vol)
	world.collect_piece(pid)
	# Tractor beam: the claw locks on, the piece lifts and spins in the beam, then is pulled in.
	var flyer := MeshInstance3D.new()
	flyer.mesh = mesh
	get_tree().current_scene.add_child(flyer)
	flyer.global_transform = start_xf
	var start: Vector3 = start_xf.origin
	var start_scale: Vector3 = start_xf.basis.get_scale()
	var dur: float = 0.36
	Vfx.burst("sparkle", start + Vector3(0, 0.05, 0), Color(0.45, 0.9, 1.0), 0.25)
	var tw := flyer.create_tween()
	tw.tween_method(func(t: float) -> void:
		if not is_instance_valid(self) or not is_instance_valid(flyer):
			return
		var claw: Vector3 = model.claw_point()
		var lift: Vector3 = start + Vector3(0, 0.35 * smoothstep(0.0, 0.45, t), 0)
		var pos: Vector3 = lift.lerp(claw, smoothstep(0.4, 1.0, t))
		flyer.global_position = pos
		flyer.scale = start_scale * lerpf(1.0, 0.25, smoothstep(0.55, 1.0, t))
		flyer.rotation += Vector3(0.06, 0.12, 0.04)
		model.beam_at(pos)
		, 0.0, 1.0, dur)
	tw.tween_callback(func() -> void:
		if is_instance_valid(self):
			model.beam_at(null))
	tw.tween_callback(flyer.queue_free)
	# Arrival is timer-driven so a cut-short animation can never leave volume stuck as pending.
	get_tree().create_timer(dur, false).timeout.connect(func() -> void:
		if is_instance_valid(self):
			_piece_arrived(type_id, vol, color))


func _piece_arrived(type_id: String, vol: float, color: Color) -> void:
	compartment.add(type_id, vol)
	_maybe_salvage_part(type_id)
	world.salvage_materials(type_id, vol)
	GameState.add_junk_removed(type_id, vol)
	_scoop_combo = mini(_scoop_combo + 1, 10)
	_combo_timer = 0.7
	Audio.play_scale("clink", _scoop_combo - 1, -6.0)
	model.squash(0.08)
	Vfx.burst("bits", to_global(model.chest_point), color, 0.4)
	var cap: float = capacity()
	EventBus.junk_scooped.emit(type_id, global_position)
	EventBus.compartment_changed.emit(compartment.fill, cap)
	var band: Array = Economy.cube_rules.get("perfect_band", [0.9, 1.0])
	model.set_fill(compartment.ratio(cap), band)
	var in_band: bool = compartment.in_perfect_band(cap, band)
	if in_band and not _was_in_band:
		Audio.play("ding", 1.0, -6.0)
		model.flash()
	_was_in_band = in_band
	if stat("auto_compactor") >= 1.0 and not compartment.can_accept(cap) and _cubing <= 0.0:
		start_cube()


# --- Cubing -------------------------------------------------------------------

func _handle_cubing(delta: float) -> void:
	if _cubing > 0.0:
		_cubing -= delta
		var t: float = 1.0 - _cubing / CUBE_TIME  # 0..1 through the cycle
		# Ram down (0-0.5), ram up + hatch open (0.5-0.7), eject (0.68), hatch closes (0.8-1.0).
		model.press(clampf(t / 0.5, 0.0, 1.0) if t < 0.55 else clampf(1.0 - (t - 0.55) / 0.2, 0.0, 1.0))
		model.open_hatch(clampf((t - 0.5) / 0.15, 0.0, 1.0) if t < 0.8 else clampf(1.0 - (t - 0.8) / 0.2, 0.0, 1.0))
		if t > 0.3 and not _crunched:
			_crunched = true
			Audio.play("crunch", 0.85, -3.0)
			EventBus.shake_requested.emit(0.12)
			Input.start_joy_vibration(0, 0.5, 0.7, 0.25)
		if not _cube_spawned and t >= 0.68:
			_cube_spawned = true
			_spawn_cube()
		if _cubing <= 0.0:
			model.press(0.0)
			model.open_hatch(0.0)
		return
	if input.cube_pressed():
		if compartment.is_empty() or compartment.pending > 0.0:
			if compartment.is_empty():
				Audio.play("buzz", 1.2, -10.0)
			return
		start_cube()


func start_cube() -> void:
	if compartment.is_empty():
		return
	_cubing = CUBE_TIME
	_cube_spawned = false
	_crunched = false
	model.shudder(CUBE_TIME * 0.45)
	Audio.play("hydraulic", 1.0, -4.0)
	Audio.play("groan", 1.0, -8.0)
	for vp: Vector3 in model.vent_points:
		Vfx.burst("steam", to_global(vp), Color(0.92, 0.92, 0.9, 0.5), 0.6)


func _spawn_cube() -> void:
	var cap: float = capacity()
	var contents: Dictionary = compartment.take_all()
	var info: Dictionary = Economy.evaluate_cube(contents, cap)
	_was_in_band = false
	model.set_fill(0.0, [0.9, 1.0])
	EventBus.compartment_changed.emit(0.0, cap)
	var cube: JunkCube = JunkCube.create(info["value"], info)
	world.add_cube(cube)
	cube.global_position = to_global(model.back_hatch_point + Vector3(0, 0.05, 0.3))
	cube.rotation.y = rotation.y
	# Pushed out by the ram: slides off the lip and drops with weight.
	cube.linear_velocity = global_transform.basis.z * 1.4 + Vector3(0, 0.4, 0)
	cube.angular_velocity = global_transform.basis.x * -1.2
	Audio.play("clunk", 1.0, -4.0)
	GameState.inc_stat("cubes_made")
	var label: String = "+" + Settings.fmt(info["value"])
	var color: Color = Color(0.92, 0.94, 0.9)
	if info["perfect"]:
		GameState.inc_stat("perfect_cubes")
		label = "PERFECT BALE  " + label
		color = Color(1.0, 0.82, 0.4)
		Audio.play("ding", 0.9, -8.0)
		model.set_happy(1.0)
	elif info["lumpy"]:
		GameState.inc_stat("lumpy_cubes")
		label = "OVERSTUFFED  " + label
		color = Color(0.8, 0.78, 0.82)
	if info["pure"]:
		GameState.inc_stat("pure_cubes")
		label = "PURE  " + label
	Vfx.float_text(global_position + Vector3(0, 1.9, 0), label, color, 0.45, 0.7)
	EventBus.cube_made.emit(info)
	get_tree().create_timer(1.5).timeout.connect(func() -> void: if is_instance_valid(model): model.set_happy(0.5))


# --- Carrying -----------------------------------------------------------------

func _handle_interact() -> void:
	if _cubing > 0.0:
		return
	if input.interact_pressed():
		if detector.can_dig() and carried.is_empty():
			detector.dig(_on_part_found)
			return
		var c: JunkCube = nearest_loose_cube()
		if c and carried.size() < carry_cap():
			pick_up(c)
		elif not carried.is_empty():
			place_top_cube()
		elif world and world.has_method("try_interact"):
			world.try_interact(self)
	elif input.drop_pressed() and not carried.is_empty():
		place_top_cube()


## Electronics (and rarely metal) junk sometimes yields a usable robot part.
func _maybe_salvage_part(type_id: String) -> void:
	var chance: float = float(Economy.robot_cfg.get("part_drop", {}).get(type_id, 0.0))
	if randf() >= chance:
		return
	var rar: Array = Economy.parts.get("rarities", [])
	var roll: float = randf() * 100.0
	var r: int = 0
	var acc: float = 0.0
	for i: int in rar.size():
		acc += float(rar[i]["weight"])
		if roll <= acc:
			r = i
			break
	var t: int = randi() % Economy.parts.get("types", [1]).size()
	GameState.parts.append({"type": t, "rarity": r})
	EventBus.part_found.emit(t, r)
	var rd: Dictionary = Economy.rarity(r)
	EventBus.toast.emit("Salvaged: %s %s" % [rd.get("name", ""), Economy.part_type(t).get("name", "part")], "hint")
	Audio.play("ding", 1.3, -10.0)


func _on_part_found(idx: int) -> void:
	var f: HexField = world.field
	var t: int = f.part_type[idx]
	var r: int = f.part_rarity[idx]
	GameState.parts.append({"type": t, "rarity": r})
	GameState.inc_stat("parts_found")
	EventBus.part_found.emit(t, r)
	var rar: Dictionary = Economy.rarity(r)
	var pt: Dictionary = Economy.part_type(t)
	var col: Color = Color.html(str(rar.get("color", "#ffffff")))
	var pos: Vector3 = f.part_pos[idx]
	# The part surfaces: a dirty little prop pops up and glints in its rarity color.
	var mi := MeshInstance3D.new()
	mi.mesh = AssetLib.model_mesh(str(pt.get("model", "metal_toolbox")))
	get_tree().current_scene.add_child(mi)
	mi.global_position = pos - Vector3(0, 0.3, 0)
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_position", pos + Vector3(0, 0.6, 0), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.8)
	tw.tween_property(mi, "global_position", to_global(model.chest_point), 0.35)
	tw.tween_callback(mi.queue_free)
	Vfx.burst("sparkle", pos + Vector3(0, 0.6, 0), col, 0.7)
	Audio.play("ding", 1.0 if r < 3 else 0.8, -6.0)
	if r >= 3:
		Audio.play("fanfare", 1.0, -8.0)
	Vfx.float_text(pos + Vector3(0, 1.4, 0), "%s %s" % [rar.get("name", ""), pt.get("name", "Part")], col, 0.55, 0.8)
	EventBus.toast.emit("Recovered: %s %s" % [rar.get("name", ""), pt.get("name", "part")], "hint")


func nearest_loose_cube() -> JunkCube:
	var best: JunkCube = null
	var best_d: float = PICKUP_RANGE
	for n: Node in get_tree().get_nodes_in_group("junk_cube"):
		var c: JunkCube = n
		if c.carried or c.claimed:
			continue
		var d: Vector3 = c.global_position - global_position
		d.y *= 0.5
		# Prefer cubes in front.
		var score: float = d.length() - maxf(0.0, d.normalized().dot(forward())) * 0.4
		if score < best_d:
			best_d = score
			best = c
	return best


func pick_up(c: JunkCube) -> void:
	c.set_carried(true)
	c.reparent(_stack_root, true)
	carried.append(c)
	var target_y: float = _stack_height(carried.size() - 1)
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "position", Vector3(0, target_y, 0), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "rotation", Vector3(0, randf_range(-0.15, 0.15), 0), 0.22)
	Audio.play("pop", 0.8, -6.0)
	model.squash(-0.2)
	c.squish(0.2)


func _stack_height(index: int) -> float:
	var h: float = 0.0
	for i: int in index:
		h += carried[i].size
	return h + carried[index].size * 0.5 if index < carried.size() else h


## Removes the top carried cube (for the Depot). Returns null when empty.
func pop_carried_cube() -> JunkCube:
	if carried.is_empty():
		return null
	var c: JunkCube = carried.pop_back()
	# Hand it back to the world's Cubes node so it persists (Depot/stations reparent it again).
	var root: Node = world.get_node_or_null("Cubes") if world else null
	c.reparent(root if root else get_tree().current_scene, true)
	return c


## Places the top carried cube in front: on the ground or on top of a cube already there (towers!).
func place_top_cube() -> void:
	var c: JunkCube = pop_carried_cube()
	if c == null:
		return
	var front: Vector3 = global_position + forward() * 1.25
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(front + Vector3(0, 12.0, 0), front + Vector3(0, -1.0, 0), 1 | 4)
	var hit: Dictionary = space.intersect_ray(q)
	var y: float = 0.0
	if not hit.is_empty():
		y = (hit["position"] as Vector3).y
		if hit["collider"] is JunkCube:
			front = (hit["collider"] as JunkCube).global_position
			front.y = y
	var dest: Vector3 = front + Vector3(0, c.size * 0.5 + 0.02, 0)
	var start: Vector3 = c.global_position
	var tw := c.create_tween()
	tw.tween_method(func(t: float) -> void:
		var top: Vector3 = (start + dest) * 0.5 + Vector3(0, 0.6, 0)
		c.global_position = start.lerp(top, t).lerp(top.lerp(dest, t), t)
		, 0.0, 1.0, 0.2)
	tw.tween_callback(func() -> void:
		c.rotation = Vector3(0, rotation.y, 0)
		c.set_carried(false)
		c.linear_velocity = Vector3.ZERO
		Audio.play("thud", 1.0, -6.0)
		c.squish(0.18))
	model.squash(0.2)


func _update_stack(delta: float) -> void:
	# Wobbly spring sway driven by acceleration.
	var acc: Vector3 = global_transform.basis.inverse() * (velocity - _prev_vel)
	_stack_sway_v += (Vector2(acc.z, -acc.x) * 0.9 - _stack_sway * 60.0 - _stack_sway_v * 7.0) * delta
	_stack_sway += _stack_sway_v * delta
	_stack_sway = _stack_sway.clamp(Vector2(-0.35, -0.35), Vector2(0.35, 0.35))
	for i: int in carried.size():
		var c: JunkCube = carried[i]
		var k: float = float(i + 1) / maxf(carried.size(), 1.0)
		c.position.x = -_stack_sway.y * k * 0.6 * (i + 1) * 0.5
		c.position.z = _stack_sway.x * k * 0.6 * (i + 1) * 0.5
		c.rotation.x = _stack_sway.x * 0.5 * k
		c.rotation.z = _stack_sway.y * 0.5 * k


# --- Hints / idle ---------------------------------------------------------------

func _update_hints(delta: float) -> void:
	prompt = ""
	var look: Variant = null
	var near_cube: JunkCube = nearest_loose_cube()
	if near_cube and carried.size() < carry_cap():
		prompt = "pick_up"
		look = near_cube.global_position
	elif not carried.is_empty():
		var depot: Node3D = world.depot if world else null
		if depot:
			look = depot.global_position
			prompt = "place" if not (depot as Depot).pad_contains(global_position) else ""
	elif world and world.field:
		var pid: int = world.field.find_scoop_target(scoop_origin(), forward(), stat("scoop_reach") + 2.0, stat("scoop_width") + 1.5)
		if pid >= 0:
			look = world.field.piece_pos[pid]
	if prompt == "" and detector.can_dig() and carried.is_empty():
		prompt = "dig"
	if world and world.has_method("interact_prompt") and prompt == "":
		prompt = world.interact_prompt(self)
	model.look_toward(look)
	# Idle: after a while Patch shakes off rust flakes; much later he dozes off.
	model.sleeping = _idle_time > 45.0
	if _idle_time > 8.0 and fmod(_idle_time, 9.0) < delta:
		model.shudder(0.25)
		Vfx.burst("bits", global_position + Vector3(0, 1.0, 0), Color(0.75, 0.4, 0.2), 0.6)
		Audio.play("beep", 0.9, -12.0)
	if model.sleeping and fmod(_idle_time, 3.0) < delta:
		Vfx.float_text(global_position + Vector3(0.3, 1.8, 0), "z", Color(0.9, 0.9, 1.0), 0.7, 0.8)
		Audio.play("beep", 0.6, -18.0)
	# Hex under the scoop for the HUD readout.
	if world and world.field:
		var h: int = world.field.hex_at(scoop_origin() + forward() * 1.0)
		if h != _focus_hex:
			_focus_hex = h
			world.view.set_focus_hex(h if h >= 0 and world.field.hex_hub[h] == 0 else -1)


func focus_hex() -> int:
	return _focus_hex


# --- Persistence ----------------------------------------------------------------

func to_dict() -> Dictionary:
	var c: Array = []
	for cube: JunkCube in carried:
		c.append(cube.to_dict())
	return {
		"pos": [global_position.x, global_position.y, global_position.z],
		"yaw": rotation.y,
		"compartment": compartment.to_dict(),
		"carried": c,
	}


func from_dict(d: Dictionary) -> void:
	var p: Array = d.get("pos", [0.0, 0.0, 3.0])
	global_position = Vector3(float(p[0]), float(p[1]) + 0.05, float(p[2]))
	rotation.y = float(d.get("yaw", 0.0))
	restore_cargo(d)


## Portable cargo (compartment + carried stack): {"compartment": {...}, "carried": [cube dicts]}.
## Also used when Patch arrives by rocket with the cargo he took off with.
func restore_cargo(d: Dictionary) -> void:
	compartment.from_dict(d.get("compartment", {}))
	model.set_fill(compartment.ratio(capacity()), Economy.cube_rules.get("perfect_band", [0.9, 1.0]))
	EventBus.compartment_changed.emit(compartment.fill, capacity())
	for cd: Dictionary in d.get("carried", []):
		var cube: JunkCube = JunkCube.from_dict(cd)
		world.add_cube(cube)
		pick_up(cube)
