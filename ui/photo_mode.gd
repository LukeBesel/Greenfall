class_name PhotoMode
extends CanvasLayer
## [photo] Photo mode (also what Steam screenshots are made with).
## Opens from the pause menu or the rebindable "photo_mode" action (P / LS click). The world is
## paused, but Lumi keeps animating so poses preview live. A dedicated photo camera renders into
## its own SubViewport (the main viewport's 3D is switched off meanwhile), so captures contain
## the graded image, letterbox and logo stamp but never the HUD or this panel, and 2x captures
## just render that viewport at twice the window size for a few frames.
## Closing restores everything it touched: pause state, mouse, HUD and other UI layers, robots,
## time of day / haze / environment, Lumi's joints, transform, face and process mode.
## Can't open during cinematics (intro, story beats that own the camera or hide the HUD, Ledger
## resolution) or rocket flights.
##
## Dev flags (screenshots): --photo[=S] opens after S wall-clock seconds; --photo-seq="k=v|k=v;..."
## applies each entry then captures, one every --photo-every=S seconds (keys: any panel value
## by name, plus yaw/pitch; pose/filter/eyes/weather take ids); --photo-open=lumi,look opens those
## panel sections only; --photo-collapsed; --photo-copy=DIR also copies captures to res://DIR;
## --photo-close closes photo mode after the last capture.

signal opened
signal closed
signal captured(path: String)

const SHOT_DIR: String = "user://screenshots"
const FREE_RADIUS: float = 25.0
const WEATHER: Array[String] = ["Live", "Clear", "Haze", "Mist"]  # l10n
const RES: Array[String] = ["1x  (window)", "2x  (supersampled)"]  # l10n
const CAM_MODES: Array[String] = ["Orbit Lumi", "Free fly"]  # l10n

var world: Node
var is_open: bool = false
## Panel values (keys are what PhotoPanel rows bind to).
var values: Dictionary = {}

var _ui: Control
var _panel: PhotoPanel
var _overlay: Control
var _toast: PanelContainer
var _toast_label: Label
var _flash: ColorRect
var _bg: CanvasLayer
var _view: TextureRect
var _sv: SubViewport
var _cam: Camera3D
var _attrs: CameraAttributesPractical
var _grade: ColorRect
var _grade_mat: ShaderMaterial
var _logo: Control
var _poser: PhotoPoser
var _capturing: bool = false
var _ui_hidden: bool = false
var _dragging: bool = false
## Camera targets (t_) and smoothed values (c_).
var _t_yaw: float = 0.0
var _t_pitch: float = -0.2
var _c_yaw: float = 0.0
var _c_pitch: float = -0.2
var _c_dist: float = 3.0
var _c_height: float = 0.7
var _c_roll: float = 0.0
var _c_fov: float = 50.0
var _t_free := Vector3.ZERO
var _c_free := Vector3.ZERO
## What open() changed, for close().
var _snap: Dictionary = {}
var _hidden_layers: Array[CanvasLayer] = []
var _robot_vis: Dictionary = {}
var _dev_seq: Array = []
var _dev_next_ms: int = -1
var _dev_open_ms: int = -1


func _init() -> void:
	values = default_values()


static func default_values() -> Dictionary:
	return {
		"cam_mode": 0, "fov": 50.0, "roll": 0.0, "distance": 3.0, "height": 0.7,
		"autofocus": true, "focus": 3.0, "blur": 0.0, "exposure": 1.0,
		"filter": 0, "contrast": 1.0, "saturation": 1.0, "warmth": 0.0, "vignette": 0.15, "grain": 0.03,
		"time_override": false, "time": 0.5, "weather": 0,
		"pose": 0, "eyes": 0, "turn": 0.0, "robots": true,
		"hide_hud": true, "thirds": false, "letterbox": false, "logo": false, "res": 0,
	}


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DevHooks.has("photo"):
		_dev_open_ms = Time.get_ticks_msec() + int(DevHooks.get_f("photo", 3.0) * 1000.0)
		for e: String in DevHooks.get_s("photo-seq", "").split(";", false):
			_dev_seq.append(e)


func get_value(key: String) -> Variant:
	return values.get(key)


func set_value(key: String, v: Variant) -> void:
	values[key] = v
	_on_value(key)


# --- Open / close ---------------------------------------------------------------------------

## Why photo mode can't open right now ("" = it can). `from_menu`: opened from the pause menu,
## which has already closed (so modal/camera-input checks don't apply).
func block_reason(from_menu: bool = false) -> String:
	if is_open:
		return "open"
	if world == null or world.get("patch") == null:
		return "unavailable"
	if bool(world.get("launching")):
		return tr("Photo mode isn't available during a rocket flight.")
	var intro: Variant = world.get("intro")
	if intro is Node and (intro as Node).has_method("busy") and bool((intro as Node).call("busy")):
		return tr("Photo mode isn't available during a cinematic.")
	var ledger: Variant = world.get("ledger")
	if ledger is Object and bool((ledger as Object).get("busy")):
		return tr("Photo mode isn't available during a cinematic.")
	var hud: Variant = world.get("hud")
	if hud is CanvasLayer and not (hud as CanvasLayer).visible:
		return tr("Photo mode isn't available during a cinematic.")
	if not from_menu:
		if world.has_method("any_modal_open") and bool(world.call("any_modal_open")):
			return "modal"
		var cam: Variant = world.get("cam")
		if cam is Object and not bool((cam as Object).get("input_enabled")):
			return tr("Photo mode isn't available during a cinematic.")
	return ""


