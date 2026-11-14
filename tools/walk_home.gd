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
##   hex10 / hex20  played: Lumi cleans one hex with the scoop key, the real Scoopies another (time x8)
##   order   steps met out of order (base 3 before base2 / the Haul Bug plans / the desk) never strand
##   heavy   outside the start area: a piece too heavy for Lift 0 gets its mark ("Needs Lift N") and
##           line; a hex left with only too-heavy pieces says which Lift finishes it
## [v9b] Save and reload mid-step: in each part, the game is saved and loaded through the real path
## (odd ones: the pause key, the Quit button, the title's Continue; even ones: the autosave, then the
## game is dropped without a quit save, as a kill, and Continue), and the card, its count or bar, the
## outlined hex, the bench row and the beam must come back the same; then the part finishes the step.
## --walk-home[=S] (after S s, default 8): prints [walk-home] lines, exit 1 on a failure.
## --walk-home-only=hex2,base2 runs some parts; --walk-home-noreload skips the reloads;
## --walk-home-shots=/abs/dir (rendered) saves a frame at each step start and at the bench rows.
## tools/check_exit.sh runs it with the tests.

static var _toasts: Array[String] = []
static var _fails: Array[String] = []
static var so: SliceOrbit
static var w: Node
static var tree: SceneTree
static var ob: Objectives
static var p: Patch
static var _live: bool = false
static var _reborn: SliceOrbit = null
static var _reloads: int = 0
static var _shot_n: int = 0


static func run_dev(p_so: SliceOrbit) -> void:
	if _live:  # a reload built a new world: the walk already running picks it up (_reload)
		_reborn = p_so
		return
	_live = true
	_bind(p_so)
	await tree.create_timer(DevHooks.get_f("walk-home", 8.0)).timeout
	if not await _wait_world():
		print("[walk-home] FAIL: no objectives / Lumi")
		tree.quit(1)
		return
	EventBus.toast.connect(func(t: String, _k: String) -> void: _toasts.append(t))
	_base_state()
	await tree.create_timer(1.0).timeout
	var only: String = DevHooks.get_s("walk-home-only", "")  # dev: --walk-home-only=hex2,base2 (iterating)
	for part: String in ["hex2", "hex3", "garden", "hex10", "base2", "haul", "tower2", "research1", "hex20", "base3", "order", "heavy", "probe"]:
		if (only == "" and part != "probe") or part in only.split(","):
			await Callable(WalkHome, "_part_" + part).call()
	print("[walk-home] %d reloads" % _reloads)
	print("[walk-home] %s" % ("PASS" if _fails.is_empty() else "FAIL: " + "; ".join(_fails)))
	tree.quit(0 if _fails.is_empty() else 1)


static func _bind(p_so: SliceOrbit) -> void:
	so = p_so
	w = so.w
	tree = w.get_tree()


static func _wait_world() -> bool:
	for k: int in 480:  # the world is whole
		if is_instance_valid(w) and not bool(w.get("building")) and w.get("objectives") != null and w.get("upgrades") != null and w.get("fleet") != null and w.get("hud") != null:
			break
		await tree.create_timer(0.5).timeout
	ob = w.get("objectives") as Objectives
	p = w.get("patch") as Patch
	return ob != null and p != null


# --- [v9b] Save and reload through the real path, and compare ----------------------------------

## What the player sees of the step: the card, its count / bar, the outlined hex and how far it is,
## the bench row it opens on, where the beam points.
static func _snap() -> Dictionary:
	return {"step": _step_id(), "card": _card(), "pr": ob.progress(), "hex": ob.target_hex,
		"frac": ob.hex_fraction() if ob.target_hex >= 0 else -1.0, "row": ob.bench_row(), "way": ob.waypoint_target()}


