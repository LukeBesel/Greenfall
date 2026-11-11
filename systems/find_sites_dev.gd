class_name FindSitesDev
extends RefCounted
## Dev flag for renders of the wrecks and buried finds (listed in autoload/DevHooks.gd):
##   --find-shot=<id>[:<state>]   put Lumi beside a wreck or tease of the planet's finds table
##       once the world is up. state: buried (default: under its junk), cleared (junk pulled off),
##       salvaged (pieces taken, the found moment over), reveal (Lumi salvages it once the town
##       stands, or at --find-shot-at=S wall-clock seconds; the found moment is held on screen
##       and the shot's camera turns to Lumi)
##   --find-shot=ping[:<find id>] lay a buried find (the first of the table by default) in the
##       soil a few metres from Lumi, so the detector pings it (use with --detector-on)
##   --find-shot-m=M              how far Lumi stands from it (default 3.4; 30 for a distance view)
##   --find-shot-side=DEG         the side she stands on, in degrees round the wreck (default 200)
##   --find-shot-cam=D,H[,TURN]   the shot's own camera (a ping uses the follow camera unless given): D m from the spot, H m up, TURN degrees
##                                round from Lumi's side (default 4.4,1.9,65)
## The city's town is built first, so the wreck stands where it would in play.

const FLAG: String = "find-shot"
const WAIT_S: float = 4.0
const SETTLE_FRAMES: int = 30
const DEFAULT_STAND_M: float = 3.4
const DEFAULT_SIDE_DEG: float = 200.0
const REVEAL_STAND_M: float = 1.8
const REVEAL_HOLD_S: float = 120.0
const REVEAL_CAM_M: float = 3.6
const PING_STAND_M: float = 4.5
const QUIET_TICKS: int = 600
const QUIET_TICK_S: float = 0.25
const DEFAULT_CAM: String = "4.4,1.9,65"
const DEFAULT_CAM_TURN_DEG: float = 65.0


static func run(so: SliceOrbit) -> void:
	var tree: SceneTree = so.w.get_tree()
	await tree.create_timer(WAIT_S).timeout
	var arg: PackedStringArray = DevHooks.get_s(FLAG, "").split(":")
	var id: String = arg[0]
	var state: String = arg[1] if arg.size() > 1 else "buried"
	if id == "ping":
		await _ping(so, state if arg.size() > 1 else "")
		return
	var finds: Finds = so.look_finds
	var sites: FindSites = so.find_sites
	var cell: int = finds.site_cell(id)
	if cell == Finds.NO_CELL:
		push_error("--find-shot: no wreck or tease '%s' on this globe" % id)
		return
	if state == "salvaged":  # taken now, so its found moment is long over by the shot
		finds.take(id)
	var hub: int = so.districts.site_of(sites.district_of(id))
	var sm: SiteManager = so.globe.site_manager
	if hub > 0 and sm:
		var p: SitePrefab = sm.build_hub(hub, true)
		if not p.is_built:
			await p.rebuilt
	var patch: Patch = so.w.get("patch")
	var c: Vector3 = so.globe.field.hex_center(cell)
	patch.place_on_sphere(c + c.normalized() * 0.3, -SphereGrid.frame(c.normalized()).z)
	for k: int in SETTLE_FRAMES:
		await tree.process_frame
	if state == "cleared" or state == "reveal":
		finds.set_cleared(id, int(sites.cfg("junk")))
	var node: Node3D = sites.show_wreck(id)
	_stand(so, node.global_position, DevHooks.get_f("find-shot-m", DEFAULT_STAND_M))
	print("[finds] %s (%s) at hex %d of %s, reach '%s'" % [id, state, cell, sites.district_of(id),
		TargetReach.for_world(so.w, true, node).reach(node.global_position)])
	if state == "reveal":
		var wait: float = DevHooks.get_f("find-shot-at", 0.0) - Time.get_ticks_msec() / 1000.0
		if wait > 0.0:
			await tree.create_timer(wait).timeout
		var by: Vector3 = _beside(so, node.global_position, REVEAL_STAND_M)
		var face: Vector3 = node.global_position - by
		patch.place_on_sphere(by, (face - by.normalized() * face.dot(by.normalized())).normalized())
		sites.use_wreck(id)
		await sites.wreck_salvaged
		var reveal: PieceReveal = so.w.get_node_or_null("PieceReveal") as PieceReveal
		for k: int in SETTLE_FRAMES:
			if reveal == null or not reveal.showing().is_empty():
				break
			await tree.process_frame
		if reveal:
			reveal.hold_for(REVEAL_HOLD_S)
		_aim_at_lumi(so, node.global_position)


