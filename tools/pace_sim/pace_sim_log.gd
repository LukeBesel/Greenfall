class_name PaceSimLog
extends RefCounted
## What happened in a run, as plain records: beats (first time something happened), small wins,
## purchases, goals, objectives, new mechanics, and one row per minute for the time series.

const SAMPLE_S: float = 60.0
## Hex counts that get their own beat.
const HEX_BEATS: Array[int] = [1, 2, 3, 5, 10, 20, 50, 74, 100, 200, 400, 800]

var beats: Dictionary[String, float] = {}
var wins: PackedFloat64Array = []
var purchases: Array[Dictionary] = []
var goals: Array[Dictionary] = []
var objectives: Array[Dictionary] = []
var mechanics: Array[Dictionary] = []
var hex_times: PackedFloat64Array = []
var minutes: Array[Dictionary] = []

var _next_sample: float = SAMPLE_S
var _earned_at_sample: float = 0.0


## Records the first time `id` happens; later calls are ignored.
func beat(id: String, t: float) -> void:
	if not beats.has(id):
		beats[id] = t


func win(t: float, _kind: String) -> void:
	if wins.is_empty() or wins[wins.size() - 1] != t:
		wins.append(t)


func purchase(t: float, kind: String, id: String, cubes: float) -> void:
	purchases.append({"t": t, "kind": kind, "id": id, "cubes": cubes})
	win(t, "purchase")


func goal(t: float, id: String) -> void:
	goals.append({"t": t, "id": id})


func objective(t: float, id: String) -> void:
	objectives.append({"t": t, "id": id})
	win(t, "objective")


func mechanic(t: float, id: String) -> void:
	mechanics.append({"t": t, "id": id})


func hex(t: float, n: int) -> void:
	hex_times.append(t)
	if n in HEX_BEATS:
		beat("hexes_%d" % n, t)


func sample(m: PaceSimModel) -> void:
	if m.t < _next_sample:
		return
	_next_sample += SAMPLE_S
	minutes.append({
		"minute": int(round(m.t / 60.0)), "cubes": m.cubes, "income_rate": (m.earned - _earned_at_sample) / SAMPLE_S,
		"hexes": m.work.hexes_done, "robots": m.robot_total(), "upgrades": int(m.stat_of("upgrades_bought")),
		"parts": m.parts, "hand_hexes": m.work.hand_hexes, "crew_hexes": m.work.crew_hexes, "earned": m.earned,
		"hub": m.hub_level, "walk_s": m.work.walk_s,
	})
	_earned_at_sample = m.earned


## The time series as CSV text.
func csv() -> String:
	var lines: PackedStringArray = ["minute,cubes,income_rate,hexes,robots,upgrades_bought,parts,hand_hexes,crew_hexes,base_level"]
	for row: Dictionary in minutes:
		lines.append("%d,%.0f,%.2f,%d,%d,%d,%.0f,%.2f,%.2f,%d" % [row["minute"], row["cubes"], row["income_rate"], row["hexes"],
			row["robots"], row["upgrades"], row["parts"], row["hand_hexes"], row["crew_hexes"], row["hub"]])
	return "\n".join(lines) + "\n"
