extends Node
## [v8snd] Dev: --audio-capture[=dir] records what the game actually mixes, as 16-bit stereo WAVs:
## <dir>/master.wav (after the Master limiter, what the speakers get) and one file per bus
## (music.wav, songs.wav, ambience.wav, sfx.wav, ui.wav, after that bus's own effects).
## Default dir: res://screenshots/audio_capture. Works headless: the Dummy driver still mixes in
## real time. Analyse the files with `python3 tools/check_audio.py --wav <dir>/master.wav`.
## A bus that has had nothing playing for a while is skipped by the mixer, so its file only holds
## the stretches where it sounded; master.wav is continuous.

const DEFAULT_DIR: String = "res://screenshots/audio_capture"
const BUFFER_S: float = 4.0

var out_dir: String = ""
var _caps: Dictionary = {}  # file name -> AudioEffectCapture
var _data: Dictionary = {}  # file name -> PackedByteArray
var _rate: int = 44100
var _done: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if out_dir == "":
		out_dir = DEFAULT_DIR
	_rate = int(AudioServer.get_mix_rate())
	for i: int in AudioServer.bus_count:
		var cap := AudioEffectCapture.new()
		cap.buffer_length = BUFFER_S
		AudioServer.add_bus_effect(i, cap)  # last in the chain: after the bus's own effects
		var file: String = "master" if i == 0 else AudioServer.get_bus_name(i).to_lower()
		_caps[file] = cap
		_data[file] = PackedByteArray()
	print("[acap] capturing %d buses at %d Hz into %s" % [_caps.size(), _rate, out_dir])


func _process(_dt: float) -> void:
	_drain()


func _drain() -> void:
	for file: String in _caps:
		var cap: AudioEffectCapture = _caps[file]
		var n: int = cap.get_frames_available()
		if n <= 0:
			continue
		var frames: PackedVector2Array = cap.get_buffer(n)
		var b: PackedByteArray = _data[file]
		var off: int = b.size()
		b.resize(off + frames.size() * 4)
		for i: int in frames.size():
			var f: Vector2 = frames[i]
			b.encode_s16(off + i * 4, int(clampf(f.x, -1.0, 1.0) * 32767.0))
			b.encode_s16(off + i * 4 + 2, int(clampf(f.y, -1.0, 1.0) * 32767.0))
		_data[file] = b


func _exit_tree() -> void:
	flush()


## Writes the WAVs (also called on quit).
func flush() -> void:
	if _done:
		return
	_done = true
	_drain()
	var dir: String = ProjectSettings.globalize_path(out_dir)
	DirAccess.make_dir_recursive_absolute(dir)
	for file: String in _data:
		var pcm: PackedByteArray = _data[file]
		var f := FileAccess.open(dir.path_join(file + ".wav"), FileAccess.WRITE)
		if f == null:
			continue
		f.store_buffer("RIFF".to_ascii_buffer())
		f.store_32(36 + pcm.size())
		f.store_buffer("WAVEfmt ".to_ascii_buffer())
		f.store_32(16)
		f.store_16(1)
		f.store_16(2)
		f.store_32(_rate)
		f.store_32(_rate * 4)
		f.store_16(4)
		f.store_16(16)
		f.store_buffer("data".to_ascii_buffer())
		f.store_32(pcm.size())
		f.store_buffer(pcm)
		f.close()
		print("[acap] %s.wav: %.1f s" % [file, pcm.size() / 4.0 / _rate])
