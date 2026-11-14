class_name WalkGoals
extends RefCounted
## [v9d] Owner, 2026-11-13: "I need to make sure all goals and all that work". Two halves:
##   1. GoalAudit on the real globe: every goal and achievement left on Verdance reads something the
##      round game writes, with a target Verdance can reach (eggs placed, hubs, Recycler, Radio...).
##   2. One goal of each kind a player does by hand, played with real key and mouse events (as
##      tools/seed_walk.gd): the counter the goal reads must move when the player does the thing.
##        stat   "Pick up 15 pieces of trash"  hold the scoop button at junk     -> junk_scooped
##        stat   "Empty your chest in the bin" walk (move key) into the bin      -> junk_dumps
##        earned "Earn 1,000 cubes"            the bin pays                      -> cubes_earned_total
##        upgrade "Chest Size level 3"         E at the bench, click Buy on the card -> level, upgrades_bought
##        stat   "Pet a stray cat"             E by a cat (when one is about)    -> cats_petted
##      (flag "Find the seed tin" and the first planting: tools/seed_walk.gd; robots, base levels,
##      stations and the rocket: the story walks.)
## --walk-goals[=S] (after S s, default 8): prints [walk-goals] lines, exit 1 on a failure.
## tools/check_exit.sh runs it with the tests.

static var _fails: Array[String] = []
static var _toasts: Array[String] = []
static var _dumps_before_scoop: float = 0.0


static func run_dev(so: SliceOrbit) -> void:
	var tree: SceneTree = so.w.get_tree()
	await tree.create_timer(DevHooks.get_f("walk-goals", 8.0)).timeout
	var w: Node = so.w
	for k: int in 240:
		if not bool(w.get("building")) and w.get("goals") != null and w.get("patch") != null:
			break
		await tree.create_timer(0.5).timeout
	var p: Patch = w.get("patch") as Patch
	var gl: Goals = w.get("goals") as Goals
	if p == null or gl == null:
		print("[walk-goals] FAIL: no Lumi / goals")
		tree.quit(1)
		return
	EventBus.toast.connect(func(t: String, _k: String) -> void: _toasts.append(t))
	# 1. The audit, with the globe's numbers.
	var fails: Array[String] = GoalAudit.audit(w)
	for f: String in fails:
		_check(false, "audit: " + f)
	print("[walk-goals] audit: %d goals, %d achievements shown, %d eggs placed over %d hubs, %d research projects open" % [
		GoalAudit.verdance_goals().size(), Achievements.shown_defs().size(), GoalAudit.reachable_eggs(w).size(),
		GoalAudit._hub_count(w), GoalAudit.researchable().size()])
	_check(fails.is_empty(), "every goal and achievement left on Verdance can complete")
	# The state the first goals come up in: the brief read, the tutorial done (the card's goals).
	GameState.flags["onboard_brief"] = true
	GameState.flags["tutorial_step"] = Tutorial.STEPS.size()
	await _scoop(so, w, p, gl)
	await _dump(so, w, p, gl)
	await _upgrade(so, w, p, gl)
	await _pet(so, w, p)
	_decor_text(w)
	print("[walk-goals] %s" % ("PASS" if _fails.is_empty() else "FAIL: " + "; ".join(_fails)))
	tree.quit(0 if _fails.is_empty() else 1)


static func _goal(gl: Goals, id: String) -> int:
	for i: int in gl.chain.size():
		if str(gl.chain[i]["id"]) == id:
			return i
	return -1


