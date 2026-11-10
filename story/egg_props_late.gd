class_name EggPropsLate
extends RefCounted
## [late] The newer curiosities (data/eggs.json, the last dozen): their props, little reactions and
## where they may appear. Frontier eggs ("where": "frontier") only turn up in the frontier whose
## biome matches.


## Frontier-only eggs for a district of this biome (data order).
static func frontier_eggs(all_ids: Array[String], all_defs: Dictionary, biome: String) -> Array[String]:
	var out: Array[String] = []
	if biome == "":
		return out
	for id: String in all_ids:
		if str(all_defs[id].get("where", "")) == "frontier" and str(all_defs[id].get("biome", "")) == biome:
			out.append(id)
	return out


static func build(kind: String, _part: int = 0) -> Node3D:
	match kind:
		"sand_piano": return sand_piano()
		"snow_bot": return snow_bot()
		"bottle": return bottle()
		"welcome_sign": return welcome_sign()
		"crossword": return crossword()
		"hopscotch": return hopscotch()
		"balloon": return balloon()
		"mailbox": return mailbox()
		"bonsai": return bonsai()
		"dish": return dish()
		"old_pod": return old_pod()
		"heir_tin": return heir_tin()
	return null


static func show_found_state(node: Node3D, kind: String) -> void:
	if kind == "balloon":
		var b: Node3D = node.get_node_or_null("Anim/Balloon")
		if b:
			b.visible = false


