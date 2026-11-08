class_name PropBatch
extends RefCounted
## [orbE] Draw-call batching for static loose props (docs/PERFORMANCE.md, perf pass 3): the
## direct mesh children of a container that never changes after it is built (the crash site's
## furrow clods and shards, an Anvil site's loose pieces) merge into one mesh per material and
## shadow mode. Conservative on purpose: only auto-named (never looked up by name), script-less,
## childless, visible MeshInstance3D children with no per-node overlay; everything else is left
## alone, and nothing that animates or is found by name is touched. The originals are hidden
## (kept for collision tools and unmerge); call merge() again after the container is rebuilt.

const NODE_NAME: String = "PropMerged"


static func merge(root: Node3D) -> Dictionary:
	if DevHooks.has("no-prop-batch"):  # A/B for the draw-call numbers
		return {"meshes": 0, "surfaces_out": 0}
	unmerge(root)
	var groups: Dictionary = {}
	var order: Array = []
	var hidden: Array[MeshInstance3D] = []
	for c: Node in root.get_children():
		var mi: MeshInstance3D = c as MeshInstance3D
		if mi == null or not _eligible(mi):
			continue
		var mesh: Mesh = mi.mesh
		for s: int in mesh.get_surface_count():
			var mat: Material = mi.get_active_material(s)
			var key: Array = [mat.get_instance_id() if mat else 0, _format(mesh, s), mi.cast_shadow]
			var g: Dictionary = groups.get(key, {})
			if g.is_empty():
				g = {"st": SurfaceTool.new(), "mat": mat, "shadow": mi.cast_shadow}
				groups[key] = g
				order.append(key)
			(g["st"] as SurfaceTool).append_from(mesh, s, mi.transform)
		hidden.append(mi)
	if hidden.size() < 2:
		return {"meshes": 0, "surfaces_out": 0}
	var by_shadow: Dictionary = {}  # cast_shadow mode -> ArrayMesh
	for key: Array in order:
		var g: Dictionary = groups[key]
		var am: ArrayMesh = by_shadow.get(g["shadow"])
		if am == null:
			am = ArrayMesh.new()
			by_shadow[g["shadow"]] = am
		(g["st"] as SurfaceTool).commit(am)
		am.surface_set_material(am.get_surface_count() - 1, g["mat"])
	var n_out: int = 0
	for mode: Variant in by_shadow:
		var out := MeshInstance3D.new()
		out.name = "%s%d" % [NODE_NAME, int(mode)]  # one per shadow mode: siblings must not share a name (Godot renames the second)
		out.mesh = by_shadow[mode]
		out.cast_shadow = mode
		out.set_meta("no_collide", true)  # the originals' colliders were made at build time
		root.add_child(out)
		n_out += (by_shadow[mode] as ArrayMesh).get_surface_count()
	for mi: MeshInstance3D in hidden:
		mi.visible = false
	root.set_meta("prop_batch_hidden", hidden)
	return {"meshes": hidden.size(), "surfaces_out": n_out}


static func unmerge(root: Node3D) -> void:
	for c: Node in root.get_children():
		if String(c.name).begins_with(NODE_NAME):
			root.remove_child(c)
			c.free()
	for mi: Variant in root.get_meta("prop_batch_hidden", []):
		if is_instance_valid(mi):
			(mi as MeshInstance3D).visible = true
	if root.has_meta("prop_batch_hidden"):
		root.remove_meta("prop_batch_hidden")


## Vertex format of a surface (ArrayMesh knows it; primitive meshes: which arrays it has), so
## only like surfaces share a SurfaceTool.
static func _format(mesh: Mesh, s: int) -> int:
	if mesh is ArrayMesh:
		return (mesh as ArrayMesh).surface_get_format(s)
	var a: Array = mesh.surface_get_arrays(s)
	var f: int = 0
	for i: int in a.size():
		if a[i] != null:
			f |= 1 << i
	return f


static func _eligible(mi: MeshInstance3D) -> bool:
	return mi.visible and mi.mesh != null and String(mi.name).begins_with("@") and mi.get_script() == null \
		and mi.get_child_count() == 0 and mi.material_overlay == null and mi.skin == null \
		and not mi.has_meta("no_batch")
