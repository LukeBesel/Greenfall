class_name PaceSim
extends Node
## The fast balance simulator: a whole planet's economy in seconds, from the same data the game
## reads. See tools/pace_sim/README.md.
##   godot --headless --path . res://tools/pace_sim/pace_sim.tscn -- --planet=<id> [--minutes=N]
##       [--csv=PATH] [--policy=NAME] [--seed=N] [--planets-dir=res://...] [--purchases=1] [--goals=1]
##       [--set=constant=value,constant=value]   what-if: replace calibration constants for this run

const POLICY_DIR: String = "res://tools/pace_sim/policies"
const DEFAULT_POLICY: String = "greedy"
## --model=current (default) is the game as it is; --model=redesign is PaceSimRedesign.
const MODEL_CURRENT: String = "current"


func _ready() -> void:
	var args: Dictionary[String, String] = _args()
	if args.has("planets-dir"):
		Planets.register_dir(args["planets-dir"])
	if args.has("rig-study"):  # every rig module scored in every city (tools/pace_sim/rig_study.gd)
		var study: Dictionary = RigStudy.run(Planets.current())
		for line: String in RigStudy.lines(study):
			print(line)
		get_tree().quit(0 if bool(study["ok"]) and (study["dominant"] as Array).is_empty() else 1)
		return
	if args.get("model", MODEL_CURRENT) != MODEL_CURRENT:
		get_tree().quit(PaceSimRedesign.main(args))
		return
	for pair: String in args.get("set", "").split(",", false):
		PaceSimData.overrides[pair.get_slice("=", 0)] = float(pair.get_slice("=", 1))
	var planet_id: StringName = StringName(args.get("planet", String(Planets.current_id())))
	var def: PlanetDefinition = Planets.by_id(planet_id)
	if def == null:
		printerr("[pace_sim] unknown planet '%s'" % planet_id)
		get_tree().quit(2)
		return
	var minutes: float = float(args.get("minutes", str(def.target_playtime_min)))
	var result: Dictionary = run(planet_id, minutes, args.get("policy", DEFAULT_POLICY), int(args.get("seed", "0")))
	if not result["ok"]:
		printerr("[pace_sim] " + str(result["error"]))
		get_tree().quit(2)
		return
	for line: String in summary(result):
		print(line)
	if args.has("purchases"):
		for row: Dictionary in (result["model"] as PaceSimModel).record.purchases:
			print("%6.1f min  %-9s %-22s %8.0f cubes" % [float(row["t"]) / 60.0, row["kind"], row["id"], row["cubes"]])
	if args.has("goals"):
		for row: Dictionary in (result["model"] as PaceSimModel).record.goals:
			print("%6.1f min  goal      %s" % [float(row["t"]) / 60.0, row["id"]])
	if args.has("csv"):
		var f: FileAccess = FileAccess.open(args["csv"], FileAccess.WRITE)
		if f == null:
			printerr("[pace_sim] cannot write %s" % args["csv"])
		else:
			f.store_string((result["model"] as PaceSimModel).record.csv())
			print("[pace_sim] time series written to %s" % args["csv"])
	get_tree().quit(0)


static func _args() -> Dictionary[String, String]:
	var out: Dictionary[String, String] = {}
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			out[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	return out


## A policy by name (one script per policy in tools/pace_sim/policies/), or null.
static func load_policy(policy_name: String) -> PaceSimPolicy:
	var path: String = "%s/%s.gd" % [POLICY_DIR, policy_name]
	if not ResourceLoader.exists(path):
		return null
	return (load(path) as GDScript).new() as PaceSimPolicy


## Runs `minutes` of play on a registered planet and returns {ok, error, planet, minutes, content,
## missing, model, report, real_ms}. The game's progress state is put aside for the run and put
## back after, so the simulator can run inside tests or a live session.
static func run(planet_id: StringName, minutes: float, policy_name: String = DEFAULT_POLICY, seed_value: int = 0) -> Dictionary:
	if not Planets.has(planet_id):
		return {"ok": false, "error": "unknown planet '%s'" % planet_id}
	var policy: PaceSimPolicy = load_policy(policy_name)
	if policy == null:
		return {"ok": false, "error": "unknown policy '%s' (no %s/%s.gd)" % [policy_name, POLICY_DIR, policy_name]}
	var started: int = Time.get_ticks_msec()
	var planet_before: StringName = Planets.current_id()
	var kept: Array = [GameState.upgrades, GameState.flags, GameState.world, GameState.stats, GameState.currencies]
	GameState.upgrades = {}
	GameState.flags = {}
	GameState.world = {}
	GameState.stats = {}
	GameState.currencies = {}
	Planets.set_current(planet_id)
	var model := PaceSimModel.new(policy, seed_value)
	model.run(minutes * 60.0)
	var report: Dictionary = PaceSimReport.build(model, minutes * 60.0)
	var step: Dictionary = model.chains.card_step()
	model.seal()
	GameState.upgrades = kept[0]
	GameState.flags = kept[1]
	GameState.world = kept[2]
	GameState.stats = kept[3]
	GameState.currencies = kept[4]
	Planets.set_current(planet_before)
	return {"ok": true, "error": "", "planet": planet_id, "minutes": minutes, "content": model.data.has_content(),
		"missing": model.data.missing, "model": model, "report": report, "card_step": step, "real_ms": Time.get_ticks_msec() - started}


## The printed report for a run() result.
static func summary(result: Dictionary) -> PackedStringArray:
	var model: PaceSimModel = result["model"]
	var out: PackedStringArray = ["[pace_sim] planet=%s minutes=%.0f policy run in %d ms" % [result["planet"], result["minutes"], result["real_ms"]]]
	if not (result["missing"] as PackedStringArray).is_empty():
		out.append("[pace_sim] no content in tables: %s" % ", ".join(result["missing"] as PackedStringArray))
	if not result["content"]:
		out.append("[pace_sim] no content: this planet has no junk or no player stats, so there is nothing to simulate")
		return out
	var d: PaceSimData = model.data
	out.append("derived from data: hex volume %.0f (clean at %.0f%%), mean take %.2f, %.0f takes a hex, %.2f cubes a unit, %.0f Parts a hand-cleaned hex before luck, hexes %.1f m apart, %d small-junk start hexes, %d hexes in the hub region, %.0f seeds to plant a hex, bloom after %.0f s" % [
		d.hex_vol, d.clean_frac * 100.0, d.mean_bite, d.bites_per_hex, d.hex_cubes / maxf(d.hex_vol, 0.001), d.finds_per_unit(d.hex_vol) * d.hex_vol * d.clean_frac * PaceSimData.mean_part_value() + d.parts_per_hex_buried,
		d.cell_spacing, d.starter_hexes, d.region_hexes, d.seeds_to_plant, d.bloom_s])
	out.append("end state: hexes=%d cubes=%.0f earned=%.0f parts=%.0f robots=%d base=%d upgrades=%d research=%d goals=%d/%d" % [
		model.work.hexes_done, model.cubes, model.earned, model.parts, model.robot_total(), model.hub_level,
		int(model.stat_of("upgrades_bought")), int(model.stat_of("research_done")), model.chains.goals_done.size(), model.data.goals.size()])
	out.append_array(PaceSimReport.lines(result["report"], model.data.k("bot_to_player")))
	out.append(PaceSimReport.fit_line(model))
	return out
