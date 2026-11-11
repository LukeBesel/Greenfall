class_name FindProps
extends RefCounted
## The things that lie round and over a find in the world (systems/find_sites.gd), built from the
## shared art kit so they sit with the rest of the planet's junk:
##   junk(seed, n)       the heap on a wreck that Lumi clears by hand, one piece per pull: a bent
##                       sheet-metal panel, a tipped drum, a crate, a tyre, a length of pipe. Real
##                       junk is colourful (style guide section 9): painted metal, not brown.
##   cache(kind, tint)   a buried paint tin or lens chip: a low mound of turned soil with the lid's
##                       rim (or the chip's edge) catching the light.
##   dug(kind, tint)     the same thing out of the ground, for the moment it is lifted.
##   flowers(seed, tint) what grows round a wreck once it has given up its pieces.
## Every piece is its own node with its origin on the ground, +Y up.

const TIN: String = "tin"
const CHIP: String = "chip"
const JUNK_KINDS: Array[String] = ["panel", "drum", "crate", "tyre", "pipe"]
## Paint of the junk pieces, by kind: kit palette names or #rrggbb.
const JUNK_PAINT: Dictionary = {"panel": "teal", "drum": "red", "crate": "#2f74c0", "pipe": "yellow"}
const SOIL := Color(0.36, 0.27, 0.19)
const TIN_STEEL := Color(0.78, 0.79, 0.8)
const PETALS: Array[Color] = [Color(0.98, 0.82, 0.2), Color(0.95, 0.45, 0.62), Color(0.97, 0.96, 0.9), Color(0.55, 0.5, 0.95)]


