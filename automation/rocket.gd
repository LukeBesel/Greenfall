class_name Rocket
extends Node3D
## The base rocket and its launch site. Stands on the LaunchPad (level 5 base) or, after landing
## in a district without one, parked on the ground. Runs the two cinematics:
##   launch(to_hub): establishing shot, Aurora rides the tower lift and boards, holographic countdown
##     with siren, beacons and steam, umbilicals and gangway retract, the engine charges, ignition
##     (energy plume, vapour billowing out of the trench, flash, shake), clamps release, lift-off,
##     climb and arc to a bright dot, then the globe flight and the destination district loads.
##   arrive(): the rocket descends on its plume and lands, the hatch opens, Aurora flies out.
## Both are skippable (Space / Esc / B) and always hand control back (or travel) at the end.
## Higher rocket tiers (RocketTiers) run the sequence faster and the Mk IV warps out.

## Launch site, behind the yard (a landmark from the default camera; the pad floats over the lot).
const PAD_POS := Vector3(-2.0, 0, -13.0)
const ARC_DIR := Vector3(0.8, 0, -0.6)
const LAND_S: float = 6.0

## The arrival cinematic finished (or was skipped) and the player has control again.
signal landed

var world: Node
var pad: LaunchPad
var model: RocketModel
var tier: int = 1
var _mode: String = ""          # "", "launch", "flight", "arrive"
var _t: float = 0.0
var _speed: float = 1.0
var _to_hub: int = 0
var _fired: Dictionary = {}
var _cam: Camera3D
var _shake: float = 0.0
var _shake_t: float = 0.0
var _trail: CPUParticles3D
var _dust: CPUParticles3D
var _dot: MeshInstance3D
var _count: Label3D
var _ui: CanvasLayer
var _bars: Array[ColorRect] = []
var _fade: ColorRect
var _hint: Label
var _base_y: float = 0.0
var _roar_next: float = 0.0
var _siren_next: float = 0.0
var _land_to := Vector3.ZERO
var _flight_s: float = 5.0
var _hidden: Array[Node] = []
# Timeline marks (seconds of sequence time), set per tier in launch().
var _t0: float = 3.8     # countdown starts
var _ig: float = 8.8     # ignition
var _lo: float = 10.2    # lift-off
var _end: float = 19.7   # hand over to the globe flight
var _cd: int = 5
var _warp: bool = false


static func tier_scale(t: int) -> float:
	return [1.0, 1.0, 1.06, 1.12, 1.2][clampi(t, 0, 4)]


func is_flying() -> bool:
	return _mode != ""


## Builds the rocket (and the pad unless `with_pad` is false: parked on the ground).
func setup(with_pad: bool) -> void:
	tier = RocketTiers.tier()
	process_mode = Node.PROCESS_MODE_ALWAYS
	if with_pad:
		pad = LaunchPad.new()
		pad.rocket_tier = tier
		add_child(pad)
		_base_y = LaunchPad.TOP_Y
	model = RocketModel.new()
	add_child(model)
	model.build(tier)
	model.scale = Vector3.ONE * tier_scale(tier)
	model.position = Vector3(0, _base_y, 0)
	_build_colliders()


func _build_colliders() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var hull := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 3.35 if pad else 2.0
	cyl.height = _base_y + 4.0
	hull.shape = cyl
	hull.position = Vector3(0, cyl.height * 0.5, 0)
	body.add_child(hull)
	if pad:
		var tower := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(6.6, 3.0, 1.6)
		tower.shape = bx
		tower.position = Vector3(0, 1.5, LaunchPad.TOWER_Z - 0.1)
		body.add_child(tower)


# --- Launch ----------------------------------------------------------------------------

