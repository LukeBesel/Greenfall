extends VerdanceCity
## Ironside (site 7), the scrapyard and works town: sheds in safety yellow, hazard orange and
## container blue under saw-tooth skylights, car stacks down the main street (the look is data:
## cities.json "scrapyard"). This script is its source landmark: the crusher yard across three
## blocks at the head of the open lot. A yellow gantry crane straddles the street with a crushed
## car on its hook, a blue press with a feed hopper and conveyor stands under it, a banded stack
## smokes over the boiler house, and a wall of crushed cubes in car paint closes the east side.
## Shut down: the stack stops smoking, the crane parks with its hook up, the floodlights come on.
## Built in the landmark's frame: x to the right seen from the yard, z toward the yard.

const YELLOW := Color(0.98, 0.76, 0.06)
const ORANGE := Color(0.95, 0.42, 0.06)
const PRESS_BLUE := Color(0.12, 0.38, 0.72)
const STACK_RED := Color(0.86, 0.14, 0.1)
const STACK_WHITE := Color(0.96, 0.95, 0.92)
const SMOKE := Color(0.98, 0.56, 0.2, 0.8)
const SMOKE_END := Color(0.72, 0.5, 0.66, 0.0)
const BEAM_Y: float = 24.0
const LEG_X: Array[float] = [7.0, 31.0]
const LEG_Z: float = 7.0
const STACK_AT := Vector3(-36.0, 0.0, -6.5)
const STACK_H: float = 44.0
const CUBE: float = 1.7


func _footprint() -> Array[Rect2]:
	return [Rect2(-8.5, -3.5, 8.5, 7.0), Rect2(6.2, -8.0, 1.6, 16.0), Rect2(30.2, -8.0, 1.6, 16.0), Rect2(-41.5, -3.0, 13.0, 10.0),
		Rect2(-38.0, -8.6, 4.0, 4.2), Rect2(34.5, -10.2, 10.6, 4.0), Rect2(-12.5, -1.2, 4.0, 2.4)]


func _build_landmark() -> void:
	var g := BuildingDetail.Geo.new()
	_gantry(g)
	_press(g)
	_boiler_house(g)
	_cube_wall(g)
	place_mesh("CrusherYard", g)
	for r: Rect2 in _footprint():
		add_landmark_solid(Vector3(r.get_center().x, 4.0, r.get_center().y), Vector3(r.size.x, 8.0, r.size.y))
	_crane_load(true)
	_crane_load(false)
	place(CityKit.smoke("StackSmoke", STACK_AT + Vector3(0, STACK_H, 0), SMOKE, SMOKE_END, 46, 11.0, 60.0, 4.0, 22.0, Vector3(1.4, 0.0, 0.5)), STATE_BROKEN)
	place_sign(Transform3D(Basis.IDENTITY, Vector3(-35.0, 6.4, 7.12)), 0.82)
	place_beacon(Vector3(-4.2, 9.4, 0.0), 0.22)
	var heads: Array[Vector3] = []
	for m: Vector3 in [Vector3(-9.6, 16.2, 9.6), Vector3(9.6, 16.2, -9.6), Vector3(44.0, 16.2, 9.6)]:
		heads.append(m)
	for x: float in [9.0, 15.0, 21.0, 27.0]:
		heads.append(Vector3(x, BEAM_Y - 1.5, 0.0))
	place_lamps("Floodlights", heads, 0.42)


## The goliath crane: two A-frame legs either side of the street, a box girder over it with a
## hazard-striped fascia, rails under the legs and three floodlight masts round the yard.
func _gantry(g: BuildingDetail.Geo) -> void:
	for lx: float in LEG_X:
		g.mat(BuildingDetail.K_METAL, YELLOW, 0, BuildingDetail.F_RUST)
		for sz: float in [-1.0, 1.0]:
			g.rod(Vector3(lx, 0.6, sz * LEG_Z), Vector3(lx, BEAM_Y - 1.2, sz * 1.2), 0.38)
		g.rod(Vector3(lx, 9.0, -4.6), Vector3(lx, 9.0, 4.6), 0.22)
		g.rod(Vector3(lx, 16.5, -2.8), Vector3(lx, 16.5, 2.8), 0.22)
		g.mat(BuildingDetail.K_FLAT, YELLOW, 0, BuildingDetail.F_STRIPES)
		g.abox(Vector3(lx - 0.7, 0.0, -LEG_Z - 1.0), Vector3(1.4, 1.1, LEG_Z * 2.0 + 2.0))
		g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
		g.abox(Vector3(lx - 0.5, 0.0, -9.6), Vector3(0.16, 0.14, 19.2))
		g.abox(Vector3(lx + 0.34, 0.0, -9.6), Vector3(0.16, 0.14, 19.2))
	g.mat(BuildingDetail.K_METAL, YELLOW, 0, BuildingDetail.F_RUST)
	g.abox(Vector3(LEG_X[0] - 3.0, BEAM_Y - 1.2, -1.3), Vector3(LEG_X[1] - LEG_X[0] + 6.0, 2.2, 2.6))
	g.mat(BuildingDetail.K_FLAT, YELLOW, 0, BuildingDetail.F_STRIPES)
	g.abox(Vector3(LEG_X[0] - 3.0, BEAM_Y - 1.5, 1.3), Vector3(LEG_X[1] - LEG_X[0] + 6.0, 0.7, 0.08))
	g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
	g.abox(Vector3(LEG_X[0] - 3.0, BEAM_Y + 1.0, -1.3), Vector3(LEG_X[1] - LEG_X[0] + 6.0, 0.9, 0.06))
	for m: Vector3 in [Vector3(-9.6, 0, 9.6), Vector3(9.6, 0, -9.6), Vector3(44.0, 0, 9.6)]:
		CityKit.lattice(g, m, 0.55, 0.3, 15.0, 6, 0.05, BuildingDetail.METAL_DARK, BuildingDetail.METAL_DARK)
		g.mat(BuildingDetail.K_METAL, ORANGE)
		g.abox(m + Vector3(-1.1, 15.0, -0.3), Vector3(2.2, 1.5, 0.6))


