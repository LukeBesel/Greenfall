extends Node
## Player settings and the default input map. All gameplay reads named actions only.

const SETTINGS_PATH: String = "user://settings.cfg"

var number_format: int = BigNum.Format.SHORT
var screen_shake: bool = true
var reduced_motion: bool = false
var hold_to_scoop: bool = true  # false = toggle
var master_volume: float = 0.9
var sfx_volume: float = 0.9
var music_volume: float = 0.55
var mouse_sensitivity: float = 0.0035
var invert_y: bool = false
var best_value_tags: bool = true
enum Quality { LOW, MEDIUM, HIGH, ULTRA }
var quality: int = Quality.HIGH

## action -> list of InputEvents (defaults). Remaps are stored on top of these.
var _defaults: Dictionary = {}


func _ready() -> void:
	_register_default_actions()
	load_settings()


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


func _joy(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e


func _register_default_actions() -> void:
	_defaults = {
		"move_forward": [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)],
		"move_back": [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)],
		"move_left": [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)],
		"move_right": [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)],
		"look_left": [_axis(JOY_AXIS_RIGHT_X, -1.0)],
		"look_right": [_axis(JOY_AXIS_RIGHT_X, 1.0)],
		"look_up": [_axis(JOY_AXIS_RIGHT_Y, -1.0)],
		"look_down": [_axis(JOY_AXIS_RIGHT_Y, 1.0)],
		"scoop": [_mouse(MOUSE_BUTTON_LEFT), _key(KEY_SPACE), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)],
		"cube": [_mouse(MOUSE_BUTTON_RIGHT), _key(KEY_C), _joy(JOY_BUTTON_X)],
		"interact": [_key(KEY_E), _joy(JOY_BUTTON_A)],
		"drop": [_key(KEY_Q), _joy(JOY_BUTTON_B)],
		"open_upgrades": [_key(KEY_TAB), _key(KEY_U), _joy(JOY_BUTTON_Y)],
		"pause": [_key(KEY_ESCAPE), _joy(JOY_BUTTON_START)],
		"zoom_in": [_mouse(MOUSE_BUTTON_WHEEL_UP), _joy(JOY_BUTTON_RIGHT_SHOULDER)],
		"zoom_out": [_mouse(MOUSE_BUTTON_WHEEL_DOWN), _joy(JOY_BUTTON_LEFT_SHOULDER)],
		"lens_view": [_key(KEY_V), _joy(JOY_BUTTON_RIGHT_STICK)],
		"ui_tab_next": [_key(KEY_E), _joy(JOY_BUTTON_RIGHT_SHOULDER)],
		"ui_tab_prev": [_key(KEY_Q), _joy(JOY_BUTTON_LEFT_SHOULDER)],
		"buy_max": [_key(KEY_SHIFT), _joy(JOY_BUTTON_LEFT_STICK)],
	}
	for action: String in _defaults:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.25)
		InputMap.action_erase_events(action)
		for ev: InputEvent in _defaults[action]:
			InputMap.action_add_event(action, ev)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "number_format", number_format)
	cfg.set_value("feel", "screen_shake", screen_shake)
	cfg.set_value("feel", "reduced_motion", reduced_motion)
	cfg.set_value("controls", "hold_to_scoop", hold_to_scoop)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("ui", "best_value_tags", best_value_tags)
	cfg.set_value("display", "quality", quality)
	cfg.save(SETTINGS_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	number_format = int(cfg.get_value("display", "number_format", number_format))
	screen_shake = bool(cfg.get_value("feel", "screen_shake", screen_shake))
	reduced_motion = bool(cfg.get_value("feel", "reduced_motion", reduced_motion))
	hold_to_scoop = bool(cfg.get_value("controls", "hold_to_scoop", hold_to_scoop))
	mouse_sensitivity = float(cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity))
	invert_y = bool(cfg.get_value("controls", "invert_y", invert_y))
	master_volume = float(cfg.get_value("audio", "master", master_volume))
	sfx_volume = float(cfg.get_value("audio", "sfx", sfx_volume))
	music_volume = float(cfg.get_value("audio", "music", music_volume))
	best_value_tags = bool(cfg.get_value("ui", "best_value_tags", best_value_tags))
	quality = int(cfg.get_value("display", "quality", quality))


## Applies the quality preset to an Environment and viewport. Low drops GI, volumetrics and
## screen-space effects while keeping the same art direction (also the Mobile-renderer tier).
func apply_render_quality(env: Environment, vp: Viewport) -> void:
	var q: int = quality
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		q = Quality.LOW
	env.sdfgi_enabled = q >= Quality.HIGH
	env.ssil_enabled = q >= Quality.HIGH
	env.ssr_enabled = q >= Quality.ULTRA
	env.ssao_enabled = q >= Quality.MEDIUM
	env.volumetric_fog_enabled = q >= Quality.MEDIUM
	env.fog_density = 0.004 if env.volumetric_fog_enabled else 0.012
	env.glow_enabled = q >= Quality.MEDIUM
	if vp:
		vp.use_taa = q >= Quality.HIGH
		vp.msaa_3d = Viewport.MSAA_DISABLED if q >= Quality.HIGH else Viewport.MSAA_2X
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q == Quality.MEDIUM else Viewport.SCREEN_SPACE_AA_DISABLED
		vp.mesh_lod_threshold = [4.0, 2.0, 1.0, 0.5][q]
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 4096, 8192][q], true)


func fmt(n: BigNum) -> String:
	return n.format(number_format)
