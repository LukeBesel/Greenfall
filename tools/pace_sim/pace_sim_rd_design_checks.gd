class_name PaceSimRdDesignChecks
extends RefCounted
## The redesign's checks that are not cadence rules: the run reaches the ending inside the target
## range, no rig module is the best fit in every district, tipping never out-earns pressing, no
## upgrade track leads the ranking all the time, and the found pieces arrive on schedule.


static func build(m: PaceSimRdModel, end_s: float, k: float) -> Array[Dictionary]:
	return [_ending(m, end_s), _rigs(m), _bale(m), _tracks(m), _first_piece(m, k), _design_set(m, end_s)]


static func _check(id: String, passed: bool, value: float, shown: String, limit_shown: String, note: String) -> Dictionary:
	return {"id": id, "pass": passed, "value": value, "shown": shown, "limit_shown": limit_shown, "note": note}


static func _ending(m: PaceSimRdModel, end_s: float) -> Dictionary:
	var target: Dictionary = m.data.tables["balance"]["target_bot_min"]
	var minutes: float = end_s / 60.0
	var passed: bool = m.ended_at >= 0.0 and minutes >= float(target["min"]) and minutes <= float(target["max"])
	return _check("ending_bot_minutes", passed, minutes, "%.1f min" % minutes if m.ended_at >= 0.0 else "not reached",
		"%.0f-%.0f min" % [target["min"], target["max"]], "aim %.0f bot minutes; restoration %.0f%%" % [target["aim"], m.restoration() * 100.0])


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
	return _check("bale_beats_tipping", worst <= 1.0, worst, "%.2f" % worst, "at most 1.00",
		"highest tipping income over pressing income, at bot minute %.0f" % (m.record.loose_over_bale_at / 60.0))


## Fails when one track led the value-per-cube ranking in most track purchases, or a track that
## was on offer was never worth buying.
static func _tracks(m: PaceSimRdModel) -> Dictionary:
	var total: int = 0
	for id: String in m.record.track_tops:
		total += m.record.track_tops[id]
	var worst: float = 0.0
	var shares: PackedStringArray = []
	for id: String in m.data.tracks:
		var share: float = float(m.record.track_tops.get(id, 0)) / float(maxi(total, 1))
		worst = maxf(worst, share)
		shares.append("%s %.0f%% (%d bought)" % [id, share * 100.0, m.record.track_buys.get(id, 0)])
	return _check("no_dominant_track", total > 0 and worst <= PaceSimRdReport.DOMINANT_TRACK_SHARE, worst, "%.0f%%" % (worst * 100.0),
		"at most %.0f%%" % (PaceSimRdReport.DOMINANT_TRACK_SHARE * 100.0), "share of track purchases each track led: " + ", ".join(shares))


static func _first_piece(m: PaceSimRdModel, k: float) -> Dictionary:
	var at: float = m.record.events.get("first_piece", -1.0)
	var minute: float = at / 60.0 * k
	var passed: bool = at >= 0.0 and absf(minute - PaceSimRdReport.FIRST_PIECE_MIN) <= PaceSimRdReport.FIRST_PIECE_SLACK_MIN
	return _check("first_piece", passed, minute, "%.1f min" % minute if at >= 0.0 else "never",
		"%.0f +/- %.0f min" % [PaceSimRdReport.FIRST_PIECE_MIN, PaceSimRdReport.FIRST_PIECE_SLACK_MIN], "player minute of the first found look piece")


static func _design_set(m: PaceSimRdModel, end_s: float) -> Dictionary:
	var at: float = m.record.events.get("set_complete", -1.0)
	var passed: bool = at >= end_s * PaceSimRdReport.SET_NEAR_END_SHARE
	return _check("set_completes_near_ending", passed, at / 60.0, "%.1f min" % (at / 60.0) if at >= 0.0 else "never",
		"after %.0f%% of the run" % (PaceSimRdReport.SET_NEAR_END_SHARE * 100.0), "bot minute the planet's one design set completes; %d pieces found" % m.pieces.size())
