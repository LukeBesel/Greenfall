class_name OldTownFlowers
extends RefCounted
## Old Town's bedding flowers: one small mesh (a leafy mound about 0.6 m across with blossoms
## standing on it) and its material (old_town_flowers.gdshader), shared by the borders round the
## lawns (OldTownGround) and the beds at the street trees' feet (OldTownTrees). The MultiMesh
## instance colour is the petal colour, so one mesh gives every colour of bed.

const SHADER: String = "res://planets/verdance/sites/old_town_flowers.gdshader"
const MOUND_R: float = 0.3
const MOUND_H: float = 0.2
const BLOSSOMS: int = 11
const PETALS: int = 6
## Petal colours a bed can take: poppy red, marigold, white, violet, pink, orange, cornflower.
const COLOURS: Array[Color] = [Color(0.9, 0.1, 0.08), Color(1.0, 0.74, 0.06), Color(0.97, 0.95, 0.9), Color(0.56, 0.3, 0.86),
	Color(1.0, 0.42, 0.62), Color(1.0, 0.46, 0.08), Color(0.25, 0.42, 0.95)]

static var _mesh: ArrayMesh
static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load(SHADER)
	return _material


## The clump: a faceted green dome and BLOSSOMS flat blossoms of PETALS sides on and just above it.
static func mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6113
	var segs: int = 7
	var ring: Array[Vector3] = []
	var mid: Array[Vector3] = []
	for i: int in segs:
		var a: float = TAU * float(i) / float(segs)
		ring.append(Vector3(cos(a), 0.0, sin(a)) * MOUND_R * rng.randf_range(0.85, 1.15))
		mid.append(Vector3(cos(a + 0.3), 0.0, sin(a + 0.3)) * MOUND_R * 0.6 + Vector3(0, MOUND_H * rng.randf_range(0.6, 0.85), 0))
	var top := Vector3(0, MOUND_H, 0)
	for i: int in segs:
		var j: int = (i + 1) % segs
		_leaf_tri(st, [ring[i], mid[i], ring[j]], rng)
		_leaf_tri(st, [ring[j], mid[i], mid[j]], rng)
		_leaf_tri(st, [mid[i], top, mid[j]], rng)
	for b: int in BLOSSOMS:
		var y: float = 1.0 - (float(b) + 0.5) / float(BLOSSOMS) * 0.8
		var rr: float = sqrt(1.0 - y * y)
		var phi: float = float(b) * 2.39996
		var out := Vector3(cos(phi) * rr, y, sin(phi) * rr)
		var c: Vector3 = Vector3(out.x * MOUND_R * 0.95, MOUND_H * (0.55 + 0.75 * y) + rng.randf_range(0.02, 0.09), out.z * MOUND_R * 0.95)
		var n: Vector3 = (out + Vector3(0, 0.9, 0)).normalized()
		var ax: Vector3 = n.cross(Vector3.RIGHT if absf(n.x) < 0.8 else Vector3.FORWARD).normalized()
		var az: Vector3 = n.cross(ax)
		var r: float = rng.randf_range(0.05, 0.075)
		for k: int in PETALS:
			var a0: float = TAU * float(k) / float(PETALS)
			var a1: float = TAU * float(k + 1) / float(PETALS)
			var pts: Array = [[c, 1.0], [c + (ax * cos(a0) + az * sin(a0)) * r, 0.0], [c + (ax * cos(a1) + az * sin(a1)) * r, 0.0]]
			for p: Array in pts:
				st.set_color(Color.WHITE)
				st.set_normal(n)
				st.set_uv(Vector2(1.0, 0.0))
				st.set_uv2(Vector2(1.0, float(p[1])))
				st.add_vertex(p[0])
	_mesh = st.commit()
	return _mesh


## A bed's petal colour: palette entry `i`, a little lighter or darker for each clump.
static func colour(i: int, rng: RandomNumberGenerator) -> Color:
	return COLOURS[posmod(i, COLOURS.size())].lightened(rng.randf_range(-0.06, 0.12))


static func _leaf_tri(st: SurfaceTool, pts: Array[Vector3], rng: RandomNumberGenerator) -> void:
	var shade: float = rng.randf()
	for p: Vector3 in pts:
		st.set_color(Color.WHITE)
		st.set_normal((p + Vector3(0, 0.25, 0)).normalized())
		st.set_uv(Vector2(shade * (0.5 + p.y / MOUND_H * 0.5), 0.0))
		st.set_uv2(Vector2.ZERO)
		st.add_vertex(p)