## A curiosity's reaction (also replayed after it has been found). `eggs` is the EasterEggs node.
static func effect(eggs: Node, e: Dictionary) -> void:
	var n: Node3D = e["node"]
	var anim: Node3D = n.get_node_or_null("Anim")
	var top: Vector3 = n.global_position + Vector3(0, 1.6, 0)
	match str(e["kind"]):
		"sand_piano":
			for k: int in 3:
				eggs.get_tree().create_timer(0.35 * k, false).timeout.connect(func() -> void: Audio.play("ding", 0.55 + 0.07 * k * k, -6.0, 0.0))
			Vfx.float_text(top, "♪", Color(1.0, 0.9, 0.6), 1.3, 1.2)
			eggs.call("_wobble", anim, 0.03)
			Vfx.burst("dust", n.global_position + Vector3(0, 0.3, 0.4), Color(0.85, 0.72, 0.52))
		"snow_bot":
			eggs.call("_hop", anim)
			eggs.call("_flash", n.get_node_or_null("Anim/Eyes"), Color(0.6, 0.95, 1.0), 3.0)
			Audio.play("beep", 0.7, -8.0)
			Vfx.burst("sparkle", top, Color(0.9, 0.97, 1.0), 0.7)
		"bottle", "old_pod", "heir_tin":
			Audio.play("dig", 1.1, -6.0)
			Vfx.burst("soil", n.global_position + Vector3(0, 0.2, 0), Color(0.5, 0.4, 0.3))
			Vfx.burst("sparkle", n.global_position + Vector3(0, 0.6, 0), Color(0.8, 1.0, 0.7), 0.6)
		"welcome_sign":
			Audio.play("chime", 0.9, -4.0)
			Vfx.burst("big_sparkle", top + Vector3(0, 0.6, 0), Color(1.0, 0.85, 0.55))
		"hopscotch":
			for k: int in 3:
				eggs.get_tree().create_timer(0.3 * k, false).timeout.connect(func() -> void:
					Audio.play_scale("blip", k * 2, -8.0)
					Vfx.float_text(n.global_position + Vector3(0, 0.6, -0.9 + 0.8 * k), str(k + 1), Color(1.0, 1.0, 0.9), 1.0, 0.8))
		"balloon":
			var b: Node3D = n.get_node_or_null("Anim/Balloon")
			if b and b.visible:
				var tw := b.create_tween()
				tw.tween_property(b, "position", b.position + Vector3(0.6, 14.0, -0.8), 6.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
				tw.tween_callback(func() -> void: b.visible = false)
			Audio.play("squeak", 1.4, -8.0)
		"mailbox":
			eggs.call("_wobble", anim, 0.05)
			Audio.play("clink", 0.8, -6.0)
		"crossword":
			Audio.play("click", 0.9, -6.0)
		"bonsai":
			Audio.play("bird", 1.1, -8.0)
			Vfx.burst("sparkle", n.global_position + Vector3(0, 0.9, 0), Color(0.75, 1.0, 0.65), 0.5)
		"dish":
			if anim:
				var tw2 := anim.create_tween()
				tw2.tween_property(anim, "rotation:y", anim.rotation.y + 0.35, 1.0).set_trans(Tween.TRANS_SINE)
			eggs.get_tree().create_timer(1.1, false).timeout.connect(func() -> void:
				Audio.play("beep", 0.5, -6.0)
				Vfx.float_text(top + Vector3(0, 0.5, 0), "· · ·  — — —  · · ·", Color(0.6, 1.0, 0.85), 1.1, 1.4))


# --- Builders -----------------------------------------------------------------------------

static func _sand() -> StandardMaterial3D:
	return DecorProps.paint(Color(0.82, 0.69, 0.5), 0.95)


## An upright piano sunk to its keys in a dune.
static func sand_piano() -> Node3D:
	var n := Node3D.new()
	var a := Node3D.new()
	a.name = "Anim"
	a.position = Vector3(0, -0.3, 0)
	a.rotation_degrees = Vector3(-6, 0, 4)
	n.add_child(a)
	var wood: ShaderMaterial = Mats.worn_paint(Color(0.18, 0.11, 0.07), 0.75, 0.0, 141.0, 0.8)
	a.add_child(EggProps.mesh(ProcMesh.rounded_box(Vector3(1.45, 1.25, 0.58), 0.03, 2), wood, Vector3(0, 0.62, 0)))
	a.add_child(EggProps.mesh(ProcMesh.box(Vector3(1.5, 0.05, 0.62)), wood, Vector3(0, 1.27, 0)))
	a.add_child(EggProps.mesh(ProcMesh.box(Vector3(1.35, 0.06, 0.24)), wood, Vector3(0, 0.66, 0.38)))
	var ivory: StandardMaterial3D = DecorProps.paint(Color(0.88, 0.84, 0.74), 0.4)
	a.add_child(EggProps.mesh(ProcMesh.box(Vector3(1.24, 0.03, 0.16)), ivory, Vector3(0, 0.705, 0.42)))
	var ebony: StandardMaterial3D = DecorProps.paint(Color(0.05, 0.05, 0.05), 0.35)
	for k: int in 18:
		if k % 7 in [2, 6]:
			continue
		a.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.03, 0.025, 0.09)), ebony, Vector3(-0.58 + k * 0.068, 0.73, 0.39)))
	var sand: StandardMaterial3D = _sand()
	n.add_child(EggProps.mesh(ProcMesh.hemisphere(1.0, 20, 6), sand, Vector3(0, -0.05, 0.05), Vector3.ZERO, Vector3(1.25, 0.42, 0.85)))
	n.add_child(EggProps.mesh(ProcMesh.hemisphere(0.6, 16, 5), sand, Vector3(0.9, -0.03, -0.3), Vector3.ZERO, Vector3(1.0, 0.35, 1.2)))
	EggProps.collider(n, Vector3(1.4, 1.0, 0.6), Vector3(0, 0.5, 0))
	return n