func try_open(from_menu: bool = false) -> bool:
	var why: String = block_reason(from_menu)
	if why != "":
		if why.length() > 12:
			EventBus.toast.emit(why, "info")
		return false
	open(from_menu)
	return true


func open(_from_menu: bool = false) -> void:
	if is_open or world == null:
		return
	is_open = true
	var tree: SceneTree = get_tree()
	_snap = {"paused": tree.paused, "mouse": Input.mouse_mode, "disable_3d": tree.root.disable_3d}
	_snapshot_world()
	tree.paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var patch: Node3D = world.get("patch")
	var model: PatchModel = patch.get("model") as PatchModel if patch else null
	if model:
		_poser = PhotoPoser.new()
		_poser.name = "PhotoPoser"
		add_child(_poser)
		_poser.attach(model)
		_snap["model_yaw"] = model.rotation.y
	_build_view()
	_build_ui()
	# Start from the game camera's framing so the switch is seamless.
	var rig: Variant = world.get("cam")
	if rig is CameraRig:
		var r: CameraRig = rig
		_t_yaw = r.yaw
		_t_pitch = clampf(r.pitch, -1.4, 0.4)
		values["distance"] = clampf(r.distance * 0.6, 1.2, 12.0)
		values["fov"] = clampf(r.camera.fov - 8.0, 20.0, 100.0)
	_c_yaw = _t_yaw
	_c_pitch = _t_pitch
	_c_dist = values["distance"]
	_c_height = values["height"]
	_c_fov = values["fov"]
	_c_roll = values["roll"]
	values["cam_mode"] = 0
	tree.root.disable_3d = true
	for k: String in values:
		if k != "filter":  # keep the slider tweaks from last time; the preset's hidden values apply below
			_on_value(k)
	_apply_grade()
	_panel.refresh()
	_update_camera(1.0)
	Audio.play("click", 0.7, -6.0)
	if DevHooks.has("photo"):
		print("[photo] open")
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_capturing = false
	var tree: SceneTree = get_tree()
	tree.root.disable_3d = _snap.get("disable_3d", false)
	if _poser:
		_poser.restore()
		_poser.queue_free()
		_poser = null
	_restore_world()
	for l: CanvasLayer in _hidden_layers:
		if is_instance_valid(l):
			l.visible = true
	_hidden_layers.clear()
	for r: Variant in _robot_vis:
		if is_instance_valid(r):
			(r as Node3D).visible = _robot_vis[r]
	_robot_vis.clear()
	if _bg:
		_bg.queue_free()
		_bg = null
	_sv = null
	_cam = null
	if _ui:
		_ui.queue_free()
		_ui = null
	_panel = null
	tree.paused = _snap.get("paused", false)
	Input.mouse_mode = _snap.get("mouse", Input.MOUSE_MODE_VISIBLE)
	if world and world.has_method("_on_modal_closed") and not tree.paused:
		world.call("_on_modal_closed")
	Audio.play("click", 0.9, -8.0)
	closed.emit()


const ENV_PROPS: Array[String] = ["fog_density", "fog_light_color", "volumetric_fog_density", "volumetric_fog_albedo",
	"adjustment_saturation", "adjustment_contrast", "ambient_light_energy", "tonemap_exposure", "glow_intensity", "glow_bloom"]
const SKY_PROPS: Array[String] = ["turbidity", "mie_coefficient", "rayleigh_color", "mie_color"]
const LIGHT_PROPS: Array[String] = ["rotation", "light_energy", "light_color", "visible"]


func _sky() -> SkyDirector:
	return world.get("sky_director") as SkyDirector if world else null


func _env() -> Environment:
	var sky: SkyDirector = _sky()
	if sky and sky.env:
		return sky.env
	return world.get("_env") as Environment if world else null


func _snapshot_world() -> void:
	var sky: SkyDirector = _sky()
	if sky:
		_snap["time"] = sky.time_of_day
		_snap["haze"] = sky.haze
		_snap["frozen"] = sky.frozen
		if sky.sky_mat:
			_snap["sky_mat"] = _grab(sky.sky_mat, SKY_PROPS)
		if sky.sun:
			_snap["sun"] = _grab(sky.sun, LIGHT_PROPS)
		if sky.moon:
			_snap["moon"] = _grab(sky.moon, LIGHT_PROPS)
	var env: Environment = _env()
	if env:
		_snap["env"] = _grab(env, ENV_PROPS)


func _restore_world() -> void:
	var sky: SkyDirector = _sky()
	if sky:
		sky.time_of_day = _snap.get("time", sky.time_of_day)
		sky.haze = _snap.get("haze", sky.haze)
		sky.frozen = _snap.get("frozen", sky.frozen)
		if sky.sky_mat and _snap.has("sky_mat"):
			_put(sky.sky_mat, _snap["sky_mat"])
		if sky.sun and _snap.has("sun"):
			_put(sky.sun, _snap["sun"])
		if sky.moon and _snap.has("moon"):
			_put(sky.moon, _snap["moon"])
	var env: Environment = _env()
	if env and _snap.has("env"):
		_put(env, _snap["env"])


