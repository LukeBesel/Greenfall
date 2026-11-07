class_name DecorProps
extends RefCounted
## [late] Builders for the Garden Mode decorations (data/decor.json). Each returns a Node3D whose
## origin is the footprint centre on the ground, facing +Z. New and well kept (these are the
## restored world's things): stone, painted wood, brass, a little warm light; vendor plants and
## props where Poly Haven has them.

static var _mats: Dictionary = {}


static func build(type_id: String) -> Node3D:
	match type_id:
		"path": return path()
		"flower_bed": return flower_bed()
		"planter": return planter()
		"bench": return bench()
		"lamp": return lamp()
		"bird_bath": return bird_bath()
		"fountain": return fountain()
		"statue": return statue()
		"lumi_sculpture": return lumi_sculpture()
		"wren_kite": return wren_kite()
	var n := Node3D.new()
	n.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.6, 0.6, 0.6)), stone()))
	return n


# --- Materials ---------------------------------------------------------------------------

static func stone(tint: Color = Color(0.78, 0.76, 0.72)) -> StandardMaterial3D:
	var key: String = "stone_" + tint.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = AssetLib.tex("concrete_pavement", "diff")
	m.normal_enabled = true
	m.normal_texture = AssetLib.tex("concrete_pavement", "nor_gl")
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.8
	m.roughness = 0.85
	_mats[key] = m
	return m


static func wood(tint: Color = Color(0.62, 0.42, 0.26)) -> StandardMaterial3D:
	var key: String = "wood_" + tint.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = 0.62
	_mats[key] = m
	return m


static func paint(col: Color, rough: float = 0.45, metal: float = 0.0) -> StandardMaterial3D:
	var key: String = "paint_%s_%.2f_%.2f" % [col.to_html(), rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	_mats[key] = m
	return m


static func water() -> StandardMaterial3D:
	if _mats.has("water"):
		return _mats["water"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.32, 0.52, 0.58, 0.72)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.04
	m.metallic = 0.3
	_mats["water"] = m
	return m


static func leaves(tint: Color = Color(0.3, 0.5, 0.22)) -> StandardMaterial3D:
	return paint(tint, 0.8)


static func _vendor(n: Node3D, id: String, h: float, pos: Vector3, yaw: float = 0.0) -> void:
	var a: AABB = AssetLib.model_aabb(id)
	var s: float = h / maxf(a.size.y, 0.01)
	n.add_child(EggProps.model(id, pos, yaw, s))


# --- Builders ----------------------------------------------------------------------------

## Two flat stepping stones per cell, a little uneven.
static func path() -> Node3D:
	var n := Node3D.new()
	var parts: Array = []
	var tones: Array[Color] = [Color(0.8, 0.78, 0.73), Color(0.72, 0.7, 0.66)]
	parts.append(ProcMesh.part(ProcMesh.rounded_box(Vector3(0.52, 0.06, 0.44), 0.03, 2), ProcMesh.xf(Vector3(-0.17, 0.03, -0.2), Vector3(0, 8, 0)), tones[0]))
	parts.append(ProcMesh.part(ProcMesh.rounded_box(Vector3(0.46, 0.06, 0.42), 0.03, 2), ProcMesh.xf(Vector3(0.19, 0.03, 0.22), Vector3(0, -11, 0)), tones[1]))
	var mi := EggProps.mesh(ProcMesh.merge(parts), stone(Color.WHITE))
	(mi.material_override as StandardMaterial3D).vertex_color_use_as_albedo = true
	n.add_child(mi)
	return n


## A 2 x 1 m raised bed: stone kerb, dark soil, a mix of flowers.
static func flower_bed() -> Node3D:
	var n := Node3D.new()
	var k: StandardMaterial3D = stone()
	for z: float in [-0.46, 0.46]:
		n.add_child(EggProps.mesh(ProcMesh.rounded_box(Vector3(1.96, 0.22, 0.09), 0.02, 2), k, Vector3(0, 0.11, z)))
	for x: float in [-0.94, 0.94]:
		n.add_child(EggProps.mesh(ProcMesh.rounded_box(Vector3(0.09, 0.22, 0.84), 0.02, 2), k, Vector3(x, 0.11, 0)))
	n.add_child(EggProps.mesh(ProcMesh.box(Vector3(1.8, 0.04, 0.84)), paint(Color(0.2, 0.15, 0.11), 0.95), Vector3(0, 0.18, 0)))
	var r := RandomNumberGenerator.new()
	r.seed = 77
	var ids: Array[String] = ["flower_gazania", "flower_heliophila", "celandine_01"]
	for i: int in 9:
		var p := Vector3(-0.75 + (i % 5) * 0.37 + r.randf_range(-0.06, 0.06), 0.19, -0.2 + (i / 5) * 0.4 + r.randf_range(-0.06, 0.06))
		_vendor(n, ids[i % ids.size()], r.randf_range(0.22, 0.34), p, r.randf_range(0, 360))
	return n


## A white hex planter with a thin light seam under the rim and a shrub.
static func planter() -> Node3D:
	var n := Node3D.new()
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.42, 0.36, 0.5, 6), paint(Color(0.9, 0.9, 0.88), 0.35), Vector3(0, 0.25, 0)))
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.43, 0.43, 0.012, 6), Mats.lamp(Color(0.6, 1.0, 0.85), 0.9), Vector3(0, 0.44, 0)))
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.38, 0.38, 0.03, 6), paint(Color(0.2, 0.15, 0.11), 0.95), Vector3(0, 0.49, 0)))
	_vendor(n, "shrub_01", 0.75, Vector3(0, 0.48, 0))
	return n


