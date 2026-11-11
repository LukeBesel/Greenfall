extends GutTest
## [v6feel] Lumi against obstacles on a round planet: he slides round corners, heaps and posts,
## hovers over kerbs, and stands still (no jitter) when he pushes straight into a wall.

const R: float = 1840.0

var lumi: Patch
var inp: FeelProbe.FeelInput


func before_each() -> void:
	var surf := SphereSurface.new(R)
	lumi = Patch.new()
	inp = FeelProbe.FeelInput.new()
	inp.world_space = true
	lumi.input = inp
	lumi.enable_sphere(surf, null)
	add_child_autofree(lumi)
	lumi.place_on_sphere(Vector3(0, R, 0), Vector3(0, 0, -1))


func _solid(shape: Shape3D, at: Vector3, layer: int = PhysLayers.PROP) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = layer
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	b.add_child(cs)
	add_child_autofree(b)
	b.global_position = Vector3(at.x, R + at.y, at.z)
	return b


func _box(size: Vector3, at: Vector3, layer: int = PhysLayers.PROP) -> StaticBody3D:
	var s := BoxShape3D.new()
	s.size = size
	return _solid(s, at, layer)


## Pushes north (-Z) for `secs`; returns [metres north, largest height above the start, the widest
## swing of his height from one tick to the next, speed at the end].
func _push(secs: float) -> Array:
	inp.stick = Vector3(0, 0, -1)
	var z0: float = lumi.global_position.z
	var top: float = 0.0
	var jit: float = 0.0
	var last: float = lumi.sphere.altitude(lumi.global_position)
	var n: int = int(secs * Engine.physics_ticks_per_second)
	for k: int in n:
		await get_tree().physics_frame
		var a: float = lumi.sphere.altitude(lumi.global_position)
		top = maxf(top, a)
		if k > 30:
			jit = maxf(jit, absf(a - last))
		last = a
	return [z0 - lumi.global_position.z, top, jit, lumi.sphere_motor.hv.length()]


func test_open_ground_is_full_speed() -> void:
	var r: Array = await _push(2.0)
	assert_gt(float(r[0]), 8.0)
	assert_lt(float(r[2]), 0.01, "no bobbing on flat ground")


# A wall corner clipped by 0.4 m of his body: he slides off it and keeps going.
func test_slides_off_a_wall_corner() -> void:
	_box(Vector3(4, 3, 4), Vector3(-2.0 - 0.15, 1.5, -5.0))  # its east face 0.15 m west of his middle
	var r: Array = await _push(3.0)
	assert_gt(float(r[0]), 9.0, "past the corner (it is 3 m ahead), went %.1f m" % float(r[0]))


# A junk heap hit off-centre: round it on the level, no hopping up its side.
func test_slides_round_a_junk_heap() -> void:
	var holder := Node3D.new()
	add_child_autofree(holder)
	holder.global_position = Vector3(0, R, 0)
	var m: StaticBody3D = MoundColliders.make(holder, Vector4(0.9, -4.0, 1.5, 0.9))
	MoundColliders.update(m, Vector3(1.6, 0.9, 1.6), true, 1.0)
	var r: Array = await _push(3.0)
	assert_gt(float(r[0]), 8.0, "round the heap, went %.1f m" % float(r[0]))
	assert_lt(float(r[1]), 0.12, "he stays at hover height, rose %.2f m" % float(r[1]))
	assert_lt(float(r[2]), 0.02, "no jitter against the heap")


# A lamp post dead ahead, a hand's width off his middle.
func test_slides_past_a_post() -> void:
	var c := CylinderShape3D.new()
	c.radius = 0.12
	c.height = 3.0
	_solid(c, Vector3(0.1, 1.5, -4.0))
	var r: Array = await _push(3.0)
	assert_gt(float(r[0]), 9.0, "past the post, went %.1f m" % float(r[0]))


# Straight into a wall: he stops and stands still, and his turn does not shove him about.
func test_dead_on_wall_stops_without_jitter() -> void:
	_box(Vector3(12, 3, 2), Vector3(0, 1.5, -5.0))
	var r: Array = await _push(2.5)
	assert_between(float(r[0]), 3.0, 3.6, "stopped at the wall")
	var p0: Vector3 = lumi.global_position
	inp.stick = Vector3(0.6, 0, -0.8).normalized()
	var worst: float = 0.0
	var back: float = 0.0
	for k: int in 120:
		await get_tree().physics_frame
		back = maxf(back, lumi.global_position.z - p0.z)
		worst = maxf(worst, absf(lumi.sphere.altitude(lumi.global_position) - lumi.sphere.altitude(p0)))
	assert_lt(back, 0.03, "turning against the wall never pushes him back off it")
	assert_lt(worst, 0.02)
	assert_gt(lumi.global_position.x - p0.x, 1.5, "and he slides along it")


# A kerb or a low planter (up to 0.45 m) is hovered over, not a wall.
func test_hovers_over_a_kerb() -> void:
	_box(Vector3(8, 0.4, 1.4), Vector3(0, 0.2, -4.0), PhysLayers.WORLD)
	var r: Array = await _push(3.0)
	assert_gt(float(r[0]), 9.0, "over the planter, went %.1f m" % float(r[0]))
	assert_between(float(r[1]), 0.3, 0.6, "lifted by it")


func test_a_prop_kerb_too() -> void:
	_box(Vector3(8, 0.3, 0.5), Vector3(0, 0.15, -4.0))
	var r: Array = await _push(3.0)
	assert_gt(float(r[0]), 9.0, "over the kerb, went %.1f m" % float(r[0]))


# Taller than he can hover over: still a wall.
func test_a_fence_is_a_wall() -> void:
	_box(Vector3(8, 0.9, 0.2), Vector3(0, 0.45, -4.0))
	var r: Array = await _push(2.5)
	assert_lt(float(r[0]), 3.6)
