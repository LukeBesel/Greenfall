extends VerdanceCity
## Kettle Bay (site 3), the working harbour: navy, white, rust-red and buoy-orange fronts, flags
## on the roofs and container stacks down the main street (the look is data: cities.json
## "kettle_bay"). This script is its source landmark: the coastal tanker Long Tide, driven bow
## first onto the town's shore, listing, with a torn plate forward and an oil slick spreading over
## the lake and up the lot. A dock crane stands at her bow.
## Running: oil pours from a gash in her bow on the side the yard sees and runs down the lot
## toward the town as a wide slick with a rainbow sheen; the slick lies on the lake too and the
## boom is torn open. Shut down: a yellow plate is welded over the gash, the slick is gone from
## the lot and the lake (clear blue water inside the boom), the orange boom closes round the hull
## with a lit marker buoy every few floats, and her deck lamps come on.
## The ship is built in her own frame (z from stern to bow, keel line at y 0), heeled and skewed,
## then set in the landmark's frame (x to the right seen from the yard, z toward the yard).

const HULL_RED := Color(0.66, 0.17, 0.1)
const NAVY := Color(0.1, 0.2, 0.46)
const WHITE := Color(0.95, 0.95, 0.92)
const DECK := Color(0.16, 0.46, 0.4)
const ORANGE := Color(0.96, 0.46, 0.08)
const YELLOW := Color(0.98, 0.78, 0.1)
const HALF_LEN: float = 35.0
const HALF_BEAM: float = 5.6
const KEEL_Y: float = -1.6
const DECK_Y: float = 7.2
const STATIONS: int = 22
const SHIP_AT := Vector3(1.5, 0.0, 1.0)
const SHIP_TURN := Vector3(-0.04, 0.22, 0.09)   # bow up, skewed off the street, listing
const SLICK_A := Color(0.2, 0.08, 0.36, 0.92)
const SLICK_B := Color(0.8, 0.2, 0.7, 0.74)
const CLEAR_A := Color(0.2, 0.62, 0.95, 0.5)
const CLEAR_B := Color(0.62, 0.9, 1.0, 0.36)
const OIL := Color(0.16, 0.05, 0.3, 0.95)
const OIL_END := Color(0.7, 0.2, 0.66, 0.6)
const GASH_AT := Vector3(2.5, 3.9, 30.4)        # in the ship's frame: the bow plate the yard sees
const TONGUE_AT := Vector3(4.0, 0.09, 41.0)     # the slick on the lot, in the landmark's frame
const TONGUE_HALF := Vector2(9.0, 17.0)
const FLOAT_R: float = 0.5
const FLOAT_LEN: float = 2.6
const BUOY_EVERY: int = 6
const BUOY_H: float = 2.3
const BOOM_AT := Vector2(5.0, -4.0)
const BOOM_R := Vector2(27.0, 44.0)
const BOOM_FLOATS: int = 84
const CRANE_AT := Vector3(-9.6, 0.0, 41.5)

var _ship := Transform3D.IDENTITY


## The wettest block one street out from the yard's ring (the lake took it): she lies there, bow
## to the town. With no lake in reach the data's dry blocks are used.
func _pick_block(site: VerdanceSite) -> Vector2i:
	var best: Vector2i = NO_BLOCK
	var most: float = 0.5
	for key: Vector2i in [Vector2i(-2, 0), Vector2i(2, 0), Vector2i(0, -2), Vector2i(0, 2)]:
		var c: Vector2 = Vector2(key) * CityLayout.PITCH
		var wet: float = site._wet_share(Rect2(c - Vector2(11, 11), Vector2(22, 22)), 2.0)
		if wet > most:
			most = wet
			best = key
	return best if best != NO_BLOCK else super._pick_block(site)


func _ship_xf() -> Transform3D:
	return Transform3D(Basis.from_euler(SHIP_TURN), SHIP_AT)


func _footprint() -> Array[Rect2]:
	var out: Array[Rect2] = [Rect2(CRANE_AT.x - 3.4, CRANE_AT.z - 3.4, 6.8, 6.8)]
	var xf: Transform3D = _ship_xf()
	for i: int in 8:
		var z: float = -HALF_LEN + 4.0 + float(i) * 8.6
		var c: Vector3 = xf * Vector3(0, 0, z)
		var half: float = _half_beam((z + HALF_LEN) / (HALF_LEN * 2.0)) + 0.6
		out.append(Rect2(c.x - half, c.z - 4.6, half * 2.0, 9.2))
	return out


