class_name LoadingVignette
extends SubViewportContainer
## [pod2] The loading screen's little 3D scene, in the game's own look: a strip of junk-covered
## street (the real junk meshes and ground material) under one warm light, and red Lumi (the Pixel
## design) gliding along it as the bar fills, beaming up each piece of junk as it passes.
## Cheap on purpose: its own tiny World3D, a ground strip, about ten junk meshes, one light, no
## shadows, no sky. Built lazily the first time the loading screen shows (never in headless runs).
## Swap the hero model in make_lumi() when the hero helper's red Lumi lands.

const STRIP: float = 7.0  # metres from the first to the last piece
const JUNK: Array[String] = ["can_rusted", "plastic_bottle_gallon", "trashbag", "cardboard_box_01",
	"old_tyre", "metal_trash_can", "can_rusted", "plastic_bottle_gallon", "trashbag", "cardboard_box_01"]

var progress: float = 0.0

var _vp: SubViewport
var _lumi: Node3D
var _model: Node3D
var _pieces: Array[Dictionary] = []
var _t: float = 0.0
var _hop: float = 0.0


## The hero model for the vignette: the current Lumi in the red Pixel colourway. Swap this for the
## hero helper's red Lumi (wt/hero) once it is in.
static func make_lumi() -> Node3D:
	var m := PatchModel.new()
	m.ready.connect(func() -> void:
		m.set_variant("pixel")
		m.set_happy(1.0), CONNECT_ONE_SHOT)
	return m


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.handle_input_locally = false
	_vp.gui_disable_input = true
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.52)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.15
	env.fog_enabled = true
	env.fog_light_color = Color(0.018, 0.022, 0.032)
	env.fog_density = 0.09
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -35, 0)
	sun.light_color = Color(1.0, 0.8, 0.6)
	sun.light_energy = 1.6
	_vp.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 2.2, 9.5)
	_vp.add_child(cam)
	cam.look_at(Vector3(0, 0.45, 0), Vector3.UP)
	cam.current = true
	# The street strip: the real dry-ground material, fading into the dark at its ends (fog).
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(16, 3.2)
	pm.material = AssetLib.pbr_material("dry_ground_rocks", 4.0)
	ground.mesh = pm
	_vp.add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i: int in JUNK.size():
		var id: String = JUNK[i]
		if not AssetLib.has_model(id):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = AssetLib.model_mesh_lite(id, 900)
		var u: float = (i + 0.5) / JUNK.size()
		var lie: bool = id != "metal_trash_can" and rng.randf() < 0.5
		mi.position = Vector3(-STRIP * 0.5 + STRIP * u, 0.03 if lie else 0.0, rng.randf_range(-0.35, 0.35))
		mi.rotation = Vector3(PI * 0.5 if lie else 0.0, rng.randf() * TAU, 0.0)
		var s: float = 0.7 if id == "metal_trash_can" else 1.0
		mi.scale = Vector3.ONE * s
		_vp.add_child(mi)
		_pieces.append({"node": mi, "u": u, "scale": s, "taken": false, "k": 0.0})
	_lumi = Node3D.new()
	_vp.add_child(_lumi)
	_model = make_lumi()
	_lumi.add_child(_model)
	_lumi.rotation.y = -PI * 0.5  # Lumi faces -Z by default; turn it to travel toward +X
	_lumi.position = Vector3(-STRIP * 0.5 - 0.8, 0.3, 0.55)


## Restart: every piece back on the street (each new load).
func reset() -> void:
	for p: Dictionary in _pieces:
		p["taken"] = false
		p["k"] = 0.0
		var n: Node3D = p["node"]
		n.visible = true
		n.scale = Vector3.ONE * float(p["scale"])
	progress = 0.0


func set_active(on: bool) -> void:
	if _vp:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


func _process(delta: float) -> void:
	if _lumi == null or not is_visible_in_tree():
		return
	_t += delta
	var x: float = -STRIP * 0.5 - 0.8 + (STRIP + 1.0) * progress
	_lumi.position.x = lerpf(_lumi.position.x, x, minf(1.0, delta * 5.0))
	_hop = maxf(0.0, _hop - delta * 3.0)
	_lumi.position.y = 0.3 + sin(_t * 2.6) * 0.04 + sin(_hop * PI) * 0.12
	var pm: PatchModel = _model as PatchModel
	var target: Variant = null
	for p: Dictionary in _pieces:
		var n: Node3D = p["node"]
		var px: float = -STRIP * 0.5 + STRIP * float(p["u"])
		if not p["taken"] and _lumi.position.x > px - 0.9:
			p["taken"] = true
		if p["taken"] and float(p["k"]) < 1.0:
			p["k"] = minf(1.0, float(p["k"]) + delta * 1.6)
			var k: float = float(p["k"])
			target = n.global_position
			# Lifted on the beam, shrinking into the hopper.
			var to: Vector3 = (pm.chest_world() if pm else _lumi.global_position + Vector3(0, 0.5, 0))
			n.global_position = n.global_position.lerp(to, minf(1.0, delta * (1.5 + k * 6.0)))
			n.scale = Vector3.ONE * float(p["scale"]) * (1.0 - k * k)
			if k >= 1.0:
				n.visible = false
				_hop = 1.0
				if pm:
					pm.hopper_pulse(0.8)
	if pm:
		pm.beam_at(target)
		pm.look_toward(target if target != null else _lumi.global_position + Vector3(2, 0.3, 1))
