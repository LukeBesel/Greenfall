extends RefCounted
## Offline voice backend for the music director (same interface as audio/music_voices.gd).
## Used by tools/render_music.gd to render the score to a WAV without an audio device.

const RATE: int = 22050

var _samples: Dictionary
var _voices: Dictionary = {}  # id -> {pcm, pos, step, gain, cur, loop}
var _next_id: int = 1
var _lp: float = 0.0


func _init(samples: Dictionary) -> void:
	_samples = samples


func start(sample: String, pitch: float, gain: float) -> int:
	if not _samples.has(sample):
		return -1
	var e: Dictionary = _samples[sample]
	var id: int = _next_id
	_next_id += 1
	_voices[id] = {"pcm": e["pcm"], "pos": 0.0, "step": pitch, "gain": gain, "cur": gain, "loop": bool(e["loop"])}
	return id


func set_gain(id: int, gain: float) -> void:
	if _voices.has(id):
		_voices[id]["gain"] = gain


func stop(id: int) -> void:
	_voices.erase(id)


func voice_count() -> int:
	return _voices.size()


## Mixes `n` samples; volume changes ramp linearly across the block (as Godot does per buffer).
## `cutoff_hz` applies a one-pole low-pass like the Music bus filter.
func mix(n: int, cutoff_hz: float = 20000.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var done: Array[int] = []
	for id: int in _voices:
		var v: Dictionary = _voices[id]
		var pcm: PackedFloat32Array = v["pcm"]
		var size: int = pcm.size()
		var pos: float = v["pos"]
		var step: float = v["step"]
		var g0: float = v["cur"]
		var g1: float = v["gain"]
		var loop: bool = v["loop"]
		var dg: float = (g1 - g0) / n
		var g: float = g0
		for i: int in n:
			var idx: int = int(pos)
			if loop and idx >= size:
				pos -= size
				idx = int(pos)
			elif not loop and idx >= size - 1:
				done.append(id)
				break
			var fr: float = pos - idx
			var nxt: float = pcm[idx + 1] if idx + 1 < size else pcm[0]
			out[i] += (pcm[idx] + (nxt - pcm[idx]) * fr) * g
			g += dg
			pos += step
		v["pos"] = pos
		v["cur"] = g1
	for id: int in done:
		_voices.erase(id)
	var a: float = 1.0 - exp(-TAU * cutoff_hz / RATE)
	for i: int in n:
		_lp += (out[i] - _lp) * a
		out[i] = _lp
	return out
