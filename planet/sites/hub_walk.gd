class_name HubWalk
extends RefCounted
## [v6hubs] Dev: --hub-walkthrough[=T]. The six-base walkthrough by numbers: T s after start (default
## 3), flies the rocket to each main-path hub of the planet's data in order (data/planets.json
## hubs[], `order`), waits for its town, and checks at each one:
##   town     the town built with the landmark the data names (StreetDressing.landmark_info kind)
##   reach    the landmark's foot can be reached on foot (TargetReach.reach, colliders loaded)
##   asleep   the card shows the hub's first step, and the landmark's prompt says it is asleep
##   prompt   with the chain done (hexes cleaned by data, outposts counted) and the price given,
##            Lumi standing on open ground by the landmark gets the wake prompt from Interactables
##   wake     using it (the real Interactables path) wakes the hub: flag hub_woken_<site>, the
##            rocket piece flag, the data's gift (cubes / parts / seeds / research / design)
##   bench    the field bench stands on the ground by the pad, the beacon is lit, the HUD counts it
##   errors   no engine or script error was logged while at the hub
## --hub-walk-hubs=N stops after the first N hubs.
## --hub-walk-fly[=N]: the first N hubs (default 1) fly the real hop (no skip): prints the flight's
## length and frames, and fails on a frame over --hub-walk-max-ms (default 250, main-thread CPU) in
## the first 6 s on the ground; with --hitch, systems/hitch.gd also prints what ran in each long frame.
## Prints a [hubwalk] line per hub and "[hubwalk] PASS|FAIL"; quits 1 on any failure.
## The rocket tier is raised for the run (--rocket-tier, unless given) so no wake hits the limit.
## Run: godot --headless --path . -- --fresh --orbit --no-intro --hop-skip --hub-walkthrough

const WAIT_TOWN_S: float = 120.0
const REACH_M: float = HubPurpose.LANDMARK_REACH_M
const LONG_MS: int = 100
const ARRIVAL_S: float = 6.0


## Counts the engine's errors (script errors, push_error, ERR_FAIL...) while it is added.
class ErrCount extends Logger:
	var n: int = 0
	var first: Array[String] = []
	var _m := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_m.lock()
		n += 1
		if first.size() < 6:
			first.append("%s:%d %s %s" % [file.get_file(), line, function, rationale if rationale != "" else code])
		_m.unlock()


## Main-thread CPU time of every frame while it is in the tree (BuildBudget.cpu_us, as --hitch
## counts it: wall time is mostly other processes on a busy box), for the long-frame check.
class FrameWatch extends Node:
	var last_us: int = 0
	var frames: PackedInt32Array = []  # ms per frame, since mark()

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		last_us = _now()

	func _now() -> int:
		var c: int = BuildBudget.cpu_us()
		return c if c > 0 else Time.get_ticks_usec()

	func _process(_d: float) -> void:
		var now: int = _now()
		frames.append(int((now - last_us) / 1000))
		last_us = now

	func mark() -> void:
		frames = PackedInt32Array()
		last_us = _now()

	## [worst ms, frames over `long_ms`, frames]
	func stats(long_ms: int) -> Array:
		var worst: int = 0
		var n: int = 0
		for f: int in frames:
			worst = maxi(worst, f)
			n += 1 if f >= long_ms else 0
		return [worst, n, frames.size()]


