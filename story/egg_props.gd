class_name EggProps
extends RefCounted
## Visual builders for the easter eggs and landmarks (procedural meshes + vendor models).
## Every builder returns a Node3D whose origin sits on the ground. Moving parts are named
## children ("Anim", "Screen", "Light", ...) the EasterEggs system pokes at.

static var _vc_cache: Dictionary = {}


## One material for merged vertex-coloured meshes (painted plastic / ceramic look).
static func vc(rough: float = 0.6, metal: float = 0.0) -> StandardMaterial3D:
	var key: String = "%.2f_%.2f" % [rough, metal]
	if _vc_cache.has(key):
		return _vc_cache[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.metallic = metal
	_vc_cache[key] = m
	return m


static func mesh(m: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.transform = ProcMesh.xf(pos, rot_deg, scl)
	# [v5load] Draw cost: paint lines, glass shards, plates under 3 cm thick and bits under 12 cm
	# cast no shadow (none was visible at the sun's shadow resolution; each was a shadow draw).
	if m and not DevHooks.has("no-shadow-trim"):
		var bb: Vector3 = m.get_aabb().size * scl.abs()
		if minf(bb.x, minf(bb.y, bb.z)) < 0.03 or maxf(bb.x, maxf(bb.y, bb.z)) < 0.12:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func model(id: String, pos: Vector3 = Vector3.ZERO, yaw_deg: float = 0.0, scl: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = AssetLib.model_mesh_lite(id, 4000)
	mi.transform = ProcMesh.xf(pos, Vector3(0, yaw_deg, 0), Vector3.ONE * scl)
	return mi


static func label(text: String, size: int, col: Color, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, emissive: bool = false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = col
	l.outline_size = 0
	l.shaded = not emissive
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.position = pos
	l.rotation_degrees = rot_deg
	return l


## A cylinder rod between two points.
static func strut(a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ProcMesh.cyl(r, r, a.distance_to(b), 6)
	mi.material_override = mat
	var dir: Vector3 = (b - a).normalized()
	mi.transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), (a + b) * 0.5)
	return mi


static func collider(n: Node3D, size: Vector3, center: Vector3) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = center
	sb.add_child(cs)
	n.add_child(sb)


static func glow(col: Color, energy: float, rng: float, pos: Vector3) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.position = pos
	return l


static func build(kind: String, part: int = 0) -> Node3D:
	match kind:
		"duck": return duck()
		"jukebox": return jukebox()
		"mural": return mural()
		"gnome": return gnome(part)
		"time_capsule": return time_capsule()
		"arcade": return arcade()
		"poster": return poster(part)
		"cat_shell": return cat_shell()
		"vending": return vending()
		"telescope": return telescope()
		"payphone": return payphone()
		"tv": return tv()
		"snail": return snail()
		"bench_bots": return bench_bots()
		"microwave": return microwave()
		"wet_floor": return wet_floor()
		"camera": return security_camera()
		"tyre_tower": return tyre_tower()
		"clothesline": return clothesline()
		"pedestal": return pedestal()
		"weather_bot": return weather_bot()
		"potato": return potato()
		"radio": return radio()
		"dev_desk": return dev_desk()
		"scarecrow": return scarecrow()
		"fishing_net": return fishing_net()
		"sand_car": return sand_car()
		"cairn": return cairn()
		"campfire": return campfire()
		"drill_press": return drill_press()
	var late: Node3D = EggPropsLate.build(kind, part)  # [late] the newer curiosities (story/egg_props_late.gd)
	if late:
		return late
	var n := Node3D.new()
	n.add_child(mesh(ProcMesh.box(Vector3(0.4, 0.4, 0.4)), vc()))
	return n


# --- Builders -------------------------------------------------------------------------

static func duck() -> Node3D:
	var n := Node3D.new()
	# [green] One hydrant: the file bundles a clean and an aged one side by side (the merged mesh
	# read as a cluster of hydrants with the duck).
	var hyd := MeshInstance3D.new()
	hyd.mesh = AssetLib.model_part("fire_hydrant", "fire_hydrant_aged")
	hyd.scale = Vector3.ONE * 1.2
	n.add_child(hyd)
	var top: float = AssetLib.model_aabb("fire_hydrant").end.y * 1.2
	var d := Node3D.new()
	d.name = "Anim"
	d.position = Vector3(0, top - 0.02, 0)
	n.add_child(d)
	d.add_child(model("rubber_duck_toy", Vector3.ZERO, 30.0, 1.7))
	collider(n, Vector3(0.5, top, 0.4), Vector3(0, top * 0.5, 0))
	return n


static func jukebox() -> Node3D:
	var n := Node3D.new()
	var wood: ShaderMaterial = Mats.worn_paint(Color(0.45, 0.12, 0.1), 0.85, 0.25, 4.0, 0.5)
	var parts: Array = []
	parts.append(ProcMesh.part(ProcMesh.rounded_box(Vector3(1.0, 1.25, 0.62), 0.06, 2), ProcMesh.xf(Vector3(0, 0.625, 0))))
	parts.append(ProcMesh.part(ProcMesh.cyl(0.5, 0.5, 0.62, 24), ProcMesh.xf(Vector3(0, 1.25, 0), Vector3(90, 0, 0))))
	n.add_child(mesh(ProcMesh.merge(parts), wood))
	var chrome: StandardMaterial3D = Mats.metal("chrome")
	# Chrome arch trim and grille.
	for k: int in 7:
		n.add_child(mesh(ProcMesh.box(Vector3(0.62, 0.025, 0.02)), chrome, Vector3(0, 0.18 + k * 0.06, 0.315)))
	# Glowing light tubes running up both sides and over the arch.
	var tube_a: StandardMaterial3D = Mats.lamp(Color(1.0, 0.55, 0.2), 0.6)
	var tube_b: StandardMaterial3D = Mats.lamp(Color(0.3, 0.85, 0.9), 0.6)
	tube_a.resource_name = "tube_a"
	tube_b.resource_name = "tube_b"
	for x: float in [-0.44, 0.44]:
		n.add_child(mesh(ProcMesh.cyl(0.035, 0.035, 1.1, 8), tube_a, Vector3(x, 0.7, 0.32)))
		n.add_child(mesh(ProcMesh.cyl(0.02, 0.02, 1.1, 8), tube_b, Vector3(x * 0.86, 0.7, 0.33)))
	# Chrome trim and a glowing tube following the arched top (short segments along a half circle).
	var trim: Array = []
	var glow_parts: Array = []
	for k: int in 14:
		var a: float = PI * (k + 0.5) / 14.0
		var rot := Vector3(0, 0, rad_to_deg(a) + 90.0)
		trim.append(ProcMesh.part(ProcMesh.box(Vector3(0.05, 0.12, 0.05)), ProcMesh.xf(Vector3(cos(a) * 0.49, 1.25 + sin(a) * 0.49, 0.3), rot)))
		glow_parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.035, 0.1, 0.03)), ProcMesh.xf(Vector3(cos(a) * 0.41, 1.25 + sin(a) * 0.41, 0.32), rot)))
	n.add_child(mesh(ProcMesh.merge(trim), chrome))
	var arch := mesh(ProcMesh.merge(glow_parts), tube_b)
	arch.name = "Arch"
	n.add_child(arch)
	# Coloured glass panel inside the arch.
	n.add_child(mesh(ProcMesh.cyl(0.38, 0.38, 0.02, 24), Mats.lamp(Color(1.0, 0.45, 0.25), 0.25), Vector3(0, 1.25, 0.305), Vector3(90, 0, 0), Vector3(1, 1, 1)))
	# Record window with a little selection card and a disc.
	n.add_child(mesh(ProcMesh.box(Vector3(0.6, 0.32, 0.02)), Mats.glass(Color(0.1, 0.12, 0.12, 0.6)), Vector3(0, 0.98, 0.32)))
	var disc := mesh(ProcMesh.cyl(0.13, 0.13, 0.01, 24), Mats.metal("dark_steel"), Vector3(0, 1.0, 0.25), Vector3(90, 0, 0))
	disc.name = "Disc"
	n.add_child(disc)
	n.add_child(label(TranslationServer.translate("SELECT  A1  ·  B4  ·  C7"), 22, Color(0.95, 0.9, 0.7), Vector3(0, 0.74, 0.32)))
	var l := glow(Color(1.0, 0.7, 0.4), 0.0, 4.0, Vector3(0, 1.0, 0.8))
	l.name = "Light"
	n.add_child(l)
	collider(n, Vector3(1.0, 1.6, 0.62), Vector3(0, 0.8, 0))
	n.scale = Vector3.ONE * 1.15
	return n


