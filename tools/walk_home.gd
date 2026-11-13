class_name WalkHome
extends RefCounted
## [v9b] Goal audit, "home": the Landing Yard steps after the first robot, played the way a player
## does (the model is tools/seed_walk.gd): the real keys and mouse button the input map binds, and
## real mouse clicks on the workbench (a press and release pushed into the window at the button's
## place on screen), on the real globe. Each part sets up the state a player is in when the step
## starts (dev: the step index, cubes and parts, the tower and bench tiers, a Scoopie; said per part),
## then checks the card, the action, the refusals, and that the next step comes.
##   hex2    the card, the outlined hex, cleaning it with the scoop key -> "Clean 3 hexes"
##   hex3    a robot's hex counts, and a line says so -> the seed step
##   garden  after the first seed: thirsty, the water key on the bed, an empty can and the refill,
##           out of seeds (each refusal says why)
##   base2   short of Parts: the card and the bench say how many; then the price tag click builds it
##   haul    the plans wait: the card's hint and a bar; the Bots row is locked; they arrive; the click
##   tower2  the bench opens on the tower row; the click
##   research1  the Research Desk first (the tab is not there yet), then a project by clicks
##   base3   the click; the Requests board: the line, the Request Board, the tab, the first offers
## --walk-home[=S] (after S s, default 8): prints [walk-home] lines, exit 1 on a failure.
## tools/check_exit.sh runs it with the tests.

static var _toasts: Array[String] = []
static var _fails: Array[String] = []
static var so: SliceOrbit
static var w: Node
static var tree: SceneTree
static var ob: Objectives
static var p: Patch


static func run_dev(p_so: SliceOrbit) -> void:
	so = p_so
	w = so.w
	tree = w.get_tree()
	await tree.create_timer(DevHooks.get_f("walk-home", 8.0)).timeout
	for k: int in 240:  # the world is whole
		if not bool(w.get("building")) and w.get("objectives") != null and w.get("upgrades") != null and w.get("fleet") != null:
			break
		await tree.create_timer(0.5).timeout
	ob = w.get("objectives") as Objectives
	p = w.get("patch") as Patch
	if ob == null or p == null:
		print("[walk-home] FAIL: no objectives / Lumi")
		tree.quit(1)
		return
	EventBus.toast.connect(func(t: String, _k: String) -> void: _toasts.append(t))
	_base_state()
	await tree.create_timer(1.0).timeout
	var only: String = DevHooks.get_s("walk-home-only", "")  # dev: --walk-home-only=hex2,base2 (iterating)
	for part: String in ["hex2", "hex3", "garden", "base2", "haul", "tower2", "research1", "base3"]:
		if only == "" or part in only.split(","):
			await Callable(WalkHome, "_part_" + part).call()
	print("[walk-home] %s" % ("PASS" if _fails.is_empty() else "FAIL: " + "; ".join(_fails)))
	tree.quit(0 if _fails.is_empty() else 1)


# --- The state a player has after the first robot (dev setup) ----------------------------------

static func _base_state() -> void:
	GameState.flags["onboard_brief"] = true
	GameState.flags["tutorial_step"] = Tutorial.STEPS.size()
	var tut: Tutorial = w.get("tutorial") as Tutorial
	if tut:
		tut.step = Tutorial.STEPS.size()  # the restart checklist is long done by now
		EventBus.tutorial_changed.emit(tut.current_text())
	YardBuilds.state()["bench"] = true  # the bench was repaired back then
	ob.revealed = true
	if SignalTower.tier() < 1:
		GameState.flags["signal_tower"] = 1  # the tower stands (the "tower" step)
	if BenchTiers.tier() < 2:  # the Bot Bay ("bench2"): as BenchTiers.buy does
		GameState.flags["bench_tier"] = 2
		Research.grant("salvage_logic")
	var fl: Fleet = w.get("fleet") as Fleet
	if fl.robot_total() < 1:  # the first Scoopie ("robot")
		fl.build("scoopie", so.bench_position())
	GameState.stats["robots_built"] = maxf(float(GameState.stats.get("robots_built", 0.0)), 1.0)
	GameState.flags["first_robot_t"] = float(GameState.stats.get("time_played", 0.0))
	for u: String in ["compartment_size", "multi_lock", "baler"]:
		if GameState.level_of(u) < 1:
			GameState.upgrades[u] = 1
	_set_money(300.0, 10.0)
	_check(float(GameState.stats.get("research_done", 0.0)) == 0.0, "the Bot Bay's free Salvage Logic is not a finished research project (research_done=%s)" % str(GameState.stats.get("research_done", 0.0)))


