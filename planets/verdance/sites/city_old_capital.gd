extends VerdanceCity
## Old Capital (site 1), the big city and the launch site: sandstone and cream fronts, copper-green
## roofs and domes, flags, red and gold banners down the main street (the look is data:
## cities.json "old_capital"). This script is its landmark, the place the whole planet is working
## toward: Launch Pad 1 across three blocks at the head of the open lot. A concrete launch table
## with a flame trench, an orange launch mount carrying the first stage of a rocket still in
## frames, a red-and-white service tower 78 m high (the tallest thing on Verdance) with three swing
## arms and a hammerhead crane, two lightning masts, a white propellant sphere and the assembly
## shed with a nose cone waiting on its cradle.
## Running (the pad still derelict): the top arm hangs broken, the sphere vents cold vapour, the
## pad is dark. Shut down (made safe): the arms stand level, the floodlights and tower lamps come on.
## Built in the landmark's frame: x to the right seen from the yard, z toward the yard.

const CONCRETE := Color(0.84, 0.82, 0.76)
const TOWER_RED := Color(0.86, 0.13, 0.1)
const TOWER_WHITE := Color(0.96, 0.95, 0.92)
const ORANGE := Color(0.96, 0.46, 0.08)
const CREAM := Color(0.97, 0.93, 0.82)
const TEAL := Color(0.06, 0.52, 0.54)
const YELLOW := Color(0.98, 0.8, 0.1)
const SANDSTONE := Color(1.0, 0.88, 0.62)
const COPPER := Color(0.3, 0.64, 0.54)
const GOLD := Color(0.92, 0.72, 0.16)
const TANK_BLUE := Color(0.14, 0.4, 0.8)
const VAPOUR := Color(0.8, 0.96, 1.0, 0.75)
const VAPOUR_END := Color(1.0, 1.0, 1.0, 0.0)
const TABLE := Rect2(-10.5, -10.5, 21.0, 21.0)
const TABLE_H: float = 1.6
const MOUNT_Y: float = 4.6
const STAGE_R: float = 3.5
const STAGE_H: float = 22.0
const TOWER_AT := Vector3(-7.2, TABLE_H, -7.0)
const TOWER_H: float = 78.0
const TOWER_HALF: float = 3.1
const TOWER_LEVELS: int = 13
const ARMS: Array[float] = [10.0, 19.0, 28.0]      # heights of the swing arms over the table
const SHED := Rect2(-45.0, -9.8, 17.0, 13.6)
const SHED_H: float = 9.0
const SPHERE_AT := Vector3(36.0, 7.6, 2.0)
const SPHERE_R: float = 5.0
const MASTS: Array[Vector2] = [Vector2(44.8, -8.8), Vector2(-45.4, 9.6)]
const MAST_H: float = 56.0


func _footprint() -> Array[Rect2]:
	var out: Array[Rect2] = [TABLE, SHED, Rect2(-42.4, 5.6, 9.6, 4.4), Rect2(SPHERE_AT.x - 5.4, SPHERE_AT.z - 5.4, 10.8, 10.8)]
	for m: Vector2 in MASTS:
		out.append(Rect2(m.x - 0.9, m.y - 0.9, 1.8, 1.8))
	return out