## The crew mural: a freestanding slab of concrete wall with a painted scene (generated image).
static func mural() -> Node3D:
	var n := Node3D.new()
	var conc: StandardMaterial3D = AssetLib.pbr_material("concrete_wall_008", 0.5, Color(0.85, 0.83, 0.8), true)
	n.add_child(mesh(ProcMesh.box(Vector3(5.2, 2.7, 0.28)), conc, Vector3(0, 1.35, 0)))
	# Broken top edge chunks.
	for k: int in 5:
		n.add_child(mesh(ProcMesh.box(Vector3(0.7, 0.3, 0.28)), conc, Vector3(-2.0 + k * 1.0, 2.75 + (k % 2) * 0.1, 0), Vector3(0, 0, (k % 3 - 1) * 8.0)))
	var q := QuadMesh.new()
	q.size = Vector2(4.9, 2.45)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(mural_image())
	m.roughness = 0.85
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	n.add_child(mesh(q, m, Vector3(0, 1.32, 0.145)))
	var spray := label(TranslationServer.translate("WE'LL BE BACK AFTER LUNCH"), 60, Color(1.0, 0.97, 0.9), Vector3(0, 2.36, 0.15))
	spray.outline_size = 10
	spray.outline_modulate = Color(0.1, 0.12, 0.2, 0.9)
	n.add_child(spray)
	n.add_child(model("spray_paint_bottles", Vector3(1.6, 0, 0.5), 20.0, 1.0))
	collider(n, Vector3(5.2, 2.7, 0.3), Vector3(0, 1.35, 0))
	return n


static func _disc(img: Image, c: Vector2, r: float, col: Color) -> void:
	for y: int in range(int(c.y - r), int(c.y + r) + 1):
		for x: int in range(int(c.x - r), int(c.x + r) + 1):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and Vector2(x, y).distance_to(c) <= r:
				img.set_pixel(x, y, col)


static func _rect(img: Image, r: Rect2i, col: Color) -> void:
	img.fill_rect(r.intersection(Rect2i(0, 0, img.get_width(), img.get_height())), col)


## A hand-painted looking scene: dawn sky, a hill, four little cleaning robots holding hands
## around a big flower, a sun. Rough edges + spray speckles so it reads as street art.
static func mural_image() -> Image:
	var w: int = 512
	var h: int = 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	for y: int in h:
		var t: float = float(y) / h
		var col: Color = Color(0.98, 0.62, 0.42).lerp(Color(0.3, 0.6, 0.85), 1.0 - t)
		for x: int in w:
			var edge: float = minf(minf(x, w - 1 - x), minf(y, h - 1 - y))
			var a: float = 1.0 if edge > 6 + rng.randi_range(0, 6) else 0.0
			img.set_pixel(x, y, Color(col, a))
	_disc(img, Vector2(400, 70), 38, Color(1.0, 0.86, 0.35))
	for y: int in range(170, h):
		for x: int in w:
			if img.get_pixel(x, y).a > 0.0 and y > 180 + sin(x * 0.02) * 10.0:
				img.set_pixel(x, y, Color(0.35, 0.62, 0.32))
	# The big flower.
	_rect(img, Rect2i(252, 110, 8, 80), Color(0.2, 0.45, 0.2))
	for k: int in 6:
		var a: float = TAU * k / 6.0
		_disc(img, Vector2(256, 100) + Vector2(cos(a), sin(a)) * 18.0, 13, Color(0.98, 0.4, 0.55))
	_disc(img, Vector2(256, 100), 11, Color(1.0, 0.85, 0.3))
	# Four robots: rounded bodies, big eyes, little antennae. Colors of the old crew.
	var cols: Array[Color] = [Color(0.25, 0.55, 0.85), Color(0.95, 0.6, 0.2), Color(0.55, 0.8, 0.45), Color(0.85, 0.85, 0.8)]
	var xs: Array[int] = [110, 180, 330, 400]
	for i: int in 4:
		var cx: int = xs[i]
		var base: int = 196 - (i % 2) * 6
		_rect(img, Rect2i(cx - 22, base - 48, 44, 42), cols[i])
		_disc(img, Vector2(cx, base - 54), 20, cols[i])
		_disc(img, Vector2(cx - 8, base - 56), 6, Color(0.1, 0.1, 0.12))
		_disc(img, Vector2(cx + 8, base - 56), 6, Color(0.1, 0.1, 0.12))
		_disc(img, Vector2(cx - 6, base - 58), 2, Color.WHITE)
		_disc(img, Vector2(cx + 10, base - 58), 2, Color.WHITE)
		_rect(img, Rect2i(cx - 1, base - 86, 3, 14), Color(0.2, 0.2, 0.2))
		_disc(img, Vector2(cx, base - 88), 4, Color(1.0, 0.3, 0.25))
		_rect(img, Rect2i(cx - 18, base - 6, 12, 8), Color(0.15, 0.15, 0.15))
		_rect(img, Rect2i(cx + 6, base - 6, 12, 8), Color(0.15, 0.15, 0.15))
		# Arms reaching to the neighbour (holding hands).
		_rect(img, Rect2i(cx + 22, base - 34, 26 if i != 1 else 40, 5), cols[i].darkened(0.2))
	# Spray speckle.
	for k: int in 1800:
		var p := Vector2i(rng.randi_range(0, w - 1), rng.randi_range(0, h - 1))
		var c: Color = img.get_pixelv(p)
		if c.a > 0.0:
			img.set_pixelv(p, c.lightened(rng.randf_range(-0.15, 0.2)))
	img.generate_mipmaps()
	return img


static func gnome(i: int) -> Node3D:
	var n := Node3D.new()
	var hats: Array[Color] = [Color(0.85, 0.15, 0.12), Color(0.15, 0.4, 0.8), Color(0.9, 0.7, 0.15), Color(0.2, 0.6, 0.3), Color(0.6, 0.2, 0.6)]
	var coats: Array[Color] = [Color(0.2, 0.35, 0.7), Color(0.75, 0.25, 0.2), Color(0.25, 0.5, 0.3), Color(0.55, 0.35, 0.2), Color(0.2, 0.55, 0.55)]
	var skin := Color(0.95, 0.75, 0.62)
	var parts: Array = []
	parts.append(ProcMesh.part(ProcMesh.cyl(0.07, 0.13, 0.24, 14), ProcMesh.xf(Vector3(0, 0.14, 0)), coats[i % 5]))
	parts.append(ProcMesh.part(ProcMesh.cyl(0.085, 0.085, 0.03, 14), ProcMesh.xf(Vector3(0, 0.17, 0)), Color(0.15, 0.1, 0.08)))
	parts.append(ProcMesh.part(ProcMesh.cyl(0.12, 0.12, 0.03, 14), ProcMesh.xf(Vector3(0, 0.015, 0)), Color(0.25, 0.18, 0.12)))
	parts.append(ProcMesh.part(ProcMesh.sphere(0.075, 14, 8), ProcMesh.xf(Vector3(0, 0.31, 0)), skin))
	parts.append(ProcMesh.part(ProcMesh.cyl(0.0, 0.07, 0.13, 12), ProcMesh.xf(Vector3(0, 0.25, 0.04), Vector3(180 - 20, 0, 0)), Color(0.96, 0.96, 0.94)))
	parts.append(ProcMesh.part(ProcMesh.sphere(0.022, 8, 4), ProcMesh.xf(Vector3(0, 0.31, 0.075)), Color(0.95, 0.55, 0.5)))
	parts.append(ProcMesh.part(ProcMesh.cyl(0.0, 0.085, 0.24, 14), ProcMesh.xf(Vector3(0, 0.46, -0.01), Vector3(-10, 0, 0)), hats[i % 5]))
	# Little arms; gnome 3 carries a lantern, gnome 1 a shovel.
	for s: float in [-1.0, 1.0]:
		parts.append(ProcMesh.part(ProcMesh.capsule(0.025, 0.12), ProcMesh.xf(Vector3(s * 0.1, 0.17, 0.03), Vector3(30, 0, s * 25)), coats[i % 5].darkened(0.1)))
	if i % 5 == 1:
		parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.015, 0.3, 0.015)), ProcMesh.xf(Vector3(0.14, 0.15, 0.05)), Color(0.5, 0.35, 0.2)))
		parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.06, 0.07, 0.01)), ProcMesh.xf(Vector3(0.14, 0.0, 0.05)), Color(0.5, 0.5, 0.52)))
	var body := mesh(ProcMesh.merge(parts), vc(0.35))
	body.name = "Anim"
	n.add_child(body)
	if i % 5 == 3:
		var lan := mesh(ProcMesh.sphere(0.03, 8, 4), Mats.lamp(Color(1.0, 0.8, 0.4), 2.0), Vector3(-0.15, 0.12, 0.06))
		n.add_child(lan)
	n.scale = Vector3.ONE * 1.5
	return n


