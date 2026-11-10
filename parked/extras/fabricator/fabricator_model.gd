class_name FabricatorModel
extends Node3D
## [yard] The Bot Fabricator's 3D model (logic: robots/fabricator/bot_fabricator.gd, orbC). A kit
## robot assembly bay: platform with hazard edges, cream bay walls under a gantry, a jointed orange
## arm that works while a bot is being built, an out-conveyor with rollers, a console, parts bins
## and pipes. The bay pad and its light glow only while building; the console is lit once built.
## Use: var m := FabricatorModel.new(); parent.add_child(m); m.set_building(fab.queue().size() > 0)
## Origin on the ground, about 4.4 x 3.2 m footprint (+ the conveyor out to z 3.0), front +Z.

var building: bool = false
var _shell: MeshInstance3D
var _bay: MeshInstance3D
var _arm_base: Node3D
var _arm_upper: Node3D
var _arm_fore: Node3D
var _t: float = 0.0


func _ready() -> void:
	name = "FabricatorModel" if name == "" else name
	_shell = YardArt.fabricator_shell().mi(0.12, "Shell")
	add_child(_shell)
	YardArt.set_powered(_shell, true)
	_bay = YardArt.fabricator_bay().mi(0.12, "Bay")
	add_child(_bay)
	YardArt.set_powered(_bay, building)
	# The arm: base turret -> upper arm -> forearm with a gripper (each its own node to animate).
	_arm_base = Node3D.new()
	_arm_base.position = Vector3(1.0, 0.24, -0.5)
	add_child(_arm_base)
	_arm_base.add_child(YardArt.arm_part("base").mi(0.12))
	_arm_upper = Node3D.new()
	_arm_upper.position = Vector3(0, 0.42, 0)
	_arm_base.add_child(_arm_upper)
	_arm_upper.add_child(YardArt.arm_part("upper").mi(0.12))
	_arm_fore = Node3D.new()
	_arm_fore.position = Vector3(0, 0.9, 0)
	_arm_upper.add_child(_arm_fore)
	_arm_fore.add_child(YardArt.arm_part("fore").mi(0.12))
	_pose(0.0)
	YardArt.solid(self, Vector3(4.4, 2.8, 3.2), Vector3(0, 1.4, -0.3), "FabricatorSolid")


## Building a bot: the bay pad glows, the bay light comes on and the arm works.
func set_building(on: bool) -> void:
	if on == building:
		return
	building = on
	if _bay:
		YardArt.set_powered(_bay, on)


func _pose(t: float) -> void:
	var w: float = 1.0 if building else 0.0
	_arm_base.rotation.y = 0.9 + sin(t * 0.9) * 0.6 * w
	_arm_upper.rotation.z = 0.35 + sin(t * 1.7) * 0.25 * w
	_arm_fore.rotation.z = 0.9 + sin(t * 2.3 + 1.0) * 0.35 * w


func _process(delta: float) -> void:
	if not building or _arm_base == null:
		return
	_t += delta
	_pose(_t)
	if fmod(_t, 1.3) < delta:
		Vfx.burst("sparkle", to_global(Vector3(0, 0.9, -0.3)), Color(1.0, 0.8, 0.45), 0.25)
