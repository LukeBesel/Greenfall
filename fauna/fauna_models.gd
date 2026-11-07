class_name FaunaModels
extends RefCounted
## [wild] Procedural animal meshes (low-poly but soft: ellipsoids and tapered limbs with a cheap
## rig, see FaunaMesh and art/shaders/fauna.gdshader). Poly Haven has only one CC0 animal that
## fits (street_rat), which the rat uses; everything else is built here. Cached per id.
## Sizes are real-world-ish (a cat is ~0.55 m nose to rump, a roe deer ~0.75 m at the shoulder).

const M = preload("res://fauna/fauna_mesh.gd")

static var _cache: Dictionary = {}

const WHITE := Color(0.93, 0.92, 0.88)
const EYE_DARK := Color(0.03, 0.025, 0.02)
const NOSE := Color(0.08, 0.06, 0.06)


static func mesh(id: String) -> Mesh:
	if _cache.has(id):
		return _cache[id]
	var m: Mesh = sculpted(id)
	match (id if m == null else ""):
		"cat": m = cat_stand()
		"cat_sit": m = cat_sit()
		"cat_curl": m = cat_curl()
		"rat": m = rat()
		"rabbit": m = rabbit()
		"deer": m = deer(false)
		"deer_stag": m = deer(true)
		"fox": m = fox({})
		"fennec": m = fox({"ears": 1.9, "len": 0.8, "fur": Color(0.93, 0.8, 0.6), "belly": Color(0.98, 0.94, 0.86), "socks": Color(0.85, 0.7, 0.5), "tip": Color(0.4, 0.3, 0.22)})
		"arctic_fox": m = fox({"ears": 0.8, "len": 0.95, "fur": Color(0.95, 0.95, 0.96), "belly": Color(1, 1, 1), "socks": Color(0.86, 0.87, 0.9), "tip": Color(0.97, 0.97, 0.98), "fluff": 1.25})
		"lizard": m = lizard()
		"frog": m = frog()
		"seal": m = seal()
		"turtle": m = turtle()
		"fish": m = fish()
		"bee": m = bee()
		"firefly": m = firefly()
		"pigeon", "sparrow", "songbird", "gull", "heron", "crane", "duck":
			m = bird(id, false)
		"pigeon_fly", "sparrow_fly", "songbird_fly", "gull_fly", "heron_fly", "crane_fly", "duck_fly":
			m = bird(id.trim_suffix("_fly"), true)
	if m == null:
		m = cat_stand()
	_cache[id] = m
	return m


## [fauna2] Sculpted animals: art/models/fauna/<species>_parts.glb (built in Blender by
## art/models/fauna/build_small.py) holds a "stand" and a "fly" pose, each a set of smooth parts
## named after their rig part (BODY, HEAD, TAIL, WING_L, WINGTIP_L__WING_L = outer wing whose
## second pivot is WING_L's origin...). Each part's origin is its pivot. They are assembled here
## into one rigged ArrayMesh for the MultiMesh path, so they animate like the procedural ones.
const PARTS: String = "res://art/models/fauna/%s_parts.glb"
const PART_IDS: Dictionary = {"BODY": 0, "LEG_FL": 1, "LEG_FR": 2, "LEG_BL": 3, "LEG_BR": 4, "HEAD": 5, "TAIL": 6,
	"WING_L": 7, "WING_R": 8, "FLEX": 9, "WINGTIP_L": 10, "WINGTIP_R": 11, "HIND": 12, "FRONT": 13}


static func sculpted(id: String) -> Mesh:
	var sp: String = id.trim_suffix("_fly")
	var pose: String = "fly" if id.ends_with("_fly") else "stand"
	if not ResourceLoader.exists(PARTS % sp):
		return null
	var scn: PackedScene = load(PARTS % sp)
	var root: Node = scn.instantiate()
	var pose_n: Node = root.find_child(pose, true, false)
	if pose_n == null:
		root.free()
		return null
	var b := FaunaMesh.new()
	b.vary = 0.04
	var origins: Dictionary = {}
	var nodes: Array = pose_n.find_children("*", "MeshInstance3D", true, false)
	for n: Node in nodes:
		origins[str(n.name).get_slice("__", 0)] = _rel_xf(n as Node3D, pose_n).origin
	for n: Node in nodes:
		var mi := n as MeshInstance3D
		var nm: String = str(mi.name)
		var key: String = nm.get_slice("__", 0).rstrip("0123456789")
		var part: int = int(PART_IDS.get(key.trim_suffix("_"), 0))
		var xf: Transform3D = _rel_xf(mi, pose_n)
		var piv2: Vector3 = origins.get(nm.get_slice("__", 1), Vector3.ZERO) if "__" in nm else Vector3.ZERO
		b.rig(part, xf.origin, piv2)
		b.add(mi.mesh, xf, Color.WHITE, 0.0, 0.0)
	root.free()
	return b.commit()


static func _rel_xf(n: Node3D, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != root:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t


# --- Cat --------------------------------------------------------------------------------------

## Coat tint goes on the fur (mask 1); the chest, muzzle and paws stay white for tuxedo/calico
## looks (mask 0), so one mesh covers ginger, black, grey and tabby cats.
static func _cat_head(b: FaunaMesh, c: Vector3, piv: Vector3, fur: Color) -> void:
	b.rig(M.HEAD, piv)
	b.ell(c, Vector3(0.062, 0.054, 0.058), fur, 1.0, Vector3.ZERO, 14, 8)
	for x: float in [-1.0, 1.0]:
		b.ell(c + Vector3(0.028 * x, -0.018, -0.026), Vector3(0.036, 0.03, 0.032), fur, 1.0)
		# Ears: outer cone (fur) and a pink inner.
		var eb: Vector3 = c + Vector3(0.036 * x, 0.038, 0.004)
		b.cone(eb, eb + Vector3(0.016 * x, 0.052, -0.004), 0.026, fur, 1.0, 5, 0.45)
		b.cone(eb + Vector3(0, 0.004, -0.008), eb + Vector3(0.014 * x, 0.046, -0.01), 0.016, Color(0.85, 0.6, 0.6), 0.0, 5, 0.3)
		# Eyes: amber-green, glossy, slit pupils.
		b.ell(c + Vector3(0.026 * x, 0.008, -0.05), Vector3(0.0125, 0.013, 0.008), Color(0.62, 0.66, 0.2), 0.0, Vector3(0, 18 * x, 0), 10, 6, 1.0)
		b.ell(c + Vector3(0.026 * x, 0.008, -0.0565), Vector3(0.0035, 0.011, 0.0025), EYE_DARK, 0.0, Vector3(0, 18 * x, 0), 6, 4, 1.0)
	b.ell(c + Vector3(0, -0.02, -0.052), Vector3(0.026, 0.02, 0.018), WHITE, 0.0)
	b.ell(c + Vector3(0, -0.006, -0.068), Vector3(0.008, 0.006, 0.005), Color(0.82, 0.52, 0.52), 0.0, Vector3.ZERO, 8, 4, 0.8)


static func cat_stand() -> Mesh:
	var b := FaunaMesh.new()
	var fur := Color(1, 1, 1)
	b.rig(M.BODY)
	b.ell(Vector3(0, 0.215, 0.0), Vector3(0.078, 0.08, 0.17), fur)
	b.ell(Vector3(0, 0.225, -0.11), Vector3(0.082, 0.088, 0.09), fur)
	b.ell(Vector3(0, 0.215, 0.11), Vector3(0.08, 0.085, 0.095), fur)
	b.ell(Vector3(0, 0.2, -0.165), Vector3(0.05, 0.06, 0.04), WHITE, 0.0)
	b.ell(Vector3(0, 0.17, -0.02), Vector3(0.055, 0.04, 0.13), WHITE, 0.3)
	b.ell(Vector3(0, 0.27, -0.16), Vector3(0.05, 0.05, 0.05), fur)  # neck
	for x: float in [-1.0, 1.0]:
		var fl: int = M.LEG_FL if x < 0.0 else M.LEG_FR
		var bl: int = M.LEG_BL if x < 0.0 else M.LEG_BR
		var hip := Vector3(0.042 * x, 0.2, -0.12)
		b.rig(fl, hip)
		b.limb(hip, Vector3(0.042 * x, 0.03, -0.13), 0.026, 0.018, fur)
		b.ell(Vector3(0.042 * x, 0.014, -0.142), Vector3(0.022, 0.015, 0.028), WHITE, 0.0)
		var bh := Vector3(0.048 * x, 0.2, 0.12)
		b.rig(bl, bh)
		b.ell(Vector3(0.05 * x, 0.165, 0.135), Vector3(0.036, 0.06, 0.055), fur, 1.0, Vector3(-20, 0, 0))
		b.limb(Vector3(0.05 * x, 0.12, 0.165), Vector3(0.048 * x, 0.03, 0.15), 0.02, 0.017, fur)
		b.ell(Vector3(0.048 * x, 0.014, 0.138), Vector3(0.021, 0.015, 0.028), WHITE, 0.0)
	b.rig(M.TAIL, Vector3(0, 0.25, 0.2))
	b.chain([Vector3(0, 0.25, 0.2), Vector3(0, 0.3, 0.3), Vector3(0, 0.39, 0.36), Vector3(0, 0.46, 0.35)], [0.02, 0.019, 0.018, 0.016], fur)
	_cat_head(b, Vector3(0, 0.31, -0.225), Vector3(0, 0.27, -0.17), fur)
	return b.commit()


static func cat_sit() -> Mesh:
	var b := FaunaMesh.new()
	var fur := Color(1, 1, 1)
	b.rig(M.BODY)
	b.ell(Vector3(0, 0.085, 0.04), Vector3(0.1, 0.085, 0.11), fur)  # haunches
	for x: float in [-1.0, 1.0]:
		b.ell(Vector3(0.07 * x, 0.07, 0.05), Vector3(0.04, 0.065, 0.08), fur)
		b.ell(Vector3(0.065 * x, 0.015, -0.03), Vector3(0.022, 0.014, 0.04), WHITE, 0.0)
	b.ell(Vector3(0, 0.18, -0.02), Vector3(0.075, 0.12, 0.08), fur, 1.0, Vector3(-18, 0, 0))
	b.ell(Vector3(0, 0.19, -0.07), Vector3(0.055, 0.085, 0.04), WHITE, 0.0, Vector3(-15, 0, 0))
	b.ell(Vector3(0, 0.27, -0.06), Vector3(0.05, 0.05, 0.05), fur)
	for x: float in [-1.0, 1.0]:
		var leg: int = M.LEG_FL if x < 0.0 else M.LEG_FR
		var sh := Vector3(0.036 * x, 0.2, -0.065)
		b.rig(leg, sh)
		b.limb(sh, Vector3(0.034 * x, 0.025, -0.095), 0.022, 0.017, fur)
		b.ell(Vector3(0.034 * x, 0.013, -0.107), Vector3(0.021, 0.014, 0.027), WHITE, 0.0)
	# Tail curled round the feet on the ground; the tip flicks.
	b.rig(M.BODY)
	b.chain([Vector3(0, 0.03, 0.15), Vector3(0.07, 0.02, 0.13), Vector3(0.11, 0.018, 0.05)], [0.02, 0.019, 0.018], fur)
	b.rig(M.TAIL, Vector3(0.11, 0.018, 0.05))
	b.chain([Vector3(0.11, 0.018, 0.05), Vector3(0.1, 0.02, -0.04), Vector3(0.07, 0.03, -0.1)], [0.018, 0.017, 0.015], fur)
	_cat_head(b, Vector3(0, 0.33, -0.1), Vector3(0, 0.28, -0.07), fur)
	return b.commit()


static func cat_curl() -> Mesh:
	var b := FaunaMesh.new()
	var fur := Color(1, 1, 1)
	b.rig(M.BODY)
	b.ell(Vector3(0.0, 0.075, 0.02), Vector3(0.14, 0.075, 0.115), fur, 1.0, Vector3(0, 20, 0))
	b.ell(Vector3(0.06, 0.07, 0.07), Vector3(0.08, 0.065, 0.07), fur)
	b.ell(Vector3(-0.07, 0.06, -0.06), Vector3(0.05, 0.03, 0.06), WHITE, 0.0)  # tucked paws
	# Tail wraps round the front.
	b.chain([Vector3(0.12, 0.03, 0.06), Vector3(0.1, 0.025, -0.06), Vector3(0.0, 0.025, -0.115), Vector3(-0.1, 0.03, -0.09)], [0.022, 0.021, 0.02, 0.017], fur)
	# Head resting on the paws, eyes closed (dark lines).
	var c := Vector3(-0.085, 0.09, -0.05)
	b.rig(M.HEAD, Vector3(-0.05, 0.08, -0.02))
	b.ell(c, Vector3(0.058, 0.05, 0.056), fur, 1.0, Vector3(0, -40, 0), 14, 8)
	var fw: Vector3 = Vector3(-0.64, 0, -0.77)
	var rt: Vector3 = Vector3(0.77, 0, -0.64)
	for x: float in [-1.0, 1.0]:
		var eb: Vector3 = c + rt * 0.034 * x + Vector3(0, 0.036, 0)
		b.cone(eb, eb + rt * 0.016 * x + Vector3(0, 0.048, 0), 0.025, fur, 1.0, 5, 0.45)
		b.ell(c + rt * 0.025 * x + fw * 0.05 + Vector3(0, 0.008, 0), Vector3(0.012, 0.0025, 0.006), EYE_DARK, 0.0, Vector3(0, -40, 0), 6, 3)
	b.ell(c + fw * 0.05 + Vector3(0, -0.018, 0), Vector3(0.024, 0.018, 0.016), WHITE, 0.0, Vector3(0, -40, 0))
	return b.commit()


# --- Small mammals -----------------------------------------------------------------------------

static func rat() -> Mesh:
	# Poly Haven's CC0 street_rat when it is on disk; a soft procedural rat otherwise.
	if ResourceLoader.exists(AssetLib.MODEL_DIR % ["street_rat", "street_rat"]):
		var m: Mesh = AssetLib.model_mesh_lite("street_rat", 900)
		if m:
			return m
	var b := FaunaMesh.new()
	var fur := Color(0.36, 0.32, 0.29)
	b.ell(Vector3(0, 0.05, 0.0), Vector3(0.045, 0.042, 0.08), fur, 0.0)
	b.ell(Vector3(0, 0.05, -0.08), Vector3(0.03, 0.028, 0.045), fur, 0.0)
	b.cone(Vector3(0, 0.048, -0.1), Vector3(0, 0.04, -0.14), 0.02, fur, 0.0, 6)
	for x: float in [-1.0, 1.0]:
		b.ell(Vector3(0.022 * x, 0.08, -0.075), Vector3(0.014, 0.016, 0.005), Color(0.75, 0.55, 0.55), 0.0)
		b.ell(Vector3(0.018 * x, 0.06, -0.115), Vector3(0.006, 0.006, 0.005), EYE_DARK, 0.0, Vector3.ZERO, 6, 4, 1.0)
	b.rig(M.TAIL, Vector3(0, 0.04, 0.075))
	b.chain([Vector3(0, 0.04, 0.075), Vector3(0.02, 0.02, 0.15), Vector3(-0.01, 0.01, 0.24)], [0.008, 0.006, 0.003], Color(0.7, 0.55, 0.52), 0.0, 5)
	return b.commit()


## [fauna2] Rabbit: a round bun with big hind feet, long ears, side-set eyes and a cotton tail.
static func rabbit() -> Mesh:
	var b := FaunaMesh.new()
	b.vary = 0.08
	var fur := Color(0.7, 0.57, 0.44)
	var belly := Color(0.95, 0.92, 0.87)
	var pink := Color(0.9, 0.66, 0.64)
	b.rig(M.BODY)
	b.ell(Vector3(0, 0.12, 0.045), Vector3(0.088, 0.096, 0.108), fur, 1.0, Vector3(-18, 0, 0), 16, 10)
	b.ell(Vector3(0, 0.13, -0.045), Vector3(0.066, 0.078, 0.075), fur, 1.0, Vector3.ZERO, 14, 9)
	b.ell(Vector3(0, 0.085, -0.02), Vector3(0.056, 0.05, 0.085), belly, 0.25)
	b.ell(Vector3(0, 0.12, -0.085), Vector3(0.04, 0.05, 0.03), belly, 0.25)  # chest bib
	b.rig(M.TAIL, Vector3(0, 0.13, 0.14))
	b.ell(Vector3(0, 0.14, 0.155), Vector3(0.032, 0.03, 0.026), WHITE, 0.0, Vector3.ZERO, 10, 6)
	for x: float in [-1.0, 1.0]:
		b.rig(M.HIND, Vector3(0.06 * x, 0.1, 0.07))
		b.ell(Vector3(0.064 * x, 0.085, 0.07), Vector3(0.034, 0.062, 0.072), fur, 1.0, Vector3(-22, 0, 0), 12, 8)
		b.ell(Vector3(0.06 * x, 0.016, 0.03), Vector3(0.022, 0.015, 0.066), fur.lightened(0.08), 1.0, Vector3(0, -6 * x, 0))
		b.ell(Vector3(0.06 * x, 0.009, -0.02), Vector3(0.018, 0.009, 0.02), belly, 0.2)  # toes
		b.rig(M.FRONT, Vector3(0.032 * x, 0.11, -0.07))
		b.limb(Vector3(0.032 * x, 0.1, -0.075), Vector3(0.03 * x, 0.022, -0.088), 0.015, 0.011, fur, 1.0)
		b.ell(Vector3(0.03 * x, 0.012, -0.098), Vector3(0.013, 0.01, 0.018), belly, 0.3)
	var c := Vector3(0, 0.2, -0.105)
	b.rig(M.HEAD, Vector3(0, 0.16, -0.07))
	b.ell(c, Vector3(0.05, 0.049, 0.058), fur, 1.0, Vector3(-8, 0, 0), 14, 9)
	for x: float in [-1.0, 1.0]:
		b.ell(c + Vector3(0.022 * x, -0.02, -0.03), Vector3(0.03, 0.027, 0.03), fur.lightened(0.08), 1.0)  # cheeks
		b.eye(c + Vector3(0.036 * x, 0.012, -0.026), Vector3(0.013, 0.015, 0.01), 58 * x, Color(0.09, 0.05, 0.03))
		b.ell(c + Vector3(0.034 * x, 0.012, -0.024), Vector3(0.016, 0.018, 0.009), belly, 0.3, Vector3(0, 58 * x, 0))  # pale eye ring
		# Long ears, tilted a little back and out; pink inside, darker rims at the tips.
		var er := Vector3(-14, 0, -9 * x)
		var ec: Vector3 = c + Vector3(0.022 * x, 0.105, 0.028)
		b.ell(ec, Vector3(0.02, 0.072, 0.01), fur, 1.0, er, 12, 8)
		b.ell(ec + Vector3(0, -0.004, -0.006), Vector3(0.013, 0.058, 0.005), pink, 0.0, er)
		b.ell(ec + Vector3(0.008 * x, 0.06, 0.012), Vector3(0.013, 0.016, 0.009), fur.darkened(0.35), 1.0, er)
		for w: int in 3:
			var o: Vector3 = c + Vector3(0.012 * x, -0.024 - w * 0.004, -0.058)
			b.limb(o, o + Vector3(0.06 * x, 0.012 - w * 0.012, 0.012), 0.0012, 0.0005, Color(0.95, 0.94, 0.9), 0.0, 3, false)
	b.ell(c + Vector3(0, -0.022, -0.052), Vector3(0.022, 0.017, 0.016), belly, 0.2)  # muzzle
	b.ell(c + Vector3(0, -0.006, -0.064), Vector3(0.008, 0.006, 0.004), pink, 0.0, Vector3.ZERO, 8, 4, 0.6)
	return b.commit()


## Foxes (red, fennec, arctic). p: ears (scale), len (body scale), fur, belly, socks, tip, fluff.
## [fauna2] Slim legs with dark socks, white ruff and cheeks, a wedge snout, amber eyes, big
## dark-backed ears and a bushy brush.
static func fox(p: Dictionary) -> Mesh:
	var b := FaunaMesh.new()
	b.vary = 0.07
	var fur: Color = p.get("fur", Color(0.86, 0.47, 0.22))
	var belly: Color = p.get("belly", Color(0.96, 0.93, 0.87))
	var socks: Color = p.get("socks", Color(0.16, 0.11, 0.09))
	var tip: Color = p.get("tip", WHITE)
	var s: float = float(p.get("len", 1.0))
	var ears: float = float(p.get("ears", 1.0))
	var fl: float = float(p.get("fluff", 1.0))
	var sc := Vector3(s, s, s)
	var ff := Vector3(fl, fl, 1.0)
	b.rig(M.BODY)
	b.ell(Vector3(0, 0.3, 0.02) * sc, Vector3(0.082, 0.092, 0.2) * sc * ff, fur, 0.0, Vector3(3, 0, 0), 16, 10)
	b.ell(Vector3(0, 0.31, -0.15) * sc, Vector3(0.088, 0.104, 0.1) * sc * fl, fur, 0.0, Vector3.ZERO, 14, 9)
	b.ell(Vector3(0, 0.305, 0.16) * sc, Vector3(0.086, 0.098, 0.1) * sc * fl, fur, 0.0, Vector3.ZERO, 14, 9)
	b.ell(Vector3(0, 0.33, 0.0) * sc, Vector3(0.055, 0.05, 0.17) * sc, fur.darkened(0.12), 0.0)  # darker back line
	b.ell(Vector3(0, 0.265, -0.2) * sc, Vector3(0.062, 0.09, 0.06) * sc * fl, belly, 0.0, Vector3(-18, 0, 0))  # ruff
	b.ell(Vector3(0, 0.24, -0.02) * sc, Vector3(0.058, 0.04, 0.16) * sc, belly.darkened(0.06), 0.0)
	for x: float in [-1.0, 1.0]:
		var sh := Vector3(0.05 * x, 0.3, -0.16) * sc
		b.rig(M.LEG_FL if x < 0.0 else M.LEG_FR, sh)
		b.ell(Vector3(0.055 * x, 0.25, -0.16) * sc, Vector3(0.034, 0.075, 0.05) * sc, fur, 0.0, Vector3(6, 0, 0))
		b.limb(Vector3(0.05 * x, 0.2, -0.168) * sc, Vector3(0.048 * x, 0.1, -0.172) * sc, 0.021 * s, 0.015 * s, socks.lerp(fur, 0.35), 0.0)
		b.limb(Vector3(0.048 * x, 0.1, -0.172) * sc, Vector3(0.048 * x, 0.024, -0.176) * sc, 0.015 * s, 0.013 * s, socks, 0.0)
		b.ell(Vector3(0.048 * x, 0.014, -0.19) * sc, Vector3(0.018, 0.014, 0.026) * sc, socks.darkened(0.1), 0.0)
		var hp := Vector3(0.055 * x, 0.31, 0.15) * sc
		b.rig(M.LEG_BL if x < 0.0 else M.LEG_BR, hp)
		b.ell(Vector3(0.058 * x, 0.245, 0.16) * sc, Vector3(0.042, 0.085, 0.07) * sc, fur, 0.0, Vector3(-15, 0, 0))
		b.limb(Vector3(0.055 * x, 0.18, 0.2) * sc, Vector3(0.052 * x, 0.1, 0.225) * sc, 0.022 * s, 0.015 * s, fur, 0.0)
		b.limb(Vector3(0.052 * x, 0.1, 0.225) * sc, Vector3(0.05 * x, 0.024, 0.2) * sc, 0.015 * s, 0.013 * s, socks, 0.0)
		b.ell(Vector3(0.05 * x, 0.014, 0.188) * sc, Vector3(0.018, 0.014, 0.026) * sc, socks.darkened(0.1), 0.0)
	b.rig(M.TAIL, Vector3(0, 0.32, 0.22) * sc)
	b.ell(Vector3(0, 0.29, 0.3) * sc, Vector3(0.05, 0.05, 0.08) * sc * fl, fur, 0.0, Vector3(20, 0, 0))
	b.ell(Vector3(0, 0.25, 0.4) * sc, Vector3(0.068, 0.066, 0.13) * sc * fl, fur, 0.0, Vector3(30, 0, 0), 14, 9)
	b.ell(Vector3(0, 0.19, 0.51) * sc, Vector3(0.056, 0.055, 0.08) * sc * fl, fur.darkened(0.08), 0.0, Vector3(38, 0, 0))
	b.ell(Vector3(0, 0.155, 0.565) * sc, Vector3(0.042, 0.042, 0.05) * sc * fl, tip, 0.0, Vector3(42, 0, 0))
	var c := Vector3(0, 0.4, -0.285) * sc
	b.rig(M.HEAD, Vector3(0, 0.34, -0.2) * sc)
	b.ell(Vector3(0, 0.36, -0.22) * sc, Vector3(0.056, 0.07, 0.07) * sc * fl, fur, 0.0)
	b.ell(c, Vector3(0.068, 0.06, 0.066) * sc, fur, 0.0, Vector3.ZERO, 14, 9)
	b.limb(c + Vector3(0, -0.01, -0.045) * sc, c + Vector3(0, -0.026, -0.13) * sc, 0.036 * s, 0.014 * s, fur, 0.0, 10)
	b.limb(c + Vector3(0, -0.03, -0.04) * sc, c + Vector3(0, -0.038, -0.118) * sc, 0.03 * s, 0.011 * s, belly, 0.0, 10)
	b.ell(c + Vector3(0, -0.025, -0.136) * sc, Vector3(0.012, 0.01, 0.01) * sc, NOSE, 0.0, Vector3.ZERO, 8, 5, 0.9)
	for x: float in [-1.0, 1.0]:
		b.ell(c + Vector3(0.042 * x, -0.024, -0.012) * sc, Vector3(0.04, 0.036, 0.046) * sc * fl, belly, 0.0)  # white cheeks
		b.eye(c + Vector3(0.033 * x, 0.012, -0.054) * sc, Vector3(0.012, 0.011, 0.008) * sc, 26 * x, Color(0.78, 0.5, 0.12), true)
		b.limb(c + Vector3(0.03 * x, 0.002, -0.06) * sc, c + Vector3(0.022 * x, -0.018, -0.1) * sc, 0.004 * s, 0.002 * s, socks.lerp(fur, 0.3), 0.0, 4)  # tear line
		var eb: Vector3 = c + Vector3(0.037 * x, 0.042, 0.008) * sc
		var et: Vector3 = eb + Vector3(0.024 * x, 0.08 * ears, 0.006) * sc
		b.cone(eb, et, 0.034 * s * sqrt(ears), socks.lerp(fur, 0.25), 0.0, 8, 0.45)
		b.cone(eb + Vector3(0, 0.004, -0.009) * sc, eb + Vector3(0.021 * x, 0.072 * ears, -0.004) * sc, 0.025 * s * sqrt(ears), belly, 0.0, 8, 0.3)
	return b.commit()


## [fauna2] Roe deer (~0.75 m at the shoulder): deep chest, slim waist and round haunch, jointed
## legs (knee, hock, fetlock) on small dark hooves, a long neck with a white throat patch, a
## wedge head with big soft ears, dark glossy eyes, a black nose over a white chin; bucks wear
## short three-tined antlers.
static func deer(stag: bool) -> Mesh:
	var b := FaunaMesh.new()
	b.vary = 0.07
	var fur := Color(0.76, 0.52, 0.34)
	var back := Color(0.62, 0.42, 0.27)
	var belly := Color(0.9, 0.8, 0.66)
	var pale := Color(0.96, 0.94, 0.9)
	var hoof := Color(0.13, 0.11, 0.1)
	var leg_c: Color = fur.darkened(0.06)
	b.rig(M.BODY)
	b.ell(Vector3(0, 0.79, -0.02), Vector3(0.142, 0.16, 0.33), fur, 1.0, Vector3(4, 0, 0), 18, 11)
	b.ell(Vector3(0, 0.765, -0.24), Vector3(0.148, 0.195, 0.17), fur, 1.0, Vector3(-10, 0, 0), 16, 10)
	b.ell(Vector3(0, 0.815, 0.24), Vector3(0.15, 0.168, 0.18), fur, 1.0, Vector3.ZERO, 16, 10)
	b.ell(Vector3(0, 0.885, -0.04), Vector3(0.085, 0.065, 0.3), back, 1.0)
	b.ell(Vector3(0, 0.665, -0.05), Vector3(0.1, 0.07, 0.25), belly, 0.6)
	b.ell(Vector3(0, 0.83, 0.385), Vector3(0.1, 0.12, 0.055), pale, 0.0)  # white rump patch
	for x: float in [-1.0, 1.0]:
		b.rig(M.LEG_FL if x < 0.0 else M.LEG_FR, Vector3(0.08 * x, 0.8, -0.25))
		b.ell(Vector3(0.088 * x, 0.68, -0.25), Vector3(0.055, 0.13, 0.08), fur, 1.0, Vector3(8, 0, 0), 12, 8)
		b.limb(Vector3(0.082 * x, 0.58, -0.27), Vector3(0.076 * x, 0.33, -0.255), 0.04, 0.025, leg_c, 1.0, 9)
		b.ell(Vector3(0.076 * x, 0.33, -0.255), Vector3(0.026, 0.03, 0.028), leg_c, 1.0, Vector3.ZERO, 8, 5)
		b.limb(Vector3(0.076 * x, 0.33, -0.255), Vector3(0.075 * x, 0.075, -0.262), 0.02, 0.016, leg_c.darkened(0.06), 1.0, 8)
		b.limb(Vector3(0.075 * x, 0.075, -0.262), Vector3(0.075 * x, 0.04, -0.282), 0.017, 0.018, leg_c.darkened(0.15), 1.0, 8)
		b.ell(Vector3(0.075 * x, 0.024, -0.29), Vector3(0.019, 0.025, 0.03), hoof, 0.0, Vector3(18, 0, 0), 8, 5, 0.3)
		b.rig(M.LEG_BL if x < 0.0 else M.LEG_BR, Vector3(0.085 * x, 0.85, 0.27))
		b.ell(Vector3(0.09 * x, 0.73, 0.27), Vector3(0.07, 0.17, 0.13), fur, 1.0, Vector3(-12, 0, 0), 12, 8)
		b.limb(Vector3(0.086 * x, 0.6, 0.32), Vector3(0.08 * x, 0.37, 0.4), 0.046, 0.026, leg_c, 1.0, 9)
		b.ell(Vector3(0.08 * x, 0.37, 0.405), Vector3(0.022, 0.03, 0.03), leg_c, 1.0, Vector3.ZERO, 8, 5)
		b.limb(Vector3(0.08 * x, 0.37, 0.4), Vector3(0.078 * x, 0.075, 0.37), 0.021, 0.016, leg_c.darkened(0.06), 1.0, 8)
		b.limb(Vector3(0.078 * x, 0.075, 0.37), Vector3(0.078 * x, 0.04, 0.35), 0.017, 0.018, leg_c.darkened(0.15), 1.0, 8)
		b.ell(Vector3(0.078 * x, 0.024, 0.343), Vector3(0.019, 0.025, 0.03), hoof, 0.0, Vector3(18, 0, 0), 8, 5, 0.3)
	b.rig(M.TAIL, Vector3(0, 0.88, 0.4))
	b.ell(Vector3(0, 0.865, 0.425), Vector3(0.028, 0.045, 0.022), fur, 1.0, Vector3(-25, 0, 0))
	# Neck and head (HEAD pivots at the withers so grazing lowers the whole neck).
	b.rig(M.HEAD, Vector3(0, 0.9, -0.3))
	b.chain([Vector3(0, 0.84, -0.3), Vector3(0, 0.95, -0.42), Vector3(0, 1.04, -0.51), Vector3(0, 1.09, -0.56)], [0.11, 0.08, 0.064, 0.058], fur, 1.0, 12)
	b.ell(Vector3(0, 0.92, -0.44), Vector3(0.058, 0.09, 0.055), belly, 0.4, Vector3(-45, 0, 0))
	b.ell(Vector3(0, 1.0, -0.545), Vector3(0.042, 0.04, 0.03), pale, 0.0, Vector3(-40, 0, 0))  # white gorget
	var c := Vector3(0, 1.12, -0.6)
	b.ell(c, Vector3(0.064, 0.066, 0.082), fur, 1.0, Vector3(-15, 0, 0), 14, 9)
	b.ell(c + Vector3(0, -0.03, -0.06), Vector3(0.048, 0.044, 0.06), fur, 1.0, Vector3(-25, 0, 0))
	b.limb(c + Vector3(0, -0.018, -0.05), c + Vector3(0, -0.06, -0.155), 0.048, 0.031, fur, 1.0, 12)
	b.ell(c + Vector3(0, -0.06, -0.168), Vector3(0.03, 0.023, 0.02), NOSE, 0.0, Vector3(-20, 0, 0), 10, 6, 0.9)
	b.ell(c + Vector3(0, -0.084, -0.14), Vector3(0.027, 0.016, 0.034), pale, 0.0)  # white chin
	b.ell(c + Vector3(0, -0.07, -0.146), Vector3(0.033, 0.012, 0.022), pale, 0.0)  # white lip band
	for x: float in [-1.0, 1.0]:
		var ep: Vector3 = c + Vector3(0.05 * x, 0.01, -0.046)
		b.ell(ep - Vector3(0.004 * x, 0, -0.002), Vector3(0.021, 0.023, 0.011), fur.lightened(0.22), 1.0, Vector3(0, 35 * x, 0))
		b.eye(ep, Vector3(0.016, 0.018, 0.012), 35 * x, Color(0.06, 0.04, 0.03))
		var er := Vector3(-10, 25 * x, -42 * x)
		var ec: Vector3 = c + Vector3(0.085 * x, 0.1, 0.03)
		b.ell(ec, Vector3(0.033, 0.072, 0.013), fur, 1.0, er, 12, 8)
		b.ell(ec + Vector3(-0.002 * x, 0.0, -0.007), Vector3(0.024, 0.058, 0.007), Color(0.95, 0.9, 0.85), 0.0, er)
		b.ell(ec + Vector3(0.044 * x, 0.046, 0.0), Vector3(0.014, 0.016, 0.013), back.darkened(0.3), 1.0, er)  # dark ear tips
		if stag:
			var ac := Color(0.6, 0.5, 0.37)
			var ab: Vector3 = c + Vector3(0.026 * x, 0.06, -0.005)
			b.ell(ab, Vector3(0.017, 0.011, 0.017), ac.darkened(0.25), 0.0)
			var mid: Vector3 = ab + Vector3(0.012 * x, 0.1, 0.01)
			var top: Vector3 = ab + Vector3(0.016 * x, 0.2, -0.012)
			b.limb(ab, mid, 0.012, 0.009, ac.darkened(0.1), 0.0, 6)
			b.limb(mid, top, 0.009, 0.004, ac.lightened(0.2), 0.0, 6)
			b.limb(mid + Vector3(0, 0.005, 0), mid + Vector3(0.004 * x, 0.05, -0.045), 0.007, 0.003, ac.lightened(0.15), 0.0, 5)
			b.limb(top + Vector3(0, -0.05, 0.002), top + Vector3(0.0, -0.02, 0.05), 0.006, 0.003, ac.lightened(0.15), 0.0, 5)
	return b.commit()


static func lizard() -> Mesh:
	var b := FaunaMesh.new()
	var skin := Color(1, 1, 1)
	b.ell(Vector3(0, 0.035, 0.0), Vector3(0.035, 0.022, 0.08), skin)
	b.ell(Vector3(0, 0.03, 0.0), Vector3(0.03, 0.015, 0.075), Color(0.9, 0.85, 0.7), 0.0)
	for x: float in [-1.0, 1.0]:
		b.rig(M.LEG_FL if x < 0.0 else M.LEG_FR, Vector3(0.025 * x, 0.03, -0.05))
		b.chain([Vector3(0.025 * x, 0.03, -0.05), Vector3(0.06 * x, 0.025, -0.06), Vector3(0.07 * x, 0.004, -0.085)], [0.009, 0.007, 0.005], skin, 1.0, 5)
		b.rig(M.LEG_BL if x < 0.0 else M.LEG_BR, Vector3(0.025 * x, 0.03, 0.05))
		b.chain([Vector3(0.025 * x, 0.03, 0.05), Vector3(0.065 * x, 0.025, 0.06), Vector3(0.075 * x, 0.004, 0.04)], [0.01, 0.007, 0.005], skin, 1.0, 5)
	b.rig(M.TAIL, Vector3(0, 0.03, 0.075))
	b.chain([Vector3(0, 0.03, 0.075), Vector3(0.01, 0.02, 0.16), Vector3(-0.015, 0.01, 0.25), Vector3(0.01, 0.006, 0.32)], [0.018, 0.012, 0.007, 0.002], skin, 1.0, 6)
	var c := Vector3(0, 0.04, -0.105)
	b.rig(M.HEAD, Vector3(0, 0.035, -0.07))
	b.ell(c, Vector3(0.026, 0.018, 0.04), skin)
	for x: float in [-1.0, 1.0]:
		b.ell(c + Vector3(0.018 * x, 0.007, -0.01), Vector3(0.006, 0.006, 0.006), EYE_DARK, 0.0, Vector3.ZERO, 6, 4, 1.0)
	return b.commit()


static func frog() -> Mesh:
	var b := FaunaMesh.new()
	var skin := Color(0.42, 0.62, 0.25)
	var belly := Color(0.88, 0.86, 0.62)
	b.ell(Vector3(0, 0.045, 0.0), Vector3(0.05, 0.035, 0.06), skin, 0.4, Vector3(-15, 0, 0), 12, 7, 0.4)
	b.ell(Vector3(0, 0.035, -0.005), Vector3(0.045, 0.025, 0.055), belly, 0.0)
	b.ell(Vector3(0, 0.055, -0.04), Vector3(0.045, 0.028, 0.035), skin, 0.4, Vector3.ZERO, 12, 6, 0.4)
	for x: float in [-1.0, 1.0]:
		b.ell(Vector3(0.026 * x, 0.08, -0.045), Vector3(0.016, 0.016, 0.016), skin, 0.4, Vector3.ZERO, 10, 6, 0.4)
		b.ell(Vector3(0.03 * x, 0.085, -0.052), Vector3(0.01, 0.01, 0.008), Color(0.7, 0.55, 0.15), 0.0, Vector3.ZERO, 8, 5, 1.0)
		b.ell(Vector3(0.031 * x, 0.085, -0.058), Vector3(0.007, 0.004, 0.003), EYE_DARK, 0.0, Vector3.ZERO, 6, 3, 1.0)
		b.rig(M.HIND, Vector3(0.04 * x, 0.04, 0.04))
		b.ell(Vector3(0.05 * x, 0.03, 0.035), Vector3(0.02, 0.022, 0.045), skin, 0.4, Vector3(0, 30 * x, 0))
		b.ell(Vector3(0.06 * x, 0.008, 0.0), Vector3(0.016, 0.006, 0.04), skin, 0.4, Vector3(0, -20 * x, 0))
		b.rig(M.FRONT, Vector3(0.03 * x, 0.035, -0.04))
		b.limb(Vector3(0.032 * x, 0.03, -0.04), Vector3(0.036 * x, 0.004, -0.055), 0.008, 0.006, skin, 0.4, 5)
	return b.commit()


## [fauna2] Harbour seal hauled out: a plump spindle in the "banana" pose (head up, rear flippers
## lifted), a pale belly and dark spots, a round head with big wet eyes, whisker pads, a V nose
## and whiskers. The coat tint (silver, brown, sand) goes on the fur.
static func seal() -> Mesh:
	var b := FaunaMesh.new()
	b.vary = 0.05
	var fur := Color(0.92, 0.92, 0.92)
	var belly := Color(1.0, 0.98, 0.95)
	var spot := Color(0.4, 0.4, 0.42)
	var flip := Color(0.6, 0.6, 0.61)
	b.rig(M.FLEX, Vector3(0, 0.15, -0.1))
	var bc := Vector3(0, 0.2, 0.02)
	var br := Vector3(0.21, 0.19, 0.42)
	b.ell(bc, br, fur, 1.0, Vector3.ZERO, 20, 12)
	b.ell(Vector3(0, 0.215, -0.27), Vector3(0.2, 0.2, 0.2), fur, 1.0, Vector3.ZERO, 16, 10)
	b.ell(Vector3(0, 0.16, 0.36), Vector3(0.135, 0.12, 0.2), fur, 1.0, Vector3(-8, 0, 0), 14, 9)
	b.ell(Vector3(0, 0.165, 0.53), Vector3(0.075, 0.065, 0.1), fur, 1.0, Vector3(-18, 0, 0))
	b.ell(Vector3(0, 0.1, -0.05), Vector3(0.18, 0.09, 0.4), belly, 0.45)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for k: int in 40:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.1, 1.0), rng.randf_range(-0.85, 0.9))
		b.patch_on(bc, br, d, Vector3(rng.randf_range(0.01, 0.026), 0.006, rng.randf_range(0.012, 0.028)), spot, 1.0)
	b.rig(M.TAIL, Vector3(0, 0.17, 0.6))
	for x: float in [-1.0, 1.0]:
		b.ell(Vector3(0.05 * x, 0.21, 0.7), Vector3(0.05, 0.014, 0.1), flip, 0.6, Vector3(-28, 16 * x, 0), 10, 5)
		b.ell(Vector3(0.065 * x, 0.25, 0.78), Vector3(0.045, 0.01, 0.04), flip.darkened(0.15), 0.6, Vector3(-28, 22 * x, 0), 8, 4)
	b.rig(M.FRONT, Vector3(0, 0.12, -0.22))
	for x: float in [-1.0, 1.0]:
		b.ell(Vector3(0.2 * x, 0.06, -0.24), Vector3(0.075, 0.02, 0.045), flip, 0.6, Vector3(0, 35 * x, -25 * x), 10, 5)
		for t: int in 3:
			b.ell(Vector3((0.255 + t * 0.006) * x, 0.04, -0.27 + t * 0.016), Vector3(0.006, 0.004, 0.009), Color(0.15, 0.13, 0.12), 0.0, Vector3.ZERO, 5, 3, 0.4)
	var c := Vector3(0, 0.43, -0.5)
	b.rig(M.HEAD, Vector3(0, 0.25, -0.3))
	b.limb(Vector3(0, 0.26, -0.3), Vector3(0, 0.38, -0.45), 0.165, 0.112, fur, 1.0, 16)
	b.ell(Vector3(0, 0.31, -0.42), Vector3(0.11, 0.08, 0.1), belly, 0.45)  # pale throat
	b.ell(c, Vector3(0.115, 0.105, 0.115), fur, 1.0, Vector3.ZERO, 18, 11)
	for k: int in 10:
		var d2 := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.3, 1.0), rng.randf_range(-0.2, 1.0))
		b.patch_on(c, Vector3(0.115, 0.105, 0.115), d2, Vector3(rng.randf_range(0.007, 0.014), 0.004, rng.randf_range(0.008, 0.015)), spot, 1.0)
	var pad := Color(0.97, 0.96, 0.93)
	for x: float in [-1.0, 1.0]:
		b.ell(c + Vector3(0.031 * x, -0.034, -0.098), Vector3(0.04, 0.034, 0.04), pad, 0.55, Vector3.ZERO, 12, 8)
		b.eye(c + Vector3(0.056 * x, 0.024, -0.093), Vector3(0.027, 0.029, 0.019), 30 * x, Color(0.05, 0.04, 0.04))
		b.ell(c + Vector3(0.05 * x, 0.06, -0.085), Vector3(0.016, 0.006, 0.01), fur.darkened(0.1), 1.0, Vector3(0, 30 * x, -15 * x))  # brow
		b.ell(c + Vector3(0.1 * x, 0.025, 0.015), Vector3(0.006, 0.008, 0.006), Color(0.1, 0.08, 0.08), 0.0)  # ear hole
		for w: int in 4:
			var o: Vector3 = c + Vector3(0.05 * x, -0.028 - w * 0.008, -0.118)
			b.limb(o, o + Vector3(0.1 * x, 0.012 - w * 0.016, 0.03), 0.0016, 0.0006, Color(0.95, 0.93, 0.86), 0.0, 3, false)
		b.ell(c + Vector3(0.009 * x, -0.014, -0.142), Vector3(0.006, 0.0045, 0.004), Color(0.01, 0.01, 0.01), 0.0, Vector3(0, 0, 30 * x), 6, 3, 0.9)  # nostril
	b.ell(c + Vector3(0, -0.012, -0.135), Vector3(0.024, 0.017, 0.012), NOSE, 0.0, Vector3(10, 0, 0), 10, 6, 0.9)
	b.ell(c + Vector3(0, -0.06, -0.09), Vector3(0.034, 0.02, 0.03), pad, 0.55)  # chin
	b.limb(c + Vector3(-0.012, -0.056, -0.122), c + Vector3(0.012, -0.056, -0.122), 0.0025, 0.0025, Color(0.25, 0.2, 0.2), 0.0, 4)  # mouth
	return b.commit()


static func turtle() -> Mesh:
	var b := FaunaMesh.new()
	var shell := Color(0.36, 0.33, 0.2)
	var skin := Color(0.45, 0.48, 0.32)
	var hs := SphereMesh.new()
	hs.radius = 1.0
	hs.height = 1.0
	hs.is_hemisphere = true
	hs.radial_segments = 14
	hs.rings = 5
	b.add(hs, Transform3D(Basis.from_scale(Vector3(0.16, 0.09, 0.2)), Vector3(0, 0.03, 0)), shell, 0.0, 0.3)
	b.ell(Vector3(0, 0.03, 0), Vector3(0.165, 0.025, 0.205), shell.darkened(0.3), 0.0)
	for k: int in 5:
		var a: float = TAU * k / 5.0
		b.ell(Vector3(cos(a) * 0.07, 0.1, sin(a) * 0.09), Vector3(0.05, 0.02, 0.05), shell.lightened(0.12), 0.0, Vector3.ZERO, 8, 4, 0.3)
	b.ell(Vector3(0, 0.12, 0), Vector3(0.05, 0.02, 0.06), shell.lightened(0.12), 0.0, Vector3.ZERO, 8, 4, 0.3)
	for x: float in [-1.0, 1.0]:
		b.rig(M.LEG_FL if x < 0.0 else M.LEG_FR, Vector3(0.12 * x, 0.03, -0.12))
		b.ell(Vector3(0.17 * x, 0.025, -0.14), Vector3(0.08, 0.015, 0.04), skin, 0.0, Vector3(0, 30 * x, 0))
		b.rig(M.LEG_BL if x < 0.0 else M.LEG_BR, Vector3(0.11 * x, 0.03, 0.14))
		b.ell(Vector3(0.14 * x, 0.022, 0.17), Vector3(0.05, 0.012, 0.035), skin, 0.0, Vector3(0, -30 * x, 0))
	b.rig(M.HEAD, Vector3(0, 0.04, -0.18))
	b.limb(Vector3(0, 0.04, -0.17), Vector3(0, 0.05, -0.25), 0.035, 0.03, skin, 0.0)
	b.ell(Vector3(0, 0.055, -0.28), Vector3(0.035, 0.03, 0.045), skin, 0.0)
	for x: float in [-1.0, 1.0]:
		b.ell(Vector3(0.025 * x, 0.065, -0.3), Vector3(0.007, 0.007, 0.007), EYE_DARK, 0.0, Vector3.ZERO, 6, 4, 1.0)
	return b.commit()


## [fauna2] Lake fish (~0.3 m): a rounded body with a dark back, silver flanks and a pale belly
## (tint = back colour), a glossy sheen, fins and a forked tail that flexes.
static func fish() -> Mesh:
	var b := FaunaMesh.new()
	b.vary = 0.08
	b.vary_scale = 40.0
	b.rig(M.FLEX, Vector3(0, 0, -0.06))
	b.ell(Vector3(0, 0, 0), Vector3(0.036, 0.052, 0.14), Color(0.86, 0.88, 0.86), 0.0, Vector3.ZERO, 14, 9, 0.7)
	b.ell(Vector3(0, -0.018, 0.0), Vector3(0.03, 0.035, 0.12), Color(0.97, 0.96, 0.92), 0.0, Vector3.ZERO, 12, 7, 0.5)
	b.ell(Vector3(0, 0.02, 0.0), Vector3(0.03, 0.036, 0.13), Color(1, 1, 1), 1.0, Vector3.ZERO, 12, 7, 0.45)
	b.ell(Vector3(0, 0.0, 0.0), Vector3(0.037, 0.006, 0.12), Color(0.75, 0.82, 0.8), 0.0, Vector3.ZERO, 10, 4, 0.8)  # lateral line
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k: int in 10:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.3, 1.0), rng.randf_range(-0.6, 0.7))
		b.patch_on(Vector3(0, 0.02, 0), Vector3(0.03, 0.036, 0.13), d, Vector3(0.004, 0.002, 0.004), Color(0.2, 0.2, 0.18), 0.0)
	b.cone(Vector3(0, 0.05, -0.01), Vector3(0, 0.085, 0.04), 0.035, Color(1, 1, 1), 1.0, 4, 0.12)
	b.cone(Vector3(0, -0.045, 0.06), Vector3(0, -0.065, 0.09), 0.018, Color(1, 1, 1), 1.0, 4, 0.12)
	b.cone(Vector3(0, 0.0, 0.125), Vector3(0, 0.05, 0.205), 0.03, Color(1, 1, 1), 1.0, 4, 0.12)
	b.cone(Vector3(0, 0.0, 0.125), Vector3(0, -0.045, 0.205), 0.03, Color(1, 1, 1), 1.0, 4, 0.12)
	for x: float in [-1.0, 1.0]:
		b.cone(Vector3(0.03 * x, -0.02, -0.06), Vector3(0.055 * x, -0.035, -0.02), 0.014, Color(0.9, 0.85, 0.75), 0.0, 4, 0.15)  # pectorals
		b.eye(Vector3(0.026 * x, 0.012, -0.1), Vector3(0.009, 0.01, 0.008), 70 * x, Color(0.75, 0.62, 0.3), true)
	b.ell(Vector3(0, -0.006, -0.135), Vector3(0.016, 0.012, 0.012), Color(0.8, 0.8, 0.75), 0.0, Vector3.ZERO, 8, 5, 0.5)  # mouth
	return b.commit()


