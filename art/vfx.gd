extends Node
## Pooled juice: one-shot particle bursts, floating numbers, expanding rings.
## CPUParticles3D everywhere so it works on Forward+, Mobile and Compatibility.

const POOL_PER_KIND: int = 6
const TEXT_POOL: int = 24

var _pools: Dictionary = {}  # kind -> Array[CPUParticles3D]
var _pool_idx: Dictionary = {}
var _texts: Array[Label3D] = []
var _text_idx: int = 0
var _soft_tex: GradientTexture2D
var _star_tex: GradientTexture2D
var _root: Node3D


func _ready() -> void:
	_root = Node3D.new()
	_root.name = "VfxRoot"
	add_child(_root)
	_soft_tex = _radial_texture(Color(1, 1, 1, 1), Color(1, 1, 1, 0), 0.0)
	_star_tex = _radial_texture(Color(1, 1, 1, 1), Color(1, 1, 1, 0), 0.55)
	for kind: String in ["dust", "sparkle", "steam", "confetti", "soil", "bits", "big_sparkle", "spark"]:  # [v7look] + spark
		_pools[kind] = []
		_pool_idx[kind] = 0
		for i: int in POOL_PER_KIND:
			var p: CPUParticles3D = _make(kind)
			_root.add_child(p)
			(_pools[kind] as Array).append(p)
	for i: int in TEXT_POOL:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = false
		l.pixel_size = 0.006
		l.font_size = 48
		l.outline_size = 8
		l.outline_modulate = Color(0.05, 0.05, 0.06, 0.7)
		l.visible = false
		l.render_priority = 10
		l.outline_render_priority = 9
		_root.add_child(l)
		_texts.append(l)


func _radial_texture(inner: Color, outer: Color, hard: float) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, inner)
	g.set_color(1, outer)
	if hard > 0.0:
		g.add_point(hard, Color(1, 1, 1, 0.9))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _quad_material(tex: Texture2D, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	# BILLBOARD_ENABLED + keep_scale rather than BILLBOARD_PARTICLES: particles that are not emitted yet
	# (one-shot bursts, explosiveness < 1) carry a zero scale, which the particle billboard ignores, so
	# they drew as a dark disc at the emitter. None of these effects use per-particle rotation.
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	return m


func _fade_ramp() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	return g


func _make(kind: String) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.9
	p.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(0.3, 0.3)
	p.mesh = q
	p.color_ramp = _fade_ramp()
	var curve := Curve.new()
	match kind:
		"dust":
			q.material = _quad_material(_soft_tex, false)
			p.amount = 10
			p.lifetime = 0.7
			p.direction = Vector3(0, 1, 0)
			p.spread = 70.0
			p.initial_velocity_min = 0.6
			p.initial_velocity_max = 1.6
			p.gravity = Vector3(0, 0.4, 0)
			p.damping_min = 2.0
			p.damping_max = 3.0
			p.scale_amount_min = 0.8
			p.scale_amount_max = 1.6
			curve.add_point(Vector2(0, 0.5))
			curve.add_point(Vector2(1, 1.6))
		"steam":
			q.material = _quad_material(_soft_tex, false)
			q.size = Vector2(0.45, 0.45)
			p.amount = 14
			p.lifetime = 1.0
			p.explosiveness = 0.6
			p.direction = Vector3(0, 1, 0)
			p.spread = 25.0
			p.initial_velocity_min = 1.5
			p.initial_velocity_max = 3.0
			p.gravity = Vector3(0, 0.6, 0)
			p.damping_min = 1.5
			p.damping_max = 2.5
			curve.add_point(Vector2(0, 0.4))
			curve.add_point(Vector2(1, 2.0))
		"sparkle", "big_sparkle":
			q.material = _quad_material(_star_tex, true)
			q.size = Vector2(0.18, 0.18) if kind == "sparkle" else Vector2(0.32, 0.32)
			p.amount = 16 if kind == "sparkle" else 48
			p.lifetime = 0.9 if kind == "sparkle" else 1.4
			p.direction = Vector3(0, 1, 0)
			p.spread = 180.0
			p.initial_velocity_min = 1.0
			p.initial_velocity_max = 3.0 if kind == "sparkle" else 6.0
			p.gravity = Vector3(0, -1.5, 0)
			p.damping_min = 1.0
			p.damping_max = 2.0
			curve.add_point(Vector2(0, 1.0))
			curve.add_point(Vector2(1, 0.0))
		"spark":  # [v7look] electric sparks (the crashed pod's torn panel): small soft points that
			# spit out and fall fast and die quickly; the star "sparkle" read as hard dots hanging round it.
			q.material = _quad_material(_soft_tex, true)
			q.size = Vector2(0.06, 0.06)
			p.amount = 10
			p.lifetime = 0.38
			p.explosiveness = 0.9
			p.direction = Vector3(0, 1, 0)
			p.spread = 75.0
			p.initial_velocity_min = 1.2
			p.initial_velocity_max = 2.6
			p.gravity = Vector3(0, -7.0, 0)
			p.damping_min = 0.5
			p.damping_max = 1.0
			curve.add_point(Vector2(0, 1.0))
			curve.add_point(Vector2(1, 0.2))
		"confetti":
			q.material = _quad_material(_soft_tex, false)
			q.size = Vector2(0.12, 0.08)
			p.amount = 40
			p.lifetime = 1.6
			p.direction = Vector3(0, 1, 0)
			p.spread = 50.0
			p.initial_velocity_min = 4.0
			p.initial_velocity_max = 7.0
			p.gravity = Vector3(0, -6.0, 0)
			p.angular_velocity_min = -400.0
			p.angular_velocity_max = 400.0
			p.hue_variation_min = -1.0
			p.hue_variation_max = 1.0
			curve.add_point(Vector2(0, 1.0))
			curve.add_point(Vector2(1, 0.8))
		"soil":
			q.material = _quad_material(_soft_tex, false)
			q.size = Vector2(0.14, 0.14)
			p.amount = 18
			p.lifetime = 0.8
			p.direction = Vector3(0, 1, 0)
			p.spread = 40.0
			p.initial_velocity_min = 2.0
			p.initial_velocity_max = 4.0
			p.gravity = Vector3(0, -9.0, 0)
			curve.add_point(Vector2(0, 1.0))
			curve.add_point(Vector2(1, 0.6))
		"bits":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.07, 0.07, 0.07)
			var mat := StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			bm.material = mat
			p.mesh = bm
			p.amount = 12
			p.lifetime = 0.7
			p.direction = Vector3(0, 1, 0)
			p.spread = 60.0
			p.initial_velocity_min = 2.0
			p.initial_velocity_max = 4.0
			p.gravity = Vector3(0, -12.0, 0)
			p.angular_velocity_min = -360.0
			p.angular_velocity_max = 360.0
			curve.add_point(Vector2(0, 1.0))
			curve.add_point(Vector2(1, 0.3))
	p.scale_amount_curve = curve
	return p


