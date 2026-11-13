extends Node
## [v8snd] Writes every built-in sound the game synthesizes to WAV files, plus a manifest, so
## tools/check_audio.py can check them (clipping, DC, loop seams, rumble, crackle):
##   godot --headless --path . res://tools/dump_audio.tscn [-- --out=screenshots/audio_dump]
## Covers: the Audio autoload's SFX (every variant) and loops (beam_hum, ...), the score's
## instruments (audio/music_synth.gd, every planet's audio/planet_synth.gd set), the planet and
## life ambience loops and one-shots (audio/ambience_synth.gd, audio/life_ambience.gd's "leaves"),
## and the CD crackle (audio/tunes_director.gd). manifest.json lists name, file, loop, kind.
## kind "bed" marks loops that play for minutes at a time (ambience beds, beam hum); they get the
## strictest checks. Exit 0 once written (check_audio.py decides pass / fail).

const MusicSynth := preload("res://audio/music_synth.gd")
const PlanetSynth := preload("res://audio/planet_synth.gd")
const AmbSynth := preload("res://audio/ambience_synth.gd")
const Tunes := preload("res://audio/tunes_director.gd")
const AMB_LOOPS: Array[String] = ["wind_warm", "wind_sea", "wind_eerie", "wind_dust", "heat_buzz", "waves", "water", "cicadas"]

var _out: String = "res://screenshots/audio_dump"
var _items: Array = []
var _frames: int = 0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))


func _process(_dt: float) -> void:
	_frames += 1
	if _frames != 2:
		return  # the Audio autoload builds its sounds in _ready
	var audio: Node = get_tree().root.get_node_or_null("Audio")
	if audio:
		var loops: Dictionary = audio.get("_loops")
		for n: String in loops:
			_wav("loop_" + n, loops[n], "bed")
		var sounds: Dictionary = audio.get("_sounds")
		for n: String in sounds:
			var list: Array = sounds[n]
			for v: int in list.size():
				if list[v] is AudioStreamWAV:
					_wav("sfx_%s_%d" % [n, v], list[v], "shot")
	var have: Dictionary = MusicSynth.build_all()
	for th: String in PlanetSynth.NEEDS:
		have.merge(PlanetSynth.build(th, have))
	for n: String in have:
		var e: Dictionary = have[n]
		_pcm("music_" + n, e["pcm"], bool(e["loop"]), "note")
	for lid: String in AMB_LOOPS:
		_pcm("amb_" + lid, AmbSynth.loop_pcm(lid), true, "bed")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4471
	_pcm("amb_leaves", AmbSynth._level(AmbSynth.wind(rng, 8.0, 0.8, 0.0, 0.0)), true, "bed")
	for v: int in 3:
		_pcm("amb_creak_%d" % v, AmbSynth.creak(rng, v), false, "shot")
	_pcm("amb_geyser", AmbSynth.geyser(rng), false, "shot")
	_pcm("amb_buoy", AmbSynth.buoy_bell(0), false, "shot")
	_pcm("amb_devil", AmbSynth.dust_devil(rng, 1), false, "shot")
	_pcm("amb_spray", AmbSynth.spray(rng), true, "bed")
	_wav("tunes_crackle", Tunes.crackle_stream(), "shot")
	for id: String in ["wind", "insects", "lapping"]:  # fauna/fauna_ambience.gd's frontier beds
		_wav("fauna_" + id, FaunaSounds.loop_stream(id), "bed")
	_wav("fauna_crickets", FaunaSounds.crickets_loop(), "bed")
	var animals: Dictionary = {}  # the wildlife's calls (purr, meow, birds, ...), fauna/fauna_sounds.gd
	FaunaSounds._synth_all(animals)
	for n: String in animals:
		var list: Array = animals[n]
		for v: int in list.size():
			_wav("fauna_%s_%d" % [n, v], list[v], "animal")
	StorySfx.ensure()  # the eggs' sounds (story/story_sfx.gd)
	var story: Dictionary = StorySfx._streams
	for n: String in story:
		_wav("story_" + n, story[n], "animal" if n == "purr" or n == "quack" else "shot")
	var f := FileAccess.open(_out.path_join("manifest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(_items, " "))
	f.close()
	print("[dump] %d sounds into %s" % [_items.size(), ProjectSettings.globalize_path(_out)])
	get_tree().quit(0)


func _pcm(n: String, pcm: PackedFloat32Array, loop: bool, kind: String) -> void:
	_wav(n, MusicSynth.to_wav(pcm, loop), kind)


func _wav(n: String, s: AudioStreamWAV, kind: String) -> void:
	var file: String = n + ".wav"
	var err: int = s.save_to_wav(_out.path_join(file))
	if err != OK:
		push_warning("[dump] %s: save failed (%d)" % [n, err])
		return
	_items.append({"name": n, "file": file, "loop": s.loop_mode != AudioStreamWAV.LOOP_DISABLED,
		"loop_begin": s.loop_begin, "loop_end": s.loop_end, "kind": kind})
