extends GutTest
## [late] The newer curiosities (data/eggs.json, story/egg_props_late.gd): 40+ in all, a prop for
## every one, frontier eggs only in their frontier, other-world eggs (a parked feature) never placed,
## Codex groups and WREN lines for each.

func _defs() -> Array:
	return Economy.planet_table("eggs")["eggs"]


func _order_and_defs() -> Array:
	var order: Array[String] = []
	var defs: Dictionary = {}
	for e: Dictionary in _defs():
		order.append(str(e["id"]))
		defs[str(e["id"])] = e
	return [order, defs]


func test_forty_plus_with_props_and_lines() -> void:
	var all: Array = _defs()
	assert_gte(all.size(), 40)
	var wren: Dictionary = Economy.planet_table("guide_lines")
	for e: Dictionary in all:
		var n: Node3D = EggProps.build(str(e["kind"]))
		assert_gt(n.get_child_count(), 0, "%s has a real prop" % e["id"])
		n.free()
		for k: String in ["name", "lore", "toast", "hint", "reward"]:
			assert_true(e.has(k), "%s has %s" % [e["id"], k])
	for id: String in ["sand_piano", "snow_bot", "bottle_message", "welcome_home", "crossword", "hopscotch", "balloon", "mailbox", "bonsai", "listening_dish", "older_pod", "heirloom_tin"]:
		assert_true(wren.has("egg_" + id), "WREN has a line for %s" % id)


func test_frontier_eggs_only_in_their_frontier() -> void:
	var od: Array = _order_and_defs()
	for b: String in ["dust_flats", "frozen_port", "sunken_city", "cradle_landing"]:
		var ids: Array[String] = EasterEggs.district_eggs(od[0], od[1], 5, 9000, 10, true, b, 4)
		var mine: Array[String] = EggPropsLate.frontier_eggs(od[0], od[1], b)
		assert_eq(mine.size(), 1, "one frontier egg for %s" % b)
		assert_true(mine[0] in ids, "%s gets its own egg" % b)
	for seed_v: int in [9000, 9001, 9002, 9003, 9004, 9005]:
		for ids: Array[String] in [EasterEggs.district_eggs(od[0], od[1], 3, seed_v, 10), EasterEggs.district_eggs(od[0], od[1], 3, seed_v, 10, true, "rustlands", 4)]:
			for id: String in ids:
				assert_false(str(od[1][id].get("where", "")) in ["frontier", "new_world"], "%s stays out of ordinary districts" % id)


func test_other_world_eggs_are_never_placed_or_listed() -> void:
	var od: Array = _order_and_defs()
	var other: Array[String] = []
	for id: String in od[0]:
		if str(od[1][id].get("where", "")) == "new_world":
			other.append(id)
	assert_gt(other.size(), 0, "the table still holds the parked eggs")
	var listed: Array = Codex.egg_defs().map(func(e: Dictionary) -> String: return str(e["id"]))
	for hub: int in 6:
		var placed: Array[String] = EasterEggs.district_eggs(od[0], od[1], hub, 4471, 10, hub > 2, "")
		for id: String in other:
			assert_false(id in placed, "%s is never placed (hub %d)" % [id, hub])
	for id: String in other:
		assert_false(id in listed, "%s is not a curiosity the Codex counts" % id)


func test_codex_groups_cover_every_egg() -> void:
	var groups: Array[String] = ["Old Town", "Any district", "Wilderness bases", "Frontiers"]
	for c: Dictionary in Codex.curiosities():
		var ok: bool = false
		for g: String in groups:
			if str(c["where"]).begins_with(g):
				ok = true
		assert_true(ok, "%s shows in a Codex group (%s)" % [c["id"], c["where"]])
