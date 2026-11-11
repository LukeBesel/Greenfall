class_name AutoplayStall
extends RefCounted
## The bot's stall watch: a run whose game clock moves on while nothing progresses (no purchase,
## no goal finished, no hex cleaned, no regrowth or city stage reached) for longer than LIMIT_S
## has stalled. The bot then prints what it was trying to do and quits with a non-zero exit code,
## so a long headless run cannot go on burning hours on a dead end.
##
## Time that is not play does not count: the bot calls pause() while the rocket flies or a
## cinematic holds Lumi, and progress() for every event above.
##
## Report keys it writes (screenshots/autoplay_report.json): stall (null, or {at_s, idle_s, doing}),
## longest_idle_s and longest_idle_from_s (the longest stretch with no progress, in game seconds).

## Game seconds with no progress before the run counts as stalled (docs/PLAN.md section 9: 4 min).
const LIMIT_S: float = 240.0

var last_s: float = -1.0
var longest_s: float = 0.0
var longest_from_s: float = 0.0
var stalled: Dictionary = {}
var _paused_s: float = 0.0
var _seen_s: float = -1.0


## Something moved on at game time `now`.
func progress(now: float) -> void:
	if last_s >= 0.0:
		_note_idle(now)
	last_s = now
	_paused_s = 0.0


## Game seconds between the last call to tick() and `now` were not play (a flight, a cinematic).
func pause(now: float) -> void:
	if _seen_s >= 0.0 and now > _seen_s:
		_paused_s += now - _seen_s
	_seen_s = now


## Seconds of play with no progress, up to `now`.
func idle_s(now: float) -> float:
	return maxf(0.0, now - last_s - _paused_s) if last_s >= 0.0 else 0.0


## Call while the bot plays. True once, on the frame the run counts as stalled; `doing` says what
## the bot was trying to do (it goes in the report).
func tick(now: float, doing: String) -> bool:
	_seen_s = now
	if last_s < 0.0:
		last_s = now
		return false
	if not stalled.is_empty() or idle_s(now) <= LIMIT_S:
		return false
	_note_idle(now)
	stalled = {"at_s": snappedf(now, 0.1), "idle_s": snappedf(idle_s(now), 0.1), "doing": doing}
	return true


func write(report: Dictionary, now: float) -> void:
	if last_s >= 0.0:
		_note_idle(now)
	report["stall"] = null if stalled.is_empty() else stalled
	report["longest_idle_s"] = snappedf(longest_s, 0.1)
	report["longest_idle_from_s"] = snappedf(longest_from_s, 0.1)


func _note_idle(now: float) -> void:
	var idle: float = idle_s(now)
	if idle > longest_s:
		longest_s = idle
		longest_from_s = last_s