static func time_capsule() -> Node3D:
	var n := Node3D.new()
	var dirt: StandardMaterial3D = AssetLib.pbr_material("brown_mud_dry", 0.8, Color(0.75, 0.65, 0.55), true)
	n.add_child(mesh(ProcMesh.cyl(0.55, 0.75, 0.12, 20), dirt, Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1.4, 1, 1)))
	var tube := Node3D.new()
	tube.name = "Anim"
	tube.position = Vector3(0, 0.2, 0)
	tube.rotation_degrees = Vector3(0, 25, 72)
	n.add_child(tube)
	tube.add_child(mesh(ProcMesh.cyl(0.18, 0.18, 0.8, 20), Mats.worn_paint(Color(0.3, 0.55, 0.5), 0.7, 0.5, 7.0, 0.5)))
	for y: float in [-0.42, 0.42]:
		tube.add_child(mesh(ProcMesh.cyl(0.2, 0.2, 0.06, 20), Mats.metal("brass"), Vector3(0, y, 0)))
	tube.add_child(label(TranslationServer.translate("OPEN IN 100 YEARS"), 26, Color(0.95, 0.92, 0.8), Vector3(0, 0, 0.185), Vector3(0, 0, 90)))
	n.add_child(glow(Color(0.6, 0.95, 1.0), 0.8, 2.5, Vector3(0, 0.6, 0)))
	return n


static func arcade() -> Node3D:
	var n := Node3D.new()
	var paint: ShaderMaterial = Mats.worn_paint(Color(0.2, 0.15, 0.45), 0.85, 0.3, 11.0, 0.5)
	var parts: Array = []
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.75, 1.0, 0.75)), ProcMesh.xf(Vector3(0, 0.5, 0))))
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.75, 0.7, 0.5)), ProcMesh.xf(Vector3(0, 1.35, -0.12))))
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.75, 0.25, 0.55)), ProcMesh.xf(Vector3(0, 1.82, -0.06))))
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.79, 0.12, 0.42)), ProcMesh.xf(Vector3(0, 1.02, 0.22), Vector3(-15, 0, 0))))
	n.add_child(mesh(ProcMesh.merge(parts), paint))
	var scr := mesh(ProcMesh.box(Vector3(0.6, 0.5, 0.02)), Mats.lamp(Color(0.1, 0.3, 0.25), 0.4), Vector3(0, 1.38, 0.135), Vector3(-12, 0, 0))
	scr.name = "Screen"
	n.add_child(scr)
	n.add_child(label(TranslationServer.translate("HI-SCORE"), 20, Color(1.0, 0.9, 0.3), Vector3(0, 1.5, 0.16), Vector3(-12, 0, 0), true))
	n.add_child(label(TranslationServer.translate("WREN  999990"), 24, Color(0.4, 1.0, 0.6), Vector3(0, 1.38, 0.16), Vector3(-12, 0, 0), true))
	n.add_child(label(TranslationServer.translate("INSERT COIN"), 18, Color(1.0, 0.5, 0.4), Vector3(0, 1.24, 0.16), Vector3(-12, 0, 0), true))
	var marquee := mesh(ProcMesh.box(Vector3(0.7, 0.18, 0.02)), Mats.lamp(Color(1.0, 0.6, 0.25), 1.2), Vector3(0, 1.82, 0.225))
	n.add_child(marquee)
	n.add_child(label(TranslationServer.translate("SWEEP-O-TRON"), 30, Color(0.2, 0.08, 0.05), Vector3(0, 1.82, 0.237)))
	n.add_child(mesh(ProcMesh.cyl(0.012, 0.012, 0.1, 6), Mats.metal("chrome"), Vector3(-0.15, 1.13, 0.28)))
	n.add_child(mesh(ProcMesh.sphere(0.03, 8, 4), Mats.lamp(Color(0.9, 0.1, 0.1), 0.5), Vector3(-0.15, 1.18, 0.28)))
	for k: int in 3:
		n.add_child(mesh(ProcMesh.cyl(0.025, 0.025, 0.02, 10), Mats.lamp([Color(1, 0.8, 0.2), Color(0.2, 0.7, 1), Color(1, 0.3, 0.6)][k], 0.8), Vector3(0.05 + k * 0.08, 1.09, 0.3), Vector3(-15, 0, 0)))
	var l := glow(Color(0.4, 1.0, 0.7), 0.6, 2.5, Vector3(0, 1.4, 0.6))
	l.name = "Light"
	n.add_child(l)
	collider(n, Vector3(0.75, 1.95, 0.75), Vector3(0, 0.97, 0))
	return n


static func poster(i: int) -> Node3D:
	var n := Node3D.new()
	n.add_child(mesh(ProcMesh.cyl(0.05, 0.06, 2.6, 8), Mats.worn_paint(Color(0.35, 0.4, 0.38), 0.6, 0.6, 3.0 + i, 0.6), Vector3(0, 1.3, 0)))
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.66)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(poster_image(i))
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var p := mesh(q, m, Vector3(0, 1.45, 0.065), Vector3(0, 0, (i - 1) * 3.0))
	p.name = "Anim"
	n.add_child(p)
	collider(n, Vector3(0.14, 2.6, 0.14), Vector3(0, 1.3, 0))
	return n


static func poster_image(i: int) -> Image:
	var w: int = 128
	var h: int = 168
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.96, 0.93, 0.82))
	var ink := Color(0.12, 0.1, 0.1)
	var red := Color(0.8, 0.15, 0.12)
	_rect(img, Rect2i(10, 8, 108, 26), red)
	# A friendly round cat face (Biscuit), drawn the same on every poster.
	_disc(img, Vector2(64, 82), 30, Color(0.95, 0.6, 0.25))
	for s: int in [-1, 1]:
		for y: int in range(42, 62):
			var half: int = int((y - 42) * 0.55)
			_rect(img, Rect2i(64 + s * 18 - half, y, half * 2 + 1, 1), Color(0.95, 0.6, 0.25))
	_disc(img, Vector2(52, 78), 4, ink)
	_disc(img, Vector2(76, 78), 4, ink)
	_disc(img, Vector2(64, 90), 3, Color(0.9, 0.4, 0.45))
	for k: int in 3:
		_rect(img, Rect2i(30, 86 + k * 4, 16, 1), ink)
		_rect(img, Rect2i(82, 86 + k * 4, 16, 1), ink)
	# Stripes on the forehead.
	for k: int in 3:
		_rect(img, Rect2i(56 + k * 6, 56, 3, 10), Color(0.8, 0.42, 0.15))
	# Lines of "text" + an arrow pointing the way (left, right, down).
	for k: int in 4:
		_rect(img, Rect2i(16, 122 + k * 8, 96 - (k % 2) * 30, 3), ink)
	var arrow_col := red
	match i % 3:
		0:
			_rect(img, Rect2i(84, 152, 30, 4), arrow_col)
			_disc(img, Vector2(114, 154), 5, arrow_col)
		1:
			_rect(img, Rect2i(14, 152, 30, 4), arrow_col)
			_disc(img, Vector2(14, 154), 5, arrow_col)
		2:
			_disc(img, Vector2(64, 156), 6, arrow_col)
	# Weathering.
	var rng := RandomNumberGenerator.new()
	rng.seed = 91 + i
	for k: int in 600:
		var p := Vector2i(rng.randi_range(0, w - 1), rng.randi_range(0, h - 1))
		img.set_pixelv(p, img.get_pixelv(p).darkened(rng.randf_range(0.0, 0.25)))
	img.generate_mipmaps()
	return img


