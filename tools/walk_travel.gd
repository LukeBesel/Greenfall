class_name WalkTravel
extends RefCounted
## [v9c] Goal audit (owner, 2026-11-13: "all goals ... need to work ... visual and easy to
## understand"): the travel steps played the way a player does, with real input events (the keys
## and mouse buttons the input map binds, and mouse clicks on the real buttons), on the real globe.
##   station 2 (hub_fly_2, hub_wake_2): the rocket marked; E at the rocket opens its list; a click on
##     Fly by NEXT STOP flies (E skips); control comes back on landing, the title says why we came,
##     the card turns to "Wake station 2", the hex to clean is outlined; real scooping there counts;
##     a Ledger dump on a cleaned hex keeps the count; E at the landmark without the price is refused
##     with a line, with it wakes the station (reward, next step, nothing left on the landmark);
##     with no cubes at all the rocket still flies home.
##   station 6 (rocket_tier_3, hub_fly_6, hub_wake_6, home_drive_5): the far station is locked in
##     the rocket's list (Fly off, a reason) until Mk III; E at the bench opens on the rocket's row
##     and a click upgrades it; the flight, the wake as above; with six stations awake the rocket's
##     list offers Other planets; the system map comes up on Ochre with Build the drive; the drive is
##     built by a click; the "to be continued" card comes, any key closes it and the game goes on.
## How the start states are made (dev, a state a player is really in; checked against an autoplay
## run's steps): the card set to the step, the price the step asks for given (as the autoplay bot had
## it at that step), stations 2-5 woken free for the late part, and the hexes past the first real
## scoop cleared by the crews' own cell clean (the cleaning itself is the hex audit's to prove;
## --hex-audit-hubs shows each far pad has its four finishable hexes).
## --walk-travel[=S] (after S s, default 8): prints [walk-travel] lines, exit 1 on a failure.
## --walk-travel-save: stops at station 2 mid-chain (two hexes cleaned) and saves; a second run
## with --walk-travel-resume (same --save-dir, no --fresh) checks the station came back and finishes it.
## tools/check_exit.sh runs all three.

static var _toasts: Array[String] = []
static var _fails: Array[String] = []
const TAG: String = "[walk-travel]"


static func run_dev(so: SliceOrbit) -> void:
	var tree: SceneTree = so.w.get_tree()
	await tree.create_timer(DevHooks.get_f("walk-travel", 8.0)).timeout
	var w: Node = so.w
	for k: int in 240:
		if not bool(w.get("building")) and w.get("objectives") != null and so.sites != null and so.sites.purpose != null:
			break
		await tree.create_timer(0.5).timeout
	EventBus.toast.connect(func(t: String, _k: String) -> void: _toasts.append(t))
	GameState.flags["onboard_brief"] = true
	GameState.flags["tutorial_step"] = Tutorial.STEPS.size()
	var tut: Tutorial = w.get("tutorial") as Tutorial
	if tut:
		tut.step = Tutorial.STEPS.size()
	if DevHooks.has("walk-travel-resume"):
		await _resume(so)
	elif DevHooks.has("walk-travel-end"):
		await _after_end(so)
	else:
		await _station_two(so)
		if not DevHooks.has("walk-travel-save"):
			await _late(so)
	_end(tree)


static func _end(tree: SceneTree) -> void:
	print("%s %s" % [TAG, "PASS" if _fails.is_empty() else "FAIL: " + "; ".join(_fails)])
	await tree.create_timer(1.0).timeout
	tree.quit(0 if _fails.is_empty() else 1)


# --- Station 2 ---------------------------------------------------------------------------------

