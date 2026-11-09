class_name Rocket
extends Node3D
## Lumi's travel ship (ShipModel; the class keeps its old name) and its landing site. Stands on the
## LaunchPad (level 5 base) or, after landing in a district without one, parked on the ground.
## Runs the two cinematics ([ship] VTOL instead of the old vertical rocket):
##   launch(to_hub): establishing shot, the canopy opens, Lumi rides the boarding lift and drops into
##     the cockpit, a countdown of beeps with siren, beacons and steam, the umbilical drops and the
##     light bridge retracts, the lift fans spool up, IGNITION: the fans blast the deck (downwash,
##     flash, shake), the docking locks release, LIFT OFF: a vertical rise to a hover, the gear
##     folds, the main engines light and the ship pitches up and flies away to a bright dot; then
##     the globe flight and the destination district loads.
##   arrive(): the ship flies in nose first, flares, hovers over the pad, lowers its gear, sets down
##     on the fans, the canopy opens and Lumi flies out.
## Both are skippable (Space / Esc / B) and always hand control back (or travel) at the end.
## Higher rocket tiers (RocketTiers) run the sequence faster and the Mk IV warps out; the look
## (ShipTiers, Mk I-VII) decides the ship's parts and size.

## Landing site, behind the yard (a landmark from the default camera; the pad floats over the lot).
const PAD_POS := Vector3(-2.0, 0, -13.0)
const ARC_DIR := Vector3(0.8, 0, -0.6)
## [ship] The ship parks nose-out along the take-off heading.
const PARK_YAW: float = 2.2143
const LAND_S: float = 7.0
## Hover height (unscaled) after the vertical lift-off / before touchdown.
const HOVER: float = 4.5

## The arrival cinematic finished (or was skipped) and the player has control again.
signal landed

var world: Node
var pad: LaunchPad
var model: ShipModel
var tier: int = 1
## [ship] The ship's look (ShipTiers, 1..7).
var look: int = 1
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
var _clutter: Array[Node3D] = []  # [vqa] yard dressing hidden during the close launch shots
# Timeline marks (seconds of sequence time), set per tier in launch().
var _t0: float = 3.8     # countdown starts
var _ig: float = 8.8     # ignition (lift fans to full)
var _lo: float = 10.2    # lift-off
var _end: float = 19.7   # hand over to the globe flight
var _cd: int = 5
var _warp: bool = false


static func tier_scale(t: int) -> float:
	return ShipTiers.scale_of(t)


func is_flying() -> bool:
	return _mode != ""


## Builds the ship (and the pad unless `with_pad` is false: parked on the ground).
func setup(with_pad: bool) -> void:
	tier = RocketTiers.tier()
	look = ShipTiers.look()
	process_mode = Node.PROCESS_MODE_ALWAYS
	if with_pad:
		pad = LaunchPad.new()
		pad.rocket_tier = tier
		pad.look = look
		pad.ship_yaw = PARK_YAW
		add_child(pad)
		_base_y = LaunchPad.TOP_Y
	model = ShipModel.new()
	add_child(model)
	model.build(look)
	_park_pose()
	_build_colliders()


func _ship_scale() -> float:
	return ShipTiers.scale_of(look)


## Nose along the take-off heading, gear down on the deck.
func _park_pose() -> void:
	model.position = Vector3(0, _base_y, 0)
	model.basis = Basis(Vector3.UP, PARK_YAW).scaled(Vector3.ONE * _ship_scale())


## Ship-frame direction (nose = +Z) in this node's frame.
func _dir(v: Vector3) -> Vector3:
	return Basis(Vector3.UP, PARK_YAW) * v


## Camera distance factor: big ships get wider shots.
func _cs() -> float:
	var e: Vector2 = ShipModel.extent(look)
	return maxf(1.0, maxf(e.x, e.y * 1.6) * _ship_scale() / 7.4)


