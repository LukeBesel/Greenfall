class_name RobotVisual
extends Node3D
## Helper-robot models. Three body types (scoopie, haul bug, skimmer; planters, waterers and
## multibots are scoopie bodies with a job kit), four looks by tier:
##   salvage  (Mk I)  worn through: chipped faded paint, a cover missing, a patch plate, a dim amber glow.
##   restored (Mk II) repainted, all covers on, ear rings lit.
##   modern   (Mk III) clean lacquer, light strips, lit hubs.
##   hover    (Mk IV) hover pods instead of wheels.
## [art6] Scoopie and Haul Bug are Blender-built (art/models/robots) in Lumi's family: a pale
## shell with the type's own accent colour (Scoopie yellow, Haul Bug orange), dark mechanics, a
## visor with two eyes and a glow ring that lights the ground. The Skimmer is still procedural.
## Faces -Z.

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
## Where a backpack tank hangs (waterer kits).
var back_point := Vector3(0, 0.62, 0.47)

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
	_worker = false
	_base = null
	_far = null
	_bucket = null
	_meter = null
	_ground = null
	_near.clear()
	_paint_mats.clear()
	_rams.clear()
	_clamps.clear()
	_feelers.clear()
	_pods.clear()
	_load_seen = -1
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
	if base_type == "skimmer":
		_skim()
	else:
		_build_worker(base_type)
	if type_id != base_type:
		_job_kit(type_id)
	_build_beam()


## Job accessories that set planters, waterers and multibots apart from cleaners.
func _job_kit(t: String) -> void:
	var top: Vector3 = hopper_point + Vector3(0, 0.08, 0.12)
	var shiny: bool = look in ["modern", "hover"]
	match t:
		"seedling":
			@warning_ignore("incompatible_ternary")
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
	var _steel: Material = Mats.metal("steel")
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
			var bp := back_point
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
			var bp := back_point + Vector3(0, 0.01, 0)
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


# --- Workers: Scoopie and Haul Bug -----------------------------------------------------
# [art6] Built in Blender (art/models/robots/build_workers.py -> workers.glb), same maker as Lumi:
# pale chipped shells over dark mechanics, panel grooves, bolts, glow rings, a dark visor with two
# round eyes. One machine per type; the four looks are its life: Mk I salvage (worn through, a side
# cover missing, a patch plate, dim amber), Mk II restored (repainted, ear rings), Mk III modern
# (clean lacquer, light strips, lit hubs), Mk IV hover (hover pods instead of wheels).
# Material slots (glb surface names): paint, accent, bucket, trim, dark, steel, tyre, glass, lamp,
# glow, eye. Colours and wear per look are in WORKER_LOOKS / WORKER_PAINT below.

const WORKERS_PATH := "res://art/models/robots/workers.glb"
const HERO_PAINT := preload("res://art/shaders/hero_paint.gdshader")
const WORKER_FAR := preload("res://art/shaders/worker_far.gdshader")
## Beyond this many metres from the camera a worker is one mesh (a few hundred triangles, one
## draw) and its part animation rests.
const FAR_M: float = 34.0
const WORKER_LOOKS := {
	"salvage": {"cover": 0.6, "rust": 0.75, "grime": 0.9, "dust": 0.65, "specks": 1.0, "edge": 0.9, "coat": 0.0, "glow": AMBER, "ring": 1.2},
	"restored": {"cover": 0.86, "rust": 0.35, "grime": 0.6, "dust": 0.45, "specks": 0.8, "edge": 0.65, "coat": 0.25, "glow": WARM, "ring": 1.8},
	"modern": {"cover": 0.93, "rust": 0.15, "grime": 0.4, "dust": 0.3, "specks": 0.5, "edge": 0.45, "coat": 0.7, "glow": LIME, "ring": 2.4},
	"hover": {"cover": 0.95, "rust": 0.1, "grime": 0.35, "dust": 0.25, "specks": 0.4, "edge": 0.4, "coat": 0.8, "glow": MINT, "ring": 2.8},
}
## [shell, accent] per type and look: the shell stays pale (it reads small and far), the accent is
## the type's own colour (Scoopie yellow, Haul Bug orange).
const WORKER_PAINT := {
	"scoopie": {"salvage": [Color(0.76, 0.71, 0.6), Color(0.82, 0.58, 0.12)], "restored": [Color(0.88, 0.85, 0.75), Color(1.0, 0.72, 0.06)],
		"modern": [Color(0.93, 0.92, 0.89), Color(1.0, 0.76, 0.1)], "hover": [Color(0.96, 0.95, 0.93), Color(1.0, 0.8, 0.2)]},
	"haulbug": {"salvage": [Color(0.74, 0.7, 0.62), Color(0.8, 0.36, 0.1)], "restored": [Color(0.88, 0.85, 0.77), Color(1.0, 0.42, 0.06)],
		"modern": [Color(0.93, 0.92, 0.89), Color(1.0, 0.45, 0.14)], "hover": [Color(0.96, 0.95, 0.93), Color(1.0, 0.5, 0.16)]},
}
## Pivots and mounting points printed by build_workers.py (robot space, metres).
const SC := {"head": Vector3(0, 0.7, -0.2), "eyes": Vector3(0, 0.839, -0.312), "antenna": Vector3(0.1, 0.925, -0.165), "boom": Vector3(0, 0.53, 0),
	"bucket": Vector3(0, 0.2, -0.535), "ram_foot": Vector3(0.312, 0.25, 0.12), "ram_ear": Vector3(0.312, 0.4, -0.25), "wheel_r": 0.15,
	"wheels": [Vector3(-0.355, 0.15, -0.25), Vector3(0.355, 0.15, -0.25), Vector3(-0.355, 0.15, 0.27), Vector3(0.355, 0.15, 0.27)],
	"pods": [Vector3(-0.3, 0.1, -0.22), Vector3(0.3, 0.1, -0.22), Vector3(-0.3, 0.1, 0.26), Vector3(0.3, 0.1, 0.26)]}