## Biscuit: a cat-shaped robot shell, curled up asleep. Tabby-orange enamel, worn at the edges.
static func cat_shell() -> Node3D:
	var n := Node3D.new()
	var shell: ShaderMaterial = Mats.worn_paint(Color(0.95, 0.58, 0.25), 0.85, 0.35, 17.0, 0.4)
	var body := Node3D.new()
	body.name = "Anim"
	n.add_child(body)
	body.add_child(mesh(ProcMesh.capsule(0.2, 0.75), shell, Vector3(0, 0.2, 0), Vector3(0, 0, 90), Vector3(1, 1, 0.9)))
	body.add_child(mesh(ProcMesh.sphere(0.17, 16, 10), shell, Vector3(0.38, 0.24, 0.08)))
	for s: float in [-1.0, 1.0]:
		body.add_child(mesh(ProcMesh.cyl(0.0, 0.07, 0.13, 4), shell, Vector3(0.42, 0.42, 0.08 + s * 0.08), Vector3(s * 12, 45, -10)))
	for s: float in [-1.0, 1.0]:
		body.add_child(mesh(ProcMesh.capsule(0.022, 0.08), Mats.metal("dark_steel"), Vector3(0.51, 0.27, 0.08 + s * 0.06), Vector3(90, 0, 0)))
	# Curled tail: a few capsule segments around the body.
	for k: int in 6:
		var a: float = PI * 0.15 + k * 0.42
		body.add_child(mesh(ProcMesh.capsule(0.05, 0.18), shell, Vector3(-0.2 + cos(a) * 0.3, 0.08, sin(a) * 0.3), Vector3(90, -rad_to_deg(a), 0)))
	body.add_child(mesh(ProcMesh.cyl(0.11, 0.11, 0.02, 16), Mats.metal("brass"), Vector3(0, 0.39, 0), Vector3.ZERO))
	body.add_child(label(TranslationServer.translate("BISCUIT"), 18, Color(0.25, 0.15, 0.1), Vector3(0, 0.401, 0), Vector3(-90, 0, 0)))
	var eye := glow(Color(0.5, 1.0, 0.6), 0.0, 1.5, Vector3(0.55, 0.3, 0.08))
	eye.name = "Light"
	n.add_child(eye)
	return n


static func vending() -> Node3D:
	var n := Node3D.new()
	var paint: ShaderMaterial = Mats.worn_paint(Color(0.75, 0.18, 0.15), 0.8, 0.45, 9.0, 0.6)
	n.add_child(mesh(ProcMesh.rounded_box(Vector3(0.95, 1.95, 0.8), 0.04, 2), paint, Vector3(0, 0.975, 0)))
	n.add_child(mesh(ProcMesh.box(Vector3(0.62, 1.2, 0.02)), Mats.glass(Color(0.15, 0.2, 0.22, 0.45)), Vector3(-0.1, 1.2, 0.41)))
	var cans: Array = []
	var cols: Array[Color] = [Color(0.9, 0.2, 0.2), Color(0.2, 0.5, 0.9), Color(0.95, 0.8, 0.2), Color(0.3, 0.75, 0.35)]
	for row: int in 4:
		cans.append(ProcMesh.part(ProcMesh.box(Vector3(0.6, 0.02, 0.5)), ProcMesh.xf(Vector3(-0.1, 0.72 + row * 0.28, 0.15)), Color(0.5, 0.5, 0.5)))
		for k: int in 5:
			if row == 0 and k != 2:
				continue  # one can left, bottom row
			if row > 0 and (k + row) % 3 == 0:
				continue
			cans.append(ProcMesh.part(ProcMesh.cyl(0.04, 0.04, 0.13, 10), ProcMesh.xf(Vector3(-0.34 + k * 0.12, 0.8 + row * 0.28, 0.3)), cols[(k + row) % 4]))
	var shelf := mesh(ProcMesh.merge(cans), vc(0.3, 0.5))
	shelf.name = "Shelf"
	n.add_child(shelf)
	var sign_ := mesh(ProcMesh.box(Vector3(0.86, 0.22, 0.02)), Mats.lamp(Color(1.0, 0.9, 0.75), 1.2), Vector3(0, 1.9 - 0.12, 0.41))
	sign_.name = "Screen"
	n.add_child(sign_)
	n.add_child(label(TranslationServer.translate("FIZZ"), 54, Color(0.75, 0.12, 0.1), Vector3(0, 1.78, 0.425)))
	n.add_child(mesh(ProcMesh.box(Vector3(0.18, 0.5, 0.03)), Mats.metal("steel"), Vector3(0.34, 1.2, 0.41)))
	n.add_child(mesh(ProcMesh.box(Vector3(0.05, 0.02, 0.01)), Mats.lamp(Color(0.2, 1.0, 0.3), 1.5), Vector3(0.34, 1.35, 0.43)))
	n.add_child(mesh(ProcMesh.box(Vector3(0.5, 0.16, 0.06)), Mats.metal("dark_steel"), Vector3(-0.1, 0.3, 0.42)))
	collider(n, Vector3(0.95, 1.95, 0.8), Vector3(0, 0.975, 0))
	return n


static func telescope() -> Node3D:
	var n := Node3D.new()
	var brass: StandardMaterial3D = Mats.metal("brass")
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	for k: int in 3:
		var a: float = TAU * k / 3.0 + 0.3
		n.add_child(strut(Vector3(cos(a) * 0.5, 0.0, sin(a) * 0.5), Vector3(0, 1.18, 0), 0.022, steel))
	var head := Node3D.new()
	head.name = "Anim"
	head.position = Vector3(0, 1.22, 0)
	head.rotation_degrees = Vector3(0, 0, 35)
	n.add_child(head)
	head.add_child(mesh(ProcMesh.cyl(0.07, 0.09, 1.0, 16), brass, Vector3(0.18, 0, 0), Vector3(0, 0, 90)))
	head.add_child(mesh(ProcMesh.cyl(0.1, 0.1, 0.08, 16), steel, Vector3(0.7, 0, 0), Vector3(0, 0, 90)))
	head.add_child(mesh(ProcMesh.cyl(0.025, 0.025, 0.16, 8), steel, Vector3(-0.38, 0, 0), Vector3(0, 0, 90)))
	head.add_child(mesh(ProcMesh.cyl(0.095, 0.095, 0.01, 16), Mats.glass(Color(0.4, 0.6, 0.9, 0.7)), Vector3(0.745, 0, 0), Vector3(0, 0, 90)))
	n.add_child(model("clipboard", Vector3(0.45, 0.0, 0.3), 30.0, 1.0))
	return n


static func payphone() -> Node3D:
	var n := Node3D.new()
	n.add_child(mesh(ProcMesh.box(Vector3(0.12, 1.1, 0.12)), Mats.metal("dark_steel"), Vector3(0, 0.55, -0.08)))
	n.add_child(mesh(ProcMesh.rounded_box(Vector3(0.62, 0.85, 0.25), 0.03, 2), Mats.worn_paint(Color(0.85, 0.65, 0.2), 0.8, 0.5, 23.0, 0.5), Vector3(0, 1.55, 0)))
	var ph := model("korean_public_payphone_01", Vector3(0, 1.2, 0.13), 0.0, 1.0)
	ph.name = "Anim"
	n.add_child(ph)
	var l := glow(Color(1.0, 0.85, 0.4), 0.0, 2.0, Vector3(0, 1.8, 0.4))
	l.name = "Light"
	n.add_child(l)
	collider(n, Vector3(0.62, 2.0, 0.35), Vector3(0, 1.0, 0))
	return n


static func tv() -> Node3D:
	var n := Node3D.new()
	n.add_child(model("plastic_monobloc_chair_01", Vector3.ZERO, 0.0, 1.0))
	var seat: float = 0.45
	var t := model("Television_01", Vector3(0, seat, 0.02), 0.0, 1.0)
	t.name = "Anim"
	n.add_child(t)
	var scr := QuadMesh.new()
	scr.size = Vector2(0.38, 0.28)
	var m := StandardMaterial3D.new()
	var nt := NoiseTexture2D.new()
	nt.width = 64
	nt.height = 48
	var fn := FastNoiseLite.new()
	fn.frequency = 0.5
	nt.noise = fn
	m.albedo_color = Color(0.6, 0.65, 0.7)
	m.emission_enabled = true
	m.emission_texture = nt
	m.emission = Color(0.7, 0.75, 0.8)
	m.emission_energy_multiplier = 0.9
	m.albedo_texture = nt
	var s := mesh(scr, m, Vector3(-0.04, seat + 0.24, 0.245))
	s.name = "Screen"
	n.add_child(s)
	var l := glow(Color(0.7, 0.8, 1.0), 0.7, 2.5, Vector3(0, seat + 0.25, 0.7))
	l.name = "Light"
	n.add_child(l)
	collider(n, Vector3(0.64, 0.95, 0.62), Vector3(0, 0.47, 0))
	return n


