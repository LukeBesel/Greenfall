extends VerdanceCity
## Lowmeadow (site 9), the garden suburb: pastel houses under red and green pitched roofs, white
## picket fences and letter boxes down the main street (the look is data: cities.json
## "lowmeadow"). This script is its source landmark: the treatment works across three blocks at
## the head of the open lot. Two round settling tanks with scraper bridges, a butter-yellow
## digester with a flare stack, a mint control house under a red roof, three pastel dosing tanks
## and a cracked outfall pipe whose spill stains the ground down toward the town in vivid violet
## and lime: poisoned soil that still reads as colour, not mud.
## The tanks stand 4.8 m out of the ground, so their mint walls and turning scraper bridges show
## over the wrecks on the lot.
## Running: lime sludge spills over the tanks' rims toward the town and gushes from the cracked
## outfall, fumes rise, the stain runs down the lot. Shut down: the tanks hold clear blue water
## and nothing spills, the stain is gone, the outfall runs clear and the works' lamps come on.
## The scraper bridges turn in both states (quicker once the works runs clean).
## Built in the landmark's frame: x to the right seen from the yard, z toward the yard.

const MINT := Color(0.62, 0.9, 0.78)
const BUTTER := Color(1.0, 0.9, 0.56)
const CORAL := Color(1.0, 0.6, 0.52)
const SKY := Color(0.56, 0.8, 1.0)
const LILAC := Color(0.82, 0.72, 0.98)
const WHITE := Color(0.97, 0.96, 0.92)
const ROOF_RED := Color(0.8, 0.22, 0.16)
const PIPE_BLUE := Color(0.16, 0.5, 0.86)
const TOXIC := Color(0.74, 0.92, 0.1)
const CLEAR := Color(0.18, 0.56, 0.9)
const STAIN_A := Color(0.62, 0.14, 0.78, 0.86)
const STAIN_B := Color(0.78, 0.94, 0.12, 0.8)
const FUME := Color(0.8, 0.96, 0.3, 0.5)
const FUME_END := Color(0.6, 0.9, 0.74, 0.0)
const FLARE_FUME := Color(0.9, 0.3, 0.8, 0.7)
const FLARE_FUME_END := Color(1.0, 0.7, 0.5, 0.0)
const TANK_R: float = 9.0
const TANK_WALL: float = 4.8
const SPILL := Color(0.74, 0.92, 0.1, 0.95)
const SPILL_END := Color(0.62, 0.14, 0.78, 0.7)
const RUN_CLEAR := Color(0.3, 0.7, 1.0, 0.9)
const RUN_CLEAR_END := Color(0.8, 0.95, 1.0, 0.5)
const SPILL_AT: Array[float] = [-0.7, 0.0, 0.7]   # round the tank's rim, radians from the side facing the yard
const BRIDGE_RATE: Vector2 = Vector2(0.12, 0.3)   # radians a second: fouled, clean

var _bridges: Array[Node3D] = []
const TANKS: Array[Vector2] = [Vector2(0.0, -1.0), Vector2(36.0, -1.0)]
const EGG_AT := Vector2(-39.6, -4.4)
const EGG_R: float = 4.8
const HOUSE := Rect2(-33.4, -8.4, 7.4, 7.0)
const DOSING: Array[float] = [-44.0, -40.2, -36.4]
const OUTFALL_X: float = 36.0
const FLARE_H: float = 24.0
const LIFT_AT := Vector2(-29.6, 5.6)   # the header tower: what shows over the roofs
const LIFT_H: float = 30.0


func _footprint() -> Array[Rect2]:
	var out: Array[Rect2] = [HOUSE, Rect2(EGG_AT.x - EGG_R - 0.2, EGG_AT.y - EGG_R - 0.2, EGG_R * 2.0 + 0.4, EGG_R * 2.0 + 0.4),
		Rect2(-45.8, 3.8, 11.2, 3.4), Rect2(-44.4, 9.9, 16.8, 0.6), Rect2(LIFT_AT.x - 2.0, LIFT_AT.y - 2.0, 4.0, 4.0)]
	for t: Vector2 in TANKS:
		out.append(Rect2(t.x - TANK_R - 0.5, t.y - TANK_R - 0.5, TANK_R * 2.0 + 1.0, TANK_R * 2.0 + 1.0))
	return out


## The spill's run from the outfall down the lot stays free of junk, so the stain shows.
func _clear_ground() -> Array[Rect2]:
	return [Rect2(OUTFALL_X - 9.0, 11.0, 13.0, 24.0)]


