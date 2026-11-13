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
	_build_stations()
	_build_litter()
	_build_hinterland()  # [v3city]
	_build_water()
	if DevHooks.has("soak"):  # dev QA soak (planet/sites/soak_watch.gd)
		SoakWatch.attach(so)
	if DevHooks.has("site-reach"):
		_reach_audit.call_deferred()
	if DevHooks.has("city-walk"):  # [v3city] dev: walk check of the start town (planet/sites/city_walk.gd)
		CityWalk.run_dev(so)
	if DevHooks.has("spot-probe"):  # [v8fix] dev: what encloses a spot (planet/sites/spot_probe.gd)
		SpotProbe.run_dev.call_deferred(so)
	if DevHooks.has("seed-walk"):  # [v8seed] dev: the first seed played with real input (tools/seed_walk.gd)
		SeedWalk.run_dev(so)
	if DevHooks.has("walk-goals"):  # [v9d] dev: every goal can complete, one of each kind played with real input (tools/walk_goals.gd)
		WalkGoals.run_dev(so)
	if DevHooks.has("step-shots"):  # [v9d] dev: a rendered frame as each story step starts (tools/step_shots.gd)
		StepShots.run_dev(so)
	if DevHooks.has("walk-home"):  # [v9b] dev: the home steps after the first robot, real input (tools/walk_home.gd)
		WalkHome.run_dev(so)
	if DevHooks.has("target-reach"):  # [v4world] dev: every collectible and objective target reachable (planet/sites/target_audit.gd)
		TargetAudit.run_dev(so)
	if DevHooks.has("planet-smoke"):  # [v7planet] dev: any planet boots, walks, hops, wakes, saves (planet/sites/planet_smoke.gd)
		PlanetSmoke.run_dev(so)
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


## [v2map] Owner note 40: the survey map (M) is only a map. Travel is at the rocket: it stands on
## the pad of the hub Lumi last landed at (from the base level in data/hub.json "rocket_level", or once Lumi
## has flown), and E there opens the destination list (ui/rocket_picker.gd): the other hubs on
## this globe (a rocket hop), other planets once the system is open, and the Homeward launch.
## Dev: --orbit-survey-launch=N still flies to the Nth hub in that list; --rocket parks it at once.
var picker: RocketPicker
var purpose: HubPurpose  # [v6hubs]
var keepers: BaseKeepers  # [v6pace]
var rocket_spot: Node3D
var _site_hub: Dictionary = {}  # site index -> planet.hubs index


