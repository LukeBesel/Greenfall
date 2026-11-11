class_name SourceSpread
extends Node
## What a running source does to the ground round it (design spec section 4). While a city's
## source runs (systems/sources.gd):
## - the hexes in its reach cannot pass a regrowth stage (`hex_stage`): they grow up to it and
##   wait there (plants/hex_levels.gd asks hex_cap);
## - once the city has reached `from_stage`, a clean hex in its reach is fouled again every
##   `every_s` seconds with `amount` of its waste, of the source's `soil_kind` where the hex can
##   hold it. The trickle waits while `max_soiled` hexes of the reach lie dirty, so it can never
##   pile up: what is out there is at most a few minutes' work for one small robot.
## Both stop the moment the source is shut down. The hex readout says why (hex_note), and the
## first hex ever fouled again comes with a hint.
##
## The reach of a source is the `hexes` land hexes nearest its city's site, where its landmark
## stands. It is small on purpose: the city as a whole must still be able to reach the stage that
## offers the job (Sources' open_stage) and opens the next city, so the reach stays under the
## share of hexes a city may leave behind (1 - the districts' stage_share); setup reports a table
## that breaks this.
##
## Data: the planet's "sources" table, key "spread" (a source may override any of its keys with a
## "spread" of its own, and names its `soil_kind`). No table, no key or hexes 0: nothing is held
## and nothing comes back.
## Emits on EventBus: source_soiled(district, cell).
## Nothing is saved: the fouled hexes are the globe's own state, and the trickle's clock starts
## again after a load.
##
## Use: var s := SourceSpread.new(); add_child(s); s.setup(def, sources, districts, cells);
##      s.soil_fn = pollution.soil; hex_levels.cap_fn = s.hex_cap

const KEY: String = "spread"

## func(cell: int, kind: String, share: float) -> float: fouls a clean hex in the world and
## returns the share of its waste that came back (Pollution.soil). Unset: the cell alone is
## written.
var soil_fn: Callable

var _sources: Sources
var _districts: Districts
var _cells: SphereCells
var _specs: Dictionary[String, Dictionary] = {}
var _reach: Dictionary[String, PackedInt32Array] = {}
var _cell_city: Dictionary[int, String] = {}
var _clock: Dictionary[String, float] = {}
var _rng := RandomNumberGenerator.new()


func _physics_process(delta: float) -> void:
	for id: String in _reach:
		step(id, delta)


# --- Rules (static: the game and the tests read the same data) -----------------------------------

## A source's spread with every field filled in: {hexes, hex_stage, from_stage, every_s, amount,
## max_soiled, kind}. `src` is the source's entry of the table.
static func spec_for(table: Dictionary, src: Dictionary) -> Dictionary:
	var base: Dictionary = table.get(KEY, {}) if table.get(KEY) is Dictionary else {}
	var own: Dictionary = src.get(KEY, {}) if src.get(KEY) is Dictionary else {}
	var d: Dictionary = base.merged(own, true)
	return {
		"hexes": maxi(0, int(d.get("hexes", 0))),
		"hex_stage": clampi(int(d.get("hex_stage", Districts.MAX_STAGE)), 1, Districts.MAX_STAGE),
		"from_stage": clampi(int(d.get("from_stage", 0)), 0, Districts.MAX_STAGE),
		"every_s": maxf(0.0, float(d.get("every_s", 0.0))),
		"amount": clampf(float(d.get("amount", 0.0)), 0.0, 1.0),
		"max_soiled": maxi(0, int(d.get("max_soiled", 0))),
		"kind": str(src.get("soil_kind", "")),
	}


## The most of a hex's waste a source brings back per second (0 when it has no trickle).
static func units_per_s(spec: Dictionary, units_per_hex: float) -> float:
	return float(spec["amount"]) * units_per_hex / float(spec["every_s"]) if float(spec["every_s"]) > 0.0 else 0.0


# --- Setup --------------------------------------------------------------------------------------

func setup(def: PlanetDefinition, sources: Sources, districts: Districts, cells: SphereCells) -> void:
	_sources = sources
	_districts = districts
	_cells = cells
	_rng.seed = hash([str(def.id) if def else "", "source_spread"])
	var table: Dictionary = def.table(Sources.TABLE) if def and def.has_table(Sources.TABLE) else {}
	for raw: Variant in table.get("sources", []):
		if not raw is Dictionary:
			continue
		var id: String = str((raw as Dictionary).get("district", ""))
		if sources == null or not sources.has(id) or _reach.has(id):
			continue
		var spec: Dictionary = spec_for(table, raw)
		if int(spec["hexes"]) <= 0:
			continue
		_specs[id] = spec
		_reach[id] = _nearest_land(id, int(spec["hexes"]))
		_clock[id] = float(spec["every_s"])
		for c: int in _reach[id]:
			_cell_city[c] = id
		_check_reach(id)


