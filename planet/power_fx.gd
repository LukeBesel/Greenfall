class_name PowerFx
extends RefCounted
## [world3] Dead / live lights and the "it comes back on" moment: a spark, a few stutters, then
## steady light. Works on neon-shader materials (art/shaders/neon.gdshader `power`),
## StandardMaterial3D emission and Light3D nodes. See planet/street_power.gd for the owner rule.

const NEON: String = "res://art/shaders/neon.gdshader"
## The stutter before a light holds: [power, seconds] steps.
const STUTTER: Array = [[1.0, 0.06], [0.0, 0.12], [0.7, 0.05], [0.0, 0.3], [1.0, 0.04], [0.15, 0.08], [1.0, 0.0]]


static func _set_mat(m: Material, p: float) -> void:
	if m is ShaderMaterial:
		(m as ShaderMaterial).set_shader_parameter("power", p)
	elif m is StandardMaterial3D:
		var sm := m as StandardMaterial3D
		if not sm.has_meta("power_e"):
			sm.set_meta("power_e", sm.emission_energy_multiplier)
		sm.emission_energy_multiplier = float(sm.get_meta("power_e")) * p


static func _set_light(l: Light3D, p: float) -> void:
	if not is_instance_valid(l):
		return
	if not l.has_meta("power_e"):
		l.set_meta("power_e", l.light_energy)
	l.light_energy = float(l.get_meta("power_e")) * p
	l.visible = p > 0.01


static func set_power(mats: Array, lights: Array, on: bool) -> void:
	for m: Material in mats:
		_set_mat(m, 1.0 if on else 0.0)
	for l: Variant in lights:
		if l is Light3D:
			_set_light(l, 1.0 if on else 0.0)


static func _step(mats: Array, lights: Array, p: float) -> void:
	for m: Material in mats:
		_set_mat(m, p)
	for l: Variant in lights:
		if l is Light3D:
			_set_light(l, p)


## Flickers lights on after `delay` s: an optional node first swings back to `home` (a sign that
## hung askew), then a spark, a few stutters and a soft buzz, then on.
static func flicker_on(host: Node, mats: Array, lights: Array, delay: float = 0.0, node: Variant = null, home: Variant = null, spark_at: Vector3 = Vector3.ZERO) -> void:
	_step(mats, lights, 0.0)
	var tw: Tween = host.create_tween()
	tw.tween_interval(delay)
	if node is Node3D and home is Transform3D and is_instance_valid(node):
		tw.tween_property(node, "transform", home, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var at: Vector3 = spark_at
	if node is Node3D and is_instance_valid(node):
		at = (node as Node3D).global_position if (node as Node3D).is_inside_tree() else Vector3.ZERO
	tw.tween_callback(func() -> void:
		if at != Vector3.ZERO:
			Vfx.burst("sparkle", at, Color(1.0, 0.85, 0.5), 0.4)
		Audio.play("clunk", randf_range(1.6, 2.0), -14.0, 0.04, "lights"))  # [v6sound] one clunk per street, not per lamp
	for s: Array in STUTTER:
		var p: float = s[0]
		tw.tween_callback(func() -> void: _step(mats, lights, p))
		if float(s[1]) > 0.0:
			tw.tween_interval(float(s[1]))


static func _managed(n: Node, root: Node) -> bool:
	var a: Node = n
	while a and a != root:
		if a.has_meta("street_power"):
			return true
		a = a.get_parent()
	return false


## All neon materials (material_override) and lights under a node: for layers that arrive live.
static func collect(root: Node, mats: Array, lights: Array) -> void:
	for n: Node in root.find_children("*", "", true, false):
		if _managed(n, root):
			continue
		if n is Light3D and not (n is DirectionalLight3D):
			lights.append(n)
		elif n is GeometryInstance3D:
			var m: Material = (n as GeometryInstance3D).material_override
			if m is ShaderMaterial and (m as ShaderMaterial).shader and (m as ShaderMaterial).shader.resource_path == NEON:
				if not (m in mats):
					mats.append(m)
