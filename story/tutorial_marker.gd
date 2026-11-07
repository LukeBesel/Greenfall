class_name TutorialMarker
extends Node3D
## [first] In-world pointer for the restart checklist: a soft amber chevron that floats over the
## thing the current step is about (a piece of junk, Lumi's hopper, the bale, the scale, the
## workbench), a thin ground ring around it, and a small edge arrow when it is off screen.
## Glides between targets instead of snapping; hides with the HUD (cinematics, menus).
## Reduced motion: no bob or pulse.

const COLOR := Color(1.0, 0.76, 0.36)
## kind -> [chevron height above the target, ground ring radius (0 = none)]
const KINDS: Dictionary = {
	"piece": [1.05, 0.5], "self": [0.75, 0.0], "bale": [1.0, 0.65], "pad": [1.7, 1.85], "bench": [1.9, 0.9],
}

var world: Node
var _chev: MeshInstance3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _chev_mat: StandardMaterial3D
var _edge: Control
var _layer: CanvasLayer
var _kind: String = ""
var _goal := Vector3.ZERO
var _pos := Vector3.ZERO
var _has: bool = false
var _alpha: float = 0.0
var _t: float = 0.0
var _finishing: bool = false


func _ready() -> void:
	top_level = true
	_chev_mat = _material(true)
	_chev = MeshInstance3D.new()
	_chev.mesh = _chevron_mesh()
	_chev.material_override = _chev_mat
	_chev.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_chev)
	_ring_mat = _material(false)
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.93
	tm.outer_radius = 1.0
	tm.rings = 48
	tm.ring_segments = 4
	_ring.mesh = tm
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_layer = CanvasLayer.new()
	_layer.layer = 4
	add_child(_layer)
	_edge = Control.new()
	_edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.draw.connect(_draw_edge)
	_layer.add_child(_edge)
	visible = false


static func _material(billboard: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = COLOR
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.no_depth_test = true
		m.render_priority = 10
	return m


## A flat downward chevron in the XY plane (billboarded by the material).
static func _chevron_mesh() -> ArrayMesh:
	var pts := PackedVector2Array([Vector2(-0.17, 0.12), Vector2(-0.1, 0.12), Vector2(0.0, 0.02),
		Vector2(0.1, 0.12), Vector2(0.17, 0.12), Vector2(0.0, -0.08)])
	var idx: PackedInt32Array = Geometry2D.triangulate_polygon(pts)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in idx:
		st.add_vertex(Vector3(pts[i].x, pts[i].y, 0.0))
	return st.commit()


func set_target(pos: Vector3, kind: String) -> void:
	if _finishing:
		return
	var jump: bool = not _has or pos.distance_to(_goal) > 9.0
	_goal = pos
	if kind != _kind:
		_kind = kind
		jump = jump or kind == "self"
	if jump:
		_pos = pos
		if _alpha > 0.0 and _has:
			_alpha = 0.0  # fade in fresh at the new spot rather than streak across the map
	_has = true


func clear() -> void:
	_has = false


## Checklist done: a quick bright pulse, then fade out and free.
func finish() -> void:
	_finishing = true
	_has = false
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_callback(queue_free)


func shown_alpha() -> float:
	return _alpha


func _process(delta: float) -> void:
	_t += delta
	var hud: CanvasLayer = world.get("hud") as CanvasLayer if world else null
	var blocked: bool = (hud != null and not hud.visible) or (world != null and world.has_method("any_modal_open") and bool(world.call("any_modal_open")))
	var want: float = 1.0 if _has and not blocked else 0.0
	_alpha = move_toward(_alpha, want, delta * (2.5 if want > _alpha else 4.0))
	visible = _alpha > 0.01
	_edge.visible = visible
	if not visible:
		return
	if _kind == "self":
		_pos = _goal
	else:
		_pos = _pos.lerp(_goal, clampf(delta * 9.0, 0.0, 1.0))
	var spec: Array = KINDS.get(_kind, [1.0, 0.5])
	var calm: bool = Settings.reduced_motion
	var bob: float = 0.0 if calm else sin(_t * 3.2) * 0.07
	_chev.global_position = _pos + Vector3(0, float(spec[0]) + bob, 0)
	var r: float = float(spec[1])
	_ring.visible = r > 0.0
	if r > 0.0:
		var pulse: float = 1.0 if calm else 1.0 + 0.06 * sin(_t * 3.2)
		_ring.global_position = Vector3(_pos.x, _ground_y(_pos) + 0.04, _pos.z)
		_ring.scale = Vector3(r * pulse, 0.25, r * pulse)
	# Near the target the chevron steps back so it never sits in Lumi's face.
	var near: float = 1.0
	var patch: Node3D = world.get("patch") as Node3D if world else null
	if patch and _kind != "self":
		near = clampf((patch.global_position.distance_to(_pos) - 0.8) / 2.0, 0.35, 1.0)
	_chev_mat.albedo_color = Color(COLOR, 0.9 * _alpha * near)
	_ring_mat.albedo_color = Color(COLOR, 0.5 * _alpha)
	_edge.queue_redraw()


func _ground_y(p: Vector3) -> float:
	return 0.0 if _kind != "pad" and _kind != "bench" else maxf(0.0, p.y)


## Off-screen: a small chevron at the screen edge pointing the way.
func _draw_edge() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var p: Vector3 = _chev.global_position
	var vs: Vector2 = _edge.size
	var behind: bool = cam.is_position_behind(p)
	var sp: Vector2 = cam.unproject_position(p)
	var margin: float = 46.0
	var on: bool = not behind and sp.x > margin and sp.x < vs.x - margin and sp.y > margin and sp.y < vs.y - margin
	if on:
		return
	var c: Vector2 = vs * 0.5
	var d: Vector2 = sp - c
	if behind:
		d = -d
		if d.length() < 1.0:
			d = Vector2(0, 1)
	var half: Vector2 = c - Vector2(margin, margin)
	var k: float = minf(half.x / maxf(absf(d.x), 0.001), half.y / maxf(absf(d.y), 0.001))
	var at: Vector2 = c + d * k
	var dir: Vector2 = d.normalized()
	var side := Vector2(-dir.y, dir.x)
	var col := Color(COLOR, 0.85 * _alpha)
	var tip: Vector2 = at + dir * 9.0
	var pts := PackedVector2Array([tip, at - dir * 6.0 + side * 9.0, at - dir * 2.0, at - dir * 6.0 - side * 9.0])
	_edge.draw_colored_polygon(pts, Color(0, 0, 0, 0.35 * _alpha))
	_edge.draw_polyline(PackedVector2Array([pts[1], tip, pts[3]]), col, 2.5, true)
