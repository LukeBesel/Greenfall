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


func _field(seed_v: int) -> HexField:
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	var f := HexField.new(9, 3.2, seed_v, CityLayout.new(seed_v, 150.0, false))
	f.generate(types, Vector2i(6, 12))
	return f


func _defs() -> Dictionary:
	var out: Dictionary = {}
	for e: Dictionary in Economy.read_json("res://data/eggs.json").get("eggs", []):
		out[str(e["id"])] = e
	return out


func test_gnomes_are_collectible_pickups() -> void:
	var g: Dictionary = _defs()["gnomes"]
	assert_true(bool(g.get("collect", false)))
	assert_eq(str(g.get("prompt", "")), "E   pick up gnome")
	assert_eq(int(g.get("parts", 0)), 5)
	assert_eq((g.get("display", []) as Array).size(), 2, "the base display has a yard spot")


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


func test_display_shows_collected_and_salutes() -> void:
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


func test_display_spot_is_in_the_yard_and_clear_of_interactables() -> void:
	var at: Array = _defs()["gnomes"]["display"]
	var p := Vector2(float(at[0]), float(at[1]))
	assert_lt(absf(p.x), CityLayout.YARD_HALF)
	assert_lt(absf(p.y), CityLayout.YARD_HALF)
	assert_gt(absf(p.x), 2.0 if absf(p.y) < 6.0 else -1.0, "at the yard edge")
	# The yard's fixed interactables / builds (depot, board, radio, observatory, demo baler, composter,
	# nursery, landing pod, lamp, hopper, recycler, camp radio, spawn).
	var others: Array[Vector2] = [Vector2(0, -1.8), Vector2(-3.6, 2.2), Vector2(-4.75, 3.45), Vector2(-5.6, -2.8),
		Vector2(-5.8, -2.2), Vector2(-5.8, 6.4), Vector2(-1.3, 6.0), Vector2(6.0, 9.5), Vector2(4.2, -3.0),
		Vector2(7.0, -0.8), Vector2(7.0, -4.8), Vector2(6.6, 3.4), Vector2(0, 3.0), Vector2(-7.0, -5.0)]
	for o: Vector2 in others:
		assert_gt(p.distance_to(o), 3.0, "display clear of %s" % str(o))


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
		var field: HexField = _field(seed_v)
		var plan: Array[Dictionary] = EasterEggs.plan_spots(field, ids, defs, [Vector3.ZERO])
		var found_it: bool = false
		for p: Dictionary in plan:
			if p["id"] == "stars":
				found_it = true
				var pos: Vector3 = p["pos"]
				assert_gt(Vector2(pos.x, pos.z - EasterEggs.SPAWN_Z).length(), 25.0, "seed %d: telescope out of the start area" % seed_v)
				assert_false(field.is_water(field.hex_at(pos)))
		assert_true(found_it, "seed %d: telescope placed" % seed_v)


func test_telescope_move_keeps_other_eggs_in_place() -> void:
	var defs: Dictionary = _defs()
	var ids: Array[String] = ["duck", "stars", "tv"]
	var field: HexField = _field(4242)
	var a: Array[Dictionary] = EasterEggs.plan_spots(field, ids, defs, [])
	var near: Dictionary = defs.duplicate(true)
	near["stars"].erase("min_spawn_dist")
	var b: Array[Dictionary] = EasterEggs.plan_spots(field, ids, near, [])
	assert_eq(a.size(), 3)
	for i: int in a.size():
		if a[i]["id"] != "stars":
			assert_eq(a[i]["pos"], b[i]["pos"], "%s stays put" % a[i]["id"])


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
