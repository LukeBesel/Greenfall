class_name CityOldTown
extends VerdanceCity
## Old Town, Verdance's first city (site 0; docs/design/PLANET1_DESIGN.md sections 4 and 15): a
## lakeside market town of warm brick and cream walls, terracotta, copper-green and slate roofs,
## roof tanks and striped market stalls (the look is data: cities.json "old_town"). This script is
## its source landmark only: the pumping station at the head of the main street, on the lake: a
## brick pump house with a standpipe tower and a burst main fountaining over a flooded forecourt
## (OldTownBurst: the jet, its spray and the flood, or the cap and the damp ground).
## set_source_state("broken" | "shut_down") switches it. Everything else is VerdanceCity.

const ID: String = "old_town"
const T_RED: int = BuildingDetail.T_RED_BRICK
const BRICK := Color(1.0, 0.9, 0.84)
const STONE := Color(0.92, 0.88, 0.8)
const PIPE_TEAL := Color(0.08, 0.5, 0.52)

var station_at := Vector3.ZERO         # the burst main
var burst_main: OldTownBurst           # the jet and the flood, or the cap and the damp ground


func _init() -> void:
	city_id = ID
	look = CityLook.of(ID)


## The town's building material (false: the pad town, true: the outskirts).
static func material(local_space: bool) -> ShaderMaterial:
	return CityLook.of(ID).material(local_space)


## Paints one planned building in the town's colours.
static func paint(bd: Dictionary, _rng: RandomNumberGenerator = null, _dist: float = 0.0) -> void:
	CityLook.of(ID).paint(bd)


## Reserves the station's block in the town's layout: its buildings go, the block stays a paved
## block. Returns false when no block is free (the station is then left out).
func plan(site: VerdanceSite) -> bool:
	_site = site
	block_key = _pick_block(site)
	if block_key == NO_BLOCK:
		return false
	var b: Dictionary = site.layout.blocks[block_key]
	var r: Rect2 = b["rect"]
	b["type"] = CityLayout.Block.BUILDINGS
	b["buildings"] = []
	b["landmark"] = true
	site.layout.blocks[block_key] = b
	var c: Vector2 = r.get_center()
	landmark_rects = [Rect2(c + Vector2(-10.5, -10.4), Vector2(16.5, 12.4)), Rect2(c + Vector2(6.3, -9.2), Vector2(4.6, 4.6))]
	station_at = Vector3(c.x + 2.6, 0.0, c.y + 9.4)
	frame = Transform3D(Basis.IDENTITY, station_at)
	var ko: YardKeepOut = site.globe_ctx.get("keep_out") as YardKeepOut
	if ko:  # the flood shows from the start: loose junk keeps off the water
		for d: Vector3 in OldTownBurst.KEEP_OFF:
			ko.add_soft_disc(station_at.x + d.x, station_at.z + d.y, d.z)
	return true


func _build_landmark() -> void:
	_build_station()


func _on_source(broken_now: bool) -> void:
	if burst_main:
		burst_main.set_broken(broken_now)


