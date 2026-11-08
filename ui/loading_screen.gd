class_name LoadingScreen
extends CanvasLayer
## [intro2] The loading screen (autoload "Loader"). Covers every scene load: startup, New Game /
## Continue, back to the title, rocket travel between districts and world travel.
## Why: on the owner's Mac build the window showed a flat purple screen and froze before the title.
## The purple was the project's default clear colour (0.55, 0.45, 0.7) showing while the first
## scene loaded and its shaders compiled with nothing drawn yet (the menu's sky and materials
## were still compiling). Now the clear colour and boot splash are near-black, and this screen
## draws from the first frame while:
##   1. the scene loads on a thread (ResourceLoader.load_threaded_request),
##   2. it is instanced (the district builds synchronously in _ready: the bar waits there),
##   3. ShaderWarmup draws every material in the new scene once, off-screen behind this cover,
##      for a few frames so the first gameplay frames neither hitch nor flash,
## then it fades out. The bar: a little red-and-white Pixel Lumi hovers along it, scooping up a
## line of tiny garbage as it fills.
##   Loader.goto("res://scenes/slice.tscn")      # instead of change_scene_to_file
##   Loader.reload()                              # instead of reload_current_scene
##   await Loader.wait_done()                    # e.g. the intro starts once the cover is gone

signal done

const BG := Color(0.018, 0.022, 0.032)
const RED := Color(0.8, 0.15, 0.14)
const RED_DARK := Color(0.55, 0.1, 0.1)
const WHITE := Color(0.95, 0.93, 0.9)
const GLOW := Color(1.0, 0.33, 0.5)
const CREAM := Color(0.95, 0.92, 0.85)
const BAR_W: float = 560.0
const PIECES: int = 15
const MIN_SHOW_S: float = 1.1
const LUMI_SCALE: float = 1.6
const PIECE_SCALE: float = 1.35

var active: bool = false
## Displayed (smoothed) progress 0..1 and the target it eases toward.
var shown: float = 0.0
var target: float = 0.0

var _root: Control
var _canvas: Control
var _status: Label
var _alpha: float = 0.0
var _fading_out: bool = false
var _path: String = ""
var _stage: int = 0  # 0 idle, 1 threaded load, 2 instancing, 3 warm-up, 4 fade out
var _t: float = 0.0
var _shown_ms: int = 0
var _warm: ShaderWarmup
var _pieces: Array[Dictionary] = []
var _flying: Array[Dictionary] = []
var _hopper: int = 0
var _blink: float = 0.0
var _blink_wait: float = 2.0
var _scene_changed: bool = false
var _tip: int = 0
var _vignette: LoadingVignette


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = UITheme.get_theme()
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_bar)
	_root.add_child(_canvas)
	_status = UITheme.label("", 14, Color(CREAM, 0.6))
	_status.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_status.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.offset_top = -120
	_status.offset_bottom = -96
	_root.add_child(_status)
	visible = false
	get_tree().scene_changed.connect(func() -> void: _scene_changed = true)


func busy() -> bool:
	return active


## Resolves once the cover is gone (immediately if nothing is loading).
func wait_done() -> void:
	while active:
		await done


func reload() -> void:
	var cur: Node = get_tree().current_scene
	goto(cur.scene_file_path if cur and cur.scene_file_path != "" else "res://scenes/slice.tscn")


## Load and switch to a scene behind the loading screen.
func goto(path: String) -> void:
	if active and _stage in [1, 2]:
		return
	_path = path
	if _warm:
		_warm.queue_free()
		_warm = null
	var cur: Node = get_tree().current_scene
	if cur and not _is_boot():
		cur.process_mode = Node.PROCESS_MODE_DISABLED  # the old scene stops while it is covered
	active = true
	_fading_out = false
	_stage = 1
	_t = 0.0
	_shown_ms = Time.get_ticks_msec()
	shown = 0.0
	target = 0.03
	_scene_changed = false
	_tip = randi()
	_reset_pieces()
	_ensure_vignette()
	_status.text = _status_text(0)
	visible = true
	if _alpha <= 0.0:
		_alpha = 1.0 if get_tree().current_scene == null or _is_boot() else 0.0
	_apply_alpha()
	var err: int = ResourceLoader.load_threaded_request(path, "PackedScene", true)
	if err != OK:
		push_warning("[loader] threaded request failed for %s (%d), loading directly" % [path, err])
		_stage = 2
	print("[loader] loading %s" % path)


func _is_boot() -> bool:
	var cur: Node = get_tree().current_scene
	return cur != null and cur.scene_file_path == "res://scenes/boot.tscn"


