class_name CradleShip
extends Node3D
## [ship] The ark *Cradle*, redesigned in the Seedglider language (owner: "still not our design"):
## the mothership is the big sister of Lumi's glider (automation/ship_model.gd). Modelled in Blender
## (art/models/ship/build_ark.py -> ark.glb + ark_points.json) with the glider's kit:
##   - a faceted manta hull (about 40 m long) with layered pearl and graphite plates, crisp seams,
##     a tangerine nose band and thin cyan chine lines
##   - huge swept wings (about 50 m across) with drooping tip fins, tangerine tips and lit edges
##   - a faceted cyan bridge canopy, and Lumi's C eyes on the nose sensor
##   - the seed vault at its heart: a faceted glass greenhouse dome with the garden glowing inside
##   - a fold ring around the aft hull (like the Mk VI-VII glider), four nacelles and a core engine
##   - a ventral bay (the Homecoming ship docks there) and the keel with the escape-pod rack
## Flies toward -Z. API kept for the intro, the core-charge memories, the Bloom finale and the
## Homecoming: alarm, thrust, ring_speed, dome_world(), pod_world(k), pod_xform(k), release_pod(k),
## CYAN, ALARM, PEARL, TANGERINE; new: wake_points() (flank light spots for the Homecoming).

const MODEL_PATH := "res://art/models/ship/ark.glb"
const POINTS_PATH := "res://art/models/ship/ark_points.json"
const CYAN := Color(0.3, 0.9, 1.0)
const ALARM := Color(1.0, 0.16, 0.1)
const PEARL := Color(0.93, 0.93, 0.91)
const TANGERINE := Color(1.0, 0.5, 0.16)
const POD_Y: float = -7.05
const POD_Z0: float = -8.5
const POD_DZ: float = 2.7
const DOME_AT := Vector3(0, 6.3, -4.5)
const DOME_R: float = 4.4
const DOME_SY: float = 0.82
const RING_Z: float = 9.7
const RING_R: float = 12.5

static var _parts: Dictionary = {}
static var _pts: Dictionary = {}

## 0..1: seams pulse red (meteor storm).
var alarm: float = 0.0
## Engine glow multiplier.
var thrust: float = 1.0
## Kept for callers (the old ring spun); now the speed of the line lights' slow breathing.
var ring_speed: float = 0.12

var _ring: Node3D
var _glow: StandardMaterial3D
var _engine: StandardMaterial3D
var _vault: StandardMaterial3D
var _nav: StandardMaterial3D
var _plume: StandardMaterial3D
var _face: ShaderMaterial
var _pods: Array[Node3D] = []
var _lights: MultiMeshInstance3D
var _light_z: Array[float] = []
var _t: float = 0.0
var _vault_light: OmniLight3D


static func _load() -> void:
	if not _parts.is_empty():
		return
	var scene: PackedScene = load(MODEL_PATH)
	if scene != null:
		var inst: Node = scene.instantiate()
		for n: Node in inst.find_children("*", "MeshInstance3D", true, false):
			_parts[str(n.name)] = (n as MeshInstance3D).mesh
		inst.free()
	_pts = Economy.read_json(POINTS_PATH)


func _ready() -> void:
	_load()
	# The glider's Mk VII finish (glossy pearl, graphite plates, gold fittings), shared materials.
	var sm := ShipModel.new()
	sm.tier = 7
	sm._make_mats()
	var mats: Dictionary = sm._mats.duplicate()
	sm.free()
	_glow = Mats.lamp(CYAN, 2.4)
	_engine = Mats.lamp(Color(0.6, 0.95, 1.0), 6.0)
	_nav = Mats.lamp(Color(1.0, 0.36, 0.12), 4.0)
	# Lighter accent plates than the Mk VII glider: the ark stays mostly pearl.
	(mats["panel"] as ShaderMaterial).set_shader_parameter("paint_color", Color(0.6, 0.62, 0.66))
	mats["glow"] = _glow
	mats["thruster"] = _engine
	mats["lamp"] = _nav
	var vg := StandardMaterial3D.new()
	vg.albedo_color = Color(0.6, 0.9, 0.95, 0.18)
	vg.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vg.roughness = 0.03
	vg.metallic = 0.4
	vg.rim_enabled = true
	vg.rim = 0.9
	vg.rim_tint = 0.3
	mats["vault_glass"] = vg
	for name: String in _parts:
		var mi := MeshInstance3D.new()
		mi.name = name
		mi.mesh = _parts[name]
		for i: int in mi.mesh.get_surface_count():
			var src: Material = mi.mesh.surface_get_material(i)
			var key: String = src.resource_name if src else ""
			if mats.has(key):
				mi.set_surface_override_material(i, mats[key])
		if name == "ark_vault_glass":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		if name == "ark_ring":
			_ring = mi
	_build_garden()
	_build_face()
	_build_engines()
	_build_pods()
	_build_running_lights()


