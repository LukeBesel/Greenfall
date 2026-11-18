class_name MapGlyphs
extends RefCounted
## [v2map] Small hand-drawn glyphs for the seed-keeper's survey hologram (ui/globe_view.gd), painted
## once into textures from soft-edged shapes (no art files, no text): a sprout for a hub, a Lumi
## head for "you are here", a smoke plume for the crashed pod. Also drawn on the legend rows.

const SIZE: int = 64
const TEAL := Color(0.47, 0.86, 0.78)
const CREAM := Color(0.98, 0.93, 0.8)
const LEAF := Color(0.58, 0.92, 0.45)
const SMOKE := Color(0.36, 0.37, 0.4)  # dark, so it reads against the pale hologram
const EMBER := Color(1.0, 0.66, 0.32)

static var _cache: Dictionary = {}


static func texture(kind: String) -> ImageTexture:
	if _cache.has(kind):
		return _cache[kind]
	var shapes: Array = []
	match kind:
		"sprout":
			shapes = [[_seg.bind(Vector2(32, 58), Vector2(32, 30), 3.2), CREAM],
				[_leaf.bind(Vector2(21, 26), Vector2(-1.0, -0.55), 13.0, 6.5), LEAF],
				[_leaf.bind(Vector2(43, 20), Vector2(1.0, -0.75), 15.0, 7.0), LEAF],
				[_seg.bind(Vector2(18, 58), Vector2(46, 58), 3.0), TEAL]]
		"lumi":
			shapes = [[_seg.bind(Vector2(32, 16), Vector2(32, 6), 2.2), CREAM],
				[_circle.bind(Vector2(32, 6), 3.5), EMBER],
				[_box.bind(Vector2(32, 36), Vector2(22, 18), 9.0), CREAM],
				[_circle.bind(Vector2(24, 35), 6.0), TEAL],
				[_circle.bind(Vector2(40, 35), 6.0), TEAL]]
		"plume":
			shapes = [[_circle.bind(Vector2(30, 46), 9.0), SMOKE],
				[_circle.bind(Vector2(36, 31), 11.0), SMOKE],
				[_circle.bind(Vector2(29, 15), 12.0), Color(SMOKE, 0.85)],
				[_box.bind(Vector2(32, 57), Vector2(12, 5), 3.0), EMBER]]
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y: int in SIZE:
		for x: int in SIZE:
			var p := Vector2(x + 0.5, y + 0.5)
			var out := Color(0, 0, 0, 0)
			var edge: float = 0.0
			for sh: Array in shapes:
				var d: float = (sh[0] as Callable).call(p)
				var col: Color = sh[1]
				var a: float = clampf(0.5 - d, 0.0, 1.0) * col.a
				edge = maxf(edge, clampf(2.0 - d, 0.0, 1.0))  # within ~2 px outside any shape
				var na: float = a + out.a * (1.0 - a)
				if na > 0.0:
					var rgb: Color = (col * a + out * out.a * (1.0 - a)) / na
					out = Color(rgb.r, rgb.g, rgb.b, na)
			# A soft dark keyline so the glyph reads over bright hexes.
			var k: float = edge * 0.6 * (1.0 - out.a)
			if k > 0.0:
				var ka: float = out.a + k
				var kc: Color = (out * out.a + Color(0.03, 0.09, 0.09) * k) / ka
				out = Color(kc.r, kc.g, kc.b, ka)
			img.set_pixel(x, y, out)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache[kind] = t
	return t


static func _circle(p: Vector2, c: Vector2, r: float) -> float:
	return p.distance_to(c) - r


static func _seg(p: Vector2, a: Vector2, b: Vector2, r: float) -> float:
	var ab: Vector2 = b - a
	var t: float = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t) - r


static func _box(p: Vector2, c: Vector2, half: Vector2, r: float) -> float:
	var q: Vector2 = (p - c).abs() - half + Vector2(r, r)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r


## A leaf: an ellipse along `dir` (half-length a, half-width b) centred at c.
static func _leaf(p: Vector2, c: Vector2, dir: Vector2, a: float, b: float) -> float:
	var u: Vector2 = dir.normalized()
	var v := Vector2(-u.y, u.x)
	var q := Vector2((p - c).dot(u) / a, (p - c).dot(v) / b)
	return (q.length() - 1.0) * minf(a, b)


## A billboard glyph for the hologram (depth-tested, so it hides behind the globe).
static func sprite(kind: String, px: float) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = texture(kind)
	s.pixel_size = px
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.render_priority = 2
	s.offset = Vector2(0, SIZE * 0.5)  # the glyph stands on its point
	return s
