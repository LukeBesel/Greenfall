class_name WalkOpening
extends RefCounted
## [v9a] Goal audit (owner, 2026-11-13: "getting stuck ... ruins the entire game. It all needs to be
## visual and easy to understand and work"). Plays the opening, New Game to the first robot, the
## way a player does: real key and mouse events from the input map, Lumi steered with W/A/S/D in
## the camera's frame (so he has to really get to the bench, the bin and the scale), the workbench
## bought by mouse clicks on its real price squares and buttons. For every step it checks that the
## step completes, that the card points somewhere in the world (beam or hex outline), and that wrong
## attempts are refused with a reason. Stuck cases tried: buying the wrong thing first and earning
## again, clicking a price you can't pay, the bin after the Baler, the Bot Bay before a clean hex.
##
## Shortcuts (said in the log as "note"): saving up (grinding cubes / parts past what one real
## load or bale shows) is a dev top-up to the step's price (the autoplay run reaches each of these
## prices by playing); when the walker can't steer round something in 40 s it is put there (a FAIL).
##
## --walk-opening[=S] (start after S s, default 6). Without --no-intro the intro is played first
## (Space pauses, Space resumes, Esc skips). Prints [walk-opening] lines, exit 1 on any failure.
## tools/check_exit.sh runs it with the tests.

const TAG: String = "[walk-opening]"

static var _toasts: Array[String] = []
static var _fails: Array[String] = []
static var _so: SliceOrbit
static var _w: Node
static var _p: Patch
static var _ob: Objectives
static var _tree: SceneTree
static var _keys: Dictionary = {}  # action -> held


static func run_dev(so: SliceOrbit) -> void:
	_so = so
	_w = so.w
	_tree = so.w.get_tree()
	await _tree.create_timer(DevHooks.get_f("walk-opening", 6.0)).timeout
	for k: int in 300:
		if not bool(_w.get("building")) and _w.get("objectives") != null and _w.get("patch") != null:
			break
		await _tree.create_timer(0.5, true, false, true).timeout
	_p = _w.get("patch") as Patch
	_ob = _w.get("objectives") as Objectives
	if _p == null or _ob == null:
		print("%s FAIL: no Lumi / objectives" % TAG)
		_tree.quit(1)
		return
	EventBus.toast.connect(func(t: String, _k: String) -> void: _toasts.append(t))
	await _intro()
	await _wait(func() -> bool: return _ob.revealed and _input_on(), 40.0)
	_check(_ob.revealed and _input_on(), "after the intro: the card is up and Lumi takes input")
	await _key_strip()
	await _checklist()
	await _dump3()
	await _compartment()
	await _scoop_size()
	await _baler()
	await _power()
	await _tower()
	await _glim()
	await _hex()
	await _bench2()
	await _robot()
	_release_all()
	print("%s %s" % [TAG, "PASS" if _fails.is_empty() else "FAIL: " + "; ".join(_fails)])
	_tree.quit(0 if _fails.is_empty() else 1)


# --- The steps ---------------------------------------------------------------------------------

static func _intro() -> void:
	var intro: Intro = _w.get("intro") as Intro
	if intro != null and DevHooks.has("intro"):  # it starts once the world is up
		await _wait(func() -> bool: return intro.running, 30.0)
	if intro == null or not intro.running:
		print("%s note: no intro this run (--no-intro or a save)" % TAG)
		return
	await _secs(4.0)
	var pauser: StoryPause = intro.get("_pauser") as StoryPause
	await _key_tap(KEY_SPACE)
	_check(pauser != null and pauser.paused, "intro: Space pauses the cinematic")
	await _secs(1.0)
	await _key_tap(KEY_SPACE)
	_check(pauser != null and not pauser.paused, "intro: Space again resumes it")
	await _key_tap(KEY_ESCAPE)
	await _wait(func() -> bool: return not intro.running, 15.0)
	_check(not intro.running, "intro: Esc skips it")
	var pm: Variant = _w.get("pause_menu")
	await _secs(0.5)
	_check(pm == null or not bool(pm.get("is_open")), "intro: the Esc that skipped did not also open the pause menu")


## The first-minutes strip (M map, V lens, G goals): the keys it shows are the bound keys and do
## what it says.
static func _key_strip() -> void:
	for it: Array in KeyHints.SHORT:
		var ev: InputEvent = _event(str(it[0]))
		var key: String = OS.get_keycode_string((ev as InputEventKey).physical_keycode) if ev is InputEventKey else ""
		_check(key != "" and Settings.glyph(str(it[0])) == key, "key strip: '%s %s' is the bound key (%s)" % [Settings.glyph(str(it[0])), str(it[1]), key])
	var cam: Node = _p.get("sphere_cam")
	if cam and "lens_view" in cam:
		var was: bool = bool(cam.get("lens_view"))
		await _tap("lens_view")
		_check(bool(cam.get("lens_view")) != was, "key strip: V switches the lens view")
		await _tap("lens_view")
	var hud: Node = _w.get("hud")
	var gp: GoalsPanel = hud.get("goals") as GoalsPanel if hud else null
	if gp:
		var ex: bool = gp.expanded
		await _tap("toggle_goals")
		_check(gp.expanded != ex, "key strip: G opens the goal list")
		await _tap("toggle_goals")
	var sv: Variant = _so.layers.get("survey") if _so.layers else null
	if sv is Object:
		await _tap("open_globe")
		await _secs(0.5)
		_check(bool((sv as Object).get("is_open")), "key strip: M opens the map")
		await _tap("open_globe")
		await _secs(1.0)
		if bool((sv as Object).get("is_open")):
			await _key_tap(KEY_ESCAPE)
			await _secs(1.0)
		_check(not bool((sv as Object).get("is_open")) and _input_on(), "key strip: M (or Esc) closes the map and Lumi moves again")


## The restart checklist: fix the bench (E), pick up 8 pieces (hold LMB), the bin, buy an upgrade.
static func _checklist() -> void:
	var tut: Tutorial = _w.get("tutorial") as Tutorial
	if tut == null or tut.done():
		print("%s note: checklist already done" % TAG)
		return
	_check(tut.step_id() == "repair" and "E" in tut.current_text(), "checklist 1: the card says fix the bench with E (%s)" % tut.current_text())
	_check(_ob.waypoint_target() is Vector3, "checklist 1: the beam stands on the bench")
	await _walk_to(func() -> Vector3: return _w.call("bench_pos"), func() -> bool: return bool(_w.call("near_bench")), "the bench")
	var pr: String = str(_w.call("interact_prompt", _p))
	_check("E" in pr, "checklist 1: at the bench the prompt names E (%s)" % pr)
	await _tap("interact")
	await _wait(func() -> bool: return tut.step_id() != "repair", 30.0)
	_check(Camp.bench_ok() and tut.step_id() == "scoop", "checklist 1: E fixed the bench")
	_check("LMB" in tut.current_text() or "Space" in tut.current_text(), "checklist 2: the card says hold LMB (%s)" % tut.current_text())
	await _scoop_load(1.0, 60.0)
	await _wait(func() -> bool: return tut.step_id() != "scoop", 5.0)
	_check(tut.step_id() == "dump", "checklist 2: picking up 8 pieces with LMB held done")
	_check(_ob.waypoint_target() is Vector3, "checklist 3: the beam stands on the bin")
	var d0: int = int(GameState.stats.get("junk_dumps", 0))
	await _to_bin()
	_check(int(GameState.stats.get("junk_dumps", 0)) > d0 and tut.step_id() == "upgrade", "checklist 3: walking into the bin emptied the chest")
	# "Buy an upgrade": the first load pays less than any upgrade costs, so earn (the card's dump3
	# step is up meanwhile), then buy at the bench.
	print("%s note: checklist 4 'buy an upgrade' waits for the cubes of a few loads (the card: %s)" % [TAG, _card()])


static func _dump3() -> void:
	if not await _on_step("dump3"):
		return
	_check(_card().contains("3") and _progress_label() != "", "dump3: the card counts the loads (%s %s)" % [_card(), _progress_label()])
	for k: int in 4:
		if _ob.current().get("id", "") != "dump3":
			break
		await _scoop_load(1.0, 60.0)
		var tgt: String = str(_ob.step_target(_ob.current()).get("to", ""))
		_check(tgt == "bin" and _ob.waypoint_target() is Vector3, "dump3: with a full chest the beam goes to the bin (%s)" % tgt)
		await _to_bin()
	await _done("dump3")


## "Buy a bigger chest": first the stuck case (spend the cubes on something else), then the buy.
static func _compartment() -> void:
	if not await _on_step("compartment"):
		return
	var tut: Tutorial = _w.get("tutorial") as Tutorial
	var cost: float = Economy.upgrade_cost("compartment_size").to_float()
	# A child buys the cheapest other thing first (Scoop Speed). Can they still afford the step later?
	await _earn(maxf(Economy.upgrade_cost("scoop_speed").to_float(), 1.0), false)
	await _open_bench()
	var ld: ListDetail = _ld()
	_check(ld != null and _sel(ld) == "compartment_size", "compartment: E at the bench opens on Chest Size (sel %s)" % (_sel(ld) if ld else "-"))
	await _click_tag("scoop_speed")
	_check(GameState.level_of("scoop_speed") == 1, "stuck test: Scoop Speed bought instead (cubes spent)")
	await _close_bench()
	if tut and not tut.done():
		_check(tut.done(), "checklist 4: any upgrade bought finishes the checklist")
	await _secs(0.6)
	var have: float = GameState.get_currency("cubes").to_float()
	if have < cost:
		_check(str(_ob.step_target(_ob.current()).get("to", "")) == "hex" and _ob.situation.contains("cubes"),
			"stuck test: short of the price, the card says how many cubes and points out to the trash (%s)" % _ob.situation)
		_check(_progress_label().contains("/"), "compartment: saving up shows cubes / price (%s)" % _progress_label())
		await _open_bench()
		ld = _ld()
		_toasts.clear()
		await _click_tag("compartment_size")
		_check(GameState.level_of("compartment_size") == 0 and str(ld.get("_d_req").text).contains("Need"),
			"stuck test: clicking a price you can't pay buys nothing and says what is missing (%s)" % str(ld.get("_d_req").text))
		await _close_bench()
		var c0: float = GameState.get_currency("cubes").to_float()
		await _scoop_load(1.0, 60.0)
		await _to_bin()
		_check(GameState.get_currency("cubes").to_float() > c0, "stuck test: the bin still pays, so the price can be earned again")
	await _earn(cost, false)
	_check(str(_ob.step_target(_ob.current()).get("to", "")) == "bench", "compartment: with the cubes, the beam goes to the bench")
	await _open_bench()
	await _click_tag("compartment_size")
	_check(GameState.level_of("compartment_size") >= 1, "compartment: a click on the price square buys Chest Size")
	await _close_bench()
	await _done("compartment")


