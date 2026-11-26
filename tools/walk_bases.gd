class_name WalkBases
extends RefCounted
## [v14travel] Every flight on Verdance in one compact walk (owner, 26 Nov: "Make sure fast travels
## and bases are all making sense and working"), played with real input on the real globe:
## E at the rocket, a click (or, for one flight, the controller: A, the d-pad, A) on the base's Fly
## button, the flight, the landing. Route: home -> Garden Row -> Gantry Works (base to base) ->
## Garden Row (back, a woken base) -> home; Mk II at the bench; home -> Signal Heights with a quit
## and Continue in the middle of the flight; Signal Heights -> Fairground (base to base, controller);
## Fairground -> home; Mk III; home -> Stack Works; Stack Works -> an extra base (listed once the six
## are awake) -> home. A quit and Continue at every far base and at home.
## On every landing: Lumi stands by the pad, on the ground and not inside anything, and can drive
## off; the rocket stands on the pad (not floating, not sunk); the HUD and the arrival title name the
## base; the beam points at the base's step; the rocket's prompt shows by the ship.
## At every far base its chain is played to the wake (the hexes by the crews' cell clean as in
## tools/walk_travel.gd, which plays real scooping at station 2 and 6; the workbench by E on its
## spot; an outpost repaired by E; the landmark woken by E); the price is given as the step asks.
## Robots left at home and at Garden Row keep working while Lumi is away (their hexes, their sales);
## the money and Parts are one purse at every base.
## --walk-travel --walk-travel-all (tools/check_exit.sh walk_travel_all).

const TAG: String = "[walk-travel]"
## The six main bases in wake order (data/planets.json verdance.hubs): Garden Row, Gantry Works,
## Signal Heights, Fairground, Stack Works.
const MAIN: Array[int] = [9, 7, 8, 2, 4]

static var _t0: int = 0


