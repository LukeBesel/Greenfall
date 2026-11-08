class_name GlimScan
extends Node3D
## [buddy] Glim's hex scanner pulse: a thin ring sweeps out over the scanned hexes and every piece
## still lying in them gets a small floating marker (one MultiMesh, per-instance colour) that
## pops in as the ring passes, bobs for a few seconds and fades. Pieces too big for Lumi's lift
## right now get an amber marker instead of cyan (see GlimScan.too_big).

const MAX_MARKERS: int = 512
const HOLD_S: float = 4.5
const RING_SPEED: float = 9.0  # m/s
const COL_OK := Color(0.35, 0.95, 1.0)
const COL_BIG := Color(1.0, 0.62, 0.22)

var field: HexField
var world: Node
var _ring: MeshInstance3D
var _ring_mat: ShaderMaterial
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _pids := PackedInt32Array()
var _delay := PackedFloat32Array()
var _big := PackedByteArray()
var _t: float = -1.0
var _origin := Vector3.ZERO
var _reach: float = 0.0
var last_count: int = 0
var last_big: int = 0
var hold_for_shot: bool = false  # --glim-scan-hold

const RING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.35, 0.95, 1.0, 1.0);
uniform float radius = 1.0;
uniform float width = 0.35;
uniform float fade = 1.0;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - MODEL_MATRIX[3].xyz; }
void fragment() {
	float d = length(wp.xz);
	float band = 1.0 - smoothstep(0.0, width, abs(d - radius));
	float trail = smoothstep(radius - width * 6.0, radius, d) * step(d, radius) * 0.18;
	float a = (band * 0.9 + trail) * fade;
	ALBEDO = tint.rgb * a;
	ALPHA = a;
}
"""

const MARK_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
void fragment() {
	ALBEDO = COLOR.rgb * COLOR.a * 1.6;
	ALPHA = COLOR.a;
}
"""


func _ready() -> void:
	_ring_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = RING_SHADER
	_ring_mat.shader = sh
	_ring = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2, 2)
	_ring.mesh = pm
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)
	# Marker: a small double cone (a gem / chevron), shared by every piece.
	var gem := CylinderMesh.new()
	gem.top_radius = 0.0
	gem.bottom_radius = 0.11
	gem.height = 0.22
	gem.radial_segments = 4
	gem.rings = 1
	var mm_mat := ShaderMaterial.new()
	var msh := Shader.new()
	msh.code = MARK_SHADER
	mm_mat.shader = msh
	gem.material = mm_mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = gem
	_mm.instance_count = MAX_MARKERS
	_mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)


## Can Lumi lift this piece right now? Uses the pace helper's lift rule when it exists
## (Patch.can_lift_piece(pid) or Economy.can_lift_vol(vol)); otherwise everything is liftable.
static func too_big(p_world: Node, f: HexField, pid: int) -> bool:
	var patch: Node = p_world.get("patch") if p_world else null
	if patch and patch.has_method("can_lift_piece"):
		return not bool(patch.call("can_lift_piece", pid))
	if Economy.has_method("can_lift_vol"):
		return not bool(Economy.call("can_lift_vol", f.piece_vol[pid]))
	return false


## The pieces still lying in `hexes` (alive, not locked), for the markers.
static func remaining(f: HexField, hexes: Array[int]) -> PackedInt32Array:
	var out := PackedInt32Array()
	for h: int in hexes:
		if h < 0 or f.is_clean(h) or f.locked.has(h):
			continue
		for pid: int in f.hex_pieces[h]:
			if f.piece_alive[pid] == 1:
				out.append(pid)
	return out


## Start a pulse from `origin` over `hexes`. Returns how many pieces were marked.
func pulse(origin: Vector3, hexes: Array[int]) -> int:
	if field == null:
		return 0
	_origin = origin
	_pids = remaining(field, hexes)
	if _pids.size() > MAX_MARKERS:
		_pids.resize(MAX_MARKERS)
	_delay.resize(_pids.size())
	_big.resize(_pids.size())
	_reach = 0.0
	last_big = 0
	for i: int in _pids.size():
		var d: float = Vector2(field.piece_pos[_pids[i]].x - origin.x, field.piece_pos[_pids[i]].z - origin.z).length()
		_delay[i] = d / RING_SPEED
		_reach = maxf(_reach, d)
		_big[i] = 1 if too_big(world, field, _pids[i]) else 0
		last_big += _big[i]
	for h: int in hexes:  # the ring covers the scanned hexes even when they're empty
		if h >= 0:
			_reach = maxf(_reach, Vector2(field.hex_center(h).x - origin.x, field.hex_center(h).z - origin.z).length() + field.hex_size)
	_reach = clampf(_reach, field.hex_size, 60.0)
	_t = 0.0
	_ring.visible = true
	_ring.global_position = Vector3(origin.x, origin.y + 0.06, origin.z)
	_ring.scale = Vector3(_reach + 1.0, 1.0, _reach + 1.0)
	last_count = _pids.size()
	return last_count


func active() -> bool:
	return _t >= 0.0


func _process(delta: float) -> void:
	if _t < 0.0:
		return
	_t += minf(delta, 0.1)
	var sweep: float = _reach / RING_SPEED
	if hold_for_shot:  # dev (slow software renders): park the ring at 65% with markers up
		_t = clampf(_t, sweep * 0.65, sweep * 0.65 + 0.3)
	var r: float = _t * RING_SPEED
	_ring.visible = r < _reach + 1.5
	if _ring.visible:
		_ring_mat.set_shader_parameter("radius", r)  # world metres (the shader measures world offsets)
		_ring_mat.set_shader_parameter("width", 0.35)
		_ring_mat.set_shader_parameter("fade", 1.0 - smoothstep(_reach * 0.75, _reach + 1.5, r))
	var shown: int = 0
	for i: int in _pids.size():
		var pid: int = _pids[i]
		var age: float = _t - _delay[i]
		if age < 0.0 or field.piece_alive[pid] != 1:
			continue
		var life: float = HOLD_S
		var a: float = minf(1.0, age * 5.0) * (1.0 - smoothstep(life - 1.0, life, age))
		if a <= 0.0:
			continue
		var pop: float = 1.0 + 0.6 * exp(-age * 7.0)  # a small pop as the ring passes
		var p: Vector3 = field.piece_pos[pid]
		var top: float = 0.55 + clampf(field.piece_vol[pid], 0.0, 2.0) * 0.5
		var xf := Transform3D(Basis(Vector3.UP, _t * 2.2 + float(pid)).scaled(Vector3(pop, -pop, pop)),
			Vector3(p.x, p.y + top + sin(_t * 3.0 + float(pid) * 0.7) * 0.06, p.z))  # point down at the piece
		_mm.set_instance_transform(shown, xf)
		var c: Color = COL_BIG if _big[i] == 1 else COL_OK
		c.a = a
		_mm.set_instance_color(shown, c)
		shown += 1
	_mm.visible_instance_count = shown
	if _t > sweep + HOLD_S + 0.2:
		_t = -1.0
		_ring.visible = false
		_mm.visible_instance_count = 0
