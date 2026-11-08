class_name Waypoint
extends Node3D
## [onboard] "Where do I go?" (playtest 2: "Read a memory shard ... I don't know where to go").
## A soft purple light beam stands on the current objective's target, a thin ring at its foot,
## and a short trail of glowing chevrons runs along the ground from Lumi toward it, flowing
## forward. Hidden near the target, with the HUD, and while there is nothing to point at.
## Reduced motion: the chevrons don't flow.
## [v1guide] Owner 2026-11-08 #17: the markers were barely noticeable on the globe. The beam is now
## a tall shaft of light up into the sky (BEAM_H, with a bright core) and the ground gets a wide
## glowing ring with a pulse running out from it, all oriented to the local up (OrbitUp), so it
## stands straight on the round planet; the trail follows the globe's ground.

const COLOR := Color(0.74, 0.48, 1.0)
const TRAIL_N: int = 9
const TRAIL_STEP_M: float = 1.7
const TRAIL_START_M: float = 1.6
const NEAR_M: float = 3.0
## [v1guide] The sky beam: tall enough to read from across the yard and over junk heaps.
const BEAM_H: float = 70.0
const BEAM_W: float = 1.6
const RING_R: float = 2.4
## [onboard2] Off-screen target: a small arrow on the screen edge, inside this thin band (px) that
## the HUD keeps free (no text, nothing else lives there).
const EDGE_INSET: float = 14.0

const SHADER_CODE: String = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(0.74, 0.48, 1.0, 1.0);
uniform float alpha = 1.0;
uniform float energy = 1.8;
uniform bool beam = false;
uniform bool disc = false;
uniform float pulse = 0.0;
void fragment() {
	float a;
	vec3 col = tint.rgb * energy;
	if (beam) {
		float across = 1.0 - abs(UV.x - 0.5) * 2.0;
		float up = 1.0 - UV.y;  // 0 at the top, 1 at the foot
		float soft = pow(across, 2.2) * (0.25 + 0.75 * pow(up, 1.6));
		float core = pow(across, 14.0) * (0.35 + 0.65 * up);
		a = soft * 0.6 + core * 0.9;
		col = mix(col, vec3(1.0, 0.92, 1.0) * energy, core * 0.6);
	} else if (disc) {
		float r = length(UV - vec2(0.5)) * 2.0;  // 0 centre, 1 edge
		float band = exp(-pow((r - 0.78) / 0.05, 2.0));
		float inner = smoothstep(0.78, 0.0, r) * 0.12;
		float wave = exp(-pow((r - pulse) / 0.04, 2.0)) * (1.0 - pulse) * 0.9;
		a = band + inner + wave * step(r, 1.0);
	} else {
		a = COLOR.a;
	}
	ALBEDO = col;
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
var _mat_disc: ShaderMaterial  # [v1guide] the ground ring
var _pos := Vector3.ZERO
var _arrow_layer: CanvasLayer
var arrow: EdgeArrow

static var _shader: Shader
static var _shader_mix: Shader  # [qafix]
var _mat_trail: ShaderMaterial  # [qafix]


func _ready() -> void:
	top_level = true
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	# [qafix] QA #36: additive chevrons washed out to a thin white line on pale ground; the trail
	# blends normally so it stays purple everywhere (the beam and ring still glow additively).
	if _shader_mix == null:
		_shader_mix = Shader.new()
		_shader_mix.code = SHADER_CODE.replace("blend_add", "blend_mix")
	_mat_trail = ShaderMaterial.new()
	_mat_trail.shader = _shader_mix
	_mat_trail.set_shader_parameter("energy", 1.0)
	_mat_beam = ShaderMaterial.new()
	_mat_beam.shader = _shader
	_mat_beam.set_shader_parameter("beam", true)
	_beam = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(BEAM_W, BEAM_H)
	q.center_offset = Vector3(0, BEAM_H * 0.5, 0)
	_beam.mesh = q
	_beam.material_override = _mat_beam
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.extra_cull_margin = BEAM_H
	add_child(_beam)
	# [v1guide] A wide flat ring on the ground (a disc drawn as a glowing band + an outward pulse).
	_mat_disc = ShaderMaterial.new()
	_mat_disc.shader = _shader
	_mat_disc.set_shader_parameter("disc", true)
	_mat_disc.set_shader_parameter("energy", 2.2)
	_ring = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(RING_R * 2.0 / 0.78, RING_R * 2.0 / 0.78)
	_ring.mesh = pm
	_ring.material_override = _mat_disc
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_trail = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _chevron()
	mm.instance_count = TRAIL_N
	_trail.multimesh = mm
	_trail.material_override = _mat_trail  # [qafix]
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail)
	visible = false
	_arrow_layer = CanvasLayer.new()
	_arrow_layer.layer = 1
	add_child(_arrow_layer)
	arrow = EdgeArrow.new()
	arrow.color = COLOR
	_arrow_layer.add_child(arrow)
	arrow.visible = false


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
		has = OrbitUp.ground_dist(p.global_position, _target as Vector3) > NEAR_M  # [v1guide] along the ground (globe too)
	_alpha = move_toward(_alpha, 1.0 if has else 0.0, delta * (2.0 if has else 3.0))
	visible = _alpha > 0.0
	if not visible or not (_target is Vector3) or p == null:
		arrow.visible = false
		return
	var goal: Vector3 = _target
	_pos = goal if _pos.distance_to(goal) > 30.0 or _pos == Vector3.ZERO else _pos.lerp(goal, clampf(delta * 6.0, 0.0, 1.0))
	var pulse: float = 0.85 + 0.15 * sin(_t * 2.2)
	_mat.set_shader_parameter("alpha", _alpha * pulse)
	_mat_beam.set_shader_parameter("alpha", _alpha * pulse)
	_mat_disc.set_shader_parameter("alpha", _alpha)
	_mat_disc.set_shader_parameter("pulse", 0.4 if Settings.reduced_motion else fmod(_t * 0.55, 1.0))
	_mat_trail.set_shader_parameter("alpha", _alpha * pulse)  # [qafix]
	var up: Vector3 = OrbitUp.up(_pos)  # [v1guide] local up: straight on the round planet
	_beam.global_position = _pos
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam:  # the beam is a camera-facing strip turning about the local up (cylindrical billboard)
		var to: Vector3 = cam.global_position - _pos
		to -= up * to.dot(up)
		if to.length() > 0.01:
			var z: Vector3 = to.normalized()
			_beam.global_basis = Basis(up.cross(z).normalized(), up, z)
	_ring.global_basis = _up_basis(up)
	_ring.global_position = _pos + up * 0.12
	_update_trail(p.global_position, _pos)
	_update_arrow(cam)


