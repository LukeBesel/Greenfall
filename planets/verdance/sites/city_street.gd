class_name CityStreet
extends RefCounted
## What lines a Verdance city's main street (cities.json "street"), so two cities are told apart
## at street level: market stalls, stacked shipping containers, stacks of crushed cars, white
## picket fences with letter boxes, or banner poles. One mesh in the city's building material;
## every piece gets a collider and a keep-off footprint.

## Per kind: metres from the road's centre line, the clear space it needs [across, along], its
## keep-off footprint when that differs, and whether it turns to face the street.
const KINDS: Dictionary = {
	"stalls": {"off": 2.9, "size": Vector2(3.4, 2.4), "rect": Vector2(3.2, 2.3), "turn": true},
	"containers": {"off": 2.9, "size": Vector2(2.8, 6.6), "turn": false},
	"car_stacks": {"off": 2.9, "size": Vector2(2.4, 4.8), "turn": false},
	"fences": {"off": 6.85, "size": Vector2(0.4, 5.2), "turn": false},
	"banners": {"off": 5.0, "size": Vector2(0.6, 0.6), "turn": false},
}
const JUNCTION_CLEAR_M: float = 7.5
const STREET_FROM: float = -98.0
const STREET_TO: float = 100.0
const CAR_PAINT: Array[Color] = [Color(0.86, 0.14, 0.1), Color(0.96, 0.74, 0.06), Color(0.12, 0.38, 0.74), Color(0.16, 0.56, 0.36),
	Color(0.94, 0.92, 0.86), Color(0.94, 0.44, 0.08), Color(0.36, 0.72, 0.8), Color(0.56, 0.2, 0.5)]
const FENCE_WHITE := Color(0.97, 0.96, 0.92)


## Lines the street east of the yard. Returns how many pieces stand.
static func build(city: VerdanceCity, site: VerdanceSite, look: CityLook, yard_r: float) -> int:
	var kind: String = str(look.data.get("street", ""))
	if not KINDS.has(kind):
		return 0
	var spec: Dictionary = KINDS[kind]
	var gap: Array = look.data.get("street_gap", [5.0, 8.0])
	var skip: float = float(look.data.get("street_skip", 0.3))
	var g := BuildingDetail.Geo.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = site.seed_value + 2203
	var n: int = 0
	var road_x: float = CityLayout.PITCH * 0.5
	var size: Vector2 = spec["size"]
	var foot: Vector2 = spec.get("rect", size - Vector2(0.1, 0.1))
	for side: float in [-1.0, 1.0]:
		var z: float = STREET_FROM
		while z < STREET_TO:
			var p := Vector2(road_x + side * float(spec["off"]), z + rng.randf_range(-0.6, 0.6))
			z += rng.randf_range(float(gap[0]), float(gap[1]))
			if absf(p.y) < yard_r or p.length() > site.town_r - 8.0 or not city.is_free(p, size):
				continue
			if absf(fposmod(p.y + CityLayout.PITCH * 0.5, CityLayout.PITCH) - CityLayout.PITCH * 0.5) < JUNCTION_CLEAR_M:
				continue  # the junctions stay open
			if rng.randf() < skip:
				continue
			var yaw: float = (PI * 0.5 * side if bool(spec["turn"]) else 0.0) + rng.randf_range(-0.08, 0.08)
			var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0.0, p.y))
			var solid := Vector3(size.x, 2.0, size.y)
			match kind:
				"stalls":
					_stall(g, xf, look, rng)
					solid = Vector3(3.0, 2.0, 2.0)
				"containers":
					solid.y = _containers(g, xf, look, rng)
				"car_stacks":
					solid.y = _car_stack(g, xf, rng)
				"fences":
					_fence(g, xf, look, rng, side)
					solid = Vector3(0.2, 1.0, size.y)
				"banners":
					_banner(g, xf, look, rng, side)
					solid = Vector3(0.3, 3.0, 0.3)
			city.add_solid(xf * Transform3D(Basis.IDENTITY, Vector3(0, solid.y * 0.5, 0)), solid)
			var ext: Vector2 = Vector2(foot.y, foot.x) if absf(sin(yaw)) > 0.5 else foot
			city.add_rect(Rect2(p - ext * 0.5, ext))
			n += 1
	if not g.empty():
		var mi: MeshInstance3D = CityKit.mesh_node("Street", g, look.material(false), 240.0)
		city.add_child(mi)
	return n