func _build_landmark() -> void:
	var g := BuildingDetail.Geo.new()
	_table(g)
	_stage(g)
	_tower(g)
	_shed(g)
	_sphere(g)
	for m: Vector2 in MASTS:
		CityKit.lattice(g, Vector3(m.x, 0.0, m.y), 0.8, 0.18, MAST_H, 14, 0.05, TOWER_RED, TOWER_WHITE)
	place_mesh("LaunchPad", g)
	var heights: Array[float] = [TABLE_H, SHED_H, 3.4, SPHERE_AT.y + SPHERE_R, 20.0, 20.0]
	for i: int in _footprint().size():
		var r: Rect2 = _footprint()[i]
		add_landmark_solid(Vector3(r.get_center().x, heights[i] * 0.5, r.get_center().y), Vector3(r.size.x, heights[i], r.size.y))
	add_landmark_solid(Vector3(0.0, TABLE_H + 10.0, 0.0), Vector3(9.0, 20.0, 9.0))
	add_landmark_solid(TOWER_AT + Vector3(0, 20.0, 0), Vector3(TOWER_HALF * 2.0 + 0.4, 40.0, TOWER_HALF * 2.0 + 0.4))
	_arms(true)
	_arms(false)
	place(CityKit.smoke("Vent", SPHERE_AT + Vector3(0, SPHERE_R + 5.0, 0), VAPOUR, VAPOUR_END, 26, 7.0, 26.0, 1.5, 11.0, Vector3(1.2, 0.0, 0.4)), STATE_BROKEN)
	place_sign(Transform3D(Basis.IDENTITY, Vector3(SHED.get_center().x, 6.6, SHED.end.y + 0.22)), 1.5)
	place_beacon(TOWER_AT + Vector3(0, TOWER_H + 5.4, 0), 0.4)
	var lamps: Array[Vector3] = []
	for k: int in 7:
		lamps.append(TOWER_AT + Vector3(TOWER_HALF + 0.3, 6.0 + float(k) * 12.0, TOWER_HALF + 0.3))
	for c: Vector2 in [Vector2(-9.6, 9.6), Vector2(9.6, 9.6), Vector2(9.6, -9.6)]:
		for dx: float in [-0.7, 0.0, 0.7]:
			lamps.append(Vector3(c.x + dx, TABLE_H + 14.4, c.y))
	for m2: Vector2 in MASTS:
		lamps.append(Vector3(m2.x, MAST_H + 0.4, m2.y))
	lamps.append(Vector3(SHED.get_center().x - 5.0, 8.6, SHED.end.y + 0.4))
	lamps.append(Vector3(SHED.get_center().x + 5.0, 8.6, SHED.end.y + 0.4))
	place_lamps("PadLights", lamps, 0.44)


## The launch table: a concrete deck with a hazard-striped edge, the dark flame trench through it
## front to back, an access ramp, and three floodlight towers on its corners.
func _table(g: BuildingDetail.Geo) -> void:
	g.uv = BuildingDetail._bay_uv(TABLE, 61)
	g.mat(BuildingDetail.K_PLAIN, CONCRETE, BuildingDetail.T_CONCRETE)
	g.abox(Vector3(TABLE.position.x, 0.0, TABLE.position.y), Vector3(TABLE.size.x, TABLE_H, TABLE.size.y), BuildingDetail.K_ROOF)
	g.mat(BuildingDetail.K_FLAT, YELLOW, 0, BuildingDetail.F_STRIPES)
	g.abox(Vector3(TABLE.position.x - 0.05, TABLE_H - 0.5, TABLE.position.y - 0.05), Vector3(TABLE.size.x + 0.1, 0.5, TABLE.size.y + 0.1), -2)
	g.mat(BuildingDetail.K_DARK, Color(0.04, 0.035, 0.03))
	g.abox(Vector3(-2.6, 0.0, TABLE.end.y - 0.02), Vector3(5.2, TABLE_H - 0.3, 0.1))
	g.abox(Vector3(-2.6, TABLE_H, -2.6), Vector3(5.2, 0.04, 13.0))
	g.mat(BuildingDetail.K_PLAIN, CONCRETE.darkened(0.1), BuildingDetail.T_CONCRETE)
	g.box(Transform3D(Basis(Vector3.RIGHT, 0.22), Vector3(7.0, TABLE_H * 0.5 - 0.1, TABLE.end.y + 3.4)), Vector3(4.0, 0.3, 7.2))
	for c: Vector2 in [Vector2(-9.6, 9.6), Vector2(9.6, 9.6), Vector2(9.6, -9.6)]:
		CityKit.lattice(g, Vector3(c.x, TABLE_H, c.y), 0.5, 0.3, 14.0, 5, 0.05, BuildingDetail.METAL_DARK, BuildingDetail.METAL_DARK)
		g.mat(BuildingDetail.K_METAL, YELLOW)
		g.abox(Vector3(c.x - 1.2, TABLE_H + 14.0, c.y - 0.3), Vector3(2.4, 1.0, 0.6))


