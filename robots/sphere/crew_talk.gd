class_name CrewTalk
extends RefCounted
## [v6crew] What the crew tells the player, in one short line each: what a robot is doing or why
## it can't work (shown when Lumi stands by it and in the Command view), a hub's readout
## ("3 robots working here, about 40 hexes an hour") and the once-on-return note of what a hub's
## crew did while Lumi was away. Logic never reads these texts: it reads state() and the crew's
## own codes (u["mode"], u["idle"]).

## A robot's state for lights, pips and badges.
enum { WORK, MOVE, CARRY, IDLE, HELP, HELLO }

## Travel, bale drops and refills: the share of a robot's bare work rate that ends up as clean
## hexes (3 Mk I Scoopies cleaned 9 hexes in 10 min against 12.6 at the bare rate).
const RATE_SHARE: float = 0.72
## Bales lying about per missing Haul Bug before a Scoopie asks for one.
const PILE_NO_HAULER: int = 6
const PILE_PER_HAULER: int = 14

# l10n:begin
const WORK_LINE: Dictionary = {"clean": "Cleaning this hex.", "plant": "Planting here.", "water": "Watering the plants.",
	"skim": "Skimming junk off the lake."}
const IDLE_LINE: Dictionary = {
	"zone clean": "No dirty ground left around this base.",
	"zone done": "My zone is done. Paint more ground for me.",
	"no bales": "No bales to carry right now.",
	"nothing to plant": "No clean ground to plant.",
	"out of seeds": "Out of seeds.",
	"nothing to water": "Nothing to water yet. Plant something first.",
	"no water": "No water nearby to fill my tank.",
	"no lake junk": "No junk on the lakes here.",
	"no path": "I can't find a way there. Trying another spot.",
}
# l10n:end
## Idle reasons the player can do something about (the badge shows "!" instead of "z").
const HELP_REASONS: Array[String] = ["zone done", "out of seeds", "no water", "nothing to water"]


static func _tr(s: String) -> String:
	return TranslationServer.translate(s)


## Haul Bugs missing at a robot's hub: bales are piling up there with too few haulers.
static func needs_hauler(crew: SphereCrew, hub: int) -> bool:
	var haulers: int = 0
	for u: Dictionary in crew.units:
		if int(u["hub"]) == hub and str(u["role"]) == "haul":
			haulers += 1
	return crew.bales_waiting(hub) >= PILE_NO_HAULER + haulers * PILE_PER_HAULER


static func state(crew: SphereCrew, u: Dictionary) -> int:
	match str(u["mode"]):
		"hello":
			return HELLO
		"work", "refill":
			return HELP if str(u["role"]) == "clean" and bool(crew.short_haul.get(int(u["hub"]), false)) else WORK
		"to_depot", "to_baler":
			return CARRY
		"go", "to_bale", "to_refill":
			return MOVE
	if str(u["idle"]) in HELP_REASONS:
		return HELP
	return IDLE


## One short line: what this robot is doing, or why it can't work.
static func line(crew: SphereCrew, u: Dictionary) -> String:
	var role: String = str(u["role"])
	match str(u["mode"]):
		"hello":
			return _tr("Hello! Looking around.")
		"go":
			if role == "clean" and bool(crew.short_haul.get(int(u["hub"]), false)):
				return _tr("Bales are piling up. Build a Haul Bug.")
			return _tr("On my way to work.")
		"work":
			if role == "clean" and bool(crew.short_haul.get(int(u["hub"]), false)):
				return _tr("Bales are piling up. Build a Haul Bug.")
			return _tr(str(WORK_LINE.get(role, WORK_LINE["clean"])))
		"to_bale":
			return _tr("Fetching a bale.")
		"to_depot":
			return _tr("Carrying bales home.")
		"to_baler":
			return _tr("Tipping junk into the baler.")
		"to_refill", "refill":
			return _tr("Filling my water tank.")
	var why: String = str(u["idle"])
	if IDLE_LINE.has(why):
		return _tr(str(IDLE_LINE[why]))
	return _tr("Looking for work.")


## The line shown when Lumi stands by a robot: its name, kind and what it is doing.
static func look_text(crew: SphereCrew, u: Dictionary) -> String:
	var kind: String = _tr(str(Economy.robots.get(str(u["type"]), {}).get("name", str(u["type"]))))
	return _tr("%s the %s: %s") % [str(u["name"]), kind, line(crew, u)]


## Clean hexes an hour a robot manages (cleaners and skimmers; 0 for the others).
static func hexes_per_hour(u: Dictionary) -> float:
	var role: String = str(u["role"])
	if role != "clean" and role != "skim":
		return 0.0
	var per: float = SphereOffline.UNITS_PER_WATER_CELL if role == "skim" else SphereOffline.UNITS_PER_CELL
	return Offline.unit_rate(str(u["type"]), int(u["tier"])) * 3600.0 / per * RATE_SHARE


## A hub's crew in numbers and one line: {robots, working, idle, hexes_per_hour, bales_waiting,
## needs_hauler, text}. `hub` is the hub site's cell (SphereCrew.hubs, globe.sites[i]["cell"]).
static func hub_summary(crew: SphereCrew, hub: int) -> Dictionary:
	var n: int = 0
	var working: int = 0
	var rate: float = 0.0
	for u: Dictionary in crew.units:
		if int(u["hub"]) != hub:
			continue
		n += 1
		var st: int = state(crew, u)
		if st != IDLE and st != HELP:
			working += 1
		rate += hexes_per_hour(u)
	var text: String = _tr("No robots here yet")
	if n > 0:
		text = TranslationServer.translate_plural("%d robot working here", "%d robots working here", n) % n
		if rate >= 1.0:
			text = _tr("%s, about %d hexes an hour") % [text, roundi(rate)]
	return {"robots": n, "working": working, "idle": n - working, "hexes_per_hour": rate,
		"bales_waiting": crew.bales_waiting(hub), "needs_hauler": n > 0 and needs_hauler(crew, hub), "text": text, "log": crew.hub_log.get(hub, {})}


## What a hub's crew did while Lumi was away, as one line ("" if nothing worth saying).
static func away_text(cells: int, cubes: float) -> String:
	if cells <= 0 and cubes < 1.0:
		return ""
	if cubes < 1.0:
		return TranslationServer.translate_plural("While you were away, your robots here cleaned %d hex.",
			"While you were away, your robots here cleaned %d hexes.", cells) % cells
	if cells <= 0:
		return _tr("While you were away, your robots here earned %s cubes.") % BigNum.from_float(cubes).format()
	return TranslationServer.translate_plural("While you were away, your robots here cleaned %d hex and earned %s cubes.",
		"While you were away, your robots here cleaned %d hexes and earned %s cubes.", cells) % [cells, BigNum.from_float(cubes).format()]
