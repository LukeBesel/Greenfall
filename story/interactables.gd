class_name Interactables
extends Node
## Small generic registry of things Patch can walk up to and press E on (easter eggs, the Ledger
## relay, ...). Each entry: a Node3D anchor, a reach radius, a prompt ("E   ..."), a callback and
## an optional `enabled` Callable. The slice scene asks it first in try_interact/interact_prompt.

var _items: Array[Dictionary] = []


## Registers an interactable (prompt: String or Callable -> String). Returns the entry so the caller can tweak/remove it later.
func register(anchor: Node3D, radius: float, prompt_: Variant, on_use: Callable, enabled: Callable = Callable()) -> Dictionary:
	var e: Dictionary = {"node": anchor, "r": radius, "prompt": prompt_, "use": on_use, "enabled": enabled}
	_items.append(e)
	return e


func unregister(anchor: Node3D) -> void:
	for i: int in range(_items.size() - 1, -1, -1):
		if _items[i]["node"] == anchor:
			_items.remove_at(i)


func count() -> int:
	return _items.size()


## Closest usable entry in reach of a position (or empty).
func nearest(pos: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for i: int in range(_items.size() - 1, -1, -1):
		var e: Dictionary = _items[i]
		var n: Node3D = e["node"]
		if not is_instance_valid(n):
			_items.remove_at(i)
			continue
		if not n.is_inside_tree() or not n.visible:
			continue
		var en: Callable = e["enabled"]
		if en.is_valid() and not bool(en.call()):
			continue
		var d: float = Vector2(n.global_position.x - pos.x, n.global_position.z - pos.z).length()
		if d < float(e["r"]) and d < best_d:
			best_d = d
			best = e
	return best


func prompt(pos: Vector3) -> String:
	var e: Dictionary = nearest(pos)
	if e.is_empty():
		return ""
	var p: Variant = e["prompt"]
	return str((p as Callable).call()) if p is Callable else str(p)


## Uses the nearest entry; returns true if something was used.
func try_use(pos: Vector3) -> bool:
	var e: Dictionary = nearest(pos)
	if e.is_empty():
		return false
	(e["use"] as Callable).call()
	return true
