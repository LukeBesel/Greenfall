class_name PickupFx
extends Node3D
## Patch's pickup show, fully pooled. Each pickup runs through:
##   lock     a cyan reticle snaps onto the piece on the ground, the eyes flash, twin lasers
##            (right claw + left claw) shoot out and converge on it;
##   lift     the piece rises with a spin and a wobble inside the tractor cone, a fresnel rim
##            glows on it and small electric arcs crawl over its surface;
##   compress it squashes down and goes white-hot;
##   stream   it bursts into light motes that spiral into the chest hopper, which pops with light.
## Everything is drawn from a fixed pool of flyer meshes plus ONE ImmediateMesh (lasers, arcs,
## motes, glows and reticles in a single additive draw), so a pickup allocates no nodes.
## Big pieces get a heavier, slower variant (more arcs and motes, a camera micro-shake).

const POOL: int = 12
const ARC_PTS: int = 6
const MAX_ARCS: int = 4
const MAX_MOTES: int = 14
const POP_TIME: float = 0.14
const CYAN := Color(0.35, 0.9, 1.0)

var model: PatchModel

var _slots: Array[Slot] = []
var _seq: int = 0
var _im: ImmediateMesh
var _im_node: MeshInstance3D
var _rng := RandomNumberGenerator.new()
var _cam_pos := Vector3.ZERO
var _cam_right := Vector3.RIGHT
var _cam_up := Vector3.UP
var _low: bool = false
var _hum: float = 0.0
var _snd_cool: Dictionary = {"blip": 0.0, "sparkle": 0.0, "whoosh": 0.0, "pop": 0.0, "servo": 0.0}
var _verts: int = 0
var _beam_on: bool = false


class Slot:
	var active: bool = false
	var t: float = 0.0
	var dur: float = 0.4
	var big: bool = false
	var seq: int = 0
	var start := Vector3.ZERO
	var start_basis := Basis.IDENTITY
	var radius: float = 0.15
	var tint := Color.WHITE
	var spin := Vector3.ZERO
	var phase: float = 0.0
	var pos := Vector3.ZERO
	var burst_pos := Vector3.ZERO
	var flyer: MeshInstance3D
	var mat: ShaderMaterial
	var arcs := PackedVector3Array()  # offsets from pos, MAX_ARCS * ARC_PTS
	var arc_count: int = 2
	var arc_t: float = 0.0
	var popped: bool = false
	var streamed: bool = false


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_rng.randomize()
	var glow_shader: Shader = preload("res://art/shaders/pickup_glow.gdshader")
	for i: int in POOL:
		var s := Slot.new()
		s.flyer = MeshInstance3D.new()
		s.flyer.visible = false
		s.flyer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.mat = ShaderMaterial.new()
		s.mat.shader = glow_shader
		s.mat.set_shader_parameter("seed", float(i) * 1.7)
		s.flyer.material_overlay = s.mat
		add_child(s.flyer)
		s.arcs.resize(MAX_ARCS * ARC_PTS)
		_slots.append(s)
	_im = ImmediateMesh.new()
	_im_node = MeshInstance3D.new()
	_im_node.mesh = _im
	var m := ShaderMaterial.new()
	m.shader = preload("res://art/shaders/pickup_fx.gdshader")
	_im_node.material_override = m
	_im_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The batch spans the whole scene around Patch; never let it be frustum-culled.
	_im_node.custom_aabb = AABB(Vector3(-1e4, -1e3, -1e4), Vector3(2e4, 2e3, 2e4))
	add_child(_im_node)


