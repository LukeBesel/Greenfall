class_name SphereOffline
extends RefCounted
## [orbC] Offline progress (and far-crew work) on a round planet, per hub region and by cell id.
## The maths is the flat game's (core/offline.gd: Offline.compute / unit_rate / units_value); this
## only turns junk units into cells: the dirty cells of a hub region, nearest the hub first, lose
## their junk (SphereCells.junk) and cells that a near ring has materialized are settled into the
## SphereField ledger (pieces removed, so the junk view hides them).
##
## A globe cell holds UNITS_PER_CELL units of junk when untouched: SphereField.FULL_PIECES pieces
## at Offline's ~0.9 units per piece. That keeps a Scoopie's work per hour the same in both games.

const UNITS_PER_CELL: float = SphereField.FULL_PIECES * 0.9
## A lake hex's floating junk (SphereField.FLOAT_PIECES floaters): Skimmers' work.
const UNITS_PER_WATER_CELL: float = SphereField.FLOAT_PIECES * 0.9
## Hub region on Verdance (163,842 cells, 10 hubs): 16 rings, ~820 cells, ~280 m across. Other
## planets scale it with their area per hub (region_rings), since planets differ in size and hub
## count (docs/DECISIONS.md "Planets differ in size"). Hex size stays 10 m everywhere, so
## UNITS_PER_CELL and the per-robot rates do not change; bigger planets go faster only through
## their bots and tools (Economy stats, which Offline.unit_rate reads).
const REGION_RINGS: int = 16
const REF_CELLS_PER_HUB: float = 163842.0 / 10.0
## A planet's hub count from its definition ("" or an unknown id: the planet being played).
static func hub_count(planet_id: String = "") -> int:
	var def: PlanetDefinition = Planets.by_id(planet_id) if Planets.has(planet_id) else Planets.current()
	return maxi(1, def.hub_count)


## Rings of a hub region on a planet of `cell_count` cells with `hubs` hubs: the region keeps the
## same share of each hub's ground as on Verdance, so its radius grows with sqrt(area per hub).
static func region_rings(cell_count: int, hubs: int) -> int:
	var per_hub: float = float(cell_count) / float(maxi(hubs, 1))
	return maxi(4, roundi(REGION_RINGS * sqrt(per_hub / REF_CELLS_PER_HUB)))


## region_rings for a planet id on this grid.
static func rings_for(grid: SphereGrid, planet_id: String = "") -> int:
	return region_rings(grid.cell_count(), hub_count(planet_id))


## Cells of the hub region, in ring order (nearest the hub first), water excluded.
static func region(grid: SphereGrid, cells: SphereCells, hub: int, rings: int = REGION_RINGS) -> PackedInt32Array:
	var out := PackedInt32Array()
	for c: int in grid.cells_around(hub, rings):
		if cells.state[c] != 5:
			out.append(c)
	return out


## The hub region's lake cells (Skimmers' ground), nearest the hub first.
static func region_water(grid: SphereGrid, cells: SphereCells, hub: int, rings: int = REGION_RINGS) -> PackedInt32Array:
	var out := PackedInt32Array()
	for c: int in grid.cells_around(hub, rings):
		if cells.state[c] == 5:
			out.append(c)
	return out


static func _dirty(cells: SphereCells, c: int) -> bool:
	return cells.is_dirty(c) or (cells.state[c] == 5 and cells.junk[c] > SphereCells.CLEAN_LEFT)


static func _upc(cells: SphereCells, c: int) -> float:
	return UNITS_PER_WATER_CELL if cells.state[c] == 5 else UNITS_PER_CELL


## Junk units left in a list of cells (land, or a lake's floaters).
static func units_left(cells: SphereCells, list: PackedInt32Array) -> float:
	var u: float = 0.0
	for c: int in list:
		if _dirty(cells, c):
			u += cells.junk[c] * _upc(cells, c)
	return u


## Write a cell's remaining junk (0..1) everywhere it lives: SphereCells (ground texture, far
## shell), and the SphereField ledger, removing pieces if the cell is materialized. Returns the
## removed piece ids (callers with a junk view hide them).
static func write_cell(cells: SphereCells, field: SphereField, c: int, left: float) -> PackedInt32Array:
	var gone := PackedInt32Array()
	left = clampf(left, 0.0, 1.0)
	if SphereCells.clean_left(left):  # [v2feel] the shared clean rule (95% cleared sweeps the rest)
		left = 0.0  # SphereCells.is_dirty's threshold: a crumb is a clean cell
	if field != null and field.materialized[c] == 1:
		gone = field.reduce_to(c, left)
		var real_left: float = 1.0 - field.removed_fraction(c) if field.hex_clean[c] == 0 else 0.0
		cells.set_junk(c, real_left if left > 0.0 else 0.0)
	else:
		cells.set_junk(c, left)
		if field != null and field.materialized[c] == 0:
			field.hex_left[c] = cells.junk[c]
			field.hex_total[c] = 1.0
	if (left <= 0.0 or not cells.is_dirty(c)) and cells.state[c] == 0:
		cells.set_state(c, 1)
	sync_clean(cells, field, c)
	return gone


