class_name FeelFx
extends Node
## [first] Core-loop "juice" that ties existing Vfx/Audio together without adding noise:
##   bale press   Lumi squashes on the ram stroke and stretches back, a deep thunk under the crunch;
##                the bale pops out squashed and springs to shape
##   upgrades     after closing the workbench with new installs, Lumi shows them off (a little
##                stretch, a glint and a two-note confirm)
##   first robot  a rollout moment once the menu is closed: a soft light column, rings, the robot
##                springs to size, Lumi turns to look, "NEW CREWMATE" text
##   hex reveal   a dust-and-glint sweep that rides the ground shader's reveal ripple outward; the
##                first hex adds a low airy sweep and a rising three-note chord
## Screen shake goes through EventBus.shake_requested (CameraRig honours Shake and Reduced motion);
## squash and stretch is skipped with Reduced motion.

const RIPPLE_SPEED: float = 5.0  ## matches ground_pbr.gdshader ripple_speed
const ROBOT_CYAN := Color(0.55, 0.9, 1.0)

var world: Node
var _pending_robot: String = ""
var _installs: int = 0
var _was_modal: bool = false
var _demo: String = ""
var _demo_done: bool = false


func _ready() -> void:
	EventBus.cube_made.connect(func(_i: Dictionary) -> void: _pop_newest_cube())
	EventBus.upgrade_bought.connect(func(_id: String, _l: int) -> void: _installs += 1)
	EventBus.robot_built.connect(_on_robot_built)
	EventBus.hex_cleaned.connect(_on_hex_cleaned)
	_demo = DevHooks.get_s("first-demo", "")
	if DevHooks.has("tutorial-step"):  # dev: jump the restart checklist (shots of a given step)
		var st: int = int(DevHooks.get_f("tutorial-step", 0.0))
		GameState.flags["tutorial_step"] = st
		var tut: Tutorial = world.get("tutorial") as Tutorial if world else null
		if tut:
			tut.step = st
			tut._announce.call_deferred()


func _process(_delta: float) -> void:
	if world == null:
		return
	if _demo != "" and not _demo_done:
		_demo_tick()
	var modal: bool = world.has_method("any_modal_open") and bool(world.call("any_modal_open"))
	var hud: CanvasLayer = world.get("hud") as CanvasLayer
	var free: bool = not modal and (hud == null or hud.visible)
	if free and _was_modal:
		if _installs > 0:
			show_off_upgrade(_installs)
			_installs = 0
	_was_modal = modal
	if free and _pending_robot != "":
		var n: String = _pending_robot
		_pending_robot = ""
		rollout(n)


# --- Bale press ----------------------------------------------------------------------------

