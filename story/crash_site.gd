class_name CrashSite
extends Node3D
## [intro2] Where Lumi's escape pod came down, beside the start: a shallow scorched furrow ploughed
## in from the direction it fell, a ring of thrown-up dirt, the pod sunk in and leaning back, a thin
## smoke plume, and damaged panels that flicker and spit sparks.
## It mends as Lumi does: the repair stage follows the upgrades bought (no extra save state).
##   stage 0 (no upgrades yet)   smoking, sparking, a hanging panel, glitching seams, worn paint
##   stage 1 (first upgrade)     sparks stop, the panel is bolted back, a faint wisp of smoke
##   stage 2 (REPAIR_LEVELS)     repaired: clean paint, steady cyan seams, beacon blinking calmly
## Cheap: one CPUParticles3D (smoke), pooled Vfx sparks, a couple of lights. Works in Compatibility.

const LEAN := Vector3(0.2, 0.0, 0.11)  # back and to the side (radians)
const SINK: float = 0.14
## Total upgrade levels for the full repair.
const REPAIR_LEVELS: int = 4
## The direction the pod came in from (the intro's chase starts at land + (-120, 95, 80)).
const FROM_DIR := Vector3(-120, 0, 80)

var pod: Node3D
var stage: int = -1
var _smoke: CPUParticles3D
var _panel: Node3D
var _wires: OmniLight3D
var _wire_node: Node3D
var _wire_mat: StandardMaterial3D
var _seam: StandardMaterial3D
var _beacon: StandardMaterial3D
var _spark_t: float = 1.0
var _glitch_t: float = 0.0
var _t: float = 0.0


## Puts a pod (new or the intro's) into its crash pose at ground point `at`, yaw `yaw`.
static func attach(parent: Node, the_pod: Node3D, at: Vector3, yaw: float) -> CrashSite:
	var site := CrashSite.new()
	site.name = "CrashSite"
	parent.add_child(site)
	site.global_position = at
	if the_pod.get_parent():
		the_pod.reparent(site, false)
	else:
		site.add_child(the_pod)
	site.pod = the_pod
	site.setup(yaw)
	return site


func setup(yaw: float) -> void:
	pod.position = Vector3(0, -SINK, 0)
	pod.rotation_order = EULER_ORDER_YXZ
	pod.rotation = Vector3(LEAN.x, yaw, LEAN.z)
	var scorch: Node3D = pod.get_node_or_null("Scorch")
	if scorch:
		scorch.visible = false
	_build_ground()
	_build_damage()
	set_stage(stage_for_upgrades())
	if not EventBus.upgrade_bought.is_connected(_on_upgrade):
		EventBus.upgrade_bought.connect(_on_upgrade)


## 0 damaged, 1 patched, 2 repaired: from the total upgrade levels bought.
static func stage_for_upgrades() -> int:
	var total: int = 0
	for k: String in GameState.upgrades:
		total += int(GameState.upgrades[k])
	return 0 if total <= 0 else (1 if total < REPAIR_LEVELS else 2)


func _on_upgrade(_id: String, _lvl: int) -> void:
	var s: int = stage_for_upgrades()
	if s > stage:
		set_stage(s)
		# A little repair moment.
		Vfx.burst("sparkle", pod.global_transform * Vector3(0, 1.3, 0), Color(0.4, 0.95, 1.0), 0.8)
		if is_inside_tree() and Audio.has_sound("chime"):
			Audio.play("chime", 1.3, -16.0)


func set_stage(s: int) -> void:
	stage = clampi(s, 0, 2)
	_smoke.emitting = stage < 2
	_smoke.color = Color(0.42, 0.4, 0.38, 0.45 if stage == 0 else 0.18)
	_panel.rotation = Vector3(-0.8, 0.0, 0.18) if stage == 0 else Vector3.ZERO
	_wires.visible = stage == 0
	_wire_node.visible = stage == 0
	EscapePod.set_wear(pod, EscapePod.PEARL, 0.45 if stage == 0 else (0.25 if stage == 1 else 0.0))
	_seam.emission_energy_multiplier = 1.5
	_seam.emission = EscapePod.CYAN


# --- Ground ------------------------------------------------------------------------------