## The launch mount and what stands on it: the rocket's first stage, plated in cream with a teal
## band and orange roll marks up to two thirds, bare ring frames and stringers above.
func _stage(g: BuildingDetail.Geo) -> void:
	var base := Vector3(0.0, TABLE_H, 0.0)
	g.mat(BuildingDetail.K_METAL, ORANGE, 0, BuildingDetail.F_RUST)
	for a: float in [0.785, 2.356, 3.927, 5.498]:
		g.rod(base + Vector3(cos(a) * 5.4, 0, sin(a) * 5.4), base + Vector3(cos(a) * 3.9, MOUNT_Y - TABLE_H, sin(a) * 3.9), 0.42)
	g.cyl(Transform3D(Basis.IDENTITY, Vector3(0, MOUNT_Y + 0.3, 0)), STAGE_R + 0.9, STAGE_R + 0.9, 0.6, 20, false)
	g.mat(BuildingDetail.K_DARK, Color(0.05, 0.05, 0.06))
	for a2: float in [0.0, 1.571, 3.142, 4.712]:
		g.cyl(Transform3D(Basis.IDENTITY, Vector3(cos(a2) * 1.7, MOUNT_Y + 0.2, sin(a2) * 1.7)), 0.7, 1.15, 1.4, 10)
	var y0: float = MOUNT_Y + 0.8
	var bands: Array = [[0.0, 0.2, CREAM], [0.2, 0.27, ORANGE], [0.27, 0.62, CREAM], [0.62, 0.74, TEAL], [0.74, 1.0, CREAM]]
	for b: Array in bands:
		g.mat(BuildingDetail.K_METAL, b[2] as Color)
		var from: float = float(b[0])
		var to: float = float(b[1])
		g.cyl(Transform3D(Basis.IDENTITY, Vector3(0, y0 + STAGE_H * (from + to) * 0.5, 0)), STAGE_R, STAGE_R, STAGE_H * (to - from), 20, false)
	g.mat(BuildingDetail.K_DARK, Color(0.06, 0.06, 0.07))
	g.cyl(Transform3D(Basis.IDENTITY, Vector3(0, y0 + STAGE_H - 0.1, 0)), STAGE_R - 0.15, STAGE_R - 0.15, 0.1, 20)
	# Frames above the plating: the stage is not finished.
	g.mat(BuildingDetail.K_METAL, Color(0.74, 0.76, 0.78))
	var top: float = y0 + STAGE_H
	for k: int in 12:
		var a3: float = TAU * float(k) / 12.0
		g.rod(Vector3(cos(a3) * STAGE_R, top, sin(a3) * STAGE_R), Vector3(cos(a3) * STAGE_R, top + 7.0, sin(a3) * STAGE_R), 0.06)
	for y: float in [top + 2.3, top + 4.6, top + 7.0]:
		g.cyl(Transform3D(Basis.IDENTITY, Vector3(0, y, 0)), STAGE_R + 0.05, STAGE_R + 0.05, 0.2, 20, false)
	g.mat(BuildingDetail.K_FLAT, ORANGE, 0, BuildingDetail.F_STRIPES)
	g.cyl(Transform3D(Basis.IDENTITY, Vector3(0, top + 0.2, 0)), STAGE_R + 0.03, STAGE_R + 0.03, 0.4, 20, false)


