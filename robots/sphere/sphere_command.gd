class_name SphereCommand
extends Node
## [orbC] Command view on a round planet: SphereCam's "command" view (30-400 m up, top of the
## screen = the camera frame's forward) replaces the flat overhead camera. Picking ray-casts
## against the globe (the terrain height, not a plane) and returns cell ids, so zone painting,
## robot orders and hex picking all speak cell ids like the rest of the sphere code.
## While the view is on, the streamer's hex outlines are shown (SphereStreamer.outlines).
## Input (when `input_enabled`): move keys / left stick pan the view away from Lumi (who stands
## still meanwhile), left drag paints the selected role's zone, right drag erases it, middle click
## sends the nearest robot to the hex, Tab cycles the role, interact (E) recentres on Lumi.
## CommandOverlay draws the robots (clustered when they crowd), the zone and the role label.

signal cell_picked(cell: int)

## [v6crew] Jobs a zone can be painted for (Haul Bugs follow the bales, so they have none).
const ROLES: Array[String] = ["clean", "plant", "water", "skim"]

var cam: SphereCam
var surface: SphereSurface
var grid: SphereGrid
var crew: SphereCrew
var streamer: SphereStreamer
var input_enabled: bool = true
var role: String = "clean"
var hover_cell: int = -1
var _paint: int = 0  # 1 paint, -1 erase
## [v3qa] Controller: the cell under the screen centre is the cursor; A held paints, X held
## erases, Y cycles the role (the flat Command view's pad scheme). A kid on a pad could not
## paint a zone at all, so "Send your robot to work" never finished.
var using_pad: bool = false
var _pad_paint: int = 0
var _was_command: bool = false
## Lumi's input: off while commanding, so the move keys pan the view instead of walking.
var lumi_input: PlayerInput
var overlay: CommandOverlay
## [v6crew] Cells painted since the view was opened (the guided step's "Good!" line).
var painted_now: int = 0
## [v6crew] The robot under the cursor (or the pad's reticle): its line is shown by the overlay.
var hover_unit: Dictionary = {}


## [v6crew] The jobs the player can paint right now: those he has a robot for (always "clean").
func roles() -> Array[String]:
	var out: Array[String] = ["clean"]
	if crew != null:
		for r: String in ROLES:
			if r == "clean":
				continue
			for u: Dictionary in crew.robots():
				if str(u["role"]) == r:
					out.append(r)
					break
	return out


func next_role() -> void:
	var rs: Array[String] = roles()
	role = rs[(rs.find(role) + 1) % rs.size()]


## [v6crew] The hub this view is over (the one nearest the camera's focus).
func view_hub() -> int:
	if crew == null:
		return -1
	var d: Vector3 = cam.command_focus if cam != null and cam.command_focus != Vector3.ZERO else Vector3.ZERO
	if d == Vector3.ZERO and crew.focus != null and is_instance_valid(crew.focus):
		d = surface.up_at(crew.focus.global_position)
	return crew.nearest_hub(d) if d != Vector3.ZERO else crew.hub_cell


func _ready() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 4  # [v7look] under the HUD (5): the overlay's shade dims the world, never the HUD
	add_child(cl)
	overlay = CommandOverlay.new()
	overlay.cmd = self
	cl.add_child(overlay)


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
		_pad_paint = 0
		painted_now = 0
		if not roles().has(role):
			role = "clean"
		if lumi_input:
			lumi_input.enabled = not on
		if not on and cam:
			cam.recenter_command()
	if on and input_enabled and InputMap.has_action("move_left"):
		cam.pan_command(Input.get_vector("move_left", "move_right", "move_forward", "move_back"), _delta)
	if not on or cam.camera == null:
		hover_cell = -1
		return
	var vp: Viewport = cam.get_viewport()
	if vp == null:
		return
	var at: Vector2 = vp.get_visible_rect().size * 0.5 if using_pad else vp.get_mouse_position()  # [v3qa]
	hover_cell = pick_cell(cam.camera, at, surface, grid)
	var paint: int = _pad_paint if using_pad else _paint
	if paint != 0 and hover_cell >= 0 and crew:
		if paint > 0 and not (crew.zones.get(role, {}) as Dictionary).has(hover_cell):
			painted_now += 1
		crew.set_zone_cell(role, hover_cell, paint > 0)
	hover_unit = _unit_near(at, 26.0) if crew != null and paint == 0 else {}


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or not is_active():
		return
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.4):
		using_pad = true  # [v3qa]
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 2.0 or event is InputEventMouseButton:
		using_pad = false
		_pad_paint = 0
	if event is InputEventJoypadButton:  # [v3qa] A paint, X erase, Y next role
		var jb: InputEventJoypadButton = event
		match jb.button_index:
			JOY_BUTTON_A:
				_pad_paint = 1 if jb.pressed else (0 if _pad_paint == 1 else _pad_paint)
			JOY_BUTTON_X:
				_pad_paint = -1 if jb.pressed else (0 if _pad_paint == -1 else _pad_paint)
			JOY_BUTTON_Y:
				if jb.pressed:
					next_role()
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
		next_role()
	elif event.is_action_pressed("interact"):
		cam.recenter_command()


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


## [v6crew] The robot drawn nearest a screen point, within `px` pixels ({} if none).
func _unit_near(at: Vector2, px: float) -> Dictionary:
	var best: Dictionary = {}
	var bd: float = px
	for u: Dictionary in crew.robots():
		var p: Vector3 = surface.ground(crew.unit_dir(u))
		var sp: Variant = CommandOverlay.screen_of(cam.camera, surface, p + surface.up_at(p) * 0.8)
		if sp == null:
			continue
		var d: float = (sp as Vector2).distance_to(at)
		if d < bd:
			bd = d
			best = u
	return best
