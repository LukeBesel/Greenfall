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
##
## Save and reload: at a point in every step (and during the intro and WREN's first brief) the walk
## quits and comes back the way a player does: Esc, the pause menu's Quit (it saves) to the title,
## then Continue, which loads the save through the real path. In the intro (no pause menu: Esc
## skips it) it is a window close (the game saves on the close request), then a start again. Then the
## card, its count, the beam, the chest, what Lumi carries, the money and the step's state must be
## what they were, and the walk goes on from there (so the step can still be finished). Dev: the
## --fresh / --objective arguments are dropped before the first Continue (a restart has none), and
## --intro stays only while a windowed start would replay it. --walk-opening-no-reload skips this.
## Not yet run to the end (drafts, not in check_exit):
## --walk-opening-full: no top-ups and no reloads: every price is earned by scooping, baling,
##   selling and digging; prints the game minutes each step took.
## --walk-opening-pad: the same walk on a controller (joypad events through the input map, buys by
##   A on the bench's focused row, Y closes).

const TAG: String = "[walk-opening]"

static var _toasts: Array[String] = []
static var _fails: Array[String] = []
static var _so: SliceOrbit
static var _w: Node
static var _p: Patch
static var _ob: Objectives
static var _tree: SceneTree
static var _keys: Dictionary = {}  # action -> held
static var _active: bool = false
static var _quit_skipped: bool = false  # the last _quit_and_continue could not quit (no pause menu there)
static var _next_so: SliceOrbit  # set by run_dev when the world is rebuilt after a Continue
static var _full: bool = false
static var _pad: bool = false
static var _reloads: bool = true
static var _ts: float = 1.0
static var _step_f: int = 0  # physics frame the current step started on
static var _times: Array[String] = []


static func run_dev(so: SliceOrbit) -> void:
	if _active:  # the world rebuilt after Continue: the running walk picks it up
		_next_so = so
		return
	_active = true
	_full = DevHooks.has("walk-opening-full")
	_pad = DevHooks.has("walk-opening-pad")
	_reloads = not (_full or _pad or DevHooks.has("walk-opening-no-reload"))
	_ts = maxf(Engine.time_scale, 1.0)
	_tree = so.w.get_tree()
	await _tree.create_timer(DevHooks.get_f("walk-opening", 6.0), true, false, true).timeout
	if not await _bind(so):
		print("%s FAIL: no Lumi / objectives" % TAG)
		_tree.quit(1)
		return
	print("%s mode: %s" % [TAG, "full grind" if _full else ("controller" if _pad else ("reloads" if _reloads else "plain"))])
	EventBus.toast.connect(func(t: String, _k: String) -> void: _toasts.append(t))
	await _intro()
	await _brief_reload()
	# WREN's brief plays first after a skip (its lines run on the subtitle clock): wait on the
	# condition, long, not a tight time.
	await _wait(func() -> bool: return _ob.revealed and _input_on(), 300.0)
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
	if _full:
		print("%s game minutes per step: %s" % [TAG, ", ".join(_times)])
	print("%s %s" % [TAG, "PASS" if _fails.is_empty() else "FAIL: " + "; ".join(_fails)])
	_tree.quit(0 if _fails.is_empty() else 1)


# --- The steps ---------------------------------------------------------------------------------