func _build_ground() -> void:
	var back: Vector3 = Vector3(FROM_DIR.x, 0, FROM_DIR.z).normalized()
	var ang: float = atan2(back.x, back.z)
	# The furrow: two soft dark smears stretched back along the approach.
	for layer: Array in [[Vector2(2.6, 7.5), 0.55, 0.018, 2.4], [Vector2(1.4, 4.6), 0.7, 0.024, 1.6]]:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = layer[0]
		mi.mesh = pm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.06, 0.05, 0.045, float(layer[1]))
		m.albedo_texture = EscapePod._soft_tex()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 1.0
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.rotation.y = ang
		mi.position = back * float(layer[3]) + Vector3(0, float(layer[2]), 0)
		add_child(mi)
	# Thrown-up earth: low clods along the furrow's lips and in a bank in front of the pod.
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = Color(0.3, 0.24, 0.18)
	dirt.roughness = 1.0
	var burnt := StandardMaterial3D.new()
	burnt.albedo_color = Color(0.11, 0.09, 0.08)
	burnt.roughness = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var side: Vector3 = back.cross(Vector3.UP).normalized()
	for i: int in 22:
		var along: float = rng.randf_range(-1.6, 5.5)
		var lat: float = (1.0 if i % 2 == 0 else -1.0) * rng.randf_range(0.9, 1.4) * (1.0 - clampf(along / 7.0, 0.0, 0.6))
		if along < 0.0:
			lat *= rng.randf_range(0.0, 1.0)  # the bank in front
		var p: Vector3 = back * along + side * lat
		var clod := MeshInstance3D.new()
		clod.mesh = ProcMesh.sphere(rng.randf_range(0.12, 0.3), 7, 4)
		clod.material_override = burnt if rng.randf() < 0.35 else dirt
		clod.scale = Vector3(1.4, rng.randf_range(0.35, 0.6), 1.0)
		clod.rotation.y = rng.randf() * TAU
		clod.position = p + Vector3(0, 0.0, 0)
		add_child(clod)
	# Two hull shards that broke off on impact.
	var shard_m: Material = EscapePod.paint(EscapePod.PANEL, 0.4, 0.5)
	for k: int in 2:
		var sh := MeshInstance3D.new()
		sh.mesh = ProcMesh.box(Vector3(0.36, 0.025, 0.24))
		sh.material_override = shard_m
		sh.position = back * (2.6 + k * 1.7) + side * (0.7 - k * 1.3) + Vector3(0, 0.05, 0)
		sh.rotation = Vector3(0.3, rng.randf() * TAU, 0.2)
		add_child(sh)


# --- Damage -----------------------------------------------------------------------------

