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

const LEAN := Vector3(0.28, 0.0, 0.15)  # back and to the side (radians): it reads as crashed from across the yard
const SINK: float = 0.2
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
	_smoke.emitting = stage < 2
	_smoke.color = Color(0.3, 0.29, 0.28, 0.62 if stage == 0 else 0.2)
	EscapePod.set_condition(pod, stage)


# --- Ground ------------------------------------------------------------------------------

## The furrow: how far it runs back from the pod, its half-width at the pod and at its tail, and
## how high its lips stand at the pod (m). Low enough to walk over.
const FURROW_LEN: float = 7.4
const FURROW_HALF: Vector2 = Vector2(0.78, 0.36)
const FURROW_LIP: float = 0.36
const FURROW_SKIRT: float = 0.85  # from the trench's edge out to the foot of the lip
## The crash site's turn on a start yard (radians about up, from the yard's own frame).
const YARD_YAW: float = 0.5


## Discs (x, z, radius; metres from the pod) over the furrow of a crash site turned `yaw` about
## up: loose junk keeps off them (YardKeepOut), so the trench reads as ploughed earth and not as
## lumps under a litter carpet.
static func furrow_discs(yaw: float = 0.0) -> Array[Vector3]:
	var back: Vector3 = Basis(Vector3.UP, yaw) * Vector3(FROM_DIR.x, 0, FROM_DIR.z).normalized()
	var out: Array[Vector3] = []
	var n: int = 6
	for i: int in n:
		var t: float = float(i) / float(n - 1)
		var c: Vector3 = back * lerpf(1.6, FURROW_LEN, t)
		out.append(Vector3(c.x, c.z, lerpf(FURROW_HALF.x, FURROW_HALF.y, t) + FURROW_SKIRT + 0.25))
	return out


func _build_ground() -> void:
	var back: Vector3 = Vector3(FROM_DIR.x, 0, FROM_DIR.z).normalized()
	var ang: float = atan2(back.x, back.z)
	var side: Vector3 = back.cross(Vector3.UP).normalized()
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	_build_trench(back, side, rng)
	# Thrown-up earth: clods along the lips' crests and scattered just outside them.
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = Color(0.42, 0.29, 0.18)
	dirt.roughness = 1.0
	var burnt := StandardMaterial3D.new()
	burnt.albedo_color = Color(0.15, 0.12, 0.1)
	burnt.roughness = 1.0
	for i: int in 46:
		var t: float = pow(rng.randf(), 0.8)
		var sgn: float = 1.0 if i % 2 == 0 else -1.0
		var half: float = lerpf(FURROW_HALF.x, FURROW_HALF.y, t)
		var lat: float = sgn * (half + rng.randf_range(0.2, FURROW_SKIRT))
		var clod := MeshInstance3D.new()
		clod.mesh = ProcMesh.sphere(lerpf(0.2, 0.09, t) * rng.randf_range(0.7, 1.3), 7, 4)
		clod.material_override = burnt if rng.randf() < lerpf(0.4, 0.15, t) else dirt
		clod.scale = Vector3(rng.randf_range(0.9, 1.4), rng.randf_range(0.5, 0.8), rng.randf_range(0.9, 1.5))
		clod.rotation.y = ang + rng.randf_range(-0.7, 0.7)
		clod.position = back * lerpf(0.4, FURROW_LEN - 0.3, t) + side * lat + Vector3(0, lerpf(FURROW_LIP, 0.06, t) * rng.randf_range(0.3, 0.8), 0)
		add_child(clod)
	# The bank it pushed up where it stopped.
	for i: int in 7:
		var a: float = lerpf(-1.1, 1.1, float(i) / 6.0)
		var bank := MeshInstance3D.new()
		bank.mesh = ProcMesh.sphere(rng.randf_range(0.34, 0.5), 8, 5)
		bank.material_override = dirt if i % 3 != 1 else burnt
		bank.scale = Vector3(1.5, 0.45, 1.0)
		bank.rotation.y = ang + a
		bank.position = -back * (1.25 * cos(a)) + side * (1.35 * sin(a))
		add_child(bank)
	# Two hull shards that broke off on impact.
	var shard_m: Material = EscapePod.paint(EscapePod.PANEL, 0.4, 0.5)
	for k: int in 6:
		var sh := MeshInstance3D.new()
		sh.mesh = ProcMesh.box(Vector3(0.36, 0.025, 0.24) * (1.0 + 0.35 * (k % 3)))
		sh.material_override = shard_m
		sh.position = back * (2.4 + k * 0.9) + side * ((0.7 - (k % 2) * 1.3) * (1.0 + 0.2 * k)) + Vector3(0, 0.05, 0)
		sh.rotation = Vector3(0.3, rng.randf() * TAU, 0.2)
		add_child(sh)


