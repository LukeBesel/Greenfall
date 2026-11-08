class_name OrbitSites
extends Node
## [orbD] Hub sites, rocket hops and the hover-sled on the real slice-on-globe (scenes/slice_orbit.gd).
## OrbitPlanet.build_start_site() makes the SiteManager and the start yard prefab; this node adds
## what needs Lumi and the camera: the manager's focus, the parked hover-sled, hops, the interact
## prompt, planet %, saving the sites' state, and the dev flags:
##   --orbit-hop=N[,M]   rocket hop to hub N (then M) once the slice is up; prints [hop] lines
##   --orbit-sled[=T]    own the sled at tier T and ride it from the start
## Use: OrbitSites.attach(slice_orbit) after the patch, camera and depot exist.

var so: SliceOrbit
var sm: SiteManager
var sled: HoverSled
var hop: HubHop


static func attach(p_so: SliceOrbit) -> OrbitSites:
	var o := OrbitSites.new()
	o.name = "OrbitSites"
	o.so = p_so
	p_so.w.add_child(o)
	o._setup()
	return o


func _setup() -> void:
	sm = so.globe.site_manager
	var patch: Patch = so.w.get("patch")
	if sm:
		sm.focus_node = patch
		sm.anchors_fixed.connect(_on_anchors_fixed)
	HoverSled.register_upgrade()
	if DevHooks.has("orbit-sled"):
		GameState.upgrades[HoverSled.UPGRADE_ID] = clampi(int(DevHooks.get_f("orbit-sled", 1.0)), 1, 3)
	sled = HoverSled.new()
	sled.name = "HoverSled"
	sled.lumi = patch
	so.w.add_child(sled)
	var p: SitePrefab = sm.prefab(0) if sm else null
	if p:
		var at: Transform3D = p.global_transform * Transform3D(Basis(), p.anchor_local("rocket_pad").origin + Vector3(7.0, 0, 2.0))
		sled.global_transform = Transform3D(at.basis, so.globe.terrain.ground(at.origin.normalized()))
	if DevHooks.has("orbit-sled"):
		sled.mount()
	hop = HubHop.new()
	hop.name = "HubHop"
	so.w.add_child(hop)
	if DevHooks.has("orbit-hop"):
		_dev_hop.call_deferred()
	_wire_survey.call_deferred()
	if DevHooks.has("soak"):  # dev QA soak (planet/sites/soak_watch.gd)
		SoakWatch.attach(so)
	if DevHooks.has("site-reach"):
		_reach_audit.call_deferred()
	if bool(GameState.flags.get("arrived_from_rocket", false)) or DevHooks.has("orbit-arrive"):
		GameState.flags.erase("arrived_from_rocket")
		_arrive.call_deferred()
	if DevHooks.has("orbit-home"):  # dev: --orbit-home, the Homeward launch (drive Mk VII + last seed given)
		Homeward.state()["drive"] = maxi(Homeward.drive(), 7)
		GameState.flags["home_last_seed"] = true
		get_tree().create_timer(2.0).timeout.connect(func() -> void: HomewardDirector.launch_home(so.w))
	if DevHooks.has("orbit-planet-hop"):  # dev: --orbit-planet-hop=K, the interplanet rocket to planet K
		get_tree().create_timer(2.0).timeout.connect(func() -> void: launch_planet(Homeward.PLANET_BASE - int(DevHooks.get_f("orbit-planet-hop", 1.0))))


static func of(world: Node) -> OrbitSites:
	var o: Variant = world.get("orbit") if world else null
	return (o as SliceOrbit).sites if o is SliceOrbit else null


## The survey hologram's launch list (GlobeView): the hub sites on this globe, and a launch is a
## rocket hop (same planet, no scene change).
func _wire_survey() -> void:
	var gv: Variant = so.w.get("globe")
	if not (gv is GlobeView) or sm == null:
		return
	var v: GlobeView = gv
	var pl: PlanetData = so.globe.planet
	var site_hub: Dictionary = {}  # planet.hubs index -> site index
	for k: int in pl.hubs.size():
		for i: int in sm.sites.size():
			if int(sm.sites[i]["cell"]) == pl.hubs[k]:
				site_hub[k] = i
	v.hub_order = func() -> Array:
		var cur: int = sm.nearest if sm.nearest >= 0 else 0
		for k: Variant in site_hub:
			if site_hub[k] == cur:
				v.current_hub = int(k)
		return site_hub.keys()
	v.rocket_ready = func() -> bool: return not hop.flying
	v.rocket_lock_text = func() -> String: return tr("The rocket is in flight.")
	v.launch_to = func(k: int) -> void:
		if site_hub.has(k):
			hop_to(int(site_hub[k]))
	if DevHooks.has("orbit-survey-launch"):  # dev: launch from the survey list to its Nth entry
		var keys: Array = v.hub_order.call()
		var pick: int = int(keys[clampi(int(DevHooks.get_f("orbit-survey-launch", 1.0)), 0, keys.size() - 1)])
		print("[hop] survey list %d hubs (current %d), launching to hub %d (site %d)" % [keys.size(), v.current_hub, pick, int(site_hub[pick])])
		await get_tree().create_timer(1.0).timeout
		v.launch_to.call(pick)