static func _intro() -> void:
	var intro: Intro = _w.get("intro") as Intro
	if intro != null and DevHooks.has("intro"):  # it starts once the world is up
		# It starts after the loading screen's fade (wall clock): wait for it, not for a time.
		await _wait(func() -> bool: return intro.running or bool(GameState.flags.get("intro_done", false)), 900.0)
	if intro == null or not intro.running:
		print("%s note: no intro this run (--no-intro or a save)" % TAG)
		return
	await _secs(4.0)
	if _reloads:  # the intro has no pause menu (Esc skips it): the window is closed mid-film
		var saved: String = "intro_done=%s brief=%s" % [str(GameState.flags.get("intro_done", false)), str(GameState.flags.get("onboard_brief", false))]
		await _quit_and_continue("during the intro", "close")
		intro = _w.get("intro") as Intro
		var again: bool = intro != null and intro.running
		_check(true, "quit during the intro (saved %s): after Continue the intro %s, Lumi at %s" % [saved, "plays again from the start" if again else "does not play", _yard(_p.global_position)])
		if not again:
			await _wait(func() -> bool: return _ob.revealed, 60.0)
			_check(_input_on(), "quit during the intro: after Continue Lumi takes input")
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
		if bool(cam.get("lens_view")) == was:  # who swallowed the key?
			var vp: Viewport = _p.get_viewport()
			print("%s debug V: focus %s, paused %s, modal %s, ts %.2f, view %s, input %s, scene %s" % [TAG, str(vp.gui_get_focus_owner()), str(_tree.paused),
				str(_w.call("any_modal_open")), Engine.time_scale, str(cam.get("view")), str(Input.is_action_pressed("lens_view")), str(_tree.current_scene)])
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
	_check(tut.step_id() == "repair" and Settings.glyph("interact") in tut.current_text(), "checklist 1: the card says fix the bench with %s (%s)" % [Settings.glyph("interact"), tut.current_text()])
	await _secs(0.6)
	_check(_beam_at(_w.call("bench_pos")), "checklist 1: the beam stands on the bench")
	await _walk_to(func() -> Vector3: return _w.call("bench_pos"), func() -> bool: return bool(_w.call("near_bench")), "the bench")
	var pr: String = str(_w.call("interact_prompt", _p))
	_check(Settings.glyph("interact") in pr, "checklist 1: at the bench the prompt names %s (%s)" % [Settings.glyph("interact"), pr])
	await _tap("interact")
	await _wait(func() -> bool: return tut.step_id() != "repair", 30.0)
	_check(Camp.bench_ok() and tut.step_id() == "scoop", "checklist 1: E fixed the bench")
	_check(Settings.glyph("scoop") in tut.current_text(), "checklist 2: the card says hold %s (%s)" % [Settings.glyph("scoop"), tut.current_text()])
	await _secs(0.6)
	_check(not _beam_at(_w.call("bench_pos")), "checklist 2: the beam left the bench (the card is about the junk now)")
	await _scoop_load(1.0, 60.0)
	await _wait(func() -> bool: return tut.step_id() != "scoop", 5.0)
	_check(tut.step_id() == "dump", "checklist 2: picking up 8 pieces with LMB held done")
	await _reload("checklist 3, a full chest")
	tut = _w.get("tutorial") as Tutorial
	await _secs(0.6)
	_check(_beam_at(Objectives.bin_point(_w)), "checklist 3: the beam stands on the bin (beam %s, card '%s')" % [_yard(_beam()) if _beam() is Vector3 else "none", tut.current_text()])
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
		if _ob.current().get("id", "") != "dump3":  # emptied on the way (junk by the bin): done already
			break
		var tgt: String = str(_ob.step_target(_ob.current()).get("to", ""))
		_check(tgt == "bin" and _ob.waypoint_target() is Vector3, "dump3: with a full chest the beam goes to the bin (%s)" % tgt)
		await _to_bin()
		if k < 2 and _ob.current().get("id", "") == "dump3":
			await _reload("dump3 after %d load%s" % [int(_ob.value_of(_ob.current())), "" if int(_ob.value_of(_ob.current())) == 1 else "s"])
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
	await _reload("compartment, price in hand")
	await _open_bench()
	await _click_tag("compartment_size")
	_check(GameState.level_of("compartment_size") >= 1, "compartment: a click on the price square buys Chest Size")
	await _close_bench()
	await _reload("compartment, just bought")
	await _done("compartment")


static func _scoop_size() -> void:
	if not await _on_step("scoop_size"):
		return
	await _earn(Economy.upgrade_cost("multi_lock").to_float(), false)
	await _reload("scoop_size, price in hand")
	await _open_bench()
	var ld: ListDetail = _ld()
	_check(ld != null and _sel(ld) == "multi_lock", "scoop_size: the bench opens on Scoop Size")
	if _pad:
		await _click_tag("multi_lock")
	else:
		await _click(ld.get("_d_btn") as Control)  # this time the big button in the detail panel
	_check(GameState.level_of("multi_lock") >= 1, "scoop_size: the detail panel's Install button buys it" if not _pad else "scoop_size: A on its row buys it")
	await _close_bench()
	await _reload("scoop_size, just bought")
	await _done("scoop_size")