## Wood slats on two cast-iron feet, with a back rest.
static func bench() -> Node3D:
	var n := Node3D.new()
	var iron: StandardMaterial3D = paint(Color(0.12, 0.13, 0.13), 0.5, 0.6)
	var w: StandardMaterial3D = wood()
	for x: float in [-0.75, 0.75]:
		n.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.06, 0.42, 0.46)), iron, Vector3(x, 0.21, 0.02)))
		n.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.06, 0.5, 0.06)), iron, Vector3(x, 0.66, -0.2), Vector3(-12, 0, 0)))
		n.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.07, 0.05, 0.36)), iron, Vector3(x, 0.62, 0.05)))
	for i: int in 4:
		n.add_child(EggProps.mesh(ProcMesh.rounded_box(Vector3(1.8, 0.04, 0.09), 0.012, 1), w, Vector3(0, 0.44, -0.16 + i * 0.11)))
	for i: int in 3:
		n.add_child(EggProps.mesh(ProcMesh.rounded_box(Vector3(1.8, 0.09, 0.035), 0.012, 1), w, Vector3(0, 0.58 + i * 0.12, -0.21 - i * 0.025), Vector3(-12, 0, 0)))
	EggProps.collider(n, Vector3(1.7, 0.45, 0.45), Vector3(0, 0.22, 0))
	return n


## A slim garden lamp; the light only comes on in the dark (dim, short range, no shadows).
static func lamp() -> Node3D:
	var n := Node3D.new()
	var dark: StandardMaterial3D = paint(Color(0.16, 0.18, 0.18), 0.4, 0.7)
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.11, 0.14, 0.12, 12), dark, Vector3(0, 0.06, 0)))
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.035, 0.045, 2.2, 10), dark, Vector3(0, 1.16, 0)))
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.13, 0.05, 0.08, 12), dark, Vector3(0, 2.3, 0)))
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.09, 0.09, 0.2, 12), Mats.lamp(Color(1.0, 0.85, 0.6), 1.4), Vector3(0, 2.16, 0)))
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.02, 0.13, 0.06, 12), dark, Vector3(0, 2.36, 0)))
	var l := EggProps.glow(Color(1.0, 0.84, 0.62), 0.9, 5.5, Vector3(0, 2.05, 0))
	l.name = "Light"
	l.shadow_enabled = false
	n.add_child(l)
	return n


