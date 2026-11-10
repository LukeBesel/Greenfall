class_name Patch
extends CharacterBody3D
## P-47CH "Lumi": the player robot. Movement on treads, scooping junk into the chest compartment,
## compacting cubes (Pure / Perfect / Lumpy), carrying a wobbly stack and dropping or stacking cubes.
## All intent comes from an InputSource so the player, touch and the autoplay bot share this code.

const PICKUP_RANGE: float = 1.9
const CUBE_TIME: float = 1.7
## Pieces at least this big get the heavy pickup animation.
const BIG_PIECE_VOL: float = 1.5

var input: InputSource
var world: Node  # the slice scene: field, view, collect_piece(), depot

var compartment := Compartment.new()
var carried: Array[JunkCube] = []
var model: PatchModel
var detector: PartDetector
var pickup_fx: PickupFx

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
## [orbit] Set by enable_sphere() once the planet is built (planet/orbit/): radial gravity and
## hover through SphereMotor, input in the camera's surface frame.
var sphere: SphereSurface
var sphere_motor: SphereMotor
var sphere_cam: Node3D  # SphereCam (anything with a `frame: Basis`)
var _shape: CollisionShape3D
var water: float = 0.0
var _plant_t: float = 0.0
var _water_t: float = 0.0


func _ready() -> void:
	add_to_group("patch")
	collision_layer = 2
	collision_mask = 1 | 4 | PhysLayers.PROP  # [world2] props are solid
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.1, 1.2, 1.0)
	shape.shape = box
	shape.position = Vector3(0, 0.6, 0)
	add_child(shape)
	_shape = shape
	model = PatchModel.new()
	model.name = "Model"
	add_child(model)
	detector = PartDetector.new()
	detector.name = "Detector"
	detector.patch = self
	add_child(detector)
	pickup_fx = PickupFx.new()
	pickup_fx.name = "PickupFx"
	pickup_fx.model = model
	add_child(pickup_fx)
	_stack_root = Node3D.new()
	_stack_root.name = "Stack"
	_stack_root.position = model.stack_point
	add_child(_stack_root)
	if input == null:
		input = PlayerInput.new()


## [orbit] Local up: the radial direction on the planet (+Y until enable_sphere has run).
func up() -> Vector3:
	return sphere.up_at(global_position) if sphere else Vector3.UP


## [orbit] Switches Lumi to a round planet: SphereMotor movement (hover, radial gravity, boost,
## jump), the collision box lifted so it only meets walls and props.
func enable_sphere(surface: SphereSurface, cam_node: Node3D) -> void:
	sphere = surface
	sphere_cam = cam_node
	sphere_motor = SphereMotor.new(surface)
	sphere_motor.landed.connect(func(impact: float) -> void:
		if impact > 2.0:
			model.squash(-clampf(impact * 0.06, 0.1, 0.45)))
	sphere_motor.jumped.connect(func() -> void:
		model.squash(0.3)
		Audio.play("whoosh", 1.3, -12.0))
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	if _shape:
		(_shape.shape as BoxShape3D).size = Vector3(1.1, 0.95, 1.0)
		_shape.position = Vector3(0, 0.25 + 0.475, 0)


## [orbit] Puts Lumi on the planet's ground under `pos`, facing `fwd`.
func place_on_sphere(pos: Vector3, fwd: Vector3) -> void:
	sphere_motor.place(self, pos, fwd)
	_prev_vel = Vector3.ZERO


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
	# wedged against the base), put him back on the ground where he is instead of falling forever.
	if sphere.altitude(global_position) < -3.0:  # [orbit] under the planet's ground
		place_on_sphere(global_position, forward())
		GameState.inc_stat("fell_through")
	_handle_cubing(delta)
	_handle_tools(delta)
	if tool == Tool.SCOOP:
		_handle_scoop(delta)
	_handle_interact()
	_update_stack(delta)
	_update_hints(delta)


# --- Movement -----------------------------------------------------------------

## [v4bots] Hover Jets (data/upgrades.json hover_jets), a world where everyone floats (Tidewell),
## or riding the hover-sled (player/vehicle.gd parks itself under Lumi while mounted).
func can_hover_water() -> bool:
	if stat("hover_water") >= 1.0 or (world != null and world.has_meta("hover_water")):
		return true
	var sled: HoverSled = get_node_or_null("HoverSled") as HoverSled
	return sled != null and sled.mounted


