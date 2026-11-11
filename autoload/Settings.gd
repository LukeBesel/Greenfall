extends Node
## Player settings and the default input map. All gameplay reads named actions only.

const SETTINGS_PATH: String = "user://settings.cfg"

signal changed
## Emitted when the last input switches between keyboard/mouse and a controller.
signal input_device_changed(pad: bool)

## Gameplay actions the Controls tab can rebind: [action, display name]. All share one input
## context (gameplay), so a key used by two of them is a conflict. UI-only actions (ui_tab_*,
## buy_max) live in their own context and are not checked against these.
# l10n:begin
const REBINDABLE: Array = [
	["move_forward", "Move forward"], ["move_back", "Move back"],
	["move_left", "Move left"], ["move_right", "Move right"],
	["scoop", "Scoop junk"], ["cube", "Press a cube"], ["interact", "Interact"], ["drop", "Drop"],
	["tool_scoop", "Tool: scoop"], ["tool_plant", "Tool: plant"], ["tool_water", "Tool: water"],
	["open_upgrades", "Upgrades"], ["open_command", "Command view"], ["open_globe", "Globe map"],
	["lens_view", "Lens view"], ["open_codex", "Codex"], ["pause", "Pause"],
	["toggle_goals", "Show more goals"],  # [hud]
	["zoom_in", "Zoom in"], ["zoom_out", "Zoom out"],
	["photo_mode", "Photo mode"],  # [photo]
	["glim_scan", "Glim: scan (hold: upgrades)"],  # [buddy]
	["boost", "Hover boost"],  # [orbD] hold on the walkable globe (SphereInput)
]
# l10n:end
# l10n:begin
const JOY_NAMES: Dictionary = {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "View", JOY_BUTTON_START: "Menu", JOY_BUTTON_LEFT_STICK: "LS",
	JOY_BUTTON_RIGHT_STICK: "RS", JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
	JOY_BUTTON_MISC1: "Share",
	JOY_BUTTON_TOUCHPAD: "Touchpad", JOY_BUTTON_PADDLE1: "Paddle 1",  # [orbD]
}
# l10n:end
enum SubtitleSize { SMALL, MEDIUM, LARGE }

## Where settings are written (tests point this at a scratch file).
var settings_path: String = SETTINGS_PATH
var number_format: int = BigNum.Format.SHORT
## Camera shake strength 0..1 (0 = off).
var shake_intensity: float = 1.0
## Legacy on/off view of shake_intensity.
var screen_shake: bool:
	get:
		return shake_intensity > 0.0
	set(v):
		shake_intensity = 1.0 if v else 0.0