static func _v3(p: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


# --- The pumping station -------------------------------------------------------------------------

## Pump house No. 1: a red-brick hall with a gable roof and tall works windows, a brick standpipe
## tower with a riveted tank and a tiled cap, two teal mains out of the front wall, and the burst
## one fountaining over the forecourt.
func _build_station() -> void:
	var g := BuildingDetail.Geo.new()
	var hall: Rect2 = landmark_rects[0]
	var tower: Rect2 = landmark_rects[1]
	var hc: Vector2 = hall.get_center()
	var eaves: float = 12.0
	var ridge: float = 16.2
	var south := Vector3(0, 0, 1)
	g.uv = BuildingDetail._bay_uv(hall, 77)
	# Stone plinth, brick walls with works windows on the long sides, brick piers, a stone cornice.
	g.mat(BuildingDetail.K_COPING, STONE.darkened(0.12))
	g.abox(_v3(hall.position - Vector2(0.25, 0.25), 0.0), Vector3(hall.size.x + 0.5, 1.1, hall.size.y + 0.5))
	g.mat(BuildingDetail.K_FACADE, BRICK, T_RED, BuildingDetail.F_RIBBON)
	g.abox(_v3(hall.position, 0.0), Vector3(hall.size.x, eaves, hall.size.y), -2)
	g.mat(BuildingDetail.K_PLAIN, BRICK.darkened(0.12), T_RED)
	var piers: int = 6
	for i: int in piers + 1:
		var x: float = hall.position.x + hall.size.x * float(i) / float(piers)
		for z: float in [hall.position.y - 0.3, hall.end.y - 0.3]:
			g.abox(Vector3(x - 0.45, 0.0, z), Vector3(0.9, eaves, 0.6))
	g.mat(BuildingDetail.K_COPING, STONE)
	g.abox(_v3(hall.position - Vector2(0.45, 0.45), eaves - 0.5), Vector3(hall.size.x + 0.9, 0.55, hall.size.y + 0.9))
	g.abox(_v3(hall.position - Vector2(0.2, 0.2), 4.3), Vector3(hall.size.x + 0.4, 0.3, hall.size.y + 0.4))
	# The gable roof: two slopes of tile-red roofing, brick gable ends, a raised lantern on the ridge.
	g.mat(BuildingDetail.K_ROOF, Color(0.82, 0.34, 0.2), 0, BuildingDetail.F_ROOF_SEAMS_X)
	var x0: float = hall.position.x - 0.5
	var x1: float = hall.end.x + 0.5
	var z0: float = hall.position.y - 0.6
	var z1: float = hall.end.y + 0.6
	var zm: float = hc.y
	for sgn: float in [-1.0, 1.0]:
		var ze: float = z0 if sgn < 0.0 else z1
		var nrm := Vector3(0, absf(ze - zm), sgn * (ridge - eaves)).normalized()
		g.quad(Vector3(x0, eaves, ze), Vector3(x1, eaves, ze), Vector3(x1, ridge, zm), Vector3(x0, ridge, zm), nrm)
	g.mat(BuildingDetail.K_PLAIN, BRICK, T_RED)
	for xe: float in [hall.position.x, hall.end.x]:
		var out := Vector3(-1.0 if xe < hc.x else 1.0, 0, 0)
		g.tri(Vector3(xe, eaves, hall.position.y), Vector3(xe, eaves, hall.end.y), Vector3(xe, ridge - 0.15, zm), out)
	g.mat(BuildingDetail.K_METAL, PIPE_TEAL.darkened(0.1), 0, BuildingDetail.F_RUST)
	g.abox(Vector3(hc.x - 4.0, ridge - 0.5, zm - 0.9), Vector3(8.0, 1.3, 1.8))
	g.mat(BuildingDetail.K_ROOF, Color(0.82, 0.34, 0.2))
	g.abox(Vector3(hc.x - 4.3, ridge + 0.8, zm - 1.2), Vector3(8.6, 0.12, 2.4))
	# The big sliding door on the street front, and the painted sign board over it.
	var fz: float = hall.end.y
	g.mat(BuildingDetail.K_METAL, PIPE_TEAL, 0, BuildingDetail.F_RUST)
	g.abox(Vector3(hc.x - 5.6, 1.1, fz + 0.02), Vector3(4.2, 4.6, 0.16))
	g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
	g.abox(Vector3(hc.x - 6.0, 5.7, fz + 0.02), Vector3(8.6, 0.14, 0.22))
	g.mat(BuildingDetail.K_FLAT, Color(0.06, 0.36, 0.4))
	g.abox(Vector3(hc.x - 6.2, 8.6, fz + 0.3), Vector3(12.4, 1.9, 0.14))
	g.mat(BuildingDetail.K_FLAT, Color(0.93, 0.68, 0.1))
	g.abox(Vector3(hc.x - 6.3, 8.5, fz + 0.28), Vector3(12.6, 0.12, 0.2))
	g.abox(Vector3(hc.x - 6.3, 10.48, fz + 0.28), Vector3(12.6, 0.12, 0.2))
	_sign = Label3D.new()
	_sign.name = "StationSign"
	_sign.text = "OLD TOWN WATERWORKS"
	_sign.font_size = 160
	_sign.pixel_size = 0.0062
	_sign.outline_size = 0
	_sign.double_sided = false
	_sign.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	_sign.position = Vector3(hc.x, 9.55, fz + 0.46)
	_sign.visibility_range_end = 260.0
	add_child(_sign)
	# The standpipe tower: a brick shaft with stone bands, the tank, a tiled cone and a finial.
	var tc: Vector2 = tower.get_center()
	var shaft: float = 25.0
	g.uv = BuildingDetail._bay_uv(tower, 78)
	g.mat(BuildingDetail.K_PLAIN, BRICK.darkened(0.05), T_RED)
	g.abox(_v3(tower.position, 0.0), Vector3(tower.size.x, shaft, tower.size.y), -2)
	g.mat(BuildingDetail.K_COPING, STONE)
	for y: float in [1.0, 8.0, 16.0, shaft - 0.4]:
		g.abox(_v3(tower.position - Vector2(0.22, 0.22), y - 0.3), Vector3(tower.size.x + 0.44, 0.6 if y > 2.0 else 1.0, tower.size.y + 0.44))
	g.mat(BuildingDetail.K_DARK, Color(0.04, 0.045, 0.05))
	for y2: float in [10.5, 19.0]:
		g.abox(Vector3(tc.x - 0.5, y2, tower.end.y - 0.02), Vector3(1.0, 2.6, 0.06))
	g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
	g.cyl(Transform3D(Basis.IDENTITY, _v3(tc, shaft + 0.2)), 4.0, 3.2, 0.4, 18)
	g.mat(BuildingDetail.K_METAL, Color(0.9, 0.84, 0.68), 0, BuildingDetail.F_HOOPS | BuildingDetail.F_RUST)
	g.cyl(Transform3D(Basis.IDENTITY, _v3(tc, shaft + 3.2)), 3.7, 3.7, 5.6, 20)
	g.mat(BuildingDetail.K_METAL, PIPE_TEAL)
	g.cyl(Transform3D(Basis.IDENTITY, _v3(tc, shaft + 2.2)), 3.76, 3.76, 1.0, 20, false)
	g.mat(BuildingDetail.K_FLAT, Color(0.82, 0.34, 0.2))
	g.cyl(Transform3D(Basis.IDENTITY, _v3(tc, shaft + 7.4)), 0.25, 4.1, 2.8, 20)
	g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
	g.cyl(Transform3D(Basis.IDENTITY, _v3(tc, shaft + 9.6)), 0.05, 0.08, 1.8, 6)
	# A ladder up the tower's east face.
	for e: float in [-0.25, 0.25]:
		g.rod(Vector3(tower.end.x + 0.12, 0.3, tc.y + e), Vector3(tower.end.x + 0.12, shaft, tc.y + e), 0.03)
	for k: int in 50:
		g.rod(Vector3(tower.end.x + 0.12, 0.6 + k * 0.48, tc.y - 0.25), Vector3(tower.end.x + 0.12, 0.6 + k * 0.48, tc.y + 0.25), 0.02)
	# The two mains: out of the front wall, over concrete saddles, down into the street. The east
	# one burst at its last joint.
	var burst: Vector3 = station_at
	var pr: float = 0.55
	for pi: int in 2:
		var px: float = burst.x if pi == 1 else burst.x - 4.4
		var zend: float = burst.z - (0.9 if pi == 1 else -0.6)
		g.mat(BuildingDetail.K_METAL, PIPE_TEAL, 0, BuildingDetail.F_RUST)
		g.cyl(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(px, 1.5, (fz + zend) * 0.5)), pr, pr, zend - fz, 14, false)
		g.mat(BuildingDetail.K_METAL, Color(0.78, 0.8, 0.8))
		for zf: float in [fz + 0.2, lerpf(fz, zend, 0.5), zend - 0.1]:
			g.cyl(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(px, 1.5, zf)), pr + 0.14, pr + 0.14, 0.16, 14)
		g.mat(BuildingDetail.K_COPING, STONE.darkened(0.2))
		for zs: float in [lerpf(fz, zend, 0.25), lerpf(fz, zend, 0.78)]:
			g.abox(Vector3(px - 0.8, 0.0, zs - 0.3), Vector3(1.6, 1.0, 0.6))
		# A red valve wheel on a stem.
		g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
		g.cyl(Transform3D(Basis.IDENTITY, Vector3(px, 2.5, fz + 1.6)), 0.06, 0.06, 1.0, 6)
		g.mat(BuildingDetail.K_FLAT, Color(0.84, 0.14, 0.1))
		g.cyl(Transform3D(Basis.IDENTITY, Vector3(px, 3.0, fz + 1.6)), 0.5, 0.5, 0.08, 12)
		if pi == 0:
			# The sound main drops into the ground through an elbow.
			g.mat(BuildingDetail.K_METAL, PIPE_TEAL, 0, BuildingDetail.F_RUST)
			g.cyl(Transform3D(Basis.IDENTITY, Vector3(px, 0.75, zend + pr * 0.2)), pr, pr, 1.5, 14)
		PropColliders.add_box(_body, Transform3D(Basis.IDENTITY, Vector3(px, 1.05, (fz + zend) * 0.5)), Vector3(1.4, 2.1, zend - fz))
		_rects.append(Rect2(px - 0.9, fz, 1.8, zend - fz + 0.4))
	# The torn end of the burst main: a split flange and a peeled-back plate.
	g.mat(BuildingDetail.K_METAL, PIPE_TEAL.darkened(0.2), 0, BuildingDetail.F_RUST)
	g.box(Transform3D(Basis.from_euler(Vector3(0.9, 0.3, 0.2)), burst + Vector3(0.5, 1.7, -0.5)), Vector3(0.9, 0.06, 1.1))
	g.box(Transform3D(Basis.from_euler(Vector3(-0.5, -0.4, 0.7)), burst + Vector3(-0.6, 1.3, -0.3)), Vector3(0.8, 0.06, 0.9))
	# Striped barriers round the hole and a warning beacon on a post.
	for bi: int in 5:
		var a: float = -0.5 + bi * 1.05
		var bp: Vector3 = burst + Vector3(sin(a) * 4.6, 0.0, cos(a) * 3.6 + 0.6)
		var bx := Transform3D(Basis(Vector3.UP, a + (0.25 if bi % 2 == 0 else -0.2)), bp)
		g.mat(BuildingDetail.K_FLAT, Color(0.96, 0.62, 0.06), 0, BuildingDetail.F_STRIPES)
		g.box(bx * Transform3D(Basis.IDENTITY, Vector3(0, 0.85, 0)), Vector3(2.0, 0.26, 0.06))
		g.box(bx * Transform3D(Basis.IDENTITY, Vector3(0, 0.45, 0)), Vector3(2.0, 0.16, 0.06))
		g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
		for sx: float in [-0.9, 0.9]:
			g.box(bx * Transform3D(Basis.IDENTITY, Vector3(sx, 0.5, 0)), Vector3(0.07, 1.0, 0.07))
			g.box(bx * Transform3D(Basis.IDENTITY, Vector3(sx, 0.03, 0)), Vector3(0.1, 0.06, 0.7))
		PropColliders.add_box(_body, bx * Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)), Vector3(2.0, 1.0, 0.25))
	var post: Vector3 = burst + Vector3(-2.2, 0.0, 1.6)
	g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
	g.cyl(Transform3D(Basis.IDENTITY, post + Vector3(0, 1.6, 0)), 0.05, 0.07, 3.2, 8)
	var mi := MeshInstance3D.new()
	mi.name = "Station"
	mi.mesh = g.mesh()
	mi.material_override = material(false)
	mi.set_meta("no_collide", true)
	add_child(mi)
	stats["station_tris"] = g.tri_count()
	PropColliders.add_box(_body, Transform3D(Basis.IDENTITY, _v3(hc, eaves * 0.5)), Vector3(hall.size.x + 0.6, eaves, hall.size.y + 0.6))
	PropColliders.add_box(_body, Transform3D(Basis.IDENTITY, _v3(tc, shaft * 0.5)), Vector3(tower.size.x + 0.4, shaft, tower.size.y + 0.4))
	# The beacon lamp (its material flashes while the main is broken).
	_beacon = StandardMaterial3D.new()
	_beacon.albedo_color = Color(1.0, 0.55, 0.1)
	_beacon.emission_enabled = true
	_beacon.emission = _beacon.albedo_color
	var lamp := MeshInstance3D.new()
	lamp.name = "Beacon"
	lamp.mesh = ProcMesh.sphere(0.16, 10, 6)
	lamp.material_override = _beacon
	lamp.position = post + Vector3(0, 3.3, 0)
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lamp)
	burst_main = OldTownBurst.new()
	burst_main.name = "Burst"
	burst_main.position = burst
	add_child(burst_main)
	burst_main.build(material(false))