static func _baler() -> void:
	if not await _on_step("baler"):
		return
	if GameState.get_currency("cubes").to_float() < Economy.upgrade_cost("baler").to_float():
		await _reload("baler, saving up")
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
	_check(_card(true).contains("[%s]" % Settings.glyph("cube")), "power: the card names the bale key %s (%s)" % [Settings.glyph("cube"), _card(true)])
	_check(KeyHints.items_for(true, true).any(func(it: Array) -> bool: return str(it[0]) == "cube"), "power: the full key list has 'press bale'")
	# The old habit: a chest to the bin. After the Baler the bin takes no loose junk; say why.
	if _p.compartment.fill >= _p.capacity() * 0.45:  # a chest left full from saving up: bale it first
		await _make_and_sell_bale()
	await _scoop_load(0.5, 40.0)
	await _wait(func() -> bool: return _p.compartment.pending <= 0.0, 3.0)
	print("%s note: power: chest for the bin test %.1f / %.1f" % [TAG, _p.compartment.fill, _p.capacity()])
	var bin0: Vector3 = Objectives.bin_point(_w)
	await _walk_to(func() -> Vector3: return bin0, func() -> bool: return _flat(_p.global_position - bin0).length() < 5.0, "near the bin")
	var fl0: int = _float_idx()
	_toasts.clear()
	var f0: float = _p.compartment.fill
	await _to_bin()
	await _secs(1.5)
	_check(_p.compartment.fill >= f0 - 0.01, "power: the bin takes no loose junk after the Baler")
	var said: String = ", ".join(_floats_since(fl0)) + " | " + ", ".join(_toasts)
	_check(said.contains(TranslationServer.translate("No loose trash now. Press [%s] for a bale, then put it on the scale.") % Settings.glyph("cube")), "power: at the bin with loose junk, a line says to press a bale (%s)" % said)
	for k: int in 4:
		if int(GameState.stats.get("cubes_cashed", 0)) >= 3:
			break
		await _make_and_sell_bale("power, %d bale%s sold, one carried" % [int(GameState.stats.get("cubes_cashed", 0)), "" if int(GameState.stats.get("cubes_cashed", 0)) == 1 else "s"] if k == 1 else "")
	await _done("power")


static func _tower() -> void:
	if not await _on_step("tower"):
		return
	await _earn_parts(SignalTower.next_cost())
	await _reload("tower, price in hand")
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
		await _reload("glim, saving up")
	await _earn_parts(cost)
	await _open_bench()
	_check(_sel(_ld()) == "glim", "glim: the bench opens on Repair Glim (%s)" % _sel(_ld()))
	await _click_tag("glim")
	await _close_bench()
	if _reloads:
		await _secs(1.0)
		if not bool(GameState.flags.get("glim_repaired", false)):
			await _reload("glim, mid-repair")
		else:
			print("%s note: the Glim repair is instant (no mid-repair state to save)" % TAG)
	Engine.time_scale = maxf(4.0, _ts)
	await _wait(func() -> bool: return bool(GameState.flags.get("glim_repaired", false)) and _input_on(), 60.0)
	Engine.time_scale = _ts
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
	var t0: float = _gt()
	var resets: int = 0
	var mid: bool = false
	while int(GameState.stats.get("hexes_cleaned", 0)) < 1 and _gt() - t0 < 600.0:
		if not mid and f.removed_fraction(h) > 0.4:
			mid = true
			await _reload("hex, %d%% clean" % int(f.removed_fraction(h) * 100.0))
			f = _w.get("field") as HexField
			_check(_ob.target_hex == h, "hex: after the reload the same hex is outlined (%d, was %d)" % [_ob.target_hex, h])
		if _p.compartment.fill >= _p.capacity() * 0.9:
			await _tap("cube")  # a bale, left behind
			await _secs(2.0)
		var pid: int = _liftable(f, h)
		if pid < 0 and resets < 3:  # every piece left was skipped once: try them again (other angles)
			resets += 1
			_skip.clear()
			continue
		if pid < 0:
			break
		await _scoop_piece(f, pid)
	var left: Array[String] = []
	for q: int in f.hex_pieces[h]:
		if f.piece_alive[q] == 1:
			left.append("%s %s" % [_yard(f.piece_pos[q]).split(" =")[0], "liftable" if Pace.can_lift(f, q) else "too big"])
	_check(int(GameState.stats.get("hexes_cleaned", 0)) >= 1, "hex: holding LMB on the outlined hex's junk cleans it (%d%%%s)" % [int(f.removed_fraction(h) * 100.0), "" if int(GameState.stats.get("hexes_cleaned", 0)) >= 1 else "; left: " + ", ".join(left.slice(0, 8))])
	await _done("hex")


static func _bench2() -> void:
	if not await _on_step("bench2"):
		return
	await _earn_parts(BenchTiers.next_cost())
	await _reload("bench2, price in hand")
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
	await _reload("robot, just built")
	await _done("robot")
	_check(str(_ob.current().get("id", "")) == "hex2", "robot: the next step comes (%s)" % str(_ob.current().get("id", "")))


# --- Save, quit and Continue ------------------------------------------------------------------

## Binds the walk to a (re)built world once it is up.
static func _bind(so: SliceOrbit) -> bool:
	_so = so
	_w = so.w
	for k: int in 400:
		if is_instance_valid(_w) and not bool(_w.get("building")) and _w.get("objectives") != null and _w.get("patch") != null:
			break
		await _tree.create_timer(0.5, true, false, true).timeout
	_p = _w.get("patch") as Patch
	_ob = _w.get("objectives") as Objectives
	_reach = null  # a new world: a new field
	return _p != null and _ob != null