## Starts the show for one piece. `dur` must match the gameplay arrival timer.
func launch(mesh: Mesh, xf: Transform3D, dur: float, big: bool, tint: Color) -> void:
	var s: Slot = _free_slot()
	_seq += 1
	_low = Settings.quality <= 0
	s.active = true
	s.t = 0.0
	s.dur = dur
	s.big = big
	s.seq = _seq
	s.start = xf.origin
	s.start_basis = xf.basis
	s.pos = xf.origin
	s.burst_pos = xf.origin
	s.tint = tint
	s.popped = false
	s.streamed = false
	s.phase = _rng.randf() * TAU
	s.spin = Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(5.0, 8.0) * (1.0 if _rng.randf() < 0.5 else -1.0), _rng.randf_range(-1.5, 1.5))
	var sc: Vector3 = xf.basis.get_scale()
	s.radius = clampf(mesh.get_aabb().size.length() * 0.5 * maxf(sc.x, maxf(sc.y, sc.z)), 0.06, 0.6) if mesh else 0.15
	s.arc_count = 0  # clean look: no crawling arcs
	s.arc_t = 0.0
	s.flyer.mesh = mesh
	s.flyer.global_transform = xf
	s.flyer.visible = true
	s.mat.set_shader_parameter("amount", 0.0)
	s.mat.set_shader_parameter("heat", 0.0)
	_regen_arcs(s)
	if model:
		model.eye_flash(0.6 if big else 0.35)
	_sfx("blip", (1.5 if big else 2.1) + _rng.randf_range(-0.15, 0.15), -15.0, 0.07)
	_sfx("servo", (1.2 if big else 1.8) + _rng.randf_range(-0.1, 0.1), -19.0, 0.12)
	if big:
		EventBus.shake_requested.emit(0.05)
		Audio.play("hydraulic", 1.6, -16.0)


func _free_slot() -> Slot:
	var oldest: Slot = _slots[0]
	for s: Slot in _slots:
		if not s.active:
			return s
		if s.seq < oldest.seq:
			oldest = s
	_finish(oldest)
	return oldest


func _finish(s: Slot) -> void:
	s.active = false
	s.flyer.visible = false
	s.flyer.mesh = null


func active_count() -> int:
	var n: int = 0
	for s: Slot in _slots:
		if s.active:
			n += 1
	return n


func _sfx(sound: String, pitch: float, db: float, cool: float) -> void:
	if float(_snd_cool.get(sound, 0.0)) > 0.0:
		return
	_snd_cool[sound] = cool
	Audio.play(sound, pitch, db, 0.06)


func _process(delta: float) -> void:
	for k: String in _snd_cool:
		_snd_cool[k] = maxf(0.0, float(_snd_cool[k]) - delta)
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam:
		_cam_pos = cam.global_position
		_cam_right = cam.global_basis.x
		_cam_up = cam.global_basis.y
	var newest: Slot = null
	var any: bool = false
	for s: Slot in _slots:
		if not s.active:
			continue
		any = true
		s.t += delta
		if s.t >= s.dur + POP_TIME:
			_finish(s)
			continue
		_animate(s, delta)
		if s.t < s.dur * 0.62 and (newest == null or s.seq > newest.seq):
			newest = s
	if model and (newest or _beam_on):
		@warning_ignore("incompatible_ternary")
		model.beam_at(newest.pos if newest else null, newest.big if newest else false)
	_beam_on = newest != null
	# Soft continuous hum while anything is in the beam.
	_hum = move_toward(_hum, 1.0 if newest else 0.0, delta * (6.0 if newest else 3.0))
	Audio.loop("beam_hum", _hum)
	_im.clear_surfaces()
	if not any or cam == null:
		return
	_verts = 0
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for s: Slot in _slots:
		if s.active:
			_draw_slot(s)
	if _verts == 0:
		# A surface needs at least one triangle; emit an invisible one.
		_sprite(_cam_pos + Vector3(0, -1000, 0), 0.0, Color(0, 0, 0, 0))
	_im.surface_end()


