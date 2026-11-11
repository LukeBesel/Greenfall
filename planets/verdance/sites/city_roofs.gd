class_name CityRoofs
extends RefCounted
## What stands on a Verdance city's roofs, so each city has its own roofline from the street and
## its own pattern from above: wooden water tanks, painted roof signs, parasols, pitched roofs over
## low houses, works skylights, tall hoardings, domes and flags. Which props a city carries and on
## what share of its roofs is data (cities.json "roof_props"); the colours are the city's palette.
## One MultiMesh per prop kind, coloured per instance.

const RANGE_FAR: float = 520.0
const RANGE_NEAR: float = 320.0
const MIN_ROOF_M: float = 6.5
const GABLE_PITCH: float = 0.34      # ridge height over half the span
const GABLE_OVERHANG: float = 0.45
const PARAPET_H: float = 1.2         # the proxy building's tallest parapet: a pitched roof sits on it


## `roofs`: [frame (site space), Rect2 in the frame, roof height, plan] per building.
static func build(city: VerdanceCity, roofs: Array, look: CityLook) -> void:
	var xf: Dictionary = {}
	var col: Dictionary = {}
	for k: String in ["tank", "sign", "shade", "gable", "sawtooth", "billboard", "dome", "flag"]:
		xf[k] = [] as Array[Transform3D]
		col[k] = [] as Array[Color]
	var pct: Dictionary = {}
	for k: String in xf:
		pct[k] = int(round(look.share(k) * 100.0))
	for e: Array in roofs:
		var bd: Dictionary = e[3]
		if bool(bd.get("ruined", false)):
			continue
		_roof(e[0], e[1], float(e[2]), bd, look, pct, xf, col)
	var mat: StandardMaterial3D = CityKit.vc_material()
	var two_sided: StandardMaterial3D = CityKit.vc_material()
	two_sided.cull_mode = BaseMaterial3D.CULL_DISABLED
	_emit(city, "RoofTanks", tank_mesh(), xf["tank"], col["tank"], mat, true, RANGE_FAR)
	_emit(city, "RoofSigns", sign_mesh(), xf["sign"], col["sign"], mat, true, RANGE_FAR)
	_emit(city, "RoofShades", shade_mesh(), xf["shade"], col["shade"], mat, false, RANGE_NEAR)
	_emit(city, "RoofGables", gable_mesh(), xf["gable"], col["gable"], mat, true, RANGE_FAR)
	_emit(city, "RoofSawteeth", sawtooth_mesh(), xf["sawtooth"], col["sawtooth"], mat, true, RANGE_FAR)
	_emit(city, "RoofBillboards", billboard_mesh(), xf["billboard"], col["billboard"], mat, true, RANGE_FAR)
	_emit(city, "RoofDomes", dome_mesh(), xf["dome"], [], mat, true, RANGE_FAR)
	_emit(city, "RoofFlags", flag_mesh(), xf["flag"], col["flag"], two_sided, false, RANGE_NEAR)


static func _emit(city: VerdanceCity, nm: String, mesh: Mesh, xfs: Array[Transform3D], cols: Array[Color], mat: Material, shadows: bool,
		range_m: float) -> void:
	if not xfs.is_empty():
		city.add_batch(nm, mesh, xfs, cols, mat, shadows, range_m)


static func _pick(list: Array[Color], i: int) -> Color:
	return list[i % list.size()] if not list.is_empty() else Color.WHITE