## Three packed snowballs around a loader robot's frame, with a scarf and lamp eyes.
static func snow_bot() -> Node3D:
	var n := Node3D.new()
	var snow: StandardMaterial3D = DecorProps.paint(Color(0.93, 0.95, 0.98), 0.9)
	n.add_child(EggProps.mesh(ProcMesh.sphere(0.5, 16, 8), snow, Vector3(0, 0.42, 0), Vector3.ZERO, Vector3(1, 0.9, 1)))
	n.add_child(EggProps.mesh(ProcMesh.sphere(0.37, 16, 8), snow, Vector3(0, 1.06, 0)))
	var steel: ShaderMaterial = Mats.worn_paint(Color(0.9, 0.62, 0.15), 0.6, 0.6, 142.0, 0.5)
	for sx: float in [-1.0, 1.0]:
		n.add_child(EggProps.strut(Vector3(sx * 0.3, 1.1, 0), Vector3(sx * 0.75, 1.45, 0.1), 0.035, steel))
		n.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.1, 0.06, 0.14)), steel, Vector3(sx * 0.78, 1.47, 0.1)))
	var a := Node3D.new()
	a.name = "Anim"
	a.position = Vector3(0, 1.48, 0)
	n.add_child(a)
	a.add_child(EggProps.mesh(ProcMesh.sphere(0.27, 14, 7), snow, Vector3(0, 0.12, 0)))
	var eyes := EggProps.mesh(ProcMesh.box(Vector3(0.26, 0.05, 0.03)), Mats.lamp(Color(0.5, 0.85, 1.0), 0.6), Vector3(0, 0.17, 0.25))
	eyes.name = "Eyes"
	a.add_child(eyes)
	a.add_child(EggProps.mesh(ProcMesh.cyl(0.17, 0.21, 0.24, 14), Mats.worn_paint(Color(0.3, 0.32, 0.34), 0.5, 0.7, 143.0, 0.4), Vector3(0, 0.44, 0), Vector3(0, 0, 8)))
	n.add_child(EggProps.mesh(ProcMesh.torus(0.22, 0.34, 18, 8), DecorProps.paint(Color(0.72, 0.16, 0.14), 0.9), Vector3(0, 1.38, 0)))
	n.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.14, 0.42, 0.04)), DecorProps.paint(Color(0.72, 0.16, 0.14), 0.9), Vector3(0.14, 1.15, 0.33), Vector3(8, 0, -6)))
	EggProps.collider(n, Vector3(0.8, 1.9, 0.8), Vector3(0, 0.95, 0))
	return n


## A corked green bottle lying in the silt.
static func bottle() -> Node3D:
	var n := Node3D.new()
	var a := Node3D.new()
	a.name = "Anim"
	a.position = Vector3(0, 0.07, 0)
	a.rotation_degrees = Vector3(0, 30, 88)
	n.add_child(a)
	var glass: StandardMaterial3D = Mats.glass(Color(0.16, 0.38, 0.2, 0.75), 0.1)
	a.add_child(EggProps.mesh(ProcMesh.cyl(0.065, 0.07, 0.24, 14), glass))
	a.add_child(EggProps.mesh(ProcMesh.cyl(0.025, 0.06, 0.08, 12), glass, Vector3(0, 0.16, 0)))
	a.add_child(EggProps.mesh(ProcMesh.cyl(0.024, 0.024, 0.05, 8), DecorProps.paint(Color(0.55, 0.4, 0.26), 0.9), Vector3(0, 0.215, 0)))
	a.add_child(EggProps.mesh(ProcMesh.cyl(0.03, 0.03, 0.18, 8), DecorProps.paint(Color(0.92, 0.88, 0.76), 0.9), Vector3(0, -0.01, 0)))
	n.add_child(EggProps.mesh(ProcMesh.hemisphere(0.3, 12, 4), DecorProps.paint(Color(0.36, 0.35, 0.3), 0.95), Vector3.ZERO, Vector3.ZERO, Vector3(1.3, 0.15, 1.0)))
	return n


## A painted banner on two poles: WELCOME HOME, CRADLE (old spellings crossed out).
static func welcome_sign() -> Node3D:
	var n := Node3D.new()
	var pole: StandardMaterial3D = DecorProps.paint(Color(0.85, 0.85, 0.82), 0.5, 0.4)
	for x: float in [-1.6, 1.6]:
		n.add_child(EggProps.mesh(ProcMesh.cyl(0.04, 0.05, 2.6, 8), pole, Vector3(x, 1.3, 0)))
	var cloth: StandardMaterial3D = DecorProps.paint(Color(0.93, 0.9, 0.8), 0.9)
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	n.add_child(EggProps.mesh(ProcMesh.box(Vector3(3.1, 0.8, 0.02)), cloth, Vector3(0, 2.05, 0)))
	n.add_child(EggProps.label("WELCOME HOME, CRADLE", 64, Color(0.2, 0.42, 0.3), Vector3(0, 2.0, 0.02)))
	var old := EggProps.label("WELLCOME HOEM", 30, Color(0.55, 0.35, 0.3, 0.8), Vector3(-0.6, 2.32, 0.02), Vector3(0, 0, 2))
	n.add_child(old)
	n.add_child(EggProps.mesh(ProcMesh.box(Vector3(1.15, 0.015, 0.01)), DecorProps.paint(Color(0.55, 0.35, 0.3)), Vector3(-0.6, 2.33, 0.03), Vector3(0, 0, 2)))
	return n