static func _set_money(cubes: float, parts: float) -> void:
	GameState.currencies["cubes"] = BigNum.from_float(cubes)
	GameState.currencies["parts"] = BigNum.from_float(parts)
	EventBus.currency_changed.emit("cubes", GameState.currencies["cubes"])


static func _goto(id: String) -> bool:
	var idx: int = ob.chain.map(func(d: Dictionary) -> String: return str(d["id"])).find(id)
	if idx < 0:
		_check(false, "no step %s" % id)
		return false
	ob.step = idx
	GameState.flags["objective_step"] = idx
	ob.changed.emit(idx)
	await tree.create_timer(0.8).timeout
	return true


static func _step_id() -> String:
	return str(ob.current().get("id", ""))


## The card as the player reads it: [title, why, hint, count].
static func _card() -> Array[String]:
	var hud: Node = w.get("hud")
	var gp: GoalsPanel = hud.get("goals") as GoalsPanel if hud else null
	var oc: ObjectiveCard = gp.objective if gp else null
	if oc == null:
		return ["", "", "", ""]
	return oc.read()  # [v9d] the card as text: title, why (also when folded), hint or cost chips, count


static func _wait_step_not(id: String, secs: float) -> bool:
	for k: int in int(secs * 4.0):
		if _step_id() != id:
			return true
		await tree.create_timer(0.25).timeout
	return _step_id() != id


# --- hex2: clean one more hex with the scoop key -----------------------------------------------

static func _part_hex2() -> void:
	GameState.stats["hexes_cleaned"] = 1.0
	if not await _goto("hex2"):
		return
	var c: Array[String] = _card()
	_check(c[0] == "Clean 2 hexes" and c[3] == "1 / 2", "hex2: the card says Clean 2 hexes, 1 / 2 (%s)" % str(c))
	_check(ob.target_hex >= 0, "hex2: a hex is outlined on the ground (%d)" % ob.target_hex)
	await _tap("tool_scoop")
	var f: SphereField = so.globe.field
	var over: int = 0
	var alive: int = 0
	for hh: int in f.hexes_near(p.global_position, 4):
		for pid: int in f.hex_pieces[hh]:
			if f.piece_alive[pid] == 1:
				alive += 1
				if f.hex_at(f.piece_pos[pid]) != hh:
					over += 1
	print("[walk-home] note: %d of %d live pieces round the yard lie over their hex's border" % [over, alive])
	var t0: int = Time.get_ticks_msec()
	var took: int = 0
	var stall: int = 0
	while float(GameState.stats.get("hexes_cleaned", 0.0)) < 2.0 and Time.get_ticks_msec() - t0 < 240000:
		var h: int = ob.target_hex
		if h < 0:
			await tree.create_timer(0.3).timeout
			continue
		var best: int = -1
		var bd: float = INF
		for pid: int in f.hex_pieces[h]:
			if f.piece_alive[pid] == 1 and Pace.can_lift(f, pid):
				var d: float = f.piece_pos[pid].distance_to(p.global_position)
				if d < bd:
					bd = d
					best = pid
		if best < 0:
			_check(false, "hex2: the outlined hex %d has nothing liftable left at %.0f%%" % [h, f.removed_fraction(h) * 100.0])
			break
		var at: Vector3 = f.piece_pos[best]
		var up: Vector3 = at.normalized()
		var away: Vector3 = p.global_position - at
		away = (away - up * away.dot(up))
		away = away.normalized() if away.length() > 0.05 else -SphereGrid.frame(up).z
		_stand(at + away * 1.1, at)
		await _frames(3)
		if p.compartment.fill >= p.capacity() * 0.85:
			p.compartment.take_all()  # (dev) the bin trips are the earlier steps' walk
		var fr0: float = f.removed_fraction(h)
		await _hold("scoop", 0.7)
		took += 1
		if f.piece_alive[best] == 1:
			stall += 1
		else:
			stall = 0
		if stall == 6:  # the same piece six times: say why it stays
			var o: Vector3 = p.scoop_origin()
			var u: Vector3 = o.normalized()
			var dd: Vector3 = f.piece_pos[best] - o
			var tgt: int = Pace.find_scoop_target(f, o, p.forward(), p.stat("scoop_reach"), p.stat("scoop_width"), Pace.lift_class())
			var gnd: float = so.globe.terrain.ground(f.piece_pos[best].normalized()).length()
			print("[walk-home] note: piece %d won't come: size %d (lift %d), vol %.2f, up %.2f m over the scoop, %.2f m over the ground, fwd %.2f, scoop finds %d, locked %s, toasts %s" % [best, Pace.piece_size(f, best), Pace.lift_class(), f.piece_vol[best], dd.dot(u), f.piece_pos[best].length() - gnd, dd.dot((p.forward() - u * p.forward().dot(u)).normalized()), tgt, str(f.locked.has(h)), str(_toasts.slice(-3))])
		if took % 40 == 1:
			print("[walk-home] note: hex %d %.0f%% -> %.0f%%, piece %d alive=%d at %.1f m, chest %.1f/%.1f, tool %d, input %s" % [h, fr0 * 100.0, f.removed_fraction(h) * 100.0, best, f.piece_alive[best], p.global_position.distance_to(at), p.compartment.fill, p.capacity(), p.tool, str((p.input as PlayerInput).enabled if p.input is PlayerInput else "?")])
	await tree.create_timer(0.3).timeout
	_check(float(GameState.stats.get("hexes_cleaned", 0.0)) >= 2.0, "hex2: scooping cleans the outlined hex (%d scoops)" % took)
	var moved: bool = await _wait_step_not("hex2", 4.0)
	await tree.create_timer(2.5).timeout  # the card's DONE beat, then the next step slides in
	c = _card()
	_check(moved and _step_id() == "hex3" and c[0] == "Clean 3 hexes", "hex2 done: the card moves on to Clean 3 hexes (%s, %s)" % [_step_id(), str(c)])


