class_name LumiScreen
extends RefCounted
## [v6screens] Where Lumi's body is on screen, in canvas units (what Controls are laid out in), so
## 2D overlays can keep off her: her meshes' boxes projected by the camera. Empty when she is not
## in view (hidden by a close camera, behind it, or no camera).

## Mesh boxes larger than this (m) are effects (beam, glow), not her body.
const MAX_PART_M: float = 4.0


static func rect(patch: Node3D, camera: Camera3D) -> Rect2:
	if patch == null or camera == null or not is_instance_valid(patch) or not is_instance_valid(camera):
		return Rect2()
	var model: Node = patch.get("model") as Node
	if model == null:
		model = patch
	var r := Rect2()
	var first: bool = true
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch: Node in n.get_children():
			stack.append(ch)
		if not (n is MeshInstance3D):
			continue
		var mi: MeshInstance3D = n
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var bb: AABB = mi.mesh.get_aabb()
		if bb.size.length() > MAX_PART_M:
			continue
		for k: int in 8:
			var wp: Vector3 = mi.global_transform * bb.get_endpoint(k)
			if camera.is_position_behind(wp):
				continue
			var sp: Vector2 = camera.unproject_position(wp)
			if first:
				r = Rect2(sp, Vector2.ZERO)
				first = false
			else:
				r = r.expand(sp)
	return r
