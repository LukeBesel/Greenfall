class_name BuildBudget
extends RefCounted
## [leftovers] Time-sliced building behind the loading screen.
## The Loader (ui/loading_screen.gd) opens a budget before it switches scenes; scenes/slice.gd then
## builds the district as a coroutine and the heavy builders (FieldView, LitterView, FarJunk,
## CityView, StreetDressing) check in from their loops:
##     if BuildBudget.due():
##         await BuildBudget.pause()
## With no budget open (tests, tools, the save round trip) due() is always false, nothing awaits
## and every builder runs synchronously exactly as before. Same order, same RNG draws: only the
## frames in between change, so the bar and the Lumi vignette keep moving.

## The open budget, or null (synchronous building).
static var current: BuildBudget = null

## Work allowed per frame before a builder yields (the loader's own frame comes on top). It
## grows with what a loading-screen frame itself costs (twice that, at most MAX_SLICE_US), so a
## slow renderer (software GL: ~200 ms per frame for the 3D vignette) doesn't double the load
## time; on a GPU a frame costs a few ms and the slice stays at SLICE_US.
const SLICE_US: int = 45000
const MAX_SLICE_US: int = 400000

var tree: SceneTree
var frames: int = 0
## Longest stretch of work between two yields, and where it ended (for the load report).
var longest_us: int = 0
var longest_at: String = ""
var _since: int = 0
var _slice_us: int = SLICE_US
var _frame_us: int = 0  # smoothed cost of one yielded frame
var _from: float = 0.0
var _to: float = 0.0
var _sub: float = 0.0


## [v3city] A budget opened in play (a hub town building as Lumi comes near): a fixed slice of
## this many microseconds a frame instead of the loader's adaptive one. 0 = the loader's rule.
var play_slice_us: int = 0


## [v3city] Opens a budget for building in play (no loading screen): `slice_us` of work a frame.
static func begin_play(p_tree: SceneTree, slice_us: int) -> BuildBudget:
	var b: BuildBudget = begin(p_tree)
	b.play_slice_us = slice_us
	b._slice_us = slice_us
	return b


static func begin(p_tree: SceneTree) -> BuildBudget:
	current = BuildBudget.new()
	current.tree = p_tree
	current._since = Time.get_ticks_usec()
	lap_on = DevHooks.has("load-report")
	_lap_us = current._since
	if lap_on:
		_lap_cpu = cpu_us()
		_since_cpu = _lap_cpu
		longest_cpu_us = 0
	return current


static func end() -> void:
	current = null


static func active() -> bool:
	return current != null


## True when the current frame's work slice is used up (never without a budget).
static func due() -> bool:
	return current != null and Time.get_ticks_usec() - current._since >= current._slice_us


## Hand the frame back (draws the loading screen), then carry on. No-op without a budget.
static func pause(at: String = "") -> void:
	var b: BuildBudget = current
	if b == null:
		return
	b._note(at)
	last_at = at
	var t0: int = Time.get_ticks_usec()
	await b.tree.process_frame
	b.frames += 1
	b._since = Time.get_ticks_usec()
	_lap_us = b._since
	if lap_on:
		_since_cpu = cpu_us()
		_lap_cpu = _since_cpu
	var f: int = b._since - t0
	if f > 500000 and DevHooks.has("load-report"):
		print("[budget] a %.0f ms frame after %s" % [f / 1000.0, at])
	b._frame_us = f if b._frame_us == 0 else int(lerpf(b._frame_us, f, 0.3))
	b._slice_us = clampi(b._frame_us * 2, SLICE_US, MAX_SLICE_US)
	if b.play_slice_us > 0:
		b._slice_us = b.play_slice_us  # [v3city] in play: a fixed few ms a frame


## Yield only if this frame's slice is used up.
static func check(at: String = "") -> void:
	if due():
		await pause(at)


## Progress: the build step now running covers [from, to] of the build; sub(f) moves inside it.
static func span(from: float, to: float) -> void:
	if current:
		current._from = from
		current._to = to
		current._sub = 0.0


static func sub(f: float) -> void:
	if current:
		current._sub = clampf(f, current._sub, 1.0)


## Build progress 0..1.
func progress() -> float:
	return lerpf(_from, _to, _sub)


## [v5load] Builders that carry on across frames after their caller returned (a setup() that a
## synchronous caller can't await): they count themselves in and out here, and the build waits
## with idle() before it reads what they make. Always 0 without a budget.
static var busy: int = 0
static var last_at: String = ""  # the latest yield's label (the loader's --load-report)


static func idle() -> void:
	while current != null and busy > 0:
		await pause("background")


## Build tasks not yet waited on. WorkerThreadPool keeps a task (and the script its callable
## holds) until someone waits on it; one left over at quit crashes the exit (see StorySfx).
static var _tasks: Array[int] = []
static var _groups: Array[int] = []
## [v6qa] What each task's callable runs on, held until the task is waited on. A Callable does not
## keep its RefCounted target alive: a hub town freed mid-build (Lumi walked off, a check hopped on)
## dropped its CityLayout while the layout bake's group task still ran on it (a use-after-free that
## showed up as "corrupted size vs. prev_size" at quit, exit 134).
static var _task_refs: Dictionary = {}
static var _group_refs: Dictionary = {}


