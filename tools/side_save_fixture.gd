extends SceneTree
## Writes tests/fixtures/saves/side_systems_v4/slot_0.save for tests/test_side_systems_saves.gd: a
## real Verdance globe save (version 4) as a player of the side systems parked in task M3-13 left
## it (parked/README.md): a Requests board mid-run on the Mk IV bench, trinkets, Lumi Level 14,
## a retired caretaker in the nursery, Garden Mode decorations at the start hub, bought ship
## looks, the cut world events in the director's memory and the achievements now hidden.
## Run:  godot --headless --path . -s res://tools/side_save_fixture.gd [-- <path to a globe slot save>]
## (default source: the M1-08 fixture's Verdance slot, itself a real globe save).

const SOURCE: String = "res://tests/fixtures/saves/parked_v4/p1/slot_0.save"
const OUT: String = "res://tests/fixtures/saves/side_systems_v4/slot_0.save"
## What the parked side systems kept in GameState.flags. The test reads these too.
const SIDE_FLAGS: Dictionary = {
	"contracts": {"slots": [
		{"state": "active", "tpl": "perfect_bales", "n": 8, "time_s": 720.0, "pay": "cubes", "parts": 2, "income_s": 120.0, "tier": 1,
			"offer_left": 1200.0, "left": 300.0, "base": 4.0, "peak": 0.0, "wait": 0.0},
		{"state": "done", "tpl": "dig_parts", "n": 3, "time_s": 720.0, "pay": "parts", "parts": 2, "income_s": 120.0, "tier": 1,
			"offer_left": 1200.0, "left": 0.0, "base": 9.0, "peak": 0.0, "wait": 0.0},
		{"state": "wait", "wait": 40.0}], "done_total": 7, "events_seen": 3.0, "track_done": 7},
	"requests_unlocked": true,
	"trinkets": ["golden_bolt", "rain_jar", "photo_moss_deer", "crumb_bag", "pic_cat", "contract_pen", "capsule_moon_rock", "lumi_lens_cap"],
	"lumi": {"level": 14, "xp": 420, "total": 23000},
	"nursery": [{"name": "Bobbin-07", "type": "scoopie", "tier": 0, "trait": "", "build": {}, "unix": 1794000000.0, "from": 0}],
	"nursery_service": {"Bobbin-07": 120.0},
	"ship_style": {"paint": "coral", "trim": "graphite", "glow": "violet", "owned": ["paints:coral", "trims:graphite", "glows:violet"]},
	"decor_kinds": ["bench", "lamp", "fountain"],
	"bench_tier": 4,
	"events": {"next_in": 120.0, "recent": ["supply_drop", "wildlife_visit", "robot_hiccup"],
		"done": {"supply_drop": 1, "robot_hiccup": 2, "wildlife_visit": 1, "salvage_surge": 3}},
}
const SIDE_STATS: Dictionary = {
	"contracts_done": 7.0, "trinkets_found": 8.0, "lumi_levels": 13.0, "robots_retired": 1.0, "nursery_visits": 4.0, "decor_placed": 3.0,
	"decor_kinds": 3.0, "decor_charm_best": 6.0, "photos_taken": 1.0, "ev_metal_bales": 6.0, "builder_full_custom": 1.0,
}
## Achievements the save earned that Planet 1 now hides (parked/achievements_parked.json).
const SIDE_ACHIEVEMENTS: Array[String] = ["late_decor_1", "extras_retire_1", "builder_mix", "home_answered"]
const SIDE_DECOR: Array[Dictionary] = [{"t": "bench", "x": 3, "z": 12, "r": 0}, {"t": "lamp", "x": 5, "z": 12, "r": 0},
	{"t": "fountain", "x": -1, "z": 13, "r": 0}]
const SIDE_CHARM: float = 6.0


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var src_path: String = args[0] if not args.is_empty() else ProjectSettings.globalize_path(SOURCE)
	var src: Dictionary = _read(src_path)
	if src.is_empty() or not (src.get("orbit") is Dictionary) or (src["orbit"] as Dictionary).is_empty():
		push_error("not a globe save: %s" % src_path)
		quit(1)
		return
	var out: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	_write(out, with_side_systems(src))
	print("[fixture] wrote %s (version %d)" % [OUT, int(src.get("version", 0))])
	quit()


## The save with everything the parked side systems kept in it.
static func with_side_systems(src: Dictionary) -> Dictionary:
	var d: Dictionary = src.duplicate(true)
	var flags: Dictionary = d["flags"]
	flags.merge(SIDE_FLAGS.duplicate(true), true)
	var tabs: Array = flags.get("bench_tabs", [])
	if not ("contracts" in tabs):
		tabs.append("contracts")
	flags["bench_tabs"] = tabs
	var stats: Dictionary = d["stats"]
	for k: String in SIDE_STATS:
		stats[k] = SIDE_STATS[k]
	for id: String in SIDE_ACHIEVEMENTS:
		(flags["achievements"] as Dictionary)[id] = 1794000000.0
	# The start hub: Garden Mode's decorations and their charm, the nursery built in the yard.
	var hub0: Dictionary = ((d["orbit"] as Dictionary)["hub_worlds"] as Dictionary)["0"]
	hub0["decor"] = {"items": SIDE_DECOR.duplicate(true)}
	hub0["decor_charm"] = SIDE_CHARM
	var camp: Dictionary = hub0.get("camp", {})
	var built: Dictionary = camp.get("built", {})
	built["nursery"] = true
	camp["built"] = built
	hub0["camp"] = camp
	return d


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