static func _scoop_size() -> void:
	if not await _on_step("scoop_size"):
		return
	await _earn(Economy.upgrade_cost("multi_lock").to_float(), false)
	await _open_bench()
	var ld: ListDetail = _ld()
	_check(ld != null and _sel(ld) == "multi_lock", "scoop_size: the bench opens on Scoop Size")
	await _click(ld.get("_d_btn") as Control)  # this time the big button in the detail panel
	_check(GameState.level_of("multi_lock") >= 1, "scoop_size: the detail panel's Install button buys it")
	await _close_bench()
	await _done("scoop_size")


static func _baler() -> void:
	if not await _on_step("baler"):
		return
	await _earn(Economy.upgrade_cost("baler").to_float(), false)
	await _open_bench()
	_check(_sel(_ld()) == "baler", "baler: the bench opens on the Baler")
	_toasts.clear()
	await _click_tag("baler")
	_check(Pace.baler_unlocked(), "baler: bought by a click")
	_check(_said("bale"), "baler: a line says how to make a bale (%s)" % str(_toasts))
	await _close_bench()
	await _done("baler")


static func _power() -> void:
	if not await _on_step("power"):
		return
	_check(_card(true).contains("[RMB]") or _card(true).contains("[C]"), "power: the card names the bale key (%s)" % _card(true))
	_check(KeyHints.items_for(true, true).any(func(it: Array) -> bool: return str(it[0]) == "cube"), "power: the full key list has 'press bale'")
	# The old habit: a chest to the bin. After the Baler the bin takes no loose junk; say why.
	if _p.compartment.fill >= _p.capacity() * 0.45:  # a chest left full from saving up: bale it first
		await _make_and_sell_bale()
	await _scoop_load(0.5, 40.0)
	await _wait(func() -> bool: return _p.compartment.pending <= 0.0, 3.0)
	_check(_p.compartment.fill < _p.capacity() * 0.9, "power: a half-full chest for the bin test (%.1f / %.1f)" % [_p.compartment.fill, _p.capacity()])
	var bin0: Vector3 = Objectives.bin_point(_w)
	await _walk_to(func() -> Vector3: return bin0, func() -> bool: return _flat(_p.global_position - bin0).length() < 5.0, "near the bin")
	var fl0: int = _float_idx()
	_toasts.clear()
	var f0: float = _p.compartment.fill
	await _to_bin()
	await _secs(1.5)
	_check(_p.compartment.fill >= f0 - 0.01, "power: the bin takes no loose junk after the Baler")
	var said: String = ", ".join(_floats_since(fl0)) + " | " + ", ".join(_toasts)
	_check(said.to_lower().contains("bale"), "power: at the bin with loose junk, a line says to press a bale (%s)" % said)
	for k: int in 3:
		if int(GameState.stats.get("cubes_cashed", 0)) >= 3:
			break
		await _make_and_sell_bale()
	await _done("power")


static func _tower() -> void:
	if not await _on_step("tower"):
		return
	await _earn_parts(SignalTower.next_cost())
	await _open_bench()
	var scr: UpgradesScreen = _w.get("upgrades") as UpgradesScreen
	_check(str(scr.get("_tab")) == "build" and _sel(_ld()) == "signal_tower", "tower: the bench opens on Build, Signal Tower (%s %s)" % [str(scr.get("_tab")), _sel(_ld())])
	await _click_tag("signal_tower")
	_check(SignalTower.tier() >= 1, "tower: a click builds the signal tower")
	await _close_bench()
	await _done("tower")


static func _glim() -> void:
	if not await _on_step("glim"):
		return
	var cost: Dictionary = YardBuilds.def("glim").get("cost", {})
	await _dig_part()
	if not GameState.can_afford_all(cost):
		_check(_ob.situation != "" and (_ob.situation.contains("cubes") or _ob.situation.contains("parts")),
			"glim: short of the price, the card says what is missing (%s)" % _ob.situation)
	await _earn_parts(cost)
	await _open_bench()
	_check(_sel(_ld()) == "glim", "glim: the bench opens on Repair Glim (%s)" % _sel(_ld()))
	await _click_tag("glim")
	await _close_bench()
	Engine.time_scale = 4.0
	await _wait(func() -> bool: return bool(GameState.flags.get("glim_repaired", false)) and _input_on(), 60.0)
	Engine.time_scale = 1.0
	_check(bool(GameState.flags.get("glim_repaired", false)), "glim: built by a click; the repair plays and he is up")
	await _done("glim")