## Third-person camera field of view (degrees); lens view adds 10.
var fov: float = 62.0
var mouse_smoothing: bool = false
## Interface scale (root window content_scale_factor), 0.8..1.5.
var ui_scale: float = 1.0
var subtitles_enabled: bool = true
var subtitle_size: int = SubtitleSize.MEDIUM
## Solid backdrop behind subtitle lines for readability.
var subtitle_background: bool = false
## Okabe-Ito based palette for progress, meter and rarity colours (see UITheme helpers).
var colorblind: bool = false
## True when the most recent input came from a controller (prompt glyphs follow it).
var last_input_pad: bool = false
var reduced_motion: bool = false
var hold_to_scoop: bool = true  # false = toggle
var master_volume: float = 0.9
var sfx_volume: float = 0.9
var music_volume: float = 0.55
## [v6sound] Wind, wildlife and planet beds; and menu clicks. Defaults: data/sound.json "volumes".
var ambience_volume: float = 0.8
var ui_volume: float = 0.8
var mouse_sensitivity: float = 0.0035
var invert_y: bool = false
var best_value_tags: bool = true
## [hud] In-game HUD density: FULL (everything, no auto-fade), MINIMAL (default: non-essential
## elements fade after a few seconds without change), HIDDEN (only prompts and notifications).
enum HudMode { FULL, MINIMAL, HIDDEN }
var hud_mode: int = HudMode.MINIMAL
enum Quality { LOW, MEDIUM, HIGH, ULTRA }
var quality: int = Quality.MEDIUM  # [v1menu] Medium on a first run (owner, 2026-11-08)
var fullscreen: bool = false
var vsync: bool = true
## 3D render resolution as a fraction of the window (UI stays sharp).
var render_scale: float = 1.0
# [deck] Auto-detected graphics (systems/quality_detect.gd). quality_auto stays true until the
# player picks a preset; quality_note says what was detected ("Steam Deck", "integrated GPU ...").
var quality_auto: bool = false
var quality_note: String = ""
## The first-play frame-time probe (systems/quality_probe.gd) ran (it only steps down once).
var quality_probe_done: bool = false
## Pad button art: 0 automatic (from the controller's name), 1 Xbox, 2 PlayStation, 3 Steam Deck.
var glyph_style: int = 0
## Right-stick camera speed multiplier (0.5..2).
var stick_sensitivity: float = 1.0
## Joypad device id of the last controller input (for the automatic glyph style).
var last_pad_device: int = 0
## [l10n] UI language: "" = system default, else a locale code (see LANGUAGES). Saved.
var language: String = ""
## [l10n] Dev override from `--locale=xx` (never saved).
var locale_override: String = ""
## [l10n] Language picker entries: [locale code, name shown in its own language]. "" follows the OS.
const LANGUAGES: Array = [
	["", "System default"], ["en", "English"],
	["de", "Deutsch"], ["fr", "Français"], ["es", "Español"], ["pt_BR", "Português (Brasil)"],  # [i18n]
	["zh_CN", "简体中文"], ["ja", "日本語"],  # [i18n]
	["pseudo", "Pseudo (test)"],
]
## [l10n] Locales "System default" may pick (complete .po files only; see docs/LOCALIZATION.md).
const SYSTEM_LOCALES: Array[String] = ["en", "de", "fr", "es", "pt_BR", "zh_CN", "ja"]  # [i18n]
## Every UI font is at least this many px (Steam Deck readability at 1280x800).
const MIN_FONT_PX: int = 12

## action -> list of InputEvents (defaults). Remaps are stored on top of these.
var _defaults: Dictionary = {}
## action -> full event list, for actions the player has rebound.
var _overrides: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_default_actions()
	# [v6sound] Where the volume sliders start for a new player is data, not code.
	master_volume = SoundCfg.volume_default("master", master_volume)
	music_volume = SoundCfg.volume_default("music", music_volume)
	ambience_volume = SoundCfg.volume_default("ambience", ambience_volume)
	sfx_volume = SoundCfg.volume_default("sfx", sfx_volume)
	ui_volume = SoundCfg.volume_default("ui", ui_volume)
	load_settings()
	PadHold.install(get_tree())  # [orbD] hold the pad's map button (View) for the goal tracker
	for a: String in OS.get_cmdline_user_args():  # [l10n] dev hook: --locale=pseudo|de|es|en
		if a.begins_with("--locale="):
			locale_override = a.substr(9)
	apply_language()
	apply_display()
	apply_ui_scale()
	add_child(QualityProbe.new())  # [deck] first-play frame-time probe (steps a detected preset down)
	ReadableUI.install(get_tree())  # [deck] font-size floor for every Label/Button