func _wire_survey() -> void:
	if sm == null:
		return
	var pl: PlanetData = so.globe.planet
	for k: int in pl.hubs.size():
		for i: int in sm.sites.size():
			if int(sm.sites[i]["cell"]) == pl.hubs[k]:
				_site_hub[i] = k
	var gv: Variant = so.w.get("globe")
	if gv is GlobeView:
		(gv as GlobeView).travel_in_map = false
	picker = RocketPicker.new()
	picker.name = "RocketPicker"
	so.w.add_child(picker)
	picker.entries_fn = destinations
	picker.blocker_fn = func() -> String: return tr("The rocket is in flight.") if hop.flying or bool(so.w.get("launching")) else ""
	picker.planets_open = func() -> bool: return Homeward.system_open()
	picker.open_planets = _open_planets
	picker.home_ready = func() -> bool: return HomewardDirector.home_ready(so.w)
	picker.launch_home = func() -> void: HomewardDirector.launch_home(so.w)
	picker.picked.connect(func(site: int) -> void: hop_to(site))
	picker.closed.connect(func() -> void:
		if not hop.flying and not (so.layers and so.layers.system_map and so.layers.system_map.is_open):
			so.on_modal_closed())
	rocket_spot = Node3D.new()
	rocket_spot.name = "RocketSpot"
	add_child(rocket_spot)
	_register_rocket()
	hop.hopped.connect(func(to_i: int) -> void:
		GameState.orbit["rocket_site"] = to_i
		GameState.orbit["rocket_owned"] = true
		var flown: Array = GameState.orbit.get("hubs_flown", [])  # [v5play] the "Launch the rocket onward" goal counts these
		if not flown.has(to_i):
			flown.append(to_i)
		GameState.orbit["hubs_flown"] = flown)
	purpose = HubPurpose.attach(self)  # [v6hubs] every hub's purpose: arrival, local steps, the wake
	keepers = BaseKeepers.attach(self)  # [v6pace] woken bases clean their own region while Lumi is away
	picker.planet_line_fn = func() -> String: return tr("Bases restored: %d of %d") % [HubPlan.restored_main(sm.planet_id), HubPlan.main_total(sm.planet_id)] if HubPlan.has_plan(sm.planet_id) else ""
	_sync_rocket()
	if DevHooks.has("orbit-rocket-open"):  # dev: open the rocket's list after T s; prints its rows
		get_tree().create_timer(DevHooks.get_f("orbit-rocket-open", 3.0)).timeout.connect(func() -> void:
			_sync_rocket()
			open_rocket()
			print("[rocket] parked %s at site %d, list %s, prompt '%s'" % [rocket_spot.visible, rocket_site(), str(picker.offered_sites()), rocket_prompt()])
			if DevHooks.has("hop-shots"):  # [v6hubs] dev: a picture of the list
				get_tree().create_timer(0.6, true, false, true).timeout.connect(func() -> void:
					await RenderingServer.frame_post_draw
					DevHooks.save_viewport("%s_picker.png" % DevHooks.get_s("hop-shots", "screenshots/hop")))
			for e: Dictionary in destinations():  # [v6hubs]
				print("[rocket]   site %d: %s | %s | %s | %s | %s%s" % [int(e["site"]), e["name"], e.get("town", ""), e.get("offer", ""), e.get("state", ""), e.get("robots", ""), " | " + str(e["tag"]) if str(e.get("tag", "")) != "" else ""]))
	if DevHooks.has("orbit-survey-launch"):  # dev: fly to the Nth hub of the rocket's list
		await get_tree().create_timer(1.0).timeout
		var keys: Array = picker.offered_sites()
		if keys.is_empty():
			print("[hop] rocket list empty")
			return
		var pick: int = int(keys[clampi(int(DevHooks.get_f("orbit-survey-launch", 1.0)), 0, keys.size() - 1)])
		print("[hop] rocket list %d hubs (at site %d), flying to site %d" % [keys.size(), rocket_site(), pick])
		hop_to(pick)


## Whether Lumi has a rocket on this globe: the base level `Hub.rocket_level()` builds it,
## and once Lumi has flown (a hop or an arrival from another planet) it travels with him.
func rocket_unlocked() -> bool:
	var hub: Variant = so.w.get("hub")
	return DevHooks.has("rocket") or bool(GameState.orbit.get("rocket_owned", false)) \
		or (hub is Hub and Hub.rocket_open((hub as Hub).level))


## The hub whose pad the rocket stands on (the last landing, else the start site).
func rocket_site() -> int:
	return clampi(int(GameState.orbit.get("rocket_site", 0)), 0, maxi(sm.sites.size() - 1, 0)) if sm else 0


func rocket_prompt() -> String:
	return tr("E   Rocket: choose a destination")


func open_rocket() -> void:
	if picker == null or picker.is_open or hop.flying:
		return
	so.set_input(false)
	picker.open()


## The rocket's list: [{site, name, km, town, offer, state, robots, tag, home, next}].
## [v6hubs] With a hub plan (data/planets.json hubs): home first, then the next hub of the path,
## then the other hubs the plan lists (restored or visited, extras once the path is done), nearest
## first, never capped. Without one: the six nearest hubs.
func destinations() -> Array:
	var out: Array = []
	if sm == null:
		return out
	var from_i: int = rocket_site()
	var here: Vector3 = sm.pad_xf(from_i).origin.normalized()
	var R: float = so.globe.terrain.R
	var plan: bool = HubPlan.has_plan(sm.planet_id)
	var next_i: int = HubPlan.next_site(sm.planet_id) if plan else -1
	for i: int in sm.sites.size():
		if i == from_i or (not _site_hub.is_empty() and not _site_hub.has(i)):
			continue
		if plan and not HubPlan.listed(sm.planet_id, i):
			continue
		var d: Vector3 = (sm.sites[i]["transform"] as Transform3D).origin.normalized()
		var e: Dictionary = {"site": i, "name": site_name(i), "km": here.angle_to(d) * R / 1000.0}
		if plan and not HubPlan.entry(sm.planet_id, i).is_empty():
			var he: Dictionary = HubPlan.entry(sm.planet_id, i)
			e["home"] = HubPlan.is_home(sm.planet_id, i)
			e["next"] = i == next_i and HubPlan.is_main(sm.planet_id, i)
			e["town"] = purpose.town_name(i) if purpose else HubPlan.town_name(sm.planet_id, i)
			e["offer"] = tr(str(he.get("desc", "")))
			e["state"] = purpose.status_text(i) if purpose else ""
			e["robots"] = purpose.crew_line(i) if purpose else ""
			e["tag"] = tr("HOME") if bool(e["home"]) else (tr("NEXT STOP") if bool(e["next"]) else "")
			if not bool(e["home"]) and not HubPlan.woken(i) and not HubPlan.seen(i) and HubPlan.at_limit(sm.planet_id):
				e["locked"] = tr("Upgrade the rocket first")  # the rocket's tier (RocketTiers.hub_limit)
		out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra: int = 0 if bool(a.get("home", false)) else (1 if bool(a.get("next", false)) else 2)
		var rb: int = 0 if bool(b.get("home", false)) else (1 if bool(b.get("next", false)) else 2)
		return ra < rb if ra != rb else float(a["km"]) < float(b["km"]))
	return out if plan else out.slice(0, 6)