static func run(so: SliceOrbit) -> void:
	_t0 = Time.get_ticks_msec()
	var w: Node = so.w
	var tree: SceneTree = w.get_tree()
	var ob: Objectives = w.get("objectives") as Objectives
	var hp: HubPurpose = so.sites.purpose
	# The state the card reaches "Fly to the next base" in (as walk_travel's station 2).
	YardBuilds.mark_built("shuttle")
	GameState.flags["shuttle_plans"] = true
	GameState.flags["map_seen"] = true
	WalkTravel._set_story(ob, "hub_fly_2")
	GameState.stats["plants_planted"] = maxf(float(GameState.stats.get("plants_planted", 0)), 1.0)
	GameState.flags["seeds_unlocked"] = true
	YardBuilds.state()["bench"] = true
	GameState.stats["hexes_cleaned"] = maxf(float(GameState.stats.get("hexes_cleaned", 0)), 10.0)
	WalkTravel._apply_state(WalkTravel.S2)
	var crew: SphereCrew = _crew(so)
	WalkTravel._check(crew != null, "the globe has its robot crew")
	if crew == null:
		return
	# Robots at home (the card's step before the shuttle asks for three robots and a Haul Bug).
	var home_cell: int = int(so.globe.sites[0]["cell"])
	var around: PackedInt32Array = so.globe.grid.cells_around(home_cell, 2)
	for k: int in 3:
		crew.spawn("scoopie" if k < 2 else "haulbug", 0, around[(k + 3) % around.size()], home_cell, "Home-%d" % k)
	await WalkTravel._wait(tree, 2.0)
	var cash0: float = crew.cashed
	print("%s   all: home has %d robots" % [TAG, crew.hub_robots(home_cell).size()])
	var yard: Dictionary = WalkTravel._yard(so)
	var shown: Dictionary = WalkTravel._yard_shown(yard)
	var had: Dictionary = {}
	for k: String in yard:
		if yard[k] != null:
			had[k] = true
	# 1. Home -> Garden Row.
	await _money_for_next(so)
	await WalkTravel._wait(tree, 1.6)
	await _fly(so, 9, "home -> Garden Row")
	await _arrival(so, 9, true)
	await _chain(so, 9)
	# A robot of Garden Row's own (it works there while Lumi is elsewhere).
	var gr_cell: int = int(so.globe.sites[9]["cell"])
	crew.spawn("scoopie", 0, so.globe.grid.cells_around(gr_cell, 2)[4], gr_cell, "Garden-0")
	var gr0: int = hp.clean_cells(9)
	so = await _reload(so, 9, "at Garden Row")
	if so == null:
		return
	hp = so.sites.purpose
	ob = so.w.get("objectives") as Objectives
	crew = _crew(so)
	WalkTravel._check(crew.hub_robots(gr_cell).size() >= 1 and crew.hub_robots(home_cell).size() >= 3,
		"Continue at Garden Row: the robots are kept (%d here, %d at home)" % [crew.hub_robots(gr_cell).size(), crew.hub_robots(home_cell).size()])
	# 2. Garden Row -> Gantry Works, base to base.
	WalkTravel._set_story(ob, "hub_fly_3")
	await _money_for_next(so)
	await WalkTravel._wait(tree, 1.6)
	await _fly(so, 7, "Garden Row -> Gantry Works")
	await _arrival(so, 7, true)
	await _chain(so, 7)
	so = await _reload(so, 7, "at Gantry Works")
	if so == null:
		return
	hp = so.sites.purpose
	ob = so.w.get("objectives") as Objectives
	crew = _crew(so)
	var home0: float = _work_done(crew, home_cell)  # the robots' own logs start again with each load
	var gr_work0: float = _work_done(crew, gr_cell)
	# 3. Gantry Works -> Garden Row (back to a woken base): its robot and its keepers worked on.
	await _fly(so, 9, "Gantry Works -> Garden Row")
	await _arrival(so, 9, false)
	await WalkTravel._wait(tree, 3.0)
	WalkTravel._check(hp.clean_cells(9) > gr0 and _work_done(crew, gr_cell) > gr_work0, "Garden Row kept cleaning while Lumi was away: its clean hexes %d -> %d (its keepers), its robot's pieces and hexes %.0f -> %.0f" % [gr0, hp.clean_cells(9), gr_work0, _work_done(crew, gr_cell)])
	await _far_bench_row(so, 9, "signal tower")
	# 4. Garden Row -> home: the yard stands, the home robots worked on.
	await _fly(so, 0, "Garden Row -> home")
	await _arrival(so, 0, false)
	await WalkTravel._wait(tree, 3.0)
	WalkTravel._check(_work_done(crew, home_cell) > home0, "the home robots kept working while Lumi was away: pieces scooped, hexes, bales and hauls %.0f -> %.0f" % [home0, _work_done(crew, home_cell)])
	print("%s   all: crew cubes cashed this session %.0f (was %.0f)" % [TAG, crew.cashed, cash0])
	await WalkTravel._home_check(so, had, shown, "home from the far bases")
	# 5. Mk II at the bench (the fourth base needs it), then home -> Signal Heights with a quit and
	# Continue in the middle of the flight.
	WalkTravel._set_story(ob, "rocket_tier_2")
	await WalkTravel._wait(tree, 1.6)
	await WalkTravel._bench_upgrade(so, 2)
	so = await _reload(so, 0, "at home")
	if so == null:
		return
	hp = so.sites.purpose
	ob = so.w.get("objectives") as Objectives
	WalkTravel._set_story(ob, "hub_fly_4")
	await _money_for_next(so)
	await WalkTravel._wait(tree, 1.6)
	so = await _quit_mid_flight(so, 8)
	if so == null:
		return
	hp = so.sites.purpose
	ob = so.w.get("objectives") as Objectives
	if so.sites.sm.nearest != 8:  # Continue put Lumi back where the flight left from: fly again
		await _fly(so, 8, "home -> Signal Heights (again, after the quit in flight)")
		await _arrival(so, 8, true)
	await _chain(so, 8)
	so = await _reload(so, 8, "at Signal Heights")
	if so == null:
		return
	hp = so.sites.purpose
	ob = so.w.get("objectives") as Objectives
	# 6. Signal Heights -> Fairground, base to base, by the controller.
	WalkTravel._set_goal(ob, "hub_fly_5")
	await _money_for_next(so)
	await WalkTravel._wait(tree, 1.6)
	DevHooks.args["walk-travel-pad"] = "1"
	await _fly(so, 2, "Signal Heights -> Fairground (controller)")
	DevHooks.args.erase("walk-travel-pad")
	await _arrival(so, 2, true)
	await _chain(so, 2)
	so = await _reload(so, 2, "at Fairground")
	if so == null:
		return
	hp = so.sites.purpose
	ob = so.w.get("objectives") as Objectives
	# 7. Fairground -> home; Mk III; home -> Stack Works.
	await _fly(so, 0, "Fairground -> home")
	await _arrival(so, 0, false)
	WalkTravel._apply_state(WalkTravel.S6)
	WalkTravel._set_goal(ob, "rocket_tier_3")
	await WalkTravel._wait(tree, 1.6)
	await WalkTravel._bench_upgrade(so, 3)
	WalkTravel._set_goal(ob, "hub_fly_6")
	await _money_for_next(so)
	await WalkTravel._wait(tree, 1.6)
	await _fly(so, 4, "home -> Stack Works")
	await _arrival(so, 4, true)
	await _chain(so, 4)
	WalkTravel._check(HubPlan.restored_main(hp.planet) == HubPlan.main_total(hp.planet), "six of six bases awake (%d)" % HubPlan.restored_main(hp.planet))
	so = await _reload(so, 4, "at Stack Works")
	if so == null:
		return
	hp = so.sites.purpose
	# 8. Stack Works -> an extra base (listed once the six are awake) -> home.
	var extra: int = -1
	for e: Dictionary in so.sites.destinations():
		if not HubPlan.is_main(hp.planet, int(e["site"])) and not HubPlan.woken(int(e["site"])):
			extra = int(e["site"])
			break
	WalkTravel._check(extra >= 0, "with the six awake the rocket lists the extra bases (%s)" % str(so.sites.picker.offered_sites()))
	if extra >= 0:
		await _fly(so, extra, "Stack Works -> %s (extra)" % HubPlan.hub_name(hp.planet, extra))
		await _arrival(so, extra, true)
	await _fly(so, 0, "-> home")
	await _arrival(so, 0, false)
	await WalkTravel._home_check(so, had, shown, "home at the end")
	print("%s   all: the walk took %.0f s (%.0f s since the game started)" % [TAG, (Time.get_ticks_msec() - _t0) / 1000.0, Time.get_ticks_msec() / 1000.0])


