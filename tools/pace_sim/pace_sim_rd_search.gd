class_name PaceSimRdSearch
extends RefCounted
## A coordinate hill-climb over proposal values (--model=redesign --search=N). It tries one value
## up and down by a step, keeps a change that lowers the penalty, and prints the best set as a
## --set string. The values it may move and their ranges are in rd_search_params.json.

const PARAMS_PATH: String = "res://tools/pace_sim/rd_search_params.json"
const START_STEP: float = 0.2
const MIN_STEP: float = 0.03
## Penalty weights: a failed check, each minute off the target ending, each district's share off
## its target minutes, and a run that never ends.
const W_FAIL: float = 10.0
const W_END_MIN: float = 0.5
const W_DISTRICT: float = 4.0
const W_NO_ENDING: float = 200.0


## How far a run is from what the plan asks for: 0 is perfect.
static func penalty(result: Dictionary) -> float:
	if not result["ok"]:
		return INF
	var report: Dictionary = result["report"]
	var m: PaceSimRdModel = result["model"]
	var p: float = 0.0
	for c: Dictionary in report["checks"]:
		if not c["pass"]:
			p += W_FAIL
	if not report["ended"]:
		return p + W_NO_ENDING * (1.5 - m.restoration())
	p += absf(float(report["end_min"]) - m.data.num("balance.target_bot_min.aim")) * W_END_MIN
	for d: Dictionary in report["districts"]:
		p += absf(float(d["player_min"]) - float(d["target_min"])) / float(d["target_min"]) * W_DISTRICT
	return p


static func run(proposal: String, tries: int, base: Dictionary) -> PackedStringArray:
	var params: Array = Economy.read_json(PARAMS_PATH).get("params", [])
	var current: Dictionary = base.duplicate()
	var first: Dictionary = PaceSimRedesign.run(proposal, PaceSimRedesign.MAX_MINUTES, PaceSimRedesign.DEFAULT_POLICY, {"set": current})
	if not first["ok"]:
		return ["search: " + str(first["error"])]
	var best: float = penalty(first)
	var out: PackedStringArray = ["search: start penalty %.2f" % best]
	var data: PaceSimRdData = (first["model"] as PaceSimRdModel).data
	var step: float = START_STEP
	var done: int = 0
	while done < tries and step >= MIN_STEP:
		var improved: bool = false
		for row: Variant in params:
			var path: String = str((row as Dictionary)["path"])
			var now: float = float(current.get(path, data.num(path)))
			for factor: float in [1.0 + step, 1.0 / (1.0 + step)]:
				if done >= tries:
					break
				var trial: Dictionary = current.duplicate()
				trial[path] = clampf(now * factor, float((row as Dictionary)["min"]), float((row as Dictionary)["max"]))
				done += 1
				var p: float = penalty(PaceSimRedesign.run(proposal, PaceSimRedesign.MAX_MINUTES, PaceSimRedesign.DEFAULT_POLICY, {"set": trial}))
				if p < best - 0.001:
					best = p
					current = trial
					improved = true
					out.append("search: %s = %.4g -> penalty %.2f" % [path, float(trial[path]), p])
					break
		if not improved:
			step *= 0.5
	var pairs: PackedStringArray = []
	for path: String in current:
		pairs.append("%s=%.4g" % [path, float(current[path])])
	out.append("search: %d runs, best penalty %.2f" % [done, best])
	out.append("search: --set=" + ",".join(pairs))
	return out