static func snail() -> Node3D:
	var n := Node3D.new()
	n.add_child(model("Barrel_01", Vector3.ZERO, 40.0, 1.0))
	var g := Node3D.new()
	g.name = "Anim"
	g.position = Vector3(0.0, 0.88, 0.05)
	n.add_child(g)
	var parts: Array = []
	parts.append(ProcMesh.part(ProcMesh.capsule(0.03, 0.16), ProcMesh.xf(Vector3(0, 0.02, 0), Vector3(90, 0, 0), Vector3(1, 0.6, 1)), Color(0.75, 0.68, 0.55)))
	parts.append(ProcMesh.part(ProcMesh.sphere(0.055, 14, 8), ProcMesh.xf(Vector3(0, 0.07, -0.02)), Color(0.7, 0.45, 0.25)))
	parts.append(ProcMesh.part(ProcMesh.torus(0.0, 0.04, 14, 6), ProcMesh.xf(Vector3(0.03, 0.08, -0.02), Vector3(0, 0, 90)), Color(0.85, 0.65, 0.4)))
	for s: float in [-1.0, 1.0]:
		parts.append(ProcMesh.part(ProcMesh.cyl(0.005, 0.006, 0.06, 4), ProcMesh.xf(Vector3(s * 0.012, 0.05, 0.09), Vector3(-30, 0, s * 15)), Color(0.75, 0.68, 0.55)))
		parts.append(ProcMesh.part(ProcMesh.sphere(0.008, 6, 3), ProcMesh.xf(Vector3(s * 0.02, 0.08, 0.105)), Color(0.15, 0.12, 0.1)))
	g.add_child(mesh(ProcMesh.merge(parts), vc(0.25)))
	g.scale = Vector3.ONE * 1.6
	collider(n, Vector3(0.56, 0.88, 0.56), Vector3(0, 0.44, 0))
	return n


## Two tiny old robots on a bench, one leaning on the other. Waiting for a lunch break to end.
static func bench_bots() -> Node3D:
	var n := Node3D.new()
	n.add_child(model("modular_street_seating", Vector3(0.0, 0, 0), 0.0, 0.6))
	var cols: Array[Color] = [Color(0.3, 0.5, 0.7), Color(0.85, 0.75, 0.55)]
	for k: int in 2:
		var b := Node3D.new()
		b.position = Vector3(-0.35 + k * 0.6, 0.5, -0.02)
		b.rotation_degrees = Vector3(0, 0, -14.0 if k == 0 else 4.0)
		n.add_child(b)
		var paint: ShaderMaterial = Mats.worn_paint(cols[k], 0.7, 0.7, 30.0 + k, 0.7)
		b.add_child(mesh(ProcMesh.rounded_box(Vector3(0.34, 0.32, 0.26), 0.06, 2), paint, Vector3(0, 0.16, 0)))
		b.add_child(mesh(ProcMesh.hemisphere(0.15, 14, 5), paint, Vector3(0, 0.33, 0)))
		for s: float in [-1.0, 1.0]:
			b.add_child(mesh(ProcMesh.cyl(0.04, 0.04, 0.03, 10), Mats.glass(Color(0.05, 0.05, 0.06, 1.0), 0.1), Vector3(s * 0.06, 0.38, 0.13), Vector3(90, 0, 0)))
			b.add_child(mesh(ProcMesh.capsule(0.03, 0.2), Mats.metal("dark_steel"), Vector3(s * 0.08, 0.02, 0.2), Vector3(80, 0, 0)))
		if k == 0:
			b.add_child(mesh(ProcMesh.capsule(0.025, 0.4), Mats.metal("dark_steel"), Vector3(0.28, 0.26, -0.02), Vector3(0, 0, 70)))
	var fl := model("flower_heliophila", Vector3(-0.05, 0.5, 0.0), 0.0, 0.5)
	fl.name = "Flower"
	fl.visible = false
	n.add_child(fl)
	collider(n, Vector3(2.6, 0.6, 0.5), Vector3(0, 0.3, 0))
	return n


static func microwave() -> Node3D:
	var n := Node3D.new()
	n.add_child(model("cardboard_box_01", Vector3.ZERO, 10.0, 1.4))
	var top: float = AssetLib.model_aabb("cardboard_box_01").end.y * 1.4
	var mw := model("vintage_microwave", Vector3(0, top, 0), -5.0, 0.6)
	mw.name = "Anim"
	n.add_child(mw)
	var led := mesh(ProcMesh.box(Vector3(0.08, 0.03, 0.01)), Mats.lamp(Color(0.3, 1.0, 0.4), 2.0), Vector3(0.22, top + 0.22, 0.23))
	led.name = "Screen"
	n.add_child(led)
	collider(n, Vector3(0.65, top + 0.32, 0.5), Vector3(0, (top + 0.32) * 0.5, 0))
	return n


static func wet_floor() -> Node3D:
	var n := Node3D.new()
	var s := model("WetFloorSign_01", Vector3.ZERO, 0.0, 1.5)
	s.name = "Anim"
	n.add_child(s)
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.35)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.42, 0.35, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	n.add_child(mesh(q, m, Vector3(0.15, 0.012, 0.35), Vector3(-90, 20, 0)))
	n.add_child(label(TranslationServer.translate("(it is not wet)"), 14, Color(0.3, 0.25, 0.2), Vector3(0.2, 0.015, 0.36), Vector3(-90, 20, 0)))
	return n


static func security_camera() -> Node3D:
	var n := Node3D.new()
	n.add_child(mesh(ProcMesh.cyl(0.06, 0.08, 3.0, 8), Mats.worn_paint(Color(0.4, 0.42, 0.45), 0.7, 0.6, 41.0, 0.6), Vector3(0, 1.5, 0)))
	var head := Node3D.new()
	head.name = "Anim"
	head.position = Vector3(0, 3.0, 0)
	n.add_child(head)
	var c := model("security_camera_01", Vector3(0, -0.1, 0), 180.0, 1.6)
	head.add_child(c)
	var led := mesh(ProcMesh.sphere(0.025, 6, 3), Mats.lamp(Color(1.0, 0.2, 0.15), 3.0), Vector3(0.0, 0.1, 0.35))
	led.name = "Led"
	head.add_child(led)
	n.add_child(mesh(ProcMesh.box(Vector3(1.0, 0.36, 0.03)), Mats.worn_paint(Color(0.85, 0.75, 0.2), 0.8, 0.5, 42.0, 0.6), Vector3(0, 1.7, 0.1)))
	n.add_child(label(TranslationServer.translate("THE LEDGER IS WATCHING\n(FOR SAVINGS)"), 18, Color(0.12, 0.1, 0.08), Vector3(0, 1.7, 0.117)))
	collider(n, Vector3(0.18, 3.0, 0.18), Vector3(0, 1.5, 0))
	return n


static func tyre_tower() -> Node3D:
	var n := Node3D.new()
	var stack := Node3D.new()
	stack.name = "Anim"
	n.add_child(stack)
	for k: int in 8:
		var t := model("old_tyre", Vector3(sin(k * 1.7) * 0.05, 0.3 + k * 0.165, cos(k * 2.3) * 0.05), 0.0, 1.0)
		t.rotation_degrees = Vector3(90, k * 37.0, sin(k * 1.3) * 4.0)
		t.position.y = 0.0825 + k * 0.165
		t.position -= Vector3(0, 0, 0)
		stack.add_child(t)
	var duckie := model("rubber_duck_toy", Vector3(0, 8 * 0.165, 0), 60.0, 1.0)
	stack.add_child(duckie)
	collider(n, Vector3(0.6, 1.4, 0.6), Vector3(0, 0.7, 0))
	return n


# --- Second wave (content depth): six for anywhere, six for wilderness bases -------------

static func _wood() -> ShaderMaterial:
	return Mats.worn_paint(Color(0.48, 0.34, 0.22), 0.4, 0.1, 51.0, 0.6)


## Scale for a vendor model so it ends up `h` metres tall.
static func _fit(id: String, h: float) -> float:
	var a: AABB = AssetLib.model_aabb(id)
	return h / maxf(a.size.y, 0.01)


