class_name AutoplayCadence
extends RefCounted
## The bot's cadence table: one row per city (district) of the planet, in play order, with the
## beats the pacing rules (docs/PLAN.md section 9) are read from.
##
## Beats (game seconds): arrive_s (Lumi first stands in the city; the first city counts from the
## bot taking control), first_hex_s (first hex of the city cleaned), mastery1_s (Lumi learns the
## city's new pollution kind: the first kind it lists that no earlier city has), source_s (its
## source shut down), stage4_s and stage5_s (the city reaches regrowth stage 4 and 5). Crew:
## crew_arrive (robots owned on arrival) and crew_leave (when the next city is reached, or at the
## end).
##
## The city's span runs from its arrival to the next city's arrival (the last city's to the end
## of the run). Over that span: purchases, longest_wait_s (between purchases, counted from the
## span's start), goal_gap_s (between finished goals), cubes_max (most cubes held), parts_max and
## parts_end (Parts held).
##
## Report keys it writes (screenshots/autoplay_report.json): cadence (the rows), launch_s.
## A staged run (--save-dir) keeps the table across stages in its own file (to_dict / from_dict).

## Game seconds between kept samples of cubes and Parts held.
const SAMPLE_S: float = 5.0

var rows: Array[Dictionary] = []
var launch_s: float = -1.0
var _index: Dictionary[String, int] = {}
var _kind_city: Dictionary[String, int] = {}
var _spends: Array[float] = []
var _goals: Array[float] = []
## (game seconds, cubes held, Parts held)
var _samples: Array[Vector3] = []


## cities: [{id, name, pollution: [kind, ...]}] in play order.
func setup(cities: Array[Dictionary]) -> void:
	rows.clear()
	_index.clear()
	_kind_city.clear()
	for c: Dictionary in cities:
		var i: int = rows.size()
		var id: String = str(c.get("id", ""))
		_index[id] = i
		var new_kind: String = ""
		for k: Variant in c.get("pollution", []):
			if not _kind_city.has(str(k)):
				_kind_city[str(k)] = i
				if new_kind == "":
					new_kind = str(k)
		rows.append({"city": id, "name": str(c.get("name", id)), "kind": new_kind, "arrive_s": -1.0, "first_hex_s": -1.0,
			"mastery1_s": -1.0, "source_s": -1.0, "stage4_s": -1.0, "stage5_s": -1.0, "crew_arrive": -1, "crew_leave": -1})


func has_city(id: String) -> bool:
	return _index.has(id)


func arrived(id: String) -> bool:
	return _index.has(id) and float(rows[_index[id]]["arrive_s"]) >= 0.0


func arrive(id: String, now: float, crew: int) -> void:
	if not _index.has(id) or arrived(id):
		return
	var row: Dictionary = rows[_index[id]]
	row["arrive_s"] = now
	row["crew_arrive"] = crew
	var prev: int = _last_arrived_before(_index[id])
	if prev >= 0 and int(rows[prev]["crew_leave"]) < 0:
		rows[prev]["crew_leave"] = crew


func hex_cleaned(id: String, now: float) -> void:
	_first(id, "first_hex_s", now)


func mastery_gained(kind: String, level: int, now: float) -> void:
	if level >= 1 and _kind_city.has(kind) and float(rows[_kind_city[kind]]["mastery1_s"]) < 0.0:
		rows[_kind_city[kind]]["mastery1_s"] = now


func source_shut(id: String, now: float) -> void:
	_first(id, "source_s", now)


func stage_reached(id: String, stage: int, now: float) -> void:
	if stage >= 4:
		_first(id, "stage4_s", now)
	if stage >= 5:
		_first(id, "stage5_s", now)


func spent(now: float) -> void:
	_spends.append(now)


func goal_done(now: float) -> void:
	_goals.append(now)


## Cubes and Parts held at game time `now` (the bot calls it once a second; a sample is kept
## every SAMPLE_S, and always when it is a new high).
func sample(now: float, cubes: float, parts: float) -> void:
	if not _samples.is_empty():
		var last: Vector3 = _samples[-1]
		if now - last.x < SAMPLE_S and cubes <= last.y and parts <= last.z:
			return
	_samples.append(Vector3(now, cubes, parts))


func launched(now: float) -> void:
	if launch_s < 0.0:
		launch_s = now


## The longest stretch inside [start, end] with none of `times` in it, counted from `start`.
static func longest_wait(times: Array[float], start: float, end: float) -> float:
	var prev: float = start
	var best: float = 0.0
	for t: float in times:
		if t < start:
			continue
		if t > end:
			break
		best = maxf(best, t - prev)
		prev = t
	return maxf(best, end - prev)


