# Parked with the travel layer (M1-08). These were methods of HubHop (planet/sites/hub_hop.gd): the
# interplanet departure and arrival legs. Paste them back into that class to restore them; they use
# its _leg, _fade, _take_parked, _veil, _focus, ship, flying, hopped and the VEIL / LEG_M / CRUISE_ALT constants.

## Drops the veil at once (a cinematic takes over the screen).
func clear_veil() -> void:
	if _veil:
		_veil.get_parent().queue_free()
		_veil = null


func _veil_now(a: float) -> void:
	if _veil == null:
		var cl := CanvasLayer.new()
		cl.layer = 90
		add_child(cl)
		_veil = ColorRect.new()
		_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
		_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cl.add_child(_veil)
	_veil.color = Color(VEIL.r, VEIL.g, VEIL.b, a)

## Interplanet departure from hub i's pad: lift off, head out low, then the veil covers the
## screen and stays (the caller switches worlds). The ship is left in place for the scene change.
func depart_with(sm: SiteManager, lumi: Patch, cam: SphereCam, terrain: SphereTerrain, from_i: int) -> bool:
	if flying or sm == null or lumi == null or cam == null or terrain == null:
		return false
	flying = true
	var a: Transform3D = sm.pad_xf(from_i)
	var dir_a: Vector3 = a.origin.normalized()
	var axis: Vector3 = SphereGrid.frame(dir_a).x
	_board(a, lumi, cam)
	Audio.play("whoosh", 0.6, -2.0)
	await _leg(dir_a, axis, 0.0, LEG_M / terrain.R, true, terrain, lumi, a.origin)
	await _fade(1.0)
	flying = false
	return true


## Interplanet arrival on hub i's pad (the new globe's start site): the veil lifts on a low
## approach and the ship lands; Lumi steps off beside it.
func arrive_with(sm: SiteManager, lumi: Patch, cam: SphereCam, terrain: SphereTerrain, to_i: int) -> bool:
	if flying or sm == null or lumi == null or cam == null or terrain == null:
		return false
	flying = true
	var b0: Transform3D = sm.pad_xf(to_i)
	var dir_b: Vector3 = b0.origin.normalized()
	var axis: Vector3 = SphereGrid.frame(dir_b).x
	var a0: float = -LEG_M / terrain.R
	var dir_a: Vector3 = dir_b.rotated(axis, a0)
	_board(Transform3D(SphereGrid.frame(dir_a), terrain.ground(dir_a) + dir_a * CRUISE_ALT), lumi, cam)
	_veil_now(1.0)
	await _fade(0.0, true)
	await _leg(dir_a, axis, 0.0, -a0, false, terrain, lumi, b0.origin)
	_step_off(sm, lumi, cam, terrain, to_i)
	flying = false
	hopped.emit(to_i)
	return true


func _board(at: Transform3D, lumi: Patch, cam: SphereCam) -> void:
	ship = _take_parked()  # [v2map]
	ship.global_transform = at
	_focus = Node3D.new()
	_focus.name = "HopFocus"
	add_child(_focus)
	_saved_cam = [cam.distance, cam.max_distance]
	cam.target = _focus
	cam.max_distance = 40.0
	cam.distance = 16.0
	lumi.visible = false
	lumi.process_mode = Node.PROCESS_MODE_DISABLED


var _saved_cam: Array = [6.2, 26.0]


func _step_off(sm: SiteManager, lumi: Patch, cam: SphereCam, terrain: SphereTerrain, to_i: int) -> void:
	var b: Transform3D = sm.pad_xf(to_i)
	ship.global_transform = b
	ship.set_lift(0.0)
	var step: Vector3 = b * Vector3(4.5, 0, 3.0)
	var north: Vector3 = -SphereGrid.frame(step.normalized()).z
	lumi.process_mode = Node.PROCESS_MODE_INHERIT
	lumi.visible = true
	lumi.place_on_sphere(terrain.ground(step.normalized()), north)
	cam.target = lumi
	cam.distance = float(_saved_cam[0])
	cam.max_distance = float(_saved_cam[1])
	cam.reset_frame(north)
	cam.snap()
	if _focus:
		_focus.queue_free()
		_focus = null
	Audio.play("thud", 1.0, -6.0)
	var keep: ShipModel = ship  # parked on the pad until the next hop
	ship = null
	keep.name = "ParkedShip"
	for c: Node in get_children():
		if c is ShipModel and c != keep:
			c.queue_free()