# --- hex3: a robot's hex counts, and says so ------------------------------------------------------

static func _part_hex3() -> void:
	if _step_id() != "hex3" and not await _goto("hex3"):
		return
	var crews: OrbitCrews = so.get("crews") as OrbitCrews
	if crews == null or crews.crew == null:
		_check(false, "hex3: no robot crew")
		return
	var f: SphereField = so.globe.field
	var far: int = -1
	for h: int in f.hexes_near(p.global_position, 8):
		if not f.is_clean(h) and f.hex_hub[h] == 0 and not f.is_water(h) and f.hex_center(h).distance_to(p.global_position) > 70.0:
			far = h
			break
	if far < 0:
		_check(false, "hex3: no far dirty hex for the robot")
		return
	_toasts.clear()
	crews.work_cell(far, 0.0)  # the Scoopie finishes a hex out of Lumi's sight (its report, as SphereCrew sends it)
	crews.crew.cell_cleaned.emit(far)
	await tree.create_timer(0.3).timeout
	_check(_said("robot"), "hex3: a robot's hex says so on screen (%s)" % str(_toasts))
	if _step_id() == "hex3":  # one hex was not enough (the robot's counted, 2 / 3 -> 3 / 3 needs one more)
		GameState.stats["hexes_cleaned"] = 3.0
	var moved: bool = await _wait_step_not("hex3", 4.0)
	_check(moved and _step_id() == "seed", "hex3 done: on to the seed (%s)" % _step_id())


# --- After the first seed: water, empty can, refill, out of seeds ----------------------------------

