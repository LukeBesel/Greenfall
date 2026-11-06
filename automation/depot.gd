class_name Depot
extends Node3D
## The Depot Intake: a rusty pad with a big hungry chute. Patch rolls onto the pad and his carried
## cubes hop off his back into the chute one by one. Loose cubes pushed onto the pad get sucked in.

const PAD_RADIUS: float = 1.7
const FEED_INTERVAL: float = 0.16

var patch: Node3D  # Patch (set by the scene)
var _chute: Node3D
var _chute_mouth: Vector3
var _feed_timer: float = 0.0
var _combo: int = 0
var _combo_timer: float = 0.0
var _light_mat: ShaderMaterial
var _pad_mat: ShaderMaterial
var _t: float = 0.0


func _ready() -> void:
	add_to_group("depot")
	_build()


func _build() -> void:
	var pad := MeshInstance3D.new()
	pad.mesh = ProcMesh.cyl(PAD_RADIUS, PAD_RADIUS + 0.12, 0.14, 32)
	_pad_mat = ProcMesh.toon_material(Color(0.95, 0.78, 0.3), 0.5, 2.0)
	pad.material_override = _pad_mat
	pad.position = Vector3(0, 0.07, 0)
	add_child(pad)
	var inner := MeshInstance3D.new()
	inner.mesh = ProcMesh.cyl(PAD_RADIUS * 0.72, PAD_RADIUS * 0.72, 0.15, 32)
	inner.material_override = ProcMesh.toon_material(Color(0.32, 0.3, 0.38), 0.3, 3.0)
	inner.position = Vector3(0, 0.08, 0)
	add_child(inner)
	# Arrow chevrons pointing to the chute.
	var chev_mat: ShaderMaterial = ProcMesh.toon_material(Color(1.0, 0.85, 0.35), 0.2)
	for k: int in 3:
		var c := MeshInstance3D.new()
		c.mesh = ProcMesh.box(Vector3(0.5, 0.02, 0.12))
		c.material_override = chev_mat
		c.position = Vector3(0, 0.165, 0.5 - k * 0.45)
		c.rotation_degrees = Vector3(0, 0, 0)
		add_child(c)
	# The chute machine behind the pad (-Z).
	_chute = Node3D.new()
	_chute.position = Vector3(0, 0, -2.6)
	add_child(_chute)
	var body_mat: ShaderMaterial = ProcMesh.toon_material(Color(0.95, 0.45, 0.35), 0.5, 11.0)
	var base := MeshInstance3D.new()
	base.mesh = ProcMesh.rounded_box(Vector3(2.0, 2.0, 1.6), 0.25, 3)
	base.material_override = body_mat
	base.position = Vector3(0, 1.0, 0)
	_chute.add_child(base)
	var funnel := MeshInstance3D.new()
	funnel.mesh = ProcMesh.cyl(1.0, 0.55, 0.8, 20)
	funnel.material_override = ProcMesh.toon_material(Color(0.75, 0.78, 0.82), 0.55, 12.0)
	funnel.position = Vector3(0, 2.35, 0.1)
	_chute.add_child(funnel)
	var mouth := MeshInstance3D.new()
	mouth.mesh = ProcMesh.cyl(0.85, 0.85, 0.05, 20)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.06, 0.1)
	mouth.material_override = dark
	mouth.position = Vector3(0, 2.74, 0.1)
	_chute.add_child(mouth)
	_chute_mouth = _chute.position + Vector3(0, 2.9, 0.1)
	# Sign + light.
	var sign_label := Label3D.new()
	sign_label.text = "DEPOT"
	sign_label.font_size = 96
	sign_label.pixel_size = 0.005
	sign_label.outline_size = 16
	sign_label.modulate = Color(1.0, 0.95, 0.8)
	sign_label.outline_modulate = Color(0.3, 0.12, 0.1)
	sign_label.position = Vector3(0, 1.2, 0.82)
	_chute.add_child(sign_label)
	var lamp := MeshInstance3D.new()
	lamp.mesh = ProcMesh.sphere(0.16, 12, 6)
	_light_mat = ProcMesh.toon_material(Color(0.5, 1.0, 0.6), 0.0)
	_light_mat.set_shader_parameter("emission_color", Color(0.5, 1.0, 0.6))
	_light_mat.set_shader_parameter("emission_strength", 0.8)
	lamp.material_override = _light_mat
	lamp.position = Vector3(0.75, 2.15, 0.6)
	_chute.add_child(lamp)
	# Collision for the machine so cubes and Patch bump into it.
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.0, 2.8, 1.6)
	cs.shape = bs
	cs.position = Vector3(0, 1.4, 0)
	sb.add_child(cs)
	_chute.add_child(sb)


