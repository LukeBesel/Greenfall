extends GutTest
## Parked in task M3-13 with the Collection's trinkets (parked/side/trinkets/): cut from
## tests/test_events.gd (it used its before_each / after_each). It does not run.

# --- Collection ----------------------------------------------------------------------------------

func test_collection_roll_and_grant() -> void:
	assert_eq(Collection.count(), 0)
	var all: Array[String] = Collection.unfound("capsule")
	assert_true(all.size() >= 3)
	var id: String = Collection.roll("capsule", 0.0)
	assert_true(Collection.grant(id, true))
	assert_false(Collection.grant(id, true), "no duplicates")
	assert_false(id in Collection.unfound("capsule"))
	for t: String in Collection.unfound("capsule"):
		Collection.grant(t, true)
	assert_eq(Collection.roll("capsule", 0.5), "", "complete source rolls nothing")
	for t: Dictionary in Collection.defs():
		assert_ne(Collection.source_name(str(t["source"])), "", "every trinket has a source")
