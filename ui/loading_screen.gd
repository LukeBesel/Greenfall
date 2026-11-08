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
##   2. it is instanced; [leftovers] the district builds across frames (a BuildBudget is open:
##      systems/build_budget.gd), the bar shows its real progress and Lumi keeps moving,
##   3. ShaderWarmup draws every material in the new scene once, off-screen behind this cover,
##      for a few frames so the first gameplay frames neither hitch nor flash,
## then it fades out. [v1menu] The picture (owner, 2026-11-08: "simple, clean, continuous"): a
## night sky with a small round Verdance in the middle, red Pixel Lumi orbiting it, and a thin
## progress ring around the planet. All 2D on this canvas (the 3D LoadingVignette, whose Lumi
## showed two sets of eyes, is dormant); animation steps are capped per frame so a long build
## slice slows the orbit for a frame instead of making it jump.
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
const TITLE_TOP: float = 28.0  # [qafix] px between the screen top and the title's cap line
const MIN_SHOW_S: float = 1.1
const LUMI_SCALE: float = 1.6
const ANIM_DT_MAX: float = 1.0 / 30.0  # [v1menu] most animation per frame: no jumps after a stall
const PLANET_R: float = 64.0
const RING_R: float = 92.0
const ORBIT := Vector2(170.0, 52.0)  # Lumi's orbit radii (an ellipse seen from slightly above)
const SKY_TOP := Color(0.02, 0.03, 0.07)
const SKY_BOTTOM := Color(0.06, 0.05, 0.11)
const SEA := Color(0.1, 0.36, 0.42)
const LAND := Color(0.36, 0.6, 0.3)
const ATMO := Color(0.55, 0.85, 1.0)

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
var _stars: PackedVector3Array = PackedVector3Array()  # x, y in 0..1 of the screen; z = phase
var _orbit_a: float = 0.0
var _blink: float = 0.0
var _blink_wait: float = 2.0
var _scene_changed: bool = false
var _tip: int = 0
var _vignette: LoadingVignette
## Longest gap between two loader frames during this load (ms), and when the last frame ran.
var max_stall_ms: float = 0.0
var _stall_stage: int = 0
var _last_frame_us: int = 0
var _build_frames: int = -1
var _build_still: int = 0


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
	max_stall_ms = 0.0
	_last_frame_us = 0
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
	if DisplayServer.get_name() == "headless" or DevHooks.has("loader-2d") or not DevHooks.has("loader-3d"):
		return  # [v1menu] dormant: the 2D orbit picture is the loading screen (--loader-3d for the old one)
	if _vignette == null:
		_vignette = LoadingVignette.new()
		_vignette.set_anchors_preset(Control.PRESET_CENTER)
		_vignette.offset_left = -560
		_vignette.offset_right = 560
		_vignette.offset_top = -300
		_vignette.offset_bottom = 60
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
	if active:
		var now_us: int = Time.get_ticks_usec()
		if _last_frame_us > 0:
			if (now_us - _last_frame_us) / 1000.0 > max_stall_ms:
				max_stall_ms = (now_us - _last_frame_us) / 1000.0
				_stall_stage = _stage
		_last_frame_us = now_us
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
				target = maxf(target, 0.04 + 0.14 * float(prog[0]))
			if st == ResourceLoader.THREAD_LOAD_LOADED and _alpha >= 1.0:
				_stage = 2
				target = maxf(target, 0.18)
			elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				push_warning("[loader] threaded load failed for %s, loading directly" % _path)
				_stage = 2
		2:
			# Let the bar reach the "building" mark, draw one frame, then instance (this frame
			# blocks while the new scene's _ready builds everything).
			target = maxf(target, 0.2)
			if shown >= 0.18 or _t > 4.0:
				_status.text = _status_text(1)
				_stage = 5
		5:
			_stage = 6
			var ps: PackedScene = ResourceLoader.load_threaded_get(_path) as PackedScene
			if ps == null:
				ps = load(_path) as PackedScene
			var tree := get_tree()
			tree.paused = false
			BuildBudget.begin(tree)  # [leftovers] the new scene may build across frames
			_build_frames = -1
			_build_still = 0
			if ps:
				tree.change_scene_to_packed(ps)
			else:
				tree.change_scene_to_file(_path)
		6:
			if _scene_changed and get_tree().current_scene != null and _still_building():
				target = maxf(target, 0.2 + 0.65 * BuildBudget.current.progress())
			elif _scene_changed and get_tree().current_scene != null:
				BuildBudget.end()
				_stage = 3
				target = maxf(target, 0.86)
				_status.text = _status_text(2)
				_warm = ShaderWarmup.new()
				add_child(_warm)
				_warm.start(get_tree().current_scene)
		3:
			var wk: float = _warm.progress() if _warm else 1.0
			target = maxf(target, 0.86 + 0.12 * wk)
			var min_ok: bool = (Time.get_ticks_msec() - _shown_ms) / 1000.0 >= (0.0 if _headless() else MIN_SHOW_S)
			if (_warm == null or _warm.finished()) and min_ok:
				target = 1.0
				if shown >= 0.985 or _headless():
					_stage = 4
					_fading_out = true
					if _warm:
						_warm.queue_free()
						_warm = null
					print("[loader] ready in %d ms, longest frame %.0f ms (ending in stage %s) (%s)" % [Time.get_ticks_msec() - _shown_ms, max_stall_ms, ["idle", "load", "pre-build", "warm-up", "fade", "switch", "build"][_stall_stage], _path])
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
	_update_lumi(minf(real, ANIM_DT_MAX))
	if _vignette:
		_vignette.progress = shown
		_vignette.set_active(visible)
	_canvas.queue_redraw()
	if active and DevHooks.has("loader-shot") and _path.ends_with("slice.tscn"):
		_dev_shot()