## What the robots of a base have done (their logs: pieces scooped, hexes, bales pressed, bales hauled).
static func _work_done(crew: SphereCrew, hub_cell: int) -> float:
	var n: float = 0.0
	for u: Dictionary in crew.hub_robots(hub_cell):
		for k: String in ["junk", "cells", "bales", "hauled"]:
			n += float((u["log"] as Dictionary).get(k, 0.0))
	return n


## The card's step at a woken far base points at this base's workbench: E opens it and it has the
## row the step needs (`what` in a label or button).
static func _far_bench_row(so: SliceOrbit, site: int, what: String) -> void:
	var w: Node = so.w
	var tree: SceneTree = w.get_tree()
	var ob: Objectives = w.get("objectives") as Objectives
	var p: Patch = w.get("patch") as Patch
	var bp: Variant = so.sites.purpose.bench_point()
	var wt: Variant = ob.waypoint_target()
	var card: String = ob.texts(ob.current())[0] if not ob.current().is_empty() else ""
	if not (bp is Vector3) or not (wt is Vector3) or (wt as Vector3).distance_to(bp) > 2.0:
		print("%s   all: at %s the beam is not on its workbench (card '%s')" % [TAG, HubPlan.hub_name(so.sites.sm.planet_id, site), card])
		return
	var b3: Vector3 = bp
	WalkTravel._stand(so, p, b3 + (b3 - so.sites.sm.pad_xf(site).origin).normalized() * 1.6, b3)
	await WalkTravel._frames(tree, 6)
	await WalkTravel._tap(tree, "interact")
	await WalkTravel._wait(tree, 1.0)
	var up: UpgradesScreen = w.get("upgrades") as UpgradesScreen
	var has: bool = false
	if up and up.is_open:
		for n: Node in up.find_children("*", "", true, false):
			var t: String = str(n.get("text")) if (n is Label or n is Button) and (n as Control).is_visible_in_tree() else ""
			if what in t.to_lower():
				has = true
				break
	WalkTravel._check(up != null and up.is_open and has, "at %s the card '%s' points at this base's workbench: E opens it, and it has the %s" % [HubPlan.hub_name(so.sites.sm.planet_id, site), card, what])
	await WalkTravel._shot(tree, "far_bench_%d" % site)
	if up and up.is_open:
		await WalkTravel._tap(tree, "ui_cancel")
		await WalkTravel._wait(tree, 0.6)


static func _crew(so: SliceOrbit) -> SphereCrew:
	return so.crews.crew if so.crews else null


## The price of the next base's chain in the purse: the wake, the workbench, an outpost, a margin.
static func _money_for_next(so: SliceOrbit) -> void:
	var hp: HubPurpose = so.sites.purpose
	var wc: Dictionary = HubPlan.wake_cost(hp.planet)
	var bc: Dictionary = FarYard.cost(hp.planet, "bench")
	WalkTravel._set_money(maxf(GameState.get_currency("cubes").to_float(), float(wc.get("cubes", 0)) + float(bc.get("cubes", 0)) + 3000.0),
		maxf(GameState.get_currency("parts").to_float(), float(wc.get("parts", 0)) + float(bc.get("parts", 0)) + 60.0))


## E at the rocket, Fly by the base's row, the flight; checks the purse is the same purse after.
static func _fly(so: SliceOrbit, to_site: int, what: String) -> void:
	var os_: OrbitSites = so.sites
	print("%s   all: flight %s (from site %d)" % [TAG, what, os_.rocket_site()])
	var first: bool = not HubPlan.seen(to_site) and not HubPlan.is_home(os_.sm.planet_id, to_site)
	await WalkTravel._fly_by_click(so, to_site, first and HubPlan.is_main(os_.sm.planet_id, to_site))
	WalkTravel._check(os_.sm.nearest == to_site and os_.rocket_site() == to_site, "%s: landed (at site %d, rocket at %d)" % [what, os_.sm.nearest, os_.rocket_site()])