static func _part_garden() -> void:
	var g: Garden = w.get("garden") as Garden
	var fs: FirstSeed = w.get("first_seed") as FirstSeed
	if g == null or fs == null:
		_check(false, "garden: no garden / greenhouse")
		return
	# (dev) the seed step as tools/seed_walk.gd plays it: the tin taken, the seed in the first bed.
	GameState.flags["seed_signal"] = true
	GameState.flags["seeds_unlocked"] = true
	GameState.add_currency("seeds", BigNum.from_float(1.0))
	var slot: int = fs.bed_slots[0]
	if g.slot_species[slot] < 0:
		g.plant(slot)
	var moved: bool = await _wait_step_not("seed", 4.0)
	_check(moved, "seed planted: the card moves on (%s)" % _step_id())
	_check(g.slot_water[slot] <= 0.0, "garden: the new seed is thirsty (water %.1f)" % g.slot_water[slot])
	var marks: Node = _find_marks()
	_check(marks != null, "garden: the plant marks (thirsty drop, soil, rings) are in the world")
	# The water key on the bed.
	_stand(fs.to_global(FirstSeed.GREENHOUSE_POS + Vector3(0.0, 0.0, FirstSeed.BED_SPOTS[0].z)), g.slot_pos[slot])
	await _frames(4)
	p.water = p.water_cap()
	await _tap("tool_water")
	_check(p.tool == Patch.Tool.WATER, "garden: the water key takes the can")
	await _hold("scoop", 1.0)
	_check(g.slot_water[slot] > 0.0, "garden: holding the button on the bed waters the seed (water %.1f)" % g.slot_water[slot])
	# An empty can away from the yard: refused with a line; back in the yard it fills.
	var f: SphereField = so.globe.field
	var clean: int = -1
	for h: int in f.hexes_near(p.global_position, 6):
		if f.is_clean(h) and f.hex_hub[h] == 0 and not f.is_water(h) and f.hex_center(h).distance_to(so.bench_position()) > Patch.REFILL_YARD_M + 6.0:
			clean = h
			break
	if clean < 0:
		_check(false, "garden: no clean hex outside the yard")
		return
	var c: Vector3 = f.hex_center(clean)
	_stand(c, c + _north(c) * 3.0)
	await _frames(4)
	p.water = 0.0
	_toasts.clear()
	await _hold("scoop", 0.8)
	_check(_said("empty") and p.water <= 0.0, "garden: an empty can says so, away from the yard (%s)" % str(_toasts))
	var yard: Vector3 = so.bench_position()
	_stand(yard + _north(yard) * 4.0, yard)
	await tree.create_timer(1.5).timeout
	_check(p.water > 5.0, "garden: the can fills by itself in the yard (%.1f)" % p.water)
	# No seeds left: the seed key on clean ground says why.
	GameState.currencies["seeds"] = BigNum.zero()
	_stand(c, c + _north(c) * 3.0)
	await _frames(4)
	await _tap("tool_plant")
	_toasts.clear()
	await _hold("scoop", 1.0)
	_check(_said("seeds"), "garden: no seeds left, a line says where more come from (%s)" % str(_toasts))
	await _tap("tool_scoop")


static func _find_marks() -> Node:
	for n: Node in w.get_tree().root.find_children("*", "GardenMarks", true, false):
		return n
	return null


# --- base2: short of Parts, then the click ----------------------------------------------------------

static func _part_base2() -> void:
	var hub: Hub = w.get("hub") as Hub
	if not await _goto("base2"):
		return
	_set_money(1500.0, 100.0)
	await tree.create_timer(0.6).timeout
	var c: Array[String] = _card()
	_check(c[0] == "Base to level 2" and "50" in c[2], "base2: the card says how many Parts are missing (%s)" % str(c))
	var ld: ListDetail = await _open_bench()
	if ld == null:
		return
	_check(_tab() == "patch" and str(ld.get("_sel")) == "hub_level", "base2: the bench opens on the base row (%s / %s)" % [_tab(), str(ld.get("_sel"))])
	_check(str(ld.get("_d_req").text).contains("50"), "base2: the bench says 50 more Parts (%s)" % str(ld.get("_d_req").text))
	await _click(_price_tag(ld, "hub_level"))
	_check(hub.level == 1, "base2: a click while short builds nothing")
	_set_money(1500.0, 150.0)
	await tree.create_timer(0.4).timeout
	await _click(_price_tag(ld, "hub_level"))
	_check(hub.level == 2, "base2: clicking the price tag builds level 2 (level %d)" % hub.level)
	await _close_bench()
	var moved: bool = await _wait_step_not("base2", 4.0)
	_check(moved, "base2 done: the card moves on (%s)" % _step_id())


# --- haul: the plans wait, then the click -------------------------------------------------------

