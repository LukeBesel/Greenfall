class_name Intro
extends Node
## Opening cinematic on a fresh game (skippable with Esc / Space / Enter / A):
##   1. Wide shot over the hazy junk city, title card.
##   2. A landing pod streaks down through the haze and slams in beside the old shack.
##   3. Steam, the hatch drops, Aurora drifts out asleep, then its eyes flicker on.
##   4. WREN's voice crackles in over the Cradle uplink. Fade into play.
## The pod stays in the world afterwards as a landmark.

signal finished

var world: Node
var running: bool = false
## True from _finish() until the fade-out has handed the camera and controls back.
var ending: bool = false

var _cam: Camera3D
var _prev_cam: Camera3D
var _layer: CanvasLayer
var _fade: ColorRect
var _title: Label
var _sub: Label
var _skip: Label
var _bars: Array[ColorRect] = []
var _pod: Node3D
var _hatch: Node3D
var _skipped: bool = false
var _t: float = 0.0
var _cam_from := Transform3D()
var _cam_to := Transform3D()
var _cam_dur: float = 1.0
var _cam_t: float = 0.0

const POD_POS := Vector3(6.0, 0.0, 9.5)


## Builds the pod prop (also used after the intro as a landmark).
static func build_pod() -> Node3D:
	var pod := Node3D.new()
	pod.name = "LandingPod"
	var shell: ShaderMaterial = Mats.worn_paint(Color(0.88, 0.88, 0.85), 0.8, 0.35, 21.0, 0.6)
	var dark: StandardMaterial3D = Mats.metal("dark_steel")
	var accent: ShaderMaterial = Mats.worn_paint(Color(1.0, 0.55, 0.18), 0.85, 0.3, 5.0, 0.5)
	var body := MeshInstance3D.new()
	body.mesh = ProcMesh.capsule(0.75, 2.2)
	body.material_override = shell
	body.position = Vector3(0, 0.95, 0)
	body.rotation_degrees = Vector3(0, 0, 8)
	pod.add_child(body)
	for k: int in 3:
		var fin := MeshInstance3D.new()
		fin.mesh = ProcMesh.rounded_box(Vector3(0.12, 0.7, 0.5), 0.04, 2)
		fin.material_override = dark
		var a: float = TAU * k / 3.0
		fin.position = Vector3(cos(a) * 0.72, 0.4, sin(a) * 0.72)
		fin.rotation = Vector3(0, -a, 0)
		pod.add_child(fin)
	var band := MeshInstance3D.new()
	band.mesh = ProcMesh.torus(0.72, 0.8, 32, 6)
	band.material_override = accent
	band.position = Vector3(0.06, 1.25, 0)
	band.rotation_degrees = Vector3(0, 0, 8)
	pod.add_child(band)
	var window := MeshInstance3D.new()
	window.mesh = ProcMesh.cyl(0.22, 0.22, 0.05, 24)
	window.material_override = Mats.lamp(Color(0.3, 0.85, 1.0), 1.5)
	window.position = Vector3(0.18, 1.7, -0.68)
	window.rotation_degrees = Vector3(90, 0, 8)
	pod.add_child(window)
	# Hatch (front), hinged at the bottom.
	var hatch := Node3D.new()
	hatch.name = "Hatch"
	hatch.position = Vector3(0.05, 0.35, -0.72)
	pod.add_child(hatch)
	var door := MeshInstance3D.new()
	door.mesh = ProcMesh.rounded_box(Vector3(0.8, 1.1, 0.08), 0.06, 2)
	door.material_override = shell
	door.position = Vector3(0, 0.55, 0)
	hatch.add_child(door)
	var stripe := MeshInstance3D.new()
	stripe.mesh = ProcMesh.box(Vector3(0.6, 0.05, 0.02))
	stripe.material_override = Mats.lamp(Color(1.0, 0.6, 0.2), 2.0)
	stripe.position = Vector3(0, 0.9, -0.05)
	hatch.add_child(stripe)
	# Scorched crater ring.
	var scorch := MeshInstance3D.new()
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.08, 0.07, 0.06, 0.75)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.roughness = 1.0
	scorch.mesh = ProcMesh.cyl(1.8, 1.8, 0.01, 32)
	scorch.material_override = sm
	scorch.position = Vector3(0, 0.02, 0)
	pod.add_child(scorch)
	return pod