## A washing line between two poles with exactly one sock on it.
static func clothesline() -> Node3D:
	var n := Node3D.new()
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	for x: float in [-1.2, 1.2]:
		n.add_child(strut(Vector3(x, 0, 0), Vector3(x, 1.75, 0), 0.03, steel))
		n.add_child(strut(Vector3(x - 0.15, 1.7, 0), Vector3(x + 0.15, 1.7, 0), 0.02, steel))
	var line := Node3D.new()
	line.name = "Anim"
	line.position = Vector3(0, 1.68, 0)
	n.add_child(line)
	line.add_child(mesh(ProcMesh.cyl(0.006, 0.006, 2.4, 4), Mats.metal("steel"), Vector3.ZERO, Vector3(0, 0, 90)))
	var sock := Node3D.new()
	sock.name = "Prize"
	sock.position = Vector3(0.25, 0, 0)
	line.add_child(sock)
	var parts: Array = []
	for k: int in 4:
		parts.append(ProcMesh.part(ProcMesh.cyl(0.055, 0.055, 0.07, 10), ProcMesh.xf(Vector3(0, -0.07 - k * 0.07, 0)), Color(0.9, 0.25, 0.3) if k % 2 == 0 else Color(0.95, 0.92, 0.85)))
	parts.append(ProcMesh.part(ProcMesh.capsule(0.055, 0.22), ProcMesh.xf(Vector3(0.07, -0.34, 0), Vector3(0, 0, 90)), Color(0.9, 0.25, 0.3)))
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.03, 0.06, 0.02)), ProcMesh.xf(Vector3(0, 0.0, 0)), Color(0.9, 0.75, 0.3)))
	sock.add_child(mesh(ProcMesh.merge(parts), vc(0.9)))
	collider(n, Vector3(2.6, 1.8, 0.2), Vector3(0, 0.9, 0))
	return n


## A stone pedestal holding one perfect golden cube.
static func pedestal() -> Node3D:
	var n := Node3D.new()
	var stone: ShaderMaterial = Mats.worn_paint(Color(0.72, 0.7, 0.66), 0.9, 0.05, 61.0, 0.6)
	n.add_child(mesh(ProcMesh.rounded_box(Vector3(0.7, 0.12, 0.7), 0.02, 2), stone, Vector3(0, 0.06, 0)))
	n.add_child(mesh(ProcMesh.rounded_box(Vector3(0.5, 0.9, 0.5), 0.03, 2), stone, Vector3(0, 0.57, 0)))
	n.add_child(mesh(ProcMesh.rounded_box(Vector3(0.62, 0.08, 0.62), 0.02, 2), stone, Vector3(0, 1.06, 0)))
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1.0, 0.78, 0.3)
	gold.metallic = 1.0
	gold.roughness = 0.22
	gold.emission_enabled = true
	gold.emission = Color(1.0, 0.7, 0.25)
	gold.emission_energy_multiplier = 0.25
	var cube := mesh(ProcMesh.rounded_box(Vector3(0.34, 0.34, 0.34), 0.03, 2), gold, Vector3(0, 1.3, 0), Vector3(0, 20, 0))
	cube.name = "Anim"
	n.add_child(cube)
	n.add_child(mesh(ProcMesh.box(Vector3(0.36, 0.16, 0.01)), Mats.metal("brass"), Vector3(0, 0.75, 0.256)))
	n.add_child(label(TranslationServer.translate("EMPLOYEE OF\nTHE MONTH\n— CUBE —"), 14, Color(0.2, 0.13, 0.05), Vector3(0, 0.75, 0.262)))
	n.add_child(glow(Color(1.0, 0.8, 0.4), 0.5, 2.0, Vector3(0, 1.6, 0.3)))
	collider(n, Vector3(0.7, 1.5, 0.7), Vector3(0, 0.75, 0))
	return n


## A weather-station robot on a pole: anemometer cups, one eye, total confidence.
static func weather_bot() -> Node3D:
	var n := Node3D.new()
	n.add_child(mesh(ProcMesh.cyl(0.05, 0.07, 2.0, 8), Mats.worn_paint(Color(0.85, 0.85, 0.8), 0.6, 0.6, 71.0, 0.6), Vector3(0, 1.0, 0)))
	var head := Node3D.new()
	head.name = "Anim"
	head.position = Vector3(0, 2.0, 0)
	n.add_child(head)
	var paint: ShaderMaterial = Mats.worn_paint(Color(0.95, 0.75, 0.2), 0.75, 0.55, 72.0, 0.5)
	head.add_child(mesh(ProcMesh.rounded_box(Vector3(0.42, 0.34, 0.36), 0.07, 2), paint, Vector3(0, 0.17, 0)))
	head.add_child(mesh(ProcMesh.cyl(0.075, 0.075, 0.03, 14), Mats.glass(Color(0.05, 0.05, 0.06, 1.0), 0.1), Vector3(0, 0.2, 0.185), Vector3(90, 0, 0)))
	var eye := mesh(ProcMesh.sphere(0.035, 8, 4), Mats.lamp(Color(0.5, 0.85, 1.0), 2.0), Vector3(0, 0.2, 0.2))
	eye.name = "Screen"
	head.add_child(eye)
	var steel: StandardMaterial3D = Mats.metal("steel")
	head.add_child(mesh(ProcMesh.cyl(0.012, 0.012, 0.3, 6), steel, Vector3(0, 0.49, 0)))
	var cups := Node3D.new()
	cups.position = Vector3(0, 0.64, 0)
	head.add_child(cups)
	for k: int in 3:
		var a: float = TAU * k / 3.0
		cups.add_child(strut(Vector3.ZERO, Vector3(cos(a), 0, sin(a)) * 0.22, 0.008, steel))
		cups.add_child(mesh(ProcMesh.hemisphere(0.05, 10, 4), Mats.worn_paint(Color(0.9, 0.3, 0.2), 0.8, 0.3, 73.0 + k, 0.4), Vector3(cos(a), 0, sin(a)) * 0.22, Vector3(90, rad_to_deg(-a), 0)))
	n.add_child(mesh(ProcMesh.box(Vector3(0.5, 0.2, 0.02)), Mats.worn_paint(Color(0.2, 0.35, 0.6), 0.8, 0.4, 74.0, 0.5), Vector3(0, 1.35, 0.06)))
	n.add_child(label(TranslationServer.translate("FORECAST\nALWAYS RIGHT*"), 13, Color(0.92, 0.92, 0.85), Vector3(0, 1.35, 0.072)))
	collider(n, Vector3(0.2, 2.4, 0.2), Vector3(0, 1.2, 0))
	return n


## A show crate with one enormous potato in it.
static func potato() -> Node3D:
	var n := Node3D.new()
	var sc: float = _fit("wooden_crate_02", 0.55)
	n.add_child(model("wooden_crate_02", Vector3.ZERO, 0.0, sc))
	var top: float = AssetLib.model_aabb("wooden_crate_02").end.y * sc
	var parts: Array = []
	var skin := Color(0.72, 0.55, 0.33)
	parts.append(ProcMesh.part(ProcMesh.sphere(0.5, 20, 12), ProcMesh.xf(Vector3.ZERO, Vector3(0, 0, 8), Vector3(1.0, 0.62, 0.72)), skin))
	parts.append(ProcMesh.part(ProcMesh.sphere(0.3, 14, 8), ProcMesh.xf(Vector3(0.32, 0.05, 0.05), Vector3.ZERO, Vector3(1.0, 0.75, 0.85)), skin.darkened(0.04)))
	for k: int in 9:
		var a: float = k * 2.4
		parts.append(ProcMesh.part(ProcMesh.sphere(0.025, 6, 3), ProcMesh.xf(Vector3(cos(a) * 0.38, sin(k * 1.7) * 0.2, sin(a) * 0.3)), skin.darkened(0.35)))
	var pot := mesh(ProcMesh.merge(parts), vc(0.85))
	pot.name = "Anim"
	pot.position = Vector3(0, top + 0.22, 0)
	n.add_child(pot)
	var ribbon := mesh(ProcMesh.cyl(0.08, 0.08, 0.02, 12), Mats.lamp(Color(0.25, 0.45, 0.95), 0.3), Vector3(0, top + 0.2, 0.36), Vector3(80, 0, 0))
	pot.add_child(ribbon)
	ribbon.position = Vector3(0, 0.0, 0.36)
	n.add_child(label(TranslationServer.translate("SHOW ENTRY"), 26, Color(0.18, 0.1, 0.05), Vector3(0, top * 0.5, 0.33)))
	collider(n, Vector3(1.0, top + 0.6, 0.8), Vector3(0, (top + 0.6) * 0.5, 0))
	return n