func _build_landmark() -> void:
	var g := BuildingDetail.Geo.new()
	var lamps: Array[Vector3] = []
	for t: Vector2 in TANKS:
		_tank(g, t)
		_bridge(t)
		for a: float in SPILL_AT:
			var rim := Vector3(t.x + sin(a) * (TANK_R + 0.6), TANK_WALL + 0.3, t.y + cos(a) * (TANK_R + 0.6))
			var run: CPUParticles3D = CityKit.stream("Spill", rim, SPILL, SPILL_END, 26, TANK_WALL, 2.2, 1.0)
			run.rotation.y = a
			place(run, STATE_BROKEN)
		lamps.append(Vector3(t.x, TANK_WALL + 3.3, t.y))
		_liquid(t, true)
		_liquid(t, false)
	_digester(g)
	_house(g)
	_outfall(g)
	place_mesh("TreatmentWorks", g)
	for i: int in _footprint().size():
		var r: Rect2 = _footprint()[i]
		var h: float = [6.5, 16.0, 5.2, 4.2, 20.0, TANK_WALL, TANK_WALL][i]
		add_landmark_solid(Vector3(r.get_center().x, h * 0.5, r.get_center().y), Vector3(r.size.x, h, r.size.y))
	place_sign(Transform3D(Basis.IDENTITY, Vector3(-36.0, 3.4, 10.32)), 0.58)
	place_beacon(Vector3(HOUSE.end.x - 0.5, 7.6, HOUSE.end.y - 0.5), 0.2)
	var flare := Vector3(EGG_AT.x + 3.0, FLARE_H, EGG_AT.y + 3.6)
	place(CityKit.smoke("FlareFume", flare, FLARE_FUME, FLARE_FUME_END, 22, 8.0, 30.0, 1.5, 12.0, Vector3(1.0, 0.0, 0.4)), STATE_BROKEN)
	# The spill: out of the cracked outfall, across the street and down the lot toward the town.
	var stain: MeshInstance3D = CityKit.film("Stain", Vector2(11.0, 17.0), STAIN_A, STAIN_B, 0.25, false, 0.22)
	stain.position = Vector3(OUTFALL_X - 3.0, 0.16, 24.0)
	place(stain, STATE_BROKEN)
	var seep: MeshInstance3D = CityKit.film("Seep", Vector2(13.0, 6.0), STAIN_A, STAIN_B, 0.25, false, 0.3)
	seep.position = Vector3(2.0, 0.16, 13.0)
	place(seep, STATE_BROKEN)
	var mouth := Vector3(OUTFALL_X, 1.5, 10.6)
	place(CityKit.stream("OutfallSpill", mouth, SPILL, SPILL_END, 30, 1.5, 1.3, 0.8), STATE_BROKEN)
	place(CityKit.stream("OutfallRun", mouth, RUN_CLEAR, RUN_CLEAR_END, 30, 1.5, 1.0, 0.6), STATE_SHUT_DOWN)
	var clean: MeshInstance3D = CityKit.film("ClearRun", Vector2(3.4, 4.6), Color(CLEAR, 0.75), Color(0.6, 0.86, 1.0, 0.55), 0.0, false, 0.5)
	clean.position = Vector3(OUTFALL_X, 0.16, 13.6)
	place(clean, STATE_SHUT_DOWN)
	lamps.append_array([Vector3(HOUSE.get_center().x, 4.6, HOUSE.end.y + 0.3), Vector3(-43.0, 5.0, 10.3), Vector3(-36.0, 5.0, 10.3), Vector3(-29.0, 5.0, 10.3),
		Vector3(EGG_AT.x, 16.4, EGG_AT.y), Vector3(LIFT_AT.x, LIFT_H + 8.8, LIFT_AT.y)])
	place_lamps("WorksLamps", lamps, 0.3)


func _animate(now: float, broken_now: bool) -> void:
	var turn: float = now * (BRIDGE_RATE.x if broken_now else BRIDGE_RATE.y)
	for i: int in _bridges.size():
		move_part(_bridges[i], turn + float(i) * 1.3)


