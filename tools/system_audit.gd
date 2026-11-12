extends Node
## [orbB] Which of the slice's systems a run builds:
##   godot --headless --path . res://tools/system_audit.tscn -- --fresh
## Prints the slice's named members (set or null) and every script class in the slice's tree,
## then quits.

const MEMBERS: Array[String] = ["field", "litter", "tutorial", "wren", "fleet", "planet", "globe",
	"sky_director", "hub", "rocket", "shards", "garden", "hex_levels", "goals", "first_seed", "water",
	"doc_view", "interactables", "camp", "eggs", "ledger", "outposts", "events", "lumi_level", "photo",
	"fauna", "orbit", "view", "depot", "patch", "hud", "upgrades",
	"music", "intro", "objectives", "core_charge", "composter", "pause_menu", "research", "achievements",
	"codex"]


func _ready() -> void:
	await get_tree().process_frame
	SaveManager.enabled = false
	var s: Node = (load("res://scenes/slice.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(s)
	var t0: int = Time.get_ticks_msec()
	while (s.get("patch") == null or s.get("building") == true) and Time.get_ticks_msec() - t0 < 120000:
		await get_tree().process_frame
	await get_tree().create_timer(8.0).timeout  # deferred attaches, the first replans
	var set_: Array[String] = []
	var unset: Array[String] = []
	for m: String in MEMBERS:
		var v: Variant = s.get(m)
		(set_ if v != null and (not v is Object or is_instance_valid(v)) else unset).append(m)
	print("[audit] members set: ", " ".join(set_))
	print("[audit] members null: ", " ".join(unset))
	var classes: Dictionary = {}
	var stack: Array[Node] = [s]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var sc: Script = n.get_script() as Script
		if sc and sc.get_global_name() != "":
			classes[str(sc.get_global_name())] = true
		stack.append_array(n.get_children())
	for n: Node in get_tree().root.get_children():  # systems that attach next to the slice
		var sc2: Script = n.get_script() as Script
		if sc2 and sc2.get_global_name() != "" and n != s:
			classes[str(sc2.get_global_name())] = true
	var ks: Array = classes.keys()
	ks.sort()
	print("[audit] classes: ", " ".join(ks))
	get_tree().quit()