static func _station_two(so: SliceOrbit) -> void:
	var w: Node = so.w
	var tree: SceneTree = w.get_tree()
	var ob: Objectives = w.get("objectives") as Objectives
	var os_: OrbitSites = so.sites
	var hp: HubPurpose = os_.purpose
	var p: Patch = w.get("patch") as Patch
	# The state the card reaches hub_fly_2 in: the seed planted (the rocket comes with that step).
	_set_story(ob, "hub_fly_2")
	GameState.stats["plants_planted"] = maxf(float(GameState.stats.get("plants_planted", 0)), 1.0)
	GameState.flags["seeds_unlocked"] = true
	YardBuilds.state()["bench"] = true  # the workbench was fixed in the first minutes
	GameState.stats["hexes_cleaned"] = maxf(float(GameState.stats.get("hexes_cleaned", 0)), 3.0)
	var site: int = HubPlan.next_site(hp.planet)
	_check(site == 9, "the next station is Garden Row (site %d)" % site)
	var cost: Dictionary = HubPlan.wake_cost(hp.planet)
	# 1. Short of the station's price: no beam on the rocket yet, the card says what is missing.
	_set_money(float(cost.get("cubes", 0)) * 0.5, 0.0)
	await _wait(tree, 1.6)
	_check(os_.rocket_spot.visible, "the rocket stands on the pad once the seed is planted")
	var tgt: Dictionary = ob.step_target(ob.current())
	_check(str(ob.current().get("id", "")) == "hub_fly_2" and tgt.get("pos", null) == null and ob.situation != "",
		"short of the price: no beam on the rocket, the card says what is missing ('%s')" % ob.situation)
	# 2. Enough for the station: the beam stands on the rocket.
	_set_money(float(cost.get("cubes", 0)) + 300.0, float(cost.get("parts", 0)) + 6.0)
	await _wait(tree, 1.6)
	tgt = ob.step_target(ob.current())
	_check(tgt.get("pos", null) is Vector3 and (tgt["pos"] as Vector3).distance_to(os_.rocket_spot.global_position) < 1.0
		and ob.waypoint_target() is Vector3, "with the price: the beam stands on the rocket (%s, card '%s')" % [str(tgt), str(ob.current().get("id", ""))])
	_stand(so, p, os_.sm.pad_xf(0) * Vector3(9.0, 0, 7.0), os_.rocket_spot.global_position)
	await _shot(tree, "1_rocket_beam")
	# 3. E at the rocket opens its list; a click on Fly by NEXT STOP flies there.
	await _fly_by_click(so, site, true)
	_check(GameState.stats.get("hubs_seen", 0) >= 1 and str(ob.current().get("id", "")) == "hub_wake_2",
		"landed: hubs_seen 1, the card says '%s'" % ob.texts(ob.current())[0])
	# 4. The station's chain: clean 4 hexes, with the hex outlined (not a beam on the landmark).
	for k: int in 12:  # the card's next-step beat first
		await _wait(tree, 0.5)
		if ob.target_hex >= 0:
			break
	var st: Dictionary = hp.current_step(site)
	_check(str(st.get("do", "")) == "clean" and hp.card_text.contains("0 / %d" % int(st.get("need", 0))),
		"the station's card: '%s'" % hp.card_text)
	tgt = ob.step_target(ob.current())
	_check(str(tgt.get("to", "")) == "hex" and ob.target_hex >= 0 and _in_region(os_, site, ob.target_hex),
		"the hex to clean is outlined, in the station's ground (hex %d)" % ob.target_hex)
	if ob.target_hex < 0:
		var f: SphereField = so.globe.field
		for ring: int in [2, 3, 4, 6, 8]:
			var n_ok: int = 0
			var n_d: int = 0
			for hid: int in f.hexes_near(p.global_position, ring):
				if not f.is_clean(hid) and f.hex_hub[hid] == 0 and not f.is_water(hid):
					n_d += 1
					n_ok += 1 if ob._hex_ok(hid) else 0
			print("%s   ring %d: %d dirty land hexes, %d the card would outline" % [TAG, ring, n_d, n_ok])
	await _wait(tree, 4.0)
	await _shot(tree, "2_station_card")
	# Real scooping at the station.
	await _scoop_real(so, p)
	# The rest of the hexes: the crews' cell clean (see the header), two first.
	_clean_cells(os_, site, 2)
	await _wait(tree, 1.2)
	st = hp.current_step(site)
	_check(int(st.get("have", 0)) >= 2, "two hexes clean: the card counts %d / %d" % [int(st.get("have", 0)), int(st.get("need", 0))])
	if DevHooks.has("walk-travel-save"):
		print("%s saved mid-chain at site %d: %s" % [TAG, site, str(SaveManager.save_game())])
		return
	await _finish_station(so, site, true)
	# 6. Stranded? No cubes at all: the rocket still flies home.
	_set_money(0.0, 0.0)
	await _fly_by_click(so, 0, false)
	_check(hp.site == 0 or os_.sm.nearest == 0, "with no cubes the rocket flies home (at site %d)" % os_.sm.nearest)


