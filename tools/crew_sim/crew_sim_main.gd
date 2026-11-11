extends Node
## Command line of the crew simulator (tools/crew_sim/README.md):
##   godot --headless --path . res://tools/crew_sim/crew_sim.tscn -- [--planet=<id>]
##       [--policy=default|all_scroungers|no_scroungers|all] [--set=key=value,...]
## --set replaces a calibration number for this run (plain numbers only).

const POLICIES: Array[String] = [CrewSim.POLICY_DEFAULT, CrewSim.POLICY_ALL_FINDERS, CrewSim.POLICY_NO_FINDERS]


func _ready() -> void:
	var args: Dictionary[String, String] = _args()
	var def: PlanetDefinition = Planets.by_id(StringName(args.get("planet", String(Planets.current_id()))))
	if def == null:
		printerr("[crew_sim] unknown planet '%s'" % args.get("planet", ""))
		get_tree().quit(2)
		return
	var cal: Dictionary = CrewSim.load_calibration()
	for pair: String in args.get("set", "").split(",", false):
		cal[pair.get_slice("=", 0)] = float(pair.get_slice("=", 1))
	var want: String = args.get("policy", CrewSim.POLICY_DEFAULT)
	for policy: String in (POLICIES if want == "all" else [want] as Array[String]):
		for line: String in summary(policy, CrewSim.run(def, cal, policy)):
			print(line)
	get_tree().quit(0)


## The run in words: one block per policy.
static func summary(policy: String, r: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var by_city: PackedStringArray = []
	for n: int in r["crew_by_city"]:
		by_city.append(str(n))
	var curve: PackedStringArray = []
	var minute: int = 10
	for n: int in r["curve"]:
		curve.append("%d: %d" % [minute, n])
		minute += 10
	var types: PackedStringArray = []
	var by_type: Dictionary = r["by_type"]
	for id: String in by_type:
		types.append("%s %d" % [id, int(by_type[id])])
	out.append("[crew_sim] policy %s: %.0f player minutes" % [policy, float(r["minutes"])])
	out.append("[crew_sim]   crew after each city: %s; at the end %d of %d (%s)" % [", ".join(by_city), int(r["crew_end"]), int(r["cap_end"]), ", ".join(types)])
	out.append("[crew_sim]   crew by player minute: %s" % ", ".join(curve))
	out.append("[crew_sim]   first robot at minute %.0f, Assembler at minute %.0f; built by hand %d, by the Assembler %d" % [
		float(r["first_robot_min"]), float(r["first_assembler_min"]), int(r["hand_built"]), int(r["assembled"])])
	out.append("[crew_sim]   Parts: %.0f earned (%.0f Scroungers, %.0f hands, %.0f salvage), %.0f on robots, %.0f on tiers, %.0f left" % [
		float(r["parts_earned"]), float(r["parts_scrounged"]), float(r["parts_hand"]), float(r["parts_arrival"]),
		float(r["parts_on_builds"]), float(r["parts_on_tiers"]), float(r["parts_left"])])
	out.append("[crew_sim]   ground: %.0f buried parts left by cleaning, %.0f still in the ground; fastest doubling %.0f s, longest wait for a robot from city 2 on %.0f s" % [
		float(r["ground_seeded"]), float(r["ground_left"]), float(r["fastest_doubling_s"]), float(r["longest_stall_s"])])
	return out


static func _args() -> Dictionary[String, String]:
	var out: Dictionary[String, String] = {}
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var body: String = a.substr(2)
			out[body.get_slice("=", 0)] = body.get_slice("=", 1) if "=" in body else "1"
	return out