static func bee() -> Mesh:
	var b := FaunaMesh.new()
	b.ell(Vector3(0, 0, 0.006), Vector3(0.007, 0.007, 0.011), Color(0.95, 0.7, 0.1), 0.0, Vector3.ZERO, 8, 5)
	b.ell(Vector3(0, 0, 0.012), Vector3(0.0072, 0.0072, 0.003), Color(0.08, 0.06, 0.04), 0.0, Vector3.ZERO, 8, 3)
	b.ell(Vector3(0, 0, -0.008), Vector3(0.005, 0.005, 0.005), Color(0.15, 0.12, 0.08), 0.0, Vector3.ZERO, 6, 4)
	for x: float in [-1.0, 1.0]:
		b.rig(M.WING_L if x < 0.0 else M.WING_R, Vector3(0.003 * x, 0.006, -0.002))
		b.ell(Vector3(0.01 * x, 0.007, 0.0), Vector3(0.009, 0.001, 0.005), Color(0.85, 0.9, 0.95), 0.0, Vector3.ZERO, 6, 3, 1.0)
	return b.commit()


static func firefly() -> Mesh:
	var s := SphereMesh.new()
	s.radius = 0.02
	s.height = 0.04
	s.radial_segments = 6
	s.rings = 3
	return s


# --- Birds -------------------------------------------------------------------------------------

