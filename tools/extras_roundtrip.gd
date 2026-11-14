class_name ExtrasRoundtrip
extends RefCounted
## [extras] Save round-trip coverage for the keepsakes (used by tools/save_roundtrip.gd): radio
## unlocks and the playing song, album records, nursery caretakers (+ service clock), and the
## Seed of the Week run in its own slot (seed, twist rules, kit, and the main save untouched).


## Builds some keepsake state in the live district `s`.
static func setup(s: Node) -> void:
	GameState.stats["hexes_cleaned"] = maxf(float(GameState.stats.get("hexes_cleaned", 0.0)), 22.0)
	Radio.note_planet("ochre", 3)
	Radio.check_unlocks()
	Radio.play("ochre_caravan")
	Tunes.grant("glass_dunes", true)  # [main] songs that are still CDs (Verdance borrows the Ochre songs that have files). [tunes] a CD found, one lying in the rubble, the pity counter
	CdFinds.pending()["sandglass"] = {"hub": GameState.current_hub, "hex": 3, "planet": "ochre"}
	Tunes.st()["pity"] = 7
	Tunes.hold("twin_noon")  # a scratched CD in the case
	Tunes.note_play("clean_sweep")
	var e: Dictionary = PhotoAlbum.entry(GameState.current_hub)
	e["name"] = "Old Town"
	e["before"] = PhotoAlbum.dir().path_join("h0_before.jpg")
	e["m50"] = PhotoAlbum.dir().path_join("h0_m50.jpg")
	PhotoAlbum.st()["photos"] = [{"src": "user://screenshots/rt.png", "thumb": PhotoAlbum.dir().path_join("photo_rt.jpg"), "unix": 1.0}]
	var fl: Fleet = s.get("fleet") as Fleet
	if fl:
		var r: Robot = fl.spawn("scoopie", 0, Vector3(1, 0.2, 3), 0.0, "Retiree-01")
		r.trait_id = "chatty"
		RobotBuilder.equip(r, "topper", "top_hat")
		Nursery.retire(fl, r)
		Nursery.note_service(fl)


## [v6qa] With no song picked the mood music moves on by itself between save and load (that flaked):
## compare the pick, and for a picked radio track that it is the one playing.
static func _radio_track() -> String:
	var pick: String = Radio.playing()
	if pick == "" or pick == Tunes.SHUFFLE or not Tunes.song(pick).is_empty():
		return pick
	# [main] "live" = the director holds the pick as its radio track. Whether it is audibly on it this
	# very frame (get_music_track is "" in a gap or before the director's next tick) is timing, not
	# saved state: it read false before the save and true after once, on a loaded box.
	var md: Variant = Audio.get("_music")
	var forced: String = str((md as Object).get("forced_track")) if md is Object else ""
	return "%s live %s" % [pick, str(forced == pick)]


static func snap(s: Node) -> Dictionary:
	Radio.planets()  # normalise JSON floats
	var nu: Nursery = Nursery.of(s)
	return {
		"radio": JSON.stringify(Radio.st()),
		"songs": JSON.stringify(JSON.parse_string(JSON.stringify(Tunes.st()))),  # [tunes] ints load back as floats
		"songs_found": ",".join(Tunes.found()),
		"radio_track": _radio_track(),  # [v6qa] the saved pick (and that it plays), not whatever mood track is on
		"album": JSON.stringify(PhotoAlbum.st()),
		"nursery": JSON.stringify(Nursery.list()),
		"nursery_live": nu.keepers.size() if nu else -1,
		"nursery_service": (Nursery.service() as Dictionary).size(),
	}


## The challenge runs in its own slot and leaves the main save as it was.
static func weekly(rt: Node, packed: PackedScene) -> void:
	var main_slot: int = SaveManager.slot
	var main_path: String = SaveManager.slot_path(main_slot)
	var main_before: String = FileAccess.get_file_as_string(main_path) if FileAccess.file_exists(main_path) else ""
	var keep_state: Dictionary = GameState.to_dict()
	WeeklyChallenge.path_override = SaveManager.save_dir().path_join("roundtrip_weekly.save")
	WeeklyChallenge.reset_cache()
	WeeklyChallenge.active = true
	SaveManager.slot = WeeklyChallenge.slot()
	WeeklyChallenge.prepare_state()
	GameState.reload_in_memory = true
	var s: Node = packed.instantiate()
	rt.get_tree().root.add_child(s)
	for i: int in 25:
		await rt.get_tree().process_frame
	rt.call("_check", "weekly_seed", WeeklyChallenge.current_seed(), (s.planet as PlanetData).seed_value)
	var runner: WeeklyRun = s.get_node_or_null("WeeklyRun") as WeeklyRun
	rt.call("_check", "weekly_run_built", true, runner != null)
	if runner:
		runner._start_run()
	var tw: Dictionary = WeeklyChallenge.twist()
	var banned: String = ""
	for t: String in ["scoopie", "haulbug", "drip", "multibot"]:
		if WeeklyChallenge.robot_block_for(tw, t) != "":
			banned = t
			break
	if banned != "":
		rt.call("_check", "weekly_twist_blocks_" + banned, true, (s.fleet as Fleet).build_block_reason(banned) != "")
	rt.call("_check", "weekly_kit_robots", true, (s.fleet as Fleet).robots().size() >= 1)
	var kit_n: int = (s.fleet as Fleet).robots().size()
	SaveManager.save_game()
	s.queue_free()
	await rt.get_tree().process_frame
	await rt.get_tree().process_frame
	var d: Dictionary = SaveManager.read_dict(SaveManager.slot_path(WeeklyChallenge.slot()))
	rt.call("_check", "weekly_slot_saved", WeeklyChallenge.week_id(), str((d.get("flags", {}) as Dictionary).get("weekly_id", "")))
	rt.call("_check", "weekly_resumable", true, WeeklyChallenge.has_run())
	# Resume it: the same run comes back with its robots.
	GameState.from_dict(SaveManager.migrate(d))
	GameState.reload_in_memory = true
	var s2: Node = packed.instantiate()
	rt.get_tree().root.add_child(s2)
	for i: int in 25:
		await rt.get_tree().process_frame
	rt.call("_check", "weekly_resumed_robots", kit_n, (s2.fleet as Fleet).robots().size())
	rt.call("_check", "weekly_resumed_no_intro", false, bool(GameState.flags.get("weekly_intro", false)))
	s2.queue_free()
	await rt.get_tree().process_frame
	WeeklyChallenge.active = false
	SaveManager.slot = main_slot
	var main_after: String = FileAccess.get_file_as_string(main_path) if FileAccess.file_exists(main_path) else ""
	rt.call("_check", "weekly_main_save_untouched", main_before.md5_text(), main_after.md5_text())
	rt.call("_check", "weekly_seed_back_home", true, CradleMode.world_seed() != WeeklyChallenge.current_seed())
	SaveManager.delete_save(WeeklyChallenge.slot())
	DirAccess.remove_absolute(WeeklyChallenge.path_override)
	WeeklyChallenge.path_override = ""
	WeeklyChallenge.reset_cache()
	GameState.from_dict(keep_state)
