extends Node
## Dev hook `--no-hud` (store screenshots and trailer shots, docs/steam/TRAILER.md): keeps the
## gameplay HUD, toasts, subtitles and event banners hidden. Full-screen views opened on purpose
## (Command view, hologram map, workbench) stay visible. Added by DevHooks; does nothing otherwise.

const HIDE_SCRIPTS: Array[String] = ["res://ui/hud.gd", "res://ui/subtitles.gd", "res://ui/event_hud.gd", "res://story/ledger_uplink.gd"]

var _t: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.25:
		return
	_t = 0.0
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	_hide_in(scene)


func _hide_in(n: Node) -> void:
	for c: Node in n.get_children():
		if c is CanvasLayer:
			var sc: Script = c.get_script()
			if sc and sc.resource_path in HIDE_SCRIPTS:
				(c as CanvasLayer).visible = false
		elif c.get_child_count() > 0 and not (c is Control):
			_hide_in(c)
