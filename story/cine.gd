class_name Cine
extends Node
## A short letterboxed story beat in the game world (used by the Bloom Core memories).
## begin() takes the camera, HUD and controls; end() always hands them back (also if the node is
## freed early). Space / Esc / Enter skip: `skipped` turns true and hold() returns true, so a
## beat written as `if await c.hold(2.0): return` stops at once; the owner then calls end().
## open_stage() puts a SpaceStage (the off-world sets) full screen under the letterbox.

signal ended

var world: Node
var cam: Camera3D
var stage: SpaceStage
var skipped: bool = false
var running: bool = false

var _prev_cam: Camera3D
var _layer: CanvasLayer
var _stage_layer: CanvasLayer
var _fade: ColorRect
var _cap: Label
var _bars: Array[ColorRect] = []
var _vignette: TextureRect
var _restored: bool = false


func begin() -> void:
	running = true
	_layer = CanvasLayer.new()
	_layer.layer = 40
	add_child(_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	_layer.add_child(root)
	_vignette = TextureRect.new()
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 1.0)
	var grad := Gradient.new()
	grad.set_color(0, Color(0.15, 0.1, 0.02, 0.0))
	grad.set_color(1, Color(0.15, 0.1, 0.02, 0.85))
	g.gradient = grad
	_vignette.texture = g
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.visible = false
	root.add_child(_vignette)
	for top: bool in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bar)
		_bars.append(bar)
		var tw := bar.create_tween()
		tw.tween_property(bar, "offset_bottom" if top else "offset_top", 70.0 if top else -70.0, 0.6)
	_cap = UITheme.label("", 18, Color(0.92, 0.94, 0.96))
	_cap.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_cap.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_cap.offset_top = -64
	_cap.offset_bottom = -30
	_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_cap)
	var skip := UITheme.label(tr("Space / Esc  skip"), 12, Color(1, 1, 1, 0.45))
	skip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	skip.offset_left = -170
	skip.offset_top = 24
	root.add_child(skip)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)
	_set_player_enabled(false)
	if world.get("hud") != null:
		world.hud.visible = false
	if world.get("music") != null:
		world.music.set_cinematic(true)
	_prev_cam = get_viewport().get_camera_3d()
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.far = 900.0
	world.add_child(cam)
	if _prev_cam:
		cam.global_transform = _prev_cam.global_transform
	cam.current = true


## Warm memory look: a soft sepia vignette over everything.
func memory_tint(on: bool) -> void:
	_vignette.visible = on


func open_stage() -> SpaceStage:
	_stage_layer = CanvasLayer.new()
	_stage_layer.layer = 2
	add_child(_stage_layer)
	stage = SpaceStage.new()
	_stage_layer.add_child(stage)
	get_viewport().disable_3d = true
	return stage


func close_stage() -> void:
	get_viewport().disable_3d = false
	if _stage_layer and is_instance_valid(_stage_layer):
		_stage_layer.queue_free()
	_stage_layer = null
	stage = null


func caption(t: String) -> void:
	_cap.text = tr(t) if t != "" else t  # [l10n]
	_cap.modulate.a = 0.0
	if t != "":
		_cap.create_tween().tween_property(_cap, "modulate:a", 1.0, 0.5)


func wren(t: String, stage_n: int = 2) -> void:
	if world.get("wren") != null:
		world.wren.line_started.emit(t, stage_n)


func fade_to(a: float, dur: float) -> void:
	_fade.create_tween().tween_property(_fade, "color:a", a, dur)


## Waits s seconds; true if the beat was skipped.
func hold(s: float) -> bool:
	if skipped:
		return true
	await get_tree().create_timer(s).timeout
	return skipped


## Fade out, hand everything back, fade in, free.
func end() -> void:
	if not running:
		return
	running = false
	fade_to(1.0, 0.35)
	await get_tree().create_timer(0.4).timeout
	_restore()
	fade_to(0.0, 0.6)
	for b: ColorRect in _bars:
		b.visible = false
	_cap.visible = false
	_vignette.visible = false
	await get_tree().create_timer(0.65).timeout
	ended.emit()
	queue_free()


func _restore() -> void:
	if _restored:
		return
	_restored = true
	close_stage()
	var modal: bool = world.has_method("any_modal_open") and world.any_modal_open()
	if _prev_cam and is_instance_valid(_prev_cam) and not modal:
		_prev_cam.current = true
	if cam and is_instance_valid(cam):
		cam.queue_free()
	cam = null
	if world.get("hud") != null and not modal:
		world.hud.visible = true
	if world.get("music") != null:
		world.music.set_cinematic(false)
	if not modal:
		_set_player_enabled(true)


func _exit_tree() -> void:
	if running and not _restored:
		_restore()


func _unhandled_input(event: InputEvent) -> void:
	if not running or skipped:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel") \
			or (event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_SPACE):
		get_viewport().set_input_as_handled()
		skipped = true


func _set_player_enabled(on: bool) -> void:
	var patch: Node = world.patch
	if patch.get("input") is PlayerInput:
		(patch.input as PlayerInput).enabled = on
	if world.get("cam") != null:
		world.cam.input_enabled = on
