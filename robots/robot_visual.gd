class_name RobotVisual
extends Node3D
## Procedural helper-robot models. Three body types (scoopie, haul bug, skimmer; planters,
## waterers and multibots are scoopie bodies with a job kit), four looks by tier, each a clear leap:
##   salvage  (Mk I)  junkyard improvisation: mismatched panels and wheels, exposed wiring, one tin-can eye.
##   restored (Mk II) repainted and confident: chunky, matching wheels, stripes, a tidy periscope head.
##   modern   (Mk III) glossy shells, panel seams, light strips, visor eye, magnetically floating limbs.
##   hover    (Mk IV) levitating egg/teardrop shell, orbiting rings, detached hands, thrusters, tractor beam.
## Helpers are deliberately warm-coloured (yellow / orange / coral / pearl) and a bit taller than Patch,
## so they never read as "small Patches". Faces -Z.

var type_id: String = "scoopie"
var look: String = "salvage"

var hover: bool = false
## Skimmers float on pontoons: the robot holds its height instead of falling (and bobs).
var floats: bool = false
## Parked with nothing to do: plays a small idle animation.
var idle: bool = false
## Spray origin for waterers (local).
var nozzle_point := Vector3(0, 0.7, -0.55)
var emitter_point := Vector3(0, 0.5, -0.4)
var hopper_point := Vector3(0, 0.6, 0)
var fork_point := Vector3(0, 0.35, -0.7)

var _body: Node3D
var _arm: Node3D
var _head: Node3D
var _eye: Node3D
var _antenna: Node3D
var _emitter: Node3D
var _wheels: Array[Node3D] = []
var _rings: Array[Node3D] = []
var _floaters: Array[Node3D] = []
var _flames: Array[MeshInstance3D] = []
var _glow_mats: Array[StandardMaterial3D] = []
var _eye_mat: StandardMaterial3D
var _beacon_mat: StandardMaterial3D
var _field_mat: StandardMaterial3D
var _beam: MeshInstance3D
var _beam_mat: ShaderMaterial
var _beam_core_mat: StandardMaterial3D
var _t: float = 0.0
var _idle_t: float = 0.0
var _fill_node: Node3D
var _fill: float = 1.0
var _blink_phase: float = 0.0
var _seed: float = 0.0

const AMBER := Color(1.0, 0.55, 0.12)
const WARM := Color(1.0, 0.72, 0.25)
const LIME := Color(0.45, 1.0, 0.55)
const MINT := Color(0.3, 1.0, 0.82)


func build(p_type: String, p_look: String) -> void:
	type_id = p_type
	look = p_look
	hover = look == "hover"
	floats = type_id == "skimmer"
	_fill_node = null
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	_wheels.clear()
	_rings.clear()
	_floaters.clear()
	_flames.clear()
	_glow_mats.clear()
	_arm = null
	_head = null
	_eye = null
	_antenna = null
	_emitter = null
	_eye_mat = null
	_beacon_mat = null
	_field_mat = null
	_seed = randf() * 10.0
	_blink_phase = randf() * 4.0
	_body = Node3D.new()
	add_child(_body)
	var base_type: String = "scoopie" if type_id in ["seedling", "drip", "multibot"] else type_id
	var key: String = base_type + "/" + look
	match key:
		"haulbug/salvage": _haul_salvage()
		"haulbug/restored": _haul_restored()
		"haulbug/modern": _haul_modern()
		"haulbug/hover": _haul_hover()
		"scoopie/restored": _scoop_restored()
		"scoopie/modern": _scoop_modern()
		"scoopie/hover": _scoop_hover()
		"skimmer/salvage", "skimmer/restored", "skimmer/modern", "skimmer/hover": _skim()
		_: _scoop_salvage()
	if type_id != base_type:
		_job_kit(type_id)
	_build_beam()


## Job accessories that set planters, waterers and multibots apart from cleaners.
func _job_kit(t: String) -> void:
	var top: Vector3 = hopper_point + Vector3(0, 0.08, 0.12)
	var shiny: bool = look in ["modern", "hover"]
	match t:
		"seedling":
			var green: Material = _gloss(Color(0.35, 0.7, 0.3), 0.3) if shiny else _worn(Color(0.35, 0.6, 0.28), 0.7, 0.4)
			_mi(_body, ProcMesh.cyl(0.11, 0.13, 0.26, 16), green, top + Vector3(0, 0.13, 0))
			_mi(_body, ProcMesh.cyl(0.12, 0.12, 0.04, 16), _glow(Color(0.6, 1.0, 0.4), 1.5), top + Vector3(0, 0.27, 0))
			_rod(_body, top + Vector3(0, 0.0, -0.05), emitter_point + Vector3(0, -0.05, 0), 0.018, green)
			_stencil(_body, "SEEDS", top + Vector3(0, 0.13, -0.125), Vector3(0, 180, 0), 28)
		"drip":
			_drip_kit(top)
		"multibot":
			var rack: Material = _worn(Color(0.55, 0.55, 0.58), 0.4, 0.6)
			_mi(_body, ProcMesh.box(Vector3(0.36, 0.04, 0.2)), rack, top + Vector3(0, 0.03, 0))
			_mi(_body, ProcMesh.cyl(0.05, 0.05, 0.16, 10), _worn(Color(0.35, 0.6, 0.28), 0.7, 0.4), top + Vector3(-0.12, 0.12, 0))
			_mi(_body, ProcMesh.capsule(0.05, 0.18), _worn(Color(0.3, 0.5, 0.75), 0.7, 0.4), top + Vector3(0.0, 0.12, 0), Vector3(0, 0, 90))
			_mi(_body, _rbox(Vector3(0.1, 0.03, 0.12), 0.01, 2), _worn(Color(0.95, 0.75, 0.2), 0.7, 0.4), top + Vector3(0.13, 0.1, 0))
			_stencil(_body, "MULTI", top + Vector3(0, 0.03, -0.105), Vector3(0, 180, 0), 24)


## Waterer kit per tier: a strapped plastic drum and garden hose (Mk I), a painted tank with a
## sight glass and spray bar (Mk II), a glossy capsule with a glowing level strip and boom (Mk III),
## a glass orb of glowing water with a ring nozzle (Mk IV). The level gauge follows the tank.
func _drip_kit(top: Vector3) -> void:
	var steel: Material = Mats.metal("steel")
	match look:
		"salvage":
			var drum: Material = _worn(Color(0.2, 0.45, 0.8), 0.85, 0.2, 0.6)
			_mi(_body, ProcMesh.cyl(0.14, 0.14, 0.42, 18), drum, top + Vector3(0, 0.14, 0.02), Vector3(0, 0, 90))
			for x: float in [-0.15, 0.15]:
				_mi(_body, ProcMesh.torus(0.135, 0.15, 18, 4), Mats.rubber(), top + Vector3(x, 0.14, 0.02), Vector3(0, 0, 90))
			_mi(_body, ProcMesh.cyl(0.04, 0.04, 0.04, 10), _worn(Color(0.9, 0.2, 0.1), 0.8, 0.3), top + Vector3(0.12, 0.29, 0.02))
			# Jam-jar sight glass with the water inside.
			var jar := _mi(_body, ProcMesh.cyl(0.055, 0.055, 0.16, 14), _glass(), top + Vector3(-0.2, 0.33, 0.1))
			jar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_fill_gauge(top + Vector3(-0.2, 0.255, 0.1), ProcMesh.cyl(0.048, 0.048, 0.15, 12), Mats.lamp(Color(0.35, 0.7, 1.0), 1.2), 0.15)
			# Garden hose to a pipe nozzle out front.
			var hose: Material = Mats.rubber(Color(0.15, 0.55, 0.25))
			_cable(_body, top + Vector3(-0.2, 0.14, -0.15), top + Vector3(-0.3, 0.0, -0.35), top + Vector3(0, 0.02, -0.48), 0.018, hose)
			_mi(_body, ProcMesh.cyl(0.03, 0.02, 0.08, 10), Mats.metal("brass"), top + Vector3(0, 0.02, -0.52), Vector3(90, 0, 0))
			nozzle_point = top + Vector3(0, 0.03, -0.57)
		"restored":
			# Painted backpack tank with a sight glass on top, piped to a chrome spray bar out front.
			var blue: Material = _worn(Color(0.22, 0.5, 0.88), 0.95, 0.2, 0.3, 0.0)
			var bp := Vector3(0, 0.62, 0.47)
			_mi(_body, ProcMesh.capsule(0.14, 0.56), blue, bp, Vector3(0, 0, 90))
			for x: float in [-0.18, 0.18]:
				_mi(_body, ProcMesh.torus(0.135, 0.148, 20, 4), _worn(Color(0.95, 0.95, 0.92), 0.95, 0.1, 0.2, 0.0), bp + Vector3(x, 0, 0), Vector3(0, 0, 90))
			_mi(_body, ProcMesh.box(Vector3(0.24, 0.02, 0.05)), Mats.metal("dark_steel"), bp + Vector3(0, 0.14, 0))
			var gauge := _node(_body, bp + Vector3(-0.11, 0.152, 0))
			_fill_node = gauge
			_mi(gauge, ProcMesh.box(Vector3(0.22, 0.01, 0.03)), Mats.lamp(Color(0.35, 0.75, 1.0), 1.8), Vector3(0.11, 0, 0))
			gauge.set_meta("axis", "x")
			_cable(_body, bp + Vector3(0.24, 0.0, -0.1), Vector3(0.36, 0.72, 0.0), Vector3(0.18, 0.76, -0.42), 0.02, Mats.rubber(Color(0.12, 0.12, 0.13)))
			_mi(_body, ProcMesh.cyl(0.018, 0.018, 0.4, 8), Mats.metal("chrome"), Vector3(0, 0.76, -0.43), Vector3(0, 0, 90))
			for x: float in [-0.14, 0.0, 0.14]:
				_mi(_body, ProcMesh.cyl(0.015, 0.022, 0.05, 8), _glow(Color(0.5, 0.8, 1.0), 1.0), Vector3(x, 0.74, -0.45), Vector3(-60, 0, 0))
			_stencil(_body, "H2O", bp + Vector3(0, 0, 0.143), Vector3.ZERO, 30)
			nozzle_point = Vector3(0, 0.74, -0.48)
		"modern":
			# A glossy backpack tank behind the visor head, level strip on top, hose to a front nozzle ring.
			var white: Material = _gloss(Color(0.95, 0.95, 0.94), 0.25, 0.0, 0.6)
			var dk: Material = _gloss(Color(0.07, 0.08, 0.09), 0.3, 0.4, 0.3)
			var bp := Vector3(0, 0.63, 0.47)
			_mi(_body, ProcMesh.capsule(0.15, 0.56), white, bp, Vector3(0, 0, 90))
			for x: float in [-0.2, 0.2]:
				_mi(_body, ProcMesh.torus(0.145, 0.16, 20, 4), _gloss(Color(1.0, 0.38, 0.26), 0.28), bp + Vector3(x, 0, 0), Vector3(0, 0, 90))
			_mi(_body, _rbox(Vector3(0.36, 0.02, 0.06), 0.01, 1), dk, bp + Vector3(0, 0.148, 0))
			var strip := _node(_body, bp + Vector3(-0.16, 0.16, 0))
			_fill_node = strip
			_mi(strip, ProcMesh.box(Vector3(0.32, 0.012, 0.035)), _glow(Color(0.3, 0.85, 1.0), 2.5), Vector3(0.16, 0, 0))
			strip.set_meta("axis", "x")
			_cable(_body, bp + Vector3(0.24, -0.02, -0.08), Vector3(0.38, 0.62, 0.0), Vector3(0.12, 0.6, -0.38), 0.016, dk)
			_mi(_body, ProcMesh.cyl(0.03, 0.03, 0.08, 12), dk, Vector3(0.08, 0.6, -0.4), Vector3(90, 0, 0))
			_mi(_body, ProcMesh.torus(0.025, 0.042, 16, 4), _glow(Color(0.3, 0.85, 1.0), 3.0), Vector3(0.08, 0.6, -0.445), Vector3(90, 0, 0))
			nozzle_point = Vector3(0.08, 0.6, -0.46)
		_:
			# Mk IV: a floating glass orb of glowing water above the crown.
			var orb_c: Vector3 = hopper_point + Vector3(0, 0.22, 0)
			var orb := _floater(_body, orb_c, 0.02)
			var glass := _mi(orb, ProcMesh.sphere(0.16, 24, 12), _glass(), Vector3.ZERO)
			glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var inner := _node(orb, Vector3(0, -0.14, 0))
			_mi(inner, ProcMesh.sphere(0.135, 20, 10), _glow(Color(0.3, 0.8, 1.0), 2.0), Vector3(0, 0.14, 0))
			_fill_node = inner
			_mi(orb, ProcMesh.torus(0.16, 0.18, 28, 4), _gloss(Color(1.0, 0.76, 0.35), 0.2, 1.0, 0.0), Vector3.ZERO)
			nozzle_point = emitter_point
	_fill_node_base()


