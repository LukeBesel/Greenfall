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

## The player on arriving, from autoplay runs stopped there (--autoplay --time-scale=8
## --stop-at=landed_N_s, then --walk-travel-state): station 2 at 18.5 game min, station 6 at 97 game min (time-scale 8).
const S2: Dictionary = {"cubes": 1531.0, "parts": 191.0, "upgrades": {"baler": 1, "compartment_size": 1, "lift_strength": 2, "multi_lock": 1, "scoop_speed": 1}}
const S6: Dictionary = {"cubes": 413910.0, "parts": 101.0, "upgrades": {"auto_compactor": 1, "baler": 1, "compartment_size": 12, "lift_strength": 2, "multi_lock": 4, "scoop_speed": 11, "scoop_width": 10, "laser_reach": 7, "magnet_arm": 3, "tread_speed": 12, "hover_jets": 1, "detector_range": 6}}

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
	if DevHooks.has("walk-travel-state"):  # print the loaded save's player state (an autoplay stop) and quit
		var ups: Dictionary = {}
		for k: String in GameState.upgrades:
			if int(GameState.upgrades[k]) > 0:
				ups[k] = GameState.upgrades[k]
		var ob0: Objectives = w.get("objectives") as Objectives
		print("%s state: step '%s', at site %d, lift_class %d, cubes %.0f, parts %.0f, upgrades %s, robots %s" % [TAG, str(ob0.current().get("id", "")),
			so.sites.sm.nearest, Pace.lift_class(), GameState.get_currency("cubes").to_float(), GameState.get_currency("parts").to_float(), JSON.stringify(ups),
			str((w.get("fleet") as Fleet).robot_total()) if w.get("fleet") is Fleet else "?"])
		tree.quit(0)
		return
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
	_apply_state(S2)
	var cost: Dictionary = HubPlan.wake_cost(hp.planet)
	# 1. Short of the station's price: no beam on the rocket yet, the card says what is missing.
	_set_money(float(cost.get("cubes", 0)) * 0.5, 0.0)
	await _wait(tree, 1.6)
	_check(os_.rocket_spot.visible, "the rocket stands on the pad once the seed is planted")
	var tgt: Dictionary = ob.step_target(ob.current())
	_check(str(ob.current().get("id", "")) == "hub_fly_2" and tgt.get("pos", null) == null and ob.situation != "",
		"short of the price: no beam on the rocket, the card says what is missing ('%s')" % ob.situation)
	# 2. Enough for the station: the beam stands on the rocket.
	_set_money(float(S2["cubes"]), float(S2["parts"]))
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
	_count_hexes(so, ob, p, site)
	await _wait(tree, 4.0)
	await _shot(tree, "2_station_card")
	# Real scooping at the station: the hexes the card outlines, one after another, chest pressed
	# into bales and set down as it fills (two first when the run stops to save).
	var parts0: float = GameState.get_currency("parts").to_float()
	var want: int = 2 if DevHooks.has("walk-travel-save") else int(st.get("need", 4))
	var got: int = await _clean_real(so, site, want, 900.0)
	st = hp.current_step(site)
	var counted: int = int(st.get("have", 0)) if str(st.get("do", "")) == "clean" else want
	_check(got >= want and counted >= want, "%d hexes cleaned by real scooping: the card counts %d (step now '%s')" % [got, counted, hp.card_text])
	print("%s   Parts found while cleaning here: %+.0f" % [TAG, GameState.get_currency("parts").to_float() - parts0])
	if DevHooks.has("walk-travel-save"):
		print("%s saved mid-chain at site %d: %s" % [TAG, site, str(SaveManager.save_game())])
		return
	if DevHooks.has("walk-travel-pad"):  # the controller pass: the wake by A, then stop
		await _finish_station(so, site, false)
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
				var oa: Node3D = ops.items[i].anchor if ops.items[i].anchor else ops.items[i]
				if oa.global_position.distance_to(op) < 0.5:
					k = i
			var oc: Variant = os_.so.get("crews")
			(oc as Object).call("work_cell", int(ops.spots[k]["hex"]), 0.0)
			var rc: Dictionary = ops.repair_cost(k)
			_set_money(float(rc.get("cubes", 0)) + 10.0, float(rc.get("parts", 0)) + 2.0)
			var o3: Vector3 = op
			_stand(so, p, o3 + SphereGrid.frame(o3.normalized()).x * 1.2, o3)
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
	# Station 3 (Gantry Works, with an outpost in its chain), arriving with no Parts for the repair.
	_set_story(ob, "hub_fly_3")
	var c3: Dictionary = HubPlan.wake_cost(hp.planet)
	_set_money(float(c3.get("cubes", 0)) + 2000.0, float(c3.get("parts", 0)) + 6.0)
	await _wait(tree, 1.6)
	await _fly_by_click(so, 7, true)
	_check(str(ob.current().get("id", "")) == "hub_wake_3", "landed: the card says '%s'" % ob.texts(ob.current())[0])
	_count_hexes(so, ob, p, 7)
	await _outpost_no_parts(so, 7)
	await _finish_station(so, 7, false)
	await _fly_by_click(so, 0, false)
	# Rocket Mk II, then stations 4 and 5, all by the same steps.
	_set_story(ob, "rocket_tier_2")
	await _bench_upgrade(so, 2)
	for e: Array in [["hub_fly_4", 8, false], ["hub_fly_5", 2, true]]:
		if bool(e[2]):
			_set_goal(ob, str(e[0]))
		else:
			_set_story(ob, str(e[0]))
		var ck: Dictionary = HubPlan.wake_cost(hp.planet)
		_set_money(float(ck.get("cubes", 0)) + 500.0, float(ck.get("parts", 0)) + 10.0)
		await _wait(tree, 1.6)
		_check(str(ob.current().get("id", "")) == str(e[0]), "the card: '%s'" % ob.texts(ob.current())[0])
		await _fly_by_click(so, int(e[1]), true)
		_check(str(ob.current().get("id", "")).begins_with("hub_wake_"), "landed: the card says '%s'" % ob.texts(ob.current())[0])
		_count_hexes(so, ob, p, int(e[1]))
		await _finish_station(so, int(e[1]), false)
		await _fly_by_click(so, 0, false)
	# The player at the last station, as an autoplay run had it there (S6), the home base at 5.
	_apply_state(S6)
	var hub: Hub = w.get("hub") as Hub
	if hub:
		hub.level = 5
		hub.level_changed.emit(5)
	GameState.world["hub_level"] = 5
	_set_goal(ob, "rocket_tier_3")
	await _wait(tree, 1.6)
	_check(str(ob.current().get("id", "")) == "rocket_tier_3", "the card: '%s'" % ob.texts(ob.current())[0])
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
	var tgt: Dictionary = ob.step_target(ob.current())
	_check(str(tgt.get("to", "")) == "bench" and (tgt.get("row", []) as Array) == ["patch", "rocket_tier"], "the step points at the bench's rocket row (%s)" % str(tgt))
	await _bench_upgrade(so, 3)
	await _wait(tree, 5.0)
	_set_goal(ob, "hub_fly_6")
	_set_money(float(S6["cubes"]), float(S6["parts"]))
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
	await _wait(tree, 4.0)
	await _shot(tree, "clean_step_%d" % site)
	_count_hexes(so, ob, p, site)
	var got: int = await _clean_real(so, site, 4, 900.0)
	_check(got >= 4, "%d hexes cleaned by real scooping at Stack Works" % got)
	await _outpost_repair(so, site)  # not in its chain: the one more station whose outpost is repaired by E
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
	var stock0: Array = [GameState.get_currency("cubes").to_float(), GameState.get_currency("parts").to_float(), GameState.get_currency("seeds").to_float()]
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
	var stock1: Array = [GameState.get_currency("cubes").to_float(), GameState.get_currency("parts").to_float(), GameState.get_currency("seeds").to_float()]
	_check(stock1[0] >= stock0[0] - 0.5 and stock1[1] >= stock0[1] - 0.5 and stock1[2] >= stock0[2] - 0.5, "the trip cost nothing (cubes, Parts, seeds %s -> %s)" % [str(stock0), str(stock1)])
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