## The one rule for "this hex is now clean" in the ledger, the same one SphereField uses when a
## save loads: not dirty any more (land junk <= SphereCells.CLEAN_LEFT, or a lake's floaters gone) -> hex_clean, and
## counted in cleaned_count unless it is hub ground or a lake. Returns true if it just turned clean.
## Keeps the live count identical to the count after a reload.
static func sync_clean(cells: SphereCells, field: SphereField, c: int) -> bool:
	if field == null or field.hex_clean[c] == 1 or field.cell_dirty(c):
		return false
	field.hex_clean[c] = 1
	if field.hex_hub[c] == 0 and field.hex_water[c] == 0:
		field.cleaned_count += 1
	return true


## Take `units` of junk from the region, nearest dirty cell first. Returns {units, cells (cleaned
## fully), touched (PackedInt32Array), pieces (removed piece ids)}.
static func take_units(cells: SphereCells, field: SphereField, list: PackedInt32Array, units: float) -> Dictionary:
	var out: Dictionary = {"units": 0.0, "cells": 0, "touched": PackedInt32Array(), "pieces": PackedInt32Array()}
	var budget: float = units
	for c: int in list:
		if budget <= 1e-6:
			break
		if not _dirty(cells, c):
			continue
		var upc: float = _upc(cells, c)
		var have: float = cells.junk[c] * upc
		var take: float = minf(have, budget)
		budget -= take
		var left: float = (have - take) / upc
		(out["pieces"] as PackedInt32Array).append_array(write_cell(cells, field, c, left))
		(out["touched"] as PackedInt32Array).append(c)
		if not _dirty(cells, c):
			out["cells"] = int(out["cells"]) + 1
	out["units"] = units - budget
	return out


## The offline jump for a whole planet. `hubs` = [{cell, robots: [{type, tier}], rings?,
## scrubbers?, filter_per_s?}]; rings default to the planet's region size (rings_for). Each hub earns Offline.compute() over its own region's junk and
## the region's cells are cleaned by the units it baled. Returns compute()'s keys summed over the
## hubs (seconds, units, cubes, waiting_value, air) plus cells, pieces and per-hub results in
## "hubs". Does NOT add currency: Offline.apply() the result once.
static func simulate(grid: SphereGrid, cells: SphereCells, field: SphereField, hubs: Array, seconds: float, planet_id: String = "") -> Dictionary:
	var def_rings: int = rings_for(grid, planet_id)
	var total: Dictionary = {"seconds": clampf(seconds, 0.0, Offline.CAP_S), "units": 0.0, "cubes": 0.0, "waiting_value": 0.0,
		"air": 0.0, "cells": 0, "pieces": PackedInt32Array(), "hubs": []}
	for h: Dictionary in hubs:
		var rings: int = int(h.get("rings", def_rings))
		var list: PackedInt32Array = region(grid, cells, int(h["cell"]), rings)
		# Skimmers work the region's lakes, everyone else its land: same maths, own junk caps.
		var land: Array = []
		var skim: Array = []
		for r: Dictionary in h.get("robots", []):
			var role: String = str(Economy.robots.get(str(r.get("type", "")), {}).get("role", "clean"))
			if role == "skim":
				skim.append(r)
			else:
				land.append(r)
				if role == "haul":
					skim.append(r)  # haulers serve both
		var res: Dictionary = Offline.compute(land, int(h.get("scrubbers", 0)), float(h.get("filter_per_s", 1.0)),
			seconds, units_left(cells, list))
		var took: Dictionary = take_units(cells, field, list, float(res["units"]))
		if not skim.is_empty():
			var wl: PackedInt32Array = region_water(grid, cells, int(h["cell"]), rings)
			var wres: Dictionary = Offline.compute(skim, 0, 1.0, seconds, units_left(cells, wl))
			var wt: Dictionary = take_units(cells, field, wl, float(wres["units"]))
			for k: String in ["units", "cubes", "waiting_value"]:
				res[k] = float(res[k]) + float(wres[k])
			took["cells"] = int(took["cells"]) + int(wt["cells"])
			(took["pieces"] as PackedInt32Array).append_array(wt["pieces"])
		res["cells"] = took["cells"]
		res["hub"] = int(h["cell"])
		for k: String in ["units", "cubes", "waiting_value", "air"]:
			total[k] = float(total[k]) + float(res[k])
		total["cells"] = int(total["cells"]) + int(took["cells"])
		(total["pieces"] as PackedInt32Array).append_array(took["pieces"])
		(total["hubs"] as Array).append(res)
	return total
