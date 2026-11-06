class_name LaunchPad
extends Node3D
## The base's launch pad (comes with a level 5 base): a floating white launch ring held up by three
## anti-grav emitters, chasing cyan guide lights, energy clamps that hold the rocket and release at
## ignition, a slim service tower with a lift, a boarding gangway and umbilicals that retract,
## energy cells, floodlights, warning beacons and a holographic countdown. `construction` = true
## builds the level 4 placeholder: a holographic outline of the pad and rocket to come.
## Local frame matches RocketModel: the tower stands at -Z, the front (+Z) faces the base.

const TOP_Y: float = 1.25          # deck height: the rocket's feet stand here
const R: float = 3.3
const TOWER_Z: float = -4.4

var construction: bool = false
var rocket_tier: int = 1
var gangway: Node3D
var lift: Node3D
var _clamps: Array[Node3D] = []
var _hoses: Array[Node3D] = []
var _beacons: Array[StandardMaterial3D] = []
var _spin: SpotLight3D
var _spin_head: Node3D
var _vents: Array[CPUParticles3D] = []
var _steam: Array[CPUParticles3D] = []
var _chase_mat: ShaderMaterial
var _cell_strips: Array[Node3D] = []
var _alarm: bool = false
var _t: float = 0.0
var _soft_tex: GradientTexture2D

const CHASE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 col : source_color = vec4(0.3, 0.88, 1.0, 1.0);
uniform float speed = 0.35;
uniform float energy = 3.0;
uniform float dashes = 24.0;
void fragment() {
	float a = UV.x * dashes;
	float dash = smoothstep(0.15, 0.3, fract(a)) * smoothstep(0.85, 0.7, fract(a));
	float run = pow(fract(UV.x * 3.0 - TIME * speed), 6.0);
	ALBEDO = col.rgb * energy * dash * (0.25 + 2.5 * run);
}
"""


func _ready() -> void:
	_soft_tex = _radial()
	if construction:
		_build_hologram()
	else:
		_build()


func _build() -> void:
	var white := _gloss(Color(0.93, 0.94, 0.95), 0.25, 0.1, 0.8)
	var grey := _gloss(Color(0.55, 0.58, 0.62), 0.3, 0.7, 0.3)
	var dark := _gloss(Color(0.05, 0.06, 0.08), 0.12, 0.4, 1.0)
	var tang := _gloss(Color(1.0, 0.55, 0.18), 0.22, 0.1, 1.0)
	var glow := Mats.lamp(RocketModel.GLOW, 3.0)
	# Deck: a shallow dish, flat on top, open in the middle (the flame pit) so the plume passes through.
	var pit: float = 1.3
	var prof := PackedVector2Array([Vector2(pit, TOP_Y - 0.5), Vector2(2.2, TOP_Y - 0.5), Vector2(3.05, TOP_Y - 0.25), Vector2(R, TOP_Y - 0.08), Vector2(R, TOP_Y), Vector2(pit, TOP_Y), Vector2(pit, TOP_Y - 0.5)])
	var deck := _mi(self, RocketModel.lathe(prof, 56), white, Vector3.ZERO)
	deck.set_meta("deck", true)
	_mi(self, ProcMesh.torus(2.5, 2.95, 56, 4), dark, Vector3(0, TOP_Y + 0.005, 0)).scale = Vector3(1, 0.05, 1)
	_mi(self, ProcMesh.torus(pit - 0.02, pit + 0.1, 40, 4), glow, Vector3(0, TOP_Y + 0.02, 0))
	_mi(self, ProcMesh.torus(pit - 0.02, pit + 0.06, 40, 4), glow, Vector3(0, TOP_Y - 0.5, 0))
	# Flame grate: three thin spokes across the pit.
	for k: int in 3:
		var a: float = TAU * k / 3.0 + 0.5
		_mi(self, ProcMesh.box(Vector3(pit * 2.0, 0.05, 0.06)), grey, Vector3(0, TOP_Y - 0.45, 0), Vector3(0, -rad_to_deg(a), 0))
	# Chasing guide lights around the rim.
	_chase_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = CHASE_SHADER
	_chase_mat.shader = sh
	var rim := _mi(self, ProcMesh.torus(2.68, 2.8, 64, 3), _chase_mat, Vector3(0, TOP_Y + 0.02, 0))
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Tangerine hazard chevrons at the deck edge, the pad number on the deck.
	for k: int in 8:
		var a2: float = TAU * (k + 0.5) / 8.0
		_mi(self, ProcMesh.box(Vector3(0.12, 0.03, 0.5)), tang, Vector3(cos(a2) * 3.1, TOP_Y + 0.01, sin(a2) * 3.1), Vector3(0, -rad_to_deg(a2), 0))
	var num := Label3D.new()
	num.text = "PAD 01"
	num.font_size = 96
	num.pixel_size = 0.006
	num.modulate = Color(0.5, 1.5, 2.0)
	num.shaded = false
	num.rotation_degrees = Vector3(-90, 0, 0)
	num.position = Vector3(0, TOP_Y + 0.04, 2.0)
	add_child(num)
	# Underside glow and three anti-grav emitters with light beams to ground plates.
	_mi(self, ProcMesh.torus(1.9, 2.0, 40, 4), Mats.lamp(RocketModel.GLOW, 2.0), Vector3(0, TOP_Y - 0.5, 0))
	for a_deg: float in RocketModel.CLAMP_ANGLES:
		var a3: float = deg_to_rad(a_deg + 60.0)
		var p := Vector3(cos(a3) * 2.45, 0, sin(a3) * 2.45)
		_mi(self, ProcMesh.cyl(0.32, 0.22, 0.3, 20), white, p + Vector3(0, TOP_Y - 0.55, 0))
		_mi(self, ProcMesh.torus(0.2, 0.26, 20, 4), glow, p + Vector3(0, TOP_Y - 0.71, 0))
		var beam := _mi(self, ProcMesh.cyl(0.22, 0.42, TOP_Y - 0.72, 16), RocketModel._additive(Color(0.25, 0.8, 1.0, 0.22)), p + Vector3(0, (TOP_Y - 0.72) * 0.5, 0))
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mi(self, ProcMesh.cyl(0.55, 0.6, 0.06, 6), grey, p + Vector3(0, 0.03, 0))
		_mi(self, ProcMesh.torus(0.42, 0.48, 6, 3), glow, p + Vector3(0, 0.07, 0))
	# Energy clamps: pylons from the deck leaning in to hold the hull; they swing out at ignition.
	var hold_r: float = 1.62 if rocket_tier >= 3 else 1.04
	for a_deg: float in RocketModel.CLAMP_ANGLES:
		var a4: float = deg_to_rad(a_deg)
		var dir := Vector3(cos(a4), 0, sin(a4))
		var piv := Node3D.new()
		piv.position = dir * 2.3 + Vector3(0, TOP_Y, 0)
		piv.basis = Basis.looking_at(-dir, Vector3.UP)  # local -Z points at the rocket
		add_child(piv)
		var top := Vector3(0, 2.3, -(2.3 - hold_r - 0.12))
		_mi(piv, ProcMesh.cyl(0.22, 0.28, 0.2, 16), grey, Vector3(0, 0.1, 0))
		_rod(piv, Vector3(0, 0.15, 0), top, 0.1, white)
		_rod(piv, Vector3(0, 0.4, 0.02), top + Vector3(0, -0.2, 0.08), 0.03, glow)
		_mi(piv, RobotVisual._rbox(Vector3(0.36, 0.42, 0.2), 0.06, 2), white, top)
		_mi(piv, ProcMesh.box(Vector3(0.28, 0.3, 0.04)), Mats.lamp(RocketModel.GLOW, 4.0), top + Vector3(0, 0, -0.11))
		_clamps.append(piv)
	# Service tower.
	var tz := Vector3(0, 0, TOWER_Z)
	_mi(self, ProcMesh.cyl(0.95, 1.05, 0.25, 6), grey, tz + Vector3(0, 0.12, 0))
	_mi(self, RobotVisual._rbox(Vector3(1.0, 11.6, 1.0), 0.14, 3), white, tz + Vector3(0, 5.95, 0))
	for x: float in [-0.36, 0.36]:
		_mi(self, ProcMesh.box(Vector3(0.05, 10.8, 0.03)), glow, tz + Vector3(x, 5.9, 0.51))
	for y: float in [3.0, 6.2, 9.4]:
		_mi(self, ProcMesh.box(Vector3(1.04, 0.7, 1.04)), dark, tz + Vector3(0, y, 0))
		_mi(self, ProcMesh.box(Vector3(1.06, 0.05, 1.06)), tang, tz + Vector3(0, y - 0.4, 0))
	# Truss bracing on the tower sides.
	for sx: float in [-0.56, 0.56]:
		for k5: int in 7:
			var y0: float = 0.4 + k5 * 1.6
			var zz: float = 0.42 if k5 % 2 == 0 else -0.42
			_rod(self, tz + Vector3(sx, y0, zz), tz + Vector3(sx, y0 + 1.6, -zz), 0.035, grey)
	var top_y: float = 11.8
	_mi(self, ProcMesh.cyl(0.5, 0.7, 0.3, 20), grey, tz + Vector3(0, top_y, 0))
	_mi(self, ProcMesh.cyl(0.02, 0.02, 1.4, 6), grey, tz + Vector3(0.3, top_y + 0.8, 0))
	_beacon(tz + Vector3(0, top_y + 0.32, 0), 0.2)
	_spin_head = Node3D.new()
	_spin_head.position = tz + Vector3(0, top_y + 0.32, 0)
	add_child(_spin_head)
	_spin = SpotLight3D.new()
	_spin.light_color = Color(1.0, 0.5, 0.15)
	_spin.light_energy = 0.0
	_spin.spot_range = 24.0
	_spin.spot_angle = 18.0
	_spin.rotation_degrees = Vector3(-12, 0, 0)
	_spin_head.add_child(_spin)
	# Lift platform on the tower's front face (Aurora rides it to the gangway).
	lift = Node3D.new()
	lift.position = tz + Vector3(0, 0.3, 0.75)
	add_child(lift)
	_mi(lift, ProcMesh.cyl(0.42, 0.42, 0.06, 24), white, Vector3.ZERO)
	_mi(lift, ProcMesh.torus(0.38, 0.44, 24, 4), glow, Vector3(0, 0.02, 0))
	# Gangway: pivots at the tower, reaches the hatch, swings away before ignition.
	var hy: float = TOP_Y + RocketModel.HATCH_Y * _rocket_scale() - 0.6
	gangway = Node3D.new()
	gangway.position = tz + Vector3(0.0, hy, 0.5)
	add_child(gangway)
	var reach: float = absf(TOWER_Z) - 0.5 - RocketModel.hull_r(RocketModel.HATCH_Y) * _rocket_scale() - 0.05
	_mi(gangway, ProcMesh.box(Vector3(0.9, 0.12, reach)), white, Vector3(0, 0, reach * 0.5))
	_mi(gangway, ProcMesh.box(Vector3(0.7, 0.02, reach)), dark, Vector3(0, 0.07, reach * 0.5))
	for x2: float in [-0.45, 0.45]:
		var rail := _mi(gangway, ProcMesh.box(Vector3(0.04, 0.6, reach)), Mats.glass(Color(0.4, 0.8, 1.0, 0.25)), Vector3(x2, 0.36, reach * 0.5))
		rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mi(gangway, ProcMesh.box(Vector3(0.05, 0.04, reach)), glow, Vector3(x2, 0.67, reach * 0.5))
	# Umbilicals: two hoses from the tower to the hull; they drop away at T-3.
	for k2: int in 2:
		var hy2: float = TOP_Y + (2.5 + k2 * 0.7) * _rocket_scale()
		var piv2 := Node3D.new()
		piv2.position = tz + Vector3(-0.3 + k2 * 0.6, hy2 + 0.6, 0.5)
		add_child(piv2)
		var end := Vector3(0.0, -0.6, absf(TOWER_Z) - 0.5 - 1.02 * _rocket_scale())
		var prev := Vector3.ZERO
		for s: int in 6:
			var u: float = float(s + 1) / 6.0
			var p2: Vector3 = Vector3.ZERO.lerp(end, u) + Vector3(0, -sin(u * PI) * 0.45, 0)
			_rod(piv2, prev, p2, 0.07, Mats.rubber(Color(0.12, 0.13, 0.15)))
			prev = p2
		_mi(piv2, ProcMesh.cyl(0.12, 0.12, 0.2, 12), Mats.lamp(Color(1.0, 0.55, 0.18), 2.5), end, Vector3(90, 0, 0))
		_hoses.append(piv2)
	# Energy cells either side of the tower, with glowing level strips.
	for x3: float in [-2.6, 2.6]:
		var cp := Vector3(x3, 0, TOWER_Z - 0.2)
		_mi(self, ProcMesh.cyl(0.62, 0.7, 0.2, 20), grey, cp + Vector3(0, 0.1, 0))
		_mi(self, ProcMesh.capsule(0.55, 2.4), white, cp + Vector3(0, 1.4, 0))
		_mi(self, ProcMesh.cyl(0.57, 0.57, 0.12, 24), tang, cp + Vector3(0, 1.9, 0))
		var strip := Node3D.new()
		strip.position = cp + Vector3(0, 0.5, 0.55)
		add_child(strip)
		_mi(strip, ProcMesh.box(Vector3(0.12, 1.6, 0.04)), glow, Vector3(0, 0.8, 0))
		_cell_strips.append(strip)
		_beacon(cp + Vector3(0, 2.68, 0), 0.12)
		_rod(self, cp + Vector3(signf(-x3) * 0.5, 0.6, 0), tz + Vector3(signf(x3) * 0.5, 0.6, 0), 0.08, grey)
	# Floodlights aimed at the rocket.
	for x4: float in [-1.0, 1.0]:
		var fp := Vector3(x4 * 4.4, 0, -1.6)
		_mi(self, ProcMesh.cyl(0.06, 0.09, 5.0, 10), grey, fp + Vector3(0, 2.5, 0))
		var head := Node3D.new()
		head.position = fp + Vector3(0, 5.0, 0)
		add_child(head)
		head.look_at_from_position(head.position + global_position, global_position + Vector3(0, 5.5, 0))
		_mi(head, RobotVisual._rbox(Vector3(0.6, 0.35, 0.3), 0.06, 2), white, Vector3.ZERO)
		_mi(head, ProcMesh.box(Vector3(0.5, 0.26, 0.02)), Mats.lamp(Color(0.85, 0.95, 1.0), 4.0), Vector3(0, 0, -0.16))
		var sl := SpotLight3D.new()
		sl.light_energy = 2.5
		sl.light_color = Color(0.85, 0.95, 1.0)
		sl.spot_range = 14.0
		sl.spot_angle = 22.0
		head.add_child(sl)
	# The pad sign.
	var sign_l := Label3D.new()
	sign_l.text = "LAUNCH PAD"
	sign_l.font_size = 96
	sign_l.pixel_size = 0.008
	sign_l.modulate = Color(0.5, 1.5, 2.0, 0.9)
	sign_l.shaded = false
	sign_l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sign_l.position = tz + Vector3(0, top_y + 1.3, 0)
	add_child(sign_l)
	# Vapour: big billows out of the flame trench (both sides) and steam vents during countdown.
	for side: float in [-1.0, 1.0]:
		var v := _vapour(Vector3(side, 0.08, 0))
		v.position = Vector3(side * 2.6, TOP_Y - 0.5, 0)
		_vents.append(v)

	# Steam jets at the clamp bases and from under the deck rim during the countdown.
	for a_deg: float in RocketModel.CLAMP_ANGLES:
		var a6: float = deg_to_rad(a_deg)
		var s2 := _steam_vent()
		s2.position = Vector3(cos(a6) * 2.6, TOP_Y + 0.1, sin(a6) * 2.6)
		s2.direction = Vector3(cos(a6) * 0.5, 1, sin(a6) * 0.5)
		_steam.append(s2)
		var s3 := _steam_vent()
		s3.position = Vector3(cos(a6 + 1.0) * 3.0, TOP_Y - 0.4, sin(a6 + 1.0) * 3.0)
		s3.direction = Vector3(cos(a6 + 1.0), -0.3, sin(a6 + 1.0))
		s3.initial_velocity_min = 2.0
		s3.initial_velocity_max = 3.5
		_steam.append(s3)
	var under := _vapour(Vector3(0, -1, 0))
	under.position = Vector3(0, TOP_Y - 0.7, 0)
	under.spread = 80.0
	_vents.append(under)


func _rocket_scale() -> float:
	return Rocket.tier_scale(rocket_tier)


## The level 4 placeholder: a hologram of the coming pad and rocket.
func _build_hologram() -> void:
	var holo := RocketModel._additive(Color(0.25, 0.8, 1.0, 0.18))
	var line := RocketModel._additive(Color(0.35, 0.9, 1.0, 0.7))
	_mi(self, ProcMesh.cyl(R, R, 0.04, 48), holo, Vector3(0, TOP_Y, 0))
	for r: float in [R, 2.8, 1.3]:
		_mi(self, ProcMesh.torus(r - 0.03, r + 0.03, 48, 3), line, Vector3(0, TOP_Y, 0))
	for y: float in [1.0, 3.0, 5.0, 7.0]:
		_mi(self, ProcMesh.torus(RocketModel.hull_r(y) - 0.02, RocketModel.hull_r(y) + 0.02, 32, 3), line, Vector3(0, TOP_Y + y, 0))
	var ghost := _mi(self, ProcMesh.cyl(0.6, 1.0, 8.0, 24), holo, Vector3(0, TOP_Y + 4.5, 0))
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi(self, ProcMesh.box(Vector3(1.0, 11.0, 1.0)), holo, Vector3(0, 5.5, TOWER_Z))
	var sign_l := Label3D.new()
	sign_l.text = "LAUNCH PAD\nBASE LEVEL 5"
	sign_l.font_size = 80
	sign_l.pixel_size = 0.008
	sign_l.modulate = Color(0.5, 1.5, 2.0, 0.9)
	sign_l.shaded = false
	sign_l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sign_l.position = Vector3(0, TOP_Y + 10.0, 0)
	add_child(sign_l)


# --- Sequence hooks (driven by Rocket) ---------------------------------------------------

func set_alarm(on: bool) -> void:
	_alarm = on
	_spin.light_energy = 6.0 if on else 0.0


func vent_steam(on: bool) -> void:
	for s: CPUParticles3D in _steam:
		s.emitting = on


func billow(on: bool) -> void:
	for v: CPUParticles3D in _vents:
		v.emitting = on


## 0..1: hoses dropped away (they swing down on their tower pivots).
func set_hoses(k: float) -> void:
	for h: Node3D in _hoses:
		h.rotation.x = k * 1.1


## 0..1: gangway swung back against the tower.
func set_gangway(k: float) -> void:
	gangway.rotation.y = k * deg_to_rad(105.0)


## 0..1: clamps swung open.
func set_clamps(k: float) -> void:
	for c: Node3D in _clamps:
		c.rotation.x = 0.0
		c.basis = Basis.looking_at(-Vector3(c.position.x, 0, c.position.z).normalized(), Vector3.UP) * Basis(Vector3.RIGHT, k * 0.75)


## 0..1: energy drained from the cells (the level strips shrink).
func set_fuel(k: float) -> void:
	for s: Node3D in _cell_strips:
		s.scale = Vector3(1, maxf(0.05, 1.0 - k), 1)


func lift_point() -> Vector3:
	return lift.global_position


func _process(delta: float) -> void:
	_t += delta
	if construction:
		return
	if _spin_head:
		_spin_head.rotate_y(delta * (5.0 if _alarm else 0.6))
	var blink: bool = fmod(_t, 0.5 if _alarm else 1.6) < (0.25 if _alarm else 0.12)
	for m: StandardMaterial3D in _beacons:
		m.emission_energy_multiplier = 7.0 if blink else 0.4
	if _chase_mat:
		_chase_mat.set_shader_parameter("speed", 1.6 if _alarm else 0.35)
		_chase_mat.set_shader_parameter("col", Color(1.0, 0.45, 0.15) if _alarm and blink else RocketModel.GLOW)


# --- Helpers ---------------------------------------------------------------------------

func _beacon(p: Vector3, r: float) -> void:
	var m: StandardMaterial3D = Mats.lamp(Color(1.0, 0.45, 0.12), 2.0)
	_beacons.append(m)
	_mi(self, ProcMesh.sphere(r, 12, 6), m, p)


func _vapour(dir: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 70
	p.lifetime = 4.0
	p.local_coords = false
	p.direction = dir
	p.spread = 28.0
	p.initial_velocity_min = 7.0
	p.initial_velocity_max = 13.0
	p.damping_min = 2.2
	p.damping_max = 3.2
	p.gravity = Vector3(0, 0.7, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.6
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -20.0
	p.angular_velocity_max = 20.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.4
	var c := Curve.new()
	c.add_point(Vector2(0, 0.6))
	c.add_point(Vector2(0.4, 2.6))
	c.add_point(Vector2(1, 4.2))
	p.scale_amount_curve = c
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.add_point(0.06, Color(0.97, 0.99, 1.0, 0.9))
	g.add_point(0.55, Color(0.9, 0.94, 0.98, 0.55))
	g.set_color(g.get_point_count() - 1, Color(0.88, 0.92, 0.96, 0.0))
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(2.2, 2.2)
	q.material = _puff_mat()
	p.mesh = q
	add_child(p)
	return p


func _steam_vent() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 40
	p.lifetime = 2.2
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 14.0
	p.initial_velocity_min = 3.5
	p.initial_velocity_max = 6.0
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.gravity = Vector3(0, 0.5, 0)
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(1, 2.5))
	p.scale_amount_curve = c
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.9))
	g.set_color(1, Color(0.92, 0.96, 1.0, 0.0))
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(1.1, 1.1)
	q.material = _puff_mat()
	p.mesh = q
	add_child(p)
	return p


func _puff_mat() -> StandardMaterial3D:
	# Clean bright vapour: unshaded so it never reads as dark smoke against the sky.
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_tex
	m.roughness = 1.0
	m.disable_receive_shadows = true
	return m


func _radial() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.45, Color(1, 1, 1, 0.6))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _gloss(c: Color, rough: float, metal: float, coat: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if coat > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = coat
		m.clearcoat_roughness = 0.1
	return m


func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot
	parent.add_child(m)
	return m


func _rod(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var m := _mi(parent, ProcMesh.cyl(r, r, a.distance_to(b), 10), mat, (a + b) * 0.5)
	var up: Vector3 = (b - a).normalized()
	var side: Vector3 = up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	m.basis = Basis(side, up, side.cross(up)).orthonormalized()
	return m
