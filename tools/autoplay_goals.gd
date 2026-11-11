class_name AutoplayGoals
extends RefCounted
## The bot's record of the goal tiers (story/goals.gd): when each goal was finished, the longest
## wait between two finished goals in each tier and over all tiers, and how long any tier stood
## with no active goal. The cadence rule (docs/PLAN.md section 9): no gap between goals longer
## than GAP_LIMIT_S.
##
## Report keys it writes (screenshots/autoplay_report.json): goal_tiers (one row per tier and one
## for all tiers: done, longest_gap_s, gap_from_s, empty_s), goal_gap_longest_s, goal_gap_ok.

const GAP_LIMIT_S: float = 240.0
const ALL: String = "all"

var times: Dictionary = {}
var empty_s: Dictionary = {}
var _sampled_at: float = -1.0


func on_completed(goals: Goals, index: int, now: float) -> void:
	for key: String in [goals.tier_of(index), ALL]:
		if not times.has(key):
			times[key] = []
		(times[key] as Array).append(now)


## Call while the bot plays: adds up the time each tier had no active goal.
func sample(goals: Goals, now: float) -> void:
	var dt: float = now - _sampled_at if _sampled_at >= 0.0 else 0.0
	_sampled_at = now
	for tier: String in goals.tier_ids():
		if goals.active(tier) < 0:
			empty_s[tier] = float(empty_s.get(tier, 0.0)) + dt


## The longest stretch with nothing finished between `start` and `end`: [seconds, where it began].
static func longest_gap(finished: Array, start: float, end: float) -> Array[float]:
	var marks: Array = finished.duplicate()
	marks.sort()
	marks.append(end)
	var prev: float = start
	var best: float = 0.0
	var from: float = start
	for t: float in marks:
		if t - prev > best:
			best = t - prev
			from = prev
		prev = maxf(prev, t)
	return [best, from]


## One row per tier, then one for all tiers together.
func table(goals: Goals, start: float, end: float) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var keys: Array[String] = goals.tier_ids()
	keys.append(ALL)
	for key: String in keys:
		var finished: Array = times.get(key, [])
		var gap: Array[float] = longest_gap(finished, start, end)
		rows.append({"tier": key, "done": finished.size(), "longest_gap_s": snappedf(gap[0], 0.1), "gap_from_s": snappedf(gap[1], 0.1),
			"empty_s": snappedf(float(empty_s.get(key, 0.0)), 0.1)})
	return rows


func write(report: Dictionary, goals: Goals, start: float, end: float) -> void:
	var rows: Array[Dictionary] = table(goals, start, end)
	var all_gap: float = float(rows[-1]["longest_gap_s"])
	report["goal_tiers"] = rows
	report["goal_gap_longest_s"] = all_gap
	report["goal_gap_ok"] = all_gap <= GAP_LIMIT_S
	print("[goals] tier      done  longest gap   from      no active goal")
	for row: Dictionary in rows:
		print("[goals] %-8s %5d  %7.1f min  %5.1f min  %6.1f s" % [str(row["tier"]), int(row["done"]), float(row["longest_gap_s"]) / 60.0,
			float(row["gap_from_s"]) / 60.0, float(row["empty_s"])])
	print("[goals] longest gap with no goal finished: %.1f min (limit %.1f): %s" % [all_gap / 60.0, GAP_LIMIT_S / 60.0,
		"PASS" if all_gap <= GAP_LIMIT_S else "FAIL"])