static func _roof(fr: Transform3D, r: Rect2, y: float, bd: Dictionary, look: CityLook, pct: Dictionary, xf: Dictionary, col: Dictionary) -> void:
	var floors: int = int(bd["floors"])
	var face: Vector2 = bd["face"]
	var h: int = hash([int(bd["seed"]), 4421])
	var c: Vector2 = r.get_center()
	var back: Vector2 = -face
	var lat := Vector2(-face.y, face.x)
	var depth: float = absf(r.size.x * face.x) + absf(r.size.y * face.y)
	var width: float = absf(r.size.x * lat.x) + absf(r.size.y * lat.y)
	# A pitched roof covers the whole of a low building; nothing else stands on it.
	if floors <= 3 and (h >> 13) % 100 < int(pct["gable"]) and minf(depth, width) >= 4.5:
		var along_x: bool = r.size.x >= r.size.y
		var span: float = (r.size.y if along_x else r.size.x) + GABLE_OVERHANG * 2.0
		var length: float = (r.size.x if along_x else r.size.y) + GABLE_OVERHANG * 2.0
		var rise: float = clampf(span * 0.5 * GABLE_PITCH * 2.0, 1.6, 3.6)
		var b := Basis(Vector3.UP, 0.0 if along_x else PI * 0.5).scaled_local(Vector3(length, rise, span))
		(xf["gable"] as Array[Transform3D]).append(fr * Transform3D(b, CityKit.v3(c, y + PARAPET_H)))
		(col["gable"] as Array[Color]).append(_pick(look.gables, h >> 3))
		return
	if depth < MIN_ROOF_M or width < MIN_ROOF_M:
		return
	# Works skylights fill a low roof.
	if floors <= 6 and (h >> 15) % 100 < int(pct["sawtooth"]) and minf(depth, width) >= 8.0:
		var bs := Basis(Vector3.UP, 0.0 if r.size.x >= r.size.y else PI * 0.5).scaled_local(
			Vector3(maxf(r.size.x, r.size.y) - 1.6, 2.4, minf(r.size.x, r.size.y) - 1.6))
		(xf["sawtooth"] as Array[Transform3D]).append(fr * Transform3D(bs, CityKit.v3(c, y)))
		(col["sawtooth"] as Array[Color]).append(_pick(look.gables, h >> 5))
		return
	# The tank stands on the back half (a setback tier keeps its back wall on the plan's).
	if floors >= 3 and h % 100 < int(pct["tank"]):
		var tp: Vector2 = c + back * (depth * 0.5 - 2.3) + lat * (float((h >> 7) % 100) / 100.0 - 0.5) * (width - 4.8)
		var sc: float = 0.85 + float((h >> 14) % 40) / 100.0
		(xf["tank"] as Array[Transform3D]).append(fr * Transform3D(Basis(Vector3.UP, float(h % 7)).scaled(Vector3.ONE * sc), CityKit.v3(tp, y)))
		(col["tank"] as Array[Color]).append(_pick(look.tanks, h >> 3))
	# A painted sign on the street parapet of the walk-ups (no setbacks under six floors).
	if floors >= 3 and floors <= 5 and width >= 7.5 and (h >> 9) % 100 < int(pct["sign"]):
		var sp: Vector2 = c + face * (depth * 0.5 - 0.7)
		(xf["sign"] as Array[Transform3D]).append(fr * Transform3D(Basis(Vector3.UP, atan2(face.x, face.y)), CityKit.v3(sp, y)))
		(col["sign"] as Array[Color]).append(_pick(look.signs, h >> 5))
	# Parasols on a roof terrace.
	if floors <= 7 and (h >> 11) % 100 < int(pct["shade"]):
		for k: int in 1 + (h >> 4) % 3:
			var pp: Vector2 = c + lat * (float(k) - 1.0) * 2.6 + face * (depth * 0.1) + back * float((h >> (k + 2)) % 3)
			if not r.grow(-1.6).has_point(pp):
				continue
			(xf["shade"] as Array[Transform3D]).append(fr * Transform3D(Basis(Vector3.UP, float(k)), CityKit.v3(pp, y)))
			(col["shade"] as Array[Color]).append(_pick(look.awnings, (h >> 6) + k))
	# A hoarding on the back of a tall roof, turned to the street.
	if floors >= 6 and width >= 9.0 and (h >> 17) % 100 < int(pct["billboard"]):
		var bp: Vector2 = c + back * (depth * 0.5 - 1.6)
		var s: float = 1.0 + float((h >> 19) % 30) / 100.0
		(xf["billboard"] as Array[Transform3D]).append(fr * Transform3D(Basis(Vector3.UP, atan2(face.x, face.y)).scaled(Vector3.ONE * s), CityKit.v3(bp, y)))
		(col["billboard"] as Array[Color]).append(_pick(look.signs, h >> 7))
	# A dome over the middle of a mid-rise civic roof.
	if floors >= 4 and floors <= 14 and minf(depth, width) >= 9.0 and (h >> 21) % 100 < int(pct["dome"]):
		var ds: float = minf(depth, width) * 0.3
		(xf["dome"] as Array[Transform3D]).append(fr * Transform3D(Basis.from_scale(Vector3.ONE * ds), CityKit.v3(c, y)))
	# A flag on the street corner of the roof.
	if floors >= 2 and (h >> 23) % 100 < int(pct["flag"]):
		var fp: Vector2 = c + face * (depth * 0.5 - 0.9) + lat * (width * 0.5 - 1.2) * (1.0 if (h >> 2) % 2 == 0 else -1.0)
		(xf["flag"] as Array[Transform3D]).append(fr * Transform3D(Basis(Vector3.UP, float(h % 5) * 0.4), CityKit.v3(fp, y)))
		(col["flag"] as Array[Color]).append(_pick(look.signs, h >> 9))


