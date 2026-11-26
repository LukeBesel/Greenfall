class_name PadHold
extends Node
## [orbD] Long-press on the pad's map button (View / Back by default): a short press opens the
## globe map as before; holding it HOLD_S toggles the goal tracker ("toggle_goals"), so the goals
## work on any pad, Xbox included (every standard button already has a job).
## It intercepts the joypad button bound to "open_globe" (whatever it is rebound to) before any
## other node sees it, and re-sends the right action as an InputEventAction. Keyboard M and the
## other toggle_goals bindings (G, touchpad, paddle 1) are untouched.
## It keeps itself the root's last child, so its _input runs first (input goes last child first).

signal sent(action: String)

const HOLD_S: float = 0.5
const SHORT_ACTION: String = "open_globe"
const LONG_ACTION: String = "toggle_goals"

var _held: bool = false
var _t: float = 0.0
var _fired_long: bool = false
var _release_next: String = ""


static func install(tree: SceneTree) -> void:
	if tree.root.get_node_or_null("PadHold"):
		return
	var n := PadHold.new()
	n.name = "PadHold"
	n.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child.call_deferred(n)


## True for a pad button event that is bound to the map action.
static func is_hold_button(event: InputEvent) -> bool:
	return event is InputEventJoypadButton and InputMap.has_action(SHORT_ACTION) and event.is_action(SHORT_ACTION, true)


func _input(event: InputEvent) -> void:
	if not is_hold_button(event):
		return
	get_viewport().set_input_as_handled()
	if event.is_pressed() and not event.is_echo():
		_held = true
		_t = 0.0
		_fired_long = false
	elif not event.is_pressed() and _held:
		_held = false
		if not _fired_long:
			send(SHORT_ACTION)


func _process(delta: float) -> void:
	var p: Node = get_parent()
	if p and p.get_child(p.get_child_count() - 1) != self:
		p.move_child(self, -1)
	if _release_next != "":
		_send_one(_release_next, false)
		_release_next = ""
	if _held and not _fired_long:
		_t += delta
		if _t >= HOLD_S:
			_fired_long = true
			send(LONG_ACTION)


## Press now, release next frame (like a real button tap).
func send(action: String) -> void:
	if not InputMap.has_action(action):
		return
	_send_one(action, true)
	_release_next = action
	sent.emit(action)


func _send_one(action: String, pressed: bool) -> void:
	var a := InputEventAction.new()
	a.action = action
	a.pressed = pressed
	Input.parse_input_event(a)
