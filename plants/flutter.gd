class_name Flutter
extends Node3D
## [v6life] Small life over planted ground on the globe: butterflies by day, fireflies from dusk.
## A few per planted cell near Lumi (more as the cell's hex level rises), none over junk or bare
## clean ground, so the dirty world is still and the planted part isn't. (Fauna already brings the
## cats, birds, rabbits and fish; its own bees and fireflies need Sustained / Thriving ground,
## which a player sees late.)
## Cheap: two MultiMeshes (only one is drawn at a time), every wander, flap and blink runs in the
## vertex shader from the instance's home and phase; the CPU only re-homes instances when Lumi
## changes cell or a hex level changes. No sound, no colliders, nothing saved.

const RINGS: int = 4
const MAX_N: int = 24
## Butterflies per cell by hex level 0..5.
const PER_LEVEL: Array[int] = [0, 0, 1, 2, 2, 3]
const COLORS: Array[Color] = [Color(1.0, 0.62, 0.15), Color(0.96, 0.95, 0.85), Color(0.4, 0.6, 1.0), Color(1.0, 0.85, 0.25), Color(0.9, 0.45, 0.72)]

const BUTTERFLY: String = """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
varying vec3 tint;
varying float edge;
void vertex() {
	float ph = INSTANCE_CUSTOM.r * 6.283;
	float sp = 0.5 + INSTANCE_CUSTOM.g * 0.4;
	float t = TIME * sp + ph;
	float rad = 1.3 + INSTANCE_CUSTOM.b * 1.6;
	// A lazy figure round the home spot; the body turns to where it is going.
	vec3 off = vec3(sin(t * 0.7) * rad + sin(t * 1.9) * 0.3, 0.55 + sin(t * 1.3 + ph) * 0.3 + INSTANCE_CUSTOM.b * 0.5, cos(t * 0.53 + ph) * rad);
	vec2 vel = vec2(cos(t * 0.7) * 0.7 * rad + cos(t * 1.9) * 0.57, -sin(t * 0.53 + ph) * 0.53 * rad);
	float a = atan(vel.x, vel.y);
	float flap = sin(TIME * (11.0 + INSTANCE_CUSTOM.g * 5.0) + ph);
	vec3 v = VERTEX;
	v.y += abs(v.x) * flap * 0.9;
	v.x *= 1.0 - 0.35 * abs(flap);
	float c = cos(a);
	float s = sin(a);
	v = vec3(v.x * c + v.z * s, v.y, -v.x * s + v.z * c);
	VERTEX = v + off;
	tint = COLOR.rgb;
	edge = UV.x;
}
void fragment() {
	ALBEDO = tint * mix(1.0, 0.35, smoothstep(0.75, 1.0, edge));
	ROUGHNESS = 1.0;
}
"""

