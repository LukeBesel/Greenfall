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
	var m: Mesh = null
	match id:
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


static func rabbit() -> Mesh:
	var b := FaunaMesh.new()
	var fur := Color(0.62, 0.5, 0.38)
	b.ell(Vector3(0, 0.11, 0.04), Vector3(0.075, 0.085, 0.1), fur)
	b.ell(Vector3(0, 0.12, -0.04), Vector3(0.06, 0.07, 0.07), fur)
	b.ell(Vector3(0, 0.08, -0.03), Vector3(0.05, 0.05, 0.08), Color(0.9, 0.86, 0.8), 0.0)
	b.rig(M.TAIL, Vector3(0, 0.12, 0.13))
	b.ell(Vector3(0, 0.12, 0.14), Vector3(0.03, 0.03, 0.025), WHITE, 0.0)
	for x: float in [-1.0, 1.0]:
		b.rig(M.HIND, Vector3(0.05 * x, 0.08, 0.06))
		b.ell(Vector3(0.05 * x, 0.06, 0.06), Vector3(0.03, 0.05, 0.065), fur)
		b.ell(Vector3(0.048 * x, 0.012, 0.03), Vector3(0.018, 0.012, 0.055), fur.darkened(0.1))
		b.rig(M.FRONT, Vector3(0.03 * x, 0.1, -0.07))
		b.limb(Vector3(0.03 * x, 0.09, -0.07), Vector3(0.03 * x, 0.015, -0.085), 0.014, 0.011, fur)
	var c := Vector3(0, 0.19, -0.1)
	b.rig(M.HEAD, Vector3(0, 0.15, -0.07))
	b.ell(c, Vector3(0.045, 0.045, 0.055), fur)
	b.ell(c + Vector3(0, -0.015, -0.045), Vector3(0.025, 0.02, 0.02), Color(0.88, 0.82, 0.75), 0.0)
	b.ell(c + Vector3(0, -0.008, -0.064), Vector3(0.006, 0.005, 0.004), Color(0.6, 0.4, 0.4), 0.0)
	for x: float in [-1.0, 1.0]:
		b.ell(c + Vector3(0.03 * x, 0.012, -0.028), Vector3(0.011, 0.012, 0.01), EYE_DARK, 0.0, Vector3.ZERO, 8, 5, 1.0)
		b.ell(c + Vector3(0.018 * x, 0.085, 0.02), Vector3(0.016, 0.06, 0.008), fur, 1.0, Vector3(-15, 0, 10 * x))
		b.ell(c + Vector3(0.018 * x, 0.085, 0.014), Vector3(0.01, 0.048, 0.004), Color(0.85, 0.65, 0.62), 0.0, Vector3(-15, 0, 10 * x))
	return b.commit()


## Foxes (red, fennec, arctic). p: ears (scale), len (body scale), fur, belly, socks, tip, fluff.
static func fox(p: Dictionary) -> Mesh:
	var b := FaunaMesh.new()
	var fur: Color = p.get("fur", Color(0.82, 0.42, 0.16))
	var belly: Color = p.get("belly", Color(0.95, 0.92, 0.86))
	var socks: Color = p.get("socks", Color(0.16, 0.11, 0.09))
	var tip: Color = p.get("tip", WHITE)
	var s: float = float(p.get("len", 1.0))
	var ears: float = float(p.get("ears", 1.0))
	var fluff: float = float(p.get("fluff", 1.0))
	var sc := Vector3(s, s, s)
	b.ell(Vector3(0, 0.3, 0) * sc, Vector3(0.085, 0.09, 0.22) * sc * Vector3(fluff, fluff, 1), fur, 0.0)
	b.ell(Vector3(0, 0.3, -0.15) * sc, Vector3(0.09, 0.1, 0.1) * sc * fluff, fur, 0.0)
	b.ell(Vector3(0, 0.26, -0.13) * sc, Vector3(0.06, 0.07, 0.08) * sc, belly, 0.0)
	for x: float in [-1.0, 1.0]:
		var hip := Vector3(0.05 * x, 0.28, -0.16) * sc
		b.rig(M.LEG_FL if x < 0.0 else M.LEG_FR, hip)
		b.limb(hip, Vector3(0.05 * x, 0.14, -0.17) * sc, 0.027 * s, 0.02 * s, fur, 0.0)
		b.limb(Vector3(0.05 * x, 0.14, -0.17) * sc, Vector3(0.05 * x, 0.02, -0.18) * sc, 0.02 * s, 0.017 * s, socks, 0.0)
		var bh := Vector3(0.055 * x, 0.29, 0.15) * sc
		b.rig(M.LEG_BL if x < 0.0 else M.LEG_BR, bh)
		b.ell(Vector3(0.055 * x, 0.25, 0.16) * sc, Vector3(0.04, 0.08, 0.07) * sc, fur, 0.0, Vector3(-15, 0, 0))
		b.limb(Vector3(0.055 * x, 0.18, 0.19) * sc, Vector3(0.05 * x, 0.02, 0.17) * sc, 0.02 * s, 0.017 * s, socks, 0.0)
	b.rig(M.TAIL, Vector3(0, 0.31, 0.2) * sc)
	b.ell(Vector3(0, 0.25, 0.37) * sc, Vector3(0.065, 0.065, 0.17) * sc * fluff, fur, 0.0, Vector3(30, 0, 0))
	b.ell(Vector3(0, 0.18, 0.5) * sc, Vector3(0.045, 0.045, 0.06) * sc * fluff, tip, 0.0, Vector3(40, 0, 0))
	var c := Vector3(0, 0.39, -0.28) * sc
	b.rig(M.HEAD, Vector3(0, 0.34, -0.2) * sc)
	b.ell(Vector3(0, 0.36, -0.22) * sc, Vector3(0.05, 0.06, 0.06) * sc, fur, 0.0)
	b.ell(c, Vector3(0.068, 0.06, 0.065) * sc, fur, 0.0)
	b.ell(c + Vector3(0, -0.02, 0.0) * sc, Vector3(0.06, 0.04, 0.05) * sc, belly, 0.0)
	b.cone(c + Vector3(0, -0.01, -0.04) * sc, c + Vector3(0, -0.02, -0.13) * sc, 0.038 * s, fur, 0.0, 8)
	b.cone(c + Vector3(0, -0.026, -0.04) * sc, c + Vector3(0, -0.03, -0.12) * sc, 0.03 * s, belly, 0.0, 8)
	b.ell(c + Vector3(0, -0.02, -0.13) * sc, Vector3(0.011, 0.009, 0.009) * sc, NOSE, 0.0, Vector3.ZERO, 8, 4, 1.0)
	for x: float in [-1.0, 1.0]:
		b.ell(c + Vector3(0.033 * x, 0.012, -0.05) * sc, Vector3(0.011, 0.01, 0.007) * sc, Color(0.2, 0.12, 0.05), 0.0, Vector3(0, 25 * x, 0), 8, 5, 1.0)
		var eb: Vector3 = c + Vector3(0.036 * x, 0.04, 0.01) * sc
		b.cone(eb, eb + Vector3(0.018 * x, 0.075 * ears, 0.004) * sc, 0.03 * s * sqrt(ears), fur, 0.0, 6, 0.5)
		b.cone(eb + Vector3(0, 0.004, -0.009) * sc, eb + Vector3(0.016 * x, 0.068 * ears, -0.006) * sc, 0.02 * s * sqrt(ears), belly.darkened(0.08), 0.0, 6, 0.3)
	return b.commit()


static func deer(stag: bool) -> Mesh:
	var b := FaunaMesh.new()
	var fur := Color(0.58, 0.4, 0.24)
	var dark := Color(0.25, 0.18, 0.12)
	var pale := Color(0.92, 0.88, 0.8)
	b.ell(Vector3(0, 0.74, 0.02), Vector3(0.16, 0.2, 0.42), fur, 0.0)
	b.ell(Vector3(0, 0.76, -0.27), Vector3(0.16, 0.22, 0.18), fur, 0.0)
	b.ell(Vector3(0, 0.76, 0.29), Vector3(0.165, 0.21, 0.17), fur, 0.0)
	b.ell(Vector3(0, 0.6, 0.0), Vector3(0.12, 0.09, 0.32), fur.lightened(0.18), 0.0)
	b.ell(Vector3(0, 0.8, 0.43), Vector3(0.1, 0.13, 0.05), pale, 0.0)  # rump patch
	for x: float in [-1.0, 1.0]:
		var sh := Vector3(0.085 * x, 0.72, -0.29)
		b.rig(M.LEG_FL if x < 0.0 else M.LEG_FR, sh)
		b.ell(Vector3(0.085 * x, 0.62, -0.3), Vector3(0.06, 0.12, 0.08), fur, 0.0)
		b.limb(Vector3(0.08 * x, 0.55, -0.31), Vector3(0.075 * x, 0.32, -0.31), 0.045, 0.03, fur, 0.0)
		b.limb(Vector3(0.075 * x, 0.32, -0.31), Vector3(0.075 * x, 0.04, -0.32), 0.026, 0.02, fur.darkened(0.12), 0.0, 6)
		b.cone(Vector3(0.075 * x, 0.05, -0.32), Vector3(0.075 * x, 0.0, -0.345), 0.022, dark, 0.0, 6, 1.0, 0.6)
		var hp := Vector3(0.09 * x, 0.78, 0.3)
		b.rig(M.LEG_BL if x < 0.0 else M.LEG_BR, hp)
		b.ell(Vector3(0.09 * x, 0.64, 0.31), Vector3(0.08, 0.19, 0.14), fur, 0.0, Vector3(-10, 0, 0))
		b.limb(Vector3(0.085 * x, 0.5, 0.36), Vector3(0.08 * x, 0.3, 0.41), 0.042, 0.026, fur, 0.0)
		b.limb(Vector3(0.08 * x, 0.3, 0.41), Vector3(0.078 * x, 0.04, 0.36), 0.024, 0.02, fur.darkened(0.12), 0.0, 6)
		b.cone(Vector3(0.078 * x, 0.05, 0.36), Vector3(0.078 * x, 0.0, 0.335), 0.022, dark, 0.0, 6, 1.0, 0.6)
	b.rig(M.TAIL, Vector3(0, 0.88, 0.45))
	b.ell(Vector3(0, 0.86, 0.47), Vector3(0.04, 0.07, 0.03), fur, 0.0, Vector3(-20, 0, 0))
	# Neck and head (part HEAD pivots at the withers so grazing lowers the whole neck).
	var piv := Vector3(0, 0.9, -0.3)
	b.rig(M.HEAD, piv)
	b.limb(Vector3(0, 0.88, -0.33), Vector3(0, 1.18, -0.5), 0.09, 0.06, fur, 0.0, 10)
	b.ell(Vector3(0, 0.92, -0.42), Vector3(0.07, 0.11, 0.07), pale.darkened(0.1), 0.0, Vector3(-30, 0, 0))
	var c := Vector3(0, 1.22, -0.55)
	b.ell(c, Vector3(0.075, 0.075, 0.09), fur, 0.0)
	b.cone(c + Vector3(0, -0.01, -0.05), c + Vector3(0, -0.06, -0.2), 0.055, fur, 0.0, 10)
	b.ell(c + Vector3(0, -0.055, -0.19), Vector3(0.028, 0.022, 0.02), NOSE, 0.0, Vector3.ZERO, 8, 4, 0.9)
	b.ell(c + Vector3(0, -0.07, -0.13), Vector3(0.035, 0.02, 0.05), pale, 0.0)
	for x: float in [-1.0, 1.0]:
		b.ell(c + Vector3(0.058 * x, 0.012, -0.04), Vector3(0.016, 0.018, 0.012), EYE_DARK, 0.0, Vector3(0, 30 * x, 0), 8, 5, 1.0)
		b.ell(c + Vector3(0.085 * x, 0.06, 0.03), Vector3(0.05, 0.022, 0.08), fur, 0.0, Vector3(20, 25 * x, 40 * x))
		b.ell(c + Vector3(0.087 * x, 0.064, 0.02), Vector3(0.036, 0.012, 0.06), pale, 0.0, Vector3(20, 25 * x, 40 * x))
		if stag:
			var ab: Vector3 = c + Vector3(0.03 * x, 0.07, 0.02)
			var top: Vector3 = ab + Vector3(0.04 * x, 0.22, 0.03)
			b.limb(ab, top, 0.014, 0.008, Color(0.55, 0.45, 0.32), 0.0, 5)
			b.limb(ab + Vector3(0.015 * x, 0.1, 0.01), ab + Vector3(0.02 * x, 0.15, -0.07), 0.009, 0.005, Color(0.55, 0.45, 0.32), 0.0, 5)
			b.limb(top + Vector3(-0.01 * x, -0.03, 0.0), top + Vector3(0.0, 0.03, 0.06), 0.008, 0.004, Color(0.55, 0.45, 0.32), 0.0, 5)
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


