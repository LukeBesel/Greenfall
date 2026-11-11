class_name Pollution
extends Node
## The pollution kinds of the planet being played (design spec section 2): families of waste, each
## with its own spawn rule, tool gate and payout. All of it is data: the planet's "pollution_kinds"
## table names the kinds, and each district of the "districts" table lists the kinds its hexes hold.
##
## A hex has ONE ledger of waste (SphereField.hex_left of hex_total; SphereCells.junk as a share).
## Every kind on the hex owns a share of it, so "clean" stays one rule: the hex is clean when 95%
## of its waste is gone, whatever the kinds, and no kind's share is small enough to sweep away
## untouched (MIN_SHARE). How a kind is worked is its `work`:
##   pieces  loose junk Lumi and cleaner robots scoop (the base kind; a hex's remaining share)
##   heavy   a few big pieces from the kind's own models, scooped once the gate is met
##   float   the floating waste of a water hex (the whole hex)
##   held    no pieces: Lumi takes it with a tool ("water" or "plant"), a robot of a listed role
##           with its own. Its share is "held": scooping cannot take it (SphereCells.hold).
## What Lumi takes of any kind goes into her chest and pays its share of the hex's cube value
## (HexWorth) times the kind's yield over the hex's average yield. Robots are paid nothing.
##
## Emits on EventBus: pollution_cleared(kind, amount, by_player) in units of waste (robot work is
## batched every POLL_S), pollution_blocked(kind, cell) when Lumi tries a kind she has no tool for.
##
## A planet without the table has one implicit kind, so every listener still gets its events.
##
## Mastery (systems/mastery.gd, given with set_mastery): robots leave a kind alone until Lumi has
## learnt it and work it faster as she masters it (systems/pollution_crew.gd keeps the hexes that
## are shut to them); Lumi's own rate on a kind rises with its level.
##
## Use: var p := Pollution.new(); add_child(p); p.setup(def, grid, cells, field, site_cells, saved)

const TABLE: String = "pollution_kinds"
const WORK_PIECES: String = "pieces"
const WORK_HEAVY: String = "heavy"
const WORK_FLOAT: String = "float"
const WORK_HELD: String = "held"
const ON_WATER: String = "water"
const IMPLICIT_KIND: String = "waste"
## A kind's share of a hex is never below this: above the part of a hex that sweeps away by itself.
const MIN_SHARE: float = 0.08
## All the kinds beside the base kind never own more of a hex than this.
const MAX_OTHER_SHARE: float = 0.9
const POLL_S: float = 0.5
const HINT_GAP_MS: int = 5000
const LEFT_EPS: float = 0.001
## A hex's held share may pass its junk left by this much (rounding) before it is cut down to fit.
const HOLD_SLACK: float = 0.0001
const SAVE_SCALE: float = 10000.0
const NO_ZONE: int = -1
const FAR_RING: int = 9999

## func(cell: int, became_clean: bool, by_player: bool): the world writes the hex where it shows.
var cell_written: Callable
## Lumi's mastery of the kinds (null: none on this planet, robots work everything at their own rate).
var mastery: Mastery

var _kinds: Array[Dictionary] = []
var _index: Dictionary[String, int] = {}
var _default: PackedInt32Array = PackedInt32Array()
var _zone_ids: Array[String] = []
var _zone_kinds: Array[PackedInt32Array] = []
var _zone_cells: Array[PackedInt32Array] = []
var _cell_zone: Dictionary[int, int] = {}
var _cell_ring: Dictionary[int, int] = {}
var _cell_kinds: Dictionary[int, PackedInt32Array] = {}
## Hex -> share still left (0..1) of each held kind on it, by kind index. Only dirty hexes.
var _held: Dictionary[int, PackedFloat32Array] = {}
var _debt: Dictionary[String, float] = {}
var _robot_acc: PackedFloat32Array = PackedFloat32Array()
var _grid: SphereGrid
var _cells: SphereCells
var _field: SphereField
var _noise: FastNoiseLite
var _seed: int = 0
var _poll: float = 0.0
var _hint_ms: int = -HINT_GAP_MS
var _crew_gate: PollutionCrew


