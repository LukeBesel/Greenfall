class_name AutoplayTravel
extends RefCounted
## The bot's travel between cities (districts), as a player would do it: walk to the parked
## rocket, pick a destination, fly. The planner says which city Lumi should be in now; the bot
## (tools/autoplay.gd) works wherever it stands until the planner points elsewhere and the rocket's
## energy cells are full.
##
## Where to be (target_city):
##   1. the earliest open city whose source job is on offer and paid for (the job gates its city's
##      last stage, and only Lumi can do it);
##   2. else the newest open city until it reaches the stage that opens the next one;
##   3. else (every city open) the earliest city still below the last stage.
## The workbench stands only in the start yard, so the bot also flies home (site 0) for a tool, the
## Assembler or a round of shopping (see home_wanted), then back.

## The city stage that opens the next city (planets/verdance/data/districts.json: unlock stage).
const OPEN_STAGE_FALLBACK: int = 4
## How close to the parked rocket Lumi walks before choosing a destination (its prompt reaches 6.5 m).
const BOARD_M: float = 4.0
## Shopping alone brings Lumi home at most this often (game seconds); a city's tool or the
## Assembler always does.
const SHOP_EVERY_S: float = 900.0
## A walk to the rocket that takes longer than this is given up and tried again later.
const WALK_GIVE_UP_S: float = 120.0

var home_trip: bool = false
var home_since_s: float = -1.0
var last_home_s: float = 0.0
var hops: int = 0
## Walks to the rocket given up on (WALK_GIVE_UP_S): the bot boarded from where it stood.
var board_stuck: int = 0
var why: String = ""


## The city (district id) Lumi should be in now, or "" when the planet has no districts.
static func target_city(d: Districts, src: Sources) -> String:
	if d == null or d.count() == 0:
		return ""
	var open: Array[String] = []
	for id: String in d.ids():
		if d.is_unlocked(id):
			open.append(id)
	if open.is_empty():
		return ""
	for id: String in open:
		if job_waiting(src, id):
			return id
	var newest: String = open[-1]
	if open.size() < d.count() and d.stage_of(newest) < open_stage(d, newest):
		return newest
	if open.size() == d.count() and not shut_or_none(src, newest):
		return newest
	for id: String in open:
		if d.stage_of(id) < Districts.MAX_STAGE:
			return id
	return newest


## A source job in `id` that Lumi can do now.
static func job_waiting(src: Sources, id: String) -> bool:
	return src != null and src.has(id) and not src.is_shut(id) and src.is_open(id) and src.can_afford(id)


static func shut_or_none(src: Sources, id: String) -> bool:
	return src == null or not src.has(id) or src.is_shut(id)


## The stage of `id` that opens the city after it (the next city's unlock rule).
static func open_stage(d: Districts, id: String) -> int:
	for other: String in d.ids():
		var rule: Dictionary = d.spec_of(other).get("unlock", {})
		if str(rule.get("district", "")) == id:
			return int(rule.get("stage", OPEN_STAGE_FALLBACK))
	return Districts.MAX_STAGE


## Whether Lumi, away from the start yard, should fly home now: a tool for an open city waits at
## the bench, the Assembler is on offer and paid for, or there is shopping worth the trip and the
## last trip home was long enough ago. Sets `why`.
func home_wanted(tool_waiting: bool, assembler_ready: bool, shop_wanted: bool, now: float) -> bool:
	if tool_waiting:
		why = "a tool waits at the bench"
	elif assembler_ready:
		why = "the Assembler is on offer"
	elif shop_wanted and now - last_home_s >= SHOP_EVERY_S:
		why = "shopping"
	else:
		why = ""
	return why != ""


## The site Lumi should stand at now: home (0) during a home trip, else the target city's site.
func want_site(d: Districts, src: Sources) -> int:
	if home_trip:
		return 0
	var id: String = target_city(d, src)
	return d.site_of(id) if id != "" else -1


## Lumi reached the bench during a home trip: the trip is done.
func shopped(now: float) -> void:
	home_trip = false
	home_since_s = -1.0
	last_home_s = now
