class_name HexWorth
extends RefCounted
## What one hex holds and what it is worth (design spec section 14: "a hex has a cube value; a unit
## of waste does not"). Each district states the units of waste in one of its hexes (`hex_work`)
## and the cubes a whole cleaned hex pays when Lumi tips it loose (`hex_cubes`). A load pays its
## share of the hex's value by the share of the hex's waste it holds, so heavier hexes in later
## districts do not pay more per hex than the district says.
##
## Data: the planet's "districts" table. Per district: hex_work, hex_cubes and an optional
## first_hexes {work, rings, full_ring} that makes the hexes round the site lighter (`work` out to
## `rings`, rising evenly to hex_work at `full_ring`). Top level: open_ground {hex_work, hex_cubes}
## for hexes outside every district.
##
## A planet without these fields keeps the weight every hex had before districts existed
## (DEFAULT_WORK) and a hex is worth its waste at the planet's average waste value, which is what
## a unit-priced hex paid.

## Units of waste in a hex when the planet's data does not say.
const DEFAULT_WORK: float = 407.0

var open_work: float = DEFAULT_WORK
var open_cubes: float = DEFAULT_WORK
var _work: Dictionary[int, float] = {}
var _cubes: Dictionary[int, float] = {}


## The worth of every district hex of `def` on `grid`. site_cells[i] is the hex hub site i stands
## on. Where two districts overlap, a hex belongs to the earlier one (as in Districts).
static func for_planet(def: PlanetDefinition, grid: SphereGrid, site_cells: PackedInt32Array) -> HexWorth:
	var out := HexWorth.new()
	var mean: float = mean_waste_value()
	out.open_cubes = DEFAULT_WORK * mean
	if def == null or not def.has_table(Districts.TABLE):
		return out
	var table: Dictionary = def.table(Districts.TABLE)
	var open: Dictionary = table.get("open_ground", {})
	out.open_work = maxf(1.0, float(open.get("hex_work", DEFAULT_WORK)))
	out.open_cubes = float(open.get("hex_cubes", out.open_work * mean))
	if grid == null:
		return out
	for raw: Variant in table.get("districts", []):
		if not raw is Dictionary:
			continue
		var d: Dictionary = raw
		var site: int = int(d.get("site", 0))
		if site < 0 or site >= site_cells.size():
			continue
		var work: float = maxf(1.0, float(d.get("hex_work", out.open_work)))
		var cubes: float = float(d.get("hex_cubes", work * mean))
		var first: Dictionary = d.get("first_hexes", {})
		var rings: Array[PackedInt32Array] = rings_around(grid, site_cells[site], int(d.get("rings", Districts.FALLBACK_RINGS)))
		for r: int in rings.size():
			var w: float = work_at_ring(work, first, r)
			for c: int in rings[r]:
				if out._work.has(c):
					continue
				out._work[c] = w
				out._cubes[c] = cubes
	return out


## Units of waste in a hex `ring` rings from its district's site.
static func work_at_ring(full_work: float, first: Dictionary, ring: int) -> float:
	if first.is_empty():
		return full_work
	var start: float = float(first.get("work", full_work))
	var flat: int = int(first.get("rings", 0))
	var full: int = maxi(int(first.get("full_ring", flat + 1)), flat + 1)
	if ring <= flat:
		return start
	if ring >= full:
		return full_work
	return lerpf(start, full_work, float(ring - flat) / float(full - flat))


## The hexes at exactly 0, 1, .. `rings` rings from `cell`.
static func rings_around(grid: SphereGrid, cell: int, rings: int) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = [PackedInt32Array([cell])]
	var seen: Dictionary[int, bool] = {cell: true}
	for _r: int in rings:
		var next := PackedInt32Array()
		for c: int in out[-1]:
			for k: int in grid.nbr_count[c]:
				var j: int = grid.nbr[c * SphereGrid.MAX_N + k]
				if not seen.has(j):
					seen[j] = true
					next.append(j)
		out.append(next)
	return out


## The planet's average cubes per unit of waste, weighted as the field lays it.
static func mean_waste_value() -> float:
	var wsum: float = 0.0
	var vsum: float = 0.0
	for id: String in Economy.junk_ids:
		var t: Dictionary = Economy.junk_types[id]
		var w: float = float(t.get("weight", 1.0))
		wsum += w
		vsum += w * float(t.get("value", 1.0))
	return vsum / wsum if wsum > 0.0 else 1.0


## Units of waste in an untouched hex.
func work(cell: int) -> float:
	return _work.get(cell, open_work)


## Cubes the whole hex pays, tipped loose.
func cubes(cell: int) -> float:
	return _cubes.get(cell, open_cubes)


## Cubes (loose) for `vol` units taken from a hex of `total` units that had `left_before` left.
## Only the waste down to the clean line counts (the rest sweeps away when the hex turns clean:
## `clean_share` of the hex, 0.95 on the globe), so a hex cleaned by hand from full pays exactly
## its value however the last scoop falls.
func share(cell: int, vol: float, left_before: float, total: float, clean_share: float) -> float:
	return share_of(cubes(cell), vol, left_before, total, clean_share)


static func share_of(hex_cubes: float, vol: float, left_before: float, total: float, clean_share: float) -> float:
	var payable: float = total * clampf(clean_share, 0.01, 1.0)
	if payable <= 0.0 or vol <= 0.0:
		return 0.0
	var above_line: float = maxf(0.0, left_before - (total - payable))
	return hex_cubes * minf(vol, above_line) / payable
