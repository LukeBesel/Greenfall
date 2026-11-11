extends VerdanceCity
## Highreach (site 8), the downtown: glass-blue and white towers, hoardings on the roofs, magenta,
## cyan and yellow signs (the look is data: cities.json "highreach"). This script is its source
## landmark: the incinerator plant across three blocks at the head of the open lot. Three
## red-and-white stacks stand in the middle behind the waste bunker, pouring violet smog that
## spreads into a tinted layer over this district only; a tall sky-blue boiler hall feeds them
## through a silver flue duct on a pipe bridge, and a cyan tipping hall with three bay doors
## sends its yellow conveyor gallery over the street to the bunker.
## Shut down: the plumes stop, the layer lifts, the stack lights and the plant's lamps come on.
## Built in the landmark's frame: x to the right seen from the yard, z toward the yard.

const HALL_BLUE := Color(0.42, 0.68, 0.94)
const HALL_PALE := Color(0.9, 0.94, 0.98)
const CYAN := Color(0.06, 0.66, 0.8)
const MAGENTA := Color(0.9, 0.1, 0.54)
const YELLOW := Color(0.98, 0.82, 0.08)
const SILVER := Color(0.78, 0.8, 0.82)
const STACK_RED := Color(0.88, 0.14, 0.12)
const STACK_WHITE := Color(0.97, 0.96, 0.93)
const SMOG := Color(0.8, 0.4, 0.88, 0.85)
const SMOG_END := Color(1.0, 0.7, 0.52, 0.0)
const LAYER_WARM := Color(1.0, 0.74, 0.5, 0.3)
const LAYER_Y: float = 95.0
const LAYER_HALF: float = 420.0
const HALL := Rect2(-46.0, -9.0, 20.0, 16.0)
const HALL_H: float = 24.0
const TIP := Rect2(25.5, -9.0, 20.5, 17.0)
const TIP_H: float = 9.0
const BUNKER := Rect2(-10.0, 1.0, 20.0, 8.6)
const BUNKER_H: float = 10.0
## The stacks: x, z, height.
const STACKS: Array[Vector3] = [Vector3(-7.0, -5.0, 60.0), Vector3(0.0, -5.0, 72.0), Vector3(7.0, -5.0, 54.0)]
const DUCT_Y: float = 9.0
## Per district stage 0..5: how thick the smog layer is while the plant still runs.
const LAYER_BY_STAGE: Array[float] = [1.0, 1.0, 0.9, 0.75, 0.6, 0.45]

var _layer: MeshInstance3D


func _footprint() -> Array[Rect2]:
	var out: Array[Rect2] = [HALL, TIP, BUNKER, Rect2(-24.0, -9.2, 0.8, 8.4), Rect2(-12.7, -9.2, 0.8, 8.4)]
	for s: Vector3 in STACKS:
		out.append(Rect2(s.x - 2.7, s.y - 2.7, 5.4, 5.4))
	return out


func _build_landmark() -> void:
	var g := BuildingDetail.Geo.new()
	_halls(g)
	_ducts(g)
	var tops: Array[Vector3] = []
	for s: Vector3 in STACKS:
		var base := Vector3(s.x, 0.0, s.y)
		CityKit.banded(g, base, 2.3, 1.45, s.z, 11, STACK_RED, STACK_WHITE, 18)
		g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
		g.cyl(Transform3D(Basis.IDENTITY, base + Vector3(0, s.z * 0.62, 0)), 2.25, 2.3, 0.2, 18, false)
		tops.append(base + Vector3(1.5, s.z - 0.6, 0.0))
		tops.append(base + Vector3(-1.5, s.z - 0.6, 0.0))
		tops.append(base + Vector3(0.0, s.z * 0.62 + 0.3, 2.1))
		place(CityKit.smoke("Smog%d" % int(s.x), base + Vector3(0, s.z, 0), SMOG, SMOG_END, 44, 15.0, 95.0, 5.0, 36.0, Vector3(1.6, 0.0, 0.5)), STATE_BROKEN)
	place_mesh("Incinerator", g)
	for r: Rect2 in _footprint():
		var h: float = HALL_H if r == HALL else (TIP_H if r == TIP else (BUNKER_H if r == BUNKER else (DUCT_Y - 1.0 if r.size.x < 1.0 else 20.0)))
		add_landmark_solid(Vector3(r.get_center().x, h * 0.5, r.get_center().y), Vector3(r.size.x, h, r.size.y))
	place_sign(Transform3D(Basis.IDENTITY, Vector3(0.0, 7.4, BUNKER.end.y + 0.2)), 1.3)
	place_beacon(Vector3(HALL.end.x - 0.6, HALL_H + 1.4, HALL.end.y - 0.6), 0.3)
	place_lamps("StackLights", tops, 0.34, Color(1.0, 0.25, 0.2))
	var lamps: Array[Vector3] = []
	for x: float in [-8.0, -2.7, 2.7, 8.0]:
		lamps.append(Vector3(HALL.get_center().x + x, 14.6, HALL.end.y + 0.3))
		lamps.append(Vector3(x, BUNKER_H + 0.5, BUNKER.end.y - 0.3))
	for x2: float in [29.0, 35.8, 42.6]:
		lamps.append(Vector3(x2, TIP_H - 1.0, TIP.end.y + 0.3))
	place_lamps("PlantLamps", lamps, 0.3)
	var haze: Color = CityLook.colour(look.data.get("haze", [0.86, 0.56, 0.9, 0.42]))
	_layer = CityKit.film("SmogLayer", Vector2(LAYER_HALF, LAYER_HALF), haze, LAYER_WARM, 0.0, true, 0.012)
	_layer.position = Vector3(0.0, LAYER_Y, CityLayout.PITCH * 2.0)
	_layer.extra_cull_margin = LAYER_HALF
	place(_layer, STATE_BROKEN)