func pad_contains(world_pos: Vector3) -> bool:
	var d: Vector3 = world_pos - global_position
	d.y = 0.0
	return d.length() <= PAD_RADIUS


func mouth_world() -> Vector3:
	return to_global(_chute_mouth)


func _physics_process(delta: float) -> void:
	_t += delta
	_light_mat.set_shader_parameter("emission_strength", 0.6 + 0.3 * sin(_t * 3.0))
	_combo_timer -= delta
	if _combo_timer <= 0.0:
		_combo = 0
	_feed_timer -= delta
	if patch and _feed_timer <= 0.0 and pad_contains(patch.global_position) and patch.has_method("pop_carried_cube"):
		var cube: JunkCube = patch.pop_carried_cube()
		if cube:
			_feed_timer = FEED_INTERVAL
			_swallow(cube)
	# Loose cubes on the pad get sucked in.
	for n: Node in get_tree().get_nodes_in_group("junk_cube"):
		var c: JunkCube = n
		if c.carried or c.claimed:
			continue
		if pad_contains(c.global_position) and c.global_position.y < 3.0:
			_swallow(c)


func _swallow(cube: JunkCube) -> void:
	cube.claimed = true
	cube.set_carried(true)
	var start: Vector3 = cube.global_position
	var end: Vector3 = mouth_world()
	var top: Vector3 = (start + end) * 0.5 + Vector3(0, 2.2, 0)
	Audio.play("whoosh", 1.2, -8.0)
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		var a: Vector3 = start.lerp(top, t)
		var b: Vector3 = top.lerp(end, t)
		cube.global_position = a.lerp(b, t)
		cube.rotation += Vector3(0.15, 0.2, 0.1)
		, 0.0, 1.0, 0.32).set_trans(Tween.TRANS_SINE)
	tw.tween_property(cube, "scale", Vector3.ONE * 0.2, 0.08)
	tw.tween_callback(_cash.bind(cube))


func _cash(cube: JunkCube) -> void:
	_combo += 1
	_combo_timer = 1.2
	var v: BigNum = cube.value
	GameState.add_currency("cubes", v)
	GameState.inc_stat("cubes_cashed")
	EventBus.cube_cashed.emit(v, mouth_world())
	Audio.play_scale("coin", mini(_combo - 1, 8), -4.0)
	var col: Color = Color(1.0, 0.9, 0.35) if cube.info.get("perfect", false) else Color(0.85, 1.0, 0.6)
	Vfx.float_text(mouth_world() + Vector3(0, 0.4, 0), "+" + Settings.fmt(v), col, 1.0 + minf(_combo * 0.08, 0.6))
	Vfx.burst("sparkle", mouth_world(), Color(1.0, 0.9, 0.5))
	Vfx.ring(global_position, PAD_RADIUS * 1.4, Color(1.0, 0.9, 0.5, 0.8), 0.45)
	var tw := create_tween()
	tw.tween_property(_chute, "scale", Vector3(1.08, 0.9, 1.08), 0.05)
	tw.tween_property(_chute, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	cube.queue_free()
