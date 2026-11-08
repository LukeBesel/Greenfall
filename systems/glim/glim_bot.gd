class_name GlimBot
extends Node3D
## [buddy] Glim's body: a tiny floating lantern bot (pearl shell, a cyan lantern core behind a
## glass band, orange accents, two small eyes, an optional top). Follows a target smoothly at
## shoulder height with a soft bob and carries one cheap OmniLight (shadows only above Low).

const SIZE: float = 0.17  # shell radius (Lumi is ~1.3 m tall)
const FOLLOW_OFFSET := Vector3(0.62, 1.4, 0.3)  # target-local: right, up, behind (beside his head)

var target: Node3D
var sky: Node  # SkyDirector (time of day for the lantern); null = always night-bright
var light: OmniLight3D
var light_range: float = 6.0
var light_energy: float = 1.1
var scanning: float = 0.0  # 0..1 brief scan flare (eyes squint, core flares)
var music_bpm: float = 0.0  # > 0 while a found song plays (Music upgrade): bob to the beat, notes
var _notes: Array[Label3D] = []
var _beat: float = 0.0
var _groove: float = 0.0  # 0..1 eases in/out with the music
var _root: Node3D
var _shell_mat: StandardMaterial3D
var _accent_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _glass_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _eyes: Array[MeshInstance3D] = []
var _top: Node3D
var _top_id: String = ""
var _t: float = 0.0
var _blink_t: float = 2.0
var _vel := Vector3.ZERO
var _yaw: float = 0.0


func _ready() -> void:
	_root = Node3D.new()
	add_child(_root)
	_build()
	apply_look()