## One-shot burst of a kind at a world position.
func burst(kind: String, pos: Vector3, color: Color = Color.WHITE, amount_scale: float = 1.0) -> void:
	if not _pools.has(kind):
		return
	var list: Array = _pools[kind]
	var idx: int = _pool_idx[kind]
	_pool_idx[kind] = (idx + 1) % list.size()
	var p: CPUParticles3D = list[idx]
	p.global_position = pos
	p.color = color
	p.amount = maxi(1, int(_base_amount(kind) * amount_scale * Settings.particle_scale()))  # [deck] fewer on Low
	p.restart()
	p.emitting = true


func _base_amount(kind: String) -> int:
	match kind:
		"dust": return 10
		"steam": return 14
		"sparkle": return 16
		"spark": return 10
		"big_sparkle": return 48
		"confetti": return 40
		"soil": return 18
		"bits": return 12
	return 10


## Floating text that drifts up and fades. size ~1 normal, 2 for big events.
func float_text(pos: Vector3, text: String, color: Color = Color.WHITE, size: float = 1.0, rise: float = 1.4) -> void:
	# [v9d] One floating line per spot: the same words already up are not drawn again, and another
	# line starting near a visible one stacks above it instead of on top of it.
	var lift: float = 0.0
	for o: Label3D in _texts:
		if not o.visible or o.modulate.a <= 0.05:
			continue
		if o.text == text and o.global_position.distance_to(pos) < 4.0:
			return
		if o.global_position.distance_to(pos + OrbitUp.up(pos) * lift) < 0.55 * maxf(size, o.scale.x):
			lift += 0.55 * maxf(size, o.scale.x)
	pos += OrbitUp.up(pos) * lift
	var l: Label3D = _texts[_text_idx]
	_text_idx = (_text_idx + 1) % _texts.size()
	var tw_old: Variant = l.get_meta("tween") if l.has_meta("tween") else null
	if tw_old is Tween and (tw_old as Tween).is_valid():
		(tw_old as Tween).kill()
	l.text = text
	l.modulate = color
	l.outline_modulate.a = 0.85
	pos = _clear_of_hud(pos, rise)
	l.global_position = pos
	l.scale = Vector3.ONE * size
	l.modulate.a = 0.0
	l.visible = true
	var tw: Tween = create_tween()
	l.set_meta("tween", tw)
	tw.set_parallel(true)
	tw.tween_property(l, "modulate:a", color.a, 0.12)
	tw.tween_property(l, "global_position", pos + OrbitUp.up(pos) * rise, 1.6)  # [v1guide] rises along the local up on the globe.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(1.1)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.5).set_delay(1.1)
	tw.chain().tween_callback(func() -> void: l.visible = false)