## A wooden roof tank: four steel legs with braces, a platform, the staved barrel with three
## hoops and a shallow cone. The barrel takes the instance colour.
static func tank_mesh() -> ArrayMesh:
	var g := BuildingDetail.Geo.new()
	var dark := Color(0.2, 0.2, 0.21)
	g.col = dark
	for sx: float in [-0.95, 0.95]:
		for sz: float in [-0.95, 0.95]:
			g.rod(Vector3(sx, 0.0, sz), Vector3(sx * 0.85, 2.2, sz * 0.85), 0.07)
	for a: Array in [[Vector3(-0.95, 0.2, -0.95), Vector3(0.85, 2.0, -0.85)], [Vector3(0.95, 0.2, 0.95), Vector3(-0.85, 2.0, 0.85)],
			[Vector3(-0.95, 0.2, 0.95), Vector3(-0.85, 2.0, -0.85)], [Vector3(0.95, 0.2, -0.95), Vector3(0.85, 2.0, 0.85)]]:
		g.rod(a[0], a[1], 0.035)
	g.cyl(Transform3D(Basis.IDENTITY, Vector3(0, 2.25, 0)), 1.45, 1.45, 0.12, 12)
	g.col = Color(1, 1, 1)
	g.cyl(Transform3D(Basis.IDENTITY, Vector3(0, 3.55, 0)), 1.25, 1.32, 2.5, 14)
	g.col = Color(0.3, 0.3, 0.32)
	for y: float in [2.7, 3.5, 4.4]:
		g.cyl(Transform3D(Basis.IDENTITY, Vector3(0, y, 0)), 1.31, 1.34, 0.08, 14, false)
	g.col = Color(0.62, 0.6, 0.58)
	g.cyl(Transform3D(Basis.IDENTITY, Vector3(0, 5.2, 0)), 0.08, 1.4, 0.8, 14)
	return CityKit.vc_mesh(g)


## A roof sign: a steel frame and a painted board facing +Z, the instance colour as its field
## with a dark lettering band and two darker rules across it.
static func sign_mesh() -> ArrayMesh:
	var g := BuildingDetail.Geo.new()
	g.col = Color(0.18, 0.18, 0.19)
	for sx: float in [-2.8, 0.0, 2.8]:
		g.rod(Vector3(sx, 0.0, -0.15), Vector3(sx, 4.6, -0.15), 0.06)
		g.rod(Vector3(sx, 0.0, -1.6), Vector3(sx, 3.4, -0.15), 0.04)
	g.rod(Vector3(-3.1, 1.5, -0.15), Vector3(3.1, 1.5, -0.15), 0.05)
	g.box(Transform3D(Basis.IDENTITY, Vector3(0, 3.1, -0.06)), Vector3(6.5, 3.1, 0.06))
	g.col = Color(1, 1, 1)
	g.box(Transform3D(Basis.IDENTITY, Vector3(0, 3.1, 0.0)), Vector3(6.3, 2.9, 0.06))
	g.col = Color(0.3, 0.3, 0.3)
	g.box(Transform3D(Basis.IDENTITY, Vector3(0, 3.5, 0.02)), Vector3(5.5, 0.7, 0.06))
	g.col = Color(0.55, 0.55, 0.55)
	g.box(Transform3D(Basis.IDENTITY, Vector3(0, 2.3, 0.02)), Vector3(5.5, 0.22, 0.06))
	g.box(Transform3D(Basis.IDENTITY, Vector3(0, 4.3, 0.02)), Vector3(6.3, 0.14, 0.06))
	return CityKit.vc_mesh(g)


