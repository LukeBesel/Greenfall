class_name CarryPoint
extends RefCounted
## [world2] Where Lumi holds carried bales: clearly ABOVE the body (playtest #2: "carrying a bale
## looks like it's inside Lumi"). The top of the model's solid parts (thin antennae and fins
## ignored) in Lumi's local space, plus a small gap, a touch forward of centre so the stack reads in
## front of the head from the follow camera. Cached per model (the design can change).
## [v6feel] Use `frame(model, holder) * of(model, holder)` for the point in the holder's space.

const GAP: float = 0.2  # [v1guide] owner 2026-11-08 #22: a carried bale still clipped (was 0.12)
const FORWARD: float = 0.08


static func of(model: Node3D, holder: Node3D) -> Vector3:
	if model == null:
		return Vector3(0, 1.4, 0)
	# [v6feel] The key follows the built parts: a Character Builder change rebuilds the model under
	# the same design name (a taller head part kept the old, lower point).
	var built: Variant = model.get("_root")
	var key: String = "%d|%s|%d" % [model.get_instance_id(), str(model.get("variant")), (built as Object).get_instance_id() if built is Object and is_instance_valid(built) else 0]
	if model.has_meta("carry_point") and str(model.get_meta("carry_key", "")) == key:
		return model.get_meta("carry_point")
	var top: float = 0.0
	var inv: Transform3D = frame(model, holder).affine_inverse() * holder.global_transform.affine_inverse()
	for n: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		# [v6feel] Hidden parts only (a put-away prop). Not is_visible_in_tree(): with Lumi himself
		# hidden (inside the rocket, behind the loader) every mesh was skipped, and the point was
		# cached at 0.8 m, inside his body, for the rest of the session.
		if mi.mesh == null or not _shown_in(mi, model) or mi.top_level:
			continue
		var ab: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
		if ab.size.x < 0.12 and ab.size.z < 0.12:
			continue  # antenna, wire, fin
		if ab.position.y > 2.5:
			continue  # floating fx
		top = maxf(top, ab.end.y)
	var p := Vector3(0, maxf(top, 0.6) + GAP, -FORWARD)
	if top <= 0.0:
		return Vector3(0, 1.4, -FORWARD)  # nothing built yet: a safe height, not cached
	model.set_meta("carry_point", p)
	model.set_meta("carry_key", key)
	return p


static func _shown_in(n: Node3D, model: Node3D) -> bool:
	var cur: Node = n
	while cur != null and cur != model:
		if cur is Node3D and not (cur as Node3D).visible:
			return false
		cur = cur.get_parent()
	return true


## [v6feel] The space the point lives in, as seen from the holder: Lumi's floating body (it bobs,
## leans into a run and squashes), so the stack rides his lean rigidly and the gap over his head is
## the same in every pose. Identity for a model without one.
static func frame(model: Node3D, holder: Node3D) -> Transform3D:
	var fl: Variant = model.get("_float") if model else null
	if fl is Node3D and is_instance_valid(fl) and (fl as Node3D).is_inside_tree():
		return holder.global_transform.affine_inverse() * (fl as Node3D).global_transform
	return Transform3D.IDENTITY
