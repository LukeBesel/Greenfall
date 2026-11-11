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
	out.append("[crew_sim]   job parts (the rocket): %d built for %.0f Parts; they held the Assembler's line for %.0f s" % [
		int(r["job_parts_built"]), float(r["parts_on_jobs"]), float(r["line_held_s"])])
	out.append("[crew_sim]   ground: %.0f buried parts left by cleaning, %.0f still in the ground; fastest doubling %.0f s, longest wait for a robot from city 2 on %.0f s" % [
		float(r["ground_seeded"]), float(r["ground_left"]), float(r["fastest_doubling_s"]), float(r["longest_stall_s"])])
	out.append_array(mastery_lines(r.get("mastery", {})))
	return out


## The mastery ledger in words: hand share by city against the planet's rule, the levels reached,
## and when each kind was first learnt.
static func mastery_lines(m: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	if m.is_empty():
		return out
	var shares: PackedStringArray = []
	var needed: PackedStringArray = []
	var cover: PackedStringArray = []
	var learnt: PackedStringArray = []
	var waited: float = 0.0
	var cities: Array = m["by_city"]
	for i: int in cities.size():
		var c: Dictionary = cities[i]
		shares.append("%.0f%%" % (float(c["hand_share"]) * 100.0))
		needed.append("%.1f" % float(c["hand_needed_per_min"]))
		cover.append("%.0f%%" % (float(c["coverage"]) * 100.0))
		waited += float(c["waiting_robot_min"])
		var first: Dictionary = c["first_level_min"]
		for id: String in first:
			learnt.append("%s in city %d after %.1f min" % [id, i + 1, float(first[id])])
	var levels: PackedStringArray = []
	for id: String in (m["levels"] as Dictionary):
		levels.append("%s %d" % [id, int(m["levels"][id])])
	var rule: Dictionary = m["rule"]
	var met: PackedStringArray = []
	for i: Variant in (rule.get("target_met", []) as Array):
		met.append(str(int(i) + 1))
	out.append("[crew_sim]   hand share of cleaning by city: %s; all cities by volume %.0f%%" % [", ".join(shares), float(m["hand_share_volume"]) * 100.0])
	out.append("[crew_sim]   rule (at least %.0f%% in cities 1-%d): %s, lowest %.0f%%; the old %.0f%% line holds in cities: %s" % [
		float(rule.get("min", 0.0)) * 100.0, int(rule.get("cities", 0)), "PASS" if bool(rule.get("pass", false)) else "FAIL",
		float(rule.get("worst", 0.0)) * 100.0, float(rule.get("target", 0.0)) * 100.0, ", ".join(met) if not met.is_empty() else "none"])
	out.append("[crew_sim]   hexes a minute Lumi would need for that line, by city: %s; hand and crew capacity against each city's hexes: %s" % [
		", ".join(needed), ", ".join(cover)])
	out.append("[crew_sim]   mastery at the end: %s; first level: %s; robots waiting on a kind Lumi had not learnt: %.0f robot-minutes" % [
		", ".join(levels), "; ".join(learnt), waited])
	return out


static func _args() -> Dictionary[String, String]:
	var out: Dictionary[String, String] = {}
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var body: String = a.substr(2)
			out[body.get_slice("=", 0)] = body.get_slice("=", 1) if "=" in body else "1"
	return out