## A tank's scraper bridge, built round the tank's middle at rim height so it can turn: a steel
## deck across the tank with blue handrails and the orange drive in the middle.
func _bridge(t: Vector2) -> void:
	var g := BuildingDetail.Geo.new()
	g.mat(BuildingDetail.K_METAL, Color(0.74, 0.76, 0.78))
	g.abox(Vector3(-TANK_R - 0.4, 0.5, -0.7), Vector3(TANK_R * 2.0 + 0.8, 0.16, 1.4))
	g.mat(BuildingDetail.K_METAL, PIPE_BLUE)
	for sz: float in [-0.7, 0.7]:
		g.rod(Vector3(-TANK_R - 0.4, 1.6, sz), Vector3(TANK_R + 0.4, 1.6, sz), 0.06)
		for k: int in 9:
			var x: float = -TANK_R + float(k) * TANK_R * 0.25
			g.rod(Vector3(x, 0.6, sz), Vector3(x, 1.6, sz), 0.04)
	g.mat(BuildingDetail.K_METAL, Color(0.95, 0.46, 0.1), 0, BuildingDetail.F_RUST)
	g.cyl(Transform3D(Basis.IDENTITY, Vector3(0, 1.5, 0)), 0.9, 1.0, 1.8, 12)
	g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
	g.cyl(Transform3D(Basis.IDENTITY, Vector3(0, 2.8, 0)), 0.06, 0.06, 0.9, 6)
	_bridges.append(place_part("Bridge%d" % int(t.x), g, Vector3(t.x, TANK_WALL, t.y)))


## A settling tank: a mint concrete ring with a white rim, a coral band and three dark
## buttresses' worth of height (the scraper bridge is its own turning part, _bridge).
func _tank(g: BuildingDetail.Geo, t: Vector2) -> void:
	var c := Vector3(t.x, 0.0, t.y)
	g.mat(BuildingDetail.K_PLAIN, MINT, BuildingDetail.T_CONCRETE)
	g.cyl(Transform3D(Basis.IDENTITY, c + Vector3(0, TANK_WALL * 0.5, 0)), TANK_R + 0.4, TANK_R + 0.5, TANK_WALL, 28, false)
	g.mat(BuildingDetail.K_COPING, WHITE)
	g.cyl(Transform3D(Basis.IDENTITY, c + Vector3(0, TANK_WALL + 0.1, 0)), TANK_R + 0.55, TANK_R + 0.55, 0.2, 28, false)
	g.mat(BuildingDetail.K_FLAT, CORAL)
	g.cyl(Transform3D(Basis.IDENTITY, c + Vector3(0, 0.5, 0)), TANK_R + 0.52, TANK_R + 0.52, 0.5, 28, false)
	# The rim's top face: a flat ring.
	g.mat(BuildingDetail.K_COPING, WHITE)
	for i: int in 28:
		var a0: float = TAU * float(i) / 28.0
		var a1: float = TAU * float(i + 1) / 28.0
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var y := Vector3(0, TANK_WALL + 0.2, 0)
		g.quad(c + d0 * (TANK_R - 0.3) + y, c + d1 * (TANK_R - 0.3) + y, c + d1 * (TANK_R + 0.55) + y, c + d0 * (TANK_R + 0.55) + y, Vector3.UP)
	g.mat(BuildingDetail.K_FLAT, SKY)
	g.cyl(Transform3D(Basis.IDENTITY, c + Vector3(0, TANK_WALL - 0.9, 0)), TANK_R + 0.52, TANK_R + 0.52, 0.5, 28, false)


## What a tank holds: lime sludge under a violet film while the works runs, clear blue water after.
func _liquid(t: Vector2, running: bool) -> void:
	var g := BuildingDetail.Geo.new()
	g.mat(BuildingDetail.K_FLAT, TOXIC if running else CLEAR)
	g.cyl(Transform3D(Basis.IDENTITY, Vector3(t.x, TANK_WALL - 0.5, t.y)), TANK_R - 0.3, TANK_R - 0.3, 0.1, 28)
	place_mesh(("Sludge%d" if running else "Water%d") % int(t.x), g, STATE_BROKEN if running else STATE_SHUT_DOWN)
	if running:
		var film: MeshInstance3D = CityKit.film("Scum%d" % int(t.x), Vector2(TANK_R - 0.4, TANK_R - 0.4), STAIN_A, Color(0.9, 0.3, 0.7, 0.5), 0.3, false, 0.4)
		film.position = Vector3(t.x, TANK_WALL - 0.42, t.y)
		place(film, STATE_BROKEN)
		place(CityKit.smoke("Fume%d" % int(t.x), Vector3(t.x, TANK_WALL, t.y), FUME, FUME_END, 12, 6.0, 13.0, 3.0, 9.0, Vector3(0.6, 0.0, 0.2)), STATE_BROKEN)