## The trench itself, one mesh lofted along the pod's path: outside ground, up over a lip of
## turned earth, down a scorched inner face to a dark floor, and up the other side. The lips are
## highest and the trench widest at the pod; both run out to nothing at the tail. Every section is
## jittered, so the lips are lumpy and the edge wanders.
func _build_trench(back: Vector3, side: Vector3, rng: RandomNumberGenerator) -> void:
	var soil := Color(0.4, 0.27, 0.17)
	var crest := Color(0.5, 0.35, 0.21)
	var scorch := Color(0.16, 0.12, 0.1)
	var floor_c := Color(0.08, 0.07, 0.065)
	var sections: int = 26
	var rows: Array = []  # per section: [[point, colour] x 7]
	for i: int in sections + 1:
		var t: float = float(i) / float(sections)
		var along: float = lerpf(-0.2, FURROW_LEN, t)
		var fade: float = clampf((1.0 - t) * 4.0, 0.0, 1.0) * clampf(t * 10.0 + 0.4, 0.0, 1.0)
		var tail: float = clampf((1.0 - t) * 3.5, 0.0, 1.0)  # the last stretch: the trench shallows out and closes
		var half: float = lerpf(FURROW_HALF.x, FURROW_HALF.y, t) * rng.randf_range(0.9, 1.1) * lerpf(0.12, 1.0, tail)
		var mid: Vector3 = back * along + side * sin(t * 5.0) * 0.12
		var row: Array = []
		for sgn: float in [-1.0, 1.0]:
			var lip: float = lerpf(FURROW_LIP, 0.1, t) * fade * rng.randf_range(0.7, 1.25)
			var foot: Vector3 = mid + side * sgn * (half + FURROW_SKIRT * rng.randf_range(0.85, 1.1))
			var top: Vector3 = mid + side * sgn * (half + 0.32 * rng.randf_range(0.8, 1.2)) + Vector3(0, lip, 0)
			var inner: Vector3 = mid + side * sgn * half * 0.8 + Vector3(0, 0.1, 0)
			var part: Array = [[foot + Vector3(0, 0.04, 0), soil], [top, crest.lightened(rng.randf_range(-0.08, 0.08))], [inner, soil.lerp(scorch, tail)]]
			if sgn > 0.0:
				part.reverse()
			row.append_array(part)
		row.insert(3, [mid + Vector3(0, 0.085, 0), soil.lerp(floor_c, tail)])
		rows.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in sections:
		for j: int in 6:
			var quad: Array = [rows[i][j], rows[i + 1][j], rows[i + 1][j + 1], rows[i][j + 1]]
			for idx: int in [0, 1, 2, 0, 2, 3]:
				st.set_color(quad[idx][1])
				st.set_uv(Vector2((quad[idx][0] as Vector3).x, (quad[idx][0] as Vector3).z) * 0.6)
				st.add_vertex(quad[idx][0])
	st.index()
	st.generate_normals()
	var m: StandardMaterial3D = AssetLib.pbr_material("farm_soil", 1.0, Color.WHITE)
	m.albedo_texture = null  # the soil's bumps and roughness; the colour is the lofted mesh's own
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.name = "Furrow"
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# --- Damage -----------------------------------------------------------------------------

func _build_damage() -> void:
	var bn: MeshInstance3D = pod.get_node_or_null("Beacon")
	_beacon = bn.material_override as StandardMaterial3D if bn else Mats.lamp(EscapePod.LAMP, 3.0)
	var home: Vector3 = EscapePod.facet_point(4, 1.2, 0.0)
	# Smoke: a light plume from the top of the pod, drifting with the breeze.
	_smoke = CPUParticles3D.new()
	_smoke.name = "Smoke"
	var q := QuadMesh.new()
	q.size = Vector2(1.3, 1.3)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.vertex_color_use_as_albedo = true
	sm.albedo_texture = EscapePod._soft_tex()
	sm.disable_receive_shadows = true
	q.material = sm
	_smoke.mesh = q
	_smoke.amount = 30
	_smoke.lifetime = 7.5
	_smoke.preprocess = 5.0
	_smoke.local_coords = false
	_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_smoke.emission_sphere_radius = 0.2
	_smoke.direction = Vector3(0.25, 1, 0.1)
	_smoke.spread = 12.0
	_smoke.gravity = Vector3(0.18, 0.25, 0.05)
	_smoke.initial_velocity_min = 0.7
	_smoke.initial_velocity_max = 1.1
	_smoke.angle_max = 180.0
	_smoke.scale_amount_min = 0.6
	_smoke.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 3.4))
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
		Vfx.burst("sparkle", at, Color(1.0, 0.62, 0.25), 0.35)
		if randf() < 0.5:
			Vfx.burst("sparkle", at + Vector3(0, -0.1, 0), Color(1.0, 0.85, 0.55), 0.2)
		if is_inside_tree() and randf() < 0.4 and Audio.has_sound("zap"):
			Audio.play("zap", randf_range(1.2, 1.6), -24.0)
