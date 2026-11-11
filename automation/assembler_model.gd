class_name AssemblerModel
extends Node3D
## The Assembler's building (logic: systems/crew/robot_chain.gd): an old factory line standing
## again. A concrete pad with hazard edges, cream bay walls under a tin roof and a yellow gantry, a
## jointed orange arm that works while a robot is on the line, the door's out-conveyor at the
## front (robots roll out here), a loading bay of parts bins on the left (Scroungers' parts go in
## here), a console on the right and a stack at the back. The bay pad and its lights glow only
## while a robot is being built.
## Origin on the ground, about 4.6 x 3.4 m (the conveyor reaches z 3.0), front +Z.
## Use: var m := AssemblerModel.new(); parent.add_child(m); m.set_building(true)

## Where a finished robot is set down (local): the end of the out-conveyor.
const DOOR_LOCAL := Vector3(0.0, 0.0, 3.6)
## Radius the crew's routes keep clear of (metres).
const FOOTPRINT_R: float = 2.9
const WEAR: float = 0.22
const SPARK_EVERY_S: float = 1.3

var building: bool = false
var _bay: MeshInstance3D
var _arm_base: Node3D
var _arm_upper: Node3D
var _arm_fore: Node3D
var _t: float = 0.0


func _ready() -> void:
	var shell: MeshInstance3D = _shell().mi(WEAR, "Shell")
	add_child(shell)
	YardArt.set_powered(shell, true)
	_bay = _bay_kit().mi(WEAR, "Bay")
	add_child(_bay)
	YardArt.set_powered(_bay, building)
	# The arm: base turret, upper arm, forearm with a gripper, each its own node to animate.
	_arm_base = Node3D.new()
	_arm_base.position = Vector3(1.0, 0.24, -0.5)
	add_child(_arm_base)
	_arm_base.add_child(_arm("base").mi(WEAR))
	_arm_upper = Node3D.new()
	_arm_upper.position = Vector3(0, 0.42, 0)
	_arm_base.add_child(_arm_upper)
	_arm_upper.add_child(_arm("upper").mi(WEAR))
	_arm_fore = Node3D.new()
	_arm_fore.position = Vector3(0, 0.9, 0)
	_arm_upper.add_child(_arm_fore)
	_arm_fore.add_child(_arm("fore").mi(WEAR))
	_pose(0.0)
	YardArt.solid(self, Vector3(4.4, 2.8, 3.2), Vector3(0, 1.4, -0.3), "AssemblerSolid")


func _process(delta: float) -> void:
	if not building or _arm_base == null:
		return
	_t += delta
	_pose(_t)
	if fmod(_t, SPARK_EVERY_S) < delta:
		Vfx.burst("sparkle", to_global(Vector3(0, 0.9, -0.3)), Color(1.0, 0.8, 0.45), 0.25)


## A robot is on the line: the bay pad glows, the bay lights come on and the arm works.
func set_building(on: bool) -> void:
	if on == building:
		return
	building = on
	if _bay:
		YardArt.set_powered(_bay, on)


## World position where a finished robot rolls out.
func door_position() -> Vector3:
	return to_global(DOOR_LOCAL)


func _pose(t: float) -> void:
	var w: float = 1.0 if building else 0.0
	_arm_base.rotation.y = 0.9 + sin(t * 0.9) * 0.6 * w
	_arm_upper.rotation.z = 0.35 + sin(t * 1.7) * 0.25 * w
	_arm_fore.rotation.z = 0.9 + sin(t * 2.3 + 1.0) * 0.35 * w