## A buried find a few metres from Lumi, in the hex she stands on.
static func _ping(so: SliceOrbit, find_id: String) -> void:
	var finds: Finds = so.look_finds
	var patch: Patch = so.w.get("patch")
	if find_id == "":
		for e: Dictionary in finds.entries():
			if e["where"] == Finds.BURIED and not finds.is_taken(str(e["id"])):
				find_id = str(e["id"])
				break
	var cell: int = so.cell_at(patch.global_position)
	if not finds.surface(find_id, cell):
		push_error("--find-shot=ping: '%s' is not a buried find still to be found" % find_id)
		return
	var node: Node3D = so.find_sites.show_cache(find_id)
	_stand(so, node.global_position, DevHooks.get_f("find-shot-m", PING_STAND_M), DevHooks.has("find-shot-cam"))
	print("[finds] ping %s at hex %d" % [find_id, cell])
	# The detector's readout shares the one message line with the robot's talk: keep the line
	# free so the shot shows the ping.
	var tree: SceneTree = so.w.get_tree()
	for k: int in QUIET_TICKS:
		if Subtitles.current:
			Subtitles.current.clear()
		await tree.create_timer(QUIET_TICK_S).timeout


## Lumi `dist` m from `at` on free ground, facing it, and a camera of the shot's own looking at
## the spot from `cam_turn` degrees further round (the follow camera would put Lumi in the way).
static func _stand(so: SliceOrbit, at: Vector3, dist: float, own_cam: bool = true) -> void:
	var patch: Patch = so.w.get("patch")
	var up: Vector3 = at.normalized()
	var fr: Basis = SphereGrid.frame(up)
	var t: TargetReach = TargetReach.for_world(so.w, true)
	var side: float = deg_to_rad(DevHooks.get_f("find-shot-side", DEFAULT_SIDE_DEG))
	for k: int in 12:  # the first free side, turning from the one asked for
		var a: float = side + TAU * float(k) / 12.0
		if t == null or t.is_free((at + (fr.x * cos(a) + fr.z * sin(a)) * dist).normalized()):
			side = a
			break
	var stand: Vector3 = so.globe.terrain.ground((at + (fr.x * cos(side) + fr.z * sin(side)) * dist).normalized())
	var s_up: Vector3 = stand.normalized()
	var to: Vector3 = at - stand
	to = (to - s_up * to.dot(s_up)).normalized()
	patch.place_on_sphere(stand + s_up * 0.3, to)
	so.cam.reset_frame(to)
	so.cam.snap()
	if not own_cam:  # the follow camera: Lumi, her detector readout and the prompt in view
		return
	var view: PackedStringArray = DevHooks.get_s("find-shot-cam", DEFAULT_CAM).split(",")
	var turn: float = side + deg_to_rad(float(view[2]) if view.size() > 2 else DEFAULT_CAM_TURN_DEG)
	var eye := Camera3D.new()
	eye.name = "FindShotCam"
	eye.fov = 50.0
	so.w.add_child(eye)
	var from: Vector3 = at + (fr.x * cos(turn) + fr.z * sin(turn)) * float(view[0]) + up * (float(view[1]) if view.size() > 1 else 1.8)
	eye.look_at_from_position(from, at + up * 0.45, up)
	eye.make_current()


## A free spot on the ground `dist` m from `at`, on the side Lumi stands now.
static func _beside(so: SliceOrbit, at: Vector3, dist: float) -> Vector3:
	var patch: Patch = so.w.get("patch")
	var up: Vector3 = at.normalized()
	var off: Vector3 = patch.global_position - at
	off = (off - up * off.dot(up)).normalized() * dist
	var g: Vector3 = so.globe.terrain.ground((at + off).normalized())
	return g + g.normalized() * 0.3


## The shot's camera in front of Lumi, the wreck at her side: the found moment is on her.
static func _aim_at_lumi(so: SliceOrbit, wreck_at: Vector3) -> void:
	var patch: Patch = so.w.get("patch")
	var eye: Camera3D = so.w.get_node_or_null("FindShotCam") as Camera3D
	if eye == null:
		return
	var at: Vector3 = patch.global_position
	var up: Vector3 = at.normalized()
	var to_wreck: Vector3 = wreck_at - at
	to_wreck = (to_wreck - up * to_wreck.dot(up)).normalized()
	var side: Vector3 = up.cross(to_wreck).normalized()
	var from: Vector3 = at + (side * 0.8 - to_wreck * 0.35).normalized() * REVEAL_CAM_M + up * 1.3
	eye.look_at_from_position(from, at + up * 0.55 + to_wreck * 0.5, up)