## stat: hold the scoop button facing junk next to Lumi.
static func _scoop(so: SliceOrbit, w: Node, p: Patch, gl: Goals, quiet: bool = false) -> void:
	var tree: SceneTree = w.get_tree()
	var f: HexField = w.field
	var best: int = -1
	var bd: float = INF
	var bin_at: Vector3 = (w.depot as Node3D).global_position
	for pid: int in f.piece_pos.size():
		if f.piece_alive[pid] == 0 or not Pace.can_lift(f, pid):
			continue
		if quiet and f.piece_pos[pid].distance_to(bin_at) < 14.0:
			continue  # away from the bin, so the chest stays full
		var d: float = f.piece_pos[pid].distance_to(p.global_position)
		if d < bd:
			bd = d
			best = pid
	if best < 0:
		_check(false, "stat: junk to scoop near Lumi")
		return
	var jp: Vector3 = f.piece_pos[best]
	var back: Vector3 = (p.global_position - jp)
	back = (back - jp.normalized() * back.dot(jp.normalized())).normalized()
	_stand(so, p, jp + back * 1.4, jp)
	await _frames(tree, 6)
	if p.tool != Patch.Tool.SCOOP:
		await _tap(tree, "tool_scoop")
	var gi: int = _goal(gl, "scoop_15")
	var v0: float = gl.value_of(gi) if gi >= 0 else 0.0
	var s0: float = float(GameState.stats.get("junk_scooped", 0.0))
	_dumps_before_scoop = float(GameState.stats.get("junk_dumps", 0.0))
	await _hold(tree, "scoop", 2.5)
	await _frames(tree, 20)
	if quiet:
		return
	var s1: float = float(GameState.stats.get("junk_scooped", 0.0))
	_check(s1 > s0, "stat: holding the scoop button at junk counts junk_scooped (%d -> %d)" % [int(s0), int(s1)])
	_check(gi < 0 or gl.value_of(gi) > v0, "stat: \"Pick up 15 pieces of trash\" moves (%.0f -> %.0f)" % [v0, gl.value_of(gi) if gi >= 0 else -1.0])


## stat + earned: walk into the trash bin with junk in the chest (the move key held).
static func _dump(so: SliceOrbit, w: Node, p: Patch, gl: Goals) -> void:
	var tree: SceneTree = w.get_tree()
	if p.compartment.is_empty() and float(GameState.stats.get("junk_dumps", 0.0)) > _dumps_before_scoop:
		print("[walk-goals] note: the junk by the pad is in the bin's reach: the chest went in while scooping")
	for k: int in 8:  # fill the chest again away from the bin (hold the button at junk)
		if not p.compartment.is_empty():
			break
		await _scoop(so, w, p, gl, true)
	if p.compartment.is_empty():
		_check(false, "stat: junk in the chest for the bin")
		return
	var bin: Node3D = Pace.trash_bin(tree, (w.depot as Node3D).global_position)
	var at: Vector3 = bin.global_position if bin else (w.depot as Node3D).global_position
	var away: Vector3 = so.yard_point("pod") - at
	away = (away - at.normalized() * away.dot(at.normalized())).normalized()
	_stand(so, p, at + away * 4.0, at)
	await _frames(tree, 6)
	var d0: float = float(GameState.stats.get("junk_dumps", 0.0))
	var e0: float = BigNum.from_serialized(GameState.stats.get("cubes_earned_total", [0.0, 0])).to_float()
	var gi: int = _goal(gl, "earn_1k")
	var v0: float = gl.value_of(gi) if gi >= 0 else 0.0
	_send("move_forward", true)
	for k: int in 40:
		await tree.create_timer(0.1).timeout
		if float(GameState.stats.get("junk_dumps", 0.0)) > d0:
			break
	_send("move_forward", false)
	await _frames(tree, 4)
	print("[walk-goals] dump: chest %.2f, Lumi %.1f m from the bin, try_dump radius walk done" % [p.compartment.fill, p.global_position.distance_to(at)])
	var e1: float = BigNum.from_serialized(GameState.stats.get("cubes_earned_total", [0.0, 0])).to_float()
	_check(float(GameState.stats.get("junk_dumps", 0.0)) > d0, "stat: walking into the bin counts junk_dumps (\"Empty your chest in the bin\")")
	_check(e1 > e0, "earned: the bin's cubes count toward lifetime cubes (%.0f -> %.0f)" % [e0, e1])
	_check(gi < 0 or gl.value_of(gi) > v0, "earned: \"Earn 1,000 cubes\" moves")