func _status_text(stage: int) -> String:
	match stage:
		0: return tr("Loading")
		1: return tr("Setting the scene")
		2: return tr("Warming up")
	return ""


## [pod2] The 3D street scene above the bar (built on first use; skipped headless).
func _ensure_vignette() -> void:
	if DisplayServer.get_name() == "headless" or DevHooks.has("loader-2d"):
		return
	if _vignette == null:
		_vignette = LoadingVignette.new()
		_vignette.set_anchors_preset(Control.PRESET_CENTER)
		_vignette.offset_left = -480
		_vignette.offset_right = 480
		_vignette.offset_top = -270
		_vignette.offset_bottom = 40
		_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(_vignette)
		_root.move_child(_vignette, 1)  # above the backdrop, under the bar
	else:
		_vignette.reset()


func _apply_alpha() -> void:
	_root.modulate.a = _alpha
	visible = _alpha > 0.001


func _process(delta: float) -> void:
	if not visible and not active:
		return
	var real: float = delta / maxf(Engine.time_scale, 0.0001)  # [intro2] pacing in real seconds
	real = minf(real, 0.1)
	_t += real
	if not _fading_out and _alpha < 1.0:
		_alpha = minf(1.0, _alpha + real / 0.25)
		_apply_alpha()
	match _stage:
		1:
			var prog: Array = []
			var st: int = ResourceLoader.load_threaded_get_status(_path, prog)
			if prog.size() > 0:
				target = maxf(target, 0.04 + 0.5 * float(prog[0]))
			if st == ResourceLoader.THREAD_LOAD_LOADED and _alpha >= 1.0:
				_stage = 2
				target = maxf(target, 0.56)
			elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				push_warning("[loader] threaded load failed for %s, loading directly" % _path)
				_stage = 2
		2:
			# Let the bar reach the "building" mark, draw one frame, then instance (this frame
			# blocks while the new scene's _ready builds everything).
			target = maxf(target, 0.6)
			if shown >= 0.55 or _t > 4.0:
				_status.text = _status_text(1)
				_stage = 5
		5:
			_stage = 6
			var ps: PackedScene = ResourceLoader.load_threaded_get(_path) as PackedScene
			if ps == null:
				ps = load(_path) as PackedScene
			var tree := get_tree()
			tree.paused = false
			if ps:
				tree.change_scene_to_packed(ps)
			else:
				tree.change_scene_to_file(_path)
		6:
			if _scene_changed and get_tree().current_scene != null:
				_stage = 3
				target = maxf(target, 0.72)
				shown = maxf(shown, 0.7)
				_status.text = _status_text(2)
				_warm = ShaderWarmup.new()
				add_child(_warm)
				_warm.start(get_tree().current_scene)
		3:
			var wk: float = _warm.progress() if _warm else 1.0
			target = maxf(target, 0.72 + 0.26 * wk)
			var min_ok: bool = (Time.get_ticks_msec() - _shown_ms) / 1000.0 >= (0.0 if _headless() else MIN_SHOW_S)
			if (_warm == null or _warm.finished()) and min_ok:
				target = 1.0
				if shown >= 0.985 or _headless():
					_stage = 4
					_fading_out = true
					if _warm:
						_warm.queue_free()
						_warm = null
					print("[loader] ready in %d ms" % (Time.get_ticks_msec() - _shown_ms))
		4:
			_alpha = maxf(0.0, _alpha - real / 0.45)
			_apply_alpha()
			if _alpha <= 0.0:
				_stage = 0
				active = false
				_fading_out = false
				done.emit()
	# Smooth, never backwards; a little creep keeps it alive during the blocking steps.
	if shown < target:
		shown = minf(target, shown + maxf((target - shown) * minf(1.0, real * 3.5), real * 0.04))
	_update_lumi(real)
	if _vignette:
		_vignette.progress = shown
		_vignette.set_active(visible)
	_canvas.queue_redraw()


## Headless runs and screenshot tooling skip the minimum show time.
func _headless() -> bool:
	return DisplayServer.get_name() == "headless" or DevHooks.has("shot")


# --- The bar and Pixel Lumi -------------------------------------------------------------

func _reset_pieces() -> void:
	_pieces.clear()
	_flying.clear()
	_hopper = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_usec()
	for i: int in PIECES:
		var u: float = (i + 0.6 + rng.randf_range(-0.2, 0.2)) / (PIECES + 0.4)
		_pieces.append({"u": u, "kind": rng.randi() % 5, "rot": rng.randf_range(-0.6, 0.6),
			"col": [Color(0.55, 0.62, 0.66), Color(0.42, 0.62, 0.45), Color(0.72, 0.6, 0.42), Color(0.3, 0.32, 0.36), Color(0.75, 0.42, 0.3)][rng.randi() % 5],
			"taken": false})