func _add(mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	(parent if parent else self).add_child(mi)
	return mi


## The garden inside the vault: a glowing bed, rounded shrubs and a green light.
func _build_garden() -> void:
	var v: Array = _pts.get("vault", [0.0, 5.1, -4.5, DOME_R])
	var base := Vector3(float(v[0]), float(v[1]), float(v[2]))
	_vault = Mats.lamp(Color(0.45, 0.95, 0.5), 0.9)
	_vault.albedo_color = Color(0.2, 0.5, 0.22)
	_add(ProcMesh.cyl(DOME_R * 0.92, DOME_R * 0.92, 0.12, 32), _vault, base + Vector3(0, 0.05, 0), Vector3.ZERO, Vector3(1, 1, 1.25))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var leaf := Mats.lamp(Color(0.4, 1.0, 0.45), 1.0)
	leaf.albedo_color = Color(0.25, 0.65, 0.25)
	for i: int in 18:
		var a: float = rng.randf() * TAU
		var r: float = rng.randf_range(0.4, DOME_R * 0.72)
		var p := Vector3(cos(a) * r, 0, sin(a) * r * 1.25)
		_add(ProcMesh.sphere(rng.randf_range(0.35, 0.75), 10, 6), leaf, base + p + Vector3(0, 0.4 + 1.1 * (1.0 - r / DOME_R), 0))
	_vault_light = OmniLight3D.new()
	_vault_light.light_color = Color(0.55, 1.0, 0.7)
	_vault_light.light_energy = 2.0
	_vault_light.omni_range = 9.0
	_vault_light.position = base + Vector3(0, 1.8, 0)
	add_child(_vault_light)


## Lumi's C eyes on the nose sensor (the face shader's front is -Z, the ark's nose).
func _build_face() -> void:
	var e: Array = _pts.get("eyes", [0.0, 0.45, -21.39])
	var holder := Node3D.new()
	holder.position = Vector3(float(e[0]), float(e[1]), float(e[2]))
	holder.rotation = Vector3(deg_to_rad(14.0), 0, 0)
	add_child(holder)
	_face = ShaderMaterial.new()
	_face.shader = preload("res://art/shaders/bot_face.gdshader")
	_face.set_shader_parameter("eye_color", CYAN)
	_face.set_shader_parameter("half_width", 1.2)
	_face.set_shader_parameter("half_height", 0.3)
	_face.set_shader_parameter("eye_spacing", 2.0)
	_face.set_shader_parameter("eye_radius", 0.75)
	_face.set_shader_parameter("energy", 3.5)
	var bm := BoxMesh.new()
	bm.size = Vector3(2.4, 0.6, 0.04)
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = _face
	holder.add_child(mi)


## A soft heat glow behind each nozzle (no solid plume: the ark cruises).
func _build_engines() -> void:
	_plume = StandardMaterial3D.new()
	_plume.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_plume.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_plume.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_plume.cull_mode = BaseMaterial3D.CULL_DISABLED
	_plume.albedo_texture = EscapePod._soft_tex()
	_plume.albedo_color = Color(0.45, 0.85, 1.0, 0.1)
	_plume.disable_fog = true
	for nz: Dictionary in _pts.get("nozzles", []):
		var p: Array = nz["pos"]
		var r: float = float(nz["r"])
		var q := QuadMesh.new()
		q.size = Vector2(r * 4.0, r * 4.0)
		var m := _add(q, _plume, Vector3(float(p[0]), float(p[1]), float(p[2]) + 0.3), Vector3(0, PI, 0))
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The escape-pod rack under the keel: six pods (story/escape_pod.gd) hanging in clamps.
## The intro's pod is rack slot 2, released with release_pod(2).
func _build_pods() -> void:
	var dark: StandardMaterial3D = Mats.metal("dark_steel")
	for k: int in 6:
		var holder := Node3D.new()
		holder.position = Vector3(0, POD_Y, POD_Z0 + k * POD_DZ)
		add_child(holder)
		var pod: Node3D = EscapePod.build()
		pod.position = Vector3(0, -EscapePod.PROFILE[-1].y * 0.5, 0)
		pod.rotation.y = PI * 0.5  # doors face the ship's side
		for n: String in ["Scorch", "Spill", "PodLight"]:
			var c: Node = pod.get_node_or_null(n)
			if c:
				c.queue_free()
		holder.add_child(pod)
		_add(ProcMesh.cyl(0.16, 0.22, 0.7, 8), dark, Vector3(0, EscapePod.PROFILE[-1].y * 0.5 + 0.3, 0), Vector3.ZERO, Vector3.ONE, holder)
		_pods.append(holder)


## Thin running lights down the spine and along the flanks, a slow chase toward the tail.
func _build_running_lights() -> void:
	var xs: Array[Vector3] = []
	for key: String in ["spine", "flank"]:
		for p: Array in _pts.get(key, []):
			xs.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = ProcMesh.sphere(0.1, 6, 3)
	mm.instance_count = xs.size()
	for i: int in xs.size():
		mm.set_instance_transform(i, Transform3D(Basis(), xs[i]))
		mm.set_instance_color(i, Color(1, 1, 1))
		_light_z.append(xs[i].z)
	_lights = MultiMeshInstance3D.new()
	_lights.name = "RunningLights"
	_lights.multimesh = mm
	var m := Mats.lamp(Color(0.75, 0.95, 1.0), 3.0)
	m.vertex_color_use_as_albedo = true
	_lights.material_override = m
	_lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lights)