func should_play() -> bool:
	if DevHooks.has("intro"):
		return true
	if GameState.flags.get("intro_done", false):
		return false
	if DisplayServer.get_name() == "headless":
		return false
	for f: String in ["shot", "autoplay", "open", "spawn-pos", "spawn-hex", "robots", "no-intro"]:
		if DevHooks.has(f):
			return false
	return true


## Places the pod landmark (called every load once the intro has happened).
func place_pod() -> void:
	if _pod == null:
		_pod = build_pod()
		world.add_child(_pod)
	_pod.global_position = POD_POS + Vector3(0, _ground(POD_POS), 0)
	_pod.rotation.y = 0.5
	_hatch = _pod.get_node("Hatch")
	_hatch.rotation.x = -1.45


func _ground(p: Vector3) -> float:
	var layout: CityLayout = world.field.layout
	return clampf(layout.height_at(p.x, p.z), 0.0, 0.3) if layout else 0.0


func play() -> void:
	running = true
	var patch: Node3D = world.patch
	_set_player_enabled(false)
	if world.get("hud") != null:
		world.hud.visible = false
	if world.get("music") != null:
		world.music.set_cinematic(true)
	_build_overlay()
	_prev_cam = get_viewport().get_camera_3d()
	_cam = Camera3D.new()
	_cam.fov = 55.0
	world.add_child(_cam)
	_cam.current = true
	# Pod (hidden, high in the sky).
	_pod = build_pod()
	world.add_child(_pod)
	_hatch = _pod.get_node("Hatch")
	var land: Vector3 = POD_POS + Vector3(0, _ground(POD_POS), 0)
	_pod.rotation.y = 0.5
	_pod.global_position = land + Vector3(-60, 140, 40)
	patch.visible = false
	var model: PatchModel = patch.get("model")
	if model:
		model.sleeping = true

	# Shot 1: wide establishing shot over the city.
	_shot(Vector3(-40, 34, 46), Vector3(0, 2, 0), Vector3(-26, 22, 30), Vector3(0, 1, 0), 7.0)
	_fade_to(0.0, 2.5)
	await _wait(1.2)
	if _skipped:
		return
	_show_title("GREENFALL", "Verdance  ·  three hundred years after everyone left")
	await _wait(4.0)
	if _skipped:
		return
	_hide_title()
	# Shot 2: the pod streaks down.
	_shot(Vector3(-14, 6, 18), land + Vector3(-20, 30, 10), Vector3(-10, 4, 15), land + Vector3(0, 1, 0), 3.2)
	var trail_t: float = 0.0
	var start: Vector3 = _pod.global_position
	Audio.play("whoosh", 0.4, 0.0)
	while trail_t < 2.6 and not _skipped:
		trail_t += get_process_delta_time()
		var k: float = clampf(trail_t / 2.6, 0.0, 1.0)
		var e: float = k * k
		_pod.global_position = start.lerp(land, e)
		_pod.rotation.z = (1.0 - k) * 0.6
		if randf() < 0.7:
			Vfx.burst("steam", _pod.global_position + Vector3(0, 1.0, 0), Color(1.0, 0.75, 0.45, 0.8), 0.6)
			Vfx.burst("sparkle", _pod.global_position + Vector3(0, 1.0, 0), Color(1.0, 0.6, 0.25), 0.3)
		await get_tree().process_frame
	if _skipped:
		return
	_pod.global_position = land
	_pod.rotation.z = 0.0
	if not _skipped:
		Audio.play("thud", 0.5, 4.0)
		Audio.play("crunch", 0.6, 0.0)
		EventBus.shake_requested.emit(1.0)
		for i: int in 6:
			Vfx.burst("dust", land + Vector3(randf_range(-1.5, 1.5), 0.3, randf_range(-1.5, 1.5)), Color(0.6, 0.55, 0.48, 0.8), 1.5)
		Vfx.burst("bits", land + Vector3(0, 0.5, 0), Color(0.4, 0.38, 0.34), 1.0)
	await _wait(1.6)
	if _skipped:
		return
	# Shot 3: close on the hatch. Steam, it drops open, Aurora drifts out.
	var front: Vector3 = _pod.global_transform * Vector3(0, 0.8, -3.2)
	_shot(front + Vector3(0.6, 0.6, 0.0), land + Vector3(0, 1.0, 0), front + Vector3(0.3, 0.2, 0.6), land + Vector3(0, 0.8, 0), 5.0)
	await _wait(0.6)
	if _skipped:
		return
	for i: int in 4:
		Vfx.burst("steam", _pod.global_transform * Vector3(0, 0.9, -0.8), Color(0.9, 0.92, 0.95, 0.7), 1.0)
	Audio.play("steam", 0.7, -2.0)
	await _wait(0.6)
	if _skipped:
		return
	Audio.play("hydraulic", 0.8, -4.0)
	var tw := create_tween()
	tw.tween_property(_hatch, "rotation:x", -1.45, 0.9).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	await _wait(1.0)
	if _skipped:
		return
	var out_from: Vector3 = _pod.global_transform * Vector3(0, 0.3, -0.3)
	var out_to: Vector3 = _pod.global_transform * Vector3(0, 0.05, -2.2)
	out_to.y = _ground(out_to) + 0.05
	patch.visible = true
	patch.global_position = out_from
	patch.look_at(patch.global_position + (out_to - out_from) * Vector3(1, 0, 1), Vector3.UP)
	patch.rotate_object_local(Vector3.UP, PI)
	var drift := create_tween()
	drift.tween_property(patch, "global_position", out_to, 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _wait(2.4)
	if _skipped:
		return
	# Shot 4: face close-up. Eyes flicker on.
	var face_cam: Vector3 = out_to + (out_to - out_from).normalized() * 1.6 + Vector3(0.3, 0.75, 0)
	_shot(face_cam, out_to + Vector3(0, 0.75, 0), face_cam + Vector3(0, -0.05, 0) - (out_to - out_from).normalized() * 0.3, out_to + Vector3(0, 0.7, 0), 6.0)
	await _wait(0.8)
	if _skipped:
		return
	if model:
		for i: int in 3:
			model.sleeping = false
			Audio.play("blip", 0.9 + i * 0.15, -8.0)
			await _wait(0.12)
			if _skipped:
				return
			model.sleeping = true
			await _wait(0.25)
			if _skipped:
				return
		model.sleeping = false
		model.flash()
		Audio.play("servo", 1.2, -6.0)
		await _wait(0.6)
		if _skipped:
			return
		model.look_toward(out_to + Vector3(-3, 1, 2))
		await _wait(0.9)
		if _skipped:
			return
		model.look_toward(out_to + Vector3(3, 1, 2))
		await _wait(0.9)
		if _skipped:
			return
		model.look_toward(null)
		model.set_happy(1.0)
		Audio.play("chirp" if Audio.has_sound("chirp") else "blip", 1.3, -6.0)
	await _wait(0.6)
	if _skipped:
		return
	_subtitle("WREN:  ...Signal. Lumi? LM-1, can you hear me?")
	await _wait(3.2)
	if _skipped:
		return
	_subtitle("WREN:  This is WREN, up on the Cradle. You made it down. Look at all of it...")
	await _wait(3.6)
	if _skipped:
		return
	_subtitle("WREN:  Let's start small. One can at a time.")
	await _wait(2.8)
	if _skipped:
		return
	_finish()


func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 40
	add_child(_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	_layer.add_child(root)
	for top: bool in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		bar.custom_minimum_size = Vector2(0, 0)
		if top:
			bar.offset_bottom = 70
		else:
			bar.offset_top = -70
		root.add_child(bar)
		_bars.append(bar)
	_title = UITheme.label("", 64, Color(1, 1, 1))
	_title.set_anchors_preset(Control.PRESET_CENTER)
	_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_title.grow_vertical = Control.GROW_DIRECTION_BOTH
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_constant_override("outline_size", 0)
	_title.modulate.a = 0.0
	root.add_child(_title)
	_sub = UITheme.label("", 18, Color(0.9, 0.92, 0.95))
	_sub.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_sub.offset_top = -64
	_sub.offset_bottom = -30
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.modulate.a = 0.0
	root.add_child(_sub)
	_skip = UITheme.label("", 12, Color(1, 1, 1, 0.45))
	Settings.bind_text(_skip, func() -> String: return "%s  skip" % ("Space / Esc" if not Settings.last_input_pad else Settings.glyph("ui_accept")))  # [deck]
	_skip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip.offset_left = -170
	_skip.offset_top = 24
	root.add_child(_skip)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)


func _show_title(t: String, sub: String) -> void:
	_title.text = t + "\n"
	var s := UITheme.label(sub, 16, Color(1, 1, 1, 0.75))
	s.name = "TitleSub"
	s.set_anchors_preset(Control.PRESET_CENTER)
	s.grow_horizontal = Control.GROW_DIRECTION_BOTH
	s.offset_top = 30
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.modulate.a = 0.0
	_title.get_parent().add_child(s)
	create_tween().tween_property(_title, "modulate:a", 1.0, 1.2)
	create_tween().tween_property(s, "modulate:a", 1.0, 1.6)


func _hide_title() -> void:
	create_tween().tween_property(_title, "modulate:a", 0.0, 0.8)
	var s: Node = _title.get_parent().get_node_or_null("TitleSub")
	if s:
		create_tween().tween_property(s, "modulate:a", 0.0, 0.8)


func _subtitle(t: String) -> void:
	_sub.text = t
	_sub.modulate.a = 0.0
	create_tween().tween_property(_sub, "modulate:a", 1.0, 0.3)
	Audio.play("blip", 0.7, -14.0)


func _fade_to(a: float, dur: float) -> void:
	create_tween().tween_property(_fade, "color:a", a, dur)


func _shot(from: Vector3, from_look: Vector3, to: Vector3, to_look: Vector3, dur: float) -> void:
	_cam_from = Transform3D(Basis(), from).looking_at(from_look, Vector3.UP)
	_cam_to = Transform3D(Basis(), to).looking_at(to_look, Vector3.UP)
	_cam_dur = dur
	_cam_t = 0.0
	if _cam:
		_cam.global_transform = _cam_from


func _process(delta: float) -> void:
	if not running or _cam == null:
		return
	_cam_t += delta
	var k: float = clampf(_cam_t / _cam_dur, 0.0, 1.0)
	var e: float = k * k * (3.0 - 2.0 * k)
	_cam.global_transform = _cam_from.interpolate_with(_cam_to, e)


func _wait(s: float) -> void:
	if _skipped:
		return
	await get_tree().create_timer(s).timeout


func _unhandled_input(event: InputEvent) -> void:
	if not running or _skipped:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel") \
			or (event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_SPACE):
		get_viewport().set_input_as_handled()
		_skipped = true
		_finish()


func _finish() -> void:
	if not running:
		return
	running = false
	ending = true
	var patch: Node3D = world.patch
	patch.visible = true
	var model: PatchModel = patch.get("model")
	if model:
		model.sleeping = false
		model.set_happy(0.6)
	place_pod()
	if patch.global_position.distance_to(POD_POS) > 6.0 or _skipped:
		patch.global_position = Vector3(0, 0.05, 3.0)
	GameState.flags["intro_done"] = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.4)
	tw.tween_callback(func() -> void:
		ending = false
		var modal: bool = world.has_method("any_modal_open") and world.any_modal_open()
		if _prev_cam and is_instance_valid(_prev_cam) and not modal:
			_prev_cam.current = true
		if _cam:
			_cam.queue_free()
		if world.get("hud") != null and not modal:
			world.hud.visible = true
		if world.get("music") != null:
			world.music.set_cinematic(false)
		for b: ColorRect in _bars:
			b.visible = false
		_title.visible = false
		_sub.visible = false
		_skip.visible = false
		if not modal:
			_set_player_enabled(true))
	tw.tween_property(_fade, "color:a", 0.0, 0.8)
	tw.tween_callback(func() -> void:
		_layer.queue_free()
		finished.emit())


## The intro (or its fade-out) still owns the camera and controls.
func busy() -> bool:
	return running or ending


func _set_player_enabled(on: bool) -> void:
	var patch: Node = world.patch
	if patch.get("input") is PlayerInput:
		(patch.input as PlayerInput).enabled = on
	if world.get("cam") != null:
		world.cam.input_enabled = on
