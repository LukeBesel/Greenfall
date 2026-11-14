extends GutTest
## [v8pause] Owner item 78: "when i pause there is still sound coming out of game for the
## animation". While the game is paused (pause menu and every other pausing screen) or a story
## cinematic is paused (StoryPause -> Audio.hold_world), no world sound plays; menu sounds do, and
## the held sounds resume where they were.

var _bed: AudioStreamPlayer


func _loop_stream() -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(22050 * 2)
	for i: int in 22050:
		data.encode_s16(i * 2, int(8000.0 * sin(float(i) * 0.1)))
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = 22050
	return w


func before_each() -> void:
	# An ambience-like bed under a node that runs while paused (as audio/ambience.gd does).
	var host := Node.new()
	host.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child_autofree(host)
	_bed = AudioStreamPlayer.new()
	_bed.bus = "Ambience"
	_bed.stream = _loop_stream()
	host.add_child(_bed)


func after_each() -> void:
	get_tree().paused = false
	Audio.hold_world("test", false)
	Audio.loop("beam_hum", 0.0)
	await _frames(2)


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _audible() -> Array[String]:
	var out: Array[String] = []
	for p: Node in Audio.world_players(get_tree().root):
		if bool(p.get("playing")) and not bool(p.get("stream_paused")):
			out.append("%s (%s)" % [p.get_path(), p.get("bus")])
	return out


func _start_world_sounds() -> void:
	_bed.play()
	Audio.loop("beam_hum", 1.0)
	Audio.play("whoosh", 1.0, 0.0, 0.0)
	await _frames(2)
	assert_true(_bed.playing, "the bed plays before the pause")
	assert_true((Audio._loop_players["beam_hum"] as AudioStreamPlayer).playing, "the beam hum plays before the pause")


func test_tree_pause_silences_world_sounds_and_resumes_them() -> void:
	await _start_world_sounds()
	get_tree().paused = true
	await _frames(2)
	assert_true(Audio.is_world_paused())
	assert_eq(_audible(), [] as Array[String], "nothing on a world bus plays while paused")
	# A caller re-levelling the loop while paused must not restart it.
	Audio.loop("beam_hum", 1.0)
	assert_true(Audio.holds(Audio._loop_players["beam_hum"]))
	assert_eq(_audible(), [] as Array[String])
	# Menu sounds still play.
	# (Checked at once: a click is a few ms long, and a unique tag keeps the min-gap gate out of it.)
	Audio.play("click", 1.0, 0.0, 0.0, "pausetest%d" % Time.get_ticks_usec())
	var ui_on: bool = false
	for p: AudioStreamPlayer in Audio._players:
		if p.bus == "UI" and p.playing:
			ui_on = true
	assert_true(ui_on, "a menu click plays while paused")
	get_tree().paused = false
	await _frames(2)
	assert_false(Audio.is_world_paused())
	assert_false(_bed.stream_paused, "the bed resumes")
	assert_true(_bed.playing)
	assert_true((Audio._loop_players["beam_hum"] as AudioStreamPlayer).playing, "the hum resumes")


func test_story_pause_hold_silences_world_sounds() -> void:
	await _start_world_sounds()
	Audio.hold_world("test", true)
	await _frames(1)
	assert_eq(_audible(), [] as Array[String], "a paused cinematic holds every world sound")
	Audio.hold_world("test", false)
	await _frames(1)
	assert_true(_bed.playing, "and lets them go on after")


func test_story_pause_card_holds_the_world() -> void:
	var sp := StoryPause.new()
	add_child_autofree(sp)
	sp.set_paused(true)
	assert_true(Audio.is_world_paused())
	sp.set_paused(false)
	assert_false(Audio.is_world_paused())