## Spots along the flanks (local) where the Homecoming's waking lights can sit.
func wake_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p: Array in _pts.get("flank", []):
		out.append(Vector3(float(p[0]), float(p[1]) + 0.25, float(p[2])))
	return out


## The seed-vault dome's centre in world space.
func dome_world() -> Vector3:
	return global_transform * (DOME_AT + Vector3(0, 1.2, 0))


## Where the cargo pods hang (k = 0..5) in world space.
func pod_world(k: int = 2) -> Vector3:
	return global_transform * Vector3(0, POD_Y, POD_Z0 + clampi(k, 0, 5) * POD_DZ)


## A rack pod's own transform (the intro swaps in its loose pod exactly there).
func pod_xform(k: int = 2) -> Transform3D:
	var h: Node3D = _pods[clampi(k, 0, _pods.size() - 1)]
	return (h.get_child(0) as Node3D).global_transform


## Hide a rack pod (it has been blown loose); release_pod(k, false) puts it back.
func release_pod(k: int, gone: bool = true) -> void:
	if k >= 0 and k < _pods.size():
		_pods[k].visible = not gone


func _process(delta: float) -> void:
	_t += delta
	var pulse: float = 0.5 + 0.5 * sin(_t * 9.0)
	var a: float = clampf(alarm, 0.0, 1.0)
	_glow.emission = CYAN.lerp(ALARM, a * (0.55 + 0.45 * pulse))
	_glow.emission_energy_multiplier = 2.4 + a * pulse * 3.0 + 0.4 * sin(_t * ring_speed * 20.0)
	_engine.emission_energy_multiplier = 6.0 * thrust + sin(_t * 23.0) * 0.3
	_plume.albedo_color.a = 0.35 * clampf(thrust, 0.0, 1.5) + sin(_t * 31.0) * 0.02
	_vault.emission_energy_multiplier = 0.9 + sin(_t * 1.3) * 0.25
	_vault_light.light_color = Color(0.55, 1.0, 0.7).lerp(ALARM, a * pulse)
	_nav.emission_energy_multiplier = 6.0 if fmod(_t, 1.6) < 0.12 else 1.0
	if _face:
		_face.set_shader_parameter("eye_color", CYAN.lerp(ALARM, a * pulse))
		_face.set_shader_parameter("blink", 1.0 if fmod(_t, 4.3) < 0.12 else 0.0)
	# Running lights: a slow chase toward the tail (red in the storm), updated ten times a second.
	if _lights and fmod(_t, 0.1) < delta:
		var mm: MultiMesh = _lights.multimesh
		var head: float = fmod(_t * 9.0, 38.0) - 20.0
		for i: int in _light_z.size():
			var b: float = 0.35 + 0.65 * clampf(1.0 - absf(_light_z[i] - head) / 3.0, 0.0, 1.0)
			mm.set_instance_color(i, Color(b, b, b).lerp(Color(ALARM.r * b, ALARM.g * b, ALARM.b * b), a))
