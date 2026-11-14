extends GutTest
## [v7pod] The escape pod's cabin: the open hatch looks into a real cabin (the inner lining no
## longer runs across the doorway), the cabin wakes up with the repair stages, nothing of the
## outer shell cuts through it, and it stays within a modest budget.


func _pod() -> Node3D:
	var pod: Node3D = EscapePod.build()
	add_child_autofree(pod)
	return pod


func _tris(mi: MeshInstance3D) -> int:
	var n: int = 0
	for s: int in mi.mesh.get_surface_count():
		var arr: Array = mi.mesh.surface_get_arrays(s)
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		n += ((idx as PackedInt32Array).size() if idx != null and (idx as PackedInt32Array).size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n


func test_doorway_is_open() -> void:
	var pod: Node3D = _pod()
	var lin: MeshInstance3D = pod.get_node("Lining")
	var a0: float = EscapePod._ang(EscapePod.DOOR_J0) + 0.01
	var a1: float = EscapePod._ang(EscapePod.DOOR_J1) - 0.01
	for s: int in lin.mesh.get_surface_count():
		var vs: PackedVector3Array = lin.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for i: int in range(0, vs.size(), 3):
			var c: Vector3 = (vs[i] + vs[i + 1] + vs[i + 2]) / 3.0
			var a: float = atan2(c.x, -c.z)  # 0 faces -Z, the door
			var in_door: bool = a > a0 and a < a1 and c.y > EscapePod.DOOR_Y0 + 0.01 and c.y < EscapePod.DOOR_Y1 - 0.01
			assert_false(in_door, "no lining across the doorway at %s" % c)
			if in_door:
				return


func test_cabin_wakes_with_repairs() -> void:
	var pod: Node3D = _pod()
	var cab: Dictionary = pod.get_meta("cabin")
	EscapePod.set_open(pod, true)
	var energy: Array[float] = []
	for stage: int in 4:
		EscapePod.set_condition(pod, stage)
		assert_eq(bool((cab["cabin"] as Node).get_meta("kit_powered")), stage >= 1, "console at stage %d" % stage)
		assert_eq(bool((cab["lamps"] as Node).get_meta("kit_powered")), stage >= 2, "lamps at stage %d" % stage)
		energy.append((pod.get_node("PodLight") as OmniLight3D).light_energy)
	assert_lt(energy[0], energy[1], "dim while dead")
	assert_lt(energy[1], energy[2])
	EscapePod.set_condition(pod, 0)
	EscapePod.animate(pod, 0.1, 0.016)
	var al: StandardMaterial3D = (cab["alarm"] as MeshInstance3D).material_override
	assert_gt(al.emission_energy_multiplier, 0.0, "the alarm blinks while dead")


func test_cabin_survives_batching_and_budget() -> void:
	var pod: Node3D = _pod()
	PodBatch.merge(pod)
	var cab: Dictionary = pod.get_meta("cabin")
	var tris: int = 0
	var draws: int = 0
	for k: String in ["cabin", "lamps", "alarm"]:
		var mi: MeshInstance3D = cab[k]
		assert_true(mi.is_visible_in_tree(), "%s stays its own node" % k)
		tris += _tris(mi)
		draws += mi.mesh.get_surface_count()
	assert_lt(tris, 9000, "cabin triangles")
	assert_lte(draws, 10, "cabin draw calls")
	for stage: int in 4:
		EscapePod.set_condition(pod, stage)  # still swaps after the merge


func test_no_shell_part_cuts_into_the_cabin() -> void:
	# The cabin's free space: inside the lining, above the floor, below the lamps.
	var pod: Node3D = _pod()
	var cabin_names: Array[String] = ["Cabin", "CabinLamps", "CabinAlarm", "Lining", "Jamb", "PodLight", "Hatch"]
	for n: Node in pod.get_children():
		if not (n is MeshInstance3D) or cabin_names.has(String(n.name)):
			continue
		var mi: MeshInstance3D = n
		if mi.mesh == null:
			continue
		var xf: Transform3D = mi.transform
		for s: int in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var p: Vector3 = xf * v
				if p.y < 0.6 or p.y > 1.5:
					continue
				var r_in: float = (EscapePod._door_r(p.y) - EscapePod.WALL) * cos(PI / EscapePod.SEGS) - 0.01
				assert_gt(Vector2(p.x, p.z).length(), r_in, "%s pokes into the cabin at %s" % [mi.name, p])
				if Vector2(p.x, p.z).length() <= r_in:
					return
