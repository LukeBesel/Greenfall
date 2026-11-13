class_name SeedWalk
extends RefCounted
## [v8seed] Owner, 2026-11-13: "It wont let me plant in the dirt... i cant plant the first seed".
## The autoplay bot always got past the seed step (it walks to a clean hex's free slot), so this
## plays "Plant the first seed" the way a player does, with real input events (the keys and the
## mouse button the input map binds), on the real globe:
##   1. the step starts: the seed key is refused with a line, and the signal and beacon come at once;
##   2. at the tin in the greenhouse: the interact key takes it (the cinematic runs, a seed comes);
##   3. on a road spot by the pad: the seed key, the button held: nothing goes in, and a line says why;
##   4. the owner's slip: the water key, the button held on a bed: no seed used, a line says "plant first";
##   5. the seed key, the button held on a bed (the dirt the player sees): the seed goes in.
## --seed-walk[=S] (after S s, default 8): prints [seedwalk] lines, exit 1 on a failure.
## tools/check_exit.sh runs it with the tests.

static var _toasts: Array[String] = []
static var _fails: Array[String] = []


static func run_dev(so: SliceOrbit) -> void:
	var tree: SceneTree = so.w.get_tree()
	await tree.create_timer(DevHooks.get_f("seed-walk", 8.0)).timeout
	var w: Node = so.w
	for k: int in 240:  # the world is whole (the slice runs disabled while the globe builds)
		if not bool(w.get("building")) and w.get("first_seed") != null and w.get("objectives") != null:
			break
		await tree.create_timer(0.5).timeout
	var fs: FirstSeed = w.get("first_seed") as FirstSeed
	var ob: Objectives = w.get("objectives") as Objectives
	var p: Patch = w.get("patch") as Patch
	if fs == null or ob == null or p == null:
		print("[seedwalk] FAIL: no greenhouse / objectives / Lumi")
		tree.quit(1)
		return
	EventBus.toast.connect(func(t: String, _k: String) -> void: _toasts.append(t))
	# The state a new game reaches the step in: three clean hexes, the step up, no seed yet.
	var idx: int = ob.chain.map(func(d: Dictionary) -> String: return str(d["id"])).find("seed")
	ob.step = idx
	ob.revealed = true
	GameState.flags["objective_step"] = idx
	GameState.flags["onboard_brief"] = true
	GameState.flags["tutorial_step"] = Tutorial.STEPS.size()
	GameState.stats["hexes_cleaned"] = maxf(float(GameState.stats.get("hexes_cleaned", 0)), 3.0)
	_check(not GameState.flags.get("seeds_unlocked", false), "a fresh game has no seeds yet")
	# 1. The seed key before the tin: refused, with a line.
	_toasts.clear()
	await _tap(tree, "tool_plant")
	_check(p.tool == Patch.Tool.SCOOP and _said("seed"), "seed key before the tin: refused with a line (%s)" % str(_toasts))
	for k: int in 40:
		if GameState.flags.get("seed_signal", false):
			break
		await tree.create_timer(0.25).timeout
	var tgt: Dictionary = ob.step_target(ob.current())
	_check(GameState.flags.get("seed_signal", false) and str(tgt.get("to", "")) == "place", "the signal and the beacon come as the step starts (to=%s)" % str(tgt.get("to", "")))
	# 2. At the tin: interact.
	var tin: Vector3 = fs._tin.global_position
	_stand(so, p, fs.to_global(FirstSeed.GREENHOUSE_POS + Vector3(0.0, 0.0, 0.5)), tin)
	await _frames(tree, 6)
	_check(fs.near_tin(p.global_position), "standing in the aisle by the tin, it can be taken")
	Engine.time_scale = 8.0  # the cinematic's lines (timers) at speed
	await _tap(tree, "interact")
	for k: int in 120:
		if GameState.flags.get("seeds_unlocked", false) and (p.input as PlayerInput).enabled:
			break
		await tree.create_timer(1.0).timeout
	Engine.time_scale = 1.0
	await _frames(tree, 4)
	_check(GameState.flags.get("seeds_unlocked", false), "the tin gives the seeds")
	_check(GameState.get_currency("seeds").to_float() >= 1.0, "a seed to plant")
	tgt = ob.step_target(ob.current())
	_check(str(tgt.get("to", "")) == "place", "the beacon stands on the beds while the seed waits")
	if DevHooks.has("seed-pose"):  # renders: stop at the beds with the seed tool out (--seed-pose=water: the can)
		var gp: Garden = w.get("garden") as Garden
		_stand(so, p, fs.to_global(FirstSeed.GREENHOUSE_POS + Vector3(-0.2, 0.0, FirstSeed.BED_SPOTS[0].z - 0.4)), gp.slot_pos[fs.bed_slots[0]])
		await _tap(tree, "tool_water" if DevHooks.get_s("seed-pose", "") == "water" else "tool_plant")
		print("[seedwalk] posed at the beds")
		return
	# 3. A road spot by the pad (where the greenhouse stood before): refused with a line.
	var site: Transform3D = so.globe.sites[0]["transform"]
	var road: Vector3 = so.globe.terrain.ground((site * Vector3(11.0, 0.0, 11.6)).normalized())
	var crews: Variant = so.get("crews")
	for rh: int in so.globe.field.hexes_near(road, 1):  # clean (as the owner's were), so the refusal is the ground's
		if crews != null and not so.globe.field.is_clean(rh) and so.globe.field.hex_hub[rh] == 0 and not so.globe.field.is_water(rh):
			(crews as OrbitCrews).work_cell(rh, 0.0)
	_stand(so, p, road, road + _north(road) * 3.0)
	await _frames(tree, 4)
	var planted0: int = int(GameState.stats.get("plants_planted", 0))
	var g: Garden = w.get("garden") as Garden
	var why: String = g.plant_refusal(p.global_position, p.forward())
	await _tap(tree, "tool_plant")
	_toasts.clear()
	await _hold(tree, "scoop", 1.2)
	if why == "":
		print("[seedwalk] note: the road spot took a seed (open ground there now)")
	else:
		_check(int(GameState.stats.get("plants_planted", 0)) == planted0 and why == "paved" and _said(_refusal(why)),
			"on the road: no seed, and a line why (%s: %s)" % [why, str(_toasts)])
	# 4. + 5. Back at the beds: the water key first (the owner's shot), then the seed key.
	var bed: Vector3 = g.slot_pos[fs.bed_slots[0]]
	_stand(so, p, fs.to_global(FirstSeed.GREENHOUSE_POS + Vector3(0.0, 0.0, FirstSeed.BED_SPOTS[0].z)), bed)
	await _frames(tree, 6)
	await _tap(tree, "tool_water")
	_toasts.clear()
	var seeds0: float = GameState.get_currency("seeds").to_float()
	await _hold(tree, "scoop", 1.0)
	_check(GameState.get_currency("seeds").to_float() == seeds0 and _said("plant"),
		"the water key on the bed: no seed used, a line says plant first (%s)" % str(_toasts))
	await _tap(tree, "tool_plant")
	_check(p.tool == Patch.Tool.PLANT, "the seed key picks the seed")
	await _hold(tree, "scoop", 1.5)
	_check(int(GameState.stats.get("plants_planted", 0)) >= planted0 + 1, "holding the button on the bed plants the seed")
	_check(g.slot_species[fs.bed_slots[0]] >= 0 or g.planted_slots().size() > 0, "a plant in the bed")
	_check((g.persist_sparse().get("beds", []) as Array).size() > 0, "the bed's plant is saved")
	print("[seedwalk] %s" % ("PASS" if _fails.is_empty() else "FAIL: " + "; ".join(_fails)))
	tree.quit(0 if _fails.is_empty() else 1)