## The ram stroke lands (called from Patch at the crunch): squash, thunk, a small shake.
static func bale_press(p: Patch) -> void:
	Audio.play("thunk", 1.0, -4.0)
	EventBus.shake_requested.emit(0.16)
	if Settings.reduced_motion or p.model == null:
		return
	var m: Node3D = p.model
	var tw := m.create_tween()
	tw.tween_property(m, "scale", Vector3(1.09, 0.88, 1.09), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "scale", Vector3(0.96, 1.06, 0.96), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## The fresh bale leaves the hatch squashed and springs to shape.
func _pop_newest_cube() -> void:
	if Settings.reduced_motion or world == null or world.get("patch") == null:
		return
	var p: Node3D = world.patch
	var best: JunkCube = null
	var bd: float = 9.0
	for n: Node in get_tree().get_nodes_in_group("junk_cube"):
		var c: JunkCube = n as JunkCube
		if c == null or c.carried or c.has_meta("popped"):
			continue
		var d: float = c.global_position.distance_squared_to(p.global_position)
		if d < bd:
			bd = d
			best = c
	if best == null:
		return
	best.set_meta("popped", true)
	var vis: Node3D = best.get("_visual") as Node3D
	if vis == null:
		return
	var s0: Vector3 = vis.scale
	vis.scale = s0 * Vector3(1.22, 0.7, 1.22)
	var tw := vis.create_tween()
	tw.tween_property(vis, "scale", s0 * Vector3(0.94, 1.08, 0.94), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(vis, "scale", s0, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


# --- Upgrades ------------------------------------------------------------------------------

func show_off_upgrade(n: int) -> void:
	var p: Patch = world.get("patch") as Patch
	if p == null:
		return
	Audio.play("confirm", 1.0 + minf(n - 1, 4) * 0.03, -9.0)
	Audio.play("servo", 1.5, -14.0)
	Vfx.burst("sparkle", p.global_position + Vector3(0, 0.9, 0), Color(1.0, 0.85, 0.5), 0.8)
	p.model.set_happy(1.0)
	if not Settings.reduced_motion:
		var m: Node3D = p.model
		var tw := m.create_tween()
		tw.tween_property(m, "scale", Vector3(0.95, 1.08, 0.95), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(m, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(1.6).timeout.connect(func() -> void: if is_instance_valid(p): p.model.set_happy(0.5))


# --- First robot ---------------------------------------------------------------------------

func _on_robot_built(rname: String) -> void:
	if int(GameState.stats.get("robots_built", 0)) != 1 or GameState.flags.get("first_robot_moment", false):
		return
	GameState.flags["first_robot_moment"] = true
	_pending_robot = rname
	# Keep it out of sight until the moment plays (the build usually happens inside the menu).
	var r: Robot = world.fleet.find_robot(rname) if world and world.get("fleet") else null
	if r and r.visual and not Settings.reduced_motion:
		r.visual.scale = Vector3.ONE * 0.01


func rollout(rname: String) -> void:
	var r: Robot = world.fleet.find_robot(rname) if world.get("fleet") else null
	if r == null:
		return
	var at: Vector3 = r.global_position
	Vfx.pillar(at, ROBOT_CYAN, 5.0, 1.8)
	Vfx.ring(at, 2.2, Color(ROBOT_CYAN, 0.8), 0.7)
	get_tree().create_timer(0.25).timeout.connect(func() -> void: Vfx.ring(at, 3.4, Color(ROBOT_CYAN, 0.5), 0.9))
	Vfx.burst("big_sparkle", at + Vector3(0, 0.6, 0), Color(0.7, 0.95, 1.0), 0.6)
	Audio.play("confirm", 0.75, -6.0)
	Audio.play("servo", 0.9, -9.0)
	get_tree().create_timer(0.35).timeout.connect(func() -> void: Audio.play("beep", 1.3, -10.0))
	get_tree().create_timer(0.55).timeout.connect(func() -> void: Audio.play("beep", 1.6, -11.0))
	Vfx.float_text(at + Vector3(0, 1.6, 0), tr("NEW CREWMATE  ·  %s") % rname, Color(0.75, 0.95, 1.0), 0.9, 1.0)
	if r.visual:
		var v: Node3D = r.visual
		if Settings.reduced_motion:
			v.scale = Vector3.ONE
		else:
			v.scale = Vector3(0.6, 0.2, 0.6)
			var tw := v.create_tween()
			tw.tween_interval(0.15)
			tw.tween_property(v, "scale", Vector3(0.9, 1.25, 0.9), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(v, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var p: Patch = world.get("patch") as Patch
	if p:
		p.model.look_toward(at + Vector3(0, 0.5, 0))
		p.model.set_happy(1.0)
		get_tree().create_timer(2.2).timeout.connect(func() -> void:
			if is_instance_valid(p):
				p.model.look_toward(null)
				p.model.set_happy(0.5))


# --- Hex reveal ----------------------------------------------------------------------------

func _on_hex_cleaned(hid: int, center: Vector3, _bonus: BigNum) -> void:
	if world == null or world.get("field") == null:
		return
	var f: HexField = world.field
	var first: bool = f.cleaned_count == 1
	var r: float = f.hex_size * 1.1
	Vfx.sweep(center, r, RIPPLE_SPEED, Color(0.86, 0.8, 0.68, 0.45), first)
	if first:
		Audio.play("sweep", 0.8, -8.0)
		var notes: Array[float] = [1.0, 1.2599, 1.4983]
		for k: int in notes.size():
			get_tree().create_timer(0.18 + 0.14 * k).timeout.connect(func() -> void: Audio.play("chime", notes[k] * 1.5, -12.0, 0.0))
		get_tree().create_timer(0.5).timeout.connect(func() -> void: Vfx.sweep(center, r * 1.35, RIPPLE_SPEED * 0.8, Color(1.0, 0.92, 0.7, 0.3), true))
	else:
		Audio.play("sweep", 1.0, -14.0)


# --- Dev: stage a moment for screenshots ----------------------------------------------------
## --first-demo=bale|sale|robot|reveal fires the moment so it peaks at --shot-delay. Leads are
## game seconds; DevHooks counts wall time, so they are divided by the time scale (software
## renders run a few frames a minute: pair with --time-scale=0.1 so the moment spans frames).
const DEMO_LEAD: Dictionary = {"bale": 0.6, "sale": 1.1, "robot": 0.5, "reveal": 0.45}


func _demo_tick() -> void:
	var t: float = float(DevHooks.get("_elapsed"))
	var ts: float = maxf(Engine.time_scale, 0.01)
	var at: float = DevHooks.get_f("shot-delay", 10.0) - float(DEMO_LEAD.get(_demo, 0.5)) / ts
	if _demo == "bale" and t >= at - 3.0 / ts and world.patch.compartment.is_empty():
		var cap: float = world.patch.capacity()
		world.patch.compartment.add("metal", cap * 0.95)
		EventBus.compartment_changed.emit(world.patch.compartment.fill, cap)
	if t < at:
		return
	_demo_done = true
	var p: Patch = world.patch
	match _demo:
		"bale":
			p.start_cube()
		"sale":
			var cube: JunkCube = JunkCube.create(BigNum.from_float(84.0), {"fill": 0.95, "perfect": true, "colors": [Color(0.55, 0.5, 0.45)]})
			world.add_cube(cube)
			cube.global_position = (world.depot as Node3D).global_position + Vector3(0.3, 0.6, 0.2)
		"robot":
			var r: Robot = world.fleet.spawn("scoopie", 0, p.global_position + p.global_transform.basis.z * -3.0 + Vector3(1.2, 0, 0), 0.0, "Tin-15")
			GameState.inc_stat("robots_built")
			EventBus.robot_built.emit(r.robot_name)
		"reveal":
			var h: int = p.focus_hex()
			var f: HexField = world.field
			if h < 0 or f.is_clean(h):
				h = f.hex_at(p.global_position + p.global_transform.basis.z * -4.0)
			for pid: int in f.hex_pieces[h]:
				if f.piece_alive[pid] != 0:
					world.collect_piece(pid)