static func _hex() -> void:
	if not await _on_step("hex"):
		return
	# The Bot Bay is locked until a hex is clean, and says so.
	await _earn_parts(BenchTiers.next_cost())
	var why: String = BenchTiers.block_reason(_w)
	_check(why.contains("hex"), "bench2 before a clean hex: the Bot Bay says 'Clean 1 hex first' (%s)" % why)
	await _secs(0.6)
	var h: int = _ob.target_hex
	_check(h >= 0, "hex: a target hex is picked and outlined")
	var ol: ObjectiveHex = _ob.outline
	_check(ol != null and ol.is_visible_in_tree(), "hex: its outline shows on the ground")
	_check(_progress_label().ends_with("%"), "hex: the card shows the %% cleaned (%s)" % _progress_label())
	var f: HexField = _w.get("field") as HexField
	var t0: int = Time.get_ticks_msec()
	while int(GameState.stats.get("hexes_cleaned", 0)) < 1 and Time.get_ticks_msec() - t0 < 300000:
		if _p.compartment.fill >= _p.capacity() * 0.9:
			await _tap("cube")  # a bale, left behind
			await _secs(2.0)
		var pid: int = _liftable(f, h)
		if pid < 0:
			break
		await _scoop_piece(f, pid)
	_check(int(GameState.stats.get("hexes_cleaned", 0)) >= 1, "hex: holding LMB on the outlined hex's junk cleans it (%d%%)" % int(f.removed_fraction(h) * 100.0))
	await _done("hex")


static func _bench2() -> void:
	if not await _on_step("bench2"):
		return
	await _earn_parts(BenchTiers.next_cost())
	await _open_bench()
	_check(_sel(_ld()) == "bench_tier", "bench2: the bench opens on the Bot Bay (%s)" % _sel(_ld()))
	var parts0: float = GameState.get_currency("parts").to_float()
	await _click_tag("bench_tier")
	_check(BenchTiers.tier() >= 2, "bench2: a click buys the Bot Bay")
	_check(GameState.get_currency("parts").to_float() >= parts0 - 20.0 + 39.0, "bench2: the robot kit's 40 Parts are paid")
	_check(UpgradesScreen.tab_visible("bots", _w), "bench2: the Bots tab is open")
	await _close_bench()
	await _done("bench2")


static func _robot() -> void:
	if not await _on_step("robot"):
		return
	var fl: Fleet = _w.get("fleet") as Fleet
	await _earn_parts({"cubes": fl.build_cost("scoopie").to_float(), "parts": fl.build_parts("scoopie").to_float()})
	await _open_bench()
	var scr: UpgradesScreen = _w.get("upgrades") as UpgradesScreen
	_check(str(scr.get("_tab")) == "bots", "robot: the bench opens on the Bots tab (%s)" % str(scr.get("_tab")))
	_check(_sel(_ld()) == "build_scoopie", "robot: on the Scoopie (%s)" % _sel(_ld()))
	await _click_tag("build_scoopie")
	_check(fl.robot_total() >= 1, "robot: a click builds the Scoopie")
	await _close_bench()
	await _done("robot")
	_check(str(_ob.current().get("id", "")) == "hex2", "robot: the next step comes (%s)" % str(_ob.current().get("id", "")))


# --- Steps' shared checks ----------------------------------------------------------------------

## Waits for `id` on the card; checks it says something, shows a marker. False if the chain moved on.
static func _on_step(id: String) -> bool:
	await _wait(func() -> bool: return str(_ob.current().get("id", "")) == id or _ob.step > _index(id), 20.0)
	if _stopped:
		return false
	if str(_ob.current().get("id", "")) != id:
		if _ob.step < _index(id):  # the chain is stuck on an earlier step: stop here
			_check(false, "%s: the step never came up (card stuck on %s)" % [id, str(_ob.current().get("id", ""))])
			_stopped = true
		else:
			print("%s note: %s was done before its turn (skipped)" % [TAG, id])
		return false
	await _secs(0.5)
	var tgt: Dictionary = _ob.step_target(_ob.current())
	var marked: bool = _ob.waypoint_target() is Vector3 or _ob.target_hex >= 0
	_check(_card() != "" and marked, "%s: card '%s' / '%s', marker %s" % [id, _card(), _card(true), str(tgt.get("to", ""))])
	return true


static func _done(id: String) -> void:
	await _wait(func() -> bool: return _ob.step > _index(id), 10.0)
	_check(_ob.step > _index(id), "%s: complete, the card moves on" % id)
	await _secs(1.8)


static func _index(id: String) -> int:
	for i: int in _ob.chain.size():
		if str((_ob.chain[i] as Dictionary).get("id", "")) == id:
			return i
	return -1


static func _card(why: bool = false) -> String:
	var def: Dictionary = _ob.current()
	return "" if def.is_empty() else Objectives.texts(def)[1 if why else 0]


static func _progress_label() -> String:
	return str(_ob.progress()[1])


# --- Earning ---------------------------------------------------------------------------------

## Real loads (or bales) until `cubes`; past two real rounds it's a dev top-up (said in the log).
static func _earn(cubes: float, _bales: bool) -> void:
	var rounds: int = 0
	while GameState.get_currency("cubes").to_float() < cubes and rounds < 2:
		rounds += 1
		if Pace.baler_unlocked():
			await _make_and_sell_bale()
		else:
			await _scoop_load(1.0, 60.0)
			await _to_bin()
	var have: float = GameState.get_currency("cubes").to_float()
	if have < cubes:
		print("%s note: top-up %.0f cubes (saving up)" % [TAG, cubes - have])
		GameState.add_currency("cubes", BigNum.from_float(ceilf(cubes - have)))


