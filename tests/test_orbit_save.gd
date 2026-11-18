extends GutTest
## [orbB] The globe's save (core/save_orbit.gd): schema upgrades, sites, positions as direction + height.


func test_schema1_upgrades_to_current() -> void:
	var od: Dictionary = {"schema": 1, "seed": 4471, "cells_n": 163842, "lumi": {"at": [0.0, 1.0, 0.0, 0.5]}}
	OrbitSave.migrate(od)
	assert_eq(int(od["schema"]), OrbitSave.SCHEMA)
	assert_eq(str(od["planet_id"]), "verdance", "B1 saves were Verdance")
	assert_eq(int(od["freq"]), 128)
	assert_true(od.has("hubs"))
	assert_eq((od["lumi"] as Dictionary)["at"], [0.0, 1.0, 0.0, 0.5], "positions untouched")


func test_empty_stays_empty() -> void:
	assert_true(OrbitSave.migrate({}).is_empty(), "no globe save: nothing to upgrade")


func test_sites_round_trip() -> void:
	var sites: Array[Dictionary] = [{"cell": 99758, "index": 0, "dir": Vector3.UP}, {"cell": 143620, "index": 1}]
	var od: Dictionary = {"sites": OrbitSave.sites_to_array(sites)}
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(od))  # as it comes back from disk
	assert_eq(OrbitSave.site_cells(parsed), PackedInt32Array([99758, 143620]))
	assert_eq(OrbitSave.hub_level({"hubs": {"1": {"level": 3}}}, 1), 3)
	assert_eq(OrbitSave.hub_level({}, 0), 1, "a hub without state starts at level 1")