## Saves and loads the game the way a player does, then checks the step came back the same.
## `extra` returns part-specific values to compare too (floats within 5%, keys ending in "_s" within
## 3 minutes, as a clock moves on). Returns false if the world did not come back.
static func _reload(tag: String, extra: Callable = Callable()) -> bool:
	if DevHooks.has("walk-home-noreload"):
		return true
	await tree.create_timer(1.0).timeout
	for k: int in 24:  # not in the card's DONE beat: the next step is what the player reads
		if _card()[3] != "DONE":
			break
		await tree.create_timer(0.25).timeout
	var hub0: int = GameState.current_hub
	var tower0: bool = w.get_node_or_null("SignalTower") != null
	var a: Dictionary = _snap()
	var ea: Dictionary = extra.call() if extra.is_valid() else {}
	_reloads += 1
	var kill: bool = _reloads % 2 == 0
	DevHooks.args.erase("fresh")  # from now on the game loads its save, as Continue does
	DevHooks.args["menu"] = "1"  # dev flags skip the title; with --menu it shows, Continue and all
	_reborn = null
	if kill:  # the autosave writes, then the game is gone without a quit save
		SaveManager.set("_timer", SaveManager.AUTOSAVE_INTERVAL)
		await _frames(3)
		SaveManager.finish_write()
		Loader.goto(PauseMenu.TITLE_SCENE)
	else:  # the pause key, then Quit
		await _tap("pause")
		await tree.create_timer(0.5).timeout
		var pm: PauseMenu = w.get("pause_menu") as PauseMenu
		var quit: Button = _button_named(pm, "Quit")
		_check(pm != null and pm.is_open and quit != null, "%s: the pause key opens the pause menu with Quit" % tag)
		if quit == null:
			return await _fatal(tag)
		await _click(quit)
	var menu: Node = null
	for k: int in 240:
		var cs: Node = tree.current_scene
		if cs and cs.scene_file_path == PauseMenu.TITLE_SCENE and cs.get("_continue") != null and (cs.get("_continue") as Button).is_visible_in_tree():
			menu = cs
			break
		await tree.create_timer(0.5).timeout
	_check(menu != null, "%s: back at the title with Continue (%s)" % [tag, "kill" if kill else "Quit"])
	if menu == null:
		return await _fatal(tag)
	await tree.create_timer(1.5).timeout
	await _click(menu.get("_continue") as Button)
	DevHooks.args.erase("menu")
	for k: int in 600:
		if _reborn != null:
			break
		await tree.create_timer(0.5).timeout
	if _reborn == null:
		_check(false, "%s: Continue builds the world again" % tag)
		return await _fatal(tag)
	_bind(_reborn)
	if not await _wait_world():
		_check(false, "%s: the loaded world has its card and Lumi" % tag)
		return await _fatal(tag)
	await tree.create_timer(3.0).timeout  # the card fades in
	var b: Dictionary = _snap()
	if GameState.current_hub != hub0 or (w.get_node_or_null("SignalTower") != null) != tower0:
		print("[walk-home] note: %s: current hub %d -> %d, tower node %s -> %s" % [tag, hub0, GameState.current_hub, str(tower0), str(w.get_node_or_null("SignalTower") != null)])
	var eb: Dictionary = extra.call() if extra.is_valid() else {}
	var diff: Array[String] = []
	for k: String in ["step", "row"]:
		if str(a[k]) != str(b[k]):
			diff.append("%s %s -> %s" % [k, str(a[k]), str(b[k])])
	var digits := RegEx.create_from_string("[0-9.,]+[KMB]?")
	var ca: String = digits.sub(str((a["card"] as Array).slice(0, 3)), "#", true)  # numbers in a price line tick on
	var cb: String = digits.sub(str((b["card"] as Array).slice(0, 3)), "#", true)
	if ca != cb:  # the count: below, with the bar
		diff.append("card %s -> %s" % [str(a["card"]), str(b["card"])])
	var pa: Array = a["pr"]
	var pb: Array = b["pr"]
	if absf(float(pa[0]) - float(pb[0])) > 0.06 or (float(pa[0]) < 0.0 and str(pa[1]) != str(pb[1])):
		diff.append("count %s -> %s" % [str(pa), str(pb)])
	# The outline is picked afresh on load (the most-cleared hex near Lumi): another hex is fine if
	# the old one kept its progress and the new one is at least as far along.
	var kept: float = (so.globe.field as HexField).removed_fraction(int(a["hex"])) if int(a["hex"]) >= 0 else 0.0
	if int(a["hex"]) >= 0 and int(b["hex"]) != int(a["hex"]) and int(b["hex"]) >= 0 and absf(kept - float(a["frac"])) <= 0.05 and float(b["frac"]) >= float(a["frac"]) - 0.01:
		print("[walk-home] note: %s: the outline moved to hex %d (%.0f%%); hex %d kept %.0f%%" % [tag, int(b["hex"]), float(b["frac"]) * 100.0, int(a["hex"]), kept * 100.0])
	elif int(a["hex"]) >= 0 and (int(b["hex"]) < 0 or absf(float(a["frac"]) - float(b["frac"])) > 0.05):
		diff.append("outlined hex %d %.0f%% -> %d %.0f%%" % [int(a["hex"]), float(a["frac"]) * 100.0, int(b["hex"]), float(b["frac"]) * 100.0])
	if (a["way"] is Vector3) != (b["way"] is Vector3) or (a["way"] is Vector3 and (a["way"] as Vector3).distance_to(b["way"]) > 4.0):
		diff.append("beam %s -> %s" % [str(a["way"]), str(b["way"])])
	for k: String in ea:
		var va: Variant = ea[k]
		var vb: Variant = eb.get(k)
		if va is float or va is int:
			var tol: float = 180.0 if k.ends_with("_s") else maxf(absf(float(va)) * 0.05, 0.01)
			if vb == null or absf(float(va) - float(vb)) > tol:
				diff.append("%s %s -> %s" % [k, str(va), str(vb)])
		elif str(va) != str(vb):
			diff.append("%s %s -> %s" % [k, str(va), str(vb)])
	_check(diff.is_empty(), "%s: saved and loaded (%s): the same card, count, marker and bench row%s" % [tag, "kill" if kill else "Quit", "" if diff.is_empty() else ": " + "; ".join(diff)])
	return true


