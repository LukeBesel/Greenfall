class_name PlanetSmoke
extends RefCounted
## [v7planet] Dev: --planet-smoke=write|read. The proof that a planet is data, not code
## (docs/NEW_PLANET.md): boots any planet of data/planets.json on its globe and checks the basics.
##   write  (with --fresh --orbit-planet=<id> --save-dir=D): the globe's size against its data, the
##          start site built, Lumi walks a few metres on his own input, the rocket hops to hub 1
##          and its site builds, hub 1 is woken (the hub plan's wake, or level 2 on a planet without
##          a plan), then the game is saved to disk.
##   read   (a new process, --save-dir=D, no --fresh, no --orbit-planet): the save brings back the
##          same planet, globe size, Lumi's spot and hub 1's level.
## Every step prints a [smoke] line; the last is "[smoke] <phase> <planet> PASS|FAIL (n)". Engine
## and script errors logged while it runs count as failures. Quits 1 on any failure.
## Run both phases with tools/planet_smoke.sh <planet id>.

const WALK_S: float = 4.0
const WALK_MIN_M: float = 2.0
const SITE_WAIT_S: float = 90.0


static func run_dev(so: SliceOrbit) -> void:
	var tree: SceneTree = so.get_tree()
	var errs := HubWalk.ErrCount.new()
	OS.add_logger(errs)
	var bad: Array[String] = []
	var phase: String = DevHooks.get_s("planet-smoke", "write")
	await tree.create_timer(3.0).timeout
	var g: OrbitPlanet = so.globe
	var pid: String = str(g.spec.get("id", "?"))
	var spec: Dictionary = GlobeSpec.of(pid)
	print("[smoke] %s planet %s (%s): f=%d, %d cells, R %.0f m, %d hub sites (data %d), site kit %s, hub plan %d hubs, sound theme %s, current %s" % [
		phase, pid, PlanetCfg.name_of(pid), g.grid.freq, g.grid.cell_count(), g.grid.radius_m, g.sites.size(), int(spec["hub_count"]),
		PlanetCfg.site_kit(pid), HubPlan.entries(pid).size(), Audio.get_planet_theme(), PlanetCfg.current])
	if g.grid.freq != int(spec["frequency"]) or g.grid.cell_count() != GlobeSpec.cells_for(int(spec["frequency"])):
		bad.append("globe: f=%d, data says %d" % [g.grid.freq, int(spec["frequency"])])
	if g.sites.size() < 2:
		bad.append("sites: %d hub sites, need 2 or more (globe.hub_count)" % g.sites.size())
	if PlanetCfg.current != pid or HubPlan.active_planet != pid:
		bad.append("lookups: PlanetCfg.current %s, HubPlan.active_planet %s, globe %s" % [PlanetCfg.current, HubPlan.active_planet, pid])
	var sm: SiteManager = g.site_manager
	# The site Lumi stands at is built: the start yard on a new game, hub 1 after the load (far
	# sites are freed as Lumi leaves them).
	var here: int = 1 if phase == "read" and sm and sm.sites.size() > 1 else 0
	var t0: float = 0.0
	while t0 < SITE_WAIT_S and sm and not (sm.prefab(here) != null and sm.prefab(here).is_built):
		await tree.create_timer(0.5).timeout
		t0 += 0.5
	var p0: SitePrefab = sm.prefab(here) if sm else null
	if p0 == null or not p0.is_built:
		bad.append("site %d (where Lumi is): not built" % here)
	if phase == "read":
		await _read(so, pid, bad)
	else:
		await _write(so, pid, bad)
	OS.remove_logger(errs)
	if errs.n > 0:
		bad.append("errors: %d logged, first %s" % [errs.n, errs.first])
	for b: String in bad:
		print("[smoke]   FAIL %s" % b)
	print("[smoke] %s %s %s" % [phase, pid, "PASS" if bad.is_empty() else "FAIL (%d)" % bad.size()])
	# The last site's deferred footprint probe runs on after its build; let it finish before quitting.
	var w8: float = 0.0
	while sm and sm.sites.size() > 1 and not sm.probed.has(1) and w8 < 30.0:
		await tree.create_timer(0.5).timeout
		w8 += 0.5
	await tree.create_timer(0.5).timeout
	tree.quit(0 if bad.is_empty() else 1)


