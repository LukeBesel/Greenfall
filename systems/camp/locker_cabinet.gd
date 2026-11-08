class_name LockerCabinet
extends Node3D
## [ui6] The Locker as a real build (owner: "The Locker is an actual locker build you unlock with
## parts"): a tall steel cabinet in the yard, bought once from the workbench Build tab
## (data/camp.json builds.locker, data/builds.json). Walk up and press E to open the character
## builder: Lumi's look, Glim's looks and the robots' styles (ui/locker_panel.gd). Nothing in the
## yard and no way in before it's built.

const REACH: float = 2.2
const POS := Vector3(-6.4, 0.0, 4.6)

var world: Node
var _anchor: Node3D
var _overlay: CanvasLayer


static func is_built() -> bool:
	return YardBuilds.built("locker")


func setup(p_world: Node) -> void:
	world = p_world
	name = "LockerCabinet"
	_build_mesh()
	position = YardBuilds.pos("locker", POS)
	rotation.y = deg_to_rad(float(YardBuilds.def("locker").get("yaw_deg", 90.0)))
	_anchor = Node3D.new()
	_anchor.name = "LockerReach"
	world.add_child(_anchor)
	_anchor.global_position = position + Basis(Vector3.UP, rotation.y) * Vector3(0, 0, 0.9)
	if world.get("interactables") != null:
		(world.interactables as Interactables).register(_anchor, REACH,
			func() -> String: return tr("E   open locker"),
			func() -> void: open(),
			func() -> bool: return visible)
	visible = is_built()
	YardBuilds.events.built.connect(_on_built)  # a method: the static signal drops it when we're freed


func _on_built(id: String) -> void:
	if id == "locker":
		visible = true


## A tall two-door steel cabinet with a thin cyan light seam and a small vent grille.
func _build_mesh() -> void:
	var body := MeshInstance3D.new()
	body.mesh = ProcMesh.box(Vector3(1.1, 2.0, 0.55))
	body.material_override = Mats.metal("dark_steel")
	body.position = Vector3(0, 1.0, 0)
	add_child(body)
	for side: float in [-0.275, 0.275]:
		var door := MeshInstance3D.new()
		door.mesh = ProcMesh.box(Vector3(0.52, 1.88, 0.04))
		door.material_override = Mats.metal("dark_steel")
		door.position = Vector3(side, 1.0, 0.29)
		add_child(door)
		var handle := MeshInstance3D.new()
		handle.mesh = ProcMesh.box(Vector3(0.03, 0.22, 0.04))
		handle.material_override = Mats.metal("chrome")
		handle.position = Vector3(side * 0.25, 1.05, 0.33)
		add_child(handle)
		for k: int in 4:
			var slot := MeshInstance3D.new()
			slot.mesh = ProcMesh.box(Vector3(0.3, 0.025, 0.01))
			slot.material_override = Mats.metal("chrome")
			slot.position = Vector3(side, 1.7 - k * 0.06, 0.315)
			add_child(slot)
	var seam := MeshInstance3D.new()
	seam.mesh = ProcMesh.box(Vector3(0.012, 1.8, 0.012))
	seam.material_override = Mats.lamp(Color(0.45, 0.88, 1.0), 1.4)
	seam.position = Vector3(0, 1.0, 0.315)
	add_child(seam)
	var top := MeshInstance3D.new()
	top.mesh = ProcMesh.box(Vector3(1.04, 0.012, 0.012))
	top.material_override = Mats.lamp(Color(0.45, 0.88, 1.0), 1.1)
	top.position = Vector3(0, 1.97, 0.3)
	add_child(top)


## Opens the Locker over the game (Esc / B or Close shuts it).
func open() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return
	_overlay = LockerPanel.open_overlay(world)
	_overlay.tree_exited.connect(func() -> void: _overlay = null)