func _on_stage() -> void:
	if _layer:
		(_layer.material_override as ShaderMaterial).set_shader_parameter("strength", LAYER_BY_STAGE[stage])


## The boiler hall (sky-blue cladding in three bands with a yellow and a magenta stripe, a roof
## monitor and louvres) and the tipping hall (cyan, three striped bay doors, a ramp kerb), joined
## by the yellow conveyor gallery that climbs over the street.
func _halls(g: BuildingDetail.Geo) -> void:
	g.uv = BuildingDetail._bay_uv(HALL, 41)
	for band: Array in [[0.0, 8.0, HALL_BLUE.darkened(0.12)], [8.0, 16.6, HALL_BLUE], [16.6, HALL_H, HALL_PALE]]:
		g.mat(BuildingDetail.K_METAL, band[2] as Color)
		g.abox(Vector3(HALL.position.x, float(band[0]), HALL.position.y), Vector3(HALL.size.x, float(band[1]) - float(band[0]), HALL.size.y), -2)
	g.mat(BuildingDetail.K_FLAT, YELLOW)
	g.abox(Vector3(HALL.position.x - 0.06, 7.6, HALL.position.y - 0.06), Vector3(HALL.size.x + 0.12, 0.8, HALL.size.y + 0.12), -2)
	g.mat(BuildingDetail.K_FLAT, MAGENTA)
	g.abox(Vector3(HALL.position.x - 0.06, 16.2, HALL.position.y - 0.06), Vector3(HALL.size.x + 0.12, 0.8, HALL.size.y + 0.12), -2)
	g.mat(BuildingDetail.K_ROOF, Color(0.24, 0.38, 0.62), 0, BuildingDetail.F_ROOF_SEAMS_X)
	g.abox(Vector3(HALL.position.x - 0.3, HALL_H, HALL.position.y - 0.3), Vector3(HALL.size.x + 0.6, 0.3, HALL.size.y + 0.6))
	g.mat(BuildingDetail.K_METAL, HALL_PALE)
	g.abox(Vector3(HALL.get_center().x - 6.0, HALL_H + 0.3, -5.0), Vector3(12.0, 2.6, 6.0))
	g.mat(BuildingDetail.K_DARK, Color(0.06, 0.08, 0.12))
	for x: float in [-8.0, -2.7, 2.7, 8.0]:
		g.abox(Vector3(HALL.get_center().x + x - 1.5, 10.0, HALL.end.y), Vector3(3.0, 4.2, 0.08))
	g.mat(BuildingDetail.K_GLASS, Color(0.3, 0.52, 0.7))
	g.abox(Vector3(HALL.get_center().x - 8.6, 1.2, HALL.end.y), Vector3(17.2, 3.4, 0.08))
	# The waste bunker in front of the stacks: pale panels, a magenta band, the plant's name board.
	g.uv = BuildingDetail._bay_uv(BUNKER, 47)
	g.mat(BuildingDetail.K_METAL, HALL_PALE, 0, BuildingDetail.F_RUST)
	g.abox(Vector3(BUNKER.position.x, 0.0, BUNKER.position.y), Vector3(BUNKER.size.x, BUNKER_H, BUNKER.size.y), BuildingDetail.K_ROOF)
	g.mat(BuildingDetail.K_FLAT, YELLOW)
	g.abox(Vector3(BUNKER.position.x - 0.05, 4.6, BUNKER.position.y - 0.05), Vector3(BUNKER.size.x + 0.1, 0.7, BUNKER.size.y + 0.1), -2)
	g.mat(BuildingDetail.K_FLAT, Color(0.1, 0.12, 0.3))
	g.abox(Vector3(-9.6, 6.2, BUNKER.end.y + 0.04), Vector3(19.2, 2.4, 0.1))
	g.mat(BuildingDetail.K_FLAT, MAGENTA)
	g.abox(Vector3(-9.7, 8.7, BUNKER.end.y + 0.02), Vector3(19.4, 0.5, 0.14))
	g.mat(BuildingDetail.K_DARK, Color(0.06, 0.08, 0.12))
	for bx: float in [-6.0, 0.0, 6.0]:
		g.abox(Vector3(bx - 2.0, 0.0, BUNKER.end.y), Vector3(4.0, 3.6, 0.08))
	# The tipping hall.
	g.uv = BuildingDetail._bay_uv(TIP, 43)
	g.mat(BuildingDetail.K_METAL, CYAN, 0, BuildingDetail.F_RUST)
	g.abox(Vector3(TIP.position.x, 0.0, TIP.position.y), Vector3(TIP.size.x, TIP_H, TIP.size.y), -2)
	g.mat(BuildingDetail.K_ROOF, Color(0.1, 0.46, 0.56), 0, BuildingDetail.F_ROOF_SEAMS_X)
	g.abox(Vector3(TIP.position.x - 0.3, TIP_H, TIP.position.y - 0.3), Vector3(TIP.size.x + 0.6, 0.25, TIP.size.y + 0.6))
	for x2: float in [29.0, 35.8, 42.6]:
		g.mat(BuildingDetail.K_DARK, Color(0.05, 0.05, 0.07))
		g.abox(Vector3(x2 - 2.5, 0.0, TIP.end.y), Vector3(5.0, 6.0, 0.08))
		g.mat(BuildingDetail.K_FLAT, YELLOW, 0, BuildingDetail.F_STRIPES)
		g.abox(Vector3(x2 - 2.9, 0.0, TIP.end.y + 0.02), Vector3(0.4, 6.4, 0.12))
		g.abox(Vector3(x2 + 2.5, 0.0, TIP.end.y + 0.02), Vector3(0.4, 6.4, 0.12))
		g.abox(Vector3(x2 - 2.9, 6.0, TIP.end.y + 0.02), Vector3(5.8, 0.4, 0.12))
	g.mat(BuildingDetail.K_FLAT, MAGENTA)
	g.abox(Vector3(TIP.position.x - 0.05, TIP_H - 1.6, TIP.position.y - 0.05), Vector3(TIP.size.x + 0.1, 0.6, TIP.size.y + 0.1), -2)
	# The conveyor gallery: up from the tipping hall's roof, over the street, onto the bunker.
	var a := Vector3(TIP.position.x + 1.0, TIP_H + 0.6, 5.0)
	var b := Vector3(BUNKER.end.x - 2.0, BUNKER_H + 1.6, 5.0)
	g.mat(BuildingDetail.K_METAL, YELLOW, 0, BuildingDetail.F_RUST)
	g.rod(a, b, 1.5)
	g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
	var mid: Vector3 = a.lerp(b, 0.55)
	g.rod(Vector3(12.4, 0.0, 3.6), mid + Vector3(0, -1.4, -1.0), 0.2)
	g.rod(Vector3(12.4, 0.0, 6.4), mid + Vector3(0, -1.4, 1.0), 0.2)


