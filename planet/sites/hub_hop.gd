class_name HubHop
extends Node3D
## [orbD] The rocket hop between hubs on the same globe: no scene change, and short.
## Lumi boards the ship on this hub's rocket_pad anchor. It lifts off low (CRUISE_ALT, so the
## ground under it stays detailed terrain and the far shell only shows at the horizon) and
## heads off toward the target. The view then fades out (sky-blue veil). While faded, the ship
## jumps to the far leg, the target's ground chunks settle and its site prefab is built. The view
## fades back in on the approach, and the ship lands on the target's rocket_pad; Lumi steps off
## beside it. Owner (Nov 8): keep it well under 10 s, blue sky, no high-altitude pastel map.
## Flight time is LEG_S out + the fade + LEG_S in (about 7 s plus however long the target
## takes to build behind the veil), whatever the distance, so Anvil's long hops cost the same.
## Use: var h := HubHop.new(); add_child(h); await h.hop_with(site_manager, lumi, cam, terrain, i, j)
## (or h.hop(globe, i, j) when the globe has lumi / cam / terrain / site_manager).
## Dev: --orbit-hop=N[,M] (planet/sites/orbit_sites.gd).

signal hopped(to_hub: int)

const CRUISE_ALT: float = 45.0
## Ground covered on each visible leg (m), and its time (s).
const LEG_M: float = 260.0
const LEG_S: float = 2.8
const FADE_S: float = 0.6
const VEIL := Color(0.66, 0.8, 0.95)

var ship: ShipModel
var flying: bool = false
var progress: float = 0.0
var _focus: Node3D
var _veil: ColorRect


## Seconds a hop is on screen (the build behind the veil comes on top).
static func duration(_dist_m: float = 0.0) -> float:
	return LEG_S * 2.0 + FADE_S * 2.0


## Altitude along a leg 0..1: out leg climbs to CRUISE_ALT, in leg descends from it.
static func leg_alt(t: float, outbound: bool) -> float:
	var k: float = smoothstep(0.0, 0.7, t) if outbound else 1.0 - smoothstep(0.3, 1.0, t)
	return CRUISE_ALT * k


func hop(globe: Node3D, from_i: int, to_i: int) -> bool:
	return await hop_with(globe.get("site_manager"), globe.get("lumi"), globe.get("cam"), globe.get("terrain"), from_i, to_i)


func hop_with(sm: SiteManager, lumi: Patch, cam: SphereCam, terrain: SphereTerrain, from_i: int, to_i: int) -> bool:
	if flying or from_i == to_i:
		return false
	if sm == null or lumi == null or cam == null or terrain == null:
		return false
	flying = true
	var a: Transform3D = sm.pad_xf(from_i)
	var b0: Transform3D = sm.pad_xf(to_i)
	var dir_a: Vector3 = a.origin.normalized()
	var dir_b: Vector3 = b0.origin.normalized()
	var ang: float = dir_a.angle_to(dir_b)
	var axis: Vector3 = dir_a.cross(dir_b).normalized() if ang > 0.0001 else SphereGrid.frame(dir_a).x
	var leg_ang: float = minf(LEG_M / terrain.R, ang * 0.45)
	ship = _take_parked()  # [v2map] the parked rocket lifts off (no twin left on the pad)
	ship.global_transform = a
	_focus = Node3D.new()
	_focus.name = "HopFocus"
	add_child(_focus)
	var old_dist: float = cam.distance
	var old_max: float = cam.max_distance
	cam.target = _focus
	cam.max_distance = 40.0
	cam.distance = 16.0
	lumi.visible = false
	lumi.process_mode = Node.PROCESS_MODE_DISABLED
	Audio.play("whoosh", 0.7, -4.0)
	EventBus.toast.emit(tr("Rocket hop: %.1f km") % (ang * terrain.R / 1000.0), "info")
	# Out leg: lift off and head toward the target.
	await _leg(dir_a, axis, 0.0, leg_ang, true, terrain, lumi, a.origin)
	await _fade(1.0)
	# Behind the veil: carry Lumi to the far leg, settle the ground there, build the site.
	var start_in: float = ang - leg_ang
	var d_in: Vector3 = dir_a.rotated(axis, start_in)
	lumi.global_position = terrain.ground(d_in) + d_in * CRUISE_ALT
	var g: Node = sm.globe
	if g and g.has_method("update_centres"):
		g.call("update_centres")
	var st: Variant = g.get("streamer") if g else null
	if st is SphereStreamer:
		(st as SphereStreamer).settle(6000)
	var p: SitePrefab = sm.build_hub(to_i)
	if not p.is_built:
		await p.rebuilt
	for hf: Node in get_tree().get_nodes_in_group("hub_frame"):  # [v5load] the hub's systems too, while the veil hides the frame
		(hf as HubFrame).switch_to(to_i)
	b0 = sm.pad_xf(to_i)
	await _fade(0.0, true)
	# In leg: approach low and land on the pad.
	await _leg(dir_a, axis, start_in, ang, false, terrain, lumi, b0.origin)
	var b: Transform3D = sm.pad_xf(to_i)
	ship.global_transform = b
	ship.set_lift(0.0)
	var step: Vector3 = b * Vector3(4.5, 0, 3.0)
	var north: Vector3 = -SphereGrid.frame(step.normalized()).z
	lumi.process_mode = Node.PROCESS_MODE_INHERIT
	lumi.visible = true
	lumi.place_on_sphere(terrain.ground(step.normalized()), north)
	cam.target = lumi
	cam.distance = old_dist
	cam.max_distance = old_max
	cam.reset_frame(north)
	cam.snap()
	_focus.queue_free()
	Audio.play("thud", 1.0, -6.0)
	flying = false
	hopped.emit(to_i)
	var keep: ShipModel = ship  # parked on the pad until the next hop
	ship = null
	keep.name = "ParkedShip"
	for c: Node in get_children():
		if c is ShipModel and c != keep:
			c.queue_free()
	return true


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