const HB := {"head": Vector3(0, 0.56, -0.4), "eyes": Vector3(0, 0.669, -0.522), "feeler": Vector3(0.11, 0.745, -0.4), "hinge": Vector3(0.465, 0.345, 0.3),
	"fork": Vector3(0, 0.2, -0.6), "meter": Vector3(-0.24, 0.605, -0.005), "bed": Vector3(0, 0.335, 0.3), "wheel_r": 0.13,
	"wheels": [Vector3(-0.4, 0.13, -0.36), Vector3(0.4, 0.13, -0.36), Vector3(-0.4, 0.13, 0.08), Vector3(0.4, 0.13, 0.08), Vector3(-0.4, 0.13, 0.5), Vector3(0.4, 0.13, 0.5)],
	"pods": [Vector3(-0.33, 0.1, -0.3), Vector3(0.33, 0.1, -0.3), Vector3(-0.33, 0.1, 0.14), Vector3(0.33, 0.1, 0.14), Vector3(-0.33, 0.1, 0.52), Vector3(0.33, 0.1, 0.52)]}
const CLAMP_OPEN: float = -0.5
const CLAMP_SHUT: float = 0.16
const HAUL_FULL: int = 6

static var _wparts: Dictionary = {}
static var _lamp_mat: StandardMaterial3D
static var _visor_mat: StandardMaterial3D
static var _glow_tex: GradientTexture2D
static var _sun_dir := Vector3(-0.5, 0.6, 0.6)
static var _sun_frame: int = -1000

## True for the Blender-built bodies (Scoopie and Haul Bug bases).
var _worker: bool = false
var _base: Node3D
var _far: MeshInstance3D
var _far_mat: ShaderMaterial
var _near: Array[MeshInstance3D] = []
var _paint_mats: Array[ShaderMaterial] = []
var _mats: Dictionary = {}
var _ring_mat: StandardMaterial3D
var _status_mat: StandardMaterial3D
var _ground: MeshInstance3D
var _ground_mat: StandardMaterial3D
var _bucket: Node3D
var _rams: Array = []          # [barrel node, rod node, foot (body space), ear (arm space)]
var _clamps: Array[Node3D] = []
var _feelers: Array[Node3D] = []
var _meter: Node3D
var _pods: Array[Node3D] = []
var _bed_at := Vector3.ZERO
# Motion with weight (see _animate_worker): everything below rides springs.
var _spd_prev: float = 0.0
var _acc: float = 0.0
var _turn: float = 0.0
var _fwd_prev := Vector3.ZERO
var _sq: float = 0.0           # body height on its suspension (m)
var _sq_v: float = 0.0
var _pitch: float = 0.0
var _pitch_v: float = 0.0
var _roll: float = 0.0
var _roll_v: float = 0.0
var _arm_a: float = 0.0
var _arm_v: float = 0.0
var _curl: float = 0.0         # the bucket's tilt in the body's frame
var _curl_v: float = 0.0
var _cycle: float = 0.0
var _was_working: bool = false
var _head_yaw: float = 0.0
var _head_yaw_v: float = 0.0
var _head_pitch: float = 0.0
var _head_pitch_v: float = 0.0
var _glance: float = 0.0
var _glance_t: float = 2.0
var _whip: float = 0.0
var _whip_v: float = 0.0
var _load: int = 0
var _load_seen: int = -1
var _clamp: float = CLAMP_OPEN
var _clamp_v: float = 0.0
var _clamp_kick: float = 0.0
var _bump_t: float = 0.0
var _lod_t: float = 0.0
var _is_far: bool = false
var _dumped: bool = false