func _animate(s: Slot, delta: float) -> void:
	var u: float = s.t / s.dur
	var lift_h: float = 0.5 if s.big else 0.36
	var chest: Vector3 = model.chest_world() if model else s.start
	# Lift: hold on the ground for the lock, then rise with an overshoot, drifting toward Patch.
	var lu: float = clampf((u - 0.12) / 0.4, 0.0, 1.0)
	var rise: float = 1.0 - pow(1.0 - lu, 3.0)
	rise += sin(lu * PI) * 0.05
	var wob: Vector3 = Vector3.ZERO
	var lifted: Vector3 = s.start + Vector3(0, lift_h * rise, 0) + wob
	# Like the concept: the piece is drawn up into the open claw and floats right at the palm.
	var hold: Vector3 = s.pos
	if model:
		var claw: Vector3 = model.claw_point()
		var out: Vector3 = (claw - chest)
		out.y = 0.0
		out = out.normalized() if out.length() > 0.01 else Vector3.FORWARD
		hold = claw + out * (0.2 + minf(s.radius, 0.3) * 0.6) + Vector3(0, 0.04 + sin(s.t * 3.0 + s.phase) * 0.01, 0)
	var pull: float = smoothstep(0.18, 0.55, u)
	var hover: Vector3 = lifted.lerp(hold, pull * pull * (3.0 - 2.0 * pull))
	# Compress: squash into a hot bead and slide a little toward the chest.
	var cu: float = clampf((u - 0.6) / 0.34, 0.0, 1.0)
	var ce: float = cu * cu * (3.0 - 2.0 * cu)
	s.pos = hover.lerp(chest, ce)
	if not s.streamed:
		s.burst_pos = s.pos
	var spin_t: float = s.t * (0.6 if s.big else 1.0)
	var b: Basis = Basis.from_euler(s.spin * 0.12 * spin_t * smoothstep(0.08, 0.4, u))
	var squash: Vector3 = Vector3.ONE * lerpf(1.0, 0.12, smoothstep(0.2, 1.0, cu))
	var pulse: float = 1.0
	s.flyer.global_transform = Transform3D(b * s.start_basis, s.pos)
	s.flyer.scale *= squash * pulse
	s.flyer.visible = u < 0.96
	s.mat.set_shader_parameter("amount", smoothstep(0.0, 0.12, u) * (1.0 + 0.6 * cu))
	s.mat.set_shader_parameter("heat", 0.0)
	# Arcs re-strike every few frames.
	s.arc_t -= delta
	if s.arc_t <= 0.0:
		s.arc_t = 0.05 if s.big else 0.04
		_regen_arcs(s)
	if not s.streamed and u >= 0.68:
		s.streamed = true
		_sfx("sparkle", (1.1 if s.big else 1.5) + _rng.randf_range(-0.2, 0.2), -20.0, 0.1)
		_sfx("whoosh", (1.3 if s.big else 2.2) + _rng.randf_range(-0.2, 0.2), -21.0, 0.1)
	if not s.popped and u >= 0.97:
		s.popped = true
		if model:
			model.hopper_pulse(1.0 if s.big else 0.6)
		_sfx("pop", (1.2 if s.big else 1.7) + _rng.randf_range(-0.15, 0.15), -17.0, 0.07)


## Electric arcs: jagged strokes that start and end on the piece's surface.
func _regen_arcs(s: Slot) -> void:
	var r: float = s.radius
	for a: int in s.arc_count:
		var d0: Vector3 = _rand_dir()
		var d1: Vector3 = (d0 + _rand_dir() * 1.3).normalized()
		for i: int in ARC_PTS:
			var f: float = float(i) / (ARC_PTS - 1)
			var d: Vector3 = d0.slerp(d1, f) if d0.dot(d1) > -0.99 else d0
			var jitter: float = 0.0 if (i == 0 or i == ARC_PTS - 1) else _rng.randf_range(0.0, 0.35)
			s.arcs[a * ARC_PTS + i] = d * r * (0.85 + jitter) + _rand_dir() * r * 0.12 * jitter


func _rand_dir() -> Vector3:
	return Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()