func _mat(c: Color, rough: float = 0.35, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _mesh(mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = ProcMesh.xf(pos, rot, scl)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(mi)
	return mi


func _build() -> void:
	_shell_mat = _mat(Color(0.92, 0.9, 0.87), 0.28)
	_shell_mat.clearcoat_enabled = true
	_shell_mat.clearcoat = 0.6
	_accent_mat = _mat(Color(1.0, 0.55, 0.18), 0.4)
	_core_mat = _mat(Color(0.3, 0.9, 1.0))
	_core_mat.emission_enabled = true
	_core_mat.emission_energy_multiplier = 3.0
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glass_mat = _mat(Color(0.7, 0.95, 1.0, 0.35), 0.05)
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_mat.emission_enabled = true
	_glass_mat.emission_energy_multiplier = 0.8
	_eye_mat = _mat(Color(0.05, 0.06, 0.08), 0.2)
	_eye_mat.emission_enabled = true
	_eye_mat.emission_energy_multiplier = 1.6
	var r: float = SIZE
	# Upper shell dome and a lower cap, split by the glowing lantern band.
	_mesh(ProcMesh.hemisphere(r, 20, 8), _shell_mat, Vector3(0, r * 0.18, 0))
	_mesh(ProcMesh.hemisphere(r * 0.92, 20, 6), _shell_mat, Vector3(0, -r * 0.18, 0), Vector3(180, 0, 0))
	_mesh(ProcMesh.cyl(r * 0.97, r * 0.97, r * 0.38, 20), _glass_mat)
	_mesh(ProcMesh.sphere(r * 0.62, 14, 7), _core_mat)
	# Orange accents: a thin rim under the dome and a little keel fin at the bottom.
	_mesh(ProcMesh.torus(r * 0.93, r * 1.03, 24, 6), _accent_mat, Vector3(0, r * 0.2, 0))
	_mesh(ProcMesh.cyl(r * 0.16, r * 0.05, r * 0.42, 8), _accent_mat, Vector3(0, -r * 1.02, 0))
	# Two small eyes on the dome's front (-Z is forward), slightly apart and up.
	for sx: float in [-1.0, 1.0]:
		var e: MeshInstance3D = _mesh(ProcMesh.capsule(r * 0.11, r * 0.36), _eye_mat,
			Vector3(sx * r * 0.34, r * 0.52, -r * 0.83), Vector3(-30, 0, 0))
		_eyes.append(e)
	# Side nubs (tiny ear lenses, orange).
	for sx: float in [-1.0, 1.0]:
		_mesh(ProcMesh.cyl(r * 0.14, r * 0.14, r * 0.12, 10), _accent_mat, Vector3(sx * r * 1.0, r * 0.18, 0), Vector3(0, 0, 90))
	light = OmniLight3D.new()
	light.light_color = Color(0.55, 0.92, 1.0)
	light.omni_attenuation = 1.4
	light.light_specular = 0.25
	light.shadow_enabled = Settings.quality >= Settings.Quality.HIGH  # never on Low / Medium
	light.light_volumetric_fog_energy = 0.0
	light.position = Vector3(0, -0.05, 0)
	add_child(light)


## Re-reads the worn look from Glim's state.
func apply_look() -> void:
	if _shell_mat == null:
		return
	_shell_mat.albedo_color = Glim.worn_color("shells")
	var g: Color = Glim.worn_color("glows")
	_core_mat.albedo_color = g
	_core_mat.emission = g
	_glass_mat.albedo_color = Color(g.r, g.g, g.b, 0.3).lerp(Color(1, 1, 1, 0.3), 0.4)
	_glass_mat.emission = g * 0.6
	_eye_mat.emission = g
	light.light_color = g.lerp(Color.WHITE, 0.35)
	var top: String = Glim.worn("tops")
	if top != _top_id:
		_top_id = top
		if _top:
			_top.queue_free()
		_top = _build_top(top)


func _build_top(id: String) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(0, SIZE * 1.15, 0)
	_root.add_child(n)
	var r: float = SIZE
	var add := func(mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.transform = ProcMesh.xf(pos, rot)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(mi)
	match id:
		"antenna":
			add.call(ProcMesh.cyl(r * 0.03, r * 0.04, r * 0.7), _mat(Color(0.3, 0.32, 0.36), 0.4, 0.6), Vector3(r * 0.12, r * 0.3, 0), Vector3(0, 0, -12))
			add.call(ProcMesh.sphere(r * 0.1, 10, 5), _core_mat, Vector3(r * 0.2, r * 0.68, 0))
		"sprout":
			var leaf := _mat(Color(0.45, 0.78, 0.32), 0.6)
			add.call(ProcMesh.cyl(r * 0.03, r * 0.035, r * 0.4), leaf, Vector3(0, r * 0.15, 0))
			add.call(ProcMesh.sphere(r * 0.16, 10, 5), leaf, Vector3(r * 0.16, r * 0.36, 0), Vector3(0, 0, -40))
			add.call(ProcMesh.sphere(r * 0.13, 10, 5), leaf, Vector3(-r * 0.13, r * 0.32, 0), Vector3(0, 0, 40))
		"beanie":
			var wool := _mat(Color(0.86, 0.36, 0.3), 0.95)
			add.call(ProcMesh.hemisphere(r * 0.78, 16, 6), wool, Vector3(0, -r * 0.32, 0))
			add.call(ProcMesh.torus(r * 0.68, r * 0.84, 18, 6), _mat(Color(0.95, 0.92, 0.85), 0.95), Vector3(0, -r * 0.3, 0))
			add.call(ProcMesh.sphere(r * 0.16, 10, 5), _mat(Color(0.95, 0.92, 0.85), 0.95), Vector3(0, r * 0.5, 0))
		"halo":
			var gold := _mat(Color(1.0, 0.85, 0.45), 0.2, 0.8)
			gold.emission_enabled = true
			gold.emission = Color(1.0, 0.8, 0.4)
			gold.emission_energy_multiplier = 1.5
			add.call(ProcMesh.torus(r * 0.5, r * 0.6, 24, 6), gold, Vector3(0, r * 0.35, 0))
	return n


## Soft music-note glow: three little notes drift up around him while a song plays.
func _update_notes(_delta: float) -> void:
	if _groove <= 0.0:
		for n: Label3D in _notes:
			n.visible = false
		return
	if _notes.is_empty():
		for i: int in 3:
			var n := Label3D.new()
			n.text = ["♪", "♫", "♪"][i]
			n.font_size = 48
			n.pixel_size = 0.0035
			n.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			n.shaded = false
			n.no_depth_test = false
			n.outline_size = 0
			n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(n)
			_notes.append(n)
	var g: Color = Glim.worn_color("glows")
	for i: int in _notes.size():
		var n: Label3D = _notes[i]
		var ph: float = fmod(_t * 0.45 + float(i) / 3.0, 1.0)  # rise 0..1, staggered
		var side: float = sin(float(i) * 2.4 + _t * 0.7)
		n.visible = true
		n.position = Vector3(side * 0.22, SIZE * 0.9 + ph * 0.45, cos(float(i) * 2.4) * 0.12)
		var c: Color = g.lerp(Color.WHITE, 0.3)
		c.a = sin(ph * PI) * 0.85 * _groove
		n.modulate = c


func set_light(range_m: float, energy: float) -> void:
	light_range = range_m
	light_energy = energy


## Jump to the follow point (after loading or when he's found).
func snap_to_target() -> void:
	if target:
		global_position = _follow_point()
		_vel = Vector3.ZERO


func _follow_point() -> Vector3:
	var b: Basis = Basis(Vector3.UP, target.global_rotation.y)
	return target.global_position + b * FOLLOW_OFFSET


## How bright the lantern should be: full at night, a faint glow by day.
static func night_amount(time_of_day: float) -> float:
	var d: float = absf(fmod(time_of_day + 1.0, 1.0) - 0.5)  # 0 noon .. 0.5 midnight
	return smoothstep(0.18, 0.28, d)


func _process(delta: float) -> void:
	_t += delta
	scanning = maxf(0.0, scanning - delta * 1.6)
	if target and is_instance_valid(target):
		visible = target.is_visible_in_tree()  # hidden with Lumi (rocket launch, cinematics)
		var want: Vector3 = _follow_point()
		# Critically damped spring: smooth, never overshoots much; teleport when far behind.
		var to: Vector3 = want - global_position
		if to.length() > 14.0:
			global_position = want
			_vel = Vector3.ZERO
		else:
			var k: float = 9.0
			_vel += (to * k - _vel * 2.0 * sqrt(k)) * minf(delta, 0.05)
			global_position += _vel * delta
		# Face where he's going (or Lumi's facing when still), gently.
		var flat := Vector3(_vel.x, 0, _vel.z)
		var face: float = atan2(-flat.x, -flat.z) if flat.length() > 0.4 else target.global_rotation.y
		_yaw = lerp_angle(_yaw, face, clampf(delta * 4.0, 0.0, 1.0))
	_groove = move_toward(_groove, 1.0 if music_bpm > 0.0 else 0.0, delta * 1.5)
	if music_bpm > 0.0:
		_beat += delta * music_bpm / 60.0
	var hop: float = absf(sin(_beat * PI))  # one hop per beat
	_root.position.y = sin(_t * 2.1) * 0.05 * (1.0 - _groove) + (hop * 0.07 - 0.02) * _groove
	_root.rotation = Vector3(sin(_t * 1.3) * 0.08 - clampf(_vel.length() * 0.04, 0.0, 0.25), _yaw,
		sin(_t * 1.7) * 0.06 * (1.0 - _groove) + sin(_beat * PI * 0.5) * 0.16 * _groove)  # sway every two beats
	_update_notes(delta)
	# Blink now and then; squint while scanning.
	_blink_t -= delta
	var blink: float = 1.0
	if _blink_t < 0.12:
		blink = 0.15
		if _blink_t <= 0.0:
			_blink_t = randf_range(2.5, 5.5)
	for e: MeshInstance3D in _eyes:
		e.scale = Vector3(1.0, maxf(0.15, blink * (1.0 - scanning * 0.5)), 1.0)
	var night: float = night_amount(float(sky.get("time_of_day"))) if sky and is_instance_valid(sky) else 1.0
	var flare: float = scanning * 1.5
	_core_mat.emission_energy_multiplier = 1.4 + 2.2 * night + flare * 3.0 + hop * 0.8 * _groove
	light.omni_range = lerpf(2.0, light_range, night) + flare * 2.0
	light.light_energy = lerpf(0.25, light_energy, night) + flare
	light.visible = light.light_energy > 0.05