static func _shell() -> YardArt.Kit:
	var k := YardArt.Kit.new()
	k.box(Vector3(4.6, 0.22, 3.4), Vector3(0, 0.11, -0.3), Color.WHITE, Vector3.ZERO, 0.05, "concrete")
	k.hazard(Vector3(4.62, 0.06, 3.42), Vector3(0, 0.2, -0.3))
	k.box(Vector3(2.4, 0.04, 2.2), Vector3(0, 0.24, -0.4), YardArt.GUNMETAL, Vector3.ZERO, 0.015)  # bay floor
	for s: float in [-1.0, 1.0]:  # bay walls
		k.box(Vector3(0.3, 2.5, 2.4), Vector3(s * 1.45, 1.47, -0.4), YardArt.CREAM, Vector3.ZERO, 0.06)
		k.panel(1.9, 1.9, Vector3(s * 1.61, 1.45, -0.4), YardArt.CREAM.darkened(0.05), Vector3(0, s * 90.0, 0), Color(-1, 0, 0), 0.04)
		k.hazard(Vector3(0.32, 0.3, 0.06), Vector3(s * 1.45, 0.4, 0.82))
		k.box(Vector3(0.36, 0.1, 2.5), Vector3(s * 1.45, 2.75, -0.4), YardArt.TEAL, Vector3.ZERO, 0.03)
	k.box(Vector3(3.2, 2.5, 0.2), Vector3(0, 1.47, -1.6), YardArt.TEAL_D, Vector3.ZERO, 0.05)  # back wall
	for x: float in [-0.8, 0.0, 0.8]:
		k.box(Vector3(0.08, 2.3, 0.06), Vector3(x, 1.45, -1.48), YardArt.TEAL, Vector3.ZERO, 0.02)
	k.decal("logo", Vector2(0.7, 0.7), Vector3(-0.4, 1.9, -1.45))
	k.vent(0.6, 0.4, Vector3(0.45, 0.9, -1.48), YardArt.TEAL, Vector3.ZERO, 4)
	# Tin roof over the bay, pitched to the back, and the old stack behind it.
	k.box(Vector3(3.5, 0.06, 2.9), Vector3(0, 3.06, -0.45), YardArt.RED, Vector3(6, 0, 0), 0.02)
	for x: float in [-1.5, -0.75, 0.0, 0.75, 1.5]:
		k.box(Vector3(0.06, 0.05, 2.9), Vector3(x, 3.1, -0.45), YardArt.RED.darkened(0.15), Vector3(6, 0, 0), 0.01)
	k.pipe(Vector3(1.2, 2.4, -1.75), Vector3(1.2, 4.1, -1.75), 0.16, YardArt.GUNMETAL, true)
	k.cyl(0.2, 0.08, Vector3(1.2, 4.14, -1.75), YardArt.DARK, Vector3.ZERO, 0.02, 14)
	# Gantry over the bay: two rails and a trolley with a hoist.
	for z: float in [-1.3, 0.6]:
		k.box(Vector3(3.2, 0.16, 0.16), Vector3(0, 2.86, z), YardArt.YELLOW, Vector3.ZERO, 0.03)
	k.box(Vector3(0.5, 0.18, 2.1), Vector3(-0.3, 2.86, -0.35), YardArt.GUNMETAL, Vector3.ZERO, 0.03)
	k.box(Vector3(0.3, 0.2, 0.3), Vector3(-0.3, 2.7, -0.4), YardArt.ORANGE, Vector3.ZERO, 0.04)
	k.pipe(Vector3(-0.3, 2.6, -0.4), Vector3(-0.3, 2.0, -0.4), 0.015, YardArt.STEEL, false)
	k.box(Vector3(0.24, 0.06, 0.24), Vector3(-0.3, 1.97, -0.4), YardArt.GUNMETAL, Vector3.ZERO, 0.015)
	# Status beacon on the front corner.
	k.cyl(0.12, 0.1, Vector3(1.45, 2.85, 0.7), YardArt.DARK, Vector3.ZERO, 0.02, 12)
	k.glow_cyl(0.09, 0.12, Vector3(1.45, 2.95, 0.7), YardArt.MINT, Vector3.ZERO, 12)
	_conveyor(k)
	_sides(k)
	return k


## The door: an out-conveyor from the bay mouth to the front.
static func _conveyor(k: YardArt.Kit) -> void:
	k.push(Transform3D(Basis(), Vector3(0, 0, 0.9)))
	for x: float in [-0.5, 0.5]:
		k.box(Vector3(0.1, 0.18, 2.2), Vector3(x, 0.42, 1.0), YardArt.YELLOW, Vector3.ZERO, 0.03)
		for z: float in [0.2, 1.8]:
			k.box(Vector3(0.08, 0.34, 0.08), Vector3(x, 0.17, z), YardArt.GUNMETAL)
	k.box(Vector3(0.9, 0.04, 2.2), Vector3(0, 0.48, 1.0), YardArt.RUBBER, Vector3.ZERO, 0.01)
	for i: int in 8:
		k.cyl(0.05, 0.92, Vector3(0, 0.44, 0.05 + i * 0.27), YardArt.STEEL, Vector3(0, 0, 90), 0.01, 10)
	k.decal("chevrons", Vector2(0.7, 0.24), Vector3(0, 0.505, 1.6), Vector3(-90, 0, 0))
	k.pop()


