extends GutTest
## The planet registry and PlanetDefinition: loading, validation, switching, and the rule that a
## second planet is data only.

const FIXTURES: String = "res://tests/fixtures/planets"


func after_each() -> void:
	Planets.unregister(&"testworld")
	Planets.set_current(Planets.first_shipped().id)


func test_first_planet_is_registered_and_current() -> void:
	var first: PlanetDefinition = Planets.first_shipped()
	assert_not_null(first, "a shipped planet exists")
	assert_eq(Planets.current(), first)
	assert_eq(first.validate().size(), 0, "the first planet validates: %s" % "; ".join(first.validate()))


func test_every_required_table_of_the_first_planet_parses() -> void:
	var first: PlanetDefinition = Planets.first_shipped()
	for table_name: String in PlanetDefinition.REQUIRED_TABLES:
		assert_true(first.has_table(table_name), table_name)
		assert_false(first.table(table_name).is_empty(), "%s has content" % table_name)


func test_dummy_planet_loads_from_its_folder_alone() -> void:
	assert_eq(Planets.register_dir(FIXTURES), 1)
	assert_true(Planets.has(&"testworld"))
	var dummy: PlanetDefinition = Planets.by_id(&"testworld")
	assert_eq(dummy.cell_count(), 10 * 16 * 16 + 2)
	assert_false(dummy.shipped, "the dummy never ships")
	assert_ne(Planets.first_shipped().id, &"testworld")


func test_switching_planet_emits_and_changes_current() -> void:
	Planets.register_dir(FIXTURES)
	watch_signals(Planets)
	assert_true(Planets.set_current(&"testworld"))
	assert_eq(Planets.current_id(), &"testworld")
	assert_signal_emitted(Planets, "current_changed")
	assert_false(Planets.set_current(&"no_such_planet"))
	assert_push_error("unknown planet")
	assert_eq(Planets.current_id(), &"testworld", "a bad id leaves the current planet alone")


func test_invalid_definitions_are_rejected_with_reasons() -> void:
	var bad := PlanetDefinition.new()
	bad.id = &"Bad Id"
	bad.globe_frequency = 0
	bad.tables = {"upgrades": "res://nope.json", "mystery": "res://data/junk.json"}
	var errors: String = "; ".join(bad.validate())
	for needle: String in ["lowercase", "display_name", "globe_frequency", "missing required table 'pollution'", "file not found", "unknown table 'mystery'"]:
		assert_string_contains(errors, needle)
	assert_false(Planets.register(bad, "test"))
	assert_push_error("is invalid")


func test_missing_optional_table_is_empty_not_an_error() -> void:
	Planets.register_dir(FIXTURES)
	var dummy: PlanetDefinition = Planets.by_id(&"testworld")
	assert_false(dummy.has_table("rigs"))
	assert_eq(dummy.table("rigs"), {})
