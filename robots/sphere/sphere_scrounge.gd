class_name SphereScrounge
extends RefCounted
## The parts finder's job on a round planet (role "find": the chain's Scrounger, design spec
## section 14). Called by SphereCrew's brain, so a Scrounger near Lumi and one far away as a record
## behave the same.
##
## The loop: claim the nearest cleaned hex that still holds buried parts (inside the painted
## "find" zone when there is one, else the hub's region), drive there, dig at the type's dig_rate,
## go on to the next hex until the sack is full or the ground is empty, then carry the sack to the
## base, where SphereCrew.parts_delivered fires. The parts in the ground are CrewChain's ledger
## (core/crew_chain.gd): what a Scrounger takes is gone from that hex for good.
##
## Stats (the planet's robots table): speed, dig_rate (parts a second), sack (parts per trip).

const ROLE: String = "find"
const MODE_HOME: String = "to_base"
const IDLE_EMPTY: String = "no parts in the ground"
## A sack this close to full counts as full (digging is in small float steps).
const FULL_SLACK: float = 0.001


static func sack(u: Dictionary) -> float:
	return maxf(Economy.robot_stat(str(u["type"]), "sack", int(u["tier"])), 1.0)


static func dig_rate(u: Dictionary) -> float:
	return maxf(Economy.robot_stat(str(u["type"]), "dig_rate", int(u["tier"])), 0.01)


static func carried(u: Dictionary) -> float:
	return float(u.get("parts", 0.0))


## Next thing to do for an idle Scrounger standing on `here`. True when it set off.
static func find_job(crew: SphereCrew, u: Dictionary, here: int) -> bool:
	if carried(u) >= sack(u) - FULL_SLACK:
		return go_home(crew, u)
	var c: int = -1
	if crew.chain != null and not crew.chain.stock.is_empty():
		c = crew.claim_dirty(here, int(u["hub"]), crew.rings, ROLE, str(u["name"]))
	if c < 0:
		if carried(u) > 0.0:
			return go_home(crew, u)  # the ground is empty: bring in what it has
		u["idle"] = IDLE_EMPTY
		return false
	u["job"] = c
	u["idle"] = ""
	return crew.send_to(u, c, "go")


## Carry the sack to the base of the robot's hub.
static func go_home(crew: SphereCrew, u: Dictionary) -> bool:
	var spot: Vector3 = crew.base_spot(u)
	var cell: int = crew.grid.cell_at(spot) if spot != Vector3.ZERO else crew.depot_of(int(u["hub"]))
	if not crew.send_to(u, cell, MODE_HOME):
		return false
	crew.add_waypoint(u, spot)
	return true


## One step of digging on the robot's hex. True when it is done there.
static func dig(crew: SphereCrew, u: Dictionary, dt: float) -> bool:
	var c: int = int(u["job"])
	if crew.chain == null:
		return true
	var room: float = sack(u) - carried(u)
	var got: float = crew.chain.take(c, minf(room, dig_rate(u) * dt))
	u["parts"] = carried(u) + got
	return not crew.chain.has_stock(c) or carried(u) >= sack(u) - FULL_SLACK


## The Scrounger reached its base: empties the sack and returns the Parts it brought.
static func unload(u: Dictionary) -> float:
	var parts: float = carried(u)
	u["parts"] = 0.0
	u["log"]["parts"] = float(u["log"].get("parts", 0.0)) + parts
	return parts