## The rest of a station's chain from wherever it stands, then the wake by E.
static func _finish_station(so: SliceOrbit, site: int, ledger: bool) -> void:
	var w: Node = so.w
	var tree: SceneTree = w.get_tree()
	var ob: Objectives = w.get("objectives") as Objectives
	var os_: OrbitSites = so.sites
	var hp: HubPurpose = os_.purpose
	var p: Patch = w.get("patch") as Patch
	var step_id: String = str(ob.current().get("id", ""))
	var st: Dictionary = hp.current_step(site)
	if str(st.get("do", "")) == "clean":
		_clean_cells(os_, site, int(st.get("need", 0)) - int(st.get("have", 0)))
	await _wait(tree, 1.2)
	st = hp.current_step(site)
	if str(st.get("do", "")) == "outposts":
		var op: Variant = hp.outpost_target()
		var wt: Variant = ob.waypoint_target()
		_check(op is Vector3 and wt is Vector3 and (wt as Vector3).distance_to(op) < 1.0, "the outpost step: the beam stands on the ruined outpost")
		var ops: Outposts = w.get("outposts") as Outposts
		if op is Vector3 and ops and ops.hub_index == site:
			# Its hex cleared (the crews' cell clean), then E by it with the price: repaired.
			var k: int = -1
			for i: int in ops.items.size():
				if (ops.items[i] as Node3D).global_position.distance_to(op) < 0.5:
					k = i
			var oc: Variant = os_.so.get("crews")
			(oc as Object).call("work_cell", int(ops.spots[k]["hex"]), 0.0)
			var rc: Dictionary = ops.repair_cost(k)
			_set_money(float(rc.get("cubes", 0)) + 10.0, float(rc.get("parts", 0)) + 2.0)
			var o3: Vector3 = op
			_stand(so, p, o3 + SphereGrid.frame(o3.normalized()).x * 2.5, o3)
			await _frames(tree, 6)
			print("%s   by the outpost: '%s'" % [TAG, so.interact_prompt(p)])
			await _tap(tree, "interact")
			await _wait(tree, 4.0)
			_check(ops.repaired_count() >= 1, "E by the cleared outpost with the price repairs it")
		else:
			HubPlan.state(site)["outposts"] = int(st.get("need", 1))
		await _wait(tree, 1.2)
		st = hp.current_step(site)
	_check(str(st.get("do", "")) == "wake", "the chain is done: the card asks to wake the landmark ('%s')" % hp.card_text)
	if ledger:  # a Ledger dump on a cleaned hex here: the count stays done
		var c: int = _a_clean_cell(os_, site)
		if c >= 0:
			os_.sm.cells.set_junk(c, 1.0)
			await _wait(tree, 1.2)
			_check(hp.can_wake(site), "a Ledger dump on a cleaned hex keeps the station ready (step '%s')" % str(hp.current_step(site).get("do", "")))
			os_.sm.cells.set_junk(c, 0.0)
	var lm: Dictionary = hp.landmark(site)
	_check(not lm.is_empty(), "the landmark stands")
	if lm.is_empty():
		return
	var tgt: Dictionary = ob.step_target(ob.current())
	_check(tgt.get("pos", null) is Vector3 and (tgt["pos"] as Vector3).distance_to(lm["pos"]) < 1.0, "the beam stands on the landmark")
	var tr_: TargetReach = TargetReach.for_world(w, true)
	var open_at: Vector3 = tr_.open_spot(lm["pos"]) if tr_ else lm["pos"]
	_stand(so, p, open_at, lm["pos"])
	await _frames(tree, 6)
	var ia: Interactables = w.get("interactables") as Interactables
	var seen: String = ia.prompt(p.global_position) if ia else ""
	_check(seen.begins_with("E") and seen == hp.landmark_prompt(), "by the landmark the prompt says '%s'" % seen)
	await _shot(tree, "landmark_%d" % site)
	# Short of the price: E is refused with a line.
	var cost: Dictionary = HubPlan.wake_cost(hp.planet)
	_set_money(float(cost.get("cubes", 0)) * 0.5, float(cost.get("parts", 0)))
	_toasts.clear()
	print("%s   before E: woken %s, cubes %s, afford %s, prompt '%s'" % [TAG, HubPlan.woken(site), GameState.get_currency("cubes").to_float(), GameState.can_afford_all(cost), ia.prompt(p.global_position)])
	await _tap(tree, "interact")
	await _frames(tree, 4)
	_check(not HubPlan.woken(site) and _said("needs"), "E without the price: not woken, a line why (%s)" % _quote("needs"))
	_set_money(float(cost.get("cubes", 0)) + 50.0, float(cost.get("parts", 0)) + 2.0)
	var hs0: int = HubPlan.restored_main(hp.planet)
	_toasts.clear()
	await _tap(tree, "interact")
	await _frames(tree, 4)
	_check(HubPlan.woken(site) and HubPlan.restored_main(hp.planet) == hs0 + 1 and _said("awake"),
		"E with the price wakes it: bases %d, a line (%s)" % [HubPlan.restored_main(hp.planet), _quote("awake")])
	await _wait(tree, 5.0)
	var nid: String = str(ob.current().get("id", ""))
	_check(nid != step_id, "the card moves on: '%s' -> '%s'" % [step_id, nid])
	var wt: Variant = ob.waypoint_target()
	_check(not (wt is Vector3 and (wt as Vector3).distance_to(lm["pos"]) < 1.0), "nothing points at the woken landmark")
	_check(hp.bench_point() is Vector3, "a field bench stands by the pad")


# --- Save mid-station, reload ------------------------------------------------------------------

static func _resume(so: SliceOrbit) -> void:
	var w: Node = so.w
	var tree: SceneTree = w.get_tree()
	var ob: Objectives = w.get("objectives") as Objectives
	var os_: OrbitSites = so.sites
	var hp: HubPurpose = os_.purpose
	var site: int = 9
	for k: int in 120:
		if hp.site == site and not hp.landmark(site).is_empty():
			break
		await tree.create_timer(0.5).timeout
	_check(hp.site == site, "reloaded at Garden Row (at site %d)" % hp.site)
	_check(str(ob.current().get("id", "")) == "hub_wake_2", "the card is still 'Wake station 2' (%s)" % str(ob.current().get("id", "")))
	var st: Dictionary = hp.current_step(site)
	_check(str(st.get("do", "")) == "clean" and int(st.get("have", 0)) >= 2, "the count came back: %d / %d" % [int(st.get("have", 0)), int(st.get("need", 0))])
	_check(os_.rocket_spot.visible and os_.rocket_site() == site, "the rocket waits on this station's pad")
	await _finish_station(so, site, false)