static func _grab(o: Object, props: Array[String]) -> Dictionary:
	var d: Dictionary = {}
	for p: String in props:
		d[p] = o.get(p)
	return d


static func _put(o: Object, d: Dictionary) -> void:
	for p: String in d:
		o.set(p, d[p])


# --- Views ----------------------------------------------------------------------------------

func _base_size() -> Vector2i:
	var s: Vector2i = get_tree().root.size
	return Vector2i(maxi(s.x, 64), maxi(s.y, 64))


func _build_view() -> void:
	var root: Window = get_tree().root
	_bg = CanvasLayer.new()
	_bg.layer = -100
	_bg.name = "PhotoView"
	add_child(_bg)
	_sv = SubViewport.new()
	_sv.size = _base_size()
	_sv.world_3d = root.find_world_3d()
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.use_taa = root.use_taa
	_sv.msaa_3d = root.msaa_3d
	_sv.screen_space_aa = root.screen_space_aa
	_sv.mesh_lod_threshold = root.mesh_lod_threshold
	_sv.scaling_3d_mode = root.scaling_3d_mode
	_sv.scaling_3d_scale = root.scaling_3d_scale
	_sv.positional_shadow_atlas_size = root.positional_shadow_atlas_size
	_sv.anisotropic_filtering_level = root.anisotropic_filtering_level
	_sv.use_debanding = root.use_debanding
	_bg.add_child(_sv)
	_cam = Camera3D.new()
	_cam.near = 0.05
	_cam.far = 600.0
	_attrs = CameraAttributesPractical.new()
	_cam.attributes = _attrs
	_sv.add_child(_cam)
	_cam.current = true
	_grade = ColorRect.new()
	_grade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grade_mat = ShaderMaterial.new()
	_grade_mat.shader = preload("res://art/shaders/photo_grade.gdshader")
	_grade.material = _grade_mat
	_sv.add_child(_grade)
	_logo = LogoStamp.new()
	_logo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_logo.visible = false
	_sv.add_child(_logo)
	_view = TextureRect.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.texture = _sv.get_texture()
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(_view)


func _build_ui() -> void:
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.theme = UITheme.get_theme()
	add_child(_ui)
	_overlay = ThirdsOverlay.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	_ui.add_child(_overlay)
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_flash)
	_panel = PhotoPanel.new()
	_panel.owner_mode = self
	_ui.add_child(_panel)
	_panel.capture_pressed.connect(capture)
	_panel.close_pressed.connect(close)
	var s: VBoxContainer = _panel.section(tr("Camera"))
	_panel.cycler(s, tr("Mode"), "cam_mode", CAM_MODES)
	_panel.slider(s, tr("Field of view"), "fov", 20.0, 100.0, 1.0, func(v: float) -> String: return "%d°" % int(v))
	_panel.slider(s, tr("Roll"), "roll", -45.0, 45.0, 1.0, func(v: float) -> String: return "%d°" % int(v))
	_panel.slider(s, tr("Distance"), "distance", 1.0, 12.0, 0.1, func(v: float) -> String: return "%.1f m" % v)
	_panel.slider(s, tr("Height"), "height", -0.3, 2.5, 0.05, func(v: float) -> String: return "%.2f m" % v)
	_panel.action(s, tr("Reset camera"), reset_camera)
	s = _panel.section(tr("Lens"))
	_panel.toggle(s, tr("Auto-focus Lumi"), "autofocus")
	_panel.slider(s, tr("Focus distance"), "focus", 0.5, 30.0, 0.1, func(v: float) -> String: return "%.1f m" % v)
	_panel.slider(s, tr("Blur"), "blur", 0.0, 1.0, 0.01, func(v: float) -> String: return tr("Off") if v < 0.01 else "%d%%" % int(v * 100.0))
	_panel.slider(s, tr("Exposure"), "exposure", 0.4, 2.2, 0.01, func(v: float) -> String: return tr("%+.1f EV") % (log(v) / log(2.0)))
	s = _panel.section(tr("Look"))
	_panel.cycler(s, tr("Filter"), "filter", PhotoFilters.names())
	_panel.slider(s, tr("Contrast"), "contrast", 0.6, 1.5, 0.01, func(v: float) -> String: return "%d" % int(round((v - 1.0) * 100.0)))
	_panel.slider(s, tr("Saturation"), "saturation", 0.0, 1.6, 0.01, func(v: float) -> String: return "%d" % int(round((v - 1.0) * 100.0)))
	_panel.slider(s, tr("Warmth"), "warmth", -1.0, 1.0, 0.01, func(v: float) -> String: return "%d" % int(round(v * 100.0)))
	_panel.slider(s, tr("Vignette"), "vignette", 0.0, 1.0, 0.01, func(v: float) -> String: return "%d%%" % int(v * 100.0))
	_panel.slider(s, tr("Grain"), "grain", 0.0, 1.0, 0.01, func(v: float) -> String: return "%d%%" % int(v * 100.0))
	s = _panel.section(tr("World"), false)
	_panel.toggle(s, tr("Set time of day"), "time_override")
	_panel.slider(s, tr("Time"), "time", 0.0, 1.0, 0.005, func(v: float) -> String:
		var mins: int = int(round(v * 1440.0)) % 1440
		@warning_ignore("integer_division")
		return "%02d:%02d" % [mins / 60, mins % 60])
	_panel.cycler(s, tr("Weather"), "weather", WEATHER)
	s = _panel.section(tr("Lumi"))
	_panel.cycler(s, tr("Pose"), "pose", PhotoPoser.pose_names())
	_panel.cycler(s, tr("Eyes"), "eyes", PhotoPoser.eye_names())
	_panel.slider(s, tr("Turn"), "turn", -180.0, 180.0, 1.0, func(v: float) -> String: return "%d°" % int(v))
	_panel.toggle(s, tr("Show robots"), "robots")
	s = _panel.section(tr("Frame"), false)
	_panel.toggle(s, tr("Hide HUD"), "hide_hud")
	_panel.toggle(s, tr("Rule of thirds"), "thirds")
	_panel.toggle(s, tr("Letterbox 2.39:1"), "letterbox")
	_panel.toggle(s, tr("Greenfall stamp"), "logo")
	_panel.cycler(s, tr("Resolution"), "res", RES)
	_toast = PanelContainer.new()
	_toast.add_theme_stylebox_override("panel", UITheme.box(Color(0.045, 0.05, 0.055, 0.88), Color(1, 1, 1, 0.12), 1, 5, 10))
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.offset_left = 20.0
	_toast.offset_top = -64.0
	_toast.offset_bottom = -20.0
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_toast)
	_toast_label = UITheme.label("", 14, UITheme.CREAM)
	_toast.add_child(_toast_label)
	_panel._update_hints()
	var dev_open: String = DevHooks.get_s("photo-open", "")
	if dev_open != "":
		var want: PackedStringArray = dev_open.split(",")
		for n: String in [tr("Camera"), tr("Lens"), tr("Look"), tr("World"), tr("Lumi"), tr("Frame")]:
			_panel.open_section(n, want.has(n.to_lower()))
	if DevHooks.has("photo-collapsed"):
		_panel.set_collapsed(true)
	else:
		_panel.focus_first()