func _input(event: InputEvent) -> void:
	var pad: bool
	if event is InputEventJoypadButton:
		pad = true
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) < 0.5:
			return
		pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		pad = false
	elif event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length() < 4.0:
			return
		pad = false
	else:
		return
	if pad:
		last_pad_device = event.device  # [deck]
	if pad != last_input_pad:
		last_input_pad = pad
		input_device_changed.emit(pad)


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
		"open_globe": [_key(KEY_M), _joy(JOY_BUTTON_BACK)],
		"open_command": [_key(KEY_B), _joy(JOY_BUTTON_DPAD_DOWN)],
		"tool_scoop": [_key(KEY_1), _joy(JOY_BUTTON_DPAD_UP)],
		"tool_plant": [_key(KEY_2), _joy(JOY_BUTTON_DPAD_LEFT)],
		"tool_water": [_key(KEY_3), _joy(JOY_BUTTON_DPAD_RIGHT)],
		"ui_tab_next": [_key(KEY_E), _joy(JOY_BUTTON_RIGHT_SHOULDER)],
		"ui_tab_prev": [_key(KEY_Q), _joy(JOY_BUTTON_LEFT_SHOULDER)],
		"buy_max": [_key(KEY_SHIFT), _joy(JOY_BUTTON_LEFT_STICK)],
		"open_codex": [_key(KEY_K), _joy(JOY_BUTTON_MISC1)],
		"toggle_goals": [_key(KEY_G), _joy(JOY_BUTTON_TOUCHPAD), _joy(JOY_BUTTON_PADDLE1)],  # [hud] expand the goal tracker; [orbD] pad: hold View (ui/pad_hold.gd), or touchpad / paddle 1
		"photo_mode": [_key(KEY_P)],  # [photo] pad: via the pause menu
		"garden_mode": [_key(KEY_H)],  # [late] Garden Mode (ui/garden_placer.gd); pad: via the pause menu
		"glim_scan": [_key(KEY_F), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)],  # [buddy] tap: hex scan, hold: Glim panel
		"boost": [_key(KEY_SHIFT), _joy(JOY_BUTTON_LEFT_STICK)],  # [orbD] hover-boost on the globe (x4), also the sled's boost
	}
	for action: String in _defaults:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.25)
		InputMap.action_erase_events(action)
		for ev: InputEvent in _defaults[action]:
			InputMap.action_add_event(action, ev)
	# [deck] Godot 4.7's built-in ui_accept / ui_cancel have no controller buttons: without these
	# a pad can move focus but not press anything or back out (Steam Deck: A confirms, B backs).
	for pair: Array in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B]]:
		var has_btn: bool = false
		for ev: InputEvent in InputMap.action_get_events(pair[0]):
			if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == pair[1]:
				has_btn = true
		if not has_btn:
			InputMap.action_add_event(pair[0], _joy(pair[1]))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "number_format", number_format)
	cfg.set_value("feel", "screen_shake", screen_shake)
	cfg.set_value("feel", "shake_intensity", shake_intensity)
	cfg.set_value("camera", "fov", fov)
	cfg.set_value("camera", "mouse_smoothing", mouse_smoothing)
	cfg.set_value("ui", "scale", ui_scale)
	cfg.set_value("ui", "colorblind", colorblind)
	cfg.set_value("subtitles", "enabled", subtitles_enabled)
	cfg.set_value("subtitles", "size", subtitle_size)
	cfg.set_value("subtitles", "background", subtitle_background)
	for action: String in _overrides:
		var evs: Array = []
		for ev: InputEvent in _overrides[action]:
			var d: Dictionary = event_to_dict(ev)
			if not d.is_empty():
				evs.append(d)
		cfg.set_value("bindings", action, evs)
	cfg.set_value("feel", "reduced_motion", reduced_motion)
	cfg.set_value("controls", "hold_to_scoop", hold_to_scoop)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "ambience", ambience_volume)
	cfg.set_value("audio", "ui", ui_volume)
	cfg.set_value("ui", "best_value_tags", best_value_tags)
	cfg.set_value("ui", "hud_mode", hud_mode)  # [hud]
	cfg.set_value("display", "quality", quality)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("display", "render_scale", render_scale)
	cfg.set_value("display", "quality_auto", quality_auto)  # [deck]
	cfg.set_value("display", "quality_note", quality_note)
	cfg.set_value("display", "quality_probe_done", quality_probe_done)
	cfg.set_value("controls", "glyph_style", glyph_style)
	cfg.set_value("controls", "stick_sensitivity", stick_sensitivity)
	cfg.set_value("ui", "language", language)  # [l10n]
	cfg.save(settings_path)
	changed.emit()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		auto_detect_display(cfg)  # [deck] first launch
		return
	number_format = int(cfg.get_value("display", "number_format", number_format))
	screen_shake = bool(cfg.get_value("feel", "screen_shake", screen_shake))
	shake_intensity = clampf(float(cfg.get_value("feel", "shake_intensity", shake_intensity)), 0.0, 1.0)
	fov = clampf(float(cfg.get_value("camera", "fov", fov)), 50.0, 90.0)
	mouse_smoothing = bool(cfg.get_value("camera", "mouse_smoothing", mouse_smoothing))
	ui_scale = clampf(float(cfg.get_value("ui", "scale", ui_scale)), 0.8, 1.5)
	colorblind = bool(cfg.get_value("ui", "colorblind", colorblind))
	subtitles_enabled = bool(cfg.get_value("subtitles", "enabled", subtitles_enabled))
	subtitle_size = clampi(int(cfg.get_value("subtitles", "size", subtitle_size)), 0, 2)
	subtitle_background = bool(cfg.get_value("subtitles", "background", subtitle_background))
	if cfg.has_section("bindings"):
		for action: String in cfg.get_section_keys("bindings"):
			if not _defaults.has(action):
				continue
			var evs: Array[InputEvent] = []
			for d: Variant in cfg.get_value("bindings", action, []):
				if d is Dictionary:
					var ev: InputEvent = event_from_dict(d)
					if ev:
						evs.append(ev)
			if not evs.is_empty():
				_set_events(action, evs)
	reduced_motion = bool(cfg.get_value("feel", "reduced_motion", reduced_motion))
	hold_to_scoop = bool(cfg.get_value("controls", "hold_to_scoop", hold_to_scoop))
	mouse_sensitivity = float(cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity))
	invert_y = bool(cfg.get_value("controls", "invert_y", invert_y))
	master_volume = float(cfg.get_value("audio", "master", master_volume))
	sfx_volume = float(cfg.get_value("audio", "sfx", sfx_volume))
	music_volume = float(cfg.get_value("audio", "music", music_volume))
	ambience_volume = float(cfg.get_value("audio", "ambience", ambience_volume))
	ui_volume = float(cfg.get_value("audio", "ui", ui_volume))
	best_value_tags = bool(cfg.get_value("ui", "best_value_tags", best_value_tags))
	hud_mode = clampi(int(cfg.get_value("ui", "hud_mode", hud_mode)), 0, 2)  # [hud]
	quality = int(cfg.get_value("display", "quality", quality))
	fullscreen = bool(cfg.get_value("display", "fullscreen", fullscreen))
	vsync = bool(cfg.get_value("display", "vsync", vsync))
	render_scale = clampf(float(cfg.get_value("display", "render_scale", render_scale)), 0.5, 1.0)
	quality_auto = bool(cfg.get_value("display", "quality_auto", false))  # [deck]
	quality_note = str(cfg.get_value("display", "quality_note", ""))
	quality_probe_done = bool(cfg.get_value("display", "quality_probe_done", false))
	glyph_style = clampi(int(cfg.get_value("controls", "glyph_style", 0)), 0, 3)
	stick_sensitivity = clampf(float(cfg.get_value("controls", "stick_sensitivity", 1.0)), 0.5, 2.0)
	language = str(cfg.get_value("ui", "language", ""))  # [l10n]
	auto_detect_display(cfg)