## The service tower: a red-and-white lattice shaft with work decks, the hammerhead crane on top
## and a mast above that.
func _tower(g: BuildingDetail.Geo) -> void:
	CityKit.lattice(g, TOWER_AT, TOWER_HALF, TOWER_HALF, TOWER_H, TOWER_LEVELS, 0.2, TOWER_RED, TOWER_WHITE)
	# Every other level is a clad work floor, red and white by turns, so the shaft reads from across the city.
	var lh: float = TOWER_H / float(TOWER_LEVELS)
	for k: int in TOWER_LEVELS:
		g.mat(BuildingDetail.K_METAL, Color(0.74, 0.76, 0.78))
		g.abox(TOWER_AT + Vector3(-TOWER_HALF - 0.5, float(k) * lh - 0.07, -TOWER_HALF - 0.5), Vector3(TOWER_HALF * 2.0 + 1.0, 0.14, TOWER_HALF * 2.0 + 1.0))
		if k % 2 == 1:
			g.mat(BuildingDetail.K_METAL, TOWER_RED if k % 4 == 1 else TOWER_WHITE, 0, BuildingDetail.F_RUST)
			g.abox(TOWER_AT + Vector3(-TOWER_HALF + 0.15, float(k) * lh, -TOWER_HALF + 0.15), Vector3(TOWER_HALF * 2.0 - 0.3, lh, TOWER_HALF * 2.0 - 0.3), -2)
	g.mat(BuildingDetail.K_METAL, YELLOW, 0, BuildingDetail.F_RUST)
	g.abox(TOWER_AT + Vector3(-3.0, TOWER_H, -3.0), Vector3(6.0, 1.6, 6.0))
	g.rod(TOWER_AT + Vector3(-7.0, TOWER_H + 2.4, -6.8), TOWER_AT + Vector3(13.0, TOWER_H + 2.4, 12.6), 0.8)
	g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
	g.rod(TOWER_AT + Vector3(7.2, TOWER_H + 1.8, 7.0), TOWER_AT + Vector3(7.2, TOWER_H - 14.0, 7.0), 0.06)
	g.cyl(Transform3D(Basis.IDENTITY, TOWER_AT + Vector3(0, TOWER_H + 3.6, 0)), 0.08, 0.16, 4.0, 6)


## The swing arms from the tower to the stage. Running: the lower two reach it, the top one has
## dropped and hangs. Shut down: all three are level.
func _arms(running: bool) -> void:
	var g := BuildingDetail.Geo.new()
	var to_stage: Vector3 = (Vector3(0, 0, 0) - Vector3(TOWER_AT.x, 0, TOWER_AT.z)).normalized()
	var reach: float = maxf(2.2, Vector2(TOWER_AT.x, TOWER_AT.z).length() - STAGE_R - TOWER_HALF)
	for i: int in ARMS.size():
		var root: Vector3 = Vector3(TOWER_AT.x, TABLE_H + ARMS[i], TOWER_AT.z) + to_stage * TOWER_HALF
		var tip: Vector3 = root + to_stage * reach
		if running and i == ARMS.size() - 1:
			tip = root + (to_stage * 0.45 + Vector3(0, -0.89, 0)) * reach
		g.mat(BuildingDetail.K_METAL, TOWER_WHITE if i % 2 == 0 else TOWER_RED, 0, BuildingDetail.F_RUST)
		for o: Vector3 in [Vector3(0, 0.9, 0), Vector3(0, -0.9, 0)]:
			g.rod(root + o, tip + o * 0.6, 0.22)
		g.rod(root + Vector3(0, 0.9, 0), tip + Vector3(0, -0.5, 0), 0.1)
		g.mat(BuildingDetail.K_METAL, YELLOW)
		g.box(Transform3D(Basis.looking_at(tip - root, Vector3(0.3, 1, 0.1)), tip), Vector3(2.4, 2.4, 0.7))
	place_mesh("ArmsRunning" if running else "ArmsLevel", g, STATE_BROKEN if running else STATE_SHUT_DOWN)