func toast(text: String) -> void:
	if _toast == null:
		EventBus.toast.emit(text, "info")
		return
	_toast_label.text = text
	_toast.reset_size()
	var tw := create_tween()
	tw.tween_property(_toast, "modulate:a", 1.0, 0.15)
	tw.tween_interval(3.5)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.5)


# --- Values ---------------------------------------------------------------------------------

func _on_value(key: String) -> void:
	if not is_open:
		return
	match key:
		"filter":
			var fv: Dictionary = PhotoFilters.values(PhotoFilters.id_at(int(values["filter"])))
			for k: String in ["contrast", "saturation", "warmth", "vignette", "grain"]:
				values[k] = fv[k]
			if _panel:
				_panel.refresh()
			_apply_grade()
		"contrast", "saturation", "warmth", "vignette", "grain", "letterbox":
			_apply_grade()
		"time_override", "time", "weather":
			_apply_world()
			_apply_grade()
		"pose":
			if _poser:
				_poser.pose = PhotoPoser.pose_ids()[int(values["pose"])]
		"eyes":
			if _poser:
				_poser.eyes = str(PhotoPoser.EYES[int(values["eyes"])][0])
		"turn":
			var patch: Node3D = world.get("patch")
			var model: Node3D = patch.get("model") if patch else null
			if model:
				model.rotation.y = float(_snap.get("model_yaw", 0.0)) + deg_to_rad(float(values["turn"]))
		"robots":
			_apply_robots()
		"hide_hud":
			_apply_hud()
		"thirds":
			if _overlay:
				_overlay.visible = bool(values["thirds"]) and not _ui_hidden
		"logo":
			if _logo:
				_logo.visible = bool(values["logo"])
		"cam_mode":
			if int(values["cam_mode"]) == 1 and _cam:
				_t_free = _cam.global_position
				_c_free = _t_free
				var f: Vector3 = -_cam.global_transform.basis.z
				_t_yaw = atan2(-f.x, -f.z)
				_t_pitch = asin(clampf(f.y, -1.0, 1.0))
				_c_yaw = _t_yaw
				_c_pitch = _t_pitch
			elif _cam:
				reset_camera(false)


func _apply_grade() -> void:
	if _grade_mat == null:
		return
	var fv: Dictionary = PhotoFilters.values(PhotoFilters.id_at(int(values["filter"])))
	for k: String in ["contrast", "saturation", "warmth", "vignette", "grain"]:
		fv[k] = values[k]
	PhotoFilters.apply(_grade_mat, fv)
	_grade_mat.set_shader_parameter("letterbox", 1.0 if bool(values["letterbox"]) else 0.0)
	var env: Environment = _env()
	if env and _snap.has("env"):
		env.glow_intensity = float(_snap["env"]["glow_intensity"]) * float(fv.get("glow", 1.0))
		env.glow_bloom = float(_snap["env"]["glow_bloom"]) * (1.0 + (float(fv.get("glow", 1.0)) - 1.0) * 0.5)
	if _overlay:
		_overlay.set("letterbox", bool(values["letterbox"]))
		_overlay.queue_redraw()
	if _logo:
		_logo.set("letterbox", bool(values["letterbox"]))
		_logo.queue_redraw()


