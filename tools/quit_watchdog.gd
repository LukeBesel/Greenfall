class_name QuitWatchdog
extends RefCounted
## Backstop for --quit-after (autoload/DevHooks.gd). The flag is read in _process, so a run whose
## main loop stops turning (a frame that never ends, a quit that never finishes) used to go on
## until someone stopped it by hand. This thread watches the wall clock by itself: when the run is
## `grace_s` past its limit it says so and ends the process.

const POLL_MS: int = 100

## Wall-clock ms the limit counts from. DevHooks keeps it equal to its own start (a planet may
## move that start to the end of its build).
var start_ms: int = 0

var _limit_ms: int = 0
var _grace_ms: int = 0
var _on_overdue: Callable
var _thread: Thread
var _lock := Mutex.new()
var _stopped: bool = false


## True once `now_ms` is past the limit and the grace after it.
static func overdue(now_ms: int, from_ms: int, limit_ms: int, grace_ms: int) -> bool:
	return now_ms - from_ms >= limit_ms + grace_ms


## Starts watching. `on_overdue` replaces ending the process (tests); it runs on the watchdog's thread.
func start(from_ms: int, limit_s: float, grace_s: float, on_overdue: Callable = Callable()) -> void:
	if _thread != null:
		return
	start_ms = from_ms
	_limit_ms = int(limit_s * 1000.0)
	_grace_ms = int(grace_s * 1000.0)
	_on_overdue = on_overdue
	_thread = Thread.new()
	_thread.start(_run)


## Stops watching and waits for the thread (call before the owner leaves the tree).
func stop() -> void:
	if _thread == null:
		return
	_lock.lock()
	_stopped = true
	_lock.unlock()
	_thread.wait_to_finish()
	_thread = null


func _is_stopped() -> bool:
	_lock.lock()
	var s: bool = _stopped
	_lock.unlock()
	return s


func _run() -> void:
	while not _is_stopped():
		if overdue(Time.get_ticks_msec(), start_ms, _limit_ms, _grace_ms):
			if _on_overdue.is_valid():
				_on_overdue.call()
			else:
				printerr("[DevHooks] --quit-after: the main loop did not stop %.0f s past the limit; ending the process." % (_grace_ms / 1000.0))
				OS.kill(OS.get_process_id())
			return
		OS.delay_msec(POLL_MS)
