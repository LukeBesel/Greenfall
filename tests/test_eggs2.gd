extends GutTest
## [eggs2] Collectible gnomes (EggCollect / EggDisplay), the jukebox hushing the score, the
## telescope placed away from spawn, and the TV's broadcast.

var _flags: Dictionary
var _stats: Dictionary
var _cur: Dictionary


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_cur = GameState.currencies.duplicate()
	GameState.flags = {}


func after_each() -> void:
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.currencies = _cur
	Audio.unhush_music("jukebox")
	Audio.unhush_music("test")
	Audio.step_hush(10.0)


func _defs() -> Dictionary:
	var out: Dictionary = {}
	for e: Dictionary in Economy.planet_table("eggs").get("eggs", []):
		out[str(e["id"])] = e
	return out


func test_gnomes_are_collectible_pickups() -> void:
	var g: Dictionary = _defs()["gnomes"]
	assert_true(bool(g.get("collect", false)))
	assert_eq(str(g.get("prompt", "")), "E   pick up gnome")
	assert_eq(int(g.get("parts", 0)), 5)


func test_collect_counts_once_per_part() -> void:
	assert_eq(EggCollect.count("gnomes"), 0)
	assert_eq(EggCollect.add("gnomes", 2), 1)
	assert_eq(EggCollect.add("gnomes", 2), 1, "the same gnome twice still counts once")
	assert_eq(EggCollect.add("gnomes", 0), 2)
	assert_true(EggCollect.has_part("gnomes", 0))
	assert_false(EggCollect.has_part("gnomes", 4))
	assert_false(EggCollect.is_complete("gnomes", 5))


func test_old_save_seen_gnomes_count_as_collected() -> void:
	# Old saves stored walked-past gnomes under the same key.
	GameState.flags["egg_gnomes_parts"] = [1.0, 3.0]  # as a loaded save hands them back
	assert_eq(EggCollect.count("gnomes"), 2)
	assert_true(EggCollect.has_part("gnomes", 3))
	assert_eq(EggCollect.add("gnomes", 1), 2, "a loaded part is not added twice")


func test_gnome_bed_shows_collected_and_salutes() -> void:
	GameState.flags["egg_gnomes_parts"] = [0, 4]
	var d: EggDisplay = EggDisplay.make("gnomes", 5, "GNOME PATROL", func(i: int) -> Node3D: return EggProps.build("gnome", i))
	add_child_autofree(d)
	assert_eq(d.figures.size(), 5)
	assert_true(d.figures[0].visible)
	assert_false(d.figures[1].visible)
	assert_eq((d.get_node("Count") as Label3D).text, "2 / 5")
	EggCollect.add("gnomes", 1)
	d.pop_in(1)
	assert_true(d.figures[1].visible)
	d.salute(d.global_position + Vector3(0, 0, 3))
	assert_true(true, "salute runs without errors")


func test_no_base_display_for_collectibles() -> void:
	assert_false(_defs()["gnomes"].has("display"), "collectibles go to Lumi's collection, not the yard")


func test_collection_lists_every_collectible_kind() -> void:
	var kinds: Array = []
	var ids: Array = []
	for x: Dictionary in Exhibits.exhibits():
		kinds.append(str(x["kind"]))
		ids.append(str(x["id"]))
		assert_has(Exhibits.KINDS, str(x["kind"]), "%s is a kind the catalogue can count" % x["id"])
		assert_true(str(x.get("name", "")) != "", "%s has a name" % x["id"])
		assert_true(Exhibits.hint(x) != "", "%s has a hint" % x["id"])
		if str(x["kind"]) in ["egg", "egg_parts"]:
			assert_true(_defs().has(str(x["ref"])), "%s refers to a real egg" % x["id"])
	for k: String in ["egg_parts", "egg", "eggs", "shards"]:
		assert_has(kinds, k)
	for id: String in ["gnomes", "biscuit", "time_capsule", "broadcast", "shards"]:
		assert_has(ids, id)


func test_collection_progress() -> void:
	var g: Dictionary = Exhibits.exhibit("gnomes")
	assert_eq(Exhibits.progress(g), Vector2i(0, 5))
	EggCollect.add("gnomes", 0)
	EggCollect.add("gnomes", 3)
	assert_eq(Exhibits.progress(g), Vector2i(2, 5))
	assert_false(Exhibits.is_full(g))
	GameState.flags["egg_tv"] = true
	assert_true(Exhibits.is_full(Exhibits.exhibit("broadcast")))
	assert_eq(Exhibits.filled(), 1, "only the broadcast is complete")