## Quits and comes back as a player does. how "menu": Esc, the pause menu's Quit (saves, then the
## title); "close": the window closed (the game saves on the close request) and started again.
## Then Continue on the title screen, a real click.
static func _quit_and_continue(label: String, how: String) -> void:
	_release_all()
	await _frames(3)
	var pm: PauseMenu = _w.get("pause_menu") as PauseMenu
	if how == "menu":
		await _tap("pause")
		await _secs(0.6)
		if pm == null or not pm.is_open:
			how = "close"
	if how == "close":
		print("%s note: %s: no pause menu here (Esc skips); the window is closed and the game started again" % [TAG, label])
	_quit_skipped = false
	# A restart has no --fresh / dev jump; the intro plays again only where a windowed start would.
	for a: String in ["fresh", "objective", "orbit"]:
		DevHooks.args.erase(a)
	DevHooks.args["menu"] = "title"  # any dev flag makes the title skip itself: show it, as a restart does
	if bool(GameState.flags.get("intro_done", false)):
		DevHooks.args.erase("intro")
	if how == "menu":
		var quit: Button = null
		for b: Node in pm.find_children("*", "Button", true, false):
			if (b as Button).text == TranslationServer.translate("Quit") and (b as Button).is_visible_in_tree():
				quit = b
		_check(quit != null, "%s: the pause menu has Quit" % label)
		if quit == null:
			return
		await _click(quit)
	else:
		SaveManager.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)  # what the OS close does
		Loader.goto(PauseMenu.TITLE_SCENE)  # (the game starts again on its title screen)
	var menu: Node = null
	for k: int in 120:
		var sc: Node = _tree.current_scene
		if sc and sc.get("_continue") is Button and (sc.get("_continue") as Button).is_visible_in_tree():
			menu = sc
			break
		await _secs(0.5)
	_check(menu != null, "%s: back on the title, Continue is offered" % label)
	if menu == null:
		return
	await _secs(1.0)
	_next_so = null
	await _click(menu.get("_continue") as Control)
	DevHooks.args.erase("menu")
	for k: int in 600:
		if _next_so != null:
			break
		await _secs(0.5)
	_check(_next_so != null, "%s: Continue loads the game" % label)
	if _next_so == null:
		return
	await _bind(_next_so)
	_next_so = null
	await _secs(2.5)  # the card refreshes, the beam settles


## Everything a player would notice if a save lost it.
static func _snap() -> Dictionary:
	var tut: Tutorial = _w.get("tutorial") as Tutorial
	var fl: Fleet = _w.get("fleet") as Fleet
	var f: HexField = _w.get("field") as HexField
	var cur: Dictionary = _ob.current()
	return {"card": str(cur.get("id", "")), "checklist": tut.step_id() if tut and not tut.done() else "",
		"count": _progress_label(), "to": str(_ob.step_target(cur).get("to", "")) if not cur.is_empty() else "",
		"beam": _beam(), "chest": snappedf(_p.compartment.fill, 0.1), "carried": _p.carried.size(),
		"cubes": GameState.get_currency("cubes").to_float(), "parts": GameState.get_currency("parts").to_float(),
		"hex": _ob.target_hex, "clean": snappedf(f.removed_fraction(_ob.target_hex), 0.01) if _ob.target_hex >= 0 else 0.0,
		"bench_ok": Camp.bench_ok(), "tower": SignalTower.tier(), "glim": bool(GameState.flags.get("glim_repaired", false)),
		"bench_tier": BenchTiers.tier(), "robots": fl.robot_total() if fl else 0,
		"upgrades": [GameState.level_of("scoop_speed"), GameState.level_of("compartment_size"), GameState.level_of("multi_lock"), GameState.level_of("baler")],
		"sold": int(GameState.stats.get("cubes_cashed", 0)), "dumps": int(GameState.stats.get("junk_dumps", 0)), "pos": _p.global_position}


## Saves, quits to the title and continues at `label`; the step must be as it was.
static func _reload(label: String) -> void:
	if not _reloads:
		return
	await _secs(2.5)  # a step that just started picks its hex on the card's next refresh
	var a: Dictionary = _snap()
	await _quit_and_continue(label, "menu")
	if _quit_skipped:
		_check(false, "reload at %s: Esc opens no pause menu, so there is no way to quit and save here" % label)
		return
	var b: Dictionary = _snap()
	var diff: Array[String] = []
	for k: String in a:
		var x: Variant = a[k]
		var y: Variant = b[k]
		var same: bool = x == y
		if k in ["cubes", "parts"]:
			same = absf(float(x) - float(y)) < 1.0
		elif k == "chest":
			same = absf(float(x) - float(y)) < 0.35
		elif k == "beam":
			same = (x == null and y == null) or (x is Vector3 and y is Vector3 and (x as Vector3).distance_to(y) < 2.5)
		elif k == "pos":
			continue
		if not same:
			diff.append("%s %s -> %s" % [k, _short(x), _short(y)])
	var moved: float = _flat(b["pos"] - a["pos"]).length() if b["pos"] is Vector3 else -1.0
	_check(diff.is_empty() and _input_on(), "reload at %s: card '%s' %s, beam on %s, chest %.1f, carrying %d: the same after Continue%s (Lumi %.1f m from where he was)" % [
		label, str(b["card"] if b["card"] != "" else b["checklist"]), str(b["count"]), str(b["to"]), float(b["chest"]), int(b["carried"]),
		"" if diff.is_empty() else "; CHANGED: " + ", ".join(diff), moved])


