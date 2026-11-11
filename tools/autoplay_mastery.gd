class_name AutoplayMastery
extends RefCounted
## The bot's side of mastery (systems/mastery.gd): it counts who cleared what, notes when each
## mastery level came, and tells the bot which kind it should work by hand next so the crew is
## not left waiting on a kind Lumi has not learnt.
##
## Report keys it writes (screenshots/autoplay_report.json): mastery {kind: level},
## mastery_times_s {"kind:level": game seconds}, hand_units, crew_units, hand_share (of all
## cleaning by volume), and hand_share_min_window (the lowest share over any WINDOW_S of play in
## which robots cleaned anything).

const WINDOW_S: float = 300.0
const SAMPLE_S: float = 30.0

var hand_units: float = 0.0
var crew_units: float = 0.0
var times: Dictionary = {}
var _samples: Array[Vector3] = []  # (game seconds, hand units, crew units)
var _sample_t: float = -SAMPLE_S


func on_cleared(_kind: String, amount: float, by_player: bool) -> void:
	if by_player:
		hand_units += amount
	else:
		crew_units += amount


func on_gained(kind: String, level: int, now: float) -> void:
	times["%s:%d" % [kind, level]] = now


## Call about once a second with the game time: keeps the samples the window share is read from.
func sample(now: float) -> void:
	if now - _sample_t < SAMPLE_S:
		return
	_sample_t = now
	_samples.append(Vector3(now, hand_units, crew_units))


func hand_share() -> float:
	var total: float = hand_units + crew_units
	return hand_units / total if total > 0.0 else 1.0


## The lowest hand share over any WINDOW_S stretch (1 when robots never cleaned anything).
func lowest_window_share() -> float:
	var worst: float = 1.0
	var steps: int = int(WINDOW_S / SAMPLE_S)
	for i: int in range(steps, _samples.size()):
		var hand: float = _samples[i].y - _samples[i - steps].y
		var crew: float = _samples[i].z - _samples[i - steps].z
		if hand + crew > 0.0:
			worst = minf(worst, hand / (hand + crew))
	return worst


## The kind the bot should work by hand now: one Lumi has the tool for, that robots may not work
## yet, and that is not the base kind (plain cleaning teaches that). held: kinds worked with a
## tool (true) or scooped kinds (false). "" when there is none.
static func kind_to_learn(mastery: Mastery, pollution: Pollution, held: bool) -> String:
	if mastery == null or pollution == null or not mastery.enabled():
		return ""
	for id: String in mastery.kinds():
		if id == pollution.base_id() or mastery.robots_can_work(id) or not pollution.can_work(id):
			continue
		if (str(pollution.kind(id)["work"]) == Pollution.WORK_HELD) == held:
			return id
	return ""


func write(report: Dictionary, mastery: Mastery) -> void:
	var levels: Dictionary = {}
	if mastery != null:
		for id: String in mastery.kinds():
			levels[id] = mastery.level(id)
	report["mastery"] = levels
	report["mastery_times_s"] = times
	report["hand_units"] = snappedf(hand_units, 1.0)
	report["crew_units"] = snappedf(crew_units, 1.0)
	report["hand_share"] = snappedf(hand_share(), 0.001)
	report["hand_share_min_window"] = snappedf(lowest_window_share(), 0.001)