## [v1guide] A basis with +Y along `up` (any yaw).
static func _up_basis(up: Vector3) -> Basis:
	var ref: Vector3 = Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x: Vector3 = ref.cross(up).normalized()
	return Basis(x, up, x.cross(up).normalized()).orthonormalized()


## [onboard2] When the beam is off screen, a small arrow on the screen edge points toward it.
func _update_arrow(cam: Camera3D) -> void:
	if cam == null:
		arrow.visible = false
		return
	var rect: Rect2 = get_viewport().get_visible_rect().grow(-EDGE_INSET)
	var pt: Vector3 = _pos + OrbitUp.up(_pos) * 1.5
	var local: Vector3 = cam.global_transform.affine_inverse() * pt
	if not cam.is_position_behind(pt) and rect.has_point(cam.unproject_position(pt)):
		arrow.visible = false
		return
	var dir := Vector2(local.x, -local.y)
	if local.z > 0.0 and absf(dir.x) < 0.001:  # straight behind: point down (turn around)
		dir = Vector2(0, 1)
	arrow.visible = true
	arrow.place(edge_point(rect, dir), dir.angle(), _alpha)


## Where a ray from the rect's centre along dir leaves the rect.
static func edge_point(rect: Rect2, dir: Vector2) -> Vector2:
	var c: Vector2 = rect.get_center()
	var h: Vector2 = rect.size * 0.5
	if dir.length_squared() < 1e-8:
		return c
	var tx: float = h.x / absf(dir.x) if absf(dir.x) > 1e-6 else INF
	var ty: float = h.y / absf(dir.y) if absf(dir.y) > 1e-6 else INF
	return c + dir * minf(tx, ty)


func _update_trail(from: Vector3, to: Vector3) -> void:
	var mm: MultiMesh = _trail.multimesh
	var up0: Vector3 = OrbitUp.up(from)
	var d: Vector3 = to - from
	d -= up0 * d.dot(up0)  # [v1guide] along the ground (the flat game: the x/z plane)
	var dist: float = d.length()
	var dir: Vector3 = d / maxf(dist, 0.001)
	var flow: float = 0.0 if Settings.reduced_motion else fmod(_t * 1.4, TRAIL_STEP_M)
	var f: HexField = world.get("field") as HexField
	var sf: SphereField = f as SphereField
	for i: int in TRAIL_N:
		var s: float = TRAIL_START_M + i * TRAIL_STEP_M + flow
		var a: float = 0.0
		if s < dist - 1.0:
			a = clampf((s - TRAIL_START_M) / 1.2, 0.0, 1.0) * clampf(1.0 - float(i) / TRAIL_N, 0.0, 1.0)
			a = minf(a, clampf((dist - 1.0 - s) / 1.5, 0.0, 1.0))
		var pt: Vector3 = from + dir * s
		var xf: Transform3D
		if sf:  # [v1guide] on the globe: on the ground under the point, facing along it
			var n: Vector3 = pt.normalized()
			var g: Vector3 = sf.terrain.ground(n) + n * (0.08 + sf.ground_height(sf.hex_at(pt), pt))
			var fw: Vector3 = (dir - n * dir.dot(n)).normalized()
			xf = Transform3D(Basis.looking_at(fw, n), g)
		else:
			var y: float = 0.06
			if f:
				var lay: CityLayout = f.layout
				y += lay.height_at(pt.x, pt.z) if lay else 0.0
				y += f.ground_height(f.hex_at(pt), pt)
			xf = Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(pt.x, y, pt.z))
		mm.set_instance_transform(i, xf)
		mm.set_instance_color(i, Color(1, 1, 1, a * 0.9))


## A flat chevron pointing along -Z (Basis.looking_at's forward), 0.5 m wide.
static func _chevron() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w: float = 0.1  # [qafix] QA #36: a little bolder (was 0.07)
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
