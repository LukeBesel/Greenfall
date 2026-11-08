class_name HubHop
extends Node3D
## [orbD] The rocket hop between hubs on the same globe: no scene change. Lumi boards the ship on
## this hub's rocket_pad anchor, it lifts off along the local up, cruises a great-circle arc over
## the curve (altitude grows with the distance, so the horizon bends away), and lands on the
## other site's rocket_pad; Lumi steps off beside it. The target site's prefab and ground chunks
## are built during the cruise (Lumi's position is carried with the ship, so the streamer and
## SiteManager follow it).
## Travel time grows gently with distance (owner, Nov 8: big later planets must not feel slower):
## T = clamp(5 + d / 450 m, 7, 15) s, so a 1.7 km hop on Verdance takes ~9 s and a 3 km hop on
## Anvil ~12 s.
## Use: var h := HubHop.new(); globe.add_child(h); await h.hop(globe, from_i, to_i)
## The globe needs: lumi (Patch with sphere_motor), cam (SphereCam), terrain, site_manager.
## Dev: --orbit-hop=N (hop to hub N once the globe is up; --orbit-hop=N,M hops back to M after).

signal hopped(to_hub: int)

const MIN_T: float = 7.0
const MAX_T: float = 15.0

var ship: ShipModel
var flying: bool = false
var progress: float = 0.0
var _focus: Node3D


static func duration(dist_m: float) -> float:
	return clampf(5.0 + dist_m / 450.0, MIN_T, MAX_T)


## Peak cruise altitude above the ground (m) for a hop of dist_m.
static func cruise_alt(dist_m: float) -> float:
	return clampf(dist_m * 0.06, 50.0, 300.0)  # low enough that the curve stays gentle and the ground stays near


## Altitude profile 0..1 -> m: a quick climb, a long cruise, a soft landing.
static func alt_at(t: float, peak: float) -> float:
	var up: float = smoothstep(0.0, 0.3, t)
	var down: float = 1.0 - smoothstep(0.72, 1.0, t)
	return peak * minf(up, down)


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
	var dist: float = dir_a.angle_to(dir_b) * terrain.R
	var T: float = duration(dist)
	var peak: float = cruise_alt(dist)
	ship = ShipModel.new()
	ship.name = "HopShip"
	add_child(ship)
	ship.build(int(GameState.get("rocket_tier")) if GameState.get("rocket_tier") != null else 1)
	ship.global_transform = a
	_focus = Node3D.new()
	_focus.name = "HopFocus"
	add_child(_focus)
	var old_target: Node3D = cam.target
	var old_dist: float = cam.distance
	var old_max: float = cam.max_distance
	cam.target = _focus
	cam.max_distance = 60.0
	cam.distance = 18.0
	lumi.visible = false
	lumi.process_mode = Node.PROCESS_MODE_DISABLED
	Audio.play("whoosh", 0.7, -4.0)
	EventBus.toast.emit(tr("Rocket hop: %.1f km") % (dist / 1000.0), "info")
	var axis: Vector3 = dir_a.cross(dir_b).normalized()
	var ang: float = dir_a.angle_to(dir_b)
	var built_target: bool = false
	var t: float = 0.0
	var prev := a.origin
	while t < T:
		var dt: float = get_process_delta_time()
		t += dt
		progress = clampf(t / T, 0.0, 1.0)
		# Hold on the pad for a moment, then the arc (eased so it leaves and arrives slowly).
		var k: float = smoothstep(0.08, 0.92, progress)
		var d: Vector3 = dir_a.rotated(axis, ang * k) if ang > 0.0001 else dir_a
		var ground: Vector3 = terrain.ground(d)
		if k >= 1.0:
			ground = b0.origin
		var pos: Vector3 = ground + d * alt_at(progress, peak)
		var up: Vector3 = d
		var fwd: Vector3 = (pos - prev)
		fwd = (fwd - up * fwd.dot(up))
		if fwd.length() < 0.001:
			fwd = (dir_b - up * dir_b.dot(up))
		var bas := Basis.looking_at(fwd.normalized(), up)
		ship.global_transform = Transform3D(bas, pos)
		ship.set_lift(1.0 - smoothstep(0.85, 1.0, progress) if progress > 0.5 else smoothstep(0.0, 0.1, progress))
		_focus.global_position = pos + up * 2.0
		lumi.global_position = pos
		prev = pos
		if not built_target and progress > 0.35:
			built_target = true
			var p: SitePrefab = sm.build_hub(to_i)
			if not p.is_built:
				await p.rebuilt
		await get_tree().process_frame
	# Landed: Lumi steps off beside the ship, on the target's pad.
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
	# The ship stays parked on the pad until the next hop.
	var keep: ShipModel = ship
	ship = null
	keep.name = "ParkedShip"
	for c: Node in get_children():
		if c is ShipModel and c != keep:
			c.queue_free()
	return true
