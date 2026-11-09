class_name BeepGate
extends RefCounted
## [v4calm] Owner item 50 ("the beeping is still super annoying"): short repeating sounds share
## named slots. take(slot, gap_s) is true at most once per gap_s seconds (real time) per slot, so
## a crew of bots or several lamps can never stack beeps on top of each other.

static var _next_ms: Dictionary = {}


static func take(slot: String, gap_s: float) -> bool:
	var now: int = Time.get_ticks_msec()
	if now < int(_next_ms.get(slot, 0)):
		return false
	_next_ms[slot] = now + int(gap_s * 1000.0)
	return true


static func reset() -> void:
	_next_ms.clear()