static func _part_haul() -> void:
	var fl: Fleet = w.get("fleet") as Fleet
	GameState.flags.erase("haul_rig")
	Research.done_list().erase("haul_rig")
	GameState.flags["first_robot_t"] = float(GameState.stats.get("time_played", 0.0)) - 300.0  # 5 min since the Scoopie
	GameState.stats["hexes_cleaned"] = maxf(float(GameState.stats.get("hexes_cleaned", 0.0)), 10.0)
	if not await _goto("haul"):
		return
	await tree.create_timer(0.6).timeout
	var c: Array[String] = _card()
	var pr: Array = ob.progress()
	_check(c[1].contains("Keep cleaning") and float(pr[0]) > 0.1 and float(pr[0]) < 0.5, "haul: while the plans come, the card says so with a bar (%s, %s)" % [str(c), str(pr)])
	var ld: ListDetail = await _open_bench()
	if ld == null:
		return
	_check(_tab() == "patch" or _tab() == "bots", "haul: the bench opens (%s)" % _tab())
	await _click(_tab_button("bots"))
	ld = _list()
	var row: Dictionary = _row(ld, "build_haulbug")
	_check(str(row.get("state", "")) == "locked", "haul: the Haul Bug row is locked while the plans come (%s)" % str(row.get("state", "")))
	await _close_bench()
	# The plans come (20 min after the first robot).
	_toasts.clear()
	GameState.flags["first_robot_t"] = float(GameState.stats.get("time_played", 0.0)) - 1201.0
	for k: int in 12:
		if GameState.flags.get("haul_rig", false):
			break
		await tree.create_timer(0.25).timeout
	_check(GameState.flags.get("haul_rig", false), "haul: the plans arrive")
	await tree.create_timer(0.5).timeout
	c = _card()
	_check(c[1].contains("Bots tab"), "haul: then the card says Bots tab (%s)" % str(c))
	_set_money(400.0, 40.0)
	ld = await _open_bench()
	if ld == null:
		return
	_check(_tab() == "bots" and str(ld.get("_sel")) == "build_haulbug", "haul: the bench opens on the Haul Bug (%s / %s)" % [_tab(), str(ld.get("_sel"))])
	await _click(_price_tag(ld, "build_haulbug"))
	_check(fl.count("haulbug") >= 1, "haul: clicking its price tag builds a Haul Bug")
	await _close_bench()
	var moved: bool = await _wait_step_not("haul", 4.0)
	_check(moved, "haul done: the card moves on (%s)" % _step_id())


# --- tower2 ----------------------------------------------------------------------------------------

static func _part_tower2() -> void:
	if not await _goto("tower2"):
		return
	var cost: Dictionary = SignalTower.next_cost()
	_set_money(float(cost.get("cubes", 0.0)), float(cost.get("parts", 0.0)))
	var ld: ListDetail = await _open_bench()
	if ld == null:
		return
	_check(str(ld.get("_sel")) == "hb_signal_tower", "tower2: the bench opens on the tower row (%s)" % str(ld.get("_sel")))
	await _click(_price_tag(ld, "hb_signal_tower"))
	_check(SignalTower.tier() >= 2, "tower2: clicking its price tag boosts the tower (tier %d)" % SignalTower.tier())
	await _close_bench()
	var moved: bool = await _wait_step_not("tower2", 4.0)
	_check(moved, "tower2 done: the card moves on (%s)" % _step_id())


# --- research1: the Research Desk first, then a project ------------------------------------------