## [l10n] The locale actually used: the dev override, the chosen language, or the OS language when
## it is one of SYSTEM_LOCALES (else English).
func resolved_locale() -> String:
	if locale_override != "":
		return locale_override
	if language != "":
		return language
	return system_locale_for(OS.get_locale())  # [i18n]


## [i18n] Maps an OS locale ("de_AT", "pt_PT", "zh_Hans_CN", "ja_JP") to one of SYSTEM_LOCALES, else
## "en". Exact match first, then the language; Traditional Chinese (TW/HK/MO/Hant) stays English.
static func system_locale_for(os_locale: String) -> String:
	if os_locale in SYSTEM_LOCALES:
		return os_locale
	var lang: String = os_locale.split("_")[0].split("-")[0].to_lower()
	if lang in SYSTEM_LOCALES:
		return lang
	if lang == "zh":
		for t: String in ["TW", "HK", "MO", "Hant"]:
			if t in os_locale:
				return "en"
	for l: String in SYSTEM_LOCALES:
		if l.begins_with(lang + "_"):
			return l
	return "en"


## [l10n] Applies the language to TranslationServer. Controls showing a plain msgid update at once;
## text built in code refreshes when its screen is rebuilt.
func apply_language() -> void:
	TranslationServer.set_locale(resolved_locale())
	CJKFallback.apply(resolved_locale())  # [i18n] CJK glyph fallback on the UI fonts