## A toast (not an achievement) holding the text, any case.
static func _said(t: String) -> bool:
	for s: String in _toasts:
		if not s.begins_with("Achievement") and t.to_lower() in s.to_lower():
			return true
	return false


## A word from the line Lumi says for the refusal reason (the line itself is Patch's).
static func _refusal(why: String) -> String:
	return {"dirty": "clean", "paved": "soil", "full": "growing", "seeds": "seeds"}.get(why, "seed")


static func _check(ok: bool, what: String) -> void:
	print("[seedwalk] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


static func _frames(tree: SceneTree, n: int) -> void:
	for k: int in n:
		await tree.physics_frame


## The first key or mouse-button event the input map binds to the action (what a player presses).
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
	await tree.physics_frame  # the press lands in a physics step, where Lumi reads just-pressed
	_send(action, true)
	await tree.create_timer(0.1).timeout  # a real key press is down for a tenth of a second or so
	_send(action, false)
	await _frames(tree, 2)


static func _hold(tree: SceneTree, action: String, secs: float) -> void:
	await tree.physics_frame
	_send(action, true)
	await tree.create_timer(secs).timeout
	_send(action, false)
	await _frames(tree, 2)


## Puts Lumi on the ground at pos, facing look (the steps a player walks are not the point here).
static func _stand(so: SliceOrbit, p: Patch, pos: Vector3, look: Vector3) -> void:
	var gp: Vector3 = so.globe.terrain.ground(pos.normalized())
	var up: Vector3 = gp.normalized()
	var fwd: Vector3 = look - gp
	fwd = (fwd - up * fwd.dot(up)).normalized()
	p.place_on_sphere(gp, fwd)


static func _north(p: Vector3) -> Vector3:
	return -SphereGrid.frame(p.normalized()).z
