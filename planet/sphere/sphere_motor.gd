class_name SphereMotor
extends RefCounted
## [smove] Hover movement for a CharacterBody3D on a planet (Lumi; usable by Patch.gd directly).
## - Gravity toward the planet centre, body up = local radial up, a re-orthonormalised basis built
##   from (up, forward) every step: no Euler angles, no latitude, fine at the poles.
## - Hover: the body rides `ride_height` above the ground on a critically damped spring (the
##   collision shape is lifted so it only touches walls and props, never the floor). Ground =
##   max(analytic SphereSurface height, a physics ray against mask 1), so props and terrain meshes
##   lift him too. Jumping switches to ballistic flight until he lands back on the spring.
## - Boost: a hover-boost for fast travel that ramps speed up to `boost_mult` and lifts him a bit.
## - Slopes: uphill is a little slower, slopes above `max_slope` push him back down.
## Horizontal tuning is Patch's (ACCEL 16, DECEL 22, TURN_RATE 9, GRAVITY 20, speed 4.6).
##
## Use: motor.step(body, wish, delta, boost, jump) once per physics frame, `wish` = desired
## world-space move (any vector, projected to the tangent plane, length 0..1).

signal landed(impact: float)
signal jumped

var surface: SphereSurface
var accel: float = 16.0
var decel: float = 22.0
var turn_rate: float = 9.0
var gravity: float = 20.0
var speed: float = 4.6
## Boosted top speed = speed * boost_mult; boost_ramp = seconds to reach it from walking.
var boost_mult: float = 4.0
## [orbD] Vehicle multiplier on the walking top speed (the hover-sled sets it; Patch keeps
## setting `speed` from its stat every frame).
var speed_mult: float = 1.0
var boost_ramp: float = 0.8
var boost_lift: float = 0.35
var jump_speed: float = 6.5
var air_control: float = 0.35
var ride_height: float = 0.0
var spring_k: float = 160.0
var max_slope: float = deg_to_rad(42.0)
## Ray-sample the physics ground too (needs a physics space). Off = analytic surface only.
var use_ray: bool = true
var ray_mask: int = 1

var fwd := Vector3.FORWARD
var hv := Vector3.ZERO  # tangent velocity
var vv: float = 0.0     # radial velocity
var grounded: bool = true
var boost_t: float = 0.0
var distance: float = 0.0
var ground_normal := Vector3.UP
var altitude: float = 0.0
var _last_up := Vector3.ZERO
var _jump_lock: float = 0.0


func _init(p_surface: SphereSurface = null) -> void:
	surface = p_surface if p_surface else SphereSurface.new()


func up(body: Node3D) -> Vector3:
	return surface.up_at(body.global_position)


## Places the body on the ground under `pos`, facing `facing` (projected to the tangent plane).
func place(body: CharacterBody3D, pos: Vector3, facing: Vector3) -> void:
	var u: Vector3 = surface.up_at(pos)
	body.global_position = surface.ground(u) + u * ride_height
	fwd = SphereMath.tangent_dir(facing, u, fwd)
	_last_up = u
	hv = Vector3.ZERO
	vv = 0.0
	grounded = true
	body.up_direction = u
	body.global_basis = SphereMath.basis_from_up_fwd(u, fwd)


func face(body: Node3D, facing: Vector3) -> void:
	var u: Vector3 = up(body)
	fwd = SphereMath.tangent_dir(facing, u, fwd)
	body.global_basis = SphereMath.basis_from_up_fwd(u, fwd)


func speed_ratio() -> float:
	return hv.length() / maxf(speed, 0.01)


## Ground under the body: [altitude above it, normal].
func sample_ground(body: CharacterBody3D, u: Vector3) -> Array:
	var p: Vector3 = body.global_position
	var alt: float = surface.altitude(p)
	var n: Vector3 = surface.ground_normal(u)
	if use_ray and body.is_inside_tree():
		var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
		if space:
			var q := PhysicsRayQueryParameters3D.create(p + u * 1.2, p - u * 3.0, ray_mask, [body.get_rid()])
			var hit: Dictionary = space.intersect_ray(q)
			if not hit.is_empty():
				var a2: float = (p - (hit["position"] as Vector3)).dot(u)
				if a2 < alt:
					alt = a2
					n = hit["normal"]
	return [alt, n]