## The assembly shed (sandstone walls, a copper-green roof, a tall teal door and the pad's name in
## gilt letters) and a nose cone on its cradle in front of it.
func _shed(g: BuildingDetail.Geo) -> void:
	g.uv = BuildingDetail._bay_uv(SHED, 67)
	g.mat(BuildingDetail.K_FACADE, SANDSTONE, BuildingDetail.T_BRICK, BuildingDetail.F_RIBBON)
	g.abox(Vector3(SHED.position.x, 0.0, SHED.position.y), Vector3(SHED.size.x, SHED_H, SHED.size.y), -2)
	g.mat(BuildingDetail.K_ROOF, COPPER, 0, BuildingDetail.F_ROOF_SEAMS_X)
	var sc: Vector2 = SHED.get_center()
	g.box(Transform3D(Basis(Vector3.RIGHT, 0.08), Vector3(sc.x, SHED_H + 0.6, sc.y)), Vector3(SHED.size.x + 1.0, 0.16, SHED.size.y + 1.2))
	g.mat(BuildingDetail.K_COPING, SANDSTONE.lightened(0.2))
	g.abox(Vector3(SHED.position.x - 0.3, SHED_H - 0.5, SHED.position.y - 0.3), Vector3(SHED.size.x + 0.6, 0.5, SHED.size.y + 0.6))
	g.mat(BuildingDetail.K_METAL, TEAL, 0, BuildingDetail.F_RUST)
	g.abox(Vector3(SHED.get_center().x - 3.4, 0.0, SHED.end.y), Vector3(6.8, 5.0, 0.14))
	g.mat(BuildingDetail.K_FLAT, Color(0.1, 0.24, 0.2))
	g.abox(Vector3(SHED.position.x + 0.8, 5.5, SHED.end.y + 0.02), Vector3(SHED.size.x - 1.6, 2.2, 0.12))
	g.mat(BuildingDetail.K_FLAT, GOLD)
	g.abox(Vector3(SHED.position.x + 0.7, 5.4, SHED.end.y), Vector3(SHED.size.x - 1.4, 0.1, 0.18))
	g.abox(Vector3(SHED.position.x + 0.7, 7.7, SHED.end.y), Vector3(SHED.size.x - 1.4, 0.1, 0.18))
	# The nose cone, lying on a yellow cradle.
	var c := Vector3(-37.6, 2.0, 7.8)
	var lie := Basis(Vector3.FORWARD, PI * 0.5)
	g.mat(BuildingDetail.K_METAL, CREAM)
	g.cyl(Transform3D(lie, c + Vector3(-1.4, 0, 0)), 1.7, 1.7, 2.6, 16)
	g.cyl(Transform3D(lie, c + Vector3(2.0, 0, 0)), 0.2, 1.7, 4.2, 16)
	g.mat(BuildingDetail.K_METAL, ORANGE)
	g.cyl(Transform3D(lie, c + Vector3(-0.2, 0, 0)), 1.73, 1.73, 0.4, 16, false)
	g.mat(BuildingDetail.K_METAL, YELLOW, 0, BuildingDetail.F_RUST)
	for x: float in [-2.2, 0.8]:
		g.abox(Vector3(c.x + x - 0.2, 0.0, c.z - 1.9), Vector3(0.4, 1.0, 3.8))
	g.abox(Vector3(c.x - 3.0, 0.0, c.z - 0.2), Vector3(5.4, 0.3, 0.4))


## The propellant sphere: white with a blue band on six legs, a ladder ring and the vent pipe.
func _sphere(g: BuildingDetail.Geo) -> void:
	var rings: int = 10
	for i: int in rings:
		var a0: float = -PI * 0.5 + PI * float(i) / float(rings)
		var a1: float = -PI * 0.5 + PI * float(i + 1) / float(rings)
		g.mat(BuildingDetail.K_METAL, TANK_BLUE if i == 5 else TOWER_WHITE, 0, BuildingDetail.F_RUST if i < 3 else 0)
		CityKit.ball_ring(g, SPHERE_AT, SPHERE_R, SPHERE_R, a0, a1, 18)
	g.mat(BuildingDetail.K_METAL, TANK_BLUE.darkened(0.2))
	for k: int in 6:
		var a: float = TAU * float(k) / 6.0
		g.rod(Vector3(SPHERE_AT.x + cos(a) * 4.6, 0, SPHERE_AT.z + sin(a) * 4.6), SPHERE_AT + Vector3(cos(a) * 4.4, -1.0, sin(a) * 4.4), 0.22)
	g.mat(BuildingDetail.K_METAL, Color(0.74, 0.76, 0.78))
	g.cyl(Transform3D(Basis.IDENTITY, SPHERE_AT + Vector3(0, SPHERE_R + 2.5, 0)), 0.2, 0.2, 5.0, 8)