## The slick's tongue on the lot stays free of junk, so the oil shows.
func _clear_ground() -> Array[Rect2]:
	return [Rect2(TONGUE_AT.x - TONGUE_HALF.x * 0.8, TONGUE_AT.z - TONGUE_HALF.y * 0.85, TONGUE_HALF.x * 1.6, TONGUE_HALF.y * 1.7)]


func _build_landmark() -> void:
	_ship = _ship_xf()
	var g := BuildingDetail.Geo.new()
	_hull(g)
	_deck_gear(g)
	_house(g)
	CityKit.xform(g, 0, _ship)
	_crane(g)
	place_mesh("Tanker", g)
	for i: int in 8:
		var z: float = -HALF_LEN + 4.0 + float(i) * 8.6
		var half: float = _half_beam((z + HALF_LEN) / (HALF_LEN * 2.0))
		PropColliders.add_box(_body, frame * _ship * Transform3D(Basis.IDENTITY, Vector3(0, 3.4, z)), Vector3(half * 2.0, 10.0, 8.8))
	add_landmark_solid(CRANE_AT + Vector3(0, 4.0, 0), Vector3(6.4, 8.0, 6.4))
	place_sign(_ship * Transform3D(Basis.IDENTITY, Vector3(0, DECK_Y + 10.3, -19.42)), 1.15)
	place_beacon(_ship * Vector3(0, DECK_Y + 16.6, -24.0), 0.26)
	_slick()
	var lamps: Array[Vector3] = _boom()
	for p: Vector3 in [Vector3(-4.4, DECK_Y + 9.4, -19.6), Vector3(4.4, DECK_Y + 9.4, -19.6), Vector3(0, DECK_Y + 9.0, 0.0), Vector3(0, DECK_Y + 11.4, 27.5),
			Vector3(-4.2, DECK_Y + 3.2, -19.4), Vector3(4.2, DECK_Y + 3.2, -19.4), Vector3(0, DECK_Y + 6.2, -19.4)]:
		lamps.append(_ship * p)
	lamps.append(CRANE_AT + Vector3(0, 20.5, 0))
	place_lamps("DeckLamps", lamps, 0.36)


## Half the hull's beam at station t (0 stern, 1 bow): a full stern, a long parallel middle body
## and a bow that closes to the stem.
static func _half_beam(t: float) -> float:
	if t < 0.1:
		return HALF_BEAM * lerpf(0.8, 1.0, t / 0.1)
	if t < 0.72:
		return HALF_BEAM
	return HALF_BEAM * maxf(0.03, 1.0 - pow((t - 0.72) / 0.28, 1.9))


static func _deck_y(t: float) -> float:
	return DECK_Y + 2.0 * pow(maxf(0.0, t - 0.7) / 0.3, 2.0) + 0.5 * pow(maxf(0.0, 0.12 - t) / 0.12, 2.0)


## One hull section: keel, bilge, waterline, sheer strake and deck edge, down the starboard side.
static func _section(t: float) -> Array[Vector3]:
	var z: float = lerpf(-HALF_LEN, HALF_LEN, t)
	var b: float = _half_beam(t)
	var dy: float = _deck_y(t)
	var flare: float = 1.0 + 0.35 * pow(maxf(0.0, t - 0.75) / 0.25, 2.0)
	return [Vector3(0, KEEL_Y, z), Vector3(b * 0.8, KEEL_Y + 0.8, z), Vector3(b, KEEL_Y + 3.4, z), Vector3(b * flare, dy - 1.5, z),
		Vector3(b * flare + 0.02, dy, z), Vector3(b * flare + 0.02, dy + 1.0, z)]