func _apply_world() -> void:
	var sky: SkyDirector = _sky()
	if sky == null:
		return
	sky.time_of_day = float(values["time"]) if bool(values["time_override"]) else float(_snap.get("time", sky.time_of_day))
	var h0: float = float(_snap.get("haze", sky.haze))
	match int(values["weather"]):
		1:
			sky.haze = 0.0
		2:
			sky.haze = 1.0
		3:
			sky.haze = clampf(h0 * 0.5 + 0.35, 0.0, 1.0)
		_:
			sky.haze = h0
	sky._apply()
	var env: Environment = sky.env
	match int(values["weather"]):
		2:
			env.fog_density *= 1.6
			env.volumetric_fog_density *= 1.5
		3:
			env.fog_density *= 2.4
			env.volumetric_fog_density *= 4.0
			env.volumetric_fog_albedo = Color(0.92, 0.94, 0.97)


func _apply_robots() -> void:
	var fleet: Variant = world.get("fleet")
	if not (fleet is Fleet):
		return
	for r: Robot in (fleet as Fleet).robots():
		if not _robot_vis.has(r):
			_robot_vis[r] = r.visible
		r.visible = bool(values["robots"]) and bool(_robot_vis[r])


func _apply_hud() -> void:
	if bool(values["hide_hud"]):
		for n: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
			var l: CanvasLayer = n
			if l == self or is_ancestor_of(l) or not l.visible:
				continue
			l.visible = false
			_hidden_layers.append(l)
	else:
		for l: CanvasLayer in _hidden_layers:
			if is_instance_valid(l):
				l.visible = true
		_hidden_layers.clear()


func reset_camera(full: bool = true) -> void:
	var patch: Node3D = world.get("patch") if world else null
	if patch == null:
		return
	if full:
		values["distance"] = 3.0
		values["height"] = 0.7
		values["roll"] = 0.0
		values["fov"] = 50.0
		values["cam_mode"] = 0
		# Face Lumi from the front-left three-quarter view.
		_t_yaw = patch.global_rotation.y + PI + 0.5
		_t_pitch = -0.12
		if _panel:
			_panel.refresh()


# --- Camera ---------------------------------------------------------------------------------

func _lumi_pos() -> Vector3:
	var patch: Node3D = world.get("patch")
	return patch.global_position


func _pad() -> int:
	var pads: Array[int] = Input.get_connected_joypads()
	return pads[0] if not pads.is_empty() else -1


func _axis(pad: int, a: JoyAxis) -> float:
	if pad < 0:
		return 0.0
	var v: float = Input.get_joy_axis(pad, a)
	return 0.0 if absf(v) < 0.15 else (v - signf(v) * 0.15) / 0.85


func _key(k: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(k) else 0.0


func _poll_input(delta: float) -> void:
	var pad: int = _pad()
	var free: bool = int(values["cam_mode"]) == 1
	var panel_off: bool = _panel == null or _panel.collapsed or _ui_hidden
	var fast: float = 2.5 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	var inv: float = -1.0 if Settings.invert_y else 1.0
	# Look / orbit: right stick always; left stick too when the panel isn't using it.
	var look := Vector2(_axis(pad, JOY_AXIS_RIGHT_X), _axis(pad, JOY_AXIS_RIGHT_Y) * inv)
	var move := Vector2.ZERO
	if panel_off:
		var ls := Vector2(_axis(pad, JOY_AXIS_LEFT_X), _axis(pad, JOY_AXIS_LEFT_Y))
		if free:
			move += ls
		else:
			look += ls * Vector2(1.0, inv)
	var kx: float = _key(KEY_D) - _key(KEY_A)
	var ky: float = _key(KEY_S) - _key(KEY_W)
	if free:
		move += Vector2(kx, ky)
	else:
		look += Vector2(kx, -ky * 0.7)
	_t_yaw -= look.x * 1.9 * delta
	_t_pitch -= look.y * 1.3 * delta
	var trig: float = _axis(pad, JOY_AXIS_TRIGGER_RIGHT) - _axis(pad, JOY_AXIS_TRIGGER_LEFT)
	var up: float = _key(KEY_R) - _key(KEY_F)
	var roll: float = _key(KEY_E) - _key(KEY_Q)
	var zoom: float = _key(KEY_X) - _key(KEY_Z)
	if pad >= 0:
		zoom += (1.0 if Input.is_joy_button_pressed(pad, JOY_BUTTON_RIGHT_SHOULDER) else 0.0) - (1.0 if Input.is_joy_button_pressed(pad, JOY_BUTTON_LEFT_SHOULDER) else 0.0)
		if panel_off:
			up += (1.0 if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_UP) else 0.0) - (1.0 if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_DOWN) else 0.0)
			roll += (1.0 if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_RIGHT) else 0.0) - (1.0 if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_LEFT) else 0.0)
	var changed: Array[String] = []
	if free:
		var b := Basis(Vector3.UP, _t_yaw)
		var v: Vector3 = b * Vector3(move.x, 0, move.y) * 3.0 * fast
		v.y += (up + trig) * 2.0 * fast
		_t_free += v * delta
	else:
		if trig != 0.0:
			values["distance"] = clampf(float(values["distance"]) - trig * 3.0 * delta, 1.0, 12.0)
			changed.append("distance")
		if up != 0.0:
			values["height"] = clampf(float(values["height"]) + up * 1.2 * delta, -0.3, 2.5)
			changed.append("height")
	if roll != 0.0:
		values["roll"] = clampf(float(values["roll"]) + roll * 40.0 * delta, -45.0, 45.0)
		changed.append("roll")
	if zoom != 0.0:
		values["fov"] = clampf(float(values["fov"]) + zoom * 30.0 * delta, 20.0, 100.0)
		changed.append("fov")
	if _panel:
		for k: String in changed:
			_panel.refresh(k)


