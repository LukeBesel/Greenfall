class_name PaceSimRdStudies
extends RefCounted
## Studies of a redesign proposal that need more than one run: the five players side by side,
## the rig loadouts against each other, and how the checks hold when one constant at a time is
## moved up and down. Each returns plain rows plus the checks that are judged on them.

const STUDY_PATH: String = "res://tools/pace_sim/rd_sensitivity.json"
## No player may reach the launch point in under this share of the default player's time.
const FASTEST_SHARE: float = 0.6
## Time to the launch point must differ by at least this share between the best and the worst
## sensible rig loadout.
const RIG_SPREAD_MIN: float = 0.08


static func _check(id: String, passed: bool, value: float, shown: String, limit_shown: String, note: String) -> Dictionary:
	return {"id": id, "pass": passed, "value": value, "shown": shown, "limit_shown": limit_shown, "note": note}


## Ids of the required checks a run failed.
static func failed(report: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	for c: Dictionary in report["checks"]:
		if not c["pass"] and not bool(c.get("advisory", false)):
			out.append(str(c["id"]))
	return out


## The passing check that has used most of its allowance, as "id 93%".
static func tightest(report: Dictionary) -> String:
	var best: String = ""
	var best_use: float = 0.0
	for c: Dictionary in report["checks"]:
		var use: float = float(c.get("use", -1.0))
		if c["pass"] and not bool(c.get("advisory", false)) and use > best_use:
			best_use = use
			best = str(c["id"])
	return "%s %.0f%%" % [best, best_use * 100.0]


## Every policy on the same numbers. {rows: [{policy, ended, end_min, crew, crew_by_city, failed}], checks}.
static func players(proposal: String, opts: Dictionary) -> Dictionary:
	var rows: Array[Dictionary] = []
	for policy_name: String in PaceSimRedesign.COMPARE_POLICIES:
		var result: Dictionary = PaceSimRedesign.run(proposal, PaceSimRedesign.MAX_MINUTES, policy_name, opts)
		if not result["ok"]:
			rows.append({"policy": policy_name, "ended": false, "end_min": 0.0, "crew": 0, "crew_by_city": [], "failed": [str(result["error"])], "over_cap": false})
			continue
		var m: PaceSimRdModel = result["model"]
		var crew: PackedStringArray = []
		for z: PaceSimRdDistrict in m.zones:
			crew.append(str(z.crew_at_stage4))
		rows.append({"policy": policy_name, "ended": bool(result["report"]["ended"]), "end_min": float(result["report"]["end_min"]), "crew": m.robot_total(),
			"scroungers": m.robots.get(str(m.data.tables["robots"]["chain"]["scrounger"]), 0), "hexes": m.hexes_clean,
			"crew_by_city": crew, "failed": failed(result["report"]), "over_cap": m.robot_total() > m.crew_cap()})
	var base: float = float(rows[0]["end_min"])
	var stuck: PackedStringArray = []
	var fastest: float = INF
	var fastest_name: String = ""
	for row: Dictionary in rows:
		if not row["ended"]:
			stuck.append(str(row["policy"]))
		elif float(row["end_min"]) < fastest:
			fastest = float(row["end_min"])
			fastest_name = str(row["policy"])
	var checks: Array[Dictionary] = [
		_check("every_player_launches", stuck.is_empty(), float(stuck.size()), "%d stuck" % stuck.size(), "0",
			"players who do not reach the launch point in %.0f bot minutes: %s" % [PaceSimRedesign.MAX_MINUTES, ", ".join(stuck) if not stuck.is_empty() else "none"]),
		_check("no_player_too_fast", fastest >= base * FASTEST_SHARE, fastest / maxf(base, 0.001), "%.0f%% of the default" % (fastest / maxf(base, 0.001) * 100.0),
			"at least %.0f%%" % (FASTEST_SHARE * 100.0), "fastest player: %s at %.1f bot minutes against the default's %.1f" % [fastest_name, fastest, base]),
	]
	return {"rows": rows, "checks": checks}


static func players_lines(study: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = ["policy          launch(bot min)  hexes  robots  scroungers  crew when each city reached stage 4   failed checks"]
	for row: Dictionary in study["rows"]:
		out.append("%-15s %-16s %5d  %6d  %10d  %-36s %s" % [row["policy"], "%.1f" % float(row["end_min"]) if row["ended"] else "none",
			int(row.get("hexes", 0)), row["crew"], int(row.get("scroungers", 0)), ", ".join(row["crew_by_city"]),
			", ".join(row["failed"]) if not (row["failed"] as Array).is_empty() else "none"])
	out.append_array(_check_lines(study["checks"]))
	return out


## Every named loadout of the proposal's rig table, held for a whole run by the default player.
## {rows: [{name, modules, ended, end_min, city_min}], checks}.
static func rigs(proposal: String, opts: Dictionary) -> Dictionary:
	var table: Dictionary = Economy.read_json("%s/%s/rigs.json" % [PaceSimRdData.PROPOSALS_DIR, proposal])
	var rows: Array[Dictionary] = []
	var loadouts: Dictionary = table.get("loadouts", {})
	for loadout: String in loadouts:
		var rig: Dictionary = {}
		for module: Variant in loadouts[loadout]:
			rig[str(table["modules"][str(module)]["slot"])] = str(module)
		var result: Dictionary = PaceSimRedesign.run(proposal, PaceSimRedesign.MAX_MINUTES, PaceSimRedesign.DEFAULT_POLICY, {"set": opts.get("set", {}), "rig": rig})
		var city_min: Array[float] = []
		if result["ok"]:
			for d: Dictionary in result["report"]["districts"]:
				city_min.append(float(d["player_min"]))
		rows.append({"name": loadout, "modules": loadouts[loadout], "ended": result["ok"] and bool(result["report"]["ended"]),
			"end_min": float(result["report"]["end_min"]) if result["ok"] else 0.0, "city_min": city_min})
	return {"rows": rows, "checks": _rig_checks(rows)}


static func rigs_lines(study: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = ["loadout     launch(bot min)  player minutes in each city            modules"]
	for row: Dictionary in study["rows"]:
		var cities: PackedStringArray = []
		for minutes: float in row["city_min"]:
			cities.append("%.1f" % minutes)
		out.append("%-11s %-16s %-38s %s" % [row["name"], "%.1f" % float(row["end_min"]) if row["ended"] else "none", ", ".join(cities), ", ".join(row["modules"])])
	out.append_array(_check_lines(study["checks"]))
	return out


static func _rig_checks(rows: Array[Dictionary]) -> Array[Dictionary]:
	var best: float = INF
	var worst: float = 0.0
	var best_name: String = ""
	var worst_name: String = ""
	var all_end: bool = not rows.is_empty()
	for row: Dictionary in rows:
		all_end = all_end and bool(row["ended"])
		if float(row["end_min"]) < best:
			best = float(row["end_min"])
			best_name = str(row["name"])
		if float(row["end_min"]) > worst:
			worst = float(row["end_min"])
			worst_name = str(row["name"])
	var spread: float = (worst - best) / maxf(best, 0.001) if all_end else 0.0
	var winners: Dictionary[String, int] = {}
	var by_city: PackedStringArray = []
	var cities: int = (rows[0]["city_min"] as Array).size() if all_end else 0
	for i: int in cities:
		var quickest: String = ""
		var quickest_min: float = INF
		for row: Dictionary in rows:
			if float(row["city_min"][i]) < quickest_min:
				quickest_min = float(row["city_min"][i])
				quickest = str(row["name"])
		winners[quickest] = winners.get(quickest, 0) + 1
		by_city.append(quickest)
	return [
		_check("rig_loadout_spread", all_end and spread >= RIG_SPREAD_MIN, spread, "%.1f%%" % (spread * 100.0), "at least %.0f%%" % (RIG_SPREAD_MIN * 100.0),
			"time to the launch point, best loadout (%s, %.1f bot min) against worst (%s, %.1f)" % [best_name, best, worst_name, worst]),
		_check("rig_no_loadout_best_everywhere", all_end and winners.size() > 1, float(winners.size()), "%d loadouts lead a city" % winners.size(), "more than 1",
			"quickest loadout in each city: " + ", ".join(by_city)),
	]


## Moves each listed constant down and up by the study's swing, one at a time, for the default
## player. which = "top" (the constants the proposal must survive) or "candidates" (the wider
## list the top ones were picked from). {rows: [{path, base, runs: [{factor, value, ended,
## end_min, crew, failed, tightest}]}], checks, swing}.
static func sensitivity(proposal: String, which: String, opts: Dictionary) -> Dictionary:
	var cfg: Dictionary = Economy.read_json(STUDY_PATH)
	var swing: float = float(cfg.get("swing", 0.1))
	var base_set: Dictionary = opts.get("set", {})
	var rows: Array[Dictionary] = []
	var broken: PackedStringArray = []
	for path: Variant in cfg.get(which, []):
		var base: float = float(base_set.get(str(path), _table_value(proposal, str(path))))
		var runs: Array[Dictionary] = []
		for factor: float in [1.0 - swing, 1.0 + swing]:
			var trial: Dictionary = base_set.duplicate()
			trial[str(path)] = base * factor
			var result: Dictionary = PaceSimRedesign.run(proposal, PaceSimRedesign.MAX_MINUTES, PaceSimRedesign.DEFAULT_POLICY, {"set": trial})
			var report: Dictionary = result["report"]
			var fails: PackedStringArray = failed(report)
			runs.append({"factor": factor, "value": base * factor, "ended": bool(report["ended"]), "end_min": float(report["end_min"]),
				"crew": (result["model"] as PaceSimRdModel).robot_total(), "failed": fails, "tightest": tightest(report)})
			if not fails.is_empty():
				broken.append("%s x%.2f (%s)" % [path, factor, ", ".join(fails)])
		rows.append({"path": str(path), "base": base, "runs": runs})
	var checks: Array[Dictionary] = [_check("survives_one_constant_moved", broken.is_empty(), float(broken.size()), "%d of %d runs fail" % [broken.size(), rows.size() * 2],
		"0", "each constant moved by -%.0f%% and +%.0f%%, one at a time%s" % [swing * 100.0, swing * 100.0, "" if broken.is_empty() else ": " + "; ".join(broken)])]
	return {"rows": rows, "checks": checks, "swing": swing}


static func sensitivity_lines(study: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = ["constant                                        base      change  launch(bot min)  crew  failed checks (else the tightest pass)"]
	for row: Dictionary in study["rows"]:
		for run: Dictionary in row["runs"]:
			out.append("%-46s %8.4g  %+5.0f%%  %-15s  %4d  %s" % [row["path"], float(row["base"]), (float(run["factor"]) - 1.0) * 100.0,
				"%.1f" % float(run["end_min"]) if run["ended"] else "none", run["crew"],
				", ".join(run["failed"]) if not (run["failed"] as Array).is_empty() else "none (%s)" % run["tightest"]])
	out.append_array(_check_lines(study["checks"]))
	return out


## A number of the proposal as it stands on disk, by dotted path ("robots.chain.carry").
static func _table_value(proposal: String, path: String) -> float:
	var keys: PackedStringArray = path.split(".")
	var at: Variant = Economy.read_json("%s/%s/%s.json" % [PaceSimRdData.PROPOSALS_DIR, proposal, keys[0]])
	for i: int in range(1, keys.size()):
		if at is Dictionary and (at as Dictionary).has(keys[i]):
			at = (at as Dictionary)[keys[i]]
		elif at is Array and keys[i].is_valid_int() and int(keys[i]) < (at as Array).size():
			at = (at as Array)[int(keys[i])]
		else:
			push_error("pace_sim sensitivity: no value at '%s'" % path)
			return 0.0
	return float(at)


static func _check_lines(checks: Array) -> PackedStringArray:
	var out: PackedStringArray = []
	for c: Dictionary in checks:
		out.append("%s  %-30s %s  (limit %s)  %s" % ["PASS" if c["pass"] else "FAIL", c["id"], c["shown"], c["limit_shown"], c["note"]])
	return out
