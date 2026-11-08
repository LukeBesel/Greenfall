class_name SphereInput
extends PlayerInput
## [smove] PlayerInput plus the two planet-walk intents: hover-boost (hold) and jump (press).
## Actions "boost" / "jump" are registered here if the project doesn't define them yet
## (Shift / left trigger, F / left-stick click); Settings can take them over later.

static func ensure_actions() -> void:
	_ensure("boost", [_k(KEY_SHIFT), _ax(JOY_AXIS_TRIGGER_LEFT, 1.0)])
	_ensure("jump", [_k(KEY_F), _jb(JOY_BUTTON_LEFT_STICK)])


static func _ensure(action: String, evs: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.25)
	for e: InputEvent in evs:
		InputMap.action_add_event(action, e)


static func _k(code: Key) -> InputEvent:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


static func _ax(axis: JoyAxis, v: float) -> InputEvent:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = v
	return e


static func _jb(b: JoyButton) -> InputEvent:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	return e


func _init() -> void:
	ensure_actions()


func boost_held() -> bool:
	return enabled and Input.is_action_pressed("boost")


func jump_pressed() -> bool:
	return _fresh() and Input.is_action_just_pressed("jump")
