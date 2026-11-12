class_name FieldBenchModel
extends Node3D
## A field bench at a city's base (systems/camp/field_benches.gd): a smaller salvaged workbench
## under a tarp, painted in the city's own colours (data "field_bench" looks), fresh paint over
## honest wear, lit when it is set up. Before that it stands packed: a strapped crate with the
## folded legs and the rolled tarp on top and a pennant on a pole, so the kit reads from across
## the yard. Local frame: origin on the ground, the bench along X, its working side facing +Z.
## set_ready(on, animate) switches the two (the set-up moment: dust, a chime, the light comes on).

const SIZE := Vector3(1.7, 0.95, 0.72)
## The bench's solid box (Lumi and robots stop at it).
const SOLID := Vector3(1.8, 1.0, 0.8)
const KIT_SOLID := Vector3(1.2, 0.8, 0.8)
## The tarp slopes down toward the working side (degrees about X; positive lowers +Z).
const TARP_TILT_DEG: float = 13.0

var look: Dictionary[String, Color] = {}
var _bench: Node3D
var _kit: Node3D
var _bench_body: StaticBody3D
var _kit_body: StaticBody3D


## Builds both states for the colours `p_look` ({frame, panel, canopy, trim}).
func build(p_look: Dictionary[String, Color]) -> void:
	look = p_look
	_bench = Node3D.new()
	_bench.name = "Bench"
	add_child(_bench)
	_bench.add_child(_bench_kit().mi(0.3, "BenchMesh"))
	_bench_body = YardArt.solid(_bench, SOLID, Vector3(0, SOLID.y * 0.5, -0.05), "BenchSolid")
	_kit = Node3D.new()
	_kit.name = "Kit"
	add_child(_kit)
	_kit.add_child(_packed_kit().mi(0.3, "KitMesh"))
	_kit_body = YardArt.solid(_kit, KIT_SOLID, Vector3(0, KIT_SOLID.y * 0.5, 0), "KitSolid")