func _nearest_land(district: String, count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for c: int in _districts.cells_of(district):
		if out.size() >= count:
			break
		if Districts.cell_stage(_cells, c) != Districts.NOT_LAND:
			out.append(c)
	return out


## A reach that holds more hexes below the job's stage than the city may leave behind would lock
## the city: the job could never come on offer.
func _check_reach(district: String) -> void:
	var spec: Dictionary = _specs[district]
	if int(spec["hex_stage"]) >= int(_sources.spec_of(district)["open_stage"]):
		return
	if _reach[district].size() > spare_hexes(district):
		push_error("SourceSpread: %s holds %d hexes at stage %d, but only %d may stay below the job's stage" % [
			district, _reach[district].size(), int(spec["hex_stage"]), spare_hexes(district)])


# --- Queries ------------------------------------------------------------------------------------

## The cities whose source reaches into the ground round it.
func ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in _reach:
		out.append(id)
	return out


## The spread of a city's source ({} when it has none): see spec_for.
func spec_of(district: String) -> Dictionary:
	return _specs.get(district, {})


## The hexes a city's source reaches, nearest first.
func reach_of(district: String) -> PackedInt32Array:
	return _reach.get(district, PackedInt32Array())


## How many of a city's land hexes may stay below a stage while the city still reaches it.
func spare_hexes(district: String) -> int:
	var land: int = _districts.land_of(district)
	return land - Districts.hexes_needed(PackedInt32Array([land]), _districts.stage_share)


## Whether a hex lies in the reach of a source that still runs.
func holds(cell: int) -> bool:
	var id: String = _cell_city.get(cell, "")
	return id != "" and not _sources.is_shut(id)


## The highest regrowth stage a hex may reach for now (Districts.MAX_STAGE when nothing holds it).
func hex_cap(cell: int) -> int:
	return int(_specs[_cell_city[cell]]["hex_stage"]) if holds(cell) else Districts.MAX_STAGE


## Whether a city's source fouls the ground now: it runs, the city is open and has reached the
## stage the trickle starts at.
func trickling(district: String) -> bool:
	if not _reach.has(district) or _sources.is_shut(district) or not _districts.is_unlocked(district):
		return false
	var spec: Dictionary = _specs[district]
	return float(spec["every_s"]) > 0.0 and float(spec["amount"]) > 0.0 and int(spec["max_soiled"]) > 0 \
		and _districts.stage_of(district) >= int(spec["from_stage"])


## Hexes of a city's reach that lie dirty now.
func dirty_in_reach(district: String) -> int:
	var n: int = 0
	for c: int in reach_of(district):
		n += 1 if _cells.is_dirty(c) else 0
	return n


## The hex readout's line for a hex the source is the reason for, in the player's language: one
## held at its stage, or lying dirty in the reach while the trickle runs. "" for any other hex.
func hex_note(cell: int) -> String:
	if not holds(cell):
		return ""
	var stuck: bool = Districts.cell_stage(_cells, cell) >= hex_cap(cell)
	var fouled: bool = _cells.is_dirty(cell) and trickling(_cell_city[cell])
	return tr("SOURCE STILL RUNNING") if stuck or fouled else ""


# --- The trickle --------------------------------------------------------------------------------

## Carries a city's trickle on by `seconds` (the node calls this on the fixed tick). Returns the
## hex that was fouled now, or -1.
func step(district: String, seconds: float) -> int:
	if not trickling(district):
		if _clock.has(district):
			_clock[district] = float(_specs[district]["every_s"])
		return -1
	_clock[district] -= seconds
	if _clock[district] > 0.0:
		return -1
	var spec: Dictionary = _specs[district]
	_clock[district] = float(spec["every_s"])
	if dirty_in_reach(district) >= int(spec["max_soiled"]):
		return -1
	var clean: Array[int] = []
	for c: int in _reach[district]:
		if Districts.cell_stage(_cells, c) >= 1:
			clean.append(c)
	while not clean.is_empty():
		var c: int = clean.pop_at(_rng.randi() % clean.size())
		if _soil(c, str(spec["kind"]), float(spec["amount"])) > 0.0:
			GameState.inc_stat("source_soiled", 1)
			if DevHooks.has("autoplay"):  # pacing log
				print("[sources] %s fouled hex %d again at %.1f min" % [district, c, float(GameState.stats.get("time_played", 0.0)) / 60.0])
			EventBus.source_soiled.emit(district, c)
			if Once.take("toast_source_soiled"):
				EventBus.toast.emit(tr("A source that still runs fouls the ground round it again. Shut it down to stop it."), "hint")
			return c
	return -1


func _soil(cell: int, kind: String, share: float) -> float:
	if soil_fn.is_valid():
		return float(soil_fn.call(cell, kind, share))
	_cells.set_state(cell, PlanetData.State.JUNK)
	_cells.set_junk(cell, share)
	return share
