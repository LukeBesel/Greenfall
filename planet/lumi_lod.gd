class_name LumiLod
extends Node
## [orbE] Lumi's model at a distance (Command view, 30-400 m up): the rig is 27 meshes / 64
## surfaces, nearly all casting shadows (~190 draws). Past SWITCH_M a proxy takes over: the same
## meshes merged into one surface per material (shared materials, so glow and colours match),
## no shadow. Visibility ranges do the switch on the GPU side; the proxy is rebuilt from the
## current rig (pose, cosmetics) every few seconds while the camera is far, never when near.

const SWITCH_M: float = 30.0
const MARGIN_M: float = 3.0
const REFRESH_S: float = 4.0

var model: Node3D
var cam_fn: Callable  # () -> Vector3 camera position
var proxy: MeshInstance3D
var stats: Dictionary = {"surfaces_in": 0, "surfaces_out": 0}
var _t: float = 0.0
var _rig: Array[MeshInstance3D] = []


func setup(p_model: Node3D, p_cam_fn: Callable) -> void:
	model = p_model
	cam_fn = p_cam_fn
	rebuild()


## Re-merge the rig's visible meshes into the proxy and set the visibility ranges.
func rebuild() -> void:
	if model == null or not is_instance_valid(model):
		return
	if proxy and is_instance_valid(proxy):
		proxy.get_parent().remove_child(proxy)
		proxy.free()
	proxy = null
	_rig.clear()
	var groups: Dictionary = {}
	var order: Array = []
	var n_in: int = 0
	for n: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		if mi.mesh == null or not mi.is_visible_in_tree() or mi.skin != null:
			continue
		var xf: Transform3D = _relative(mi)
		for s: int in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(s)
			var key: Array = [mat.get_instance_id() if mat else 0, PropBatch._format(mi.mesh, s)]
			var g: Dictionary = groups.get(key, {})
			if g.is_empty():
				g = {"st": SurfaceTool.new(), "mat": mat}
				groups[key] = g
				order.append(key)
			(g["st"] as SurfaceTool).append_from(mi.mesh, s, xf)
			n_in += 1
		mi.visibility_range_end = SWITCH_M
		mi.visibility_range_end_margin = MARGIN_M
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		_rig.append(mi)
	if order.is_empty():
		return
	var am := ArrayMesh.new()
	for key: Array in order:
		var g: Dictionary = groups[key]
		(g["st"] as SurfaceTool).commit(am)
		am.surface_set_material(am.get_surface_count() - 1, g["mat"])
	proxy = MeshInstance3D.new()
	proxy.name = "LumiFar"
	proxy.mesh = am
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	proxy.visibility_range_begin = SWITCH_M
	proxy.visibility_range_begin_margin = MARGIN_M
	model.add_child(proxy)
	stats = {"surfaces_in": n_in, "surfaces_out": am.get_surface_count()}


func _process(delta: float) -> void:
	if model == null or not is_instance_valid(model) or not cam_fn.is_valid():
		return
	_t += delta
	if _t < REFRESH_S:
		return
	_t = 0.0
	var far: bool = (cam_fn.call() as Vector3).distance_to(model.global_position) > SWITCH_M - MARGIN_M
	if far:
		rebuild()  # the far view shows the rig as it is now (cosmetics, held items)


func _relative(n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != model:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf
