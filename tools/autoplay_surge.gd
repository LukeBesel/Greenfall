class_name AutoplaySurge
extends RefCounted
## The bot's side of the Surge (systems/surge.gd): it lets a full Bloom Core go when it is
## sweeping dirty ground with room in the chest, the way a player would, and notes when each
## Surge came.
##
## Report keys it writes (screenshots/autoplay_report.json): surges (how many), surge_times_s
## (game seconds of each release), surge_charged_s (game seconds each charge filled).

## The bot keeps a full core until the chest is emptier than this: the burst is for sweeping.
const CHEST_ROOM: float = 0.5

var times: Array[float] = []
var charged: Array[float] = []


func on_charged(now: float) -> void:
	charged.append(now)


## Call every frame of play. sweeping: the bot is holding the sweep on waste in reach.
## chest_ratio: how full the chest is (0..1). Returns true on the frame it releases a Surge.
func tick(surge: Surge, sweeping: bool, chest_ratio: float, now: float) -> bool:
	if surge == null or not surge.can_release() or not sweeping or chest_ratio > CHEST_ROOM:
		return false
	if not surge.release():
		return false
	times.append(now)
	return true


func write(report: Dictionary) -> void:
	report["surges"] = times.size()
	report["surge_times_s"] = times
	report["surge_charged_s"] = charged