func _draw_slot(s: Slot) -> void:
	var u: float = s.t / s.dur
	var glow: Color = CYAN
	# Reticle on the ground: snaps in from 1.9x in ~0.07 s, spins, then fades as the piece leaves.
	var ret_in: float = clampf(s.t / 0.07, 0.0, 1.0)
	var ret_a: float = ret_in * (1.0 - smoothstep(0.3, 0.5, u))
	if ret_a > 0.01:
		var snap: float = lerpf(1.9, 1.0, 1.0 - pow(1.0 - ret_in, 3.0))
		var size: float = (minf(s.radius, 0.45) * 1.3 + 0.1) * snap
		var flash: float = 1.0 + 1.5 * (1.0 - smoothstep(0.0, 0.12, s.t))
		_flat(s.start + Vector3(0, 0.03, 0), size, Color(glow, 0.6 * ret_a * minf(flash, 1.4)), s.t * 1.2 + s.phase)
	# Palm beam (concept style): a fan of fine light rays from the open claw to the piece, with
	# sparkle dust flowing back into the palm.
	var las: float = 1.0 - smoothstep(0.62, 0.8, u)
	if las > 0.01 and model:
		var reach: float = 1.0 - pow(1.0 - clampf(s.t / 0.06, 0.0, 1.0), 2.0)
		var flick: float = 0.93 + 0.07 * sin(s.t * 9.0 + s.phase)
		var claw: Vector3 = model.claw_point()
		var tgt: Vector3 = claw.lerp(s.pos, reach)
		var axis: Vector3 = tgt - claw
		var side: Vector3 = axis.cross(Vector3.UP)
		side = side.normalized() if side.length() > 0.001 else Vector3.RIGHT
		var upv: Vector3 = side.cross(axis).normalized()
		var spread: float = minf(s.radius, 0.3) * 0.9 + 0.05
		var rays: int = 3
		for i: int in rays:
			# Fixed fan (no spinning): rays leave the palm close together and land evenly on the piece.
			var ang: float = TAU * float(i) / rays + PI * 0.5
			var off: Vector3 = side * cos(ang) + upv * sin(ang)
			var start: Vector3 = claw + off * 0.025
			var end: Vector3 = tgt + off * spread * 0.4
			_ribbon(start, end, 0.012, Color(CYAN, 0.3 * las * flick))
			_ribbon(start, end, 0.0045, Color(0.92, 1.0, 1.0, 1.0 * las * flick))
		var dust: int = 0
		for i: int in dust:
			var f: float = fmod(float(i) / dust + s.t * 2.6 + s.phase, 1.0)
			var ang2: float = float(i) * 2.39996 + s.t * 5.0
			var pp: Vector3 = tgt.lerp(claw, f) + (side * cos(ang2) + upv * sin(ang2)) * spread * (1.0 - f) * 0.9
			_sprite(pp, 0.025 + 0.02 * (1.0 - f), Color(glow.lerp(Color.WHITE, 0.4), 0.8 * las * sin(f * PI)))
		if reach >= 1.0:
			_sprite(s.pos, minf(s.radius, 0.3) * 1.0 + 0.06, Color(glow, 0.25 * las))
	# Arcs crawling over the piece while it is held.
	var arc_a: float = smoothstep(0.1, 0.2, u) * (1.0 - smoothstep(0.62, 0.7, u))
	if arc_a > 0.01:
		for a: int in s.arc_count:
			for i: int in ARC_PTS - 1:
				var p0: Vector3 = s.pos + s.arcs[a * ARC_PTS + i]
				var p1: Vector3 = s.pos + s.arcs[a * ARC_PTS + i + 1]
				_ribbon(p0, p1, 0.03, Color(0.55, 0.85, 1.0, 0.6 * arc_a))
				_ribbon(p0, p1, 0.008, Color(0.9, 1.0, 1.0, 1.0 * arc_a))
	# Compression flash: a hot bead where the piece collapses.
	var cu: float = clampf((u - 0.55) / 0.15, 0.0, 1.0) * (1.0 - smoothstep(0.72, 0.8, u))
	if false:
		_sprite(s.pos, (minf(s.radius, 0.3) * 0.6 + 0.05) * (1.0 + 0.6 * cu), Color(glow.lerp(Color.WHITE, 0.5), 0.8 * cu))
	# Light stream: motes spiral from the burst point into the chest hopper.
	if false and s.streamed and model:
		var chest: Vector3 = model.chest_world()
		@warning_ignore("integer_division")
		var n: int = (MAX_MOTES if s.big else 9) / (2 if _low else 1)
		var along: Vector3 = chest - s.burst_pos
		var side: Vector3 = along.cross(Vector3.UP)
		side = side.normalized() if side.length() > 0.001 else Vector3.RIGHT
		var up: Vector3 = side.cross(along).normalized()
		var span: float = s.dur * 0.32
		for i: int in n:
			var f: float = float(i) / n
			var mu: float = clampf((s.t - s.dur * 0.68 - f * s.dur * 0.08) / span, 0.0, 1.0)
			if mu <= 0.0 or mu >= 1.0:
				continue
			var e: float = mu * mu * (3.0 - 2.0 * mu)
			var ang: float = f * TAU + mu * (9.0 if s.big else 7.0) + s.phase
			var rad: float = (minf(s.radius, 0.3) * 0.9 + 0.05) * (1.0 - e) * (1.0 + 0.3 * sin(f * 13.0))
			var p: Vector3 = s.burst_pos.lerp(chest, e) + (side * cos(ang) + up * sin(ang)) * rad + Vector3(0, sin(mu * PI) * 0.12, 0)
			var col: Color = glow.lerp(s.tint, 0.25 + 0.3 * float(i % 3 == 0))
			var a: float = sin(mu * PI) * 0.4 + 0.6
			_sprite(p, 0.05 if i % 4 else 0.08, Color(col, a))
			# Short tail toward where it came from.
			var back: float = clampf(mu - 0.08, 0.0, 1.0)
			var eb: float = back * back * (3.0 - 2.0 * back)
			var angb: float = f * TAU + back * (9.0 if s.big else 7.0) + s.phase
			var pb: Vector3 = s.burst_pos.lerp(chest, eb) + (side * cos(angb) + up * sin(angb)) * (minf(s.radius, 0.3) * 0.9 + 0.05) * (1.0 - eb) * (1.0 + 0.3 * sin(f * 13.0)) + Vector3(0, sin(back * PI) * 0.12, 0)
			_ribbon(pb, p, 0.012, Color(col, 0.5 * a))
	# Soft pop of light on the chest panel.
	if s.popped and model:
		var pu: float = clampf((s.t - s.dur * 0.97) / POP_TIME, 0.0, 1.0)
		var pa: float = 1.0 - pu
		_sprite(model.chest_world(), (0.22 if s.big else 0.16) * (0.7 + pu * 0.8), Color(glow.lerp(Color.WHITE, 0.3), 0.85 * pa))