static func _short(v: Variant) -> String:
	return _yard(v) if v is Vector3 else str(v)


## Quitting while WREN gives her first brief (before the card shows), then Continue.
static func _brief_reload() -> void:
	if not _reloads or _ob.revealed:
		return
	await _wait(func() -> bool: return bool(GameState.flags.get("onboard_brief", false)) or _ob.revealed, 20.0)
	if _ob.revealed:
		print("%s note: the card came before a brief could be interrupted" % TAG)
		return
	await _secs(1.0)
	await _quit_and_continue("during WREN's first brief", "menu")
	if _quit_skipped:
		return
	await _wait(func() -> bool: return _ob.revealed, 20.0)
	var tut: Tutorial = _w.get("tutorial") as Tutorial
	_check(_ob.revealed or (tut != null and not tut.done()), "quit during the brief: after Continue the card (or the checklist) is up (%s / %s)" % [_card(), tut.current_text() if tut else ""])
	_check(_input_on(), "quit during the brief: Lumi takes input after Continue")


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
	_step_f = Engine.get_physics_frames()
	await _secs(0.5)
	var tgt: Dictionary = _ob.step_target(_ob.current())
	var marked: bool = _ob.waypoint_target() is Vector3 or _ob.target_hex >= 0
	_check(_card() != "" and marked, "%s: card '%s' / '%s', marker %s" % [id, _card(), _card(true), str(tgt.get("to", ""))])
	return true


static func _done(id: String) -> void:
	await _wait(func() -> bool: return _ob.step > _index(id), 10.0)
	_check(_ob.step > _index(id), "%s: complete, the card moves on" % id)
	var mins: float = float(Engine.get_physics_frames() - _step_f) / float(Engine.physics_ticks_per_second) / 60.0
	_times.append("%s %.1f" % [id, mins])
	if _full:
		print("%s time: %s took %.1f game min (%.1f min in all)" % [TAG, id, mins, float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second) / 60.0])
	await _secs(1.8)


static func _index(id: String) -> int:
	for i: int in _ob.chain.size():
		if str((_ob.chain[i] as Dictionary).get("id", "")) == id:
			return i
	return -1


## Where the purple beam really stands now (the Waypoint's own target, not a fresh computation).
static func _beam() -> Variant:
	var wp: Waypoint = _ob.waypoint
	var r: Variant = wp.get("_raw")
	return r if r is Vector3 else wp.get("_target")


static func _beam_at(at: Variant, m: float = 2.5) -> bool:
	var b: Variant = _beam()
	return b is Vector3 and at is Vector3 and (b as Vector3).distance_to(at) < m


static func _card(why: bool = false) -> String:
	var def: Dictionary = _ob.current()
	return "" if def.is_empty() else Objectives.texts(def)[1 if why else 0]


static func _progress_label() -> String:
	return str(_ob.progress()[1])


# --- Earning ---------------------------------------------------------------------------------

## Real loads (or bales) until `cubes`; past two real rounds it's a dev top-up (said in the log).
static func _earn(cubes: float, _bales: bool) -> void:
	var rounds: int = 0
	while GameState.get_currency("cubes").to_float() < cubes and (rounds < 2 or (_full and rounds < 60)):
		rounds += 1
		if Pace.baler_unlocked():
			await _make_and_sell_bale()
		else:
			await _scoop_load(1.0, 60.0)
			await _to_bin()
	var have: float = GameState.get_currency("cubes").to_float()
	if have < cubes and _full:
		_check(false, "full grind: %.0f cubes not earned in %d rounds" % [cubes, rounds])
	if have < cubes:
		print("%s note: top-up %.0f cubes (saving up)" % [TAG, cubes - have])
		GameState.add_currency("cubes", BigNum.from_float(ceilf(cubes - have)))


static func _earn_parts(cost: Dictionary) -> void:
	var need: float = float(Currencies.fold(cost).get("parts", 0.0)) - GameState.get_currency("parts").to_float()
	var tries: int = 0
	while _full and need > 0.0 and tries < 40:  # dig what the detector finds, else bales (Lumi levels pay Parts too)
		tries += 1
		if not await _dig_part(150.0):
			await _make_and_sell_bale()
		need = float(Currencies.fold(cost).get("parts", 0.0)) - GameState.get_currency("parts").to_float()
	if need > 0.0 and _full:
		_check(false, "full grind: %.0f Parts still missing" % need)
	if need > 0.0:
		print("%s note: top-up %.0f parts (salvage and digging)" % [TAG, need])
		GameState.add_currency("parts", BigNum.from_float(ceilf(need)))
	await _earn(float(Currencies.fold(cost).get("cubes", 0.0)), true)