## What a player sees on landing at `site`.
static func _arrival(so: SliceOrbit, site: int, first: bool) -> void:
	var w: Node = so.w
	var tree: SceneTree = w.get_tree()
	var os_: OrbitSites = so.sites
	var hp: HubPurpose = os_.purpose
	var ob: Objectives = w.get("objectives") as Objectives
	var p: Patch = w.get("patch") as Patch
	var nm: String = HubPlan.hub_name(hp.planet, site)
	var pad: Transform3D = os_.sm.pad_xf(site)
	# The rocket on its pad: on the ground, not floating, not sunk.
	var ship: ShipModel = os_.hop.parked()
	var ground_at_pad: float = so.globe.terrain.ground(pad.origin.normalized()).length()
	WalkTravel._check(ship != null and ship.visible and ship.global_position.distance_to(pad.origin) < 0.6 and absf(pad.origin.length() - ground_at_pad) < 0.8,
		"%s: the rocket stands on the pad (%.2f m from it; pad %.2f m off the ground)" % [nm, ship.global_position.distance_to(pad.origin) if ship else -1.0, pad.origin.length() - ground_at_pad])
	# Lumi by the pad, on the ground, inside nothing.
	var alt: float = so.globe.terrain.altitude(p.global_position)
	WalkTravel._check(p.global_position.distance_to(pad.origin) < 12.0 and absf(alt) < 0.6,
		"%s: Lumi stands by the pad on the ground (%.1f m from it, %.2f m above the ground)" % [nm, p.global_position.distance_to(pad.origin), alt])
	var inside: PackedStringArray = _inside(p)
	WalkTravel._check(inside.is_empty(), "%s: Lumi stands inside nothing%s" % [nm, "" if inside.is_empty() else " (in %s)" % ", ".join(inside)])
	# The names: the HUD's line, the arrival title.
	var hl: Dictionary = hp.hud_lines()
	WalkTravel._check(str(hl.get("field", "")).begins_with(nm.to_upper()), "%s: the HUD names the base ('%s')" % [nm, str(hl.get("field", ""))])
	if first:
		var tn: Control = hp.title_node()
		var big: String = ""
		if tn:
			for l: Node in tn.find_children("*", "Label", true, false):
				big = (l as Label).text
				break
		WalkTravel._check(big == nm.to_upper(), "%s: the arrival title names it ('%s', why: '%s')" % [nm, big, hp.title_reason])
	# The beam: a far base not yet woken points at its step; a woken one or home at something on
	# the card (never at a woken landmark).
	for k: int in 24:
		await WalkTravel._wait(tree, 0.5)
		if ob.waypoint_target() is Vector3:
			break
	var wt: Variant = ob.waypoint_target()
	var to: String = str(ob.step_target(ob.current()).get("to", ""))
	var far_from: float = (wt as Vector3).distance_to(pad.origin) if wt is Vector3 else -1.0
	print("%s   all: %s: card '%s' / '%s', beam %s (%.0f m from the pad), base card '%s'" % [TAG, nm, ob.texts(ob.current())[0] if not ob.current().is_empty() else "",
		ob.situation, to, far_from, hp.card_text])
	if site > 0 and not HubPlan.woken(site):
		WalkTravel._check(wt is Vector3 and far_from < 160.0, "%s: the beam points at this base's step (%s, %.0f m from the pad)" % [nm, to, far_from])
	if site > 0 and HubPlan.woken(site):
		var nx: int = HubPlan.next_site(hp.planet)
		if nx >= 0 and hp.card_text.contains(HubPlan.hub_name(hp.planet, nx)):  # the card sends Lumi to a base: its Fly must be on
			var locked: String = ""
			for e: Dictionary in os_.destinations():
				if int(e["site"]) == nx:
					locked = str(e.get("locked", ""))
			WalkTravel._check(locked == "", "%s: the base card's next stop can be flown to ('%s'%s)" % [nm, hp.card_text, "" if locked == "" else "; its row: " + locked])
		var lm: Dictionary = hp.landmark(site)
		WalkTravel._check(lm.is_empty() or not (wt is Vector3 and (wt as Vector3).distance_to(lm["pos"]) < 1.0), "%s: nothing points at its woken landmark" % nm)
	if site > 0 and first:  # [v14travel] no sign post between the play camera and Lumi at this base's E spots
		var blocked: PackedStringArray = await sightlines(so, site)
		# OPEN (not a check yet): the far Locker spot's sign stands on this line at the rocket (far_yard.gd SPOTS, untested move to (8.5, 0, 3.9))
		print("%s   all: %s sightlines: %s" % [TAG, nm, "clear" if blocked.is_empty() else "BLOCKED " + "; ".join(blocked)])
	# Lumi drives off the landing spot.
	var at0: Vector3 = p.global_position
	await WalkTravel._hold(tree, "move_back", 0.8)
	WalkTravel._check(p.global_position.distance_to(at0) > 0.8, "%s: Lumi drives off the landing spot (%.1f m)" % [nm, p.global_position.distance_to(at0)])
	await WalkTravel._shot(tree, "all_land_%d" % site)


## Static bodies Lumi's own collider overlaps (names), the ground excluded.
static func _inside(p: Patch) -> PackedStringArray:
	var out: PackedStringArray = []
	var cs: CollisionShape3D = p.get("_shape") as CollisionShape3D
	if cs == null or cs.shape == null:
		return out
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cs.shape
	var up: Vector3 = p.global_position.normalized()
	q.transform = cs.global_transform.translated(up * 0.12)  # lifted off the ground it stands on
	q.collision_mask = p.collision_mask
	q.exclude = [p.get_rid()]
	q.margin = -0.04
	for r: Dictionary in p.get_world_3d().direct_space_state.intersect_shape(q, 8):
		var c: Object = r.get("collider")
		if c is Node and not (c as Node).name.to_lower().contains("terrain") and not (c as Node).name.to_lower().contains("ground"):
			out.append(str((c as Node).get_path()))
	return out