## A reload that did not come back: the walk can't go on in a freed world.
static func _fatal(tag: String) -> bool:
	print("[walk-home] FAIL: the reload at %s did not come back; stopping. %s" % [tag, "; ".join(_fails)])
	tree.quit(1)
	await tree.create_timer(600.0).timeout
	return false


static func _button_named(root: Node, text: String) -> Button:
	if root == null:
		return null
	for n: Node in root.find_children("*", "Button", true, false):
		var b: Button = n as Button
		if b.is_visible_in_tree() and (b.text == text or b.text == TranslationServer.translate(text)):
			return b
	return null


## (shot runs) Lumi a few metres from the outlined hex, facing it, as a player who followed the beam.
static func _face_target() -> void:
	if not _quick() or ob.target_hex < 0:
		return
	var f: SphereField = so.globe.field
	var c: Vector3 = f.hex_center(ob.target_hex)
	var away: Vector3 = p.global_position - c
	var up: Vector3 = c.normalized()
	away = (away - up * away.dot(up))
	away = away.normalized() if away.length() > 0.5 else -_north(c)
	_stand(c + away * f.hex_size * 1.6, c)
	await tree.create_timer(1.0).timeout


## Rendered shot runs skip the long scooping and robot waits (the headless walk plays those).
static func _quick() -> bool:
	return DevHooks.has("walk-home-shots")


## (rendered runs, --walk-home-shots=DIR) one frame of what the player sees now.
static func _shot(name: String) -> void:
	var dir: String = DevHooks.get_s("walk-home-shots", "")
	if dir == "" or DisplayServer.get_name() == "headless":
		return
	await tree.create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(dir)
	var img: Image = tree.root.get_texture().get_image()
	var path: String = "%s/%02d_%s.png" % [dir, _shot_n, name]
	_shot_n += 1
	img.save_png(path)
	print("[walk-home] shot %s" % path)


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
	await _face_target()
	await _shot("hex2_start")
	if _quick():
		GameState.stats["hexes_cleaned"] = 2.0
		await _wait_step_not("hex2", 4.0)
		return
	var took: int = await _scoop_until("hex2", func() -> int: return ob.target_hex, func() -> bool: return ob.target_hex >= 0 and ob.hex_fraction() >= 0.5)
	await _reload("hex2 half cleaned")
	took += await _scoop_until("hex2", func() -> int: return ob.target_hex, func() -> bool: return float(GameState.stats.get("hexes_cleaned", 0.0)) >= 2.0)
	await tree.create_timer(0.3).timeout
	_check(float(GameState.stats.get("hexes_cleaned", 0.0)) >= 2.0, "hex2: scooping cleans the outlined hex (%d scoops)" % took)
	var moved: bool = await _wait_step_not("hex2", 4.0)
	await tree.create_timer(2.5).timeout  # the card's DONE beat, then the next step slides in
	c = _card()
	_check(moved and _step_id() == "hex3" and c[0] == "Clean 3 hexes", "hex2 done: the card moves on to Clean 3 hexes (%s, %s)" % [_step_id(), str(c)])


