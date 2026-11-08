class_name ObjectiveHex
extends Node3D
## [onboard] Outlines an objective's target hex on the ground: a thin glowing line that follows the
## hex's natural border (the same HexField.border_warp the junk placement and the ground use), a
## faint wash just inside it and a slow light running along it (the % is on the card and the HUD line).
## The line warms from cyan toward green as the hex clears. Fades between targets; hides with the
## HUD (cinematics, menus) and the reduced-motion setting stops the running light.

const CYAN := Color(0.5, 0.88, 1.0)
const GREEN := Color(0.55, 1.0, 0.7)
const STEP_M: float = 0.25  ## contour grid spacing
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
var _cache: Dictionary = {}  # hex -> loops (contours cost ~30 ms; Lumi walks back and forth)

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
	var f: HexField = world.field
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


func _build(f: HexField) -> void:
	if f is SphereField:  # [orbB] the globe: the cell's own frame and corners
		_build_sphere(f as SphereField)
		return
	if not _cache.has(hex):
		_cache[hex] = contour(f, hex, maxf(STEP_M, f.hex_size * 0.06))
	_loops = _cache[hex]
	_inward.clear()
	for loop: PackedVector2Array in _loops:
		_inward.append(_inward_sign(f, loop))
	_height_t = 0.0
	_mesh(f)
	var c: Vector3 = f.hex_center(hex)
	_label.position = Vector3(c.x, _surface(f, c.x, c.z) + 1.9, c.z)


## +1 when a loop's left-hand normal points into the hex, else -1.
func _inward_sign(f: HexField, loop: PackedVector2Array) -> float:
	var n: int = loop.size()
	var vote: float = 0.0
	for k: int in [0, n / 3, (2 * n) / 3]:
		var a: Vector2 = loop[k]
		var b: Vector2 = loop[(k + 1) % n]
		var t: Vector2 = (b - a).normalized()
		var nl := Vector2(-t.y, t.x)
		vote += signf(inside_value(f, hex, a + nl * 0.3))
	return 1.0 if vote >= 0.0 else -1.0


## [orbB] On the globe this node sits on the cell's centre with local up (+Y); loops are in metres
## east/south of it, along the cell's real corners (subdivided so the line hugs the terrain).
func _build_sphere(f: SphereField) -> void:
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


func _surface(f: HexField, x: float, z: float) -> float:
	if f is SphereField and hex >= 0:  # [orbB] ground (+ heap) height in this node's frame
		var sf: SphereField = f
		var ctr: Vector3 = sf.grid.centers[hex]
		var fr: Basis = SphereGrid.frame(ctr)
		var d: Vector3 = (ctr + (fr.x * x + fr.z * z) / sf.grid.radius_m).normalized()
		var g: Vector3 = sf.terrain.ground(d)
		g += d * sf.ground_height(hex, g)
		return (global_transform.affine_inverse() * g).y
	var lay: CityLayout = f.layout
	var y: float = lay.height_at(x, z) if lay else 0.0
	var p := Vector3(x, 0.0, z)
	return y + f.ground_height(f.hex_at(p + (f.border_warp(p) if f.natural_borders else Vector3.ZERO)), p)


func _mesh(f: HexField) -> void:
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


# --- The contour (pure; tests) -----------------------------------------------------------------

## > 0 inside hex h, < 0 outside, 0 on its border: half the distance margin to the nearest
## neighbouring centre, measured at the warped position (hex cells are the Voronoi cells of the
## centres, so this is continuous and exact at the edges).
static func inside_value(f: HexField, h: int, p: Vector2) -> float:
	var p3 := Vector3(p.x, 0.0, p.y)
	if f.natural_borders:
		p3 += f.border_warp(p3)
	var w := Vector2(p3.x, p3.z)
	var a: Vector2i = f.hex_axial[h]
	var c: Vector2 = Hex.axial_to_world(a, f.hex_size)
	var dc: float = w.distance_to(c)
	var m: float = INF
	for d: Vector2i in Hex.DIRECTIONS:
		m = minf(m, w.distance_to(Hex.axial_to_world(a + d, f.hex_size)) - dc)
	return m * 0.5