static func _earn_parts(cost: Dictionary) -> void:
	var need: float = float(Currencies.fold(cost).get("parts", 0.0)) - GameState.get_currency("parts").to_float()
	if need > 0.0:
		print("%s note: top-up %.0f parts (salvage and digging)" % [TAG, need])
		GameState.add_currency("parts", BigNum.from_float(ceilf(need)))
	await _earn(float(Currencies.fold(cost).get("cubes", 0.0)), true)


## The nearest buried part the detector finds: walk onto it, E digs it up.
static func _dig_part() -> void:
	var f: HexField = _w.get("field") as HexField
	var det: PartDetector = _p.get("detector") as PartDetector
	if f == null or det == null:
		return
	var i: int = f.nearest_part(_p.global_position, 60.0)
	if i < 0 or f.part_found[i] != 0:
		print("%s note: no buried part within 60 m to dig" % TAG)
		return
	var at: Vector3 = f.part_pos[i]
	await _walk_to(func() -> Vector3: return at, func() -> bool: return det.can_dig(), "a buried part", 0.8)
	var parts0: float = GameState.get_currency("parts").to_float()
	await _tap("interact")
	await _wait(func() -> bool: return GameState.get_currency("parts").to_float() > parts0, 10.0)
	_check(GameState.get_currency("parts").to_float() > parts0, "parts: E on the detector's spot digs a part up (+%.0f)" % (GameState.get_currency("parts").to_float() - parts0))


static func _make_and_sell_bale() -> void:
	await _scoop_load(0.95, 60.0)
	await _wait(func() -> bool: return _p.compartment.pending <= 0.0, 3.0)  # the last pieces fly in
	var made0: int = int(GameState.stats.get("cubes_made", 0))
	var before: Array[Node] = _tree.get_nodes_in_group("junk_cube")
	await _tap("cube")
	await _wait(func() -> bool: return int(GameState.stats.get("cubes_made", 0)) > made0, 6.0)
	_check(int(GameState.stats.get("cubes_made", 0)) > made0, "bale: RMB presses a bale")
	await _secs(1.0)
	var bale: JunkCube = null
	for n: Node in _tree.get_nodes_in_group("junk_cube"):
		if not (n in before):
			bale = n as JunkCube
	if bale and _p.nearest_loose_cube() != bale:  # pressed out behind him: turn round to it
		await _walk_to(func() -> Vector3: return bale.global_position, func() -> bool: return _p.nearest_loose_cube() == bale, "the bale", 0.9)
	await _tap("interact")
	_check(not _p.carried.is_empty(), "bale: E picks it up (bale %s m away)" % ("%.1f" % _flat(bale.global_position - _p.global_position).length() if bale else "none"))
	if str(_ob.current().get("id", "")) == "power":
		_check(str(_ob.step_target(_ob.current()).get("to", "")) == "depot" and _ob.waypoint_target() is Vector3, "bale: carrying it, the beam goes to the scale (%s)" % str(_ob.step_target(_ob.current()).get("to", "")))
	var dp: Node3D = _w.get("depot") as Node3D
	var cashed0: int = int(GameState.stats.get("cubes_cashed", 0))
	await _walk_to(func() -> Vector3: return dp.global_position, func() -> bool: return dp.call("pad_contains", _p.global_position), "the scale")
	await _wait(func() -> bool: return int(GameState.stats.get("cubes_cashed", 0)) > cashed0, 6.0)
	_check(int(GameState.stats.get("cubes_cashed", 0)) > cashed0, "bale: stepping on the scale sells it")


# --- Scooping ---------------------------------------------------------------------------------

## Scoops (walking to the nearest liftable piece, LMB held) until the chest is `frac` full.
static func _scoop_load(frac: float, max_s: float) -> void:
	var f: HexField = _w.get("field") as HexField
	var t0: int = Time.get_ticks_msec()
	while _p.compartment.fill < _p.capacity() * frac * 0.98 and Time.get_ticks_msec() - t0 < max_s * 1000.0:
		var pid: int = _liftable(f, -1)
		if pid < 0:
			_check(false, "nothing liftable near Lumi")
			return
		await _scoop_piece(f, pid)
	_check(_p.compartment.fill >= _p.capacity() * frac * 0.9, "scoop: LMB held on the junk fills the chest (%.1f / %.1f, Lumi at %s)" % [_p.compartment.fill, _p.capacity(), _yard(_p.global_position)])


static func _scoop_piece(f: HexField, pid: int) -> void:
	var at: Vector3 = f.piece_pos[pid]
	await _walk_to(func() -> Vector3: return at, func() -> bool: return _p.global_position.distance_to(at) < 1.3, "a piece", 1.0, 12.0, true)
	_hold_action("scoop", true)
	var t0: int = Time.get_ticks_msec()
	while f.piece_alive[pid] == 1 and Time.get_ticks_msec() - t0 < 3000 and _p.compartment.can_accept(_p.capacity()):
		await _frames(3)
	_hold_action("scoop", false)
	if f.piece_alive[pid] == 1 and _p.compartment.can_accept(_p.capacity()):
		_skip[pid] = true  # bitten or out of reach: the next one
	await _frames(2)