func _bar_rect() -> Rect2:
	var sz: Vector2 = _canvas.size
	return Rect2(Vector2((sz.x - BAR_W) * 0.5, sz.y * 0.5 + 40.0), Vector2(BAR_W, 10.0))


func _lumi_pos() -> Vector2:
	var r: Rect2 = _bar_rect()
	var x: float = r.position.x + r.size.x * shown
	return Vector2(x, r.position.y - 62.0 + sin(_t * 3.2) * 5.0)


func _update_lumi(dt: float) -> void:
	var r: Rect2 = _bar_rect()
	var lx: float = r.position.x + r.size.x * shown
	for p: Dictionary in _pieces:
		if not p["taken"] and r.position.x + r.size.x * float(p["u"]) <= lx + 26.0:
			p["taken"] = true
			_flying.append({"from": Vector2(r.position.x + r.size.x * float(p["u"]), r.position.y - 9.0), "k": 0.0, "piece": p})
	var i: int = _flying.size() - 1
	while i >= 0:
		var f: Dictionary = _flying[i]
		f["k"] = float(f["k"]) + dt * 3.2
		if float(f["k"]) >= 1.0:
			_flying.remove_at(i)
			_hopper += 1
		i -= 1
	_blink_wait -= dt
	if _blink_wait <= 0.0:
		_blink = 0.14
		_blink_wait = randf_range(1.8, 3.6)
	_blink = maxf(0.0, _blink - dt)


func _draw_bar() -> void:
	var c: Control = _canvas
	var r: Rect2 = _bar_rect()
	# Title, small and quiet.
	var font: Font = UITheme.font()
	var title: String = "GREENFALL"
	var tw: float = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	c.draw_string(font, Vector2((c.size.x - tw) * 0.5, r.position.y - (330.0 if _vignette else 120.0)), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(CREAM, 0.85))
	# Track and fill (the cleaned stretch glows faintly pink behind Lumi).
	c.draw_rect(Rect2(r.position - Vector2(2, 2), r.size + Vector2(4, 4)), Color(1, 1, 1, 0.06))
	_round_rect(c, r, Color(0.09, 0.1, 0.13))
	var fill := Rect2(r.position, Vector2(r.size.x * shown, r.size.y))
	if fill.size.x > 1.0:
		_round_rect(c, fill.grow(3.0), Color(GLOW, 0.12))
		_round_rect(c, fill, Color(0.93, 0.9, 0.88))
		_round_rect(c, Rect2(fill.position + Vector2(0, fill.size.y - 3.0), Vector2(fill.size.x, 3.0)), Color(GLOW, 0.75))
	if _vignette:
		# [pod2] The 3D street above the bar shows Lumi and the junk; the bar stays clean.
		var pct3: String = "%d%%" % int(round(shown * 100.0))
		c.draw_string(font, Vector2(r.end.x + 14.0, r.position.y + 10.0), pct3, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(CREAM, 0.45))
		return
	# The line of garbage waiting ahead.
	for p: Dictionary in _pieces:
		if p["taken"]:
			continue
		_draw_piece(c, Vector2(r.position.x + r.size.x * float(p["u"]), r.position.y - 9.0), p, 1.0)
	# Pieces being scooped: an arc up into Lumi's hopper, shrinking.
	var lp: Vector2 = _lumi_pos()
	for f: Dictionary in _flying:
		var k: float = float(f["k"])
		var to: Vector2 = lp + Vector2(-30, -2)
		var pos: Vector2 = (f["from"] as Vector2).lerp(to, k) + Vector2(0, -sin(k * PI) * 26.0)
		_draw_piece(c, pos, f["piece"], 1.0 - k * 0.8)
	_draw_lumi(c, lp)
	# Percent, tiny.
	var pct: String = "%d%%" % int(round(shown * 100.0))
	c.draw_string(font, Vector2(r.end.x + 14.0, r.position.y + 10.0), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(CREAM, 0.45))


func _round_rect(c: Control, r: Rect2, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(minf(r.size.y * 0.5, 8.0)))
	sb.anti_aliasing = true
	c.draw_style_box(sb, r)