static func _write(so: SliceOrbit, pid: String, bad: Array[String]) -> void:
	var tree: SceneTree = so.get_tree()
	var g: OrbitPlanet = so.globe
	var sm: SiteManager = g.site_manager
	var patch: Patch = so.w.get("patch")
	# Walk: Lumi's own input straight ahead (with the lap test's detour round props).
	var keep: InputSource = patch.input
	var auto := SphereAutoInput.new(Vector3(0, 0, -1), false)
	auto.body = patch
	patch.input = auto
	var a: Vector3 = patch.global_position
	await tree.create_timer(WALK_S).timeout
	patch.input = keep
	var walked: float = HubWalk._ground_d(a, patch.global_position)
	var up_err: float = absf(patch.global_position.length() - g.terrain.ground(patch.global_position.normalized()).length())
	print("[smoke] write walk: %.1f m in %.1f s, %.2f m off the ground" % [walked, WALK_S, up_err])
	if walked < WALK_MIN_M:
		bad.append("walk: only %.1f m in %.1f s" % [walked, WALK_S])
	if up_err > 1.0:
		bad.append("walk: Lumi %.2f m off the ground" % up_err)
	if sm == null or sm.sites.size() < 2:
		return
	# The start town's landmark is the one the data names (it is built before HubPurpose comes up,
	# so it reads the plan through PlanetCfg.use_planet). Checked here: far sites are freed later.
	_check_landmark(pid, sm, 0, bad)
	# Hop to hub 1 and wait for its site.
	if not DevHooks.has("hop-skip"):
		DevHooks.args["hop-skip"] = "1"
	var ok: bool = await so.sites.hop_to(1)
	var t: float = 0.0
	while t < SITE_WAIT_S and not (sm.prefab(1) != null and sm.prefab(1).is_built):
		await tree.create_timer(0.5).timeout
		t += 0.5
	var p1: SitePrefab = sm.prefab(1)
	print("[smoke] write hop to hub 1: %s, site %s built in %.0f s, Lumi %.0f m from its pad" % [
		"ok" if ok else "refused", p1.site_id if p1 else "-", t, HubWalk._ground_d(patch.global_position, sm.pad_xf(1).origin)])
	if not ok:
		bad.append("hop: refused")
	if p1 == null or not p1.is_built:
		bad.append("hub 1: site not built after %.0f s" % SITE_WAIT_S)
		return
	# Wake hub 1: the hub plan's wake (towns planets with hubs[]), else level 2 by hand.
	var purpose: HubPurpose = so.sites.purpose
	if HubPlan.has_plan(pid) and purpose:
		purpose.wake(1, true)
	else:
		sm.set_level(1, 2)
		sm.set_built(1)
	await tree.create_timer(1.0).timeout
	print("[smoke] write wake hub 1: level %d, built %d, woken %s" % [sm.levels[1], sm.built[1], HubPlan.woken(1)])
	if sm.levels[1] < 2 or sm.built[1] != 1:
		bad.append("wake: hub 1 at level %d, built %d" % [sm.levels[1], sm.built[1]])
	_check_landmark(pid, sm, 1, bad)
	_check_card(so, pid, bad)
	# Save.
	var saved: bool = SaveManager.save_game()
	var od: Dictionary = GameState.orbit
	print("[smoke] write saved %s: planet_id %s, freq %d, lumi %s" % [saved, od.get("planet_id", "?"), int(od.get("freq", 0)), str((od.get("lumi", {}) as Dictionary).get("at", []))])
	if not saved:
		bad.append("save: SaveManager.save_game failed (needs --save-dir)")
	if str(od.get("planet_id", "")) != pid or int(od.get("freq", 0)) != g.grid.freq:
		bad.append("save: orbit dict says %s f=%d" % [od.get("planet_id", "?"), int(od.get("freq", 0))])