static func _part_research1() -> void:
	GameState.stats["research_done"] = 0.0
	var hub: Hub = w.get("hub") as Hub
	if hub.level < 2:  # (dev) base 2 comes before this step; the desk waits for it
		_set_money(1500.0, 150.0)
		hub.upgrade()
	if not await _goto("research1"):
		return
	_set_money(100.0, 0.0)
	await tree.create_timer(0.6).timeout
	_check(_step_id() == "research1", "research1: does not complete by itself (research_done=%s)" % str(GameState.stats.get("research_done", 0.0)))
	var c: Array[String] = _card()
	_check(c[1].contains("Research Desk") and c[3].contains("/"), "research1: no Research tab yet: the card says Research Desk first, with its price (%s)" % str(c))
	_set_money(2850.0, 60.0)  # the desk, and a first project (250)
	var ld: ListDetail = await _open_bench()
	if ld == null:
		return
	_check(_tab() == "patch" and str(ld.get("_sel")) == "bench_tier", "research1: the bench opens on the Research Desk (%s / %s)" % [_tab(), str(ld.get("_sel"))])
	await _click(_price_tag(ld, "bench_tier"))
	_check(BenchTiers.tier() >= 3, "research1: clicking its price tag adds the desk (tier %d)" % BenchTiers.tier())
	await tree.create_timer(1.2).timeout  # the tabs refresh once a second
	var rb: Button = _tab_button("research")
	_check(rb != null and rb.visible, "research1: the Research tab is there now")
	if rb == null:
		return
	await _click(rb)
	ld = _list()
	var pick: String = ""
	for it: Dictionary in BenchLists.research():
		if str(it.get("state", "")) == "ready":
			pick = str(it["id"])
			break
	_check(pick != "", "research1: a project you can pay for (cubes %s)" % Settings.fmt(GameState.get_currency("cubes")))
	if pick == "":
		return
	if not ld.select_id(pick):
		_check(false, "research1: %s not listed" % pick)
		return
	await _frames(3)
	var pick_cat: String = str(Research.def(pick).get("branch", ""))
	await _click(_price_tag(ld, pick))
	if Research.active().is_empty() and not Research.has(pick):
		print("[walk-home] note: %s after the click: status %s, row %s, sel %s, cat %s, can_start %s (%s), toasts %s" % [pick, Research.status(pick), str(_row(ld, pick).get("state", "?")), str(ld.get("_sel")), str(ld.get("_cat")), str(Research.can_start(pick)), Research.reason(pick), str(_toasts.slice(-3))])
	_check(not Research.active().is_empty() or Research.has(pick), "research1: clicking a project's price tag starts it (%s, %s)" % [pick, pick_cat])
	await _close_bench()
	Research.now_override = Research.now() + Research.duration(pick) + 1.0  # (dev) its research time passes
	await tree.create_timer(1.2).timeout
	Research.now_override = -1.0
	_check(float(GameState.stats.get("research_done", 0.0)) >= 1.0, "research1: the project finishes")
	var moved: bool = await _wait_step_not("research1", 4.0)
	_check(moved, "research1 done: the card moves on (%s)" % _step_id())


# --- base3 and the Requests board ------------------------------------------------------------

static func _part_base3() -> void:
	var hub: Hub = w.get("hub") as Hub
	if not await _goto("base3"):
		return
	_set_money(9000.0, 350.0)
	var ld: ListDetail = await _open_bench()
	if ld == null:
		return
	_check(str(ld.get("_sel")) == "hub_level", "base3: the bench opens on the base row (%s)" % str(ld.get("_sel")))
	_toasts.clear()
	await _click(_price_tag(ld, "hub_level"))
	_check(hub.level == 3, "base3: clicking the price tag builds level 3 (level %d)" % hub.level)
	await _close_bench()
	var moved: bool = await _wait_step_not("base3", 4.0)
	_check(moved, "base3 done: the card moves on (%s)" % _step_id())
	await tree.create_timer(1.5).timeout
	_check(not _said("New at the workbench") and _said("Request Board"), "base3: the Requests line points at the Request Board, not a tab that isn't there (%s)" % str(_toasts))
	_set_money(8000.0, 150.0)
	ld = await _open_bench()
	if ld == null:
		return
	if not ld.select_id("bench_tier"):
		_check(false, "base3: no Request Board row")
		return
	await _frames(3)
	await _click(_price_tag(ld, "bench_tier"))
	_check(BenchTiers.tier() >= 4, "base3: clicking the Request Board's price tag adds it (tier %d)" % BenchTiers.tier())
	await tree.create_timer(1.2).timeout
	var cb: Button = _tab_button("contracts")
	_check(cb != null and cb.visible, "base3: the Requests tab is there")
	if cb:
		await _click(cb)
	await tree.create_timer(1.2).timeout
	_check(_tab() == "contracts" and Contracts.unlocked(), "base3: the Requests tab opens (%s)" % _tab())
	var offers: int = 0
	for s: Variant in Contracts.slots():
		if s is Dictionary and str((s as Dictionary).get("state", "")) in ["offer", "open", "active"]:
			offers += 1
	_check(offers > 0, "base3: the board has a first request (%d)" % offers)
	await _close_bench()


# --- The workbench by real input -------------------------------------------------------------------

static func _up() -> UpgradesScreen:
	return w.get("upgrades") as UpgradesScreen


static func _tab() -> String:
	return str(_up().get("_tab"))


static func _list() -> ListDetail:
	return _up().get("_panel") as ListDetail