## A save made after the "to be continued" card, loaded again (Continue): where Lumi stands, the card
## does not come back, the goals go on, the rocket is at hand.
static func _after_end(so: SliceOrbit) -> void:
	var w: Node = so.w
	var tree: SceneTree = w.get_tree()
	var ob: Objectives = w.get("objectives") as Objectives
	var os_: OrbitSites = so.sites
	var p: Patch = w.get("patch") as Patch
	await _wait(tree, 20.0)
	var hd: HomewardDirector = HomewardDirector.of(w)
	_check(hd != null and hd.tbc != null and not hd.tbc.is_open and not tree.paused, "the end card does not come back")
	_check(Homeward.drive() >= 5 and HubPlan.restored_main(os_.sm.planet_id) == 6, "the drive and the six stations are kept")
	var gid: String = str(ob.current().get("id", ""))
	_check(gid != "" and gid != "home_drive_5", "the card goes on ('%s')" % gid)
	var at: int = os_.sm.nearest
	_check(p.global_position.distance_to(os_.sm.pad_xf(at).origin) < 60.0 and os_.rocket_site() == at and os_.rocket_spot.visible,
		"Lumi is back by the rocket at %s (%.0f m from its pad)" % [HubPlan.hub_name(os_.sm.planet_id, at), p.global_position.distance_to(os_.sm.pad_xf(at).origin)])
	_check((p.input as PlayerInput).enabled, "Lumi can move")


# --- The late stations, the drive, the end card ------------------------------------------------

