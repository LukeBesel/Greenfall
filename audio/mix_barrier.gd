extends Node
## [v10quit] Crash fix: signal 11 on the audio mixer thread, copying a freed bus StringName (seen
## at the start of a threaded load; same family as the [qafix] crash in audio/audio_vol.gd).
## Godot 4.7's mixer reads each playback's bus details by pointer and copies them
## (AudioServer::_mix_step); any change to a playing player's per-bus volumes (volume_db, bus,
## every 3D player's panning) swaps in new details and retires the old ones, which the main thread
## frees two frames later (AudioServer::_cleanup_lists, no lock). A mixer step that stalls across
## two main frames (all cores busy: a threaded load, a loaded machine) then copies freed memory.
## The barrier: once per frame the main thread takes and releases the audio driver lock, which the
## mixer holds for a whole mix step, so no mix step can span two main frames and nothing it reads
## is freed under it. Uncontended this costs nothing; when the mixer is stalled the frame waits
## for that one step (instead of the game crashing).
## Forced repro (gdb holds the mixer mid-copy): tools/audio_race_stress.gd; --no-mix-barrier turns
## this off to show the crash.

var _on: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000  # after every other node's _process this frame
	_on = not OS.get_cmdline_user_args().has("--no-mix-barrier")
	set_process(_on)


func _process(_delta: float) -> void:
	AudioServer.lock()
	AudioServer.unlock()