## Walks (puts) Lumi at the bench and presses the interact key: the workbench opens.
static func _open_bench() -> ListDetail:
	if _up().is_open:
		await _close_bench()
	var b: Vector3 = so.bench_position()
	var gp: Vector3 = so.globe.terrain.ground(b.normalized())
	var off: Vector3 = (so.globe.terrain.ground((b + _north(b) * 2.0).normalized()) - gp)
	_stand(gp + off.normalized() * 1.8, b)
	await _frames(4)
	await _tap("interact")
	for k: int in 12:
		if _up().is_open:
			break
		await tree.create_timer(0.1).timeout
	_check(_up().is_open, "the interact key at the bench opens the workbench (near=%s)" % str(so.near_bench()))
	await tree.create_timer(0.6).timeout  # the unfold
	return _list()


static func _close_bench() -> void:
	if _up().is_open:
		await _click(_up().get("_close_btn") as Control)
	_check(not _up().is_open, "the Close button closes the workbench")
	await tree.create_timer(0.5).timeout


static func _tab_button(id: String) -> Button:
	var bs: Array = _up().get("_tab_buttons")
	for i: int in UpgradesScreen.TABS.size():
		if str(UpgradesScreen.TABS[i]["id"]) == id and i < bs.size():
			return bs[i] as Button
	return null


static func _row(ld: ListDetail, id: String) -> Dictionary:
	if ld == null:
		return {}
	for it: Dictionary in (ld.get("_items") as Array):
		if str(it.get("id", "")) == id:
			return it
	return {}


## The price square on a row (the owner's buy button: a click on the row only selects it).
static func _price_tag(ld: ListDetail, id: String) -> Control:
	if ld == null:
		return null
	ld.refresh()
	var b: Button = (ld.get("_rows") as Dictionary).get(id) as Button
	if b == null:
		_check(false, "no row %s on the %s tab" % [id, _tab()])
		return null
	return (b.get_meta("parts") as Array)[3] as Control


## A left click (press and release) at the control's place on screen, through the window.
static func _click(c: Control) -> void:
	if c == null:
		return
	await _frames(2)
	var vp: Viewport = c.get_viewport()
	var at: Vector2 = (c.get_global_transform_with_canvas() * (c.size * 0.5))
	var win: Vector2 = tree.root.get_final_transform() * at
	var mv := InputEventMouseMotion.new()
	mv.position = win
	mv.global_position = win
	tree.root.push_input(mv)
	await _frames(1)
	var hov: Control = vp.gui_get_hovered_control()
	if hov != c and not c.is_ancestor_of(hov) and not (hov != null and hov.is_ancestor_of(c) and hov.mouse_filter == Control.MOUSE_FILTER_PASS):
		print("[walk-home] note: the mouse over %s finds %s" % [c.name, str(hov.get_path()) if hov else "nothing"])
	for down: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = win
		ev.global_position = win
		Input.parse_input_event(ev)  # the button state (rows read Input.is_mouse_button_pressed)
		tree.root.push_input(ev)
		await _frames(2)
	await tree.create_timer(0.3).timeout


# --- Small helpers (as tools/seed_walk.gd) -------------------------------------------------------

static func _said(t: String) -> bool:
	for s: String in _toasts:
		if not s.begins_with("Achievement") and t.to_lower() in s.to_lower():
			return true
	return false


static func _check(ok: bool, what: String) -> void:
	print("[walk-home] %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


static func _frames(n: int) -> void:
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


static func _tap(action: String) -> void:
	await tree.physics_frame
	_send(action, true)
	await tree.create_timer(0.1).timeout
	_send(action, false)
	await _frames(2)


static func _hold(action: String, secs: float) -> void:
	await tree.physics_frame
	_send(action, true)
	await tree.create_timer(secs).timeout
	_send(action, false)
	await _frames(2)


static func _stand(pos: Vector3, look: Vector3) -> void:
	var gp: Vector3 = so.globe.terrain.ground(pos.normalized())
	var up: Vector3 = gp.normalized()
	var fwd: Vector3 = look - gp
	fwd = (fwd - up * fwd.dot(up)).normalized()
	p.place_on_sphere(gp, fwd)


static func _north(at: Vector3) -> Vector3:
	return -SphereGrid.frame(at.normalized()).z