## upgrade: E at the bench opens it; a click on the Chest Size card's Buy button buys a level.
static func _upgrade(so: SliceOrbit, w: Node, p: Patch, gl: Goals) -> void:
	var tree: SceneTree = w.get_tree()
	var id: String = "compartment_size"
	var cost: float = Economy.upgrade_cost(id).to_float()
	var have: float = GameState.get_currency("cubes").to_float()
	if have < cost:  # the cubes a player has by the chest step (the bin pays them): topped up, said
		print("[walk-goals] note: %.0f cubes topped up to the Chest Size price %.0f" % [have, cost])
		GameState.add_currency("cubes", BigNum.from_float(cost - have + 1.0))
	var bp: Vector3 = so.bench_position()
	var away: Vector3 = so.yard_point("pod") - bp
	away = (away - bp.normalized() * away.dot(bp.normalized())).normalized()
	_stand(so, p, bp + away * 1.6, bp)
	await _frames(tree, 6)
	var up: UpgradesScreen = w.get("upgrades") as UpgradesScreen
	for k: int in 3:  # the first E may repair the broken bench
		if _open(up):
			break
		await _tap(tree, "interact")
		await tree.create_timer(1.5).timeout
	_check(_open(up), "upgrade: E at the bench opens it")
	if not _open(up):
		return
	await _frames(tree, 4)
	# The list row (a click selects it), then the detail panel's Install / Buy button.
	var ld: ListDetail = null
	for n: Node in up.find_children("*", "", true, false):
		if n is ListDetail and (n as Control).is_visible_in_tree():
			ld = n
	_check(ld != null, "upgrade: the bench shows the upgrade list")
	if ld == null:
		return
	var row: Button = (ld.get("_rows") as Dictionary).get(id) as Button
	_check(row != null and row.is_visible_in_tree(), "upgrade: Chest Size has a row in the list")
	var lv0: int = GameState.level_of(id)
	var b0: float = float(GameState.stats.get("upgrades_bought", 0.0))
	if row:  # the row's middle: its name and price tag (a click on the tag buys, ui/list_detail.gd)
		await _click(tree, row)
		await _frames(tree, 6)
	_check(str(ld.get("_sel")) == id, "upgrade: a click on the row selects Chest Size (%s)" % str(ld.get("_sel")))
	if GameState.level_of(id) == lv0:  # not the tag: the detail panel's button
		var btn: Button = ld.get("_d_btn") as Button
		_check(btn != null and btn.is_visible_in_tree() and not btn.disabled, "upgrade: the detail panel's button can be clicked (%s)" % (btn.text if btn else "none"))
		if btn:
			await _click(tree, btn)
		await _frames(tree, 6)
	_check(GameState.level_of(id) > lv0, "upgrade: a click buys Chest Size (%d -> %d)" % [lv0, GameState.level_of(id)])
	_check(float(GameState.stats.get("upgrades_bought", 0.0)) > b0, "upgrade: upgrades_bought counts it (\"Buy an upgrade at the bench\")")
	# Refused: with no cubes, a click buys nothing and the row says why.
	var cubes: float = GameState.get_currency("cubes").to_float()
	GameState.spend("cubes", BigNum.from_float(cubes))
	await tree.create_timer(0.6).timeout  # the list refreshes
	var lv1: int = GameState.level_of(id)
	var t0: int = _toasts.size()
	if row:
		await _click(tree, row)
		await _frames(tree, 6)
	var it2: Dictionary = ld.call("_find", id)
	_check(GameState.level_of(id) == lv1 and str(it2.get("state", "")) != "ready", "upgrade: with no cubes a click buys nothing (state %s, reason '%s')" % [str(it2.get("state", "")), str(it2.get("reason", ""))])
	_check(_toasts.size() > t0, "upgrade: the refused click says why (%s)" % (_toasts[-1] if _toasts.size() > t0 else "nothing"))
	GameState.add_currency("cubes", BigNum.from_float(cubes))
	var gi: int = _goal(gl, "compartment_3")
	_check(gi < 0 or gl.value_of(gi) == float(GameState.level_of(id)), "upgrade: \"Chest Size level 3\" reads the level")
	await _tap(tree, "ui_cancel")
	await tree.create_timer(0.5).timeout
	if _open(up):
		up.call("close_screen") if up.has_method("close_screen") else null
	await _frames(tree, 4)


static func _open(up: UpgradesScreen) -> bool:
	var v: Variant = up.get("is_open")
	return bool(v)