func site_name(i: int) -> String:
	var pn: String = HubPlan.hub_name(sm.planet_id, i) if sm else ""  # [v6hubs] the hub's own name
	if pn != "":
		return pn
	var pl: PlanetData = so.globe.planet
	if _site_hub.has(i):
		var cell: int = pl.hubs[int(_site_hub[i])]
		if pl.city[cell] >= 0:
			return tr(str(pl.cities[pl.city[cell]]["name"]))
		return tr("%s site") % PlanetData.BIOMES[pl.biome[cell]].capitalize().replace("_", " ")
	return tr("Hub %d") % i


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


## Keeps the parked rocket on its pad (shown once unlocked and the pad's site is built).
func _sync_rocket() -> void:
	if rocket_spot == null or sm == null:
		return
	var i: int = rocket_site()
	var p: SitePrefab = sm.prefab(i)
	var on: bool = rocket_unlocked() and p != null and p.is_built and p.is_inside_tree()
	rocket_spot.visible = on
	if hop.flying:
		return
	var ship: ShipModel = hop.parked()
	if not on:
		if ship:
			ship.visible = false
		return
	var xf: Transform3D = sm.pad_xf(i)
	rocket_spot.global_transform = xf
	if ship == null:
		ship = hop.park(xf, int(GameState.flags.get("rocket_tier", 1)))
	ship.visible = true
	if ship.global_position.distance_to(xf.origin) > 0.5:
		ship.global_transform = xf


var _rocket_t: float = 0.0
var _rocket_registered: bool = false


## [v9c] The rocket's E entry. This runs (deferred) before the yard's Interactables exist, so the
## entry never took and E at the rocket did nothing: no way to fly at all with real input (the bot
## and the hub walkthrough call hop_to). Retried from _process until it takes, as HubPurpose does.
func _register_rocket() -> bool:
	if _rocket_registered or rocket_spot == null:
		return _rocket_registered
	var ia: Variant = so.w.get("interactables")
	if ia is Interactables:
		(ia as Interactables).register(rocket_spot, 6.5, rocket_prompt, open_rocket, func() -> bool: return rocket_spot.visible and not hop.flying)
		_rocket_registered = true
	return _rocket_registered


func _process(delta: float) -> void:
	if not _late_q.is_empty():  # [v6qa]
		_sweep_late_step()
	_rocket_t += delta
	if _rocket_t >= 0.5:
		_rocket_t = 0.0
		_register_rocket()
		_sync_rocket()


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
		if d is Depot:
			(d as Depot).seat_bin(p)  # [v3clear]
		if stations:
			stations.transform = (d as Node3D).transform * Transform3D(Basis(), Vector3(0, 0, 1.8))


## Ground litter on junk cells near Lumi (planet/sites/sphere_litter.gd, the flat LitterView's
## carpet); the slice's `litter`, so Patch's scoop sweeps it. --no-litter turns it off.
var litter: SphereLitter


## [v3city] The land between the hub towns (planet/sites/hinterland.gd), Verdance only.
var hinterland: Hinterland