## Scoops (the scoop key held at the nearest liftable piece of hex_fn's hex) until done_fn says so.
## Lumi is put by each piece; a near-full chest is emptied (dev: the bin trips are earlier steps).
static func _scoop_until(tag: String, hex_fn: Callable, done_fn: Callable, secs: float = 240.0) -> int:
	await _tap("tool_scoop")
	var t0: int = Time.get_ticks_msec()
	var took: int = 0
	var stall: int = 0
	while not done_fn.call() and Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		var f: SphereField = so.globe.field
		var h: int = hex_fn.call()
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
			print("[walk-home] note: %s: hex %d has nothing liftable left at %.0f%%" % [tag, h, f.removed_fraction(h) * 100.0])
			return took
		var at: Vector3 = f.piece_pos[best]
		var up: Vector3 = at.normalized()
		var away: Vector3 = p.global_position - at
		away = (away - up * away.dot(up))
		away = away.normalized() if away.length() > 0.05 else -SphereGrid.frame(up).z
		_stand(at + away * 1.1, at)
		await _frames(3)
		if p.compartment.fill >= p.capacity() * 0.85:
			p.compartment.take_all()
		await _hold("scoop", 0.7)
		took += 1
		stall = stall + 1 if f.piece_alive[best] == 1 else 0
		if stall == 6:
			print("[walk-home] note: %s: piece %d (size %d, lift %d) stays after 6 scoops" % [tag, best, Pace.piece_size(f, best), Pace.lift_class()])
	p.compartment.take_all()  # (dev) the bin trip after the hex
	return took


# --- hex3: a robot's hex counts, and says so ------------------------------------------------------

static func _part_hex3() -> void:
	if _step_id() != "hex3" and not await _goto("hex3"):
		return
	await _shot("hex3_start")
	await _reload("hex3")
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
	fs.set("_hint_water", true)  # (dev) as taking the tin does
	var slot: int = fs.bed_slots[0]
	if g.slot_species[slot] < 0:
		g.plant(slot)
	var moved: bool = await _wait_step_not("seed", 4.0)
	_check(moved, "seed planted: the card moves on (%s)" % _step_id())
	_check(g.slot_water[slot] <= 0.0, "garden: the new seed is thirsty (water %.1f)" % g.slot_water[slot])
	var marks: Node = _find_marks()
	_check(marks != null, "garden: the plant marks (thirsty drop, soil, rings) are in the world")
	await tree.create_timer(1.0).timeout
	var wc: Array[String] = _card()
	_check(wc[0].contains("watering can") and not (wc[1] + wc[2]).contains("more cubes"), "garden: after planting, the card says one thing: water it, with the keys (%s)" % str(wc))
	var garden_vals: Callable = func() -> Dictionary:
		var gg: Garden = w.get("garden") as Garden
		return {"species": gg.slot_species[slot] if gg else -9, "water": gg.slot_water[slot] if gg else -9.0, "marks": _find_marks() != null, "seeds": GameState.get_currency("seeds").to_float()}
	await _reload("seed planted, not watered", garden_vals)
	g = w.get("garden") as Garden
	fs = w.get("first_seed") as FirstSeed
	if g == null or fs == null:
		_check(false, "garden: no garden after the reload")
		return
	# The water key on the bed.
	_stand(fs.to_global(FirstSeed.GREENHOUSE_POS + Vector3(0.0, 0.0, FirstSeed.BED_SPOTS[0].z)), g.slot_pos[slot])
	await _frames(4)
	await _shot("seed_bed_thirsty")
	p.water = p.water_cap()
	await _tap("tool_water")
	_check(p.tool == Patch.Tool.WATER, "garden: the water key takes the can")
	await _hold("scoop", 1.0)
	_check(g.slot_water[slot] > 0.0, "garden: holding the button on the bed waters the seed (water %.1f)" % g.slot_water[slot])
	await _shot("seed_watered")
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
	await _tap("tool_water")
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


