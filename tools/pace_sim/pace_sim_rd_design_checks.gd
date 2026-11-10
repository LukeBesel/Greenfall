class_name PaceSimRdDesignChecks
extends RefCounted
## The redesign's checks that are not cadence rules: the run reaches the ending inside the target
## range, no rig module is the best fit in every district, tipping never out-earns pressing and
## any pressed bale pays more than a loose load, no upgrade track leads the ranking most of the
## time at equal prices, the found pieces arrive on schedule, the authored early goal lands in
## time, and the rocket is a ladder through the launch city, not a wall after it.

## The launch may trail the last city's last stage by at most this (player seconds: the goal-gap rule).
const ROCKET_WAIT_MAX_S: float = 240.0


static func build(m: PaceSimRdModel, end_s: float, k: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = [_ending(m, end_s), _rigs(m), _bale(m), _pressed(m), _tracks(m), _first_piece(m, k), _design_set(m, end_s)]
	out.append_array(_authored_goals(m, k))
	if not m.rocket_parts().is_empty():
		out.append(_rocket(m, end_s, k))
	return out


static func _check(id: String, passed: bool, value: float, shown: String, limit_shown: String, note: String) -> Dictionary:
	return {"id": id, "pass": passed, "value": value, "shown": shown, "limit_shown": limit_shown, "note": note}


static func _ending(m: PaceSimRdModel, end_s: float) -> Dictionary:
	var target: Dictionary = m.data.tables["balance"]["target_bot_min"]
	var minutes: float = end_s / 60.0
	var passed: bool = m.ended_at >= 0.0 and minutes >= float(target["min"]) and minutes <= float(target["max"])
	var aim: float = float(target["aim"])
	var off: float = (aim - minutes) / (aim - float(target["min"])) if minutes < aim else (minutes - aim) / (float(target["max"]) - aim)
	return PaceSimRdReport.used(_check("ending_bot_minutes", passed, minutes, "%.1f min" % minutes if m.ended_at >= 0.0 else "not reached",
		"%.0f-%.0f min" % [target["min"], target["max"]], "aim %.0f bot minutes; restoration %.0f%%" % [target["aim"], m.restoration() * 100.0]), off)


## Fails when one module of a slot is the best fit in every district that was judged.
static func _rigs(m: PaceSimRdModel) -> Dictionary:
	var dominant: PackedStringArray = []
	var summary: PackedStringArray = []
	for slot: Variant in m.data.tables["rigs"]["slots"]:
		var seen: Dictionary[String, int] = {}
		for district: String in m.record.rig_best:
			var best: String = str(m.record.rig_best[district].get(str(slot), ""))
			seen[best] = seen.get(best, 0) + 1
		var parts: PackedStringArray = []
		for id: String in seen:
			parts.append("%s x%d" % [id, seen[id]])
			if seen[id] == m.record.rig_best.size() and seen[id] > 1:
				dominant.append(id)
		summary.append("%s: %s" % [slot, ", ".join(parts)])
	return _check("rig_no_dominant_module", dominant.is_empty() and not m.record.rig_best.is_empty(), float(dominant.size()),
		"%d dominant" % dominant.size(), "0", "best fit by district, " + "; ".join(summary))


static func _bale(m: PaceSimRdModel) -> Dictionary:
	var worst: float = m.record.loose_over_bale
	return PaceSimRdReport.used(_check("bale_beats_tipping", worst <= 1.0, worst, "%.2f" % worst, "at most 1.00",
		"highest tipping income over pressing income, at bot minute %.0f" % (m.record.loose_over_bale_at / 60.0)), worst)


## Any pressed bale, the worst a player makes included, pays more than tipping the same load loose.
static func _pressed(m: PaceSimRdModel) -> Dictionary:
	var worst: float = m.data.num("balance.hand.bale_mult_worst")
	var loose: float = m.data.num("balance.hand.loose_mult")
	return _check("pressed_bale_pays_more", worst > loose, worst / loose, "x%.2f against x%.2f" % [worst, loose], "worst bale above loose",
		"payout multiplier of the worst pressed bale against a loose load (a perfect bale pays x%.2f)" % m.data.kept_bale_mult)


## Fails when, with every open track priced the same, one track was the best buy in more than
## half of the track purchases, or a track on offer was never bought.
static func _tracks(m: PaceSimRdModel) -> Dictionary:
	var total: float = 0.0
	for id: String in m.record.track_tops_equal:
		total += m.record.track_tops_equal[id]
	var worst: float = 0.0
	var unbought: int = 0
	var shares: PackedStringArray = []
	for id: String in m.data.tracks:
		var share: float = m.record.track_tops_equal.get(id, 0.0) / maxf(total, 1.0)
		worst = maxf(worst, share)
		if m.record.track_buys.get(id, 0) == 0:
			unbought += 1
		shares.append("%s %.0f%% (at its real price %.0f%%, %d bought)" % [id, share * 100.0,
			float(m.record.track_tops.get(id, 0)) / maxf(total, 1.0) * 100.0, m.record.track_buys.get(id, 0)])
	return PaceSimRdReport.used(_check("no_dominant_track", total > 0.0 and unbought == 0 and worst <= PaceSimRdReport.DOMINANT_TRACK_SHARE, worst, "%.0f%%" % (worst * 100.0),
		"at most %.0f%%" % (PaceSimRdReport.DOMINANT_TRACK_SHARE * 100.0), "share of track purchases each track led at equal prices: " + ", ".join(shares)),
		worst / PaceSimRdReport.DOMINANT_TRACK_SHARE)


## One check per authored district-sized goal (goals.json district_goals): done by its minute.
static func _authored_goals(m: PaceSimRdModel, k: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Variant in m.data.tables["goals"].get("district_goals", []):
		var goal: Dictionary = row
		var at: float = m.record.events.get(str(goal["event"]), -1.0)
		var minute: float = at / 60.0 * k
		out.append(PaceSimRdReport.used(_check("goal_" + str(goal["id"]), at >= 0.0 and minute <= float(goal["max_player_min"]), minute,
			"%.1f min" % minute if at >= 0.0 else "never", "by minute %.0f" % float(goal["max_player_min"]),
			"player minute the district-sized goal '%s' is done" % str(goal["label"])), minute / float(goal["max_player_min"])))
	return out


## The rocket is the launch city's goal ladder: its last part is fitted no later than a goal gap
## after the last city thrives.
static func _rocket(m: PaceSimRdModel, end_s: float, k: float) -> Dictionary:
	var thriving: float = m.record.events.get("all_cities_thriving", -1.0)
	var done: float = m.record.events.get("rocket_complete", -1.0)
	var wait: float = maxf(0.0, done - thriving) * k if thriving >= 0.0 and done >= 0.0 else INF
	var steps: PackedStringArray = []
	var parts_cost: float = 0.0
	for i: int in m.rocket_parts().size():
		parts_cost += float(m.rocket_parts()[i]["parts"])
		var at: float = m.record.events.get("rocket_fit:%d" % (i + 1), -1.0)
		steps.append("-" if at < 0.0 else "%.0f" % (at / 60.0 * k))
	return PaceSimRdReport.used(_check("rocket_is_a_ladder", done >= 0.0 and wait <= ROCKET_WAIT_MAX_S, wait, "%.0f s" % wait if done >= 0.0 else "not built",
		"at most %.0f s" % ROCKET_WAIT_MAX_S, "player seconds the launch waits on the rocket after the last city thrives; parts fitted at player minutes [%s]; the rocket costs %.0f Parts of %.0f earned (%.0f%%); run ends at %.1f" % [
			", ".join(steps), parts_cost, m.parts_earned, parts_cost / maxf(m.parts_earned, 1.0) * 100.0, end_s / 60.0 * k]), wait / ROCKET_WAIT_MAX_S)


static func _first_piece(m: PaceSimRdModel, k: float) -> Dictionary:
	var at: float = m.record.events.get("first_piece", -1.0)
	var minute: float = at / 60.0 * k
	var passed: bool = at >= 0.0 and absf(minute - PaceSimRdReport.FIRST_PIECE_MIN) <= PaceSimRdReport.FIRST_PIECE_SLACK_MIN
	return PaceSimRdReport.used(_check("first_piece", passed, minute, "%.1f min" % minute if at >= 0.0 else "never",
		"%.0f +/- %.0f min" % [PaceSimRdReport.FIRST_PIECE_MIN, PaceSimRdReport.FIRST_PIECE_SLACK_MIN], "player minute of the first found look piece"),
		absf(minute - PaceSimRdReport.FIRST_PIECE_MIN) / PaceSimRdReport.FIRST_PIECE_SLACK_MIN)


static func _design_set(m: PaceSimRdModel, end_s: float) -> Dictionary:
	var at: float = m.record.events.get("set_complete", -1.0)
	var passed: bool = at >= end_s * PaceSimRdReport.SET_NEAR_END_SHARE
	return _check("set_completes_near_ending", passed, at / 60.0, "%.1f min" % (at / 60.0) if at >= 0.0 else "never",
		"after %.0f%% of the run" % (PaceSimRdReport.SET_NEAR_END_SHARE * 100.0), "bot minute the planet's one design set completes; %d pieces found" % m.pieces.size())