## Shows the bench set up (true) or packed (false). animate: the set-up moment.
func set_ready(on: bool, animate: bool) -> void:
	if _bench == null:
		return
	_bench.visible = on
	_kit.visible = not on
	_set_solid(_bench_body, on)
	_set_solid(_kit_body, not on)
	YardArt.set_powered(_bench, on)
	YardArt.set_powered(_kit, not on)
	if not animate or not is_inside_tree():
		return
	var up: Vector3 = global_basis.y.normalized()
	Vfx.burst("dust", global_position + up * 0.3, Color(0.85, 0.78, 0.65), 0.6)
	Vfx.burst("big_sparkle", global_position + up * 1.4, Color(0.5, 0.9, 1.0))
	_bench.scale = Vector3(1.0, 0.05, 1.0)
	create_tween().tween_property(_bench, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	YardArt.flicker_on(self, _bench, 0.5)


static func _set_solid(body: StaticBody3D, on: bool) -> void:
	for c: Node in body.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred("disabled", not on)


## The working bench: painted legs and rails, a timber top with a steel wear plate, a drawer
## cabinet, a pegboard with tools and a small cyan screen (Lumi's link), parts bins, a crate of
## salvage beside it and a tarp on two poles over it.
func _bench_kit() -> YardArt.Kit:
	var k := YardArt.Kit.new()
	var frame: Color = look.get("frame", YardArt.TEAL)
	var panel: Color = look.get("panel", YardArt.CREAM)
	var canopy: Color = look.get("canopy", YardArt.ORANGE)
	var trim: Color = look.get("trim", YardArt.YELLOW)
	var hx: float = SIZE.x * 0.5
	var hz: float = SIZE.z * 0.5
	k.box(Vector3(SIZE.x, 0.07, SIZE.z), Vector3(0, 0.9, 0), YardArt.WOOD, Vector3.ZERO, 0.02)
	k.box(Vector3(SIZE.x + 0.04, 0.06, 0.04), Vector3(0, 0.88, hz + 0.01), YardArt.STEEL)
	k.box(Vector3(0.6, 0.012, 0.42), Vector3(0.3, 0.94, 0.05), YardArt.STEEL, Vector3.ZERO, 0.004)
	k.bolts4(Vector3(0.3, 0.946, 0.05), Vector3(0.27, 0, 0), Vector3(0, 0, 0.18), Vector3.UP, YardArt.GUNMETAL, 0.012)
	for x: float in [-hx + 0.06, hx - 0.06]:
		for z: float in [-hz + 0.06, hz - 0.06]:
			k.box(Vector3(0.08, 0.86, 0.08), Vector3(x, 0.43, z), frame)
			k.box(Vector3(0.14, 0.04, 0.14), Vector3(x, 0.02, z), YardArt.RUBBER)
			k.bolt(Vector3(x, 0.78, z + 0.045 * signf(z)), Vector3(0, 0, signf(z)))
	k.box(Vector3(SIZE.x - 0.12, 0.1, 0.05), Vector3(0, 0.8, hz - 0.06), frame)
	k.hazard(Vector3(SIZE.x - 0.2, 0.05, 0.02), Vector3(0, 0.8, hz - 0.03), Vector3.ZERO, trim)
	k.box(Vector3(SIZE.x - 0.12, 0.04, SIZE.z - 0.1), Vector3(0, 0.24, 0), frame.darkened(0.25))
	# Drawer cabinet on the left.
	k.box(Vector3(0.5, 0.5, SIZE.z - 0.12), Vector3(-hx + 0.34, 0.55, 0), panel)
	for y: float in [0.42, 0.68]:
		k.box(Vector3(0.44, 0.17, 0.03), Vector3(-hx + 0.34, y, hz - 0.05), panel.lightened(0.12))
		k.box(Vector3(0.18, 0.025, 0.035), Vector3(-hx + 0.34, y + 0.03, hz - 0.03), YardArt.STEEL, Vector3.ZERO, 0.008)
	# On the top: a vice, a toolbox in the trim colour, a mug, a coil of wire.
	k.box(Vector3(0.18, 0.1, 0.16), Vector3(hx - 0.2, 0.98, 0.2), YardArt.GUNMETAL)
	k.box(Vector3(0.18, 0.11, 0.04), Vector3(hx - 0.2, 1.04, 0.3), frame)
	k.cyl(0.02, 0.24, Vector3(hx - 0.2, 1.03, 0.38), YardArt.STEEL, Vector3(90, 0, 0), 0.004, 8)
	k.box(Vector3(0.44, 0.18, 0.22), Vector3(-0.35, 1.03, -0.1), trim, Vector3(0, 7, 0))
	k.box(Vector3(0.46, 0.04, 0.24), Vector3(-0.35, 1.13, -0.1), trim.darkened(0.15), Vector3(0, 7, 0))
	k.box(Vector3(0.18, 0.02, 0.03), Vector3(-0.35, 1.16, -0.1), YardArt.STEEL, Vector3(0, 7, 0), 0.006)
	k.cyl(0.042, 0.1, Vector3(0.05, 0.99, 0.18), YardArt.CREAM, Vector3.ZERO, 0.01, 12)
	k.cyl(0.08, 0.05, Vector3(0.62, 0.96, -0.18), YardArt.ORANGE, Vector3.ZERO, 0.012, 14)
	k.cyl(0.045, 0.055, Vector3(0.62, 0.96, -0.18), YardArt.DARK, Vector3.ZERO, 0.008, 10)
	# Pegboard on the back legs, with tools, parts bins and Lumi's little link screen.
	for x2: float in [-hx + 0.06, hx - 0.06]:
		k.box(Vector3(0.07, 0.8, 0.07), Vector3(x2, 1.3, -hz + 0.06), frame)
	k.box(Vector3(SIZE.x - 0.14, 0.56, 0.035), Vector3(0, 1.28, -hz + 0.05), panel.darkened(0.08))
	for i: int in 7:
		for j: int in 3:
			k.box(Vector3(0.022, 0.022, 0.01), Vector3(-0.66 + i * 0.22, 1.1 + j * 0.17, -hz + 0.07), YardArt.DARK, Vector3.ZERO, 0.004)
	k.box(Vector3(0.045, 0.32, 0.02), Vector3(-0.42, 1.3, -hz + 0.08), YardArt.STEEL, Vector3(0, 0, 16), 0.008)
	k.box(Vector3(0.04, 0.28, 0.03), Vector3(-0.18, 1.28, -hz + 0.08), YardArt.WOOD, Vector3.ZERO, 0.01)
	k.box(Vector3(0.15, 0.055, 0.05), Vector3(-0.18, 1.43, -hz + 0.085), YardArt.GUNMETAL, Vector3.ZERO, 0.012)
	for i2: int in 3:
		k.box(Vector3(0.16, 0.09, 0.11), Vector3(0.05 + i2 * 0.18, 1.07, -hz + 0.12), [trim, YardArt.BLUE, YardArt.RED][i2], Vector3.ZERO, 0.014)
	k.box(Vector3(0.36, 0.26, 0.09), Vector3(0.5, 1.42, -hz + 0.11), YardArt.CREAM)
	k.glow_box(Vector3(0.29, 0.19, 0.02), Vector3(0.5, 1.42, -hz + 0.165), YardArt.CYAN)
	k.box(Vector3(SIZE.x + 0.04, 0.035, 0.18), Vector3(0, 1.6, -hz + 0.1), frame)
	# Salvage crate on the floor at the right end and a cable reel under the top.
	k.box(Vector3(0.5, 0.36, 0.42), Vector3(hx + 0.34, 0.18, 0.08), trim.darkened(0.1), Vector3(0, -6, 0))
	k.box(Vector3(0.52, 0.04, 0.44), Vector3(hx + 0.34, 0.37, 0.08), trim.darkened(0.3), Vector3(0, -6, 0))
	k.cyl(0.05, 0.12, Vector3(hx + 0.26, 0.45, 0.12), YardArt.STEEL, Vector3(0, 0, 80), 0.01, 10)
	k.box(Vector3(0.16, 0.1, 0.1), Vector3(hx + 0.44, 0.44, 0.02), YardArt.RED, Vector3(0, 20, 0), 0.012)
	k.cyl(0.16, 0.16, Vector3(0.35, 0.36, 0.0), YardArt.TEAL, Vector3(90, 0, 0), 0.015, 14)
	k.cyl(0.06, 0.2, Vector3(0.35, 0.36, 0.0), YardArt.GUNMETAL, Vector3(90, 0, 0), 0.008, 10)
	_canopy(k, frame, canopy, hx, hz)
	k.light(Vector3(0.2, 1.75, 0.1), YardArt.WARM, 0.8, 2.6)
	return k


## Two poles behind the bench hold a tarp sloping forward over it, edged and tied off.
func _canopy(k: YardArt.Kit, frame: Color, canopy: Color, hx: float, hz: float) -> void:
	var back_z: float = -hz - 0.12
	for x: float in [-hx - 0.05, hx + 0.05]:
		k.cyl(0.035, 2.45, Vector3(x, 1.225, back_z), frame, Vector3.ZERO, 0.008, 10)
		k.cyl(0.07, 0.05, Vector3(x, 0.025, back_z), YardArt.GUNMETAL, Vector3.ZERO, 0.01, 10)
		k.pipe(Vector3(x, 2.38, back_z), Vector3(x, 2.05, hz + 0.45), 0.022, frame, false)
	var mid_z: float = (back_z + hz + 0.45) * 0.5
	k.push(ProcMesh.xf(Vector3(0, 2.25, mid_z), Vector3(TARP_TILT_DEG, 0, 0)))
	k.box(Vector3(SIZE.x + 0.4, 0.04, 1.6), Vector3.ZERO, canopy, Vector3.ZERO, 0.01)
	for i: int in 4:  # sewn seams, a shade lighter
		k.box(Vector3(0.06, 0.044, 1.58), Vector3(lerpf(-hx, hx, float(i) / 3.0), 0.0, 0.0), canopy.lightened(0.2), Vector3.ZERO, 0.006)
	k.box(Vector3(SIZE.x + 0.42, 0.14, 0.04), Vector3(0, -0.06, 0.8), canopy.darkened(0.15), Vector3.ZERO, 0.01)  # the hanging front flap
	k.pop()
	k.cable([Vector3(-hx - 0.05, 2.1, hz + 0.45), Vector3(-hx - 0.3, 1.0, hz + 0.7), Vector3(-hx - 0.45, 0.02, hz + 0.95)], 0.008, YardArt.CREAM)
	k.cable([Vector3(hx + 0.05, 2.1, hz + 0.45), Vector3(hx + 0.3, 1.0, hz + 0.7), Vector3(hx + 0.45, 0.02, hz + 0.95)], 0.008, YardArt.CREAM)


## The packed kit: a strapped crate with the bench's folded legs and the rolled tarp on top, a
## stencilled band in the trim colour and a pennant pole with a small cyan beacon.
func _packed_kit() -> YardArt.Kit:
	var k := YardArt.Kit.new()
	var frame: Color = look.get("frame", YardArt.TEAL)
	var canopy: Color = look.get("canopy", YardArt.ORANGE)
	var trim: Color = look.get("trim", YardArt.YELLOW)
	k.box(Vector3(1.1, 0.62, 0.7), Vector3(0, 0.33, 0), YardArt.WOOD, Vector3.ZERO, 0.02)
	for x: float in [-0.5, 0.5]:
		k.box(Vector3(0.08, 0.66, 0.74), Vector3(x, 0.33, 0), YardArt.WOOD.darkened(0.2), Vector3.ZERO, 0.01)
	k.box(Vector3(1.12, 0.14, 0.72), Vector3(0, 0.42, 0), trim, Vector3.ZERO, 0.01)
	k.decal("chevrons", Vector2(0.34, 0.12), Vector3(0, 0.42, 0.365))
	for x2: float in [-0.28, 0.28]:
		k.box(Vector3(0.05, 0.68, 0.76), Vector3(x2, 0.34, 0), YardArt.RUBBER, Vector3.ZERO, 0.005)
	for i: int in 4:
		k.box(Vector3(0.07, 0.07, 1.0), Vector3(-0.3 + i * 0.2, 0.7, 0), frame, Vector3(0, 90, 0), 0.01)
	k.cyl(0.13, 1.0, Vector3(0, 0.88, 0.05), canopy, Vector3(0, 0, 90), 0.02, 14)
	k.box(Vector3(0.6, 0.18, 0.4), Vector3(0.0, 0.1, 0.62), trim.darkened(0.15), Vector3(0, 12, 0))
	k.cyl(0.03, 2.2, Vector3(0.62, 1.1, -0.3), frame, Vector3.ZERO, 0.006, 8)
	k.box(Vector3(0.5, 0.3, 0.012), Vector3(0.88, 1.98, -0.3), canopy, Vector3.ZERO, 0.004)
	k.glow_cyl(0.045, 0.07, Vector3(0.62, 2.24, -0.3), YardArt.CYAN)
	k.light(Vector3(0.62, 2.3, -0.3), YardArt.CYAN, 0.5, 2.0)
	return k
