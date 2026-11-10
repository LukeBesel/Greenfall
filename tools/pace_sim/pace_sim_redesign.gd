class_name PaceSimRedesign
extends RefCounted
## Entry point of the redesign model (--model=redesign): Planet 1 as docs/design/PLANET1_DESIGN.md
## describes it, played from a PROPOSAL data set in tools/pace_sim/proposals/<name>/.
##   godot --headless --path . res://tools/pace_sim/pace_sim.tscn -- --model=redesign
##       [--proposal=NAME] [--minutes=N] [--policy=default|rush_robots|no_robots] [--rig=mod,mod,mod]
##       [--set=path=value,...] [--purchases=1] [--csv=PATH] [--compare=1] [--search=N]

const POLICY_DIR: String = "res://tools/pace_sim/rd_policies"
const DEFAULT_POLICY: String = "default"
const DEFAULT_PROPOSAL: String = "planet1"
## A run stops here if the ending has not come (bot minutes).
const MAX_MINUTES: float = 300.0
const COMPARE_POLICIES: PackedStringArray = ["default", "rush_robots", "no_robots", "all_scroungers", "no_scroungers"]


## A policy by name (one script per policy in tools/pace_sim/rd_policies/), or null.
static func load_policy(policy_name: String) -> PaceSimRdPolicy:
	var path: String = "%s/%s.gd" % [POLICY_DIR, policy_name]
	if not ResourceLoader.exists(path):
		return null
	return (load(path) as GDScript).new() as PaceSimRdPolicy


## Plays proposal `proposal` to the ending (or `max_minutes`) and returns {ok, error, proposal,
## policy, model, report, real_ms}. opts: "set" = {dotted path: number} overrides of proposal
## values, "rig" = {slot: module} to keep fitted. The game's progress state is put aside for the
## run and put back after.
static func run(proposal: String = DEFAULT_PROPOSAL, max_minutes: float = MAX_MINUTES, policy_name: String = DEFAULT_POLICY,
		opts: Dictionary = {}) -> Dictionary:
	var planet_id: StringName = PaceSimRdData.planet_of(proposal)
	if not Planets.has(planet_id):
		return {"ok": false, "error": "proposal '%s' is missing or names an unknown planet '%s'" % [proposal, planet_id]}
	var policy: PaceSimRdPolicy = load_policy(policy_name)
	if policy == null:
		return {"ok": false, "error": "unknown policy '%s' (no %s/%s.gd)" % [policy_name, POLICY_DIR, policy_name]}
	policy.fixed_rig.assign(opts.get("rig", {}))
	var started: int = Time.get_ticks_msec()
	var planet_before: StringName = Planets.current_id()
	var kept: Array = [GameState.upgrades, GameState.flags, GameState.world, GameState.stats, GameState.currencies]
	GameState.upgrades = {}
	GameState.flags = {}
	GameState.world = {}
	GameState.stats = {}
	GameState.currencies = {}
	Planets.set_current(planet_id)
	var data := PaceSimRdData.new(proposal, opts.get("set", {}))
	var out: Dictionary = {"ok": data.ok, "error": data.error, "proposal": proposal, "policy": policy_name}
	if data.ok:
		var model := PaceSimRdModel.new(data, policy)
		model.run(max_minutes * 60.0)
		out["model"] = model
		out["report"] = PaceSimRdReport.build(model)
		model.seal()
	GameState.upgrades = kept[0]
	GameState.flags = kept[1]
	GameState.world = kept[2]
	GameState.stats = kept[3]
	GameState.currencies = kept[4]
	Planets.set_current(planet_before)
	out["real_ms"] = Time.get_ticks_msec() - started
	return out


