class_name PaceSimPolicy
extends RefCounted
## What a player buys and when. One script per policy in tools/pace_sim/policies/, picked with
## --policy=NAME. A policy only calls the model's buy/build methods, which enforce every rule and
## cost, so it cannot cheat.


## Called whenever Lumi stands at the workbench: buy whatever this policy wants now.
func shop(_m: PaceSimModel) -> void:
	pass


## Whether something is worth walking back to the bench for (asked while Lumi is out working).
func wants_trip(_m: PaceSimModel) -> bool:
	return false