func _update_camera(delta: float) -> void:
	if _cam == null:
		return
	var lumi: Vector3 = _lumi_pos()
	var free: bool = int(values["cam_mode"]) == 1
	_t_pitch = clampf(_t_pitch, -1.45, 1.2 if free else 0.55)
	var k: float = 1.0 - exp(-delta * 10.0)
	_c_yaw = lerp_angle(_c_yaw, _t_yaw, k)
	_c_pitch = lerpf(_c_pitch, _t_pitch, k)
	_c_dist = lerpf(_c_dist, float(values["distance"]), k)
	_c_height = lerpf(_c_height, float(values["height"]), k)
	_c_roll = lerpf(_c_roll, float(values["roll"]), k)
	_c_fov = lerpf(_c_fov, float(values["fov"]), k)
	var pos: Vector3
	var basis: Basis
	if free:
		var off: Vector3 = _t_free - lumi
		if off.length() > FREE_RADIUS:
			_t_free = lumi + off.normalized() * FREE_RADIUS
		_t_free.y = clampf(_t_free.y, lumi.y + 0.12, lumi.y + FREE_RADIUS * 0.6)
		_c_free = _c_free.lerp(_t_free, k)
		pos = _c_free
		basis = Basis(Vector3.UP, _c_yaw) * Basis(Vector3.RIGHT, _c_pitch)
	else:
		var focus: Vector3 = lumi + Vector3(0, _c_height, 0)
		var rot := Basis(Vector3.UP, _c_yaw) * Basis(Vector3.RIGHT, _c_pitch)
		pos = focus + rot * Vector3(0, 0, _c_dist)
		pos.y = maxf(pos.y, lumi.y + 0.08)
		basis = Basis.looking_at(focus - pos, Vector3.UP) if pos.distance_to(focus) > 0.01 else rot
	basis = basis * Basis(Vector3.FORWARD, deg_to_rad(_c_roll))
	_cam.global_transform = Transform3D(basis, pos)
	_cam.fov = _c_fov
	# Depth of field: focus on Lumi's face (auto) or at a set distance.
	var head: Vector3 = lumi + Vector3(0, 0.75, 0)
	var fd: float = pos.distance_to(head) if bool(values["autofocus"]) else float(values["focus"])
	if bool(values["autofocus"]) and absf(float(values["focus"]) - fd) > 0.05:
		values["focus"] = fd
		if _panel:
			_panel.refresh("focus")
	var blur: float = float(values["blur"])
	_attrs.dof_blur_far_enabled = blur > 0.01
	_attrs.dof_blur_near_enabled = blur > 0.01 and fd > 0.9
	_attrs.dof_blur_far_distance = fd + 0.35 + fd * 0.12
	_attrs.dof_blur_far_transition = maxf(0.4, fd * lerpf(2.2, 0.5, blur))
	_attrs.dof_blur_near_distance = maxf(0.05, fd - 0.3 - fd * 0.1)
	_attrs.dof_blur_near_transition = maxf(0.1, _attrs.dof_blur_near_distance * 0.7)
	_attrs.dof_blur_amount = lerpf(0.03, 0.2, blur)
	_attrs.exposure_multiplier = float(values["exposure"])
	if _poser:
		_poser.camera_pos = pos


func _process(delta: float) -> void:
	_dev_tick()
	if not is_open:
		return
	if _sv and not _capturing and _sv.size != _base_size():
		_sv.size = _base_size()
	_poll_input(delta)
	_update_camera(delta)


# --- Input ----------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k: Key = (event as InputEventKey).physical_keycode
		if _ui_hidden and k != KEY_C:
			_set_ui_hidden(false)
			get_viewport().set_input_as_handled()
			return
		match k:
			KEY_TAB:
				_panel.set_collapsed(not _panel.collapsed)
			KEY_H:
				_set_ui_hidden(true)
			KEY_C:
				capture()
			_:
				if event.is_action_pressed("pause") or event.is_action_pressed("photo_mode") or event.is_action_pressed("ui_cancel"):
					close()
				else:
					return
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		var b: JoyButton = (event as InputEventJoypadButton).button_index
		if _ui_hidden:
			_set_ui_hidden(false)
			get_viewport().set_input_as_handled()
			return
		match b:
			JOY_BUTTON_Y:
				_panel.set_collapsed(not _panel.collapsed)
			JOY_BUTTON_X:
				capture()
			JOY_BUTTON_BACK:
				set_value("cam_mode", 1 - int(values["cam_mode"]))
				_panel.refresh("cam_mode")
			JOY_BUTTON_RIGHT_STICK:
				reset_camera()
			JOY_BUTTON_A:
				if _panel.collapsed:
					capture()
				else:
					return
			JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
				if _panel.collapsed or b == JOY_BUTTON_LEFT_SHOULDER or b == JOY_BUTTON_RIGHT_SHOULDER:
					pass  # polled in _poll_input
				else:
					return
			_:
				if event.is_action_pressed("pause") or event.is_action_pressed("photo_mode") or event.is_action_pressed("ui_cancel"):
					close()
				else:
					return
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		if event.is_action_pressed("photo_mode"):
			if try_open():
				get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed and not (_panel and _panel.covers(mb.position))
			if mb.pressed and _panel and not _panel.covers(mb.position):
				var f: Control = get_viewport().gui_get_focus_owner()
				if f:
					f.release_focus()
		elif mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var d: float = -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			if mb.ctrl_pressed:
				values["fov"] = clampf(float(values["fov"]) + d * 3.0, 20.0, 100.0)
				_panel.refresh("fov")
			elif int(values["cam_mode"]) == 1:
				_t_free += -_cam.global_transform.basis.z * -d * 0.6
			else:
				values["distance"] = clampf(float(values["distance"]) * (1.0 + d * 0.08), 1.0, 12.0)
				_panel.refresh("distance")
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		var mm: InputEventMouseMotion = event
		var s: float = Settings.mouse_sensitivity * 1.2
		_t_yaw -= mm.relative.x * s
		_t_pitch -= mm.relative.y * s * (-1.0 if Settings.invert_y else 1.0)
		get_viewport().set_input_as_handled()


