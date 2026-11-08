class_name PauseWatch
extends Node
## [qafix] Autoplay watchdog for a paused SceneTree. The bot drives Lumi from Patch's physics step,
## so anything that pauses the tree and waits for a person (a choice, a reading, a "back to work"
## button) stalls the run for good. This node keeps running while paused and:
##  - logs every modal that opens (EventBus.ui_modal_changed) with the GDScript stack that opened it,
##  - logs every paused / unpaused edge with the screens that are open,
##  - after STALL_S seconds paused with nobody to answer, closes what is open the way a person
##    would (resolve()) and logs "[pause-watch] stall".
## Added by AutoplayBot; never in a normal game.

const STALL_S: float = 3.0

var world: Node
var stalls: int = 0
var _was: bool = false
var _paused_ms: int = 0


func _ready() -> void:
	name = "PauseWatch"
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.ui_modal_changed.connect(_on_modal)


func _on_modal(open: bool) -> void:
	if open:
		print("[pause-watch] modal opened at %.1f min: %s" % [_min(), ", ".join(open_screens())])
		print_stack()


func _process(_delta: float) -> void:
	var p: bool = get_tree().paused
	if p != _was:
		_was = p
		_paused_ms = Time.get_ticks_msec()
		print("[pause-watch] tree %s at %.1f min: %s" % ["PAUSED" if p else "running", _min(), ", ".join(open_screens())])
	if p and Time.get_ticks_msec() - _paused_ms > int(STALL_S * 1000.0):
		stalls += 1
		var what: Array[String] = open_screens()
		print("[pause-watch] stall %d at %.1f min, closing: %s" % [stalls, _min(), ", ".join(what)])
		resolve()
		_paused_ms = Time.get_ticks_msec()


func _min() -> float:
	return float(GameState.stats.get("time_played", 0.0)) / 60.0


## Nodes that say they are open (is_open), and visible answer cards (the scratched-CD choice).
func open_screens() -> Array[String]:
	var out: Array[String] = []
	if world == null:
		return out
	for n: Node in world.find_children("*", "", true, false):
		if n == self:
			continue
		var o: Variant = n.get("is_open")
		if o is bool and o:
			out.append(str(n.name))
		elif n is ScratchedCdUI and str(n.get("_ask_id")) != "":
			out.append("%s(ask)" % n.name)
	return out


## Closes whatever is waiting for a person, the way they would.
func resolve() -> void:
	for n: Node in world.find_children("*", "", true, false):
		if n is ScratchedCdUI and str(n.get("_ask_id")) != "":
			n.call("_answer", "keep" if not Tunes.case_full() else "play")
			continue
		var o: Variant = n.get("is_open")
		if not (o is bool and o):
			continue
		for m: String in ["close_doc", "close_panel", "close_menu", "close_screen", "close_view", "close"]:
			if n.has_method(m):
				n.call(m)
				break
	if get_tree().paused and open_screens().is_empty():
		get_tree().paused = false  # nothing left that owns the pause