func _water_at(p: Vector3) -> bool:
	if world == null or world.field == null:
		return false
	var h: int = world.field.hex_at(p)
	return h >= 0 and world.field.is_water(h)


## [v4bots] The move with the lake taken out: straight on if the ground ahead is land, else the
## nearest turn (up to 85 degrees either way) that stays on land, slowed by how far it turns, so
## he slides along the shore. ZERO when every way ahead is water.
func shore_clamp(wish: Vector3, probe_m: float) -> Vector3:
	var out: Vector3 = shore_clamp_at(global_position, up(), wish, probe_m, _water_at)
	if not out.is_equal_approx(wish):
		_shore_hint()
	return out


static func shore_clamp_at(pos: Vector3, u: Vector3, wish: Vector3, probe_m: float, is_water: Callable) -> Vector3:
	var n: Vector3 = wish.normalized()
	if not bool(is_water.call(pos + n * probe_m)):
		return wish
	for deg: float in [25.0, -25.0, 50.0, -50.0, 70.0, -70.0, 85.0, -85.0]:
		var d: Vector3 = n.rotated(u, deg_to_rad(deg))
		if not bool(is_water.call(pos + d * probe_m)):
			return d * wish.length() * cos(deg_to_rad(deg))
	return Vector3.ZERO


## Once per save: why he stopped, and the fix.
func _shore_hint() -> void:
	if GameState.flags.get("shore_hint", false) or stat("hover_water") >= 1.0:
		return
	GameState.flags["shore_hint"] = true
	EventBus.toast.emit(tr("Lumi can't swim. Hover Jets at the workbench let him float over lakes."), "info")


func _move(delta: float) -> void:
	var wish: Vector3 = Vector3.ZERO
	if _cubing <= 0.0:
		# [orbit] The stick is camera-local (x right, z back): read it in the camera's surface frame.
		var mv: Vector3 = input.get_world_move(0.0)
		if input.get("world_space") == true:  # [orbB] the autoplay bot steers in world space
			wish = mv - up() * mv.dot(up())
		else:
			var f: Basis = sphere_cam.get("frame") if sphere_cam and "frame" in sphere_cam else global_basis
			wish = f.x * mv.x + f.z * mv.z
	var speed: float = stat("move_speed") * (0.55 if input.scoop_held() and wish.length() > 0.1 else 1.0)
	# Wading: Patch can't swim yet. Shallow lake water slows him and splashes.
	var here: int = world.field.hex_at(global_position) if world and world.field else -1
	var hover: bool = can_hover_water()
	if here >= 0 and world.field.is_water(here) and not hover:  # [planet-tidewell] floats over water there
		speed *= 0.45
		if _tangent(velocity).length() > 0.5 and randf() < 0.15:
			Vfx.burst("soil", global_position + up() * 0.15, Color(0.6, 0.7, 0.75, 0.7), 0.3)
	# [v4bots] Owner item 54: no Hover Jets, no lakes. On land he stops at the shore (sliding along
	# it); already in the water (a load, a knock) he can still wade out.
	var shore: bool = here >= 0 and not hover and not world.field.is_water(here)
	var from: Vector3 = global_position
	if shore and wish.length() > 0.01:
		wish = shore_clamp(wish, 0.9 + stat("move_speed") * delta * 4.0)
	# A heavy stack slows him a touch, never much.
	speed *= 1.0 - 0.03 * carried.size()
	sphere_motor.speed = speed
	var boost: bool = _cubing <= 0.0 and input.has_method("boost_held") and bool(input.call("boost_held"))
	var jump: bool = _cubing <= 0.0 and input.has_method("jump_pressed") and bool(input.call("jump_pressed"))
	sphere_motor.step(self, wish, delta, boost, jump)
	if shore and _water_at(global_position):  # [v4bots] momentum (a boost) carried him past the probe
		global_position = from
		sphere_motor.hv = Vector3.ZERO
		velocity = up() * velocity.dot(up())
		_shore_hint()
	# Nudge cubes we bump into.
	for i: int in get_slide_collision_count():
		var col: KinematicCollision3D = get_slide_collision(i)
		var body: Object = col.get_collider()
		if body is JunkCube and not (body as JunkCube).carried:
			(body as JunkCube).apply_central_impulse(-col.get_normal() * 0.6)
	var hspeed: float = _tangent(velocity).length()
	var accel_w: Vector3 = (velocity - _prev_vel) / maxf(delta, 0.0001)
	_prev_vel = velocity
	var local_acc: Vector3 = global_transform.basis.inverse() * accel_w
	model.set_motion(hspeed, hspeed / maxf(stat("move_speed"), 0.1), Vector2(local_acc.x, -local_acc.z), delta)
	var now_moving: bool = hspeed > 0.6
	if now_moving != _moving:
		_moving = now_moving
		Vfx.burst("dust", global_position + up() * 0.1, Color(0.8, 0.65, 0.5, 0.7), 0.8)
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