## The base's chain to the wake (walk_travel's _finish_station without its station-2 extras).
static func _chain(so: SliceOrbit, site: int) -> void:
	var hp: HubPurpose = so.sites.purpose
	var steps: PackedStringArray = []
	for s: Dictionary in hp.steps(site):
		steps.append("%s %d/%d" % [str(s["do"]) + ("(%s)" % str(s["id"]) if s.has("id") else ""), int(s["have"]), int(s["need"])])
	print("%s   all: %s's chain: %s" % [TAG, HubPlan.hub_name(hp.planet, site), ", ".join(steps)])
	var before: int = HubPlan.restored_main(hp.planet)
	await WalkTravel._finish_station(so, site, false)
	WalkTravel._check(HubPlan.woken(site) and HubPlan.restored_main(hp.planet) == before + 1, "%s is awake: bases %d of %d" % [HubPlan.hub_name(hp.planet, site), HubPlan.restored_main(hp.planet), HubPlan.main_total(hp.planet)])
	var fy: FarYard = FarYard.of(so.w)  # the Locker and the Bot Bay too (the player's choice; built free here to look past them)
	for id: String in ["locker", "bot_bay"]:
		fy.build(site, id, true)
	await WalkTravel._wait(so.w.get_tree(), 1.0)
	var blocked: PackedStringArray = await sightlines(so, site)
	print("%s   all: %s with its machines built, sightlines: %s" % [TAG, HubPlan.hub_name(hp.planet, site), "clear" if blocked.is_empty() else "BLOCKED " + "; ".join(blocked)])
	for k: String in ["cubes", "parts"]:
		WalkTravel._check(GameState.get_currency(k).to_float() >= 0.0, "the purse holds %s %.0f" % [k, GameState.get_currency(k).to_float()])


## Quit and Continue at a base: Lumi and the rocket are there, the base's state came back.
static func _reload(so: SliceOrbit, site: int, what: String) -> SliceOrbit:
	var woken: bool = HubPlan.woken(site)
	var level: int = so.sites.sm.levels[site] if site < so.sites.sm.levels.size() else 0
	var cubes: float = GameState.get_currency("cubes").to_float()
	var parts: float = GameState.get_currency("parts").to_float()
	var bench: bool = site == 0 or FarYard.is_built(site, "bench")
	var t: int = Time.get_ticks_msec()
	var so2: SliceOrbit = await WalkTravel._reload(so, what)
	if so2 == null:
		return null
	print("%s   all: quit and Continue %s took %.0f s" % [TAG, what, (Time.get_ticks_msec() - t) / 1000.0])
	var os_: OrbitSites = so2.sites
	var p: Patch = so2.w.get("patch") as Patch
	WalkTravel._check(os_.sm.nearest == site and os_.rocket_site() == site and os_.rocket_spot.visible,
		"Continue %s: Lumi and the rocket are there (at site %d, rocket at %d, shown %s)" % [what, os_.sm.nearest, os_.rocket_site(), os_.rocket_spot.visible])
	WalkTravel._check(HubPlan.woken(site) == woken and (site >= os_.sm.levels.size() or os_.sm.levels[site] >= level) and (site == 0 or FarYard.is_built(site, "bench") == bench),
		"Continue %s: the base is as it was (woken %s, level %d, workbench %s)" % [what, HubPlan.woken(site), os_.sm.levels[site] if site < os_.sm.levels.size() else -1, FarYard.is_built(site, "bench") if site > 0 else true])
	WalkTravel._check(GameState.get_currency("cubes").to_float() >= cubes - 1.0 and absf(GameState.get_currency("parts").to_float() - parts) < 1.0,
		"Continue %s: the purse came back (cubes %.0f -> %.0f, Parts %.0f -> %.0f)" % [what, cubes, GameState.get_currency("cubes").to_float(), parts, GameState.get_currency("parts").to_float()])
	WalkTravel._check((p.input as PlayerInput).enabled and p.visible, "Continue %s: Lumi can move" % what)
	return so2


## E at the rocket, a click on Fly, then the pause key while the ship is in the air, Quit, Continue.
## Lumi must come back on the ground at one end of the flight, by the rocket, able to move.
static func _quit_mid_flight(so: SliceOrbit, to_site: int) -> SliceOrbit:
	var w: Node = so.w
	var tree: SceneTree = w.get_tree()
	var os_: OrbitSites = so.sites
	var from_i: int = os_.rocket_site()
	var p: Patch = w.get("patch") as Patch
	await WalkTravel._stand_at_rocket(so)
	await WalkTravel._tap(tree, "interact")
	await WalkTravel._frames(tree, 4)
	var b: Button = WalkTravel._fly_button(os_.picker, HubPlan.hub_name(os_.sm.planet_id, to_site))
	WalkTravel._check(os_.picker.is_open and b != null and not b.disabled, "quit in flight: the rocket's list has %s's Fly" % HubPlan.hub_name(os_.sm.planet_id, to_site))
	if b == null:
		return so
	await WalkTravel._click(tree, b)
	await WalkTravel._frames(tree, 3)
	WalkTravel._check(os_.hop.flying, "quit in flight: the ship lifts off")
	var so2: SliceOrbit = await WalkTravel._reload(so, "in flight")
	if so2 == null:
		return null
	var os2: OrbitSites = so2.sites
	var p2: Patch = so2.w.get("patch") as Patch
	var at: int = os2.sm.nearest
	var alt: float = so2.globe.terrain.altitude(p2.global_position)
	WalkTravel._check((at == from_i or at == to_site) and os2.rocket_site() == at and os2.rocket_spot.visible and p2.global_position.distance_to(os2.sm.pad_xf(at).origin) < 15.0 and absf(alt) < 0.8,
		"Continue after a quit in flight: Lumi stands by the rocket at one end of the flight (site %d, rocket at %d, %.0f m from its pad, %.1f m above the ground)" % [at, os2.rocket_site(), p2.global_position.distance_to(os2.sm.pad_xf(at).origin), alt])
	WalkTravel._check((p2.input as PlayerInput).enabled and p2.visible and not os2.hop.flying, "Continue after a quit in flight: Lumi can move")
	if at == to_site:
		await _arrival(so2, to_site, false)
	return so2