static func seal() -> Mesh:
	var b := FaunaMesh.new()
	var fur := Color(0.5, 0.5, 0.5)
	b.rig(M.FLEX, Vector3(0, 0.15, -0.1))
	b.ell(Vector3(0, 0.17, 0.0), Vector3(0.2, 0.17, 0.45), fur, 1.0, Vector3.ZERO, 16, 9)
	b.ell(Vector3(0, 0.13, 0.35), Vector3(0.13, 0.1, 0.25), fur, 1.0)
	b.ell(Vector3(0, 0.1, 0.05), Vector3(0.17, 0.08, 0.38), fur.lightened(0.25), 0.6)
	for x: float in [-1.0, 1.0]:
		b.ell(Vector3(0.09 * x, 0.04, 0.62), Vector3(0.07, 0.015, 0.1), fur.darkened(0.2), 0.8, Vector3(0, 25 * x, 0))
	b.rig(M.FRONT, Vector3(0.15, 0.1, -0.15))
	for x: float in [-1.0, 1.0]:
		b.ell(Vector3(0.19 * x, 0.05, -0.15), Vector3(0.1, 0.02, 0.05), fur.darkened(0.2), 0.8, Vector3(0, -30 * x, -20 * x))
	var c := Vector3(0, 0.33, -0.4)
	b.rig(M.HEAD, Vector3(0, 0.25, -0.3))
	b.ell(Vector3(0, 0.27, -0.33), Vector3(0.13, 0.12, 0.12), fur, 1.0)
	b.ell(c, Vector3(0.11, 0.1, 0.11), fur, 1.0)
	b.ell(c + Vector3(0, -0.03, -0.08), Vector3(0.06, 0.045, 0.05), fur.lightened(0.2), 0.6)
	b.ell(c + Vector3(0, -0.015, -0.125), Vector3(0.018, 0.012, 0.01), NOSE, 0.0, Vector3.ZERO, 8, 4, 1.0)
	for x: float in [-1.0, 1.0]:
		b.ell(c + Vector3(0.05 * x, 0.025, -0.08), Vector3(0.022, 0.024, 0.016), EYE_DARK, 0.0, Vector3(0, 25 * x, 0), 10, 6, 1.0)
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


