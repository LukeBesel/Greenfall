extends SceneTree
## Writes tests/fixtures/saves/parked_v4/: a save tree as a player of the full five-planet game
## left it, for tests/test_parked_saves.gd. It takes a real Verdance save (any globe save written
## by this build) and adds what the parked features kept in it (parked/README.md):
##   p1/slot_0.save   Verdance, plus the parked features' flags, stats, goals, achievements,
##                    Codex keys, research, decor and hub state (PARKED_* below)
##   p1/slot_1.save   a second planet's world (the campaign's world slot)
##   p1/slot_9.save   a Seed of the Week run;  p1/weekly.save its record
##   p1/profile.save  the prestige profile: worlds, Heirlooms, the campaign's state; its
##                    "current" world is the second planet
##   p2/slot_0.save, p2/profile.save   a second save profile
##   profiles.cfg     the remembered profile (1)
## Run:  godot --headless --path . -s res://tools/parked_save_fixture.gd -- <path to a slot_0.save>

const OUT: String = "res://tests/fixtures/saves/parked_v4"
## What the parked features left in a Verdance save. The test reads these too.
const PARKED_FLAGS: Dictionary = {
	"seed_ark": {"wave": 2, "start": 140.0}, "late_bridge_hint": true, "museum_built": true, "arrived_from_rocket": true,
	"home_arrived_planet": 0, "home_last_seed": true, "late_start_robots": ["scoopie", "haulbug"], "egg_older_pod": true,
	"weekly_id": "2026-W45", "fabricator": {"verdance": {"built": true, "paused": false, "mix": {"scoopie": 3, "haulbug": 1}, "queue": ["scoopie"], "made": {"scoopie": 4}, "cur": "scoopie", "t": 12.5}},
}
const PARKED_STATS: Dictionary = {
	"ark_waves": 2.0, "planets_restored": 1.0, "planets_landed": 2.0, "planets_visited": 2.0, "planet_flights": 3.0, "system_pct": 24.0,
	"relics_found": 1.0, "drive_tier": 5.0, "drive_upgrades": 1.0, "worlds_seeded": 1.0, "worlds_landed": 1.0, "heirloom_levels": 3.0,
	"heirlooms_bought": 3.0, "starseeds_earned": 46.0, "weekly_chips": 2.0, "ark_bridge_opened": 1.0, "homecoming": 0.0,
}
const PARKED_GOALS: Array[String] = ["home_drive_5", "home_land_1", "ark_1", "late_bridge", "late_heirloom_1"]
const PARKED_ACHIEVEMENTS: Array[String] = ["home_landed", "ark_1", "late_bridge", "late_heirloom_1", "extras_weekly_1", "late_older_pod"]
const PARKED_CODEX: Array[String] = ["homeward:ochre_arrive", "homeward:the_answer", "sightings:first_light"]
const PARKED_DECOR: Array[Dictionary] = [{"t": "weekly_pennant", "x": 3, "z": 12, "r": 0}, {"t": "weekly_arch", "x": -4, "z": 14, "r": 1}]


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- <path to a globe slot_0.save>")
		quit(1)
		return
	var src: Dictionary = _read(args[0])
	if src.is_empty() or not (src.get("orbit") is Dictionary) or (src["orbit"] as Dictionary).is_empty():
		push_error("not a globe save: %s" % args[0])
		quit(1)
		return
	var out_dir: String = ProjectSettings.globalize_path(OUT)
	for d: String in ["p1", "p2"]:
		DirAccess.make_dir_recursive_absolute(out_dir.path_join(d))
	_write(out_dir.path_join("p1/slot_0.save"), with_parked(src))
	_write(out_dir.path_join("p1/slot_1.save"), _other_world("ochre", 61000.0))
	_write(out_dir.path_join("p1/slot_9.save"), _other_world("verdance", 300.0))
	_write(out_dir.path_join("p1/weekly.save"), {"weeks": {"2026-W45": {"best_time": 1800.0, "best_score": 3500, "done": true}}, "chips": [{"week": "2026-W45", "color": "#e8a33d"}]})
	_write(out_dir.path_join("p1/profile.save"), _profile("First", 1))
	_write(out_dir.path_join("p2/slot_0.save"), _other_world("verdance", 77.0))
	_write(out_dir.path_join("p2/profile.save"), _profile("Second", 0))
	var cf := ConfigFile.new()
	cf.set_value("profiles", "current", 1)
	cf.save(out_dir.path_join("profiles.cfg"))
	print("[fixture] wrote %s (Verdance: %s cubes, %d hexes cleaned)" % [OUT, str(src["currencies"].get("cubes")), int(src["stats"].get("hexes_cleaned", 0))])
	quit()


