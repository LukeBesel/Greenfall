class_name PollutionSoil
extends RefCounted
## Waste that comes back onto clean ground (design spec section 4): a city's running source fouls
## a clean hex near it again (systems/source_spread.gd asks through Pollution.soil). Pollution
## owns one of these.
##
## What comes back is part of the hex's own waste, so every rule a dirty hex has still holds: the
## same ledger, the same 95% clean rule, the same tools and robots. A kind worked with a tool
## (held) comes back as that kind where the hex holds it; any other kind comes back as loose
## pieces: where the hex has been laid out, the pieces that were taken from it, those of that
## kind first; a hex laid out while it was clean (after a load) gets its pieces laid out now
## (SphereField.lay_again). Waste nobody can scoop never lies anywhere: a hex that can get no
## piece back is left clean.
##
## The hex keeps what grew on it. Its regrowth level is not touched (HexLevels never drops), and
## the cell state it showed (planted, growing, restored) is put back when it is clean again.
##
## Use: var s := PollutionSoil.new(); s.setup(pollution, saved); s.soil(cell, "litter", 0.3)

## The least that may come back: clearly above the part of a hex that sweeps away by itself.
const MIN_BACK: float = SphereCells.CLEAN_LEFT * 2.0

var _p: Pollution
## Hex -> the cell state it showed before it was fouled.
var _state_before: Dictionary[int, int] = {}


## `saved` is save_state()'s array.
func setup(p: Pollution, saved: Array = []) -> void:
	_p = p
	for i: int in range(0, saved.size() - 1, 2):
		_state_before[int(saved[i])] = int(saved[i + 1])


## Flat pairs [hex, state before, ...] of the hexes that are fouled now.
func save_state() -> Array:
	var out: Array = []
	for c: int in _state_before:
		out.append(c)
		out.append(_state_before[c])
	return out


## Whether a hex lies fouled by a source right now.
func is_soiled(cell: int) -> bool:
	return _state_before.has(cell)


## Fouls clean land hex `cell` again with `share` (0..1) of its waste, as kind `kind_id` where
## the hex can hold it. Returns the share that came back (0: not clean land, or nothing to bring
## back).
func soil(cell: int, kind_id: String, share: float) -> float:
	var cells: SphereCells = _p._cells
	var field: SphereField = _p._field
	if cells == null or cell < 0 or cell >= cells.n or Districts.cell_stage(cells, cell) < 1:
		return 0.0
	var k: int = _p._index.get(kind_id, -1)
	var held: bool = k >= 0 and str(_p._kinds[k]["work"]) == Pollution.WORK_HELD and k in _p.kinds_at(cell) and cell < cells.hold.size()
	var back: float = clampf(share, MIN_BACK, 1.0)
	if held:
		back = clampf(back, MIN_BACK, maxf(MIN_BACK, _p.share_of(cell, kind_id)))
	var before: int = cells.state[cell]
	var laid_out: bool = field != null and field.materialized[cell] == 1
	if laid_out and not held and field.pieces_in(cell).is_empty():
		return _lay_out(field, cell, back, before)
	if laid_out:
		back = _held_back(field, cell, back) if held else _pieces_back(field, cell, back, k)
		if back <= 0.0:
			return 0.0
	elif field != null:
		field.hex_left[cell] = back
		field.hex_total[cell] = 1.0
		_unclean(field, cell)
	_state_before[cell] = before
	cells.set_state(cell, PlanetData.State.JUNK)
	cells.set_junk(cell, back)
	if held:
		var left := PackedFloat32Array()
		left.resize(_p._kinds.size())
		left[k] = clampf(back / _p.share_of(cell, kind_id), 0.0, 1.0)
		_p._held[cell] = left
		cells.hold[cell] = back
	if laid_out and _p.cell_written.is_valid():
		_p.cell_written.call(cell, false, false)
	return back


## A hex laid out while it was clean: its cell is written dirty and its pieces are laid out from
## that. Undone when no piece comes of it.
func _lay_out(field: SphereField, cell: int, back: float, before: int) -> float:
	var cells: SphereCells = _p._cells
	cells.set_state(cell, PlanetData.State.JUNK)
	cells.set_junk(cell, back)
	if field.lay_again(cell).is_empty() or field.hex_total[cell] <= 0.0:
		cells.set_junk(cell, 0.0)
		cells.set_state(cell, before)
		return 0.0
	_unclean(field, cell)
	_state_before[cell] = before
	if _p.cell_written.is_valid():
		_p.cell_written.call(cell, false, false)
	return field.hex_left[cell] / field.hex_total[cell]


## Puts back the cell state of every fouled hex that is clean again (Pollution's poll calls it:
## the clean-hex flow writes its own state first, so this cannot run inside it).
func settle() -> void:
	if _state_before.is_empty():
		return
	var cells: SphereCells = _p._cells
	for c: int in _state_before.keys():
		if cells.is_dirty(c):
			continue
		var before: int = _state_before[c]
		_state_before.erase(c)
		if cells.state[c] == PlanetData.State.CLEAN and before > PlanetData.State.CLEAN and before != PlanetData.State.WATER:
			cells.set_state(c, before)


## A held kind on a laid-out hex: no pieces, the ledger alone rises.
func _held_back(field: SphereField, cell: int, back: float) -> float:
	var total: float = field.worth.work(cell)  # a hex laid out while clean has no ledger of its own yet
	if total <= 0.0:
		return 0.0
	field.hex_total[cell] = total
	field.hex_left[cell] = back * total
	_unclean(field, cell)
	return back


## Loose waste on a laid-out hex: pieces taken from it come back, those of kind `k` first, until
## `back` of the hex is there. Returns the share that is back (0 when nothing could be).
func _pieces_back(field: SphereField, cell: int, back: float, k: int) -> float:
	var total: float = field.hex_total[cell]
	if total <= 0.0:
		return 0.0
	var picked := PackedInt32Array()
	var vol: float = 0.0
	for want_kind: bool in [true, false]:
		for pid: int in field.pieces_in(cell):
			if vol >= back * total:
				break
			if field.piece_alive[pid] == 1 or (int(field.piece_kind[pid]) == k) != want_kind:
				continue
			picked.append(pid)
			vol += field.piece_vol[pid]
	if picked.is_empty():
		return 0.0
	field.revive_pieces(picked)
	if field.hex_clean[cell] == 1:  # too little came back to count: take it away again
		field.sweep_cell(cell)
		return 0.0
	return field.hex_left[cell] / total


func _unclean(field: SphereField, cell: int) -> void:
	if field.hex_clean[cell] == 0:
		return
	field.hex_clean[cell] = 0
	if field.hex_hub[cell] == 0 and field.hex_water[cell] == 0:
		field.cleaned_count -= 1