func step(body: CharacterBody3D, wish: Vector3, delta: float, boost: bool = false, jump: bool = false) -> void:
	var p0: Vector3 = body.global_position
	var u: Vector3 = surface.up_at(p0)
	if _last_up == Vector3.ZERO:
		_last_up = u
	# Carry the heading and velocity into this point's tangent plane (parallel transport).
	fwd = SphereMath.tangent_dir(SphereMath.transport_vec(fwd, _last_up, u), u, fwd)
	hv = SphereMath.tangent(SphereMath.transport_vec(hv, _last_up, u), u)
	_last_up = u
	body.up_direction = u
	var g: Array = sample_ground(body, u)
	altitude = g[0]
	ground_normal = SphereMath.slerp_safe(ground_normal, g[1], SphereMath.damp(12.0, delta)) if ground_normal.dot(g[1]) > -0.5 else g[1]
	_jump_lock = maxf(0.0, _jump_lock - delta)
	# --- Horizontal -------------------------------------------------------------------------
	var w: Vector3 = SphereMath.tangent(wish, u).limit_length(1.0)
	boost_t = move_toward(boost_t, 1.0 if boost and w.length() > 0.1 else 0.0, delta / maxf(boost_ramp, 0.01) * (1.0 if boost else 2.0))
	var ease_b: float = boost_t * boost_t * (3.0 - 2.0 * boost_t)
	var top: float = speed * speed_mult * lerpf(1.0, boost_mult, ease_b)  # [orbD] speed_mult
	var target: Vector3 = w * top
	# Slopes: the tangent part of the ground normal points downhill.
	var down: Vector3 = SphereMath.tangent(ground_normal, u)
	var steep: float = down.length()  # sin(slope)
	if steep > 0.01 and grounded:
		var dd: Vector3 = down / steep
		var up_amt: float = -target.dot(dd)
		if up_amt > 0.0:
			var slope: float = asin(clampf(steep, 0.0, 1.0))
			if slope > max_slope:
				target += dd * up_amt  # no climbing walls
				hv += dd * gravity * steep * delta
			else:
				target *= 1.0 - 0.35 * steep
	var rate: float = accel if target.length() > hv.length() else decel
	if ease_b > 0.01 and target.length() > hv.length():
		rate = maxf(accel * 0.6, (top - speed) / maxf(boost_ramp, 0.01))
	if not grounded:
		rate *= air_control
	hv = hv.move_toward(target, rate * delta)
	# --- Vertical ---------------------------------------------------------------------------
	var ride: float = ride_height + boost_lift * ease_b
	if grounded:
		if jump and _jump_lock <= 0.0:
			vv = jump_speed
			grounded = false
			_jump_lock = 0.25
			jumped.emit()
		else:
			var c: float = 2.0 * sqrt(spring_k)
			vv += (spring_k * (ride - altitude) - c * vv) * delta
			vv = clampf(vv, -8.0, 8.0)
			if altitude > ride + 0.6:  # ground dropped away (ledge): fall
				grounded = false
	if not grounded:
		vv -= gravity * delta
		if altitude <= ride + 0.02 and vv <= 0.0 and _jump_lock <= 0.0:
			grounded = true
			landed.emit(-vv)
			vv = 0.0
	body.velocity = hv + u * vv
	body.move_and_slide()
	# --- After the move ---------------------------------------------------------------------
	var p1: Vector3 = body.global_position
	var u1: Vector3 = surface.up_at(p1)
	var alt1: float = surface.altitude(p1)
	if alt1 < ride_height - 0.05:  # never sink into the ground
		body.global_position = p1 + u1 * (ride_height - alt1)
		if vv < 0.0:
			vv = 0.0
	# [orbD] Held up by a body the ground ray doesn't see (a junk mound, a prop on its own layer):
	# land on it. Without this he hung there "falling" forever, vv grew without bound and the
	# slide ate all his tangent speed, wedged between a mound and a prop.
	if not grounded and vv < -2.0 and body.get_real_velocity().dot(u1) > vv * 0.3:
		grounded = true
		landed.emit(-vv)
		vv = 0.0
	vv = clampf(vv, -40.0, 40.0)
	# Walls: keep only the tangent velocity the slide left us.
	var real: Vector3 = SphereMath.tangent(body.get_real_velocity(), u1)
	if real.length() < hv.length() - 0.01 and body.get_slide_collision_count() > 0:
		hv = SphereMath.tangent(SphereMath.transport_vec(hv, u, u1), u1).limit_length(real.length())
	var hs: float = hv.length()
	if hs > 0.3:
		var hd: Vector3 = hv / hs
		var f: Vector3 = SphereMath.tangent_dir(SphereMath.transport_vec(fwd, u, u1), u1, fwd)
		var hd1: Vector3 = SphereMath.tangent_dir(SphereMath.transport_vec(hd, u, u1), u1, f)
		if f.dot(hd1) < -0.98:
			f = (f + SphereMath.any_perpendicular(u1) * 0.05).normalized()
		fwd = SphereMath.tangent_dir(SphereMath.slerp_safe(f, hd1, SphereMath.damp(turn_rate, delta)), u1, f)
	else:
		fwd = SphereMath.tangent_dir(SphereMath.transport_vec(fwd, u, u1), u1, fwd)
	hv = SphereMath.tangent(SphereMath.transport_vec(hv, u, u1), u1)
	_last_up = u1
	body.up_direction = u1
	body.global_basis = SphereMath.basis_from_up_fwd(u1, fwd)
	distance += surface.arc_dist(p0, body.global_position)