static func _read(so: SliceOrbit, pid: String, bad: Array[String]) -> void:
	var g: OrbitPlanet = so.globe
	var sm: SiteManager = g.site_manager
	var patch: Patch = so.w.get("patch")
	var want_pid: String = DevHooks.get_s("planet-smoke-want", pid)
	if pid != want_pid:
		bad.append("load: built %s, the save was %s" % [pid, want_pid])
	var want: Array = (GameState.orbit.get("lumi", {}) as Dictionary).get("at", [])
	var got: Array = g.to_dirh(patch.global_position)
	var off_m: float = INF
	if want.size() == 4:
		off_m = Vector3(float(want[0]), float(want[1]), float(want[2])).distance_to(Vector3(float(got[0]), float(got[1]), float(got[2]))) * g.grid.radius_m
	print("[smoke] read lumi %.2f m from the saved spot, hub 1 level %d built %d woken %s" % [off_m, sm.levels[1] if sm and sm.sites.size() > 1 else -1, sm.built[1] if sm and sm.sites.size() > 1 else -1, HubPlan.woken(1)])
	if off_m > 0.5:
		bad.append("load: Lumi %.2f m from the saved spot" % off_m)
	if sm and sm.sites.size() > 1 and (sm.levels[1] < 2 or sm.built[1] != 1):
		bad.append("load: hub 1 at level %d, built %d" % [sm.levels[1], sm.built[1]])
	if HubPlan.has_plan(pid) and not HubPlan.woken(1):
		bad.append("load: hub 1 not woken")
	await so.get_tree().process_frame


## The landmark kind the built town really has ("" when none): its StreetDressing, anywhere below.
static func _landmark_kind(p: SitePrefab) -> String:
	if p == null or not p.is_built:
		return ""
	var todo: Array[Node] = [p]
	while not todo.is_empty():
		var n: Node = todo.pop_back()
		if n is StreetDressing:
			return str((n as StreetDressing).landmark_info()["kind"])
		todo.append_array(n.get_children())
	return ""


static func _check_landmark(pid: String, sm: SiteManager, i: int, bad: Array[String]) -> void:
	if not HubPlan.has_plan(pid):
		return
	var want: String = HubPlan.landmark_kind(pid, i)
	var got: String = _landmark_kind(sm.prefab(i))
	print("[smoke] write hub %d landmark %s (data %s)" % [i, got, want])
	if want != "" and got != want:
		bad.append("landmark: hub %d has '%s', data says %s" % [i, got, want])


## The card's hub steps (story/planet_steps.gd): a generated planet has exactly its own (fly, wake
## per main-path hub, rocket tiers where its rocket needs them), none of the shared ones, and after
## the hop and the wake above, the steps for hub 2 hold. Every hub step is reachable: no target
## past the planet's main path.
static func _check_card(so: SliceOrbit, pid: String, bad: Array[String]) -> void:
	var ob: Objectives = so.w.get("objectives") as Objectives
	var gl: Goals = so.w.get("goals") as Goals
	if ob == null:
		bad.append("card: no Objectives")
		return
	var hub_steps: Array = ob.chain.filter(func(d: Dictionary) -> bool: return PlanetSteps.is_hub_step(d))
	var ids: PackedStringArray = []
	for d: Dictionary in hub_steps:
		ids.append("%s(%s)" % [d["id"], "held" if ob.value_of(d) >= ob.target_of(d) else "open"])
	var goal_hubs: int = gl.chain.filter(func(d: Dictionary) -> bool: return PlanetSteps.is_hub_step(d)).size() if gl else -1
	print("[smoke] write card %s hub steps: %s; hub goals left %d" % [str(PlanetCfg.value(pid, "hub_steps", "generated")), ", ".join(ids), goal_hubs])
	if not PlanetSteps.generated(pid):
		return
	var want: Array = PlanetSteps.steps_for(pid)
	if hub_steps.size() != want.size():
		bad.append("card: %d hub steps, the planet's hubs make %d" % [hub_steps.size(), want.size()])
	if goal_hubs != 0:
		bad.append("card: %d shared hub goals still on the goal chain" % goal_hubs)
	var main: int = HubPlan.main_total(pid)
	for d: Dictionary in hub_steps:
		if str(d["key"]) != "rocket_tier" and int(d["target"]) > main - 1:
			bad.append("card: %s waits for %d hubs, the planet has %d on its main path" % [d["id"], int(d["target"]) + 1, main])
		if str(d["id"]).ends_with("_2") and ob.value_of(d) < ob.target_of(d):
			bad.append("card: %s not done after the hop and the wake" % d["id"])