## [v9b] A seed planted with the seed key on the steepest clean hex near the yard, then watered:
## the plant and water rings on a slope (a frame of it in rendered runs).
static func _plant_on_slope() -> void:
	var f: SphereField = so.globe.field
	var g: Garden = w.get("garden") as Garden
	var cands: Array = []  # [slope deg, hex]
	var yard: Vector3 = so.bench_position()
	for h: int in f.hexes_near(yard, 12):
		if not f.is_clean(h) or f.hex_hub[h] != 0 or f.is_water(h):
			continue
		var c: Vector3 = f.hex_center(h)
		var n: Vector3 = c.normalized()
		var fr: Basis = SphereGrid.frame(n)
		var g0: Vector3 = so.globe.terrain.ground(n)
		var dx: Vector3 = so.globe.terrain.ground((c + fr.x * 2.0).normalized()) - g0
		var dz: Vector3 = so.globe.terrain.ground((c + fr.z * 2.0).normalized()) - g0
		cands.append([rad_to_deg(acos(clampf(absf(dx.cross(dz).normalized().dot(n)), 0.0, 1.0))), h])
	cands.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) > float(y[0]))
	GameState.add_currency("seeds", BigNum.from_float(1.0))
	var steep: float = -1.0
	var at: Vector3 = Vector3.ZERO
	for cd: Array in cands.slice(0, 12):  # the steepest clean ground a seed takes (not road or pad)
		var c: Vector3 = f.hex_center(int(cd[1]))
		for k: int in 4:
			var off: Vector3 = SphereGrid.frame(c.normalized()) * Vector3(cos(k * 1.57), 0.0, sin(k * 1.57)) * 2.5
			_stand(c + off, c + off + _north(c) * 3.0)
			await _frames(2)
			if g.free_slot_near(p.global_position, p.forward()) >= 0:
				steep = float(cd[0])
				at = c + off
				break
		if steep >= 0.0:
			break
	if steep < 0.0:
		_check(false, "garden: no clean hex near the yard that takes a seed (%d clean hexes)" % cands.size())
		return
	var n0: float = float(GameState.stats.get("plants_planted", 0.0))
	await _tap("tool_plant")
	_toasts.clear()
	await _hold("scoop", 1.0)
	var planted: bool = float(GameState.stats.get("plants_planted", 0.0)) > n0
	_check(planted, "garden: the seed key plants on a %.0f deg slope (%s)" % [steep, str(_toasts)])
	p.water = p.water_cap()
	await _tap("tool_water")
	await _hold("scoop", 1.0)
	await _shot("slope_plant_%ddeg" % int(steep))
	await _tap("tool_scoop")


# --- hex10 / hex20: Lumi cleans one, the Scoopies another --------------------------------------

static func _part_hex10() -> void:
	await _hex_goal("hex10", 10)


static func _part_hex20() -> void:
	await _hex_goal("hex20", 20)


static func _hex_goal(id: String, goal: int) -> void:
	GameState.stats["hexes_cleaned"] = float(goal - 2)
	if not await _goto(id):
		return
	var c: Array[String] = _card()
	_check(c[0] == "Clean %d hexes" % goal and c[3] == "%d / %d" % [goal - 2, goal], "%s: the card says Clean %d hexes, %d / %d (%s)" % [id, goal, goal - 2, goal, str(c)])
	var way: Variant = ob.waypoint_target()
	_check(ob.target_hex >= 0 or way is Vector3, "%s: a hex is outlined (%d) or the beam points to dirty ground (%s)" % [id, ob.target_hex, str(way)])
	await _face_target()
	await _shot(id + "_start")
	if _quick():
		GameState.stats["hexes_cleaned"] = float(goal)
		await _wait_step_not(id, 4.0)
		if goal >= 20:
			await _plant_on_slope()
		return
	var n0: float = float(GameState.stats.get("hexes_cleaned", 0.0))
	_toasts.clear()
	var took: int = await _scoop_until(id, func() -> int: return ob.target_hex, func() -> bool: return ob.target_hex >= 0 and ob.hex_fraction() >= 0.5)
	await _reload(id + " half cleaned")
	took += await _scoop_until(id, func() -> int: return ob.target_hex, func() -> bool: return float(GameState.stats.get("hexes_cleaned", 0.0)) >= n0 + 1.0)
	_check(float(GameState.stats.get("hexes_cleaned", 0.0)) >= n0 + 1.0, "%s: Lumi's hex counts (%d scoops)" % [id, took])
	# The last one: the real Scoopies, time x8, Lumi idle by the bench.
	var fl: Fleet = w.get("fleet") as Fleet
	_set_money(5000.0, 500.0)
	for k: int in 2:
		if fl.count("scoopie") < 3:
			fl.build("scoopie", so.bench_position())
	var yard: Vector3 = so.bench_position()
	_stand(yard + _north(yard) * 4.0, yard)
	Engine.time_scale = 8.0
	var t0: int = Time.get_ticks_msec()
	while float(GameState.stats.get("hexes_cleaned", 0.0)) < float(goal) and Time.get_ticks_msec() - t0 < 300000:
		await tree.create_timer(0.5, true, false, true).timeout
	Engine.time_scale = 1.0
	_check(float(GameState.stats.get("hexes_cleaned", 0.0)) >= float(goal), "%s: %d Scoopies clean the last hex (%.0f s real at x8)" % [id, fl.count("scoopie"), (Time.get_ticks_msec() - t0) / 1000.0])
	_check(_said("robot"), "%s: a robot's hex in this step says so on screen (%s)" % [id, str(_toasts.filter(func(t: String) -> bool: return "obot" in t))])
	var moved: bool = await _wait_step_not(id, 4.0)
	_check(moved, "%s done: the card moves on (%s)" % [id, _step_id()])
	if goal >= 20:
		await _plant_on_slope()  # by now there is clean ground round the yard to choose from