static func run_dev(hp: HubPurpose) -> void:
	var tree: SceneTree = hp.get_tree()
	if not DevHooks.has("rocket-tier"):
		DevHooks.args["rocket-tier"] = str(RocketTiers.max_tier())
	await tree.create_timer(DevHooks.get_f("hub-walkthrough", 3.0)).timeout
	var errs := ErrCount.new()
	OS.add_logger(errs)
	var fw := FrameWatch.new()
	fw.name = "HubWalkFrames"
	hp.add_child(fw)
	var skip_given: bool = DevHooks.has("hop-skip")
	var order: Array = HubPlan.entries(hp.planet).duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("order", 0)) < int(b.get("order", 0)))
	var fails: int = 0
	var t_all: int = Time.get_ticks_msec()
	var done: int = 0
	for e: Dictionary in order:
		var i: int = int(e["site"])
		if HubPlan.is_home(hp.planet, i) or not HubPlan.is_main(hp.planet, i) or i >= hp.sm.sites.size():
			continue
		if DevHooks.has("hub-walk-hubs") and done >= int(DevHooks.get_f("hub-walk-hubs", 5.0)):
			break
		# --hub-walk-fly[=N]: the first N hubs (default 1) fly the real hop, not the skip.
		var fly: bool = DevHooks.has("hub-walk-fly") and done < int(DevHooks.get_f("hub-walk-fly", 1.0))
		if fly:
			DevHooks.args.erase("hop-skip")
		elif skip_given or DevHooks.has("hub-walk-fly"):
			DevHooks.args["hop-skip"] = "1"
		var bad: Array[String] = await _visit(hp, e, errs, fw if fly else null)
		done += 1
		fails += 1 if not bad.is_empty() else 0
		if not hp.is_inside_tree():
			break
	OS.remove_logger(errs)
	var all_up: bool = HubPlan.restored_main(hp.planet) >= HubPlan.main_total(hp.planet)
	if not all_up and not DevHooks.has("hub-walk-hubs"):
		fails += 1
	print("[hubwalk] %d hubs visited, bases %d/%d, card '%s' (%d s)" % [done, HubPlan.restored_main(hp.planet), HubPlan.main_total(hp.planet),
		hp.card_text, (Time.get_ticks_msec() - t_all) / 1000])
	print("[hubwalk] %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	# The site manager's footprint probe and anchor fix of the last town run on after it is built;
	# quitting inside them leaks their queries at exit.
	var w8: float = 0.0
	while hp.site >= 0 and not hp.sm.probed.has(hp.site) and w8 < 60.0:
		await tree.create_timer(0.5).timeout
		w8 += 0.5
	await tree.create_timer(1.0).timeout
	tree.quit(0 if fails == 0 else 1)


## One hub: fly there, check it, wake it. Returns what failed ([] when all is well).
static func _visit(hp: HubPurpose, e: Dictionary, errs: ErrCount, fw: FrameWatch = null) -> Array[String]:
	var tree: SceneTree = hp.get_tree()
	var i: int = int(e["site"])
	var nm: String = str(e.get("id", i))
	var bad: Array[String] = []
	var notes: PackedStringArray = []
	var err0: int = errs.n
	var t0: int = Time.get_ticks_msec()
	# Fly.
	if fw:
		fw.mark()
	var t_fly: int = Time.get_ticks_msec()
	var ok: bool = await hp.sites.hop_to(i)
	if not ok:
		bad.append("hop refused")
	if fw:
		# The real flight: its length, then the frames of the first seconds on the ground.
		var fl: Array = fw.stats(LONG_MS)
		notes.append("flew %.1f s (worst frame %d ms cpu, %d of %d over %d ms)" % [(Time.get_ticks_msec() - t_fly) / 1000.0, fl[0], fl[1], fl[2], LONG_MS])
		fw.mark()
		await tree.create_timer(ARRIVAL_S).timeout
		var ar: Array = fw.stats(LONG_MS)
		var max_ms: int = int(DevHooks.get_f("hub-walk-max-ms", 250.0))
		notes.append("arrival %.0f s: worst frame %d ms cpu, %d of %d over %d ms" % [ARRIVAL_S, ar[0], ar[1], ar[2], LONG_MS])
		if int(ar[0]) > max_ms:
			bad.append("hitch: a %d ms frame in the first %.0f s on the ground (limit %d ms; add --hitch for what ran)" % [ar[0], ARRIVAL_S, max_ms])
	# The arrival title: name, town, and why we came.
	if hp.title_reason == "":
		bad.append("arrival: no reason line under the title")
	else:
		notes.append("why '%s'" % hp.title_reason)
	# The town and its landmark.
	var lm: Dictionary = {}
	var waited: float = 0.0
	while waited < WAIT_TOWN_S:
		lm = hp.landmark(i) if hp.site == i else {}
		if not lm.is_empty() and _built_kind(hp, i) != "":
			break
		await tree.create_timer(0.5).timeout
		waited += 0.5
	for k: int in 4:
		await tree.physics_frame
	var want_kind: String = HubPlan.landmark_kind(hp.planet, i)
	var got_kind: String = _built_kind(hp, i)
	notes.append("town %s in %.0f s" % [hp.town_name(i), waited])
	if lm.is_empty() or got_kind == "":
		bad.append("town: no landmark after %.0f s (site %d, at site %d)" % [waited, i, hp.site])
		_report(nm, i, bad, notes, errs, err0, t0)
		return bad
	if want_kind != "" and got_kind != want_kind:
		bad.append("town: landmark is %s, data says %s" % [got_kind, want_kind])
	# Reach.
	var foot: Vector3 = lm["pos"]
	var tr_: TargetReach = TargetReach.for_world(hp.so.w, true)
	var why: String = tr_.reach(foot) if tr_ else "no TargetReach"
	var open_at: Vector3 = tr_.open_spot(foot) if tr_ else foot
	var open_d: float = _ground_d(open_at, foot)
	notes.append("landmark %.0f m from the pad, open ground %.1f m from its foot" % [_ground_d(foot, hp.sm.pad_xf(i).origin), open_d])
	# The foot itself may stand in the landmark's own collider (a crane's leg, a stack): fine while
	# open ground that leads out lies inside the prompt's radius.
	if why != "":
		notes.append("foot %s" % why)
		if not (tr_ and tr_.escapes(open_at.normalized())) or open_d < 0.01:
			bad.append("reach: landmark cut off (%s), no open ground near it" % why)
	if open_d > REACH_M - 1.0:
		bad.append("reach: nearest open ground %.1f m from the foot, prompt radius %.0f m" % [open_d, REACH_M])
	# Asleep.
	hp._refresh()
	var card0: String = hp.card_text
	var prompt0: String = hp.landmark_prompt()
	if card0 == "" or not card0.begins_with(HubPlan.hub_name(hp.planet, i)):
		bad.append("asleep: card '%s'" % card0)
	if prompt0 == "" or hp.can_wake(i) != (HubPlan.chain(hp.planet, i).size() <= 1):
		bad.append("asleep: prompt '%s'" % prompt0)
	# The chain, by data; the price.
	_fill_chain(hp, i)
	GameState.add_all(HubPlan.wake_cost(hp.planet))
	hp._refresh()
	if not hp.can_wake(i):
		bad.append("chain: still on step '%s' after the chain was filled" % str(hp.current_step(i).get("do", "")))
	if HubPlan.at_limit(hp.planet):
		bad.append("limit: rocket tier %d allows %d bases" % [RocketTiers.tier(), HubPlan.rocket_limit()])
	# Lumi by the landmark: the prompt the player sees.
	var patch: Node3D = hp.so.w.get("patch")
	var ia: Variant = hp.so.w.get("interactables")
	var stand: Vector3 = open_at + open_at.normalized() * 0.3
	patch.global_position = stand
	for k: int in 3:
		await tree.physics_frame
	await tree.process_frame
	var seen: String = (ia as Interactables).prompt(patch.global_position) if ia is Interactables else ""
	var want_prompt: String = hp.landmark_prompt()
	if seen != want_prompt or not want_prompt.begins_with("E"):
		bad.append("prompt: Lumi by the landmark sees '%s', the landmark says '%s'" % [seen, want_prompt])
	# Wake through the real interact path.
	var before: Dictionary = _stock()
	var cost: Dictionary = HubPlan.wake_cost(hp.planet)
	var used: bool = (ia as Interactables).try_use(patch.global_position) if ia is Interactables and seen == want_prompt else false
	if not used or not HubPlan.woken(i):
		hp.use_landmark()  # go on with the walk; the failure is noted
		bad.append("wake: E by the landmark did not wake it (used %s)" % used)
	if not HubPlan.woken(i):
		bad.append("wake: not woken")
	if not bool(GameState.flags.get("hub_woken_%d" % i, false)):
		bad.append("wake: no flag hub_woken_%d" % i)
	var piece: Variant = e.get("piece", null)
	if piece is Dictionary and not bool(GameState.flags.get("rocket_piece_" + str(piece["id"]), false)):
		bad.append("reward: no rocket piece %s" % str(piece["id"]))
	var gift: Dictionary = e.get("gift", {}) if e.get("gift", {}) is Dictionary else {}
	var after: Dictionary = _stock()
	var got: PackedStringArray = []
	for c: String in ["cubes", "parts", "seeds"]:
		var want: float = float(gift.get(c, 0.0)) - float(cost.get(c, 0.0))
		var d: float = float(after[c]) - float(before[c])
		if absf(d - want) > maxf(1.0, absf(want) * 0.001):
			bad.append("reward: %s %+.0f, expected %+.0f" % [c, d, want])
		elif float(gift.get(c, 0.0)) > 0.0:
			got.append("+%d %s" % [int(gift[c]), c])
	if str(gift.get("research", "")) != "":
		if not Research.has(str(gift["research"])):
			bad.append("reward: research %s not given" % gift["research"])
		else:
			got.append("research " + str(gift["research"]))
	if str(gift.get("design", "")) != "":
		if not Designs.is_unlocked(str(gift["design"])):
			bad.append("reward: design %s not unlocked" % gift["design"])
		else:
			got.append("design " + str(gift["design"]))
	if piece is Dictionary:
		got.append("piece " + str(piece["id"]))
	notes.append("gave " + ", ".join(got))
	# The bench, the beacon, the HUD (after a poll).
	await tree.create_timer(HubPurpose.POLL_S * 2.5).timeout
	var bp: Variant = hp.bench_point()
	if bp == null:
		bad.append("bench: no field bench")
	else:
		var g: Vector3 = hp.sm.terrain.ground((bp as Vector3).normalized()) if hp.sm.terrain else bp
		var off: float = (bp as Vector3).length() - g.length()
		if absf(off) > 0.4:
			bad.append("bench: %.2f m off the ground" % off)
		var pd: float = _ground_d(bp, hp.sm.pad_xf(i).origin)
		if pd > 14.0:
			bad.append("bench: %.0f m from the pad" % pd)
	var bc: Variant = hp.get("_beacon")
	if not (bc is Node3D and (bc as Node3D).visible):
		bad.append("beacon: not lit")
	var hud: Dictionary = hp.hud_lines()
	var want_hud: String = "%d/%d" % [HubPlan.restored_main(hp.planet), HubPlan.main_total(hp.planet)]
	if not str(hud.get("planet", "")).contains(want_hud):
		bad.append("hud: '%s' (want %s)" % [str(hud.get("planet", "")), want_hud])
	notes.append("hud '%s', card '%s'" % [str(hud.get("planet", "")), hp.card_text])
	_report(nm, i, bad, notes, errs, err0, t0)
	return bad


## The landmark kind the built town really has ("" while it builds).
static func _built_kind(hp: HubPurpose, i: int) -> String:
	var p: SitePrefab = hp.sm.prefab(i)
	if p == null or not p.is_built or p.content == null:
		return ""
	for c: Node in p.content.get_children():
		var dr: Variant = c.get("dressing")
		if dr is StreetDressing and (dr as StreetDressing).is_inside_tree():
			return str((dr as StreetDressing).landmark_info()["kind"])
	return ""


## Does hub i's chain by data: cleans the hexes it asks for, counts its outposts as repaired.
static func _fill_chain(hp: HubPurpose, i: int) -> void:
	var need: int = 0
	for s: Dictionary in HubPlan.chain(hp.planet, i):
		match str(s["do"]):
			"clean":
				need += int(s.get("hexes", 8))
			"outposts":
				HubPlan.state(i)["outposts"] = int(s.get("count", 1))
	need -= hp.cleaned_here(i)
	for c: int in hp.sm.regions[i]:
		if need <= 0:
			break
		if hp.sm.cells.is_dirty(c) and hp.sm.cells.state[c] != 5 and (hp.sm.cells.flags[c] & SphereCells.F_HUB) == 0:
			hp.sm.cells.set_junk(c, 0.0)
			hp.sm.cells.set_state(c, 1)
			need -= 1


static func _stock() -> Dictionary:
	var out: Dictionary = {}
	for c: String in ["cubes", "parts", "seeds"]:
		out[c] = GameState.get_currency(c).to_float()
	return out


static func _ground_d(a: Vector3, b: Vector3) -> float:
	var u: Vector3 = a.normalized()
	var dv: Vector3 = b - a
	return (dv - u * dv.dot(u)).length()


static func _report(nm: String, i: int, bad: Array[String], notes: PackedStringArray, errs: ErrCount, err0: int, t0: int) -> void:
	var ne: int = errs.n - err0
	if ne > 0:
		bad.append("errors: %d logged (%s)" % [ne, "; ".join(errs.first)])
	print("[hubwalk] %s site %d: %s in %d s | %s%s" % [nm, i, "ok" if bad.is_empty() else "FAIL", (Time.get_ticks_msec() - t0) / 1000,
		"; ".join(notes), "" if bad.is_empty() else " | " + "; ".join(bad)])
