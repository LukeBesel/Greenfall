class_name LaunchPad
extends Node3D
## [ship] The base's landing pad (comes with a level 5 base) for Lumi's ship (ShipModel): a low,
## chamfered octagonal pearl deck on anti-grav emitters, a landing circle in thin cyan with
## tangerine corner chevrons, chasing rim lights, two rows of approach lights, docking locks that
## hold the gear and release for take-off, a boarding lift beside the cockpit with a light bridge,
## a compact service mast (beacon, floodlights, energy cells, an umbilical to the ship) and vents
## for steam and the VTOL downwash. The deck grows with the ship (ShipTiers.pad_scale).
## `construction` = true builds the level 4 placeholder: a hologram of the pad and the ship to come.
## Local frame: the Rocket node's (unrotated); the ship stands at the centre, nose along `ship_yaw`;
## the boarding lift is on its starboard side (toward the yard), the mast off its port side.

const TOP_Y: float = 0.6           # deck height: the ship's gear stands here
const R0: float = 4.7              # deck radius at pad scale 1
const TOWER_Z: float = -5.6        # legacy; the mast now stands off the ship's port side

var construction: bool = false
## In-planet rocket tier (kept for callers); the look (1..7) decides the size.
var rocket_tier: int = 1
var look: int = -1                 # -1: ShipTiers.look()
var ship_yaw: float = Rocket.PARK_YAW
var gangway: Node3D
var lift: Node3D
var _r: float = R0
var _locks: Array[Node3D] = []
var _lock_mats: Array[StandardMaterial3D] = []
var _hoses: Array[Node3D] = []
var _beacons: Array[StandardMaterial3D] = []
var _spin: SpotLight3D
var _spin_head: Node3D
var _vents: Array[CPUParticles3D] = []
var _steam: Array[CPUParticles3D] = []
var _chase_mat: ShaderMaterial
var _approach_mat: ShaderMaterial
var _cell_strips: Array[Node3D] = []
var _alarm: bool = false
var _t: float = 0.0