func _fill_gauge(bottom: Vector3, mesh: Mesh, mat: Material, h: float) -> void:
	_fill_node = _node(_body, bottom)
	_mi(_fill_node, mesh, mat, Vector3(0, h * 0.5, 0))


func _fill_node_base() -> void:
	if _fill_node:
		_fill_node.set_meta("s0", _fill_node.scale)


## Tank level 0..1 for the waterer's gauge.
func set_fill(f: float) -> void:
	_fill = clampf(f, 0.0, 1.0)


func _glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.8, 0.92, 1.0, 0.28)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic = 0.1
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	return m


# --- Material helpers ------------------------------------------------------------------

func _worn(c: Color, cov: float, rust: float, grime: float = 0.4, fade: float = 0.15) -> ShaderMaterial:
	var m: ShaderMaterial = Mats.worn_paint(c, cov, rust, _seed + randf() * 5.0, grime)
	m.set_shader_parameter("fade", fade)
	return m


func _gloss(c: Color, rough: float = 0.22, metal: float = 0.05, coat: float = 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if coat > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = coat
		m.clearcoat_roughness = 0.1
	return m


func _glow(c: Color, energy: float = 2.5) -> StandardMaterial3D:
	var m: StandardMaterial3D = Mats.lamp(c, energy)
	_glow_mats.append(m)
	m.set_meta("base", energy)
	return m


func _additive(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	return m


func _wood(tint: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.42, 0.3, 0.19).lerp(Color(0.6, 0.5, 0.36), tint)
	m.roughness = 0.92
	return m


# --- Mesh helpers ----------------------------------------------------------------------

## ProcMesh.rounded_box with its triangle winding reversed: the shared builder emits back-facing
## triangles (only the far walls render), so flip each triangle here.
static var _rbox_cache: Dictionary = {}


static func _rbox(size: Vector3, radius: float, seg: int = 4) -> ArrayMesh:
	var key: String = "%s|%.4f|%d" % [size, radius, seg]
	if _rbox_cache.has(key):
		return _rbox_cache[key]
	var src: ArrayMesh = ProcMesh.rounded_box(size, radius, seg)
	var arr: Array = src.surface_get_arrays(0)
	for idx: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR]:
		var a = arr[idx]
		if a == null:
			continue
		for t: int in range(0, a.size(), 3):
			var tmp = a[t + 1]
			a[t + 1] = a[t + 2]
			a[t + 2] = tmp
		arr[idx] = a
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_rbox_cache[key] = out
	return out


func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot
	m.scale = scl
	parent.add_child(m)
	return m


func _node(parent: Node3D, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees = rot
	parent.add_child(n)
	return n


## Cylinder from a to b.
func _rod(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material, segs: int = 8) -> MeshInstance3D:
	var d: Vector3 = b - a
	var l: float = maxf(d.length(), 0.001)
	var y: Vector3 = d / l
	var ref: Vector3 = Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x: Vector3 = y.cross(ref).normalized()
	var z: Vector3 = x.cross(y)
	var m := MeshInstance3D.new()
	m.mesh = ProcMesh.cyl(r, r, l, segs)
	m.material_override = mat
	m.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	parent.add_child(m)
	return m


## Sagging cable through three points.
func _cable(parent: Node3D, a: Vector3, mid: Vector3, b: Vector3, r: float, mat: Material) -> void:
	var p: Vector3 = a
	for i: int in range(1, 5):
		var t: float = i / 4.0
		var q: Vector3 = a.lerp(mid, t).lerp(mid.lerp(b, t), t)
		_rod(parent, p, q, r, mat, 6)
		p = q


func _wheel(parent: Node3D, pos: Vector3, r: float, w: float, tyre: Material, hub: Material) -> Node3D:
	var n := _node(parent, pos)
	n.set_meta("r", r)
	_mi(n, ProcMesh.cyl(r, r, w, 18), tyre, Vector3.ZERO, Vector3(0, 0, 90))
	_mi(n, ProcMesh.cyl(r * 0.55, r * 0.55, w + 0.01, 10), hub, Vector3.ZERO, Vector3(0, 0, 90))
	_mi(n, ProcMesh.box(Vector3(w + 0.02, r * 0.9, 0.02)), hub, Vector3.ZERO)  # spoke so the spin reads
	_wheels.append(n)
	return n


func _floater(parent: Node3D, pos: Vector3, amp: float = 0.02) -> Node3D:
	var n := _node(parent, pos)
	n.set_meta("base", pos)
	n.set_meta("amp", amp)
	n.set_meta("ph", randf() * TAU)
	_floaters.append(n)
	return n


func _ring(parent: Node3D, pos: Vector3, tilt: Vector3, spd: float) -> Node3D:
	var holder := _node(parent, pos, tilt)
	var spin := _node(holder, Vector3.ZERO)
	spin.set_meta("spd", spd)
	_rings.append(spin)
	return spin


func _stencil(parent: Node3D, text: String, pos: Vector3, rot: Vector3, px: int = 40, col: Color = Color(0.95, 0.92, 0.85, 0.9)) -> void:
	var l: Label3D = Mats.stencil(text, px, col)
	l.position = pos
	l.rotation_degrees = rot
	parent.add_child(l)


func _beacon(parent: Node3D, pos: Vector3, col: Color, stalk: float = 0.12) -> void:
	_beacon_mat = Mats.lamp(col, 1.5)
	_mi(parent, ProcMesh.cyl(0.008, 0.008, stalk, 6), Mats.metal("dark_steel"), pos - Vector3(0, stalk * 0.5, 0))
	_mi(parent, ProcMesh.sphere(0.026, 10, 5), _beacon_mat, pos + Vector3(0, 0.01, 0))


## Single round eye: bezel + glowing lens inside an _eye node (blinks by scaling y).
func _round_eye(parent: Node3D, pos: Vector3, r: float, col: Color, bezel: Material) -> void:
	_mi(parent, ProcMesh.torus(r * 0.9, r * 1.3, 18, 6), bezel, pos, Vector3(90, 0, 0))
	_eye = _node(parent, pos)
	_eye_mat = _glow(col, 3.0)
	_mi(_eye, ProcMesh.cyl(r, r, 0.012, 18), _eye_mat, Vector3.ZERO, Vector3(90, 0, 0))
	_mi(_eye, ProcMesh.cyl(r * 0.35, r * 0.35, 0.014, 12), Mats.lamp(Color(1, 0.95, 0.85), 4.0), Vector3(r * 0.25, r * 0.25, -0.002), Vector3(90, 0, 0))


# --- Scoopie ---------------------------------------------------------------------------

## Mk I: a hand-welded trough of mismatched panels on four different wheels, a tin-can eye on a bent pipe,
## a car battery strapped to the back and a snow-shovel scoop.
func _scoop_salvage() -> void:
	var frame: Material = Mats.metal("dark_steel")
	var tyre: Material = Mats.rubber()
	var pipe: Material = _worn(Color(0.5, 0.5, 0.48), 0.2, 0.9, 0.6)
	for x: float in [-0.21, 0.21]:
		_mi(_body, ProcMesh.box(Vector3(0.045, 0.05, 0.68)), frame, Vector3(x, 0.2, 0))
	for z: float in [-0.31, 0.31]:
		_mi(_body, ProcMesh.box(Vector3(0.47, 0.04, 0.045)), frame, Vector3(0, 0.2, z))
	# Mismatched wheels: a fat old tyre, a thin cart wheel, a caster and a painted pram wheel.
	_rod(_body, Vector3(-0.3, 0.15, 0.25), Vector3(0.3, 0.13, 0.25), 0.018, frame)
	_wheel(_body, Vector3(-0.31, 0.15, 0.25), 0.15, 0.09, tyre, _worn(Color(0.8, 0.2, 0.12), 0.7, 0.6))
	_wheel(_body, Vector3(0.31, 0.13, 0.25), 0.13, 0.05, tyre, Mats.metal("steel"))
	_rod(_body, Vector3(-0.21, 0.2, -0.27), Vector3(-0.25, 0.085, -0.27), 0.012, frame)
	_wheel(_body, Vector3(-0.27, 0.085, -0.27), 0.085, 0.045, Mats.rubber(Color(0.75, 0.72, 0.65)), frame)
	_rod(_body, Vector3(0.21, 0.2, -0.27), Vector3(0.26, 0.105, -0.27), 0.012, frame)
	_wheel(_body, Vector3(0.27, 0.105, -0.27), 0.105, 0.05, tyre, _worn(Color(0.95, 0.75, 0.15), 0.8, 0.5))
	# Trough hopper, every panel from a different scrap.
	_mi(_body, ProcMesh.box(Vector3(0.5, 0.03, 0.56)), frame, Vector3(0, 0.24, 0))
	_mi(_body, _rbox(Vector3(0.025, 0.36, 0.57), 0.01, 1), _worn(Color(0.38, 0.72, 0.55), 0.6, 0.7), Vector3(-0.255, 0.41, 0), Vector3(0, 0, -5))
	_mi(_body, _rbox(Vector3(0.025, 0.33, 0.57), 0.01, 1), _worn(Color(0.82, 0.25, 0.16), 0.55, 0.8), Vector3(0.258, 0.4, 0), Vector3(0, 0, 6))
	_mi(_body, _rbox(Vector3(0.53, 0.42, 0.025), 0.01, 1), _worn(Color(0.95, 0.7, 0.15), 0.6, 0.7), Vector3(0, 0.44, 0.285))
	_mi(_body, _rbox(Vector3(0.52, 0.25, 0.025), 0.01, 1), _worn(Color(0.6, 0.6, 0.6), 0.1, 0.9), Vector3(0, 0.36, -0.285), Vector3(8, 0, 0))
	# Riveted patch plate and rivets.
	_mi(_body, ProcMesh.box(Vector3(0.012, 0.13, 0.17)), _worn(Color(0.35, 0.45, 0.75), 0.65, 0.6), Vector3(0.28, 0.46, 0.05), Vector3(0, 0, 6))
	for p: Vector3 in [Vector3(0.29, 0.52, -0.02), Vector3(0.29, 0.52, 0.12), Vector3(0.276, 0.4, -0.02), Vector3(0.276, 0.4, 0.12)]:
		_mi(_body, ProcMesh.sphere(0.008, 6, 3), Mats.metal("steel"), p)
	_stencil(_body, "Nº7", Vector3(-0.08, 0.5, 0.299), Vector3.ZERO, 64, Color(0.15, 0.12, 0.1, 0.85))
	hopper_point = Vector3(0, 0.55, 0)
	# Car battery strapped to the back, wires everywhere.
	_mi(_body, ProcMesh.box(Vector3(0.3, 0.02, 0.15)), frame, Vector3(0.04, 0.25, 0.37))
	_mi(_body, _rbox(Vector3(0.22, 0.15, 0.13), 0.01, 1), _gloss(Color(0.07, 0.07, 0.08), 0.6, 0.0, 0.0), Vector3(0.05, 0.335, 0.37))
	_mi(_body, ProcMesh.cyl(0.015, 0.015, 0.025, 8), Mats.lamp(Color(0.9, 0.15, 0.1), 0.3), Vector3(-0.02, 0.42, 0.37))
	_mi(_body, ProcMesh.cyl(0.015, 0.015, 0.025, 8), Mats.metal("dark_steel"), Vector3(0.12, 0.42, 0.37))
	_cable(_body, Vector3(-0.02, 0.43, 0.37), Vector3(-0.12, 0.72, 0.45), Vector3(-0.17, 0.62, 0.3), 0.009, Mats.rubber(Color(0.75, 0.1, 0.08)))
	_cable(_body, Vector3(0.12, 0.43, 0.37), Vector3(0.36, 0.58, 0.2), Vector3(0.1, 0.6, -0.29), 0.008, Mats.rubber(Color(0.9, 0.75, 0.1)))
	_cable(_body, Vector3(0.2, 0.3, 0.32), Vector3(0.3, 0.1, 0.1), Vector3(0.27, 0.3, -0.1), 0.007, Mats.rubber(Color(0.15, 0.35, 0.8)))
	# Bent-pipe neck with a tin-can head.
	_rod(_body, Vector3(-0.17, 0.4, 0.3), Vector3(-0.17, 0.82, 0.26), 0.022, pipe)
	_mi(_body, ProcMesh.sphere(0.03, 8, 4), pipe, Vector3(-0.17, 0.82, 0.26))
	_rod(_body, Vector3(-0.17, 0.82, 0.26), Vector3(-0.1, 0.9, 0.14), 0.022, pipe)
	_head = _node(_body, Vector3(-0.09, 0.92, 0.1), Vector3(0, 0, 12))
	_mi(_head, ProcMesh.cyl(0.075, 0.075, 0.15, 16), _worn(Color(0.85, 0.3, 0.2), 0.55, 0.7), Vector3.ZERO, Vector3(90, 0, 0))
	_mi(_head, ProcMesh.torus(0.07, 0.08, 16, 4), Mats.metal("steel"), Vector3(0, 0, 0.04), Vector3(90, 0, 0))
	_mi(_head, ProcMesh.box(Vector3(0.18, 0.012, 0.09)), _worn(Color(0.4, 0.4, 0.4), 0.1, 0.9), Vector3(0, 0.08, -0.06), Vector3(-12, 0, 0))
	_round_eye(_head, Vector3(0, 0, -0.078), 0.045, AMBER, Mats.metal("chrome"))
	_antenna = _node(_head, Vector3(0.03, 0.07, 0.03))
	_rod(_antenna, Vector3.ZERO, Vector3(0.02, 0.13, 0.03), 0.004, Mats.metal("steel"), 5)
	_mi(_antenna, ProcMesh.cyl(0.018, 0.018, 0.01, 10), _worn(Color(0.9, 0.15, 0.1), 0.8, 0.3), Vector3(0.02, 0.135, 0.03))
	# Scoop arm: a pipe and a sawn-off snow shovel.
	_arm = _node(_body, Vector3(0.0, 0.42, -0.31))
	_mi(_arm, ProcMesh.cyl(0.025, 0.025, 0.2, 10), frame, Vector3.ZERO, Vector3(0, 0, 90))
	_rod(_arm, Vector3(0.05, 0, 0), Vector3(0.05, -0.2, -0.22), 0.02, pipe)
	_rod(_arm, Vector3(-0.05, 0, 0), Vector3(-0.07, -0.2, -0.22), 0.016, frame)
	var shovel: Material = _worn(Color(0.95, 0.78, 0.2), 0.7, 0.5)
	_mi(_arm, ProcMesh.box(Vector3(0.32, 0.014, 0.2)), shovel, Vector3(0, -0.25, -0.3), Vector3(-12, 0, 0))
	for x: float in [-0.16, 0.16]:
		_mi(_arm, ProcMesh.box(Vector3(0.012, 0.06, 0.2)), shovel, Vector3(x, -0.23, -0.3), Vector3(-12, 0, 0))
	_mi(_arm, ProcMesh.box(Vector3(0.32, 0.08, 0.012)), shovel, Vector3(0, -0.2, -0.2), Vector3(-12, 0, 0))
	emitter_point = _arm.position + Vector3(0, -0.25, -0.32)


func _head_restored(pos: Vector3, paint: Material, trim: Material, accent: Material) -> void:
	_mi(_body, ProcMesh.cyl(0.035, 0.045, pos.y - 0.62, 12), trim, Vector3(pos.x, (pos.y + 0.62) * 0.5, pos.z + 0.04))
	_head = _node(_body, pos)
	_mi(_head, _rbox(Vector3(0.24, 0.16, 0.19), 0.05, 2), paint, Vector3.ZERO)
	_mi(_head, _rbox(Vector3(0.26, 0.02, 0.1), 0.008, 1), accent, Vector3(0, 0.085, -0.08), Vector3(-10, 0, 0))
	_round_eye(_head, Vector3(0, -0.005, -0.1), 0.048, WARM, trim)
	for x: float in [-0.125, 0.125]:
		_mi(_head, ProcMesh.cyl(0.03, 0.03, 0.03, 12), trim, Vector3(x, 0, 0), Vector3(0, 0, 90))
	_antenna = _node(_head, Vector3(0.08, 0.08, 0.05))
	_beacon(_antenna, Vector3(0, 0.12, 0), AMBER, 0.12)


## Mk II: the same trough idea rebuilt properly: one sunflower-yellow shell, red stripe, fenders,
## matching wheels, a twin-ram bucket and a neat periscope head.
func _scoop_restored() -> void:
	var paint: Material = _worn(Color(1.0, 0.74, 0.08), 0.94, 0.25, 0.35, 0.05)
	var trim: Material = _worn(Color(0.15, 0.16, 0.18), 0.95, 0.2, 0.3, 0.0)
	var accent: Material = _worn(Color(0.9, 0.16, 0.1), 0.95, 0.2, 0.3, 0.0)
	var tyre: Material = Mats.rubber()
	_mi(_body, _rbox(Vector3(0.6, 0.1, 0.74), 0.03, 2), trim, Vector3(0, 0.2, 0))
	for x: float in [-0.37, 0.37]:
		for z: float in [-0.24, 0.24]:
			_wheel(_body, Vector3(x, 0.15, z), 0.15, 0.1, tyre, accent)
			_mi(_body, _rbox(Vector3(0.14, 0.03, 0.34), 0.012, 2), paint, Vector3(x, 0.32, z))
	_mi(_body, _rbox(Vector3(0.62, 0.42, 0.68), 0.08, 3), paint, Vector3(0, 0.47, 0))
	_mi(_body, _rbox(Vector3(0.632, 0.05, 0.692), 0.08, 3), accent, Vector3(0, 0.5, 0))
	for x: float in [-0.29, 0.29]:
		_mi(_body, _rbox(Vector3(0.05, 0.05, 0.66), 0.015, 1), trim, Vector3(x, 0.69, 0))
	for z: float in [-0.32, 0.32]:
		_mi(_body, _rbox(Vector3(0.62, 0.05, 0.05), 0.015, 1), trim, Vector3(0, 0.69, z))
	_mi(_body, ProcMesh.box(Vector3(0.52, 0.004, 0.58)), _gloss(Color(0.03, 0.03, 0.035), 0.9, 0.0, 0.0), Vector3(0, 0.683, 0))
	_stencil(_body, "SCP-2", Vector3(0.318, 0.4, 0.05), Vector3(0, 90, 0), 52, Color(0.12, 0.12, 0.13, 0.9))
	_stencil(_body, "SCP-2", Vector3(-0.318, 0.4, -0.05), Vector3(0, -90, 0), 52, Color(0.12, 0.12, 0.13, 0.9))
	for x: float in [-0.2, 0.2]:
		_mi(_body, ProcMesh.cyl(0.03, 0.03, 0.012, 14), Mats.lamp(Color(1.0, 0.92, 0.75), 1.5), Vector3(x, 0.32, -0.343), Vector3(90, 0, 0))
		_mi(_body, ProcMesh.cyl(0.025, 0.025, 0.012, 10), Mats.lamp(Color(1.0, 0.1, 0.05), 1.0), Vector3(x, 0.32, 0.343), Vector3(90, 0, 0))
	hopper_point = Vector3(0, 0.7, 0)
	_head_restored(Vector3(-0.14, 0.96, 0.16), paint, trim, accent)
	# Twin-ram bucket arm.
	_arm = _node(_body, Vector3(0, 0.5, -0.33))
	_mi(_arm, ProcMesh.cyl(0.03, 0.03, 0.58, 12), trim, Vector3.ZERO, Vector3(0, 0, 90))
	for x: float in [-0.25, 0.25]:
		_rod(_arm, Vector3(x, 0, 0), Vector3(x, -0.2, -0.24), 0.028, trim)
		_rod(_arm, Vector3(x * 0.8, 0.02, 0), Vector3(x * 0.8, -0.12, -0.16), 0.018, Mats.metal("chrome"))
	_mi(_arm, _rbox(Vector3(0.54, 0.13, 0.2), 0.03, 2), paint, Vector3(0, -0.27, -0.32))
	for i: int in 5:
		_mi(_arm, ProcMesh.box(Vector3(0.04, 0.02, 0.05)), Mats.metal("steel"), Vector3(-0.2 + i * 0.1, -0.33, -0.43))
	emitter_point = _arm.position + Vector3(0, -0.27, -0.36)


## Mk III: glossy pearl-white shell over a dark skirt, coral band, panel seams and lime light strips,
## a floating visor head and forearms held on glowing magnetic joints.
func _scoop_modern() -> void:
	var white: Material = _gloss(Color(0.95, 0.94, 0.92), 0.35, 0.0, 0.5)
	var coral: Material = _gloss(Color(1.0, 0.38, 0.26), 0.28)
	var dark: Material = _gloss(Color(0.07, 0.08, 0.09), 0.35, 0.4, 0.3)
	var lite: Material = _glow(LIME, 2.5)
	_mi(_body, _rbox(Vector3(0.58, 0.14, 0.7), 0.06, 2), dark, Vector3(0, 0.13, 0))
	for x: float in [-0.25, 0.25]:
		for z: float in [-0.24, 0.24]:
			_wheel(_body, Vector3(x, 0.09, z), 0.09, 0.07, Mats.rubber(), dark)
	_mi(_body, _rbox(Vector3(0.64, 0.44, 0.74), 0.16, 4), white, Vector3(0, 0.43, 0))
	_mi(_body, _rbox(Vector3(0.656, 0.2, 0.756), 0.13, 3), coral, Vector3(0, 0.31, 0))
	# Panel seams.
	for x: float in [-0.321, 0.321]:
		_mi(_body, ProcMesh.box(Vector3(0.004, 0.2, 0.004)), dark, Vector3(x, 0.5, 0.12))
	_mi(_body, ProcMesh.box(Vector3(0.3, 0.004, 0.004)), dark, Vector3(0, 0.5, -0.371))
	# Light strips.
	for x: float in [-0.322, 0.322]:
		_mi(_body, ProcMesh.box(Vector3(0.006, 0.022, 0.36)), lite, Vector3(x, 0.52, -0.08))
	_mi(_body, ProcMesh.box(Vector3(0.28, 0.022, 0.006)), lite, Vector3(0, 0.36, -0.372))
	# Hopper mouth with a glowing ring.
	_mi(_body, _rbox(Vector3(0.42, 0.02, 0.5), 0.05, 2), dark, Vector3(0, 0.645, 0))
	_mi(_body, ProcMesh.torus(0.2, 0.215, 28, 4), lite, Vector3(0, 0.652, 0), Vector3.ZERO, Vector3(1.0, 1.0, 1.2))
	hopper_point = Vector3(0, 0.66, 0)
	# Floating visor head over a magnetic neck.
	_mi(_body, ProcMesh.cyl(0.04, 0.05, 0.1, 14), dark, Vector3(0, 0.69, 0.22))
	_mi(_body, ProcMesh.torus(0.045, 0.065, 18, 4), _glow(LIME, 3.0), Vector3(0, 0.755, 0.22))
	var hf := _floater(_body, Vector3(0, 0.86, 0.2), 0.012)
	_head = _node(hf, Vector3.ZERO)
	_mi(_head, _rbox(Vector3(0.34, 0.19, 0.25), 0.085, 3), white, Vector3.ZERO)
	_mi(_head, _rbox(Vector3(0.345, 0.07, 0.255), 0.03, 2), coral, Vector3(0, 0.065, 0.0))
	_mi(_head, _rbox(Vector3(0.28, 0.1, 0.03), 0.03, 2), _gloss(Color(0.02, 0.03, 0.04), 0.05, 0.3, 1.0), Vector3(0, -0.005, -0.118))
	_eye = _node(_head, Vector3(0, -0.005, -0.135))
	_eye_mat = _glow(LIME, 3.5)
	_mi(_eye, _rbox(Vector3(0.17, 0.035, 0.006), 0.012, 1), _eye_mat, Vector3.ZERO)
	_antenna = _node(_head, Vector3(-0.12, 0.09, 0.06))
	_rod(_antenna, Vector3.ZERO, Vector3(0, 0.08, 0), 0.006, dark, 6)
	_mi(_antenna, ProcMesh.sphere(0.018, 10, 5), coral, Vector3(0, 0.085, 0))
	# Arms: shoulders on the body, forearms + scoop floating on glowing joints.
	_arm = _node(_body, Vector3(0, 0.5, -0.24))
	for x: float in [-0.35, 0.35]:
		_mi(_arm, ProcMesh.sphere(0.06, 14, 7), dark, Vector3(x, 0, 0))
		_rod(_arm, Vector3(x, 0, 0), Vector3(x * 1.03, -0.09, -0.16), 0.038, white, 12)
		_mi(_arm, ProcMesh.torus(0.03, 0.05, 16, 4), _glow(LIME, 3.0), Vector3(x * 1.03, -0.115, -0.2), Vector3(-60, 0, 0))
	var fore := _floater(_arm, Vector3(0, -0.02, -0.02), 0.01)
	for x: float in [-0.35, 0.35]:
		_rod(fore, Vector3(x * 1.03, -0.12, -0.23), Vector3(x * 0.9, -0.2, -0.33), 0.034, white, 12)
	_mi(fore, _rbox(Vector3(0.58, 0.07, 0.22), 0.03, 2), coral, Vector3(0, -0.24, -0.38), Vector3(-8, 0, 0))
	_mi(fore, ProcMesh.box(Vector3(0.5, 0.012, 0.006)), lite, Vector3(0, -0.205, -0.49), Vector3(-8, 0, 0))
	emitter_point = _arm.position + Vector3(0, -0.26, -0.4)


func _thruster(parent: Node3D, pos: Vector3, r: float, shell: Material) -> void:
	_mi(parent, ProcMesh.cyl(r * 0.75, r, r * 0.9, 18), shell, pos)
	_mi(parent, ProcMesh.cyl(r * 0.7, r * 0.7, 0.012, 18), _glow(MINT, 4.0), pos - Vector3(0, r * 0.46, 0))
	var flame := _mi(parent, ProcMesh.cyl(r * 0.65, 0.01, r * 3.0, 14), _additive(Color(0.25, 0.9, 0.8, 0.35)), pos - Vector3(0, r * 0.46 + r * 1.5, 0))
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.set_meta("base_y", flame.position.y)
	flame.set_meta("h", r * 3.0)
	_flames.append(flame)


func _float_hand(parent: Node3D, pos: Vector3, side: float, shell: Material, cuff: Material) -> void:
	var h := _floater(parent, pos, 0.03)
	_mi(h, ProcMesh.sphere(0.07, 16, 8), shell, Vector3.ZERO, Vector3.ZERO, Vector3(0.75, 0.6, 1.15))
	_mi(h, ProcMesh.sphere(0.026, 10, 5), shell, Vector3(-side * 0.045, 0.02, -0.05))
	_mi(h, ProcMesh.torus(0.045, 0.06, 18, 4), cuff, Vector3(0, 0, 0.065), Vector3(90, 0, 0))
	_mi(h, ProcMesh.cyl(0.03, 0.03, 0.006, 14), _glow(MINT, 3.0), Vector3(-side * 0.05, 0, 0), Vector3(0, 0, 90))


## Mk IV: a levitating pearl-and-tangerine spinning-top shell with a wraparound scanner band, two orbiting rings, floating hands,
## a downward thruster and a tractor-beam dish; junk enters through the glowing crown intake.
func _scoop_hover() -> void:
	var pearl: Material = _gloss(Color(0.97, 0.96, 0.94), 0.14, 0.15, 1.0)
	var tang: Material = _gloss(Color(1.0, 0.48, 0.12), 0.2, 0.15, 1.0)
	var gold: Material = _gloss(Color(1.0, 0.76, 0.35), 0.2, 1.0, 0.0)
	var dark: Material = _gloss(Color(0.05, 0.06, 0.08), 0.12, 0.3, 1.0)
	var c := Vector3(0, 0.88, 0)
	# Wide, low spinning-top shell (deliberately not an egg), tangerine underside.
	_mi(_body, ProcMesh.sphere(0.3, 32, 14), pearl, c, Vector3.ZERO, Vector3(1.3, 0.8, 1.3))
	_mi(_body, ProcMesh.hemisphere(0.305, 32, 8), tang, c, Vector3(180, 0, 0), Vector3(1.3, 0.95, 1.3))
	_mi(_body, ProcMesh.torus(0.37, 0.4, 40, 6), gold, c, Vector3.ZERO, Vector3(1.0, 0.7, 1.0))
	_mi(_body, ProcMesh.torus(0.392, 0.398, 40, 3), _glow(MINT, 2.5), c + Vector3(0, -0.012, 0))
	# Scanner band: a dark ring all the way around the shell with one glowing scan segment.
	_mi(_body, ProcMesh.torus(0.33, 0.395, 40, 6), dark, c + Vector3(0, 0.08, 0), Vector3.ZERO, Vector3(1.0, 0.55, 1.0))
	_eye = _node(_body, c + Vector3(0, 0.08, -0.38))
	_eye_mat = _glow(MINT, 4.0)
	_mi(_eye, ProcMesh.box(Vector3(0.16, 0.03, 0.03)), _eye_mat, Vector3.ZERO)
	_mi(_eye, ProcMesh.box(Vector3(0.04, 0.03, 0.03)), _glow(Color(1.0, 0.6, 0.2), 4.0), Vector3(0.11, 0, 0.01))
	# Crown intake.
	_mi(_body, ProcMesh.torus(0.07, 0.1, 22, 5), gold, c + Vector3(0, 0.235, 0))
	_mi(_body, ProcMesh.cyl(0.072, 0.072, 0.01, 18), _glow(MINT, 3.0), c + Vector3(0, 0.232, 0))
	hopper_point = c + Vector3(0, 0.27, 0)
	# Orbiting rings.
	var r1 := _ring(_body, c, Vector3(18, 0, 6), 0.9)
	_mi(r1, ProcMesh.torus(0.44, 0.465, 40, 5), gold, Vector3.ZERO)
	for i: int in 3:
		var a: float = TAU * i / 3.0
		_mi(r1, ProcMesh.sphere(0.022, 10, 5), _glow(MINT, 3.0), Vector3(cos(a), 0, sin(a)) * 0.4525)
	var r2 := _ring(_body, c + Vector3(0, -0.05, 0), Vector3(-8, 0, -24), -0.6)
	_mi(r2, ProcMesh.torus(0.5, 0.515, 40, 4), tang, Vector3.ZERO)
	_mi(r2, ProcMesh.box(Vector3(0.05, 0.03, 0.03)), _glow(MINT, 3.0), Vector3(0.508, 0, 0))
	_mi(r2, ProcMesh.box(Vector3(0.05, 0.03, 0.03)), _glow(MINT, 3.0), Vector3(-0.508, 0, 0))
	# Floating hands.
	_float_hand(_body, c + Vector3(-0.5, -0.18, -0.18), -1.0, pearl, tang)
	_float_hand(_body, c + Vector3(0.5, -0.18, -0.18), 1.0, pearl, tang)
	# Thruster and tractor dish.
	_thruster(_body, c + Vector3(0, -0.37, 0.03), 0.1, dark)
	_emitter = _node(_body, c + Vector3(0, -0.22, -0.25), Vector3(-55, 0, 0))
	_mi(_emitter, ProcMesh.cyl(0.05, 0.085, 0.07, 18), dark, Vector3.ZERO, Vector3(180, 0, 0))
	_mi(_emitter, ProcMesh.cyl(0.055, 0.055, 0.01, 18), _glow(MINT, 4.0), Vector3(0, -0.04, 0))
	emitter_point = _emitter.position


# --- Skimmer ---------------------------------------------------------------------------

## Lake bot on twin pontoons with a net basket on deck, a fan at the back and a boom net out
## front. Mk I floats on two odd plastic drums with a plank deck (and a rubber duck mascot);
## Mk II on painted pontoons with a periscope head; Mk III on glossy hulls with light strips and
## a visor head; Mk IV levitates on two glowing pods with a floating hoop and a tractor beam.
func _skim() -> void:
	var dark: Material = Mats.metal("dark_steel")
	var steel: Material = Mats.metal("steel")
	var net_mat := StandardMaterial3D.new()
	net_mat.albedo_color = Color(0.2, 0.32, 0.25, 0.55)
	net_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	net_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	net_mat.roughness = 0.9
	var hull: Material
	var trim: Material
	var accent: Material
	var hoop_mat: Material = steel
	match look:
		"salvage":
			hull = _worn(Color(0.2, 0.45, 0.8), 0.8, 0.3, 0.6)
			trim = _wood(0.4)
			accent = _worn(Color(1.0, 0.5, 0.1), 0.75, 0.4, 0.5)
		"restored":
			hull = _worn(Color(0.15, 0.62, 0.62), 0.95, 0.2, 0.3, 0.0)
			trim = _worn(Color(0.15, 0.16, 0.18), 0.95, 0.2, 0.3, 0.0)
			accent = _worn(Color(0.95, 0.2, 0.12), 0.95, 0.2, 0.3, 0.0)
			hoop_mat = Mats.metal("chrome")
		"modern":
			hull = _gloss(Color(0.95, 0.95, 0.93), 0.3, 0.0, 0.5)
			trim = _gloss(Color(0.07, 0.08, 0.09), 0.35, 0.4, 0.3)
			accent = _gloss(Color(1.0, 0.38, 0.26), 0.28)
			hoop_mat = _glow(LIME, 2.5)
		_:
			hull = _gloss(Color(0.97, 0.96, 0.94), 0.14, 0.15, 1.0)
			trim = _gloss(Color(0.05, 0.06, 0.08), 0.12, 0.3, 1.0)
			accent = _gloss(Color(1.0, 0.48, 0.12), 0.2, 0.15, 1.0)
			hoop_mat = _glow(MINT, 3.0)
	var lift: float = 0.22 if hover else 0.0
	# Pontoons.
	for x: float in [-0.34, 0.34]:
		var pc := Vector3(x, 0.13 + lift, 0.02)
		match look:
			"salvage":
				var drum: Material = hull if x < 0.0 else _worn(Color(0.85, 0.85, 0.82), 0.7, 0.3, 0.7)
				_mi(_body, ProcMesh.cyl(0.13, 0.13, 0.82, 16), drum, pc, Vector3(90, 0, 0))
				for z: float in [-0.25, 0.25]:
					_mi(_body, ProcMesh.torus(0.125, 0.14, 16, 4), Mats.rubber(), pc + Vector3(0, 0, z), Vector3(90, 0, 0))
			"restored":
				_mi(_body, ProcMesh.capsule(0.13, 0.9), hull, pc, Vector3(90, 0, 0))
				_mi(_body, ProcMesh.torus(0.128, 0.138, 18, 4), _worn(Color(0.95, 0.95, 0.92), 0.95, 0.1, 0.2, 0.0), pc + Vector3(0, 0, -0.18), Vector3(90, 0, 0))
				_mi(_body, ProcMesh.torus(0.128, 0.138, 18, 4), accent, pc + Vector3(0, 0, 0.2), Vector3(90, 0, 0))
			"modern":
				_mi(_body, ProcMesh.capsule(0.13, 0.94), hull, pc, Vector3(90, 0, 0), Vector3(1.0, 1.0, 0.8))
				_mi(_body, ProcMesh.box(Vector3(0.006, 0.02, 0.5)), _glow(LIME, 2.5), pc + Vector3(x * 0.38, 0.02, 0))
				_mi(_body, ProcMesh.box(Vector3(0.262, 0.03, 0.62)), accent, pc + Vector3(0, -0.035, 0))
			_:
				var pod := _floater(_body, pc, 0.025)
				_mi(pod, ProcMesh.sphere(0.13, 20, 10), hull, Vector3.ZERO, Vector3.ZERO, Vector3(0.9, 0.7, 3.0))
				_mi(pod, ProcMesh.sphere(0.12, 16, 8), _glow(MINT, 2.5), Vector3(0, -0.04, 0), Vector3.ZERO, Vector3(0.7, 0.3, 2.6))
				_thruster(pod, Vector3(0, -0.1, 0.2), 0.05, trim)
	# Deck across the pontoons.
	var deck_y: float = 0.29 + lift
	if look == "salvage":
		for i: int in 5:
			_mi(_body, ProcMesh.box(Vector3(0.84, 0.035, 0.12)), _wood(randf()), Vector3(randf_range(-0.02, 0.02), deck_y, -0.28 + i * 0.14), Vector3(0, randf_range(-3, 3), 0))
		_mi(_body, ProcMesh.box(Vector3(0.04, 0.05, 0.7)), dark, Vector3(-0.2, deck_y - 0.04, 0))
		_mi(_body, ProcMesh.box(Vector3(0.04, 0.05, 0.7)), dark, Vector3(0.2, deck_y - 0.04, 0))
	else:
		_mi(_body, _rbox(Vector3(0.82, 0.06, 0.72), 0.025, 2), hull if hover else trim, Vector3(0, deck_y, 0))
		if look != "restored":
			_mi(_body, ProcMesh.box(Vector3(0.6, 0.012, 0.006)), _glow(LIME if look == "modern" else MINT, 2.5), Vector3(0, deck_y, -0.363))
	# Net basket: where the catch goes.
	var bc := Vector3(0, deck_y + 0.16, 0.06)
	if look == "salvage":
		var crate: Material = _worn(Color(0.95, 0.75, 0.15), 0.8, 0.3, 0.5)
		for x2: float in [-0.19, 0.19]:
			for y2: float in [-0.08, 0.04]:
				_mi(_body, ProcMesh.box(Vector3(0.025, 0.06, 0.34)), crate, bc + Vector3(x2, y2, 0))
		for z2: float in [-0.17, 0.17]:
			for y2: float in [-0.08, 0.04]:
				_mi(_body, ProcMesh.box(Vector3(0.4, 0.06, 0.025)), crate, bc + Vector3(0, y2, z2))
	elif hover:
		_mi(_body, ProcMesh.cyl(0.2, 0.15, 0.22, 24), hull, bc)
		_mi(_body, ProcMesh.torus(0.18, 0.21, 28, 5), accent, bc + Vector3(0, 0.11, 0))
		_mi(_body, ProcMesh.cyl(0.18, 0.18, 0.01, 24), _glow(MINT, 2.5), bc + Vector3(0, 0.1, 0))
	else:
		_mi(_body, _rbox(Vector3(0.42, 0.22, 0.38), 0.04, 2), hull if look == "modern" else accent, bc)
		_mi(_body, _rbox(Vector3(0.36, 0.02, 0.32), 0.01, 1), _gloss(Color(0.03, 0.03, 0.035), 0.9, 0.0, 0.0), bc + Vector3(0, 0.105, 0))
	var catch_ := _mi(_body, ProcMesh.hemisphere(0.17, 16, 6), net_mat, bc + Vector3(0, 0.07, 0), Vector3(180, 0, 0), Vector3(1.0, 0.6, 0.9))
	catch_.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hopper_point = bc + Vector3(0, 0.12, 0)
	# Fan at the back: a duct with spinning blades (spins faster when working).
	var fan_c := Vector3(0, deck_y + 0.24, 0.42)
	_mi(_body, ProcMesh.torus(0.15, 0.18, 24, 5), dark if look == "salvage" else hull, fan_c, Vector3(90, 0, 0))
	_rod(_body, Vector3(0, deck_y, 0.36), fan_c + Vector3(0, -0.15, 0), 0.02, dark)
	var blades := _ring(_body, fan_c, Vector3(90, 0, 0), 6.0)
	for k: int in 3:
		_mi(blades, ProcMesh.box(Vector3(0.05, 0.01, 0.14)), accent, Vector3(sin(k * TAU / 3.0), 0, cos(k * TAU / 3.0)) * 0.07, Vector3(0, k * 120.0, 0))
	_mi(blades, ProcMesh.sphere(0.03, 10, 5), steel, Vector3.ZERO)
	# Head on a mast behind the basket.
	match look:
		"salvage":
			_rod(_body, Vector3(-0.26, deck_y, 0.24), Vector3(-0.24, deck_y + 0.5, 0.2), 0.02, _worn(Color(0.5, 0.5, 0.48), 0.2, 0.9, 0.6))
			_head = _node(_body, Vector3(-0.24, deck_y + 0.56, 0.18), Vector3(0, 0, -8))
			_mi(_head, ProcMesh.cyl(0.07, 0.07, 0.14, 16), _worn(Color(0.2, 0.6, 0.55), 0.6, 0.7), Vector3.ZERO, Vector3(90, 0, 0))
			_mi(_head, ProcMesh.torus(0.065, 0.075, 16, 4), steel, Vector3(0, 0, 0.04), Vector3(90, 0, 0))
			_round_eye(_head, Vector3(0, 0, -0.072), 0.042, AMBER, Mats.metal("chrome"))
			_antenna = _node(_head, Vector3(0.03, 0.065, 0.03))
			_rod(_antenna, Vector3.ZERO, Vector3(0.0, 0.12, 0.02), 0.004, steel, 5)
			_mi(_antenna, ProcMesh.sphere(0.016, 8, 4), _worn(Color(0.9, 0.15, 0.1), 0.8, 0.3), Vector3(0.0, 0.125, 0.02))
			# Rubber duck mascot riding up front.
			var duck := _node(_body, Vector3(0.27, deck_y + 0.02, -0.26), Vector3(0, 20, 0))
			var yel: Material = _gloss(Color(1.0, 0.82, 0.1), 0.35, 0.0, 0.3)
			_mi(duck, ProcMesh.sphere(0.05, 12, 6), yel, Vector3(0, 0.04, 0), Vector3.ZERO, Vector3(1.0, 0.8, 1.25))
			_mi(duck, ProcMesh.sphere(0.032, 10, 5), yel, Vector3(0, 0.1, -0.035))
			_mi(duck, ProcMesh.box(Vector3(0.025, 0.01, 0.025)), _gloss(Color(1.0, 0.45, 0.05), 0.4, 0.0, 0.0), Vector3(0, 0.097, -0.068))
		"restored":
			_rod(_body, Vector3(-0.22, deck_y, 0.24), Vector3(-0.22, 0.64, 0.24), 0.03, trim)
			_head_restored(Vector3(-0.22, deck_y + 0.62, 0.2), hull, trim, accent)
		"modern":
			_mi(_body, ProcMesh.cyl(0.04, 0.05, 0.12, 14), trim, Vector3(-0.22, deck_y + 0.08, 0.22))
			_mi(_body, ProcMesh.torus(0.045, 0.065, 18, 4), _glow(LIME, 3.0), Vector3(-0.22, deck_y + 0.15, 0.22))
			var hf := _floater(_body, Vector3(-0.22, deck_y + 0.3, 0.2), 0.012)
			_head = _node(hf, Vector3.ZERO)
			_mi(_head, _rbox(Vector3(0.26, 0.15, 0.2), 0.065, 3), hull, Vector3.ZERO)
			_mi(_head, _rbox(Vector3(0.265, 0.05, 0.205), 0.02, 2), accent, Vector3(0, 0.05, 0))
			_mi(_head, _rbox(Vector3(0.2, 0.07, 0.03), 0.025, 2), _gloss(Color(0.02, 0.03, 0.04), 0.05, 0.3, 1.0), Vector3(0, -0.005, -0.095))
			_eye = _node(_head, Vector3(0, -0.005, -0.112))
			_eye_mat = _glow(LIME, 3.5)
			_mi(_eye, _rbox(Vector3(0.13, 0.03, 0.006), 0.01, 1), _eye_mat, Vector3.ZERO)
		_:
			var hc := Vector3(-0.2, deck_y + 0.36, 0.2)
			var hf2 := _floater(_body, hc, 0.02)
			_head = _node(hf2, Vector3.ZERO)
			_mi(_head, ProcMesh.sphere(0.12, 24, 12), hull, Vector3.ZERO, Vector3.ZERO, Vector3(1.15, 0.85, 1.0))
			_mi(_head, ProcMesh.torus(0.11, 0.14, 28, 5), trim, Vector3(0, 0.0, 0), Vector3.ZERO, Vector3(1.0, 0.6, 1.0))
			_eye = _node(_head, Vector3(0, 0.0, -0.13))
			_eye_mat = _glow(MINT, 4.0)
			_mi(_eye, ProcMesh.box(Vector3(0.1, 0.025, 0.025)), _eye_mat, Vector3.ZERO)
			var r1 := _ring(_body, hc, Vector3(15, 0, 8), 1.1)
			_mi(r1, ProcMesh.torus(0.19, 0.205, 32, 4), _gloss(Color(1.0, 0.76, 0.35), 0.2, 1.0, 0.0), Vector3.ZERO)
	if look in ["salvage", "restored"]:
		_stencil(_body, "SKM-%d" % (1 if look == "salvage" else 2), Vector3(0.48, 0.14 + lift, 0.0), Vector3(0, 90, 0), 40, Color(0.95, 0.95, 0.9, 0.85))
	# Net arm: a boom out front with a hoop net that dips into the water.
	_arm = _node(_body, Vector3(0, deck_y + 0.12, -0.3))
	var boom: Material = _worn(Color(0.5, 0.5, 0.48), 0.2, 0.9, 0.6) if look == "salvage" else trim
	if hover:
		var hoop_f := _floater(_arm, Vector3(0, -0.12, -0.42), 0.03)
		_mi(hoop_f, ProcMesh.torus(0.15, 0.175, 28, 5), hoop_mat, Vector3.ZERO, Vector3(-20, 0, 0))
		var hn := _mi(hoop_f, ProcMesh.hemisphere(0.15, 16, 6), net_mat, Vector3(0, -0.01, 0), Vector3(160, 0, 0), Vector3(1.0, 0.8, 1.0))
		hn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_emitter = _node(_body, Vector3(0, deck_y + 0.02, -0.34), Vector3(-55, 0, 0))
		_mi(_emitter, ProcMesh.cyl(0.04, 0.07, 0.06, 18), trim, Vector3.ZERO, Vector3(180, 0, 0))
		_mi(_emitter, ProcMesh.cyl(0.045, 0.045, 0.01, 18), _glow(MINT, 4.0), Vector3(0, -0.035, 0))
		emitter_point = _emitter.position
	else:
		_mi(_arm, ProcMesh.cyl(0.03, 0.03, 0.2, 10), dark, Vector3.ZERO, Vector3(0, 0, 90))
		var tip := Vector3(0, -0.2, -0.42)
		if look == "restored":
			for x3: float in [-0.06, 0.06]:
				_rod(_arm, Vector3(x3, 0, 0), tip + Vector3(x3, 0.06, 0.1), 0.016, boom)
		else:
			_rod(_arm, Vector3.ZERO, tip + Vector3(0, 0.06, 0.1), 0.022 if look == "salvage" else 0.026, boom)
		if look == "modern":
			_mi(_arm, ProcMesh.torus(0.025, 0.04, 14, 4), _glow(LIME, 3.0), tip + Vector3(0, 0.06, 0.1), Vector3(-60, 0, 0))
		_mi(_arm, ProcMesh.torus(0.15, 0.17, 28, 5), hoop_mat, tip, Vector3(-25, 0, 0))
		var an := _mi(_arm, ProcMesh.hemisphere(0.15, 16, 6), net_mat, tip + Vector3(0, -0.01, 0), Vector3(155, 0, 0), Vector3(1.0, 0.8, 1.0))
		an.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		emitter_point = _arm.position + tip
	nozzle_point = emitter_point


# --- Haul Bug --------------------------------------------------------------------------

## Mk I: a pallet on mismatched wheels with a pipe mast, rebar forks, a toolbox "engine",
## a concrete-block counterweight and a scavenged headlight eye wearing a hard hat.
func _haul_salvage() -> void:
	var frame: Material = Mats.metal("dark_steel")
	var tyre: Material = Mats.rubber()
	var pipe: Material = _worn(Color(0.5, 0.5, 0.5), 0.15, 0.9, 0.6)
	for x: float in [-0.26, 0.26]:
		_mi(_body, ProcMesh.box(Vector3(0.05, 0.05, 0.84)), frame, Vector3(x, 0.2, 0.12))
	for z: float in [-0.26, 0.5]:
		_mi(_body, ProcMesh.box(Vector3(0.56, 0.045, 0.05)), frame, Vector3(0, 0.2, z))
	_wheel(_body, Vector3(-0.34, 0.16, 0.38), 0.16, 0.1, tyre, _worn(Color(0.2, 0.5, 0.75), 0.7, 0.6))
	_wheel(_body, Vector3(0.34, 0.14, 0.38), 0.14, 0.06, tyre, Mats.metal("steel"))
	_wheel(_body, Vector3(-0.32, 0.11, -0.12), 0.11, 0.06, tyre, _worn(Color(0.9, 0.75, 0.2), 0.7, 0.5))
	_wheel(_body, Vector3(0.31, 0.09, -0.12), 0.09, 0.05, Mats.rubber(Color(0.7, 0.68, 0.6)), frame)
	for i: int in 5:
		_mi(_body, ProcMesh.box(Vector3(0.62, 0.025, 0.12)), _wood(randf()), Vector3(randf_range(-0.02, 0.02), 0.236, -0.18 + i * 0.15), Vector3(0, randf_range(-3, 3), 0))
	# Counterweight and toolbox engine.
	var conc := StandardMaterial3D.new()
	conc.albedo_color = Color(0.55, 0.54, 0.5)
	conc.roughness = 0.95
	_mi(_body, ProcMesh.box(Vector3(0.4, 0.19, 0.19)), conc, Vector3(0, 0.345, 0.47))
	_stencil(_body, "HAUL", Vector3(0, 0.35, 0.566), Vector3.ZERO, 56, Color(0.85, 0.2, 0.12, 0.85))
	var red: Material = _worn(Color(0.85, 0.15, 0.1), 0.7, 0.6)
	_mi(_body, _rbox(Vector3(0.3, 0.16, 0.16), 0.015, 1), red, Vector3(0.1, 0.33, 0.18))
	_rod(_body, Vector3(0.0, 0.43, 0.18), Vector3(0.2, 0.43, 0.18), 0.008, Mats.metal("steel"))
	_cable(_body, Vector3(0.0, 0.35, 0.1), Vector3(-0.12, 0.3, -0.05), Vector3(-0.2, 0.55, -0.22), 0.009, Mats.rubber(Color(0.85, 0.7, 0.1)))
	_cable(_body, Vector3(0.2, 0.38, 0.1), Vector3(0.3, 0.6, 0.0), Vector3(0.2, 0.75, -0.22), 0.008, Mats.rubber(Color(0.75, 0.1, 0.08)))
	# Pipe mast.
	for x: float in [-0.2, 0.2]:
		_rod(_body, Vector3(x, 0.18, -0.24), Vector3(x, 0.95, -0.24), 0.022, pipe)
	_rod(_body, Vector3(-0.2, 0.95, -0.24), Vector3(0.2, 0.95, -0.24), 0.02, pipe)
	_rod(_body, Vector3(-0.2, 0.6, -0.24), Vector3(0.2, 0.62, -0.24), 0.016, frame)
	# Rebar forks on a plank carriage.
	_mi(_body, ProcMesh.box(Vector3(0.46, 0.16, 0.03)), _wood(0.3), Vector3(0, 0.22, -0.28))
	for x: float in [-0.15, 0.15]:
		_mi(_body, ProcMesh.box(Vector3(0.06, 0.2, 0.025)), frame, Vector3(x, 0.2, -0.305))
		_mi(_body, ProcMesh.box(Vector3(0.065, 0.025, 0.5)), _worn(Color(0.5, 0.5, 0.5), 0.1, 0.95), Vector3(x, 0.115, -0.55), Vector3(0, x * 10.0, 0))
	fork_point = Vector3(0, 0.13, -0.56)
	# Headlight eye with a hard hat, perched on the mast.
	_head = _node(_body, Vector3(0.0, 1.03, -0.24), Vector3(0, 0, -8))
	_mi(_head, ProcMesh.cyl(0.085, 0.07, 0.1, 18), Mats.metal("chrome"), Vector3.ZERO, Vector3(90, 0, 0))
	_mi(_head, ProcMesh.box(Vector3(0.05, 0.06, 0.04)), frame, Vector3(0, -0.07, 0.02))
	_round_eye(_head, Vector3(0, 0, -0.052), 0.06, AMBER, Mats.metal("steel"))
	_mi(_head, ProcMesh.hemisphere(0.085, 16, 5), _worn(Color(1.0, 0.82, 0.1), 0.85, 0.4), Vector3(0, 0.07, 0.01))
	_mi(_head, ProcMesh.cyl(0.105, 0.105, 0.01, 16), _worn(Color(1.0, 0.82, 0.1), 0.85, 0.4), Vector3(0, 0.072, -0.01), Vector3(-6, 0, 0))
	_antenna = _node(_body, Vector3(0.2, 0.95, -0.24))
	_rod(_antenna, Vector3.ZERO, Vector3(0.04, 0.2, 0.03), 0.004, Mats.metal("steel"), 5)
	_mi(_antenna, ProcMesh.box(Vector3(0.002, 0.05, 0.08)), _worn(Color(0.9, 0.2, 0.1), 0.9, 0.2), Vector3(0.04, 0.18, 0.07))
	emitter_point = Vector3(0, 0.5, -0.5)


## Mk II: a stubby repainted forklift in signal orange with a striped counterweight, chrome ram and
## the same tidy periscope head as the Mk II Scoopie.
func _haul_restored() -> void:
	var paint: Material = _worn(Color(1.0, 0.42, 0.06), 0.94, 0.25, 0.35, 0.05)
	var trim: Material = _worn(Color(0.15, 0.16, 0.18), 0.95, 0.2, 0.3, 0.0)
	var accent: Material = _worn(Color(1.0, 0.82, 0.12), 0.95, 0.2, 0.3, 0.0)
	var tyre: Material = Mats.rubber()
	for x: float in [-0.38, 0.38]:
		for z: float in [-0.1, 0.4]:
			_wheel(_body, Vector3(x, 0.15, z), 0.15, 0.11, tyre, accent)
			_mi(_body, _rbox(Vector3(0.15, 0.03, 0.34), 0.012, 2), paint, Vector3(x, 0.32, z))
	_mi(_body, _rbox(Vector3(0.64, 0.32, 0.74), 0.07, 3), paint, Vector3(0, 0.36, 0.15))
	_mi(_body, _rbox(Vector3(0.66, 0.24, 0.18), 0.05, 2), trim, Vector3(0, 0.46, 0.55))
	for i: int in 4:
		_mi(_body, ProcMesh.box(Vector3(0.06, 0.2, 0.01)), accent, Vector3(-0.24 + i * 0.16, 0.46, 0.643), Vector3(0, 0, 35))
	_stencil(_body, "HB-2", Vector3(0.323, 0.36, 0.1), Vector3(0, 90, 0), 56, Color(0.12, 0.12, 0.13, 0.9))
	_stencil(_body, "HB-2", Vector3(-0.323, 0.36, 0.2), Vector3(0, -90, 0), 56, Color(0.12, 0.12, 0.13, 0.9))
	for x: float in [-0.2, 0.2]:
		_mi(_body, ProcMesh.cyl(0.03, 0.03, 0.012, 14), Mats.lamp(Color(1.0, 0.92, 0.75), 1.5), Vector3(x, 0.4, -0.225), Vector3(90, 0, 0))
	# Mast with chrome ram.
	for x: float in [-0.21, 0.21]:
		_mi(_body, ProcMesh.box(Vector3(0.055, 0.86, 0.065)), trim, Vector3(x, 0.58, -0.27))
	_mi(_body, ProcMesh.box(Vector3(0.48, 0.05, 0.06)), trim, Vector3(0, 1.0, -0.27))
	_mi(_body, ProcMesh.cyl(0.025, 0.025, 0.7, 12), Mats.metal("chrome"), Vector3(0, 0.55, -0.24))
	_mi(_body, ProcMesh.cyl(0.04, 0.04, 0.3, 12), trim, Vector3(0, 0.3, -0.24))
	_mi(_body, ProcMesh.box(Vector3(0.5, 0.22, 0.04)), paint, Vector3(0, 0.25, -0.32))
	for x: float in [-0.15, 0.15]:
		_mi(_body, ProcMesh.box(Vector3(0.075, 0.22, 0.03)), Mats.metal("steel"), Vector3(x, 0.24, -0.355))
		_mi(_body, ProcMesh.box(Vector3(0.08, 0.03, 0.52)), Mats.metal("steel"), Vector3(x, 0.13, -0.6))
	fork_point = Vector3(0, 0.145, -0.62)
	_head_restored(Vector3(0.1, 0.82, 0.32), paint, trim, accent)
	emitter_point = Vector3(0, 0.5, -0.5)


## Mk III: glossy white shell, coral band, lime strips; the forks ride a glowing mag-rail with no mast,
## and a floating visor head sits on a magnetic neck.
func _haul_modern() -> void:
	var white: Material = _gloss(Color(0.95, 0.94, 0.92), 0.35, 0.0, 0.5)
	var coral: Material = _gloss(Color(1.0, 0.38, 0.26), 0.28)
	var dark: Material = _gloss(Color(0.07, 0.08, 0.09), 0.35, 0.4, 0.3)
	var lite: Material = _glow(LIME, 2.5)
	_mi(_body, _rbox(Vector3(0.62, 0.14, 0.82), 0.06, 2), dark, Vector3(0, 0.13, 0.15))
	for x: float in [-0.27, 0.27]:
		for z: float in [-0.12, 0.42]:
			_wheel(_body, Vector3(x, 0.09, z), 0.09, 0.07, Mats.rubber(), dark)
	_mi(_body, _rbox(Vector3(0.7, 0.36, 0.84), 0.15, 4), white, Vector3(0, 0.39, 0.15))
	_mi(_body, _rbox(Vector3(0.716, 0.18, 0.856), 0.12, 3), coral, Vector3(0, 0.29, 0.15))
	for x: float in [-0.351, 0.351]:
		_mi(_body, ProcMesh.box(Vector3(0.004, 0.16, 0.004)), dark, Vector3(x, 0.45, 0.3))
	for x: float in [-0.352, 0.352]:
		_mi(_body, ProcMesh.box(Vector3(0.006, 0.022, 0.46)), lite, Vector3(x, 0.47, 0.12))
	_mi(_body, ProcMesh.box(Vector3(0.36, 0.022, 0.006)), lite, Vector3(0, 0.47, 0.572))
	# Mag rail and floating fork carriage.
	_mi(_body, _rbox(Vector3(0.48, 0.4, 0.06), 0.03, 2), dark, Vector3(0, 0.42, -0.28))
	_mi(_body, _rbox(Vector3(0.5, 0.06, 0.08), 0.025, 2), coral, Vector3(0, 0.63, -0.28))
	for x: float in [-0.19, 0.19]:
		_mi(_body, ProcMesh.box(Vector3(0.016, 0.34, 0.006)), lite, Vector3(x, 0.42, -0.312))
	var forks := _floater(_body, Vector3.ZERO, 0.008)
	_mi(forks, _rbox(Vector3(0.46, 0.14, 0.035), 0.02, 2), coral, Vector3(0, 0.26, -0.34))
	for x: float in [-0.15, 0.15]:
		_mi(forks, _rbox(Vector3(0.085, 0.03, 0.54), 0.012, 2), white, Vector3(x, 0.135, -0.62))
		_mi(forks, ProcMesh.box(Vector3(0.02, 0.006, 0.4)), lite, Vector3(x, 0.151, -0.64))
		_mi(forks, _rbox(Vector3(0.085, 0.15, 0.03), 0.012, 2), white, Vector3(x, 0.2, -0.36))
	fork_point = Vector3(0, 0.15, -0.64)
	# Floating head.
	_mi(_body, ProcMesh.cyl(0.04, 0.05, 0.1, 14), dark, Vector3(0, 0.62, 0.32))
	_mi(_body, ProcMesh.torus(0.045, 0.065, 18, 4), _glow(LIME, 3.0), Vector3(0, 0.685, 0.32))
	var hf := _floater(_body, Vector3(0, 0.79, 0.3), 0.012)
	_head = _node(hf, Vector3.ZERO)
	_mi(_head, _rbox(Vector3(0.34, 0.19, 0.25), 0.085, 3), white, Vector3.ZERO)
	_mi(_head, _rbox(Vector3(0.345, 0.07, 0.255), 0.03, 2), coral, Vector3(0, 0.065, 0.0))
	_mi(_head, _rbox(Vector3(0.28, 0.1, 0.03), 0.03, 2), _gloss(Color(0.02, 0.03, 0.04), 0.05, 0.3, 1.0), Vector3(0, -0.005, -0.118))
	_eye = _node(_head, Vector3(0, -0.005, -0.135))
	_eye_mat = _glow(LIME, 3.5)
	_mi(_eye, _rbox(Vector3(0.17, 0.035, 0.006), 0.012, 1), _eye_mat, Vector3.ZERO)
	_antenna = _node(_head, Vector3(0.12, 0.09, 0.06))
	_rod(_antenna, Vector3.ZERO, Vector3(0, 0.08, 0), 0.006, dark, 6)
	_mi(_antenna, ProcMesh.sphere(0.018, 10, 5), coral, Vector3(0, 0.085, 0))
	emitter_point = Vector3(0, 0.5, -0.5)


## Mk IV: a hovering cargo drone. Teardrop body with an orbiting ring, twin thrusters, and two floating
## clamp pads that hold bales in a glowing field out front.
func _haul_hover() -> void:
	var pearl: Material = _gloss(Color(0.97, 0.96, 0.94), 0.14, 0.15, 1.0)
	var tang: Material = _gloss(Color(1.0, 0.48, 0.12), 0.2, 0.15, 1.0)
	var gold: Material = _gloss(Color(1.0, 0.76, 0.35), 0.2, 1.0, 0.0)
	var dark: Material = _gloss(Color(0.05, 0.06, 0.08), 0.12, 0.3, 1.0)
	var c := Vector3(0, 1.02, 0.28)
	_mi(_body, ProcMesh.sphere(0.3, 28, 14), pearl, c, Vector3.ZERO, Vector3(1.05, 0.72, 1.3))
	_mi(_body, ProcMesh.hemisphere(0.305, 28, 8), tang, c, Vector3(180, 0, 0), Vector3(1.05, 0.8, 1.3))
	_mi(_body, ProcMesh.cyl(0.0, 0.14, 0.32, 18), pearl, c + Vector3(0, 0, 0.42), Vector3(-90, 0, 0), Vector3(1.0, 1.0, 0.6))
	_mi(_body, ProcMesh.torus(0.31, 0.33, 36, 6), gold, c, Vector3.ZERO, Vector3(1.05, 0.6, 1.3))
	_mi(_body, ProcMesh.torus(0.3, 0.335, 40, 6), dark, c + Vector3(0, 0.05, 0), Vector3.ZERO, Vector3(1.05, 0.5, 1.3))
	_eye = _node(_body, c + Vector3(0, 0.05, -0.43))
	_eye_mat = _glow(MINT, 4.0)
	_mi(_eye, ProcMesh.box(Vector3(0.14, 0.025, 0.03)), _eye_mat, Vector3.ZERO)
	var r1 := _ring(_body, c, Vector3(90, 0, 0), 0.8)
	_mi(r1, ProcMesh.torus(0.46, 0.48, 40, 5), gold, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.0, 0.85))
	for i: int in 4:
		var a: float = TAU * i / 4.0
		_mi(r1, ProcMesh.sphere(0.02, 10, 5), _glow(MINT, 3.0), Vector3(cos(a), 0, sin(a) * 0.85) * 0.47)
	for x: float in [-0.2, 0.2]:
		_thruster(_body, c + Vector3(x, -0.22, 0.1), 0.08, dark)
	# Clamp pads and field.
	var fc := Vector3(0, 0.66, -0.68)
	for s: float in [-1.0, 1.0]:
		var pad := _floater(_body, fc + Vector3(s * 0.37, 0.02, 0), 0.012)
		_mi(pad, _rbox(Vector3(0.07, 0.5, 0.48), 0.03, 2), pearl, Vector3.ZERO)
		_mi(pad, _rbox(Vector3(0.075, 0.08, 0.5), 0.03, 2), tang, Vector3(0, 0.2, 0))
		_mi(pad, ProcMesh.box(Vector3(0.006, 0.36, 0.36)), _glow(MINT, 3.0), Vector3(-s * 0.037, -0.02, 0))
		_mi(pad, ProcMesh.cyl(0.03, 0.03, 0.01, 12), _glow(MINT, 3.0), Vector3(0, -0.255, 0))
		_rod(_body, c + Vector3(s * 0.22, -0.05, -0.25), fc + Vector3(s * 0.34, 0.24, 0.2), 0.012, _additive(Color(0.2, 0.8, 0.7, 0.25)), 6)
	_field_mat = _additive(Color(0.2, 0.9, 0.75, 0.08))
	var field := _mi(_body, ProcMesh.box(Vector3(0.66, 0.62, 0.56)), _field_mat, fc)
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fork_point = fc - Vector3(0, 0.3, 0)
	_emitter = _node(_body, c + Vector3(0, -0.12, -0.32), Vector3(-40, 0, 0))
	_mi(_emitter, ProcMesh.cyl(0.04, 0.07, 0.06, 18), dark, Vector3.ZERO, Vector3(180, 0, 0))
	_mi(_emitter, ProcMesh.cyl(0.045, 0.045, 0.01, 18), _glow(MINT, 4.0), Vector3(0, -0.035, 0))
	emitter_point = _emitter.position


# --- Tractor beam ----------------------------------------------------------------------

func _build_beam() -> void:
	_beam = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.05
	cone.bottom_radius = 0.3
	cone.height = 1.0
	cone.radial_segments = 24
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	_beam.mesh = cone
	# Same tractor_beam shader as Patch's claw, lighter (no swirl, dimmer) so it stays a helper.
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = preload("res://art/shaders/tractor_beam.gdshader")
	_beam_mat.set_shader_parameter("beam_color", MINT)
	_beam_mat.set_shader_parameter("intensity", 0.55)
	_beam_mat.set_shader_parameter("swirl", 0.35)
	_beam_mat.set_shader_parameter("ring_spacing", 0.16)
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)
	var core := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.02
	cm.bottom_radius = 0.09
	cm.height = 1.0
	cm.radial_segments = 12
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	core.mesh = cm
	_beam_core_mat = _additive(Color(0.6, 1.0, 0.9, 0.35))
	core.material_override = _beam_core_mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.add_child(core)