func launch(to_hub: int) -> void:
	if _mode != "":
		return
	_to_hub = to_hub
	var d: Dictionary = RocketTiers.def(tier)
	_cd = int(d.get("countdown_s", 5))
	_warp = bool(d.get("warp", false))
	_flight_s = float(d.get("flight_s", 5.0))
	_speed = [1.0, 1.0, 1.2, 1.4, 1.8][tier]
	_t0 = 3.8
	_ig = _t0 + _cd
	_lo = _ig + 1.4
	_end = _lo + (3.2 if _warp else 9.5)
	RocketTiers.mark_launched()
	print("[rocket] launch to hub %d (Mk %d, pad=%s)" % [to_hub, tier, pad != null])
	GameState.world.erase("rocket_parked")
	_begin("launch")
	world.music.set_cinematic(true)
	# Aurora steps onto the lift (or hovers up to the hatch when there is no pad).
	var p: Patch = world.patch
	p.set_physics_process(false)
	p.velocity = Vector3.ZERO
	p.visible = true
	p.global_position = _board_start()
	p.rotation.y = 0.0


func _board_start() -> Vector3:
	if pad:
		return pad.lift_point() + Vector3(0, 0.08, 0)
	return global_position + Vector3(0, 0.05, -3.2)


func _hatch_world() -> Vector3:
	var s: float = tier_scale(tier)
	return global_position + Vector3(0, _base_y + RocketModel.HATCH_Y * s - 0.55, -(RocketModel.hull_r(RocketModel.HATCH_Y) * s + 0.25))


func _set_hatch(open_k: float) -> void:
	if model.hatch:
		model.hatch.position.x = open_k * 0.85
		model.hatch.position.z = -RocketModel.hull_r(RocketModel.HATCH_Y) - 0.02 - open_k * 0.08


func _launch_step(dt: float) -> void:
	var t: float = _t
	var p: Patch = world.patch
	# Boarding: lift up the tower, along the gangway, into the hatch.
	var hatch_p: Vector3 = _hatch_world()
	var start: Vector3 = _board_start() if not _fired.has("start_pos") else _fired["start_pos"]
	_fired["start_pos"] = start
	if t < 3.3:
		var up_top := Vector3(start.x, hatch_p.y, start.z)
		if pad:
			pad.lift.global_position = start - Vector3(0, 0.08, 0) + Vector3(0, (up_top.y - start.y) * smoothstep(0.3, 1.9, t), 0)
		var pos: Vector3 = start.lerp(up_top, smoothstep(0.3, 1.9, t)) if t < 1.9 else up_top.lerp(hatch_p, smoothstep(1.9, 3.1, t))
		p.global_position = pos + Vector3(0, sin(t * 5.0) * 0.03, 0)
		p.scale = Vector3.ONE * (1.0 - smoothstep(2.9, 3.25, t) * 0.7)
	_once("lift", 0.3, func() -> void:
		Audio.play("servo", 0.7, -6.0)
		Audio.play("hydraulic", 1.1, -10.0))
	_once("glide", 1.9, func() -> void:
		Audio.play("whoosh", 1.3, -8.0)
		Audio.play("beep", 1.2, -6.0))
	_set_hatch(smoothstep(1.5, 2.0, t) * (1.0 - smoothstep(3.3, 3.7, t)))
	_once("aboard", 3.3, func() -> void:
		p.visible = false
		p.scale = Vector3.ONE
		Audio.play("clunk", 0.9, -4.0)
		Audio.play("hydraulic", 1.4, -8.0))
	# Countdown: holo numbers, siren, beacons, steam; the cells drain into the rocket.
	if t >= _t0 and t < _ig:
		var n: int = _cd - int(floor(t - _t0))
		_once("cd%d" % n, _t0 + (_cd - n), func() -> void:
			_show_count(str(n))
			Audio.play("beep", 1.0 + 0.12 * (_cd - n), -2.0)
			Input.start_joy_vibration(0, 0.1, 0.0, 0.1))
		if t >= _siren_next:
			_siren_next = t + 1.6
			Audio.play("siren", 1.0, -6.0, 0.0)
	_once("alarm", _t0, func() -> void:
		if pad:
			pad.set_alarm(true)
			pad.vent_steam(true)
		Audio.play("steam", 0.8, -4.0))
	var cd_k: float = clampf((t - _t0) / maxf(_ig - _t0, 0.1), 0.0, 1.0)
	var hose_t: float = _ig - (3.0 if _cd >= 3 else 1.6)
	var arm_t: float = _ig - (2.2 if _cd >= 3 else 1.4)
	if t < _ig:
		model.set_charge(cd_k * cd_k)
	if pad:
		pad.set_fuel(cd_k)
		pad.set_hoses(smoothstep(hose_t, hose_t + 0.6, t))
		pad.set_gangway(smoothstep(arm_t, arm_t + 1.0, t))
	_once("hoses", hose_t, func() -> void:
		Audio.play("hydraulic", 0.8, -2.0)
		Audio.play("steam", 0.6, -2.0))
	_once("gangway", arm_t, func() -> void:
		Audio.play("servo", 0.5, -2.0)
		Audio.play("groan", 1.4, -10.0))
	_once("charge", _ig - 2.1, func() -> void: Audio.play("charge", 1.0, -2.0, 0.0))
	# Ignition.
	_once("ignite", _ig, func() -> void:
		_show_count(tr("IGNITION"))
		model.set_charge(0.0)
		if pad:
			pad.vent_steam(false)
			pad.billow(true)
		elif _dust:
			_dust.emitting = true
		_shake = 0.85
		_flash(Color(0.8, 0.95, 1.0), 0.35)
		Audio.play("crunch", 0.45, 0.0)
		Audio.play("thud", 0.4, 0.0)
		Audio.play("whoosh", 0.4, -2.0)
		_roar_next = _ig
		Input.start_joy_vibration(0, 0.6, 1.0, 2.5)
		EventBus.shake_requested.emit(0.6))
	if t >= _ig:
		var pw: float = smoothstep(_ig, _ig + 0.5, t) * 0.75 + smoothstep(_lo - 0.2, _lo + 0.6, t) * 0.35
		model.plume.power = pw
		model.plume.light.light_energy = (9.0 + 30.0 * (1.0 - smoothstep(_ig, _ig + 0.6, t))) * pw
		if t >= _roar_next and t < _end - 1.0:
			_roar_next = t + 1.15
			Audio.play("roar", randf_range(0.85, 0.95), clampf(2.0 - (model.position.y - _base_y) * 0.05, -16.0, 2.0), 0.02)
		_shake = maxf(_shake, 0.35 * (1.0 - smoothstep(_lo + 2.0, _lo + 6.0, t)))
	if pad:
		pad.set_clamps(smoothstep(_ig + 0.5, _ig + 1.0, t))
	# The landing legs fold flush into the hull once clear of the pad.
	model.set_legs(1.0 - smoothstep(_lo + 1.0, _lo + 2.2, t))
	_once("legs_up", _lo + 1.0, func() -> void: Audio.play("servo", 0.8, -6.0))
	_once("clamps", _ig + 0.55, func() -> void:
		Audio.play("clunk", 0.7, -2.0)
		Audio.play("hydraulic", 0.6, -6.0))
	_once("count_off", _lo + 1.8, func() -> void: _count.visible = false)
	# Lift-off, climb and the arc over.
	if t >= _lo:
		var tau: float = t - _lo
		var h2: float = 1.0 * tau * tau + 0.12 * tau * tau * tau
		var s: float = 0.01 * pow(tau, 4.0)
		if _warp and tau > 1.6:
			h2 += 400.0 * pow(tau - 1.6, 2.0)
		model.position = Vector3(0, _base_y + h2, 0) + ARC_DIR.normalized() * s
		var tilt: float = atan2(0.04 * tau * tau * tau, 2.0 * tau + 0.36 * tau * tau + 0.001)
		model.basis = Basis(Vector3.UP.cross(ARC_DIR).normalized(), tilt).scaled(Vector3.ONE * tier_scale(tier))
		_trail.emitting = true
		_dot.visible = tau > 2.5
		(_dot.material_override as StandardMaterial3D).albedo_color.a = smoothstep(2.5, 6.0, tau)
	_once("liftoff", _lo, func() -> void:
		_count.position = Vector3(-2.6, _base_y + 9.0, 2.0)
		_show_count(tr("WARP") if _warp else tr("LIFT OFF"))
		Audio.play("whoosh", 0.35, 0.0)
		Audio.music_sting("level_up"))
	_once("billow_off", _lo + 3.0, func() -> void:
		if pad:
			pad.billow(false)
			pad.set_alarm(false)
		if _dust:
			_dust.emitting = false)
	if _warp:
		_once("warp", _lo + 1.6, func() -> void:
			Audio.play("charge", 2.0, 0.0, 0.0)
			Audio.play("sparkle", 0.6, 0.0)
			_flash(Color(0.75, 0.95, 1.0), 0.9))
	_launch_camera(t, dt)
	if t >= _end:
		_start_flight()