## A stone basin on a fluted pedestal, full of clean water.
static func bird_bath() -> Node3D:
	var n := Node3D.new()
	var s: StandardMaterial3D = stone(Color(0.84, 0.82, 0.78))
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.24, 0.3, 0.08, 16), s, Vector3(0, 0.04, 0)))
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.09, 0.13, 0.62, 12), s, Vector3(0, 0.39, 0)))
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.4, 0.12, 0.16, 20), s, Vector3(0, 0.76, 0)))
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.35, 0.35, 0.01, 20), water(), Vector3(0, 0.82, 0)))
	return n


## A two-tier fountain, running again (a basin, a column, a bowl and a finial).
static func fountain() -> Node3D:
	var n := Node3D.new()
	var s: StandardMaterial3D = stone(Color(0.86, 0.84, 0.8))
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.95, 0.98, 0.42, 28), s, Vector3(0, 0.21, 0)))
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.85, 0.85, 0.02, 28), water(), Vector3(0, 0.36, 0)))
	n.add_child(EggProps.mesh(ProcMesh.torus(0.86, 0.98, 28, 6), s, Vector3(0, 0.43, 0)))
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.12, 0.16, 0.9, 14), s, Vector3(0, 0.8, 0)))
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.5, 0.16, 0.18, 22), s, Vector3(0, 1.28, 0)))
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.44, 0.44, 0.015, 22), water(), Vector3(0, 1.36, 0)))
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.05, 0.08, 0.3, 10), s, Vector3(0, 1.5, 0)))
	n.add_child(EggProps.mesh(ProcMesh.sphere(0.08, 12, 6), s, Vector3(0, 1.68, 0)))
	# Falling water: thin translucent sheets from the bowl lip to the basin.
	var fall := StandardMaterial3D.new()
	fall.albedo_color = Color(0.75, 0.88, 0.95, 0.32)
	fall.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fall.roughness = 0.05
	fall.cull_mode = BaseMaterial3D.CULL_DISABLED
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.5, 0.62, 0.9, 22), fall, Vector3(0, 0.84, 0)))
	EggProps.collider(n, Vector3(1.8, 0.5, 1.8), Vector3(0, 0.25, 0))
	return n


## A Maker on a plinth, watering can in hand.
static func statue() -> Node3D:
	var n := Node3D.new()
	var s: StandardMaterial3D = stone(Color(0.8, 0.79, 0.76))
	var fig: StandardMaterial3D = stone(Color(0.7, 0.71, 0.7))
	n.add_child(EggProps.mesh(ProcMesh.rounded_box(Vector3(1.1, 0.6, 1.1), 0.04, 2), s, Vector3(0, 0.3, 0)))
	n.add_child(EggProps.mesh(ProcMesh.rounded_box(Vector3(1.25, 0.1, 1.25), 0.03, 2), s, Vector3(0, 0.05, 0)))
	var b := Node3D.new()
	b.position = Vector3(0, 0.6, 0)
	n.add_child(b)
	for sx: float in [-1.0, 1.0]:
		b.add_child(EggProps.mesh(ProcMesh.capsule(0.09, 0.8), fig, Vector3(sx * 0.11, 0.4, 0)))
	b.add_child(EggProps.mesh(ProcMesh.capsule(0.21, 0.78), fig, Vector3(0, 1.05, 0)))
	b.add_child(EggProps.mesh(ProcMesh.sphere(0.14, 14, 8), fig, Vector3(0, 1.58, 0.02)))
	b.add_child(EggProps.mesh(ProcMesh.cyl(0.2, 0.22, 0.04, 14), fig, Vector3(0, 1.68, 0.02), Vector3(-6, 0, 0)))
	b.add_child(EggProps.mesh(ProcMesh.capsule(0.06, 0.55), fig, Vector3(-0.27, 1.05, 0.08), Vector3(20, 0, -14)))
	b.add_child(EggProps.mesh(ProcMesh.capsule(0.06, 0.55), fig, Vector3(0.28, 1.12, 0.15), Vector3(70, 0, 12)))
	_vendor(b, "watering_can_metal_01", 0.3, Vector3(0.32, 1.05, 0.42), 90.0)
	EggProps.collider(n, Vector3(1.1, 2.4, 1.1), Vector3(0, 1.2, 0))
	return n