func _build_colliders() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var sc: float = _ship_scale()
	var e: Vector2 = ShipModel.extent(look)
	if pad:
		var deck := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = pad.radius()
		cyl.height = _base_y
		deck.shape = cyl
		deck.position = Vector3(0, _base_y * 0.5, 0)
		body.add_child(deck)
		var mast := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(1.4, 3.0, 4.4)
		mast.shape = bx
		mast.basis = Basis(Vector3.UP, PARK_YAW)
		mast.position = _dir(Vector3(pad.radius() + 1.1, 1.5, -0.6))
		body.add_child(mast)
	# The hull (a box along the nose) and the wings (a thin slab), turned with the ship.
	var hull := CollisionShape3D.new()
	var hb := BoxShape3D.new()
	hb.size = Vector3(1.8, 1.0, e.x) * sc
	hull.shape = hb
	hull.basis = Basis(Vector3.UP, PARK_YAW)
	hull.position = Vector3(0, _base_y + 1.1 * sc, 0) + _dir(Vector3(0, 0, (e.x * 0.5 - 3.4) * sc))
	body.add_child(hull)
	var wing := CollisionShape3D.new()
	var wb := BoxShape3D.new()
	wb.size = Vector3(e.y * 2.0, 0.25, 3.0) * sc
	wing.shape = wb
	wing.basis = Basis(Vector3.UP, PARK_YAW)
	wing.position = Vector3(0, _base_y + 1.05 * sc, 0) + _dir(Vector3(0, 0, -1.4 * sc))
	body.add_child(wing)


# --- Launch ----------------------------------------------------------------------------

func launch(to_hub: int) -> void:
	if _mode != "":
		return
	_to_hub = to_hub
	var d: Dictionary = RocketTiers.def(tier)
	_cd = int(d.get("countdown_s", 5))
	_warp = bool(d.get("warp", false))
	_flight_s = float(d.get("flight_s", 5.0))
	_speed = [1.0, 1.0, 1.2, 1.4, 1.8][clampi(tier, 0, 4)]
	_t0 = 3.8
	_ig = _t0 + _cd
	_lo = _ig + 1.4
	_end = _lo + (4.2 if _warp else 9.5)
	RocketTiers.mark_launched()
	print("[rocket] launch to hub %d (Mk %d, look %d, pad=%s)" % [to_hub, tier, look, pad != null])
	GameState.world.erase("rocket_parked")
	_begin("launch")
	world.music.set_cinematic(true)
	# Lumi steps onto the boarding lift (or hovers up beside the cockpit when there is no pad).
	var p: Patch = world.patch
	p.set_physics_process(false)
	p.velocity = Vector3.ZERO
	p.visible = true
	p.global_position = _board_start()
	p.rotation.y = PARK_YAW - PI * 0.5  # [ship] facing the ship from the starboard lift


func _board_start() -> Vector3:
	if pad:
		return pad.lift_point() + Vector3(0, 0.08, 0)
	return global_position + _dir(Vector3(-1.9, 0, ShipModel.seat(look).z) * _ship_scale()) + Vector3(0, 0.05, 0)


## The cockpit seat in world space (where Lumi drops in / pops out).
func _hatch_world() -> Vector3:
	return model.to_global(ShipModel.seat(look))


func _set_hatch(open_k: float) -> void:
	model.set_canopy(open_k)


## Ship pose in flight: position (this node's frame), pitch (nose up > 0) and roll.
func _pose(pos: Vector3, pitch: float, roll: float) -> void:
	model.position = pos
	model.basis = (Basis(Vector3.UP, PARK_YAW) * Basis(Vector3.RIGHT, -pitch) * Basis(Vector3.BACK, roll)).scaled(Vector3.ONE * _ship_scale())