## A shortwave radio on a crate, antenna aimed at the moon.
static func radio() -> Node3D:
	var n := Node3D.new()
	var sc: float = _fit("wooden_crate_02", 0.5)
	n.add_child(model("wooden_crate_02", Vector3.ZERO, 15.0, sc))
	var top: float = AssetLib.model_aabb("wooden_crate_02").end.y * sc
	var rs := Node3D.new()
	rs.name = "Anim"
	rs.position = Vector3(0, top, 0)
	n.add_child(rs)
	rs.add_child(mesh(ProcMesh.rounded_box(Vector3(0.5, 0.3, 0.26), 0.03, 2), Mats.worn_paint(Color(0.3, 0.38, 0.3), 0.85, 0.4, 81.0, 0.5), Vector3(0, 0.15, 0)))
	var dial := mesh(ProcMesh.box(Vector3(0.22, 0.08, 0.01)), Mats.lamp(Color(1.0, 0.75, 0.35), 0.5), Vector3(-0.08, 0.2, 0.131))
	dial.name = "Screen"
	n.add_child(dial)
	dial.position = Vector3(-0.08, top + 0.2, 0.131)
	for x: float in [0.12, 0.19]:
		rs.add_child(mesh(ProcMesh.cyl(0.03, 0.03, 0.03, 10), Mats.metal("chrome"), Vector3(x, 0.12, 0.14), Vector3(90, 0, 0)))
	rs.add_child(strut(Vector3(0.18, 0.3, -0.05), Vector3(0.5, 1.2, -0.25), 0.007, Mats.metal("chrome")))
	rs.add_child(strut(Vector3(-0.18, 0.3, -0.05), Vector3(-0.35, 1.0, -0.4), 0.007, Mats.metal("chrome")))
	collider(n, Vector3(0.7, top + 0.32, 0.6), Vector3(0, (top + 0.32) * 0.5, 0))
	return n


## A folding desk with a clipboard of the builders' notes.
static func dev_desk() -> Node3D:
	var n := Node3D.new()
	var wood: ShaderMaterial = _wood()
	n.add_child(mesh(ProcMesh.box(Vector3(1.0, 0.04, 0.55)), wood, Vector3(0, 0.74, 0)))
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	for sx: float in [-0.45, 0.45]:
		n.add_child(strut(Vector3(sx, 0, -0.22), Vector3(sx, 0.72, 0.22), 0.015, steel))
		n.add_child(strut(Vector3(sx, 0, 0.22), Vector3(sx, 0.72, -0.22), 0.015, steel))
	var cb := model("clipboard", Vector3(-0.1, 0.76, 0.0), 12.0, 1.0)
	cb.name = "Anim"
	n.add_child(cb)
	n.add_child(mesh(ProcMesh.cyl(0.04, 0.035, 0.1, 12), Mats.worn_paint(Color(0.85, 0.85, 0.82), 0.9, 0.0, 91.0, 0.3), Vector3(0.32, 0.81, 0.08)))
	n.add_child(mesh(ProcMesh.box(Vector3(0.6, 0.12, 0.01)), Mats.worn_paint(Color(0.95, 0.92, 0.82), 0.9, 0.0, 92.0, 0.3), Vector3(0, 0.62, 0.28)))
	n.add_child(label(TranslationServer.translate("THE BUILDERS · DO NOT TIDY"), 13, Color(0.2, 0.18, 0.15), Vector3(0, 0.62, 0.286)))
	n.add_child(model("plastic_monobloc_chair_01", Vector3(0.0, 0.0, -0.55), 0.0, 0.95))
	collider(n, Vector3(1.0, 0.78, 0.6), Vector3(0, 0.39, 0))
	return n


## A farm robot dressed as a scarecrow: straw hat, coat, arms out on a crossbar.
static func scarecrow() -> Node3D:
	var n := Node3D.new()
	var wood: ShaderMaterial = _wood()
	n.add_child(mesh(ProcMesh.cyl(0.05, 0.06, 1.9, 8), wood, Vector3(0, 0.95, 0)))
	var up := Node3D.new()
	up.name = "Anim"
	up.position = Vector3(0, 1.0, 0)
	n.add_child(up)
	up.add_child(mesh(ProcMesh.box(Vector3(1.5, 0.06, 0.06)), wood, Vector3(0, 0.45, 0)))
	var coat: ShaderMaterial = Mats.worn_paint(Color(0.35, 0.42, 0.25), 0.85, 0.1, 101.0, 0.7)
	up.add_child(mesh(ProcMesh.rounded_box(Vector3(0.5, 0.65, 0.3), 0.08, 2), coat, Vector3(0, 0.2, 0)))
	for sx: float in [-1.0, 1.0]:
		up.add_child(mesh(ProcMesh.capsule(0.07, 0.6), coat, Vector3(sx * 0.48, 0.45, 0), Vector3(0, 0, 90)))
		up.add_child(mesh(ProcMesh.cyl(0.0, 0.08, 0.18, 6), Mats.worn_paint(Color(0.9, 0.78, 0.4), 0.9, 0.0, 102.0, 0.4), Vector3(sx * 0.82, 0.45, 0), Vector3(0, 0, sx * 90)))
	var paint: ShaderMaterial = Mats.worn_paint(Color(0.75, 0.75, 0.72), 0.7, 0.75, 103.0, 0.6)
	up.add_child(mesh(ProcMesh.rounded_box(Vector3(0.32, 0.28, 0.28), 0.06, 2), paint, Vector3(0, 0.72, 0)))
	for sx: float in [-1.0, 1.0]:
		up.add_child(mesh(ProcMesh.sphere(0.035, 8, 4), Mats.lamp(Color(0.6, 1.0, 0.6), 0.8), Vector3(sx * 0.07, 0.74, 0.142)))
	var straw: ShaderMaterial = Mats.worn_paint(Color(0.92, 0.8, 0.45), 0.9, 0.0, 104.0, 0.5)
	up.add_child(mesh(ProcMesh.cyl(0.32, 0.32, 0.02, 18), straw, Vector3(0, 0.87, 0), Vector3(4, 0, -6)))
	up.add_child(mesh(ProcMesh.cyl(0.13, 0.16, 0.16, 14), straw, Vector3(0, 0.95, 0)))
	up.add_child(mesh(ProcMesh.cyl(0.165, 0.165, 0.03, 14), Mats.worn_paint(Color(0.75, 0.2, 0.15), 0.9, 0.0, 105.0, 0.4), Vector3(0, 0.89, 0)))
	collider(n, Vector3(0.3, 2.0, 0.3), Vector3(0, 1.0, 0))
	return n


## A fishing net hung between two posts, with a buoy still tangled in it.
static func fishing_net() -> Node3D:
	var n := Node3D.new()
	var wood: ShaderMaterial = _wood()
	for x: float in [-1.1, 1.1]:
		n.add_child(mesh(ProcMesh.cyl(0.05, 0.06, 1.7, 8), wood, Vector3(x, 0.85, 0)))
	var net := Node3D.new()
	net.name = "Anim"
	net.position = Vector3(0, 1.6, 0)
	n.add_child(net)
	var parts: Array = []
	var cord := Color(0.35, 0.55, 0.5)
	var cols: int = 10
	var rows: int = 6
	for i: int in cols + 1:
		var x: float = -1.1 + 2.2 * i / cols
		var sag: float = 0.25 * (1.0 - pow(2.0 * i / cols - 1.0, 2.0))
		parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.012, 1.1, 0.012)), ProcMesh.xf(Vector3(x, -0.55 - sag, 0)), cord))
	for j: int in rows + 1:
		var y: float = -1.1 * j / rows
		for i: int in cols:
			var x0: float = -1.1 + 2.2 * (i + 0.5) / cols
			var sag2: float = 0.25 * (1.0 - pow(2.0 * (i + 0.5) / cols - 1.0, 2.0))
			parts.append(ProcMesh.part(ProcMesh.box(Vector3(2.2 / cols + 0.01, 0.012, 0.012)), ProcMesh.xf(Vector3(x0, y - sag2, 0)), cord))
	for k: int in 5:
		parts.append(ProcMesh.part(ProcMesh.sphere(0.05, 8, 4), ProcMesh.xf(Vector3(-0.9 + k * 0.45, 0.02 - 0.2 * (1.0 - pow((k - 2) / 2.0, 2.0)), 0.02)), Color(0.95, 0.6, 0.15)))
	net.add_child(mesh(ProcMesh.merge(parts), vc(0.95)))
	var buoy := model("ocean_buoy", Vector3(0.35, -1.05, 0.12), 20.0, _fit("ocean_buoy", 0.55))
	buoy.name = "Prize"
	net.add_child(buoy)
	n.add_child(model("lifebuoy", Vector3(-1.1, 0.9, 0.08), 0.0, _fit("lifebuoy", 0.55)))
	(n.get_child(n.get_child_count() - 1) as Node3D).rotation_degrees = Vector3(90, 0, 0)
	collider(n, Vector3(2.4, 1.7, 0.2), Vector3(0, 0.85, 0))
	return n