func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = POLL_S
	refresh_gates()
	flush_robot_events()
	if _crew_gate != null:
		_crew_gate.flush()


func _exit_tree() -> void:
	if _cells and _cells.cell_changed.is_connected(_on_cell_changed):
		_cells.cell_changed.disconnect(_on_cell_changed)
	if mastery != null and is_instance_valid(mastery) and mastery.changed.is_connected(_on_mastery_changed):
		mastery.changed.disconnect(_on_mastery_changed)


# --- Setup and state --------------------------------------------------------------------------

## Reads the planet's kinds, works out which hexes hold which, and restores a save_state()
## dictionary (empty: every dirty hex holds its kinds untouched, so saves from before the kinds
## existed load as they are). site_cells[i] is the hex hub site i stands on.
func setup(def: PlanetDefinition, grid: SphereGrid, cells: SphereCells, field: SphereField, site_cells: PackedInt32Array, saved: Dictionary = {}) -> void:
	_grid = grid
	_cells = cells
	_field = field
	_seed = field.seed_value if field else 0
	_noise = FastNoiseLite.new()
	_noise.seed = _seed
	_noise.frequency = 1.0
	_read_kinds(def.table(TABLE) if def else {})
	_robot_acc.resize(_kinds.size())
	_build_zones(def, site_cells)
	_build_holds(saved)
	for id: Variant in (saved.get("debt", {}) as Dictionary):
		_debt[str(id)] = float(saved["debt"][id])
	if field:
		field.heavy_plan = heavy_plan
	refresh_gates()
	if cells and not cells.cell_changed.is_connected(_on_cell_changed):
		cells.cell_changed.connect(_on_cell_changed)


## Gives the kinds Lumi's mastery (after setup): from now on robots leave unlearnt kinds alone and
## work the others at their mastery rate. Re-read whenever a level moves.
func set_mastery(m: Mastery) -> void:
	mastery = m
	_crew_gate = PollutionCrew.new()
	_crew_gate.setup(self, _cells, m)
	if m != null and not m.changed.is_connected(_on_mastery_changed):
		m.changed.connect(_on_mastery_changed)


func _on_mastery_changed() -> void:
	if _crew_gate != null:
		_crew_gate.refresh()


## What a save keeps: for each held kind, the hexes where part of it is gone, and what is owed
## toward the next whole unit of a kind's cost.
func save_state() -> Dictionary:
	var held: Dictionary = {}
	for k: int in _kinds.size():
		if str(_kinds[k]["work"]) != WORK_HELD:
			continue
		var pairs := PackedInt32Array()
		for c: int in _held:
			var left: float = _held[c][k]
			if left < 1.0 - LEFT_EPS and _has_kind(c, k):
				pairs.append(c)
				pairs.append(int(round(left * SAVE_SCALE)))
		if not pairs.is_empty():
			held[str(_kinds[k]["id"])] = Marshalls.raw_to_base64(pairs.to_byte_array())
	return {"held": held, "debt": _debt.duplicate()}


func _read_kinds(table: Dictionary) -> void:
	var raw: Dictionary = table.get("kinds", {})
	var base: String = str(table.get("base", ""))
	if not raw.has(base):
		base = ""
		for id: String in raw:
			if str((raw[id] as Dictionary).get("work", WORK_PIECES)) == WORK_PIECES:
				base = id
				break
	if base == "":
		base = IMPLICIT_KIND
		raw = raw.duplicate()
		raw[base] = {"name": "Waste", "work": WORK_PIECES}
	var order: Array[String] = [base]
	for id: String in raw:
		if id != base:
			order.append(id)
	for id: String in order:
		var d: Dictionary = (raw[id] as Dictionary).duplicate(true)
		d["id"] = id
		d["work"] = WORK_PIECES if id == base else str(d.get("work", WORK_HELD))
		var spawn: Dictionary = d.get("spawn", {})
		d["share"] = clampf(float(spawn.get("share", 0.3)), MIN_SHARE, MAX_OTHER_SHARE)
		d["type"] = maxi(0, Economy.junk_ids.find(str(d.get("junk_type", ""))))
		_index[id] = _kinds.size()
		_kinds.append(d)
	_default = _to_indexes(table.get("default_kinds", [base]))


