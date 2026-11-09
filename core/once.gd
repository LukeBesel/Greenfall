class_name Once
extends RefCounted
## [v4calm] Owner items 45/47: one-off lines play ONCE per save. The keys live in
## GameState.flags["once"] (a Dictionary), so they survive save and load like every other flag.

const FLAG: String = "once"


## True the first time for this key in this save (and marks it); false ever after.
static func take(key: String) -> bool:
	if done(key):
		return false
	var d: Dictionary = GameState.flags.get(FLAG, {})
	d[key] = true
	GameState.flags[FLAG] = d
	return true


static func done(key: String) -> bool:
	var d: Variant = GameState.flags.get(FLAG, {})
	return d is Dictionary and bool((d as Dictionary).get(key, false))