## stat via E: pet a cat if one is about the start hub (cats come and go; a miss is a note).
## stat via E: "Pet a stray cat". Cats come with clean city ground, so a fresh game has none near
## the yard: dev puts one there (the adopted-cat path, Fauna's "named_cat": it lives at the base),
## then the walk stands Lumi by it and presses the interact key for real.
static func _pet(so: SliceOrbit, w: Node, p: Patch) -> void:
	var tree: SceneTree = w.get_tree()
	var fa: Fauna = w.get("fauna") as Fauna
	if fa == null:
		_check(false, "stat: Fauna in the world (cats)")
		return
	if fa.adopted_cat().is_empty():
		GameState.flags["fauna_cat"] = {"name": "Biscuit", "coat": 0, "hub": 0}  # dev: a cat that lives at the base
		print("[walk-goals] note: dev put a cat at the base (fresh games have none near the yard)")
	var cat: Fauna.Animal = null
	for k: int in 60:
		for a: Fauna.Animal in fa.animals:
			if a.kind == "cat" and a.state != Fauna.St.LEAVE and a.anchor != null:
				cat = a
				break
		if cat:
			break
		await tree.create_timer(1.0).timeout
	_check(cat != null, "stat: a cat comes to the base")
	if cat == null:
		return
	var c0: float = float(GameState.stats.get("cats_petted", 0.0))
	var bench: Vector3 = so.bench_position()
	for k: int in 8:
		var cp: Vector3 = cat.anchor.global_position
		var off: Vector3 = cp - bench  # stand on the cat's far side from the bench (E there opens the bench)
		off = (off - cp.normalized() * off.dot(cp.normalized()))
		off = off.normalized() if off.length() > 0.01 else Vector3.RIGHT
		_stand(so, p, cp + off * 1.2, cp)
		await _frames(tree, 4)
		var pr: String = str(so.interact_prompt(p)) if so.has_method("interact_prompt") else ""
		await _tap(tree, "interact")
		await tree.create_timer(0.8).timeout
		if float(GameState.stats.get("cats_petted", 0.0)) > c0:
			break
		print("[walk-goals] pet try %d: prompt '%s', %.1f m from the cat" % [k, pr, p.global_position.distance_to(cp)])
	_check(float(GameState.stats.get("cats_petted", 0.0)) > c0, "stat: E by a cat counts cats_petted (\"Pet a stray cat\")")


## The goal "Place a decoration ({garden_mode})": its card and goal row show the player's key, not "(H)".
static func _decor_text(w: Node) -> void:
	var g: Dictionary = {}
	for d: Variant in Economy.read_json("res://data/goals.json").get("goals", []):
		if str((d as Dictionary).get("key", "")) == "decor_placed":
			g = d
			break
	var shown: String = ObjectiveCard.title_of(g)
	var key: String = Settings.glyph("garden_mode")
	_check(not g.is_empty() and key in shown and not "{" in shown, "decor goal: the card says the Garden Mode key (%s)" % shown)


static func _check(ok: bool, what: String) -> void:
	print("[walk-goals] %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


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
	await tree.create_timer(0.1).timeout
	_send(action, false)
	await _frames(tree, 2)


static func _hold(tree: SceneTree, action: String, secs: float) -> void:
	await tree.physics_frame
	_send(action, true)
	await tree.create_timer(secs).timeout
	_send(action, false)
	await _frames(tree, 2)


## A left click at the middle of a control (what the mouse does on a button).
## A left click at the middle of a control, through the viewport's GUI input (what the OS mouse
## does; Input.parse_input_event does not reach the GUI in a headless window).
static func _click(tree: SceneTree, c: Control) -> void:
	var vp: Viewport = c.get_viewport()
	var at: Vector2 = c.get_global_rect().get_center()
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	vp.push_input(mm, true)
	await tree.process_frame
	var hov: Control = vp.gui_get_hovered_control()
	if hov != c and not c.is_ancestor_of(hov):
		print("[walk-goals] note: the mouse at %s is over %s, not %s" % [str(at), str(hov.get_path()) if hov else "nothing", c.name])
	for down: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		ev.position = at
		ev.global_position = at
		ev.pressed = down
		vp.push_input(ev, true)
		await tree.process_frame


static func _stand(so: SliceOrbit, p: Patch, pos: Vector3, look: Vector3) -> void:
	var gp: Vector3 = so.globe.terrain.ground(pos.normalized())
	var up: Vector3 = gp.normalized()
	var fwd: Vector3 = look - gp
	fwd = (fwd - up * fwd.dot(up)).normalized()
	p.place_on_sphere(gp, fwd)
	var cam: Variant = so.get("cam")
	if cam != null and (cam as Object).has_method("reset_frame"):  # the camera behind Lumi, as after a walk
		(cam as Object).call("reset_frame", fwd)