## The station's finishable hexes near the pad (HexAudit.far_hub: with the player's Lift, the
## 95% rule and the leftover rule), at least the chain's count within 100 m.
static func _count_hexes(so: SliceOrbit, ob: Objectives, p: Patch, site: int) -> void:
	var g: OrbitPlanet = so.globe
	var hl: HexLeftovers = HexLeftovers.for_world(so.w)
	var lines: PackedStringArray = []
	var inv: Transform3D = (g.sites[site]["transform"] as Transform3D).affine_inverse()
	var r: Array = HexAudit.far_hub(hl, g, g.field, site, int(g.sites[site]["cell"]), 100.0, Pace.lift_class(), inv, lines)
	var need: int = int(so.sites.purpose.current_step(site).get("need", 4)) if str(so.sites.purpose.current_step(site).get("do", "")) == "clean" else 4
	_check(int(r[0]) >= need, "%d finishable hexes within 100 m of the pad (of %d dirty land hexes, Lift %d; the step needs %d)" % [r[0], r[1], Pace.lift_class(), need])


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


## Cleans the station's hexes by real scooping: Lumi beside the nearest piece of the outlined hex,
## the scoop held; a full chest pressed into a bale (the cube key) and the bale set down (drop).
## Game time runs x3. Stops at `need` hexes counted on the station card, or after max_s game s.
## A hex that stops moving for 60 tries is reported with what is left in it.
static func _clean_real(so: SliceOrbit, site: int, need: int, max_s: float) -> int:
	var w: Node = so.w
	var tree: SceneTree = w.get_tree()
	var f: SphereField = so.globe.field
	var ob: Objectives = w.get("objectives") as Objectives
	var hp: HubPurpose = so.sites.purpose
	var p: Patch = w.get("patch") as Patch
	if InputMap.has_action("tool_scoop"):
		await _tap(tree, "tool_scoop")
	if DevHooks.has("walk-travel-shots"):  # pictures only: real scooping at 2 fps would take hours
		_clean_cells(so.sites, site, need - int(hp.current_step(site).get("have", 0)))
		await _wait(tree, 1.0)
		return need
	var t_end: float = float(GameState.stats.get("time_played", 0.0)) + max_s
	var tries: Dictionary = {}
	var hex_t: Dictionary = {}  # hex -> [tries, best removed]
	var n0: float = float(GameState.stats.get("junk_scooped", 0))
	var bales: int = 0
	var started: int = Time.get_ticks_msec()
	Engine.time_scale = 3.0
	_send("scoop", true)
	while true:
		var st: Dictionary = hp.current_step(site)
		var have: int = int(st.get("have", 0)) if str(st.get("do", "")) == "clean" else 99
		if have >= need or float(GameState.stats.get("time_played", 0.0)) > t_end:
			break
		if p.compartment.fill >= p.capacity() * 0.9:
			_send("scoop", false)
			await _tap(tree, "cube")
			await _wait(tree, 0.5)
			if not p.carried.is_empty():
				await _tap(tree, "drop")
				bales += 1
			await _frames(tree, 2)
			_send("scoop", true)
			continue
		var h: int = ob.target_hex
		if h < 0:
			await _frames(tree, 6)
			continue
		var ht: Array = hex_t.get(h, [0, 0.0])
		var rf: float = f.removed_fraction(h)
		if rf > float(ht[1]) + 0.001:
			ht = [0, rf]
		ht[0] = int(ht[0]) + 1
		hex_t[h] = ht
		if int(ht[0]) == 60:
			var big: int = 0
			var alive: int = 0
			for q: int in f.hex_pieces[h]:
				if f.piece_alive[q] != 0:
					alive += 1
					big += 1 if Pace.piece_size(f, q) > Pace.lift_class() else 0
			_check(false, "hex %d stopped at %.0f%% (%d pieces left, %d over the lift)" % [h, rf * 100.0, alive, big])
		var pid: int = -1
		var best: float = INF
		for q: int in f.hex_pieces[h]:
			if f.piece_alive[q] == 0 or int(tries.get(q, 0)) >= 4 or not Pace.can_lift(f, q):
				continue
			var d: float = f.piece_pos[q].distance_to(p.global_position)
			if d < best:
				best = d
				pid = q
		if pid < 0:
			await _frames(tree, 6)
			continue
		tries[pid] = int(tries.get(pid, 0)) + 1
		var pp: Vector3 = f.piece_pos[pid]
		var side: Vector3 = SphereGrid.frame(pp.normalized()).x
		_stand(so, p, pp + side * 1.1, pp)
		await _frames(tree, 8)
	_send("scoop", false)
	Engine.time_scale = 1.0
	var st2: Dictionary = hp.current_step(site)
	var got: int = int(st2.get("have", 0)) if str(st2.get("do", "")) == "clean" else need
	print("%s   real cleaning at site %d: %d hexes, %d pieces, %d bales, %.0f s of wall time" % [TAG, site, got, int(float(GameState.stats.get("junk_scooped", 0)) - n0), bales, (Time.get_ticks_msec() - started) / 1000.0])
	return got