func _laser(e: Vector3, target: Vector3, reach: float, w: float, a: float) -> void:
	var hit: Vector3 = e.lerp(target, reach)
	_ribbon(e, hit, w * 5.0, Color(CYAN, 0.32 * a))
	_ribbon(e, hit, w, Color(0.85, 1.0, 1.0, 0.95 * a))
	_sprite(e, 0.07, Color(CYAN, 0.8 * a))


# --- Geometry helpers (one shared additive surface) ----------------------------------

func _v(p: Vector3, uv: Vector2, mode: float, ang: float, c: Color) -> void:
	_im.surface_set_color(c)
	_im.surface_set_uv(uv)
	_im.surface_set_uv2(Vector2(mode, ang))
	_im.surface_add_vertex(p)
	_verts += 1


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, mode: float, ang: float, uv_x: bool) -> void:
	# a-b-c-d counter-clockwise; ribbons pin UV.x at 0.5 so only the cross profile shows.
	var ua := Vector2(0.5, 0.0) if uv_x else Vector2(0, 0)
	var ub := Vector2(0.5, 0.0) if uv_x else Vector2(1, 0)
	var uc := Vector2(0.5, 1.0) if uv_x else Vector2(1, 1)
	var ud := Vector2(0.5, 1.0) if uv_x else Vector2(0, 1)
	_v(a, ua, mode, ang, col)
	_v(b, ub, mode, ang, col)
	_v(c, uc, mode, ang, col)
	_v(a, ua, mode, ang, col)
	_v(c, uc, mode, ang, col)
	_v(d, ud, mode, ang, col)


func _ribbon(a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var dir: Vector3 = b - a
	if dir.length_squared() < 1e-6:
		return
	var side: Vector3 = dir.cross(_cam_pos - (a + b) * 0.5)
	if side.length_squared() < 1e-8:
		return
	side = side.normalized() * w
	# Extend the ends by half a width so joints between arc segments overlap.
	var ext: Vector3 = dir.normalized() * w * 0.5
	_quad(a - ext - side, b + ext - side, b + ext + side, a - ext + side, col, 0.0, 0.0, true)


func _sprite(c: Vector3, size: float, col: Color) -> void:
	var r: Vector3 = _cam_right * size
	var u: Vector3 = _cam_up * size
	_quad(c - r - u, c + r - u, c + r + u, c - r + u, col, 0.0, 0.0, false)


func _flat(c: Vector3, size: float, col: Color, ang: float) -> void:
	var x := Vector3(size, 0, 0)
	var z := Vector3(0, 0, size)
	_quad(c - x - z, c + x - z, c + x + z, c - x + z, col, 1.0, ang, false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_EXIT_TREE:
		_hum = 0.0
		Audio.loop("beam_hum", 0.0)