## Lake fish (~0.3 m): dark back, silver flanks (tint = back colour), forked tail that flexes.
static func fish() -> Mesh:
	var b := FaunaMesh.new()
	b.rig(M.FLEX, Vector3(0, 0, -0.06))
	b.ell(Vector3(0, 0, 0), Vector3(0.028, 0.05, 0.14), Color(0.82, 0.84, 0.82), 0.0, Vector3.ZERO, 12, 7, 0.6)
	b.ell(Vector3(0, 0.018, 0.0), Vector3(0.022, 0.035, 0.13), Color(1, 1, 1), 1.0, Vector3.ZERO, 10, 6, 0.4)
	b.cone(Vector3(0, 0.045, 0.0), Vector3(0, 0.08, 0.05), 0.04, Color(1, 1, 1), 1.0, 4, 0.12)
	b.cone(Vector3(0, 0.0, 0.12), Vector3(0, 0.05, 0.2), 0.03, Color(1, 1, 1), 1.0, 4, 0.12)
	b.cone(Vector3(0, 0.0, 0.12), Vector3(0, -0.045, 0.2), 0.03, Color(1, 1, 1), 1.0, 4, 0.12)
	for x: float in [-1.0, 1.0]:
		b.ell(Vector3(0.022 * x, 0.012, -0.1), Vector3(0.007, 0.009, 0.009), EYE_DARK, 0.0, Vector3.ZERO, 6, 4, 1.0)
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

## Per-species bird shape. Colours: body, breast, head, wing, beak, legs; sizes in metres.
static func bird_params(id: String) -> Dictionary:
	match id:
		"pigeon":
			return {"s": 1.0, "body": Color(0.58, 0.6, 0.66), "breast": Color(0.62, 0.58, 0.64), "head": Color(0.45, 0.47, 0.54), "neck": Color(0.35, 0.5, 0.45),
				"wing": Color(0.6, 0.63, 0.68), "bar": Color(0.2, 0.2, 0.24), "beak": Color(0.25, 0.22, 0.22), "leg": Color(0.75, 0.35, 0.35), "eye": Color(0.9, 0.45, 0.1),
				"tail": 0.09, "legh": 0.04, "neckl": 0.03, "span": 0.6}
		"sparrow":
			return {"s": 0.55, "body": Color(0.55, 0.42, 0.3), "breast": Color(0.78, 0.74, 0.66), "head": Color(0.45, 0.4, 0.38), "neck": Color(0.55, 0.42, 0.3),
				"wing": Color(0.5, 0.36, 0.22), "bar": Color(0.92, 0.9, 0.85), "beak": Color(0.25, 0.2, 0.18), "leg": Color(0.6, 0.48, 0.4), "eye": EYE_DARK,
				"tail": 0.08, "legh": 0.04, "neckl": 0.0, "span": 0.45}
		"songbird":
			return {"s": 0.52, "body": Color(0.48, 0.42, 0.33), "breast": Color(0.92, 0.45, 0.18), "head": Color(0.48, 0.42, 0.33), "neck": Color(0.92, 0.45, 0.18),
				"wing": Color(0.42, 0.36, 0.28), "bar": Color(0.42, 0.36, 0.28), "beak": Color(0.15, 0.12, 0.1), "leg": Color(0.45, 0.36, 0.3), "eye": EYE_DARK,
				"tail": 0.09, "legh": 0.05, "neckl": 0.0, "span": 0.45}
		"gull":
			return {"s": 1.45, "body": Color(0.95, 0.95, 0.95), "breast": Color(0.98, 0.98, 0.98), "head": Color(0.98, 0.98, 0.98), "neck": Color(0.97, 0.97, 0.97),
				"wing": Color(0.66, 0.7, 0.75), "bar": Color(0.1, 0.1, 0.12), "beak": Color(0.95, 0.8, 0.2), "leg": Color(0.95, 0.7, 0.45), "eye": Color(0.85, 0.8, 0.4),
				"tail": 0.08, "legh": 0.05, "neckl": 0.02, "span": 0.95}
		"duck":
			return {"s": 1.4, "body": Color(0.55, 0.5, 0.45), "breast": Color(0.5, 0.32, 0.24), "head": Color(0.1, 0.38, 0.22), "neck": Color(0.95, 0.95, 0.92),
				"wing": Color(0.5, 0.48, 0.45), "bar": Color(0.2, 0.3, 0.75), "beak": Color(0.9, 0.78, 0.25), "leg": Color(0.95, 0.55, 0.15), "eye": EYE_DARK,
				"tail": 0.06, "legh": 0.0, "neckl": 0.02, "span": 0.8, "flat_beak": true}
		"heron":
			return {"s": 1.6, "body": Color(0.62, 0.65, 0.7), "breast": Color(0.9, 0.9, 0.9), "head": Color(0.95, 0.95, 0.95), "neck": Color(0.88, 0.88, 0.9),
				"wing": Color(0.55, 0.58, 0.64), "bar": Color(0.2, 0.2, 0.24), "beak": Color(0.85, 0.7, 0.3), "leg": Color(0.55, 0.48, 0.35), "eye": Color(0.9, 0.85, 0.2),
				"tail": 0.08, "legh": 0.36, "neckl": 0.3, "span": 1.6, "long_beak": true}
		"crane":
			return {"s": 1.7, "body": Color(0.97, 0.97, 0.96), "breast": Color(0.98, 0.98, 0.97), "head": Color(0.98, 0.98, 0.98), "neck": Color(0.97, 0.97, 0.96),
				"wing": Color(0.96, 0.96, 0.95), "bar": Color(0.12, 0.12, 0.14), "beak": Color(0.95, 0.65, 0.2), "leg": Color(0.2, 0.2, 0.2), "eye": EYE_DARK,
				"tail": 0.22, "legh": 0.3, "neckl": 0.3, "span": 2.2, "long_beak": true, "crest": Color(0.85, 0.2, 0.2)}
	return bird_params("sparrow")