## The player's upgrades and stock on arriving (S2 / S6).
static func _apply_state(st: Dictionary) -> void:
	for k: String in st["upgrades"]:
		GameState.upgrades[k] = int(st["upgrades"][k])
	for k: String in st["upgrades"]:
		EventBus.upgrade_bought.emit(k, int(st["upgrades"][k]))  # systems that size themselves on a purchase (the chest)
	_set_money(float(st["cubes"]), float(st["parts"]))


## The outpost step with no Parts: E refused with a line, what the card says; fly home and back
## (the chain is kept); then the Parts, and E repairs it.
static func _outpost_no_parts(so: SliceOrbit, site: int) -> void:
	var w: Node = so.w
	var tree: SceneTree = w.get_tree()
	var ob: Objectives = w.get("objectives") as Objectives
	var hp: HubPurpose = so.sites.purpose
	var st: Dictionary = hp.current_step(site)
	if str(st.get("do", "")) == "clean":
		_clean_cells(so.sites, site, int(st.get("need", 0)) - int(st.get("have", 0)))
		await _wait(tree, 1.2)
	_check(str(hp.current_step(site).get("do", "")) == "outposts", "the chain reaches its outpost step")
	await _wait(tree, 1.0)
	await _shot(tree, "outpost_step_%d" % site)
	var cubes: float = GameState.get_currency("cubes").to_float()
	_set_money(cubes, 0.0)
	var k: int = await _at_outpost(so, site)
	if k < 0:
		return
	var ops: Outposts = w.get("outposts") as Outposts
	_toasts.clear()
	await _tap(tree, "interact")
	await _wait(tree, 1.0)
	_check(ops.level_of(k) == 0 and _said("not enough"), "no Parts: E at the outpost refused with a line (%s)" % _quote("not enough"))
	_check(ob.situation.contains(str(int(ops.repair_cost(k).get("parts", 0)))), "no Parts: the card says how many the outpost needs ('%s')" % ob.situation)
	print("%s   no Parts: station card '%s', objective card hint '%s', prompt '%s'" % [TAG, hp.card_text, ob.situation, so.interact_prompt(w.get("patch"))])
	var have0: int = int(hp.current_step(site).get("have", 0))
	var clean0: int = hp.cleaned_here(site)
	await _fly_by_click(so, 0, false)
	await _fly_by_click(so, site, false)
	await _wait(tree, 1.2)
	_check(str(hp.current_step(site).get("do", "")) == "outposts" and int(hp.current_step(site).get("have", 0)) == have0 and hp.cleaned_here(site) >= clean0,
		"flown home and back: the chain is where it was (outpost %d, %d hexes)" % [int(hp.current_step(site).get("have", 0)), hp.cleaned_here(site)])
	await _outpost_repair(so, site)
	await _wait(tree, 1.2)
	_check(str(hp.current_step(site).get("do", "")) == "wake", "the outpost counts: the chain moves to the wake")