## The plating: red below the waterline, navy topsides, a white sheer strake, the bulwark, the
## deck between, and the flat transom.
func _hull(g: BuildingDetail.Geo) -> void:
	var paints: Array = [[HULL_RED, BuildingDetail.F_RUST], [HULL_RED, BuildingDetail.F_RUST], [NAVY, BuildingDetail.F_RUST], [WHITE, 0], [NAVY, 0]]
	for i: int in STATIONS:
		var a: Array[Vector3] = _section(float(i) / float(STATIONS))
		var b: Array[Vector3] = _section(float(i + 1) / float(STATIONS))
		for side: float in [-1.0, 1.0]:
			var m := Vector3(side, 1, 1)
			for k: int in 5:
				g.mat(BuildingDetail.K_METAL, paints[k][0], 0, int(paints[k][1]))
				var nrm: Vector3 = ((b[k] - a[k]) * m).cross((a[k + 1] - a[k]) * m).normalized()
				if nrm.x * side < 0.0:
					nrm = -nrm
				g.quad(a[k] * m, b[k] * m, b[k + 1] * m, a[k + 1] * m, nrm)
		g.mat(BuildingDetail.K_METAL, DECK, 0, BuildingDetail.F_RUST)
		g.quad(a[4] * Vector3(-1, 1, 1), a[4], b[4], b[4] * Vector3(-1, 1, 1), Vector3.UP)
	var s: Array[Vector3] = _section(0.0)
	for k: int in 5:
		g.mat(BuildingDetail.K_METAL, HULL_RED if k < 2 else NAVY, 0, BuildingDetail.F_RUST)
		g.quad(s[k] * Vector3(-1, 1, 1), s[k], s[k + 1], s[k + 1] * Vector3(-1, 1, 1), Vector3(0, 0, -1))
	# The torn plate forward on the starboard bow, and the black run down from it.
	g.mat(BuildingDetail.K_DARK, Color(0.02, 0.02, 0.03))
	g.box(Transform3D(Basis.from_euler(Vector3(0.0, -0.05, 0.1)), Vector3(5.4, 3.4, 18.0)), Vector3(0.3, 2.4, 4.2))
	g.box(Transform3D(Basis.from_euler(Vector3(0.0, -0.05, 0.16)), Vector3(5.36, 1.2, 18.4)), Vector3(0.24, 2.6, 1.3))
	g.mat(BuildingDetail.K_METAL, NAVY.darkened(0.3), 0, BuildingDetail.F_RUST)
	g.box(Transform3D(Basis.from_euler(Vector3(0.5, -0.5, 0.7)), Vector3(5.6, 4.6, 16.2)), Vector3(0.08, 1.6, 2.2))
	g.box(Transform3D(Basis.from_euler(Vector3(-0.4, -0.2, -0.5)), Vector3(5.5, 2.4, 20.3)), Vector3(0.08, 1.4, 1.8))


## The cargo deck: two cargo mains and a catwalk down the middle, tank hatches, the midships
## manifold with its kingposts, and the foremast on the forecastle.
func _deck_gear(g: BuildingDetail.Geo) -> void:
	g.mat(BuildingDetail.K_METAL, ORANGE, 0, BuildingDetail.F_RUST)
	for sx: float in [-1.5, 1.5]:
		g.cyl(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(sx, DECK_Y + 0.9, 3.0)), 0.36, 0.36, 40.0, 10, false)
	g.mat(BuildingDetail.K_METAL, Color(0.74, 0.76, 0.78))
	g.abox(Vector3(-0.5, DECK_Y + 1.7, -17.0), Vector3(1.0, 0.08, 40.0))
	for z: float in [-12.0, -4.0, 4.0, 12.0, 20.0]:
		g.mat(BuildingDetail.K_METAL, WHITE)
		g.cyl(Transform3D(Basis.IDENTITY, Vector3(-3.4, DECK_Y + 0.35, z)), 0.7, 0.8, 0.7, 10)
		g.cyl(Transform3D(Basis.IDENTITY, Vector3(3.4, DECK_Y + 0.35, z)), 0.7, 0.8, 0.7, 10)
		g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
		g.rod(Vector3(-0.5, DECK_Y, z + 1.5), Vector3(-0.5, DECK_Y + 1.7, z + 1.5), 0.04)
		g.rod(Vector3(0.5, DECK_Y, z + 1.5), Vector3(0.5, DECK_Y + 1.7, z + 1.5), 0.04)
	g.mat(BuildingDetail.K_METAL, YELLOW, 0, BuildingDetail.F_RUST)
	for sx2: float in [-3.6, 3.6]:
		g.cyl(Transform3D(Basis.IDENTITY, Vector3(sx2, DECK_Y + 4.5, 0.0)), 0.22, 0.3, 9.0, 8)
		g.rod(Vector3(sx2, DECK_Y + 8.6, 0.0), Vector3(sx2 * 1.9, DECK_Y + 5.4, 3.0), 0.1)
	g.rod(Vector3(-3.6, DECK_Y + 8.8, 0.0), Vector3(3.6, DECK_Y + 8.8, 0.0), 0.14)
	g.mat(BuildingDetail.K_METAL, ORANGE)
	g.cyl(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.0, DECK_Y + 1.2, 0.0)), 0.3, 0.3, 10.6, 10)
	g.mat(BuildingDetail.K_FLAT, Color(0.86, 0.14, 0.1))
	for sx3: float in [-5.2, 5.2]:
		g.cyl(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(sx3, DECK_Y + 1.2, 0.0)), 0.5, 0.5, 0.14, 10)
	# The forecastle and foremast.
	g.mat(BuildingDetail.K_METAL, WHITE, 0, BuildingDetail.F_RUST)
	g.abox(Vector3(-2.2, DECK_Y + 1.0, 24.5), Vector3(4.4, 1.6, 5.0))
	g.mat(BuildingDetail.K_METAL, YELLOW)
	g.cyl(Transform3D(Basis.IDENTITY, Vector3(0, DECK_Y + 7.0, 27.5)), 0.1, 0.18, 9.0, 8)
	g.rod(Vector3(-1.6, DECK_Y + 9.6, 27.5), Vector3(1.6, DECK_Y + 9.6, 27.5), 0.05)


