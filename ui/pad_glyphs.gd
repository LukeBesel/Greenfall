class_name PadGlyphs
extends RefCounted
## [deck] Controller button names and badge specs per pad family (Xbox, PlayStation, Steam
## Deck). The family follows Settings.glyph_style, or the last-used controller's name on Auto.
## Keyboard and mouse bindings fall back to Settings.event_label.

enum Style { AUTO, XBOX, PLAYSTATION, DECK }
const STYLE_NAMES: Array[String] = ["Automatic", "Xbox", "PlayStation", "Steam Deck"]

## button -> [Xbox, PlayStation, Deck] names.
const BUTTONS: Dictionary = {
	JOY_BUTTON_A: ["A", "Cross", "A"], JOY_BUTTON_B: ["B", "Circle", "B"],
	JOY_BUTTON_X: ["X", "Square", "X"], JOY_BUTTON_Y: ["Y", "Triangle", "Y"],
	JOY_BUTTON_LEFT_SHOULDER: ["LB", "L1", "L1"], JOY_BUTTON_RIGHT_SHOULDER: ["RB", "R1", "R1"],
	JOY_BUTTON_LEFT_STICK: ["LS", "L3", "L3"], JOY_BUTTON_RIGHT_STICK: ["RS", "R3", "R3"],
	JOY_BUTTON_BACK: ["View", "Create", "View"], JOY_BUTTON_START: ["Menu", "Options", "Menu"],
	JOY_BUTTON_GUIDE: ["Guide", "PS", "Steam"], JOY_BUTTON_MISC1: ["Share", "Mute", "QAM"],
	JOY_BUTTON_DPAD_UP: ["D-pad up", "D-pad up", "D-pad up"], JOY_BUTTON_DPAD_DOWN: ["D-pad down", "D-pad down", "D-pad down"],
	JOY_BUTTON_DPAD_LEFT: ["D-pad left", "D-pad left", "D-pad left"], JOY_BUTTON_DPAD_RIGHT: ["D-pad right", "D-pad right", "D-pad right"],
	JOY_BUTTON_PADDLE1: ["P1", "P1", "R4"], JOY_BUTTON_PADDLE2: ["P2", "P2", "L4"],
	JOY_BUTTON_PADDLE3: ["P3", "P3", "R5"], JOY_BUTTON_PADDLE4: ["P4", "P4", "L5"],
}
const TRIGGERS: Array = [["LT", "L2", "L2"], ["RT", "R2", "R2"]]
## Face-button colours per family (Xbox letters; PlayStation shapes; Deck is monochrome).
const XBOX_COLORS: Dictionary = {
	JOY_BUTTON_A: Color(0.48, 0.82, 0.36), JOY_BUTTON_B: Color(0.94, 0.38, 0.33),
	JOY_BUTTON_X: Color(0.36, 0.6, 1.0), JOY_BUTTON_Y: Color(1.0, 0.82, 0.3),
}
const PS_COLORS: Dictionary = {
	JOY_BUTTON_A: Color(0.55, 0.7, 1.0), JOY_BUTTON_B: Color(1.0, 0.45, 0.45),
	JOY_BUTTON_X: Color(0.95, 0.6, 0.85), JOY_BUTTON_Y: Color(0.4, 0.88, 0.72),
}


## Pad family in use: the setting, else guessed from the controller's name.
static func style() -> int:
	if Settings.glyph_style != Style.AUTO:
		return Settings.glyph_style
	return style_for_name(Input.get_joy_name(Settings.last_pad_device), OS.get_environment("SteamDeck") == "1")


static func style_for_name(joy_name: String, on_deck: bool = false) -> int:
	var n: String = joy_name.to_lower()
	for h: String in ["ps3", "ps4", "ps5", "dualshock", "dualsense", "playstation", "sony", "wireless controller"]:
		if h in n:
			return Style.PLAYSTATION
	if "steam deck" in n or (on_deck and ("steam" in n or n == "")):
		return Style.DECK
	return Style.XBOX


static func _col(st: int) -> int:
	return clampi(st, 1, 3) - 1