func _draw_piece(c: Control, at: Vector2, p: Dictionary, s: float) -> void:
	var col: Color = p["col"]
	c.draw_set_transform(at, float(p["rot"]), Vector2(s, s) * PIECE_SCALE)
	match int(p["kind"]):
		0:  # can
			c.draw_rect(Rect2(-4, -7, 8, 12), col)
			c.draw_rect(Rect2(-4, -7, 8, 2), col.lightened(0.3))
		1:  # bottle
			c.draw_rect(Rect2(-3.5, -5, 7, 11), Color(col, 0.85))
			c.draw_rect(Rect2(-1.5, -9, 3, 4), Color(col, 0.85))
		2:  # box
			c.draw_rect(Rect2(-6, -5, 12, 10), col)
			c.draw_line(Vector2(-6, -1), Vector2(6, -1), col.darkened(0.3), 1.0)
		3:  # tyre
			c.draw_circle(Vector2.ZERO, 6.0, col)
			c.draw_circle(Vector2.ZERO, 2.4, BG)
		_:  # crumpled bag
			c.draw_circle(Vector2(-2, 1), 4.5, col)
			c.draw_circle(Vector2(3, -1), 4.0, col.lightened(0.1))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A tiny Pixel-design Lumi facing right: red shell, white face plate, pink-red glowing C eyes,
## an antenna bulb, a hover glow and a hopper on the back that fills as he scoops.
func _draw_lumi(c: Control, at: Vector2) -> void:
	var tilt: float = sin(_t * 1.7) * 0.05 + 0.08
	# Hover glow on the bar below.
	var r: Rect2 = _bar_rect()
	for k: int in 4:
		c.draw_circle(Vector2(at.x, r.position.y - 3.0), 22.0 - k * 5.0, Color(GLOW, 0.05 + k * 0.03))
	c.draw_set_transform(at, tilt, Vector2(LUMI_SCALE, LUMI_SCALE))
	# Thruster wisp.
	c.draw_circle(Vector2(0, 21), 5.0, Color(GLOW, 0.35))
	c.draw_circle(Vector2(0, 21), 2.5, Color(1.0, 0.8, 0.85, 0.8))
	# Hopper on the back (fills with scooped bits).
	var fillk: float = clampf(float(_hopper) / PIECES, 0.0, 1.0)
	c.draw_rect(Rect2(-24, -8, 10, 20), RED_DARK)
	c.draw_rect(Rect2(-23, 11 - 18.0 * fillk, 8, 18.0 * fillk), Color(0.6, 0.58, 0.5))
	# Body shell.
	var body := StyleBoxFlat.new()
	body.bg_color = RED
	body.set_corner_radius_all(14)
	body.anti_aliasing = true
	body.shadow_color = Color(0, 0, 0, 0.35)
	body.shadow_size = 4
	c.draw_style_box(body, Rect2(-18, -16, 36, 34))
	# White belly band and face plate.
	c.draw_rect(Rect2(-18, 8, 36, 4), WHITE)
	var face := StyleBoxFlat.new()
	face.bg_color = Color(0.1, 0.08, 0.1)
	face.set_corner_radius_all(9)
	face.border_color = WHITE
	face.set_border_width_all(2)
	face.anti_aliasing = true
	c.draw_style_box(face, Rect2(-8, -11, 24, 16))
	# Eyes: glowing C shapes, briefly flat when blinking.
	for ex: float in [0.0, 9.0]:
		var e := Vector2(ex, -3.0)
		c.draw_circle(e, 5.0, Color(GLOW, 0.18))
		if _blink > 0.0:
			c.draw_line(e + Vector2(-2.5, 0), e + Vector2(2.5, 0), GLOW, 2.0)
		else:
			c.draw_arc(e, 2.6, PI * 0.35, TAU - PI * 0.35, 12, Color(1.0, 0.5, 0.65), 2.2, true)
	# Antenna with a pink bulb.
	c.draw_line(Vector2(2, -16), Vector2(5, -25), WHITE, 2.0)
	var pulse: float = 0.6 + 0.4 * sin(_t * 5.0)
	c.draw_circle(Vector2(5, -26), 4.5, Color(GLOW, 0.25 * pulse))
	c.draw_circle(Vector2(5, -26), 2.5, Color(1.0, 0.55, 0.7))
	# A little scoop arm reaching down-forward.
	var reach: float = 0.5 + 0.5 * sin(_t * 6.0)
	c.draw_line(Vector2(14, 10), Vector2(20, 18 + reach * 3.0), WHITE, 3.0)
	c.draw_circle(Vector2(20, 18 + reach * 3.0), 2.5, GLOW)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
