extends Node
## Command-line hooks for automated verification. Pass after `--`, e.g.
##   godot --path . -- --fresh --shot=screenshots/slice.png --shot-delay=3 --quit-after=4
## Flags:
##   --fresh            ignore and don't write the save file
##   --nosave           don't write saves (but load if present)
##   --shot=PATH        save a viewport PNG (res:// or relative to project) after --shot-delay seconds
##   --shots=N          take N screenshots spaced by --shot-every seconds (suffix _0, _1, ...)
##   --quit-after=S     quit after S seconds (game time)
##   --autoplay         let tools/autoplay.gd drive Patch
##   --time-scale=X     Engine.time_scale
##   --seed=N           override the slice field seed
##   --cam=NAME         camera preset for screenshots (see CameraRig.apply_preset)
##   --give=N           start with N cubes (testing UI)
##   --open=NAME        open a UI screen on start (upgrades)
##   --quality=N        render quality preset 0..3 (Low..Ultra) for faster screenshots

var args: Dictionary = {}
var _elapsed: float = 0.0
var _shots_taken: int = 0
var _perf_t: float = 0.0
var _start_ms: int = Time.get_ticks_msec()
var _frames: int = 0
var _perf_frames: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv: PackedStringArray = a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if has("fresh") or has("nosave"):
		SaveManager.enabled = false
	if has("quality"):
		Settings.quality = clampi(int(get_f("quality", 2.0)), 0, 3)
	if has("time-scale"):
		Engine.time_scale = float(args["time-scale"])
	if not args.is_empty():
		print("[DevHooks] args: ", args)


func has(flag: String) -> bool:
	return args.has(flag)


func get_f(flag: String, default: float) -> float:
	return float(args.get(flag, default))


func get_s(flag: String, default: String) -> String:
	return str(args.get(flag, default))


func _process(delta: float) -> void:
	# Wall-clock time (frame delta is clamped by the engine on very slow frames).
	_elapsed = (Time.get_ticks_msec() - _start_ms) / 1000.0
	_frames += 1
	if has("shot"):
		var count: int = int(get_f("shots", 1.0))
		var delay: float = get_f("shot-delay", 2.0)
		var every: float = get_f("shot-every", 1.0)
		if _shots_taken < count and _elapsed >= delay + every * _shots_taken:
			_take_shot(count)
	if has("perf"):
		_perf_t += delta
		_perf_frames += 1
		if _perf_t >= 3.0:
			print("[perf] t=%.0fs frames=%d game_fps=%.2f draw_calls=%d objects=%d prims=%d" % [_elapsed, _frames, _perf_frames / _perf_t,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
			_perf_t = 0.0
			_perf_frames = 0
	if has("quit-after") and _elapsed >= get_f("quit-after", 5.0):
		print("[DevHooks] quitting after %.1fs" % _elapsed)
		if has("report"):
			print("[report] cubes=%s stats=%s parts=%d" % [GameState.get_currency("cubes").format(), JSON.stringify(GameState.stats), GameState.parts.size()])
		get_tree().quit()


func _take_shot(count: int) -> void:
	var path: String = get_s("shot", "screenshots/shot.png")
	if count > 1:
		path = path.get_basename() + "_%d.png" % _shots_taken
	_shots_taken += 1
	save_viewport(path)


func save_viewport(path: String) -> void:
	var abs_path: String = path if path.begins_with("res://") or path.begins_with("user://") or path.begins_with("/") \
		else ProjectSettings.globalize_path("res://" + path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var img: Image = get_viewport().get_texture().get_image()
	var err: Error = img.save_png(abs_path)
	print("[DevHooks] screenshot -> %s (%s)" % [abs_path, error_string(err)])
