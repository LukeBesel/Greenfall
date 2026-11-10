class_name MaterialBatch
extends RefCounted
## Merges primitive meshes per material into one ArrayMesh each, so a layer of static props is a
## handful of draw calls. (The frontier districts' batcher, kept for the later planets' sites.)

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
static func beam_xf(a: Vector3, b: Vector3, thick: float) -> Transform3D:
	var d: Vector3 = b - a
	var len_: float = d.length()
	var y: Vector3 = d / maxf(len_, 0.0001)
	var x: Vector3 = y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z: Vector3 = x.cross(y).normalized()
	return Transform3D(Basis(x * thick, y * len_, z * thick), (a + b) * 0.5)