## The accommodation block aft: three white decks with window bands, the wheelhouse with bridge
## wings and the name board, the banded funnel and a mast.
func _house(g: BuildingDetail.Geo) -> void:
	g.mat(BuildingDetail.K_METAL, WHITE, 0, BuildingDetail.F_RUST)
	g.abox(Vector3(-4.6, DECK_Y, -30.0), Vector3(9.2, 6.0, 10.5))
	g.abox(Vector3(-3.8, DECK_Y + 6.0, -28.5), Vector3(7.6, 2.9, 8.0))
	g.abox(Vector3(-6.2, DECK_Y + 5.9, -21.6), Vector3(12.4, 0.16, 2.2))
	g.mat(BuildingDetail.K_GLASS, Color(0.2, 0.42, 0.6))
	for y: float in [DECK_Y + 1.4, DECK_Y + 4.0]:
		g.abox(Vector3(-4.3, y, -19.5), Vector3(8.6, 0.9, 0.06))
		for sx: float in [-4.66, 4.6]:
			g.abox(Vector3(sx, y, -29.0), Vector3(0.06, 0.9, 8.6))
	g.abox(Vector3(-3.6, DECK_Y + 7.0, -20.5), Vector3(7.2, 1.2, 0.06))
	g.mat(BuildingDetail.K_FLAT, NAVY)
	g.abox(Vector3(-4.4, DECK_Y + 9.5, -19.56), Vector3(8.8, 1.6, 0.12))
	g.mat(BuildingDetail.K_METAL, ORANGE, 0, BuildingDetail.F_RUST)
	g.cyl(Transform3D(Basis.IDENTITY, Vector3(0, DECK_Y + 11.4, -26.5)), 1.5, 1.8, 5.0, 12)
	g.mat(BuildingDetail.K_METAL, NAVY)
	g.cyl(Transform3D(Basis.IDENTITY, Vector3(0, DECK_Y + 12.8, -26.5)), 1.62, 1.7, 1.2, 12, false)
	g.mat(BuildingDetail.K_DARK, Color(0.04, 0.04, 0.05))
	g.cyl(Transform3D(Basis.IDENTITY, Vector3(0, DECK_Y + 14.0, -26.5)), 1.52, 1.52, 0.3, 12)
	g.mat(BuildingDetail.K_METAL, YELLOW)
	g.cyl(Transform3D(Basis.IDENTITY, Vector3(0, DECK_Y + 12.8, -24.0)), 0.07, 0.12, 7.6, 6)
	g.rod(Vector3(-1.4, DECK_Y + 14.6, -24.0), Vector3(1.4, DECK_Y + 14.6, -24.0), 0.04)
	g.mat(BuildingDetail.K_FLAT, ORANGE)
	for sx2: float in [-5.0, 5.0]:
		g.box(Transform3D(Basis(Vector3.FORWARD, 0.25 * signf(sx2)), Vector3(sx2, DECK_Y + 3.4, -25.0)), Vector3(1.5, 1.3, 5.2))