## The nearest buried part the detector finds: walk onto it, E digs it up.
static func _dig_part(range_m: float = 60.0) -> bool:
	var f: HexField = _w.get("field") as HexField
	var det: PartDetector = _p.get("detector") as PartDetector
	if f == null or det == null:
		return false
	var i: int = f.nearest_part(_p.global_position, range_m)
	if i < 0 or f.part_found[i] != 0:
		print("%s note: no buried part within %.0f m to dig" % [TAG, range_m])
		return false
	var at: Vector3 = f.part_pos[i]
	await _walk_to(func() -> Vector3: return at, func() -> bool: return det.can_dig(), "a buried part", 0.8)
	var parts0: float = GameState.get_currency("parts").to_float()
	await _tap("interact")
	await _wait(func() -> bool: return GameState.get_currency("parts").to_float() > parts0, 10.0)
	_check(GameState.get_currency("parts").to_float() > parts0, "parts: E on the detector's spot digs a part up (+%.0f)" % (GameState.get_currency("parts").to_float() - parts0))
	return true


static func _make_and_sell_bale(reload_label: String = "") -> void:
	await _scoop_load(0.95, 60.0)
	await _wait(func() -> bool: return _p.compartment.pending <= 0.0, 3.0)  # the last pieces fly in
	var made0: int = int(GameState.stats.get("cubes_made", 0))
	var before: Array[Node] = _tree.get_nodes_in_group("junk_cube")
	await _tap("cube")
	await _wait(func() -> bool: return int(GameState.stats.get("cubes_made", 0)) > made0, 6.0)
	_check(int(GameState.stats.get("cubes_made", 0)) > made0, "bale: RMB presses a bale")
	# [main] The bale leaves the press some frames after the count moves; a fixed second was too
	# short on a slow runner (CI: "bale none m away"). Wait for the new bale itself.
	# Cube nodes can be reused, so "a node not there before" can miss it: the loose cube nearest
	# Lumi counts too. Pressed on the scale's plate, a bale sells at once.
	var cashed_at_press: int = int(GameState.stats.get("cubes_cashed", 0))
	var fresh: Callable = func() -> JunkCube:
		for n: Node in _tree.get_nodes_in_group("junk_cube"):
			if not (n in before) and n is JunkCube and is_instance_valid(n) and not (n as JunkCube).carried:
				return n as JunkCube
		var c: JunkCube = _p.nearest_loose_cube()
		if c:
			return c
		for n: Node in _tree.get_nodes_in_group("junk_cube"):
			if n is JunkCube and is_instance_valid(n) and not (n as JunkCube).carried and _flat((n as Node3D).global_position - _p.global_position).length() < 4.0:
				return n as JunkCube
		return null
	await _wait(func() -> bool: return fresh.call() != null or int(GameState.stats.get("cubes_cashed", 0)) > cashed_at_press, 12.0)
	await _secs(1.0)
	if fresh.call() == null and int(GameState.stats.get("cubes_cashed", 0)) > cashed_at_press:
		print("%s note: the bale was pressed on the scale and sold at once" % TAG)
		return
	var bale: JunkCube = fresh.call()
	if bale and _p.nearest_loose_cube() != bale:  # pressed out behind him: turn round to it
		await _walk_to(func() -> Vector3: return bale.global_position, func() -> bool: return _p.nearest_loose_cube() == bale, "the bale", 0.9)
	var price: Dictionary = _ob._step_price()
	if not price.is_empty() and not GameState.can_afford_all(price):
		await _secs(0.6)
		_check(_ob.situation.begins_with("Need"), "%s: saving up with a bale on the ground, the card still says what is missing (%s)" % [str(_ob.current().get("id", "")), _ob.situation])
	await _tap("interact")
	if not price.is_empty() and not GameState.can_afford_all(price):
		await _secs(0.6)
		_check(_ob.situation.begins_with("Need"), "%s: carrying a bale while saving up, the card keeps the price line (%s)" % [str(_ob.current().get("id", "")), _ob.situation])
	_check(not _p.carried.is_empty(), "bale: E picks it up (bale %s m away)" % ("%.1f" % _flat(bale.global_position - _p.global_position).length() if bale else "none"))
	if reload_label != "" and not _p.carried.is_empty():
		await _reload(reload_label)
		if _p.carried.is_empty():  # (a FAIL in _reload already) pick the bale up again if it lies about
			var c: JunkCube = _p.nearest_loose_cube()
			if c:
				await _tap("interact")
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
	var t0: float = _gt()
	while _p.compartment.fill < _p.capacity() * frac * 0.98 and _gt() - t0 < max_s:
		var pid: int = _liftable(f, -1)
		if pid < 0:
			_check(false, "nothing liftable near Lumi")
			return
		await _scoop_piece(f, pid)
	_check(_p.compartment.fill >= _p.capacity() * frac * 0.9, "scoop: LMB held on the junk fills the chest (%.1f / %.1f, Lumi at %s)" % [_p.compartment.fill, _p.capacity(), _yard(_p.global_position)])