## [v2map] The rocket parked on a pad (planet/sites/orbit_sites.gd shows it once unlocked), or null.
func parked() -> ShipModel:
	var n: Node = get_node_or_null("ParkedShip")
	return n as ShipModel if n and not n.is_queued_for_deletion() else null


## [v2map] Parks a rocket of this tier on a pad transform; returns it.
func park(xf: Transform3D, tier: int = 1) -> ShipModel:
	var s: ShipModel = parked()
	if s == null:
		s = ShipModel.new()
		s.name = "ParkedShip"
		add_child(s)
		s.build(clampi(tier, 1, 7))
	s.global_transform = xf
	s.set_lift(0.0)
	return s


## [v2map] The ship for a flight: the parked one if there is one, else a new one.
func _take_parked() -> ShipModel:
	var s: ShipModel = parked()
	if s == null:
		s = ShipModel.new()
		add_child(s)
		s.build(clampi(int(GameState.flags.get("rocket_tier", 1)), 1, 7))
	s.name = "HopShip"
	s.visible = true
	return s


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


## One visible leg along the great circle from angle a0 to a1 (radians around `axis` from dir_a).
## The out leg ends in the air; the in leg ends on `land_at`.
func _leg(dir_a: Vector3, axis: Vector3, a0: float, a1: float, outbound: bool, terrain: SphereTerrain, lumi: Node3D, land_at: Vector3) -> void:
	var t: float = 0.0
	var prev: Vector3 = ship.global_position
	while t < LEG_S:
		t += get_process_delta_time()
		var k: float = clampf(t / LEG_S, 0.0, 1.0)
		progress = k * 0.5 + (0.0 if outbound else 0.5)
		var e: float = smoothstep(0.15, 1.0, k) if outbound else smoothstep(0.0, 0.85, k)
		var d: Vector3 = dir_a.rotated(axis, lerpf(a0, a1, e))
		var pos: Vector3 = terrain.ground(d) + d * leg_alt(k, outbound)
		if not outbound and k >= 1.0:
			pos = land_at
		var fwd: Vector3 = pos - prev
		fwd -= d * fwd.dot(d)
		if fwd.length() < 0.001:
			fwd = axis.cross(d)
		ship.global_transform = Transform3D(Basis.looking_at(fwd.normalized(), d), pos)
		ship.set_lift(smoothstep(0.0, 0.25, k) if outbound else 1.0 - smoothstep(0.7, 1.0, k))
		_focus.global_position = pos + d * 2.0
		lumi.global_position = pos
		prev = pos
		await get_tree().process_frame


## Sky-blue veil over the screen (a = 0 clear, 1 covered).
func _fade(to: float, free_after: bool = false) -> void:
	if _veil == null:
		var cl := CanvasLayer.new()
		cl.layer = 90
		add_child(cl)
		_veil = ColorRect.new()
		_veil.color = Color(VEIL.r, VEIL.g, VEIL.b, 0.0)
		_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
		_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cl.add_child(_veil)
	var tw := create_tween()
	tw.tween_property(_veil, "color:a", to, FADE_S)
	await tw.finished
	if free_after and _veil:
		_veil.get_parent().queue_free()
		_veil = null
