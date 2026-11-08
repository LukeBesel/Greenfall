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


static func begin(p_tree: SceneTree) -> BuildBudget:
	current = BuildBudget.new()
	current.tree = p_tree
	current._since = Time.get_ticks_usec()
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
	var t0: int = Time.get_ticks_usec()
	await b.tree.process_frame
	b.frames += 1
	b._since = Time.get_ticks_usec()
	var f: int = b._since - t0
	if f > 500000 and DevHooks.has("load-report"):
		print("[budget] a %.0f ms frame after %s" % [f / 1000.0, at])
	b._frame_us = f if b._frame_us == 0 else int(lerpf(b._frame_us, f, 0.3))
	b._slice_us = clampi(b._frame_us * 2, SLICE_US, MAX_SLICE_US)


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


## Build tasks not yet waited on. WorkerThreadPool keeps a task (and the script its callable
## holds) until someone waits on it; one left over at quit crashes the exit (see StorySfx).
static var _tasks: Array[int] = []
static var _groups: Array[int] = []


static func add_task(c: Callable, label: String) -> int:
	var id: int = WorkerThreadPool.add_task(c, true, label)
	_tasks.append(id)
	return id


static func add_group_task(c: Callable, n: int, label: String) -> int:
	var id: int = WorkerThreadPool.add_group_task(c, n, -1, true, label)
	_groups.append(id)
	return id


## Waits for a task from add_task(), yielding frames meanwhile (blocks when synchronous).
static func join(task_id: int) -> void:
	if task_id < 0:
		return
	while current != null and not WorkerThreadPool.is_task_completed(task_id):
		await pause("join")
	WorkerThreadPool.wait_for_task_completion(task_id)
	_tasks.erase(task_id)


static func join_group(group_id: int) -> void:
	if group_id < 0:
		return
	while current != null and not WorkerThreadPool.is_group_task_completed(group_id):
		await pause("join")
	WorkerThreadPool.wait_for_group_task_completion(group_id)
	_groups.erase(group_id)


## Quitting mid-build (Audio._exit_tree): wait for whatever is still running.
static func finish_pending() -> void:
	for id: int in _tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	for id: int in _groups:
		WorkerThreadPool.wait_for_group_task_completion(id)
	_tasks.clear()
	_groups.clear()


## Loads a resource file on a loader thread while the loading screen keeps drawing, and returns
## it (hold it until it is used: then load(path) is a cache hit). Without a budget, or when it is
## cached already, it returns null at once and the caller's own load() does the work.
static func fetch(path: String) -> Resource:
	if current == null or ResourceLoader.has_cached(path) or not ResourceLoader.exists(path):
		return null
	if ResourceLoader.load_threaded_request(path) != OK:
		return null
	while current != null and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await pause("load " + path.get_file())
	return ResourceLoader.load_threaded_get(path)


func _note(at: String) -> void:
	var d: int = Time.get_ticks_usec() - _since
	if d > 80000 and DevHooks.has("load-report"):
		print("[budget] %.0f ms of work before the yield at %s" % [d / 1000.0, at])
	if d > longest_us:
		longest_us = d
		longest_at = at
