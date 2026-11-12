class_name OrbitSites
extends Node
## [orbD] Hub sites, rocket hops and the hover-sled on the real slice-on-globe (scenes/slice_orbit.gd).
## OrbitPlanet.build_start_site() makes the SiteManager and the start yard prefab; this node adds
## what needs Lumi and the camera: the manager's focus, the parked hover-sled, hops, the interact
## prompt, the travel rule, saving the sites' state, and the dev flags:
##   --orbit-hop=N[,M]   rocket hop to hub N (then M) once the slice is up; prints [hop] lines
##   --orbit-sled[=T]    own the sled at tier T and ride it from the start
## Use: OrbitSites.attach(slice_orbit) after the patch, camera and depot exist.

var so: SliceOrbit
var sm: SiteManager
var sled: HoverSled
var hop: HubHop
var charge: RocketCharge


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
	charge = RocketCharge.new()  # Lumi's work in the rocket's city charges its cells faster
	charge.name = "RocketCharge"
	charge.in_city_fn = lumi_in_rocket_city
	add_child(charge)
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
	if DevHooks.has("target-reach"):  # [v4world] dev: every collectible and objective target reachable (planet/sites/target_audit.gd)
		TargetAudit.run_dev(so)


static func of(world: Node) -> OrbitSites:
	return (world.orbit as SliceOrbit).sites


## [v2map] Owner note 40: the survey map (M) is only a map. Travel is at the rocket: it stands on
## the pad of the hub Lumi last landed at (from base level 5, or once Lumi
## has flown), and E there opens the destination list (ui/rocket_picker.gd): the other hubs on
## this globe (a rocket hop).
## Dev: --orbit-survey-launch=N still flies to the Nth hub in that list; --rocket parks it at once.
var picker: RocketPicker
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
	picker.blocker_fn = hop_blocker
	picker.empty_fn = next_city_hint
	picker.picked.connect(func(site: int) -> void: hop_to(site))
	picker.closed.connect(func() -> void:
		if not hop.flying:
			so.on_modal_closed())
	rocket_spot = Node3D.new()
	rocket_spot.name = "RocketSpot"
	add_child(rocket_spot)
	var ia: Variant = so.w.get("interactables")
	if ia is Interactables:
		(ia as Interactables).register(rocket_spot, 6.5, rocket_prompt, open_rocket, func() -> bool: return rocket_spot.visible and not hop.flying)
	hop.hopped.connect(func(to_i: int) -> void:
		GameState.orbit["rocket_site"] = to_i
		GameState.orbit["rocket_owned"] = true)
	_sync_rocket()
	if DevHooks.has("orbit-rocket-open"):  # dev: open the rocket's list after T s; prints its rows
		get_tree().create_timer(DevHooks.get_f("orbit-rocket-open", 3.0)).timeout.connect(func() -> void:
			_sync_rocket()
			open_rocket()
			print("[rocket] parked %s at site %d, list %s, prompt '%s'" % [rocket_spot.visible, rocket_site(), str(picker.offered_sites()), rocket_prompt()]))
	if DevHooks.has("orbit-survey-launch"):  # dev: fly to the Nth hub of the rocket's list
		await get_tree().create_timer(1.0).timeout
		var keys: Array = picker.offered_sites()
		if keys.is_empty():
			print("[hop] rocket list empty")
			return
		var pick: int = int(keys[clampi(int(DevHooks.get_f("orbit-survey-launch", 1.0)), 0, keys.size() - 1)])
		print("[hop] rocket list %d hubs (at site %d), flying to site %d" % [keys.size(), rocket_site(), pick])
		hop_to(pick)


## Whether Lumi has a rocket on this globe: base level 5 builds it (as the flat game's launch pad),
## a second district unlocking brings it out (there is somewhere to go), and once Lumi has flown
## (a hop) it travels with him.
func rocket_unlocked() -> bool:
	var hub: Variant = so.w.get("hub")
	return DevHooks.has("rocket") or bool(GameState.orbit.get("rocket_owned", false)) \
		or (hub is Hub and (hub as Hub).level >= 5) or (so.districts != null and so.districts.unlocked_count() > 1)


## The hub whose pad the rocket stands on (the last landing, else the start site).
func rocket_site() -> int:
	return clampi(int(GameState.orbit.get("rocket_site", 0)), 0, maxi(sm.sites.size() - 1, 0)) if sm else 0


## Whether Lumi stands in the city whose pad the rocket is on (her work there charges its cells).
## A planet without cities: anywhere counts.
func lumi_in_rocket_city() -> bool:
	var d: Districts = so.districts
	if d == null or d.count() == 0:
		return true
	var here: String = d.current_id()
	return here != "" and here == d.district_of_site(rocket_site())


## "" when the rocket can fly now, else why not: it is in flight, or its energy cells are still
## recharging from the last hop (RocketTiers; rocket upgrades shorten it).
func hop_blocker() -> String:
	if hop.flying or bool(so.w.get("launching")):
		return tr("The rocket is in flight.")
	var left: float = RocketTiers.recharge_left()
	if left > 0.0:
		return tr("Energy cells recharging: %s. Work nearby to charge them faster.") % RocketTiers.fmt_time(left)
	return ""


func rocket_prompt() -> String:
	return tr("E   Rocket: choose a destination")


func open_rocket() -> void:
	if picker == null or picker.is_open or hop.flying:
		return
	so.set_input(false)
	picker.open()


## Travel rule (systems/districts.gd): whether the rocket may fly to site i. A district's site
## once the district is unlocked; open ground as the planet's districts table says (by default
## once every district is unlocked).
func site_offered(i: int) -> bool:
	return so.districts == null or so.districts.site_offered(i)