## A market stall: a steel frame, a striped canopy in the city's awning colours, a counter and
## crates of goods.
static func _stall(g: BuildingDetail.Geo, xf: Transform3D, look: CityLook, rng: RandomNumberGenerator) -> void:
	var col: Color = look.awnings[rng.randi() % look.awnings.size()]
	g.uv = Vector2.ZERO
	g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
	for sx: float in [-1.4, 1.4]:
		for sz: float in [-0.9, 0.9]:
			g.box(xf * Transform3D(Basis.IDENTITY, Vector3(sx, 1.2 if sz > 0.0 else 1.35, sz)), Vector3(0.06, 2.4 if sz > 0.0 else 2.7, 0.06))
	# The canopy: a sloped striped sheet with a scalloped front valance.
	g.mat(BuildingDetail.K_FLAT, col, 0, BuildingDetail.F_STRIPES)
	g.box(xf * Transform3D(Basis(Vector3.RIGHT, 0.16), Vector3(0, 2.6, 0.05)), Vector3(3.2, 0.05, 2.3))
	g.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 2.28, 1.18)), Vector3(3.2, 0.28, 0.03))
	# Counter and goods.
	g.mat(BuildingDetail.K_FLAT, BuildingDetail.WOOD.lightened(0.15))
	g.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.45, 0.5)), Vector3(2.8, 0.9, 0.8))
	g.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.55, -0.55)), Vector3(2.6, 1.1, 0.5))
	for k: int in 4:
		g.mat(BuildingDetail.K_FLAT, look.signs[rng.randi() % look.signs.size()])
		g.box(xf * Transform3D(Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)), Vector3(-1.05 + k * 0.7, 1.02, 0.5)), Vector3(0.56, 0.24, 0.5))


## One to three shipping containers stacked along the street, each its own colour, with door
## bars on one end and a pale number panel. Returns the stack's height.
static func _containers(g: BuildingDetail.Geo, xf: Transform3D, look: CityLook, rng: RandomNumberGenerator) -> float:
	var n: int = 1 + rng.randi() % 3
	var size := Vector3(2.44, 2.59, 6.06)
	for i: int in n:
		var col: Color = look.signs[rng.randi() % look.signs.size()]
		var bx: Transform3D = xf * Transform3D(Basis(Vector3.UP, rng.randf_range(-0.05, 0.05) * float(i)), Vector3(0, size.y * (float(i) + 0.5), 0))
		g.mat(BuildingDetail.K_METAL, col, 0, BuildingDetail.F_RUST)
		g.box(bx, size, -1, true)
		g.mat(BuildingDetail.K_METAL, col.darkened(0.35))
		for sx: float in [-0.6, 0.0, 0.6]:
			g.box(bx * Transform3D(Basis.IDENTITY, Vector3(sx, 0, size.z * 0.5 + 0.03)), Vector3(0.07, size.y - 0.3, 0.05))
		for sz: float in [-2.0, -1.0, 0.0, 1.0, 2.0]:
			for sx2: float in [-1.0, 1.0]:
				g.box(bx * Transform3D(Basis.IDENTITY, Vector3(sx2 * (size.x * 0.5 + 0.02), 0, sz)), Vector3(0.04, size.y - 0.2, 0.12))
		g.mat(BuildingDetail.K_FLAT, Color(0.96, 0.95, 0.9))
		for sx3: float in [-1.0, 1.0]:
			g.box(bx * Transform3D(Basis.IDENTITY, Vector3(sx3 * (size.x * 0.5 + 0.03), 0.6, -1.9)), Vector3(0.03, 0.5, 1.3))
	return size.y * float(n)