static func _late(so: SliceOrbit) -> void:
	var w: Node = so.w
	var tree: SceneTree = w.get_tree()
	var ob: Objectives = w.get("objectives") as Objectives
	var os_: OrbitSites = so.sites
	var hp: HubPurpose = os_.purpose
	var p: Patch = w.get("patch") as Patch
	# Stations 3-5 woken (as the card had them), Mk II, home at base 5: the goal "Upgrade to Mk III".
	# Station 3 (Gantry Works: its chain has an outpost to repair), played like station 2.
	_set_story(ob, "hub_fly_3")
	var c3: Dictionary = HubPlan.wake_cost(hp.planet)
	_set_money(float(c3.get("cubes", 0)) + 300.0, float(c3.get("parts", 0)) + 6.0)
	await _wait(tree, 1.6)
	await _fly_by_click(so, 7, true)
	_check(str(ob.current().get("id", "")) == "hub_wake_3", "landed: the card says '%s'" % ob.texts(ob.current())[0])
	await _finish_station(so, 7, false)
	await _fly_by_click(so, 0, false)
	for s: int in [8, 2]:  # flown to and woken, as the card had them
		HubPlan.state(s)["seen"] = true
		hp.wake(s, true)
	GameState.stats["hubs_seen"] = 4
	var hub: Hub = w.get("hub") as Hub  # the home base at level 5 (base_5 comes before hub_fly_6)
	if hub:
		hub.level = 5
		hub.level_changed.emit(5)
	GameState.world["hub_level"] = 5
	GameState.stats["hubs_woken"] = 4
	GameState.flags["rocket_tier"] = 2
	GameState.stats["rocket_tier"] = 2
	_set_goal(ob, "rocket_tier_3")
	await _wait(tree, 1.6)
	_check(str(ob.current().get("id", "")) == "rocket_tier_3", "the card: '%s'" % ob.texts(ob.current())[0])
	# The far station is locked in the rocket's list.
	var site: int = HubPlan.next_site(hp.planet)
	_check(site == 4, "the last station is Stack Works (site %d)" % site)
	await _stand_at_rocket(so)
	await _tap(tree, "interact")
	await _frames(tree, 4)
	var fly: Button = _fly_button(os_.picker, HubPlan.hub_name(hp.planet, site))
	_check(fly != null and fly.disabled and _list_has(os_.picker, "Upgrade the rocket"), "at Mk II the last station's Fly is off, with the reason")
	await _tap(tree, "ui_cancel")
	await _frames(tree, 4)
	_check(not os_.picker.is_open, "Esc closes the rocket's list")
	# The beam: the bench, on the rocket's row.
	var tgt: Dictionary = ob.step_target(ob.current())
	_check(str(tgt.get("to", "")) == "bench" and (tgt.get("row", []) as Array) == ["patch", "rocket_tier"], "the step points at the bench's rocket row (%s)" % str(tgt))
	var nd: Dictionary = RocketTiers.next_def()
	_set_money(float((nd.get("cost", {}) as Dictionary).get("cubes", 0)) + 100.0, float((nd.get("cost", {}) as Dictionary).get("parts", 0)) + 5.0)
	var bp: Vector3 = so.bench_position()
	_stand(so, p, bp + (bp - os_.sm.pad_xf(0).origin).normalized() * 1.6, bp)
	await _frames(tree, 6)
	print("%s   by the bench: '%s'" % [TAG, so.interact_prompt(p)])
	await _tap(tree, "interact")
	await _wait(tree, 1.0)
	var up: UpgradesScreen = w.get("upgrades") as UpgradesScreen
	_check(up != null and up.is_open, "E at the bench opens it")
	var ub: Button = _find_button(up, "Upgrade the rocket")
	_check(ub != null and not ub.disabled, "the bench shows the rocket's row with its button")
	await _shot(tree, "3_bench_rocket")
	if ub == null and up:
		var names: PackedStringArray = []
		for b: Node in up.find_children("*", "Button", true, false):
			if (b as Button).is_visible_in_tree():
				names.append((b as Button).text)
		print("%s   bench buttons: %s; tab %s, row %s" % [TAG, ", ".join(names), str(up.get("_tab")), str(up.objective_row())])
	if ub:
		await _click(tree, ub)
		await _wait(tree, 0.6)
	_check(RocketTiers.tier() == 3, "a click upgrades the rocket to Mk III (Mk %d)" % RocketTiers.tier())
	if up and up.is_open:
		await _tap(tree, "ui_cancel")
		await _wait(tree, 0.6)
	await _wait(tree, 5.0)
	# Through to "Fly to the next station" (the goals between are the bench's and the garden's).
	_set_goal(ob, "hub_fly_6")
	var fc: Dictionary = HubPlan.wake_cost(hp.planet)
	_set_money(float(fc.get("cubes", 0)) + 500.0, float(fc.get("parts", 0)) + 10.0)
	await _wait(tree, 1.6)
	_check(str(ob.current().get("id", "")) == "hub_fly_6", "the card: '%s'" % ob.texts(ob.current())[0])
	tgt = ob.step_target(ob.current())
	_check(tgt.get("pos", null) is Vector3 and (tgt["pos"] as Vector3).distance_to(os_.rocket_spot.global_position) < 1.0, "the beam stands on the rocket")
	await _fly_by_click(so, site, true)
	_check(str(ob.current().get("id", "")) == "hub_wake_6", "landed: the card says '%s'" % ob.texts(ob.current())[0])
	for k: int in 12:
		await _wait(tree, 0.5)
		if ob.target_hex >= 0:
			break
	tgt = ob.step_target(ob.current())
	_check(str(tgt.get("to", "")) == "hex" and ob.target_hex >= 0, "the hex to clean is outlined")
	await _finish_station(so, site, true)
	_check(HubPlan.restored_main(hp.planet) == HubPlan.main_total(hp.planet), "six of six stations awake")
	# The drive: from the rocket's list, Other planets, the map comes up on the planet that needs it.
	for k: int in 40:
		if str(ob.current().get("id", "")) == "home_drive_5":
			break
		await _wait(tree, 0.5)
	_check(str(ob.current().get("id", "")) == "home_drive_5", "the card: '%s'" % ob.texts(ob.current())[0])
	_check(Homeward.system_open(), "six stations open the way off Verdance")
	var dc: Dictionary = Homeward.next_drive().get("cost", {})
	_set_money(float(dc.get("cubes", 0)) + 1000.0, float(dc.get("parts", 0)) + 10.0)
	await _wait(tree, 1.6)
	tgt = ob.step_target(ob.current())
	_check(tgt.get("pos", null) is Vector3 and (tgt["pos"] as Vector3).distance_to(os_.rocket_spot.global_position) < 1.0, "the drive step: the beam stands on the rocket")
	await _stand_at_rocket(so)
	await _tap(tree, "interact")
	await _frames(tree, 4)
	var ob_btn: Button = _find_button(os_.picker, "Other planets")
	_check(ob_btn != null, "the rocket's list offers Other planets")
	if ob_btn == null:
		return
	await _click(tree, ob_btn)
	await _wait(tree, 1.5)
	var sm_: SystemMap = SystemMap.shared(w)
	var hd: HomewardDirector = HomewardDirector.of(w)
	if hd and hd.map:
		sm_ = hd.map
	_check(sm_.is_open and (sm_.selected == 1 or Homeward.discovered(1) == false), "the system map opens (on %s; Ochre charted %s)" % [Homeward.planet_name(sm_.selected), Homeward.discovered(1)])
	await _shot(tree, "4_system_map")
	var db: Button = _find_button(sm_, "Build the drive")
	_check(db != null and not db.disabled, "Build the drive shows, ready")
	if db:
		await _click(tree, db)
		await _wait(tree, 0.6)
	_check(Homeward.drive() >= 5, "a click builds the drive (Mk %d)" % Homeward.drive())
	await _tap(tree, "ui_cancel")
	await _wait(tree, 1.0)
	_check(not sm_.is_open, "Esc closes the map")
	print("%s   input %s, modal %s, paused %s" % [TAG, (p.input as PlayerInput).enabled, so.any_modal_open(), tree.paused])
	# The end card, once WREN is done; any key closes it; the game goes on.
	var tbc: ToBeContinued = hd.tbc if hd else null
	Engine.time_scale = 4.0
	for k: int in 240:
		if tbc and tbc.is_open:
			break
		await tree.create_timer(0.5).timeout
	Engine.time_scale = 1.0
	_check(tbc != null and tbc.is_open, "the 'to be continued' card comes")
	await _shot(tree, "5_tbc")
	print("%s   input %s, modal %s, paused %s" % [TAG, (p.input as PlayerInput).enabled, so.any_modal_open(), tree.paused])
	await _wait(tree, 1.6)
	await _tap(tree, "interact")
	await _frames(tree, 4)
	_check(tbc != null and not tbc.is_open and not tree.paused, "E closes the card, the game runs on")
	_check(not os_.picker.is_open, "the key that closed the card did not also open the rocket's list")
	print("%s   input %s, modal %s, paused %s" % [TAG, (p.input as PlayerInput).enabled, so.any_modal_open(), tree.paused])
	await _wait(tree, 5.0)
	var nxt: String = ob.texts(ob.current())[0] if not ob.current().is_empty() else ""
	_check(nxt != "" and (p.input as PlayerInput).enabled, "a next goal on the card ('%s'), Lumi can move" % nxt)
	print("%s end: %s, save %s" % [TAG, ob.texts(ob.current())[0] if not ob.current().is_empty() else "", str(SaveManager.save_game())])