## The digester: a butter-yellow egg on a skirt with a coral band and a white cap, a platform
## round its shoulder, and the thin flare stack beside it.
func _digester(g: BuildingDetail.Geo) -> void:
	var c := Vector3(EGG_AT.x, 0.0, EGG_AT.y)
	g.mat(BuildingDetail.K_PLAIN, WHITE.darkened(0.1), BuildingDetail.T_CONCRETE)
	g.cyl(Transform3D(Basis.IDENTITY, c + Vector3(0, 1.0, 0)), EGG_R * 0.7, EGG_R * 0.8, 2.0, 18, false)
	var rings: int = 9
	for i: int in rings:
		var a0: float = -1.1 + 2.5 * float(i) / float(rings)
		var a1: float = -1.1 + 2.5 * float(i + 1) / float(rings)
		g.mat(BuildingDetail.K_METAL, CORAL if i == 4 else (WHITE if i == rings - 1 else BUTTER), 0, BuildingDetail.F_HOOPS)
		CityKit.ball_ring(g, c + Vector3(0, 8.4, 0), EGG_R, 7.2, a0, a1, 18, i == rings - 1)
	g.mat(BuildingDetail.K_METAL, PIPE_BLUE)
	g.cyl(Transform3D(Basis.IDENTITY, c + Vector3(0, 11.4, 0)), EGG_R + 0.7, EGG_R + 0.7, 0.12, 18)
	g.cyl(Transform3D(Basis.IDENTITY, c + Vector3(0, 12.3, 0)), EGG_R + 0.7, EGG_R + 0.7, 0.06, 18, false)
	var flare: Vector3 = c + Vector3(3.0, 0.0, 3.6)
	g.mat(BuildingDetail.K_METAL, CORAL, 0, BuildingDetail.F_RUST)
	g.cyl(Transform3D(Basis.IDENTITY, flare + Vector3(0, FLARE_H * 0.5, 0)), 0.16, 0.24, FLARE_H, 8)
	g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
	g.cyl(Transform3D(Basis.IDENTITY, flare + Vector3(0, FLARE_H, 0)), 0.34, 0.2, 0.7, 8)
	# The header tower: a coral-and-white banded shaft with a mint ball tank and a red cap.
	var lift := Vector3(LIFT_AT.x, 0.0, LIFT_AT.y)
	CityKit.banded(g, lift, 1.7, 1.4, LIFT_H, 8, CORAL, WHITE, 14)
	for i3: int in 6:
		var b0: float = -1.2 + 2.6 * float(i3) / 6.0
		var b1: float = -1.2 + 2.6 * float(i3 + 1) / 6.0
		g.mat(BuildingDetail.K_METAL, SKY if i3 == 3 else MINT, 0, BuildingDetail.F_HOOPS)
		CityKit.ball_ring(g, lift + Vector3(0, LIFT_H + 3.4, 0), 4.0, 3.8, b0, b1, 16)
	g.mat(BuildingDetail.K_ROOF, ROOF_RED)
	g.cyl(Transform3D(Basis.IDENTITY, lift + Vector3(0, LIFT_H + 7.6, 0)), 0.2, 1.3, 1.6, 16)
	# The dosing tanks in a row along the front.
	var paints: Array[Color] = [CORAL, SKY, LILAC]
	for i2: int in DOSING.size():
		var d := Vector3(DOSING[i2], 0.0, 5.5)
		g.mat(BuildingDetail.K_METAL, paints[i2], 0, BuildingDetail.F_HOOPS)
		g.cyl(Transform3D(Basis.IDENTITY, d + Vector3(0, 2.6, 0)), 1.5, 1.5, 4.6, 14)
		g.cyl(Transform3D(Basis.IDENTITY, d + Vector3(0, 5.1, 0)), 0.3, 1.5, 0.5, 14)
		g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
		for a: float in [0.6, 2.2, 3.8, 5.4]:
			g.rod(d + Vector3(cos(a) * 1.3, 0, sin(a) * 1.3), d + Vector3(cos(a) * 1.3, 0.4, sin(a) * 1.3), 0.08)
	g.mat(BuildingDetail.K_METAL, PIPE_BLUE)
	g.rod(Vector3(DOSING[0], 1.0, 5.5), Vector3(DOSING[2] + 3.0, 1.0, 5.5), 0.14)