func _build_hinterland() -> void:
	if sm == null or not PlanetCfg.has_hinterland(sm.planet_id) or DevHooks.has("no-hinterland"):  # [v7planet] towns planets (data/planets.json hinterland)
		return
	var hubs: Array[Vector3] = []
	for s: Dictionary in sm.sites:
		hubs.append((s["dir"] as Vector3).normalized())
	hinterland = Hinterland.new()
	hinterland.name = "Hinterland"
	so.w.add_child(hinterland)
	hinterland.setup(sm.grid, sm.terrain, sm.cells, hubs, int(so.globe.get("seed_value")) if so.globe.get("seed_value") != null else 4471,
		so.globe.call("yard_keep_out") as YardKeepOut if so.globe.has_method("yard_keep_out") else null)
	hinterland.focus = so.w.get("patch")
	hinterland.keep_out_late.connect(_sweep_late_keep_out)  # [v6qa]
	if DevHooks.has("hinter-walk") or DevHooks.has("hinter-walk-at"):  # [v5play] dev: walk check of the hinterland (planet/sites/hinter_walk.gd)
		HinterWalk.run_dev(so, hinterland)
	var fld: Variant = so.globe.get("field")  # [v5look] no junk mounds on the hinterland's roads
	if fld is SphereField:
		(fld as SphereField).pile_block = hinterland.is_track_cell
		(fld as SphereField).before_lay = hinterland.ensure_decided  # [v6qa] roads and buildings decided before junk is laid there
	if DevHooks.has("hinter-goto"):  # [v5look] dev: stand Lumi by the nearest track / house / works (renders)
		hinterland.rebuilt.connect(func() -> void:
			var a: PackedStringArray = DevHooks.get_s("hinter-goto", "track").split(",")
			var lumi: Node3D = so.w.get("patch")
			var spot: Array = hinterland.dev_spot(a[0], lumi.global_position, float(a[1]) if a.size() > 1 else 14.0, float(a[2]) if a.size() > 2 else 0.0)
			if spot.size() == 2:
				var at: Vector3 = spot[0]
				(lumi as Patch).place_on_sphere(at.normalized() * (sm.terrain.R + sm.terrain.height(at.normalized()) + 0.6), spot[1])
				so.cam.reset_frame(spot[1])
				so.cam.snap(), CONNECT_ONE_SHOT)
	if DevHooks.has("hinter-report"):
		get_tree().create_timer(DevHooks.get_f("hinter-report", 20.0)).timeout.connect(func() -> void:
			print("[hinter] %s nearest %s" % [str(hinterland.stats), hinterland.debug_nearest(sm.grid.cell_at((so.w.get("patch") as Node3D).global_position))]))  # [v5look]
	if DevHooks.has("keepout-junk"):  # [v6qa] dev: live junk lying in the keep-out (roads, footprints) round Lumi
		get_tree().create_timer(DevHooks.get_f("keepout-junk", 20.0)).timeout.connect(func() -> void:
			print("[keepout] %d live pieces in the keep-out within 120 m, %d moved off late" % [keep_out_junk(120.0), moved_off_roads]))


## [v6qa] Live pieces of made cells within r_m of Lumi whose spot is in the junk keep-out.
func keep_out_junk(r_m: float) -> int:
	var fld: SphereField = so.globe.get("field") as SphereField
	var lumi: Node3D = so.w.get("patch")
	if fld == null or lumi == null or not fld.keep_out.is_valid():
		return -1
	var n: int = 0
	for c: int in sm.grid.cells_within(lumi.global_position.normalized(), r_m):
		if fld.materialized[c] == 0:
			continue
		for pid: int in fld.pieces_in(c):
			if fld.piece_alive[pid] == 1 and bool(fld.keep_out.call(fld.piece_pos[pid].normalized())):
				n += 1
	return n


## [v6qa] The hinterland decided roads or buildings over cells whose junk was already made (made
## before the hinterland existed, during the load): that junk moves off them
## (SphereField.relocate_blocked), a few cells a frame (LATE_SWEEP_US).
func _sweep_late_keep_out(late: PackedInt32Array) -> void:
	var fld: SphereField = so.globe.get("field") as SphereField
	if fld == null:
		return
	for c: int in late:
		for c2: int in sm.grid.cells_around(c, 1):
			if fld.materialized[c2] == 1 and not _late_seen.has(c2):
				_late_seen[c2] = true
				_late_q.append(c2)


const LATE_SWEEP_US: int = 1500
var _late_q: Array[int] = []
var _late_seen: Dictionary = {}