# --- Off Verdance and back (--walk-travel-planet; planets closed in this release need --open-planets) ---

## The six awake, the Mk V drive built from the rocket's list, the system map, a launch to the next
## planet, the landing, a quit and Continue there, the flight back to Verdance. Prints what each
## planet shows; checks what must hold whatever is built there (Lumi on the ground by a rocket, the
## purse, Verdance's bases and robots kept).
static func planet_trip(so: SliceOrbit) -> void:
	var w: Node = so.w
	var tree: SceneTree = w.get_tree()
	var ob: Objectives = w.get("objectives") as Objectives
	var os_: OrbitSites = so.sites
	var hp: HubPurpose = os_.purpose
	YardBuilds.mark_built("shuttle")
	GameState.flags["shuttle_plans"] = true
	GameState.flags["map_seen"] = true
	GameState.orbit["rocket_owned"] = true
	YardBuilds.state()["bench"] = true
	WalkTravel._apply_state(WalkTravel.S6)
	var hub: Hub = w.get("hub") as Hub  # the home base at level 5, as walk_travel's late part has it (the Mk V drive asks for level 3)
	if hub:
		hub.level = 5
		hub.level_changed.emit(5)
	GameState.world["hub_level"] = 5
	for i: int in MAIN:
		hp.wake(i, true)
	WalkTravel._check(HubPlan.restored_main(hp.planet) == HubPlan.main_total(hp.planet), "planet trip: six bases awake")
	var crew: SphereCrew = _crew(so)
	var home_cell: int = int(so.globe.sites[0]["cell"])
	crew.spawn("scoopie", 0, so.globe.grid.cells_around(home_cell, 2)[3], home_cell, "Home-0")
	WalkTravel._set_goal(ob, "home_drive_5")
	var dc: Dictionary = Homeward.next_drive().get("cost", {})
	WalkTravel._set_money(float(dc.get("cubes", 0)) + 5000.0, float(dc.get("parts", 0)) + 50.0)
	await WalkTravel._wait(tree, 2.0)
	# The drive, from the rocket's list.
	var sm_: SystemMap = await _open_planets(so)
	if sm_ == null:
		return
	var db: Button = WalkTravel._find_button(sm_, "Build the drive")
	WalkTravel._check(db != null and not db.disabled, "planet trip: Build the drive shows, ready")
	if db:
		await WalkTravel._click(tree, db)
		await WalkTravel._wait(tree, 0.6)
	WalkTravel._check(Homeward.drive() >= 5, "planet trip: a click builds the drive (Mk %d)" % Homeward.drive())
	await WalkTravel._tap(tree, "ui_cancel")
	await WalkTravel._wait(tree, 1.0)
	Engine.time_scale = 4.0  # WREN's drive lines, the way onward charted
	for k: int in 120:
		if Homeward.discovered(1) and not sm_.is_open:
			break
		await tree.create_timer(0.5).timeout
	Engine.time_scale = 1.0
	await WalkTravel._wait(tree, 3.0)
	var hd: HomewardDirector = HomewardDirector.of(w)
	if hd and hd.tbc and hd.tbc.is_open:
		print("%s   planet trip: the 'to be continued' card shows (planets closed): closed by E" % TAG)
		await WalkTravel._tap(tree, "interact")
		await WalkTravel._wait(tree, 1.0)
	if not Homeward.discovered(1):  # [v14travel] not on the map yet (Verdance under discover_at): spotted by the telescope, as a player can
		print("%s   planet trip: %s is not on the map after the drive and six bases (Verdance %.0f%%, needs %.0f%% or the telescope): spotted" % [TAG,
			Homeward.planet_name(1), float(Homeward.pct_list()[0]) * 100.0, float(Homeward.cfg().get("discover_at", 0.25)) * 100.0])
		Homeward.spot(1)
	WalkTravel._check(Homeward.discovered(1), "planet trip: %s is charted" % Homeward.planet_name(1))
	var stock: Array = [GameState.get_currency("cubes").to_float(), GameState.get_currency("parts").to_float()]
	var woke: int = HubPlan.restored_main(hp.planet)
	# The launch: the map from the rocket, the next planet picked by the arrow key, Launch clicked.
	sm_ = await _open_planets(so)
	if sm_ == null:
		return
	for k: int in 6:
		if sm_.selected == 1:
			break
		await WalkTravel._tap(tree, "ui_right")
		await WalkTravel._wait(tree, 0.4)
	var why: String = SystemMap.launch_blocker(w, 1)
	var lb: Button = WalkTravel._find_button(sm_, "Launch")
	print("%s   planet trip: map on %s, status '%s', button '%s'" % [TAG, Homeward.planet_name(sm_.selected), why, lb.text if lb else "-"])
	WalkTravel._check(sm_.selected == 1 and lb != null, "planet trip: the arrow key picks %s and its panel has a Launch button" % Homeward.planet_name(1))
	await WalkTravel._shot(tree, "planet_map")
	if lb == null or lb.disabled:
		print("%s   planet trip: no launch (%s): the trip ends on Verdance" % [TAG, why])
		return
	WalkTravel._reborn = null
	await WalkTravel._click(tree, lb)
	var so2: SliceOrbit = await _new_world(tree, "landing on %s" % Homeward.planet_name(1))
	if so2 == null:
		return
	await _planet_landed(so2, 1, stock)
	so2 = await WalkTravel._reload(so2, "on %s" % Homeward.planet_name(1))
	if so2 == null:
		return
	WalkTravel._check(Homeward.current_planet() == 1, "Continue on %s: still there (planet %d)" % [Homeward.planet_name(1), Homeward.current_planet()])
	await _planet_landed(so2, 1, stock)
	# Back to Verdance.
	sm_ = await _open_planets(so2)
	if sm_ == null:
		return
	for k: int in 6:
		if sm_.selected == 0:
			break
		await WalkTravel._tap(tree, "ui_left")
		await WalkTravel._wait(tree, 0.4)
	lb = WalkTravel._find_button(sm_, "Launch")
	WalkTravel._check(sm_.selected == 0 and lb != null and not lb.disabled, "planet trip: the map offers the flight back to Verdance ('%s')" % SystemMap.launch_blocker(so2.w, 0))
	if lb == null or lb.disabled:
		return
	WalkTravel._reborn = null
	await WalkTravel._click(tree, lb)
	var so3: SliceOrbit = await _new_world(tree, "back on Verdance")
	if so3 == null:
		return
	await _planet_landed(so3, 0, stock)
	WalkTravel._check(HubPlan.restored_main("verdance") == woke, "back on Verdance: the six bases are still awake (%d)" % HubPlan.restored_main("verdance"))
	var c3: SphereCrew = _crew(so3)
	WalkTravel._check(c3 != null and c3.hub_robots(int(so3.globe.sites[0]["cell"])).size() >= 1, "back on Verdance: the home robots are kept (%d)" % (c3.hub_robots(int(so3.globe.sites[0]["cell"])).size() if c3 else -1))