func _set_ui_hidden(h: bool) -> void:
	_ui_hidden = h
	if _panel:
		_panel.visible = not h
		if h:
			var f: Control = get_viewport().gui_get_focus_owner()
			if f:
				f.release_focus()
		elif not _panel.collapsed:
			_panel.focus_first()
	if _overlay:
		_overlay.visible = bool(values["thirds"]) and not h


# --- Capture --------------------------------------------------------------------------------

## Saves the current photo as a timestamped PNG in user://screenshots (2x renders the photo
## viewport at twice the window size for a few frames). Returns the absolute path ("" on error).
func capture() -> String:
	if not is_open or _capturing or _sv == null:
		return ""
	_capturing = true
	var mult: int = 2 if int(values["res"]) == 1 else 1
	var base: Vector2i = _base_size()
	if mult != 1:
		_sv.size = base * mult
		for i: int in 8:  # let TAA / reprojection settle at the new size
			await _frame()
			if not is_open:
				return ""
	await _frame()
	if not is_open or _sv == null:
		_capturing = false
		return ""
	var img: Image = null if DisplayServer.get_name() == "headless" else _sv.get_texture().get_image()
	if mult != 1:
		_sv.size = base
	if img == null or img.is_empty():  # e.g. headless (no renderer)
		_capturing = false
		toast(tr("Couldn't capture the photo."))
		print("[photo] capture skipped (no image)")
		return ""
	var path: String = next_shot_path()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	var abs_path: String = ProjectSettings.globalize_path(path)
	var err: Error = img.save_png(abs_path)
	_capturing = false
	if err != OK:
		toast(tr("Couldn't save the photo (%s).") % error_string(err))
		return ""
	if DevHooks.has("photo-copy"):
		var dst: String = ProjectSettings.globalize_path("res://" + DevHooks.get_s("photo-copy", "screenshots/photo"))
		DirAccess.make_dir_recursive_absolute(dst)
		img.save_png(dst.path_join(abs_path.get_file()))
	print("[photo] saved %s (%dx%d)" % [abs_path, img.get_width(), img.get_height()])
	Audio.play("click", 0.55, -4.0)
	if _flash:
		_flash.color.a = 0.35
		create_tween().tween_property(_flash, "color:a", 0.0, 0.35)
	if _panel:
		_panel.flash_capture()
	toast(tr("Saved  %s  (%dx%d)") % [abs_path, img.get_width(), img.get_height()])
	captured.emit(abs_path)
	return abs_path


func _frame() -> void:
	if DisplayServer.get_name() == "headless":  # the dummy renderer never draws
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw


## user://screenshots/greenfall_YYYY-MM-DD_HH-MM-SS.png (with _2, _3 ... if taken the same second).
static func next_shot_path() -> String:
	var stamp: String = Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var base: String = SHOT_DIR.path_join("greenfall_" + stamp)
	var path: String = base + ".png"
	var n: int = 2
	while FileAccess.file_exists(path):
		path = "%s_%d.png" % [base, n]
		n += 1
	return path


# --- Dev automation (screenshots) -----------------------------------------------------------

func _dev_tick() -> void:
	if _dev_open_ms == 0 and not is_open:
		return  # the dev sequence already ran and closed
	if _dev_open_ms < 0 or Time.get_ticks_msec() < _dev_open_ms:
		return
	if not is_open:
		if block_reason(true) == "":
			open(true)
			_dev_open_ms = 0
			_dev_next_ms = Time.get_ticks_msec() + int(DevHooks.get_f("photo-first", 12.0) * 1000.0)
			if not _dev_seq.is_empty():
				_dev_apply(str(_dev_seq[0]))
		else:
			print("[photo] waiting: ", block_reason(true))
			_dev_open_ms = Time.get_ticks_msec() + 1000
		return
	if _dev_seq.is_empty() or _dev_next_ms < 0 or Time.get_ticks_msec() < _dev_next_ms or _capturing:
		return
	_dev_next_ms = -1
	await capture()
	_dev_seq.pop_front()
	if _dev_seq.is_empty() and DevHooks.has("photo-close"):
		print("[photo] closing")
		close()
		return
	if not _dev_seq.is_empty():
		_dev_apply(str(_dev_seq[0]))
		_dev_next_ms = Time.get_ticks_msec() + int(DevHooks.get_f("photo-every", 20.0) * 1000.0)


