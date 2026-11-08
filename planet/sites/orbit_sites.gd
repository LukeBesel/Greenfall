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
	if bool(GameState.flags.get("arrived_from_rocket", false)) or DevHooks.has("orbit-arrive"):
		GameState.flags.erase("arrived_from_rocket")
		_arrive.call_deferred()
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
		EventBus.toast.emit(tr("The Homeward launch leaves from the flat Cradle site for now."), "info")
		return false
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


func _arrive() -> void:
	await get_tree().create_timer(0.3).timeout
	var ok: bool = await hop.arrive_with(sm, so.w.get("patch"), so.cam, so.globe.terrain, 0)
	print("[hop] arrived on %s start site: %s" % [so.globe.planet_id, "ok" if ok else "FAIL"])


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