## [vqa] Floating text keeps out of the HUD bands: if it would start in the bottom 30% of the
## screen (hotbar, level bar, prompt, notifications) or end in the top 16% (currency, district,
## checklist), it is moved along the camera's up axis into the clear middle.
func _clear_of_hud(pos: Vector3, rise: float) -> Vector3:
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null or cam.is_position_behind(pos):
		return pos
	var h: float = get_viewport().get_visible_rect().size.y
	var y0: float = cam.unproject_position(pos).y
	var y1: float = cam.unproject_position(pos + Vector3(0, rise, 0)).y
	var shift_px: float = 0.0
	if y0 > h * 0.7:
		shift_px = y0 - h * 0.7
	elif y1 < h * 0.16:
		shift_px = y1 - h * 0.16
	if absf(shift_px) < 1.0:
		return pos
	var dist: float = cam.global_position.distance_to(pos)
	var m_per_px: float = 2.0 * dist * tan(deg_to_rad(cam.fov) * 0.5) / maxf(h, 1.0)
	return pos + cam.global_basis.y * shift_px * m_per_px


## Expanding flat ring on the ground (hex flips, cash-ins).
func ring(pos: Vector3, radius: float, color: Color, duration: float = 0.6) -> void:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.9
	t.outer_radius = 1.0
	t.rings = 32
	t.ring_segments = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	t.material = m
	mi.mesh = t
	_root.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.05, 0)
	if JunkCube.planet_radius > 0.0:  # [orbB] round planet: lie flat on the local ground
		mi.quaternion = Quaternion(SphereGrid.frame(pos.normalized()))
		mi.global_position = pos + pos.normalized() * 0.05
	mi.scale = Vector3(0.2, 0.05, 0.2)
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 0.05, radius), duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, duration)
	tw.chain().tween_callback(mi.queue_free)


## [first] Ground-reveal sweep: a ring of soft dust (and optional glints) riding an expanding front
## from `center` out to `max_r` at `speed` m/s, in step with the ground shader's reveal ripple.
func sweep(center: Vector3, max_r: float, speed: float, color: Color, glints: bool = false) -> void:
	var dur: float = maxf(0.2, max_r / maxf(speed, 0.1))
	for layer: int in (2 if glints else 1):
		var p := CPUParticles3D.new()
		p.local_coords = false
		p.one_shot = false
		p.explosiveness = 0.0
		var q := QuadMesh.new()
		p.mesh = q
		p.color_ramp = _fade_ramp()
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		p.emission_ring_axis = Vector3.UP
		p.emission_ring_height = 0.05
		p.emission_ring_radius = 0.6
		p.emission_ring_inner_radius = 0.2
		p.direction = Vector3(0, 1, 0)
		var curve := Curve.new()
		if layer == 0:
			q.size = Vector2(0.55, 0.55)
			q.material = _quad_material(_soft_tex, false)
			p.amount = maxi(8, int(60.0 * Settings.particle_scale()))
			p.lifetime = 1.1
			p.spread = 50.0
			p.initial_velocity_min = 0.3
			p.initial_velocity_max = 0.9
			p.gravity = Vector3(0, 0.15, 0)
			p.damping_min = 1.0
			p.damping_max = 1.6
			p.color = color
			curve.add_point(Vector2(0, 0.6))
			curve.add_point(Vector2(1, 1.8))
		else:
			q.size = Vector2(0.12, 0.12)
			q.material = _quad_material(_star_tex, true)
			p.amount = maxi(6, int(40.0 * Settings.particle_scale()))
			p.lifetime = 1.6
			p.spread = 15.0
			p.initial_velocity_min = 0.5
			p.initial_velocity_max = 1.3
			p.gravity = Vector3(0, 0.2, 0)
			p.damping_min = 0.6
			p.damping_max = 1.0
			p.color = Color(1.0, 0.95, 0.75, 0.9)
			curve.add_point(Vector2(0, 1.0))
			curve.add_point(Vector2(1, 0.2))
		p.scale_amount_curve = curve
		_root.add_child(p)
		p.global_position = center + Vector3(0, 0.08, 0)
		p.emitting = true
		var tw: Tween = create_tween()
		tw.tween_property(p, "emission_ring_radius", max_r, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(p, "emission_ring_inner_radius", max_r - 0.5, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func() -> void: p.emitting = false)
		tw.tween_interval(p.lifetime + 0.1)
		tw.tween_callback(p.queue_free)


## [first] A thin, tapered column of light that rises, holds and fades (arrivals: the first robot).
func pillar(pos: Vector3, color: Color, height: float = 6.0, duration: float = 1.6) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.12
	c.bottom_radius = 0.42
	c.height = 1.0
	c.cap_top = false
	c.cap_bottom = false
	c.radial_segments = 24
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(color.lerp(Color.WHITE, 0.35), 0.0)
	c.material = m
	mi.mesh = c
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3(1, 0.01, 1)
	var tw: Tween = create_tween()
	tw.tween_method(func(t: float) -> void:
		mi.scale = Vector3(1.0 - 0.3 * t, maxf(0.01, height * t), 1.0 - 0.3 * t)
		mi.global_position = pos + Vector3(0, height * t * 0.5, 0)
		m.albedo_color.a = 0.42 * t, 0.0, 1.0, duration * 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(duration * 0.25)
	tw.tween_property(m, "albedo_color:a", 0.0, duration * 0.45)
	tw.tween_callback(mi.queue_free)
