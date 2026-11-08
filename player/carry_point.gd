class_name CarryPoint
extends RefCounted
## [world2] Where Lumi holds carried bales: clearly ABOVE the body (playtest #2: "carrying a bale
## looks like it's inside Lumi"). The top of the model's solid parts (thin antennae and fins
## ignored) in Lumi's local space, plus a small gap, a touch forward of centre so the stack reads in
## front of the head from the follow camera. Cached per model (the design can change).

const GAP: float = 0.12
const FORWARD: float = 0.08


static func of(model: Node3D, holder: Node3D) -> Vector3:
	if model == null:
		return Vector3(0, 1.4, 0)
	var key: String = "%d|%s" % [model.get_instance_id(), str(model.get("variant"))]
	if model.has_meta("carry_point") and str(model.get_meta("carry_key", "")) == key:
		return model.get_meta("carry_point")
	var top: float = 0.0
	var inv: Transform3D = holder.global_transform.affine_inverse()
	for n: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var ab: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
		if ab.size.x < 0.12 and ab.size.z < 0.12:
			continue  # antenna, wire, fin
		if ab.position.y > 2.5:
			continue  # floating fx
		top = maxf(top, ab.end.y)
	var p := Vector3(0, maxf(top, 0.6) + GAP, -FORWARD)
	model.set_meta("carry_point", p)
	model.set_meta("carry_key", key)
	return p