func _build_damage() -> void:
	# The cyan seam and beacon materials (shared by the pod's meshes) flicker while damaged.
	var body: MeshInstance3D = pod.get_node("Body")
	for i: int in body.mesh.get_surface_count():
		var m: Material = body.mesh.surface_get_material(i)
		if m is StandardMaterial3D and (m as StandardMaterial3D).emission_enabled and (m as StandardMaterial3D).emission.b > 0.8:
			_seam = m
	if _seam == null:
		_seam = Mats.lamp(EscapePod.CYAN, 1.5)
	var bn: MeshInstance3D = pod.get_node_or_null("Beacon")
	_beacon = bn.material_override as StandardMaterial3D if bn else Mats.lamp(EscapePod.LAMP, 3.0)
	# A hull panel torn loose on the flank facing the start, hanging from its top edge.
	var a: float = EscapePod._ang(3) + PI / EscapePod.SEGS  # the facet left of the door
	var y: float = 1.12
	var r: float = EscapePod._door_r(y)
	var home: Vector3 = EscapePod._pt(a, y, r * cos(PI / EscapePod.SEGS) + 0.012)
	# Oriented onto the facet (+Z = outward); the plate swings out about its top edge (local X).
	var face := Node3D.new()
	face.name = "LoosePanel"
	face.position = home
	face.basis = Basis.looking_at(-Vector3(sin(a), 0, -cos(a)), Vector3.UP)
	pod.add_child(face)
	var swing := Node3D.new()
	face.add_child(swing)
	var plate := MeshInstance3D.new()
	plate.mesh = ProcMesh.box(Vector3(0.36, 0.3, 0.018))
	plate.material_override = EscapePod.paint(EscapePod.PANEL, 0.35, 0.3)
	plate.position = Vector3(0, -0.15, 0.009)
	swing.add_child(plate)
	_panel = swing
	# Exposed wiring behind it: a hot glow that flickers.
	var wires := MeshInstance3D.new()
	wires.name = "Wires"
	wires.mesh = ProcMesh.box(Vector3(0.24, 0.18, 0.01))
	_wire_mat = Mats.lamp(Color(1.0, 0.5, 0.2), 2.0)
	wires.material_override = _wire_mat
	wires.position = Vector3(0, -0.15, 0.006)
	face.add_child(wires)
	_wire_node = wires
	_wires = OmniLight3D.new()
	_wires.light_color = Color(1.0, 0.55, 0.25)
	_wires.light_energy = 0.0
	_wires.omni_range = 1.6
	_wires.position = home + Vector3(sin(a), 0, -cos(a)) * 0.25 + Vector3(0, -0.15, 0)
	pod.add_child(_wires)
	# Smoke: a light plume from the top of the pod, drifting with the breeze.
	_smoke = CPUParticles3D.new()
	_smoke.name = "Smoke"
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.vertex_color_use_as_albedo = true
	sm.albedo_texture = EscapePod._soft_tex()
	sm.disable_receive_shadows = true
	q.material = sm
	_smoke.mesh = q
	_smoke.amount = 14
	_smoke.lifetime = 5.5
	_smoke.preprocess = 5.0
	_smoke.local_coords = false
	_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_smoke.emission_sphere_radius = 0.2
	_smoke.direction = Vector3(0.25, 1, 0.1)
	_smoke.spread = 12.0
	_smoke.gravity = Vector3(0.18, 0.25, 0.05)
	_smoke.initial_velocity_min = 0.35
	_smoke.initial_velocity_max = 0.6
	_smoke.angle_max = 180.0
	_smoke.scale_amount_min = 0.6
	_smoke.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 2.6))
	_smoke.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.add_point(0.15, Color(1, 1, 1, 1.0))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0.0))
	_smoke.color_ramp = ramp
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_smoke.position = home + Vector3(0, 0.2, 0)
	pod.add_child(_smoke)


func _process(delta: float) -> void:
	_t += delta
	# The beacon: a nervous double blink while damaged, a calm slow blink once repaired.
	if _beacon:
		var on: bool = fmod(_t, 0.7) < 0.08 or (fmod(_t, 0.7) > 0.16 and fmod(_t, 0.7) < 0.22) if stage == 0 else fmod(_t, 2.2) < 0.15
		_beacon.emission_energy_multiplier = 3.0 if on else 0.3
	if stage != 0:
		return
	# Glitching seams: mostly steady, with short stutters (on/off, a red tinge).
	_glitch_t -= delta
	if _glitch_t <= 0.0:
		_glitch_t = randf_range(0.05, 0.12) if randf() < 0.55 else randf_range(0.6, 2.2)
		var bad: bool = randf() < 0.5
		_seam.emission_energy_multiplier = randf_range(0.0, 0.4) if bad else 1.5
		_seam.emission = EscapePod.CYAN.lerp(Color(1.0, 0.3, 0.3), 0.6) if bad and randf() < 0.3 else EscapePod.CYAN
	# Wiring flicker and spark bursts from the torn panel.
	var w: float = 0.6 + 0.4 * sin(_t * 37.0) * sin(_t * 13.0)
	_wire_mat.emission_energy_multiplier = 1.0 + 2.5 * maxf(w, 0.0)
	_wires.light_energy = 0.4 + 0.6 * maxf(w, 0.0)
	_spark_t -= delta
	if _spark_t <= 0.0:
		_spark_t = randf_range(1.1, 3.4)
		var at: Vector3 = _wires.global_position
		Vfx.burst("sparkle", at, Color(1.0, 0.62, 0.25), 0.35)
		if randf() < 0.5:
			Vfx.burst("sparkle", at + Vector3(0, -0.1, 0), Color(1.0, 0.85, 0.55), 0.2)
		_wires.light_energy = 2.2
		if is_inside_tree() and randf() < 0.4 and Audio.has_sound("zap"):
			Audio.play("zap", randf_range(1.2, 1.6), -24.0)