## Fills each arrived city's span numbers up to game time `end` and returns the rows.
func table(end: float, crew_now: int) -> Array[Dictionary]:
	var spends: Array[float] = _spends.duplicate()
	spends.sort()
	var goals: Array[float] = _goals.duplicate()
	goals.sort()
	for i: int in rows.size():
		var row: Dictionary = rows[i]
		var start: float = float(row["arrive_s"])
		if start < 0.0:
			continue
		var stop: float = _span_end(i, end)
		if int(row["crew_leave"]) < 0 and stop >= end:
			row["crew_leave"] = crew_now
		var n: int = 0
		for t: float in spends:
			if t >= start and t <= stop:
				n += 1
		row["span_s"] = snappedf(stop - start, 0.1)
		row["purchases"] = n
		row["longest_wait_s"] = snappedf(longest_wait(spends, start, stop), 0.1)
		row["goal_gap_s"] = snappedf(longest_wait(goals, start, stop), 0.1)
		var cubes_max: float = 0.0
		var parts_max: float = 0.0
		var parts_end: float = 0.0
		for s: Vector3 in _samples:
			if s.x >= start and s.x <= stop:
				cubes_max = maxf(cubes_max, s.y)
				parts_max = maxf(parts_max, s.z)
				parts_end = s.z
		row["cubes_max"] = snappedf(cubes_max, 1.0)
		row["parts_max"] = snappedf(parts_max, 1.0)
		row["parts_end"] = snappedf(parts_end, 1.0)
	return rows


func write(report: Dictionary, end: float, crew_now: int) -> void:
	report["cadence"] = table(end, crew_now)
	report["launch_s"] = launch_s
	print("[cadence] city          arrive  1st hex  mastery1  source  stage4  stage5  crew in/out  buys  longest wait  goal gap  cubes max  parts max/end")
	for row: Dictionary in rows:
		if float(row["arrive_s"]) < 0.0:
			print("[cadence] %-12s  not reached" % str(row["name"]))
			continue
		print("[cadence] %-12s %7s %8s %9s %7s %7s %7s  %4d/%-4d %6d %10.0f s %7.0f s %9.0f %7.0f/%.0f" % [str(row["name"]), _min(row["arrive_s"]),
			_min(row["first_hex_s"]), _min(row["mastery1_s"]), _min(row["source_s"]), _min(row["stage4_s"]), _min(row["stage5_s"]),
			int(row["crew_arrive"]), int(row["crew_leave"]), int(row["purchases"]), float(row["longest_wait_s"]), float(row["goal_gap_s"]),
			float(row["cubes_max"]), float(row["parts_max"]), float(row["parts_end"])])
	print("[cadence] launch: %s (game minutes; - = not yet)" % _min(launch_s))


## Everything the table is built from, for a staged run's next stage.
func to_dict() -> Dictionary:
	var samples: Array = []
	for v: Vector3 in _samples:
		samples.append([v.x, v.y, v.z])
	return {"rows": rows, "launch_s": launch_s, "spends": _spends, "goals": _goals, "samples": samples}


## Restores to_dict() over a table set up for the same cities (rows of other cities are ignored).
func from_dict(d: Dictionary) -> void:
	for row: Variant in d.get("rows", []):
		if row is Dictionary and _index.has(str((row as Dictionary).get("city", ""))):
			rows[_index[str(row["city"])]].merge(row, true)
	launch_s = float(d.get("launch_s", launch_s))
	for t: Variant in d.get("spends", []):
		_spends.append(float(t))
	for t: Variant in d.get("goals", []):
		_goals.append(float(t))
	for v: Variant in d.get("samples", []):
		if v is Array and (v as Array).size() == 3:
			_samples.append(Vector3(float(v[0]), float(v[1]), float(v[2])))


## Game seconds as minutes for the table ("-" when the beat has not come).
static func _min(v: Variant) -> String:
	var s: float = float(v)
	return "-" if s < 0.0 else "%.1f" % (s / 60.0)


func _first(id: String, key: String, now: float) -> void:
	if _index.has(id) and float(rows[_index[id]][key]) < 0.0:
		rows[_index[id]][key] = now


func _last_arrived_before(i: int) -> int:
	var best: int = -1
	var best_t: float = -1.0
	for j: int in rows.size():
		var t: float = float(rows[j]["arrive_s"])
		if j != i and t >= 0.0 and t > best_t:
			best_t = t
			best = j
	return best


## A span ends when the next city (by arrival time) is reached.
func _span_end(i: int, end: float) -> float:
	var start: float = float(rows[i]["arrive_s"])
	var stop: float = end
	for row: Dictionary in rows:
		var t: float = float(row["arrive_s"])
		if t > start and t < stop:
			stop = t
	return stop