static var _skip: Dictionary = {}
static var _stopped: bool = false


## The nearest liftable piece (in hex `h` if >= 0) that Lumi can see from where he stands (a
## player goes for the junk in view, not the piece behind the bin's wall).
static func _liftable(f: HexField, h: int) -> int:
	var cand: Array = []
	var pool: PackedInt32Array = f.hex_pieces[h] if h >= 0 else f.pieces_within(_p.global_position, 30.0)
	for pid: int in pool:
		if f.piece_alive[pid] != 1 or _skip.has(pid) or f.locked.has(f.piece_hex[pid]) or not Pace.can_lift(f, pid):
			continue
		if f.is_water(f.piece_hex[pid]) or bool(_p.call("_water_at", f.piece_pos[pid])):  # floating junk: for later (the lake by the bin)
			continue
		cand.append([f.piece_pos[pid].distance_to(_p.global_position), pid])
	cand.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	var space: PhysicsDirectSpaceState3D = _p.get_world_3d().direct_space_state
	var u: Vector3 = _p.global_position.normalized()
	for i: int in mini(cand.size(), 12):
		var pid: int = int(cand[i][1])
		var q := PhysicsRayQueryParameters3D.create(_p.global_position + u * 0.6, f.piece_pos[pid] + u * 0.4, _p.collision_mask)
		q.exclude = [_p.get_rid()]
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty() or hit["collider"] is JunkCube:
			return pid
	return int(cand[0][1]) if not cand.is_empty() else -1


## Walks to where the beam points for "empty your chest" (the bin's body) until the chest empties
## or he stands against the bin. A player stops at the bin; so does this.
static func _to_bin() -> void:
	if _p.compartment.is_empty():
		return
	var at: Vector3 = Objectives.bin_point(_w)
	var d0: int = int(GameState.stats.get("junk_dumps", 0))
	var dumped: Callable = func() -> bool: return int(GameState.stats.get("junk_dumps", 0)) > d0
	await _walk_to(func() -> Vector3: return at, dumped, "the bin", 1.3)
	await _wait(dumped, 1.5)
	if not bool(dumped.call()) and Pace.dump_allowed() and not _p.compartment.is_empty():
		var dp: Node3D = _w.get("depot") as Node3D
		_check(false, "bin: at the bin body (%.1f m) the chest did not empty; the dump reach is %.1f m round the scale, %.1f m away" % [_flat(_p.global_position - at).length(), Pace.BIN_RADIUS, _flat(dp.global_position - at).length()])
		await _walk_to(func() -> Vector3: return dp.global_position, dumped, "the scale (dump reach)")
	await _secs(0.6)


# --- The workbench ----------------------------------------------------------------------------

static func _open_bench() -> void:
	var scr: UpgradesScreen = _w.get("upgrades") as UpgradesScreen
	if scr.is_open:
		return
	await _walk_to(func() -> Vector3: return _w.call("bench_pos"), func() -> bool: return bool(_w.call("near_bench")), "the bench")
	if not Camp.bench_ok():  # only on a dev jump (--objective): the checklist fixes it in a real game
		await _tap("interact")
		var camp: Node = _w.get("camp")
		await _wait(func() -> bool: return Camp.bench_ok() and _input_on() and not (camp != null and bool(camp.get("repairing"))) and "Open" in str(_w.call("interact_prompt", _p)), 30.0)
		await _secs(1.5)
	var det: PartDetector = _p.get("detector") as PartDetector
	if det.can_dig() and _p.carried.is_empty():  # a part buried by the bench: E digs it (the prompt says so)
		_check(str(_p.prompt) == "dig", "bench: standing on a buried part, the prompt says dig (%s)" % str(_p.prompt))
		var parts0: float = GameState.get_currency("parts").to_float()
		await _tap("interact")
		await _wait(func() -> bool: return GameState.get_currency("parts").to_float() > parts0, 6.0)
		_check(GameState.get_currency("parts").to_float() > parts0, "bench: E dug the part up")
		await _secs(0.5)
	_toasts.clear()
	var fl0: int = _float_idx()
	await _tap("interact")
	await _secs(0.8)  # the hologram unfolds
	if not scr.is_open:
		var ia: Interactables = _w.get("interactables") as Interactables
		var ne: Dictionary = ia.nearest(_p.global_position) if ia else {}
		print("%s debug E: toasts %s floats %s ia %s at %s bench %s" % [TAG, str(_toasts), str(_floats_since(fl0)), str((ne.get("node") as Node).name) if not ne.is_empty() else "-", _yard(_p.global_position), _yard(_w.call("bench_pos"))])
		print("%s debug bench prompt '%s' near %s modal %s input %s fresh %s cubing %s carried %d dig %s pm %s" % [TAG, str(_w.call("interact_prompt", _p)), str(_w.call("near_bench")), str(_w.call("any_modal_open")),
			str(_input_on()), str((_p.input as PlayerInput)._fresh()), str(_p.get("_cubing")), _p.carried.size(), str((_p.get("detector") as PartDetector).can_dig()), str(bool((_w.get("pause_menu") as Object).get("is_open")))])
		await _secs(1.0)
		await _tap("interact")
		await _secs(0.8)
		print("%s debug second E: open %s" % [TAG, str(scr.is_open)])
	_check(scr.is_open, "bench: E at the bench opens the workbench")


