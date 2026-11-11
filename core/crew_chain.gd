class_name CrewChain
extends RefCounted
## The robot chain as plain data (design spec section 14): parts in the ground, and the
## Assembler's line. No nodes, no globals: the game (systems/crew/robot_chain.gd), the tests and
## the crew simulator (tools/crew_sim) all run this one class.
##
## The ground. A hex leaves buried parts the first time it is cleaned, as many as its city gives
## (table key "ground", by district id; "open_ground" outside every city). Parts finders dig them
## out with take(); a hex is seeded once, ever, so dirtying it and cleaning it again gives nothing.
## Everything the crew can ever dig is therefore bounded by the ground that has been cleaned: the
## crew cannot grow faster than the cleaning.
##
## The line. The Assembler builds one robot at a time. It pays the robot's Parts when it starts,
## takes assembly_s seconds, and hands the robot over when the crew has room. What it builds
## next follows the build mix: the type furthest below its share of what the line has built since
## the mix was last changed.
##
## Config: the "chain" dictionary of the planet's robots table (its _doc explains every key).
## Use: var c := CrewChain.new(); c.configure(cfg); c.seed_cell(cell, "city_id"); c.take(cell, 2.0)
##      var out: Dictionary = c.tick_line(dt, parts_on_hand, has_room, allowed, price_fn)

## Line states (status): what the panel says and the tests read.
const OFF: String = ""
const PAUSED: String = "paused"
const NO_MIX: String = "no_mix"
const CREW_FULL: String = "crew_full"
const NEED_PARTS: String = "need_parts"
const BUILDING: String = "building"
const SAVE_VERSION: int = 1

var cfg: Dictionary = {}
## Parts lying in cleaned ground, by hex.
var stock: Dictionary[int, float] = {}
## Hexes that have left their parts already (dug out or not).
var seeded: Dictionary[int, bool] = {}
var seeded_parts: float = 0.0
var dug_parts: float = 0.0
var delivered_parts: float = 0.0
## Cities whose arrival salvage has been paid.
var arrivals: Dictionary[String, bool] = {}
var built: bool = false
var offered: bool = false
var paused: bool = false
var mix: Dictionary[String, int] = {}
## Robots the line has built since the mix last changed (what the shares are measured on).
var made: Dictionary[String, int] = {}
var made_total: int = 0
## The type on the line ("" = none) and the seconds of work done on it.
var current: String = ""
var progress_s: float = 0.0
var status: String = OFF
## The part of a Part delivered but not paid out yet (see deliver).
var _carry: float = 0.0


func configure(p_cfg: Dictionary) -> void:
	cfg = p_cfg
	if mix.is_empty():
		reset_mix()


# --- The ground -------------------------------------------------------------------------------

## Buried parts a hex of `district_id` leaves ("" = open ground).
func parts_per_hex(district_id: String) -> float:
	var ground: Dictionary = cfg.get("ground", {})
	if district_id != "" and ground.has(district_id):
		return float(ground[district_id])
	return float(cfg.get("open_ground", 0.0))


## A hex was cleaned: it leaves its buried parts, once. Returns the parts it left (0 when it has
## been seeded before).
func seed_cell(cell: int, district_id: String) -> float:
	if seeded.has(cell):
		return 0.0
	seeded[cell] = true
	var parts: float = parts_per_hex(district_id)
	if parts > 0.0:
		stock[cell] = parts
		seeded_parts += parts
	return parts


## Marks a hex as already cleaned in the past: it will never leave parts (an older save's ground).
func mark_spent(cell: int) -> void:
	seeded[cell] = true


func stock_at(cell: int) -> float:
	return stock.get(cell, 0.0)


func has_stock(cell: int) -> bool:
	return stock.has(cell)


## Parts still in the ground everywhere.
func stock_total() -> float:
	return seeded_parts - dug_parts


## Digs up to `want` parts out of a hex. Returns what came out.
func take(cell: int, want: float) -> float:
	var have: float = stock.get(cell, 0.0)
	var got: float = minf(have, maxf(want, 0.0))
	if got <= 0.0:
		return 0.0
	if have - got <= 0.0001:
		stock.erase(cell)
	else:
		stock[cell] = have - got
	dug_parts += got
	return got


## Parts reached the base. Returns the whole Parts to pay into the wallet now: the wallet holds
## whole numbers, so a fraction waits here for the next delivery and nothing is lost.
func deliver(parts: float) -> float:
	delivered_parts += maxf(parts, 0.0)
	_carry += maxf(parts, 0.0)
	var whole: float = floorf(_carry + 0.0001)
	_carry = maxf(_carry - whole, 0.0)
	return whole


## Salvage found on first arrival in a city: the Parts to pay now (0 when paid before or none).
func claim_arrival(district_id: String) -> float:
	var table: Dictionary = cfg.get("arrival_parts", {})
	if arrivals.has(district_id) or not table.has(district_id):
		return 0.0
	arrivals[district_id] = true
	return float(table[district_id])


# --- The Assembler ------------------------------------------------------------------------------

func assembler_cfg() -> Dictionary:
	return cfg.get("assembler", {})


func assembly_s() -> float:
	return maxf(float(assembler_cfg().get("assembly_s", 40.0)), 0.1)


func max_weight() -> int:
	return int(assembler_cfg().get("max_weight", 9))


func reset_mix() -> void:
	mix.clear()
	var d: Dictionary = assembler_cfg().get("default_mix", {})
	for t: String in d:
		mix[t] = clampi(int(d[t]), 0, max_weight())
	_restart_shares()


