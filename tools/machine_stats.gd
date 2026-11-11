extends Node
## [v6yard] Triangles and draw calls (mesh surfaces) of the yard machines and the hub landmarks,
## headless:  godot --headless --path . res://tools/machine_stats.tscn
## One line per model: "[stats] name tris=N surfaces=N meshes=N lights=N". Budgets: docs/PERFORMANCE.md.

func _ready() -> void:
	var root3 := Node3D.new()
	add_child(root3)
	var rows: Array = []
	rows.append(["baler", _add(root3, AutoBaler.new())])
	rows.append(["belt_drive", _add(root3, Conveyor.new())])
	rows.append(["fabricator", _add(root3, FabricatorModel.new())])
	for l: int in [1, 3, 5]:
		var d := Depot.new()
		root3.add_child(d)
		d.process_mode = Node.PROCESS_MODE_DISABLED
		d._build_body(l)
		rows.append(["trash_bin_L%d" % l, d])
	var cp := Node3D.new()
	root3.add_child(cp)
	var parts: Dictionary = YardArt.composter()
	for k: String in parts:
		cp.add_child((parts[k] as YardArt.Kit).mi(0.2))
	rows.append(["composter", cp])
	for t: int in [1, 4]:
		var m: MeshInstance3D = (YardArt.signal_tower(t)["kit"] as YardArt.Kit).mi(0.15)
		root3.add_child(m)
		rows.append(["signal_tower_T%d" % t, m])
	var bench := Node3D.new()
	root3.add_child(bench)
	bench.add_child(MeshInstance3D.new())
	YardArt.dress_bench(bench)
	rows.append(["workbench", bench])
	var shack := Node3D.new()
	root3.add_child(shack)
	for kit: YardArt.Kit in [YardArt.shack_frame(), YardArt.shack_roof(), YardArt.shack_back(), YardArt.shack_side()]:
		shack.add_child(kit.mi(0.15))
	rows.append(["lean_to", shack])
	var pod: Node3D = EscapePod.build()
	root3.add_child(pod)
	PodBatch.merge(pod)  # as the crash site draws it
	rows.append(["pod", pod])
	var cart: MeshInstance3D = MachineArt.pod_service().mi(0.2)
	root3.add_child(cart)
	rows.append(["pod_service_cart", cart])
	for kind: String in HubLandmarks.kinds():
		for st: String in ["broken", "restored"]:
			var t0: int = Time.get_ticks_msec()
			var n: Node3D = HubLandmarks.build(kind, st, 1, "verdance")
			root3.add_child(n)
			rows.append(["landmark_%s_%s (%d ms)" % [kind, st, Time.get_ticks_msec() - t0], n])
	for r: Array in rows:
		print(_line(r[0], r[1]))
	get_tree().quit()


func _add(parent: Node3D, n: Node3D) -> Node3D:
	parent.add_child(n)
	n.process_mode = Node.PROCESS_MODE_DISABLED
	return n


func _line(nm: String, n: Node) -> String:
	var tris: int = 0
	var surfs: int = 0
	var meshes: int = 0
	var lights: int = 0
	var all: Array[Node] = n.find_children("*", "", true, false)
	all.append(n)
	for c: Node in all:
		if c is Light3D:
			lights += 1
		var mesh: Mesh = null
		var mult: int = 1
		if c is MeshInstance3D:
			mesh = (c as MeshInstance3D).mesh
		elif c is MultiMeshInstance3D and (c as MultiMeshInstance3D).multimesh:
			mesh = (c as MultiMeshInstance3D).multimesh.mesh
			mult = (c as MultiMeshInstance3D).multimesh.instance_count
		if mesh == null:
			continue
		meshes += 1
		for s: int in mesh.get_surface_count():
			surfs += 1
			var arr: Array = mesh.surface_get_arrays(s)
			var idx: Variant = arr[Mesh.ARRAY_INDEX]
			@warning_ignore("integer_division")
			tris += ((idx as PackedInt32Array).size() / 3 if idx is PackedInt32Array and not (idx as PackedInt32Array).is_empty() else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3) * mult
	return "[stats] %-40s tris=%-7d surfaces=%-3d meshes=%-3d lights=%d" % [nm, tris, surfs, meshes, lights]