static func _close_bench() -> void:
	var scr: UpgradesScreen = _w.get("upgrades") as UpgradesScreen
	if not scr.is_open:
		return
	await _key_tap(KEY_TAB)
	await _secs(0.6)
	_check(not scr.is_open and _input_on(), "bench: Tab closes it and Lumi moves again")


static func _ld() -> ListDetail:
	var scr: UpgradesScreen = _w.get("upgrades") as UpgradesScreen
	return scr.get("_panel") as ListDetail if scr else null


static func _sel(ld: ListDetail) -> String:
	return str(ld.get("_sel")) if ld else ""


## Clicks the price square of row `id` (the tab must show it).
static func _click_tag(id: String) -> void:
	var ld: ListDetail = _ld()
	var row: Button = (ld.get("_rows") as Dictionary).get(id) as Button if ld else null
	if row == null:
		ld.select_id(id)  # its category: a player clicks the category chip; the row then shows
		await _frames(3)
		row = (ld.get("_rows") as Dictionary).get(id) as Button
	if row == null:
		_check(false, "bench: no row %s on the open tab" % id)
		return
	await _click((row.get_meta("parts") as Array)[3] as Control)


## A real left click (motion, press, release) at the middle of `c` on screen.
static func _click(c: Control) -> void:
	if c == null or not c.is_visible_in_tree():
		_check(false, "click: the control is not on screen")
		return
	var pos: Vector2 = c.get_screen_transform() * (c.size * 0.5)
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	Input.parse_input_event(mm)
	await _frames(2)
	var vp: Viewport = c.get_viewport()
	# A headless run has no window (size 0), so the window-to-viewport mapping drops mouse events
	# before the GUI sees them; then the same events go straight into the viewport, in its own
	# coordinates (the GUI's real picking, gui_input and button press from there on).
	var local: bool = vp.gui_get_hovered_control() == null
	var lp: Vector2 = c.get_global_transform_with_canvas() * (c.size * 0.5)
	if local:
		var lm := InputEventMouseMotion.new()
		lm.position = lp
		lm.global_position = lp
		vp.push_input(lm, true)
		await _frames(2)
	var hov: Control = vp.gui_get_hovered_control()
	if hov == null or not (hov == c or c.is_ancestor_of(hov)):
		_check(false, "click: the pointer over %s lands on %s (something covers it)" % [c.name, str(hov)])
	for down: bool in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.position = pos
		mb.global_position = pos
		mb.pressed = down
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		Input.parse_input_event(mb)  # Input's own state (is_mouse_button_pressed)
		Input.flush_buffered_events()
		if local:
			var lb: InputEventMouseButton = mb.duplicate()
			lb.position = lp
			lb.global_position = lp
			vp.push_input(lb, true)
		await _frames(2)
	await _secs(0.3)


# --- Walking with the keys --------------------------------------------------------------------

## Walks Lumi with W/A/S/D (camera frame) toward `to` until `arrived`. Sidesteps when blocked;
## after `max_s` he is put there (a FAIL: the walker could not get there).
static func _walk_to(to: Callable, arrived: Callable, what: String, stop_m: float = 0.0, max_s: float = 40.0, scoop: bool = false) -> void:
	var t0: int = Time.get_ticks_msec()
	var last: Vector3 = _p.global_position
	var still: float = 0.0
	var side: float = 0.0
	var side_dir: int = 1
	var tries: int = 0
	var detour: Vector3 = Vector3.ZERO
	while not bool(arrived.call()):
		if Time.get_ticks_msec() - t0 > max_s * 1000.0:
			_release_all()
			var at: Vector3 = to.call()
			if what == "a piece":  # one piece wedged somewhere: a player takes another one
				print("%s note: a piece at %s out of the walker's way, took another" % [TAG, _yard(at)])
				return
			_check(false, "walk: could not get to %s in %.0f s with the keys (%.1f m left, stuck at %s, target %s; put there)" % [what, max_s, _flat(at - _p.global_position).length(), _yard(_p.global_position), _yard(at)])
			_stand(at - _flat(at - _p.global_position).normalized() * maxf(stop_m, 1.0), at)
			await _frames(4)
			return
		var tgt: Vector3 = to.call()
		# Blocked a while (a wall of the bin's bay, a crate): go round by the open yard first, as a
		# player would: a point 4 m from the target on the yard-centre side, then the target.
		if tries >= 3 and detour == Vector3.ZERO:
			var c: Vector3 = (_so.globe.sites[0]["transform"] as Transform3D).origin
			detour = tgt + _flat(c - tgt).normalized() * 4.0
		if detour != Vector3.ZERO:
			if _flat(detour - _p.global_position).length() < 0.8:
				detour = Vector3.INF  # reached: the target again
			elif detour != Vector3.INF:
				tgt = detour
		var cam: Node = _p.get("sphere_cam")
		var fr: Basis = cam.get("frame") if cam and "frame" in cam else _p.global_basis
		var d: Vector3 = _flat(tgt - _p.global_position)
		if stop_m > 0.0 and d.length() < stop_m and (detour == Vector3.ZERO or detour == Vector3.INF):
			break
		# Steer round what stands in the way, as a player does: the first free direction turning
		# out from the straight line (a ray 1.6 m ahead at knee and chest height).
		var dir: Vector3 = _steer(d.normalized(), minf(d.length(), 1.6), side_dir)
		if side > 0.0:  # still wedged: commit to the other side for a moment
			side -= 0.05
			dir = _steer(dir.rotated(_p.global_position.normalized(), PI * 0.5 * side_dir), 1.2, side_dir)
		var x: float = dir.dot(fr.x)
		var z: float = dir.dot(fr.z)
		var n: float = maxf(absf(x), absf(z))
		_hold_action("move_right", x > n * 0.4)
		_hold_action("move_left", x < -n * 0.4)
		_hold_action("move_back", z > n * 0.4)
		_hold_action("move_forward", z < -n * 0.4)
		_hold_action("scoop", scoop and d.length() < 3.0)
		await _tree.create_timer(0.05, true, false, true).timeout
		var moved: float = _p.global_position.distance_to(last)
		last = _p.global_position
		still = still + 0.05 if moved < 0.01 else 0.0
		if still > 0.6 and side <= 0.0:
			tries += 1
			side = 0.6 + 0.4 * tries  # longer each time, alternating sides
			side_dir = -side_dir
			still = 0.0
	_release_all()
	await _frames(3)


