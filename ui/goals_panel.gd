class_name GoalsPanel
extends VBoxContainer
## The guidance column (top-right, under the district line): the story card (what to do next and
## why), the restart checklist while the tutorial runs, and the three goals beside the card, one
## per tier (ui/goal_readout.gd). The toggle_goals key (G, or hold View on a pad) steps the beam
## through the goals on show and back to the card's step (Objectives.track). A finished goal is
## stamped on its row and sends a short notice to the notification stack.

const W: float = GoalReadout.W
const CYAN := Color(0.55, 0.9, 1.0)

var hud: Node
var checklist: ChecklistCard  # restart checklist card (also borrowed for one-off "next step" hints)
var objective: ObjectiveCard  # the story objective with its why (story/objectives.gd)
var readout: GoalReadout
var _goals: Goals
var _sub: String = ""  # the latest checklist / hint text


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W, 0)
	add_theme_constant_override("separation", 8)
	objective = ObjectiveCard.new()
	add_child(objective)
	checklist = ChecklistCard.new()
	add_child(checklist)
	readout = GoalReadout.new()
	add_child(readout)
	EventBus.tutorial_changed.connect(set_checklist)
	visible = false


## Restart checklist text (EventBus.tutorial_changed); "" hides it with a fade.
func set_checklist(text: String) -> void:
	if checklist.tutorial == null:
		var w: Node = hud.get("world") if hud else null
		checklist.tutorial = (w.get("tutorial") as Tutorial) if w else null
	_sub = text
	_route_sub()


## [v2guide] Owner playtest 2 #33: ONE card. While a story objective is on the card, the checklist
## step (or a one-off hint) replaces the card's text instead of showing as a second card; before the
## objectives show (the first minute) the checklist card carries it alone.
func _route_sub() -> void:
	if _objective_running() and objective.visible:
		if checklist.visible:
			checklist.visible = false
			checklist.modulate.a = 0.0
		var tut: Tutorial = checklist.tutorial
		var pr: Array = tut.step_progress() if tut and not tut.done() else [-1.0, ""]
		objective.set_substep(ChecklistCard._strip_bb(_sub).strip_edges().replace("  ", " "), pr)
	else:
		objective.set_substep("")
		checklist.set_text(_sub)


## While a story objective is on the card, a checklist step shows as the card's text.
func _objective_running() -> bool:
	return objective.objectives != null and not objective.objectives.current().is_empty()


## Step text without its "  3/8" counter (so counting up doesn't re-fade the block).
static func _strip_count(t: String) -> String:
	var i: int = t.rfind("   ")
	return t.substr(0, i) if i > 0 and t.substr(i).strip_edges().contains("/") else t


## Steps what the beam follows: the card's step, then each goal on show, then the card again.
func toggle() -> void:
	var ob: Objectives = objective.objectives
	if ob == null:
		return
	var order: Array[int] = readout.shown_goals()
	var at: int = order.find(ob.tracked_goal)
	ob.track(order[at + 1] if at + 1 < order.size() else -1)
	Audio.play("click", 1.1 if ob.tracked_goal >= 0 else 0.95, -12.0)
	if ob.tracked_goal >= 0 and hud and hud.has_method("notify"):
		hud.call("notify", tr("Following  ·  %s") % _goals.text_of(ob.tracked_goal), "hint")


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_action_pressed("toggle_goals"):
		return
	var w: Node = hud.get("world") if hud else null
	if w and w.has_method("any_modal_open") and bool(w.call("any_modal_open")):
		return
	toggle()
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	var w: Node = hud.get("world") if hud else null
	if _goals == null:
		_goals = (w.get("goals") as Goals) if w else null
		if _goals == null:
			return
		_goals.completed.connect(_on_completed)
		readout.bind(_goals)
		visible = true
	if objective.objectives == null:
		var ob: Variant = w.get("objectives") if w else null
		if ob is Objectives:
			objective.bind(ob as Objectives)
			readout.objectives = ob as Objectives
	_route_sub()
	# The goals join the card once the card itself has come up (after WREN's first message).
	readout.set_process(objective.objectives == null or objective.objectives.revealed)


func _on_completed(gi: int) -> void:
	if gi == _goals.card_goal:  # the story card says it
		return
	var reward: String = reward_text(_goals.reward_of(gi), 1.0)
	if hud and hud.has_method("notify"):
		hud.call("notify", tr("Goal complete  ·  %s%s") % [_goals.text_of(gi), ("    " + reward) if reward != "" else ""], "goal")
	Audio.play("ding", 1.35, -12.0)


static func reward_text(reward: Dictionary, t: float) -> String:
	var parts: Array[String] = []
	for k: String in ["cubes", "seeds"]:
		if float(reward.get(k, 0.0)) > 0.0:
			parts.append((TranslationServer.translate("+%s cubes") if k == "cubes" else TranslationServer.translate("+%s seeds")) % _n(round(float(reward[k]) * t)))
	if float(reward.get("parts", 0.0)) > 0.0:
		parts.append(L10nFmt.amount("parts", round(float(reward["parts"]) * t), true))
	return "  ".join(parts)


static func _n(v: float) -> String:
	return Settings.fmt(BigNum.from_float(v))


## Number of goal rows on screen (tests).
func visible_rows() -> int:
	return readout.visible_rows()