# --- Steps met out of order never strand the card --------------------------------------------------

static func _part_order() -> void:
	var hub: Hub = w.get("hub") as Hub
	while hub.level < 3:
		var nd: Dictionary = hub.level_def(hub.level + 1)
		var cost: Dictionary = nd.get("cost", {})
		_set_money(float(cost.get("cubes", 0.0)) + 10.0, float(cost.get("parts", 0.0)) + 10.0)
		if not hub.upgrade():
			break
	_check(hub.level >= 3, "order: (dev) the base at level 3 (%d)" % hub.level)
	if await _goto("base2"):
		_check(await _wait_step_not("base2", 4.0), "order: base 2 bought before its step: the step passes by itself (%s)" % _step_id())
	GameState.flags.erase("haul_rig")
	Research.done_list().erase("haul_rig")
	GameState.flags["first_robot_t"] = float(GameState.stats.get("time_played", 0.0))
	if await _goto("haul"):
		for k: int in 12:
			if GameState.flags.get("haul_rig", false):
				break
			await tree.create_timer(0.25).timeout
		_check(GameState.flags.get("haul_rig", false), "order: base 3 before the Haul Bug: the plans come at once, no 20 min wait")
		var fl: Fleet = w.get("fleet") as Fleet
		if fl.count("haulbug") >= 1:
			_check(await _wait_step_not("haul", 4.0), "order: a Haul Bug already built: the step passes (%s)" % _step_id())
		else:
			await tree.create_timer(0.6).timeout
			_check(_card()[1].contains("Bots tab"), "order: the card says Bots tab (%s)" % str(_card()))
	GameState.stats["research_done"] = maxf(float(GameState.stats.get("research_done", 0.0)), 1.0)
	if BenchTiers.tier() >= 3 and await _goto("research1"):
		_check(await _wait_step_not("research1", 4.0), "order: a project finished before its step: the step passes (%s)" % _step_id())


# --- Too heavy, outside the start area ----------------------------------------------------------------

static func _part_heavy() -> void:
	GameState.upgrades["lift_strength"] = 0
	Pace.sync_flags()
	_check(Pace.lift_class() == 0, "heavy: (dev) Lift 0 (%d)" % Pace.lift_class())
	var pad: Vector3 = so.bench_position()
	var f: SphereField = so.globe.field
	var found: int = -1
	var tries: int = 0
	for h0: int in f.hexes_near(pad, 12):
		var c0: Vector3 = f.hex_center(h0)
		var dist: float = OrbitUp.ground_dist(c0, pad)
		if dist < 70.0 or dist > 130.0 or f.is_water(h0) or f.hex_hub[h0] != 0:
			continue
		tries += 1
		if tries > 8:
			break
		_stand(c0, c0 + _north(c0) * 3.0)
		for k: int in 16:
			if f.materialized[h0] == 1:
				break
			await tree.create_timer(0.25).timeout
		found = await _aim_heavy(f)
		if found >= 0:
			break
	_check(found >= 0, "heavy: a too-heavy piece with nothing liftable in front of it, 70-130 m out (%d places)" % tries)
	if found >= 0:
		p.compartment.take_all()
		await _tap("tool_scoop")
		_toasts.clear()
		await tree.physics_frame
		_send("scoop", true)
		await tree.create_timer(0.8).timeout
		var need: int = Pace.piece_size(f, found)
		var mark: Node3D = Vfx.heavy_node
		var lab: String = ""
		if mark:
			for ch: Node in mark.get_children():
				if ch is Label3D:
					lab = (ch as Label3D).text
		_check(mark != null and mark.visible and lab.contains(str(need)), "heavy: the piece gets its mark (%s, '%s')" % [str(mark.visible) if mark else "none", lab])
		var c: Array[String] = _card()
		for k: int in 12:  # the card's line follows within a beat (slow frames in rendered runs)
			c = _card()
			if (c[1] + c[2]).contains("Lift %d" % need):
				break
			await tree.create_timer(0.25).timeout
		_check((c[1] + c[2]).contains("Lift %d" % need), "heavy: the card says which Lift (%s)" % str(c))
		await _shot("heavy_piece")
		_send("scoop", false)
		await _frames(2)
	if _quick():
		return
	# A hex with only too-heavy pieces left.
	var stuck: int = -1
	var fewest: int = 1 << 30
	for h: int in f.hexes_near(p.global_position, 3):
		if f.materialized[h] == 0 or f.is_clean(h) or f.is_water(h) or f.hex_hub[h] != 0 or Pace.hex_clearable(f, h, 0):
			continue
		var n: int = 0
		for pid: int in f.hex_pieces[h]:
			if f.piece_alive[pid] == 1 and Pace.can_lift(f, pid):
				n += 1
		if n < fewest:
			fewest = n
			stuck = h
	_check(stuck >= 0, "heavy: a hex here that Lift 0 can't finish")
	if stuck < 0:
		return
	var took: int = await _scoop_until("heavy hex", func() -> int: return stuck, func() -> bool: return Pace.hex_stuck(so.globe.field, stuck), 300.0)
	_check(Pace.hex_stuck(f, stuck), "heavy: everything liftable taken from hex %d (%d scoops, %.0f%%)" % [stuck, took, f.removed_fraction(stuck) * 100.0])
	var hc: Vector3 = f.hex_center(stuck)
	_stand(hc, hc + _north(hc) * 3.0)
	await _frames(4)
	p.compartment.take_all()
	_toasts.clear()
	await _hold("scoop", 1.2)
	await tree.create_timer(0.4).timeout
	var c2: Array[String] = _card()
	var need_h: int = Pace.hex_need(f, stuck)
	_check(Pace.heavy_hex and (c2[1] + c2[2]).contains("This hex needs Lift %d" % need_h), "heavy: the stuck hex says it needs Lift %d (%s)" % [need_h, str(c2)])
	_check(Vfx.heavy_node != null and Vfx.heavy_node.visible, "heavy: the stuck hex's nearest piece is marked")
	await _shot("heavy_hex")