## The Verdance save with everything the parked features kept in it.
static func with_parked(src: Dictionary) -> Dictionary:
	var d: Dictionary = src.duplicate(true)
	var flags: Dictionary = d["flags"]
	flags.merge(PARKED_FLAGS.duplicate(true), true)
	var stats: Dictionary = d["stats"]
	for k: String in PARKED_STATS:
		stats[k] = PARKED_STATS[k]
	(flags["goals_done"] as Array).append_array(PARKED_GOALS)
	for id: String in PARKED_ACHIEVEMENTS:
		(flags["achievements"] as Dictionary)[id] = 1794000000.0
	(flags["codex"] as Array).append_array(PARKED_CODEX)
	(flags["research"] as Dictionary)["done"] = ((flags["research"] as Dictionary).get("done", []) as Array) + ["observatory"]
	(d["currencies"] as Dictionary)["starseeds"] = [4.6, 1]
	# The start hub's dict: a built Telescope and Museum, and two Seed of the Week decorations.
	var hub0: Dictionary = ((d["orbit"] as Dictionary)["hub_worlds"] as Dictionary)["0"]
	hub0["telescope"] = {"built": true, "care": {"world": 1, "until": 1794000300.0}}
	hub0["museum"] = {"built": true}
	hub0["decor"] = {"items": PARKED_DECOR.duplicate(true)}
	return d


## A small world save as another slot holds it (no globe yet: it was never opened on this build).
static func _other_world(planet: String, cubes: float) -> Dictionary:
	return {"version": 4, "created_unix": 1793000000.0, "saved_unix": 1794000000.0, "currencies": {"cubes": BigNum.from_float(cubes).serialize()},
		"upgrades": {}, "stats": {"time_played": 900.0}, "flags": {"intro_done": true, "world_index": 1, "late_new_world": true},
		"world": {"hub_level": 1}, "parts": [], "districts": {"0": {"hub_level": 1}}, "current_hub": 0, "planet_state": {},
		"orbit": {"planet_id": planet}}


static func _profile(pname: String, current: int) -> Dictionary:
	return {"version": 1, "name": pname, "current": current, "starseeds": 0.0, "starseeds_total": 46.0, "unlocked": true, "saved_unix": 1794000000.0,
		"heirlooms": {"old_crew": 2, "seed_purse": 1},
		"worlds": [
			{"index": 0, "seed": 4471, "name": "Verdance", "type": "verdance", "modifiers": [], "slot": 0, "claimed": 46, "stats": {"ark_waves": 2}, "finale": true},
			{"index": 1, "seed": 7712, "name": "Ochre", "type": "desert_world", "modifiers": ["long_nights"], "slot": 1, "claimed": 0, "stats": {}, "planet": "ochre"}],
		"homeward": {"pct": {"verdance": 1.0, "ochre": 0.2}, "seen": ["tidewell"], "beats": ["ochre_arrive"], "relics": ["ochre_glass"], "techs": ["deep_drill"],
			"drive": 5, "rocket_tier": 4, "picks": 1, "answered": true, "launched": false, "done": false}}


static func _read(path: String) -> Dictionary:
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


static func _write(path: String, d: Dictionary) -> void:
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	f.store_string(JSON.stringify(d))
	f.close()