func _to_indexes(names: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for id: Variant in names:
		if _index.has(str(id)):
			out.append(_index[str(id)])
		else:
			push_warning("Pollution: unknown kind '%s'" % str(id))
	return out


## Each district's hexes with their ring from its site. Where two overlap, a hex belongs to the
## earlier one (as in Districts and HexWorth). A district that lists no kind gets the defaults.
func _build_zones(def: PlanetDefinition, site_cells: PackedInt32Array) -> void:
	for spec: Dictionary in Districts.specs_for(def):
		var site: int = int(spec["site"])
		if _grid == null or site < 0 or site >= site_cells.size():
			continue
		var kinds: PackedInt32Array = _to_indexes(spec.get("pollution", []))
		var z: int = _zone_ids.size()
		_zone_ids.append(str(spec["id"]))
		_zone_kinds.append(kinds if not kinds.is_empty() else _default)
		var own := PackedInt32Array()
		var rings: Array[PackedInt32Array] = HexWorth.rings_around(_grid, site_cells[site], int(spec["rings"]))
		for r: int in rings.size():
			for c: int in rings[r]:
				if _cell_zone.has(c):
					continue
				_cell_zone[c] = z
				_cell_ring[c] = r
				own.append(c)
		_zone_cells.append(own)


## Fills SphereCells.hold for every dirty hex with a held kind, from the save where it has one. A
## hex that has less waste left than its kinds would hold keeps what it has.
func _build_holds(saved: Dictionary) -> void:
	if _cells == null or not _any_held():
		return
	_cells.hold.resize(_cells.n)
	_cells.hold.fill(0.0)
	var saved_left: Dictionary[int, Dictionary] = {}
	for id: Variant in (saved.get("held", {}) as Dictionary):
		if not _index.has(str(id)):
			continue
		var pairs: PackedInt32Array = Marshalls.base64_to_raw(str(saved["held"][id])).to_int32_array()
		for i: int in range(0, pairs.size() - 1, 2):
			if not saved_left.has(pairs[i]):
				saved_left[pairs[i]] = {}
			saved_left[pairs[i]][_index[str(id)]] = float(pairs[i + 1]) / SAVE_SCALE
	var todo: Array[PackedInt32Array] = []
	if _has_held(_default):
		todo.append(PackedInt32Array(range(_cells.n)))
	else:
		for z: int in _zone_ids.size():
			if _has_held(_zone_kinds[z]):
				todo.append(_zone_cells[z])
	for list: PackedInt32Array in todo:
		for c: int in list:
			_init_hold(c, saved_left.get(c, {}))


func _init_hold(c: int, saved_left: Dictionary) -> void:
	if not _cells.is_dirty(c):
		return
	var left := PackedFloat32Array()
	left.resize(_kinds.size())
	var total: float = 0.0
	for k: int in kinds_at(c):
		if str(_kinds[k]["work"]) != WORK_HELD:
			continue
		left[k] = clampf(float(saved_left.get(k, 1.0)), 0.0, 1.0)
		total += left[k] * share_of(c, str(_kinds[k]["id"]))
	if total <= 0.0:
		return
	if total > _cells.junk[c] + HOLD_SLACK:
		for k: int in left.size():
			left[k] *= _cells.junk[c] / total
		total = _cells.junk[c]
	_held[c] = left
	_cells.hold[c] = total


func _any_held() -> bool:
	for kd: Dictionary in _kinds:
		if str(kd["work"]) == WORK_HELD:
			return true
	return false


func _has_held(list: PackedInt32Array) -> bool:
	for k: int in list:
		if str(_kinds[k]["work"]) == WORK_HELD:
			return true
	return false


## A hex that is no longer dirty holds nothing (cleaned by the last scoop, a site, a dev flag).
func _on_cell_changed(c: int) -> void:
	if _held.has(c) and not _cells.is_dirty(c):
		_held.erase(c)
		_cells.hold[c] = 0.0


# --- Queries ----------------------------------------------------------------------------------

## Kind ids, the base kind first.
func ids() -> Array[String]:
	var out: Array[String] = []
	for kd: Dictionary in _kinds:
		out.append(str(kd["id"]))
	return out


## A kind's data with every field filled in ({} for an unknown id).
func kind(id: String) -> Dictionary:
	return _kinds[_index[id]] if _index.has(id) else {}


func base_id() -> String:
	return str(_kinds[0]["id"])


## Every district's hexes, in district order.
func zone_lists() -> Array[PackedInt32Array]:
	return _zone_cells


## The kinds (indexes) of a hex outside every district.
func default_kinds() -> PackedInt32Array:
	return _default


## The kinds that spawn on a hex (kind indexes), whether or not they have been cleared since.
func kinds_at(cell: int) -> PackedInt32Array:
	if _cell_kinds.has(cell):
		return _cell_kinds[cell]
	var out := PackedInt32Array()
	if _cells != null and cell >= 0 and cell < _cells.n and (_cells.flags[cell] & SphereCells.F_HUB) == 0:
		var water: bool = _cells.state[cell] == PlanetData.State.WATER
		var z: int = _cell_zone.get(cell, NO_ZONE)
		for k: int in (_zone_kinds[z] if z >= 0 else _default):
			if _spawns(k, cell, water):
				out.append(k)
		if out.is_empty():  # plain junk: a lake with no float kind, a district that lists nothing
			out.append(0)
	_cell_kinds[cell] = out
	return out


func _spawns(k: int, cell: int, water: bool) -> bool:
	var kd: Dictionary = _kinds[k]
	var work: String = str(kd["work"])
	if water:
		return work == WORK_FLOAT
	if work == WORK_FLOAT:
		return false
	if k == 0:
		return true
	var spawn: Dictionary = kd.get("spawn", {})
	if str(spawn.get("on", "land")) == ON_WATER or int(_cell_ring.get(cell, FAR_RING)) < int(spawn.get("min_ring", 0)):
		return false
	return _roll(k, cell, float(spawn.get("cluster", 0.0))) < float(spawn.get("density", 1.0))


## 0..1 for (kind, hex), the same every run. cluster blends in a smooth field over the globe, so
## a kind lies in patches (the density is then only about right).
func _roll(k: int, cell: int, cluster: float) -> float:
	var h: float = float(absi(hash([_seed, cell, str(_kinds[k]["id"])])) % 100003) / 100003.0
	if cluster <= 0.0:
		return h
	var at: Vector3 = _grid.centers[cell].normalized() * (_grid.radius_m / 60.0) + Vector3(float(k) * 37.0, 0.0, 0.0)
	var n: float = clampf(_noise.get_noise_3dv(at) * 1.4 + 0.5, 0.0, 1.0)
	return lerpf(h, n, clampf(cluster, 0.0, 1.0))


func _has_kind(cell: int, k: int) -> bool:
	return k in kinds_at(cell)


## Kind ids with waste still on a hex (nothing for a clean hex).
func kinds_left(cell: int) -> Array[String]:
	var out: Array[String] = []
	if _cells == null or cell < 0 or cell >= _cells.n:
		return out
	var water: bool = _cells.state[cell] == PlanetData.State.WATER
	if not (_cells.is_dirty(cell) or (water and _cells.junk[cell] > SphereCells.CLEAN_LEFT)):
		return out
	for k: int in kinds_at(cell):
		if _kind_left(cell, k):
			out.append(str(_kinds[k]["id"]))
	return out


func _kind_left(cell: int, k: int) -> bool:
	match str(_kinds[k]["work"]):
		WORK_HELD:
			return held_left(cell, str(_kinds[k]["id"])) > LEFT_EPS
		WORK_FLOAT:
			return true
	if _field != null and _field.materialized[cell] == 1:
		for pid: int in _field.pieces_in(cell):
			if _field.piece_alive[pid] == 1 and _field.piece_kind[pid] == k:
				return true
		return false
	return _cells.junk[cell] > _cells.floor_of(cell) + SphereCells.WORK_EPS


## Share (0..1) of a held kind still on a hex.
func held_left(cell: int, id: String) -> float:
	return _held[cell][_index[id]] if _held.has(cell) and _index.has(id) else 0.0


## A kind's share of a hex's waste when the hex holds these kinds (the base kind has the rest).
func share_of(cell: int, id: String) -> float:
	var k: int = _index.get(id, -1)
	var list: PackedInt32Array = kinds_at(cell)
	if k < 0 or not k in list:
		return 0.0
	if list.size() == 1:
		return 1.0
	var others: float = 0.0
	for j: int in list:
		if j != 0:
			others += float(_kinds[j]["share"])
	var scale: float = minf(1.0, MAX_OTHER_SHARE / others) if others > 0.0 else 1.0
	if k != 0:
		return maxf(MIN_SHARE, float(_kinds[k]["share"]) * scale)
	return (1.0 - minf(others, MAX_OTHER_SHARE)) if 0 in list else 0.0


## SphereField's hook: the heavy kinds of a hex, each with its share of the hex's PIECE volume.
func heavy_plan(cell: int) -> Array:
	var out: Array = []
	var held: float = 0.0
	var list: PackedInt32Array = kinds_at(cell)
	for k: int in list:
		if str(_kinds[k]["work"]) == WORK_HELD:
			held += share_of(cell, str(_kinds[k]["id"]))
	for k: int in list:
		var kd: Dictionary = _kinds[k]
		if str(kd["work"]) != WORK_HEAVY:
			continue
		out.append({"kind": k, "share": share_of(cell, str(kd["id"])) / maxf(1.0 - held, 0.01), "type": int(kd["type"]),
			"pieces": int((kd.get("spawn", {}) as Dictionary).get("pieces", 3)), "models": kd.get("models", [])})
	return out


## How many hexes of a district ("" = the hexes outside every district are not counted) hold each
## kind: {kind id: hexes}. Hub ground holds nothing.
func census(district: String) -> Dictionary:
	var out: Dictionary = {}
	var z: int = _zone_ids.find(district)
	if z < 0:
		return out
	for c: int in _zone_cells[z]:
		for k: int in kinds_at(c):
			var id: String = str(_kinds[k]["id"])
			out[id] = int(out.get(id, 0)) + 1
	return out


## One line per district for a dev run: which kinds its hexes hold.
func report() -> PackedStringArray:
	var lines: PackedStringArray = []
	for z: int in _zone_ids.size():
		var parts: PackedStringArray = []
		var count: Dictionary = census(_zone_ids[z])
		for id: String in ids():
			if count.has(id):
				parts.append("%s %d" % [id, int(count[id])])
		lines.append("[pollution] %s (%d hexes): %s" % [_zone_ids[z], _zone_cells[z].size(), ", ".join(parts)])
	return lines


# --- Gates ------------------------------------------------------------------------------------

## Whether Lumi has what a kind needs. gate: {stat, min} = an upgrade stat of the planet at that
## value or more; {flag} = a progress flag that must be set. Both when both are given.
func can_work(id: String) -> bool:
	var gate: Dictionary = kind(id).get("gate", {})
	if gate.has("flag") and not bool(GameState.flags.get(str(gate["flag"]), false)):
		return false
	return not gate.has("stat") or Economy.stat(str(gate["stat"])) >= float(gate.get("min", 1.0)) - 0.001


## Tells the field which kinds' pieces Lumi cannot take yet.
func refresh_gates() -> void:
	if _field == null:
		return
	if _field.kind_blocked.size() != _kinds.size():
		_field.kind_blocked.resize(_kinds.size())
	for k: int in _kinds.size():
		_field.kind_blocked[k] = 0 if can_work(str(_kinds[k]["id"])) else 1


## Whether a hex holds waste Lumi has no tool for yet.
func hex_blocked(cell: int) -> bool:
	for id: String in kinds_left(cell):
		if not can_work(id):
			return true
	return false


## The line for the hex readout: the first kind beside the base kind still on the hex, with what
## it needs when Lumi lacks it, else how it is worked. "" for plain junk or a clean hex.
func hex_note(cell: int) -> String:
	var pick: String = ""
	for id: String in kinds_left(cell):
		if id == base_id():
			continue
		if not can_work(id):
			pick = id
			break
		if pick == "":
			pick = id
	if pick == "":
		return ""
	var kd: Dictionary = kind(pick)
	return tr(str(kd.get("prompt", ""))) if not can_work(pick) else tr(str(kd.get("hint", "")))


## A scoop pulse found nothing to take: if a piece of a gated kind is in the beam, or the hex only
## has waste another tool clears, say so (at most every few seconds). True when it spoke.
func scoop_hint(origin: Vector3, forward: Vector3, reach: float, width: float) -> bool:
	if _field == null or Time.get_ticks_msec() - _hint_ms < HINT_GAP_MS:
		return false
	var text: String = ""
	var at: Vector3 = origin + forward
	var pid: int = _field.find_scoop_target_sized(origin, forward, reach, width, 99, true)
	if pid >= 0:
		var kd: Dictionary = _kinds[_field.piece_kind[pid]]
		text = tr(str(kd.get("prompt", "")))
		at = _field.piece_pos[pid]
		EventBus.pollution_blocked.emit(str(kd["id"]), _field.piece_hex[pid])
	else:
		var cell: int = _field.hex_at(at)
		var left: Array[String] = kinds_left(cell)
		if not left.is_empty() and str(kind(left[0])["work"]) == WORK_HELD:
			text = hex_note(cell)
	if text == "":
		return false
	_hint_ms = Time.get_ticks_msec()
	Vfx.float_text(at + OrbitUp.up(at) * 1.0, text, Color(1.0, 0.75, 0.45), 0.4, 0.6)
	return true


# --- Lumi's work ------------------------------------------------------------------------------

## Lumi took `vol` units of a piece: the event for its kind.
func piece_taken(pid: int, vol: float) -> void:
	if _field == null or vol <= 0.0:
		return
	var cell: int = _field.piece_hex[pid]
	var k: int = kinds_at(cell)[0] if _field.hex_water[cell] == 1 else int(_field.piece_kind[pid])
	EventBus.pollution_cleared.emit(str(_kinds[k]["id"]), vol, true)
	if _crew_gate != null:
		_crew_gate.touched(cell)


## Lumi's rate multiplier on a kind from her mastery of it (1 with no mastery).
func hand_bonus(id: String) -> float:
	return mastery.hand_bonus(id) if mastery != null else 1.0


## Lumi's rate multiplier on the kind of piece `pid`.
func piece_hand_bonus(pid: int) -> float:
	if _field == null or mastery == null:
		return 1.0
	var cell: int = _field.piece_hex[pid]
	var k: int = kinds_at(cell)[0] if _field.hex_water[cell] == 1 else int(_field.piece_kind[pid])
	return mastery.hand_bonus(str(_kinds[k]["id"]))


## What a load of piece `pid` pays against the hex's plain share: the kind's yield over the hex's
## average yield, so a hex cleaned by hand still pays its value whatever it holds.
func piece_yield(pid: int) -> float:
	var cell: int = _field.piece_hex[pid]
	var k: int = kinds_at(cell)[0] if _field.hex_water[cell] == 1 else int(_field.piece_kind[pid])
	return _yield_factor(cell, k)


## Chance multiplier for a part worth stripping from a take of piece `pid`.
func piece_parts(pid: int) -> float:
	return float((_kinds[_field.piece_kind[pid]].get("yield", {}) as Dictionary).get("parts", 1.0))


func _yield_factor(cell: int, k: int) -> float:
	var mean: float = 0.0
	for j: int in kinds_at(cell):
		mean += share_of(cell, str(_kinds[j]["id"])) * _cube_yield(j)
	return _cube_yield(k) / mean if mean > 0.0 else 1.0


func _cube_yield(k: int) -> float:
	return float((_kinds[k].get("yield", {}) as Dictionary).get("cubes", 1.0))


## Lumi works the held kind of hex `cell` that her `tool` ("water", "plant") clears, for `seconds`
## of her scoop rate times the kind's hand_factor, into at most `room` units of chest. Returns {}
## when the hex has no such kind left; {blocked: text} when she lacks the gate or the cost; else
## {kind, type_id, color, vol, cubes, strip_scale, tool_use} for the chest (tool_use: how much of
## the tool's own stock the take used, e.g. water).
func hand_work(tool: String, cell: int, seconds: float, room: float) -> Dictionary:
	var k: int = _held_kind(cell, "tool", tool)
	if k < 0:
		return {}
	var kd: Dictionary = _kinds[k]
	var id: String = str(kd["id"])
	if not can_work(id):
		EventBus.pollution_blocked.emit(id, cell)
		return {"blocked": tr(str(kd.get("prompt", "")))}
	var cost: Dictionary = kd.get("cost", {})
	if not cost.is_empty() and not GameState.can_afford(str(cost["currency"]), BigNum.from_float(1.0)):
		return {"blocked": tr(str(cost.get("prompt", "")))}
	if room <= 0.0:
		return {"blocked": ""}
	var total: float = _field.worth.work(cell)
	var want: float = minf(room, float(kd.get("hand_factor", 1.0)) * hand_bonus(id) * Pace.pulse_volume() * maxf(Economy.stat("scoop_rate"), 0.5) * seconds)
	var left_before: float = _field.hex_left[cell] if _field.materialized[cell] == 1 else total * _cells.junk[cell]
	var took: float = _take(cell, k, want, true)
	if took <= 0.0:
		return {}
	_charge(cost, took / (share_of(cell, id) * total))
	EventBus.pollution_cleared.emit(id, took, true)
	var parts: float = float((kd.get("yield", {}) as Dictionary).get("parts", 1.0))
	return {"kind": id, "type_id": Economy.junk_ids[int(kd["type"])], "color": Color.html(str(kd.get("color", "#8a8a8a"))), "vol": took,
		"cubes": _field.worth.share(cell, took, left_before, total, _field.clean_threshold) * _yield_factor(cell, k),
		"strip_scale": RobotParts.strip_scale(took, total) * parts, "tool_use": took * float(kd.get("tool_use_per_unit", 0.0))}


## The held kind on a hex with waste left whose `field` ("tool", or a role in "robot_roles") matches.
func _held_kind(cell: int, field: String, value: String) -> int:
	if not _held.has(cell):
		return -1
	for k: int in kinds_at(cell):
		var kd: Dictionary = _kinds[k]
		if str(kd["work"]) != WORK_HELD or _held[cell][k] <= LEFT_EPS:
			continue
		if field == "tool" and str(kd.get("tool", "")) == value:
			return k
		if field != "tool" and value in (kd.get("robot_roles", []) as Array) and (_crew_gate == null or _crew_gate.open(k)):
			return k
	return -1


## Takes up to `units` of held kind `k` off a hex, everywhere the hex lives. Returns units taken.
func _take(cell: int, k: int, units: float, by_player: bool) -> float:
	var total: float = _field.worth.work(cell)
	var share: float = share_of(cell, str(_kinds[k]["id"]))
	var have: float = _held[cell][k] * share * total
	var took: float = minf(units, have)
	if took <= 0.0:
		return 0.0
	var left: PackedFloat32Array = _held[cell]
	left[k] = maxf(0.0, (have - took) / (share * total))
	_held[cell] = left
	_cells.hold[cell] = maxf(0.0, _cells.hold[cell] - took / total)
	var flipped: bool = false
	if _field.materialized[cell] == 1:
		flipped = bool(_field.take_held(cell, took)[1])
		if cell_written.is_valid():
			cell_written.call(cell, flipped, by_player)
		else:
			SphereOffline.write_cell(_cells, _field, cell, 0.0 if flipped else 1.0 - _field.removed_fraction(cell))
	else:
		SphereOffline.write_cell(_cells, _field, cell, _cells.junk[cell] - took / total)
		flipped = not _cells.is_dirty(cell)
	_last_flipped = flipped
	return took


var _last_flipped: bool = false


## Adds a take's share of a kind's cost ({currency, per_hex}) and spends each whole unit owed.
func _charge(cost: Dictionary, hex_share: float) -> void:
	if cost.is_empty():
		return
	var currency: String = str(cost["currency"])
	var owed: float = float(_debt.get(currency, 0.0)) + float(cost.get("per_hex", 0.0)) * hex_share
	while owed >= 1.0 and GameState.spend(currency, BigNum.from_float(1.0)):
		owed -= 1.0
	_debt[currency] = owed


# --- Robots -----------------------------------------------------------------------------------

## Whether hex `cell` holds waste a robot of `role` clears with its own tool.
func robot_wants(role: String, cell: int) -> bool:
	return _held_kind(cell, "role", role) >= 0


## A robot of `role` finished one action on hex `cell`: takes the kind's robot_units (charging the
## kind's cost when `spend`; nothing is taken when it cannot be paid). True if the hex became clean.
func robot_work(role: String, cell: int, spend: bool) -> bool:
	var k: int = _held_kind(cell, "role", role)
	_last_flipped = false
	if k < 0:
		return false
	var kd: Dictionary = _kinds[k]
	var cost: Dictionary = kd.get("cost", {}) if spend else {}
	if not cost.is_empty() and not GameState.can_afford(str(cost["currency"]), BigNum.from_float(1.0)):
		return false
	var took: float = _take(cell, k, float(kd.get("robot_units", 20.0)), false)
	_charge(cost, took / (share_of(cell, str(kd["id"])) * _field.worth.work(cell)))
	_robot_acc[k] += took
	return _last_flipped


## A robot scooped `hex_share` (0..1) of hex `cell`: counted for the kinds its pieces belong to.
func robot_scooped(cell: int, hex_share: float) -> void:
	if hex_share <= 0.0 or _field == null:
		return
	var units: float = hex_share * _field.worth.work(cell)
	var list: PackedInt32Array = kinds_at(cell)
	var scooped: float = 0.0
	for k: int in list:
		if str(_kinds[k]["work"]) != WORK_HELD:
			scooped += share_of(cell, str(_kinds[k]["id"]))
	for k: int in list:
		if str(_kinds[k]["work"]) != WORK_HELD and scooped > 0.0:
			_robot_acc[k] += units * share_of(cell, str(_kinds[k]["id"])) / scooped


## Emits what robots cleared since the last call, one event per kind.
func flush_robot_events() -> void:
	for k: int in _robot_acc.size():
		if _robot_acc[k] > 0.0:
			EventBus.pollution_cleared.emit(str(_kinds[k]["id"]), _robot_acc[k], false)
			_robot_acc[k] = 0.0


# --- Robots and mastery -----------------------------------------------------------------------

## A scooping robot's rate multiplier on hex `cell` from Lumi's mastery of the kinds it holds.
func crew_speed(cell: int) -> float:
	return _crew_gate.scoop_speed(cell) if _crew_gate != null else 1.0


## The rate multiplier of a robot of `role` on the held kind it works on hex `cell`.
func crew_speed_held(role: String, cell: int) -> float:
	var k: int = _held_kind(cell, "role", role)
	return _crew_gate.factor(k) if _crew_gate != null and k >= 0 else 1.0


## The rate multiplier of robots on the base kind (time away is worked at this rate).
func crew_speed_base() -> float:
	return _crew_gate.factor(0) if _crew_gate != null else 1.0


## Whether some kind a robot role works is still closed to robots.
func crew_role_gated(role: String) -> bool:
	return _crew_gate != null and _crew_gate.role_gated(role)


## The kind on hex `cell` a robot of `role` would work had Lumi learnt it ("" = none).
func crew_gate_kind(role: String, cell: int) -> String:
	return _crew_gate.gate_kind(role, cell) if _crew_gate != null else ""


## The waste of every clean land hex by kind, {kind id: units}, in a city or on open ground:
## what a save from before mastery is credited with (Mastery.seed_legacy). Lakes are left out: a
## lake with nothing floating on it was never cleaned.
func cleaned_units() -> Dictionary:
	var out: Dictionary = {}
	if _cells == null or _field == null:
		return out
	for c: int in _cells.n:
		var state: int = _cells.state[c]
		if state == PlanetData.State.JUNK or state == PlanetData.State.WATER:
			continue
		var work: float = _field.worth.work(c)
		for k: int in kinds_at(c):
			var id: String = str(_kinds[k]["id"])
			out[id] = float(out.get(id, 0.0)) + share_of(c, id) * work
	return out