## Per-species bird shape. Colours: body (back), breast, head, neck, wing, bar (wing bars / tips),
## beak, leg, eye; sizes in metres (s = scale of a ~pigeon body). [fauna2] tilt (body pitch when
## perched, degrees), tipc (primary tips), cap / cheek / bib (head markings), cere (pigeon),
## chord (wing breadth), tailc / band (tail colour, dark band).
static func bird_params(id: String) -> Dictionary:
	match id:
		"pigeon":
			return {"s": 1.0, "body": Color(0.6, 0.62, 0.68), "breast": Color(0.66, 0.6, 0.66), "head": Color(0.48, 0.5, 0.57), "neck": Color(0.32, 0.55, 0.47),
				"wing": Color(0.66, 0.68, 0.73), "bar": Color(0.16, 0.16, 0.19), "beak": Color(0.22, 0.2, 0.2), "leg": Color(0.86, 0.38, 0.38), "eye": Color(0.95, 0.5, 0.1),
				"tail": 0.1, "legh": 0.04, "neckl": 0.03, "span": 0.62, "tilt": -8.0, "tipc": Color(0.22, 0.22, 0.26), "cere": true, "bars": 2,
				"tailc": Color(0.55, 0.57, 0.63), "band": Color(0.18, 0.18, 0.2), "neck_gloss": 0.55, "chord": 1.0}
		"sparrow":
			return {"s": 0.55, "body": Color(0.6, 0.44, 0.28), "breast": Color(0.82, 0.78, 0.7), "head": Color(0.5, 0.5, 0.52), "neck": Color(0.6, 0.38, 0.22),
				"wing": Color(0.58, 0.4, 0.24), "bar": Color(0.95, 0.93, 0.88), "beak": Color(0.22, 0.18, 0.16), "leg": Color(0.65, 0.52, 0.42), "eye": EYE_DARK,
				"tail": 0.08, "legh": 0.04, "neckl": 0.0, "span": 0.42, "tilt": -22.0, "tipc": Color(0.3, 0.22, 0.16), "bars": 1, "streaks": Color(0.2, 0.14, 0.1),
				"cap": Color(0.52, 0.52, 0.55), "cheek": Color(0.92, 0.9, 0.86), "bib": Color(0.12, 0.1, 0.1), "nape": Color(0.6, 0.36, 0.2), "chord": 1.1}
		"songbird":
			return {"s": 0.55, "body": Color(0.5, 0.44, 0.34), "breast": Color(0.95, 0.47, 0.18), "head": Color(0.5, 0.44, 0.34), "neck": Color(0.95, 0.47, 0.18),
				"wing": Color(0.46, 0.4, 0.31), "bar": Color(0.46, 0.4, 0.31), "beak": Color(0.15, 0.12, 0.1), "leg": Color(0.5, 0.4, 0.33), "eye": EYE_DARK,
				"tail": 0.09, "legh": 0.05, "neckl": 0.0, "span": 0.42, "tilt": -25.0, "tipc": Color(0.3, 0.26, 0.2), "face": Color(0.95, 0.47, 0.18),
				"belly": Color(0.95, 0.94, 0.9), "chord": 1.1}
		"gull":
			return {"s": 1.45, "body": Color(0.97, 0.97, 0.97), "breast": Color(0.99, 0.99, 0.99), "head": Color(0.99, 0.99, 0.99), "neck": Color(0.98, 0.98, 0.98),
				"wing": Color(0.68, 0.72, 0.78), "bar": Color(0.1, 0.1, 0.12), "beak": Color(0.96, 0.82, 0.22), "leg": Color(0.95, 0.7, 0.6), "eye": Color(0.9, 0.85, 0.45),
				"tail": 0.08, "legh": 0.05, "neckl": 0.02, "span": 1.0, "tilt": -6.0, "tipc": Color(0.1, 0.1, 0.12), "gonys": Color(0.85, 0.2, 0.15),
				"tailc": Color(0.98, 0.98, 0.98), "chord": 0.85}
		"heron":
			return {"s": 1.6, "body": Color(0.62, 0.65, 0.7), "breast": Color(0.92, 0.92, 0.92), "head": Color(0.96, 0.96, 0.96), "neck": Color(0.9, 0.9, 0.92),
				"wing": Color(0.58, 0.61, 0.67), "bar": Color(0.2, 0.2, 0.24), "beak": Color(0.88, 0.72, 0.3), "leg": Color(0.6, 0.52, 0.38), "eye": Color(0.95, 0.88, 0.25),
				"tail": 0.08, "legh": 0.36, "neckl": 0.3, "span": 1.6, "long_beak": true, "tilt": -28.0, "tipc": Color(0.15, 0.15, 0.18), "plume": Color(0.08, 0.08, 0.1),
				"chord": 1.15}
		"crane":
			return {"s": 1.7, "body": Color(0.97, 0.97, 0.96), "breast": Color(0.98, 0.98, 0.97), "head": Color(0.98, 0.98, 0.98), "neck": Color(0.97, 0.97, 0.96),
				"wing": Color(0.96, 0.96, 0.95), "bar": Color(0.12, 0.12, 0.14), "beak": Color(0.95, 0.65, 0.2), "leg": Color(0.2, 0.2, 0.2), "eye": EYE_DARK,
				"tail": 0.22, "legh": 0.3, "neckl": 0.3, "span": 2.2, "long_beak": true, "crest": Color(0.85, 0.2, 0.2), "tilt": -10.0, "tipc": Color(0.12, 0.12, 0.14),
				"chord": 1.1}
	return bird_params("sparrow")