func _launch_camera(t: float, dt: float) -> void:
	var o: Vector3 = global_position
	var mp: Vector3 = model.global_position
	var pos: Vector3
	var look: Vector3
	var fov: float = 60.0
	if t < 1.7:
		# Establishing: wide, slow push in from the front three-quarter.
		pos = o + Vector3(13.0, 3.2, 17.0).lerp(Vector3(11.0, 3.4, 14.0), t / 1.7)
		look = o + Vector3(0, 5.5, -1.0)
		fov = 55.0
	elif t < _t0:
		# Boarding: from the tower's side, watching Aurora ride up and cross the gangway.
		pos = o + Vector3(-8.5, 4.2, -2.0).lerp(Vector3(-7.6, 6.0, -3.0), (t - 1.7) / (_t0 - 1.7))
		look = (world.patch.global_position if world.patch.visible else _hatch_world()) + Vector3(0, 0.3, 0)
		fov = 52.0
	elif t < _ig - 0.7:
		# Countdown: low front-left, rocket, beacons and the holo numbers.
		pos = o + Vector3(6.2, 1.3, 3.7).lerp(Vector3(5.4, 1.6, 3.5), (t - _t0) / maxf(_ig - 0.7 - _t0, 0.1))
		look = o + Vector3(-0.6, 5.0, 0)
		fov = 58.0
	elif t < _lo + 0.9:
		# Ignition: close and low by the engine, the plume and the billows.
		pos = o + Vector3(5.0, 3.8, 12.5).lerp(Vector3(5.4, 3.4, 11.0), (t - (_ig - 0.7)) / (_lo + 1.6 - _ig))
		look = o + Vector3(0, 2.6, 0)
		fov = 58.0
	elif t < _lo + 4.5:
		# Lift-off: low, looking up as it climbs.
		pos = o + Vector3(8.5, 1.0, 3.8)
		look = mp + Vector3(0, 3.0, 0)
	else:
		# Climb: wide from the base, the vapour column and the arc to a dot.
		# Low enough that the skyline stays in frame under the rising column.
		pos = o + Vector3(-12.0, 2.5, 30.0)
		look = (mp + Vector3(0, 2.0, 0)).lerp(o + Vector3(0, 6.0, 0), 0.28)
		fov = lerpf(58.0, 46.0, smoothstep(_lo + 4.5, _end, t))
	_cam.fov = fov
	_place_cam(pos, look, dt)


func _place_cam(pos: Vector3, look: Vector3, dt: float) -> void:
	_shake = maxf(0.0, _shake - dt * 0.5)
	_shake_t += dt * 38.0
	var s: float = _shake * _shake * (0.0 if Settings.reduced_motion else Settings.shake_intensity)
	var jitter := Vector3(sin(_shake_t * 1.3), sin(_shake_t * 1.7 + 2.0), sin(_shake_t * 1.1 + 4.0)) * 0.35 * s
	if pos.distance_to(look) < 0.1:
		return
	_cam.look_at_from_position(pos + jitter, look + jitter * 0.5, Vector3.UP)


func _start_flight() -> void:
	_mode = "flight"
	_t = 0.0
	_count.visible = false
	_trail.emitting = false
	model.plume.power = 0.0
	for b: ColorRect in _bars:
		b.visible = false
	world.globe.fly(world.hub_index, _to_hub, _flight_s)


func _travel() -> void:
	if _mode == "":
		return
	_mode = ""
	Input.stop_joy_vibration(0)
	print("[rocket] travel to hub %d" % _to_hub)
	world.travel_to(_to_hub)