## Interface scale for every 2D layer (the root window's content scale factor).
func apply_ui_scale() -> void:
	ui_scale = clampf(ui_scale, 0.8, 1.5)
	if is_inside_tree():
		get_tree().root.content_scale_factor = ui_scale


# --- Bindings -------------------------------------------------------------------------

static func is_pad_event(ev: InputEvent) -> bool:
	return ev is InputEventJoypadButton or ev is InputEventJoypadMotion


func display_name(action: String) -> String:
	for e: Array in REBINDABLE:
		if e[0] == action:
			return tr(e[1])
	return action


## Primary keyboard/mouse (pad = false) or controller (pad = true) binding, or null.
func binding(action: String, pad: bool) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	for ev: InputEvent in InputMap.action_get_events(action):
		if is_pad_event(ev) == pad:
			return ev
	return null


## Replaces the primary binding of the event's kind (keyboard/mouse or pad); other
## alternatives (e.g. the arrow keys next to WASD) stay.
func set_binding(action: String, ev: InputEvent) -> void:
	if not InputMap.has_action(action) or ev == null:
		return
	var pad: bool = is_pad_event(ev)
	var evs: Array[InputEvent] = []
	var replaced: bool = false
	for old: InputEvent in InputMap.action_get_events(action):
		if not replaced and is_pad_event(old) == pad:
			evs.append(ev)
			replaced = true
		elif not same_event(old, ev):
			evs.append(old)
	if not replaced:
		evs.append(ev)
	_set_events(action, evs)


func _set_events(action: String, evs: Array[InputEvent]) -> void:
	InputMap.action_erase_events(action)
	for ev: InputEvent in evs:
		InputMap.action_add_event(action, ev)
	var same: bool = evs.size() == (_defaults[action] as Array).size()
	if same:
		for i: int in evs.size():
			if not same_event(evs[i], _defaults[action][i]):
				same = false
				break
	if same:
		_overrides.erase(action)
	else:
		_overrides[action] = evs


func is_rebound(action: String) -> bool:
	return _overrides.has(action)


## Another rebindable action that already uses an equivalent event, or "".
func find_conflict(action: String, ev: InputEvent) -> String:
	for e: Array in REBINDABLE:
		var other: String = e[0]
		if other == action or not InputMap.has_action(other):
			continue
		for o: InputEvent in InputMap.action_get_events(other):
			if same_event(o, ev):
				return other
	return ""


## Every pair of rebindable actions sharing a binding: action -> [other actions].
func conflicts() -> Dictionary:
	var out: Dictionary = {}
	for e: Array in REBINDABLE:
		var a: String = e[0]
		if not InputMap.has_action(a):
			continue
		for ev: InputEvent in InputMap.action_get_events(a):
			var other: String = find_conflict(a, ev)
			if other != "":
				var l: Array = out.get(a, [])
				if not l.has(other):
					l.append(other)
				out[a] = l
	return out


## Back to the shipped bindings (other settings untouched).
func reset_bindings() -> void:
	_overrides.clear()
	_register_default_actions()


static func same_event(a: InputEvent, b: InputEvent) -> bool:
	if a == null or b == null:
		return false
	if a is InputEventKey and b is InputEventKey:
		return _key_code(a as InputEventKey) == _key_code(b as InputEventKey)
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return (a as InputEventJoypadButton).button_index == (b as InputEventJoypadButton).button_index
	if a is InputEventJoypadMotion and b is InputEventJoypadMotion:
		var ma: InputEventJoypadMotion = a
		var mb: InputEventJoypadMotion = b
		return ma.axis == mb.axis and signf(ma.axis_value) == signf(mb.axis_value)
	return false