## A folded newspaper and a pen on a wooden crate.
static func crossword() -> Node3D:
	var n := Node3D.new()
	n.add_child(EggProps.model("wooden_crate_02", Vector3.ZERO, 0.0, EggProps._fit("wooden_crate_02", 0.5)))
	var paper: StandardMaterial3D = DecorProps.paint(Color(0.86, 0.84, 0.78), 0.95)
	n.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.34, 0.012, 0.24)), paper, Vector3(0.02, 0.51, 0.0), Vector3(0, 12, 0)))
	n.add_child(EggProps.label("CROSSWORD", 28, Color(0.15, 0.15, 0.15), Vector3(0.02, 0.518, -0.06), Vector3(-90, 12, 0)))
	var grid_l := EggProps.label("▦▦▦▦\n▦▦▦▦", 24, Color(0.2, 0.2, 0.2), Vector3(0.03, 0.518, 0.04), Vector3(-90, 12, 0))
	n.add_child(grid_l)
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.006, 0.006, 0.14, 6), DecorProps.paint(Color(0.1, 0.2, 0.6), 0.3), Vector3(0.16, 0.52, 0.08), Vector3(0, 0, 90)))
	return n


## Chalk squares on the pavement, a pebble on seven.
static func hopscotch() -> Node3D:
	var n := Node3D.new()
	var chalk := StandardMaterial3D.new()
	chalk.albedo_color = Color(0.92, 0.92, 0.88, 0.85)
	chalk.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	chalk.roughness = 1.0
	var rows: Array = [[0.0], [0.0], [-0.3, 0.3], [0.0], [-0.3, 0.3], [0.0], [0.0]]
	var num: int = 1
	for r: int in rows.size():
		for x: float in rows[r]:
			var c := Vector3(x, 0.012, -1.6 + r * 0.55)
			for side: Array in [[Vector3(0, 0, -0.27), Vector3(0.58, 0.004, 0.025)], [Vector3(0, 0, 0.27), Vector3(0.58, 0.004, 0.025)],
					[Vector3(-0.28, 0, 0), Vector3(0.025, 0.004, 0.56)], [Vector3(0.28, 0, 0), Vector3(0.025, 0.004, 0.56)]]:
				n.add_child(EggProps.mesh(ProcMesh.box(side[1]), chalk, c + (side[0] as Vector3)))
			n.add_child(EggProps.label(str(num), 72, Color(0.95, 0.95, 0.9, 0.85), c + Vector3(0, 0.006, 0), Vector3(-90, 180, 0)))
			if num == 7:
				n.add_child(EggProps.mesh(ProcMesh.sphere(0.04, 8, 4), DecorProps.stone(Color(0.6, 0.58, 0.55)), c + Vector3(0.1, 0.02, 0.08), Vector3.ZERO, Vector3(1, 0.6, 1)))
			num += 1
	return n


## A red balloon still tied to a sign post.
static func balloon() -> Node3D:
	var n := Node3D.new()
	var post: StandardMaterial3D = DecorProps.paint(Color(0.45, 0.47, 0.48), 0.5, 0.7)
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.035, 0.035, 2.2, 8), post, Vector3(0, 1.1, 0)))
	n.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.5, 0.36, 0.02)), Mats.worn_paint(Color(0.15, 0.35, 0.6), 0.7, 0.5, 144.0, 0.6), Vector3(0, 2.05, 0.04)))
	var a := Node3D.new()
	a.name = "Anim"
	n.add_child(a)
	var b := Node3D.new()
	b.name = "Balloon"
	b.position = Vector3(0.35, 3.1, 0.15)
	a.add_child(b)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.85, 0.08, 0.08)
	red.roughness = 0.18
	red.clearcoat_enabled = true
	b.add_child(EggProps.mesh(ProcMesh.sphere(0.24, 16, 10), red, Vector3.ZERO, Vector3.ZERO, Vector3(1, 1.18, 1)))
	b.add_child(EggProps.mesh(ProcMesh.cyl(0.0, 0.035, 0.05, 8), red, Vector3(0, -0.3, 0)))
	b.add_child(EggProps.strut(Vector3(0, -0.32, 0), Vector3(-0.32, -1.6, -0.12), 0.003, DecorProps.paint(Color(0.9, 0.9, 0.9))))
	return n