## A bird, perched (wings folded) or flying (wings spread, legs tucked; wings flap via the rig).
static func bird(id: String, flying: bool) -> Mesh:
	var p: Dictionary = bird_params(id)
	var b := FaunaMesh.new()
	var s: float = float(p["s"])
	var legh: float = float(p["legh"]) * s / maxf(s, 0.001) if not flying else 0.0
	var neckl: float = float(p["neckl"])
	var by: float = 0.08 * s + (legh if not flying else 0.0)
	var body_c := Vector3(0, by, 0)
	b.rig(M.BODY)
	b.ell(body_c, Vector3(0.055, 0.058, 0.1) * s, p["body"], 0.0, Vector3(-10 if not flying else 0, 0, 0))
	b.ell(body_c + Vector3(0, -0.01, -0.05) * s, Vector3(0.05, 0.05, 0.06) * s, p["breast"], 0.0)
	# Tail.
	var tl: float = float(p["tail"])
	b.rig(M.TAIL, body_c + Vector3(0, 0.0, 0.08) * s)
	b.ell(body_c + Vector3(0, 0.01 if not flying else 0.0, 0.08 * s + tl * 0.5 * s), Vector3(0.03 * s, 0.006 * s, tl * 0.55 * s), p["wing"], 0.0, Vector3(-15 if not flying else 0, 0, 0))
	if p.has("crest"):
		b.ell(body_c + Vector3(0, -0.005, 0.1 * s + tl * 0.7 * s), Vector3(0.025 * s, 0.01 * s, 0.05 * s), p["bar"], 0.0)
	# Legs (perched only).
	if not flying and legh > 0.0:
		for x: float in [-1.0, 1.0]:
			var hip: Vector3 = body_c + Vector3(0.018 * x * s, -0.04 * s, 0.0)
			b.rig(M.LEG_BL if x < 0.0 else M.LEG_BR, hip)
			b.limb(hip, Vector3(0.018 * x * s, 0.004, 0.005 * s), 0.006 * s, 0.004 * s, p["leg"], 0.0, 5, false)
			for k: int in 3:
				var a: float = deg_to_rad(-30 + 30 * k)
				b.limb(Vector3(0.018 * x * s, 0.003, 0.005 * s), Vector3(0.018 * x * s + sin(a) * 0.02 * s, 0.002, 0.005 * s - cos(a) * 0.025 * s), 0.003 * s, 0.002 * s, p["leg"], 0.0, 4, false)
	# Wings.
	var span: float = float(p["span"])
	for x: float in [-1.0, 1.0]:
		var part: int = M.WING_L if x < 0.0 else M.WING_R
		if flying:
			var sh: Vector3 = body_c + Vector3(0.035 * x * s, 0.02 * s, -0.02 * s)
			b.rig(part, sh)
			var half: float = span * 0.5
			b.ell(sh + Vector3(half * 0.32 * x, 0, 0.01), Vector3(half * 0.34, 0.012 * s, 0.07 * s), p["wing"], 0.0)
			b.ell(sh + Vector3(half * 0.72 * x, 0, 0.03 * s), Vector3(half * 0.3, 0.008 * s, 0.05 * s), p["wing"], 0.0, Vector3(0, -12 * x, 0))
			b.ell(sh + Vector3(half * 0.9 * x, 0, 0.04 * s), Vector3(half * 0.12, 0.007 * s, 0.035 * s), p["bar"], 0.0, Vector3(0, -15 * x, 0))
		else:
			var sh2: Vector3 = body_c + Vector3(0.05 * x * s, 0.015 * s, -0.03 * s)
			b.rig(part, sh2)
			b.ell(body_c + Vector3(0.045 * x * s, 0.012 * s, 0.02 * s), Vector3(0.018 * s, 0.042 * s, 0.1 * s), p["wing"], 0.0, Vector3(-12, 6 * x, 0))
			b.ell(body_c + Vector3(0.05 * x * s, 0.0, 0.05 * s), Vector3(0.012 * s, 0.03 * s, 0.04 * s), p["bar"], 0.0, Vector3(-12, 6 * x, 0))
	# Neck + head.
	var neck_base: Vector3 = body_c + Vector3(0, 0.03, -0.06) * s
	var hc: Vector3
	if flying:
		hc = body_c + Vector3(0, 0.015 * s, -0.11 * s - neckl * 0.9)
	else:
		hc = neck_base + Vector3(0, 0.045 * s + neckl, -0.03 * s - neckl * 0.15)
	b.rig(M.HEAD, neck_base)
	b.limb(neck_base, hc, 0.035 * s * (0.7 if neckl > 0.1 else 1.0), 0.026 * s * (0.6 if neckl > 0.1 else 1.0), p["neck"], 0.0, 8)
	b.ell(hc, Vector3(0.032, 0.032, 0.036) * s, p["head"], 0.0)
	var beak_l: float = 0.17 * s if p.get("long_beak", false) else 0.035 * s
	if p.get("flat_beak", false):
		b.ell(hc + Vector3(0, -0.006 * s, -0.045 * s), Vector3(0.016 * s, 0.006 * s, 0.03 * s), p["beak"], 0.0, Vector3.ZERO, 8, 4, 0.5)
	else:
		b.cone(hc + Vector3(0, -0.004 * s, -0.026 * s), hc + Vector3(0, -0.008 * s, -0.026 * s - beak_l), 0.01 * s + beak_l * 0.06, p["beak"], 0.0, 6, 1.0, 0.5)
	if id == "duck":
		b.ell(hc + Vector3(0, -0.035 * s, 0.01), Vector3(0.03, 0.006, 0.03) * s, Color(0.97, 0.97, 0.95), 0.0)  # white collar
	if p.has("crest"):
		b.ell(hc + Vector3(0, 0.026 * s, 0.005), Vector3(0.016, 0.008, 0.02) * s, p["crest"], 0.0)
	for x: float in [-1.0, 1.0]:
		b.ell(hc + Vector3(0.024 * x * s, 0.008 * s, -0.012 * s), Vector3(0.007, 0.007, 0.006) * s, p["eye"], 0.0, Vector3.ZERO, 6, 4, 1.0)
	return b.commit()
