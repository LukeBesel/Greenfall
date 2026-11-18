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
	Vfx.burst("sparkle", p.global_position + p.up() * 0.9, Color(1.0, 0.85, 0.5), 0.8)  # [v6feel] local up
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
## --first-demo=bale|sale|robot|reveal: software renders run a few frames a minute, so the moment is
## fired ~40 s (wall) before --shot-delay and the game clock freezes at its peak (Engine.time_scale
## = 0); the shot then captures that instant. Leave the time scale at 1: a slow frame advances at most
## 8 physics ticks (0.133 s x time scale), so the freeze lands within a frame of the peak.
const DEMO_PEAK: Dictionary = {"bale": 0.22, "sale": 0.75, "robot": 0.42, "reveal": 0.45}

var _demo_setup: bool = false


func _demo_tick() -> void:
	var p: Patch = world.patch
	if not _demo_setup:
		_demo_setup = true
		_demo_prepare(p)
	var t: float = float(DevHooks.get("_elapsed"))
	if t < DevHooks.get_f("shot-delay", 60.0) - DevHooks.get_f("demo-lead", 60.0):
		return
	_demo_done = true
	match _demo:
		"bale":
			# Straight to the ram stroke and the eject (the press cycle runs on capped physics steps).
			p.model.press(1.0)
			bale_press(p)
			for vp: Vector3 in p.model.vent_points:
				Vfx.burst("steam", p.to_global(vp), Color(0.92, 0.92, 0.9, 0.5), 0.6)
			p.call("_spawn_cube")
		"sale":
			var cube: JunkCube = JunkCube.create(BigNum.from_float(84.0), {"fill": 0.95, "perfect": true, "colors": [Color(0.55, 0.5, 0.45)]})
			world.add_cube(cube)
			cube.global_position = (world.depot as Node3D).global_position + Vector3(0.0, 0.3, 0.0)
			world.depot.call("_swallow", cube)
		"robot":
			var at: Vector3 = p.global_position + p.forward() * 2.0 + p.global_transform.basis.x * 1.1
			var r: Robot = world.fleet.spawn("scoopie", 0, at, 0.0, "Tin-15")
			GameState.inc_stat("robots_built")
			EventBus.robot_built.emit(r.robot_name)
		"reveal":
			for pid: int in world.field.hex_pieces[_demo_hex]:
				if world.field.piece_alive[pid] != 0:
					world.collect_piece(pid)
	# Freeze after enough rendered frames to reach the peak (process time per frame is known only
	# once frames run: count game time ourselves).
	_freeze_at_peak(float(DEMO_PEAK.get(_demo, 0.5)))


var _demo_hex: int = -1


func _demo_prepare(p: Patch) -> void:
	match _demo:
		"bale":
			var cap: float = p.capacity()
			p.compartment.add("metal", cap * 0.95)
			EventBus.compartment_changed.emit(p.compartment.fill, cap)
		"reveal":
			# The hex ahead of Lumi, cleared down to its last few pieces (they go at the trigger).
			var f: HexField = world.field
			_demo_hex = f.hex_at(p.global_position + p.forward() * 5.0)
			var alive: Array[int] = []
			for pid: int in f.hex_pieces[_demo_hex]:
				if f.piece_alive[pid] != 0:
					alive.append(pid)
			for k: int in alive.size() - mini(6, alive.size()):
				world.collect_piece(alive[k])
			world.cam.distance = DevHooks.get_f("demo-dist", 9.0)
			world.cam.pitch = -0.62
			world.cam.snap()


func _freeze_at_peak(peak: float) -> void:
	var t: float = 0.0
	while t < peak:
		await get_tree().process_frame
		t += get_process_delta_time()
	Engine.time_scale = 0.0
	print("[first] demo %s frozen at its peak (%.2f s)" % [_demo, t])