## A street mailbox so full the flap won't shut.
static func mailbox() -> Node3D:
	var n := Node3D.new()
	var a := Node3D.new()
	a.name = "Anim"
	n.add_child(a)
	var blue: ShaderMaterial = Mats.worn_paint(Color(0.12, 0.25, 0.5), 0.8, 0.45, 145.0, 0.6)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			a.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.05, 0.35, 0.05)), blue, Vector3(sx * 0.2, 0.17, sz * 0.22)))
	a.add_child(EggProps.mesh(ProcMesh.rounded_box(Vector3(0.5, 0.75, 0.55), 0.05, 2), blue, Vector3(0, 0.72, 0)))
	a.add_child(EggProps.mesh(ProcMesh.cyl(0.25, 0.25, 0.55, 16), blue, Vector3(0, 1.1, 0), Vector3(90, 0, 0)))
	a.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.3, 0.07, 0.04)), Mats.metal("dark_steel"), Vector3(0, 1.0, 0.29), Vector3(-25, 0, 0)))
	var paper: StandardMaterial3D = DecorProps.paint(Color(0.92, 0.9, 0.84), 0.95)
	for k: int in 4:
		a.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.2, 0.004, 0.13)), paper, Vector3(-0.07 + k * 0.045, 1.02 + k * 0.01, 0.3), Vector3(-30 + k * 6, k * 9 - 12, 0)))
	n.add_child(EggProps.label("MAIL", 40, Color(0.92, 0.9, 0.84), Vector3(0, 0.82, 0.28)))
	EggProps.collider(n, Vector3(0.5, 1.3, 0.55), Vector3(0, 0.65, 0))
	return n


## A tiny, ancient tree on a little wooden stand.
static func bonsai() -> Node3D:
	var n := Node3D.new()
	var w: StandardMaterial3D = DecorProps.wood(Color(0.42, 0.28, 0.18))
	n.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.5, 0.04, 0.36)), w, Vector3(0, 0.6, 0)))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			n.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.04, 0.58, 0.04)), w, Vector3(sx * 0.21, 0.29, sz * 0.14)))
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.16, 0.12, 0.08, 16), DecorProps.paint(Color(0.28, 0.36, 0.42), 0.25), Vector3(0, 0.66, 0)))
	var bark: StandardMaterial3D = DecorProps.paint(Color(0.3, 0.22, 0.16), 0.9)
	var pts: Array[Vector3] = [Vector3(0, 0.7, 0), Vector3(0.04, 0.8, 0.01), Vector3(-0.03, 0.9, 0.0), Vector3(0.05, 0.98, -0.02)]
	for i: int in pts.size() - 1:
		n.add_child(EggProps.strut(pts[i], pts[i + 1], 0.022 - i * 0.004, bark))
	var leaf: StandardMaterial3D = DecorProps.leaves(Color(0.22, 0.4, 0.18))
	for p: Vector3 in [Vector3(0.08, 1.0, 0), Vector3(-0.08, 0.93, 0.02), Vector3(0.0, 1.06, -0.03), Vector3(0.12, 0.88, 0.04)]:
		n.add_child(EggProps.mesh(ProcMesh.sphere(0.08, 10, 5), leaf, p, Vector3.ZERO, Vector3(1.4, 0.55, 1.2)))
	return n


## A homemade dish on a tripod, still listening, with a note taped to the arm.
static func dish() -> Node3D:
	var n := Node3D.new()
	var steel: ShaderMaterial = Mats.worn_paint(Color(0.82, 0.82, 0.8), 0.7, 0.6, 146.0, 0.6)
	for k: int in 3:
		var ang: float = TAU * k / 3.0
		n.add_child(EggProps.strut(Vector3(cos(ang) * 0.5, 0, sin(ang) * 0.5), Vector3(0, 1.0, 0), 0.02, steel))
	var a := Node3D.new()
	a.name = "Anim"
	a.position = Vector3(0, 1.05, 0)
	n.add_child(a)
	var head := Node3D.new()
	head.rotation_degrees = Vector3(-50, 0, 0)
	a.add_child(head)
	var dish_m: ShaderMaterial = Mats.worn_paint(Color(0.9, 0.9, 0.88), 0.85, 0.35, 147.0, 0.5)
	head.add_child(EggProps.mesh(ProcMesh.hemisphere(0.55, 22, 6), dish_m, Vector3(0, 0, 0), Vector3(180, 0, 0), Vector3(1, 0.35, 1)))
	head.add_child(EggProps.strut(Vector3(0, 0, 0), Vector3(0, 0.55, 0), 0.012, steel))
	head.add_child(EggProps.mesh(ProcMesh.cyl(0.04, 0.05, 0.1, 10), Mats.metal("dark_steel"), Vector3(0, 0.58, 0)))
	n.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.14, 0.1, 0.005)), DecorProps.paint(Color(1.0, 0.92, 0.45), 0.9), Vector3(0.0, 0.7, 0.12), Vector3(-10, 0, 4)))
	return n


## An older seed pod from the Cradle, half buried and overgrown, hatch open.
static func old_pod() -> Node3D:
	var n := Node3D.new()
	var shell: ShaderMaterial = Mats.worn_paint(Color(0.82, 0.8, 0.74), 0.45, 0.9, 148.0, 0.9)
	var a := Node3D.new()
	a.name = "Anim"
	a.position = Vector3(0, 0.25, 0)
	a.rotation_degrees = Vector3(0, 0, 28)
	n.add_child(a)
	a.add_child(EggProps.mesh(ProcMesh.capsule(0.55, 1.9), shell, Vector3.ZERO, Vector3(0, 0, 90)))
	a.add_child(EggProps.mesh(ProcMesh.cyl(0.3, 0.3, 0.04, 16), Mats.metal("dark_steel"), Vector3(0.2, 0.56, 0.1), Vector3(10, 0, -20)))
	a.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.25, 0.04, 0.12)), Mats.lamp(Color(0.6, 1.0, 0.7), 0.25), Vector3(-0.5, 0.45, 0.25)))
	var moss: StandardMaterial3D = DecorProps.leaves(Color(0.28, 0.42, 0.2))
	var r := RandomNumberGenerator.new()
	r.seed = 5
	for k: int in 7:
		a.add_child(EggProps.mesh(ProcMesh.sphere(0.18, 10, 5), moss, Vector3(r.randf_range(-0.8, 0.8), r.randf_range(0.2, 0.5), r.randf_range(-0.35, 0.35)), Vector3.ZERO, Vector3(1.4, 0.35, 1.1)))
	n.add_child(EggProps.mesh(ProcMesh.hemisphere(1.0, 18, 5), DecorProps.paint(Color(0.33, 0.27, 0.2), 0.95), Vector3(0, -0.05, 0), Vector3.ZERO, Vector3(1.5, 0.3, 0.9)))
	EggProps.collider(n, Vector3(2.0, 0.9, 1.1), Vector3(0, 0.45, 0))
	return n


## Lumi's own seed tin from home, spilled on new ground, a sprout already up.
static func heir_tin() -> Node3D:
	var n := Node3D.new()
	var tin: StandardMaterial3D = DecorProps.paint(Color(0.3, 0.5, 0.36), 0.35, 0.6)
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.11, 0.11, 0.2, 18), tin, Vector3(0, 0.11, 0), Vector3(90, 20, 0)))
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.115, 0.115, 0.02, 18), Mats.metal("brass"), Vector3(-0.2, 0.03, 0.15), Vector3(0, 0, 80)))
	n.add_child(EggProps.mesh(ProcMesh.hemisphere(0.25, 12, 4), DecorProps.paint(Color(0.22, 0.16, 0.1), 0.95), Vector3(0.07, 0.0, 0.18), Vector3.ZERO, Vector3(1.2, 0.18, 1.0)))
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.006, 0.008, 0.12, 6), DecorProps.leaves(Color(0.35, 0.6, 0.25)), Vector3(0.1, 0.07, 0.2)))
	for sx: float in [-1.0, 1.0]:
		n.add_child(EggProps.mesh(ProcMesh.sphere(0.03, 8, 4), DecorProps.leaves(Color(0.4, 0.68, 0.28)), Vector3(0.1 + sx * 0.03, 0.13, 0.2), Vector3.ZERO, Vector3(1.4, 0.3, 0.8)))
	return n