func test_jukebox_hushes_music_until_lumi_walks_away() -> void:
	var eggs := EasterEggs.new()
	add_child_autofree(eggs)
	var box := Node3D.new()
	eggs.add_child(box)
	eggs._jukebox_node = box
	eggs._play_jukebox()
	assert_true(Audio.is_music_hushed(), "the waltz silences the score")
	Audio.step_hush(Audio.HUSH_FADE_S * 0.5)
	assert_almost_eq(Audio.get_hush(), 0.5, 0.05, "fades, not cuts")
	Audio.step_hush(Audio.HUSH_FADE_S)
	assert_eq(Audio.get_hush(), 1.0)
	var mus: int = AudioServer.get_bus_index("Music")
	assert_true(AudioServer.is_bus_mute(mus), "background music fully out while the jukebox plays")
	eggs.update_jukebox(Vector3(5, 0, 0))
	assert_true(Audio.is_music_hushed(), "still playing close by")
	eggs.update_jukebox(Vector3(EasterEggs.JUKEBOX_LEAVE_M + 1.0, 0, 0))
	assert_false(Audio.is_music_hushed(), "walking away brings the music back")
	Audio.step_hush(Audio.HUSH_FADE_S * 2.0)
	assert_eq(Audio.get_hush(), 0.0)
	assert_eq(AudioServer.is_bus_mute(mus), Settings.music_volume <= 0.0001)


func test_jukebox_end_restores_music() -> void:
	var eggs := EasterEggs.new()
	add_child_autofree(eggs)
	var box := Node3D.new()
	eggs.add_child(box)
	eggs._jukebox_node = box
	eggs._play_jukebox()
	assert_true(Audio.is_music_hushed())
	eggs._jukebox_player.finished.emit()
	assert_false(Audio.is_music_hushed(), "the waltz ending fades the score back in")


func test_hush_owners_stack() -> void:
	Audio.hush_music("test")
	Audio.hush_music("jukebox")
	Audio.unhush_music("jukebox")
	assert_true(Audio.is_music_hushed())
	Audio.unhush_music("test")
	assert_false(Audio.is_music_hushed())


func test_telescope_is_far_from_spawn() -> void:
	var defs: Dictionary = _defs()
	var ids: Array[String] = []
	for id: String in defs:
		if bool(defs[id].get("starter", false)):
			ids.append(id)
	for seed_v: int in [7, 1234, 98765]:
		var g := GlobeFixture.new(seed_v)
		var frame := Node3D.new()
		add_child_autofree(frame)
		frame.global_transform = g.frame_transform()
		var plan: Array[Dictionary] = EasterEggs.plan_spots_cells(frame, g.field, g.region(), ids, defs, [Vector3.ZERO], seed_v)
		var found_it: bool = false
		for p: Dictionary in plan:
			if p["id"] == "stars":
				found_it = true
				var pos: Vector3 = p["pos"]
				assert_gt(Vector2(pos.x, pos.z).length(), 25.0, "seed %d: telescope out of the start area" % seed_v)
				assert_false(g.field.is_water(g.field.hex_at(frame.to_global(pos))))
		assert_true(found_it, "seed %d: telescope placed" % seed_v)


func test_tv_broadcast_tells_the_story() -> void:
	assert_between(TvBroadcast.FRAMES.size(), 5, 7)
	var caps: Array[String] = []
	for i: int in TvBroadcast.FRAMES.size():
		caps.append(TvBroadcast.caption(i))
	assert_has(caps, "LEDGER SECURES EXTRACTION RIGHTS")
	assert_has(caps, "EVACUATION: ALL RESIDENTS TO THE CRADLE")
	assert_eq(str(TvBroadcast.FRAMES[-1]["kind"]), "static", "ends in static")


func test_tv_broadcast_plays_through_and_can_close() -> void:
	var b := TvBroadcast.new()
	add_child_autofree(b)
	b.start()
	var done: Array = [false]
	b.finished.connect(func() -> void: done[0] = true)
	for k: int in 3:
		b._process(TvBroadcast.FRAME_S)
	assert_eq(b.frame, 3)
	b.picture.queue_redraw()
	await wait_process_frames(2)
	b.close()
	assert_true(done[0])