## [v1menu] --loader-shot=PREFIX: saves PREFIX_1.png .. _3.png while the game scene loads (renders).
var _shots: int = 0
func _dev_shot() -> void:
	if _shots >= 3 or _t < 0.6 + _shots * 1.2:
		return
	_shots += 1
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s_%d.png" % [DevHooks.get_s("loader-shot", "screenshots/loader"), _shots])
	print("[loader] shot %d at %.1fs (stage %d)" % [_shots, _t, _stage])


## [leftovers] The new scene is still building across frames (scenes/slice.gd `building`). A
## build coroutine stopped by a script error would never finish: after 60 loader frames with
## no build frame, carry on with what exists.
func _still_building() -> bool:
	var sc: Node = get_tree().current_scene
	if BuildBudget.current == null or sc.get("building") != true:
		return false
	if BuildBudget.current.frames == _build_frames:
		_build_still += 1
		if _build_still > 60:
			push_error("[loader] the scene stopped building; showing it as it is")
			return false
	else:
		_build_frames = BuildBudget.current.frames
		_build_still = 0
	return true


## Headless runs and screenshot tooling skip the minimum show time.
func _headless() -> bool:
	return DisplayServer.get_name() == "headless" or DevHooks.has("shot")


# --- [v1menu] The picture: night sky, round Verdance, orbiting Lumi, progress ring ----------

func _reset_pieces() -> void:
	if _stars.size() > 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i: int in 90:
		_stars.append(Vector3(rng.randf(), rng.randf(), rng.randf() * TAU))


func _centre() -> Vector2:
	return _canvas.size * Vector2(0.5, 0.46)


func _update_lumi(dt: float) -> void:
	_orbit_a = fmod(_orbit_a + dt * 0.9, TAU)
	_blink_wait -= dt
	if _blink_wait <= 0.0:
		_blink = 0.14
		_blink_wait = randf_range(1.8, 3.6)
	_blink = maxf(0.0, _blink - dt)