static func add_task(c: Callable, label: String) -> int:
	_prune()
	var id: int = WorkerThreadPool.add_task(c, true, label)
	_tasks.append(id)
	_task_refs[id] = c.get_object()
	return id


static func add_group_task(c: Callable, n: int, label: String) -> int:
	_prune()
	var id: int = WorkerThreadPool.add_group_task(c, n, -1, true, label)
	_groups.append(id)
	_group_refs[id] = c.get_object()
	return id


## [v6qa] Waits out tasks that finished but whose joiner is gone (its coroutine died with a freed node).
static func _prune() -> void:
	for id: int in _tasks.duplicate():
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			_tasks.erase(id)
			_task_refs.erase(id)
	for id: int in _groups.duplicate():
		if WorkerThreadPool.is_group_task_completed(id):
			WorkerThreadPool.wait_for_group_task_completion(id)
			_groups.erase(id)
			_group_refs.erase(id)


## Waits for a task from add_task(), yielding frames meanwhile (blocks when synchronous).
static func join(task_id: int) -> void:
	if task_id < 0:
		return
	while current != null and _tasks.has(task_id) and not WorkerThreadPool.is_task_completed(task_id):  # [v6qa] _prune may have waited it already
		await pause("join")
	if not _tasks.has(task_id):  # [v6qa] waited already (_prune)
		return
	WorkerThreadPool.wait_for_task_completion(task_id)
	_tasks.erase(task_id)
	_task_refs.erase(task_id)


static func join_group(group_id: int) -> void:
	if group_id < 0:
		return
	while current != null and _groups.has(group_id) and not WorkerThreadPool.is_group_task_completed(group_id):  # [v6qa]
		await pause("join")
	if not _groups.has(group_id):  # [v6qa]
		return
	WorkerThreadPool.wait_for_group_task_completion(group_id)
	_groups.erase(group_id)
	_group_refs.erase(group_id)


## Quitting mid-build (Audio._exit_tree): wait for whatever is still running.
static func finish_pending() -> void:
	for id: int in _tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	for id: int in _groups:
		WorkerThreadPool.wait_for_group_task_completion(id)
	_tasks.clear()
	_groups.clear()
	_task_refs.clear()
	_group_refs.clear()
	for path: String in _fetching:  # [v6qa]
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_get(path)
	_fetching.clear()


## Loads a resource file on a loader thread while the loading screen keeps drawing, and returns
## it (hold it until it is used: then load(path) is a cache hit). Without a budget, or when it is
## cached already, it returns null at once and the caller's own load() does the work.
static func fetch(path: String) -> Resource:
	if current == null or ResourceLoader.has_cached(path) or not ResourceLoader.exists(path):
		return null
	if ResourceLoader.load_threaded_request(path) != OK:
		return null
	_fetching[path] = true  # [v6qa]
	while current != null and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await pause("load " + path.get_file())
	_fetching.erase(path)
	return ResourceLoader.load_threaded_get(path)


## [v6qa] Threaded loads whose fetch() has not collected them yet. Quitting while a hub town built
## left one in flight (its coroutine dies with the town) and the engine's exit freed it twice:
## "corrupted size vs. prev_size in fastbins", exit 134 (repro: --orbit-walk-in=1,380
## --quit-mid-build=30). finish_pending() collects them first.
static var _fetching: Dictionary = {}


## [v5load] Profiling aid for --load-report: prints the main-thread time since the last lap (or
## yield) when it is over 40 ms, so a long stretch between two yields can be pinned to a step.
static var _lap_us: int = 0
static var lap_on: bool = false


static func lap(label: String) -> void:
	if not lap_on:
		return
	var now: int = Time.get_ticks_usec()
	var cpu: int = cpu_us()
	if _lap_us > 0 and now - _lap_us > 40000:
		print("[lap] %.0f ms (cpu %.0f): %s" % [(now - _lap_us) / 1000.0, (cpu - _lap_cpu) / 1000.0, label])
	_lap_us = now
	_lap_cpu = cpu


## [v5load] This thread's CPU time (Linux: /proc/thread-self/schedstat), or 0. Wall-clock slices on
## a busy box (other helpers' builds) read 2-3x long; the CPU time is what an idle machine sees.
static var _lap_cpu: int = 0
static var _since_cpu: int = 0
static var longest_cpu_us: int = 0
static var longest_cpu_at: String = ""


static func cpu_us() -> int:
	var f := FileAccess.open("/proc/thread-self/schedstat", FileAccess.READ)
	if f == null:
		return 0
	@warning_ignore("integer_division")
	return int(f.get_line().get_slice(" ", 0)) / 1000


static var _report_us: int = -1  # [v6qa] --budget-report-ms=N (default 80), read on first use


func _note(at: String) -> void:
	var d: int = Time.get_ticks_usec() - _since
	if lap_on:
		var c: int = cpu_us() - _since_cpu
		if c > longest_cpu_us:
			longest_cpu_us = c
			longest_cpu_at = at
		if _report_us < 0:
			_report_us = int(DevHooks.get_f("budget-report-ms", 80.0) * 1000.0)
		if d > _report_us:  # [v6qa] --budget-report-ms=N (default 80)
			print("[budget] %.0f ms (cpu %.0f) of work before the yield at %s" % [d / 1000.0, c / 1000.0, at])
	if d > longest_us:
		longest_us = d
		longest_at = at