# --- Steps ---------------------------------------------------------------------------------------

## E at the rocket, a click on the station's Fly button, E skips the flight; checks the landing.
static func _fly_by_click(so: SliceOrbit, to_site: int, first: bool) -> void:
	var w: Node = so.w
	var tree: SceneTree = w.get_tree()
	var os_: OrbitSites = so.sites
	var hp: HubPurpose = os_.purpose
	var p: Patch = w.get("patch") as Patch
	await _stand_at_rocket(so)
	var ia: Interactables = w.get("interactables") as Interactables
	var seen: String = ia.prompt(p.global_position) if ia else ""
	_check(seen == os_.rocket_prompt(), "by the rocket the prompt says '%s'" % seen)
	if seen != os_.rocket_prompt() and ia:  # what stands nearer
		for e: Dictionary in ia._items:
			var n: Variant = e["node"]
			if is_instance_valid(n) and (n as Node3D).is_inside_tree() and (n as Node3D).global_position.distance_to(p.global_position) < 14.0:
				print("%s   near: %s %.1f m r %.1f visible %s prompt '%s'" % [TAG, (n as Node).get_path(), (n as Node3D).global_position.distance_to(p.global_position), float(e["r"]), (n as Node3D).is_visible_in_tree(),
					str((e["prompt"] as Callable).call()) if e["prompt"] is Callable else str(e["prompt"])])
		print("%s   lumi at %s, rocket spot %s" % [TAG, p.global_position, os_.rocket_spot.global_position])
	await _tap(tree, "interact")
	await _frames(tree, 4)
	_check(os_.picker.is_open, "E at the rocket opens its list")
	await _shot(tree, "picker_%d" % to_site)
	var nm: String = HubPlan.hub_name(hp.planet, to_site)
	var b: Button = _fly_button(os_.picker, nm)
	_check(b != null and not b.disabled, "%s has a Fly button%s" % [nm, " by NEXT STOP" if first else ""])
	if first:
		_check(_row_has(os_.picker, nm, "NEXT STOP"), "the station is tagged NEXT STOP")
	if b == null:
		os_.picker.close()
		return
	await _click(tree, b)
	await _frames(tree, 3)
	_check(os_.hop.flying, "the click on Fly lifts off")
	await _wait(tree, 1.0)
	await _tap(tree, "interact")  # skip the flight
	for k: int in 240:
		if not os_.hop.flying:
			break
		await tree.create_timer(0.5).timeout
	await _wait(tree, 1.0)
	_check(not os_.hop.flying and p.visible and (p.input as PlayerInput).enabled and p.process_mode != Node.PROCESS_MODE_DISABLED,
		"landed at %s: Lumi back in control" % nm)
	_check(p.global_position.distance_to(os_.sm.pad_xf(to_site).origin) < 12.0, "Lumi stands by the pad (%.1f m)" % p.global_position.distance_to(os_.sm.pad_xf(to_site).origin))
	if to_site > 0 and first:
		await _shot(tree, "landed_%d" % to_site)
		_check(hp.title_node() != null and hp.title_reason != "", "the arrival title with why we came ('%s')" % hp.title_reason)