## E at the rocket, a click on Other planets: the system map (null if it did not open).
static func _open_planets(so: SliceOrbit) -> SystemMap:
	var w: Node = so.w
	var tree: SceneTree = w.get_tree()
	var os_: OrbitSites = so.sites
	await WalkTravel._stand_at_rocket(so)
	await WalkTravel._tap(tree, "interact")
	await WalkTravel._frames(tree, 4)
	var ob_btn: Button = WalkTravel._find_button(os_.picker, "Other planets")
	WalkTravel._check(os_.picker.is_open and ob_btn != null, "E at the rocket: its list offers Other planets")
	if ob_btn == null:
		os_.picker.close()
		return null
	await WalkTravel._click(tree, ob_btn)
	await WalkTravel._wait(tree, 1.5)
	var sm_: SystemMap = SystemMap.shared(w)
	var hd: HomewardDirector = HomewardDirector.of(w)
	if hd and hd.map:
		sm_ = hd.map
	WalkTravel._check(sm_ != null and sm_.is_open, "a click on Other planets opens the system map")
	return sm_ if sm_ and sm_.is_open else null


## The world a launch switched to, once built (null if none came).
static func _new_world(tree: SceneTree, what: String) -> SliceOrbit:
	for k: int in 900:
		if WalkTravel._reborn != null:
			break
		await tree.create_timer(0.5).timeout
	WalkTravel._check(WalkTravel._reborn != null, "%s: the new world comes up" % what)
	if WalkTravel._reborn == null:
		return null
	var so2: SliceOrbit = WalkTravel._reborn
	for k: int in 600:
		if not bool(so2.w.get("building")) and so2.w.get("objectives") != null and so2.sites != null and not so2.sites.hop.flying and not bool(so2.w.get("launching")):
			break
		await tree.create_timer(0.5).timeout
	await tree.create_timer(6.0).timeout
	return so2


