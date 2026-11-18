class_name Hitch
extends RefCounted
## [v5load] Long-frame watch for play (`--hitch[=ms]`, default 30): every frame whose main-thread
## CPU time (or wall time, off Linux) is over the threshold prints a line with what ran in it:
##     [hitch] t=41.2s frame 38 ms (cpu 36) at 212 m from start: hinterland rebuild 21, chunk apply 9
## and every 20 s a summary (frames, frames over the threshold, the longest). Heavy steps report
## themselves with:
##     var h: int = Hitch.t()
##     ...work...
##     Hitch.mark("chunk apply", h)
## Both are a bool test when the watch is off. See docs/PERFORMANCE.md.

static var on: bool = false
static var limit_us: int = 30000
static var _marks: Dictionary = {}  # label -> us this frame
static var _last_us: int = 0
static var _last_cpu: int = 0
static var _t0: int = 0
static var _frames: int = 0
static var _long: int = 0
static var _max_us: int = 0
static var _sum_t: int = 0
static var total_long: int = 0
static var total_frames: int = 0
static var worst_us: int = 0
static var worst_what: String = ""


static func start(limit_ms: float) -> void:
	on = true
	limit_us = int(limit_ms * 1000.0)
	_last_us = 0
	_t0 = Time.get_ticks_usec()
	_sum_t = _t0


static func t() -> int:
	return Time.get_ticks_usec() if on else 0


static func mark(label: String, t0: int) -> void:
	if not on:
		return
	var d: int = Time.get_ticks_usec() - t0
	if d >= 1000:
		_marks[label] = int(_marks.get(label, 0)) + d


## Once a frame (OrbitDev._process). `where`: a short position note for the line.
static func frame(where: String) -> void:
	if not on:
		return
	var now: int = Time.get_ticks_usec()
	var cpu: int = BuildBudget.cpu_us()
	if _last_us > 0:
		var wall: int = now - _last_us
		var c: int = cpu - _last_cpu if cpu > 0 else wall
		_frames += 1
		total_frames += 1
		_max_us = maxi(_max_us, c)
		if c > limit_us:
			_long += 1
			total_long += 1
			var parts: Array = []
			var keys: Array = _marks.keys()
			keys.sort_custom(func(a: String, b: String) -> bool: return int(_marks[a]) > int(_marks[b]))
			for k: String in keys:
				parts.append("%s %.0f" % [k, int(_marks[k]) / 1000.0])
			var what: String = ", ".join(parts) if not parts.is_empty() else "(nothing marked)"
			if c > worst_us:
				worst_us = c
				worst_what = what
			print("[hitch] t=%.1fs frame %.0f ms (cpu %.0f) %s: %s" % [(now - _t0) / 1e6, wall / 1000.0, c / 1000.0, where, what])
	_marks.clear()
	_last_us = now
	_last_cpu = cpu
	if now - _sum_t > 20000000:
		print("[hitch] %.0fs: %d frames, %d over %d ms, longest %.0f ms (cpu)" % [(now - _t0) / 1e6, _frames, _long, limit_us / 1000, _max_us / 1000.0])
		_sum_t = now
		_frames = 0
		_long = 0
		_max_us = 0


static func summary() -> String:
	return "%d frames, %d over %d ms, worst %.0f ms (%s)" % [total_frames, total_long, limit_us / 1000, worst_us / 1000.0, worst_what]
