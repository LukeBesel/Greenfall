extends Node3D
## Art check for the wrecks (systems/wreck_model.gd, systems/find_props.gd) on the turnaround
## stage, without loading the world. Left to right: a wreck of the first planet's design under
## its junk, the same wreck cleared, the same wreck salvaged (pieces gone, flowers up), and a
## ruined wreck of a later design (the tease). In front: a buried tin, a buried chip, and both
## dug up.
##   godot --path . --rendering-driver opengl3 res://scenes/turnaround.tscn -- --fresh \
##       --model=res://tools/wreck_lineup.gd --out=screenshots/finds/lineup
## --lineup-design=ID and --lineup-tease=ID pick the two designs (default sprout, bolt).

const GAP_M: float = 1.3
const JUNK: int = 3


func _ready() -> void:
	var design: String = DevHooks.get_s("lineup-design", "sprout")
	var tease: String = DevHooks.get_s("lineup-tease", "bolt")
	var taken: Array[String] = []
	for id: String in Looks.ids():
		var d: Dictionary = Looks.def(id)
		if str(d.get("set", "")) == design and str(d.get("slot", "")) in ["ears", "chest", "pattern"]:
			taken.append(id)
	_wreck(design, Vector3(-GAP_M * 1.5, 0, 0), false, [], JUNK)
	_wreck(design, Vector3(-GAP_M * 0.5, 0, 0), false, [], 0)
	_wreck(design, Vector3(GAP_M * 0.5, 0, 0), false, taken, 0)
	_wreck(tease, Vector3(GAP_M * 1.5, 0, 0), true, [], 0)
	var x: float = -1.2
	for kind: String in [FindProps.TIN, FindProps.CHIP]:
		var tint: Color = Color(0.25, 0.62, 0.95) if kind == FindProps.TIN else Color(0.45, 0.95, 0.7)
		var buried: Node3D = FindProps.cache(kind, tint)
		buried.position = Vector3(x, 0, -1.5)
		add_child(buried)
		var out: Node3D = FindProps.dug(kind, tint)
		out.position = Vector3(x + 0.6, 0, -1.5)
		add_child(out)
		x += 1.4


func _wreck(design: String, at: Vector3, ruined: bool, stripped: Array[String], junk: int) -> void:
	var holder := Node3D.new()
	holder.position = at
	add_child(holder)
	var m := WreckModel.new()
	m.design = design
	m.pose_seed = 7
	m.ruined = ruined
	m.stripped = stripped
	holder.add_child(m)
	for piece: Dictionary in FindProps.junk(11, junk):
		holder.add_child(piece["node"] as Node3D)
	if not stripped.is_empty():
		holder.add_child(FindProps.flowers(5, m.glow()))