static func _key_code(k: InputEventKey) -> Key:
	return k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode


static func event_to_dict(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		return {"t": "key", "code": int(_key_code(ev as InputEventKey))}
	if ev is InputEventMouseButton:
		return {"t": "mouse", "button": int((ev as InputEventMouseButton).button_index)}
	if ev is InputEventJoypadButton:
		return {"t": "joy", "button": int((ev as InputEventJoypadButton).button_index)}
	if ev is InputEventJoypadMotion:
		var m: InputEventJoypadMotion = ev
		return {"t": "axis", "axis": int(m.axis), "value": 1.0 if m.axis_value >= 0.0 else -1.0}
	return {}


static func event_from_dict(d: Dictionary) -> InputEvent:
	match str(d.get("t", "")):
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(d.get("code", 0)) as Key
			return k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = int(d.get("button", 1)) as MouseButton
			return m
		"joy":
			var j := InputEventJoypadButton.new()
			j.button_index = int(d.get("button", 0)) as JoyButton
			return j
		"axis":
			var a := InputEventJoypadMotion.new()
			a.axis = int(d.get("axis", 0)) as JoyAxis
			a.axis_value = float(d.get("value", 1.0))
			return a
	return null


## Short human name for a binding ("E", "LMB", "A", "D-pad up", "RT").
static func event_label(ev: InputEvent) -> String:
	if ev is InputEventKey:
		return OS.get_keycode_string(_key_code(ev as InputEventKey))
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return TranslationServer.translate("LMB")
			MOUSE_BUTTON_RIGHT: return TranslationServer.translate("RMB")
			MOUSE_BUTTON_MIDDLE: return TranslationServer.translate("MMB")
			MOUSE_BUTTON_WHEEL_UP: return TranslationServer.translate("Wheel up")
			MOUSE_BUTTON_WHEEL_DOWN: return TranslationServer.translate("Wheel down")
		return TranslationServer.translate("Mouse %d") % int((ev as InputEventMouseButton).button_index)
	if ev is InputEventJoypadButton:
		return TranslationServer.translate(str(JOY_NAMES.get((ev as InputEventJoypadButton).button_index, TranslationServer.translate("Button %d") % int((ev as InputEventJoypadButton).button_index))))
	if ev is InputEventJoypadMotion:
		var m: InputEventJoypadMotion = ev
		var up: bool = m.axis_value < 0.0
		match m.axis:
			JOY_AXIS_LEFT_X: return TranslationServer.translate("LS left") if up else TranslationServer.translate("LS right")
			JOY_AXIS_LEFT_Y: return TranslationServer.translate("LS up") if up else TranslationServer.translate("LS down")
			JOY_AXIS_RIGHT_X: return TranslationServer.translate("RS left") if up else TranslationServer.translate("RS right")
			JOY_AXIS_RIGHT_Y: return TranslationServer.translate("RS up") if up else TranslationServer.translate("RS down")
			JOY_AXIS_TRIGGER_LEFT: return "LT"
			JOY_AXIS_TRIGGER_RIGHT: return "RT"
	return ""


## Glyph text for an action on the device last used (e.g. "E" or "A"), for HUD prompts.
func glyph(action: String) -> String:
	if action == PadHold.LONG_ACTION and last_input_pad:  # [orbD] on a pad the goals are "hold View"
		var mb: InputEvent = binding(PadHold.SHORT_ACTION, true)
		if mb and is_pad_event(mb):
			return tr("hold %s") % PadGlyphs.event_name(mb)
	var ev: InputEvent = binding(action, last_input_pad)
	if ev == null:
		ev = binding(action, not last_input_pad)
	if ev and is_pad_event(ev):
		return PadGlyphs.event_name(ev)  # [deck] Xbox / PlayStation / Deck names
	return event_label(ev) if ev else "?"


## [deck] Keeps a Label's or Button's text in step with the device in use: `make` returns the
## text (typically built with glyph()). Called now and on every device or binding change.
func bind_text(ctl: Control, make: Callable) -> void:
	var ref: WeakRef = weakref(ctl)  # no strong capture: screens may be freed any time
	var cbs: Array[Callable] = []
	var apply: Callable = func() -> void:
		var c: Object = ref.get_ref()
		if c == null:
			if input_device_changed.is_connected(cbs[1]):
				input_device_changed.disconnect(cbs[1])
			if changed.is_connected(cbs[0]):
				changed.disconnect(cbs[0])
			cbs.clear()  # [health] break the lambda <-> array cycle so both are freed
			return
		c.set("text", make.call())
	var on_dev: Callable = func(_pad: bool) -> void: apply.call()
	cbs.append(apply)
	cbs.append(on_dev)
	apply.call()
	input_device_changed.connect(on_dev)
	changed.connect(apply)
	_text_binds = _text_binds.filter(func(a: Array) -> bool: return not a.is_empty())  # [health]
	_text_binds.append(cbs)


## [health] Bindings still alive at quit: their callables and arrays reference each other, so they
## are cleared here or they (and every script their lambdas came from) leak at exit.
var _text_binds: Array[Array] = []


func _exit_tree() -> void:
	for cbs: Array in _text_binds:
		for cb: Callable in cbs:
			if input_device_changed.is_connected(cb):
				input_device_changed.disconnect(cb)
			if changed.is_connected(cb):
				changed.disconnect(cb)
		cbs.clear()
	_text_binds.clear()


## Window mode, vsync and 3D render scale. No-op for the window parts when headless.
func apply_display() -> void:
	if is_inside_tree():
		get_tree().root.scaling_3d_scale = render_scale
		# [deck] FSR 1 upscaling when rendering below native (Forward+ / Mobile only).
		var fsr_ok: bool = RenderingServer.get_current_rendering_method() != "gl_compatibility"
		get_tree().root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if (render_scale < 0.99 and fsr_ok) else Viewport.SCALING_3D_MODE_BILINEAR
	if DisplayServer.get_name() == "headless":
		return
	var want: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	var cur: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	var is_full: bool = cur == DisplayServer.WINDOW_MODE_FULLSCREEN or cur == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if is_full != fullscreen:
		DisplayServer.window_set_mode(want)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


## Re-applies the quality preset to every WorldEnvironment and shadowed sun under `root`
## (used when the preset changes mid-scene, e.g. from the pause menu).
func apply_quality_to_tree(root: Node) -> void:
	if root == null:
		return
	for n: Node in root.find_children("*", "WorldEnvironment", true, false):
		var we: WorldEnvironment = n as WorldEnvironment
		if we.environment:
			apply_render_quality(we.environment, root.get_viewport())
	for n: Node in root.find_children("*", "DirectionalLight3D", true, false):
		var sun: DirectionalLight3D = n as DirectionalLight3D
		if sun.shadow_enabled:
			apply_sun_quality(sun)
	# [deck] Far depth-of-field only on High/Ultra (the camera rig adds it at High+).
	for n: Node in root.find_children("*", "Camera3D", true, false):
		var attrs: CameraAttributesPractical = (n as Camera3D).attributes as CameraAttributesPractical
		if attrs and attrs.dof_blur_amount > 0.0:
			attrs.dof_blur_far_enabled = quality >= Quality.HIGH


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
	env.fog_density = 0.0025 if env.volumetric_fog_enabled else 0.005
	# Without GI the scene loses bounce light: lift ambient so Low still looks bright.
	env.ambient_light_energy = 1.25 if env.sdfgi_enabled else 1.7
	env.glow_enabled = q >= Quality.MEDIUM
	if vp:
		vp.use_taa = q >= Quality.HIGH
		# [deck] Low: no MSAA (costly on APUs); FXAA instead.
		# [v1menu] No MSAA on any preset: changing the sample count rebuilt every pipeline, the main
		# reason a preset change stalled. Low/Medium use FXAA, High/Ultra TAA.
		vp.msaa_3d = Viewport.MSAA_DISABLED
		var ssaa_ok: bool = RenderingServer.get_current_rendering_method() != "gl_compatibility"  # [qafix] QA #35: FXAA only warns there
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if (q <= Quality.MEDIUM and ssaa_ok) else Viewport.SCREEN_SPACE_AA_DISABLED
		vp.mesh_lod_threshold = [4.0, 2.0, 1.0, 0.5][q]
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 4096, 8192][q], true)
	# [deck] Shadow filtering: fewer PCF taps on Low (still soft-edged).
	var sq: RenderingServer.ShadowQuality = RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW if q == Quality.LOW else RenderingServer.SHADOW_QUALITY_SOFT_LOW
	RenderingServer.directional_soft_shadow_filter_set_quality(sq)
	RenderingServer.positional_soft_shadow_filter_set_quality(sq)