## Console on the right, the loading bay's parts bins on the left, pipes on the back.
static func _sides(k: YardArt.Kit) -> void:
	k.box(Vector3(0.6, 1.0, 0.5), Vector3(1.95, 0.72, 0.5), YardArt.CREAM, Vector3.ZERO, 0.04)
	k.box(Vector3(0.62, 0.3, 0.52), Vector3(1.95, 1.3, 0.42), YardArt.TEAL, Vector3(-25, 0, 0), 0.03)
	k.glow_box(Vector3(0.44, 0.2, 0.02), Vector3(1.95, 1.33, 0.67), YardArt.CYAN, Vector3(-25, 0, 0))
	for i: int in 3:
		k.glow_box(Vector3(0.04, 0.04, 0.02), Vector3(1.8 + i * 0.12, 0.95, 0.755), [YardArt.MINT, YardArt.AMBER, YardArt.MINT][i])
	for i: int in 3:
		for j: int in 2:
			k.box(Vector3(0.36, 0.22, 0.4), Vector3(-1.95, 0.36 + j * 0.24, 0.6 - i * 0.42),
				[YardArt.YELLOW, YardArt.BLUE, YardArt.RED][(i + j) % 3], Vector3.ZERO, 0.03)
	k.pipe(Vector3(-1.3, 0.25, -1.75), Vector3(-1.3, 2.4, -1.75), 0.07, YardArt.GUNMETAL, true)
	k.pipe(Vector3(-1.3, 2.4, -1.75), Vector3(1.3, 2.4, -1.75), 0.07, YardArt.GUNMETAL, true)
	k.cable([Vector3(1.95, 0.3, 0.25), Vector3(1.7, 0.25, -0.2), Vector3(1.3, 0.26, -0.6)], 0.025)


## The bay pad, its ring and lights: lit only while a robot is on the line.
static func _bay_kit() -> YardArt.Kit:
	var k := YardArt.Kit.new()
	k.cyl(0.7, 0.06, Vector3(-0.3, 0.29, -0.4), YardArt.GUNMETAL, Vector3.ZERO, 0.02, 24)
	for i: int in 20:  # a thin ring of lights round the pad, not a lit disc
		var a: float = TAU * i / 20.0
		k.glow_box(Vector3(0.12, 0.02, 0.035), Vector3(-0.3 + cos(a) * 0.62, 0.325, -0.4 + sin(a) * 0.62), YardArt.CYAN,
			Vector3(0, -rad_to_deg(a) + 90.0, 0))
	for s: float in [-1.0, 1.0]:
		k.glow_box(Vector3(0.03, 1.8, 0.03), Vector3(s * 1.28, 1.4, 0.75), YardArt.CYAN)
	k.light(Vector3(-0.3, 1.6, -0.2), YardArt.CYAN, 0.9, 3.5)
	return k


## The arm's parts (each on its own node): "base" turret, "upper" arm, "fore" arm.
static func _arm(part: String) -> YardArt.Kit:
	var k := YardArt.Kit.new()
	match part:
		"base":
			k.cyl(0.28, 0.12, Vector3(0, 0.06, 0), YardArt.GUNMETAL, Vector3.ZERO, 0.03, 16)
			k.cyl(0.2, 0.3, Vector3(0, 0.27, 0), YardArt.ORANGE, Vector3.ZERO, 0.04, 16)
			k.cyl(0.13, 0.26, Vector3(0, 0.42, 0), YardArt.DARK, Vector3(90, 0, 0), 0.03, 14)
		"upper":
			k.box(Vector3(0.16, 0.9, 0.16), Vector3(0, 0.45, 0), YardArt.ORANGE, Vector3.ZERO, 0.04)
			k.pipe(Vector3(0.1, 0.1, 0.06), Vector3(0.1, 0.8, 0.06), 0.02, YardArt.RUBBER, false)
			k.cyl(0.11, 0.22, Vector3(0, 0.9, 0), YardArt.DARK, Vector3(90, 0, 0), 0.03, 14)
		_:
			k.box(Vector3(0.13, 0.7, 0.13), Vector3(0, 0.35, 0), YardArt.ORANGE, Vector3.ZERO, 0.035)
			k.cyl(0.08, 0.1, Vector3(0, 0.74, 0), YardArt.GUNMETAL, Vector3.ZERO, 0.02, 12)
			for s: float in [-1.0, 1.0]:
				k.box(Vector3(0.03, 0.16, 0.06), Vector3(s * 0.06, 0.86, 0), YardArt.STEEL, Vector3(0, 0, s * -12.0), 0.01)
			k.glow_box(Vector3(0.03, 0.03, 0.02), Vector3(0, 0.6, 0.07), YardArt.WARM)
	return k