func _launch_step(dt: float) -> void:
	var t: float = _t
	var p: Patch = world.patch
	var sc: float = _ship_scale()
	# Boarding: the canopy opens, the lift rises to the sill, Lumi floats over and drops in.
	var seat_p: Vector3 = _hatch_world()
	var start: Vector3 = _board_start() if not _fired.has("start_pos") else _fired["start_pos"]
	_fired["start_pos"] = start
	if t < 3.3:
		var up_top := Vector3(start.x, seat_p.y + 0.35, start.z)
		if pad:
			pad.lift.global_position = start - Vector3(0, 0.08, 0) + Vector3(0, (seat_p.y - 0.3 - start.y) * smoothstep(0.3, 1.9, t), 0)
		var over: Vector3 = seat_p + Vector3(0, 0.5, 0)
		var pos: Vector3 = start.lerp(up_top, smoothstep(0.3, 1.9, t)) if t < 1.9 else up_top.lerp(over, smoothstep(1.9, 2.7, t)).lerp(seat_p, smoothstep(2.6, 3.15, t))
		p.global_position = pos + Vector3(0, sin(t * 5.0) * 0.03, 0)
		p.scale = Vector3.ONE * (1.0 - smoothstep(2.6, 3.2, t) * 0.65)
	if pad:
		pad.set_gangway(1.0 - smoothstep(1.2, 1.9, t))
	_once("lift", 0.3, func() -> void:
		Audio.play("servo", 0.7, -6.0)
		Audio.play("hydraulic", 1.1, -10.0))
	_once("canopy", 0.9, func() -> void: Audio.play("hydraulic", 1.4, -6.0))
	_once("glide", 1.9, func() -> void:
		Audio.play("whoosh", 1.3, -8.0)
		Audio.play("beep", 1.2, -6.0))
	_set_hatch(smoothstep(0.9, 1.6, t) * (1.0 - smoothstep(3.3, 3.9, t)))
	_once("aboard", 3.25, func() -> void:
		p.visible = false
		p.scale = Vector3.ONE
		Audio.play("clunk", 0.9, -4.0))
	_once("canopy_shut", 3.85, func() -> void: Audio.play("clunk", 1.2, -6.0))
	# Countdown: beeps, siren, beacons, steam; the cells drain into the ship. [ship2] No 3D text:
	# the visuals and sounds carry it (owner: no text over 3D).
	if t >= _t0 and t < _ig:
		var n: int = _cd - int(floor(t - _t0))
		_once("cd%d" % n, _t0 + (_cd - n), func() -> void:
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
		model.set_lift(0.12 * smoothstep(_ig - 2.0, _ig, t))  # fans spooling up
	if pad:
		pad.set_fuel(cd_k)
		pad.set_hoses(smoothstep(hose_t, hose_t + 0.6, t))
		if t >= 3.3:
			pad.set_gangway(maxf(smoothstep(3.3, 3.8, t), smoothstep(arm_t, arm_t + 1.0, t)))
	_once("hoses", hose_t, func() -> void:
		Audio.play("hydraulic", 0.8, -2.0)
		Audio.play("steam", 0.6, -2.0))
	_once("gangway", arm_t, func() -> void: Audio.play("servo", 0.5, -2.0))
	_once("charge", _ig - 2.1, func() -> void: Audio.play("charge", 1.0, -2.0, 0.0))
	# Ignition: the lift fans go to full and blast the deck.
	_once("ignite", _ig, func() -> void:
		model.set_charge(0.0)
		if pad:
			pad.vent_steam(false)
			pad.billow(true)
		elif _dust:
			_dust.emitting = true
		_shake = 0.6
		_flash(Color(0.8, 0.95, 1.0), 0.25)
		Audio.play("thud", 0.5, 0.0)
		Audio.play("whoosh", 0.5, -2.0)
		_roar_next = _ig
		Input.start_joy_vibration(0, 0.5, 0.8, 2.0)
		EventBus.shake_requested.emit(0.45))
	var tau: float = t - _lo
	# Lift fans: full from ignition, easing off as the main engines take over after the hover.
	if t >= _ig:
		var fans: float = smoothstep(_ig, _ig + 0.5, t) * (1.0 - 0.75 * smoothstep(_lo + 2.4, _lo + 4.0, t))
		model.set_lift(fans)
		var main: float = smoothstep(_lo + 2.0, _lo + 2.8, t) * 1.05
		model.plume.power = main
		model.plume.light.light_energy = 8.0 * main
		if t >= _roar_next and t < _end - 1.0:
			_roar_next = t + 1.15
			Audio.play("roar", randf_range(1.05, 1.15), clampf(1.0 - maxf(0.0, model.position.y - _base_y) * 0.05 - maxf(0.0, tau - 3.0) * 1.5, -18.0, 1.0), 0.02)
		_shake = maxf(_shake, 0.3 * (1.0 - smoothstep(_lo + 1.0, _lo + 4.0, t)))
	if pad:
		pad.set_clamps(smoothstep(_ig + 0.5, _ig + 1.0, t))
	# The gear folds once clear of the deck.
	model.set_legs(1.0 - smoothstep(_lo + 1.0, _lo + 2.0, t))
	_once("legs_up", _lo + 1.0, func() -> void: Audio.play("servo", 0.8, -6.0))
	_once("clamps", _ig + 0.55, func() -> void:
		Audio.play("clunk", 0.7, -2.0)
		Audio.play("hydraulic", 0.6, -6.0))
	# Lift-off: a vertical rise to a hover, then nose up and away along the heading.
	if t >= _lo:
		var h1: float = HOVER * sc * smoothstep(0.0, 2.6, tau)
		var u: float = maxf(0.0, tau - 2.4)
		var s: float = 0.9 * u * u + 0.45 * u * u * u
		var h2: float = 0.3 * u * u + 0.12 * u * u * u
		if _warp and u > 0.4:
			s += 900.0 * pow(u - 0.4, 2.0)
		var wob: float = (1.0 - smoothstep(2.0, 3.0, tau)) * smoothstep(0.0, 0.6, tau)
		var pos := Vector3(0, _base_y + h1 + h2 + sin(tau * 3.1) * 0.06 * wob, 0) + _dir(Vector3(0, 0, s))
		var pitch: float = clampf(u * 0.16, 0.0, 0.22) - (1.0 - smoothstep(0.0, 1.0, u)) * smoothstep(1.6, 2.4, tau) * 0.06
		_pose(pos, pitch, sin(tau * 2.3) * 0.03 * wob)
		_trail.emitting = u > 0.2
		_dot.visible = u > 2.0
		(_dot.material_override as StandardMaterial3D).albedo_color.a = smoothstep(2.0, 5.0, u)
	_once("liftoff", _lo, func() -> void:
		Subtitles.post(tr("LIFT OFF").capitalize(), "info")  # [ship2] once, on the message line
		Audio.play("whoosh", 0.35, 0.0)
		Audio.music_sting("level_up"))
	_once("mains", _lo + 2.1, func() -> void:
		Audio.play("whoosh", 0.6, -2.0)
		Audio.play("crunch", 0.5, -6.0)
		_shake = maxf(_shake, 0.45)
		Input.start_joy_vibration(0, 0.4, 0.9, 1.5))
	_once("billow_off", _lo + 3.0, func() -> void:
		if pad:
			pad.billow(false)
			pad.set_alarm(false)
		if _dust:
			_dust.emitting = false)
	if _warp:
		_once("warp", _lo + 2.8, func() -> void:
			Audio.play("charge", 2.0, 0.0, 0.0)
			Audio.play("sparkle", 0.6, 0.0)
			_flash(Color(0.75, 0.95, 1.0), 0.9))
	_launch_camera(t, dt)
	if t >= _end:
		_start_flight()


func _launch_camera(t: float, dt: float) -> void:
	var o: Vector3 = global_position
	var mp: Vector3 = model.global_position
	var k: float = _cs()
	var by: float = _base_y
	var pos: Vector3
	var look_at: Vector3
	var fov: float = 55.0
	# [vqa] The pad stands behind the yard's back fence: the close cameras look across the open lot
	# east of the pad (+x, a little behind it), so the yard stays out of frame.
	if t < 1.7:
		# Establishing: the ship's nose three-quarter, slow push in.
		pos = o + Vector3(11.0, 3.2, -7.0).lerp(Vector3(9.4, 2.9, -6.2), t / 1.7) * k
		look_at = o + Vector3(0, by + 1.0 * k, 0)
		fov = 50.0
	elif t < _t0:
		# Boarding: from the starboard side, Lumi on the lift and into the open canopy.
		pos = o + _dir(Vector3(-6.5, 3.4, 2.8) * k).lerp(_dir(Vector3(-5.8, 3.6, 2.2) * k), (t - 1.7) / (_t0 - 1.7))
		pos.y = o.y + by + 2.6 * k
		look_at = (world.patch.global_position if world.patch.visible else _hatch_world()) + Vector3(0, 0.2, 0)
		fov = 42.0
	elif t < _ig - 0.7:
		# Countdown: low front three-quarter, beacons and steam.
		pos = o + Vector3(8.4, 1.2, -4.4).lerp(Vector3(7.6, 1.3, -4.0), (t - _t0) / maxf(_ig - 0.7 - _t0, 0.1)) * k
		look_at = o + Vector3(0, by + 1.2 * k, 0)
		fov = 52.0
	elif t < _lo + 0.9:
		# Ignition: low by the deck edge, the fans blasting the downwash.
		pos = o + Vector3(10.5, 0.8, -1.6).lerp(Vector3(9.8, 0.9, -1.4), (t - (_ig - 0.7)) / (_lo + 1.6 - _ig)) * k
		look_at = o + Vector3(0, by + 1.0 * k, 0)
		fov = 42.0
	elif t < _lo + 5.0:
		# Lift-off and hover, then the turn away: low, looking up as it rises.
		pos = o + Vector3(9.0, 1.6, -9.5) * k
		look_at = mp + Vector3(0, 0.8 * k, 0)
		fov = 50.0
	else:
		# Fly-away: wide from the base, the ship streaking off to a dot.
		pos = o + Vector3(-12.0, 2.5, 30.0)
		look_at = (mp + Vector3(0, 1.0, 0)).lerp(o + Vector3(0, 6.0, 0), 0.25)
		fov = lerpf(58.0, 46.0, smoothstep(_lo + 5.0, _end, t))
	_cam.fov = fov
	var close: bool = t >= 1.7 and t < _lo + 5.0
	for n: Node3D in _clutter:
		if is_instance_valid(n):
			n.visible = not close
	_place_cam(pos, look_at, dt)


func _place_cam(pos: Vector3, look: Vector3, dt: float) -> void:
	_shake = maxf(0.0, _shake - dt * 0.5)
	_shake_t += dt * 38.0
	var s: float = _shake * _shake * (0.0 if Settings.reduced_motion else Settings.shake_intensity)
	var jitter := Vector3(sin(_shake_t * 1.3), sin(_shake_t * 1.7 + 2.0), sin(_shake_t * 1.1 + 4.0)) * 0.35 * s
	if pos.distance_to(look) < 0.1:
		return
	_cam.look_at_from_position(pos + jitter, look + jitter * 0.5, WorldUp.at(world, pos))  # [orbE] level on a round planet


func _start_flight() -> void:
	_mode = "flight"
	_t = 0.0
	_trail.emitting = false
	model.plume.power = 0.0
	for b: ColorRect in _bars:
		b.visible = false
	if HomewardDirector.start_flight(world, _to_hub, _flight_s):  # [home] planet trips and the home launch
		return
	world.globe.fly(world.hub_index, _to_hub, _flight_s)


func _travel() -> void:
	if _mode == "":
		return
	_mode = ""
	Input.stop_joy_vibration(0)
	print("[rocket] travel to hub %d" % _to_hub)
	if HomewardDirector.travel(world, _to_hub):  # [home]
		return
	world.travel_to(_to_hub)


# --- Arrival ---------------------------------------------------------------------------

## [ship] The ship flies in nose first, flares into a hover over the pad, lowers its gear and sets
## down on its lift fans; the canopy opens and Lumi flies out.
func arrive() -> void:
	if _mode != "":
		return
	_speed = [1.0, 1.0, 1.2, 1.4, 1.8][clampi(tier, 0, 4)]
	_begin("arrive")
	world.music.set_cinematic(true)
	var p: Patch = world.patch
	p.set_physics_process(false)
	p.velocity = Vector3.ZERO
	p.visible = false
	model.plume.power = 1.0
	model.set_legs(0.0)
	_trail.emitting = true
	_dot.visible = true
	var away: float = (pad.radius() if pad else 3.6 * _ship_scale()) + 1.4
	_land_to = global_position + Vector3(0.45, 0, 0.9).normalized() * away + Vector3(0, 0.05, 0)
	if pad:
		pad.set_gangway(1.0)
		pad.set_hoses(1.0)
		pad.set_clamps(1.0)
		pad.set_alarm(true)
	_arrive_step(0.0)
	Audio.play("whoosh", 0.4, -2.0)


func _arrive_step(dt: float) -> void:
	var t: float = _t
	var sc: float = _ship_scale()
	var fly_s: float = LAND_S * 0.6     # fly-in until the flare
	var hover_s: float = LAND_S * 0.78  # hover until the descent
	var hover := Vector3(0, _base_y + HOVER * sc, 0)
	var rest := Vector3(0, _base_y, 0)
	var start: Vector3 = hover + _dir(Vector3(0, 0, -140.0)) + Vector3(0, 55.0, 0)
	var pos: Vector3
	var pitch: float = 0.0
	if t < fly_s:
		var k: float = t / fly_s
		var e: float = 1.0 - pow(1.0 - k, 3.0)  # fast in, slowing to the hover point
		pos = start.lerp(hover, e)
		pitch = -0.08 * (1.0 - k) + 0.3 * smoothstep(0.6, 1.0, k)  # nose down in the dive, flare up
	elif t < hover_s:
		var w: float = (t - fly_s) / (hover_s - fly_s)
		pos = hover + Vector3(0, sin(t * 3.0) * 0.06, 0)
		pitch = 0.3 * (1.0 - smoothstep(0.0, 0.7, w))
	else:
		var d: float = smoothstep(hover_s, LAND_S, t)
		pos = hover.lerp(rest, d)
		pitch = 0.0
	if t >= LAND_S:
		pos = rest
	_pose(pos, pitch, sin(t * 2.2) * 0.04 * (1.0 - smoothstep(hover_s, LAND_S, t)))
	(_dot.material_override as StandardMaterial3D).albedo_color.a = 1.0 - smoothstep(0.05, 0.3, t / fly_s)
	_dot.visible = t < fly_s * 0.3
	var h: float = model.position.y - _base_y
	# Main engines brake through the fly-in and fade at the flare; the fans take the weight.
	model.plume.power = 1.0 - smoothstep(fly_s * 0.75, fly_s * 1.05, t)
	model.plume.light.light_energy = 8.0 * model.plume.power
	if t < LAND_S:
		model.set_lift(smoothstep(fly_s * 0.6, fly_s, t))
		if t >= _roar_next:
			_roar_next = t + 1.15
			Audio.play("roar", randf_range(1.05, 1.15), clampf(1.0 - h * 0.06, -16.0, 1.0), 0.02)
		_shake = maxf(_shake, 0.3 * smoothstep(8.0, 0.0, h))
	else:
		model.set_lift(maxf(0.0, 1.0 - (t - LAND_S) / 0.8))
	_trail.emitting = t < fly_s * 0.8
	_once("ground_fx", hover_s - 0.4, func() -> void:
		if pad:
			pad.billow(true)
		elif _dust:
			_dust.emitting = true)
	_once("touchdown", LAND_S, func() -> void:
		Audio.play("thud", 0.6, -2.0)
		Audio.play("clunk", 0.7, -2.0)
		Audio.play("steam", 0.7, -4.0)
		_shake = 0.4
		EventBus.shake_requested.emit(0.25)
		if pad:
			Audio.play("hydraulic", 0.7, -6.0))
	_once("settle", LAND_S + 1.4, func() -> void:
		if pad:
			pad.billow(false)
			pad.set_alarm(false)
		if _dust:
			_dust.emitting = false)
	model.set_legs(smoothstep(fly_s + 0.3, hover_s, t))
	_once("legs_down", fly_s + 0.3, func() -> void: Audio.play("servo", 0.7, -4.0))
	if pad:
		pad.set_clamps(1.0 - smoothstep(LAND_S, LAND_S + 0.6, t))
		pad.set_gangway(1.0 - smoothstep(LAND_S + 0.8, LAND_S + 1.5, t))
	# The canopy opens, Lumi pops out and flies down beside the pad.
	var exit_t: float = LAND_S + 1.6
	_set_hatch(smoothstep(exit_t - 0.7, exit_t, t))
	_once("hatch", exit_t - 0.7, func() -> void: Audio.play("hydraulic", 1.3, -6.0))
	var p: Patch = world.patch
	if t >= exit_t:
		var u: float = smoothstep(exit_t, exit_t + 2.2, t)
		var a: Vector3 = _hatch_world()
		var c: Vector3 = (a + _land_to) * 0.5 + Vector3(0, 1.4 * sc, 0)
		var pos2: Vector3 = a.lerp(c, u).lerp(c.lerp(_land_to, u), u)
		var fwd: Vector3 = c.lerp(_land_to, u) - a.lerp(c, u)
		p.visible = true
		p.scale = Vector3.ONE * (0.35 + 0.65 * smoothstep(exit_t, exit_t + 0.4, t))
		p.global_position = pos2
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
	var k: float = _cs()
	if t < LAND_S * 0.6:
		# The fly-in: from the lot, watching it come over the base.
		_cam.fov = 50.0
		_place_cam(o + Vector3(9.0, 1.8, -9.0) * k, mp + Vector3(0, 0.8, 0), dt)
	elif t < LAND_S + 1.4:
		# [vqa2] Hover and touchdown from the open lot east of the pad.
		_cam.fov = 48.0
		_place_cam(o + Vector3(10.5, 2.6, -2.5) * k, mp + Vector3(0, 0.9 * k, 0), dt)
	else:
		_cam.fov = 52.0
		_place_cam(o + Vector3(7.5, 2.6, 4.0) * k, (o + _land_to) * 0.5 + Vector3(0, 1.2, 0), dt)
	# [vqa2] Yard dressing hides for the close shots (hard cuts), as in the launch.
	var close: bool = t >= LAND_S * 0.6
	for n: Node3D in _clutter:
		if is_instance_valid(n):
			n.visible = not close


func _finish_arrival() -> void:
	if _mode != "arrive":
		return
	_mode = ""
	_park_pose()
	model.plume.power = 0.0
	model.set_lift(0.0)
	model.set_legs(1.0)
	_set_hatch(0.0)
	_trail.emitting = false
	_dot.visible = false
	if pad:
		pad.set_gangway(1.0)
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
	# [vqa] Yard dressing, future-city props and easter eggs crowd the pad from every close angle
	# (sign, fence, wires, lamp pylons, holo boards): they hide for the close shots (hard cuts) and
	# show again in the establishing and climb shots.
	_clutter.clear()
	for nm: String in ["StreetDressing", "FutureLayer", "EasterEggs"]:
		for n: Node in world.find_children(nm, "Node3D", true, false):
			_clutter.append(n as Node3D)
	# [vqa2] The hub's own street lamp (slice.gd ruin bits) stood mid-ground in the ignition shot.
	var bits: Variant = world.get("_ruin_bits")
	if bits is Dictionary and (bits as Dictionary).get("street_lamp") is Node3D:
		_clutter.append((bits as Dictionary)["street_lamp"])
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
	for n: Node3D in _clutter:
		if is_instance_valid(n):
			n.visible = true
	_clutter.clear()
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
	_trail.direction = Vector3(0, 0, -1)
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
	_trail.position = Vector3(0, 1.0, -5.5)  # [ship] behind the engines, past the hot cores
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
	_dot.position = Vector3(0, 1.0, -3.6)
	_dot.visible = false
	model.add_child(_dot)


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
