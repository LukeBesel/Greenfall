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
## Every city Lumi has reached has a field bench at its base (systems/camp/field_benches.gd), so the
## bot shops, researches and builds robots where it works; it flies home (site 0) only for what
## stays in the start yard: building the Assembler (see home_wanted). Without a field bench in the
## city (a planet that has none) it still flies home for a tool or a round of shopping.

## The city stage that opens the next city (planets/verdance/data/districts.json: unlock stage).
const OPEN_STAGE_FALLBACK: int = 4
## How close to the parked rocket Lumi walks before choosing a destination (its prompt reaches 6.5 m).
const BOARD_M: float = 4.0
## Shopping alone brings Lumi home at most this often (game seconds); a city's tool or the
## Assembler always does.
const SHOP_EVERY_S: float = 900.0
## A walk to the rocket that takes longer than this is given up: the bot boards from where it is
## (a person boxed in would call the rocket over) and counts it in board_stuck.
const WALK_GIVE_UP_S: float = 120.0

var home_trip: bool = false
var last_home_s: float = 0.0
var hops: int = 0
## Walks to the rocket given up on (WALK_GIVE_UP_S): the bot boarded from where it stood.
var board_stuck: int = 0
var why: String = ""
## When the planner first wanted to fly while the rocket's cells were still charging (-1: not waiting).
var cells_wait_from: float = -1.0
## The longest such wait (game seconds): the time a player stands by a rocket that is not ready.
var cells_wait_max_s: float = 0.0


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


## Whether Lumi, away from the start yard, should fly home now: the Assembler is on offer and paid
## for (it is built only in the start yard), or, with no field bench in this city, a tool for an
## open city waits at the bench or there is shopping worth the trip and the last trip home was long
## enough ago. Sets `why`.
func home_wanted(tool_waiting: bool, assembler_ready: bool, shop_wanted: bool, now: float, field_bench: bool = false) -> bool:
	if field_bench:
		why = "the Assembler is on offer" if assembler_ready else ""
	elif tool_waiting:
		why = "a tool waits at the bench"
	elif assembler_ready:
		why = "the Assembler is on offer"
	elif shop_wanted and now - last_home_s >= SHOP_EVERY_S:
		why = "shopping"
	else:
		why = ""
	return why != ""


## Tracks waits on the rocket's cells: `waiting` while the planner points elsewhere and the cells
## are not full yet.
func note_cells(waiting: bool, now: float) -> void:
	if waiting and cells_wait_from < 0.0:
		cells_wait_from = now
	elif not waiting and cells_wait_from >= 0.0:
		cells_wait_max_s = maxf(cells_wait_max_s, now - cells_wait_from)
		cells_wait_from = -1.0


## The site Lumi should stand at now: home (0) during a home trip, else the target city's site.
func want_site(d: Districts, src: Sources) -> int:
	if home_trip:
		return 0
	var id: String = target_city(d, src)
	return d.site_of(id) if id != "" else -1


## Lumi reached the bench during a home trip: the trip is done.
func shopped(now: float) -> void:
	home_trip = false
	last_home_s = now