static func _stand_at_rocket(so: SliceOrbit) -> void:
	var os_: OrbitSites = so.sites
	var p: Patch = so.w.get("patch") as Patch
	var xf: Transform3D = os_.sm.pad_xf(os_.rocket_site())
	_stand(so, p, xf * Vector3(4.5, 0, 3.0), xf.origin)
	await _frames(so.w.get_tree(), 6)


## A few real scoops at the station: Lumi beside a piece of its junk, facing it, the button held.
static func _scoop_real(so: SliceOrbit, p: Patch) -> void:
	var tree: SceneTree = so.w.get_tree()
	var f: SphereField = so.globe.field
	var ob: Objectives = so.w.get("objectives") as Objectives
	var h: int = ob.target_hex
	if h < 0:
		_check(false, "no hex to scoop in")
		return
	if InputMap.has_action("tool_scoop"):
		await _tap(tree, "tool_scoop")
	# Walk over first (stand there): a hex's pieces are laid round Lumi only.
	var hc: Vector3 = f.hex_center(h)
	_stand(so, p, hc + SphereGrid.frame(hc.normalized()).x * 2.0, hc)
	for k: int in 20:
		await _wait(tree, 0.5)
		if _alive_in(f, h) > 0:
			break
	var n0: float = float(GameState.stats.get("junk_scooped", 0))
	var r0: float = f.removed_fraction(h)
	for k: int in 6:
		var pid: int = -1
		var best: float = INF
		for q: int in f.hex_pieces[h]:
			if f.piece_alive[q] == 0:
				continue
			var d: float = f.piece_pos[q].distance_to(p.global_position)
			if d < best:
				best = d
				pid = q
		if pid < 0:
			break
		var pp: Vector3 = f.piece_pos[pid]
		var up: Vector3 = pp.normalized()
		var side: Vector3 = SphereGrid.frame(up).x
		_stand(so, p, pp + side * 1.1, pp)
		await _frames(tree, 3)
		if k == 0:
			print("%s   scoop: piece %d %.1f m from Lumi (ground %.2f m off), hex %d pieces %d, tool %d, size %d lift %d" % [TAG, pid, pp.distance_to(p.global_position), pp.length() - so.globe.terrain.ground(up).length(),
				h, f.hex_pieces[h].size(), int(p.tool), Pace.piece_size(f, pid), Pace.lift_class()])
		await _hold(tree, "scoop", 1.2)
	var n1: float = float(GameState.stats.get("junk_scooped", 0))
	_check(n1 > n0 or f.removed_fraction(h) > r0, "real scoops at the station take its junk (%d pieces, hex %.0f%% -> %.0f%%)" % [int(n1 - n0), r0 * 100.0, f.removed_fraction(h) * 100.0])


static func _alive_in(f: SphereField, h: int) -> int:
	var n: int = 0
	for q: int in f.hex_pieces[h]:
		n += 1 if f.piece_alive[q] != 0 else 0
	return n


static func _clean_cells(os_: OrbitSites, site: int, n: int) -> void:
	var crews: Variant = os_.so.get("crews")
	var f: SphereField = os_.so.globe.field
	var left: int = n
	for c: int in os_.sm.regions[site]:
		if left <= 0:
			break
		if os_.sm.cells.state[c] == 5 or os_.sm.cells.has_flag(c, SphereCells.F_HUB) or f.hex_hub[c] != 0 or not os_.sm.cells.is_dirty(c):
			continue
		(crews as Object).call("work_cell", c, 0.0)
		os_.so.on_hex_clean(c, true)
		left -= 1


static func _a_clean_cell(os_: OrbitSites, site: int) -> int:
	var base: int = int(HubPlan.peek(site).get("base", 0))
	var seen: int = 0
	for c: int in os_.sm.regions[site]:
		if os_.sm.cells.state[c] == 5 or os_.sm.cells.has_flag(c, SphereCells.F_HUB):
			continue
		if not os_.sm.cells.is_dirty(c):
			seen += 1
			if seen > base:
				return c
	return -1


static func _in_region(os_: OrbitSites, site: int, h: int) -> bool:
	return os_.sm.regions[site].has(h)


# --- State (dev: the start of a step) ------------------------------------------------------------

static func _set_story(ob: Objectives, id: String) -> void:
	var idx: int = ob.chain.map(func(d: Dictionary) -> String: return str(d["id"])).find(id)
	ob.step = idx
	ob.revealed = true
	GameState.flags["objective_step"] = idx


## The card on goal `id`: the story done, every goal before it done.
static func _set_goal(ob: Objectives, id: String) -> void:
	ob.step = ob.chain.size()
	ob.revealed = true
	GameState.flags["objective_step"] = ob.step
	var g: Goals = ob.goals()
	var arr: Array = GameState.flags.get("goals_done", [])
	for i: int in g.chain.size():
		var gid: String = str(g.chain[i]["id"])
		if gid == id:
			break
		if not arr.has(gid):
			arr.append(gid)
	GameState.flags["goals_done"] = arr
	g.load_chain()


