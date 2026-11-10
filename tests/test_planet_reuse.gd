extends GutTest
## The reuse check (docs/STYLE.md section 3): a second planet is data only. With the dummy planet
## from tests/fixtures/planets/testworld/ as the current planet, the real world scene builds
## headless, places the player, runs for a few seconds, saves, and loads back into a second world.
## Nothing here names the first planet: whatever the build needs comes from the fixture's tables.

const FIXTURES: String = "res://tests/fixtures/planets"
const DUMMY: StringName = &"testworld"
const WORLD_SCENE: String = "res://scenes/slice.tscn"
## A slot no other test or tool writes.
const SLOT: int = 8
const BUILD_FRAMES: int = 600
const RUN_SECONDS: float = 3.0

var _slot_before: int = 0
var _enabled_before: bool = true
var _world: Node
## EventBus connections that existed before the world was built (signal name -> callables).
var _bus_before: Dictionary = {}


func before_each() -> void:
	_bus_before = _bus_connections()
	_slot_before = SaveManager.slot
	_enabled_before = SaveManager.enabled
	SaveManager.slot = SLOT
	SaveManager.enabled = true
	SaveManager.delete_save()
	GameState.new_game()
	Planets.register_dir(FIXTURES)
	Planets.set_current(DUMMY)
	GameState.new_game()


func after_each() -> void:
	if is_instance_valid(_world):
		_world.free()
	_drop_new_bus_connections()
	SaveManager.delete_save()
	SaveManager.slot = _slot_before
	SaveManager.enabled = _enabled_before
	GameState.reload_in_memory = false
	Planets.set_current(Planets.first_shipped().id)
	Planets.unregister(DUMMY)
	GameState.new_game()
	Engine.time_scale = 1.0
	get_tree().paused = false


func test_dummy_planet_validates_from_its_own_folder() -> void:
	var dummy: PlanetDefinition = Planets.current()
	assert_eq(dummy.id, DUMMY)
	assert_eq(dummy.validate().size(), 0, "; ".join(dummy.validate()))
	var folder: String = dummy.resource_path.get_base_dir()
	for table_name: String in dummy.tables:
		assert_true(dummy.tables[table_name].begins_with(folder), "%s comes from the fixture folder" % table_name)
	for script: Script in [dummy.env_script, dummy.sites_script]:
		if script:
			assert_true(script.resource_path.begins_with(folder), "%s comes from the fixture folder" % script.resource_path)


func test_world_builds_runs_saves_and_loads_on_the_dummy_planet() -> void:
	_world = await _build_world()
	var globe: OrbitPlanet = _globe(_world)
	assert_not_null(globe, "the globe was built")
	if globe == null:
		return
	var dummy: PlanetDefinition = Planets.current()
	assert_eq(globe.planet_id, String(DUMMY), "the globe is the dummy planet's")
	assert_eq(globe.grid.freq, dummy.globe_frequency)
	assert_eq(globe.grid.cell_count(), dummy.cell_count())
	assert_eq(globe.sites.size(), dummy.hub_count, "one site per hub of the definition")
	assert_eq(str(_world.get("district_name")), dummy.display_name)
	# The start site came from the dummy's own sites table and sites script.
	var start: SitePrefab = globe.site_manager.prefab(0)
	assert_eq(start.site_id, "test_pad")
	assert_true(start.is_built, "the start site was built")
	assert_not_null(start.content.find_child("TestPadMarker", true, false), "by the fixture's sites script")
	assert_not_null(start.anchor("depot"), "with the shared yard anchors")
	var player: Node3D = _world.get("patch")
	assert_not_null(player, "the player was placed")
	if player == null:
		return
	assert_almost_eq(player.global_position.length(), dummy.radius_m(), dummy.radius_m() * 0.25, "the player stands on the globe")
	# A few seconds of simulation.
	await wait_seconds(RUN_SECONDS)
	assert_true(is_instance_valid(player) and player.is_inside_tree(), "the player is still in the world")
	assert_almost_eq(player.global_position.length(), dummy.radius_m(), dummy.radius_m() * 0.25, "and still on the globe")
	# Save, then load into a second world.
	GameState.add_currency("cubes", BigNum.from_float(321.0))
	assert_true(SaveManager.save_game(), "the game saved")
	var before: Dictionary = _snapshot(_world)
	assert_eq(str(GameState.orbit.get("planet_id", "")), String(DUMMY), "the save names the dummy planet")
	_world.queue_free()
	await wait_process_frames(2)
	GameState.new_game()
	assert_true(SaveManager.load_game(), "the save loads")
	GameState.reload_in_memory = true
	_world = await _build_world()
	assert_not_null(_globe(_world), "the globe was rebuilt from the save")
	if _globe(_world) == null:
		return
	var after: Dictionary = _snapshot(_world)
	for key: String in before:
		assert_eq(after[key], before[key], "%s survives the round trip" % key)


func _globe(world: Node) -> OrbitPlanet:
	var orbit: Variant = world.get("orbit") if is_instance_valid(world) else null
	return (orbit as SliceOrbit).globe if orbit is SliceOrbit else null


## Instantiates the world scene and waits until the player exists (or BUILD_FRAMES pass).
func _build_world() -> Node:
	var world: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(world)
	for i: int in BUILD_FRAMES:
		await get_tree().process_frame
		if world.get("patch") != null and _globe(world) != null and _globe(world).start_site != null:
			break
	await wait_process_frames(5)
	return world


func _snapshot(world: Node) -> Dictionary:
	var globe: OrbitPlanet = _globe(world)
	var player: Node3D = world.get("patch")
	var cells: Dictionary = globe.cells.to_dict()
	var at: Array = globe.to_dirh(player.global_position)
	return {
		"planet_id": str(GameState.orbit.get("planet_id", "")),
		"frequency": globe.grid.freq,
		"cells": globe.grid.cell_count(),
		"seed": globe.seed_value,
		"sites": str(OrbitSave.sites_to_array(globe.sites)),
		"cell_state": hash(cells["state"]),
		"cell_junk": hash(cells["junk"]),
		"cell_level": hash(cells["level"]),
		"cubes": snappedf(GameState.get_currency("cubes").to_float(), 0.01),
		"player_direction": "%.3f,%.3f,%.3f" % [at[0], at[1], at[2]],
	}


func _bus_connections() -> Dictionary:
	var out: Dictionary = {}
	for sig: Dictionary in EventBus.get_signal_list():
		var callables: Array[Callable] = []
		for connection: Dictionary in EventBus.get_signal_connection_list(sig["name"]):
			callables.append(connection["callable"])
		out[sig["name"]] = callables
	return out


## Some systems connect lambdas to EventBus that outlive their node (they call static functions).
## A world built here must not leave them listening in the tests that run next.
func _drop_new_bus_connections() -> void:
	for sig: Dictionary in EventBus.get_signal_list():
		var known: Array[Callable] = _bus_before.get(sig["name"], [] as Array[Callable])
		for connection: Dictionary in EventBus.get_signal_connection_list(sig["name"]):
			var callable: Callable = connection["callable"]
			if not known.has(callable):
				EventBus.disconnect(sig["name"], callable)