## Lumi round each too-heavy piece near him: a spot where the scoop sees it and nothing it can lift.
static func _aim_heavy(f: SphereField) -> int:
	var lc: int = Pace.lift_class()
	for h: int in f.hexes_near(p.global_position, 2):
		for pid: int in f.hex_pieces[h]:
			if f.piece_alive[pid] == 0 or Pace.can_lift(f, pid):
				continue
			var at: Vector3 = f.piece_pos[pid]
			var fr: Basis = SphereGrid.frame(at.normalized())
			for k: int in 6:
				var ang: float = TAU * k / 6.0
				var dir: Vector3 = fr.x * cos(ang) + fr.z * sin(ang)
				_stand(at + dir * (1.4 + pow(f.piece_vol[pid], 1.0 / 3.0) * 0.5), at)
				await _frames(2)
				var o: Vector3 = p.scoop_origin()
				var fw: Vector3 = p.forward()
				var r: float = p.stat("scoop_reach")
				var wd: float = p.stat("scoop_width")
				if Pace.find_scoop_target(f, o, fw, r, wd, lc) < 0 and f.find_scoop_target(o, fw, r, wd) == pid:
					return pid
	return -1


## dev (--walk-home-only=probe): big meshes round the yard (what a dark box there is).
static func _part_probe() -> void:
	var yard: Vector3 = so.bench_position()
	var n_seen: int = 0
	for n: Node in tree.root.find_children("*", "VisualInstance3D", true, false):
		var vi: VisualInstance3D = n as VisualInstance3D
		if not vi.is_visible_in_tree():
			continue
		var ab: AABB = vi.global_transform * vi.get_aabb()
		n_seen += 1
		if ab.size.length() < 12.0 or ab.size.length() > 400.0 or ab.get_center().distance_to(yard) > 90.0:
			continue
		var info: String = vi.get_class()
		if vi is MeshInstance3D and (vi as MeshInstance3D).mesh:
			var mi: MeshInstance3D = vi
			var mat: Material = mi.material_override if mi.material_override else (mi.mesh.surface_get_material(0) if mi.mesh.get_surface_count() > 0 else null)
			info += " %s mat %s" % [mi.mesh.get_class(), str(mat.get("albedo_color")) if mat else "none"]
		print("[walk-home] probe %s size %s at %.0f m, %s" % [str(vi.get_path()).right(100), str(ab.size.round()), ab.get_center().distance_to(yard), info])
	print("[walk-home] probe: %d visual nodes" % n_seen)


# --- base2: short of Parts, then the click ----------------------------------------------------------