## The flue ducts: two silver mains out of the hall's east wall, over the street on a pipe bridge,
## and a branch down into each stack's foot.
func _ducts(g: BuildingDetail.Geo) -> void:
	var x0: float = HALL.end.x
	var x1: float = STACKS[2].x
	g.mat(BuildingDetail.K_METAL, SILVER, 0, BuildingDetail.F_HOOPS)
	for dz: float in [-8.4, -1.6]:
		g.cyl(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3((x0 + x1) * 0.5, DUCT_Y, dz)), 1.1, 1.1, x1 - x0, 14, false)
	for s: Vector3 in STACKS:
		g.cyl(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(s.x, DUCT_Y, s.y)), 0.9, 0.9, 6.8, 12, false)
	g.mat(BuildingDetail.K_METAL, MAGENTA)
	for x: float in [-26.0, -20.0, -14.0]:
		g.cyl(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(x, DUCT_Y, -8.4)), 1.22, 1.22, 0.3, 14, false)
		g.cyl(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(x, DUCT_Y, -1.6)), 1.22, 1.22, 0.3, 14, false)
	g.mat(BuildingDetail.K_METAL, YELLOW, 0, BuildingDetail.F_RUST)
	for px: float in [-23.6, -12.3]:
		g.abox(Vector3(px - 0.3, 0.0, -9.0), Vector3(0.6, DUCT_Y - 1.1, 0.6))
		g.abox(Vector3(px - 0.3, 0.0, -1.6), Vector3(0.6, DUCT_Y - 1.1, 0.6))
		g.abox(Vector3(px - 0.4, DUCT_Y - 1.5, -9.2), Vector3(0.8, 0.4, 8.4))
