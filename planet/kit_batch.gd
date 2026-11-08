class_name KitBatch
extends RefCounted
## [orbE] Draw-call batching for a site's kit buildings (docs/PERFORMANCE.md, perf pass 3).
## Every KitBuilding draws its own "Body" mesh: ~8-14 surfaces each, so a hub yard of 12
## buildings costs ~100 surfaces (x2-3 with shadows and depth). Their materials are shared (one
## KitMat per role, state and power; paint colours are baked per vertex), so all the bodies under
## a site root merge into one mesh with one surface per material: ~10 surfaces for the whole yard.
## The originals stay in the tree, hidden (their lights, ground patches and collision are
## untouched); call merge() again after any building is rebuilt (a state change).

const NODE_NAME: String = "KitMerged"


## Merges the visible KitBuilding bodies under `root`. Returns {buildings, surfaces_in, surfaces_out}.
static func merge(root: Node3D) -> Dictionary:
	if DevHooks.has("no-kit-batch"):  # A/B for the draw-call numbers
		return {"buildings": 0, "surfaces_in": 0, "surfaces_out": 0}
	var old: Node = root.get_node_or_null(NODE_NAME)
	if old:
		root.remove_child(old)
		old.free()
	var groups: Dictionary = {}  # [material id, format] -> {st, mat}
	var order: Array = []
	var n_bld: int = 0
	var n_in: int = 0
	for kb: KitBuilding in _buildings(root):
		var mi: MeshInstance3D = kb.get_node_or_null("Body") as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var xf: Transform3D = _relative(mi, root)
		var mesh: Mesh = mi.mesh
		for s: int in mesh.get_surface_count():
			var mat: Material = mi.get_active_material(s)
			var key: Array = [mat.get_instance_id() if mat else 0, mesh.surface_get_format(s)]
			var g: Dictionary = groups.get(key, {})
			if g.is_empty():
				var st := SurfaceTool.new()
				g = {"st": st, "mat": mat}
				groups[key] = g
				order.append(key)
			(g["st"] as SurfaceTool).append_from(mesh, s, xf)
			n_in += 1
		mi.visible = false
		n_bld += 1
	if order.is_empty():
		return {"buildings": 0, "surfaces_in": 0, "surfaces_out": 0}
	var am := ArrayMesh.new()
	for key: Array in order:
		var g: Dictionary = groups[key]
		(g["st"] as SurfaceTool).commit(am)
		am.surface_set_material(am.get_surface_count() - 1, g["mat"])
	var out := MeshInstance3D.new()
	out.name = NODE_NAME
	out.mesh = am
	out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(out)
	return {"buildings": n_bld, "surfaces_in": n_in, "surfaces_out": am.get_surface_count()}


## Hidden originals back (before a building is changed by hand, or to compare).
static func unmerge(root: Node3D) -> void:
	var old: Node = root.get_node_or_null(NODE_NAME)
	if old:
		root.remove_child(old)
		old.free()
	for kb: KitBuilding in _buildings(root):
		var mi: MeshInstance3D = kb.get_node_or_null("Body") as MeshInstance3D
		if mi:
			mi.visible = true


static func _buildings(root: Node) -> Array[KitBuilding]:
	var out: Array[KitBuilding] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c: Node in n.get_children():
			if c is KitBuilding:
				if (c as KitBuilding).visible:
					out.append(c)
			elif c.name != NODE_NAME:
				stack.append(c)
	return out


## The node's transform in root's space (works before the tree computes global transforms).
static func _relative(n: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf
