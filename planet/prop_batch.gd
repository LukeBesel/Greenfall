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


# --- [v6flat] Builder batches for the planets' hub sites and props (Rime, Tidewell, Anvil) -----
# Moved here from the flat frontier district view (planet/frontier_view.gd), which went with the
# flat world.

## Merges primitive meshes per material into one ArrayMesh each.
class Batch:
	var sts: Dictionary = {}

	func add(mesh: Mesh, xf: Transform3D, mat: Material) -> void:
		var key: int = mat.get_instance_id()
		if not sts.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			sts[key] = [st, mat]
		for s: int in mesh.get_surface_count():
			(sts[key][0] as SurfaceTool).append_from(mesh, s, xf)

	func flush(parent: Node3D, shadows: bool = true) -> void:
		for key: int in sts:
			var st: SurfaceTool = sts[key][0]
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = sts[key][1]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mi)
		sts.clear()


## A transform for a box `size` from a to b (thin beams, struts, cables).
static func _beam_xf(a: Vector3, b: Vector3, thick: float) -> Transform3D:
	var d: Vector3 = b - a
	var len_: float = d.length()
	var y: Vector3 = d / maxf(len_, 0.0001)
	var x: Vector3 = y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z: Vector3 = x.cross(y).normalized()
	return Transform3D(Basis(x * thick, y * len_, z * thick), (a + b) * 0.5)