const CHASE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 col : source_color = vec4(0.3, 0.88, 1.0, 1.0);
uniform float speed = 0.35;
uniform float energy = 1.6;
uniform float dashes = 24.0;
void fragment() {
	float a = UV.x * dashes;
	float dash = smoothstep(0.15, 0.3, fract(a)) * smoothstep(0.85, 0.7, fract(a));
	float run = pow(fract(UV.x * 3.0 - TIME * speed), 6.0);
	ALBEDO = col.rgb * energy * dash * (0.25 + 2.5 * run);
}
"""


func _ready() -> void:
	if look < 0:
		look = ShipTiers.look()
	_r = R0 * ShipTiers.pad_scale(look)
	if construction:
		_build_hologram()
	else:
		_build()


## Ship-frame direction (nose = +Z) turned into the pad frame.
func _dir(v: Vector3) -> Vector3:
	return Basis(Vector3.UP, ship_yaw) * v


func _ship_scale() -> float:
	return ShipTiers.scale_of(look)


func _build() -> void:
	var white := _gloss(Color(0.93, 0.94, 0.95), 0.28, 0.08, 0.7)
	var grey := _gloss(Color(0.55, 0.58, 0.62), 0.3, 0.7, 0.3)
	var dark := _gloss(Color(0.06, 0.07, 0.085), 0.2, 0.4, 0.8)
	var tang := _gloss(ShipModel.ACCENT, 0.25, 0.1, 0.8)
	var glow := Mats.lamp(ShipModel.GLOW, 1.4)  # thin, subtle accent lines
	var r: float = _r
	# Deck: a chamfered octagon (lathe with 8 sides), a dark inlay band and a pearl centre.
	var prof := PackedVector2Array([Vector2(r * 0.55, TOP_Y - 0.42), Vector2(r * 0.94, TOP_Y - 0.42), Vector2(r, TOP_Y - 0.16),
		Vector2(r, TOP_Y - 0.05), Vector2(r - 0.05, TOP_Y), Vector2(0.0, TOP_Y)])
	var deck := _mi(self, RocketModel.lathe(prof, 8, PI / 8.0, PI / 8.0 + TAU), white, Vector3.ZERO)
	deck.set_meta("deck", true)
	var inlay := _mi(self, ProcMesh.cyl(r * 0.9, r * 0.9, 0.012, 8), dark, Vector3(0, TOP_Y + 0.004, 0))
	inlay.rotation.y = PI / 8.0
	var centre := _mi(self, ProcMesh.cyl(r * 0.8, r * 0.8, 0.014, 8), white, Vector3(0, TOP_Y + 0.008, 0))
	centre.rotation.y = PI / 8.0
	# Landing circle: two hairline cyan rings, tangerine corner chevrons, a few tick marks.
	_mi(self, ProcMesh.torus(r * 0.62, r * 0.62 + 0.035, 64, 3), glow, Vector3(0, TOP_Y + 0.02, 0))
	_mi(self, ProcMesh.torus(r * 0.3, r * 0.3 + 0.025, 48, 3), glow, Vector3(0, TOP_Y + 0.02, 0))
	for k: int in 4:
		var a: float = TAU * (k + 0.5) / 4.0
		var p := Vector3(cos(a), 0, sin(a)) * r * 0.72 + Vector3(0, TOP_Y + 0.018, 0)
		for s: float in [-1.0, 1.0]:
			var ch := _mi(self, ProcMesh.box(Vector3(0.12, 0.012, 0.7)), tang, p)
			ch.rotation.y = -a + s * 0.6
	for k2: int in 16:
		var a2: float = TAU * k2 / 16.0
		_mi(self, ProcMesh.box(Vector3(0.36, 0.01, 0.05)), dark, Vector3(cos(a2), 0, sin(a2)) * r * 0.46 + Vector3(0, TOP_Y + 0.018, 0), Vector3(0, -rad_to_deg(a2), 0))
	# Chasing guide lights around the rim.
	_chase_mat = _chase()
	var rim := _mi(self, ProcMesh.torus(r * 0.86, r * 0.86 + 0.04, 72, 3), _chase_mat, Vector3(0, TOP_Y + 0.02, 0))
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Approach lights: two short rows of studs off the deck edge along the take-off heading.
	_approach_mat = _chase()
	_approach_mat.set_shader_parameter("dashes", 6.0)
	for s2: float in [-1.0, 1.0]:
		for k3: int in 6:
			var p2: Vector3 = _dir(Vector3(s2 * 1.4 * _ship_scale(), 0, r + 0.6 + k3 * 0.9))
			_mi(self, ProcMesh.cyl(0.14, 0.18, 0.12, 12), white, p2 + Vector3(0, 0.06, 0))
			var stud := _mi(self, ProcMesh.cyl(0.08, 0.08, 0.02, 12), Mats.lamp(ShipModel.GLOW, 1.2 + 0.3 * k3), p2 + Vector3(0, 0.13, 0))
			stud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var num := Label3D.new()
	num.text = tr("PAD 01")
	num.font_size = 96
	num.pixel_size = 0.006
	num.modulate = Color(0.5, 1.5, 2.0)
	num.shaded = false
	num.rotation_degrees = Vector3(-90, 0, 0)
	num.position = Vector3(0, TOP_Y + 0.03, r * 0.72)
	add_child(num)
	# Anti-grav emitters under the deck with light beams to ground plates.
	for k4: int in 4:
		var a3: float = TAU * k4 / 4.0 + PI / 4.0
		var p3 := Vector3(cos(a3), 0, sin(a3)) * r * 0.72
		_mi(self, ProcMesh.cyl(0.34, 0.24, 0.16, 16), white, p3 + Vector3(0, TOP_Y - 0.48, 0))
		_mi(self, ProcMesh.torus(0.22, 0.24, 20, 3), glow, p3 + Vector3(0, TOP_Y - 0.57, 0))
		var beam := _mi(self, ProcMesh.cyl(0.2, 0.32, TOP_Y - 0.56, 12), RocketModel._additive(Color(0.25, 0.8, 1.0, 0.2)), p3 + Vector3(0, (TOP_Y - 0.56) * 0.5, 0))
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Docking locks: a pair of deck clamps beside each gear foot; they slide out for take-off.
	var sc: float = _ship_scale()
	var feet: Array[Vector3] = [Vector3(0, 0, 2.0 + ShipModel.front_shift(look)), Vector3(1.35, 0, -1.55), Vector3(-1.35, 0, -1.55)]
	if look < 4:  # skids: lock the rails' ends
		feet = [Vector3(0.67, 0, 0.6), Vector3(-0.67, 0, 0.6), Vector3(0.67, 0, -1.3), Vector3(-0.67, 0, -1.3)]
	for f: Vector3 in feet:
		var fp: Vector3 = _dir(f * sc)
		var piv := Node3D.new()
		piv.position = fp + Vector3(0, TOP_Y, 0)
		piv.rotation.y = ship_yaw
		add_child(piv)
		for s3: float in [-1.0, 1.0]:
			var claw := Node3D.new()
			claw.set_meta("side", s3)
			piv.add_child(claw)
			_mi(claw, RobotVisual._rbox(Vector3(0.14, 0.12, 0.34), 0.03, 2), grey, Vector3(0, 0.06, 0))
			var lm: StandardMaterial3D = Mats.lamp(ShipModel.ACCENT, 1.6)
			_lock_mats.append(lm)
			_mi(claw, ProcMesh.box(Vector3(0.02, 0.03, 0.24)), lm, Vector3(-s3 * 0.072, 0.09, 0))
			_locks.append(claw)
	set_clamps(0.0)
	# Service mast behind the pad: beacon, floodlights, energy cells and the umbilical.
	# The mast stands off the port side (away from the yard), facing the ship (+Z local).
	var mast := Node3D.new()
	mast.name = "Mast"
	mast.position = _dir(Vector3(r + 1.0, 0, -0.6))
	mast.rotation.y = ship_yaw - PI * 0.5
	add_child(mast)
	var tz := Vector3.ZERO
	_mi(mast, ProcMesh.cyl(0.7, 0.8, 0.2, 8), grey, tz + Vector3(0, 0.1, 0))
	_mi(mast, RobotVisual._rbox(Vector3(0.7, 4.2, 0.7), 0.12, 3), white, tz + Vector3(0, 2.2, 0))
	for x: float in [-0.25, 0.25]:
		_mi(mast, ProcMesh.box(Vector3(0.015, 3.6, 0.015)), glow, tz + Vector3(x, 2.2, 0.36))
	for y: float in [1.4, 3.0]:
		_mi(mast, ProcMesh.box(Vector3(0.74, 0.4, 0.74)), dark, tz + Vector3(0, y, 0))
		_mi(mast, ProcMesh.box(Vector3(0.76, 0.04, 0.76)), tang, tz + Vector3(0, y - 0.24, 0))
	var top_y: float = 4.4
	_mi(mast, ProcMesh.cyl(0.32, 0.45, 0.2, 16), grey, tz + Vector3(0, top_y, 0))
	_beacon(mast, tz + Vector3(0, top_y + 0.22, 0), 0.16)
	_spin_head = Node3D.new()
	_spin_head.position = tz + Vector3(0, top_y + 0.22, 0)
	mast.add_child(_spin_head)
	_spin = SpotLight3D.new()
	_spin.light_color = Color(1.0, 0.5, 0.15)
	_spin.light_energy = 0.0
	_spin.spot_range = 20.0
	_spin.spot_angle = 18.0
	_spin.rotation_degrees = Vector3(-12, 0, 0)
	_spin_head.add_child(_spin)
	for x2: float in [-1.0, 1.0]:
		var head := Node3D.new()
		head.position = tz + Vector3(x2 * 0.5, 3.9, 0.3)
		mast.add_child(head)
		head.look_at(global_position + Vector3(0, TOP_Y + 1.0, 0), Vector3.UP)
		_mi(head, RobotVisual._rbox(Vector3(0.5, 0.28, 0.24), 0.05, 2), white, Vector3.ZERO)
		_mi(head, ProcMesh.box(Vector3(0.42, 0.2, 0.02)), Mats.lamp(Color(0.85, 0.95, 1.0), 4.0), Vector3(0, 0, -0.13))
		var sl := SpotLight3D.new()
		sl.light_energy = 2.0
		sl.light_color = Color(0.85, 0.95, 1.0)
		sl.spot_range = 14.0
		sl.spot_angle = 30.0
		head.add_child(sl)
	for x3: float in [-1.7, 1.7]:
		var cp := tz + Vector3(x3, 0, -0.1)
		_mi(mast, ProcMesh.cyl(0.48, 0.55, 0.18, 16), grey, cp + Vector3(0, 0.09, 0))
		_mi(mast, ProcMesh.capsule(0.42, 1.8), white, cp + Vector3(0, 1.08, 0))
		_mi(mast, ProcMesh.cyl(0.44, 0.44, 0.1, 20), tang, cp + Vector3(0, 1.5, 0))
		var strip := Node3D.new()
		strip.position = cp + Vector3(0, 0.4, 0.42)
		mast.add_child(strip)
		_mi(strip, ProcMesh.box(Vector3(0.04, 1.2, 0.03)), glow, Vector3(0, 0.6, 0))
		_cell_strips.append(strip)
		_beacon(mast, cp + Vector3(0, 2.05, 0), 0.09)
	# Umbilical: a hose from the mast to the ship's flank; it drops away before take-off.
	var flank: Vector3 = _dir(Vector3(0.9, 1.1, -1.0) * sc) + Vector3(0, TOP_Y, 0)
	var piv2 := Node3D.new()
	piv2.position = mast.position + Basis(Vector3.UP, mast.rotation.y) * Vector3(0.25, 1.0, 0.36)
	add_child(piv2)
	var end: Vector3 = flank - piv2.position
	var prev := Vector3.ZERO
	for s4: int in 8:
		var u: float = float(s4 + 1) / 8.0
		var p4: Vector3 = Vector3.ZERO.lerp(end, u) + Vector3(0, -sin(u * PI) * 0.5, 0)
		_rod(piv2, prev, p4, 0.06, Mats.rubber(Color(0.12, 0.13, 0.15)))
		prev = p4
	_mi(piv2, ProcMesh.sphere(0.1, 12, 6), Mats.lamp(ShipModel.ACCENT, 2.5), end)
	_hoses.append(piv2)
	# Boarding lift beside the cockpit (port side) and a light bridge to the canopy sill.
	var seat: Vector3 = ShipModel.seat(look) * sc
	lift = Node3D.new()
	lift.position = _dir(Vector3(-1.9 * sc, 0, seat.z)) + Vector3(0, TOP_Y + 0.02, 0)
	add_child(lift)
	_mi(lift, ProcMesh.cyl(0.42, 0.46, 0.08, 24), white, Vector3.ZERO)
	_mi(lift, ProcMesh.torus(0.4, 0.425, 24, 3), glow, Vector3(0, 0.045, 0))
	gangway = Node3D.new()
	gangway.position = lift.position + Vector3(0, seat.y - 0.1 - TOP_Y, 0)
	gangway.rotation.y = ship_yaw + PI * 0.5
	add_child(gangway)
	var reach: float = 1.9 * sc - 0.55 * sc
	var bridge := _mi(gangway, ProcMesh.box(Vector3(0.6, 0.02, reach)), RocketModel._additive(Color(0.3, 0.85, 1.0, 0.35)), Vector3(0, 0, reach * 0.5))
	bridge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for x4: float in [-0.3, 0.3]:
		_mi(gangway, ProcMesh.box(Vector3(0.015, 0.015, reach)), glow, Vector3(x4, 0.02, reach * 0.5))
	set_gangway(1.0)
	# The pad sign on the mast.
	var sign_l := Label3D.new()
	sign_l.text = tr("LANDING PAD")
	sign_l.font_size = 80
	sign_l.pixel_size = 0.006
	sign_l.modulate = Color(0.5, 1.5, 2.0, 0.9)
	sign_l.shaded = false
	sign_l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sign_l.position = mast.position + Vector3(0, top_y + 0.9, 0)
	add_child(sign_l)
	# Vapour: the VTOL downwash spreading off the deck, a ground ring from under it, steam vents.
	for k5: int in 4:
		var a5: float = TAU * k5 / 4.0
		var v := _vapour(Vector3(cos(a5), 0.05, sin(a5)), 8, 3.4)
		v.position = Vector3(cos(a5), 0, sin(a5)) * r * 0.85 + Vector3(0, TOP_Y + 0.1, 0)
		_vents.append(v)
	var ground := _vapour(Vector3(1, 0, 0), 18, 4.2)
	ground.position = Vector3(0, 0.3, 0)
	ground.spread = 180.0
	ground.flatness = 0.92
	ground.gravity = Vector3(0, 0.15, 0)
	_vents.append(ground)
	for k6: int in 4:
		var a6: float = TAU * (k6 + 0.5) / 4.0
		var s2 := _steam_vent()
		s2.position = Vector3(cos(a6), 0, sin(a6)) * r * 0.93 + Vector3(0, TOP_Y + 0.05, 0)
		s2.direction = Vector3(cos(a6) * 0.3, 1, sin(a6) * 0.3)
		_steam.append(s2)


func _chase() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = CHASE_SHADER
	m.shader = sh
	return m


## Kept for callers: the ship's scale on this pad.
func _rocket_scale() -> float:
	return _ship_scale()


## The level 4 placeholder: a hologram of the coming pad and ship.
func _build_hologram() -> void:
	var holo := RocketModel._additive(Color(0.25, 0.8, 1.0, 0.16))
	var line := RocketModel._additive(Color(0.35, 0.9, 1.0, 0.7))
	var d := _mi(self, ProcMesh.cyl(_r, _r, 0.04, 8), holo, Vector3(0, TOP_Y, 0))
	d.rotation.y = PI / 8.0
	for rr: float in [_r, _r * 0.62, _r * 0.3]:
		_mi(self, ProcMesh.torus(rr - 0.03, rr + 0.03, 48, 3), line, Vector3(0, TOP_Y, 0))
	var ghost := ShipModel.new()
	add_child(ghost)
	ghost.build(look)
	ghost.position = Vector3(0, TOP_Y, 0)
	ghost.rotation.y = ship_yaw
	ghost.scale = Vector3.ONE * _ship_scale()
	for n: Node in ghost.find_children("*", "", true, false):
		if n is GeometryInstance3D:
			var gi: GeometryInstance3D = n
			gi.material_override = holo
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if n is Label3D or n is RocketPlume:
			(n as Node3D).visible = false
	var sign_l := Label3D.new()
	sign_l.text = tr("LANDING PAD\nBASE LEVEL 5")
	sign_l.font_size = 80
	sign_l.pixel_size = 0.008
	sign_l.modulate = Color(0.5, 1.5, 2.0, 0.9)
	sign_l.shaded = false
	sign_l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sign_l.position = Vector3(0, TOP_Y + 4.0, 0)
	add_child(sign_l)


## Deck radius (local).
func radius() -> float:
	return _r


# --- Sequence hooks (driven by Rocket) ---------------------------------------------------

func set_alarm(on: bool) -> void:
	_alarm = on
	if _spin:
		_spin.light_energy = 6.0 if on else 0.0


func vent_steam(on: bool) -> void:
	for s: CPUParticles3D in _steam:
		s.emitting = on


func billow(on: bool) -> void:
	for v: CPUParticles3D in _vents:
		v.emitting = on


## 0..1: umbilical dropped away (it swings down on its mast pivot).
func set_hoses(k: float) -> void:
	for h: Node3D in _hoses:
		h.rotation.x = k * 0.9
		h.visible = k < 0.98


## 0..1: light bridge retracted into the lift (0 = reaching the canopy sill).
func set_gangway(k: float) -> void:
	if gangway:
		gangway.scale = Vector3(1, 1, maxf(0.01, 1.0 - k))
		gangway.visible = k < 0.99


## 0..1: docking locks released (they slide out from the gear and dim).
func set_clamps(k: float) -> void:
	for c: Node3D in _locks:
		c.position = Vector3(float(c.get_meta("side")) * (0.2 + k * 0.3), 0, 0)
	for m: StandardMaterial3D in _lock_mats:
		m.emission = ShipModel.ACCENT if k < 0.5 else ShipModel.GLOW
		m.emission_energy_multiplier = lerpf(2.0, 0.6, k)


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
		_chase_mat.set_shader_parameter("col", Color(1.0, 0.45, 0.15) if _alarm and blink else ShipModel.GLOW)
	if _approach_mat:
		_approach_mat.set_shader_parameter("speed", 1.2 if _alarm else 0.3)


# --- Helpers ---------------------------------------------------------------------------

func _beacon(parent: Node3D, p: Vector3, r: float) -> void:
	var m: StandardMaterial3D = Mats.lamp(Color(1.0, 0.45, 0.12), 2.0)
	_beacons.append(m)
	_mi(parent, ProcMesh.sphere(r, 12, 6), m, p)


## Soft billows: few, large, slow-growing puffs that erode into wisps (art/shaders/vapour_puff.gdshader).
func _vapour(dir: Vector3, amount: int, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = amount
	p.lifetime = 4.0
	p.local_coords = false
	p.direction = dir
	p.spread = 22.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 9.0
	p.damping_min = 2.4
	p.damping_max = 3.2
	p.gravity = Vector3(0, 0.45, 0)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.25
	p.scale_amount_curve = _grow_curve(0.45, 1.3, 1.9)
	p.color_ramp = _fade_ramp(0.6)
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = vapour_material()
	p.mesh = q
	add_child(p)
	return p


func _steam_vent() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 10
	p.lifetime = 2.2
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 18.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.damping_min = 1.2
	p.damping_max = 2.0
	p.gravity = Vector3(0, 0.4, 0)
	p.scale_amount_curve = _grow_curve(0.35, 1.2, 2.0)
	p.color_ramp = _fade_ramp(0.5)
	var q := QuadMesh.new()
	q.size = Vector2(1.3, 1.3)
	q.material = vapour_material()
	p.mesh = q
	add_child(p)
	return p


static func _grow_curve(a: float, b: float, c: float) -> Curve:
	var cv := Curve.new()
	cv.max_value = 6.0  # scale grows past 1 (the default range clamps it)
	cv.add_point(Vector2(0, a))
	cv.add_point(Vector2(0.35, b))
	cv.add_point(Vector2(1, c))
	return cv


## Fades in fast, holds, fades out (the shader's erosion does most of the breaking up).
static func _fade_ramp(peak: float) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.add_point(0.08, Color(1, 1, 1, peak))
	g.add_point(0.6, Color(1, 1, 1, peak * 0.7))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0.0))
	return g


static var _vapour_mat: ShaderMaterial


## Shared vapour material (also used by the ship's trail).
static func vapour_material() -> ShaderMaterial:
	if _vapour_mat == null:
		var nz := FastNoiseLite.new()
		nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		nz.frequency = 0.02
		nz.fractal_octaves = 4
		nz.fractal_gain = 0.55
		var tex := NoiseTexture2D.new()
		tex.width = 128
		tex.height = 128
		tex.seamless = true
		tex.normalize = true
		tex.generate_mipmaps = true
		tex.noise = nz
		_vapour_mat = ShaderMaterial.new()
		_vapour_mat.shader = preload("res://art/shaders/vapour_puff.gdshader")
		_vapour_mat.set_shader_parameter("noise_tex", tex)
	return _vapour_mat


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