func _sweep_late_step() -> void:
	var fld: SphereField = so.globe.get("field") as SphereField
	var jv: SphereJunkView = so.globe.get("junk_view") as SphereJunkView
	var t0: int = Time.get_ticks_usec()
	while not _late_q.is_empty() and Time.get_ticks_usec() - t0 < LATE_SWEEP_US:
		var c: int = _late_q.pop_back()
		_late_seen.erase(c)
		var r: Array = fld.relocate_blocked(c)
		if (r[0] as PackedInt32Array).is_empty() and (r[1] as PackedInt32Array).is_empty():
			continue
		if jv:
			for pid: int in r[0]:
				jv.move_piece(pid, fld.piece_pos[pid])
			for pid: int in r[1]:
				jv.hide_piece(pid)
		so.globe.call("write_cell", c)
		moved_off_roads += (r[0] as PackedInt32Array).size() + (r[1] as PackedInt32Array).size()
	Hitch.mark("late keep-out sweep", t0 if Hitch.on else 0)


var moved_off_roads: int = 0  # [v6qa] (for checks)


func _build_litter() -> void:
	if DevHooks.has("no-litter") or so.w.get("litter") != null:
		return
	litter = SphereLitter.new()
	litter.name = "Litter"
	so.w.add_child(litter)
	so.w.set("litter", litter)
	litter.setup_globe(so.globe)
	if DevHooks.has("litter-report"):
		for k: int in 3:  # three reports, a report-interval apart (a scoop run shows the sweep)
			get_tree().create_timer(DevHooks.get_f("litter-report", 6.0) * (k + 1)).timeout.connect(func() -> void:
				print("[litter] %d cells laid, %d pieces, slowest cell %.1f ms, near-ring fill max %.1f ms" % [litter.get("_cell").size(), litter.piece_count(), litter.build_max_ms, float(so.globe.stats.get("near_fill_max_ms", 0.0))]))  # [v1world] timings


## Lake surfaces on near water cells (planet/sites/sphere_water.gd). --water-report prints a count.
var water: SphereWater


func _build_water() -> void:
	water = SphereWater.new()
	water.name = "Lakes"
	so.w.add_child(water)
	water.world = so.w
	water.setup_globe(so.globe)
	if DevHooks.has("lake-view"):  # [v4world] dev: Lumi on a lake shore (water look renders)
		SphereWater.dev_view(so)
	if DevHooks.has("water-report"):
		get_tree().create_timer(DevHooks.get_f("water-report", 6.0)).timeout.connect(func() -> void:
			print("[water] %d lake cells shown, %d fish" % [water.count(), water.fish_count()]))


## The flat game's Stations (conveyor feeder, auto-baler, recycler: automation/stations.gd) on the
## start site, in a frame that puts the flat depot spot (0, 0, -1.8) on the site's depot: the
## machines and their belts keep their flat layout round the depot, on the globe.
var stations: Stations


func _build_stations() -> void:
	var dep: Node3D = so.w.get("depot") as Node3D
	if dep == null or Stations.of(so.w) != null:
		return
	stations = Stations.new()
	stations.name = "Stations"
	stations.world = so.w
	dep.get_parent().add_child(stations)
	stations.transform = dep.transform * Transform3D(Basis(), Vector3(0, 0, 1.8))
	if "stations" in so.w:
		so.w.set("stations", stations)


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
		if DevHooks.has("quit-on-hop"):  # [v7play] dev: quit in the frame a hop starts (the autoplay stop after a wake; exit 134 repro)
			hop_to(int(h))
			await get_tree().create_timer(DevHooks.get_f("quit-on-hop", 0.0)).timeout if DevHooks.get_f("quit-on-hop", 0.0) > 0.0 else null
			print("[hop] dev: quitting %.2f s into the hop to %s" % [DevHooks.get_f("quit-on-hop", 0.0), h])
			get_tree().quit()
			return
		var t0: int = Time.get_ticks_msec()
		var ok: bool = await hop_to(int(h))
		var patch: Node3D = so.w.get("patch")
		var d: float = patch.global_position.distance_to(sm.pad_xf(int(h)).origin)
		print("[hop] to hub %s: %s in %d ms, %.1f m from its pad, site built %s" % [h, "ok" if ok else "FAIL", Time.get_ticks_msec() - t0, d, sm.prefab(int(h)) != null])
		await get_tree().create_timer(1.0 + (DevHooks.get_f("hub-dev-chain", 3.0) + 2.0 if DevHooks.has("hub-dev-chain") else 0.0)).timeout  # [v6hubs] room for the dev chain


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
		if r.is_empty():
			continue  # [orbE] the site went away while the audit waited
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