static func _load_wparts() -> void:
	if not _wparts.is_empty():
		return
	var inst: Node = (load(WORKERS_PATH) as PackedScene).instantiate()
	for n: Node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		_wparts[str(mi.name)] = mi.mesh
	inst.free()
	# Fixed lamps (headlights, tail lights): their colour is in the vertex colours.
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lamp_mat.vertex_color_use_as_albedo = true
	_visor_mat = Mats.glass(Color(0.015, 0.02, 0.028, 1.0), 0.07)
	_visor_mat.clearcoat_enabled = true
	_visor_mat.clearcoat = 0.8
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(0, 0, 0, 1))
	g.add_point(0.4, Color(0.3, 0.3, 0.3, 1))
	_glow_tex = GradientTexture2D.new()
	_glow_tex.gradient = g
	_glow_tex.fill = GradientTexture2D.FILL_RADIAL
	_glow_tex.fill_from = Vector2(0.5, 0.5)
	_glow_tex.fill_to = Vector2(1.0, 0.5)
	_glow_tex.width = 64
	_glow_tex.height = 64


## Triangles and draws of a worker body near and far (tests and the art report).
static func worker_cost(base_type: String, p_look: String) -> Dictionary:
	var v := RobotVisual.new()
	v.build(base_type, p_look)
	var near: int = 0
	var draws: int = 1  # the ground glow
	for mi: MeshInstance3D in v._near:
		for s: int in mi.mesh.get_surface_count():
			near += mi.mesh.surface_get_array_index_len(s) / 3
		draws += mi.mesh.get_surface_count()
	var far: int = v._far.mesh.surface_get_array_index_len(0) / 3
	v.free()
	return {"near": near, "far": far, "near_draws": draws, "far_draws": 2}


func _hero(c: Color, seed_: float, lk: Dictionary, metal: float = 0.0, rough: float = 0.4, cover_add: float = 0.0) -> ShaderMaterial:
	var m: ShaderMaterial = Mats.worn_paint(c, clampf(float(lk["cover"]) + cover_add, 0.0, 1.0), float(lk["rust"]), _seed + seed_, float(lk["grime"]))
	m.shader = HERO_PAINT
	m.set_shader_parameter("clearcoat", float(lk["coat"]) if metal < 0.5 else 0.0)
	m.set_shader_parameter("paint_roughness", rough)
	m.set_shader_parameter("paint_metallic", metal)
	m.set_shader_parameter("dust", float(lk["dust"]))
	m.set_shader_parameter("specks", float(lk["specks"]))
	m.set_shader_parameter("edge_wear", float(lk["edge"]))
	m.set_shader_parameter("metallic_bare", 0.3)
	m.set_shader_parameter("rim_strength", 0.06)
	m.set_shader_parameter("fade", 0.3 if look == "salvage" else 0.05)
	m.set_shader_parameter("sun_dir", _sun_dir)
	_paint_mats.append(m)
	return m