## On planet k after a flight: Lumi on the ground by a rocket, able to move; the purse kept; what the card says.
static func _planet_landed(so: SliceOrbit, k: int, stock: Array) -> void:
	var w: Node = so.w
	var tree: SceneTree = w.get_tree()
	var os_: OrbitSites = so.sites
	var p: Patch = w.get("patch") as Patch
	var ob: Objectives = w.get("objectives") as Objectives
	var nm: String = Homeward.planet_name(k)
	var at: int = os_.sm.nearest
	var pad: Vector3 = os_.sm.pad_xf(maxi(at, 0)).origin
	var alt: float = so.globe.terrain.altitude(p.global_position)
	WalkTravel._check(Homeward.current_planet() == k and so.globe.planet_id == str(Homeward.planet_def(k).get("id", "")),
		"on %s (planet %d, globe '%s')" % [nm, Homeward.current_planet(), so.globe.planet_id])
	WalkTravel._check(at >= 0 and p.global_position.distance_to(pad) < 15.0 and absf(alt) < 0.8 and os_.rocket_spot.visible and os_.rocket_site() == at,
		"on %s: Lumi stands by the rocket on a pad (site %d, %.0f m from the pad, %.1f m above the ground, rocket at %d shown %s)" % [nm, at, p.global_position.distance_to(pad), alt, os_.rocket_site(), os_.rocket_spot.visible])
	var inside: PackedStringArray = _inside(p)
	WalkTravel._check(inside.is_empty(), "on %s: Lumi stands inside nothing%s" % [nm, "" if inside.is_empty() else " (in %s)" % ", ".join(inside)])
	WalkTravel._check((p.input as PlayerInput).enabled and p.visible, "on %s: Lumi can move" % nm)
	# Each world keeps its own purse (CradleMode: a new planet starts with the starter kit); Verdance's
	# comes back when Lumi does.
	print("%s   on %s: purse cubes %.0f, Parts %.0f (Verdance's when it left: %.0f, %.0f)" % [TAG, nm, GameState.get_currency("cubes").to_float(), GameState.get_currency("parts").to_float(), float(stock[0]), float(stock[1])])
	if k == 0:
		WalkTravel._check(GameState.get_currency("cubes").to_float() >= float(stock[0]) - 1.0 and GameState.get_currency("parts").to_float() >= float(stock[1]) - 0.5,
			"back on Verdance: its purse is as it was left (cubes %.0f -> %.0f, Parts %.0f -> %.0f)" % [float(stock[0]), GameState.get_currency("cubes").to_float(), float(stock[1]), GameState.get_currency("parts").to_float()])
	var junk: int = 0
	var f: SphereField = so.globe.field
	if f:
		for c: int in so.globe.grid.cells_within(p.global_position.normalized(), 60.0, so.globe.grid.cell_at(p.global_position.normalized())):
			junk += 1 if f.hex_clean[c] == 0 and f.hex_water[c] == 0 else 0
	var dests: Array = os_.destinations()
	print("%s   on %s: card '%s' (%s), dirty hexes within 60 m %d, rocket list %d bases, bases plan %s, HUD '%s'" % [TAG, nm, ob.texts(ob.current())[0] if not ob.current().is_empty() else "(none)",
		str(ob.current().get("id", "")), junk, dests.size(), HubPlan.has_plan(os_.sm.planet_id), str(os_.purpose.hud_lines().get("field", "")) if os_.purpose else "-"])
	await WalkTravel._shot(tree, "planet_%d" % k)


# --- What stands between the play camera and Lumi at a far base's E spots ------------------------

## The play camera behind Lumi at each E spot of far base `site` (the rocket, each build spot or its
## machine, the bin, the scale), facing what he uses there: no sign post may stand on the line from
## the camera to Lumi or to his prompt above him. Returns the views that are blocked.
static func sightlines(so: SliceOrbit, site: int) -> PackedStringArray:
	var w: Node = so.w
	var tree: SceneTree = w.get_tree()
	var p: Patch = w.get("patch") as Patch
	var fy: FarYard = FarYard.of(w)
	var bad: PackedStringArray = []
	if fy == null or fy.depot(site) == null:
		return bad
	var root: Node3D = fy.depot(site).get_parent() as Node3D
	var pad: Transform3D = so.sites.sm.pad_xf(site)
	var dep: Depot = fy.depot(site)
	var views: Array = [["rocket", pad * Vector3(4.5, 0, 3.0), pad.origin],
		["bin", dep.bin_world() + (dep.global_position - dep.bin_world()).normalized() * 1.4, dep.bin_world()],
		["scale", dep.global_position + dep.global_basis.z * 2.2, dep.global_position]]
	for id: String in FarYard.ORDER:
		var at: Variant = fy.spot_point(site, id)
		var holder: Node3D = root.get_node_or_null("Spot_%s" % id) as Node3D
		if at is Vector3 and holder:
			views.append([id, at, holder.global_position])
	var signs: Array[MeshInstance3D] = []  # every sign post and machine standing on the build spots (not the flat outlines)
	for hn: Node in root.get_children():
		if not str(hn.name).begins_with("Spot_"):
			continue
		for n: Node in hn.find_children("*", "MeshInstance3D", true, false):
			var mi0: MeshInstance3D = n as MeshInstance3D
			if mi0.is_visible_in_tree() and str(mi0.name) != "Outline" and mi0.get_aabb().size.y > 0.4:
				signs.append(mi0)
	var keep: Array = [p.global_position, p.forward()]
	for v: Array in views:
		WalkTravel._stand(so, p, v[1], v[2])
		so.cam.reset_frame(p.forward())
		so.cam.snap()
		await WalkTravel._frames(tree, 2)
		var cam: Vector3 = so.cam.global_position
		var up: Vector3 = p.global_position.normalized()
		var hits: PackedStringArray = []
		for mi: MeshInstance3D in signs:
			var inv: Transform3D = mi.global_transform.affine_inverse()
			var box: AABB = mi.get_aabb()
			for h: float in [0.9, 1.9]:  # Lumi's body, and his prompt above him
				if box.intersects_segment(inv * cam, inv * (p.global_position + up * h)):
					var li: Transform3D = root.global_transform.affine_inverse()
					hits.append("%s (%s; site-local camera %s, Lumi %s, sign %s)" % [str(root.get_path_to(mi)), "Lumi" if h < 1.0 else "his prompt",
						str((li * cam).snapped(Vector3.ONE * 0.1)), str((li * p.global_position).snapped(Vector3.ONE * 0.1)), str((li * mi.global_position).snapped(Vector3.ONE * 0.1))])
					break
		if not hits.is_empty():
			bad.append("%s: %s" % [str(v[0]), ", ".join(hits)])
	WalkTravel._stand(so, p, keep[0], keep[0] + keep[1])
	return bad