## The hex's border as closed loops in the XZ plane (marching squares over inside_value, linear
## edge interpolation, one Chaikin pass). Warp islands under MIN_LOOP_M are dropped.
static func contour(f: HexField, h: int, step_m: float = STEP_M) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if h < 0 or h >= f.hex_count():
		return out
	var c3: Vector3 = f.hex_center(h)
	var ext: float = f.hex_size * 2.2 + step_m * 2.0
	var n: int = int(ceil(ext * 2.0 / step_m)) + 1
	var o := Vector2(c3.x - ext, c3.z - ext)
	var val := PackedFloat32Array()
	val.resize(n * n)
	for j: int in n:
		for i: int in n:
			val[j * n + i] = inside_value(f, h, o + Vector2(i, j) * step_m)
	# Edge ids: horizontal (i,j)-(i+1,j) = 2*(j*n+i); vertical (i,j)-(i,j+1) = 2*(j*n+i)+1.
	var pts: Dictionary = {}
	var adj: Dictionary = {}
	for j: int in n - 1:
		for i: int in n - 1:
			var v0: float = val[j * n + i]
			var v1: float = val[j * n + i + 1]
			var v2: float = val[(j + 1) * n + i + 1]
			var v3: float = val[(j + 1) * n + i]
			var code: int = (1 if v0 > 0.0 else 0) | (2 if v1 > 0.0 else 0) | (4 if v2 > 0.0 else 0) | (8 if v3 > 0.0 else 0)
			if code == 0 or code == 15:
				continue
			var eb: int = 2 * (j * n + i)  # bottom: (i,j)-(i+1,j)
			var er: int = 2 * (j * n + i + 1) + 1  # right: (i+1,j)-(i+1,j+1)
			var et: int = 2 * ((j + 1) * n + i)  # top: (i,j+1)-(i+1,j+1)
			var el: int = 2 * (j * n + i) + 1  # left: (i,j)-(i,j+1)
			var p00: Vector2 = o + Vector2(i, j) * step_m
			var p10: Vector2 = p00 + Vector2(step_m, 0)
			var p11: Vector2 = p00 + Vector2(step_m, step_m)
			var p01: Vector2 = p00 + Vector2(0, step_m)
			pts[eb] = _lerp0(p00, p10, v0, v1)
			pts[er] = _lerp0(p10, p11, v1, v2)
			pts[et] = _lerp0(p01, p11, v3, v2)
			pts[el] = _lerp0(p00, p01, v0, v3)
			var segs: Array = []
			match code:
				1, 14: segs = [[el, eb]]
				2, 13: segs = [[eb, er]]
				3, 12: segs = [[el, er]]
				4, 11: segs = [[er, et]]
				6, 9: segs = [[eb, et]]
				7, 8: segs = [[el, et]]
				5, 10:
					var mid: bool = (v0 + v1 + v2 + v3) * 0.25 > 0.0
					if (code == 5) == mid:
						segs = [[el, et], [eb, er]]
					else:
						segs = [[el, eb], [er, et]]
			for s: Array in segs:
				_link(adj, int(s[0]), int(s[1]))
				_link(adj, int(s[1]), int(s[0]))
	# Walk the segment graph into loops.
	var seen: Dictionary = {}
	for start: Variant in adj:
		if seen.has(start):
			continue
		var loop := PackedVector2Array()
		var prev: int = -1
		var cur: int = int(start)
		var length: float = 0.0
		while cur >= 0 and not seen.has(cur):
			seen[cur] = true
			if not loop.is_empty():
				length += loop[-1].distance_to(pts[cur])
			loop.append(pts[cur])
			var nxt: int = -1
			for e: Variant in adj[cur]:
				if int(e) != prev and not seen.has(e):
					nxt = int(e)
					break
			prev = cur
			cur = nxt
		if loop.size() >= 4 and length >= MIN_LOOP_M:
			out.append(_chaikin(loop))
	return out


static func _lerp0(a: Vector2, b: Vector2, va: float, vb: float) -> Vector2:
	var d: float = va - vb
	var t: float = 0.5 if absf(d) < 1e-6 else clampf(va / d, 0.0, 1.0)
	return a.lerp(b, t)


static func _link(adj: Dictionary, a: int, b: int) -> void:
	if not adj.has(a):
		adj[a] = []
	(adj[a] as Array).append(b)


## One pass of corner cutting on a closed loop: the marching-squares stair-steps become a curve.
static func _chaikin(loop: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n: int = loop.size()
	for i: int in n:
		var a: Vector2 = loop[i]
		var b: Vector2 = loop[(i + 1) % n]
		out.append(a.lerp(b, 0.25))
		out.append(a.lerp(b, 0.75))
	return out