static var _unstick: bool = false
static var _unstick_to: Vector3


static func _scoop_piece(f: HexField, pid: int) -> void:
	var at: Vector3 = f.piece_pos[pid]
	await _walk_to(func() -> Vector3: return at, func() -> bool: return _p.global_position.distance_to(at) < 1.3, "a piece", 1.0, 8.0, true)
	if _unstick:  # wedged (the lakeside by the bin bay): go back the way he came, as a player turns round
		_unstick = false
		var c: Vector3 = _unstick_to
		await _walk_to(func() -> Vector3: return c, func() -> bool: return _flat(c - _p.global_position).length() < 1.5, "where he came from (backing out)", 0.0, 30.0)
		return
	_hold_action("scoop", true)
	var t0: float = _gt()
	while f.piece_alive[pid] == 1 and _gt() - t0 < 3.0 and _p.compartment.can_accept(_p.capacity()):
		await _frames(3)
	_hold_action("scoop", false)
	if f.piece_alive[pid] == 1 and _p.compartment.can_accept(_p.capacity()):
		_skip[pid] = true  # bitten or out of reach: the next one
	await _frames(2)


static var _skip: Dictionary = {}
static var _stopped: bool = false


## The nearest liftable piece (in hex `h` if >= 0) that Lumi can see from where he stands (a
## player goes for the junk in view, not the piece behind the bin's wall).
static var _reach: TargetReach


static func _liftable(f: HexField, h: int) -> int:
	if _reach == null:
		_reach = TargetReach.for_world(_w)
	var cand: Array = []
	var pool: PackedInt32Array = f.hex_pieces[h] if h >= 0 else f.pieces_within(_p.global_position, 30.0)
	for pid: int in pool:
		if f.piece_alive[pid] != 1 or _skip.has(pid) or f.locked.has(f.piece_hex[pid]) or not Pace.can_lift(f, pid):
			continue
		if f.is_water(f.piece_hex[pid]) or bool(_p.call("_water_at", f.piece_pos[pid])):  # floating junk: for later (the lake by the bin)
			continue
		if _reach and _reach.why_ground(f.piece_pos[pid].normalized()) == "water":  # in the lake's water though its hex is land (by the bin bay)
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
	await _tap("open_upgrades")  # Tab on the keyboard, Y on a pad
	await _secs(0.6)
	_check(not scr.is_open and _input_on(), "bench: %s closes it and Lumi moves again" % Settings.glyph("open_upgrades"))


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
	if _pad:
		await _pad_accept(row)
		return
	await _click((row.get_meta("parts") as Array)[3] as Control)


## On a pad: the D-pad moves the bench's focus to `row` (as a player does), then A acts on it.
static func _pad_accept(row: Button) -> void:
	var vp: Viewport = row.get_viewport()
	for dir: String in ["ui_down", "ui_up"]:
		for k: int in 14:
			if vp.gui_get_focus_owner() == row:
				break
			await _tap_ui(dir)
	_check(vp.gui_get_focus_owner() == row, "pad: the D-pad reaches the row (focus on %s)" % str(vp.gui_get_focus_owner()))
	await _tap_ui("ui_accept")
	await _secs(0.3)