## The part of v along the ground (drops the local-up component).
func _tangent(v: Vector3) -> Vector3:
	var u: Vector3 = up()
	return v - u * v.dot(u)


# --- Tools: plant and water ---------------------------------------------------------

func water_cap() -> float:
	return float(Economy.planet_table("plants").get("water_tank", 30)) if _water_cap < 0.0 else _water_cap

var _water_cap: float = -1.0
var _no_slot_ms: int = -100000  # [v4grow]


func set_tool(t: int) -> void:
	if t != Tool.SCOOP and (world == null or world.get("garden") == null or not world.garden.unlocked()):
		EventBus.toast.emit(tr("No seeds yet. Keep cleaning."), "info")
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
		_water_cap = float(Economy.planet_table("plants").get("water_tank", 30))
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
		if s < 0 and Time.get_ticks_msec() - _no_slot_ms > 6000:  # [v4grow] say why nothing went in
			_no_slot_ms = Time.get_ticks_msec()
			EventBus.toast.emit(tr("Seeds need clean, open ground: not streets, kerbs or the pad."), "info")
		if s >= 0:
			if g.plant(s):
				model.set_scooping(true)
				model.shudder(0.15)
			else:
				Audio.play("buzz", 1.2, -10.0)
				EventBus.toast.emit(tr("Out of seeds. Blooming plants drop more."), "info")
				_plant_t = 2.0
	elif tool == Tool.WATER and _water_t <= 0.0:
		_water_t = 0.25
		if water <= 0.0:
			Audio.play("buzz", 1.0, -12.0)
			_water_t = 1.5
			EventBus.toast.emit(tr("Watering can is empty. Refill at the hub."), "info")
			return
		# The old can leaks: a bit is lost with every pour (an upgrade fixes it).
		water = maxf(0.0, water - (1.0 if GameState.level_of("fix_can") > 0 else 1.3))
		var spot: Vector3 = global_position + forward() * 1.3
		Vfx.burst("soil", spot + up() * 0.6, Color(0.55, 0.75, 1.0, 0.8), 0.7)
		Vfx.burst("dust", spot + up() * 0.05, Color(0.6, 0.75, 0.9, 0.4), 0.3)
		if randf() < 0.5:
			Audio.play("steam", 1.8, -16.0)
		for slot: int in g.planted_near(global_position, forward()):
			g.water(slot, 30.0)


# --- Scooping -----------------------------------------------------------------

func scoop_origin() -> Vector3:
	return global_position + up() * 0.2 - global_transform.basis.z * 0.25


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
		var field: HexField = world.field  # [orbit] pull along the ground (local up)
		for pid: int in field.pieces_within(scoop_origin(), stat("scoop_reach") + mag):
			var to_me: Vector3 = _tangent(scoop_origin() - field.piece_pos[pid])
			if to_me.length() > 0.4:
				world.view.move_piece(pid, field.piece_pos[pid] + to_me.normalized() * minf(2.5 * delta, to_me.length()))
	_scoop_timer -= delta
	if _scoop_timer > 0.0:
		return
	# Multi-Lock: one laser per piece, several pieces per pulse once upgraded.
	var locks: int = maxi(1, int(round(stat("pickup_count"))))
	var took: int = 0
	for k: int in locks:
		if k > 0 and not compartment.can_accept(cap):
			break
		var pid: int = Pace.find_scoop_target(world.field, scoop_origin(), forward(), stat("scoop_reach"), stat("scoop_width"), Pace.lift_class())  # [pace] Lift Strength
		if pid < 0:
			if k == 0 and not Pace.press_hint(self, world.field):  # [orbC] stuck with a part-full chest: say "press"
				Pace.heavy_hint(self, world.field, scoop_origin(), forward(), stat("scoop_reach"), stat("scoop_width"))  # [pace]
			break
		var extra: PackedInt32Array = world.field.cluster_extra(pid)  # [world2] gen-2 junk is finer: grab the little cluster
		_take_piece(pid)
		took += 1
		for e: int in extra:
			if world.field.piece_alive[e] == 1 and compartment.can_accept(cap):
				_take_piece(e)
	if took > 0:
		_scoop_timer = 1.0 / maxf(stat("scoop_rate"), 0.5)