## Short name for a binding in the given family ("A", "Cross", "R2", "LS up", "E", "LMB").
static func event_name(ev: InputEvent, st: int = -1) -> String:
	if ev == null:
		return "?"
	if st < 0:
		st = style()
	if ev is InputEventJoypadButton:
		var b: int = (ev as InputEventJoypadButton).button_index
		return str(BUTTONS[b][_col(st)]) if BUTTONS.has(b) else "Button %d" % b
	if ev is InputEventJoypadMotion:
		var m: InputEventJoypadMotion = ev
		if m.axis == JOY_AXIS_TRIGGER_LEFT or m.axis == JOY_AXIS_TRIGGER_RIGHT:
			return str(TRIGGERS[0 if m.axis == JOY_AXIS_TRIGGER_LEFT else 1][_col(st)])
		var stick: String = ["LS", "L3", "L3"][_col(st)] if m.axis <= JOY_AXIS_LEFT_Y else ["RS", "R3", "R3"][_col(st)]
		if st != Style.XBOX:
			stick = "L stick" if m.axis <= JOY_AXIS_LEFT_Y else "R stick"
		var neg: bool = m.axis_value < 0.0
		var dir: String = ("left" if neg else "right") if m.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_RIGHT_X] else ("up" if neg else "down")
		return "%s %s" % [stick, dir]
	return Settings.event_label(ev)


## Drawing spec for a binding: {shape, text, color, dir}. Shapes: key, face, ps_cross,
## ps_circle, ps_square, ps_triangle, bumper, trigger, dpad, stick, menu, view.
static func badge(ev: InputEvent, st: int = -1) -> Dictionary:
	if st < 0:
		st = style()
	var out: Dictionary = {"shape": "key", "text": Settings.event_label(ev) if ev else "?", "color": UITheme.CREAM, "dir": Vector2.ZERO}
	if ev is InputEventJoypadButton:
		var b: int = (ev as InputEventJoypadButton).button_index
		out["text"] = event_name(ev, st)
		match b:
			JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y:
				if st == Style.PLAYSTATION:
					out["shape"] = {JOY_BUTTON_A: "ps_cross", JOY_BUTTON_B: "ps_circle", JOY_BUTTON_X: "ps_square", JOY_BUTTON_Y: "ps_triangle"}[b]
					out["color"] = PS_COLORS[b]
				else:
					out["shape"] = "face"
					out["color"] = XBOX_COLORS[b] if st == Style.XBOX else Color(0.92, 0.92, 0.9)
			JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER:
				out["shape"] = "bumper"
			JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK:
				out["shape"] = "stick"
				out["text"] = "L" if b == JOY_BUTTON_LEFT_STICK else "R"
				out["press"] = true
			JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
				out["shape"] = "dpad"
				out["dir"] = {JOY_BUTTON_DPAD_UP: Vector2.UP, JOY_BUTTON_DPAD_DOWN: Vector2.DOWN, JOY_BUTTON_DPAD_LEFT: Vector2.LEFT, JOY_BUTTON_DPAD_RIGHT: Vector2.RIGHT}[b]
			JOY_BUTTON_START:
				out["shape"] = "menu" if st != Style.PLAYSTATION else "bumper"
			JOY_BUTTON_BACK:
				out["shape"] = "view" if st != Style.PLAYSTATION else "bumper"
			_:
				out["shape"] = "bumper"
	elif ev is InputEventJoypadMotion:
		var m: InputEventJoypadMotion = ev
		if m.axis == JOY_AXIS_TRIGGER_LEFT or m.axis == JOY_AXIS_TRIGGER_RIGHT:
			out["shape"] = "trigger"
			out["text"] = event_name(ev, st)
		else:
			out["shape"] = "stick"
			out["text"] = "L" if m.axis <= JOY_AXIS_LEFT_Y else "R"
			var neg: bool = m.axis_value < 0.0
			out["dir"] = (Vector2.LEFT if neg else Vector2.RIGHT) if m.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_RIGHT_X] else (Vector2.UP if neg else Vector2.DOWN)
	elif ev is InputEventMouseButton:
		out["shape"] = "key"
	return out