static func _tap_ui(action: String) -> void:
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton:
			for down: bool in [true, false]:
				var e: InputEventJoypadButton = ev.duplicate()
				e.device = 0
				e.pressed = down
				Input.parse_input_event(e)
				Input.flush_buffered_events()
				await _frames(2)
			await _frames(2)
			return
	_check(false, "pad: no joypad button on %s" % action)


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
	# coordinates (the GUI's real picking, gui_input and button press from there on). The pointer
	# is aimed again until it is over the control: the bench's hologram may still be unfolding.
	var local: bool = vp.gui_get_hovered_control() == null
	var lp: Vector2 = Vector2.ZERO
	var hov: Control = null
	var t0: float = _gt()
	while true:
		pos = c.get_screen_transform() * (c.size * 0.5)
		lp = c.get_global_transform_with_canvas() * (c.size * 0.5)
		if local:
			var lm := InputEventMouseMotion.new()
			lm.position = lp
			lm.global_position = lp
			vp.push_input(lm, true)
		else:
			var gm := InputEventMouseMotion.new()
			gm.position = pos
			gm.global_position = pos
			Input.parse_input_event(gm)
		await _frames(2)
		hov = vp.gui_get_hovered_control()
		if (hov != null and (hov == c or c.is_ancestor_of(hov))) or _gt() - t0 > 3.0:
			break
		await _frames(4)
		if hov == null and not local:
			local = true
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
	var t0: float = _gt()
	var last: Vector3 = _p.global_position
	var still: float = 0.0
	var side: float = 0.0
	var side_dir: int = 1
	var tries: int = 0
	var detour: Vector3 = Vector3.ZERO
	var best_d: float = INF
	var from_pos: Vector3 = _p.global_position
	while not bool(arrived.call()):
		if _gt() - t0 > max_s:
			_release_all()
			var at: Vector3 = to.call()
			if what == "a piece":  # wedged somewhere (across the bin bay's shore): a player goes elsewhere
				print("%s note: a piece at %s out of the walker's way, took junk elsewhere" % [TAG, _yard(at)])
				var f: HexField = _w.get("field") as HexField
				for pid: int in f.pieces_within(at, 5.0):
					_skip[pid] = true
				_unstick = true
				_unstick_to = from_pos
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
		await _frames(3)
		# Stuck is no progress toward the target (pushing on a thin post he jitters a few mm a tick).
		var dist: float = _flat(to.call() - _p.global_position).length()
		if dist < best_d - 0.3:
			best_d = dist
			still = 0.0
		else:
			still += 0.05
		last = _p.global_position
		if still > 1.0 and side <= 0.0:
			tries += 1
			side = minf(0.6 + 0.3 * tries, 1.5)  # a bit longer each time (capped), alternating sides
			side_dir = -side_dir
			still = 0.0
	_release_all()
	await _frames(3)


static func _steer(dir: Vector3, ahead: float, prefer: int) -> Vector3:
	var space: PhysicsDirectSpaceState3D = _p.get_world_3d().direct_space_state
	var u: Vector3 = _p.global_position.normalized()
	var in_water: bool = bool(_p.call("_water_at", _p.global_position))
	for k: int in [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5]:
		var dd: Vector3 = dir.rotated(u, deg_to_rad(25.0) * k * prefer)
		# On land he stops at the shore (water ahead is a wall); in the water he can always wade out.
		var free: bool = in_water or not bool(_p.call("_water_at", _p.global_position + dd * maxf(ahead, 0.9)))
		for h: float in ([0.35, 0.9] if free else []):
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
		var pad: bool = ev is InputEventJoypadButton or ev is InputEventJoypadMotion
		if pad == _pad:
			var e: InputEvent = ev.duplicate()
			if pad:
				e.device = 0  # (keyboard and mouse events keep the map's own device)
			return e
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
	elif ev is InputEventJoypadMotion:  # a stick or trigger: full tilt, or back to rest
		(ev as InputEventJoypadMotion).axis_value = (ev as InputEventJoypadMotion).axis_value if down else 0.0
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


static func _hold_action(action: String, down: bool) -> void:
	if bool(_keys.get(action, false)) == down:
		return
	_keys[action] = down
	if _pad and action.begins_with("move_"):  # one stick: both directions of an axis share it
		var x: float = (1.0 if bool(_keys.get("move_right", false)) else 0.0) - (1.0 if bool(_keys.get("move_left", false)) else 0.0)
		var y: float = (1.0 if bool(_keys.get("move_back", false)) else 0.0) - (1.0 if bool(_keys.get("move_forward", false)) else 0.0)
		for ax: Array in [[JOY_AXIS_LEFT_X, x], [JOY_AXIS_LEFT_Y, y]]:
			var m := InputEventJoypadMotion.new()
			m.device = 0
			m.axis = ax[0]
			m.axis_value = ax[1]
			Input.parse_input_event(m)
		Input.flush_buffered_events()
		return
	_send(action, down)


static func _release_all() -> void:
	for a: String in _keys.keys():
		_hold_action(a, false)


static func _tap(action: String) -> void:
	await _tree.physics_frame
	_send(action, true)
	await _frames(6)
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
		await _frames(6)
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
	var t0: float = _gt()
	while not bool(cond.call()) and _gt() - t0 < secs:
		await _frames(6)


## Game seconds waited by physics frames (a slow or busy machine runs the same game time; a
## wall-clock wait gave it fewer frames, and the walk lost a CI run that way).
static func _secs(s: float) -> void:
	await _frames(maxi(1, int(ceil(s * float(Engine.physics_ticks_per_second)))))


## Game seconds since start (physics frames).
static func _gt() -> float:
	return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)


static func _frames(n: int) -> void:
	for k: int in n:
		await _tree.physics_frame