## Crushed cars stacked flat, a whole shell on top: bright car paint, dark glass, bare rims.
## Returns the stack's height.
static func _car_stack(g: BuildingDetail.Geo, xf: Transform3D, rng: RandomNumberGenerator) -> float:
	var n: int = 2 + rng.randi() % 3
	var y: float = 0.0
	for i: int in n:
		var bx: Transform3D = xf * Transform3D(Basis(Vector3.UP, rng.randf_range(-0.12, 0.12)), Vector3(rng.randf_range(-0.1, 0.1), y + 0.3, 0))
		g.mat(BuildingDetail.K_METAL, CAR_PAINT[rng.randi() % CAR_PAINT.size()], 0, BuildingDetail.F_RUST)
		g.box(bx, Vector3(1.8, 0.56, 4.2), -1, true)
		g.mat(BuildingDetail.K_DARK, Color(0.05, 0.06, 0.08))
		g.box(bx * Transform3D(Basis.IDENTITY, Vector3(0, 0.0, 0.2)), Vector3(1.84, 0.2, 1.9))
		y += 0.6
	var top: Transform3D = xf * Transform3D(Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)), Vector3(0, y, 0))
	var paint: Color = CAR_PAINT[rng.randi() % CAR_PAINT.size()]
	g.mat(BuildingDetail.K_METAL, paint, 0, BuildingDetail.F_RUST)
	g.box(top * Transform3D(Basis.IDENTITY, Vector3(0, 0.55, 0)), Vector3(1.75, 0.6, 4.1), -1, true)
	g.box(top * Transform3D(Basis.IDENTITY, Vector3(0, 1.08, -0.2)), Vector3(1.6, 0.5, 2.1))
	g.mat(BuildingDetail.K_DARK, Color(0.06, 0.08, 0.1))
	g.box(top * Transform3D(Basis.IDENTITY, Vector3(0, 1.08, -0.2)), Vector3(1.64, 0.36, 1.8))
	g.box(top * Transform3D(Basis.IDENTITY, Vector3(0, 1.08, -0.2)), Vector3(1.4, 0.36, 2.14))
	g.mat(BuildingDetail.K_METAL, Color(0.6, 0.6, 0.62))
	for sx: float in [-0.9, 0.9]:
		for sz: float in [-1.3, 1.3]:
			g.cyl(top * Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(sx, 0.3, sz)), 0.3, 0.3, 0.14, 8)
	return y + 1.35


## A run of white picket fence along the back of the sidewalk, with a painted letter box on a post
## at its end.
static func _fence(g: BuildingDetail.Geo, xf: Transform3D, look: CityLook, rng: RandomNumberGenerator, side: float) -> void:
	var run: float = 5.0
	g.mat(BuildingDetail.K_FLAT, FENCE_WHITE)
	for y: float in [0.35, 0.75]:
		g.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, y, 0)), Vector3(0.04, 0.08, run))
	var pickets: int = 16
	for i: int in pickets:
		var z: float = -run * 0.5 + (float(i) + 0.5) * run / float(pickets)
		g.box(xf * Transform3D(Basis.IDENTITY, Vector3(0.03 * side, 0.5, z)), Vector3(0.03, 1.0 if i % 4 != 0 else 1.12, 0.11))
	g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
	g.box(xf * Transform3D(Basis.IDENTITY, Vector3(-0.5 * side, 0.55, run * 0.5 - 0.3)), Vector3(0.07, 1.1, 0.07))
	g.mat(BuildingDetail.K_FLAT, look.signs[rng.randi() % look.signs.size()])
	g.box(xf * Transform3D(Basis.IDENTITY, Vector3(-0.5 * side, 1.2, run * 0.5 - 0.3)), Vector3(0.24, 0.24, 0.42))


## A banner pole at the kerb: a dark pole with a gilt ball, an arm and a long banner in the
## city's sign colours with a pale band.
static func _banner(g: BuildingDetail.Geo, xf: Transform3D, look: CityLook, rng: RandomNumberGenerator, side: float) -> void:
	g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
	g.cyl(xf * Transform3D(Basis.IDENTITY, Vector3(0, 3.6, 0)), 0.05, 0.08, 7.2, 8)
	g.box(xf * Transform3D(Basis.IDENTITY, Vector3(-0.6 * side, 6.7, 0)), Vector3(1.2, 0.05, 0.05))
	g.mat(BuildingDetail.K_FLAT, Color(0.92, 0.72, 0.16))
	g.cyl(xf * Transform3D(Basis.IDENTITY, Vector3(0, 7.3, 0)), 0.12, 0.12, 0.2, 8)
	var col: Color = look.signs[rng.randi() % look.signs.size()]
	g.mat(BuildingDetail.K_FLAT, col)
	g.box(xf * Transform3D(Basis.IDENTITY, Vector3(-0.65 * side, 4.7, 0)), Vector3(0.95, 3.9, 0.03), -1, true)
	g.mat(BuildingDetail.K_FLAT, Color(0.96, 0.9, 0.7))
	g.box(xf * Transform3D(Basis.IDENTITY, Vector3(-0.65 * side, 5.6, 0)), Vector3(0.97, 0.5, 0.05))
	g.box(xf * Transform3D(Basis.IDENTITY, Vector3(-0.65 * side, 3.1, 0)), Vector3(0.97, 0.16, 0.05))
