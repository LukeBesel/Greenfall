# Parked with the travel layer (M1-08). These were parts of OrbitSites (planet/sites/orbit_sites.gd):
# the dev hooks at the end of _setup(), the rocket list's planet / home wiring in _wire_survey(),
# _open_planets(), launch_planet(), launch_home() and _arrive(). HubHop's interplanet legs are in
# hub_hop_interplanet.gd; RocketPicker's two extra buttons are described in parked/README.md.

# --- end of _setup() ---
#	if bool(GameState.flags.get("arrived_from_rocket", false)) or DevHooks.has("orbit-arrive"):
#		GameState.flags.erase("arrived_from_rocket")
#		_arrive.call_deferred()
#	if DevHooks.has("orbit-home"):  # dev: --orbit-home, the Homeward launch (drive Mk VII + last seed given)
#		Homeward.state()["drive"] = maxi(Homeward.drive(), 7)
#		GameState.flags["home_last_seed"] = true
#		get_tree().create_timer(2.0).timeout.connect(func() -> void: HomewardDirector.launch_home(so.w))
#	if DevHooks.has("orbit-planet-hop"):  # dev: --orbit-planet-hop=K, the interplanet rocket to planet K
#		get_tree().create_timer(2.0).timeout.connect(func() -> void: launch_planet(Homeward.PLANET_BASE - int(DevHooks.get_f("orbit-planet-hop", 1.0))))

# --- _wire_survey(), after picker.blocker_fn ---
#	picker.planets_open = func() -> bool: return Homeward.system_open()
#	picker.open_planets = _open_planets
#	picker.home_ready = func() -> bool: return HomewardDirector.home_ready(so.w)
#	picker.launch_home = func() -> void: HomewardDirector.launch_home(so.w)
#	picker.picked.connect(func(site: int) -> void: hop_to(site))
#	picker.closed.connect(func() -> void:
#		if not hop.flying and not (so.layers and so.layers.system_map and so.layers.system_map.is_open):
#			so.on_modal_closed())

func _open_planets() -> void:
	var m: SystemMap = so.layers.system_map if so.layers else null
	var d: HomewardDirector = HomewardDirector.of(so.w)
	if d and d.map:
		m = d.map
	if m == null:
		so.on_modal_closed()
		return
	m.on_here = open_rocket
	m.open_map(false, true)


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