# --- Arrival ---------------------------------------------------------------------------

## The rocket comes down on its plume and lands; Aurora flies out of the hatch.
func arrive() -> void:
	if _mode != "":
		return
	_speed = [1.0, 1.0, 1.2, 1.4, 1.8][tier]
	_begin("arrive")
	world.music.set_cinematic(true)
	var p: Patch = world.patch
	p.set_physics_process(false)
	p.velocity = Vector3.ZERO
	p.visible = false
	model.plume.power = 1.0
	_trail.emitting = true
	_dot.visible = true
	_land_to = global_position + Vector3(2.4, 0.05, 4.9)
	if pad:
		pad.set_gangway(1.0)
		pad.set_hoses(1.0)
		pad.set_clamps(1.0)
		pad.set_alarm(true)
	_arrive_step(0.0)
	Audio.play("whoosh", 0.4, -2.0)


func _arrive_step(dt: float) -> void:
	var t: float = _t
	var k: float = clampf(t / LAND_S, 0.0, 1.0)
	var e: float = 1.0 - pow(1.0 - k, 3.0)  # fast in, gentle touchdown
	var top: Vector3 = Vector3(0, _base_y + 70.0, 0) - ARC_DIR.normalized() * 25.0
	model.position = top.lerp(Vector3(0, _base_y, 0), e)
	var tilt: float = (1.0 - smoothstep(0.0, 0.7, k)) * 0.4
	model.basis = Basis(Vector3.UP.cross(-ARC_DIR).normalized(), tilt).scaled(Vector3.ONE * tier_scale(tier))
	(_dot.material_override as StandardMaterial3D).albedo_color.a = 1.0 - smoothstep(0.1, 0.4, k)
	_dot.visible = k < 0.4
	var h: float = model.position.y - _base_y
	if t < LAND_S:
		model.plume.power = 0.7 + 0.3 * smoothstep(12.0, 2.0, h)
		if t >= _roar_next:
			_roar_next = t + 1.15
			Audio.play("roar", randf_range(0.85, 0.95), clampf(2.0 - h * 0.06, -16.0, 2.0), 0.02)
		_shake = maxf(_shake, 0.4 * smoothstep(15.0, 0.0, h))
	else:
		model.plume.power = maxf(0.0, 1.0 - (t - LAND_S) / 0.6) * 0.6
	_once("ground_fx", LAND_S - 1.6, func() -> void:
		if pad:
			pad.billow(true)
		elif _dust:
			_dust.emitting = true)
	_once("touchdown", LAND_S, func() -> void:
		Audio.play("thud", 0.5, 0.0)
		Audio.play("clunk", 0.6, -2.0)
		Audio.play("steam", 0.7, -2.0)
		_shake = 0.7
		EventBus.shake_requested.emit(0.4)
		_trail.emitting = false
		if pad:
			Audio.play("hydraulic", 0.7, -6.0))
	_once("settle", LAND_S + 1.4, func() -> void:
		if pad:
			pad.billow(false)
			pad.set_alarm(false)
		if _dust:
			_dust.emitting = false)
	model.set_legs(smoothstep(LAND_S - 2.2, LAND_S - 0.8, t))
	_once("legs_down", LAND_S - 2.2, func() -> void: Audio.play("servo", 0.7, -4.0))
	if pad:
		pad.set_clamps(1.0 - smoothstep(LAND_S, LAND_S + 0.6, t))
		pad.set_gangway(1.0 - smoothstep(LAND_S + 0.8, LAND_S + 1.8, t))
	# Hatch opens, Aurora flies out and down to the ground beside the pad.
	var exit_t: float = LAND_S + 1.9
	_set_hatch(smoothstep(exit_t - 0.5, exit_t, t))
	_once("hatch", exit_t - 0.5, func() -> void: Audio.play("hydraulic", 1.3, -6.0))
	var p: Patch = world.patch
	if t >= exit_t:
		var u: float = smoothstep(exit_t, exit_t + 2.2, t)
		var a: Vector3 = _hatch_world()
		var c: Vector3 = global_position + Vector3(4.6, a.y - global_position.y + 0.6, -2.0)
		var pos: Vector3 = a.lerp(c, u).lerp(c.lerp(_land_to, u), u)
		var fwd: Vector3 = c.lerp(_land_to, u) - a.lerp(c, u)
		p.visible = true
		p.scale = Vector3.ONE * (0.3 + 0.7 * smoothstep(exit_t, exit_t + 0.35, t))
		p.global_position = pos
		if Vector2(fwd.x, fwd.z).length() > 0.01:
			p.rotation.y = atan2(fwd.x, fwd.z) + PI
	_once("aurora_out", exit_t, func() -> void:
		Audio.play("beep", 1.3, -2.0)
		Audio.play("whoosh", 1.4, -8.0))
	_arrive_camera(t, dt)
	if t >= exit_t + 2.6:
		Audio.play("fanfare", 1.0, -6.0)
		_finish_arrival()