## Applies "key=value|key=value" (panel keys, plus yaw/pitch; ids for pose/filter/eyes/weather).
func _dev_apply(entry: String) -> void:
	var cam_keys: Dictionary = {}
	for kv: String in entry.split("|", false):
		var p: PackedStringArray = kv.split("=", true, 1)
		if p.size() < 2:
			continue
		var k: String = p[0].strip_edges()
		var v: String = p[1].strip_edges()
		match k:
			"yaw", "pitch":
				cam_keys[k] = float(v)
			"pose":
				set_value("pose", maxi(0, PhotoPoser.pose_ids().find(v)))
			"filter":
				set_value("filter", PhotoFilters.index_of(v))
			"eyes":
				var i: int = 0
				for e: Array in PhotoPoser.EYES:
					if e[0] == v:
						set_value("eyes", i)
					i += 1
			"weather":
				set_value("weather", maxi(0, Array(WEATHER).map(func(w: String) -> String: return w.to_lower()).find(v.to_lower())))
			_:
				if values.has(k):
					var cur: Variant = values[k]
					if cur is bool:
						set_value(k, v == "1" or v == "true" or v == "on")
					elif cur is int:
						set_value(k, int(v))
					else:
						set_value(k, float(v))
	var patch: Node3D = world.get("patch")
	if cam_keys.has("yaw"):
		_t_yaw = patch.global_rotation.y + float(cam_keys["yaw"])
	if cam_keys.has("pitch"):
		_t_pitch = float(cam_keys["pitch"])
	if _panel:
		_panel.refresh()


# --- Overlays -------------------------------------------------------------------------------

## Rule-of-thirds guide (screen only; never in the saved photo).
class ThirdsOverlay extends Control:
	var letterbox: bool = false

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if letterbox:
			var h: float = minf(size.y, size.x / 2.39)
			r = Rect2(Vector2(0, (size.y - h) * 0.5), Vector2(size.x, h))
		var c := Color(1, 1, 1, 0.28)
		for i: int in [1, 2]:
			var x: float = r.position.x + r.size.x * i / 3.0
			var y: float = r.position.y + r.size.y * i / 3.0
			draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), c, 1.0, true)
			draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), c, 1.0, true)
		var m: Vector2 = r.get_center()
		draw_line(m - Vector2(7, 0), m + Vector2(7, 0), Color(1, 1, 1, 0.4), 1.0, true)
		draw_line(m - Vector2(0, 7), m + Vector2(0, 7), Color(1, 1, 1, 0.4), 1.0, true)


## Small "GREENFALL" stamp with a leaf mark, drawn into the photo itself (bottom right).
class LogoStamp extends Control:
	var letterbox: bool = false

	func _draw() -> void:
		var h: float = size.y
		var bottom: float = h
		if letterbox:
			bottom = h - maxf(0.0, (h - size.x / 2.39) * 0.5)
		var s: float = h / 720.0
		var font: Font = UITheme.font()
		var fs: int = int(round(20.0 * s))
		var text := "GREENFALL"
		var gap: float = 2.7 * s
		var tw: float = -gap
		for ch: String in text:
			tw += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + gap
		var x1: float = size.x - 26.0 * s
		var base_y: float = bottom - 24.0 * s
		var x0: float = x1 - tw
		var col := Color(0.95, 0.96, 0.93, 0.86)
		var shadow := Color(0, 0, 0, 0.35)
		# Letter-spaced wordmark.
		var x: float = x0
		for ch: String in text:
			draw_string(font, Vector2(x + 1.0 * s, base_y + 1.0 * s), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, shadow)
			draw_string(font, Vector2(x, base_y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + gap
		# Leaf mark: two arcs meeting at the tips, with a thin midrib.
		var c := Vector2(x0 - 16.0 * s, base_y - 7.0 * s)
		var pts := PackedVector2Array()
		var L: float = 11.0 * s
		var W: float = 5.0 * s
		var ang: float = -0.75
		for i: int in 17:
			var t: float = float(i) / 16.0
			pts.append(Vector2(lerpf(-L, L, t), -sin(t * PI) * W))
		for i: int in range(15, 0, -1):
			var t: float = float(i) / 16.0
			pts.append(Vector2(lerpf(-L, L, t), sin(t * PI) * W))
		var rot := Transform2D(ang, c)
		var leaf := PackedVector2Array()
		for p: Vector2 in pts:
			leaf.append(rot * p)
		draw_colored_polygon(leaf, Color(0.55, 0.9, 0.5, 0.9))
		draw_line(rot * Vector2(-L * 1.25, 0), rot * Vector2(L * 0.7, 0), Color(0.12, 0.25, 0.12, 0.7), maxf(1.0, 1.2 * s), true)
		# Thin rule under the wordmark.
		draw_line(Vector2(x0, base_y + 7.0 * s), Vector2(x1, base_y + 7.0 * s), Color(1, 1, 1, 0.35), maxf(1.0, s), true)