## A terrace parasol: a pole and an eight-panel canopy, alternate panels a darker shade.
static func shade_mesh() -> ArrayMesh:
	var g := BuildingDetail.Geo.new()
	g.col = Color(0.3, 0.3, 0.3)
	g.rod(Vector3(0, 0, 0), Vector3(0, 2.3, 0), 0.03)
	var top := Vector3(0, 2.55, 0)
	for i: int in 8:
		var a0: float = TAU * float(i) / 8.0
		var a1: float = TAU * float(i + 1) / 8.0
		var p0 := Vector3(cos(a0) * 1.45, 2.1, sin(a0) * 1.45)
		var p1 := Vector3(cos(a1) * 1.45, 2.1, sin(a1) * 1.45)
		g.col = Color(1, 1, 1) if i % 2 == 0 else Color(0.55, 0.55, 0.55)
		var nrm: Vector3 = (p1 - top).cross(p0 - top).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		g.tri(top, p0, p1, nrm)
		g.tri(top, p0, p1, -nrm)
	return CityKit.vc_mesh(g)


## A pitched roof in a unit box (x along the ridge, z across, eaves at y 0, ridge at y 1): two
## tiled slopes in the instance colour, darker gable ends, a fascia under the eaves and a ridge cap.
static func gable_mesh() -> ArrayMesh:
	var g := BuildingDetail.Geo.new()
	g.col = Color(1, 1, 1)
	for sgn: float in [-1.0, 1.0]:
		var nrm := Vector3(0, 0.5, sgn).normalized()
		g.quad(Vector3(-0.5, 0, sgn * 0.5), Vector3(0.5, 0, sgn * 0.5), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0), nrm)
	g.col = Color(0.8, 0.78, 0.74)
	for sx: float in [-0.47, 0.47]:
		g.tri(Vector3(sx, 0, -0.47), Vector3(sx, 0, 0.47), Vector3(sx, 0.94, 0), Vector3(signf(sx), 0, 0))
	g.col = Color(0.62, 0.6, 0.58)
	g.box(Transform3D(Basis.IDENTITY, Vector3(0, -0.06, 0)), Vector3(0.96, 0.12, 0.96), -1, true)
	g.col = Color(0.5, 0.48, 0.46)
	g.box(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)), Vector3(1.0, 0.05, 0.035))
	return CityKit.vc_mesh(g)


## Works skylights in a unit box: four saw teeth across z, each a sloped sheet in the instance
## colour and an upright glazed face.
static func sawtooth_mesh() -> ArrayMesh:
	var g := BuildingDetail.Geo.new()
	var teeth: int = 4
	for i: int in teeth:
		var z0: float = -0.5 + float(i) / float(teeth)
		var z1: float = z0 + 1.0 / float(teeth)
		g.col = Color(1, 1, 1)
		g.quad(Vector3(-0.5, 0, z0), Vector3(0.5, 0, z0), Vector3(0.5, 1, z1), Vector3(-0.5, 1, z1), Vector3(0, 0.3, -1).normalized())
		g.col = Color(0.3, 0.5, 0.62)
		g.quad(Vector3(-0.5, 0, z1), Vector3(0.5, 0, z1), Vector3(0.5, 1, z1), Vector3(-0.5, 1, z1), Vector3(0, 0, 1))
		g.col = Color(0.7, 0.7, 0.68)
		for sx: float in [-0.5, 0.5]:
			g.tri(Vector3(sx, 0, z0), Vector3(sx, 0, z1), Vector3(sx, 1, z1), Vector3(signf(sx), 0, 0))
	return CityKit.vc_mesh(g)