func _arrive_camera(t: float, dt: float) -> void:
	var o: Vector3 = global_position
	var mp: Vector3 = model.global_position
	if t < LAND_S * 0.62:
		_cam.fov = 50.0
		_place_cam(o + Vector3(-11.0, 2.0, -4.0), mp + Vector3(0, 3.0, 0), dt)
	elif t < LAND_S + 1.6:
		_cam.fov = 58.0
		_place_cam(o + Vector3(7.5, 2.0, 9.5), mp + Vector3(0, 3.0, 0), dt)
	else:
		_cam.fov = 55.0
		_place_cam(o + Vector3(7.0, 3.0, 3.6), o + Vector3(2.0, 2.4, 0.5), dt)


func _finish_arrival() -> void:
	if _mode != "arrive":
		return
	_mode = ""
	model.position = Vector3(0, _base_y, 0)
	model.basis = Basis().scaled(Vector3.ONE * tier_scale(tier))
	model.plume.power = 0.0
	model.set_legs(1.0)
	_set_hatch(0.0)
	_trail.emitting = false
	_dot.visible = false
	if pad:
		pad.set_gangway(0.0)
		pad.set_clamps(0.0)
		pad.set_hoses(0.0)
		pad.billow(false)
		pad.set_alarm(false)
	if _dust:
		_dust.emitting = false
	var p: Patch = world.patch
	p.visible = true
	p.scale = Vector3.ONE
	p.global_position = _land_to
	p.set_physics_process(true)
	_end_cinematic()
	world.music.set_cinematic(false)
	print("[rocket] landed (pad=%s), control restored" % (pad != null))
	landed.emit()


# --- Shared ----------------------------------------------------------------------------

func _begin(mode: String) -> void:
	_mode = mode
	_t = 0.0
	_fired.clear()
	_roar_next = 0.0
	_siren_next = 0.0
	_shake = 0.0
	get_tree().paused = false
	world.launching = true
	world.hud.visible = false
	world.cam.input_enabled = false
	if world.patch.input is PlayerInput:
		(world.patch.input as PlayerInput).enabled = false
	if _cam == null:
		_cam = Camera3D.new()
		_cam.top_level = true
		_cam.far = 900.0
		add_child(_cam)
	_cam.current = true
	_cam.environment = _cinematic_env()
	# The yard's festoon bulbs and bunting hang across most camera angles: hide them meanwhile.
	_hidden.clear()
	for nm: String in ["Bulbs", "Bunting"]:
		for n: Node in world.find_children(nm, "MultiMeshInstance3D", true, false):
			if (n as Node3D).visible:
				(n as Node3D).visible = false
				_hidden.append(n)
	_build_fx()
	_build_ui()


## The world's environment with the dusty haze pulled back and a touch more contrast, so the
## rocket pops against a clear sky in the cinematic shots.
func _cinematic_env() -> Environment:
	var src: Environment = world.get("_env") as Environment
	if src == null:
		return null
	var e: Environment = src.duplicate() as Environment
	e.fog_density *= 0.3
	e.fog_sky_affect = 0.1
	e.volumetric_fog_density *= 0.25
	e.volumetric_fog_sky_affect = 0.1
	e.adjustment_enabled = true
	e.adjustment_contrast = maxf(e.adjustment_contrast, 1.0) * 1.08
	e.adjustment_saturation = maxf(e.adjustment_saturation, 1.0) * 1.06
	return e


