class_name WorldBounds
extends Node
## [orbit] Lumi can never fall off the world. The district's ground collider is a square of
## half-size `layout.extent`; past it there is nothing. This keeps Lumi and the robots on it:
## - a soft wall `wall_margin` metres inside the edge (the outward part of the velocity is removed
##   and a short WREN line plays now and then),
## - a rescue if Lumi still ends up outside the square or below the ground (physics push, a bad
##   teleport): a short hover-and-fade back onto the nearest walkable ground,
## - robots (group "robot") and loose cubes (group "junk_cube") are put back without the fade.
## With Orbit active (`--orbit`), the world wraps instead and only the below-ground rescue runs.

const FALL_Y: float = -3.0
const RESCUE_INSET: float = 4.0
const FADE_IN: float = 0.22
const HOVER_T: float = 0.55

var world: Node  # the slice scene (patch, layout, field)
var half: float = 150.0
var wall_margin: float = 3.0
## Set by Orbit: no edge in a wrapping world, only the below-ground rescue.
var wraps: bool = false
var rescues: int = 0
var robot_rescues: int = 0

var _rescuing: bool = false
var _hint_cd: float = 0.0
var _fade: ColorRect


func _ready() -> void:
	process_physics_priority = 100  # after Patch and the robots have moved this frame
	var lay: CityLayout = world.get("layout") if world else null
	if lay:
		half = lay.extent
	var cl := CanvasLayer.new()
	cl.layer = 90
	add_child(cl)
	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.03, 0.05, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(_fade)


## Inner limit of the soft wall (|x|, |z|).
func wall() -> float:
	return half - wall_margin


## Off the world: outside the ground square (plus a little slack) or below the ground.
static func is_lost(p: Vector3, half_: float, wraps_: bool) -> bool:
	if p.y < FALL_Y:
		return true
	return not wraps_ and (absf(p.x) > half_ + 0.5 or absf(p.z) > half_ + 0.5)


## Clamp a point into the square [-lim, lim]^2 (y kept). Returns whether it moved.
static func clamp_xz(p: Vector3, lim: float) -> Vector3:
	return Vector3(clampf(p.x, -lim, lim), p.y, clampf(p.z, -lim, lim))


func _physics_process(delta: float) -> void:
	if world == null or get_tree().paused:
		return
	_hint_cd = maxf(0.0, _hint_cd - delta)
	var patch: Patch = world.get("patch")
	if patch and patch.visible and patch.is_physics_processing() and not _rescuing:
		if is_lost(patch.global_position, half, wraps):
			_rescue_patch(patch)
		elif not wraps:
			_soft_wall(patch)
	for n: Node in get_tree().get_nodes_in_group("robot"):
		var b := n as CharacterBody3D
		if b == null or not b.is_inside_tree():
			continue
		if is_lost(b.global_position, half, wraps):
			b.global_position = nearest_ground(b.global_position) + Vector3(0, 0.15, 0)
			b.velocity = Vector3.ZERO
			robot_rescues += 1
		elif not wraps:
			_wall_body(b)
	for n: Node in get_tree().get_nodes_in_group("junk_cube"):
		var c := n as RigidBody3D
		if c and c.is_inside_tree() and not c.freeze and is_lost(c.global_position, half, wraps):
			c.global_position = nearest_ground(c.global_position) + Vector3(0, 0.6, 0)
			c.linear_velocity = Vector3.ZERO


func _wall_body(b: CharacterBody3D) -> bool:
	var lim: float = wall()
	var p: Vector3 = b.global_position
	if absf(p.x) <= lim and absf(p.z) <= lim:
		return false
	b.global_position = clamp_xz(p, lim)
	if absf(p.x) > lim and signf(b.velocity.x) == signf(p.x):
		b.velocity.x = 0.0
	if absf(p.z) > lim and signf(b.velocity.z) == signf(p.z):
		b.velocity.z = 0.0
	return true


func _soft_wall(patch: Patch) -> void:
	if _wall_body(patch) and _hint_cd <= 0.0:
		_hint_cd = 25.0
		EventBus.toast.emit(tr("WREN: That's the edge of the survey zone, Lumi. Nothing out there but haze."), "info")


## The closest walkable ground to `p`: inside the wall, on top of whatever the down-ray hits first
## if that is low (street, yard, curb), otherwise stepping toward the base until it is.
func nearest_ground(p: Vector3) -> Vector3:
	var q: Vector3 = clamp_xz(p, wall() - RESCUE_INSET) if not wraps else p
	var space: PhysicsDirectSpaceState3D = null
	if world is Node3D and (world as Node3D).is_inside_tree():
		space = (world as Node3D).get_world_3d().direct_space_state
	for i: int in 24:
		var y: float = _ground_y(space, q)
		if y > -1.0 and y < 0.8:
			return Vector3(q.x, y, q.z)
		var flat := Vector2(q.x, q.z)
		flat = flat.move_toward(Vector2.ZERO, 3.0)
		q = Vector3(flat.x, 0.0, flat.y)
	return Vector3(0.0, 0.05, 3.0)  # the yard


func _ground_y(space: PhysicsDirectSpaceState3D, q: Vector3) -> float:
	if space == null:
		return 0.0
	var rq := PhysicsRayQueryParameters3D.create(Vector3(q.x, 40.0, q.z), Vector3(q.x, -5.0, q.z), 1)
	var hit: Dictionary = space.intersect_ray(rq)
	if hit.is_empty():
		return -99.0
	if (hit["normal"] as Vector3).y < 0.7:
		return 99.0
	return (hit["position"] as Vector3).y


## Lumi hovers up, the screen dips, he is set down on the nearest ground and drifts down to it.
func _rescue_patch(patch: Patch) -> void:
	_rescuing = true
	rescues += 1
	GameState.inc_stat("edge_rescues")
	var dest: Vector3 = nearest_ground(patch.global_position)
	patch.set_physics_process(false)
	patch.velocity = Vector3.ZERO
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.85, FADE_IN)
	await tw.finished
	if not is_instance_valid(patch):
		_rescuing = false
		return
	var from_dir := Vector3(patch.global_position.x - dest.x, 0.0, patch.global_position.z - dest.z)
	patch.global_position = dest + Vector3(0, 1.4, 0)
	if from_dir.length() > 0.5:  # face back into the district
		patch.rotation.y = atan2(from_dir.x, from_dir.z)
	var cam: Node = world.get("cam")
	if cam and cam.has_method("snap"):
		cam.call("snap")
	Vfx.burst("dust", dest + Vector3(0, 0.1, 0), Color(0.75, 0.8, 0.85, 0.6), 0.7)
	var tw2 := create_tween().set_parallel(true)
	tw2.tween_property(_fade, "color:a", 0.0, HOVER_T)
	tw2.tween_property(patch, "global_position", dest + Vector3(0, 0.05, 0), HOVER_T).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw2.finished
	if is_instance_valid(patch):
		patch.set_physics_process(true)
	_rescuing = false
	EventBus.toast.emit(tr("Lumi hovers back onto solid ground."), "info")