func _draw_bar() -> void:
	var c: Control = _canvas
	var sz: Vector2 = c.size
	var ctr: Vector2 = _centre()
	# Sky: a soft vertical gradient and slowly twinkling stars.
	c.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(sz.x, 0), sz, Vector2(0, sz.y)]),
		PackedColorArray([SKY_TOP, SKY_TOP, SKY_BOTTOM, SKY_BOTTOM]))
	for st: Vector3 in _stars:
		var tw: float = 0.35 + 0.3 * sin(_t * 1.3 + st.z)
		c.draw_circle(Vector2(st.x * sz.x, st.y * sz.y), 0.6 + fmod(st.z, 1.0), Color(CREAM, tw * 0.55))
	# Lumi behind the planet first (the far half of the orbit).
	var lp: Vector2 = ctr + Vector2(cos(_orbit_a) * ORBIT.x, sin(_orbit_a) * ORBIT.y)
	var front: bool = sin(_orbit_a) > 0.0
	var depth: float = 0.5 + 0.5 * sin(_orbit_a)  # 0 far .. 1 near
	if not front:
		_draw_trail(c, ctr)
		_draw_lumi(c, lp, depth)
	_draw_planet(c, ctr)
	# Progress ring around the planet.
	c.draw_arc(ctr, RING_R, 0.0, TAU, 96, Color(1, 1, 1, 0.07), 3.0, true)
	if shown > 0.002:
		c.draw_arc(ctr, RING_R, -PI * 0.5, -PI * 0.5 + TAU * shown, maxi(8, int(96 * shown)), Color(GLOW, 0.22), 7.0, true)
		c.draw_arc(ctr, RING_R, -PI * 0.5, -PI * 0.5 + TAU * shown, maxi(8, int(96 * shown)), Color(0.96, 0.9, 0.9), 2.5, true)
	if front:
		_draw_trail(c, ctr)
		_draw_lumi(c, lp, depth)
	var font: Font = UITheme.font()
	var title: String = "GREENFALL"
	var tw2: float = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	var ty: float = maxf(ctr.y - RING_R - 90.0, TITLE_TOP + font.get_ascent(30))
	c.draw_string(font, Vector2((sz.x - tw2) * 0.5, ty), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(CREAM, 0.85))
	var pct: String = "%d%%" % int(round(shown * 100.0))
	var pw: float = font.get_string_size(pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	c.draw_string(font, Vector2((sz.x - pw) * 0.5, ctr.y + RING_R + ORBIT.y * 0.2 + 40.0), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(CREAM, 0.5))


## A small round Verdance: sea, a few green lands, a lit side and a soft atmosphere rim.
func _draw_planet(c: Control, ctr: Vector2) -> void:
	for k: int in 6:
		c.draw_circle(ctr, PLANET_R + 34.0 - k * 6.0, Color(ATMO, 0.012 + k * 0.006))
	c.draw_circle(ctr, PLANET_R, SEA)
	var spin: float = _t * 0.12  # the lands drift slowly round
	for i: int in 7:
		var a: float = spin + i * 2.4
		var lat: float = sin(i * 1.7) * 0.7
		var x: float = sin(a) * cos(lat)
		if cos(a) < 0.0:
			continue  # on the far side
		var p: Vector2 = ctr + Vector2(x, lat * 0.9) * PLANET_R * 0.78
		var r: float = PLANET_R * (0.16 + 0.07 * sin(i * 3.1)) * (0.55 + 0.45 * cos(a))
		c.draw_circle(p, r, Color(LAND, 0.92))
		c.draw_circle(p + Vector2(r * 0.4, -r * 0.2), r * 0.6, LAND.lightened(0.08))
	# Night side: dark crescents stacked towards the lower right.
	for k: int in 5:
		var off: float = PLANET_R * (0.32 + k * 0.12)
		c.draw_arc(ctr + Vector2(off, off) * 0.28, PLANET_R - off * 0.42, -0.4, PI * 0.95, 32, Color(0.0, 0.01, 0.04, 0.16), off * 0.55, true)
	c.draw_circle(ctr + Vector2(-PLANET_R * 0.38, -PLANET_R * 0.42), PLANET_R * 0.22, Color(1, 1, 1, 0.05))
	c.draw_arc(ctr, PLANET_R + 1.5, 0.0, TAU, 72, Color(ATMO, 0.45), 2.0, true)


## A fading wisp along the orbit behind Lumi.
func _draw_trail(c: Control, ctr: Vector2) -> void:
	for k: int in 10:
		var a: float = _orbit_a - (k + 1) * 0.07
		var p: Vector2 = ctr + Vector2(cos(a) * ORBIT.x, sin(a) * ORBIT.y)
		var d: float = 0.5 + 0.5 * sin(a)
		c.draw_circle(p, (3.2 - k * 0.25) * (0.7 + 0.5 * d), Color(GLOW, 0.22 * (1.0 - k / 10.0)))


## A tiny Pixel-design Lumi: red shell, white face plate, pink-red glowing C eyes, an antenna bulb
## and a thruster wisp. `depth` 0 (far side of the orbit, smaller and dimmer) .. 1 (near).
func _draw_lumi(c: Control, at: Vector2, depth: float = 1.0) -> void:
	var dir: float = -1.0 if sin(_orbit_a) > 0.0 else 1.0  # faces the way he flies
	var s: float = LUMI_SCALE * (0.62 + 0.38 * depth)
	at.y += sin(_t * 3.2) * 3.0
	var tilt: float = sin(_t * 1.7) * 0.05 + 0.08 * dir
	c.draw_set_transform(at, tilt, Vector2(s * dir, s))
	var dim: Color = Color(1, 1, 1).lerp(Color(0.55, 0.55, 0.7), 1.0 - depth)
	c.draw_circle(Vector2(-20, 6), 6.0, Color(GLOW, 0.3))
	c.draw_circle(Vector2(-20, 6), 3.0, Color(1.0, 0.8, 0.85, 0.8))
	var body := StyleBoxFlat.new()
	body.bg_color = RED * dim
	body.set_corner_radius_all(14)
	body.anti_aliasing = true
	body.shadow_color = Color(0, 0, 0, 0.35)
	body.shadow_size = 4
	c.draw_style_box(body, Rect2(-18, -16, 36, 34))
	c.draw_rect(Rect2(-18, 8, 36, 4), WHITE * dim)
	var face := StyleBoxFlat.new()
	face.bg_color = Color(0.1, 0.08, 0.1)
	face.set_corner_radius_all(9)
	face.border_color = WHITE * dim
	face.set_border_width_all(2)
	face.anti_aliasing = true
	c.draw_style_box(face, Rect2(-8, -11, 24, 16))
	for ex: float in [0.0, 9.0]:  # one pair of eyes
		var e := Vector2(ex, -3.0)
		c.draw_circle(e, 5.0, Color(GLOW, 0.18))
		if _blink > 0.0:
			c.draw_line(e + Vector2(-2.5, 0), e + Vector2(2.5, 0), GLOW, 2.0)
		else:
			c.draw_arc(e, 2.6, PI * 0.35, TAU - PI * 0.35, 12, Color(1.0, 0.5, 0.65), 2.2, true)
	c.draw_line(Vector2(2, -16), Vector2(5, -25), WHITE * dim, 2.0)
	var pulse: float = 0.6 + 0.4 * sin(_t * 5.0)
	c.draw_circle(Vector2(5, -26), 4.5, Color(GLOW, 0.25 * pulse))
	c.draw_circle(Vector2(5, -26), 2.5, Color(1.0, 0.55, 0.7))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