## A bird, perched (wings folded) or flying (two-part wings: arm + hand, which the shader flaps,
## lagging and folding the hand on the upstroke). [fauna2] rebuilt: a plump breast and a tapered
## body, folded wings hugging the flanks with their primaries crossing over a fanned tail, a round
## head with glossy eyes and catchlights, species markings.
static func bird(id: String, flying: bool) -> Mesh:
	if id == "duck":
		return duck(flying)
	var p: Dictionary = bird_params(id)
	var b := FaunaMesh.new()
	b.vary = 0.05
	b.vary_scale = 30.0
	var s: float = float(p["s"])
	var legh: float = float(p["legh"]) if not flying else 0.0
	var neckl: float = float(p["neckl"])
	var tilt: float = float(p.get("tilt", -10.0)) if not flying else 0.0
	var by: float = 0.062 * s + legh * (0.55 if legh < 0.2 else 0.9)
	var bc := Vector3(0, by, 0)
	var tb := Basis.from_euler(Vector3(deg_to_rad(tilt), 0, 0))  # body pitch (perched: chest up)
	var at := func(v: Vector3) -> Vector3: return bc + tb * (v * s)
	var rot := Vector3(tilt, 0, 0)
	b.rig(M.BODY)
	b.ell(at.call(Vector3(0, 0.004, -0.035)), Vector3(0.05, 0.054, 0.058) * s, p["breast"], 0.0, rot, 14, 9)
	b.ell(at.call(Vector3(0, 0.008, 0.02)), Vector3(0.046, 0.046, 0.085) * s, p["body"], 0.0, rot, 14, 9)
	b.ell(at.call(Vector3(0, -0.02, 0.0)), Vector3(0.04, 0.034, 0.065) * s, p.get("belly", (p["breast"] as Color).lightened(0.12)), 0.0, rot)
	b.ell(at.call(Vector3(0, 0.03, 0.03)), Vector3(0.038, 0.022, 0.07) * s, p["wing"], 0.0, rot)  # mantle
	if p.has("streaks"):
		for k: int in 6:
			var zz: float = -0.01 + k * 0.016
			for x: float in [-1.0, 1.0]:
				b.ell(at.call(Vector3(0.016 * x, 0.05, zz)), Vector3(0.005, 0.004, 0.012) * s, p["streaks"], 0.0, rot, 6, 3)
	# Tail: a fan, with a dark terminal band on pigeons.
	var tl: float = float(p["tail"])
	var tail_c: Color = p.get("tailc", p["wing"])
	var tp: Vector3 = at.call(Vector3(0, 0.0, 0.085))
	b.rig(M.TAIL, tp)
	var trot := Vector3(tilt * 0.4 + (0.0 if flying else -12.0), 0, 0)
	b.ell(at.call(Vector3(0, 0.0, 0.085 + tl * 0.5)), Vector3(0.03 + (0.008 if flying else 0.0), 0.006, tl * 0.55) * s, tail_c, 0.0, trot, 10, 4)
	if p.has("band"):
		b.ell(at.call(Vector3(0, 0.0, 0.085 + tl * 0.92)), Vector3(0.028, 0.0062, tl * 0.14) * s, p["band"], 0.0, trot, 10, 4)
	if p.has("crest"):
		b.ell(at.call(Vector3(0, -0.005, 0.1 + tl * 0.7)), Vector3(0.025, 0.012, 0.05) * s, p["bar"], 0.0, trot)  # crane bustle
	# Legs (perched): feathered thighs, scaly shanks, three toes forward, one back.
	if not flying and legh > 0.0:
		for x: float in [-1.0, 1.0]:
			var hip: Vector3 = bc + Vector3(0.018 * x * s, -0.035 * s, 0.005 * s)
			b.rig(M.LEG_BL if x < 0.0 else M.LEG_BR, hip)
			b.ell(hip + Vector3(0, 0.006 * s, 0), Vector3(0.016, 0.02, 0.018) * s, p["body"], 0.0)
			var foot := Vector3(0.018 * x * s, 0.004, 0.006 * s)
			var lr: float = 0.0045 * s if legh < 0.2 else 0.012
			b.limb(hip, foot, lr, lr * 0.8, p["leg"], 0.0, 5, false)
			for k: int in 3:
				var a: float = deg_to_rad(-28 + 28 * k)
				b.limb(foot, foot + Vector3(sin(a) * 0.022 * s, -0.002, -cos(a) * 0.026 * s), lr * 0.55, lr * 0.4, p["leg"], 0.0, 4, false)
			b.limb(foot, foot + Vector3(0, -0.002, 0.016 * s), lr * 0.5, lr * 0.35, p["leg"], 0.0, 4, false)
	elif flying and legh == 0.0 and float(p["legh"]) > 0.2:
		# Herons and cranes trail their legs in flight.
		for x: float in [-1.0, 1.0]:
			var hip2: Vector3 = bc + Vector3(0.016 * x * s, -0.02 * s, 0.05 * s)
			b.limb(hip2, hip2 + Vector3(0, -0.01, float(p["legh"]) * 1.1), 0.01, 0.007, p["leg"], 0.0, 5, false)
	# Wings.
	var span: float = float(p["span"])
	var half: float = span * 0.5
	var chord: float = float(p.get("chord", 1.0))
	var tipc: Color = p.get("tipc", p["bar"])
	for x: float in [-1.0, 1.0]:
		if flying:
			var sh: Vector3 = bc + Vector3(0.034 * x * s, 0.02 * s, -0.03 * s)
			var wr: Vector3 = sh + Vector3(half * 0.46 * x, 0, 0.012 * s)
			b.rig(M.WING_L if x < 0.0 else M.WING_R, sh)
			# Arm wing: straight leading edge, broad rounded trailing edge; coverts on top.
			b.ell(sh + Vector3(half * 0.25 * x, 0, 0.032 * s * chord), Vector3(half * 0.27, 0.01 * s, 0.062 * s * chord), p["wing"], 0.0, Vector3.ZERO, 12, 5)
			b.ell(sh + Vector3(half * 0.22 * x, 0.004 * s, 0.006 * s), Vector3(half * 0.24, 0.009 * s, 0.032 * s * chord), (p["wing"] as Color).lightened(0.06), 0.0, Vector3.ZERO, 10, 4)
			var nb: int = int(p.get("bars", 0))
			for k: int in nb:
				b.ell(sh + Vector3(half * 0.25 * x, 0.007 * s, (0.035 + 0.022 * k) * s * chord), Vector3(half * 0.2, 0.005 * s, 0.006 * s), p["bar"], 0.0, Vector3.ZERO, 8, 3)
			# Hand: swept back and tapering to the primaries.
			b.rig(M.WINGTIP_L if x < 0.0 else M.WINGTIP_R, wr, sh)
			b.ell(wr + Vector3(half * 0.25 * x, 0, 0.036 * s * chord), Vector3(half * 0.29, 0.008 * s, 0.05 * s * chord), p["wing"], 0.0, Vector3(0, -10 * x, 0), 12, 5)
			b.ell(wr + Vector3(half * 0.4 * x, -0.001, 0.05 * s * chord), Vector3(half * 0.17, 0.0075 * s, 0.034 * s * chord), tipc, 0.0, Vector3(0, -16 * x, 0), 10, 4)
			for k2: int in 4:
				var fz: float = (0.03 + 0.016 * k2) * s * chord
				b.ell(wr + Vector3(half * (0.46 - 0.035 * k2) * x, -0.002, fz + 0.03 * s), Vector3(half * 0.11, 0.004 * s, 0.009 * s * chord), tipc, 0.0, Vector3(0, -(20 + 8 * k2) * x, 0), 8, 3)
		else:
			# Folded: a long leaf on each flank, primaries crossing over the tail.
			b.rig(M.BODY)
			var wrot := Vector3(tilt - 4.0, 5 * x, 0)
			b.ell(at.call(Vector3(0.04 * x, 0.012, 0.03)), Vector3(0.017, 0.04, 0.082) * s, p["wing"], 0.0, wrot, 12, 7)
			b.ell(at.call(Vector3(0.042 * x, 0.022, -0.0)), Vector3(0.014, 0.024, 0.04) * s, (p["wing"] as Color).lightened(0.07), 0.0, wrot, 10, 5)
			b.ell(at.call(Vector3(0.024 * x, 0.016, 0.115)), Vector3(0.012, 0.008, 0.055) * s, tipc, 0.0, Vector3(tilt - 8.0, -6 * x, 0), 8, 4)
			var nb2: int = int(p.get("bars", 0))
			for k3: int in nb2:
				b.ell(at.call(Vector3(0.054 * x, 0.012 - 0.012 * k3, 0.035 + 0.022 * k3)), Vector3(0.006, 0.02, 0.007) * s, p["bar"], 0.0, wrot, 6, 3)
	# Neck + head.
	var neck_base: Vector3 = at.call(Vector3(0, 0.03, -0.055))
	var hc: Vector3
	if flying:
		var nk: float = neckl * (0.35 if id == "heron" else 0.9)  # herons fly with the neck drawn in
		hc = bc + Vector3(0, 0.018 * s + (0.03 if id == "heron" else 0.0), -0.1 * s - nk)
	else:
		hc = neck_base + Vector3(0, 0.04 * s + neckl, -0.022 * s - neckl * 0.15)
	b.rig(M.HEAD, neck_base)
	var thin: bool = neckl > 0.1
	if thin and not flying:
		# S-curved long neck.
		var m1: Vector3 = neck_base.lerp(hc, 0.45) + Vector3(0, 0, 0.05 * s)
		b.chain([neck_base, m1, hc], [0.03 * s, 0.018 * s, 0.017 * s], p["neck"], 0.0, 8)
	else:
		b.limb(neck_base, hc, 0.034 * s * (0.6 if thin else 1.0), 0.026 * s * (0.6 if thin else 1.0), p["neck"], 0.0, 10)
	if p.has("neck_gloss"):
		var ng: Vector3 = neck_base.lerp(hc, 0.4)
		b.ell(ng, Vector3(0.033, 0.026, 0.032) * s, Color(0.42, 0.33, 0.5), 0.0, Vector3.ZERO, 10, 6, float(p["neck_gloss"]))
		b.ell(ng + Vector3(0, 0.008, -0.004) * s, Vector3(0.032, 0.02, 0.03) * s, p["neck"], 0.0, Vector3.ZERO, 10, 6, float(p["neck_gloss"]))
	b.ell(hc, Vector3(0.031, 0.031, 0.034) * s, p["head"], 0.0, Vector3.ZERO, 12, 8)
	if p.has("cap"):
		b.ell(hc + Vector3(0, 0.012, 0.003) * s, Vector3(0.026, 0.02, 0.03) * s, p["cap"], 0.0)
	if p.has("nape"):
		for x: float in [-1.0, 1.0]:
			b.ell(hc + Vector3(0.02 * x, 0.004, 0.014) * s, Vector3(0.012, 0.02, 0.022) * s, p["nape"], 0.0)
	if p.has("cheek"):
		for x: float in [-1.0, 1.0]:
			b.ell(hc + Vector3(0.021 * x, -0.008, -0.004) * s, Vector3(0.012, 0.014, 0.016) * s, p["cheek"], 0.0)
	if p.has("bib"):
		b.ell(hc + Vector3(0, -0.026, -0.012) * s, Vector3(0.017, 0.022, 0.012) * s, p["bib"], 0.0)
	if p.has("face"):
		b.ell(hc + Vector3(0, -0.006, -0.016) * s, Vector3(0.026, 0.024, 0.022) * s, p["face"], 0.0)
	if p.has("plume"):
		b.ell(hc + Vector3(0, 0.022, 0.0) * s, Vector3(0.018, 0.008, 0.026) * s, p["plume"], 0.0)  # black crown stripe
		b.limb(hc + Vector3(0, 0.018, 0.02) * s, hc + Vector3(0, 0.005, 0.11) * s, 0.004 * s, 0.0015 * s, p["plume"], 0.0, 4)  # plume
	var long_b: bool = bool(p.get("long_beak", false))
	var beak_l: float = 0.17 * s if long_b else 0.032 * s
	var bb: Vector3 = hc + Vector3(0, -0.004, -0.027) * s
	var bt: Vector3 = bb + Vector3(0, -0.006 * s if not long_b else -0.01 * s, -beak_l)
	b.cone(bb, bt, 0.011 * s + beak_l * 0.06, p["beak"], 0.0, 8, 0.85, 0.5)
	b.cone(bb + Vector3(0, -0.004, 0.0) * s, bt + Vector3(0, -0.002 * s, beak_l * 0.08), 0.008 * s + beak_l * 0.04, (p["beak"] as Color).darkened(0.1), 0.0, 6, 0.8, 0.4)
	if p.has("gonys"):
		b.ell(bt + Vector3(0, -0.003 * s, beak_l * 0.25), Vector3(0.004, 0.005, 0.006) * s, p["gonys"], 0.0)
	if p.has("cere"):
		b.ell(bb + Vector3(0, 0.004, -0.004) * s, Vector3(0.007, 0.005, 0.008) * s, Color(0.93, 0.92, 0.9), 0.0)
	if p.has("crest"):
		b.ell(hc + Vector3(0, 0.026 * s, 0.005), Vector3(0.016, 0.008, 0.02) * s, p["crest"], 0.0)
	var light_eye: bool = (p["eye"] as Color).v > 0.3
	for x: float in [-1.0, 1.0]:
		b.eye(hc + Vector3(0.022 * x, 0.008, -0.012) * s, Vector3(0.0078, 0.0082, 0.006) * s, 62 * x, p["eye"], light_eye)
		if id == "heron":
			b.ell(hc + Vector3(0.024 * x, 0.012, -0.002) * s, Vector3(0.004, 0.006, 0.02) * s, p["plume"], 0.0, Vector3(0, 62 * x, 0))  # eye stripe
	return b.commit()