static func _set_money(cubes: float, parts: float) -> void:
	GameState.currencies["cubes"] = BigNum.from_float(maxf(cubes, 0.0))
	GameState.currencies["parts"] = BigNum.from_float(maxf(parts, 0.0))
	EventBus.currency_changed.emit("cubes", GameState.currencies["cubes"])


# --- UI ----------------------------------------------------------------------------------------

static func _fly_button(picker: RocketPicker, hub_name: String) -> Button:
	var row: Control = _row_of(picker, hub_name)
	return _find_button(row, "Fly") if row else null


static func _row_of(picker: RocketPicker, hub_name: String) -> Control:
	for n: Node in picker.find_children("*", "PanelContainer", true, false):
		for l: Node in n.find_children("*", "Label", true, false):
			if (l as Label).text == hub_name:
				return n as Control
	return null


static func _row_has(picker: RocketPicker, hub_name: String, text: String) -> bool:
	var row: Control = _row_of(picker, hub_name)
	if row == null:
		return false
	for l: Node in row.find_children("*", "Label", true, false):
		if text in (l as Label).text:
			return true
	return false


static func _list_has(root: Node, text: String) -> bool:
	for l: Node in root.find_children("*", "Label", true, false):
		if text in (l as Label).text and (l as Label).is_visible_in_tree():
			return true
	return false


static func _find_button(root: Node, text: String) -> Button:
	if root == null:
		return null
	for b: Node in root.find_children("*", "Button", true, false):
		if text in (b as Button).text and (b as Button).is_visible_in_tree():
			return b as Button
	return null


## A real left click on the control's middle (mouse moved there, pressed, released).
static func _click(tree: SceneTree, c: Control) -> void:
	var vp: Viewport = c.get_viewport()
	# What a player can see: inside the screen and inside every scrolling list it sits in.
	var mid: Vector2 = c.get_global_rect().get_center()
	var shown: bool = vp.get_visible_rect().has_point(c.get_global_transform_with_canvas() * (c.size * 0.5))
	var n: Node = c.get_parent()
	while n != null and n is Control:
		if n is ScrollContainer and not (n as Control).get_global_rect().has_point(mid):
			shown = false
		n = n.get_parent()
	_check(shown, "'%s' is in view when clicked" % (c as Button).text if c is Button else c.name)
	var at: Vector2 = vp.get_final_transform() * (c.get_global_transform_with_canvas() * (c.size * 0.5))
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	Input.parse_input_event(mm)
	await tree.process_frame
	for down: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = at
		ev.global_position = at
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await tree.process_frame
	await tree.process_frame


# --- Input and helpers (as tools/seed_walk.gd) ---------------------------------------------------

## --walk-travel-shots=PREFIX (a rendered run): saves PREFIX_<name>.png at the step's moments.
static func _shot(tree: SceneTree, name: String) -> void:
	if not DevHooks.has("walk-travel-shots"):
		return
	await DevHooks.wait_wall_for(2.5)
	await RenderingServer.frame_post_draw
	DevHooks.save_viewport("%s_%s.png" % [DevHooks.get_s("walk-travel-shots", "screenshots/v9/travel"), name])


static func _quote(t: String) -> String:
	for s: String in _toasts:
		if t.to_lower() in s.to_lower():
			return s
	return "nothing said"


static func _said(t: String) -> bool:
	for s: String in _toasts:
		if not s.begins_with("Achievement") and t.to_lower() in s.to_lower():
			return true
	return false


static func _check(ok: bool, what: String) -> void:
	print("%s %s %s" % [TAG, "PASS" if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


static func _wait(tree: SceneTree, s: float) -> void:
	await tree.create_timer(s, true, false, true).timeout


static func _frames(tree: SceneTree, n: int) -> void:
	for k: int in n:
		await tree.physics_frame


static func _event(action: String) -> InputEvent:
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventMouseButton or ev is InputEventKey:
			return ev.duplicate()
	return null


static func _send(action: String, down: bool) -> void:
	var ev: InputEvent = _event(action)
	if ev == null:
		_check(false, "no key or button bound to %s" % action)
		return
	if ev is InputEventMouseButton:
		(ev as InputEventMouseButton).pressed = down
	elif ev is InputEventKey:
		(ev as InputEventKey).pressed = down
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


static func _tap(tree: SceneTree, action: String) -> void:
	await tree.physics_frame
	_send(action, true)
	await tree.create_timer(0.1, true, false, true).timeout
	_send(action, false)
	await _frames(tree, 2)


static func _hold(tree: SceneTree, action: String, secs: float) -> void:
	await tree.physics_frame
	_send(action, true)
	await tree.create_timer(secs).timeout
	_send(action, false)
	await _frames(tree, 2)


static func _stand(so: SliceOrbit, p: Patch, pos: Vector3, look: Vector3) -> void:
	var gp: Vector3 = so.globe.terrain.ground(pos.normalized())
	var up: Vector3 = gp.normalized()
	var fwd: Vector3 = look - gp
	fwd = (fwd - up * fwd.dot(up)).normalized()
	p.place_on_sphere(gp, fwd)
