extends GutTest
## [camp] Picking a radio song replaces the background score: the mood piece's voices stop, no
## stinger plays over the song, and "Back to mood music" brings the score back in from silence.
## Runs the real MusicDirector against a recording backend (headless, no audio device needed).

const MusicDirector := preload("res://audio/music_director.gd")


class FakeVoices:
	extends RefCounted
	var next_id: int = 0
	var live: Dictionary = {}  # id -> sample
	var started: Array = []  # [time, sample]
	var clock: float = 0.0

	func start(sample: String, _pitch: float, _gain: float) -> int:
		next_id += 1
		live[next_id] = sample
		started.append([clock, sample])
		return next_id

	func stop(id: int) -> void:
		live.erase(id)

	func set_gain(_id: int, _g: float) -> void:
		pass


var _fake: FakeVoices
var _dir: RefCounted


func before_each() -> void:
	_fake = FakeVoices.new()
	var samples: Dictionary = Audio._music_samples
	_dir = MusicDirector.new(samples, _fake)
	_dir.set("gaps_enabled", false)
	_dir.call("set_mood", "explore")


func _run(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		_dir.call("update", 0.05)
		_fake.clock += 0.05
		t += 0.05


func _held_voices() -> Array:
	# Sustained voices (pad chords and their blooms); one-shot notes end on their own.
	var out: Array = []
	for p: Dictionary in _dir.get("_pads"):
		out.append_array(p["ids"])
		out.append_array(p["bloom_ids"])
	return out


func test_radio_song_replaces_the_score() -> void:
	_run(12.0)
	var before: Array = _held_voices()
	assert_gt(before.size(), 0, "the mood score is playing pads")
	assert_true(_dir.call("play_track", "verdance_sprout"))
	_run(1.5)
	assert_eq(str(_dir.call("current_track")), "verdance_sprout", "the song starts straight away, not at the end of the piece")
	for id: int in before:
		assert_false(_fake.live.has(id), "the mood piece's held voice %d stopped" % id)
	_dir.call("sting", "upgrade")
	assert_eq((_dir.get("_queue") as Array).size(), 0, "no stinger plays over a radio song")
	_run(20.0)
	assert_eq(str(_dir.call("current_track")), "verdance_sprout", "the song loops: one music source")


func test_back_to_mood_music_fades_the_score_in() -> void:
	_run(4.0)
	_dir.call("play_track", "verdance_sprout")
	_run(10.0)
	var song_voices: Array = _held_voices()
	_dir.call("stop_track")
	assert_eq(float((_dir.get("_gains") as Dictionary)["pad"]), 0.0, "the score restarts from silence")
	_run(1.5)
	assert_ne(str(_dir.call("current_track")), "verdance_sprout", "the song is gone")
	for id: int in song_voices:
		assert_false(_fake.live.has(id), "the song's held voice %d stopped" % id)
	_run(6.0)
	assert_gt(float((_dir.get("_gains") as Dictionary)["pad"]), 0.05, "the score has faded back in")


func test_muted_score_for_a_song_file_stays_silent() -> void:
	_run(10.0)
	var before: Array = _held_voices()
	_dir.call("set_muted", true)
	_dir.call("sting", "upgrade")
	_run(3.0)
	for id: int in before:
		assert_false(_fake.live.has(id), "held voice %d stopped" % id)
	for l: String in (_dir.get("_gains") as Dictionary):
		assert_eq(float((_dir.get("_gains") as Dictionary)[l]), 0.0, "layer %s silent while a song file plays" % l)
	assert_eq((_dir.get("_queue") as Array).size(), 0, "no stingers")
	_dir.call("set_muted", false)
	_run(6.0)
	assert_gt(float((_dir.get("_gains") as Dictionary)["pad"]), 0.05, "the score fades back in")
