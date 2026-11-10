extends GutTest
## Parked with the Museum (M1-08). These tests were part of tests/test_eggs2.gd (its before_each /
## after_each and _defs() helper apply). The catalogue half now lives in systems/exhibits.gd.

func test_museum_lists_every_collectible_kind() -> void:
	var kinds: Array = []
	var ids: Array = []
	for x: Dictionary in Museum.exhibits():
		kinds.append(str(x["kind"]))
		ids.append(str(x["id"]))
		assert_true(str(x.get("name", "")) != "", "%s has a name" % x["id"])
		assert_true(Museum.hint(x) != "", "%s has a hint" % x["id"])
		if str(x["kind"]) in ["egg", "egg_parts"]:
			assert_true(_defs().has(str(x["ref"])), "%s refers to a real egg" % x["id"])
		if str(x["kind"]) == "relic":
			assert_false(Homeward.relic_def(str(x["ref"])).is_empty(), "%s is a real relic" % x["id"])
	for k: String in ["egg_parts", "egg", "eggs", "shards", "trinkets", "relic"]:
		assert_has(kinds, k)
	for id: String in ["gnomes", "biscuit", "time_capsule", "broadcast", "shards"]:
		assert_has(ids, id)
	var cost: Dictionary = Museum.cost()
	for c: String in cost:
		assert_has(["cubes", "parts", "seeds"], c, "museum cost uses the three currencies")


func test_museum_progress_and_completion() -> void:
	var g: Dictionary = Museum.exhibit("gnomes")
	assert_eq(Museum.progress(g), Vector2i(0, 5))
	EggCollect.add("gnomes", 0)
	EggCollect.add("gnomes", 3)
	assert_eq(Museum.progress(g), Vector2i(2, 5))
	assert_false(Museum.is_full(g))
	GameState.flags["egg_tv"] = true
	assert_true(Museum.is_full(Museum.exhibit("broadcast")))
	GameState.flags["museum_built"] = true
	assert_false(Museum.complete())
	assert_false(Museum.check_complete(), "not every plinth is full")
	assert_false(bool(GameState.flags.get("museum_complete", false)))


func test_museum_unlocks_at_the_end() -> void:
	var hw: Dictionary = Homeward.state().duplicate(true)
	Homeward.state()["answered"] = false
	assert_false(Museum.unlocked(), "locked until the Cradle answers")
	assert_ne(Museum.blocker(), "")
	Homeward.state()["answered"] = true
	assert_true(Museum.unlocked())
	for k: String in hw:
		Homeward.state()[k] = hw[k]


func test_museum_builds_with_ghosts_for_missing() -> void:
	GameState.flags["museum_built"] = true
	GameState.flags["egg_tv"] = true
	EggCollect.add("gnomes", 1)
	var m := Museum.new()
	add_child_autofree(m)
	m._build_hall(false)
	assert_eq(m.plinths.size(), Museum.exhibits().size())
	assert_not_null(m.gnome_bed)
	assert_true(m.gnome_bed.figures[1].visible)
	assert_false(m.gnome_bed.figures[0].visible, "a ghost stands in the empty slot")

