class_name PodBatch
extends RefCounted
## [orbE] Draw-call batching for the escape pod (story/escape_pod.gd), ~90 meshes / ~300 draws.
## Behaviour stays identical:
## - The pod's static shell (body, lining, jamb, skirt, fins, greebles...) merges into one mesh
##   per material in the pod's own space, so it flies, leans and lands with the pod.
## - Everything another script finds is left as it is: nodes looked up by name (Hatch and its door,
##   Beacon, Scorch, HoverGlow/HoverLight, PodLight, Spill, ReentryFire), nodes held in the pod's
##   metadata (canopy, porthole, the damage kit), anything with a script or a material overlay.
## - Each repair-stage group that EscapePod.set_condition shows or hides as a whole (Patches,
##   Planter, Bolts) merges inside the group, so swapping stages still swaps them.
## Materials are shared, so the glitching seams, glyph and fin lamps animate exactly as before.

const NODE_NAME: String = "PodMerged"
const NAMED: Array[String] = ["Hatch", "Beacon", "Scorch", "HoverGlow", "HoverLight", "PodLight", "Spill",
	"ReentryFire", "LoosePanel", "Smoke", "BeaconBeam"]
## Stage groups merged inside themselves (shown/hidden as a unit by set_condition).
const GROUPS: Array[String] = ["Patches", "Planter", "Bolts"]


static func merge(pod: Node3D) -> Dictionary:
	if pod == null or DevHooks.has("no-pod-batch"):
		return {"meshes": 0, "surfaces_out": 0}
	unmerge(pod)
	var keep: Dictionary = _referenced(pod)
	var n_mesh: int = 0
	var n_out: int = 0
	# The stage groups first (inside themselves), then the shell around them.
	for g: String in GROUPS:
		var grp: Node3D = pod.find_child(g, true, false) as Node3D
		if grp:
			var r: Dictionary = _merge_into(grp, keep, [])
			n_mesh += int(r["meshes"])
			n_out += int(r["surfaces_out"])
	var skip: Array[String] = NAMED.duplicate()
	skip.append_array(GROUPS)
	var r2: Dictionary = _merge_into(pod, keep, skip)
	n_mesh += int(r2["meshes"])
	n_out += int(r2["surfaces_out"])
	return {"meshes": n_mesh, "surfaces_out": n_out}


static func unmerge(pod: Node3D) -> void:
	for n: Node in pod.find_children(NODE_NAME + "*", "", true, false):
		var host: Node = n.get_parent()
		for mi: Variant in host.get_meta("pod_batch_hidden", []):
			if is_instance_valid(mi):
				(mi as MeshInstance3D).visible = true
		host.remove_meta("pod_batch_hidden")
		host.remove_child(n)
		n.free()


## Every node the pod's metadata points at (canopy, porthole, the damage kit's parts).
static func _referenced(pod: Node3D) -> Dictionary:
	var out: Dictionary = {}
	for k: StringName in pod.get_meta_list():
		_collect(pod.get_meta(k), out)
	return out


static func _collect(v: Variant, out: Dictionary) -> void:
	if v is Node:
		out[v] = true
	elif v is Dictionary:
		for x: Variant in (v as Dictionary).values():
			_collect(x, out)
	elif v is Array:
		for x: Variant in v:
			_collect(x, out)


## Merges the eligible meshes under `host` (in host's space) into PodMerged children.
static func _merge_into(host: Node3D, keep: Dictionary, skip: Array[String]) -> Dictionary:
	var groups: Dictionary = {}
	var order: Array = []
	var hidden: Array[MeshInstance3D] = []
	var stack: Array = [[host, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var top: Array = stack.pop_back()
		var n: Node = top[0]
		var xf: Transform3D = top[1]
		for c: Node in n.get_children():
			if skip.has(String(c.name)) or keep.has(c) or c.get_script() != null or String(c.name).begins_with(NODE_NAME):
				continue
			if not (c is Node3D) or not (c as Node3D).visible:
				continue
			var cx: Transform3D = xf * (c as Node3D).transform
			if c is MeshInstance3D:
				var mi: MeshInstance3D = c
				if mi.mesh != null and mi.material_overlay == null and mi.skin == null and mi.get_child_count() == 0:
					for s: int in mi.mesh.get_surface_count():
						var mat: Material = mi.get_active_material(s)
						var key: Array = [mat.get_instance_id() if mat else 0, PropBatch._format(mi.mesh, s), mi.cast_shadow]
						var g: Dictionary = groups.get(key, {})
						if g.is_empty():
							g = {"st": SurfaceTool.new(), "mat": mat, "shadow": mi.cast_shadow}
							groups[key] = g
							order.append(key)
						(g["st"] as SurfaceTool).append_from(mi.mesh, s, cx)
					hidden.append(mi)
					continue
			stack.append([c, cx])
	if hidden.size() < 2:
		return {"meshes": 0, "surfaces_out": 0}
	var by_shadow: Dictionary = {}
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
		out.set_meta("no_collide", true)
		host.add_child(out)
		n_out += (by_shadow[mode] as ArrayMesh).get_surface_count()
	for mi: MeshInstance3D in hidden:
		mi.visible = false
	host.set_meta("pod_batch_hidden", hidden)
	return {"meshes": hidden.size(), "surfaces_out": n_out}