## Lumi by the nearest ruined outpost's kiosk, its hex cleared (the crews' cell clean): its index.
static func _at_outpost(so: SliceOrbit, site: int) -> int:
	var w: Node = so.w
	var p: Patch = w.get("patch") as Patch
	var ops: Outposts = w.get("outposts") as Outposts
	if ops == null or ops.hub_index != site:
		_check(false, "no outposts at site %d" % site)
		return -1
	var k: int = -1
	var bd: float = INF
	for i: int in ops.items.size():
		if ops.level_of(i) >= 1:
			continue
		var a: Node3D = ops.items[i].anchor if ops.items[i].anchor else ops.items[i]
		var d: float = a.global_position.distance_to(p.global_position)
		if d < bd:
			bd = d
			k = i
	if k < 0:
		_check(false, "a ruined outpost at site %d" % site)
		return -1
	(so.get("crews") as Object).call("work_cell", int(ops.spots[k]["hex"]), 0.0)
	var o3: Vector3 = (ops.items[k].anchor if ops.items[k].anchor else ops.items[k]).global_position
	_stand(so, p, o3 + SphereGrid.frame(o3.normalized()).x * 1.2, o3)
	await _frames(w.get_tree(), 6)
	return k


## E at the nearest ruined outpost with its price: repaired.
static func _outpost_repair(so: SliceOrbit, site: int) -> void:
	var w: Node = so.w
	var k: int = await _at_outpost(so, site)
	if k < 0:
		return
	var ops: Outposts = w.get("outposts") as Outposts
	var rc: Dictionary = ops.repair_cost(k)
	_set_money(maxf(GameState.get_currency("cubes").to_float(), float(rc.get("cubes", 0)) + 10.0), maxf(GameState.get_currency("parts").to_float(), float(rc.get("parts", 0)) + 2.0))
	print("%s   by the outpost: '%s'" % [TAG, so.interact_prompt(w.get("patch"))])
	await _tap(w.get_tree(), "interact")
	await _wait(w.get_tree(), 4.0)
	_check(ops.level_of(k) >= 1, "E by the cleared outpost at %s with the price repairs it" % HubPlan.hub_name(so.sites.sm.planet_id, site))


## The rocket's next tier at the home bench: E opens it on the rocket's row, a click upgrades.
static func _bench_upgrade(so: SliceOrbit, to_tier: int) -> void:
	var w: Node = so.w
	var tree: SceneTree = w.get_tree()
	var ob: Objectives = w.get("objectives") as Objectives
	var p: Patch = w.get("patch") as Patch
	var tgt: Dictionary = ob.step_target(ob.current())
	_check(str(tgt.get("to", "")) == "bench" and (tgt.get("row", []) as Array) == ["patch", "rocket_tier"], "Mk %d: the step points at the bench's rocket row" % to_tier)
	var nd: Dictionary = RocketTiers.next_def()
	var cost: Dictionary = nd.get("cost", {})
	_set_money(maxf(GameState.get_currency("cubes").to_float(), float(cost.get("cubes", 0)) + 100.0), maxf(GameState.get_currency("parts").to_float(), float(cost.get("parts", 0)) + 5.0))
	var bp: Vector3 = so.bench_position()
	_stand(so, p, bp + (bp - so.sites.sm.pad_xf(0).origin).normalized() * 1.6, bp)
	await _frames(tree, 6)
	await _tap(tree, "interact")
	await _wait(tree, 1.0)
	var up: UpgradesScreen = w.get("upgrades") as UpgradesScreen
	_check(up != null and up.is_open, "E at the bench opens it")
	var ub: Button = _find_button(up, "Upgrade the rocket")
	_check(ub != null and not ub.disabled, "the bench shows the rocket's row with its button")
	if to_tier == 3:
		await _shot(tree, "3_bench_rocket")
	if ub:
		await _click(tree, ub)
		await _wait(tree, 0.6)
	_check(RocketTiers.tier() == to_tier, "a click upgrades the rocket to Mk %d (Mk %d)" % [to_tier, RocketTiers.tier()])
	if up and up.is_open:
		await _tap(tree, "ui_cancel")
		await _wait(tree, 0.6)
	await _wait(tree, 4.0)


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
	if DevHooks.has("walk-travel-pad"):  # a controller can't click: move the focus with the d-pad, then A
		for k: int in 14:
			if c.has_focus():
				break
			await _tap(tree, "ui_down")
		_check(c.has_focus(), "the d-pad reaches '%s'" % ((c as Button).text if c is Button else c.name))
		await _tap(tree, "ui_accept")
		await tree.process_frame
		return
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
	# A rendered run (--walk-travel-shots) draws about 2 frames a second: give each beat more room.
	await tree.create_timer(s * (4.0 if DevHooks.has("walk-travel-shots") else 1.0), true, false, true).timeout


static func _frames(tree: SceneTree, n: int) -> void:
	for k: int in n:
		await tree.physics_frame


static func _event(action: String) -> InputEvent:
	var pad: bool = DevHooks.has("walk-travel-pad")  # [controller pass] the joypad events of the same input map
	for ev: InputEvent in InputMap.action_get_events(action):
		if pad and (ev is InputEventJoypadButton or ev is InputEventJoypadMotion):
			return ev.duplicate()
		if not pad and (ev is InputEventMouseButton or ev is InputEventKey):
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
	elif ev is InputEventJoypadButton:
		(ev as InputEventJoypadButton).pressed = down
	elif ev is InputEventJoypadMotion:
		var jm: InputEventJoypadMotion = ev
		jm.axis_value = (1.0 if jm.axis_value >= 0.0 else -1.0) if down else 0.0
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
