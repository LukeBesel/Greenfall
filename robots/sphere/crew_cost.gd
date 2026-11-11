class_name CrewCost
extends RefCounted
## What the crew costs per frame, for the robot report (`--robots=...`, `--bot-report`): the time
## of SphereCrew.tick (the thinking) and of the near robots' own steps (SphereBot.step: steering,
## ground following, animation), as a mean, a worst frame, and the best one-second stretch. The
## best second is the number to compare between runs: on a busy machine the mean also counts
## the time other programs took.
##
## Use: var c := CrewCost.new(); c.add(tick_us, bodies_us) once a frame; c.summary()

const WINDOW_MS: int = 1000
## A window with fewer frames than this is not a fair second (a load hitch).
const WINDOW_MIN_FRAMES: int = 10

var frames: int = 0
var tick_us: int = 0
var bodies_us: int = 0
var worst_us: int = 0
## The frame (counted from the crew's first) on which the worst cost fell: a low number is the
## crew starting up under the loading screen, not play.
var worst_frame: int = 0
var best_window_us: float = INF
var _win_start_ms: int = -1
var _win_us: int = 0
var _win_frames: int = 0


## One frame: microseconds spent in the crew's tick and in the near robots' steps.
func add(p_tick_us: int, p_bodies_us: int) -> void:
	frames += 1
	tick_us += p_tick_us
	bodies_us += p_bodies_us
	if p_tick_us + p_bodies_us > worst_us:
		worst_us = p_tick_us + p_bodies_us
		worst_frame = frames
	var now: int = Time.get_ticks_msec()
	if _win_start_ms < 0:
		_win_start_ms = now
	_win_us += p_tick_us + p_bodies_us
	_win_frames += 1
	if now - _win_start_ms >= WINDOW_MS:
		if _win_frames >= WINDOW_MIN_FRAMES:
			best_window_us = minf(best_window_us, float(_win_us) / float(_win_frames))
		_win_start_ms = now
		_win_us = 0
		_win_frames = 0


## {frames, tick_ms, bodies_ms, total_ms (means per frame), worst_ms, worst_frame, best_second_ms}.
func summary() -> Dictionary:
	var n: float = float(maxi(frames, 1))
	return {"frames": frames, "tick_ms": float(tick_us) / 1000.0 / n, "bodies_ms": float(bodies_us) / 1000.0 / n,
		"total_ms": float(tick_us + bodies_us) / 1000.0 / n, "worst_ms": float(worst_us) / 1000.0, "worst_frame": worst_frame,
		"best_second_ms": best_window_us / 1000.0 if best_window_us < INF else 0.0}
