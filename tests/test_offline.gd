extends GutTest


func test_no_robots_no_income() -> void:
	var r: Dictionary = Offline.compute([], 0, 1.0, 3600.0)
	assert_eq(float(r["cubes"]), 0.0)


func test_cleaners_need_hauler_to_deliver() -> void:
	var cleaners: Array = [{"type": "scoopie", "tier": 0}, {"type": "scoopie", "tier": 0}]
	var r: Dictionary = Offline.compute(cleaners, 0, 1.0, 3600.0)
	assert_eq(float(r["cubes"]), 0.0)
	assert_gt(float(r["waiting_value"]), 0.0)
	var r2: Dictionary = Offline.compute(cleaners + [{"type": "haulbug", "tier": 0}], 0, 1.0, 3600.0)
	assert_gt(float(r2["cubes"]), 0.0)


func test_capped_at_eight_hours() -> void:
	var fleet: Array = [{"type": "scoopie", "tier": 0}, {"type": "haulbug", "tier": 0}]
	var a: Dictionary = Offline.compute(fleet, 1, 1.0, 8.0 * 3600.0)
	var b: Dictionary = Offline.compute(fleet, 1, 1.0, 80.0 * 3600.0)
	assert_almost_eq(float(a["cubes"]), float(b["cubes"]), 0.01)
	assert_almost_eq(float(a["air"]), float(b["air"]), 0.01)


func test_higher_tier_earns_more() -> void:
	var lo: Dictionary = Offline.compute([{"type": "scoopie", "tier": 0}, {"type": "haulbug", "tier": 0}], 0, 1.0, 3600.0)
	var hi: Dictionary = Offline.compute([{"type": "scoopie", "tier": 3}, {"type": "haulbug", "tier": 0}], 0, 1.0, 3600.0)
	assert_gt(float(hi["cubes"]), float(lo["cubes"]))


func test_capped_by_junk_left() -> void:
	# A clean district pays nothing offline (no closing and reopening the game for free cubes).
	var fleet: Array = [{"type": "scoopie", "tier": 0}, {"type": "haulbug", "tier": 0}]
	var none: Dictionary = Offline.compute(fleet, 0, 1.0, 8.0 * 3600.0, 0.0)
	assert_eq(float(none["cubes"]), 0.0)
	var some: Dictionary = Offline.compute(fleet, 0, 1.0, 8.0 * 3600.0, 50.0)
	assert_almost_eq(float(some["units"]), 50.0, 0.001)


## [v10guide] Critic 3: the away line says what was gained in kid words; no "hub", no advice about a
## robot the player may not have; nothing at all when nothing was gained.
func test_away_line_is_what_was_gained() -> void:
	var lone: Dictionary = Offline.compute([{"type": "scoopie", "tier": 0}], 1, 1.0, 3600.0)
	var line: String = Offline.summary_text(lone)
	var want: float = float(lone["cubes"]) + float(lone["waiting_value"])
	assert_gt(want, 1.0)
	assert_true(line.begins_with("While you were away, your robots earned "), line)
	assert_true(line.contains(Settings.fmt(BigNum.from_float(want))), line)
	for bad: String in ["hub", "Haul Bug", "stacked", "scrubbers"]:
		assert_false(line.contains(bad), "%s: %s" % [bad, line])
	assert_eq(Offline.summary_text(Offline.compute([], 1, 1.0, 3600.0)), "", "nothing gained: no line")