## Sun shadow settings per quality tier.
func apply_sun_quality(sun: DirectionalLight3D) -> void:
	var q: int = quality
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if q == Quality.LOW else (DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q == Quality.MEDIUM else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	sun.directional_shadow_max_distance = [35.0, 55.0, 80.0, 120.0][q]


# --- [deck] Auto-detected quality --------------------------------------------------------

## Picks quality (and render / UI scale) from the hardware when the saved settings don't have
## them yet. Never overrides a saved choice. No-op headless (tests and tools keep the defaults).
func auto_detect_display(cfg: ConfigFile) -> void:
	if DisplayServer.get_name() == "headless" or settings_path != SETTINGS_PATH:
		return
	var has_q: bool = cfg.has_section_key("display", "quality")
	var has_ui: bool = cfg.has_section_key("ui", "scale")
	if has_q and has_ui:
		return
	var d: Dictionary = QualityDetect.pick(QualityDetect.probe_info())
	if not has_q:
		quality = mini(int(d["quality"]), Quality.MEDIUM)  # [v1menu] first run: Medium at most (weaker hardware still gets Low)
		if not cfg.has_section_key("display", "render_scale"):
			render_scale = float(d["render_scale"])
		quality_auto = true
		quality_note = str(d["note"])
		quality_probe_done = false
		print("[quality] detected %s (%s), render scale %d%%" % [QualityDetect.preset_name(quality), quality_note, roundi(render_scale * 100.0)])
	if not has_ui and float(d["ui_scale"]) > 0.0:
		ui_scale = float(d["ui_scale"])
		print("[quality] handheld screen: interface scale %d%%" % roundi(ui_scale * 100.0))
	save_settings.call_deferred()


## [deck] Renderer override (project setting application/config/project_settings_override
## points here). "" = the project's Forward+ (Metal on macOS, Vulkan / D3D12 elsewhere, OpenGL if
## neither works); "mobile" = Godot's Mobile renderer for weak GPUs. Applies after a restart.
const RENDERER_OVERRIDE: String = "user://renderer_override.cfg"


func renderer_override() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(RENDERER_OVERRIDE) != OK:
		return ""
	return str(cfg.get_value("rendering", "renderer/rendering_method", ""))


func set_renderer_override(method: String) -> void:
	if method == "" or method == "forward_plus":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RENDERER_OVERRIDE))
		return
	var cfg := ConfigFile.new()
	cfg.set_value("rendering", "renderer/rendering_method", method)
	cfg.save(RENDERER_OVERRIDE)


## The player picked a preset in Settings: stop auto-adjusting it.
func set_quality_manual(q: int) -> void:
	quality = clampi(q, 0, 3)
	quality_auto = false
	quality_probe_done = true


## Particle count multiplier for the current preset (Low halves bursts and rain).
func particle_scale() -> float:
	return [0.5, 0.75, 1.0, 1.0][clampi(quality, 0, 3)]


func fmt(n: BigNum) -> String:
	return n.format(number_format)