## The other hubs on this globe the rocket may fly to, nearest first: [{site, name, km}].
func destinations() -> Array:
	var out: Array = []
	if sm == null:
		return out
	var from_i: int = rocket_site()
	var here: Vector3 = sm.pad_xf(from_i).origin.normalized()
	var R: float = so.globe.terrain.R
	for i: int in sm.sites.size():
		if i == from_i or (not _site_hub.is_empty() and not _site_hub.has(i)) or not site_offered(i):
			continue
		var d: Vector3 = (sm.sites[i]["transform"] as Transform3D).origin.normalized()
		out.append({"site": i, "name": site_name(i), "km": here.angle_to(d) * R / 1000.0})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["km"]) < float(b["km"]))
	return out.slice(0, 6)


## What opens the next district, for the rocket's list when nowhere is open yet ("" when every
## district is unlocked or the next one has no stage rule).
func next_city_hint() -> String:
	var d: Districts = so.districts
	if d == null:
		return ""
	for id: String in d.ids():
		if d.is_unlocked(id):
			continue
		var rule: Dictionary = d.spec_of(id)["unlock"]
		var other: String = str(rule.get("district", ""))
		if str(rule.get("type", "")) != Districts.UNLOCK_DISTRICT_STAGE or not d.has(other):
			return ""
		return tr("Nowhere to fly yet. Get %s to %s to open %s.") % [tr(d.name_of(other)),
			tr(Districts.stage_name(Planets.current(), int(rule.get("stage", Districts.MAX_STAGE)))), tr(d.name_of(id))]
	return ""


func site_name(i: int) -> String:
	var district: String = so.districts.district_of_site(i) if so.districts else ""
	if district != "":
		return tr(so.districts.name_of(district))
	var pl: PlanetData = so.globe.planet
	if _site_hub.has(i):
		var cell: int = pl.hubs[int(_site_hub[i])]
		if pl.city[cell] >= 0:
			return tr(str(pl.cities[pl.city[cell]]["name"]))
		return tr("%s site") % PlanetData.BIOMES[pl.biome[cell]].capitalize().replace("_", " ")
	return tr("Hub %d") % i


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


## The parked rocket rebuilt with its current tier and paint (after an upgrade or a new look).
func refresh_rocket() -> void:
	var ship: ShipModel = hop.parked()
	if ship == null or hop.flying:
		return
	hop.remove_child(ship)
	ship.queue_free()
	_sync_rocket()
	if rocket_spot and rocket_spot.visible:
		Vfx.burst("big_sparkle", rocket_spot.global_position + rocket_spot.global_basis.y * 5.0, Color(0.5, 0.9, 1.0))


var _rocket_t: float = 0.0


func _process(delta: float) -> void:
	_rocket_t += delta
	if _rocket_t >= 0.5:
		_rocket_t = 0.0
		_sync_rocket()


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


## [v3city] The land between the hub sites, when the planet's sites script builds any
## (SiteBuilders.build_surroundings).
var hinterland: Node3D


func _build_hinterland() -> void:
	if sm == null or DevHooks.has("no-hinterland"):
		return
	var hubs: Array[Vector3] = []
	for s: Dictionary in sm.sites:
		hubs.append((s["dir"] as Vector3).normalized())
	hinterland = SiteBuilders.build_surroundings(sm.planet_id, {"parent": so.w, "grid": sm.grid, "terrain": sm.terrain, "cells": sm.cells, "hubs": hubs,
		"seed": int(so.globe.get("seed_value")) if so.globe.get("seed_value") != null else 4471,
		"keep_out": so.globe.call("yard_keep_out") as YardKeepOut if so.globe.has_method("yard_keep_out") else null, "focus": so.w.get("patch")})
	if hinterland and DevHooks.has("hinter-report"):
		get_tree().create_timer(DevHooks.get_f("hinter-report", 20.0)).timeout.connect(func() -> void:
			print("[hinter] %s" % str(hinterland.get("stats"))))


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


## Rocket hop to hub i from the nearest one.
func hop_to(i: int) -> bool:
	if sm == null:
		return false
	var from_i: int = sm.nearest if sm.nearest >= 0 else 0
	var to_i: int = clampi(i, 0, sm.sites.size() - 1)
	var ok: bool = await hop.hop_with(sm, so.w.get("patch"), so.cam, so.globe.terrain, from_i, to_i)
	if ok:
		RocketTiers.mark_launched()  # the hop drained the energy cells: they recharge before the next one
	print("[hop] hub %d -> %d: %s" % [from_i, to_i, "ok" if ok else "refused"])
	return ok


## The site built on planet hub `hub_i` (PlanetData.hubs index), or -1.
func site_of_hub(hub_i: int) -> int:
	var site: Variant = _site_hub.find_key(hub_i)
	return int(site) if site != null else -1


## Whether the rocket can hop to planet hub `hub_i` now: the hub has a site, the rocket is owned,
## on the ground with full cells and not already standing there.
func can_hop_to_hub(hub_i: int) -> bool:
	var site: int = site_of_hub(hub_i)
	return site >= 0 and site != rocket_site() and hop_blocker() == "" and rocket_unlocked() and site_offered(site)


## Rocket hop to the site on planet hub `hub_i`, for callers that think in hubs (the play bot).
func hop_to_hub(hub_i: int) -> bool:
	if not can_hop_to_hub(hub_i):
		return false
	return await hop_to(site_of_hub(hub_i))


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