## The dock crane at her bow: an orange portal on four legs, a white machinery house, a lattice
## jib raised over the ship.
func _crane(g: BuildingDetail.Geo) -> void:
	var c: Vector3 = CRANE_AT
	g.mat(BuildingDetail.K_METAL, ORANGE, 0, BuildingDetail.F_RUST)
	for sx: float in [-2.8, 2.8]:
		for sz: float in [-2.8, 2.8]:
			g.rod(c + Vector3(sx, 0, sz), c + Vector3(sx * 0.7, 9.0, sz * 0.7), 0.3)
	g.abox(c + Vector3(-2.6, 9.0, -2.6), Vector3(5.2, 0.8, 5.2))
	g.cyl(Transform3D(Basis.IDENTITY, c + Vector3(0, 10.6, 0)), 1.5, 1.5, 1.6, 12)
	g.mat(BuildingDetail.K_METAL, WHITE, 0, BuildingDetail.F_RUST)
	g.abox(c + Vector3(-2.2, 11.4, -1.6), Vector3(4.4, 3.4, 5.2))
	g.mat(BuildingDetail.K_GLASS, Color(0.2, 0.42, 0.6))
	g.abox(c + Vector3(-1.9, 12.6, -1.66), Vector3(3.8, 1.3, 0.06))
	g.mat(BuildingDetail.K_METAL, ORANGE)
	var foot: Vector3 = c + Vector3(0, 13.4, -1.6)
	var tip: Vector3 = c + Vector3(3.0, 27.0, -19.0)
	for o: Vector3 in [Vector3(-0.7, 0, 0), Vector3(0.7, 0, 0), Vector3(0, 1.1, 0)]:
		g.rod(foot + o, tip + o * 0.3, 0.1)
	for k: int in 7:
		var p: Vector3 = foot.lerp(tip, float(k) / 7.0)
		var q: Vector3 = foot.lerp(tip, float(k + 1) / 7.0)
		g.rod(p + Vector3(-0.7, 0, 0) * (1.0 - float(k) / 10.0), q + Vector3(0.7, 0, 0) * (1.0 - float(k + 1) / 10.0), 0.05)
	g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
	g.rod(tip, tip + Vector3(0, -9.0, 0), 0.03)
	g.rod(c + Vector3(0, 17.5, 2.0), tip, 0.03)
	g.rod(c + Vector3(0, 14.8, 2.0), c + Vector3(0, 17.5, 2.0), 0.12)


## The slick: a wide film on the lake round her starboard side, a tongue of it up the lot at her
## bow, and the stream out of the torn plate.
func _slick() -> void:
	var water: MeshInstance3D = CityKit.film("SlickWater", Vector2(30.0, 44.0), SLICK_A, SLICK_B, 1.0)
	water.position = Vector3(BOOM_AT.x + 3.0, WATER_Y + 0.1, BOOM_AT.y)
	place(water, STATE_BROKEN)
	var clear: MeshInstance3D = CityKit.film("ClearWater", Vector2(26.0, 42.0), CLEAR_A, CLEAR_B, 0.0)
	clear.position = Vector3(BOOM_AT.x, WATER_Y + 0.1, BOOM_AT.y)
	place(clear, STATE_SHUT_DOWN)
	var land: MeshInstance3D = CityKit.film("SlickLand", TONGUE_HALF, SLICK_A, SLICK_B, 1.0, false, 0.3)
	land.position = TONGUE_AT
	place(land, STATE_BROKEN)
	var g := BuildingDetail.Geo.new()
	g.mat(BuildingDetail.K_DARK, Color(0.03, 0.02, 0.05))
	g.rod(_ship * Vector3(5.3, 2.6, 18.2), _ship * Vector3(6.4, 0.1 - SHIP_AT.y, 19.0), 0.16)
	# The gash in the bow plate the yard sees: a black hole, the plate's edges bent out, a black
	# run down the hull under it.
	var turn := Basis.from_euler(Vector3(0.0, -0.62, 0.12))
	g.box(_ship * Transform3D(turn, GASH_AT), Vector3(0.5, 2.3, 2.9))
	g.box(_ship * Transform3D(turn, GASH_AT + Vector3(-0.1, -2.6, 0.1)), Vector3(0.34, 3.2, 1.7))
	g.mat(BuildingDetail.K_METAL, ORANGE.darkened(0.25), 0, BuildingDetail.F_RUST)
	g.box(_ship * Transform3D(turn * Basis.from_euler(Vector3(0.5, 0.3, 0.5)), GASH_AT + Vector3(0.5, 1.3, 0.9)), Vector3(0.08, 1.5, 1.7))
	g.box(_ship * Transform3D(turn * Basis.from_euler(Vector3(-0.4, -0.3, -0.5)), GASH_AT + Vector3(0.5, -0.9, -1.2)), Vector3(0.08, 1.3, 1.5))
	place_mesh("Leak", g, STATE_BROKEN)
	var mouth: Vector3 = _ship * (GASH_AT + Vector3(0.5, -0.8, 0.3))
	place(CityKit.stream("OilRun", mouth, OIL, OIL_END, 70, maxf(1.0, mouth.y), 2.6, 1.4), STATE_BROKEN)
	# Made safe: a yellow plate over the gash, strapped in orange.
	var fix := BuildingDetail.Geo.new()
	fix.mat(BuildingDetail.K_METAL, YELLOW)
	fix.box(_ship * Transform3D(turn, GASH_AT + Vector3(0.15, -0.2, 0.0)), Vector3(0.14, 3.4, 3.8))
	fix.mat(BuildingDetail.K_METAL, ORANGE)
	for dz: float in [-1.2, 1.2]:
		fix.box(_ship * Transform3D(turn, GASH_AT + Vector3(0.24, -0.2, dz)), Vector3(0.1, 3.7, 0.3))
	place_mesh("Patch", fix, STATE_SHUT_DOWN)