## A hoarding: two lattice posts and a wide board facing +Z and -Z in the instance colour, with a
## pale panel and a dark band so it reads as an advert and not a blank sheet.
static func billboard_mesh() -> ArrayMesh:
	var g := BuildingDetail.Geo.new()
	g.col = Color(0.16, 0.16, 0.18)
	for sx: float in [-3.4, 3.4]:
		g.rod(Vector3(sx, 0, 0), Vector3(sx, 8.4, 0), 0.09)
		g.rod(Vector3(sx, 0, -1.8), Vector3(sx, 5.0, 0), 0.05)
	g.rod(Vector3(-3.4, 2.6, 0), Vector3(3.4, 2.6, 0), 0.05)
	g.col = Color(0.8, 0.8, 0.8)
	g.box(Transform3D(Basis.IDENTITY, Vector3(0, 5.9, 0)), Vector3(9.6, 4.8, 0.14))
	for sz: float in [-1.0, 1.0]:
		g.col = Color(1, 1, 1)
		g.box(Transform3D(Basis.IDENTITY, Vector3(-2.2, 6.3, sz * 0.08)), Vector3(3.6, 2.6, 0.04))
		g.col = Color(0.22, 0.22, 0.24)
		g.box(Transform3D(Basis.IDENTITY, Vector3(1.9, 6.6, sz * 0.08)), Vector3(4.4, 0.8, 0.04))
		g.box(Transform3D(Basis.IDENTITY, Vector3(1.9, 5.4, sz * 0.08)), Vector3(4.4, 0.3, 0.04))
		g.box(Transform3D(Basis.IDENTITY, Vector3(0, 3.8, sz * 0.08)), Vector3(9.6, 0.24, 0.04))
	return CityKit.vc_mesh(g)


## A civic dome one unit in radius: a stone drum with dark window slots, a copper-green dome in
## five rings and a gilt lantern.
static func dome_mesh() -> ArrayMesh:
	var g := BuildingDetail.Geo.new()
	g.col = Color(0.9, 0.82, 0.62)
	g.cyl(Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0)), 1.0, 1.05, 0.6, 16, false)
	g.col = Color(0.12, 0.14, 0.2)
	for i: int in 8:
		var a: float = TAU * float(i) / 8.0
		g.box(Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a), 0.32, sin(a)) * 1.0), Vector3(0.06, 0.36, 0.2))
	var rings: int = 5
	for i: int in rings:
		var a0: float = PI * 0.5 * float(i) / float(rings)
		var a1: float = PI * 0.5 * float(i + 1) / float(rings)
		g.col = Color(0.3, 0.66, 0.54) if i % 2 == 0 else Color(0.26, 0.6, 0.5)
		g.cyl(Transform3D(Basis.IDENTITY, Vector3(0, 0.6 + (sin(a0) + sin(a1)) * 0.5, 0)), cos(a1) * 1.04, cos(a0) * 1.04, sin(a1) - sin(a0), 16, false)
	g.col = Color(0.92, 0.72, 0.16)
	g.cyl(Transform3D(Basis.IDENTITY, Vector3(0, 1.72, 0)), 0.1, 0.16, 0.3, 8)
	g.cyl(Transform3D(Basis.IDENTITY, Vector3(0, 2.05, 0)), 0.01, 0.06, 0.4, 6)
	return CityKit.vc_mesh(g)


## A flagpole with a flag flying toward +X in the instance colour, a paler stripe across it.
static func flag_mesh() -> ArrayMesh:
	var g := BuildingDetail.Geo.new()
	g.col = Color(0.3, 0.3, 0.32)
	g.rod(Vector3(0, 0, 0), Vector3(0, 6.2, 0), 0.04)
	g.col = Color(0.82, 0.82, 0.82)
	g.quad(Vector3(0.05, 4.6, 0), Vector3(2.5, 4.75, 0.25), Vector3(2.5, 6.15, 0.25), Vector3(0.05, 6.1, 0), Vector3(0, 0, 1))
	g.col = Color(1, 1, 1)
	g.quad(Vector3(0.05, 5.15, 0.01), Vector3(2.5, 5.28, 0.26), Vector3(2.5, 5.68, 0.26), Vector3(0.05, 5.6, 0.01), Vector3(0, 0, 1))
	return CityKit.vc_mesh(g)
