class_name EggCollect
extends RefCounted
## [eggs2] Shared helper for collectible easter eggs (eggs.json "collect": true, trigger "chain").
## Each part is a real pickup: E lifts it with Lumi's tractor beam into the compartment, a toast
## counts it ("Gnome 2 / 5"), and the base's EggDisplay shows the parts collected so far.
## Collected parts live in flags["egg_<id>_parts"] (the same key the old walk-up "seen" chain
## used, so parts seen in older saves count as collected).

const LIFT_S: float = 0.75


static func parts(id: String) -> Array:
	return GameState.flags.get("egg_%s_parts" % id, [])


static func has_part(id: String, part: int) -> bool:
	return part in parts(id)


static func count(id: String) -> int:
	return parts(id).size()


## Records part `part` of egg `id`. Returns the new count (unchanged if it was already there).
static func add(id: String, part: int) -> int:
	var list: Array = parts(id).duplicate()
	if not (part in list):
		list.append(part)
		GameState.flags["egg_%s_parts" % id] = list
	return list.size()


static func is_complete(id: String, total: int) -> bool:
	return count(id) >= total


## The tractor-beam show: the prop's mesh flies into Lumi's chest hopper (the same PickupFx the
## junk uses) and the prop itself is hidden. Returns the seconds until it has arrived.
static func lift(patch: Node3D, prop: Node3D, tint: Color) -> float:
	var mi: MeshInstance3D = prop.get_node_or_null("Anim") as MeshInstance3D
	if mi == null:
		for c: Node in prop.get_children():
			if c is MeshInstance3D:
				mi = c
				break
	prop.visible = false
	if patch == null or mi == null or patch.get("pickup_fx") == null:
		return 0.2
	(patch.get("pickup_fx") as Node).call("launch", mi.mesh, mi.global_transform, LIFT_S, true, tint)
	var model: Node = patch.get("model")
	if model and model.has_method("beam_at"):
		model.call("beam_at", mi.global_position, true)
		patch.get_tree().create_timer(LIFT_S, false).timeout.connect(func() -> void:
			if is_instance_valid(model):
				model.call("beam_at", null))
	return LIFT_S
