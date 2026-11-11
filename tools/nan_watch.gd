class_name NanWatch
extends Node
## Dev: --nan-watch. Names the nodes whose transform is not finite (the renderer only prints
## `Condition "!v.is_finite()"` with no node). Checks the whole tree a few times a second and
## prints each offender once: "[nan] path (script) local=... parent_ok=...".

const CHECK_EVERY_S: float = 0.25
const MAX_REPORTS: int = 40

var _t: float = 0.0
var _seen: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000  # after everything that moves things this frame


func _process(_delta: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _t < CHECK_EVERY_S or _seen.size() >= MAX_REPORTS:
		return
	_t = now
	for n: Node3D in non_finite(get_tree().root):
		var id: int = n.get_instance_id()
		if _seen.has(id):
			continue
		_seen[id] = true
		var sc: Script = n.get_script() as Script
		var par: Node3D = n.get_parent() as Node3D
		print("[nan] %s (%s) local=%s parent_ok=%s time_played=%.1f min" % [n.get_path(), sc.resource_path if sc else n.get_class(),
			str(n.transform), str(par == null or par.global_transform.is_finite()), float(GameState.stats.get("time_played", 0.0)) / 60.0])


## Every Node3D under `root` whose own (local) transform is not finite: the nodes that were given
## the bad value, not the children that inherit it.
static func non_finite(root: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and not (n as Node3D).transform.is_finite():
			out.append(n as Node3D)
		stack.append_array(n.get_children())
	return out