func weight(type_id: String) -> int:
	return mix.get(type_id, 0)


## Sets a type's share number in the mix. The shares are measured afresh from here on.
func set_weight(type_id: String, w: int) -> void:
	var v: int = clampi(w, 0, max_weight())
	if mix.get(type_id, 0) == v:
		return
	mix[type_id] = v
	_restart_shares()


## A type's share of the line's output, 0..1, among the types it may build.
func share(type_id: String, allowed: Array[String]) -> float:
	var sum: int = 0
	for t: String in allowed:
		sum += mix.get(t, 0)
	return float(mix.get(type_id, 0)) / float(sum) if sum > 0 and type_id in allowed else 0.0


## What the line builds next: the allowed type furthest below its share ("" = nothing to build).
## Ties go to the earlier type in `allowed`.
func next_type(allowed: Array[String]) -> String:
	return pick(allowed, made, made_total)


## The next `n` robots off the line, for the panel's preview.
func upcoming(n: int, allowed: Array[String]) -> Array[String]:
	var out: Array[String] = []
	var counts: Dictionary[String, int] = made.duplicate()
	var total: int = made_total
	if current != "":
		out.append(current)
	while out.size() < n:
		var t: String = pick(allowed, counts, total)
		if t == "":
			break
		out.append(t)
		counts[t] = counts.get(t, 0) + 1
		total += 1
	return out


## One step of the line. `parts` = Parts on hand, `has_room` = the crew can take one more robot,
## `allowed` = the types the line may build, `price_fn.call(type_id) -> float` = Parts for one.
## Returns {"spend": Parts to take from the wallet now, "built": type handed over now or ""}.
func tick_line(dt: float, parts: float, has_room: bool, allowed: Array[String], price_fn: Callable) -> Dictionary:
	var out: Dictionary = {"spend": 0.0, "built": ""}
	if not built:
		status = OFF
		return out
	if paused:
		status = PAUSED
		return out
	if current == "":
		if not has_room:
			status = CREW_FULL
			return out
		var t: String = next_type(allowed)
		if t == "":
			status = NO_MIX
			return out
		var price: float = float(price_fn.call(t))
		if parts - price < float(assembler_cfg().get("reserve_parts", 0.0)):
			status = NEED_PARTS
			return out
		out["spend"] = price
		current = t
		progress_s = 0.0
	progress_s = minf(progress_s + dt, assembly_s())
	status = BUILDING
	if progress_s < assembly_s():
		return out
	if not has_room:
		status = CREW_FULL  # the finished robot waits in the door
		return out
	out["built"] = current
	made[current] = made.get(current, 0) + 1
	made_total += 1
	current = ""
	progress_s = 0.0
	return out


## How far the robot on the line is, 0..1.
func progress() -> float:
	return clampf(progress_s / assembly_s(), 0.0, 1.0) if current != "" else 0.0


# --- Save ---------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var ground: Array = []
	for c: int in stock:
		ground.append([c, snappedf(stock[c], 0.001)])
	return {"v": SAVE_VERSION, "ground": ground, "seeded": seeded.keys(), "seeded_parts": seeded_parts, "dug": dug_parts,
		"delivered": delivered_parts, "arrivals": arrivals.keys(), "built": built, "offered": offered, "paused": paused,
		"mix": mix.duplicate(), "made": made.duplicate(), "current": current, "progress_s": progress_s, "carry": _carry}


func from_dict(d: Dictionary) -> void:
	stock.clear()
	seeded.clear()
	arrivals.clear()
	for raw: Variant in d.get("ground", []):
		var pair: Array = raw
		stock[int(pair[0])] = float(pair[1])
	for c: Variant in d.get("seeded", []):
		seeded[int(c)] = true
	for id: Variant in d.get("arrivals", []):
		arrivals[str(id)] = true
	seeded_parts = float(d.get("seeded_parts", 0.0))
	dug_parts = float(d.get("dug", 0.0))
	delivered_parts = float(d.get("delivered", 0.0))
	built = bool(d.get("built", false))
	offered = bool(d.get("offered", false))
	paused = bool(d.get("paused", false))
	current = str(d.get("current", ""))
	progress_s = float(d.get("progress_s", 0.0))
	_carry = float(d.get("carry", 0.0))
	if d.has("mix"):
		mix.clear()
		var saved_mix: Dictionary = d["mix"]
		for t: Variant in saved_mix:
			mix[str(t)] = clampi(int(saved_mix[t]), 0, max_weight())
	made.clear()
	made_total = 0
	var saved_made: Dictionary = d.get("made", {})
	for t: Variant in saved_made:
		made[str(t)] = int(saved_made[t])
		made_total += int(saved_made[t])


func _restart_shares() -> void:
	made.clear()
	made_total = 0


## The allowed type furthest below its share of the mix, given how many of each there are: the
## rule the line follows, also used to choose what to build by hand.
func pick(allowed: Array[String], counts: Dictionary[String, int], total: int) -> String:
	var sum: int = 0
	for t: String in allowed:
		sum += mix.get(t, 0)
	if sum <= 0:
		return ""
	var best: String = ""
	var best_gap: float = -INF
	for t: String in allowed:
		var w: int = mix.get(t, 0)
		if w <= 0:
			continue
		var gap: float = float(w) / float(sum) - float(counts.get(t, 0)) / float(total + 1)
		if gap > best_gap + 1e-9:
			best_gap = gap
			best = t
	return best