static func _part_base2() -> void:
	var hub: Hub = w.get("hub") as Hub
	if not await _goto("base2"):
		return
	_set_money(1500.0, 100.0)
	await tree.create_timer(0.6).timeout
	var c: Array[String] = _card()
	_check(c[0] == "Base to level 2" and "50" in c[2], "base2: the card says how many Parts are missing (%s)" % str(c))
	await _shot("base2_start")
	await _reload("base2 short of Parts", func() -> Dictionary: return {"level": (w.get("hub") as Hub).level, "parts": GameState.get_currency("parts").to_float()})
	hub = w.get("hub") as Hub
	var ld: ListDetail = await _open_bench()
	await _shot("base2_bench")
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
	await _reload("base2 just bought", func() -> Dictionary: return {"level": (w.get("hub") as Hub).level})


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
	await _shot("haul_waiting")
	await _reload("haul, plans on the way", func() -> Dictionary: return {"plans": GameState.flags.get("haul_rig", false), "t0_s": float(GameState.flags.get("first_robot_t", -1.0))})
	fl = w.get("fleet") as Fleet
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
	await _shot("haul_bench")
	await _click(_price_tag(ld, "build_haulbug"))
	_check(fl.count("haulbug") >= 1, "haul: clicking its price tag builds a Haul Bug")
	await _close_bench()
	var moved: bool = await _wait_step_not("haul", 4.0)
	_check(moved, "haul done: the card moves on (%s)" % _step_id())


# --- tower2 ----------------------------------------------------------------------------------------

static func _part_tower2() -> void:
	if not await _goto("tower2"):
		return
	await _shot("tower2_start")
	await _reload("tower2", func() -> Dictionary: return {"tier": SignalTower.tier()})
	var cost: Dictionary = SignalTower.next_cost()
	_set_money(float(cost.get("cubes", 0.0)), float(cost.get("parts", 0.0)))
	var ld: ListDetail = await _open_bench()
	if ld == null:
		return
	if str(ld.get("_sel")) != "hb_signal_tower":
		var fw: Fleet = _up().get("fleet") as Fleet
		var uw: Node = fw.world if fw else null
		print("[walk-home] note: bench fleet.world valid %s, is w %s, its tower %s, available tiered %s" % [str(is_instance_valid(uw)), str(uw == w), str(uw.get_node_or_null("SignalTower") != null) if is_instance_valid(uw) else "-", str(HubBuilds.available(uw, "tiered").map(func(e: Dictionary) -> String: return str(e["id"]))) if is_instance_valid(uw) else "-"])
		print("[walk-home] note: tower row: listed %s, kind %s, built %s, hidden %s, node %s, tier %d/%d, bench world is this world %s, target %s" % [str(HubBuilds.listed(w, "signal_tower")), HubBuilds.kind_now("signal_tower"), str(HubBuilds.is_built(w, "signal_tower")), str(Homeward.hidden_builds()), str(w.get_node_or_null("SignalTower") != null), SignalTower.tier(), SignalTower.max_tier(), str(uw == w), str(ob.step_target(ob.current()))])
	_check(str(ld.get("_sel")) == "hb_signal_tower", "tower2: the bench opens on the tower row (%s)" % str(ld.get("_sel")))
	await _shot("tower2_bench")
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
	await _shot("research1_start")
	_set_money(2850.0, 60.0)  # the desk, and a first project (250)
	var ld: ListDetail = await _open_bench()
	if ld == null:
		return
	_check(_tab() == "patch" and str(ld.get("_sel")) == "bench_tier", "research1: the bench opens on the Research Desk (%s / %s)" % [_tab(), str(ld.get("_sel"))])
	await _shot("research1_bench")
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
	await _shot("research1_running")
	await _close_bench()
	await _reload("research1, a project running", func() -> Dictionary: return {"active": Research.active_id(), "left_s": Research.remaining(), "tier": BenchTiers.tier()})
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
	await _shot("base3_start")
	await _reload("base3", func() -> Dictionary: return {"level": (w.get("hub") as Hub).level})
	hub = w.get("hub") as Hub
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
	await _shot("requests_tab")
	await _close_bench()
	var board: Callable = func() -> Dictionary:
		var ids: Array[String] = []
		for sl: Variant in Contracts.slots():
			if sl is Dictionary:
				ids.append("%s:%s" % [str((sl as Dictionary).get("state", "")), str((sl as Dictionary).get("tpl", ""))])
		return {"open": Contracts.unlocked(), "tier": BenchTiers.tier(), "slots": ",".join(ids)}
	await _reload("Request Board bought, no request taken", board)
	ld = await _open_bench()
	cb = _tab_button("contracts")
	_check(cb != null and cb.visible, "after the reload the Requests tab is there")
	if cb:
		await _click(cb)
	await tree.create_timer(1.2).timeout
	_check(_tab() == "contracts", "after the reload the Requests tab opens (%s)" % _tab())
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
	Input.parse_input_event(mv)
	Input.flush_buffered_events()
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
		Input.parse_input_event(ev)  # once, through the window as a real click (it also sets the button state rows read)
		Input.flush_buffered_events()
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