func _end_cinematic() -> void:
	world.launching = false
	for n: Node in _hidden:
		if is_instance_valid(n):
			(n as Node3D).visible = true
	_hidden.clear()
	world.hud.visible = true
	world.cam.target = world.patch
	world.cam.yaw = world.patch.rotation.y
	world.cam.snap()
	world.cam.camera.current = true
	world.cam.input_enabled = true
	if world.patch.input is PlayerInput:
		(world.patch.input as PlayerInput).enabled = true
	if _ui:
		_ui.queue_free()
		_ui = null
		_bars.clear()
		_fade = null
		_hint = null
	if _count:
		_count.visible = false
	Input.stop_joy_vibration(0)


func _process(delta: float) -> void:
	if _mode == "":
		return
	var dt: float = delta * _speed
	if DevHooks.has("rocket-shots"):
		dt = _shot_hold(dt)
	_step(dt)
	if _hint:
		_hint.modulate.a = clampf(_t - 0.6, 0.0, 0.7)
	if _fade and _fade.color.a > 0.0:
		_fade.color.a = maxf(0.0, _fade.color.a - delta * 1.4)


func _step(dt: float) -> void:
	_t += dt
	match _mode:
		"launch":
			_launch_step(dt)
		"flight":
			if _t >= _flight_s + 0.4:
				_travel()
		"arrive":
			_arrive_step(dt)
			if _t > 40.0:  # watchdog: never leave the player locked out
				_finish_arrival()


## Screenshots (slow software rendering): --rocket-shots=T1,T2,... fast-forwards the sequence to
## 2 s before each time, plays up to it, holds there (plume and particles keep going) for
## --rocket-shot-wait wall seconds, saves screenshots/<--rocket-shot-name>_<i>.png, then quits.
func _shot_hold(dt: float) -> float:
	var times: PackedStringArray = DevHooks.get_s("rocket-shots", "").split(",")
	var i: int = int(_fired.get("shot_i", 0))
	if i >= times.size():
		return dt
	var target: float = float(times[i])
	while _t < target - 2.0 and _mode != "" and _mode != "flight":
		_step(0.05)
	if _t + dt < target:
		return dt
	var now: float = Time.get_ticks_msec() / 1000.0
	if not _fired.has("shot_wall"):
		_fired["shot_wall"] = now
	elif now - float(_fired["shot_wall"]) >= DevHooks.get_f("rocket-shot-wait", 20.0):
		DevHooks.save_viewport("screenshots/%s_%d.png" % [DevHooks.get_s("rocket-shot-name", "rocket"), i])
		_fired["shot_i"] = i + 1
		_fired.erase("shot_wall")
		if i + 1 >= times.size():
			get_tree().quit()
	return maxf(0.0, target - _t)


func _input(event: InputEvent) -> void:
	if _mode == "" or not event.is_pressed() or event.is_echo():
		return
	var skip: bool = event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")
	if event is InputEventKey:
		var kc: Key = (event as InputEventKey).keycode
		skip = skip or kc == KEY_SPACE or kc == KEY_ESCAPE
	elif event is InputEventJoypadButton:
		var bi: JoyButton = (event as InputEventJoypadButton).button_index
		skip = skip or bi == JOY_BUTTON_B or bi == JOY_BUTTON_START
	if not skip:
		return
	get_viewport().set_input_as_handled()
	skip_sequence()


func skip_sequence() -> void:
	match _mode:
		"launch", "flight":
			_travel()
		"arrive":
			_finish_arrival()


func _once(key: String, at: float, f: Callable) -> void:
	if _t >= at and not _fired.has(key):
		_fired[key] = true
		f.call()