## Points the tractor beam from the emitter to a world position (hover tier). null hides it.
func beam_to(world_pos: Variant) -> void:
	if _beam == null:
		return
	if world_pos == null or not (hover or look == "modern"):
		_beam.visible = false
		return
	var a: Vector3 = _emitter.global_position if _emitter else to_global(emitter_point)
	var b: Vector3 = world_pos
	var len: float = maxf(a.distance_to(b), 0.05)
	_beam.visible = true
	var up: Vector3 = (a - b).normalized()
	var side: Vector3 = up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var w: float = 1.0 if hover else 0.45  # Mk III: a slim beam from the arm emitter
	_beam.global_transform = Transform3D(Basis(side * w, up * len, side.cross(up) * w), (a + b) * 0.5)
	_beam_mat.set_shader_parameter("beam_length", len)


# --- Idle life -------------------------------------------------------------------------

func animate(speed: float, working: bool, delta: float) -> void:
	_t += delta
	for w: Node3D in _wheels:
		w.rotation.x -= speed * delta / float(w.get_meta("r", 0.12))
	if hover and _body:
		_body.position.y = sin(_t * 2.2) * 0.035
		_body.rotation.z = sin(_t * 1.3) * 0.03
		_body.rotation.x = lerpf(_body.rotation.x, -clampf(speed * 0.08, 0.0, 0.15), clampf(delta * 3.0, 0.0, 1.0))
	elif _body and floats:
		# Pontoons bob and roll a little on the water.
		_body.position.y = sin(_t * 1.8 + _seed) * 0.02
		_body.rotation.z = sin(_t * 1.2 + _seed) * 0.04
		_body.rotation.x = sin(_t * 1.5) * 0.025 - clampf(speed * 0.04, 0.0, 0.08)
	elif _body:
		# Wheeled units idle-rumble; the salvage ones rattle a bit more.
		var rattle: float = 0.004 if look == "salvage" else 0.0015
		_body.position.y = absf(sin(_t * (14.0 if look == "salvage" else 9.0))) * rattle * (1.0 + speed)
	# Idle: parked with nothing to do. A slow look-around sway and a happy little hop now and then.
	if _body:
		if idle:
			_idle_t += delta
			_body.rotation.y = sin(_idle_t * 0.9 + _seed) * 0.18
			var ph: float = fmod(_idle_t + _seed, 5.5)
			if ph < 0.45:
				_body.position.y += sin(ph / 0.45 * PI) * 0.07
		else:
			_idle_t = 0.0
			_body.rotation.y = lerpf(_body.rotation.y, 0.0, clampf(delta * 5.0, 0.0, 1.0))
	if _fill_node:
		var s0: Vector3 = _fill_node.get_meta("s0", Vector3.ONE)
		var k: float = maxf(_fill, 0.03)
		if str(_fill_node.get_meta("axis", "y")) == "x":
			_fill_node.scale.x = lerpf(_fill_node.scale.x, s0.x * k, clampf(delta * 4.0, 0.0, 1.0))
		else:
			_fill_node.scale.y = lerpf(_fill_node.scale.y, s0.y * k, clampf(delta * 4.0, 0.0, 1.0))
	for r: Node3D in _rings:
		r.rotate_object_local(Vector3.UP, float(r.get_meta("spd", 1.0)) * delta * (2.5 if working else 1.0))
	for f: Node3D in _floaters:
		var base: Vector3 = f.get_meta("base")
		var amp: float = f.get_meta("amp")
		var ph: float = f.get_meta("ph")
		f.position = base + Vector3(sin(_t * 1.1 + ph) * amp * 0.6, sin(_t * 1.9 + ph) * amp, cos(_t * 0.9 + ph) * amp * 0.5)
	for fl: MeshInstance3D in _flames:
		var k: float = 0.85 + 0.15 * sin(_t * 31.0 + float(fl.get_instance_id() % 97)) + speed * 0.15
		fl.scale.y = k
		fl.position.y = float(fl.get_meta("base_y")) + float(fl.get_meta("h")) * (1.0 - k) * 0.5
	for m: StandardMaterial3D in _glow_mats:
		if m == _eye_mat:
			continue
		m.emission_energy_multiplier = float(m.get_meta("base")) * (0.85 + 0.15 * sin(_t * 3.0))
	if _eye and _eye_mat:
		var cycle: float = fmod(_t + _blink_phase, 4.2)
		var blink: bool = cycle < 0.12 or (cycle > 0.3 and cycle < 0.4 and int(_blink_phase * 10.0) % 2 == 0)
		_eye.scale.y = lerpf(_eye.scale.y, 0.12 if blink else 1.0, clampf(delta * 30.0, 0.0, 1.0))
		var e: float = float(_eye_mat.get_meta("base"))
		if look == "salvage":
			# Loose wire: the old eye sputters now and then.
			var sputter: bool = fmod(_t * 1.7 + _blink_phase, 5.0) < 0.35 and sin(_t * 60.0) > 0.0
			_eye_mat.emission_energy_multiplier = e * (0.25 if sputter else 1.0)
		else:
			_eye_mat.emission_energy_multiplier = e * (1.15 if working else 1.0) * (0.92 + 0.08 * sin(_t * 5.0))
	if _head:
		var look_y: float = sin(_t * 0.55 + _blink_phase) * 0.35 + sin(_t * 1.7) * 0.05
		_head.rotation.y = lerpf(_head.rotation.y, 0.0 if working else look_y, clampf(delta * 3.0, 0.0, 1.0))
		_head.rotation.x = lerpf(_head.rotation.x, -0.25 if working else 0.0, clampf(delta * 3.0, 0.0, 1.0))
	if _antenna:
		_antenna.rotation.z = sin(_t * 7.0) * (0.05 + 0.1 * minf(speed, 1.5))
		_antenna.rotation.x = cos(_t * 5.3) * 0.04
	if _arm and not hover:
		_arm.rotation.x = (sin(_t * 9.0) * 0.4 - 0.2) if working else lerpf(_arm.rotation.x, sin(_t * 0.8) * 0.03, delta * 4.0)
	if _field_mat:
		_field_mat.albedo_color.a = 0.07 + 0.03 * sin(_t * 4.0) + (0.05 if working else 0.0)
	if _beam and _beam.visible:
		_beam_core_mat.albedo_color.a = 0.3 + 0.1 * sin(_t * 40.0)
	if _beacon_mat:
		_beacon_mat.emission_energy_multiplier = 1.0 + (2.0 if fmod(_t, 1.4) < 0.15 else 0.0)