func _take_piece(pid: int) -> void:
	var field: HexField = world.field
	var type_id: String = Economy.junk_ids[field.piece_type[pid]]
	var vol: float = field.piece_vol[pid]
	var whole: bool = true
	if field.has_method("bite"):  # [orbB] globe pieces are heavy: a flat scoop pulse's worth per take
		vol = float(field.call("bite", pid, SphereField.FLAT_BITE_VOL))
		whole = bool(field.call("is_whole_take", pid, vol))
	var start_xf: Transform3D = world.view.piece_transform(pid)
	var mesh: Mesh = world.view.piece_mesh(pid)
	var color: Color = Color.html(str(Economy.junk_types[type_id].get("cube_color", "#888888")))
	compartment.reserve(vol)
	if world.get("events") != null:
		world.events.on_patch_take(pid, vol)  # [events] streak, surge share, audit score
	if whole:
		world.collect_piece(pid)
	elif world.has_method("piece_bitten"):  # [orbB] the piece stays; its cell's junk goes down
		world.call("piece_bitten", pid)
	# Tractor beam show (pooled, see PickupFx): lock-on reticle, twin lasers, lift with arcs,
	# compress to light and stream into the chest hopper. Big pieces get a heavier, slower take.
	var big: bool = vol >= BIG_PIECE_VOL
	var dur: float = 0.52 if big else 0.4
	pickup_fx.launch(mesh, start_xf, dur, big, color)
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
	Audio.play_ladder("clink", _scoop_combo - 1, -7.0)  # [first] gentle combo ladder
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
	if stat("auto_compactor") >= 1.0 and Pace.baler_unlocked() and not compartment.can_accept(cap) and _cubing <= 0.0:  # [pace]
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
			FeelFx.bale_press(self)  # [first] squash/stretch, thunk, small shake
			Input.start_joy_vibration(0, 0.5, 0.7, 0.25)
		if not _cube_spawned and t >= 0.68:
			_cube_spawned = true
			_spawn_cube()
		if _cubing <= 0.0:
			model.press(0.0)
			model.open_hatch(0.0)
		return
	if input.cube_pressed():
		if not Pace.baler_unlocked():  # [pace] the bale press is an upgrade
			Pace.baler_hint(self)
			return
		if compartment.is_empty() or compartment.pending > 0.0:
			if compartment.is_empty():
				Audio.play("buzz", 1.2, -10.0)
			return
		start_cube()


func start_cube() -> void:
	if compartment.is_empty() or not Pace.baler_unlocked():  # [pace]
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
	if world.get("events") != null:
		info = world.events.apply_bale_bonus(info)  # [events] streak tier + Salvage Surge share
	_was_in_band = false
	model.set_fill(0.0, [0.9, 1.0])
	EventBus.compartment_changed.emit(0.0, cap)
	var cube: JunkCube = JunkCube.create(info["value"], info)
	world.add_cube(cube)
	cube.global_position = to_global(model.back_hatch_point + Vector3(0, 0.05, 0.3))
	cube.global_basis = global_basis.orthonormalized()
	# Pushed out by the ram: slides off the lip and drops with weight.
	cube.linear_velocity = global_transform.basis.z * 1.4 + up() * 0.4
	cube.angular_velocity = global_transform.basis.x * -1.2
	Audio.play("clunk", 1.0, -4.0)
	GameState.inc_stat("cubes_made")
	var label: String = "+" + Settings.fmt(info["value"])
	var color: Color = Color(0.92, 0.94, 0.9)
	if info["perfect"]:
		GameState.inc_stat("perfect_cubes")
		label = tr("PERFECT BALE  %s") % label
		color = Color(1.0, 0.82, 0.4)
		Audio.play("ding", 0.9, -8.0)
		model.set_happy(1.0)
	elif info["lumpy"]:
		GameState.inc_stat("lumpy_cubes")
		label = tr("OVERSTUFFED  %s") % label
		color = Color(0.8, 0.78, 0.82)
	if info["pure"]:
		GameState.inc_stat("pure_cubes")
		label = tr("PURE  %s") % label
	if float(info.get("surge_frac", 0.0)) > 0.0:
		label = tr("SURGE  %s") % label
		color = Color(1.0, 0.82, 0.3)
	if float(info.get("streak_bonus", 0.0)) > 0.0:
		label += tr("  (streak +%d%%)") % int(round(float(info["streak_bonus"]) * 100.0))
	Vfx.float_text(global_position + up() * 1.9, label, color, 0.45, 0.7)
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
	RobotParts.salvage(t, r)  # [ui2] salvaged robot parts pay Parts
	var rd: Dictionary = Economy.rarity(r)
	EventBus.toast.emit(tr("Salvaged: %s") % L10nFmt.part_label(tr(str(rd.get("name", ""))), tr(str(Economy.part_type(t).get("name", "part")))) + "  " + RobotParts.gain_text(r), "reward")  # [v4calm] cut  [i18n2] [ui2]
	Audio.play("ding", 1.3, -10.0)