## The printed report for a run() result.
static func summary(result: Dictionary) -> PackedStringArray:
	var m: PaceSimRdModel = result["model"]
	var report: Dictionary = result["report"]
	var out: PackedStringArray = ["[pace_sim redesign] proposal=%s policy=%s: %s after %.1f bot minutes (player about %.0f), run in %d ms" % [
		result["proposal"], result["policy"], "ENDING" if report["ended"] else "no ending", report["end_min"],
		float(report["end_min"]) * m.data.num("balance.bot_to_player"), result["real_ms"]]]
	out.append("kept from the planet's tables: litter pays %.2f cubes a unit, a perfect bale x%.2f" % [m.data.kept_litter_value, m.data.kept_bale_mult])
	out.append("end state: hexes clean %d, restoration %.0f%%, cubes earned %.0f, robots %d, purchases %d" % [
		m.hexes_clean, m.restoration() * 100.0, m.earned, m.robot_total(), m.record.purchases.size()])
	out.append_array(PaceSimRdReport.lines(report))
	return out


## One line per policy: how the same numbers play for different players.
static func compare(proposal: String, opts: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = ["policy        ending(bot min)  hexes  robots  purchases  lowest hand share  failed checks"]
	for policy_name: String in COMPARE_POLICIES:
		var result: Dictionary = run(proposal, MAX_MINUTES, policy_name, opts)
		if not result["ok"]:
			out.append("%s: %s" % [policy_name, result["error"]])
			continue
		var m: PaceSimRdModel = result["model"]
		var failed: PackedStringArray = []
		var share: float = 0.0
		for c: Dictionary in result["report"]["checks"]:
			if not c["pass"]:
				failed.append(str(c["id"]))
			if str(c["id"]) == "hand_share":
				share = float(c["value"])
		out.append("%-13s %-16s %5d  %6d  %9d  %16.0f%%  %s" % [policy_name, "%.1f" % float(result["report"]["end_min"]) if result["report"]["ended"] else "none",
			m.hexes_clean, m.robot_total(), m.record.purchases.size(), share * 100.0, ", ".join(failed) if not failed.is_empty() else "none"])
	return out


## Command line: called by PaceSim when --model=redesign. Returns the process exit code.
static func main(args: Dictionary[String, String]) -> int:
	var opts: Dictionary = {"set": {}, "rig": {}}
	for pair: String in args.get("set", "").split(",", false):
		opts["set"][pair.get_slice("=", 0)] = float(pair.get_slice("=", 1))
	var proposal: String = args.get("proposal", DEFAULT_PROPOSAL)
	if args.has("search"):
		for line: String in PaceSimRdSearch.run(proposal, int(args["search"]), opts["set"]):
			print(line)
		return 0
	if args.has("compare"):
		for line: String in compare(proposal, opts):
			print(line)
		return 0
	var result: Dictionary = run(proposal, float(args.get("minutes", str(MAX_MINUTES))), args.get("policy", DEFAULT_POLICY), _with_rig(opts, proposal, args.get("rig", "")))
	if not result["ok"]:
		printerr("[pace_sim redesign] " + str(result["error"]))
		return 2
	for line: String in summary(result):
		print(line)
	var m: PaceSimRdModel = result["model"]
	if args.has("purchases"):
		for row: Dictionary in m.record.purchases:
			print("%6.1f min  %-9s %-22s %8.0f cubes %6.0f parts" % [float(row["t"]) / 60.0, row["type"], row["id"], row["cubes"], row["parts"]])
	if args.has("csv"):
		var f: FileAccess = FileAccess.open(args["csv"], FileAccess.WRITE)
		if f == null:
			printerr("[pace_sim redesign] cannot write %s" % args["csv"])
		else:
			f.store_string(m.record.csv())
	return 0


## Turns --rig=module,module into {slot: module} using the proposal's rig table.
static func _with_rig(opts: Dictionary, proposal: String, rig_arg: String) -> Dictionary:
	if rig_arg == "":
		return opts
	var rigs: Dictionary = Economy.read_json("%s/%s/rigs.json" % [PaceSimRdData.PROPOSALS_DIR, proposal])
	for module: String in rig_arg.split(",", false):
		if (rigs.get("modules", {}) as Dictionary).has(module):
			opts["rig"][str(rigs["modules"][module]["slot"])] = module
	return opts