## The trolley, cab and hook. Running: over the street with a crushed car hanging. Parked: at the
## west leg, hook up, nothing on it.
func _crane_load(running: bool) -> void:
	var g := BuildingDetail.Geo.new()
	var x: float = 18.0 if running else LEG_X[0] + 2.4
	var hook_y: float = 9.5 if running else 19.0
	g.mat(BuildingDetail.K_METAL, ORANGE, 0, BuildingDetail.F_RUST)
	g.abox(Vector3(x - 1.8, BEAM_Y - 2.3, -1.7), Vector3(3.6, 1.1, 3.4))
	g.abox(Vector3(x - 1.2, BEAM_Y - 4.9, 1.75), Vector3(2.4, 2.6, 2.2))
	g.mat(BuildingDetail.K_GLASS, Color(0.3, 0.5, 0.62))
	g.abox(Vector3(x - 1.0, BEAM_Y - 4.2, 3.9), Vector3(2.0, 1.4, 0.08))
	g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
	for sx: float in [-0.5, 0.5]:
		g.rod(Vector3(x + sx, BEAM_Y - 2.3, 0), Vector3(x + sx * 0.3, hook_y + 1.4, 0), 0.04)
	g.cyl(Transform3D(Basis.IDENTITY, Vector3(x, hook_y + 0.9, 0)), 1.25, 1.25, 0.5, 14)
	if running:
		g.mat(BuildingDetail.K_METAL, Color(0.14, 0.56, 0.5), 0, BuildingDetail.F_RUST)
		g.box(Transform3D(Basis.from_euler(Vector3(0.12, 0.5, -0.08)), Vector3(x, hook_y + 0.2, 0)), Vector3(1.9, 0.75, 4.1), -1, true)
		g.mat(BuildingDetail.K_DARK, Color(0.05, 0.06, 0.08))
		g.box(Transform3D(Basis.from_euler(Vector3(0.12, 0.5, -0.08)), Vector3(x, hook_y + 0.2, 0.2)), Vector3(1.94, 0.3, 1.8))
	place_mesh("CraneRunning" if running else "CraneParked", g, STATE_BROKEN if running else STATE_SHUT_DOWN)


