class_name ObjectiveHex
extends Node3D
## [onboard] Outlines an objective's target hex on the ground: a thin glowing line along the cell's
## border, a faint wash just inside it and a slow light running along it (the % is on the card and the HUD line).
## The line warms from cyan toward green as the hex clears. Fades between targets; hides with the
## HUD (cinematics, menus) and the reduced-motion setting stops the running light.

const CYAN := Color(0.5, 0.88, 1.0)
const GREEN := Color(0.55, 1.0, 0.7)
const WIDTH_M: float = 0.22  ## the ribbon (the bright core in the shader is ~1/4 of it)
const WASH_M: float = 0.7  ## the inner wash band
const LIFT_M: float = 0.045
const MIN_LOOP_M: float = 2.0  ## drop warp islands smaller than this
const HEIGHT_REFRESH_S: float = 0.6

const SHADER_CODE: String = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(0.5, 0.88, 1.0, 1.0);
uniform float alpha = 1.0;
uniform float energy = 2.1;
uniform float run = 1.0;
void fragment() {
	float a;
	if (COLOR.a > 0.5) {
		float d = abs(UV.y - 0.5) * 2.0;
		float core = 1.0 - smoothstep(0.12, 0.3, d);
		float halo = exp(-d * d * 7.0) * 0.28;
		float runner = pow(0.5 + 0.5 * sin(UV.x * 0.55 - TIME * 1.6), 14.0) * run;
		a = (core + halo) * (0.72 + 0.6 * runner);
	} else {
		a = pow(1.0 - UV.y, 2.2) * 0.05;
	}
	ALBEDO = tint.rgb * energy;
	ALPHA = clamp(a * alpha, 0.0, 1.0);
}
"""

var world: Node
## [onboard] The focus outline (the hex Lumi stands in) is dimmer and has no % label.
var show_label: bool = false  # owner: no floating text; the % is on the card and the HUD line
var strength: float = 1.0
var hex: int = -1
var _want: int = -1
var _alpha: float = 0.0
var _mat: ShaderMaterial
var _mi: MeshInstance3D
var _label: Label3D
var _loops: Array[PackedVector2Array] = []
var _inward: Array[float] = []
var _height_t: float = 0.0
var _cache: Dictionary = {}  # hex -> loops

static var _shader: Shader


func _ready() -> void:
	top_level = true
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_mi = MeshInstance3D.new()
	_mi.material_override = _mat
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true  # a steady ~24 px at 720p however far the camera is
	_label.font = UITheme.font()
	_label.font_size = 64
	_label.pixel_size = 0.0008
	_label.outline_size = 14
	_label.outline_modulate = Color(0, 0, 0, 0.55)
	_label.modulate = Color(0.85, 0.97, 1.0)
	_label.render_priority = 2
	_label.outline_render_priority = 1
	add_child(_label)
	visible = false


## Shows the outline around hex h (-1 hides it). A new hex fades in after the old one fades out.
func set_hex(h: int) -> void:
	_want = h


func _process(delta: float) -> void:
	if world == null or world.get("field") == null:
		return
	var f: SphereField = world.field
	var hud_on: bool = world.get("hud") == null or (world.hud as CanvasLayer).visible
	var modal: bool = world.has_method("any_modal_open") and bool(world.call("any_modal_open"))
	var show_: bool = _want >= 0 and _want == hex and hud_on and not modal
	_alpha = move_toward(_alpha, 1.0 if show_ else 0.0, delta * (1.6 if show_ else 3.5))
	if _want != hex and _alpha <= 0.0:
		hex = _want
		if hex >= 0:
			_build(f)
	visible = _alpha > 0.0 and hex >= 0
	if not visible:
		return
	var frac: float = f.removed_fraction(hex)
	_mat.set_shader_parameter("alpha", strength * _alpha * (0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.0021)))
	_mat.set_shader_parameter("tint", CYAN.lerp(GREEN, clampf(frac, 0.0, 1.0)))
	_mat.set_shader_parameter("run", 0.0 if Settings.reduced_motion else 1.0)
	_label.text = "%d%%" % int(floor(frac * 100.0))
	_label.visible = show_label
	_label.modulate.a = _alpha
	_label.outline_modulate.a = 0.55 * _alpha
	_height_t -= delta
	if _height_t <= 0.0:  # junk mounds settle as the hex is cleaned: keep the line on the ground
		_height_t = HEIGHT_REFRESH_S
		_mesh(f)


## This node sits on the cell's centre with local up (+Y); loops are in metres east/south of it,
## along the cell's real corners (subdivided so the line hugs the terrain).
func _build(f: SphereField) -> void:
	var ctr: Vector3 = f.grid.centers[hex]
	var fr: Basis = SphereGrid.frame(ctr)
	global_transform = Transform3D(fr, f.terrain.ground(ctr))
	if not _cache.has(hex):
		var loop := PackedVector2Array()
		var cs: PackedVector3Array = f.grid.corners(hex)
		for k: int in cs.size():
			var a: Vector3 = cs[k] - ctr
			var b: Vector3 = cs[(k + 1) % cs.size()] - ctr
			var pa := Vector2(a.dot(fr.x), a.dot(fr.z)) * f.grid.radius_m
			var pb := Vector2(b.dot(fr.x), b.dot(fr.z)) * f.grid.radius_m
			for s: int in 6:
				loop.append(pa.lerp(pb, s / 6.0))
		var arr: Array[PackedVector2Array] = [loop]
		_cache[hex] = arr
	_loops = _cache[hex]
	_inward.clear()
	for loop: PackedVector2Array in _loops:  # the left normal points in when it faces the centre
		var a: Vector2 = loop[0]
		var t: Vector2 = (loop[1] - a).normalized()
		_inward.append(1.0 if Vector2(-t.y, t.x).dot(-a) >= 0.0 else -1.0)
	_height_t = 0.0
	_mesh(f)
	_label.position = Vector3(0.0, _surface(f, 0.0, 0.0) + 1.9, 0.0)


## Ground (+ heap) height in this node's frame.
func _surface(f: SphereField, x: float, z: float) -> float:
	var ctr: Vector3 = f.grid.centers[hex]
	var fr: Basis = SphereGrid.frame(ctr)
	var d: Vector3 = (ctr + (fr.x * x + fr.z * z) / f.grid.radius_m).normalized()
	var g: Vector3 = f.terrain.ground(d)
	g += d * f.ground_height(hex, g)
	return (global_transform.affine_inverse() * g).y


func _mesh(f: SphereField) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for li: int in _loops.size():
		var loop: PackedVector2Array = _loops[li]
		var inw: float = _inward[li]
		var n: int = loop.size()
		var ys := PackedFloat32Array()
		ys.resize(n)
		for i: int in n:
			ys[i] = _surface(f, loop[i].x, loop[i].y) + LIFT_M
		var dist: float = 0.0
		for i: int in n:
			var j: int = (i + 1) % n
			var seg: float = loop[i].distance_to(loop[j])
			_quad(st, loop, ys, i, dist, dist + seg, inw, true)
			_quad(st, loop, ys, i, dist, dist + seg, inw, false)
			dist += seg
	_mi.mesh = st.commit()


static func _normal_at(loop: PackedVector2Array, i: int) -> Vector2:
	var n: int = loop.size()
	var t: Vector2 = (loop[(i + 1) % n] - loop[(i - 1 + n) % n]).normalized()
	return Vector2(-t.y, t.x)


## One segment of the line ribbon (line = true) or of the inner wash band.
func _quad(st: SurfaceTool, loop: PackedVector2Array, ys: PackedFloat32Array, i: int, u0: float, u1: float, inw: float, line: bool) -> void:
	var n: int = loop.size()
	var j: int = (i + 1) % n
	var na: Vector2 = _normal_at(loop, i) * inw
	var nb: Vector2 = _normal_at(loop, j) * inw
	var a: Vector2 = loop[i]
	var b: Vector2 = loop[j]
	var v: Array[Vector3] = []
	var uv: Array[Vector2] = []
	if line:
		var h: float = WIDTH_M * 0.5
		v = [_v3(a - na * h, ys[i]), _v3(a + na * h, ys[i]), _v3(b + nb * h, ys[j]), _v3(b - nb * h, ys[j])]
		uv = [Vector2(u0, 0.0), Vector2(u0, 1.0), Vector2(u1, 1.0), Vector2(u1, 0.0)]
	else:
		v = [_v3(a, ys[i] - 0.005), _v3(a + na * WASH_M, ys[i] - 0.005), _v3(b + nb * WASH_M, ys[j] - 0.005), _v3(b, ys[j] - 0.005)]
		uv = [Vector2(u0, 0.0), Vector2(u0, 1.0), Vector2(u1, 1.0), Vector2(u1, 0.0)]
	var col := Color(1, 1, 1, 1.0 if line else 0.0)
	for k: int in [0, 1, 2, 0, 2, 3]:
		st.set_color(col)
		st.set_uv(uv[k])
		st.add_vertex(v[k])


static func _v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)
