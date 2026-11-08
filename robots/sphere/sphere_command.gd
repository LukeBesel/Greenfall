class_name SphereCommand
extends Node
## [orbC] Command view on a round planet: SphereCam's "command" view (30-400 m up, top of the
## screen = the camera frame's forward) replaces the flat overhead camera. Picking ray-casts
## against the globe (the terrain height, not a plane) and returns cell ids, so zone painting,
## robot orders and hex picking all speak cell ids like the rest of the sphere code.
## While the view is on, the streamer's hex outlines are shown (SphereStreamer.outlines).
## Input (when `input_enabled`): left drag paints the selected role's zone, right drag erases it,
## middle click sends the nearest robot to the hex, Tab cycles the role.

signal cell_picked(cell: int)

const ROLES: Array[String] = ["clean", "plant", "water", "haul"]

var cam: SphereCam
var surface: SphereSurface
var grid: SphereGrid
var crew: SphereCrew
var streamer: SphereStreamer
var input_enabled: bool = true
var role: String = "clean"
var hover_cell: int = -1
var _paint: int = 0  # 1 paint, -1 erase
var _was_command: bool = false


## Where a camera ray through `screen_pos` meets the ground: a unit direction (ZERO = sky).
## Intersects the sphere at the planet radius, then refines against the terrain height there.
static func pick_dir(camera: Camera3D, screen_pos: Vector2, p_surface: SphereSurface) -> Vector3:
	var o: Vector3 = camera.project_ray_origin(screen_pos) - p_surface.center
	var d: Vector3 = camera.project_ray_normal(screen_pos)
	return ray_dir(o, d, p_surface)


## Ray (origin relative to the planet centre, unit direction) against the ground.
static func ray_dir(o: Vector3, d: Vector3, p_surface: SphereSurface) -> Vector3:
	var h: float = 0.0
	var hit := Vector3.ZERO
	for _i: int in 5:
		var r: float = p_surface.radius + h
		var b: float = o.dot(d)
		var c: float = o.dot(o) - r * r
		var disc: float = b * b - c
		if disc < 0.0:
			return hit  # misses the planet (or the refined shell): keep the last hit
		var t: float = -b - sqrt(disc)
		if t < 0.0:
			t = -b + sqrt(disc)
			if t < 0.0:
				return hit
		hit = (o + d * t).normalized()
		var nh: float = p_surface.height(hit)
		if absf(nh - h) < 0.02:
			break
		h = nh
	return hit


static func pick_cell(camera: Camera3D, screen_pos: Vector2, p_surface: SphereSurface, p_grid: SphereGrid) -> int:
	var d: Vector3 = pick_dir(camera, screen_pos, p_surface)
	return p_grid.cell_at(d) if d != Vector3.ZERO else -1


func is_active() -> bool:
	return cam != null and cam.view == "command"


func _process(_delta: float) -> void:
	var on: bool = is_active()
	if on != _was_command:
		_was_command = on
		if streamer:
			streamer.outlines = on
		_paint = 0
	if not on or cam.camera == null:
		hover_cell = -1
		return
	var vp: Viewport = cam.get_viewport()
	if vp == null:
		return
	hover_cell = pick_cell(cam.camera, vp.get_mouse_position(), surface, grid)
	if _paint != 0 and hover_cell >= 0 and crew:
		crew.set_zone_cell(role, hover_cell, _paint > 0)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or not is_active():
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		var c: int = pick_cell(cam.camera, mb.position, surface, grid)
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_paint = 1 if mb.pressed else 0
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_paint = -1 if mb.pressed else 0
		elif mb.button_index == MOUSE_BUTTON_MIDDLE and mb.pressed and c >= 0:
			order_nearest(c)
		if mb.pressed and c >= 0:
			cell_picked.emit(c)
	elif event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_TAB:
		role = ROLES[(ROLES.find(role) + 1) % ROLES.size()]


## Send the nearest robot of the selected role to `cell`. Returns its unit ({} if none).
func order_nearest(cell: int) -> Dictionary:
	if crew == null:
		return {}
	var best: Dictionary = {}
	var best_d: float = INF
	var at: Vector3 = grid.centers[cell]
	for u: Dictionary in crew.robots():
		if str(u["role"]) != role:
			continue
		var dd: float = crew.unit_dir(u).angle_to(at)
		if dd < best_d:
			best_d = dd
			best = u
	if not best.is_empty():
		crew.order(best, cell)
	return best