func _on_part_found(idx: int) -> void:
	var f: HexField = world.field
	var t: int = f.part_type[idx]
	var r: int = f.part_rarity[idx]
	GameState.inc_stat("parts_found")
	RobotParts.salvage(t, r)  # [ui2] pays Parts at the rarity's value
	var rar: Dictionary = Economy.rarity(r)
	var pt: Dictionary = Economy.part_type(t)
	var col: Color = UITheme.rarity_color(r)
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
	Vfx.float_text(pos + Vector3(0, 1.4, 0), L10nFmt.part_label(tr(str(rar.get("name", ""))), tr(str(pt.get("name", "Part")))), col, 0.55, 0.8)  # [i18n2]
	EventBus.toast.emit(tr("Recovered: %s") % L10nFmt.part_label(tr(str(rar.get("name", ""))), tr(str(pt.get("name", "part")))) + "  " + RobotParts.gain_text(r), "reward")  # [v4calm] cut  [i18n2] [qafix] QA #20: name the Parts it paid


func nearest_loose_cube() -> JunkCube:
	var best: JunkCube = null
	var best_d: float = PICKUP_RANGE
	for n: Node in get_tree().get_nodes_in_group("junk_cube"):
		var c: JunkCube = n
		if c.carried or c.claimed:
			continue
		var d: Vector3 = c.global_position - global_position
		d -= up() * d.dot(up()) * 0.5
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
	var u: Vector3 = sphere.up_at(front)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(front + u * 2.5, front - u * 1.0, 1 | 4 | PhysLayers.MOUND)
	var hit: Dictionary = space.intersect_ray(q)
	var base: Vector3 = sphere.ground(u)
	if not hit.is_empty():
		var hp: Vector3 = hit["position"]
		base = front + u * (hp - front).dot(u)
		if hit["collider"] is JunkCube:
			var cp: Vector3 = (hit["collider"] as JunkCube).global_position
			base = cp + u * (hp - cp).dot(u)
	var dest: Vector3 = base + u * (c.size * 0.5 + 0.02)
	var start: Vector3 = c.global_position
	var rest_basis: Basis = global_basis.orthonormalized()
	var tw := c.create_tween()
	tw.tween_method(func(t: float) -> void:
		var top: Vector3 = (start + dest) * 0.5 + u * 0.6
		c.global_position = start.lerp(top, t).lerp(top.lerp(dest, t), t)
		, 0.0, 1.0, 0.2)
	tw.tween_callback(func() -> void:
		c.global_basis = rest_basis
		c.set_carried(false)
		c.linear_velocity = Vector3.ZERO
		Audio.play("thud", 1.0, -6.0)
		c.squish(0.18))
	model.squash(0.2)


func _update_stack(delta: float) -> void:
	if not carried.is_empty():
		_stack_root.position = CarryPoint.of(model, self)  # [world2] held clearly above Lumi, not inside him
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
		Vfx.burst("bits", global_position + up() * 1.0, Color(0.75, 0.4, 0.2), 0.6)
		if _idle_time < 20.0:  # [v4calm] item 50: one soft beep per idle stretch, not every 9 s
			Audio.play("beep", 0.9, -20.0)
	if model.sleeping and fmod(_idle_time, 3.0) < delta:
		Vfx.float_text(global_position + up() * 1.8 + global_basis.x * 0.3, "z", Color(0.9, 0.9, 1.0), 0.7, 0.8)  # [v4calm] silent snore
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