static func _steer(dir: Vector3, ahead: float, prefer: int) -> Vector3:
	var space: PhysicsDirectSpaceState3D = _p.get_world_3d().direct_space_state
	var u: Vector3 = _p.global_position.normalized()
	for k: int in [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5]:
		var dd: Vector3 = dir.rotated(u, deg_to_rad(25.0) * k * prefer)
		var free: bool = true
		for h: float in [0.35, 0.9]:
			var from: Vector3 = _p.global_position + u * h
			var q := PhysicsRayQueryParameters3D.create(from, from + dd * maxf(ahead, 0.6), _p.collision_mask)
			q.exclude = [_p.get_rid()]
			var hit: Dictionary = space.intersect_ray(q)
			if not hit.is_empty() and not (hit["collider"] is JunkCube):
				free = false
				break
		if free:
			return dd
	return dir


## A point in the start yard's own metres (x, z from its centre): readable in the log.
static func _yard(at: Vector3) -> String:
	var l: Vector3 = (_so.globe.sites[0]["transform"] as Transform3D).affine_inverse() * at
	return "yard (%.1f, %.1f) = world %.1f,%.1f,%.1f" % [l.x, l.z, at.x, at.y, at.z]


static func _flat(v: Vector3) -> Vector3:
	var u: Vector3 = _p.global_position.normalized()
	return v - u * v.dot(u)


static func _stand(pos: Vector3, look: Vector3) -> void:
	var gp: Vector3 = _so.globe.terrain.ground(pos.normalized())
	var up: Vector3 = gp.normalized()
	var fwd: Vector3 = look - gp
	fwd = (fwd - up * fwd.dot(up)).normalized()
	_p.place_on_sphere(gp, fwd)


# --- Input ------------------------------------------------------------------------------------

static func _input_on() -> bool:
	return _p.input is PlayerInput and (_p.input as PlayerInput).enabled


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


static func _hold_action(action: String, down: bool) -> void:
	if bool(_keys.get(action, false)) == down:
		return
	_keys[action] = down
	_send(action, down)


static func _release_all() -> void:
	for a: String in _keys.keys():
		_hold_action(a, false)


static func _tap(action: String) -> void:
	await _tree.physics_frame
	_send(action, true)
	await _tree.create_timer(0.1, true, false, true).timeout
	_send(action, false)
	await _frames(3)


static func _key_tap(code: Key) -> void:
	for down: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = down
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await _tree.create_timer(0.1, true, false, true).timeout
	await _frames(3)


# --- Small helpers ----------------------------------------------------------------------------

static func _said(t: String) -> bool:
	for s: String in _toasts:
		if not s.begins_with("Achievement") and t.to_lower() in s.to_lower():
			return true
	return false


## The floating 3D lines (Vfx.float_text) shown since index `i0` of its pool.
static func _float_idx() -> int:
	return int(Vfx.get("_text_idx"))


static func _floats_since(i0: int) -> Array[String]:
	var out: Array[String] = []
	var pool: Array = Vfx.get("_texts")
	var i: int = i0
	while i != _float_idx() and out.size() < pool.size():
		out.append(str((pool[i] as Label3D).text))
		i = (i + 1) % pool.size()
	return out


static func _check(ok: bool, what: String) -> void:
	print("%s %s %s" % [TAG, "ok  " if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


static func _wait(cond: Callable, secs: float) -> void:
	var t0: int = Time.get_ticks_msec()
	while not bool(cond.call()) and Time.get_ticks_msec() - t0 < secs * 1000.0 / maxf(Engine.time_scale, 1.0):
		await _tree.create_timer(0.25, true, false, true).timeout


static func _secs(s: float) -> void:
	await _tree.create_timer(s, true, false, true).timeout


static func _frames(n: int) -> void:
	for k: int in n:
		await _tree.physics_frame
