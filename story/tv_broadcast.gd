class_name TvBroadcast
extends Node
## [eggs2] "Still Broadcasting" (egg "tv"): adjusting the antenna tunes in the last news broadcast
## from Old Town, a loop of simple stylised frames drawn here (no image files) with one caption
## each: the green city before, the Ledger's rigs arriving, the system strip-mined and buried in
## trash, the evacuation to the Cradle, the empty city ("WE'LL BE BACK"), then static. The picture
## renders into a SubViewport that is shown both on the TV's screen and in a close-up overlay with
## a readable caption. E / Esc closes it; it can be watched again any time.

signal finished

const W: int = 320
const H: int = 240
const FRAME_S: float = 3.6
const STATIC_S: float = 0.35

## Captions are English data (tr() at display time). "kind" picks the drawing.
const FRAMES: Array[Dictionary] = [
	{"kind": "green", "caption": "OLD TOWN IN BLOOM: SEED SWAP THIS SATURDAY"},
	{"kind": "rigs", "caption": "LEDGER SECURES EXTRACTION RIGHTS"},
	{"kind": "trash", "caption": "THE SYSTEM IS STRIP-MINED. THE WASTE STAYS HERE"},
	{"kind": "evac", "caption": "EVACUATION: ALL RESIDENTS TO THE CRADLE"},
	{"kind": "empty", "caption": "OLD TOWN, TONIGHT. A SIGN ON THE TOWN HALL"},
	{"kind": "static", "caption": "SIGNAL LOST"},
]

var world: Node
var screen: MeshInstance3D  # the TV's screen quad (shows the same picture)
var viewport: SubViewport
var picture: Control
var frame: int = 0
var _t: float = 0.0
var _static_t: float = STATIC_S
var _hold: int = -1  # dev: hold one frame (--tv-frame=N)
var _wall_step: float = 0.0  # dev: advance by wall clock every S s (--tv-step=S), for slow renders
var _wall0: int = 0
var _layer: CanvasLayer
var _caption: Label
var _old_mat: Material
var _done: bool = false


static func caption(i: int) -> String:
	return str(FRAMES[clampi(i, 0, FRAMES.size() - 1)]["caption"])


func start() -> void:
	_hold = int(DevHooks.get_f("tv-frame", -1.0)) if DevHooks.has("tv-frame") else -1
	_wall_step = DevHooks.get_f("tv-step", 0.0) if DevHooks.has("tv-step") else 0.0
	_wall0 = Time.get_ticks_msec()
	viewport = SubViewport.new()
	viewport.size = Vector2i(W, H)
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	picture = _Picture.new()
	picture.set("tv", self)
	picture.size = Vector2(W, H)
	viewport.add_child(picture)
	var tex: ViewportTexture = viewport.get_texture()
	if screen:
		_old_mat = screen.material_override
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = tex
		m.albedo_color = Color(0.9, 0.9, 0.9)
		screen.material_override = m
	_build_overlay(tex)
	_lock(true)
	frame = maxi(_hold, 0)
	_static_t = STATIC_S
	_update_caption()