## A car sunk to its doors in sand, with a very old parking ticket under the wiper.
static func sand_car() -> Node3D:
	var n := Node3D.new()
	var car := model("covered_car", Vector3(0, -0.35, 0), 0.0, 1.0)
	car.name = "Anim"
	var coat := StandardMaterial3D.new()
	coat.albedo_color = Color(0.86, 0.72, 0.5, 0.45)
	coat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	coat.roughness = 1.0
	car.material_overlay = coat
	n.add_child(car)
	var a: AABB = AssetLib.model_aabb("covered_car")
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color(0.86, 0.73, 0.52)
	sand.roughness = 1.0
	n.add_child(mesh(ProcMesh.hemisphere(1.0, 20, 6), sand, Vector3(a.get_center().x, -0.05, a.get_center().z), Vector3.ZERO, Vector3(a.size.x * 0.75, 0.55, a.size.z * 0.7)))
	n.add_child(mesh(ProcMesh.hemisphere(1.0, 14, 5), sand, Vector3(a.get_center().x + a.size.x * 0.45, -0.05, a.get_center().z + 0.3), Vector3.ZERO, Vector3(1.0, 0.4, 0.9)))
	var tk := mesh(ProcMesh.box(Vector3(0.3, 0.01, 0.18)), Mats.worn_paint(Color(0.98, 0.95, 0.85), 0.95, 0.0, 111.0, 0.2), Vector3(a.get_center().x, a.end.y - 0.38, a.get_center().z), Vector3(0, 10, 0))
	n.add_child(tk)
	n.add_child(label(TranslationServer.translate("FINE"), 18, Color(0.75, 0.12, 0.1), Vector3(a.get_center().x, a.end.y - 0.37, a.get_center().z), Vector3(-90, 10, 0)))
	collider(n, Vector3(a.size.x, a.size.y - 0.35, a.size.z) * 0.9, Vector3(a.get_center().x, (a.size.y - 0.35) * 0.5, a.get_center().z))
	return n


## A hiker's cairn of flat stones; Patch adds the top one.
static func cairn() -> Node3D:
	var n := Node3D.new()
	var stack := Node3D.new()
	stack.name = "Anim"
	n.add_child(stack)
	var y: float = 0.0
	var stone := Mats.worn_paint(Color(0.55, 0.54, 0.52), 0.9, 0.0, 121.0, 0.7)
	for k: int in 6:
		var r: float = 0.36 - k * 0.05
		var h: float = 0.13 - k * 0.008
		stack.add_child(mesh(ProcMesh.sphere(1.0, 14, 7), stone, Vector3(sin(k * 2.1) * 0.03, y + h * 0.5, cos(k * 1.3) * 0.03), Vector3(0, k * 40.0, sin(k * 1.7) * 6.0), Vector3(r, h * 0.55, r * 0.85)))
		y += h * 0.92
	var top := mesh(ProcMesh.sphere(1.0, 12, 6), Mats.worn_paint(Color(0.75, 0.72, 0.66), 0.9, 0.0, 122.0, 0.4), Vector3(0, y + 0.04, 0), Vector3(0, 25, 4), Vector3(0.08, 0.045, 0.07))
	top.name = "Top"
	top.visible = false
	stack.add_child(top)
	collider(n, Vector3(0.7, y, 0.6), Vector3(0, y * 0.5, 0))
	return n


## A ring of stones, two stools, a kettle: somebody's last camping trip. "Flame" and "Light" wake up.
static func campfire() -> Node3D:
	var n := Node3D.new()
	var parts: Array = []
	for k: int in 9:
		var a: float = TAU * k / 9.0
		parts.append(ProcMesh.part(ProcMesh.sphere(0.1, 10, 5), ProcMesh.xf(Vector3(cos(a) * 0.42, 0.04, sin(a) * 0.42), Vector3(0, k * 30.0, 0), Vector3(1.2, 0.6, 1.0)), Color(0.5, 0.49, 0.47).lightened(0.1 * sin(k * 2.0))))
	for k: int in 3:
		parts.append(ProcMesh.part(ProcMesh.cyl(0.04, 0.045, 0.6, 8), ProcMesh.xf(Vector3(0, 0.08, 0), Vector3(90, k * 60.0, 12)), Color(0.32, 0.22, 0.14)))
	parts.append(ProcMesh.part(ProcMesh.cyl(0.25, 0.3, 0.02, 14), ProcMesh.xf(Vector3(0, 0.01, 0)), Color(0.15, 0.14, 0.13)))
	n.add_child(mesh(ProcMesh.merge(parts), vc(0.95)))
	var canvas: ShaderMaterial = Mats.worn_paint(Color(0.3, 0.45, 0.6), 0.9, 0.0, 131.0, 0.5)
	for sx: float in [-1.0, 1.0]:
		var st := Node3D.new()
		st.position = Vector3(sx * 0.95, 0, 0.3)
		st.rotation.y = sx * 0.5
		n.add_child(st)
		st.add_child(strut(Vector3(-0.15, 0, -0.15), Vector3(0.15, 0.38, 0.15), 0.012, Mats.metal("steel")))
		st.add_child(strut(Vector3(0.15, 0, -0.15), Vector3(-0.15, 0.38, 0.15), 0.012, Mats.metal("steel")))
		st.add_child(mesh(ProcMesh.box(Vector3(0.34, 0.02, 0.3)), canvas, Vector3(0, 0.39, 0)))
	var kettle := Node3D.new()
	kettle.position = Vector3(0.5, 0, -0.35)
	n.add_child(kettle)
	var dented := Mats.metal("steel")
	kettle.add_child(mesh(ProcMesh.sphere(0.12, 14, 8), dented, Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(1, 0.85, 1.05)))
	kettle.add_child(mesh(ProcMesh.cyl(0.015, 0.03, 0.12, 6), dented, Vector3(0.12, 0.14, 0), Vector3(0, 0, -55)))
	kettle.add_child(mesh(ProcMesh.torus(0.07, 0.085, 12, 4), Mats.metal("dark_steel"), Vector3(0, 0.22, 0), Vector3(90, 0, 0)))
	var flame := Node3D.new()
	flame.name = "Flame"
	flame.visible = false
	n.add_child(flame)
	flame.add_child(mesh(ProcMesh.cyl(0.0, 0.14, 0.38, 8), Mats.lamp(Color(1.0, 0.55, 0.15), 3.0), Vector3(0, 0.27, 0)))
	flame.add_child(mesh(ProcMesh.cyl(0.0, 0.08, 0.26, 8), Mats.lamp(Color(1.0, 0.85, 0.4), 3.5), Vector3(0.05, 0.22, 0.03)))
	var l := glow(Color(1.0, 0.6, 0.3), 0.0, 5.0, Vector3(0, 0.6, 0))
	l.name = "Light"
	n.add_child(l)
	collider(n, Vector3(1.0, 0.25, 1.0), Vector3(0, 0.12, 0))
	return n


## A drill press alone in a field, and its sign.
static func drill_press() -> Node3D:
	var n := Node3D.new()
	n.add_child(model("old_drill_press", Vector3.ZERO, 0.0, 1.0))
	var a: AABB = AssetLib.model_aabb("old_drill_press")
	var sign_ := Node3D.new()
	sign_.name = "Sign"
	sign_.position = Vector3(a.end.x + 0.45, 0, 0.3)
	n.add_child(sign_)
	sign_.add_child(mesh(ProcMesh.box(Vector3(0.05, 1.0, 0.05)), _wood(), Vector3(0, 0.5, 0)))
	sign_.add_child(mesh(ProcMesh.box(Vector3(0.55, 0.32, 0.02)), Mats.worn_paint(Color(0.93, 0.9, 0.8), 0.9, 0.1, 141.0, 0.5), Vector3(0, 0.95, 0.035)))
	sign_.add_child(label(TranslationServer.translate("BACK IN\n5 MINUTES"), 22, Color(0.15, 0.12, 0.1), Vector3(0, 0.95, 0.047)))
	var bolt := mesh(ProcMesh.cyl(0.025, 0.025, 0.06, 6), Mats.metal("chrome"), Vector3(a.get_center().x, a.end.y * 0.55, a.get_center().z + 0.1))
	bolt.name = "Bolt"
	bolt.visible = false
	n.add_child(bolt)
	collider(n, a.size * 0.85, a.get_center())
	return n