## The car press: a blue steel frame with yellow rams, a hopper on top, a conveyor rising to it
## from the west and a chute of cubes out of the east side.
func _press(g: BuildingDetail.Geo) -> void:
	g.mat(BuildingDetail.K_METAL, PRESS_BLUE, 0, BuildingDetail.F_RUST)
	g.abox(Vector3(-8.0, 0.0, -3.0), Vector3(7.6, 1.2, 6.0))
	for sx: float in [-7.6, -1.2]:
		for sz: float in [-2.8, 2.0]:
			g.abox(Vector3(sx, 1.2, sz), Vector3(0.8, 5.6, 0.8))
	g.abox(Vector3(-8.0, 6.8, -3.0), Vector3(7.6, 1.3, 6.0))
	g.mat(BuildingDetail.K_DARK, Color(0.05, 0.05, 0.06))
	g.abox(Vector3(-6.8, 1.2, -2.0), Vector3(5.6, 2.2, 4.0))
	g.mat(BuildingDetail.K_METAL, YELLOW)
	for sx2: float in [-5.8, -2.6]:
		g.cyl(Transform3D(Basis.IDENTITY, Vector3(sx2, 5.3, 0.0)), 0.42, 0.42, 3.0, 12)
	g.mat(BuildingDetail.K_METAL, Color(0.74, 0.76, 0.78))
	g.abox(Vector3(-7.0, 3.4, -2.2), Vector3(5.6, 0.5, 4.4))
	g.mat(BuildingDetail.K_FLAT, YELLOW, 0, BuildingDetail.F_STRIPES)
	g.abox(Vector3(-8.05, 0.0, 3.0), Vector3(7.7, 1.2, 0.06))
	g.mat(BuildingDetail.K_METAL, ORANGE, 0, BuildingDetail.F_RUST)
	g.cyl(Transform3D(Basis.IDENTITY, Vector3(-4.2, 8.7, 0.0)), 2.6, 1.3, 1.3, 4)
	# The conveyor from the yard floor to the hopper.
	g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
	g.rod(Vector3(-12.4, 0.5, 0.0), Vector3(-6.6, 8.6, 0.0), 0.5)
	for t: float in [0.3, 0.7]:
		var p: Vector3 = Vector3(-12.4, 0.5, 0.0).lerp(Vector3(-6.6, 8.6, 0.0), t)
		g.rod(Vector3(p.x, 0.0, -0.8), p, 0.09)
		g.rod(Vector3(p.x, 0.0, 0.8), p, 0.09)
	g.mat(BuildingDetail.K_METAL, YELLOW)
	g.rod(Vector3(-12.4, 1.2, 0.62), Vector3(-6.6, 9.3, 0.62), 0.05)
	g.rod(Vector3(-12.4, 1.2, -0.62), Vector3(-6.6, 9.3, -0.62), 0.05)
	g.mat(BuildingDetail.K_METAL, Color(0.74, 0.76, 0.78))
	g.box(Transform3D(Basis(Vector3.FORWARD, -0.5), Vector3(1.6, 1.3, 0.0)), Vector3(4.6, 0.12, 2.2))


## The boiler house under the stack: an orange corrugated shed with a blue door and the yard's
## name board, and the banded stack behind it with its flue.
func _boiler_house(g: BuildingDetail.Geo) -> void:
	var r := Rect2(-41.0, -3.0, 12.0, 10.0)
	g.uv = BuildingDetail._bay_uv(r, 31)
	g.mat(BuildingDetail.K_FACADE, ORANGE.lightened(0.1), BuildingDetail.T_CONCRETE, BuildingDetail.F_RIBBON)
	g.abox(Vector3(r.position.x, 0.0, r.position.y), Vector3(r.size.x, 8.0, r.size.y), -2)
	g.mat(BuildingDetail.K_ROOF, PRESS_BLUE, 0, BuildingDetail.F_ROOF_SEAMS_X)
	g.box(Transform3D(Basis(Vector3.RIGHT, 0.1), Vector3(r.get_center().x, 8.5, r.get_center().y)), Vector3(r.size.x + 0.8, 0.14, r.size.y + 1.0))
	g.mat(BuildingDetail.K_METAL, PRESS_BLUE, 0, BuildingDetail.F_RUST)
	g.abox(Vector3(-33.6, 0.0, 7.0), Vector3(3.6, 4.4, 0.14))
	g.mat(BuildingDetail.K_FLAT, Color(0.1, 0.1, 0.11))
	g.abox(Vector3(-40.6, 5.5, 7.0), Vector3(11.2, 1.8, 0.1))
	g.mat(BuildingDetail.K_FLAT, YELLOW)
	g.abox(Vector3(-40.7, 5.4, 6.98), Vector3(11.4, 0.1, 0.16))
	g.abox(Vector3(-40.7, 7.3, 6.98), Vector3(11.4, 0.1, 0.16))
	CityKit.banded(g, STACK_AT, 1.9, 1.2, STACK_H, 9, STACK_RED, STACK_WHITE)
	g.mat(BuildingDetail.K_METAL, Color(0.74, 0.76, 0.78), 0, BuildingDetail.F_RUST)
	g.cyl(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(STACK_AT.x, 5.5, -4.0)), 0.8, 0.8, 2.6, 12, false)


## The wall of crushed cubes: five courses of car-paint blocks, stepped down at its ends.
func _cube_wall(g: BuildingDetail.Geo) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7103
	for row: int in 5:
		for i: int in range(row >> 1, 6 - ((row + 1) >> 1)):
			for d: int in 2:
				if row >= 3 and d == 1:
					continue
				g.mat(BuildingDetail.K_METAL, CityStreet.CAR_PAINT[rng.randi() % CityStreet.CAR_PAINT.size()], 0, BuildingDetail.F_RUST)
				var at := Vector3(35.4 + float(i) * (CUBE + 0.04) + CUBE * 0.5, (float(row) + 0.5) * CUBE, -9.3 + float(d) * (CUBE + 0.05))
				g.box(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.05, 0.05)), at), Vector3.ONE * CUBE, -1, row == 0)
