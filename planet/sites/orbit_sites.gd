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
	return await hop.hop_with(sm, so.w.get("patch"), so.cam, so.globe.terrain, from_i, clampi(i, 0, sm.sites.size() - 1))


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