## The interplanet rocket from this globe (SystemMap -> HomewardDirector): lift off from the
## nearest hub's pad, then Homeward switches worlds; the new globe lands Lumi on its start site.
## target: Homeward's launch target (PLANET_BASE - k). The Cradle (HOME) is not on a globe yet.
func launch_planet(target: int) -> bool:
	if target == Homeward.HOME:
		return await launch_home()
	var k: int = Homeward.PLANET_BASE - target
	if sm == null or hop.flying:
		return false
	so.w.set("launching", true)
	GameState.flags["arrived_from_rocket"] = true
	var from_i: int = sm.nearest if sm.nearest >= 0 else 0
	await hop.depart_with(sm, so.w.get("patch"), so.cam, so.globe.terrain, from_i)
	print("[hop] interplanet to %s" % Homeward.planet_name(k))
	if not Homeward.travel_to_planet(k, get_tree()):
		so.w.set("launching", false)
		GameState.flags.erase("arrived_from_rocket")
		return false
	return true


## The Homeward launch from this globe: lift off from the nearest hub's pad, then the real ending
## (Homecoming: the rise to the Cradle, the vault, the finale). Lumi is set back on the pad out
## of sight first, since the finale films him landing in the ark's beam.
func launch_home() -> bool:
	if sm == null or hop.flying:
		return false
	so.w.set("launching", true)
	var from_i: int = sm.nearest if sm.nearest >= 0 else 0
	var patch: Patch = so.w.get("patch")
	await hop.depart_with(sm, patch, so.cam, so.globe.terrain, from_i)
	hop._step_off(sm, patch, so.cam, so.globe.terrain, from_i)
	patch.visible = false
	print("[hop] Homeward launch from %s hub %d" % [so.globe.planet_id, from_i])
	var h: Homecoming = Homecoming.play_now(so.w)
	await get_tree().create_timer(0.5).timeout
	hop.clear_veil()
	so.w.set("launching", false)
	return h != null


func _arrive() -> void:
	await get_tree().create_timer(0.3).timeout
	var ok: bool = await hop.arrive_with(sm, so.w.get("patch"), so.cam, so.globe.terrain, 0)
	print("[hop] arrived on %s start site: %s" % [so.globe.planet_id, "ok" if ok else "FAIL"])


## The start site's depot follows its anchor if it had to move out of the prefab's geometry.
func _on_anchors_fixed(i: int, p: SitePrefab) -> void:
	if i != 0:
		return
	var d: Variant = so.w.get("depot")
	if d is Node3D and (d as Node3D).get_parent() == p.get_parent():
		(d as Node3D).transform = p.anchor_local("depot")


func interact_prompt() -> String:
	var t: String = sled.prompt() if sled else ""
	return ("E   " + t) if t != "" else ""


func planet_fraction() -> float:
	return sm.planet_fraction() if sm else 0.0


## Rocket hop to hub i from the nearest one.
func hop_to(i: int) -> bool:
	if sm == null:
		return false
	var from_i: int = sm.nearest if sm.nearest >= 0 else 0
	var to_i: int = clampi(i, 0, sm.sites.size() - 1)
	var ok: bool = await hop.hop_with(sm, so.w.get("patch"), so.cam, so.globe.terrain, from_i, to_i)
	print("[hop] hub %d -> %d: %s" % [from_i, to_i, "ok" if ok else "refused"])
	return ok


func save_state() -> Dictionary:
	return sm.save_state() if sm else {}


func load_state(d: Dictionary) -> void:
	if sm and not d.is_empty():
		sm.load_state(d)


func _dev_hop() -> void:
	await get_tree().create_timer(1.0).timeout
	for h: String in DevHooks.get_s("orbit-hop", "1").split(","):
		var t0: int = Time.get_ticks_msec()
		var ok: bool = await hop_to(int(h))
		var patch: Node3D = so.w.get("patch")
		var d: float = patch.global_position.distance_to(sm.pad_xf(int(h)).origin)
		print("[hop] to hub %s: %s in %d ms, %.1f m from its pad, site built %s" % [h, "ok" if ok else "FAIL", Time.get_ticks_msec() - t0, d, sm.prefab(int(h)) != null])
		await get_tree().create_timer(1.0).timeout


## Dev: --site-reach. Narrow-gap audit (planet/sites/site_reach.gd) of every hub site on this
## globe, one at a time; prints a [reach] line per hub and quits (1 if an anchor is cut off).
func _reach_audit() -> void:
	await get_tree().create_timer(1.0).timeout
	sm.set_process(false)
	var bad: int = 0
	for i: int in sm.sites.size():
		var p: SitePrefab = sm.build_hub(i, true)
		if not p.is_built:
			await p.rebuilt
		for k: int in 3:
			await get_tree().physics_frame
		await SiteReach.fix_anchors(p, so.globe.terrain)  # as SiteManager does after a build (idempotent) [orbE] a coroutine now
		var t0: int = Time.get_ticks_msec()
		var r: Dictionary = await SiteReach.audit(p, so.globe.terrain)  # [orbE] a coroutine now
		var cut: Array = r["cut"]
		bad += cut.size() + (0 if r["start_free"] else 1)
		print("[reach] %s hub %d %s: %d/%d anchors reachable, %d m2 walkable from the pad%s%s (%d ms)" % [
			so.globe.planet_id, i, p.site_id, (r["anchors"] as Dictionary).size() - cut.size(), (r["anchors"] as Dictionary).size(),
			int(int(r["reachable"]) * SiteReach.STEP * SiteReach.STEP), "" if r["start_free"] else ", LANDING SPOT BLOCKED (%s)" % r["why"],
			"" if cut.is_empty() else ", cut off: " + ", ".join(cut.map(func(nm: String) -> String: return "%s@(%.1f,%.1f)" % [nm, p.anchor_local(nm).origin.x, p.anchor_local(nm).origin.z])), Time.get_ticks_msec() - t0])
		if i > 0:
			sm.free_hub(i)
			await get_tree().process_frame
	print("[reach] %s: %s" % [so.globe.planet_id, "PASS" if bad == 0 else "FAIL (%d)" % bad])
	get_tree().quit(0 if bad == 0 else 1)
