extends GutTest
## The future layer is pure function of seed + hex levels + hub level + cleaned share:
## same inputs give the same build, a dusty district shows nothing, and every level adds.

var layout: CityLayout
var field: HexField


func before_each() -> void:
	layout = CityLayout.new(4471, 150.0, false)
	field = HexField.new(9, 3.2, 4471, layout)
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	field.generate(types, Vector2i(6, 12))


func _levels(n: int) -> Dictionary:
	var lv: Dictionary = {}
	for id: int in field.hex_count():
		if field.hex_hub[id] == 0 and not field.is_water(id):
			lv[id] = n
	return lv


func _plan(n: int) -> Dictionary:
	return FutureLayer.plan(field, layout, _levels(n), clampi(n, 1, 5), 1.0 if n >= 1 else 0.0)


func _sig(p: Dictionary) -> Array:
	var out: Array = []
	for ch: String in FutureLayer.CHANNELS:
		var c: Dictionary = p[ch]
		out.append([ch, (c["key"] as Array).duplicate(), str(c["xf"]), str(c["col"])])
	out.append(str(p["labels"]))
	out.append(str(p["movers"]))
	return out


func test_dusty_district_shows_nothing() -> void:
	var p: Dictionary = FutureLayer.plan(field, layout, _levels(0), 1, 0.0)
	assert_eq(FutureLayer.count(p), 0)
	assert_eq(float(p["score"]), 0.0)
	assert_eq(float(p["aurora"]), 0.0)


func test_build_is_deterministic_per_level() -> void:
	for n: int in range(0, 6):
		var a: Dictionary = _plan(n)
		var b: Dictionary = _plan(n)
		assert_eq(_sig(a), _sig(b), "level %d plan differs between runs" % n)


func test_each_level_adds_and_keys_are_unique() -> void:
	var prev_keys: Dictionary = {}
	var prev_n: int = -1
	for n: int in range(0, 6):
		var p: Dictionary = _plan(n)
		var keys: Dictionary = {}
		for ch: String in FutureLayer.CHANNELS:
			for k: int in p[ch]["key"]:
				assert_false(keys.has(k), "duplicate element key at level %d" % n)
				keys[k] = true
		assert_gt(FutureLayer.count(p), prev_n, "level %d should show more than level %d" % [n, n - 1])
		# Leveling up only adds: whatever stood before is still there (so only new pieces draw in).
		for k: int in prev_keys:
			assert_true(keys.has(k), "element vanished going to level %d" % n)
		prev_keys = keys
		prev_n = FutureLayer.count(p)


func test_level_milestones() -> void:
	var p1: Dictionary = _plan(1)
	assert_gt((p1["line"]["xf"] as Array).size(), 0, "clean hexes get light seams")
	assert_eq((p1["planter"]["xf"] as Array).size(), 0)
	var p4: Dictionary = _plan(4)
	assert_gt((p4["sign"]["xf"] as Array).size(), 0, "sustained hexes get holo signs")
	var p5: Dictionary = _plan(5)
	assert_gt((p5["platform"]["xf"] as Array).size(), 0, "thriving hexes get hover platforms")
	assert_gt((p5["spire"]["xf"] as Array).size(), 0, "a thriving district grows a skyline")
	assert_gt((p5["labels"] as Array).size(), 0, "thriving hexes get holo billboards")
	assert_gt((p5["movers"] as Array).size(), 0, "drones and hover traffic")
	assert_gt(float(p5["aurora"]), 0.5)


func test_district_score_range() -> void:
	assert_eq(FutureLayer.district_score(_levels(0), 1, 0.0), 0.0)
	assert_almost_eq(FutureLayer.district_score(_levels(5), 5, 1.0), 1.0, 0.0001)
	var mid: float = FutureLayer.district_score(_levels(3), 3, 1.0)
	assert_between(mid, 0.3, 0.8)


class FakeWorld:
	extends Node
	var field: HexField
	var layout: CityLayout
	var hex_levels: HexLevels


func test_level_up_rebuilds_and_sweeps() -> void:
	var w := FakeWorld.new()
	w.field = field
	w.layout = layout
	w.hex_levels = HexLevels.new()
	w.hex_levels.levels = _levels(0)
	add_child_autofree(w)
	autofree(w.hex_levels)
	var fl := FutureLayer.new()
	w.add_child(fl)
	fl.setup(w)
	assert_eq(FutureLayer.count(fl.last_plan), 0)
	var hid: int = int(w.hex_levels.levels.keys()[0])
	w.hex_levels.levels[hid] = 2
	EventBus.hex_level_changed.emit(hid, 2)
	await wait_process_frames(2)
	assert_gt((fl.last_plan["line"]["xf"] as Array).size(), 0, "the levelled hex lights up")
	var sweeps: int = 0
	for c: Node in fl.get_children():
		if c is MeshInstance3D and c.name != "Aurora":
			sweeps += 1
	assert_eq(sweeps, 1, "one light sweep plays over the hex")