## Topiary Lumi holding up a seedling: clipped box body, domed head, brass eyes and antenna.
static func lumi_sculpture() -> Node3D:
	var n := Node3D.new()
	var s: StandardMaterial3D = stone(Color(0.84, 0.83, 0.8))
	var hedge: StandardMaterial3D = leaves(Color(0.26, 0.44, 0.2))
	var brass: StandardMaterial3D = Mats.metal("brass")
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.9, 0.95, 0.3, 6), s, Vector3(0, 0.15, 0)))
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.91, 0.91, 0.012, 6), Mats.lamp(Color(0.6, 1.0, 0.85), 0.8), Vector3(0, 0.28, 0)))
	n.add_child(EggProps.mesh(ProcMesh.rounded_box(Vector3(0.9, 0.85, 0.75), 0.22, 4), hedge, Vector3(0, 0.78, 0)))
	n.add_child(EggProps.mesh(ProcMesh.hemisphere(0.48, 18, 8), hedge, Vector3(0, 1.2, 0)))
	for sx: float in [-1.0, 1.0]:
		n.add_child(EggProps.mesh(ProcMesh.cyl(0.11, 0.11, 0.04, 16), brass, Vector3(sx * 0.18, 1.42, 0.4), Vector3(90, 0, 0)))
		n.add_child(EggProps.mesh(ProcMesh.capsule(0.09, 0.5), hedge, Vector3(sx * 0.52, 1.05, 0.12), Vector3(-50, 0, sx * -20)))
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.015, 0.015, 0.35, 6), brass, Vector3(0, 1.82, 0)))
	n.add_child(EggProps.mesh(ProcMesh.sphere(0.07, 12, 6), brass, Vector3(0, 2.02, 0)))
	_vendor(n, "pine_sapling_small", 0.35, Vector3(0, 1.32, 0.62))
	EggProps.collider(n, Vector3(1.0, 2.0, 1.0), Vector3(0, 1.0, 0))
	return n


## A kite in WREN's bird shape on a long tether from a post. Always catching a breeze.
static func wren_kite() -> Node3D:
	var n := Node3D.new()
	var dark: StandardMaterial3D = paint(Color(0.2, 0.22, 0.22), 0.4, 0.6)
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.03, 0.04, 1.3, 8), dark, Vector3(0, 0.65, 0)))
	var top := Vector3(0, 1.3, 0)
	var kite_at := Vector3(0.6, 4.6, -1.4)
	n.add_child(EggProps.strut(top, kite_at, 0.004, paint(Color(0.9, 0.9, 0.86))))
	var k := Node3D.new()
	k.name = "Anim"
	k.position = kite_at
	k.rotation_degrees = Vector3(-60, 20, 8)
	n.add_child(k)
	var sail: StandardMaterial3D = paint(Color(0.35, 0.78, 0.72), 0.5)
	sail.cull_mode = BaseMaterial3D.CULL_DISABLED
	k.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.18, 0.02, 0.7)), sail, Vector3(0, 0, 0)))
	for sx: float in [-1.0, 1.0]:
		k.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.6, 0.015, 0.28)), sail, Vector3(sx * 0.36, 0, -0.04), Vector3(0, sx * 18, 0)))
	k.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.3, 0.015, 0.2)), paint(Color(1.0, 0.7, 0.26), 0.5), Vector3(0, 0, 0.42), Vector3(0, 45, 0)))
	return n