func _show_count(text: String) -> void:
	_count.text = text
	_count.visible = true
	var s: float = 1.0 if text.length() <= 2 else 0.45
	_count.scale = Vector3.ONE * 1.4 * s
	create_tween().tween_property(_count, "scale", Vector3.ONE * s, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _flash(c: Color, a: float) -> void:
	if _fade:
		_fade.color = Color(c.r, c.g, c.b, a)


func _soft_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.45, Color(1, 1, 1, 0.55))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var soft := GradientTexture2D.new()
	soft.gradient = g
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	return soft


func _build_fx() -> void:
	if _trail:
		return
	var soft: GradientTexture2D = _soft_tex()
	# Vapour trail: stays in the world as the rocket climbs (a column, then a curving ribbon).
	_trail = CPUParticles3D.new()
	_trail.emitting = false
	_trail.amount = 70
	_trail.lifetime = 7.0
	_trail.local_coords = false
	_trail.direction = Vector3(0, -1, 0)
	_trail.spread = 12.0
	_trail.initial_velocity_min = 2.0
	_trail.initial_velocity_max = 4.0
	_trail.damping_min = 1.0
	_trail.damping_max = 2.0
	_trail.gravity = Vector3(0.25, 0.2, 0)
	_trail.scale_amount_curve = LaunchPad._grow_curve(0.5, 1.5, 2.6)
	_trail.color_ramp = LaunchPad._fade_ramp(0.8)
	var q := QuadMesh.new()
	q.size = Vector2(2.6, 2.6)
	q.material = LaunchPad.vapour_material()
	_trail.mesh = q
	_trail.position = Vector3(0, RocketModel.NOZZLE_Y - 3.5, 0)  # below the hot core
	model.add_child(_trail)
	# Ground dust ring when there is no pad (parked landings and take-offs).
	if pad == null:
		_dust = _trail.duplicate() as CPUParticles3D
		_dust.direction = Vector3(1, 0.1, 0)
		_dust.spread = 180.0
		_dust.flatness = 0.92
		_dust.initial_velocity_min = 6.0
		_dust.initial_velocity_max = 11.0
		_dust.damping_min = 2.5
		_dust.damping_max = 3.5
		_dust.lifetime = 4.0
		_dust.amount = 22
		_dust.gravity = Vector3(0, 0.15, 0)
		_dust.position = Vector3(0, 0.4, 0)
		add_child(_dust)
	# Bright dot: a fixed-size flare that keeps the rocket visible once it is far away.
	_dot = MeshInstance3D.new()
	var dq := QuadMesh.new()
	dq.size = Vector2(0.06, 0.06)
	_dot.mesh = dq
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.fixed_size = true
	dm.albedo_texture = soft
	dm.albedo_color = Color(0.8, 0.97, 1.0, 0.0)
	_dot.material_override = dm
	_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dot.position = Vector3(0, RocketModel.NOZZLE_Y - 0.6, 0)
	_dot.visible = false
	model.add_child(_dot)
	# Holographic countdown beside the rocket.
	_count = Label3D.new()
	_count.font_size = 200
	_count.pixel_size = 0.011
	_count.modulate = Color(0.2, 1.2, 2.4)
	_count.outline_size = 24
	_count.outline_modulate = Color(0.0, 0.25, 0.45, 0.6)
	_count.shaded = false
	_count.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_count.position = Vector3(-3.4, _base_y + 5.6, 1.6)
	_count.visible = false
	add_child(_count)


func _build_ui() -> void:
	if _ui:
		return
	_ui = CanvasLayer.new()
	_ui.layer = 40
	add_child(_ui)
	for top: bool in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 1)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 0.9
		bar.anchor_bottom = 0.1 if top else 1.0
		_ui.add_child(bar)
		_bars.append(bar)
	_fade = ColorRect.new()
	_fade.color = Color(1, 1, 1, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_fade)
	_hint = Label.new()
	_hint.text = tr("Space / Esc  skip")
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	_hint.anchor_left = 1.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 0.93
	_hint.anchor_bottom = 0.93
	_hint.offset_left = -190.0
	_hint.offset_right = -24.0
	_hint.modulate.a = 0.0
	_ui.add_child(_hint)