## [fauna2] Mallard drake: a boat-shaped grey body riding low, chestnut breast, glossy green head
## over a white collar, a flat yellow bill with a dark nail, a blue speculum, black tail coverts
## with the drake's curl over a white tail. Flying: two-part wings, orange feet trailing.
static func duck(flying: bool) -> Mesh:
	var b := FaunaMesh.new()
	b.vary = 0.05
	b.vary_scale = 26.0
	var grey := Color(0.74, 0.74, 0.72)
	var chest := Color(0.46, 0.26, 0.17)
	var head := Color(0.06, 0.34, 0.2)
	var bill := Color(0.92, 0.8, 0.25)
	var black := Color(0.07, 0.07, 0.08)
	var backc := Color(0.48, 0.42, 0.34)
	var spec := Color(0.18, 0.28, 0.8)
	var by: float = 0.065 if not flying else 0.0
	b.rig(M.BODY)
	b.ell(Vector3(0, by, 0.01), Vector3(0.1, 0.07, 0.19), grey, 0.0, Vector3.ZERO, 16, 10)
	b.ell(Vector3(0, by + 0.012, -0.12), Vector3(0.082, 0.078, 0.085), chest, 0.0, Vector3(-10, 0, 0), 14, 9)
	b.ell(Vector3(0, by + 0.045, 0.04), Vector3(0.066, 0.03, 0.14), backc, 0.0)
	b.ell(Vector3(0, by + 0.02, 0.17), Vector3(0.056, 0.05, 0.06), black, 0.0, Vector3.ZERO, 10, 6, 0.3)
	b.ell(Vector3(0, by - 0.035, 0.0), Vector3(0.085, 0.03, 0.17), grey.lightened(0.1), 0.0)
	b.rig(M.TAIL, Vector3(0, by + 0.03, 0.19))
	b.ell(Vector3(0, by + 0.035, 0.235), Vector3(0.045, 0.01, 0.05), Color(0.92, 0.92, 0.9), 0.0, Vector3(-15, 0, 0), 10, 4)
	b.chain([Vector3(0, by + 0.05, 0.19), Vector3(0, by + 0.075, 0.185), Vector3(0, by + 0.08, 0.165)], [0.007, 0.006, 0.004], black, 0.0, 5)  # drake curl
	for x: float in [-1.0, 1.0]:
		if flying:
			var sh := Vector3(0.06 * x, by + 0.03, -0.05)
			var half: float = 0.42
			var wr: Vector3 = sh + Vector3(half * 0.46 * x, 0, 0.01)
			b.rig(M.WING_L if x < 0.0 else M.WING_R, sh)
			b.ell(sh + Vector3(half * 0.25 * x, 0, 0.045), Vector3(half * 0.27, 0.012, 0.075), backc.lightened(0.1), 0.0, Vector3.ZERO, 12, 5)
			b.ell(sh + Vector3(half * 0.3 * x, 0.006, 0.09), Vector3(half * 0.16, 0.008, 0.022), spec, 0.0, Vector3.ZERO, 10, 4, 0.6)
			b.rig(M.WINGTIP_L if x < 0.0 else M.WINGTIP_R, wr, sh)
			b.ell(wr + Vector3(half * 0.26 * x, 0, 0.045), Vector3(half * 0.29, 0.01, 0.06), backc, 0.0, Vector3(0, -12 * x, 0), 12, 5)
			b.ell(wr + Vector3(half * 0.42 * x, -0.002, 0.06), Vector3(half * 0.15, 0.008, 0.04), backc.darkened(0.3), 0.0, Vector3(0, -18 * x, 0), 10, 4)
			b.rig(M.BODY)
			b.limb(Vector3(0.025 * x, by - 0.02, 0.12), Vector3(0.03 * x, by - 0.02, 0.2), 0.008, 0.006, Color(0.95, 0.55, 0.15), 0.0, 5)
			b.ell(Vector3(0.03 * x, by - 0.02, 0.22), Vector3(0.022, 0.004, 0.025), Color(0.95, 0.55, 0.15), 0.0)
		else:
			var wrot := Vector3(-4, 4 * x, 0)
			b.ell(Vector3(0.072 * x, by + 0.03, 0.05), Vector3(0.026, 0.04, 0.13), backc.lightened(0.12), 0.0, wrot, 12, 7)
			b.ell(Vector3(0.095 * x, by + 0.025, 0.075), Vector3(0.006, 0.014, 0.03), spec, 0.0, wrot, 8, 4, 0.6)
			b.ell(Vector3(0.095 * x, by + 0.025, 0.11), Vector3(0.0062, 0.016, 0.005), WHITE, 0.0, wrot, 6, 3)
			b.ell(Vector3(0.04 * x, by + 0.045, 0.16), Vector3(0.016, 0.012, 0.06), backc.darkened(0.35), 0.0, Vector3(-6, -5 * x, 0))
	var nb := Vector3(0, by + 0.05, -0.13)
	var c := Vector3(0, by + 0.155, -0.175) if not flying else Vector3(0, by + 0.05, -0.32)
	b.rig(M.HEAD, nb)
	b.limb(nb, c + Vector3(0, -0.02, 0.01), 0.046, 0.033, head, 0.0, 12)
	b.ell(nb.lerp(c, 0.42), Vector3(0.045, 0.012, 0.043), WHITE, 0.0, Vector3(-35 if not flying else -80, 0, 0))  # collar
	b.ell(c, Vector3(0.04, 0.04, 0.05), head, 0.0, Vector3.ZERO, 14, 9, 0.55)
	b.ell(c + Vector3(0, 0.005, 0.005), Vector3(0.03, 0.038, 0.04), head.lightened(0.08), 0.0, Vector3.ZERO, 10, 6, 0.55)
	b.ell(c + Vector3(0, -0.014, -0.065), Vector3(0.021, 0.008, 0.038), bill, 0.0, Vector3(-6, 0, 0), 10, 5, 0.4)
	b.ell(c + Vector3(0, -0.019, -0.065), Vector3(0.018, 0.005, 0.034), bill.darkened(0.15), 0.0, Vector3(-6, 0, 0))
	b.ell(c + Vector3(0, -0.012, -0.1), Vector3(0.008, 0.005, 0.006), black, 0.0)
	for x: float in [-1.0, 1.0]:
		b.eye(c + Vector3(0.03 * x, 0.01, -0.014), Vector3(0.0085, 0.0085, 0.0065), 66 * x)
		b.ell(c + Vector3(0.006 * x, -0.008, -0.088), Vector3(0.002, 0.0015, 0.004), black, 0.0)  # nostrils
	return b.commit()
