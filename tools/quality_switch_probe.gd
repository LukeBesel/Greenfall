extends Node
## [v1menu] Times a quality preset change the way Settings does it (set_quality_manual +
## apply_quality_to_tree), on the title screen or in the game: the call itself and the slowest of
## the next frames (pipeline compiles show up there). Rendered runs only, e.g.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver vulkan --resolution 960x540 -- --quality-probe [--fresh]
## Prints `[qprobe] Medium -> Low: call N ms, worst frame M ms` per switch, then quits.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _frames(n: int) -> float:
	var worst: float = 0.0
	var t: int = Time.get_ticks_usec()
	for i: int in n:
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		worst = maxf(worst, (now - t) / 1000.0)
		t = now
	return worst


func _run() -> void:
	while Loader.busy() or get_tree().current_scene == null:
		await get_tree().process_frame
	await _frames(int(DevHooks.get_f("qprobe-settle", 90.0)))
	var names: Array[String] = ["Low", "Medium", "High", "Ultra"]
	for q: int in [0, 1, 2, 3, 1]:
		var from: int = Settings.quality
		var t0: int = Time.get_ticks_usec()
		Settings.set_quality_manual(q)
		Settings.apply_quality_to_tree(get_tree().current_scene)
		var call_ms: float = (Time.get_ticks_usec() - t0) / 1000.0
		var worst: float = await _frames(20)
		print("[qprobe] %s -> %s: call %.0f ms, worst frame %.0f ms" % [names[from], names[q], call_ms, worst])
	get_tree().quit()
