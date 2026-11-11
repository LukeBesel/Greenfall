class_name CrashSite
extends Node3D
## [intro2] Where Lumi's escape pod came down, beside the start: a shallow scorched furrow ploughed
## in from the direction it fell, a ring of thrown-up dirt, the pod sunk in and leaning back, a thin
## smoke plume, and damaged panels that flicker and spit sparks.
## It mends as Lumi does: the repair stage follows the upgrades bought (no extra save state).
##   stage 0 (no upgrades yet)   smoking, sparking, torn panel and dangling wire, cracked glass,
##                               stuttering seams, heat-tinted sooty paint
##   stage 1 (first upgrade)     sparks stop, bolted patch plates, strobing fin lamps, faint smoke
##   stage 2 (REPAIR_LEVELS)     restored: clean pearl and tangerine, lit fins, hover glow underneath
##   stage 3 (PLANTER_LEVELS)    planter-beacon: seedlings round the skirt and a soft beacon beam
## The pod's own look per stage lives in EscapePod.set_condition() / animate().
## Cheap: one CPUParticles3D (smoke), pooled Vfx sparks, a couple of lights. Works in Compatibility.

const LEAN := Vector3(0.2, 0.0, 0.11)  # back and to the side (radians)
const SINK: float = 0.14
## Total upgrade levels for the full repair.
const REPAIR_LEVELS: int = 4
## Total upgrade levels for the planter-beacon (late game).
const PLANTER_LEVELS: int = 14
## The direction the pod came in from (the intro's chase starts at land + (-120, 95, 80)).
const FROM_DIR := Vector3(-120, 0, 80)

var pod: Node3D
var stage: int = -1
var _smoke: CPUParticles3D
var _beacon: StandardMaterial3D
var _spark_t: float = 1.0
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
	PropBatch.merge(self)  # [orbE] perf: the furrow's clods and shards (static) as one mesh per material
	_build_plume()  # [v2feel] after the merge: the plume's shader works in its own frame
	PodBatch.merge(pod)  # [orbE] perf: the pod's static shell and each repair-stage group, merged per material
	_build_service()  # [v6yard]
	if not EventBus.upgrade_bought.is_connected(_on_upgrade):
		EventBus.upgrade_bought.connect(_on_upgrade)


## 0 damaged, 1 patched, 2 repaired: from the total upgrade levels bought.
static func stage_for_upgrades() -> int:
	var total: int = 0
	for k: String in GameState.upgrades:
		total += int(GameState.upgrades[k])
	if total >= PLANTER_LEVELS:
		return 3
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
	stage = clampi(s, 0, 3)
	_show_service()  # [v6yard]
	_smoke.emitting = stage < 2
	_smoke.color = Color(0.42, 0.4, 0.38, 0.45 if stage == 0 else 0.18)
	EscapePod.set_condition(pod, stage)


# --- [v6yard] The repair stand ------------------------------------------------------------

var _service: Node3D
const SERVICE_AT := Vector3(2.9, 0.0, 1.0)  # site frame: clear of the door ramp and the furrow


## A service cart, its work lamp and three cones by the pod while it is being mended (stages 1-2):
## the pod reads as a thing Lumi is fixing. Model and colours: MachineArt.pod_service,
## data/machine_art.json "pod".
func _build_service() -> void:
	if _service != null or not bool(MachineArt.cfg().get("pod", {}).get("service", true)):
		return
	_service = Node3D.new()
	_service.name = "Service"
	_service.position = SERVICE_AT
	_service.rotation.y = -atan2(SERVICE_AT.z, SERVICE_AT.x) + 0.2  # drawers (-X) toward the pod, a touch askew
	add_child(_service)
	_service.add_child(MachineArt.pod_service().mi(0.2, "Cart"))
	YardArt.solid(_service, MachineArt.POD_SERVICE_SOLID, Vector3(0, 0.5, 0), "CartBody")
	_show_service()


func _show_service() -> void:
	if _service == null:
		return
	var on: bool = stage == 1 or stage == 2
	_service.visible = on
	YardArt.set_powered(_service, on)
	for c: Node in _service.find_children("*", "CollisionShape3D", true, false):
		(c as CollisionShape3D).disabled = not on


# --- Ground ------------------------------------------------------------------------------

func _build_ground() -> void:
	var back: Vector3 = Vector3(FROM_DIR.x, 0, FROM_DIR.z).normalized()
	var ang: float = atan2(back.x, back.z)
	# The furrow: two soft dark smears stretched back along the approach.
	for layer: Array in [[Vector2(2.8, 8.0), 0.8, 0.018, 2.6], [Vector2(1.5, 5.0), 0.92, 0.024, 1.8]]:
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
	var bn: MeshInstance3D = pod.get_node_or_null("Beacon")
	_beacon = bn.material_override as StandardMaterial3D if bn else Mats.lamp(EscapePod.LAMP, 3.0)
	var home: Vector3 = EscapePod.facet_point(4, 1.2, 0.0)
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


## [v2feel] Owner item 38: a very tall smoke column over the pod, home's landmark from far across the
## globe (one cylinder and a shader, art/shaders/smoke_plume.gdshader). In the site's frame: +Y up.
const PLUME_H: float = 320.0


func _build_plume() -> void:
	var cyl := CylinderMesh.new()
	cyl.height = PLUME_H
	cyl.bottom_radius = 1.0
	cyl.top_radius = 22.0
	cyl.radial_segments = 18
	cyl.rings = 16
	cyl.cap_top = false
	cyl.cap_bottom = false
	var mat := ShaderMaterial.new()
	mat.shader = load("res://art/shaders/smoke_plume.gdshader")
	mat.set_shader_parameter("height", PLUME_H)
	cyl.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Plume"
	mi.mesh = cyl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-40, -PLUME_H * 0.5, -40), Vector3(120, PLUME_H, 80))
	mi.position = Vector3(0, PLUME_H * 0.5 + 1.2, 0)
	mi.add_to_group("see_through")  # transparent and faded near the camera: never a view blocker
	add_child(mi)


func _process(delta: float) -> void:
	_t += delta
	EscapePod.animate(pod, _t, delta)
	# The beacon: a nervous double blink while damaged, a calm slow blink once repaired.
	if _beacon:
		var ph: float = fmod(_t, 0.7)
		var on: bool = (ph < 0.08 or (ph > 0.16 and ph < 0.22)) if stage == 0 else fmod(_t, 2.2) < 0.15
		_beacon.emission_energy_multiplier = 3.0 if on else 0.3
	if stage != 0:
		return
	_spark_t -= delta
	if _spark_t <= 0.0:
		_spark_t = randf_range(1.1, 3.4)
		var at: Vector3 = EscapePod.spark(pod)
		Vfx.burst("spark", at, Color(1.0, 0.7, 0.32), 0.8)  # [v7look] was "sparkle" (hard star dots)
		if randf() < 0.5:
			Vfx.burst("spark", at + Vector3(0, -0.1, 0), Color(1.0, 0.86, 0.6), 0.5)
		if is_inside_tree() and randf() < 0.4 and Audio.has_sound("zap"):
			Audio.play("zap", randf_range(1.2, 1.6), -24.0)