## A glb part as a MeshInstance3D under `parent`, at `pos`, with this robot's materials on its
## surfaces (by surface material name).
func _wpart(parent: Node3D, part: String, pos: Vector3 = Vector3.ZERO, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _wparts[part]
	mi.position = pos
	for i: int in mi.mesh.get_surface_count():
		var src: Material = mi.mesh.surface_get_material(i)
		var key: String = src.resource_name if src else ""
		if _mats.has(key):
			mi.set_surface_override_material(i, _mats[key])
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = FAR_M
	mi.visibility_range_end_margin = 3.0
	parent.add_child(mi)
	_near.append(mi)
	return mi


func _build_worker(base_type: String) -> void:
	_load_wparts()
	_worker = true
	var pre: String = "sc_" if base_type == "scoopie" else "hb_"
	var a: Dictionary = SC if base_type == "scoopie" else HB
	var lk: Dictionary = WORKER_LOOKS[look]
	var cols: Array = WORKER_PAINT[base_type][look]
	var glow: Color = lk["glow"]
	var lit: bool = look in ["modern", "hover"]
	_eye_mat = _glow(glow, 3.2 if look != "salvage" else 2.2)
	_ring_mat = _glow(glow, float(lk["ring"]))
	_beacon_mat = Mats.lamp(AMBER, 1.5)
	_status_mat = Mats.lamp(glow, 1.0)
	_mats = {
		"paint": _hero(cols[0], 3.0, lk, 0.0, 0.36),
		"accent": _hero(cols[1], 11.0, lk, 0.0, 0.38, -0.04),
		"bucket": _hero(cols[1], 17.0, lk, 0.1, 0.4, -0.14),
		"trim": _hero(Color(0.16, 0.17, 0.19), 7.0, lk, 0.35, 0.42, 0.05),
		"dark": _hero(Color(0.1, 0.105, 0.115), 5.0, lk, 0.85, 0.3, 0.1),
		"steel": Mats.metal("steel"),
		"tyre": Mats.rubber(),
		"glass": _visor_mat,
		"lamp": _lamp_mat,
		"glow": _glow(glow, 2.6),
		"eye": _eye_mat,
	}
	(_mats["bucket"] as ShaderMaterial).set_shader_parameter("edge_wear", 1.0)
	# Unsprung: axles and wheels (hover pods hang on the body instead). The body rides above.
	_base = _node(self, Vector3.ZERO)
	move_child(_base, 0)
	if not hover:
		_wpart(_base, pre + "base")
		for p: Vector3 in a["wheels"]:
			var w := _node(_base, p)
			w.set_meta("r", float(a["wheel_r"]))
			_wpart(w, pre + "tyre")
			if lit:
				_wpart(w, pre + "hub_glow", Vector3.ZERO, false)
			_wheels.append(w)
	else:
		for p: Vector3 in a["pods"]:
			var pod := _node(_body, p)
			_wpart(pod, pre + "pod")
			_wpart(pod, pre + "pod_glow", Vector3.ZERO, false)
			_pods.append(pod)
	_wpart(_body, pre + "body")
	_wpart(_body, pre + "lamps", Vector3.ZERO, false)
	if lit:
		_wpart(_body, pre + "body_glow", Vector3.ZERO, false)
	if look == "salvage":
		# The patch plate and the loose cable come off another machine: its paint.
		var own: Material = _mats["accent"]
		_mats["accent"] = _hero(Color(0.3, 0.5, 0.5), 23.0, lk, 0.0, 0.5, -0.1)
		_wpart(_body, pre + "patch")
		_wpart(_body, pre + "guts", Vector3.ZERO, false)
		_mats["accent"] = own
	_wpart(_body, pre + "ring", Vector3.ZERO, false).set_surface_override_material(0, _ring_mat)
	_wpart(_body, pre + "status", Vector3.ZERO, false).set_surface_override_material(0, _status_mat)
	# Head: glances on its neck; the eyes blink in their own node.
	_head = _node(_body, a["head"])
	_wpart(_head, pre + "head")
	if look != "salvage":
		_wpart(_head, pre + "head_glow", Vector3.ZERO, false)
	_eye = _node(_head, (a["eyes"] as Vector3) - (a["head"] as Vector3))
	_wpart(_eye, pre + "eyes", Vector3.ZERO, false)
	if base_type == "scoopie":
		_antenna = _node(_head, (a["antenna"] as Vector3) - (a["head"] as Vector3))
		_wpart(_antenna, pre + "antenna", Vector3.ZERO, false)
		_wpart(_antenna, pre + "beacon", Vector3.ZERO, false).set_surface_override_material(0, _beacon_mat)
		_arm = _node(_body, a["boom"])
		_wpart(_arm, pre + "boom")
		_bucket = _node(_arm, (a["bucket"] as Vector3) - (a["boom"] as Vector3))
		_wpart(_bucket, pre + "bucket")
		for s: float in [-1.0, 1.0]:
			var foot: Vector3 = (a["ram_foot"] as Vector3) * Vector3(s, 1, 1)
			var ear: Vector3 = ((a["ram_ear"] as Vector3) - (a["boom"] as Vector3)) * Vector3(s, 1, 1)
			var barrel := _node(_body, foot)
			_wpart(barrel, pre + "ram_cyl", Vector3.ZERO, false)
			var rod := _node(_body, foot)
			_wpart(rod, pre + "ram_rod", Vector3.ZERO, false)
			_rams.append([barrel, rod, foot, ear])
		hopper_point = Vector3(0, 0.66, 0.12)
		back_point = Vector3(0, 0.62, 0.62)
		emitter_point = Vector3(0, 0.1, -0.74)
		nozzle_point = Vector3(0, 0.5, -0.5)
		fork_point = Vector3(0, 0.12, -0.72)
		_aim_rams()
	else:
		for s: float in [-1.0, 1.0]:
			var f := _node(_head, ((a["feeler"] as Vector3) - (a["head"] as Vector3)) * Vector3(s, 1, 1))
			f.scale.x = s
			_wpart(f, pre + "feeler", Vector3.ZERO, false)
			if s > 0.0:
				_wpart(f, pre + "beacon", Vector3.ZERO, false).set_surface_override_material(0, _beacon_mat)
			_feelers.append(f)
		_arm = _node(_body, a["fork"])
		_wpart(_arm, pre + "fork")
		for s: float in [-1.0, 1.0]:
			var c := _node(_body, (a["hinge"] as Vector3) * Vector3(s, 1, 1))
			_wpart(c, pre + ("clamp_r" if s > 0.0 else "clamp_l"))
			c.set_meta("side", s)
			c.rotation.z = CLAMP_OPEN * s
			_clamps.append(c)
		_meter = _node(_body, a["meter"])
		_wpart(_meter, pre + "meter", Vector3.ZERO, false).set_surface_override_material(0, _status_mat)
		_meter.scale.x = 0.001
		_meter.visible = false
		_bed_at = a["bed"]
		# SphereBales stacks the bales 0.12 m above the hopper point: on the deck.
		hopper_point = _bed_at - Vector3(0, 0.12, 0)
		fork_point = Vector3(0, 0.125, -0.8)
		emitter_point = Vector3(0, 0.45, -0.62)
	# One cheap mesh for the far view.
	_far = MeshInstance3D.new()
	_far.mesh = _wparts[pre + "far"]
	_far_mat = ShaderMaterial.new()
	_far_mat.shader = WORKER_FAR
	_far_mat.set_shader_parameter("paint", cols[0])
	_far_mat.set_shader_parameter("accent", cols[1])
	_far_mat.set_shader_parameter("glow", glow)
	_far.material_override = _far_mat
	_far.visibility_range_begin = FAR_M
	_far.visibility_range_begin_margin = 3.0
	add_child(_far)
	# The ring's light on the ground (the owner's world target: a robot's glow on the ground under it).
	_ground = MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(2.3, 2.6) if base_type == "haulbug" else Vector2(2.1, 2.3)
	_ground.mesh = q
	_ground_mat = StandardMaterial3D.new()
	_ground_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ground_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ground_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ground_mat.albedo_texture = _glow_tex
	_ground_mat.disable_receive_shadows = true
	_ground.material_override = _ground_mat
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ground.position = Vector3(0, 0.035, 0.05)
	add_child(_ground)
	_glance_t = randf_range(0.5, 3.0)
	_tint_ground()


## Bales on the Haul Bug's bed. The globe's crew hangs them as a "Cargo" node next to the visual,
## which animate() counts; previews and tests call this.
func set_load(n: int) -> void:
	_load = maxi(n, 0)


## The rams between the tub and the booms: each barrel looks at its boom ear, each rod back.
func _aim_rams() -> void:
	if _arm == null:
		return
	for r: Array in _rams:
		var foot: Vector3 = r[2]
		var ear: Vector3 = _arm.transform * (r[3] as Vector3)
		var d: Vector3 = ear - foot
		if d.length_squared() < 0.0001:
			continue
		(r[0] as Node3D).transform = Transform3D(Basis.looking_at(d, Vector3.UP), foot)
		(r[1] as Node3D).transform = Transform3D(Basis.looking_at(-d, Vector3.UP), ear)


func _tint_ground() -> void:
	if _ring_mat == null or _ground_mat == null:
		return
	var c: Color = _ring_mat.emission
	var k: float = float(_ring_mat.get_meta("base")) * (0.34 if hover else 0.26)
	_ground_mat.albedo_color = Color(c.r * k, c.g * k, c.b * k, 1.0)
	if _far_mat != null:
		_far_mat.set_shader_parameter("glow", c)


## A few times a second: near or far, the glow on the ground (the Locker can recolour the lights),
## the sun for the paint's rim.
func _slow_tick() -> void:
	_tint_ground()
	if not is_inside_tree():
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	_is_far = cam != null and cam.global_position.distance_squared_to(global_position) > (FAR_M + 2.0) * (FAR_M + 2.0)
	var f: int = Engine.get_process_frames()
	if f - _sun_frame > 240:
		_sun_frame = f
		for n: Node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
			var sun: DirectionalLight3D = n
			if sun.visible and sun.light_energy > 0.05:
				_sun_dir = sun.global_transform.basis.z.normalized()
				break
	for m: ShaderMaterial in _paint_mats:
		m.set_shader_parameter("sun_dir", _sun_dir)


## Scoop cycle: [until phase, boom angle, bucket tilt (body frame), body pitch]. Dip and tip the
## lip down (anticipation), crowd in and curl, throw the booms over the head, flick the bucket
## into the hopper, hang a beat, come back down.
const SCOOP_KEYS: Array = [
	[0.1, -0.07, -0.3, 0.035],
	[0.3, -0.03, 0.55, -0.05],
	[0.56, 2.12, 0.75, 0.03],
	[0.7, 2.12, 2.75, 0.05],
	[0.78, 2.0, 2.5, 0.0],
	[1.0, 0.0, 0.1, 0.0],
]
const SCOOP_S: float = 2.7


func _animate_worker(speed: float, working: bool, delta: float) -> void:
	var dt: float = minf(delta, 0.05)
	for w: Node3D in _wheels:
		w.rotation.x -= speed * delta / float(w.get_meta("r", 0.12))
	# Level of detail: far away the single mesh shows and the springs rest.
	_lod_t -= delta
	if _lod_t <= 0.0:
		_lod_t = 0.4 + fmod(_seed, 0.2)
		_slow_tick()
	if _is_far:
		_spd_prev = speed
		return
	# What the body feels: acceleration along its way and its turn rate.
	_acc = lerpf(_acc, clampf((speed - _spd_prev) / maxf(delta, 0.001), -8.0, 8.0), clampf(delta * 9.0, 0.0, 1.0))
	_spd_prev = speed
	if is_inside_tree():
		var f: Vector3 = -global_basis.z
		var rate: float = 0.0
		if _fwd_prev != Vector3.ZERO and delta > 0.0001:
			rate = clampf(_fwd_prev.signed_angle_to(f, global_basis.y.normalized()) / delta, -5.0, 5.0)
		_fwd_prev = f
		_turn = lerpf(_turn, rate, clampf(delta * 7.0, 0.0, 1.0))
	# The Haul Bug's load: the crew's Cargo node (two meshes a bale) sits on the bed and rides the body.
	var cargo: Node3D = null
	if not _clamps.is_empty():
		var par: Node = get_parent()
		cargo = par.get_node_or_null("Cargo") as Node3D if par != null else null
		if cargo != null and cargo.is_queued_for_deletion():
			cargo = null
		if cargo != null:
			_load = cargo.get_child_count() / 2
		elif par is SphereBot:
			_load = 0
		if _load != _load_seen:
			if _load_seen >= 0:
				# A bale lands: the bed drops under it and bounces; taken off, it springs up. The
				# clamps let go for a moment either way.
				_sq_v += -0.55 if _load > _load_seen else 0.4
				_pitch_v += -0.5 if _load > _load_seen else 0.3
				_clamp_kick = 0.5
			_load_seen = _load
	var heavy: float = 1.0 + 0.2 * minf(float(_load), 8.0)
	var sag: float = -0.0065 * minf(float(_load), 8.0)
	# Road: small knocks through the suspension while it rolls (the worn Mk I rattles more).
	_bump_t -= delta * minf(speed, 3.5)
	if _bump_t <= 0.0 and speed > 0.2 and not hover:
		_bump_t = randf_range(0.5, 1.4)
		var k: float = 1.5 if look == "salvage" else 1.0
		_sq_v += randf_range(-0.16, 0.1) * k / heavy
		_roll_v += randf_range(-0.35, 0.35) * k / heavy
	# Targets for the tool.
	var arm_to: float = 0.0
	var curl_to: float = 0.06
	var lunge: float = 0.0
	if _bucket != null:
		if working:
			if not _was_working:
				_cycle = 0.0
			_cycle = fmod(_cycle + delta / SCOOP_S, 1.0)
			var from: Array = [0.0, 0.0, 0.1, 0.0]
			for key: Array in SCOOP_KEYS:
				if _cycle <= float(key[0]):
					var u: float = smoothstep(0.0, 1.0, (_cycle - float(from[0])) / maxf(float(key[0]) - float(from[0]), 0.001))
					arm_to = lerpf(float(from[1]), float(key[1]), u)
					curl_to = lerpf(float(from[2]), float(key[2]), u)
					lunge = lerpf(float(from[3]), float(key[3]), u)
					break
				from = key
			# The load leaves the bucket: the body rocks back and the suspension takes it.
			if _cycle > 0.62 and not _dumped:
				_dumped = true
				_sq_v -= 0.3
				_pitch_v += 0.6
			elif _cycle < 0.3:
				_dumped = false
		else:
			_cycle = 0.0
			_dumped = false
			# Under way the bucket is carried a hand off the ground, tipped back.
			var carry: float = clampf(speed * 0.6, 0.0, 1.0)
			arm_to = lerpf(0.0, 0.16, carry) + sin(_t * 0.8 + _seed) * 0.008
			curl_to = lerpf(0.06, 0.42, carry)
	elif _arm != null:
		# Haul Bug: the fork rides a little up under way and works up and down when it loads.
		arm_to = (0.045 + 0.04 * sin(_t * 3.0)) if working else (0.03 if speed > 0.3 else 0.0)
	_was_working = working
	# Springs. Suspension (softer and slower under load), pitch from acceleration, roll from turns.
	_sq_v += (-(170.0 / heavy) * (_sq - sag) - (10.0 / sqrt(heavy)) * _sq_v) * dt
	_sq = clampf(_sq + _sq_v * dt, -0.09, 0.05)
	var pitch_to: float = clampf(_acc * 0.013, -0.085, 0.085) + lunge
	_pitch_v += ((pitch_to - _pitch) * 95.0 - _pitch_v * 7.5) * dt
	_pitch = clampf(_pitch + _pitch_v * dt, -0.16, 0.16)
	var roll_to: float = clampf(-_turn * speed * 0.016, -0.07, 0.07)
	_roll_v += ((roll_to - _roll) * 85.0 - _roll_v * 8.0) * dt
	_roll = clampf(_roll + _roll_v * dt, -0.12, 0.12)
	var idle_yaw: float = 0.0
	if idle:
		_idle_t += delta
		idle_yaw = sin(_idle_t * 0.9 + _seed) * 0.1
	else:
		_idle_t = 0.0
	var bob: float = sin(_t * 2.2 + _seed) * 0.03 if hover else 0.0
	_body.position = Vector3(0, _sq + bob, -lunge * 0.5)
	_body.rotation = Vector3(_pitch - (clampf(speed * 0.03, 0.0, 0.08) if hover else 0.0),
		lerp_angle(_body.rotation.y, idle_yaw, clampf(delta * 4.0, 0.0, 1.0)),
		_roll + (sin(_t * 1.3 + _seed) * 0.02 if hover else 0.0))
	if cargo != null:
		cargo.transform = transform * _body.transform * Transform3D(Basis.IDENTITY, _bed_at + Vector3(0, 0.005, 0))
	# Booms and bucket: springs chase the keys, so the throw overshoots and the bucket follows through.
	if _bucket != null:
		_arm_v += ((arm_to - _arm_a) * 130.0 - _arm_v * 13.0) * dt
		_arm_a = clampf(_arm_a + _arm_v * dt, -0.14, 2.3)
		_curl_v += ((curl_to - _curl) * 210.0 - _curl_v * 14.0 - _arm_v * 3.0) * dt
		_curl = clampf(_curl + _curl_v * dt, -0.6, 3.1)
		_arm.rotation.x = _arm_a
		# Up to the top the bucket is held level against the boom's swing; then it tips over.
		_bucket.rotation.x = clampf(_curl - _arm_a, -1.7, 1.0)
		_aim_rams()
	elif _arm != null:
		_arm_v += ((arm_to - _arm_a) * 120.0 - _arm_v * 11.0) * dt
		_arm_a = clampf(_arm_a + _arm_v * dt, -0.02, 0.16)
		_arm.position.y = float((HB["fork"] as Vector3).y) + _arm_a
	# Clamps: open wide when empty, shut on a load; they let go and take hold again when it changes.
	if not _clamps.is_empty():
		_clamp_kick = maxf(0.0, _clamp_kick - delta)
		var c_to: float = CLAMP_OPEN if _load <= 0 else (CLAMP_OPEN * 0.6 if _clamp_kick > 0.2 else CLAMP_SHUT)
		_clamp_v += ((c_to - _clamp) * 140.0 - _clamp_v * 11.0) * dt
		_clamp = clampf(_clamp + _clamp_v * dt, -0.8, 0.22)
		for c: Node3D in _clamps:
			c.rotation.z = _clamp * float(c.get_meta("side", 1.0))
		if _meter != null:
			var want: float = clampf(float(_load) / float(HAUL_FULL), 0.0, 1.0)
			_meter.visible = want > 0.0
			_meter.scale.x = lerpf(_meter.scale.x, maxf(want, 0.001), clampf(delta * 6.0, 0.0, 1.0))
	# Head: watches the work (down at the dig, up after the throw), leads a turn, glances about.
	if _head != null:
		_glance_t -= delta
		if _glance_t <= 0.0:
			var still: bool = speed < 0.15 and not working
			_glance = 0.0 if (_glance != 0.0 or not still) else randf_range(0.3, 0.75) * (1.0 if randf() < 0.5 else -1.0)
			_glance_t = randf_range(0.7, 1.8) if _glance != 0.0 else randf_range(2.2, 5.5)
		if speed > 0.15 or working:
			_glance = 0.0
		var yaw_to: float = _glance + clampf(_turn * 0.16, -0.4, 0.4)
		var pit_to: float = -_pitch * 0.9 - _sq * 2.0
		if working and _bucket != null:
			pit_to += lerpf(-0.42, 0.3, smoothstep(0.3, 1.6, _arm_a))
		elif working:
			pit_to -= 0.2
		_head_yaw_v += ((yaw_to - _head_yaw) * 75.0 - _head_yaw_v * 10.5) * dt
		_head_yaw = clampf(_head_yaw + _head_yaw_v * dt, -1.0, 1.0)
		_head_pitch_v += ((pit_to - _head_pitch) * 60.0 - _head_pitch_v * 8.0) * dt
		_head_pitch = clampf(_head_pitch + _head_pitch_v * dt, -0.6, 0.5)
		_head.rotation = Vector3(_head_pitch, _head_yaw, -_roll * 0.6)
	# Antenna and feelers whip against the motion.
	_whip_v += ((-_acc * 0.035 - _sq_v * 0.5 - _whip) * 90.0 - _whip_v * 4.5) * dt
	_whip = clampf(_whip + _whip_v * dt, -0.6, 0.6)
	if _antenna != null:
		_antenna.rotation = Vector3(_whip + cos(_t * 5.3) * 0.02, 0, _roll * 2.0 + sin(_t * 7.0) * 0.02 * minf(speed, 1.5))
	for i: int in _feelers.size():
		_feelers[i].rotation = Vector3(_whip * 0.9 + sin(_t * 1.7 + i * 1.3 + _seed) * 0.05, 0, (_roll * 2.0 + sin(_t * 1.1 + i * 2.0) * 0.04) * _feelers[i].scale.x)
	# Lights: eyes blink and brighten at work; the ring breathes; the status light tells the job.
	if _eye != null and _eye_mat != null:
		var cyc: float = fmod(_t + _blink_phase, 4.2)
		var blink: bool = cyc < 0.12 or (cyc > 0.3 and cyc < 0.4 and int(_blink_phase * 10.0) % 2 == 0)
		_eye.scale.y = lerpf(_eye.scale.y, 0.1 if blink else 1.0, clampf(delta * 30.0, 0.0, 1.0))
		var e: float = float(_eye_mat.get_meta("base"))
		var sputter: bool = look == "salvage" and fmod(_t * 1.7 + _blink_phase, 5.0) < 0.3 and sin(_t * 60.0) > 0.0
		_eye_mat.emission_energy_multiplier = e * (0.3 if sputter else (1.2 if working else 1.0))
	var pulse: float = 0.88 + 0.12 * sin(_t * 2.6 + _seed)
	for m: StandardMaterial3D in _glow_mats:
		if m != _eye_mat:
			m.emission_energy_multiplier = float(m.get_meta("base")) * pulse * (1.25 if working and m == _ring_mat else 1.0)
	if _status_mat != null:
		# Working: a quick amber beat. Rolling or loaded: steady. Parked: a slow breath.
		if working:
			_status_mat.emission = AMBER
			_status_mat.emission_energy_multiplier = 0.6 + 2.4 * (1.0 if fmod(_t, 0.5) < 0.25 else 0.0)
		else:
			_status_mat.emission = _ring_mat.emission
			_status_mat.emission_energy_multiplier = 1.8 if speed > 0.15 or _load > 0 else 0.9 + 0.5 * sin(_t * 1.4 + _seed)
	if _beacon_mat != null:
		_beacon_mat.emission_energy_multiplier = 0.8 + (2.4 if fmod(_t + _seed, 1.4) < 0.15 else 0.0)
	if _beam and _beam.visible:
		_beam_core_mat.albedo_color.a = 0.3 + 0.1 * sin(_t * 40.0)


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


func _thruster(parent: Node3D, pos: Vector3, r: float, shell: Material) -> void:
	_mi(parent, ProcMesh.cyl(r * 0.75, r, r * 0.9, 18), shell, pos)
	_mi(parent, ProcMesh.cyl(r * 0.7, r * 0.7, 0.012, 18), _glow(MINT, 4.0), pos - Vector3(0, r * 0.46, 0))
	var flame := _mi(parent, ProcMesh.cyl(r * 0.65, 0.01, r * 3.0, 14), _additive(Color(0.25, 0.9, 0.8, 0.35)), pos - Vector3(0, r * 0.46 + r * 1.5, 0))
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.set_meta("base_y", flame.position.y)
	flame.set_meta("h", r * 3.0)
	_flames.append(flame)


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
	var len_: float = maxf(a.distance_to(b), 0.05)
	_beam.visible = true
	var up: Vector3 = (a - b).normalized()
	var side: Vector3 = up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var w: float = 1.0 if hover else 0.45  # Mk III: a slim beam from the arm emitter
	_beam.global_transform = Transform3D(Basis(side * w, up * len_, side.cross(up) * w), (a + b) * 0.5)
	_beam_mat.set_shader_parameter("beam_length", len_)


## The job kits' moving bits on any body: the waterer's level gauge.
func _animate_kit_bits(delta: float) -> void:
	if _fill_node:
		var s0: Vector3 = _fill_node.get_meta("s0", Vector3.ONE)
		var k: float = maxf(_fill, 0.03)
		if str(_fill_node.get_meta("axis", "y")) == "x":
			_fill_node.scale.x = lerpf(_fill_node.scale.x, s0.x * k, clampf(delta * 4.0, 0.0, 1.0))
		else:
			_fill_node.scale.y = lerpf(_fill_node.scale.y, s0.y * k, clampf(delta * 4.0, 0.0, 1.0))


# --- Idle life -------------------------------------------------------------------------

func animate(speed: float, working: bool, delta: float) -> void:
	_t += delta
	if _worker and _body != null:
		_animate_worker(speed, working, delta)
		_animate_kit_bits(delta)
		return
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
	_animate_kit_bits(delta)
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
		_arm.rotation.x = (sin(_t * 9.0) * 0.4 - 0.2) if working else lerpf(_arm.rotation.x, sin(_t * 0.8) * 0.03, clampf(delta * 4.0, 0.0, 1.0))  # [v7play] unclamped, a long frame (delta > 0.5 s) overshot and diverged to NaN
	if _field_mat:
		_field_mat.albedo_color.a = 0.07 + 0.03 * sin(_t * 4.0) + (0.05 if working else 0.0)
	if _beam and _beam.visible:
		_beam_core_mat.albedo_color.a = 0.3 + 0.1 * sin(_t * 40.0)
	if _beacon_mat:
		_beacon_mat.emission_energy_multiplier = 1.0 + (2.0 if fmod(_t, 1.4) < 0.15 else 0.0)
