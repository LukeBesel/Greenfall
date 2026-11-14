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
## [v6feel] Where the ground ray starts above the body's base (lower = it never finds an awning).
var ray_top: float = 1.2
## [v6feel] Level slide (Lumi): walls, heaps and props all act as upright walls, so he slides round
## them on the level instead of riding up a heap's side and jittering; contacts are kept in `hits`.
## Off = CharacterBody3D.move_and_slide in 3D (the walker demo).
var flat_slide: bool = false
## [v6feel] With flat_slide: solid things up to this high (kerbs, low planters, steps) are hovered
## over with a quick lift instead of stopping him. Junk heaps (PhysLayers.MOUND) and bales never are.
var max_step: float = 0.45
var step_mask: int = 1
## [v6feel] With flat_slide: the share of his speed kept while rounding a prop he clipped nearly
## head-on (0 = plain slide, which lost nearly all of it).
var round_keep: float = 0.6
var hits: Array[KinematicCollision3D] = []
var _climb: float = 0.0   # extra ride height while crossing a low obstacle
var _climb_t: float = 0.0
var _under: float = 0.0

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
			var q := PhysicsRayQueryParameters3D.create(p + u * ray_top, p - u * 3.0, ray_mask, [body.get_rid()])
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
	if flat_slide:  # [v6feel] crossing a kerb: hold the lift a moment, then let it go
		_climb_t = maxf(0.0, _climb_t - delta)
		if _climb_t <= 0.0:
			_climb = move_toward(_climb, 0.0, delta * 2.0)
		_under = maxf(0.0, surface.altitude(p0) - altitude)  # what he is over already (a kerb's top)
		ride = maxf(ride, _climb - _under)
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
			if _climb_t > 0.0 and altitude < ride - 0.02:  # [v6feel] a quick thruster kick over the kerb
				vv = maxf(vv, minf(3.5, (ride - altitude) * 16.0))
			if altitude > ride + 0.6:  # ground dropped away (ledge): fall
				grounded = false
	if not grounded:
		vv -= gravity * delta
		if altitude <= ride + 0.02 and vv <= 0.0 and _jump_lock <= 0.0:
			grounded = true
			landed.emit(-vv)
			vv = 0.0
	body.velocity = hv + u * vv
	if flat_slide:
		_level_slide(body, u, delta)
	else:
		# [v6feel] move_and_slide moves by the engine's own frame delta, not ours: scale the
		# velocity so a manual step(delta) (tests, a fixed-step caller) moves by `delta`.
		var ed: float = body.get_physics_process_delta_time() if Engine.is_in_physics_frame() else body.get_process_delta_time()
		var k: float = delta / ed if ed > 1e-6 else 1.0
		body.velocity *= k
		body.move_and_slide()
		body.velocity /= k
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
	var real_v: Vector3 = (p1 - p0) / maxf(delta, 1e-5)  # [v6feel] our delta, either path
	if not grounded and vv < -2.0 and real_v.dot(u1) > vv * 0.3:
		grounded = true
		landed.emit(-vv)
		vv = 0.0
	vv = clampf(vv, -40.0, 40.0)
	# Walls: keep only the tangent velocity the slide left us.
	var real: Vector3 = SphereMath.tangent(real_v, u1)
	if flat_slide:
		pass  # _level_slide already took the blocked part out of hv
	elif real.length() < hv.length() - 0.01 and body.get_slide_collision_count() > 0:
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


## [v6feel] The move for flat_slide: along the ground first, sliding on each contact's level normal
## (up to 4 contacts a tick), then up or down. A low obstacle ahead starts a climb instead.
func _level_slide(body: CharacterBody3D, u: Vector3, delta: float) -> void:
	hits.clear()
	if not PhysicsServer3D.body_get_space(body.get_rid()).is_valid():  # [v7play] out of every space for a frame (a rocket hop): no test motion
		return
	var motion: Vector3 = hv * delta
	for i: int in 4:
		if motion.length_squared() < 1e-10:
			break
		var col: KinematicCollision3D = body.move_and_collide(motion, false, 0.001, true)
		if col == null:
			break
		hits.append(col)
		var n3: Vector3 = col.get_normal()
		var n: Vector3 = SphereMath.tangent(n3, u)
		if _can_climb(body, col, u, n):
			break  # he keeps his speed and goes on as soon as the lift clears it
		if n.length() < 0.15:  # the top or underside of something: nothing to slide on
			if n3.dot(u) > 0.0:
				_climb = maxf(_climb, altitude + _under + 0.06)
				_climb_t = 0.2
			break
		n = n.normalized()
		# [v6feel] His body is round: on its side the true contact normal points from the contact
		# to his axis. The engine gives a box post's face normal for a hit on its edge, which squares
		# him up against a thin post he only clipped (he stalled a second on near dead-on pushes).
		var radial: Vector3 = SphereMath.tangent(body.global_position - col.get_position(), u)
		if radial.length() > 0.3 and radial.normalized().dot(n) > 0.2:
			n = radial.normalized()
		motion = SphereMath.tangent(col.get_remainder().slide(n), u)
		if hv.dot(n) < 0.0:
			var hs0: float = hv.length()
			hv = hv.slide(n)
			# [v6feel] Rounding a post, a bin or a heap he clipped nearly head-on: keep some of his
			# speed along the way round (he dropped to a crawl for half a second on a lamp post).
			# Not on walls (WORLD only), and not on a square hit, where the way round is noise.
			var co: Object = col.get_collider()
			if round_keep > 0.0 and co is CollisionObject3D and ((co as CollisionObject3D).collision_layer & PhysLayers.PROP) != 0:
				var hs1: float = hv.length()
				if hs1 > hs0 * 0.15 and hs1 < hs0 * round_keep:
					hv *= hs0 * round_keep / hs1
	var vc: KinematicCollision3D = body.move_and_collide(u * vv * delta, false, 0.001, false)
	if vc != null:
		hits.append(vc)
		if vv > 0.0 and vc.get_normal().dot(u) < -0.5:
			vv = 0.0  # bumped his head


## True (and the climb is under way) when the thing hit is low enough to hover over.
func _can_climb(body: CharacterBody3D, col: KinematicCollision3D, u: Vector3, n_level: Vector3) -> bool:
	if max_step <= 0.0 or not grounded or n_level.length() < 0.15:
		return false
	var co: Object = col.get_collider()
	if co is RigidBody3D:
		return false
	if co is CollisionObject3D and ((co as CollisionObject3D).collision_layer & PhysLayers.MOUND) != 0:
		return false
	var base: Vector3 = body.global_position - u * altitude  # the ground under him
	var cp: Vector3 = col.get_position()
	var at: Vector3 = cp - n_level.normalized() * 0.15
	at = base + SphereMath.tangent(at - base, u)
	var q := PhysicsRayQueryParameters3D.create(at + u * (max_step + 0.3), at - u * 0.2, step_mask, [body.get_rid()])
	q.hit_from_inside = true
	var hit: Dictionary = body.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	var top: float = ((hit["position"] as Vector3) - base).dot(u)
	if top > max_step or top < 0.02:
		return false
	_climb = maxf(_climb, top + _under + 0.03)  # over the planet's own ground
	_climb_t = 0.35
	return true