## The floating boom: orange floats in a ring on the water round the hull. Torn open while she
## leaks (half the floats, drifting off line), closed once the leak is stopped, with a marker buoy
## on a pole every few floats. Returns the buoys' lamp points (lit when shut down).
func _boom() -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5527
	var open: Array[Transform3D] = []
	var closed: Array[Transform3D] = []
	var buoys: Array[Vector3] = []
	for i: int in BOOM_FLOATS:
		var a: float = TAU * float(i) / float(BOOM_FLOATS)
		var p := Vector3(BOOM_AT.x + cos(a) * BOOM_R.x, WATER_Y + 0.12, BOOM_AT.y + sin(a) * BOOM_R.y)
		var sp: Vector3 = frame * p
		if not _site._wet(sp.x, sp.z):
			continue
		var turn: float = atan2(-cos(a) * BOOM_R.y, -sin(a) * BOOM_R.x)  # the float's long axis lies along the ring
		closed.append(Transform3D(Basis(Vector3.UP, turn), p))
		if closed.size() % BUOY_EVERY == 1:
			buoys.append(p)
		if i % 9 < 5:
			var drift := Vector3(rng.randf_range(-2.5, 2.5), 0.0, rng.randf_range(-2.5, 2.5))
			open.append(Transform3D(Basis(Vector3.UP, turn + rng.randf_range(-0.7, 0.7)), p + drift))
	var fg := BuildingDetail.Geo.new()
	fg.col = Color(1, 1, 1)
	fg.cyl(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO), FLOAT_R, FLOAT_R, FLOAT_LEN, 8)
	var mesh: ArrayMesh = CityKit.vc_mesh(fg)
	var mat: StandardMaterial3D = CityKit.vc_material(0.6)
	mat.albedo_color = ORANGE
	for e: Array in [["BoomOpen", open, STATE_BROKEN], ["BoomClosed", closed, STATE_SHUT_DOWN]]:
		var holder := Node3D.new()
		holder.name = str(e[0])
		place(holder, str(e[2]))
		if not (e[1] as Array).is_empty():
			CityKit.mmi_on(holder, "Floats", mesh, e[1], [], mat, false, 320.0)
	stats["boom_floats"] = closed.size()
	var poles := BuildingDetail.Geo.new()
	var lamps: Array[Vector3] = []
	for b: Vector3 in buoys:
		poles.mat(BuildingDetail.K_METAL, YELLOW)
		poles.cyl(Transform3D(Basis.IDENTITY, b + Vector3(0, BUOY_H * 0.5, 0)), 0.06, 0.09, BUOY_H, 6)
		poles.mat(BuildingDetail.K_FLAT, ORANGE)
		poles.cyl(Transform3D(Basis.IDENTITY, b + Vector3(0, 0.5, 0)), 0.3, 0.55, 0.7, 8)
		lamps.append(b + Vector3(0, BUOY_H + 0.2, 0))
	if not poles.empty():
		place_mesh("BoomBuoys", poles, STATE_SHUT_DOWN)
	return lamps
