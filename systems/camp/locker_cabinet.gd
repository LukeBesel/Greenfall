class_name LockerCabinet
extends Node3D
## The Locker as a place (design spec section 13): a tall salvaged steel locker in the yard with
## a small turntable beside it (systems/camp/locker_stage.gd). It is a yard build, offered once
## the first piece of a look has been found (the planet's yard table: builds.locker). Walk up and
## press E: Lumi steps onto the turntable and the Locker panel opens (ui/locker_panel.gd). It is
## the only place looks are edited: Lumi's, Glim's and the crew's. Nothing stands in the yard and
## there is no way in before it is built.

const REACH: float = 2.2
const POS := Vector3(-6.4, 0.0, 4.6)

## Where the turntable stands when the yard table does not say (builds.locker.turntable), in the
## cabinet's own frame: x along its face, z out from its doors.
const STAGE_POS := Vector2(-3.0, 0.3)
const USED_STAT: String = "locker_opened"
## Save flag the goal chain reads: the Locker stands.
const BUILT_FLAG: String = "locker_built"

var world: Node
var stage: LockerStage
var _anchor: Node3D
var _overlay: CanvasLayer


static func is_built() -> bool:
	return YardBuilds.built("locker")


func setup(p_world: Node) -> void:
	world = p_world
	name = "LockerCabinet"
	_build_mesh()
	stage = LockerStage.new()
	stage.name = "LockerStage"
	var at: Array = YardBuilds.def("locker").get("turntable", [])
	stage.position = Vector3(float(at[0]), 0.0, float(at[1])) if at.size() >= 2 else Vector3(STAGE_POS.x, 0.0, STAGE_POS.y)
	add_child(stage)
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
	if visible:
		GameState.flags[BUILT_FLAG] = true
	if DevHooks.has("open-locker"):  # [ui7] screenshots: --open-locker=bots [--locker-design]
		YardBuilds.mark_built("locker")
		visible = true
		get_tree().create_timer(DevHooks.get_f("open-locker-at", 6.0)).timeout.connect(_dev_open)
	YardBuilds.events.built.connect(_on_built)  # a method: the static signal drops it when we're freed


func _on_built(id: String) -> void:
	if id == "locker":
		visible = true
		GameState.flags[BUILT_FLAG] = true


## [yard] A chunky two-door kit locker (systems/camp/yard_art.gd YardArt.locker): plinth, teal
## shell, cream louvred doors, a helmet rack and a thin cyan status seam. It only shows once built,
## so it is always powered.
func _build_mesh() -> void:
	var m: MeshInstance3D = YardArt.locker().mi(0.12, "LockerBody")
	add_child(m)
	YardArt.set_powered(m, true)
	YardArt.solid(self, Vector3(1.3, 2.2, 0.75), Vector3(0, 1.1, 0), "LockerSolid")


## Opens the Locker: Lumi onto the turntable, the panel over the game (Esc / B or Close shuts it).
func open() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return
	stage.begin(world, LumiStyle.current())
	GameState.inc_stat(USED_STAT)
	_overlay = LockerPanel.open_overlay(world, stage)
	_overlay.tree_exited.connect(_on_overlay_closed)


func _on_overlay_closed() -> void:
	_overlay = null
	if stage and is_instance_valid(stage):
		stage.end()


## Dev: opens the Locker on a section (--open-locker=lumi|bots|rocket; --open-locker-slot=ID picks
## the slot shown on Lumi's page); --locker-design paints
## the Scoopie design (treads, a top hat, mint glow, neon underglow) so the shot shows one applied.
func _dev_open() -> void:
	var sec: String = DevHooks.get_s("open-locker", "bots")
	if DevHooks.has("locker-design"):
		var fl: Fleet = world.get("fleet") as Fleet
		for id: String in ["treads", "top_hat"]:
			RobotBuilder.add_part(id)
		if not ("livery_neon" in Contracts.owned()):
			Contracts.owned().append("livery_neon")
		RobotDesign.set_part(fl, "scoopie", "mobility", "treads")
		RobotDesign.set_part(fl, "scoopie", "topper", "top_hat")
		RobotDesign.set_field(fl, "scoopie", "glow", "mint")
		RobotDesign.set_field(fl, "scoopie", "livery", "livery_neon")
	open()
	if _overlay:
		for n: Node in _overlay.find_children("*", "", true, false):
			if n is LockerPanel:
				(n as LockerPanel).set_editing("target:" + sec if sec in ["lumi", "glim"] else sec)
			elif n is LumiBuilder and DevHooks.has("open-locker-slot"):
				(n as LumiBuilder).select_slot(DevHooks.get_s("open-locker-slot", ""))