const FIREFLY: String = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform float amount = 1.0;
varying float glow;
void vertex() {
	float ph = INSTANCE_CUSTOM.r * 6.283;
	float t = TIME * (0.25 + INSTANCE_CUSTOM.g * 0.2) + ph;
	float rad = 1.0 + INSTANCE_CUSTOM.b * 2.2;
	vec3 off = vec3(sin(t * 0.9) * rad, 0.5 + sin(t * 0.6 + ph) * 0.35 + INSTANCE_CUSTOM.b * 0.7, cos(t * 0.7 + ph) * rad);
	glow = pow(max(sin(TIME * (0.9 + INSTANCE_CUSTOM.g * 0.8) + ph * 3.0), 0.0), 2.0) * amount;
	// Billboard: the quad faces the camera at the animated spot.
	vec3 centre = (MODEL_MATRIX * vec4(off, 1.0)).xyz;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 upv = INV_VIEW_MATRIX[1].xyz;
	vec3 wp = centre + (right * VERTEX.x + upv * VERTEX.y) * (0.6 + 0.4 * glow);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
}
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float core = smoothstep(1.0, 0.0, d);
	ALBEDO = vec3(0.85, 1.0, 0.35) * core * core * glow * 2.2;
}
"""

var cells: SphereCells
var grid: SphereGrid
var terrain: SphereTerrain
var world: Node
var shown: int = 0
var _bfly: MultiMeshInstance3D
var _ffly: MultiMeshInstance3D
var _fmat: ShaderMaterial
var _cell: int = -1
var _poll: float = 0.0
var _dirty: bool = true
var _night: float = 0.0


func setup(p_world: Node, globe: OrbitPlanet) -> void:
	name = "Flutter"
	world = p_world
	cells = globe.cells
	grid = globe.grid
	terrain = globe.terrain
	var bm := ShaderMaterial.new()
	var bs := Shader.new()
	bs.code = BUTTERFLY
	bm.shader = bs
	_bfly = _mmi("Butterflies", _wing_mesh(), bm)
	_fmat = ShaderMaterial.new()
	var fs := Shader.new()
	fs.code = FIREFLY
	_fmat.shader = fs
	var q := QuadMesh.new()
	q.size = Vector2(0.16, 0.16)
	_ffly = _mmi("Fireflies", q, _fmat)
	_ffly.visible = false
	EventBus.hex_level_changed.connect(func(_h: int, _l: int) -> void: _dirty = true)


## Two wings (a pair of triangles each side of the body line), about 0.26 m across.
static func _wing_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [-1.0, 1.0]:
		var pts: Array = [[Vector3(0, 0, -0.03), 0.0], [Vector3(0.13 * side, 0, -0.09), 1.0], [Vector3(0.11 * side, 0, 0.02), 1.0],
			[Vector3(0, 0, -0.03), 0.0], [Vector3(0.11 * side, 0, 0.02), 1.0], [Vector3(0.07 * side, 0, 0.09), 1.0],
			[Vector3(0, 0, -0.03), 0.0], [Vector3(0.07 * side, 0, 0.09), 1.0], [Vector3(0, 0, 0.05), 0.0]]
		for e: Array in pts:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(float(e[1]), 0.0))
			st.add_vertex(e[0])
	return st.commit()


func _mmi(nm: String, mesh: Mesh, mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = MAX_N
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var r: float = terrain.R + 200.0
	mi.custom_aabb = AABB(Vector3(-r, -r, -r), Vector3(r, r, r) * 2.0)
	mi.top_level = true
	add_child(mi)
	return mi


## How many flutter over a cell: by its hex level, on clean land only.
static func count_for(state: int, level: int, flags: int) -> int:
	if state != 1 or (flags & SphereCells.F_HUB) != 0:
		return 0
	return PER_LEVEL[clampi(level, 0, 5)]


static func _h(a: int, b: int) -> float:
	var x: int = ((a * 73856093) ^ (b * 19349663) ^ 0x5bd1e995) & 0xFFFFFFFF
	x = ((x ^ (x >> 13)) * 1274126177) & 0xFFFFFFFF
	return float((x ^ (x >> 16)) & 0xFFFF) / 65535.0


## Homes for the cells round `centre`, nearest rings first: [Transform3D, Color, custom Color].
func plan(centre: int) -> Array:
	var out: Array = []
	for c: int in grid.cells_around(centre, RINGS):
		var n: int = count_for(cells.state[c], cells.level[c], cells.flags[c])
		for k: int in n:
			if _h(c, k + 90) < 0.35:  # not every cell: sparse and calm
				continue
			if out.size() >= MAX_N:
				return out
			var up: Vector3 = grid.centers[c]
			var f: Basis = SphereGrid.frame(up)
			var a: float = _h(c, k * 3 + 1) * TAU
			var r: float = _h(c, k * 3 + 2) * 3.0
			var d: Vector3 = (up + (f.x * cos(a) + f.z * sin(a)) * r / terrain.R).normalized()
			out.append([Transform3D(SphereGrid.frame(d), terrain.ground(d)), COLORS[int(_h(c, k + 40) * 4.999)],
				Color(_h(c, k + 7), _h(c, k + 11), _h(c, k + 17), 0.0)])
	return out


func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.5
	var sky: Variant = world.get("sky_director") if world else null
	if sky is Object:
		var tod: float = float((sky as Object).get("time_of_day"))
		_night = maxf(1.0 - smoothstep(0.2, 0.27, tod), smoothstep(0.73, 0.8, tod))
	_bfly.visible = _night < 0.5 and shown > 0
	_ffly.visible = _night >= 0.5 and shown > 0
	_fmat.set_shader_parameter("amount", smoothstep(0.5, 0.9, _night))
	var patch: Variant = world.get("patch") if world else null
	if not (patch is Node3D) or not (patch as Node3D).is_inside_tree():
		return
	var c: int = grid.cell_at_from((patch as Node3D).global_position, _cell)
	if c == _cell and not _dirty:
		return
	_cell = c
	_dirty = false
	var homes: Array = plan(c)
	shown = homes.size()
	for mi: MultiMeshInstance3D in [_bfly, _ffly]:
		var mm: MultiMesh = mi.multimesh
		for i: int in shown:
			mm.set_instance_transform(i, homes[i][0])
			mm.set_instance_color(i, homes[i][1])
			mm.set_instance_custom_data(i, homes[i][2])
		mm.visible_instance_count = shown
