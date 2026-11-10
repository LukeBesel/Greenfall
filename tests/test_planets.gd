extends GutTest
## The planet registry and PlanetDefinition: loading, validation, switching, and the rule that a
## second planet is data only.

const FIXTURES: String = "res://tests/fixtures/planets"
## Top-level folders that may name a planet's files: tests, tools and the planets themselves.
const NOT_SHARED_DIRS: Array[String] = ["tests", "tools", "planets", "addons"]


func after_each() -> void:
	Planets.set_current(Planets.first_shipped().id)
	Planets.unregister(&"testworld")


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
	bad.tables = {"upgrades": "res://nope.json", "mystery": "res://data/currencies.json"}
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


func test_every_registered_table_of_the_first_planet_exists_and_parses() -> void:
	var first: PlanetDefinition = Planets.first_shipped()
	assert_gt(first.tables.size(), PlanetDefinition.REQUIRED_TABLES.size(), "optional tables are registered too")
	for table_name: String in first.tables:
		assert_true(first.has_table(table_name), "%s: file exists (%s)" % [table_name, first.tables[table_name]])
		assert_false(first.table(table_name).is_empty(), "%s parses and has content" % table_name)


func test_first_planet_tables_live_in_its_own_folder_and_all_are_registered() -> void:
	var first: PlanetDefinition = Planets.first_shipped()
	var data_dir: String = _data_dir(first)
	var registered: Array = first.tables.values()
	for path: String in registered:
		assert_eq(path.get_base_dir(), data_dir, "%s is inside the planet's data folder" % path)
	for file: String in _data_files(first):
		assert_has(registered, "%s/%s" % [data_dir, file], "%s is registered as a table" % file)
		assert_false(FileAccess.file_exists("res://data/%s" % file), "%s has no copy left in the global data folder" % file)


func test_planet_table_is_a_private_copy_of_the_current_planets_table() -> void:
	var copy: Dictionary = Economy.planet_table("goals")
	assert_eq(copy, Planets.current().table("goals"))
	copy["_edited_by_test"] = true
	assert_false(Planets.current().table("goals").has("_edited_by_test"), "editing the copy leaves the definition alone")
	assert_eq(Economy.planet_table("no_such_table"), {})


func test_economy_and_cached_loaders_follow_the_current_planet() -> void:
	Planets.register_dir(FIXTURES)
	assert_false(Economy.upgrade_order.is_empty())
	assert_false(Research.ids().is_empty())
	Planets.set_current(&"testworld")
	assert_eq(Economy.robot_order.size(), 0, "the dummy planet has no robots table")
	assert_eq(Research.ids().size(), 0, "a cached table is dropped when the planet changes")
	Planets.unregister(&"testworld")
	assert_eq(Planets.current(), Planets.first_shipped(), "removing the current planet falls back to the first")
	assert_false(Economy.robot_order.is_empty(), "Economy reloads for the planet it fell back to")
	assert_false(Research.ids().is_empty())


## Shared code asks the definition for planet content: it never names a planet's folder and never
## reads one of the planet's tables from the global data folder.
func test_shared_code_never_reads_planet_content_by_path() -> void:
	var first: PlanetDefinition = Planets.first_shipped()
	var needles: Array[String] = [first.resource_path.get_base_dir()]
	for file: String in _data_files(first):
		needles.append("res://data/%s" % file)
	assert_gt(needles.size(), PlanetDefinition.REQUIRED_TABLES.size(), "the planet's data folder was listed")
	var hits: Array[String] = []
	_scan_scripts("res://", needles, hits)
	assert_eq(hits, [] as Array[String], "fixed paths to planet content in shared code:\n%s" % "\n".join(hits))


func _data_dir(def: PlanetDefinition) -> String:
	return def.resource_path.get_base_dir() + "/data"


func _data_files(def: PlanetDefinition) -> Array[String]:
	var out: Array[String] = []
	for file: String in DirAccess.get_files_at(_data_dir(def)):
		if file.get_extension() == "json":
			out.append(file)
	return out


func _scan_scripts(dir_path: String, needles: Array[String], hits: Array[String]) -> void:
	for folder: String in DirAccess.get_directories_at(dir_path):
		if dir_path == "res://" and folder in NOT_SHARED_DIRS:
			continue
		_scan_scripts(dir_path.path_join(folder), needles, hits)
	for file: String in DirAccess.get_files_at(dir_path):
		if file.get_extension() != "gd":
			continue
		var path: String = dir_path.path_join(file)
		var text: String = FileAccess.get_file_as_string(path)
		for needle: String in needles:
			if text.contains(needle):
				hits.append("%s contains %s" % [path, needle])