func _build_overlay(tex: Texture2D) -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 21
	add_child(_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	_layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	# A chunky old set: a dark plastic bezel round the picture.
	var bezel := PanelContainer.new()
	bezel.add_theme_stylebox_override("panel", UITheme.box(Color(0.11, 0.1, 0.09), Color(0.3, 0.27, 0.22), 2, 18, 18))
	center.add_child(bezel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	bezel.add_child(vb)
	var top := UITheme.label(tr("CH 4  ·  OLD TOWN NEWS  ·  LAST BROADCAST"), 13, Color(0.75, 0.72, 0.65))
	vb.add_child(top)
	var tr_ := TextureRect.new()
	tr_.texture = tex
	tr_.custom_minimum_size = Vector2(W, H) * 2.0
	tr_.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr_.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr_.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	vb.add_child(tr_)
	_caption = UITheme.label("", 22, Color(0.98, 0.96, 0.9))
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.custom_minimum_size = Vector2(W * 2.0, 0)
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(_caption)
	var hint := PromptLabel.new(tr("{interact}  [k]/ Esc  [/k]turn it off"), 13, Color(0.6, 0.58, 0.52))
	vb.add_child(hint)


func _update_caption() -> void:
	if _caption:
		_caption.text = tr(caption(frame))


func close() -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(screen):
		screen.material_override = _old_mat
	_lock(false)
	finished.emit()
	queue_free()


func _exit_tree() -> void:
	if not _done:
		_done = true
		if is_instance_valid(screen):
			screen.material_override = _old_mat
		_lock(false)


func _unhandled_input(event: InputEvent) -> void:
	if _t > 0.5 and (event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		close()


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_static_t = maxf(0.0, _static_t - delta)
	var want: int = frame
	if _hold >= 0:
		want = _hold
	elif _wall_step > 0.0:
		want = mini(int((Time.get_ticks_msec() - _wall0) / 1000.0 / _wall_step), FRAMES.size() - 1)
	elif _t >= FRAME_S * (frame + 1):
		want = frame + 1
	if want != frame:
		if want >= FRAMES.size():
			close()
			return
		frame = want
		_static_t = STATIC_S
		_update_caption()
		Audio.play("tv_static", randf_range(0.9, 1.2), -12.0)
	picture.queue_redraw()


func _lock(on: bool) -> void:
	if world == null:
		return
	if world.get("patch") != null and world.patch and world.patch.input is PlayerInput:
		(world.patch.input as PlayerInput).enabled = not on
	if world.get("cam") != null and world.cam:
		world.cam.input_enabled = not on


## The picture: stylised shapes, scanlines, a little snow; a burst of static between frames.
class _Picture extends Control:
	const BUNTING: Array[Color] = [Color(0.95, 0.4, 0.35), Color(0.95, 0.8, 0.3), Color(0.4, 0.7, 0.95)]
	var tv: TvBroadcast
	var rng := RandomNumberGenerator.new()

	func _draw() -> void:
		if tv == null:
			return
		var t: float = tv._t
		var kind: String = str(TvBroadcast.FRAMES[tv.frame]["kind"])
		if kind == "static" or tv._static_t > 0.0:
			_snow(1.0)
			if kind == "static":
				_text(tr("SIGNAL LOST"), Vector2(160, 122), 18, Color(1, 1, 1, 0.85))
			return
		match kind:
			"green": _green(t)
			"rigs": _rigs(t)
			"trash": _trash(t)
			"evac": _evac(t)
			"empty": _empty(t)
		_lower_third(tr(TvBroadcast.caption(tv.frame)))
		_text(tr("LIVE"), Vector2(286, 18), 10, Color(1.0, 0.35, 0.3))
		# Scanlines and a light glitch band now and then (the caption stays readable).
		for y: int in range(0, 240, 3):
			draw_rect(Rect2(0, y, 320, 1), Color(0, 0, 0, 0.12))
		if fmod(t, 2.3) < 0.12:
			var gy: float = fmod(t * 97.0, 170.0)
			draw_rect(Rect2(0, gy, 320, 6), Color(1, 1, 1, 0.12))
		_snow(0.12)

	# --- helpers ---
	func _sky(top: Color, bottom: Color, horizon: float = 170.0) -> void:
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(320, 0), Vector2(320, horizon), Vector2(0, horizon)]),
			PackedColorArray([top, top, bottom, bottom]))

	func _suns(a: Vector2, b: Vector2, col_a: Color, col_b: Color) -> void:
		# The two suns of the system: a big gold one and a small orange companion.
		draw_circle(a, 16.0, Color(col_a, 0.25))
		draw_circle(a, 11.0, col_a)
		draw_circle(b, 8.0, Color(col_b, 0.25))
		draw_circle(b, 5.0, col_b)

	func _skyline(base: float, col: Color, seed_: int, windows: Color = Color(0, 0, 0, 0)) -> void:
		rng.seed = seed_
		var x: float = -4.0
		while x < 320.0:
			var w: float = rng.randf_range(22, 44)
			var h: float = rng.randf_range(40, 95)
			draw_rect(Rect2(x, base - h, w - 3, h), col)
			if windows.a > 0.0:
				for wy: int in range(int(base - h + 8), int(base - 8), 12):
					for wx: int in range(int(x + 5), int(x + w - 8), 9):
						if rng.randf() < 0.6:
							draw_rect(Rect2(wx, wy, 4, 5), windows)
			x += w

	func _ground(y: float, col: Color) -> void:
		draw_rect(Rect2(0, y, 320, 240 - y), col)

	func _tree(p: Vector2, s: float, leaf: Color) -> void:
		draw_rect(Rect2(p.x - 2, p.y - 14 * s, 4, 14 * s), Color(0.4, 0.28, 0.18))
		draw_circle(p + Vector2(0, -18 * s), 9.0 * s, leaf)
		draw_circle(p + Vector2(-6 * s, -14 * s), 6.0 * s, leaf.darkened(0.1))
		draw_circle(p + Vector2(6 * s, -14 * s), 6.0 * s, leaf.lightened(0.08))

	func _heap(cx: float, base: float, w: float, h: float, seed_: int) -> void:
		rng.seed = seed_
		var pts := PackedVector2Array()
		for k: int in 9:
			var a: float = PI * k / 8.0
			pts.append(Vector2(cx - cos(a) * w * 0.5, base - sin(a) * h * rng.randf_range(0.75, 1.1)))
		draw_colored_polygon(pts, Color(0.32, 0.27, 0.22))
		for k: int in 26:
			var px: float = cx + rng.randf_range(-0.42, 0.42) * w
			var top: float = base - h * sin(acos(clampf((px - cx) / (w * 0.5), -1.0, 1.0)))
			var py: float = rng.randf_range(top, base - 3)
			var cols: Array[Color] = [Color(0.8, 0.76, 0.66), Color(0.55, 0.6, 0.65), Color(0.7, 0.35, 0.25), Color(0.25, 0.4, 0.6), Color(0.6, 0.55, 0.3)]
			draw_rect(Rect2(px, py, rng.randf_range(3, 8), rng.randf_range(2, 5)), cols[k % cols.size()])

	func _lower_third(text: String) -> void:
		draw_rect(Rect2(0, 196, 320, 30), Color(0.05, 0.1, 0.25, 0.88))
		draw_rect(Rect2(0, 196, 320, 2), Color(0.95, 0.75, 0.25))
		_text(text, Vector2(160, 216), 11, Color(1, 1, 1))

	func _text(s: String, center: Vector2, size: int, col: Color) -> void:
		var f: Font = get_theme_default_font()
		var w: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var sz: int = size
		while w > 304.0 and sz > 7:
			sz -= 1
			w = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		draw_string(f, Vector2(center.x - w * 0.5, center.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)

	func _snow(amount: float) -> void:
		rng.seed = int(tv._t * 30.0) * 7919 + 13
		if amount >= 1.0:
			draw_rect(Rect2(0, 0, 320, 240), Color(0.2, 0.2, 0.22))
		for k: int in int(900 * amount):
			var g: float = rng.randf()
			draw_rect(Rect2(rng.randf() * 320.0, rng.randf() * 240.0, rng.randf_range(1, 3), 1), Color(g, g, g, 0.8 if amount >= 1.0 else 0.35))

	# --- frames ---
	func _green(t: float) -> void:
		_sky(Color(0.35, 0.62, 0.95), Color(0.75, 0.88, 0.98))
		_suns(Vector2(70, 46), Vector2(104, 64), Color(1.0, 0.93, 0.55), Color(1.0, 0.6, 0.35))
		_skyline(170, Color(0.86, 0.8, 0.7), 11, Color(0.45, 0.6, 0.75))
		_ground(170, Color(0.36, 0.62, 0.3))
		draw_rect(Rect2(0, 182, 320, 10), Color(0.55, 0.55, 0.52))
		for k: int in 7:
			_tree(Vector2(20 + k * 48, 178), 1.1, Color(0.25, 0.6, 0.28))
		for k: int in 6:  # bunting
			var x: float = 30 + k * 46
			var flag: Color = BUNTING[k % 3]
			draw_colored_polygon(PackedVector2Array([Vector2(x, 96), Vector2(x + 10, 96), Vector2(x + 5, 104)]), flag)
		draw_line(Vector2(20, 95), Vector2(300, 97), Color(0.3, 0.3, 0.3), 1.0)
		for k: int in 5:  # people strolling
			var px: float = fmod(40.0 + k * 60.0 + t * 8.0, 320.0)
			var coat: Color = BUNTING[(k + 1) % 3]
			draw_rect(Rect2(px, 183, 3, 7), coat)
			draw_circle(Vector2(px + 1.5, 181), 2.0, Color(0.95, 0.78, 0.62))

	func _rigs(t: float) -> void:
		_sky(Color(0.55, 0.5, 0.48), Color(0.85, 0.66, 0.45))
		_suns(Vector2(250, 40), Vector2(276, 58), Color(1.0, 0.85, 0.55), Color(1.0, 0.55, 0.3))
		_skyline(170, Color(0.66, 0.6, 0.55), 11, Color(0.5, 0.55, 0.6))
		_ground(170, Color(0.42, 0.5, 0.3))
		# Ledger mining rigs lowering in on cables: dark hulls with red eyes and drill legs.
		for k: int in 3:
			var cx: float = 60.0 + k * 100.0
			var y: float = minf(40.0 + k * 10.0 + t * 6.0, 92.0 + k * 6.0)
			draw_colored_polygon(PackedVector2Array([Vector2(cx - 36, y), Vector2(cx + 36, y), Vector2(cx + 24, y + 26), Vector2(cx - 24, y + 26)]), Color(0.16, 0.17, 0.2))
			draw_rect(Rect2(cx - 14, y - 10, 28, 10), Color(0.22, 0.23, 0.26))
			draw_line(Vector2(cx - 18, y + 26), Vector2(cx - 26, y + 70), Color(0.2, 0.2, 0.22), 3.0)
			draw_line(Vector2(cx + 18, y + 26), Vector2(cx + 26, y + 70), Color(0.2, 0.2, 0.22), 3.0)
			draw_colored_polygon(PackedVector2Array([Vector2(cx - 6, y + 26), Vector2(cx + 6, y + 26), Vector2(cx, y + 62)]), Color(0.35, 0.33, 0.3))
			draw_circle(Vector2(cx, y + 12), 3.0, Color(1.0, 0.2, 0.15) if fmod(t + k * 0.3, 1.0) < 0.6 else Color(0.5, 0.1, 0.08))
			draw_line(Vector2(cx, 0), Vector2(cx, y - 10), Color(0.15, 0.15, 0.17), 1.0)
		# The Ledger's mark: a ruled square.
		draw_rect(Rect2(14, 14, 26, 26), Color(0.9, 0.9, 0.88), false, 2.0)
		for k: int in 3:
			draw_line(Vector2(18, 21 + k * 6), Vector2(36, 21 + k * 6), Color(0.9, 0.9, 0.88), 1.5)
		_text(tr("BREAKING"), Vector2(160, 186), 12, Color(1.0, 0.85, 0.3))

	func _trash(t: float) -> void:
		_sky(Color(0.48, 0.42, 0.36), Color(0.72, 0.6, 0.45))
		_suns(Vector2(80, 50), Vector2(104, 66), Color(0.95, 0.8, 0.55, 0.7), Color(0.95, 0.55, 0.35, 0.7))
		_skyline(160, Color(0.45, 0.42, 0.4), 23)
		_ground(160, Color(0.38, 0.33, 0.28))
		_heap(70, 196, 150, 50, 3)
		_heap(220, 196, 190, 64, 5)
		_heap(150, 200, 110, 34, 9)
		# Strip-mine terraces on the far hill and a haul conveyor spilling waste.
		for k: int in 4:
			draw_rect(Rect2(200 + k * 10, 120 + k * 9, 120 - k * 10, 3), Color(0.55, 0.45, 0.35))
		draw_line(Vector2(330, 70), Vector2(240, 128), Color(0.2, 0.2, 0.22), 4.0)
		var fall: float = fmod(t * 40.0, 60.0)
		draw_rect(Rect2(238, 128 + fall, 5, 4), Color(0.7, 0.6, 0.45))
		draw_rect(Rect2(244, 128 + fmod(fall + 30.0, 60.0), 4, 3), Color(0.5, 0.55, 0.6))
		# Haze.
		draw_rect(Rect2(0, 0, 320, 196), Color(0.75, 0.62, 0.45, 0.18))

	func _evac(t: float) -> void:
		_sky(Color(0.12, 0.14, 0.3), Color(0.85, 0.5, 0.35))
		_suns(Vector2(60, 160), Vector2(90, 166), Color(1.0, 0.6, 0.35), Color(1.0, 0.4, 0.25))
		# The Cradle: a long ark high above, its lights on.
		var ark_y: float = 34.0
		draw_colored_polygon(PackedVector2Array([Vector2(120, ark_y), Vector2(300, ark_y - 4), Vector2(312, ark_y + 6), Vector2(296, ark_y + 16), Vector2(118, ark_y + 14), Vector2(108, ark_y + 7)]), Color(0.82, 0.84, 0.88))
		for k: int in 12:
			draw_rect(Rect2(128 + k * 14, ark_y + 6, 6, 2), Color(1.0, 0.9, 0.5))
		_text(tr("CRADLE"), Vector2(210, ark_y + 30), 9, Color(0.9, 0.92, 1.0, 0.8))
		_skyline(180, Color(0.18, 0.17, 0.22), 11, Color(1.0, 0.85, 0.5, 0.8))
		_ground(180, Color(0.15, 0.14, 0.16))
		# Shuttles rising toward it on bright trails.
		for k: int in 4:
			var u: float = fmod(t * 0.22 + k * 0.25, 1.0)
			var p: Vector2 = Vector2(40.0 + k * 70.0, 178.0).lerp(Vector2(150.0 + k * 40.0, ark_y + 20.0), u)
			draw_line(p, p + Vector2(-8, 40) * (0.5 + u), Color(1.0, 0.8, 0.5, 0.6), 2.0)
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -7), p + Vector2(3, 3), p + Vector2(-3, 3)]), Color(0.95, 0.95, 0.98))

	func _empty(t: float) -> void:
		_sky(Color(0.5, 0.5, 0.52), Color(0.7, 0.66, 0.6))
		_suns(Vector2(270, 54), Vector2(292, 70), Color(0.95, 0.85, 0.65, 0.6), Color(0.95, 0.6, 0.4, 0.6))
		_skyline(176, Color(0.55, 0.52, 0.5), 11)
		# The town hall with a hand-painted banner.
		draw_rect(Rect2(90, 90, 140, 86), Color(0.62, 0.57, 0.52))
		draw_colored_polygon(PackedVector2Array([Vector2(84, 90), Vector2(236, 90), Vector2(160, 64)]), Color(0.5, 0.45, 0.42))
		for k: int in 5:
			draw_rect(Rect2(100 + k * 26, 140, 10, 36), Color(0.35, 0.32, 0.3))
		draw_rect(Rect2(100, 100, 120, 30), Color(0.93, 0.9, 0.82))
		var sway: float = sin(t * 1.2) * 1.0
		_text(tr("WE'LL BE BACK"), Vector2(160, 120 + sway), 16, Color(0.75, 0.2, 0.15))
		_ground(176, Color(0.42, 0.38, 0.33))
		_heap(40, 200, 90, 22, 13)
		_heap(270, 202, 110, 28, 17)
		# A lone cleanup bot, still sweeping.
		var bx: float = 150.0 + sin(t * 0.6) * 30.0
		draw_rect(Rect2(bx - 6, 186, 12, 9), Color(0.85, 0.85, 0.8))
		draw_circle(Vector2(bx, 185), 5.0, Color(0.85, 0.85, 0.8))
		draw_circle(Vector2(bx + 2, 184), 1.6, Color(0.3, 0.8, 1.0))