## The control house (mint render, a red pitched roof, a white door and windows) and the works'
## name board on posts along the block's front.
func _house(g: BuildingDetail.Geo) -> void:
	g.uv = BuildingDetail._bay_uv(HOUSE, 51)
	g.mat(BuildingDetail.K_FACADE, MINT, BuildingDetail.T_CONCRETE)
	g.abox(Vector3(HOUSE.position.x, 0.0, HOUSE.position.y), Vector3(HOUSE.size.x, 4.4, HOUSE.size.y), -2)
	var x0: float = HOUSE.position.x - 0.5
	var x1: float = HOUSE.end.x + 0.5
	var zc: float = HOUSE.get_center().y
	g.mat(BuildingDetail.K_ROOF, ROOF_RED, 0, BuildingDetail.F_ROOF_SEAMS_X)
	for sgn: float in [-1.0, 1.0]:
		var ze: float = zc + sgn * (HOUSE.size.y * 0.5 + 0.5)
		g.quad(Vector3(x0, 4.3, ze), Vector3(x1, 4.3, ze), Vector3(x1, 6.5, zc), Vector3(x0, 6.5, zc), Vector3(0, 0.85, sgn * 0.5).normalized())
	g.mat(BuildingDetail.K_PLAIN, MINT.darkened(0.06), BuildingDetail.T_CONCRETE)
	for xe: float in [HOUSE.position.x, HOUSE.end.x]:
		g.tri(Vector3(xe, 4.4, HOUSE.position.y), Vector3(xe, 4.4, HOUSE.end.y), Vector3(xe, 6.4, zc), Vector3(-1.0 if xe < HOUSE.get_center().x else 1.0, 0, 0))
	g.mat(BuildingDetail.K_FLAT, WHITE)
	g.abox(Vector3(HOUSE.get_center().x - 0.6, 0.0, HOUSE.end.y), Vector3(1.2, 2.3, 0.08))
	g.mat(BuildingDetail.K_FLAT, PIPE_BLUE.darkened(0.2))
	g.abox(Vector3(-44.4, 2.6, 10.1), Vector3(16.8, 1.6, 0.14))
	g.mat(BuildingDetail.K_FLAT, WHITE)
	g.abox(Vector3(-44.5, 2.5, 10.08), Vector3(17.0, 0.1, 0.2))
	g.abox(Vector3(-44.5, 4.2, 10.08), Vector3(17.0, 0.1, 0.2))
	for px: float in [-44.0, -36.0, -28.0]:
		g.abox(Vector3(px - 0.1, 0.0, 10.0), Vector3(0.2, 4.4, 0.2))


## The outfall: a blue main out of the east tank's front wall on two saddles, split open at its
## end, with a red valve wheel.
func _outfall(g: BuildingDetail.Geo) -> void:
	var z0: float = TANKS[1].y + TANK_R + 0.3
	var z1: float = 10.4
	g.mat(BuildingDetail.K_METAL, PIPE_BLUE, 0, BuildingDetail.F_RUST)
	g.cyl(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(OUTFALL_X, 1.0, (z0 + z1) * 0.5)), 0.6, 0.6, z1 - z0, 14, false)
	g.mat(BuildingDetail.K_METAL, Color(0.78, 0.8, 0.8))
	g.cyl(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(OUTFALL_X, 1.0, z0 + 0.2)), 0.76, 0.76, 0.18, 14)
	g.mat(BuildingDetail.K_COPING, WHITE.darkened(0.2))
	g.abox(Vector3(OUTFALL_X - 0.8, 0.0, z1 - 0.7), Vector3(1.6, 0.5, 0.6))
	g.mat(BuildingDetail.K_METAL, PIPE_BLUE.darkened(0.25), 0, BuildingDetail.F_RUST)
	g.box(Transform3D(Basis.from_euler(Vector3(0.8, 0.3, 0.2)), Vector3(OUTFALL_X + 0.5, 1.3, z1 + 0.3)), Vector3(0.9, 0.06, 1.0))
	g.box(Transform3D(Basis.from_euler(Vector3(-0.5, -0.4, 0.7)), Vector3(OUTFALL_X - 0.6, 0.8, z1 + 0.4)), Vector3(0.8, 0.06, 0.9))
	g.mat(BuildingDetail.K_FLAT, Color(0.86, 0.14, 0.1))
	g.cyl(Transform3D(Basis.IDENTITY, Vector3(OUTFALL_X, 1.9, z0 + 0.6)), 0.4, 0.4, 0.08, 12)
