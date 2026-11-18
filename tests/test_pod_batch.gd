extends GutTest
## [orbE] Pod batching keeps behaviour identical: every repair stage still swaps (the stage
## groups show/hide with their merged meshes inside them), the door, beacon and damage kit are
## untouched, the per-frame animation runs on every stage, and the draw count drops.


func _surfaces(n: Node) -> int:
	var c: int = 0
	for m: Node in n.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m
		if mi.is_visible_in_tree() and mi.mesh:
			c += mi.mesh.get_surface_count()
	return c


func test_every_stage_still_swaps() -> void:
	var pod: Node3D = EscapePod.build()
	add_child_autofree(pod)
	EscapePod.set_condition(pod, 0)
	var before: int = _surfaces(pod)
	var r: Dictionary = PodBatch.merge(pod)
	assert_gt(int(r["meshes"]), 20, "most of the pod merges")
	assert_lt(_surfaces(pod), before, "fewer visible surfaces")
	assert_not_null(pod.get_node_or_null("Hatch"), "the door stays its own node")
	assert_not_null(pod.get_node_or_null("Beacon"))
	var kit: Dictionary = pod.get_meta("kit")
	for stage: int in 4:
		EscapePod.set_condition(pod, stage)
		EscapePod.animate(pod, 1.0 + stage, 0.016)
		assert_eq((kit["bolts"] as Node3D).visible, stage == 1, "bolts at stage %d" % stage)
		assert_eq((kit["patches"] as Node3D).visible, stage == 1, "patches at stage %d" % stage)
		assert_eq((kit["planter"] as Node3D).visible, stage == 3, "planter at stage %d" % stage)
		assert_eq((kit["wires"] as Node3D).visible, stage == 0)
		assert_eq((kit["cable"] as Node3D).visible, stage == 0)
		assert_eq((pod.get_node("HoverGlow") as Node3D).visible, stage >= 2)
		# What a group shows is what it holds: its merged mesh lives inside it.
		for g: String in ["patches", "planter"]:
			var grp: Node3D = kit[g]
			var found: Array[Node] = grp.find_children(PodBatch.NODE_NAME + "*", "", false, false)
			assert_gt(found.size(), 0, "%s merged inside itself" % g)
			for merged: Node in found:
				assert_eq((merged as Node3D).is_visible_in_tree(), grp.is_visible_in_tree())


func test_unmerge_restores() -> void:
	var pod: Node3D = EscapePod.build()
	add_child_autofree(pod)
	EscapePod.set_condition(pod, 1)
	var before: int = _surfaces(pod)
	PodBatch.merge(pod)
	PodBatch.unmerge(pod)
	assert_eq(_surfaces(pod), before)
	assert_eq(pod.find_children(PodBatch.NODE_NAME + "*", "", true, false).size(), 0)
