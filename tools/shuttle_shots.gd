class_name ShuttleShots
extends RefCounted
## [art5] Dev: --shuttle-shots=PREFIX (a rendered run, with --rocket): the shuttle on its pad from
## the play camera at noon, dusk and night (a wide and a close frame each), then hops with frames
## at --hop-marks along each leg (planet/sites/hub_hop.gd): 0 -> 1 at noon, back at dusk, out again
## at night. Quits when done. tools/shuttle_shots.sh runs it inside the render lock.
##   --shuttle-shots-start=S  wall seconds before the first frame (default 105)
##   --shuttle-shots-hops=0,2 which of noon / dusk / night get a hop (default 0,1,2)
##   --shuttle-shots-tier=N   the parked ship's look
##   --shuttle-shots-stills=0 skips the pad stills

const TIMES: Array = [["day", 0.5], ["dusk", 0.735], ["night", 0.0]]


static func run_dev(so: Node) -> void:
	var tree: SceneTree = so.get_tree()
	var prefix: String = DevHooks.get_s("shuttle-shots", "screenshots/art/shuttle/x")
	if DevHooks.has("shuttle-shots-tier"):
		GameState.flags["rocket_tier"] = int(DevHooks.get_f("shuttle-shots-tier", 1.0))
	await DevHooks.wait_wall(DevHooks.get_f("shuttle-shots-start", 105.0))
	var os_: OrbitSites = OrbitSites.of(so.get("w"))
	os_._sync_rocket()
	if DevHooks.get_f("shuttle-shots-stills", 1.0) > 0.0:
		for tm: Array in TIMES:
			_time(so, float(tm[1]))
			_stand(so, os_, Vector3(5.0, 0, 8.5), 7.5, -0.22)
			await DevHooks.wait_wall_for(6.0)
			await _save(tree, "%s_pad_%s.png" % [prefix, tm[0]])
			_stand(so, os_, Vector3(-3.6, 0, 4.6), 3.2, -0.12)
			await DevHooks.wait_wall_for(4.0)
			await _save(tree, "%s_close_%s.png" % [prefix, tm[0]])
			# The ship alone (Lumi hidden for the frame): front quarter and tail.
			var patch: Patch = so.get("w").get("patch")
			patch.visible = false
			for hv: Array in [["hero", Vector3(-2.7, 0, 4.7), 0.9, -0.02], ["tail", Vector3(2.9, 0, -4.9), 0.8, -0.03], ["side", Vector3(4.7, 0, 0.3), 0.5, 0.0], ["gear", Vector3(2.6, 0, 2.9), 0.3, -0.01]]:
				_stand(so, os_, hv[1], float(hv[2]), float(hv[3]))
				await DevHooks.wait_wall_for(3.0)
				await _save(tree, "%s_%s_%s.png" % [prefix, hv[0], tm[0]])
			patch.visible = true
	# --shuttle-shots-hops=0,2 picks which of TIMES get a hop (default all three, in order).
	for ks: String in DevHooks.get_s("shuttle-shots-hops", "0,1,2").split(",", false):
		var k: int = clampi(int(ks), 0, TIMES.size() - 1)
		_time(so, float(TIMES[k][1]))
		_stand(so, os_, Vector3(4.5, 0, 3.0), 6.2, -0.3)
		for f: int in 4:
			await tree.process_frame
		os_.hop._shot_done.clear()
		os_.hop.shot_prefix = "%s_%s" % [prefix, TIMES[k][0]]
		var to_i: int = 1 if os_.sm.nearest <= 0 else 0
		var ok: bool = await os_.hop_to(to_i)
		print("[shuttle-shots] hop %d to %d: %s" % [k, to_i, ok])
		await _save(tree, "%s_%s_landed.png" % [prefix, TIMES[k][0]])
		for f: int in 12:
			await tree.process_frame
		os_._sync_rocket()
		_stand(so, os_, Vector3(5.0, 0, 8.5), 7.5, -0.22)
		for f: int in 6:
			await tree.process_frame
		await _save(tree, "%s_%s_after.png" % [prefix, TIMES[k][0]])
	tree.quit()


static func _save(tree: SceneTree, path: String) -> void:
	await RenderingServer.frame_post_draw
	DevHooks.save_viewport(path)
	await tree.process_frame


static func _time(so: Node, t: float) -> void:
	var sky: Variant = so.get("w").get("sky_director")
	var patch: Patch = so.get("w").get("patch")
	if sky is SkyDirector:
		(sky as SkyDirector).time_of_day = t
		(sky as SkyDirector).spin = SkyDirector.spin_for_local_time(t, patch.global_position)
		(sky as SkyDirector).frozen = true


## Lumi at `off` (pad-local metres) looking at the ship, the play camera `dist` behind him.
static func _stand(so: Node, os_: OrbitSites, off: Vector3, dist: float, pitch: float) -> void:
	var globe: OrbitPlanet = so.get("globe")
	var patch: Patch = so.get("w").get("patch")
	var cam: SphereCam = so.get("cam")
	var xf: Transform3D = os_.sm.pad_xf(os_.rocket_site())
	var at: Vector3 = globe.terrain.ground((xf * off).normalized())
	var up: Vector3 = at.normalized()
	var look: Vector3 = xf.origin - at
	look = (look - up * look.dot(up)).normalized()
	patch.place_on_sphere(at, look)
	cam.distance = dist
	cam.pitch = pitch
	cam.reset_frame(look)
	cam.snap()
