class_name Waypoint
extends Node3D
## [onboard] "Where do I go?" (playtest 2: "Read a memory shard ... I don't know where to go").
## A soft purple light beam stands on the current objective's target, a thin ring at its foot,
## and a short trail of glowing chevrons runs along the ground from Lumi toward it, flowing
## forward. Hidden near the target, with the HUD, and while there is nothing to point at.
## Reduced motion: the chevrons don't flow.

const COLOR := Color(0.74, 0.48, 1.0)
const TRAIL_N: int = 9
const TRAIL_STEP_M: float = 1.7
const TRAIL_START_M: float = 1.6
const NEAR_M: float = 3.0

const SHADER_CODE: String = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(0.74, 0.48, 1.0, 1.0);
uniform float alpha = 1.0;
uniform float energy = 1.8;
uniform bool beam = false;
void fragment() {
	float a;
	if (beam) {
		float across = 1.0 - abs(UV.x - 0.5) * 2.0;
		a = pow(across, 3.0) * (1.0 - UV.y) * 0.55;
	} else {
		a = COLOR.a;
	}
	ALBEDO = tint.rgb * energy;
	ALPHA = clamp(a * alpha, 0.0, 1.0);
}
"""

var world: Node
var _target: Variant = null
var _alpha: float = 0.0
var _t: float = 0.0
var _beam: MeshInstance3D
var _ring: MeshInstance3D
var _trail: MultiMeshInstance3D
var _mat_beam: ShaderMaterial
var _mat: ShaderMaterial
var _pos := Vector3.ZERO

static var _shader: Shader


func _ready() -> void:
	top_level = true
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_mat_beam = ShaderMaterial.new()
	_mat_beam.shader = _shader
	_mat_beam.set_shader_parameter("beam", true)
	_beam = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 12.0)
	q.center_offset = Vector3(0, 6.0, 0)
	_beam.mesh = q
	_beam.material_override = _mat_beam
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.62
	tm.outer_radius = 0.66
	tm.rings = 40
	tm.ring_segments = 3
	_ring.mesh = tm
	_ring.material_override = _mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_trail = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _chevron()
	mm.instance_count = TRAIL_N
	_trail.multimesh = mm
	_trail.material_override = _mat
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail)
	visible = false


## World position to point at, or null for none.
func set_target(p: Variant) -> void:
	_target = p


func _process(delta: float) -> void:
	_t += delta
	var p: Patch = world.get("patch") as Patch if world else null
	var hud_on: bool = world != null and (world.get("hud") == null or (world.hud as CanvasLayer).visible)
	var modal: bool = world != null and world.has_method("any_modal_open") and bool(world.call("any_modal_open"))
	var has: bool = _target is Vector3 and p != null and hud_on and not modal
	if has:
		var tp: Vector3 = _target
		has = Vector2(tp.x - p.global_position.x, tp.z - p.global_position.z).length() > NEAR_M
	_alpha = move_toward(_alpha, 1.0 if has else 0.0, delta * (2.0 if has else 3.0))
	visible = _alpha > 0.0
	if not visible or not (_target is Vector3) or p == null:
		return
	var goal: Vector3 = _target
	_pos = goal if _pos.distance_to(goal) > 30.0 or _pos == Vector3.ZERO else _pos.lerp(goal, clampf(delta * 6.0, 0.0, 1.0))
	var pulse: float = 0.85 + 0.15 * sin(_t * 2.2)
	_mat.set_shader_parameter("alpha", _alpha * pulse)
	_mat_beam.set_shader_parameter("alpha", _alpha * pulse)
	_beam.global_position = _pos
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam:  # the beam is a camera-facing strip (cylindrical billboard)
		var to: Vector3 = (cam.global_position - _pos) * Vector3(1, 0, 1)
		if to.length() > 0.01:
			_beam.global_basis = Basis.looking_at(-to.normalized(), Vector3.UP)
	_ring.global_position = _pos + Vector3(0, 0.05, 0)
	_ring.scale = Vector3.ONE * (1.0 + 0.08 * sin(_t * 2.2))
	_update_trail(p.global_position, _pos)


func _update_trail(from: Vector3, to: Vector3) -> void:
	var mm: MultiMesh = _trail.multimesh
	var d := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var dist: float = d.length()
	var dir: Vector3 = d / maxf(dist, 0.001)
	var flow: float = 0.0 if Settings.reduced_motion else fmod(_t * 1.4, TRAIL_STEP_M)
	var f: HexField = world.get("field") as HexField
	for i: int in TRAIL_N:
		var s: float = TRAIL_START_M + i * TRAIL_STEP_M + flow
		var a: float = 0.0
		if s < dist - 1.0:
			a = clampf((s - TRAIL_START_M) / 1.2, 0.0, 1.0) * clampf(1.0 - float(i) / TRAIL_N, 0.0, 1.0)
			a = minf(a, clampf((dist - 1.0 - s) / 1.5, 0.0, 1.0))
		var pt: Vector3 = from + dir * s
		var y: float = 0.06
		if f:
			var lay: CityLayout = f.layout
			y += lay.height_at(pt.x, pt.z) if lay else 0.0
			y += f.ground_height(f.hex_at(pt), pt)
		var xf := Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(pt.x, y, pt.z))
		mm.set_instance_transform(i, xf)
		mm.set_instance_color(i, Color(1, 1, 1, a * 0.9))


## A flat chevron pointing along -Z (Basis.looking_at's forward), 0.5 m wide.
static func _chevron() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w: float = 0.07
	var pts: Array[Vector3] = [Vector3(-0.25, 0, 0.12), Vector3(0, 0, -0.14), Vector3(0.25, 0, 0.12)]
	for k: int in 2:
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[k + 1]
		var n: Vector3 = Vector3(0, 1, 0).cross(b - a).normalized() * w
		var quad: Array[Vector3] = [a - n, a + n, b + n, b - n]
		for idx: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color.WHITE)
			st.add_vertex(quad[idx])
	return st.commit()