## `n` junk pieces leaning on a wreck at the origin, each {node, kind}. The first lies across
## the wreck; the rest stand round it, leaving its raised arm and crown in view.
static func junk(heap_seed: int, n: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = heap_seed
	var turn: float = rng.randf() * TAU
	for k: int in n:
		var kind: String = JUNK_KINDS[k % JUNK_KINDS.size()]
		var holder := Node3D.new()
		holder.name = "Junk_%d_%s" % [k, kind]
		var a: float = turn + TAU * float(k) / float(maxi(n, 1)) + rng.randf_range(-0.25, 0.25)
		var r: float = 0.18 if k == 0 else rng.randf_range(0.62, 0.82)
		holder.position = Vector3(cos(a) * r, 0.0, sin(a) * r)
		holder.rotation.y = -a + PI * 0.5 + rng.randf_range(-0.3, 0.3)
		holder.add_child(_junk_mesh(kind, heap_seed + k * 31))
		out.append({"node": holder, "kind": kind})
	return out


static func _junk_mesh(kind: String, piece_seed: int) -> MeshInstance3D:
	var b := KitMesh.Builder.new(piece_seed, {}, "repaired")
	var paint: String = "paint:" + str(JUNK_PAINT.get(kind, "orange"))
	match kind:
		"panel":  # a bent body panel propped over the wreck
			b.box(paint, Vector3(1.25, 0.05, 0.85), KitMesh.xf(Vector3(0, 0.52, 0.1), Vector3(-38, 0, 6)), 0.02)
			b.box(paint, Vector3(1.25, 0.05, 0.4), KitMesh.xf(Vector3(0.02, 0.2, 0.62), Vector3(-72, 0, 6)), 0.02)
			for x: float in [-0.45, 0.0, 0.45]:
				b.box("dark_steel", Vector3(0.06, 0.035, 0.8), KitMesh.xf(Vector3(x, 0.555, 0.08), Vector3(-38, 0, 6)), 0.012)
		"drum":
			KitProps.barrel(b, KitMesh.xf(Vector3.ZERO, Vector3(0, 20, 0)), paint, true)
		"crate":
			KitProps.crate(b, KitMesh.xf(Vector3.ZERO, Vector3(0, 0, 14)), Vector3(0.62, 0.5, 0.62), paint)
		"tyre":
			var ring := PackedVector3Array()
			for i: int in 13:
				var t: float = TAU * float(i) / 12.0
				ring.append(Vector3(cos(t) * 0.3, 0.3 + sin(t) * 0.3, 0.0))
			b.add("rubber", KitMesh.sweep(ring, 0.11, 8), KitMesh.xf(Vector3(0, 0.02, 0), Vector3(28, 0, 0)))
			b.cyl("steel", 0.17, 0.1, KitMesh.xf(Vector3(0, 0.28, -0.05), Vector3(118, 0, 0)), 0.02, 12)
		_:  # pipe
			KitProps.pipe_run(b, KitMesh.xf(Vector3(0, 0.0, 0), Vector3(0, 0, 0)),
				PackedVector3Array([Vector3(-0.7, 0.1, 0.0), Vector3(0.1, 0.16, 0.0), Vector3(0.55, 0.62, 0.05)]), 0.07, paint)
	var mi: MeshInstance3D = KitMesh.instance(b)
	mi.name = "Mesh"
	return mi


## A buried find still in the ground: turned soil with a rim of the tin (or an edge of the chip)
## showing, and a child "Glint" light in the find's colour for the world to pulse.
static func cache(kind: String, tint: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Cache_" + kind
	var b := KitMesh.Builder.new(hash(kind), {}, "repaired")
	b.add("dirt", KitMesh.pebble(1), Transform3D(Basis().scaled(Vector3(0.36, 0.2, 0.32)), Vector3(0, 0.0, 0)), -1.0, 0.0)
	b.add("dirt", KitMesh.pebble(2), Transform3D(Basis(Vector3.UP, 1.9).scaled(Vector3(0.2, 0.12, 0.2)), Vector3(0.24, 0.0, 0.12)), -1.0, 0.0)
	b.add("dirt", KitMesh.pebble(3), Transform3D(Basis(Vector3.UP, 4.0).scaled(Vector3(0.16, 0.1, 0.18)), Vector3(-0.2, 0.0, -0.16)), -1.0, 0.0)
	var mound: MeshInstance3D = KitMesh.instance(b)
	mound.name = "Mound"
	root.add_child(mound)
	var thing: Node3D = dug(kind, tint)
	thing.name = "Thing"
	# Three quarters under: only the rim and a smear of colour show.
	thing.position = Vector3(0.03, -0.1 if kind == TIN else -0.02, 0.0)
	thing.rotation_degrees = Vector3(24, 35, -18)
	root.add_child(thing)
	var glint := OmniLight3D.new()
	glint.name = "Glint"
	glint.light_color = tint.lightened(0.25)
	glint.light_energy = 0.5
	glint.omni_range = 1.3
	glint.shadow_enabled = false
	glint.position = Vector3(0, 0.3, 0)
	root.add_child(glint)
	return root


## The find out of the ground: a dented paint tin with its colour run down the side, or a lens
## chip (a thick hexagon of coloured glass in a steel rim).
static func dug(kind: String, tint: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Dug_" + kind
	if kind == CHIP:
		var glass := StandardMaterial3D.new()
		glass.albedo_color = Color(tint.r, tint.g, tint.b, 0.82)
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.roughness = 0.08
		glass.metallic_specular = 0.9
		glass.emission_enabled = true
		glass.emission = tint
		glass.emission_energy_multiplier = 0.35
		root.add_child(EggProps.mesh(ProcMesh.cyl(0.085, 0.085, 0.03, 6), glass, Vector3(0, 0.02, 0)))
		root.add_child(EggProps.mesh(ProcMesh.cyl(0.1, 0.1, 0.022, 6), DecorProps.paint(TIN_STEEL, 0.3, 0.9), Vector3(0, 0.015, 0)))
		return root
	var steel: StandardMaterial3D = DecorProps.paint(TIN_STEEL, 0.32, 0.85)
	var paint: StandardMaterial3D = DecorProps.paint(tint, 0.35, 0.0)
	root.add_child(EggProps.mesh(ProcMesh.cyl(0.085, 0.085, 0.19, 20), steel, Vector3(0, 0.095, 0)))
	root.add_child(EggProps.mesh(ProcMesh.cyl(0.091, 0.091, 0.014, 20), steel, Vector3(0, 0.185, 0)))
	root.add_child(EggProps.mesh(ProcMesh.cyl(0.091, 0.091, 0.012, 20), steel, Vector3(0, 0.008, 0)))
	# The label band and the runs of paint from under the lid.
	root.add_child(EggProps.mesh(ProcMesh.cyl(0.0865, 0.0865, 0.09, 20), paint, Vector3(0, 0.085, 0)))
	root.add_child(EggProps.mesh(ProcMesh.cyl(0.07, 0.07, 0.006, 16), paint, Vector3(0, 0.194, 0)))
	for run: Array in [[0.4, 0.07], [1.7, 0.045], [2.6, 0.085], [4.4, 0.06]]:
		var a: float = run[0]
		var len_m: float = run[1]
		root.add_child(EggProps.mesh(ProcMesh.capsule(0.012, len_m + 0.024), paint, Vector3(cos(a) * 0.086, 0.18 - len_m * 0.5, sin(a) * 0.086)))
	# The wire handle, fallen to one side.
	root.add_child(EggProps.mesh(ProcMesh.torus(0.082, 0.089, 20, 6), steel, Vector3(0, 0.13, 0.03), Vector3(62, 0, 0)))
	return root


## A handful of grass tufts and flowers round a salvaged wreck: the ground taking it back.
static func flowers(patch_seed: int, tint: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Flowers"
	var rng := RandomNumberGenerator.new()
	rng.seed = patch_seed
	var stem: StandardMaterial3D = DecorProps.paint(Color(0.24, 0.5, 0.16), 0.7)
	var grass := StandardMaterial3D.new()
	grass.vertex_color_use_as_albedo = true
	grass.cull_mode = BaseMaterial3D.CULL_DISABLED
	grass.roughness = 0.8
	for k: int in 9:
		var a: float = rng.randf() * TAU
		var r: float = rng.randf_range(0.55, 1.15)
		var at := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var tuft: MeshInstance3D = EggProps.mesh(KitMesh.grass_tuft(), grass, at, Vector3(0, rng.randf() * 360.0, 0), Vector3.ONE * rng.randf_range(0.8, 1.3))
		tuft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(tuft)
		if k % 3 == 2:
			continue
		var h: float = rng.randf_range(0.22, 0.4)
		var petal: Color = tint.lightened(0.2) if k == 0 else PETALS[rng.randi() % PETALS.size()]
		root.add_child(EggProps.mesh(ProcMesh.cyl(0.008, 0.01, h, 5), stem, at + Vector3(0.05, h * 0.5, 0.03)))
		root.add_child(EggProps.mesh(ProcMesh.sphere(0.05, 8, 4), DecorProps.paint(petal, 0.6), at + Vector3(0.05, h, 0.03), Vector3.ZERO, Vector3(1, 0.45, 1)))
		root.add_child(EggProps.mesh(ProcMesh.sphere(0.02, 6, 3), DecorProps.paint(Color(0.95, 0.75, 0.15), 0.6), at + Vector3(0.05, h + 0.016, 0.03)))
	return root
