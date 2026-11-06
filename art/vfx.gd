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
	for kind: String in ["dust", "sparkle", "steam", "confetti", "soil", "bits", "big_sparkle"]:
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
		l.font_size = 64
		l.outline_size = 18
		l.outline_modulate = Color(0.18, 0.1, 0.3, 0.85)
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
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
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
	p.amount = maxi(1, int(_base_amount(kind) * amount_scale))
	p.restart()
	p.emitting = true


func _base_amount(kind: String) -> int:
	match kind:
		"dust": return 10
		"steam": return 14
		"sparkle": return 16
		"big_sparkle": return 48
		"confetti": return 40
		"soil": return 18
		"bits": return 12
	return 10


## Floating text that drifts up and fades. size ~1 normal, 2 for big events.
func float_text(pos: Vector3, text: String, color: Color = Color.WHITE, size: float = 1.0, rise: float = 1.4) -> void:
	var l: Label3D = _texts[_text_idx]
	_text_idx = (_text_idx + 1) % _texts.size()
	var tw_old: Variant = l.get_meta("tween", null)
	if tw_old is Tween and (tw_old as Tween).is_valid():
		(tw_old as Tween).kill()
	l.text = text
	l.modulate = color
	l.outline_modulate.a = 0.85
	l.global_position = pos
	l.scale = Vector3.ONE * size * 0.3
	l.visible = true
	var tw: Tween = create_tween()
	l.set_meta("tween", tw)
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector3.ONE * size, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "global_position", pos + Vector3(0, rise, 0), 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.8)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.35).set_delay(0.8)
	tw.chain().tween_callback(func() -> void: l.visible = false)


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
	mi.scale = Vector3(0.2, 0.05, 0.2)
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 0.05, radius), duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, duration)
	tw.chain().tween_callback(mi.queue_free)
